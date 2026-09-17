import SwiftUI

/// M0 骨架：最小面板占位。M2 实现完整 UI（状态灯、域名列表、操作按钮，规范见任务书 §6）。
struct MenuBarView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("秋葵")
                .font(.title2.bold())
            Text("项目骨架（M0）")
                .foregroundStyle(.secondary)
            Button("退出") {
                NSApp.terminate(nil)
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 320)
    }
}
