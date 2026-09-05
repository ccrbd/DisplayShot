#!/usr/bin/env bash
# Fails if any third-party product name or URL that must not appear in this
# repository is found in tracked (or staged) files. Run from the repo root.
set -euo pipefail
cd "$(dirname "$0")/.."

# Pattern is assembled from fragments so this script does not itself trip the check.
A="light"; B="shot"; C="prnt"; D="scr"; E="skill"; F="brains"
PATTERN="${A}${B}|${C}${D}|${E}${F}"

if git grep -n -i -E "$PATTERN" -- ':!scripts/check-ip.sh' >/dev/null 2>&1; then
  echo "check-ip: disallowed third-party references found:" >&2
  git grep -n -i -E "$PATTERN" -- ':!scripts/check-ip.sh' >&2
  exit 1
fi
echo "check-ip: OK"
