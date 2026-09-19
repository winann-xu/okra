import Foundation

/// launchd 安装/卸载（root daemon，任务书 §7 组件 B）。
/// plist 模板唯一来源：本文件（随 helper 二进制分发）。
/// 安装后 daemon 以 root 运行，通过 plist 的 EnvironmentVariables 拿到用户家目录以定位状态文件。
enum Install {
    static let helperHome = Paths.installDir + "/" + Paths.binaryName
    static let startInterval = 43200 // 12h

    /// 供 plist 内联的模板（占位符安装时替换）。
    static var plistTemplate: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>__LABEL__</string>
            <key>Program</key>
            <string>__HELPER__</string>
            <key>RunAtLoad</key>
            <true/>
            <key>StartInterval</key>
            <integer>__INTERVAL__</integer>
            <key>EnvironmentVariables</key>
            <dict>
                <key>OKRA_USER_HOME</key>
                <string>__USER_HOME__</string>
            </dict>
            <key>StandardOutPath</key>
            <string>__SUPPORT_DIR__/helper.stdout.log</string>
            <key>StandardErrorPath</key>
            <string>__SUPPORT_DIR__/helper.stderr.log</string>
        </dict>
        </plist>
        """
    }

    /// 安装：复制 helper 到 /Library/Okra → 写 plist → launchctl bootstrap。
    static func install(userHome: String, interval: Int? = nil) throws {
        try requireRoot()
        guard !userHome.isEmpty, userHome.hasPrefix("/"), userHome != "/var/root" else {
            throw OkraError("无法确定用户家目录（请用 --user-home 指定）")
        }
        let fm = FileManager.default
        try fm.createDirectory(atPath: Paths.installDir, withIntermediateDirectories: true)
        let src = CommandLine.arguments[0]
        if fm.fileExists(atPath: helperHome) { try fm.removeItem(atPath: helperHome) }
        try fm.copyItem(atPath: src, toPath: helperHome)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperHome)

        let supportDir = userHome + "/Library/Application Support/Okra"
        try fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        var plist = plistTemplate
            .replacingOccurrences(of: "__LABEL__", with: Paths.label)
            .replacingOccurrences(of: "__HELPER__", with: helperHome)
            .replacingOccurrences(of: "__INTERVAL__", with: String(interval ?? startInterval))
            .replacingOccurrences(of: "__USER_HOME__", with: userHome)
            .replacingOccurrences(of: "__SUPPORT_DIR__", with: supportDir)
        try plist.write(toFile: Paths.plistPath, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: Paths.plistPath)

        // 重载服务：先卸载旧实例，再加载（launchctl 卸载是异步的，需等待到位）
        try reloadService()
        print("launchd 服务已安装：\(Paths.label)（\(interval ?? startInterval)/\(86400)h 定时，开机加载）")
    }

    /// 重载服务：卸载旧实例 → 等待卸载到位 → bootstrap（含重试与加载结果校验）。
    /// 注意 launchctl 的 service-target 必须写成 `<domain>/<label>`：
    /// 旧写法 `bootout system <label>` 报 "Unrecognized target specifier" 且静默不卸载，
    /// 随后 bootstrap 因"已加载"报 EIO(5)（2026-09-19 真机复现，见 docs/M3-acceptance.md）。
    private static func reloadService() throws {
        var lastRC: Int32 = -1
        for attempt in 1...5 {
            unloadService()
            _ = waitFor(loaded: false, seconds: 3)
            lastRC = runLaunchctl(["bootstrap", "system", Paths.plistPath])
            if lastRC == 0, waitFor(loaded: true, seconds: 2) { return }
            print("  提示：第 \(attempt) 次加载未成功（rc=\(lastRC)），重试…")
            usleep(500_000)
        }
        throw OkraError("launchctl 加载服务失败（rc=\(lastRC)，已重试 5 次），可重试运行 install")
    }

    /// 卸载服务（幂等）。正确写法：`bootout system/<label>`。
    static func unloadService() {
        _ = runLaunchctl(["bootout", "system/\(Paths.label)"], quiet: true)
    }

    private static func isLoaded() -> Bool {
        runLaunchctl(["print", "system/\(Paths.label)"], quiet: true) == 0
    }

    /// 轮询等待服务进入指定加载状态。
    private static func waitFor(loaded: Bool, seconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if isLoaded() == loaded { return true }
            usleep(200_000)
        }
        return isLoaded() == loaded
    }

    /// 卸载：移除服务 + plist + helper 二进制 + 还原 hosts + 清理支持目录。
    static func uninstall(userHome: String) throws {
        try requireRoot()
        unloadService()
        _ = waitFor(loaded: false, seconds: 3)   // 等卸载到位再删 plist
        try? FileManager.default.removeItem(atPath: Paths.plistPath)
        try? FileManager.default.removeItem(atPath: Paths.installDir)

        let home = ProcessInfo.processInfo.environment["OKRA_USER_HOME"] ?? userHome
        do {
            var hosts = try HostsFile(path: Paths.hostsPath)
            if hosts.removeBlock() {
                try hosts.commit()
                Dns.flush()
                print("hosts 已还原（Okra 区块已移除，其余内容保留）")
            } else {
                print("hosts 无 Okra 区块，无需还原")
            }
        } catch {
            print("警告：hosts 还原失败：\((error as? OkraError)?.description ?? "\(error)")")
        }
        try? FileManager.default.removeItem(
            atPath: home + "/Library/Application Support/Okra")
        print("秋葵已卸载（服务/plist/二进制/状态与备份均已清理）")
    }

    @discardableResult
    private static func runLaunchctl(_ args: [String], quiet: Bool = false) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            if !quiet {
                print("警告：launchctl \(args.joined(separator: " ")) 执行失败：\(error.localizedDescription)")
            }
            return -1
        }
    }
}
