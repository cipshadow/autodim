#!/bin/bash
# Builds AutoDim.app without Xcode (Command Line Tools only).
# Usage: ./build.sh [debug|release]   (debug adds --simulate-time and logging)
# ./build.sh check   runs the schedule unit checks.
set -euo pipefail
cd "$(dirname "$0")"

SRC=DisplayFilter
if [[ "${1:-release}" == "check" ]]; then
  swiftc Checks/main.swift $SRC/Schedule.swift $SRC/ColorTemperature.swift -o build/checks 2>/dev/null || { mkdir -p build; swiftc Checks/main.swift $SRC/Schedule.swift $SRC/ColorTemperature.swift -o build/checks; }
  exec build/checks
fi

MODE="${1:-release}"
BUNDLE_ID="${BUNDLE_ID:-com.cipshadow.autodim}"
APP=build/AutoDim.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

FLAGS=(-parse-as-library -target arm64-apple-macosx15.0)
if [[ "$MODE" == "debug" ]]; then FLAGS+=(-DDEBUG -Onone); else FLAGS+=(-O); fi
swiftc "${FLAGS[@]}" $SRC/*.swift -o "$APP/Contents/MacOS/AutoDim"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>AutoDim</string>
	<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
	<key>CFBundleName</key><string>AutoDim</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.1</string>
	<key>CFBundleVersion</key><string>2</string>
	<key>LSMinimumSystemVersion</key><string>15.0</string>
	<key>LSUIElement</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - --options runtime --entitlements $SRC/DisplayFilter.entitlements "$APP"
echo "Built $APP ($MODE)"
