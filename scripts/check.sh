#!/usr/bin/env bash
# Run before every deploy: release build + all tests. Ends with ALL GREEN, or exits non-zero.
set -uo pipefail
cd "$(dirname "$0")/.."

bash scripts/gen-skill.sh  # skill/*.md into the binary
log=$(mktemp)
if ! swift build -c release >"$log" 2>&1; then
  grep -E 'error:' "$log" | head -20
  echo "BUILD FAILED (full log: $log)"
  exit 1
fi
if ! swift test >"$log" 2>&1; then
  grep -E 'failed|error:' "$log" | head -20
  echo "TESTS FAILED (full log: $log)"
  exit 1
fi
rm -f "$log"
echo "ALL GREEN"
