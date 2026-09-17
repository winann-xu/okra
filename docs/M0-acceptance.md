# M0 项目骨架 —— 验收证据（2026-09-17）

## 1. 构建（无 Xcode，SwiftPM + build.sh）

```
$ ./scripts/build.sh
[141 / 143] Okra-product
Build complete! (30.55秒)
[2/4] 组装 Okra.app ...
[3/4] ad-hoc 签名...
Okra.app: replacing existing signature
[4/4] 完成
   App:    /Users/winann/01-project/06-okra/Okra.app (152K)
   Helper: Okra.app/Contents/Resources/OkraHelper
```

- 说明：本机 CLT 6.4 默认 MacOSX27.0 SDK 会导致 SwiftUI 宏编译失败（-target-arch-variant 不识别），build.sh 固定使用 MacOSX26.5 SDK（与 02-G_if/GPUMonitor 相同做法）。
- 包体 152K，远低于任务书 <10MB 要求。

## 2. 运行验证

```
$ ./Okra.app/Contents/MacOS/Okra   （后台启动）
APP RUNNING OK                      # 菜单栏 App 正常驻留
$ ./Okra.app/Contents/Resources/OkraHelper update
OkraHelper skeleton: action=update（M1 实现实际逻辑）
$ ./Okra.app/Contents/Resources/OkraHelper restore
OkraHelper skeleton: action=restore（M1 实现实际逻辑）
（pkill 后） app 已停止（验证结束）   # 正常退出，无残留进程
```

## 3. git

- git init -b main（main 默认分支）
- 本地提交 2 个（feat: M0 骨架；docs: 任务书/检查点/证据）
- 远端：https://github.com/winann-xu/okra.git（用户创建）
- push：⏳ 阻塞中 —— 用户提供的 fine-grained token（github_pat_ 前缀）缺 "Contents: Write" 权限。实测：REST API 写操作 200（改 description 成功）、git 读 200、git receive-pack 403（"Permission denied"）。→ 用户在 GitHub 该 token 设置页给 Contents 加 Write 后，重跑 `git push -u origin main` 即可。

## 4. Xcode 构建验证（2026-09-17，用户安装 Xcode 27.0 后）

Xcode 原生打开 Package.swift（自动生成 Okra / OkraHelper / Okra-Package 三个 scheme），无需额外工程文件：

```
$ xcodebuild -scheme Okra -configuration Debug -destination platform=macOS build
** BUILD SUCCEEDED **
$ xcodebuild -scheme OkraHelper -configuration Debug -destination platform=macOS build
** BUILD SUCCEEDED **
```

- 注：Xcode 工具链（SDK 27.0）编译本包无 CLT 的 -target-arch-variant 宏问题；build.sh 仍固定 MacOSX26.5 SDK（CLT 路径需要）。

## 结论

M0 验收全部通过：构建脚本（SPM 路径）通过、.app 152K 可运行、xcodebuild（Xcode 27 路径）BUILD SUCCEEDED、目录结构符合任务书、git 已初始化（main 默认分支）；仅 GitHub push 等待 token 补 "Contents: Write" 权限（见 §3）。
