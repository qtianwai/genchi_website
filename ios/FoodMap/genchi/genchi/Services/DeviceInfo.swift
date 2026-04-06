// 设备上下文采集工具（v15.0 新增）
// 用于反馈提交时自动附带设备信息，帮助定位问题

import UIKit

struct DeviceContext {
    /// 设备型号标识符，如 "iPhone16,1"
    static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    /// iOS 系统版本，如 "17.4"
    static var iosVersion: String {
        UIDevice.current.systemVersion
    }

    /// App 版本号，如 "1.0.0 (42)"
    static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
