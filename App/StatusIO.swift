import SwiftUI
import Foundation

/// 单域名探测记录（任务书 §7 schema：domain/http_code/ms/ok）。
struct ProbeRow: Identifiable, Equatable {
    /// 延迟阈值：≥3000ms 判定为限速降级
    /// （2026-09-17 基线：正常 ≤0.5s，github.com 限速 10s，3s 给足余量）
    static let thresholdMs = 3000

    let domain: String
    let code: Int   // 0 = 连接失败/超时
    let ms: Int

    var id: String { domain }

    /// 任务书 FR3 判定：连接失败=红；2xx/3xx 且 < 阈值=绿；
    /// 其余（限速超阈 / 非 2xx-3xx 状态码）=黄
    var level: ProbeLevel {
        if code == 0 { return .red }
        if (200..<400).contains(code) { return ms < Self.thresholdMs ? .green : .yellow }
        return .yellow
    }

    var msText: String { code == 0 ? "超时" : "\(ms) ms" }
    var codeText: String { code == 0 ? "—" : "\(code)" }
}

/// 总体状态：绿=畅通 / 黄=降级 / 红=不可达（任务书 FR3）。
enum ProbeLevel: String, Equatable {
    case green, yellow, red

    var color: Color {
        switch self {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }
}

/// 状态文件（App 侧）：读取 helper 写的 status.json（schema 与 helper 侧一致，任务书 §7）。
/// 位置：~/Library/Application Support/Okra/status.json
enum StatusIO {
    struct Snapshot {
        var lastUpdate: String?
        var updateOk: Bool?
        var updateError: String?
        var source: String?
        var entries: Int?
        var lastProbe: String?
        var probes: [ProbeRow]
        var overall: ProbeLevel?
    }

    static var supportDir: String {
        let home = ProcessInfo.processInfo.environment["OKRA_USER_HOME"] ?? NSHomeDirectory()
        return home + "/Library/Application Support/Okra"
    }

    static var statusFile: String { supportDir + "/status.json" }

    static func read() -> Snapshot {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: statusFile)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Snapshot(probes: [])
        }
        var s = Snapshot(probes: [])
        s.lastUpdate = obj["last_update"] as? String
        s.updateOk = obj["update_ok"] as? Bool
        s.updateError = obj["update_error"] as? String
        s.source = obj["source"] as? String
        s.entries = obj["entries"] as? Int
        s.lastProbe = obj["last_probe"] as? String
        s.overall = (obj["overall"] as? String).flatMap(ProbeLevel.init(rawValue:))
        if let arr = obj["probes"] as? [[String: Any]] {
            s.probes = arr.compactMap { p in
                guard let d = p["domain"] as? String else { return nil }
                return ProbeRow(domain: d, code: p["http_code"] as? Int ?? 0, ms: p["ms"] as? Int ?? 0)
            }
        }
        return s
    }
}

/// 时间格式化：ISO8601（UTC）→ 本地 "MM-dd HH:mm"。
enum TimeFmt {
    static func isoDate(_ s: String) -> Date? {
        ISO8601DateFormatter().date(from: s)
    }

    static func local(_ s: String?) -> String {
        guard let s, let d = isoDate(s) else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }
}