import SwiftUI
import Combine

/// App 核心状态：
/// - 每 2s 轮询 status.json → 秒级反映到 UI（任务书 §7）
/// - 60min 探测排程（FR3）；hosts 更新成功后立即触发一次探测（FR3）
/// - M3：设置动作（安装/还原/卸载/周期变更）统一走 root helper + 系统授权对话框
@MainActor
final class StatusModel: ObservableObject {
    @Published private(set) var snapshot = StatusIO.Snapshot(probes: [])
    @Published var probing = false
    @Published var updating = false
    @Published var lastError: String?
    @Published private(set) var actionBusy = false
    @Published var actionFeedback: ActionFeedback?

    /// 设置动作的一次性反馈（安装/还原/卸载/周期变更）。
    struct ActionFeedback: Equatable {
        var text: String
        var isError: Bool = false
    }

    /// 探测周期：用户可配（默认 60min，D4 不更频繁）；OKRA_PROBE_INTERVAL（秒）仅测试覆盖。
    static var probeInterval: TimeInterval {
        if let s = ProcessInfo.processInfo.environment["OKRA_PROBE_INTERVAL"],
           let v = Double(s), v > 0 { return v }
        return Double(AppSettings.probeIntervalMinutes) * 60
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

    // MARK: - 手动更新（M2 机制保留：osascript 管理员授权直跑 helper）

    func updateNow() async {
        guard !updating else { return }
        updating = true
        lastError = nil
        defer { updating = false }
        let (rc, out) = await runHelper("update")
        if rc == 0 {
            // 状态文件为唯一事实来源：轮询自动发现更新成功 → 触发更新后探测
        } else if helperCancelled(out) {
            lastError = "已取消授权，本次更新未执行"
        } else {
            lastError = "更新未完成：\(firstLine(out))"
        }
    }

    // MARK: - 设置动作（M3：root helper + 系统授权对话框）

    /// 更新周期变更：持久化；已装服务 → 立即以新周期重装服务生效，未装 → 安装时生效。
    func setUpdateInterval(_ hours: Int) {
        AppSettings.updateIntervalHours = hours
        guard !actionBusy else { return }
        guard ServiceInfo.intervalSeconds != nil else {
            actionFeedback = ActionFeedback(text: "已保存：安装定时服务后生效")
            return
        }
        actionBusy = true
        actionFeedback = ActionFeedback(text: "等待管理员授权…")
        Task {
            let (rc, out) = await self.runHelper("install", ["--interval", String(hours * 3600)])
            self.actionBusy = false
            self.actionFeedback = self.resultFeedback(rc, out,
                ok: "定时服务已按 \(hours) 小时周期重装",
                cancel: "已取消授权，周期已保存，下次安装时生效")
        }
    }

    /// 探测周期变更：持久化 + 立即重排程（仅 App 侧，不涉及 helper）。
    func setProbeInterval(_ minutes: Int) {
        AppSettings.probeIntervalMinutes = minutes
        scheduleProbe()
        actionFeedback = ActionFeedback(text: "探测周期已设为 \(minutes / 60) 小时")
    }

    /// 安装定时服务：root → helper install（复制二进制 + 写 plist + launchd bootstrap，立即运行一次）。
    func installService() async {
        guard !actionBusy, ServiceInfo.intervalSeconds == nil else { return }
        actionBusy = true
        actionFeedback = ActionFeedback(text: "等待管理员授权…")
        let (rc, out) = await runHelper("install",
            ["--interval", String(AppSettings.updateIntervalHours * 3600)])
        actionBusy = false
        actionFeedback = resultFeedback(rc, out,
            ok: "定时服务已安装：每 \(AppSettings.updateIntervalHours) 小时更新，开机运行",
            cancel: "已取消授权，服务未安装")
    }

    /// 一键还原：root → helper restore（移除 Okra 区块，其余 hosts 内容逐字节保留，刷 DNS）。
    func restoreHosts() async {
        guard !actionBusy else { return }
        actionBusy = true
        actionFeedback = ActionFeedback(text: "等待管理员授权…")
        let (rc, out) = await runHelper("restore")
        actionBusy = false
        actionFeedback = resultFeedback(rc, out,
            ok: "已还原：Okra 区块已移除，其余 hosts 内容保留",
            cancel: "已取消授权，未还原")
    }

    /// 卸载秋葵：停 App 排程 → root 清理（服务/plist/二进制/hosts/状态与备份）
    /// → 移除登录项 → 退出。
    func uninstallApp() async {
        guard !actionBusy else { return }
        actionBusy = true
        actionFeedback = ActionFeedback(text: "等待管理员授权…")
        shutdownScheduling()
        let (rc, out) = await runHelper("uninstall")
        LoginItem.unregister()
        actionBusy = false
        if rc == 0 {
            actionFeedback = ActionFeedback(text: "已卸载（服务/hosts/数据已清理），即将退出…")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            NSApplication.shared.terminate(nil)
        } else if helperCancelled(out) {
            actionFeedback = ActionFeedback(text: "已取消授权，未卸载")
            restartScheduling()
        } else {
            actionFeedback = ActionFeedback(text: firstLine(out), isError: true)
            restartScheduling()
        }
    }

    // MARK: - 统一 helper 调用

    /// 经系统管理员授权对话框以 root 运行 helper 子命令（对话框由 helper 内的 osascript 调起）。
    /// nonisolated：阻塞的 helper 进程跑在主 actor 之外，授权弹窗期间 UI 保持响应。
    /// helper 选择：优先 App 内置副本（与本 App 的调用协议同版本），已装副本仅服务 launchd；
    /// 已装副本可能来自旧版本（如缺 auth 子命令），故不作为首选。
    nonisolated func runHelper(_ subcommand: String, _ extra: [String] = []) async -> (Int32, String) {
        let fm = FileManager.default
        let bundled = (Bundle.main.resourcePath ?? "") + "/OkraHelper"
        let candidates = [bundled, "/Library/Okra/OkraHelper"]
        guard let helper = candidates.first(where: { !$0.isEmpty && fm.fileExists(atPath: $0) }) else {
            return (-1, "未找到 helper 程序（请重新构建项目）")
        }
        // 输出落临时文件而非 Pipe：共享 Pipe 的写端仍被父进程持有，EOF 永不到达，
        // readDataToEndOfFile 会永久死锁（2026-09-18 实测：授权对话框结束后 UI 全部置灰）。
        let outURL = fm.temporaryDirectory.appendingPathComponent("okra-helper-\(UUID().uuidString).log")
        fm.createFile(atPath: outURL.path, contents: nil)
        guard let outHandle = try? FileHandle(forWritingTo: outURL) else {
            try? fm.removeItem(at: outURL)
            return (-1, "无法创建临时输出文件")
        }
        // OKRA_USER_HOME 让 root 定位用户状态目录（helper 据此找状态文件/备份目录）。
        // 提权由 helper（普通二进制）内调 osascript 完成：真机实测（2026-09-18）
        // 本 App bundle（LSUIElement）直接调 osascript 管理员权限时系统授权对话框
        // 不出现；"普通二进制 → osascript"形式对话框稳定出现。
        let p = Process()
        p.executableURL = URL(fileURLWithPath: helper)
        p.arguments = ["auth", subcommand] + extra
        var env = ProcessInfo.processInfo.environment
        env["OKRA_USER_HOME"] = NSHomeDirectory()
        p.environment = env
        p.standardOutput = outHandle
        p.standardError = outHandle
        do {
            try p.run()
            try? outHandle.close()   // 父进程释放写端（子进程已持有自己的副本），子进程退出后文件即可读
            p.waitUntilExit()
        } catch {
            try? outHandle.close()
            try? fm.removeItem(at: outURL)
            return (-1, "无法调起授权对话框：\(error.localizedDescription)")
        }
        let out = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
        try? fm.removeItem(at: outURL)
        // OKRA_DEBUG：把每次调用的 rc 与完整输出落盘，便于排查授权对话框问题
        if ProcessInfo.processInfo.environment["OKRA_DEBUG"] != nil {
            let logURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/Okra-helper-debug.log")
            let line = "[\(Date())] runHelper \(subcommand) \(extra.joined(separator: " ")): rc=\(p.terminationStatus) out=\n\(out)\n"
            if let data = line.data(using: .utf8) {
                let dir = logURL.deletingLastPathComponent()
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                if !fm.fileExists(atPath: logURL.path) {
                    fm.createFile(atPath: logURL.path, contents: nil)
                }
                if let fh = try? FileHandle(forWritingTo: logURL) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    try? fh.close()
                }
            }
        }
        return (p.terminationStatus, out)
    }

    /// root 调用结果归一为人话反馈。
    private func resultFeedback(_ rc: Int32, _ out: String, ok: String, cancel: String) -> ActionFeedback {
        if rc == 0 { return ActionFeedback(text: ok) }
        if helperCancelled(out) { return ActionFeedback(text: cancel) }
        return ActionFeedback(text: firstLine(out), isError: true)
    }

    // MARK: - 排程开关（卸载前停，取消后恢复）

    private func shutdownScheduling() {
        pollTimer?.invalidate()
        pollTimer = nil
        probeTimer?.invalidate()
        probeTimer = nil
    }

    private func restartScheduling() {
        guard pollTimer == nil else { return }
        startPolling()
        scheduleProbe()
    }
}

/// 用户取消系统授权对话框（osascript 错误 -128）。
func helperCancelled(_ out: String) -> Bool {
    out.contains("error number -128") || out.contains("User cancelled") || out.contains("用户已取消")
}

/// 输出首个非空行（错误人话化展示用）。
func firstLine(_ s: String) -> String {
    (s.split(whereSeparator: { $0 == "\n" }).first.map(String.init) ?? s)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}