#!/bin/bash
# Builds build.noindex/HealthyMac.app (release). Optional: SIGN_IDENTITY="Apple Development: ..." ./scripts/build-app.sh
# Using a real signing identity keeps macOS privacy permissions (Full Disk Access) across rebuilds;
# ad-hoc signing ("-") resets them every build.
set -euo pipefail
# Output goes to build.noindex/: the ".noindex" suffix stops Spotlight from listing a
# second HealthyMac.app next to the installed one in /Applications.
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/HealthyMac"
APP="build.noindex/HealthyMac.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HealthyMac"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
echo "Install: cp -R \"$APP\" /Applications/"
