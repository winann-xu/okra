// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Okra",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // 组件 A：菜单栏 App
        .executableTarget(
            name: "Okra",
            path: "App"
        ),
        // 组件 B：root 级 launchd daemon
        .executableTarget(
            name: "OkraHelper",
            path: "Helper"
        )
    ]
)
