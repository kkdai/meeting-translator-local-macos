#!/bin/bash
set -e

# Phase 2+: depends on MLX (translation), which needs its Metal shaders compiled
# and bundled by Xcode's build system -- `swift build` alone links fine but fails
# at runtime with "Failed to load the default metallib" (see
# docs/design/2026-08-05-phase0-spike-results-translation.md's "環境發現"
# section for why). So this packages via `xcodebuild` against the bare
# Package.swift instead of `swiftc`/`swift build` directly.

APP_NAME="MeetingTranslatorLocal"
BUNDLE_ID="com.local.MeetingTranslatorLocal"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MAC_OS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
DERIVED_DATA_DIR=".build/xcode"

cd "$(dirname "$0")"

echo "🧹 清理舊的編譯檔案..."
rm -rf "$APP_DIR"

echo "🛠 建置中（xcodebuild -scheme ${APP_NAME} -configuration Release）..."
xcodebuild -scheme "$APP_NAME" \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -skipMacroValidation \
  build

BIN_PATH="${DERIVED_DATA_DIR}/Build/Products/Release/${APP_NAME}"
BUNDLE_PATH="${DERIVED_DATA_DIR}/Build/Products/Release/mlx-swift_Cmlx.bundle"

if [ ! -f "$BIN_PATH" ]; then
  echo "❌ 找不到編譯產物：$BIN_PATH"
  exit 1
fi

echo "📂 建立 App 目錄結構..."
mkdir -p "$MAC_OS_DIR"
mkdir -p "$RESOURCES_DIR"
cp "$BIN_PATH" "${MAC_OS_DIR}/${APP_NAME}"

if [ -d "$BUNDLE_PATH" ]; then
  echo "📦 複製 MLX Metal shader bundle..."
  # MLX looks for its resource bundle relative to the running executable when
  # that's a bare binary (works for spike CLIs sitting next to the bundle),
  # but inside a proper .app it resolves resources via Bundle.main, which
  # means Contents/Resources/ -- copying only into Contents/MacOS/ (matching
  # the spike CLI layout) builds and launches fine but crashes on first MLX
  # call with "Failed to load the default metallib". Copy to both so it's
  # found regardless of which lookup path fires.
  cp -R "$BUNDLE_PATH" "${MAC_OS_DIR}/"
  cp -R "$BUNDLE_PATH" "${RESOURCES_DIR}/"
fi

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
    <string>0.2.0-phase2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>MeetingTranslatorLocal 需要螢幕錄製權限，以便擷取會議應用程式的音訊進行本地端語音辨識與翻譯。</string>
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
