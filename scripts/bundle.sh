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
# Set by install-dev.sh only, so About tells a local build from a release.
dev=${GZYMS_DEV_BUILD:+"<key>GzymsDevBuild</key><string>$GZYMS_DEV_BUILD</string>"}

bash scripts/gen-skill.sh  # skill/*.md and whatsnew/*.md into the binary
swift build -c release
scripts/make-icon.sh
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp .build/release/gzyms "$app/Contents/MacOS/gzyms"
cp .build/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp -R assets/sounds "$app/Contents/Resources/"  # the Gzyms cat (ElevenLabs sound effects)
ditto .build/release/Sparkle.framework "$app/Contents/Frameworks/Sparkle.framework"  # ditto keeps the framework's symlinks
# The music reader: loaded into /usr/bin/perl, which may read MediaRemote (see tools/media-reader/reader.m).
clang -fobjc-arc -O2 -dynamiclib -framework Foundation -o "$app/Contents/Resources/media-reader.dylib" tools/media-reader/reader.m
# Its sender, the same way, and the userscript the loopback server hands to the browser (Settings → Hacks).
clang -fobjc-arc -O2 -dynamiclib -framework Foundation -o "$app/Contents/Resources/media-send.dylib" tools/media-send/send.m
cp assets/gzyms-media.user.js "$app/Contents/Resources/"
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
  $dev
  <key>LSUIElement</key><true/>
  <key>NSCameraUsageDescription</key><string>Gzyms shows your camera in the check before a meeting.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Gzyms reminds you of meetings that have a video link.</string>
  <key>NSAppleEventsUsageDescription</key><string>Your Gzyms plugins can control other apps.</string>
  <key>NSMicrophoneUsageDescription</key><string>Gzyms shows a live mic level in the microphone popup.</string>
  <key>SUFeedURL</key><string>$feed</string>
  <key>SUPublicEDKey</key><string>kJAN3IJiKfJDXN05aHu6YvjqCSgFaEEOIhnPt/28Qtw=</string>
  <key>SUEnableAutomaticChecks</key><true/>
</dict></plist>
EOF
# Inside out, no --deep (sparkle-project.org/documentation/sandboxing): Sparkle's helpers, the framework, then the app.
# One identity for dev and release keeps macOS grants across rebuilds, updates and dev <-> release.
# GZYMS_SIGN_ID="Gzyms Dev" (scripts/make-dev-cert.sh) on a Mac without the Developer ID; install-dev.sh skips the
# secure timestamp (GZYMS_TIMESTAMP=--timestamp=none) so it builds offline.
sign_id="${GZYMS_SIGN_ID:-Developer ID Application: Grzegorz Zalewski (AM4DX85G8P)}"
sign=(codesign --force --options runtime "${GZYMS_TIMESTAMP:---timestamp}" --sign "$sign_id")
fw="$app/Contents/Frameworks/Sparkle.framework"
"${sign[@]}" "$fw/Versions/B/Autoupdate"
"${sign[@]}" "$fw/Versions/B/Updater.app"
"${sign[@]}" "$fw"
"${sign[@]}" "$app/Contents/Resources/media-reader.dylib" "$app/Contents/Resources/media-send.dylib"
"${sign[@]}" --identifier "$label" --entitlements scripts/Gzyms.entitlements "$app"
codesign --verify --deep --strict "$app"
echo "bundled Gzyms $version at $app (feed $feed)"
