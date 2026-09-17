import SwiftUI

@main
struct OkraApp: App {
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            // M0 占位图标；M2 按状态染色（绿/黄/红）
            Image(systemName: "leaf.fill")
        }
    }
}
