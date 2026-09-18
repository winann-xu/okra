import Foundation

/// App 本地设置（UserDefaults 持久化，任务书 FR5）。
/// - 更新周期：安装/重装 launchd 服务时经 `install --interval` 下发（组件 B 从 plist 读取）
/// - 探测周期：仅 App 自身探测排程使用（组件 A），不涉及 helper
enum AppSettings {
    private static let store = UserDefaults.standard

    /// 更新周期选项（小时）：4 / 12 / 24，默认 12
    static let updateIntervalOptions = [4, 12, 24]
    static var updateIntervalHours: Int {
        get { store.object(forKey: "updateIntervalHours") as? Int ?? 12 }
        set { store.set(newValue, forKey: "updateIntervalHours") }
    }

    /// 探测周期选项（分钟）：60 / 120 / 240。下限 60min（D4：不更频繁）
    static let probeIntervalOptions = [60, 120, 240]
    static var probeIntervalMinutes: Int {
        get { store.object(forKey: "probeIntervalMinutes") as? Int ?? 60 }
        set { store.set(newValue, forKey: "probeIntervalMinutes") }
    }
}