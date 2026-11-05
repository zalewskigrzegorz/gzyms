#!/usr/bin/env bash
# A Sparkle update in folder $1: Gzyms-<version>.zip (Developer ID, notarized, stapled), its notes from
# whatsnew/<version>.md, and appcast.xml. Ends by bumping the Homebrew cask (a local commit, no push) and printing
# the steps it does not do: the GitHub release, the appcast to the site, the tap push.
# Signing reads the EdDSA key from the login Keychain (made once with .build/artifacts/sparkle/Sparkle/bin/generate_keys);
# macOS asks to allow that. Notarizing uses the notarytool profile GZYMS_NOTARY_PROFILE (default gzyms-notary),
# stored once with `xcrun notarytool store-credentials`. Order: sign, zip, notarize, staple, zip again for Sparkle.
set -euo pipefail
cd "$(dirname "$0")/.."

out="${1:?usage: release.sh <empty out folder>}"  # old zips left in it would land in the appcast
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
# The zip goes to GitHub Releases (the Homebrew tap's url too), the appcast to gzyms.dev.
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --embed-release-notes \
  --download-url-prefix "https://github.com/zalewskigrzegorz/gzyms/releases/download/v$version/" "$out"
ls -1 "$out"

# Homebrew installs update only through `brew upgrade`, so every release bumps the cask. Local commit, never a push.
tap="${GZYMS_TAP:-$HOME/Code/personal/homebrew-tap}"
sha=$(shasum -a 256 "$zip" | cut -d' ' -f1)
if [ -f "$tap/Casks/gzyms.rb" ]; then
  sed -i '' -E -e "s/^( *version )\".*\"/\1\"$version\"/" -e "s/^( *sha256 )\".*\"/\1\"$sha\"/" \
    -e '/^ *# Placeholder until/d' "$tap/Casks/gzyms.rb"
  if git -C "$tap" diff --quiet -- Casks/gzyms.rb; then
    echo "cask already at $version"
  else
    git -C "$tap" commit -q -m "chore(gzyms): bump cask to $version 🔖" -- Casks/gzyms.rb
    echo "cask bumped to $version ($sha), committed in $tap"
  fi
else
  echo "no cask at $tap/Casks/gzyms.rb, sha256 $sha"
fi

notes="--notes-file $out/Gzyms-$version.md"
[ -f "$out/Gzyms-$version.md" ] || notes="--generate-notes"
cat <<EOF
Not done here (nothing left this machine):
  1. gh release create v$version "$zip" --repo zalewskigrzegorz/gzyms $notes
  2. cp "$out/appcast.xml" ~/Code/personal/gzyms-site/site/, then deploy gzyms.dev (wrangler deploy)
  3. git -C $tap push
EOF
