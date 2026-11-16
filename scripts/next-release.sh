#!/usr/bin/env bash
# What goes into the next version: the pull requests labelled next-release (anyone can see the list on GitHub).
# Prints them and the version they make: release.feature.fix, one feat bumps the middle number, fixes alone the last.
# The first number stays Greg's call: pass it as $2 to override.
#   scripts/next-release.sh            the list and the version
#   scripts/next-release.sh --draft    also writes whatsnew/<version>.md from the titles, to rewrite by hand
#   scripts/next-release.sh --done     after a release: takes the label off the merged ones
set -euo pipefail
cd "$(dirname "$0")/.."

repo=zalewskigrzegorz/gzyms label=next-release
mode="${1:-}"
cur=$(sed -nE 's/^let gzymsVersion = "(.*)"/\1/p' Sources/gzyms/Report.swift)
[ -n "$cur" ] || { echo "no gzymsVersion in Sources/gzyms/Report.swift"; exit 1; }

# number, state, title; a closed (not merged) PR is not going anywhere
prs=$(gh pr list --repo "$repo" --label "$label" --state all --limit 100 --json number,state,title \
  --jq '.[] | select(.state != "CLOSED") | "\(.number)\t\(.state)\t\(.title)"')
if [ -z "$prs" ]; then echo "no pull request labelled $label"; exit 0; fi

if [ "$mode" = --done ]; then
  echo "$prs" | awk -F'\t' '$2 == "MERGED" { print $1 }' | while read -r n; do
    gh pr edit "$n" --repo "$repo" --remove-label "$label" >/dev/null && echo "#$n: label off"
  done
  exit 0
fi

IFS=. read -r major minor patch <<< "$cur"
if echo "$prs" | cut -f3 | grep -Eq '^feat(\(|:|!)'; then next="$major.$((minor + 1)).0"; else next="$major.$minor.$((patch + 1))"; fi
next="${2:-$next}"

echo "$cur -> $next"
echo "$prs" | awk -F'\t' '{ printf "  #%s %-6s %s\n", $1, tolower($2), $3 }'
open=$(echo "$prs" | awk -F'\t' '$2 == "OPEN"' | wc -l | tr -d ' ')
[ "$open" = 0 ] || echo "$open still open: merge them or drop the label before the release"

if [ "$mode" = --draft ]; then
  f="whatsnew/$next.md"
  [ -e "$f" ] && { echo "$f is there already, not touched"; exit 0; }
  {
    printf '# %s\n\nThe notes Gzyms shows once after an update to this version. Only the "- " lines are shown.\n\n' "$next"
    # "feat(audio): built-in pills show their direction 🐛" -> "- Built-in pills show their direction."
    echo "$prs" | cut -f3 | grep -Ev '^(chore|docs|test|ci|refactor)(\(|:)' \
      | sed -E 's/^[a-z]+(\([^)]*\))?!?: //; s/ [^ [:alnum:][:punct:]]+$//' \
      | awk '{ print "- " toupper(substr($0, 1, 1)) substr($0, 2) "." }'
  } > "$f"
  echo "wrote $f: rewrite each line for people, then scripts/release.sh"
fi
