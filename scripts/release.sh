#!/usr/bin/env bash
# A Sparkle update in folder $1: Gzyms-<version>.zip, its notes from whatsnew/<version>.md, and appcast.xml.
# Upload the folder's contents to where SUFeedURL points. Signing reads the EdDSA key from the login Keychain
# (made once with .build/artifacts/sparkle/Sparkle/bin/generate_keys); macOS asks to allow that.
set -euo pipefail
cd "$(dirname "$0")/.."

out="$1"
mkdir -p "$out"
version=$(sed -nE 's/^let gzymsVersion = "(.*)"/\1/p' Sources/gzyms/Report.swift)
bash scripts/bundle.sh "$out/Gzyms.app"
ditto -c -k --sequesterRsrc --keepParent "$out/Gzyms.app" "$out/Gzyms-$version.zip"  # keeps the framework's symlinks
rm -rf "$out/Gzyms.app"
[ -f "whatsnew/$version.md" ] && cp "whatsnew/$version.md" "$out/Gzyms-$version.md"  # same name as the zip = its notes
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --embed-release-notes "$out"
ls -1 "$out"
