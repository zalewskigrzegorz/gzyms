#!/usr/bin/env bash
# Build release and put it together as a signed Gzyms.app at $1. Used by install-dev.sh and release.sh.
# GZYMS_FEED_URL replaces the appcast address (a local test feed); the version comes from gzymsVersion in Report.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

app="$1"
[[ "$app" == *.app ]] || { echo "usage: $0 <path>/Gzyms.app"; exit 1; }  # it is replaced whole
label="dev.gzyms"
feed="${GZYMS_FEED_URL:-https://gzyms.dev/appcast.xml}"
version=$(sed -nE 's/^let gzymsVersion = "(.*)"/\1/p' Sources/gzyms/Report.swift)
[ -n "$version" ] || { echo "no gzymsVersion in Sources/gzyms/Report.swift"; exit 1; }

bash scripts/gen-skill.sh  # skill/*.md and whatsnew/*.md into the binary
swift build -c release
scripts/make-icon.sh
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp .build/release/gzyms "$app/Contents/MacOS/gzyms"
cp .build/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp -R assets/sounds "$app/Contents/Resources/"  # the Gzyms cat (ElevenLabs sound effects)
ditto .build/release/Sparkle.framework "$app/Contents/Frameworks/Sparkle.framework"  # ditto keeps the framework's symlinks
# Gzyms is not sandboxed, so Sparkle's XPC services are not needed (sparkle-project.org/documentation/sandboxing).
rm -rf "$app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$app/Contents/Frameworks/Sparkle.framework/XPCServices"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$label</string>
  <key>CFBundleName</key><string>Gzyms</string>
  <key>CFBundleExecutable</key><string>gzyms</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSUIElement</key><true/>
  <key>NSCameraUsageDescription</key><string>Gzyms shows your camera in the check before a meeting.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Gzyms reminds you of meetings that have a video link.</string>
  <key>NSMicrophoneUsageDescription</key><string>Gzyms shows a live mic level in the microphone popup.</string>
  <key>SUFeedURL</key><string>$feed</string>
  <key>SUPublicEDKey</key><string>kJAN3IJiKfJDXN05aHu6YvjqCSgFaEEOIhnPt/28Qtw=</string>
  <key>SUEnableAutomaticChecks</key><true/>
</dict></plist>
EOF
# Inside out: Sparkle's helpers, the framework, then the app. A stable identity keeps macOS grants across updates.
fw="$app/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "Gzyms Dev" "$fw/Versions/B/Autoupdate"
codesign --force --sign "Gzyms Dev" "$fw/Versions/B/Updater.app"
codesign --force --sign "Gzyms Dev" "$fw"
codesign --force --sign "Gzyms Dev" --identifier "$label" "$app"
codesign --verify --deep --strict "$app"
echo "bundled Gzyms $version at $app (feed $feed)"
