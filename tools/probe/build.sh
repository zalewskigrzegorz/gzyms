#!/usr/bin/env bash
# Gzyms Probe: a real app (own bundle id, in the Dock) that sends macOS notifications and sets its Dock badge,
# so every notification path of Gzyms can be tested on demand. A test tool, never part of Gzyms itself.
set -euo pipefail
cd "$(dirname "$0")"

app="$HOME/Applications/Gzyms Probe.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -O -parse-as-library -o "$app/Contents/MacOS/probe" Probe.swift
# The Media tab: the bar's MediaRemote reader, a one-shot command sender (both loaded into /usr/bin/perl) and the userscript it serves.
clang -fobjc-arc -O2 -dynamiclib -framework Foundation -o "$app/Contents/Resources/media-reader.dylib" ../media-reader/reader.m
clang -fobjc-arc -O2 -dynamiclib -framework Foundation -o "$app/Contents/Resources/media-send.dylib" ../media-send/send.m
cp ../../assets/gzyms-media.user.js "$app/Contents/Resources/"
codesign --force --sign "Gzyms Dev" "$app/Contents/Resources/media-reader.dylib" "$app/Contents/Resources/media-send.dylib"
# ProbeIcon.svg → ProbeIcon.icns, the same way scripts/make-icon.sh builds Gzyms' icon.
set_dir=$(mktemp -d)/ProbeIcon.iconset && mkdir -p "$set_dir"
for s in 16 32 128 256 512; do
  sips -s format png ProbeIcon.svg -z "$s" "$s" --out "$set_dir/icon_${s}x${s}.png" >/dev/null
  sips -s format png ProbeIcon.svg -z $((s * 2)) $((s * 2)) --out "$set_dir/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o "$app/Contents/Resources/ProbeIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.gzyms.probe</string>
  <key>CFBundleName</key><string>Gzyms Probe</string>
  <key>CFBundleExecutable</key><string>probe</string>
  <key>CFBundleIconFile</key><string>ProbeIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
</dict></plist>
PLIST
codesign --force --sign "Gzyms Dev" --identifier dev.gzyms.probe "$app"
echo "built $app"
