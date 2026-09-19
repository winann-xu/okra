# 秋葵 (Okra) 检查点 (Checkpoint)

用途：跨会话 / 跨 Agent 断档交接锚点。
规则：
1. 任何 Agent 接手本项目，先读 `项目任务书.md`（唯一权威任务书），再读本文件，然后从"下一步"继续。
2. 每完成一个里程碑（M0~M4）或做出任何新决策，立即更新本文件：更新"当前状态"与"里程碑状态表"，并在"日志"追加一条（日期 + 做了什么 + 验收证据位置）。
3. 违反任务书 §7 hosts 铁律的代码不允许合入；发现即回滚并记录。

## 当前状态

- 阶段：阶段 3 —— M3 提权路径修复完成（授权对话框不出现 + UI 置灰两个阻塞缺陷），沙箱回归 m1 22+6 / m3 17 全绿；**待用户真机 E2E 点通**（设置动作均需管理员授权对话框，新顺序见 docs/M3-acceptance.md 末节）
- 更新时间：2026-09-19
- 下一步：用户按 docs/M3-acceptance.md「E2E 剩余清单」逐项点通（每步授权后我从 CLI 侧核验状态）→ 收口 M3 → 启动 M4（打包签名公证 + 全新用户账户全流程 + 首次安装流 E2E）。阻塞提示：当前 GitHub 直连不可达（见日志 2026-09-19），本轮修复的分支推送待网络恢复后补做。

## 里程碑状态表

| 里程碑 | 内容 | 状态 | 验收证据 |
|---|---|---|---|
| M0 | 项目骨架（目录结构、SwiftPM 双目标工程、构建脚本、plist 模板、git/GitHub） | ✅ 完成（2026-09-17） | docs/M0-acceptance.md（双路径构建、运行验证、push 记录）；GitHub: github.com/winann-xu/okra |
| M1 | root helper（hosts 区块写入/还原、备份、原子写、主备源、DNS 刷新、状态文件、12h 定时） | ✅ 完成（2026-09-17） | docs/M1-acceptance.md（scripts/m1-acceptance.sh 沙箱 22 项 + 真实源 6 项全绿；install/uninstall 的 root E2E 归 M4） |
| M2 | 菜单栏 App（状态染色、popover 面板、60min 探测、状态文件读取） | ✅ 完成（2026-09-18） | docs/M2-acceptance.md（窗口级捕获+Vision OCR 验证 UI 数据与 status.json 一致；20s 短周期实测定时探测；模拟更新验证"更新成功→立即探测"；[立即更新] 弹窗实测归 M3） |
| M3 | 设置 / 一键还原 / 卸载（含其余 hosts 内容逐字节保留验证） | 🟡 实现完成 + 提权路径修复完成，待真机 E2E（2026-09-19） | docs/M3-acceptance.md（沙箱 17/17；m1 沙箱 22+真实源 6 回归；登录项 register/unregister 实测；设置页窗口级截图 OCR；E2E 剩余清单已更新） |
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
- D9：50% 行数剧变阈值仅同源连续更新生效，源切换不比对（否则主源停摆后备源永远被拒，任务书 §11）
- D10：原子写用 rename(2) 系统调用（本机 macOS 27 的 FileManager.moveItem 目标已存在时报 EEXIST，实测不可用，任务书 §11）

## 待办 / 阻塞

- [x] M2 完成（2026-09-18，证据 docs/M2-acceptance.md）。[立即更新] 触发机制已按建议实现（osascript 管理员授权直跑 helper，一次性程序不做 marker 轮询）；授权弹窗真实环境实测归 M3。
- [x] M3 完成（2026-09-18，实现+沙箱验收；待真机 E2E 六步点通后收口）。
- [x] 仓库可见性（2026-09-18 用户决策）：保持 public，不改 private（任务书新增 D11）。
- [ ] M4 前提醒用户：install/uninstall 的 root E2E 需 sudo（launchd bootstrap + 真实 /etc/hosts 实战），届时由用户执行授权。
- [x] 已解除（2026-09-17）：Xcode 27.0 已装（xcodebuild 双 scheme 验证通过）；token 补 "Contents: Write" 后 push 成功；keychain 旧 github.com 凭据条目已删除（git 现走全局 gh 助手）；git 身份已配置（xwag14 / xwag14@gmail.com）；gh 已认证
- [ ] 待用户真机点通 E2E（提权对话框）：设置→更新周期 4 小时 → [立即更新] → [还原 hosts] → [卸载秋葵] → 重开 App 重装（清单见 docs/M3-acceptance.md 末节）
- [x] 2026-09-19 GitHub 恢复后推送并合并：PR #5（fix/helper-auth-relay）已 merge 入 main（4c0ba88），远端分支已删

## 日志

- 2026-09-17 阶段 0：完成可行性评估与 3 轮网络实测（数据见任务书 §3、§12）；确认范围（仅 GitHub）、技术栈（Swift/SwiftUI）、hosts 铁律、探测周期（60min）、UI 标准、项目名与目录；创建本任务书与本检查点文件。
- 2026-09-17 M0 启动（用户指令"开始项目"）：环境排查（本机无 Xcode；brew cask xcode 已移除；App Store 无 Xcode；Apple 下载页需登录）；git init（main 默认分支）；创建目录结构 App/、Helper/、Resources/、docs/；骨架代码就绪并 swiftc 编译验证；备源验证与备源 2 URL 勘误（D7）。
- 2026-09-17 M0 完成（用户指令：参照 02-G_if 构建方式、免 Xcode；提供 GitHub 仓库 okra）：删除 XcodeGen 方案，改为 SwiftPM（Package.swift 双 executableTarget）+ scripts/build.sh（SDK 固定 MacOSX26.5、组装 Okra.app、ad-hoc 签名、helper 入 Resources）；构建通过（30.5s，包体 152K），App 实测启动/驻留/退出正常，helper 可执行；git 身份配置 + 首次提交；任务书更新 D8 与 M0 验收口径。
- 2026-09-17 M0 收口（用户装好 Xcode 27.0 + token 补 Contents:Write 权限）：xcodebuild 双 scheme BUILD SUCCEEDED（Xcode 原生开 Package.swift，无需工程文件）；push 3 提交至 winann-xu/okra（main=54cb5de）；删除 keychain 旧 github.com 凭据（9/12 条目，曾致 403），git 改走全局 gh 助手；M0 验收全绿，证据见 docs/M0-acceptance.md。下一步 M1。
- 2026-09-17 M1 完成：Helper/ 全部 Swift 实现（上一会话已写、未编译验证；本轮接手后逐层排障）：① 修复编译错误（trimmingCharacters 漏接收者）；② 发现并修复最隐蔽缺陷——main.swift 仅声明 func main() 无顶层语句时生成空入口桩（进程静默 exit 0 不执行业务代码），改顶层入口 + build.sh 加行为级入口哨兵；③ 本机 macOS 27 实测 FileManager.moveItem 目标已存在报 EEXIST、裸 rename(2) 正常，原子写改用 rename(2)（D10）；④ commit() 无结尾换行误删末行修复；⑤ 50% 剧变阈值改仅同源生效（D9，否则源切换永久锁死）；⑥ 状态文件 null 字段显式 NSNull 保 schema 恒定；⑦ fetch 支持 file:// 测试源。验收 scripts/m1-acceptance.sh：沙箱 22 项（铁律逐项 + 边界：无结尾换行/标记损坏/剧变/空镜像/他人区块含后续修改）+ 真实三源 6 项（主源 38 条、全源失败保旧配置、主源故障降级备源 1 84 条、还原干净）= 28/28 全绿；App 启动/驻留/退出正常；install/uninstall 非 root 干净报错。任务书新增 D9/D10。下一步 M2。
- 2026-09-18 M2 完成：App/ 六文件全部实现并构建通过（App 856K + helper 入 Resources）。要点：① 入口分发（OKRA_PREVIEW 窗口预览 / 菜单栏常驻；SceneBuilder 不支持 if/else，用 @main enum 分发两个 App）；② 发现并修复 Info.plist LSUIElement=true 抑制 WindowGroup 开窗（预览模式运行时 setActivationPolicy(.regular)）；③ 探测 5 域 URLSession 并行 10s 超时，写 status.json（更新字段 null 占位保 schema）；④ 2s 轮询 + 60min 探测定时 + 更新成功即时补探 + 启动过期补探；⑤ [立即更新] 经 osascript 管理员授权直跑 helper；⑥ 面板 = 状态灯+结论+5 域名列表+时间+三按钮。验收：本会话 GUI 受限（全屏截屏为空白帧缓冲、AX 树对任何窗口均 0，最小测试 App 亦如此——会话级限制），改用窗口级捕获（screencapture -l<id>）+ Vision OCR 验证：UI 文本/延迟/HTTP 码与 status.json 完全一致（3079/2172/3317/2587/3455ms；200/403/200/404/200；"部分服务异常"/"0/5 域正常"）；OKRA_PROBE_INTERVAL=20 实测定时探测+重新计周期；模拟更新成功 6s 内触发补探（last_probe > last_update）；CGWindowList 交叉验证窗口存在。证据 docs/M2-acceptance.md；人眼确认与 [立即更新] 弹窗实测归 M3。
- 2026-09-18 M3 提交收口（本会话接手）：接手后首跑构建失败，定位 LoginItem.swift unregister 调试行误用全局 log(String)（26.5 SDK 无 String 重载）→ 改为与 register 一致的 OKRA_DEBUG+stderr 诊断；重建通过（1.1M）、m3-acceptance 复跑 17/17 全绿。发现 M1/M2 分支从未开 PR（main 滞留 M0 收口提交 6169543），违反 AGENT.md GitHub Flow；现从 main 线性链补开 3 个 PR 并依序合并（M1→M2→M3），M3 按 feat/test/docs 三个原子提交推送。下一步：用户真机 E2E 六步（docs/M3-acceptance.md）。
- 2026-09-18 流程闭环：用户更新 token（补 Pull requests 权限）后，PR #1/#2/#3（M1/M2/M3）依序合并入 main（merge commit，分支已删），main=c453eb5 为最新；merged main 构建验证通过（1.1M）；生产 App 以 open 重启（launchd 持有）、登录项已注册（raw=1）、启动补探测正常（overall=yellow，hosts 内现有 GitHub520 区块逐字节完好）。用户决策仓库保持 public（任务书新增 D11）。下一步：用户真机 E2E 六步（docs/M3-acceptance.md）→ 收口 M3 → 启动 M4。
- 2026-09-19 E2E 首轮发现与提权路径修复（本会话接手）：接手时工作区留有未提交的在途改动且**编译不通过**（`URL.resolvingSymbolicLinks()` 不存在，已修正为 `resolvingSymlinksInPath()`），说明上一轮的提权修复未走完构建-验证闭环。本轮完成：① helper 新增 `auth` 提权中继子命令（App 不直接调 osascript），输出继承 stdio 不经 Pipe，显式传 `OKRA_USER_HOME`，路径单引号包裹；② App `runHelper` 输出落临时文件（原共享 Pipe 写端被父进程持有 → `readDataToEndOfFile` 永不返回，实测表现为对话框结束后 UI 置灰），`OKRA_DEBUG=1` 落 rc+输出到 `~/Library/Logs/Okra-helper-debug.log`；③ helper 选择改为优先 App 内置副本（已装副本 9/18 旧构建缺 auth），并删掉已无意义的 `preferAppBundled` 参数；④ 修复 dscacheutil 路径（macOS 27 实测 `/usr/sbin/dscacheutil` 不存在→`/usr/bin`，此前每轮更新打警告且 `-flushcache` 从未执行，证据 `~/Library/Application Support/Okra/helper.stdout.log`），子命令非零退出码显式告警。回归：build.sh 通过（含入口哨兵）、m1 沙箱 22/22 + 真实源 6/6、m3 17/17。证据 docs/M3-acceptance.md 末节；任务书新增 D12。本轮改动落在分支 fix/helper-auth-relay（4 个原子提交，合并情况见下条）。
- 2026-09-19 网络观测（19:00 CST）：GitHub 直连整体不可达——`github.com` 七个候选 IP（20.205.243.166 / 140.82.112.3 / 140.82.113.3 / 140.82.114.3 / 140.82.121.4 / 140.82.116.3 / 172.182.252.133）:443 全部 6~8s 超时，`raw.githubusercontent.com` 185.199.111.133 超时；同期 www.baidu.com 0.08s、raw.hellogithub.com 0.14s、cdn.jsdelivr.net 0.27s 均 200。故 `git push`/`git fetch`（github.com:443）与 raw 备源因此失败，非 hosts 配置问题；服务保留旧配置的降级行为正确。待网络恢复补推送与 PR。
- 2026-09-19 推送合并闭环：GitHub 于 19:11 恢复（github.com 走 hosts 固定 IP 20.205.243.166，TLS 正常、首包 6s，属限速态），`git push` 成功 → PR #5（fix/helper-auth-relay，含 4 个原子提交）已 merge 入 main（merge commit 4c0ba88，远端分支已删），本地 main 已 ff 到 4c0ba88 且工作区干净。后台重试脚本（/tmp/okra-push-retry.sh）已停止。
- 2026-09-19 生产弹层缺陷（E2E 第二轮，用户报告「点了设置没反应」）：定位为 `MenuBarExtra` 未指定样式，默认走 `.menu`（下拉菜单）——该样式忽略自定义布局/图形、点按钮即收起菜单，故点「设置」看不到任何变化。此前 M2/M3 的 UI 验收全走 `OKRA_PREVIEW` 的 WindowGroup，从未覆盖真实弹层形态，属验收盲区。修复：显式 `.menuBarExtraStyle(.window)` + 设置页固定高度 460（弹层无外部尺寸约束）。已重建（1.1M）并重启 App（pid 42053）。同轮排查证据：`defaults read com.winann.okra` 无 `updateIntervalHours` 键 → 用户未真正触发周期变更；`log show` 无 osascript 记录 → 未发起过提权；AX 树可用（`System Events` 能读到状态项「叶子/状态菜单」、position 1005,4 size 34,24），与检查点旧记录「AX 树返回 0」不一致，后续 GUI 验证可改用 AX + 合成点击（/tmp/click / /tmp/winany）。
- 2026-09-19 弹层第二轮修复（用户反馈「修好 #4 后再点设置，界面没出来」）：定位为 `.window` 样式弹层内 `ScrollView` 的已知塌缩缺陷（SO 77487268：首次展开正常，其后展开塌缩到极小高度）——设置页外层正是 ScrollView，塌缩后连材质卡片一起变 0 高，观感就是"什么都没有"。修复：设置页去 ScrollView 改平铺 VStack（约 570pt，由弹层按内容撑开），并撤掉上一轮加的固定 460 高度。同时本轮把 launchctl 卸载写法修复（PR #8）合并入 main=a471584；弹层相关改动仍在 PR #7 分支（未合并，待真机确认）。环境侧新增能力：本会话 AX 可用（可读状态项/菜单栏）、可用 screencapture 区域抓帧（/tmp/catch-panel.sh、/tmp/panel-watch.sh）与 Vision OCR（/tmp/ocr）做独立取证。
- 2026-09-19 用户真机第三轮（授权链路打通 + 发现 launchctl 缺陷）：用户点设置页「4 小时」后授权对话框正常弹出、root 动作执行成功（/Library/Okra/OkraHelper 更新为新构建、plist 写成 StartInterval=14400），但状态文件报 `launchctl bootstrap 失败（rc=5）`，且 `launchctl print` 显示已加载实例仍是 `run interval = 43200`。根因：`bootout` 写成 `<domain> <label>`（无效形式，rc=64，代码忽略返回值）→ 旧实例仍在 → bootstrap EIO(5)。非 root 用 gui/501 域完整复现并验证正确写法 `bootout system/<label>`；修复见 PR #8（已合并）。另用户反馈设置页两组「4 小时」无法区分 → 两个选择器补标题（同 PR #8）。
- 2026-09-19 已装服务状态核验（CLI 侧，E2E 第 1 步已有证据）：`/Library/LaunchDaemons/com.winann.okra.helper.plist` 存在（RunAtLoad=true，StartInterval=43200，Program=/Library/Okra/OkraHelper，OKRA_USER_HOME 已写）；helper.stdout.log 显示 00:14（RunAtLoad）与 12:14（StartInterval 二轮）两次更新成功，各 39 条目标记；status.json 最近更新 2026-09-19T04:14:39Z（源 hellogithub，39 条，update_ok=true），最近探测 2026-09-19T10:47:00Z（overall=yellow，objects.githubusercontent.com 404 未过）。

## 给新 Agent 的交接提示

1. 权威文档优先级：`项目任务书.md` > 本文件 > 代码注释；编码与沟通规范以目录内 `AGENT.md`（用户既定技术规范，含 git 工作流要求）为准。三者冲突时以任务书 + AGENT.md 为准并修正本文件。
2. 动手前必读任务书 §7（hosts 铁律）与 §9（各 M 的验收标准）；每个 M 的验收必须产出可复现的证据命令/输出，存档到 docs/。
3. 环境注意：项目目录 /Users/winann/01-project/06-okra；macOS 27.0 + CommandLineTools（无 Xcode，构建走 scripts/build.sh，勿引入 Xcode 依赖）；写 /etc/hosts 需 root（helper 安装走系统授权对话框）；git 远端 winann-xu/okra（gh 已认证）。注意：MTPLX/Agent 会话内 GUI 受限——全屏 screencapture 得空白帧缓冲、System Events AX 树对任何窗口返回 0；GUI 验证须用窗口级捕获（`screencapture -l<CGWindowID>`，windowID 可从 CGWindowListCopyWindowInfo 取）+ Vision OCR（python 无 pyobjc，用 swift 脚本），窗口存在性用 CGWindowList（WindowServer 层）交叉验证。
4. 任何范围变更（加 HF、改周期、换技术栈）必须先经用户确认，并更新任务书 §11 决策记录。
