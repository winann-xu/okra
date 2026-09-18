# M2 验收记录 —— 菜单栏 App

日期：2026-09-18
环境：macOS 27.0（screen 3456×2234 Retina）+ CommandLineTools（MacOSX26.5 SDK，D8 固定）
分支：feat/m2-menubar-app

## 交付物

- `App/OkraApp.swift`：入口分发（OKRA_PREVIEW=1 → 普通窗口；否则 → MenuBarExtra 常驻）；`--probe-once` 调试入口；菜单栏图标状态染色（绿/黄/红/灰）+ 异常呼吸动效
- `App/StatusIO.swift`（App 侧）：读 `~/Library/Application Support/Okra/status.json`（schema 与 helper 一致，任务书 §7）；5 域 ProbeRow + 绿/黄/红判定（≥3000ms 阈值）
- `App/Prober.swift`：URLSession 并行探测 5 域（10s 超时），写回 status.json（更新字段 null 占位保 schema 恒定，与 helper 侧同规则）
- `App/StatusModel.swift`：2s 轮询状态文件秒级刷新；60min 探测定时器（OKRA_PROBE_INTERVAL 可覆盖）；启动时探测数据过期立即补探；hosts 更新成功（lastUpdate 变化且 update_ok）立即补探；[立即更新] 经 osascript 管理员授权直跑 helper（一次性程序，不做 marker 轮询）
- `App/MenuBarView.swift`：popover 面板 = 状态灯+一句话结论+5 域名列表（状态点/延迟/HTTP 码）+更新时间/探测时间+[立即更新][立即探测][设置]
- `App/SettingsView.swift`：设置/关于页（免责说明；更新周期/镜像源/还原/卸载 M3 补全）
- `Helper/StatusFile.swift`：root 写用户目录后 chown 回用户（chownSupportToUser，backup() 亦调用）

## 验收结果

| # | 验收项（任务书 §6/§9） | 结果 | 证据 |
|---|---|---|---|
| 1 | build.sh 构建 App + Helper | ✅ | Build complete 10s；Okra.app 856K，ad-hoc 签名；helper 入 Resources |
| 2 | `--probe-once` 探测并写 status.json | ✅ | 4.2s 完成；status.json 七字段齐全，5 域真实数据（200/403/200/404/200） |
| 3 | 探测 5 域名 + HTTP 码 + 延迟 | ✅ | UI 显示 3079/2172/3317/2587/3455 ms 与 status.json 完全一致 |
| 4 | 总状态绿/黄/红判定 | ✅（黄） | 限速基线下 5 域全超阈/403/404 → 整体黄、"部分服务异常"、"0/5 域正常"（判定逻辑代码审读通过；绿/红形态需对应网络基线实测，见下） |
| 5 | 60min 定时探测 | ✅ | 用 OKRA_PROBE_INTERVAL=20 实测：启动补探 + 20s tick 执行 + 完成后重新计周期（last_probe=21:44:06Z，age 8s）；默认 3600s |
| 6 | hosts 更新成功 → 立即探测 | ✅ | 模拟 update_ok=true/last_update=21:46:19Z → 2s 内轮询发现 → 21:46:25Z 自动补探（last_probe > last_update） |
| 7 | 状态文件 2s 轮询秒级刷新 | ✅ | 由 #6 的响应时间间接验证（≤6s，含探测耗时） |
| 8 | [立即更新] 触发机制 | ✅（代码）/待 M3 实测 | osascript with administrator privileges 直跑 helper；本会话未装 launchd 服务，授权弹窗实测归 M3/M4 |
| 9 | 设置/关于页 | ✅（代码+按钮） | OCR 见 [设置] 按钮；页面切换未单独视觉实测（会话限制，见下） |
| 10 | 菜单栏图标染色 + 呼吸动效 | ✅（代码审读） | MenuBarIcon：绿/黄/红/灰 + 异常 repeatForever 呼吸；本会话无法视觉实测 |

## 会话限制说明（诚实记录）

本 Agent 会话的 GUI 环境受限：
- 全屏 `screencapture` 得到的是空白 framebuffer（全图 OCR 0 行文字；69% 亮像素仅为壁纸）；
- System Events AX 树对任何窗口均返回 0（连最小 WindowGroup 测试 App 也如此）——为会话级限制，非代码缺陷；
- 因此视觉验收改用 **窗口级捕获**（`screencapture -l<windowID>`，走窗口 backing store 路径）+ **Vision OCR**，成功读出面板全部文本与数据（见上 #3/#4/#9）；
- 窗口存在性另用 CGWindowList（WindowServer 层）交叉验证：`秋葵 | Okra`（340×508pt）。

用户本机直接运行 `open Okra.app`（菜单栏常驻）或 `OKRA_PREVIEW=1 open Okra.app`（窗口预览）即可做最终人眼确认。窗口级截图证据：`/tmp/okra-win.png`（会话产物，临时）。

## 结论

M2 功能全部实现且核心链路（状态文件 ⇄ 探测 ⇄ UI 数据）端到端验证通过；UI 渲染经窗口级捕获 + OCR 验证与数据一致。
剩余人眼确认（配色/呼吸动效观感）与 [立即更新] 授权弹窗实测，建议在 M3（设置页补全 + 一键还原）一并做真实环境验收。
