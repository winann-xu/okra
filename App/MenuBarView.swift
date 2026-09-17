import SwiftUI

/// Popover 主面板（任务书 §6）：
/// 顶部状态灯 + 一句话结论；中部 5 域名列表（域名 + 状态点 + 延迟 + HTTP 码）；
/// 底部更新时间 / 探测时间 + [立即更新] [立即探测] [设置]。
struct MenuBarView: View {
    @EnvironmentObject var model: StatusModel
    @State private var showSettings = false

    var body: some View {
        Group {
            if showSettings {
                SettingsView(onBack: { withAnimation(.easeInOut(duration: 0.15)) { showSettings = false } })
            } else {
                mainPanel
            }
        }
        .frame(width: 320)
        .padding(10)
    }

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            domainList
            Divider()
            footer
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    // MARK: - 顶部：状态灯 + 一句话结论

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Circle()
                    .fill(lampColor)
                    .frame(width: 14, height: 14)
                    .shadow(color: lampColor.opacity(0.7), radius: 5)
                Text(conclusion)
                    .font(.headline)
                Spacer()
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var level: ProbeLevel? { model.overall }

    private var lampColor: Color {
        (level ?? nil).map { $0.color } ?? Color.secondary.opacity(0.5)
    }

    private var conclusion: String {
        switch level {
        case .green: return "GitHub 访问畅通"
        case .yellow: return "部分服务异常"
        case .red: return "GitHub 不可达"
        case nil: return model.probing ? "正在探测…" : "等待首次探测"
        }
    }

    private var subtitle: String {
        let rows = model.rows
        let normal = rows.filter { $0.level == .green }.count
        if level == nil {
            return model.probing ? "正在探测 5 个域名" : "尚未有探测数据"
        }
        return "\(normal)/5 域正常"
    }

    // MARK: - 中部：5 域名列表

    private var domainList: some View {
        VStack(spacing: 0) {
            ForEach(model.rows) { row in
                HStack(spacing: 8) {
                    Circle()
                        .fill(row.level?.color ?? Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text(row.domain)
                        .font(.callout.monospaced())
                    Spacer()
                    Text(row.ms.map { String($0) + " ms" } ?? "—")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(row.code.map { String($0) } ?? "—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(row.level?.color ?? Color.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.vertical, 5)
            }
        }
    }

    // MARK: - 底部：时间 + 操作按钮

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("更新 \(TimeFmt.local(model.snapshot.lastUpdate))")
                Spacer()
                Text("探测 \(TimeFmt.local(model.snapshot.lastProbe))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let err = model.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                Button(model.updating ? "更新中…" : "立即更新") {
                    Task { await model.updateNow() }
                }
                .disabled(model.updating)

                Button(model.probing ? "探测中…" : "立即探测") {
                    Task { await model.probeNow() }
                }
                .disabled(model.probing)

                Button("设置") {
                    withAnimation(.easeInOut(duration: 0.15)) { showSettings = true }
                }
            }
            .controlSize(.small)
        }
    }
}
