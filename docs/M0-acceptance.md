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
- 远端：https://github.com/winann-xu/okra.git
- 首次 push 成功（见 git log / GitHub 仓库）

## 结论

M0 验收通过：构建脚本产出可运行 Okra.app（含 OkraHelper）；目录结构符合任务书；git 已初始化并推送 GitHub。
