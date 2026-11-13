#!/bin/zsh
# Build Red Light.app and install it in /Applications.
set -e
cd "$(dirname "$0")"
APP="build/Red Light.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS"
swiftc -O -target arm64-apple-macos14 main.swift -o "$APP/Contents/MacOS/RedLight"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Red Light</string>
<key>CFBundleDisplayName</key><string>Red Light</string>
<key>CFBundleIdentifier</key><string>local.redlight</string>
<key>CFBundleExecutable</key><string>RedLight</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
if [[ "$1" == "--install" ]]; then
  pkill -x RedLight || true
  rm -rf "/Applications/Red Light.app"
  cp -R "$APP" /Applications/
  open "/Applications/Red Light.app"
  echo "Installed and opened /Applications/Red Light.app"
fi
