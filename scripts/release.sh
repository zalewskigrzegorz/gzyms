#!/usr/bin/env bash
# A Sparkle update in folder $1: Gzyms-<version>.zip (Developer ID, notarized, stapled), its notes from
# whatsnew/<version>.md, and appcast.xml. Upload the folder's contents to where SUFeedURL points.
# Signing reads the EdDSA key from the login Keychain (made once with .build/artifacts/sparkle/Sparkle/bin/generate_keys);
# macOS asks to allow that. Notarizing uses the notarytool profile GZYMS_NOTARY_PROFILE (default gzyms-notary),
# stored once with `xcrun notarytool store-credentials`. Order: sign, zip, notarize, staple, zip again for Sparkle.
set -euo pipefail
cd "$(dirname "$0")/.."

out="$1"
profile="${GZYMS_NOTARY_PROFILE:-gzyms-notary}"
mkdir -p "$out"
version=$(sed -nE 's/^let gzymsVersion = "(.*)"/\1/p' Sources/gzyms/Report.swift)
app="$out/Gzyms.app"
zip="$out/Gzyms-$version.zip"
bash scripts/bundle.sh "$app"

ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"  # keeps the framework's symlinks
id=$(xcrun notarytool submit "$zip" --keychain-profile "$profile" --output-format json | plutil -extract id raw -)
echo "notarization $id submitted, waiting (a new team's first ones can take hours)"
xcrun notarytool wait "$id" --keychain-profile "$profile" || true  # the status below decides
status=$(xcrun notarytool info "$id" --keychain-profile "$profile" --output-format json | plutil -extract status raw -)
if [ "$status" != "Accepted" ]; then
  echo "notarization $status ($id):"
  xcrun notarytool log "$id" --keychain-profile "$profile"
  exit 1
fi
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl -a -vv --type exec "$app"
rm "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"  # now with the ticket inside, for first launch offline
rm -rf "$app"

[ -f "whatsnew/$version.md" ] && cp "whatsnew/$version.md" "$out/Gzyms-$version.md"  # same name as the zip = its notes
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --embed-release-notes "$out"
ls -1 "$out"
