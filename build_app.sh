#!/bin/bash
set -e

APP_NAME="GengarileoAssistant"
BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "🔨 Swift 컴파일 진행 중 (GengarileoAssistant)..."
swiftc -O -module-cache-path /tmp/swift-cache -parse-as-library "$BUILD_DIR/Sources/GengarileoAssistant/"*.swift -o "$BUILD_DIR/$APP_NAME"

echo "📦 .app 번들 구조 생성 중..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/public/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true

mv "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

cat << 'EOF' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>GengarileoAssistant</string>
    <key>CFBundleIdentifier</key>
    <string>com.declan.GengarileoAssistant</string>
    <key>CFBundleName</key>
    <string>GengarileoAssistant</string>
    <key>CFBundleDisplayName</key>
    <string>Gengarileo 개인비서</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCalendarsUsageDescription</key>
    <string>아이폰 16 프로 캘린더와 실적발표 및 청약 일정을 동기화하기 위해 권한이 필요합니다.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>아이폰 16 프로 캘린더와 실적발표 및 청약 일정을 동기화하기 위해 전체 접근 권한이 필요합니다.</string>
</dict>
</plist>
EOF

chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
echo "✅ 빌드 완료: $APP_BUNDLE"
