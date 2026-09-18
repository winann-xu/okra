import Foundation

/// 状态文件：helper 写更新结果，App 写探测结果（合并保留对方字段）。
/// 位置：~/Library/Application Support/Okra/status.json（任务书 §7 schema）。
enum StatusIO {
    struct Snapshot {
        var lastUpdate: String?
        var updateOk: Bool?
        var updateError: String?
        var source: String?
        var entries: Int?
        var lastProbe: String?
        var probes: [[String: Any]]?
        var overall: String?
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func read() -> Snapshot {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Paths.statusFile)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Snapshot()
        }
        return parse(obj)
    }

    private static func parse(_ obj: [String: Any]) -> Snapshot {
        var s = Snapshot()
        s.lastUpdate = obj["last_update"] as? String
        s.updateOk = obj["update_ok"] as? Bool
        s.updateError = obj["update_error"] as? String
        s.source = obj["source"] as? String
        s.entries = obj["entries"] as? Int
        s.lastProbe = obj["last_probe"] as? String
        s.probes = obj["probes"] as? [[String: Any]]
        s.overall = obj["overall"] as? String
        return s
    }

    /// 写出更新结果；探测相关字段（last_probe/probes/overall）从旧文件保留。
    static func writeUpdate(ok: Bool, error: String?, source: String?, entries: Int?) throws {
        let old = read()
        var obj: [String: Any] = [:]
        // schema 固定：null 字段显式写 NSNull（直接赋 Swift nil 会把键从 JSON 里删掉）
        obj["last_update"] = iso.string(from: Date())
        obj["update_ok"] = ok
        if let error { obj["update_error"] = error } else { obj["update_error"] = NSNull() }
        if let source { obj["source"] = source } else { obj["source"] = NSNull() }
        if let entries { obj["entries"] = entries } else { obj["entries"] = NSNull() }
        obj["last_probe"] = old.lastProbe ?? NSNull()
        obj["probes"] = old.probes ?? []
        obj["overall"] = old.overall ?? "unknown"
        try ensureSupportDir()
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: Paths.statusFile), options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                               ofItemAtPath: Paths.statusFile)
        chownSupportToUser()
    }

    static func ensureSupportDir() throws {
        try FileManager.default.createDirectory(atPath: Paths.supportDir,
                                               withIntermediateDirectories: true)
        chownSupportToUser()
    }
}

/// root 运行时把支持目录/备份目录/状态文件 chown 给对应用户：
/// App（用户身份）需要目录写权限（原子写依赖目录可写），且要与 helper（root 身份）
/// 交替读写状态文件；用户名无法解析时静默跳过（不阻塞主流程）。
func chownSupportToUser() {
    guard geteuid() == 0 else { return }
    let home = ProcessInfo.processInfo.environment["OKRA_USER_HOME"] ?? NSHomeDirectory()
    let name = (home as NSString).lastPathComponent
    guard !name.isEmpty, let pw = getpwnam(name)?.pointee else { return }
    for path in [Paths.supportDir, Paths.backupDir, Paths.statusFile] {
        var st = stat()
        if stat(path, &st) == 0 { chown(path, pw.pw_uid, pw.pw_gid) }
    }
}