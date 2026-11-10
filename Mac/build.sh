#!/bin/bash
# iPhone Fare (Mac): builds, bundles and signs the receiver app → Mac/build/iPhone Fare.app
# Uses the shared packet format from ../iOS/Fare/FareProtokol.swift. Needs Xcode command line tools (swiftc).
# Signed with your "Apple Development" certificate if there is one, so the Accessibility permission survives rebuilds
# (with an ad-hoc signature macOS forgets it after every build).
set -euo pipefail
cd "$(dirname "$0")"
[ -f ../Config/local.env ] && source ../Config/local.env
BUNDLE_ID="${IPHONEFARE_MAC_BUNDLE_ID:-com.example.iphonefare.mac}"
APP="build/iPhone Fare.app"
rm -rf build; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -o "$APP/Contents/MacOS/iPhoneFare" main.swift ../iOS/Fare/FareProtokol.swift \
  -framework SwiftUI -framework Network -framework ApplicationServices
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>iPhone Fare</string>
  <key>CFBundleDisplayName</key><string>iPhone Fare</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>iPhoneFare</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>iPhone Fare uygulamasından fare hareketlerini almak için.</string>
  <key>NSBonjourServices</key><array><string>_iphonefare._udp</string></array>
</dict></plist>
PL
KIMLIK=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
if [ -n "$KIMLIK" ]; then codesign --force -s "$KIMLIK" "$APP" >/dev/null 2>&1; else codesign --force -s - "$APP" >/dev/null 2>&1; fi
echo "Built: Mac/$APP  (drag it to Applications and open it)"
