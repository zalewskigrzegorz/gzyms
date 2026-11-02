#!/usr/bin/env bash
# Build release, put it in ~/Applications/Gzyms.app signed like a release (see bundle.sh), run it at login via launchd.
set -euo pipefail
cd "$(dirname "$0")/.."

app="$HOME/Applications/Gzyms.app"
label="dev.gzyms"
plist="$HOME/Library/LaunchAgents/$label.plist"
logs="$HOME/Library/Logs/Gzyms"

mkdir -p "$logs"
GZYMS_TIMESTAMP=--timestamp=none bash scripts/bundle.sh "$app"

cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$app/Contents/MacOS/gzyms</string></array>
  <key>EnvironmentVariables</key><dict><key>GZYMS_LAUNCHD</key><string>1</string></dict>  <!-- without it gzyms hands over to this job -->
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
