import SwiftUI

/// 设置页（M2：关于与免责；更新周期 / 镜像源 / 还原 / 卸载由 M3 补全）。
struct SettingsView: View {
    var onBack: () -> Void

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button("返回") { onBack() }
                    .controlSize(.small)
                Spacer()
                Text("设置")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("秋葵 \(version)")
                    .font(.title3.bold())
                Text("通过管理 /etc/hosts 优化 GitHub 访问")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("说明")
                    .font(.subheadline.bold())
                Text("仅个人自用，不公开分发。绕过网络限制属灰色地带，使用请自行评估风险。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
    }
}
