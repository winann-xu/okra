#!/bin/bash
# M4 发布打包：Release 构建 → 组装/签名 .app → dist/Okra-<版本>.zip + SHA-256
# 用法：scripts/package.sh [版本号]（默认 0.1.0）
#   OKRA_SIGN_IDENTITY="Developer ID Application: … (TEAMID)" 时用证书签名（可公证）；
#   默认 ad-hoc（自用路线，任务书 §10：接收方首次需 xattr -d com.apple.quarantine）。
set -e
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
OKRA_VERSION="$VERSION" ./scripts/build.sh --release

DIST=dist
rm -rf "$DIST"
mkdir -p "$DIST"
ZIP="$DIST/Okra-$VERSION.zip"
# ditto 保留签名与扩展属性（zip 命令会破坏 .app 的签名密封）
ditto -c -k --sequesterRsrc --keepParent Okra.app "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"

echo
echo "打包完成：$(pwd)/$ZIP （$(du -sh "$ZIP" | cut -f1)）"
if [ -n "${OKRA_SIGN_IDENTITY:-}" ]; then
    echo "签名：$OKRA_SIGN_IDENTITY（hardened runtime + 时间戳；公证可继续 notarytool submit）"
else
    echo "签名：ad-hoc（自用）。在别的 Mac 上首次打开需：xattr -d com.apple.quarantine Okra.app"
fi
