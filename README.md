# 秋葵 (Okra)

macOS 菜单栏工具：通过管理 /etc/hosts 优化中国大陆访问 GitHub。

- 技术栈：Swift + SwiftUI，零第三方运行时依赖
- 目标系统：macOS 13+
- 构建：SwiftPM + 脚本打包（无需 Xcode，仅 CommandLineTools；见决策 D9）
- 架构：Okra.app（菜单栏 UI + 探测） + OkraHelper（root daemon，launchd 12h 定时更新）
- 权威文档：`项目任务书.md`（范围/铁律/验收标准）、`check point.md`（进度与交接）、`AGENT.md`（编码规范）

## 构建

```bash
./scripts/build.sh
```

产物：`Okra.app`（ad-hoc 签名，含 Resources/OkraHelper）。

## 目录

```
App/        菜单栏 App 源码
Helper/     root daemon 源码
Resources/  launchd plist 模板
scripts/    构建脚本
docs/       里程碑验收证据
```