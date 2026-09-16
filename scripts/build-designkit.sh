#!/bin/sh
# Builds the DEBUG Design Kit and wraps it as DesignKit.app so it launches like an app
# (menu bar, Dock icon, Window → Design Kit). Until Prompt 2's Xcode project exists,
# this is how Ryan runs the demo.
#
#   scripts/build-designkit.sh          → .build/DesignKit.app
#   open .build/DesignKit.app
set -eu
cd "$(dirname "$0")/.."
swift build --product DesignKit -c debug >/dev/null
BIN="$(swift build --product DesignKit -c debug --show-bin-path)/DesignKit"
APP=".build/DesignKit.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DesignKit"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>NetRelish Design Kit</string>
  <key>CFBundleDisplayName</key><string>NetRelish Design Kit</string>
  <key>CFBundleIdentifier</key><string>com.shepdesign.netrelish.designkit</string>
  <key>CFBundleExecutable</key><string>DesignKit</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
echo "built $APP"
