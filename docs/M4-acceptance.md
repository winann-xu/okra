# M4 验收记录（打包 / 签名 / 公证 / 首次安装流程）

## 范围（任务书 §9 M4）
① 发布打包流程（Release 构建 → .app 组装 → 签名 → 分发产物）
② 签名路线：Developer ID + 公证，或自用 ad-hoc + `xattr -d com.apple.quarantine`（任务书 §10）
③ 首次运行安装流程（授权对话框装 helper）端到端
④ 新 macOS 用户账号全流程走通

## 环境事实（2026-09-19 实测）
| 项 | 结果 |
|---|---|
| 有效签名身份 | `security find-identity -v -p codesigning` → **0 valid identities found**（无 Developer ID 证书） |
| 公证工具 | `xcrun -f notarytool` → `/Library/Developer/CommandLineTools/usr/bin/notarytool`（存在，但无证书无法签名/公证） |
| 当前构建签名 | ad-hoc（`Signature=adhoc`、`TeamIdentifier=not set`） |
| Gatekeeper 评估 | `spctl -a -vv Okra.app` → `rejected`（ad-hoc 的预期结果；本机构建无 quarantine 属性，可直接运行） |

**结论**：公证路线需用户先加入 Apple Developer Program 并生成 "Developer ID Application" 证书；在拿到证书之前，M4 只能走任务书 §10 的自用 ad-hoc 路线。

## 已完成的打包流程（本轮，路线无关）
`scripts/build.sh` 增加 `--release` 与 `OKRA_VERSION` / `OKRA_SIGN_IDENTITY` 支持：

- 构建配置可选（默认 debug；`--release` 用于发布），入口哨兵逻辑对两种配置都生效
- `Info.plist` 的 `CFBundleShortVersionString` 由 `OKRA_VERSION` 注入（不再硬编码）
- 签名二选一：设了 `OKRA_SIGN_IDENTITY` → Developer ID + hardened runtime + 时间戳（为后续公证准备）；未设 → ad-hoc
- 新增签名校验步骤（`codesign --verify --deep --strict`，输出 Identifier/Signature/TeamIdentifier）

`scripts/package.sh`（新增）：
- 调 `build.sh --release` → `ditto` 打包（保留签名密封与扩展属性）→ 产出 `dist/Okra-<版本>.zip` + `.sha256`

实测（2026-09-19，版本 0.1.0）：
```
Build complete! (29.32秒)
[3/5] ad-hoc 签名...            Okra.app: replacing existing signature
[4/5] 校验签名...               Okra.app: valid on disk
                                Okra.app: satisfies its Designated Requirement
                                Identifier=com.winann.okra  Signature=adhoc  TeamIdentifier=not set
[5/5] 完成   App: …/Okra.app (708K)，版本 0.1.0
打包完成：…/dist/Okra-0.1.0.zip （200K）
3ab39fdef70de319e135947d9753a7511ea046eb326fbd6ebd13aa933405ee45  dist/Okra-0.1.0.zip
```
（Release 包体 708K / zip 200K，远低于 FR6 的 10MB 上限）

## 发布包独立复核（2026-09-19，解压自 zip）
```
du -sh /tmp/okra-release-test/Okra.app            → 708K
xattr -l Okra.app                                  → com.apple.provenance（无 quarantine）
codesign --verify --deep --strict                  → valid on disk / satisfies its Designated Requirement
codesign -dv                                        → Identifier=com.winann.okra  Signature=adhoc  TeamIdentifier=not set
Info.plist                                          → CFBundleShortVersionString=0.1.0  LSMinimumSystemVersion=13.0
Contents/Resources/OkraHelper                       → 201512 字节（release 构建产物）
```
即：`ditto` 打包未破坏签名密封，本地构建产物无 quarantine 属性（双击即开）。

Release 构建 UI 冒烟（`OKRA_PREVIEW=1 OKRA_PREVIEW_SETTINGS=1 OKRA_UNREGISTER=1` + 窗口级截图 + Vision OCR）：设置页渲染正常——更新排程（两组周期）、定时服务「已安装：每 4 小时自动更新，开机运行」、登录项、镜像源、还原/卸载、关于；未出现 release 优化导致的渲染或崩溃问题。

## 决策与收口（2026-09-19，任务书 D13）
- **签名路线：自用 ad-hoc**。不做 Developer ID / 公证（本机 0 个有效签名身份；定位仅个人自用、不公开分发）。分发提示：发布包在别的 Mac 首次打开需 `xattr -d com.apple.quarantine Okra.app`。
- **新 macOS 用户账号验证：免做**（用户决定）。首次安装流程以 M3 真机实测（授权对话框装 helper → RunAtLoad 更新成功 → 状态文件/探测正常）与本节发布包冒烟等效覆盖。
- 交付物：`dist/Okra-0.1.0.zip`（200K）+ `dist/Okra-0.1.0.zip.sha256`（本地产物，按 .gitignore 不入库）。
