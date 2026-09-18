import SwiftUI
import Combine

/// App 核心状态：
/// - 每 2s 轮询 status.json → 秒级反映到 UI（任务书 §7）
/// - 60min 探测排程（FR3）；hosts 更新成功后立即触发一次探测（FR3）
@MainActor
final class StatusModel: ObservableObject {
    @Published private(set) var snapshot = StatusIO.Snapshot(probes: [])
    @Published var probing = false
    @Published var updating = false
    @Published var lastError: String?

    /// 60min 探测周期（FR3）。
    static var probeInterval: TimeInterval {
        guard let s = ProcessInfo.processInfo.environment["OKRA_PROBE_INTERVAL"],
              let v = Double(s), v > 0 else { return 3600 }
        return v
    }

    private var pollTimer: Timer?
    private var probeTimer: Timer?
    private var lastSeenUpdate: String?

    init() {
        reload()
        startPolling()
        scheduleProbe()
        // 启动时探测数据缺失或已过期（>周期）→ 立即探一次，避免 UI 空窗
        if shouldProbeNow { Task { await probeNow() } }
    }

    var overall: ProbeLevel? { snapshot.overall }

    /// 固定 5 域展示行（FR3）；无探测数据的域以灰点占位。
    struct Row: Identifiable {
        let domain: String
        let level: ProbeLevel?
        let code: Int?
        let ms: Int?
        var id: String { domain }
    }

    var rows: [Row] {
        let byDomain = Dictionary(uniqueKeysWithValues: snapshot.probes.map { ($0.domain, $0) })
        return Prober.domains.map { d in
            let p = byDomain[d]
            return Row(domain: d, level: p?.level, code: p?.code, ms: p?.ms)
        }
    }

    // MARK: - 状态文件轮询

    private func startPolling() {
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    func reload() {
        let new = StatusIO.read()
        snapshot = new
        if new.lastUpdate != lastSeenUpdate {
            lastSeenUpdate = new.lastUpdate
            // FR3：每次 hosts 更新成功后立即触发一次探测（不等下个整点周期）
            if new.updateOk == true, needsReprobe {
                Task { await probeNow() }
            }
        }
    }

    private var needsReprobe: Bool {
        guard let lu = snapshot.lastUpdate else { return snapshot.lastProbe == nil }
        guard let lp = snapshot.lastProbe else { return true }
        return lu >= lp   // 均为 ISO8601 UTC 字符串，可按字典序比较
    }

    private var shouldProbeNow: Bool {
        guard let lp = snapshot.lastProbe, let d = TimeFmt.isoDate(lp) else { return true }
        return Date().timeIntervalSince(d) > Self.probeInterval
    }

    // MARK: - 探测

    func scheduleProbe() {
        probeTimer?.invalidate()
        let t = Timer(timeInterval: Self.probeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.probeNow(scheduled: true) }
        }
        RunLoop.main.add(t, forMode: .common)
        probeTimer = t
    }

    /// 执行一次探测并写回状态文件；定时探测完成后从本次完成时刻重新计周期。
    func probeNow(scheduled: Bool = false) async {
        guard !probing else { return }
        probing = true
        lastError = nil
        defer { probing = false }
        let rows = await Prober.runOnce()
        do {
            try Prober.write(rows)
            reload()
            if scheduled { scheduleProbe() }
        } catch {
            lastError = "探测结果写入失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 手动更新（检查点建议方案，待用户确认）

    /// 立即更新：经系统管理员授权对话框（osascript）运行 root helper。
    /// launchd 服务为一次性程序，不做标记文件轮询，故不采用 IPC 标记方案
    /// （任务书 FR2 括号内方案与 §7 一次性架构冲突，见检查点"下一步"）。
    func updateNow() async {
        guard !updating else { return }
        updating = true
        lastError = nil
        defer { updating = false }

        let fm = FileManager.default
        let candidates = [
            "/Library/Okra/OkraHelper",                        // 已安装服务（M4）
            (Bundle.main.resourcePath ?? "") + "/OkraHelper",  // 随 App 分发的 helper
        ]
        guard let helper = candidates.first(where: { !$0.isEmpty && fm.fileExists(atPath: $0) }) else {
            lastError = "暂不可更新：未找到 helper 程序（安装后提供）"
            return
        }
        // 以 root 运行，helper 需 OKRA_USER_HOME 定位用户状态目录
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "do shell script \"\(helper) update\" with administrator privileges"]
        var env = ProcessInfo.processInfo.environment
        env["OKRA_USER_HOME"] = NSHomeDirectory()
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            lastError = "无法调起授权对话框：\(error.localizedDescription)"
            return
        }
        if p.terminationStatus != 0 {
            lastError = "更新未执行（拒绝了授权或网络不可用）"
        }
        // 状态文件为唯一事实来源：helper 写入后轮询自动发现更新成功 → 触发更新后探测
    }
}
