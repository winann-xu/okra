import Foundation

/// 定时服务（launchd LaunchDaemon）状态：App 直接读系统 plist（0644，用户可读），
/// 无需 helper 参与。plist 由 helper 的 install/uninstall 写入/移除（唯一写方是 helper）。
enum ServiceInfo {
    static let label = "com.winann.okra.helper"
    static let plistPath = "/Library/LaunchDaemons/" + label + ".plist"

    /// 已安装服务的 StartInterval（秒）；未安装返回 nil。
    static var intervalSeconds: Int? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return obj["StartInterval"] as? Int
    }
}