#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
APP="$PWD/build/PoteNad.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PoteNad "$APP/Contents/MacOS/PoteNad"
cp Assets/PoteNad.icns "$APP/Contents/Resources/PoteNad.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
