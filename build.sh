#!/usr/bin/env bash
# Builds RedmiBudsControl with SwiftPM and wraps it into a launchable .app bundle
# (no full Xcode required — Command Line Tools is enough).
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="RedmiBudsControl"
BUNDLE_ID="ua.local.redmibudscontrol"
VERSION="0.1.0"
BUILD="1"

echo "==> swift build (release)"
swift build -c release

BIN=".build/release/$APP_NAME"
APP_DIR="build/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$RESOURCES"
cp "$BIN" "$CONTENTS/MacOS/$APP_NAME"

# App icon
[ -f resources/AppIcon.icns ] && cp resources/AppIcon.icns "$RESOURCES/AppIcon.icns" || echo "warn: resources/AppIcon.icns missing (run: swift tools/make_icon.swift)"

# Auth oracle requires the Xiaomi native lib. Extract it from the official APK
# if missing (legal: the user supplies the APK they already have installed).
if [ ! -f resources/libxm_bluetooth.so ]; then
  echo "ERROR: resources/libxm_bluetooth.so missing."
  echo "  Get the official 'Xiaomi Earbuds' APK (com.mi.earphone) from APKPure/APKMirror,"
  echo "  then:  ./tools/reverse_auth.sh <xiaomi_earbuds.apk>   (it extracts the .so)"
  echo "  and copy it to resources/libxm_bluetooth.so"
  exit 1
fi

# Build & bundle the standalone auth oracle (Unicorn-emulated Xiaomi cipher).
# Build dep: libunicorn (vendored in Vendor/unicorn, or `brew install unicorn`).
if [ -f Vendor/unicorn/lib/libunicorn.a ]; then
  UNI_INC="Vendor/unicorn/include"; UNI_LIB="Vendor/unicorn/lib/libunicorn.a"
else
  UNI_INC="/opt/homebrew/include"; UNI_LIB="/opt/homebrew/lib/libunicorn.a"
fi
echo "==> building auth_helper (libunicorn: $UNI_LIB)"
clang -O2 -I "$UNI_INC" resources/auth_helper.c "$UNI_LIB" -lpthread -lm -o "$RESOURCES/auth_helper" \
  || { echo "ERROR: auth_helper build failed. Run: brew install unicorn"; exit 1; }
cp resources/libxm_bluetooth.so "$RESOURCES/libxm_bluetooth.so"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>Redmi Buds Control needs Bluetooth to connect to your earbuds and control ANC / EQ.</string>
  <key>NSBluetoothPeripheralUsageDescription</key>
  <string>Redmi Buds Control needs Bluetooth to connect to your earbuds.</string>
</dict>
</plist>
PLIST

# Strip any quarantine attribute so it opens without a warning on first launch.
xattr -cr "$APP_DIR" 2>/dev/null || true

echo ""
echo "==> Built: $APP_DIR"
echo "    Launch with:  open \"$APP_DIR\""
