#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

SIGN_IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application:/ { print $2; exit }')}"
if [ -z "$SIGN_IDENTITY" ]; then
    echo "No Developer ID Application certificate found." >&2
    exit 1
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-KimiUsageBar}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG_PATH="build/KimiUsageBar-$VERSION.dmg"

CODESIGN_IDENTITY="$SIGN_IDENTITY" bash build.sh
codesign --verify --deep --strict --verbose=2 build/KimiUsageBar.app

rm -rf build/dmg "$DMG_PATH"
mkdir -p build/dmg
ditto build/KimiUsageBar.app build/dmg/KimiUsageBar.app
ln -s /Applications build/dmg/Applications
hdiutil create -volname KimiUsageBar -srcfolder build/dmg -ov -format UDZO "$DMG_PATH"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"

xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl -a -t open --context context:primary-signature -v "$DMG_PATH"

echo "Released artifact: $DMG_PATH"
