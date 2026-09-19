# 验收证据存档目录（M0~M4 各里程碑的命令输出/截图）

| 文件 | 里程碑 | 说明 |
|---|---|---|
| M0-acceptance.md | M0 | 双路径构建（build.sh / xcodebuild）、运行验证、git/GitHub 就绪记录 |
| M1-acceptance.md | M1 | scripts/m1-acceptance.sh 沙箱 22 项 + 真实源 6 项全绿；铁律逐项对照；缺陷修复记录 |
| M2-acceptance.md | M2 | 窗口级捕获 + Vision OCR 验证 UI 与 status.json 一致；定时探测与「更新后立即探测」实测 |
| M3-acceptance.md | M3 | 沙箱 17/17；登录项状态机实测；设置页 OCR 验收；真机 E2E 五步全绿 + hosts 逐字节实测 |
| M4-acceptance.md | M4 | 签名环境事实（0 证书 / notarytool 可用 / spctl 结果）；Release 打包流程实测；签名路线与全新账号 E2E 待办 |
