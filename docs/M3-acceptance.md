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

## 真机 E2E 首轮实测与提权路径修复（2026-09-19）

### 暴露的缺陷（均已修复）
| # | 现象 | 根因 | 修复 |
|---|---|---|---|
| 1 | 点设置动作后系统授权对话框不出现，动作无输出地卡住 | LSUIElement 应用 bundle 直接调 `osascript … with administrator privileges` 不弹窗（9/18 真机实测） | helper 新增 `auth` 中继子命令：App 调普通二进制，由其内部发起 osascript 提权 |
| 2 | 授权对话框消失后 App UI 全部置灰 | `runHelper` 用共享 Pipe 读输出，写端仍被父进程持有 → `readDataToEndOfFile` 永不返回 | 输出落临时文件；helper 侧 `auth` 直接继承 stdio，不经 Pipe |
| 3 | 每轮更新 stderr 打「`/usr/sbin/dscacheutil` 不存在」 | macOS 27 该文件位于 `/usr/bin`（实测 `/usr/sbin/dscacheutil` 不存在） | 候选路径取首个可执行者；子命令非零退出码显式告警 |
| 4 | 生产形态点菜单栏「设置」无任何反应（面板不切换） | `MenuBarExtra` 默认样式是 `.menu`（下拉菜单）：自定义布局/图形被忽略、点按钮即收起菜单。此前 M2/M3 的 UI 验收全部走 `OKRA_PREVIEW` 的 WindowGroup，未覆盖真实弹层形态 | 显式 `.menuBarExtraStyle(.window)`，并把设置页放进固定高度（弹层无外部尺寸约束，ScrollView 需确定高度） |

证据：#3 见 `~/Library/Application Support/Okra/helper.stdout.log`（9/19 00:14 与 12:14 两轮 RunAtLoad/StartInterval 更新均带该警告）。

### 附带改进
- App 调 helper 时优先用 App 内置副本（与本 App 调用协议同版本），已装副本仅供 launchd 使用——避免「已装副本为旧版本、无 auth 子命令」导致的失败。
- `OKRA_DEBUG=1` 时每次授权调用把 rc + 完整输出追加到 `~/Library/Logs/Okra-helper-debug.log`，便于排查授权问题。

### 沙箱回归（新构建，2026-09-19）
- `scripts/build.sh`：构建通过（含入口哨兵），包体 1.1M
- `scripts/m1-acceptance.sh live`：沙箱 22/22 + 真实源 6/6（主源 38 条、备源 84 条、全源失败保留旧配置）
- `scripts/m3-acceptance.sh`：17/17（铁律逐项 + 他人区块逐字节保留 + 还原 + 非 root 干净报错）

### 环境观测（2026-09-19 19:00 CST）
GitHub 直连当前不可达：`github.com` 候选 IP（20.205.243.166、140.82.112.3、140.82.113.3、140.82.114.3、140.82.121.4、140.82.116.3、172.182.252.133）:443 全部 6~8s 超时，`raw.githubusercontent.com` 185.199.111.133 超时；同期 www.baidu.com / raw.hellogithub.com / cdn.jsdelivr.net 均 200 且 <0.3s。即当下 GitHub 链路整体不可达（非 hosts 配置问题），git push 与 raw 备源在此期间不可用。

### E2E 剩余清单（新顺序，需用户点击授权对话框）
「已装服务」状态下的 helper 二进制为 9/18 旧构建，但 App 侧已改为优先内置 helper，可任选起点：
1. 设置 → 更新周期改 4 小时 → 授权 → 核验 plist `StartInterval=14400` + `/Library/Okra/OkraHelper` 被新构建覆盖
2. [立即更新] → 授权 → 核验 `status.json` 的 `last_update` 刷新 + 触发补探测
3. [还原 hosts] → 二次确认 → 授权 → 核验 Okra 区块移除、他人区块逐字节完好
4. [卸载秋葵] → 二次确认 → 授权 → 核验 launchd 服务/plist/二进制/状态目录/登录项全清
5. 重新打开 App → [安装定时服务] → 授权 → 登录项自动恢复注册
（步骤 1 的「安装」与 12h 定时更新已于 9/19 00:14/12:14 实测通过：plist 存在 + RunAtLoad 更新成功 + StartInterval 二轮触发）

## 备注
- sfltool dumpbtm 在无 GUI 会话环境会挂起（已知现象），登录项状态以 SMAppService.status 为准
- macOS 27 SDK 的 SMAppService.Status Swift 接口仅暴露 3 个 case，raw=3 为未公开内部状态
  （首次注册前短暂出现，注册后即 .enabled，不影响逻辑）