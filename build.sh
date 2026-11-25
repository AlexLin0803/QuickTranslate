#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="QuickTranslate"
BUNDLE_ID="com.local.quicktranslate"
APP_BUNDLE="${SCRIPT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ARCH="$(uname -m)"

echo "🔨 Building ${APP_NAME}.app (${ARCH})..."

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

MODULE_CACHE="/tmp/quicktranslate-module-cache"
mkdir -p "${MODULE_CACHE}"

CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" swiftc \
  -O \
  -swift-version 5 \
  -module-cache-path "${MODULE_CACHE}" \
  -target "${ARCH}-apple-macosx15.0" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Translation \
  -framework Vision \
  -framework NaturalLanguage \
  -framework AVFoundation \
  -framework Carbon \
  -framework CoreServices \
  -framework ApplicationServices \
  "${SCRIPT_DIR}/Sources/"*.swift \
  -o "${MACOS_DIR}/${APP_NAME}"

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>QuickTranslate uses screen capture only when you trigger Screenshot OCR (⌥S) to recognize and translate text inside images or UI.</string>
</dict>
</plist>
EOF

echo "🔏 Ad-hoc signing ${APP_NAME}.app..."
codesign --force --deep --sign - --identifier "${BUNDLE_ID}" "${APP_BUNDLE}"

echo "✅ Built successfully: ${APP_BUNDLE}"
