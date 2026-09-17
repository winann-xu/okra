# 秋葵 (Okra) 检查点 (Checkpoint)

用途：跨会话 / 跨 Agent 断档交接锚点。
规则：
1. 任何 Agent 接手本项目，先读 `项目任务书.md`（唯一权威任务书），再读本文件，然后从"下一步"继续。
2. 每完成一个里程碑（M0~M4）或做出任何新决策，立即更新本文件：更新"当前状态"与"里程碑状态表"，并在"日志"追加一条（日期 + 做了什么 + 验收证据位置）。
3. 违反任务书 §7 hosts 铁律的代码不允许合入；发现即回滚并记录。

## 当前状态

- 阶段：阶段 2 —— M0 已完成，待启动 M1（root helper）
- 更新时间：2026-09-17
- 下一步：启动 M1：实现 §7 全部 hosts 铁律 + 主备源拉取 + DNS 刷新 + 状态文件 + 12h 定时（Helper/ 内，Swift 实现）。

## 里程碑状态表

| 里程碑 | 内容 | 状态 | 验收证据 |
|---|---|---|---|
| M0 | 项目骨架（目录结构、SwiftPM 双目标工程、构建脚本、plist 模板、git/GitHub） | ✅ 完成（2026-09-17） | docs/M0-acceptance.md（构建输出、运行验证、push 记录）；GitHub: github.com/winann-xu/okra |
| M1 | root helper（hosts 区块写入/还原、备份、原子写、主备源、DNS 刷新、状态文件、12h 定时） | ⬜ 未开始 | — |
| M2 | 菜单栏 App（状态染色、popover 面板、60min 探测、状态文件读取） | ⬜ 未开始 | — |
| M3 | 设置 / 一键还原 / 卸载（含其余 hosts 内容逐字节保留验证） | ⬜ 未开始 | — |
| M4 | 打包、签名、公证、首次安装流程端到端 | ⬜ 未开始 | — |

## 已确认的关键决策（详见任务书 §11）

- v1 只做 GitHub；HuggingFace 移至 v2（主域名 SNI 层封锁，hosts 无效，证据见任务书 §8）
- 技术栈：Swift + SwiftUI，零第三方依赖，包体 < 10MB（当前 152K）
- 构建体系（D8，用户决定）：SwiftPM + scripts/build.sh 组装 .app + ad-hoc 签名，不用 Xcode；CLT 固定 MacOSX26.5 SDK（27.0 SDK 会致 SwiftUI 宏编译失败）
- hosts 铁律：只管理 `# Okra Start` / `# Okra End` 区块；区块外字节绝不动；备份 + 原子写 + 写前校验（任务书 §7）
- 探测周期 60min；hosts 更新成功后立即补探测一次
- 更新周期 12h（launchd StartInterval=43200，root daemon 独立运行）
- UI 要求：漂亮、人性化，原生 macOS 质感，中文界面，不暴露命令行概念
- 项目名：秋葵 / Okra；目录：/Users/winann/01-project/06-okra；GitHub：winann-xu/okra
- D7：备源 2 URL 勘误（521xvwebsites → 521xueweihan/GitHub520），三源均已实测验证（任务书 §7/§11）

## 待办 / 阻塞

- [ ] M1 开工（无阻塞）
- [ ] 仓库可见性提醒待用户确认：用户以 PUBLIC 创建了 winann-xu/okra；任务书定位"仅个人自用、不公开分发"，建议评估是否转 private（`gh repo edit okra --visibility private`）
- [x] 阻塞已解除：Xcode 不再需要（D8）；git 身份已配置（xwag14 / xwag14@gmail.com）；gh 已认证，仓库已建

## 日志

- 2026-09-17 阶段 0：完成可行性评估与 3 轮网络实测（数据见任务书 §3、§12）；确认范围（仅 GitHub）、技术栈（Swift/SwiftUI）、hosts 铁律、探测周期（60min）、UI 标准、项目名与目录；创建本任务书与本检查点文件。
- 2026-09-17 M0 启动（用户指令"开始项目"）：环境排查（本机无 Xcode；brew cask xcode 已移除；App Store 无 Xcode；Apple 下载页需登录）；git init（main 默认分支）；创建目录结构 App/、Helper/、Resources/、docs/；骨架代码就绪并 swiftc 编译验证；备源验证与备源 2 URL 勘误（D7）。
- 2026-09-17 M0 完成（用户指令：参照 02-G_if 构建方式、免 Xcode；提供 GitHub 仓库 okra）：删除 XcodeGen 方案，改为 SwiftPM（Package.swift 双 executableTarget）+ scripts/build.sh（SDK 固定 MacOSX26.5、组装 Okra.app、ad-hoc 签名、helper 入 Resources）；构建通过（30.5s，包体 152K），App 实测启动/驻留/退出正常，helper 可执行；git 身份配置 + 首次提交并推送 winann-xu/okra；任务书更新 D8 与 M0 验收口径。验收证据：docs/M0-acceptance.md。

## 给新 Agent 的交接提示

1. 权威文档优先级：`项目任务书.md` > 本文件 > 代码注释；编码与沟通规范以目录内 `AGENT.md`（用户既定技术规范，含 git 工作流要求）为准。三者冲突时以任务书 + AGENT.md 为准并修正本文件。
2. 动手前必读任务书 §7（hosts 铁律）与 §9（各 M 的验收标准）；每个 M 的验收必须产出可复现的证据命令/输出，存档到 docs/。
3. 环境注意：项目目录 /Users/winann/01-project/06-okra；macOS 27.0 + CommandLineTools（无 Xcode，构建走 scripts/build.sh，勿引入 Xcode 依赖）；写 /etc/hosts 需 root（helper 安装走系统授权对话框）；git 远端 winann-xu/okra（gh 已认证）。
4. 任何范围变更（加 HF、改周期、换技术栈）必须先经用户确认，并更新任务书 §11 决策记录。
