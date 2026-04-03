// 微信登录管理类
// 封装微信 SDK 调用逻辑，处理授权回调

import Foundation
// TODO: 微信开放平台审核通过后取消注释
// import UIKit

// 微信登录管理器
class WechatAuthManager: NSObject {
    static let shared = WechatAuthManager()

    // 微信 AppID（需要在微信开放平台申请）
    // TODO: 替换为你的微信 AppID
    private let wechatAppID = "YOUR_WECHAT_APP_ID"

    // 微信 Universal Link（iOS 9+ 必需）
    // TODO: 替换为你的 Universal Link
    private let universalLink = "https://your-domain.com/wechat/"

    // 登录回调
    private var loginCompletion: ((Result<String, WechatAuthError>) -> Void)?

    private override init() {
        super.init()
    }

    // 注册微信 SDK（在 App 启动时调用）
    func registerApp() {
        // TODO: 集成微信 SDK 后取消注释
        // WXApi.registerApp(wechatAppID, universalLink: universalLink)
        print("[微信登录] 微信 SDK 注册完成（AppID: \(wechatAppID)）")
    }

    // 检查是否安装微信
    func isWechatInstalled() -> Bool {
        // TODO: 微信开放平台审核通过后取消注释
        // WXApi.isWXAppInstalled()
        // if let url = URL(string: "weixin://") {
        //     return UIApplication.shared.canOpenURL(url)
        // }
        return false
    }

    // 发起微信登录
    func login(completion: @escaping (Result<String, WechatAuthError>) -> Void) {
        guard isWechatInstalled() else {
            completion(.failure(.wechatNotInstalled))
            return
        }

        self.loginCompletion = completion

        // TODO: 集成微信 SDK 后取消注释
        /*
        let req = SendAuthReq()
        req.scope = "snsapi_userinfo"
        req.state = "wechat_login_\(Int(Date().timeIntervalSince1970))"
        WXApi.send(req)
        */

        // 临时实现：模拟回调（用于测试 UI）
        print("[微信登录] 发起微信授权请求")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // 模拟返回 code
            completion(.failure(.sdkNotIntegrated))
        }
    }

    // 处理微信回调（在 AppDelegate 或 SceneDelegate 中调用）
    func handleOpenURL(_ url: URL) -> Bool {
        // TODO: 集成微信 SDK 后取消注释
        // return WXApi.handleOpen(url, delegate: self)
        return false
    }
}

// TODO: 集成微信 SDK 后实现 WXApiDelegate
/*
extension WechatAuthManager: WXApiDelegate {
    func onReq(_ req: BaseReq) {
        // 微信向第三方程序发起请求
    }

    func onResp(_ resp: BaseResp) {
        // 微信回调
        guard let authResp = resp as? SendAuthResp else {
            loginCompletion?(.failure(.authFailed))
            return
        }

        if authResp.errCode == 0, let code = authResp.code {
            // 授权成功，返回 code
            loginCompletion?(.success(code))
        } else {
            // 授权失败或取消
            let error: WechatAuthError = authResp.errCode == -2 ? .userCancelled : .authFailed
            loginCompletion?(.failure(error))
        }

        loginCompletion = nil
    }
}
*/

// 微信登录错误类型
enum WechatAuthError: LocalizedError {
    case wechatNotInstalled
    case authFailed
    case userCancelled
    case sdkNotIntegrated

    var errorDescription: String? {
        switch self {
        case .wechatNotInstalled:
            return "未安装微信，请先安装微信客户端"
        case .authFailed:
            return "微信授权失败，请重试"
        case .userCancelled:
            return "已取消微信登录"
        case .sdkNotIntegrated:
            return "微信 SDK 尚未集成，请联系开发者"
        }
    }
}
