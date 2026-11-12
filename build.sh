#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
swift build -c release --arch arm64 --arch x86_64

APP_PATH="build/KimiUsageBar.app"
rm -rf "$APP_PATH" build/icon
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" build/icon
xcrun actool Resources/AppIcon.icon \
    --app-icon AppIcon \
    --compile build/icon \
    --output-partial-info-plist build/icon/icon-info.plist \
    --minimum-deployment-target 13.0 \
    --platform macosx \
    --target-device mac
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
cp build/icon/AppIcon.icns build/icon/Assets.car "$APP_PATH/Contents/Resources/"
cp "$BIN_DIR/KimiUsageBar" "$APP_PATH/Contents/MacOS/KimiUsageBar"
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"
chmod 755 "$APP_PATH/Contents/MacOS/KimiUsageBar"
codesign --force --sign - "$APP_PATH"

echo "Built $APP_PATH"
