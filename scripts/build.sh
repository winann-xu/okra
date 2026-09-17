#!/bin/bash
set -e
echo "=== Okra 构建脚本（无需 Xcode：SwiftPM + 手动 .app 打包）==="

cd "$(dirname "$0")/.."

# 注意：本机 CLT 6.4 默认使用 MacOSX27.0 SDK，其中新引入的
# -target-arch-variant 参数会导致 SwiftUI 宏（@State 等）编译失败，
# 指定 MacOSX26.5 SDK 可正常构建（与 02-G_if/GPUMonitor 项目相同做法）。
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
[ -d "$SDK" ] || SDK=MacOSX

echo "[1/4] 编译（swift build）..."
SDKROOT="$SDK" swift build 2>&1

# 入口哨兵：main.swift 无顶层语句时会静默生成空入口（exit 0 但不执行业务代码）。
# 实际运行并检查 stdout（字符串字面量在 Mach-O 里是 UTF-16，strings 不可靠，行为检查才可靠）。
_sentinel_dir="$(mktemp -d)"
out="$(OKRA_SUPPORT_DIR="$_sentinel_dir/okra" ./.build/debug/OkraHelper status 2>&1)"
echo "$out" | grep -q "尚无状态数据\|最近更新" || {
    echo "错误：OkraHelper 入口未生效（status 无预期输出：$out）"; exit 1; }
rm -rf "$_sentinel_dir"

APP="Okra.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "[2/4] 组装 $APP ..."
cat > "$APP/Contents/Info.plist" << 'PLIST'
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
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

cp .build/debug/Okra "$APP/Contents/MacOS/"
chmod +x "$APP/Contents/MacOS/Okra"
# helper 随 App 分发（安装时由 App 复制到系统目录，M1/M4 实现）
cp .build/debug/OkraHelper "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "[3/4] ad-hoc 签名..."
codesign --force --deep -s - "$APP" 2>&1 || echo "Warning: ad-hoc 签名失败（不影响本地直接运行）"

echo "[4/4] 完成"
echo "   App:    $(pwd)/$APP ($(du -sh "$APP" | cut -f1))"
echo "   Helper: $APP/Contents/Resources/OkraHelper"