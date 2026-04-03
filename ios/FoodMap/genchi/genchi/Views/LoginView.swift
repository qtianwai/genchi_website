// 登录页面
// 手机号 + 短信验证码登录

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authState: AuthState

    @State private var phone = ""
    @State private var otp = ""
    @State private var step: LoginStep = .phone  // 当前步骤
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    // TODO: 微信开放平台审核通过后取消注释
    // @State private var isWechatLoading = false

    enum LoginStep { case phone, otp }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // ── Logo 区域 ──
            VStack(spacing: 12) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.orange)
                Text("跟吃")
                    .font(.title).fontWeight(.bold)
                Text("跟着达人，发现身边好店")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 48)

            // ── 输入区域 ──
            VStack(spacing: 16) {
                if step == .phone {
                    // 手机号输入
                    VStack(alignment: .leading, spacing: 6) {
                        Text("手机号")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            Text("+86")
                                .foregroundColor(.secondary)
                                .padding(.leading, 14)
                            Divider().frame(height: 20)
                            TextField("请输入手机号", text: $phone)
                                .keyboardType(.phonePad)
                                .padding(.leading, 8)
                        }
                        .frame(height: 50)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    // 验证码输入
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("验证码已发送至 +86 \(phone)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("重新发送") {
                                step = .phone
                            }
                            .font(.caption)
                            .foregroundColor(.orange)
                        }
                        TextField("请输入 6 位验证码", text: $otp)
                            .keyboardType(.numberPad)
                            .padding(14)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                // 错误提示
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 主操作按钮
                Button(action: handleAction) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(step == .phone ? "获取验证码" : "登录")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isButtonDisabled ? Color.gray.opacity(0.4) : Color.orange)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isButtonDisabled)
            }
            .padding(.horizontal, 28)

            // TODO: 微信开放平台审核通过后取消注释
            /*
            // ── 分隔线 ──
            HStack {
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color(.systemGray4))
                Text("或")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color(.systemGray4))
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            // ── 微信登录按钮 ──
            Button(action: handleWechatLogin) {
                HStack(spacing: 10) {
                    if isWechatLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        // 微信图标（使用系统图标代替，集成 SDK 后可换成微信 logo）
                        Image(systemName: "message.fill")
                            .font(.system(size: 18))
                    }
                    Text("微信登录")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(red: 0.24, green: 0.78, blue: 0.24))  // 微信绿色
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isWechatLoading)
            .padding(.horizontal, 28)
            .padding(.top, 12)
            */

            Spacer()

            // 底部隐私说明
            Text("登录即表示同意《用户协议》和《隐私政策》")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 30)
        }
    }

    var isButtonDisabled: Bool {
        isLoading || (step == .phone ? phone.count < 11 : otp.count < 6)
    }

    func handleAction() {
        errorMessage = nil
        isLoading = true
        Task {
            do {
                if step == .phone {
                    try await authState.signInWithPhone(phone: "+86\(phone)")
                    await MainActor.run { step = .otp }
                } else {
                    try await authState.verifyOTP(phone: "+86\(phone)", token: otp)
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
            await MainActor.run { isLoading = false }
        }
    }

    // TODO: 微信开放平台审核通过后取消注释
    /*
    func handleWechatLogin() {
        errorMessage = nil
        isWechatLoading = true

        WechatAuthManager.shared.login { result in
            Task {
                switch result {
                case .success(let code):
                    do {
                        try await authState.signInWithWechat(code: code)
                    } catch {
                        await MainActor.run {
                            errorMessage = error.localizedDescription
                        }
                    }
                case .failure(let error):
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                    }
                }
                await MainActor.run { isWechatLoading = false }
            }
        }
    }
    */
}
