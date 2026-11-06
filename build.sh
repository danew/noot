#!/bin/sh
# Builds noot.app into ./build. Pass --install to copy it to /Applications.
set -e
cd "$(dirname "$0")"

APP=build/noot.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 Sources/main.swift -o "$APP/Contents/MacOS/noot"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>noot</string>
  <key>CFBundleIdentifier</key><string>com.danew.noot</string>
  <key>CFBundleName</key><string>noot</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"

if [ "$1" = "--install" ]; then
  rm -rf /Applications/noot.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/noot.app"
fi
