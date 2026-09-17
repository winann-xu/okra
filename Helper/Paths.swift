import Foundation

/// 路径与常量集中定义。
/// 环境变量覆盖仅供测试使用（CI/沙箱验证），生产路径固定：
///   OKRA_HOSTS_PATH  —— hosts 文件路径（默认 /etc/hosts）
///   OKRA_SUPPORT_DIR —— 支持目录（默认 $OKRA_USER_HOME 或 $HOME 下的 Library/Application Support/Okra）
///   OKRA_SOURCES     —— 逗号分隔的镜像 URL 列表（默认三源，见 Sources.swift）
///   OKRA_SKIP_DNS_FLUSH —— =1 时跳过 DNS 刷新（测试用）
enum Paths {
    static var hostsPath: String {
        ProcessInfo.processInfo.environment["OKRA_HOSTS_PATH"] ?? "/etc/hosts"
    }

    static var supportDir: String {
        if let d = ProcessInfo.processInfo.environment["OKRA_SUPPORT_DIR"] { return d }
        let home = ProcessInfo.processInfo.environment["OKRA_USER_HOME"] ?? NSHomeDirectory()
        return home + "/Library/Application Support/Okra"
    }

    static var statusFile: String { supportDir + "/status.json" }
    static var backupDir: String { supportDir + "/backups" }

    static let label = "com.winann.okra.helper"
    static let plistPath = "/Library/LaunchDaemons/" + label + ".plist"
    static let installDir = "/Library/Okra"
    static let binaryName = "OkraHelper"
    static let startMarker = "# Okra Start"
    static let endMarker = "# Okra End"
}

func requireRoot() throws {
    guard geteuid() == 0 else { throw OkraError("该操作需要 root 权限（sudo 运行或由 App 授权安装）") }
}

struct OkraError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
    init(_ message: String) { self.message = message }
}