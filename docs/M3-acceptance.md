# M3 验收记录（2026-09-18）

## 范围（任务书 §9 M3 + checkpoint）
① SettingsView 完整化（更新周期可配置、镜像源展示、一键还原、卸载入口，全部经系统管理员
授权对话框调用 root helper）② helper restore/uninstall 命令（M1 已实现，本次回归）
③ 登录项（SMAppService）④ UI 验收 ⑤ E2E 验收（真机点通，移交用户）。

## 代码变更
- App/SettingsView.swift：完整设置页（更新周期 4/12/24h、探测周期 1/2/4h 分段选择器；
  定时服务状态 + 安装入口；镜像源三源展示 + 当前源高亮 + 上次更新结果；
  还原 hosts / 卸载秋葵（危险操作二次确认：按钮变「确认…？」再点才执行）；关于与免责）
- App/AppSettings.swift（新）：UserDefaults 持久化更新/探测周期（默认 12h / 60min）
- App/ServiceInfo.swift（新）：直读 /Library/LaunchDaemons plist 判断服务安装状态与周期
- App/LoginItem.swift（新）：SMAppService 登录项注册/注销（幂等，失败仅告警；
  OKRA_DEBUG=1 输出状态诊断）
- App/StatusModel.swift：统一 runHelper（osascript 管理员授权 + OKRA_USER_HOME，
  nonisolated 执行避免对话框期间 UI 冻结）；新增 installService / restoreHosts /
  uninstallApp / setUpdateInterval（服务已装→立即重装服务生效）/ setProbeInterval（立即重排程）
- App/OkraApp.swift：生产/预览启动均幂等注册登录项；OKRA_UNREGISTER=1 测试钩子
- App/MenuBarView.swift：OKRA_PREVIEW_SETTINGS=1 预览窗口直开设置页（UI 验收钩子）
- helper 无代码变更（restore/uninstall/install --interval 均已在 M1 实现并通过本次回归）

## 沙箱验收（scripts/m3-acceptance.sh，17/17 通过）
- T1 首次更新：区块写入、镜像条目写入、行内注释行丢弃
- T2 更新后区块外内容（含他人 GitHub520 区块 + 用户自定义行）逐字节一致
- T3 模拟他人后续修改（他人区块内加行 + 区块外加行）
- T4 二次更新：幂等（区块唯一）、他人后续修改逐字节保留
- T5 一键还原：无标记残留、还原后与还原前（去区块）逐字节一致
- T6 还原后再更新：可恢复、他人内容仍逐字节保留
- T7 非 root uninstall：非零退出 + 人话报错 + 未动 hosts

## 登录项（FR1）验证
- SMAppService 状态机实测（本 SDK 映射：notRegistered=0, enabled=1, requiresApproval=2）：
  register 0→1 ✓；unregister 1→0 ✓（下次启动读到 0）；已 enabled 时 register 幂等无副作用 ✓
- 设置页 UI 正确显示「登录项（登录时自动启动）：已注册」（窗口级截图 OCR 确认）
- 当前机器状态：生产菜单栏 App 运行中，登录项已注册

## 设置页 UI 验收（窗口级截图 + Vision OCR，OKRA_PREVIEW/OKRA_PREVIEW_SETTINGS=1）
- 返回/设置、更新排程双分段选择器（4/12/24h 与 1/2/4h）、定时服务状态行、
  登录项状态行、安装定时服务按钮、镜像源三源列表（当前源绿点 + URL 截断）、
  上次更新结果行、还原 hosts / 卸载秋葵按钮 + 说明、关于与免责——全部渲染正常

## E2E 验收（待用户真机点通——需管理员授权对话框交互）
按序操作（每步我都会从 CLI 侧核验状态）：
1. 菜单栏 App → 设置 → [安装定时服务] → 授权 → 核验 launchd 服务 + 立即执行一次更新
2. 设置 → 更新周期改 4 小时 → 授权 → 核验 plist StartInterval=14400
3. [立即更新] → 授权 → 核验状态文件 last_update 刷新 + 探测触发
4. [还原 hosts] → 二次确认 → 授权 → 核验 GitHub520 区块逐字节完好、无 Okra 残留
5. [卸载秋葵] → 二次确认 → 授权 → 核验 launchd/plist/二进制/状态目录/登录项全清
6. 重新打开 App → 登录项自动恢复注册

## 备注
- sfltool dumpbtm 在无 GUI 会话环境会挂起（已知现象），登录项状态以 SMAppService.status 为准
- macOS 27 SDK 的 SMAppService.Status Swift 接口仅暴露 3 个 case，raw=3 为未公开内部状态
  （首次注册前短暂出现，注册后即 .enabled，不影响逻辑）