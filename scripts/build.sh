#!/bin/bash
set -e
echo "=== Okra 构建脚本（无需 Xcode：SwiftPM + 手动 .app 打包）==="

cd "$(dirname "$0")/.."

# 构建配置：默认 debug（本地开发/验收）；--release 用于发布（M4）
CONFIG=debug
[ "${1:-}" = "--release" ] && CONFIG=release
BUILD_DIR=".build/$CONFIG"
VERSION="${OKRA_VERSION:-0.1.0}"

# 注意：本机 CLT 6.4 默认使用 MacOSX27.0 SDK，其中新引入的
# -target-arch-variant 参数会导致 SwiftUI 宏（@State 等）编译失败，
# 指定 MacOSX26.5 SDK 可正常构建（与 02-G_if/GPUMonitor 项目相同做法）。
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
[ -d "$SDK" ] || SDK=MacOSX

echo "[1/5] 编译（swift build -c $CONFIG）..."
SDKROOT="$SDK" swift build -c "$CONFIG" 2>&1

# 入口哨兵：main.swift 无顶层语句时会静默生成空入口（exit 0 但不执行业务代码）。
# 实际运行并检查 stdout（字符串字面量在 Mach-O 里是 UTF-16，strings 不可靠，行为检查才可靠）。
_sentinel_dir="$(mktemp -d)"
out="$(OKRA_SUPPORT_DIR="$_sentinel_dir/okra" "$BUILD_DIR/OkraHelper" status 2>&1)"
echo "$out" | grep -q "尚无状态数据\|最近更新" || {
    echo "错误：OkraHelper 入口未生效（status 无预期输出：$out）"; exit 1; }
rm -rf "$_sentinel_dir"

APP="Okra.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "[2/5] 组装 $APP （版本 $VERSION）..."
cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleExecutable</key><string>Okra</string>
    <key>CFBundleIdentifier</key><string>com.winann.okra</string>
    <key>CFBundleName</key><string>Okra</string>
    <key>CFBundleDisplayName</key><string>秋葵</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

cp "$BUILD_DIR/Okra" "$APP/Contents/MacOS/"
chmod +x "$APP/Contents/MacOS/Okra"
# helper 随 App 分发（安装时由 App 复制到系统目录）
cp "$BUILD_DIR/OkraHelper" "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# 签名：设了 OKRA_SIGN_IDENTITY 用 Developer ID（hardened runtime + 时间戳，可公证）；
# 否则 ad-hoc（自用路线，任务书 §10）。
if [ -n "${OKRA_SIGN_IDENTITY:-}" ]; then
    echo "[3/5] 签名（$OKRA_SIGN_IDENTITY，hardened runtime + 时间戳）..."
    codesign --force --deep --options runtime --timestamp -s "$OKRA_SIGN_IDENTITY" "$APP"
else
    echo "[3/5] ad-hoc 签名..."
    codesign --force --deep -s - "$APP" 2>&1 || echo "Warning: ad-hoc 签名失败（不影响本地直接运行）"
fi

echo "[4/5] 校验签名..."
codesign --verify --deep --strict --verbose=1 "$APP" 2>&1 | tail -2
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "^(Identifier|Signature|TeamIdentifier)=" || true

echo "[5/5] 完成"
echo "   App:    $(pwd)/$APP ($(du -sh "$APP" | cut -f1))，版本 $VERSION"
echo "   Helper: $APP/Contents/Resources/OkraHelper"
