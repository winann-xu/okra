import Foundation

/// DNS 缓存刷新：`dscacheutil -flushcache; killall -HUP mDNSResponder`（任务书 §3 第 5 条）。
enum Dns {
    static func flush() {
        let env = ProcessInfo.processInfo.environment
        if env["OKRA_SKIP_DNS_FLUSH"] == "1" {
            print("  DNS 刷新：跳过（测试模式）")
            return
        }
        guard geteuid() == 0 else {
            print("  DNS 刷新：无 root 权限，跳过（hosts 已写入，新连接将按系统节奏生效）")
            return
        }
        run("/usr/sbin/dscacheutil", ["-flushcache"])
        run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
        print("  DNS 缓存已刷新")
    }

    @discardableResult
    private static func run(_ launchPath: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        p.standardError = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            print("  警告：\(launchPath) 执行失败：\(error.localizedDescription)")
            return -1
        }
    }
}
