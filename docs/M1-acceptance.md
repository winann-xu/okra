# M1 验收证据（root helper）

- 日期：2026-09-17
- 构建：`./scripts/build.sh`（SwiftPM，SDK MacOSX26.5）通过，构建含入口哨兵检查
- 验收脚本：`scripts/m1-acceptance.sh [live]`
  - 无参数 = 沙箱测试（file:// 离线源，确定性可复现，共 22 项）
  - `live` = 追加真实三源网络测试（共 6 项）
- 复现方式：`./scripts/build.sh && ./scripts/m1-acceptance.sh live`

## 结果总览（2026-09-17 实测，28/28 全绿）

沙箱（T1~T9，22 项）：全部 PASS
真实源（L1~L4，6 项）：全部 PASS

关键实测数据（2026-09-17 当日源内容）：
- hellogithub 主源：更新成功，38 条（9/17 上午基线 47 行，源内容日间波动正常）
- 备源 1（jsdelivr/ittuann）：84 条（去重后）
- 源切换 38 → 84 条（跨源 +121%）被正确接受（验证 D9：剧变阈值仅同源生效）

## 验收标准逐项对照（任务书 §9 M1）

| 验收项 | 对应测试 | 结果 |
|---|---|---|
| 手动触发更新 | T1a（update 子命令，退出码 0）、status 子命令 T1e | PASS |
| diff /etc/hosts 证明仅 Okra 区块变化 | T1b（区块外逐字节比对）、T2（diff 中区块外无任何 +/- 行） | PASS（沙箱 /etc/hosts 同构夹具，含 tab 分隔、IPv6 行、注释、他人区块） |
| 连续更新两次无重复条目 | T3（两次更新后文件逐字节一致）、T3b（域名唯一性） | PASS |
| 镜像源模拟故障保留旧配置且状态文件有 error | T4b/T5b（拒绝后逐字节未动）、T4c/T4d（update_ok=false + 原因人话化）、L2（全源失败） | PASS |
| 预置其他工具 hosts 区块（含他人后续修改）100% 保留 | T6（更新后他人改行 + 他人新增行，还原后与预期文件逐字节一致） | PASS |

## 任务书 §7 hosts 铁律逐项验证

1. 只管理 Okra 区块，区块外绝不动 → T1b/T2/T6/T7c/T8b
2. 首次写入前完整备份（带时间戳）→ T1c/T1d（备份与更新前文件逐字节一致；保留最近 10 份）
3. 区块化替换而非追加 → T3/T3b
4. 原子写（临时文件→校验→rename；失败放弃且原文件不动）→ 全部拒绝场景 T4b/T5b/T8b；macOS 27 moveItem 陷阱修复见下
5. 写前校验（可解析/空数据/行数剧变）→ T4a（同源 50→300 拒绝）、T5a（空镜像拒绝）、T8a（单侧标记损坏拒绝）

## 附加边界测试（超出 M1 最低要求）

- T7 文件无结尾换行：更新成功且结尾状态保持（修复了 commit() 重拆文本误删末行的 bug）
- T8 标记损坏（只有单侧标记）：update 拒绝执行、文件逐字节不动
- T9 状态文件 schema 完整（任务书 §7 八个字段恒存在，null 显式写入）
- install/uninstall 非 root 调用：干净报错"该操作需要 root 权限"（rc=1）。
  **完整 launchd 安装/卸载 E2E 需 root，归入 M4 首次安装流程端到端验证**（含真实 /etc/hosts 实战）。

## 验收过程中发现并修复的缺陷（全部已验证）

1. `main.swift` 仅有 `func main()` 声明（无顶层语句）时，Swift 6.2 生成**空入口桩**：进程静默退出 0、业务代码完全不执行——最隐蔽，构建"成功"、链接通过。改为顶层入口代码；build.sh 增加行为级入口哨兵（运行 `status` 并检查 stdout）。
2. 本机 macOS 27.0 上 `FileManager.moveItem()` 在目标文件已存在时报 EEXIST（516），而裸 `rename(2)` 系统调用可正常原子替换（已用独立小程序实测两者行为差异）。原子写改用 `rename(2)`。
3. `commit()` 对"文件无结尾换行"场景重拆文本会误删末行，导致写前校验必失败。改为直接以内存行数组为校验基准。
4. 50% 行数剧变阈值原为"与当前区块比"，三源条目数天然不同（38/84/40）会导致主源停摆后备源永远被拒、且切换后系统永久锁死在错误态。修正为仅同源连续更新才比对（决策 D9）。
5. `writeUpdate` 对 nil 字段直接赋 Swift 可选值，导致 `source`/`entries`/`update_error` 键从 JSON 消失。改为显式 NSNull，schema 恒定。
6. `rangeOfOkraBlock` 内 `trimmingCharacters` 漏写接收者（编译错误，上一会话代码从未通过编译）。
7. `fetch()` 支持 `file://` 源（仅配合 OKRA_SOURCES 测试覆盖使用），使验收可离线确定性复现。

## 结论

M1 验收通过（28/28）。helper 已具备 update/restore/install/uninstall/status 全部子命令；
install/uninstall 的 root E2E 与真实 /etc/hosts 实战随 M4 首次安装流程一并验证。