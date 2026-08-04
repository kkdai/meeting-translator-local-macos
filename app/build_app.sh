#!/bin/bash
set -e

# Phase 1 build script: WhisperKit only, no MLX yet, so plain `swift build`
# is sufficient (MLX would require xcodebuild -- see
# docs/design/2026-08-04-roadmap.md's "換機器接續開發前必看" section for why).

APP_NAME="MeetingTranslatorLocal"
BUNDLE_ID="com.local.MeetingTranslatorLocal"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MAC_OS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

cd "$(dirname "$0")"

echo "🧹 清理舊的編譯檔案..."
rm -rf "$APP_DIR"

echo "🛠 建置中（swift build -c release）..."
swift build -c release

BIN_PATH=".build/release/${APP_NAME}"
if [ ! -f "$BIN_PATH" ]; then
  echo "❌ 找不到編譯產物：$BIN_PATH"
  exit 1
fi

echo "📂 建立 App 目錄結構..."
mkdir -p "$MAC_OS_DIR"
mkdir -p "$RESOURCES_DIR"
cp "$BIN_PATH" "${MAC_OS_DIR}/${APP_NAME}"

echo "📝 產生 Info.plist..."
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0-phase1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>MeetingTranslatorLocal 需要螢幕錄製權限，以便擷取會議應用程式的音訊進行本地端語音辨識。</string>
</dict>
</plist>
EOF

echo "🔏 進行 ad-hoc 簽名..."
codesign --sign - --force --deep --preserve-metadata=entitlements "${APP_DIR}"

echo "🔄 重置螢幕錄製權限（ad-hoc 簽名每次都會更換身分）..."
tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null && echo "   ✅ 已重置，開啟 App 後系統會重新詢問授權" || true

echo ""
echo "✅ 打包完成：${APP_DIR}"
echo "👉 執行以下指令開啟 App:"
echo "   open ${APP_DIR}"
