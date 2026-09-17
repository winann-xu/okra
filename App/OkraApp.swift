import SwiftUI

/// App 入口分发：OKRA_PREVIEW=1 → 普通窗口（UI 检视/验收）；否则 → 菜单栏常驻。
/// SceneBuilder 不支持 if/else 分支，故用显式分发到两个 App。
@main
enum OkraMain {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        if env["OKRA_PREVIEW"] == "1" {
            PreviewApp.main()
        } else {
            OkraApp.main()
        }
    }
}

/// 菜单栏常驻 App（生产形态）。
struct OkraApp: App {
    @StateObject private var model = StatusModel()

    init() {
        // 调试/测试入口：Okra --probe-once = 执行一次探测并写状态文件后退出（不启动 GUI）。
        if CommandLine.arguments.contains("--probe-once") {
            let sem = DispatchSemaphore(value: 0)
            var failed = false
            Task.detached(priority: .userInitiated) {
                do { try await Prober.runAndWrite() } catch { failed = true }
                sem.signal()
            }
            sem.wait()
            exit(failed ? 1 : 0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            MenuBarIcon()
                .environmentObject(model)
        }
    }
}

/// 预览形态：主面板以普通窗口展示，便于检视 UI 与自动化验收（M2 交付形态）。
struct PreviewApp: App {
    @StateObject private var model = StatusModel()

    init() {
        // Info.plist 为菜单栏常驻形态设了 LSUIElement（agent 模式，会抑制 WindowGroup 开窗）；
        // 预览模式运行时改回 regular，使窗口正常显示。
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Okra") {
            MenuBarView()
                .environmentObject(model)
                .frame(width: 340, height: 480)
        }
        .windowResizability(.contentSize)
    }
}

/// 菜单栏图标：单色（SF Symbol）+ 状态染色（绿/黄/红/灰），异常时带轻微呼吸动效。
struct MenuBarIcon: View {
    @EnvironmentObject var model: StatusModel
    @State private var dim = false

    private var level: ProbeLevel? { model.overall }

    var body: some View {
        Image(systemName: "leaf.fill")
            .foregroundStyle(tint)
            .opacity(dim ? 0.3 : 1.0)
            .onAppear(perform: syncBreathing)
            .onChange(of: level) { _ in syncBreathing() }
    }

    private var tint: Color {
        switch level {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        case nil: return .secondary
        }
    }

    /// 呼吸动效：黄/红时 repeatForever；回绿/灰时停止动画复位。
    private func syncBreathing() {
        let abnormal = level != nil && level != .green
        if abnormal && !dim {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { dim = true }
        } else if !abnormal && dim {
            withAnimation(.easeOut(duration: 0.3)) { dim = false }
        }
    }
}
