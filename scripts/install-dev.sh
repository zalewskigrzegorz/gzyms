#!/usr/bin/env bash
# Build release, put it in ~/Applications/Gzyms.app signed as "Gzyms Dev", run it at login via launchd.
# Needs scripts/make-dev-cert.sh once per Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

app="$HOME/Applications/Gzyms.app"
label="dev.gzyms"
plist="$HOME/Library/LaunchAgents/$label.plist"
logs="$HOME/Library/Logs/Gzyms"

bash scripts/gen-skill.sh  # skill/*.md into the binary
swift build -c release
scripts/make-icon.sh
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$logs"
cp .build/release/gzyms "$app/Contents/MacOS/gzyms"
cp .build/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp -R assets/sounds "$app/Contents/Resources/"  # the Gzyms cat (ElevenLabs sound effects)
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$label</string>
  <key>CFBundleName</key><string>Gzyms</string>
  <key>CFBundleExecutable</key><string>gzyms</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>LSUIElement</key><true/>
  <key>NSCameraUsageDescription</key><string>Gzyms shows your camera in the check before a meeting.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Gzyms reminds you of meetings that have a video link.</string>
  <key>NSMicrophoneUsageDescription</key><string>Gzyms shows a live mic level in the microphone popup.</string>
</dict></plist>
EOF
codesign --force --sign "Gzyms Dev" --identifier "$label" "$app"

cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$app/Contents/MacOS/gzyms</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>  <!-- back after a crash, not after Quit -->
  <key>StandardErrorPath</key><string>$logs/gzyms.log</string>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
EOF

launchctl bootout "gui/$UID/$label" 2>/dev/null || true
# bootout returns before launchd has let go; bootstrapping too early fails with "5: Input/output error".
for _ in $(seq 1 50); do launchctl print "gui/$UID/$label" >/dev/null 2>&1 || break; sleep 0.1; done
launchctl bootstrap "gui/$UID" "$plist"
sleep 1
launchctl print "gui/$UID/$label" | grep -E '^\s*state = '

# `gzyms hud` and other commands from any terminal.
mkdir -p "$HOME/.local/bin"
ln -sf "$app/Contents/MacOS/gzyms" "$HOME/.local/bin/gzyms"
