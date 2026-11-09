#!/usr/bin/env bash
# Runs the log checks in checks/ against the running Gzyms: tools/probe/check.sh [name…], every check when none.
# Run it after each macOS update, patches too. Build Probe first with tools/probe/build.sh.
# Probe starts through `open` so it is its own app to macOS: its Accessibility grant, not the terminal's.
set -euo pipefail
dir="$(cd "$(dirname "$0")" && pwd)/checks"
files=()
if (($#)); then for n in "$@"; do files+=("$dir/$n.check"); done; else files=("$dir"/*.check); fi
out=$(mktemp)
trap 'rm -f "$out"' EXIT
# -g: in the background. macOS shows no banner for the app in front, so a frontmost Probe reads as a stuck NC.
open -g -n -W --stdout "$out" --stderr "$out" -a "$HOME/Applications/Gzyms Probe.app" --args check "${files[@]}"
cat "$out"
! grep -q '✗' "$out"
