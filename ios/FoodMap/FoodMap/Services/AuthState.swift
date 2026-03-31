// 用户认证状态管理
// 使用 Supabase Auth 处理用户注册、登录、登出

import Foundation
import Combine

// 全局认证状态，通过 EnvironmentObject 注入到所有视图
class AuthState: ObservableObject {
    @Published var isLoggedIn = false
    @Published var userId = ""
    @Published var isLoading = true  // 启动时检查登录状态

    private let supabaseURL = "https://ygsxhvsmivcckmjmjmhr.supabase.co"
    private let supabaseAnonKey = "sb_publishable_gQdKpwmrgSIQOV2G45mghg_uWiIRnrd"

    init() {
        // 检查本地是否有保存的 session
        checkStoredSession()
    }

    // 检查本地存储的登录 token
    func checkStoredSession() {
        if let token = UserDefaults.standard.string(forKey: "access_token"),
           let uid = UserDefaults.standard.string(forKey: "user_id"),
           !token.isEmpty {
            self.userId = uid
            self.isLoggedIn = true
        }
        self.isLoading = false
    }

    // 手机号 + 验证码登录（Supabase OTP）
    func signInWithPhone(phone: String) async throws {
        let url = URL(string: "\(supabaseURL)/auth/v1/otp")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let body = ["phone": phone]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.sendOTPFailed
        }
    }

    // 验证 OTP 验证码
    func verifyOTP(phone: String, token: String) async throws {
        let url = URL(string: "\(supabaseURL)/auth/v1/verify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let body: [String: String] = ["phone": phone, "token": token, "type": "sms"]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.verifyOTPFailed
        }

        // 解析返回的 token 和 user id
        struct AuthResponse: Codable {
            let access_token: String
            let user: UserInfo
            struct UserInfo: Codable { let id: String }
        }
        let authResp = try JSONDecoder().decode(AuthResponse.self, from: data)

        // 保存到本地
        UserDefaults.standard.set(authResp.access_token, forKey: "access_token")
        UserDefaults.standard.set(authResp.user.id, forKey: "user_id")

        await MainActor.run {
            self.userId = authResp.user.id
            self.isLoggedIn = true
        }
    }

    // 登出
    func signOut() {
        UserDefaults.standard.removeObject(forKey: "access_token")
        UserDefaults.standard.removeObject(forKey: "user_id")
        isLoggedIn = false
        userId = ""
    }
}

enum AuthError: LocalizedError {
    case sendOTPFailed
    case verifyOTPFailed

    var errorDescription: String? {
        switch self {
        case .sendOTPFailed: return "发送验证码失败，请检查手机号"
        case .verifyOTPFailed: return "验证码错误或已过期"
        }
    }
}
