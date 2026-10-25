#!/bin/bash
# Builds AutoDim.app without Xcode (Command Line Tools only).
# Usage: ./build.sh [debug|release]   (debug adds --simulate-time and logging)
# ./build.sh check   runs the schedule unit checks.
# ./build.sh package creates a universal DMG and verifies it after mounting.
set -euo pipefail
cd "$(dirname "$0")"

SRC=DisplayFilter
MINIMUM_MACOS=13.0
ARCHS=(arm64 x86_64)
LINK_FLAGS=(-Xlinker -F -Xlinker /System/Library/PrivateFrameworks -Xlinker -weak_framework -Xlinker CoreDisplay -Xlinker -weak_framework -Xlinker DisplayServices)
if [[ "${1:-release}" == "check" ]]; then
  mkdir -p build
  HOST_ARCH="$(uname -m)"
  clang -target "$HOST_ARCH-apple-macosx$MINIMUM_MACOS" -c "$SRC/HardwareBrightnessShim.c" -o build/hardware-brightness-shim-checks.o
  swiftc -target "$HOST_ARCH-apple-macosx$MINIMUM_MACOS" Checks/main.swift Checks/HardwareBrightnessChecks.swift $SRC/Schedule.swift $SRC/ColorTemperature.swift $SRC/DisplayIdentity.swift $SRC/HardwareBrightness.swift build/hardware-brightness-shim-checks.o "${LINK_FLAGS[@]}" -o build/checks
  exec build/checks
fi

MODE="${1:-release}"
PACKAGE=0
if [[ "$MODE" == "package" ]]; then
  MODE=release
  PACKAGE=1
fi
BUNDLE_ID="${BUNDLE_ID:-com.cipshadow.autodim}"
APP=build/AutoDim.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

FLAGS=(-parse-as-library)
if [[ "$MODE" == "debug" ]]; then FLAGS+=(-DDEBUG -Onone); else FLAGS+=(-O); fi
for ARCH in "${ARCHS[@]}"; do
  clang -target "$ARCH-apple-macosx$MINIMUM_MACOS" -c "$SRC/HardwareBrightnessShim.c" -o "build/hardware-brightness-shim-$ARCH.o"
  swiftc "${FLAGS[@]}" -target "$ARCH-apple-macosx$MINIMUM_MACOS" $SRC/*.swift "build/hardware-brightness-shim-$ARCH.o" "${LINK_FLAGS[@]}" -o "$APP/Contents/MacOS/AutoDim-$ARCH"
done
lipo -create "$APP/Contents/MacOS/AutoDim-arm64" "$APP/Contents/MacOS/AutoDim-x86_64" -output "$APP/Contents/MacOS/AutoDim"
rm -f "$APP/Contents/MacOS/AutoDim-arm64" "$APP/Contents/MacOS/AutoDim-x86_64"
lipo -verify_arch arm64 "$APP/Contents/MacOS/AutoDim"
lipo -verify_arch x86_64 "$APP/Contents/MacOS/AutoDim"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>AutoDim</string>
	<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
	<key>CFBundleName</key><string>AutoDim</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>$MINIMUM_MACOS</string>
	<key>LSUIElement</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - --options runtime --entitlements $SRC/DisplayFilter.entitlements "$APP"
codesign --verify --deep --strict "$APP"

if [[ "$PACKAGE" == 1 ]]; then
  VERSION="${VERSION:-1.0.0}"
  # GitHub pull-request refs contain a slash (for example, "8/merge").
  # Release artifact filenames must remain flat.
  VERSION="${VERSION//\//-}"
  ARCHIVE="build/AutoDim-$VERSION.dmg"
  VERIFY_ROOT="$(mktemp -d)"
  STAGE_ROOT="$(mktemp -d)"

  rm -f "$ARCHIVE" "$ARCHIVE.sha256"
  cp -R "$APP" "$STAGE_ROOT/AutoDim.app"
  ln -s /Applications "$STAGE_ROOT/Applications"
  hdiutil create -volname "AutoDim" -srcfolder "$STAGE_ROOT" -ov -format UDZO "$ARCHIVE" >/dev/null
  hdiutil verify "$ARCHIVE" >/dev/null
  MOUNT_POINT="$(hdiutil attach -readonly -nobrowse -mountpoint "$VERIFY_ROOT" "$ARCHIVE" | tail -1 | awk '{print $NF}')"
  codesign --verify --deep --strict "$MOUNT_POINT/AutoDim.app"
  lipo -verify_arch arm64 "$MOUNT_POINT/AutoDim.app/Contents/MacOS/AutoDim"
  lipo -verify_arch x86_64 "$MOUNT_POINT/AutoDim.app/Contents/MacOS/AutoDim"
  hdiutil detach "$MOUNT_POINT" >/dev/null
  (
    cd build
    shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256"
  )
  echo "Built and verified $ARCHIVE"
  exit 0
fi

echo "Built $APP ($MODE)"
