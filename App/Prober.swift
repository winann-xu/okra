import Foundation

/// 探测执行器（任务书 FR3）：5 个探测域名，URLSession GET，10s 超时，记录 HTTP 码 + 耗时。
/// 探测完成后把探测字段写回 status.json（保留 helper 写的更新字段；schema 固定）。
enum Prober {
    static let domains = [
        "github.com",
        "api.github.com",
        "raw.githubusercontent.com",
        "objects.githubusercontent.com",
        "codeload.github.com",
    ]

    /// 任务书 FR3 判定：全绿→绿；全红→红；其余→黄
    static func overall(_ rows: [ProbeRow]) -> ProbeLevel? {
        guard !rows.isEmpty else { return nil }
        if rows.allSatisfy({ $0.level == .green }) { return .green }
        if rows.allSatisfy({ $0.level == .red }) { return .red }
        return .yellow
    }

    /// 并行探测 5 域（每域至多 10s）。
    static func runOnce() async -> [ProbeRow] {
        let session = URLSession(configuration: .ephemeral)
        let results = await withTaskGroup(of: ProbeRow.self) { group in
            for domain in domains {
                group.addTask { await Self.probeOne(domain, session) }
            }
            var byDomain: [String: ProbeRow] = [:]
            for await row in group { byDomain[row.domain] = row }
            return byDomain
        }
        return domains.map { results[$0] ?? ProbeRow(domain: $0, code: 0, ms: 10_000) }
    }

    private static func probeOne(_ domain: String, _ session: URLSession) async -> ProbeRow {
        var request = URLRequest(url: URL(string: "https://\(domain)/")!)
        request.timeoutInterval = 10
        let start = Date()
        var code = 0
        do {
            let (_, response) = try await session.data(for: request)
            code = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            code = 0   // 连接失败/超时
        }
        return ProbeRow(domain: domain, code: code, ms: Int(Date().timeIntervalSince(start) * 1000))
    }

    /// 探测一次并写状态文件（--probe-once 入口 / 手动触发）。
    @discardableResult
    static func runAndWrite() async throws -> [ProbeRow] {
        let rows = await runOnce()
        try write(rows)
        return rows
    }

    /// 写探测结果：更新字段从旧文件保留（null → NSNull，schema 恒定，与 helper 侧一致）。
    static func write(_ rows: [ProbeRow]) throws {
        var obj: [String: Any] = [:]
        let url = URL(fileURLWithPath: StatusIO.statusFile)
        if let data = try? Data(contentsOf: url),
           let old = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            obj = old
        }
        for key in ["last_update", "update_ok", "update_error", "source", "entries"] {
            if obj[key] == nil { obj[key] = NSNull() }
        }
        obj["last_probe"] = ISO8601DateFormatter().string(from: Date())
        obj["probes"] = rows.map {
            ["domain": $0.domain, "http_code": $0.code, "ms": $0.ms, "ok": $0.level == .green]
        }
        obj["overall"] = overall(rows)?.rawValue ?? "unknown"
        try FileManager.default.createDirectory(atPath: StatusIO.supportDir,
                                               withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: StatusIO.statusFile)
    }
}
