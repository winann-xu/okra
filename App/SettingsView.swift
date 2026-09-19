import SwiftUI

/// 设置页（任务书 §6/FR5）：周期选择、镜像源展示、定时服务安装、
/// 一键还原、卸载（危险操作二次确认）、关于与免责。
struct SettingsView: View {
    @EnvironmentObject var model: StatusModel
    var onBack: () -> Void

    /// 二次确认状态：点危险操作后按钮变为"确认…"，再点一次才执行
    @State private var confirmRestore = false
    @State private var confirmUninstall = false

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.0"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                feedback
                scheduleSection
                Divider()
                serviceSection
                sourceSection
                Divider()
                actionSection
                aboutSection
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    private var header: some View {
        HStack {
            Button("返回") { onBack() }
                .controlSize(.small)
            Spacer()
            Text("设置")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let fb = model.actionFeedback {
            Text(fb.text)
                .font(.caption)
                .foregroundStyle(fb.isError ? Color.red : Color.secondary)
        }
    }

    // MARK: - 更新排程（FR5：更新周期 4/12/24h；探测周期下限 60min，D4）

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("更新排程")
                .font(.subheadline.bold())
            Text("更新周期（hosts 自动更新）")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("更新周期", selection: Binding(
                get: { AppSettings.updateIntervalHours },
                set: { model.setUpdateInterval($0) }
            )) {
                ForEach(AppSettings.updateIntervalOptions, id: \.self) { h in
                    Text("\(h) 小时").tag(h)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("探测周期（访问状态检查）")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("探测周期", selection: Binding(
                get: { AppSettings.probeIntervalMinutes },
                set: { model.setProbeInterval($0) }
            )) {
                ForEach(AppSettings.probeIntervalOptions, id: \.self) { m in
                    Text(m == 60 ? "1 小时" : "\(m / 60) 小时").tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - 定时服务（FR1/FR2：launchd 定时 + 开机运行；M3：安装入口）

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("定时服务")
                .font(.subheadline.bold())
            serviceStateLine
            Text("登录项（登录时自动启动）：\(LoginItem.isRegistered ? "已注册" : "未注册")")
                .font(.caption)
                .foregroundStyle(.secondary)
            if ServiceInfo.intervalSeconds == nil {
                Button(model.actionBusy ? "安装中…" : "安装定时服务") {
                    Task { await model.installService() }
                }
                .controlSize(.small)
                .disabled(model.actionBusy)
            }
        }
    }

    private var serviceStateLine: some View {
        Group {
            if let secs = ServiceInfo.intervalSeconds {
                Text("已安装：每 \(secs / 3600) 小时自动更新，开机运行")
            } else {
                Text("未安装：不会自动更新（仍可用主面板「立即更新」）")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - 镜像源展示（任务书 §6：主/备源状态）；列表镜像 Helper/Sources.swift

    private static let mirrorSources: [(name: String, url: String)] = [
        ("hellogithub", "https://raw.hellogithub.com/hosts"),
        ("ittuann-jsdelivr", "https://cdn.jsdelivr.net/gh/ittuann/GitHub-IP-hosts@main/hosts"),
        ("github520", "https://raw.githubusercontent.com/521xueweihan/GitHub520/main/hosts"),
    ]

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("镜像源")
                .font(.subheadline.bold())
            ForEach(Self.mirrorSources, id: \.name) { src in
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.snapshot.source == src.name ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(src.name)
                        .font(.caption.monospaced())
                    Spacer()
                    Text(src.url)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Text(sourceStatusLine)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(model.snapshot.updateOk == false ? Color.orange : Color.secondary)
        }
    }

    private var sourceStatusLine: String {
        if let err = model.snapshot.updateError {
            return "最近更新：失败（\(err)）"
        }
        if let n = model.snapshot.entries {
            return "最近更新：成功（\(n) 条）"
        }
        return "尚无更新记录"
    }

    // MARK: - 数据与服务（危险操作二次确认，任务书 §6 交互原则）

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("数据与服务")
                .font(.subheadline.bold())
            HStack(spacing: 8) {
                Button(confirmRestore ? "确认还原？" : "还原 hosts") {
                    if confirmRestore {
                        confirmRestore = false
                        Task { await model.restoreHosts() }
                    } else {
                        withAnimation(.easeInOut(duration: 0.15)) { confirmRestore = true }
                    }
                }
                .controlSize(.small)
                .tint(confirmRestore ? .red : .accentColor)
                .disabled(model.actionBusy)

                Button(confirmUninstall ? "确认卸载？" : "卸载秋葵") {
                    if confirmUninstall {
                        confirmUninstall = false
                        Task { await model.uninstallApp() }
                    } else {
                        withAnimation(.easeInOut(duration: 0.15)) { confirmUninstall = true }
                    }
                }
                .controlSize(.small)
                .tint(.red)
                .disabled(model.actionBusy)
            }
            Text("还原保留其余 hosts 内容原样；卸载会移除秋葵在系统中的全部痕迹")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("关于")
                .font(.subheadline.bold())
            Text("秋葵 \(version)")
                .font(.callout)
            Text("通过管理 /etc/hosts 优化 GitHub 访问")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("仅个人自用，不公开分发。绕过网络限制属灰色地带，使用请自行评估风险。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}