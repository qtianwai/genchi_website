// 用户认证状态管理
// 改为调用后端自建短信接口，不再依赖 Supabase Auth
// 验证码由后端通过阿里云短信发送，验证成功后返回 user_id

import Foundation
import Combine

// 全局认证状态，通过 EnvironmentObject 注入到所有视图
class AuthState: ObservableObject {
    @Published var isLoggedIn = false
    @Published var userId = ""
    @Published var isLoading = true  // 启动时检查登录状态
    @Published var isAdmin = false   // 是否为管理员（v3.0 新增）
    @Published var nickname: String = "美食探索者"  // 用户昵称
    @Published var avatarURL: String? = nil         // 用户头像 URL，nil 表示未上传

    init() {
        checkStoredSession()
    }

    // 检查本地是否有保存的登录状态
    func checkStoredSession() {
        if let uiTestUserId = ProcessInfo.processInfo.environment["UITEST_USER_ID"],
           !uiTestUserId.isEmpty {
            self.userId = uiTestUserId
            self.isLoggedIn = true
            self.isLoading = false
            return
        }

        if let uid = UserDefaults.standard.string(forKey: "user_id"),
           !uid.isEmpty {
            self.userId = uid
            self.isLoggedIn = true
            // 异步检查管理员身份 + 加载用户 profile
            Task {
                await checkAdminStatus(userId: uid)
                await loadProfile(userId: uid)
            }
        }
        self.isLoading = false
    }

    // 检查当前用户是否为管理员（v3.0 新增）
    func checkAdminStatus(userId: String) async {
        guard let url = URL(string: "\(BASE_URL)/api/admin/check") else { return }
        var request = URLRequest(url: url)
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let resp = try? JSONDecoder().decode(AdminCheckResponse.self, from: data) else {
            return
        }
        await MainActor.run { self.isAdmin = resp.is_admin }
    }

    // 第一步：发送验证码（调用后端接口，后端再调阿里云短信）
    func signInWithPhone(phone: String) async throws {
        guard let url = URL(string: "\(BASE_URL)/api/auth/send-otp") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Body: Codable { let phone: String }
        request.httpBody = try JSONEncoder().encode(Body(phone: phone))

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.sendOTPFailed
        }
        if httpResponse.statusCode != 200 {
            // 解析后端返回的错误信息
            if let errorBody = try? JSONDecoder().decode([String: String].self, from: data),
               let detail = errorBody["detail"] {
                throw AuthError.custom(detail)
            }
            throw AuthError.sendOTPFailed
        }
    }

    // 第二步：验证验证码，成功后保存 user_id
    func verifyOTP(phone: String, token: String) async throws {
        guard let url = URL(string: "\(BASE_URL)/api/auth/verify-otp") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Body: Codable { let phone: String; let code: String }
        request.httpBody = try JSONEncoder().encode(Body(phone: phone, code: token))

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.verifyOTPFailed
        }
        if httpResponse.statusCode != 200 {
            if let errorBody = try? JSONDecoder().decode([String: String].self, from: data),
               let detail = errorBody["detail"] {
                throw AuthError.custom(detail)
            }
            throw AuthError.verifyOTPFailed
        }

        // 解析返回的 user_id
        struct VerifyResponse: Codable {
            let status: String
            let user_id: String
            let access_token: String
        }
        let resp = try JSONDecoder().decode(VerifyResponse.self, from: data)

        // 保存到本地
        UserDefaults.standard.set(resp.user_id, forKey: "user_id")

        await MainActor.run {
            self.userId = resp.user_id
            self.isLoggedIn = true
        }

        // 检查管理员身份（v3.0 新增）
        await checkAdminStatus(userId: resp.user_id)
        // 加载用户 profile
        await loadProfile(userId: resp.user_id)
    }

    // TODO: 微信开放平台审核通过后取消注释
    /*
    // 微信登录：传入微信授权 code，后端换取 user_id
    func signInWithWechat(code: String) async throws {
        guard let url = URL(string: "\(BASE_URL)/api/auth/wechat-login") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Body: Codable { let code: String }
        request.httpBody = try JSONEncoder().encode(Body(code: code))

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.wechatLoginFailed
        }
        if httpResponse.statusCode != 200 {
            if let errorBody = try? JSONDecoder().decode([String: String].self, from: data),
               let detail = errorBody["detail"] {
                throw AuthError.custom(detail)
            }
            throw AuthError.wechatLoginFailed
        }

        // 解析返回的 user_id
        struct LoginResponse: Codable {
            let status: String
            let user_id: String
            let access_token: String
        }
        let resp = try JSONDecoder().decode(LoginResponse.self, from: data)

        // 保存到本地
        UserDefaults.standard.set(resp.user_id, forKey: "user_id")

        await MainActor.run {
            self.userId = resp.user_id
            self.isLoggedIn = true
        }
    }
    */

    // 登出
    func signOut() {
        UserDefaults.standard.removeObject(forKey: "user_id")
        isLoggedIn = false
        userId = ""
        isAdmin = false  // 登出时重置管理员状态
        nickname = "美食探索者"  // 重置昵称
        avatarURL = nil          // 重置头像
    }

    // 加载用户 profile（昵称 + 头像）
    func loadProfile(userId: String) async {
        guard let url = URL(string: "\(BASE_URL)/api/profile/\(userId)") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else { return }
        await MainActor.run {
            self.nickname = profile.nickname
            self.avatarURL = profile.avatar_url
        }
    }

    // 更新昵称
    func updateNickname(_ newNickname: String) async throws {
        guard let url = URL(string: "\(BASE_URL)/api/profile/update") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Body: Codable { let user_id: String; let nickname: String }
        request.httpBody = try JSONEncoder().encode(Body(user_id: userId, nickname: newNickname))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorBody = try? JSONDecoder().decode([String: String].self, from: data),
               let detail = errorBody["detail"] {
                throw AuthError.custom(detail)
            }
            throw AuthError.custom("昵称更新失败")
        }
        await MainActor.run { self.nickname = newNickname }
    }

    // 上传头像（multipart/form-data）
    func uploadAvatar(_ imageData: Data) async throws {
        guard let url = URL(string: "\(BASE_URL)/api/profile/upload-avatar") else {
            throw URLError(.badURL)
        }
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // user_id 字段
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"user_id\"\r\n\r\n\(userId)\r\n".data(using: .utf8)!)
        // file 字段
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"avatar.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.custom("头像上传失败")
        }
        struct Resp: Codable { let avatar_url: String }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        await MainActor.run { self.avatarURL = resp.avatar_url }
    }
}

enum AuthError: LocalizedError {
    case sendOTPFailed
    case verifyOTPFailed
    case wechatLoginFailed
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .sendOTPFailed: return "发送验证码失败，请检查手机号"
        case .verifyOTPFailed: return "验证码错误或已过期"
        case .wechatLoginFailed: return "微信登录失败，请重试"
        case .custom(let msg): return msg
        }
    }
}
