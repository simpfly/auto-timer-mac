#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="It's Time"
BIN_NAME="itstime"
BUNDLE_NAME="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_NAME}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🔨 正在编译 ${BIN_NAME}..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${BIN_NAME}"

echo "📦 正在打包 ${BUNDLE_NAME}..."
# 清理旧构建产物与同名包
rm -rf "${BUNDLE_NAME}" "AutoTimer.app"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 拷贝二进制
cp "${BIN_PATH}" "${MACOS_DIR}/${BIN_NAME}"
chmod +x "${MACOS_DIR}/${BIN_NAME}"

# 拷贝高清图标与内置资源
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

if [ -d "Resources" ]; then
    cp -R Resources/* "${RESOURCES_DIR}/"
fi

# 生成 Info.plist
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${BIN_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.curiosita.itstime</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSCalendarsUsageDescription</key>
    <string>It's Time 需要访问日历以同步并定时自动打开会议或播放日程提醒。</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>It's Time 需要访问日历以同步并定时自动打开会议或播放日程提醒。</string>
    <key>NSRemindersUsageDescription</key>
    <string>It's Time 需要访问提醒事项以导入待办并定时提醒。</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>It's Time 需要访问提醒事项以导入待办并定时提醒。</string>
</dict>
</plist>
EOF

echo "✅ 打包完成: ${SCRIPT_DIR}/${BUNDLE_NAME}"
echo "💡 可在终端执行: open \"${BUNDLE_NAME}\"，或直接双击运行！"
