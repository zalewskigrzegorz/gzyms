#!/usr/bin/env bash
# assets/AppIcon.svg → .build/AppIcon.icns (sips renders the SVG at every size, iconutil packs them).
set -euo pipefail
cd "$(dirname "$0")/.."

out=.build/AppIcon.icns
[ -f "$out" ] && [ "$out" -nt assets/AppIcon.svg ] && exit 0
set=.build/AppIcon.iconset
rm -rf "$set" && mkdir -p "$set"
for s in 16 32 128 256 512; do
  sips -s format png assets/AppIcon.svg -z "$s" "$s" --out "$set/icon_${s}x${s}.png" >/dev/null
  sips -s format png assets/AppIcon.svg -z $((s * 2)) $((s * 2)) --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o "$out"
