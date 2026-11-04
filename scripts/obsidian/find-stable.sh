#!/usr/bin/env bash
# Print the full sha of the newest first-parent commit reachable from <ref>
# whose gradle.properties declares `channel = STABLE`.
# Exits 1 (message on stderr) if none is found within the last 500 commits.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <ref>" >&2
  exit 2
fi
ref="$1"

while read -r sha; do
  if git show "$sha:gradle.properties" 2>/dev/null \
      | tr -d '\r' \
      | grep -Eq '^channel[[:space:]]*=[[:space:]]*STABLE[[:space:]]*$'; then
    echo "$sha"
    exit 0
  fi
done < <(git rev-list --first-parent --max-count=500 "$ref")

echo "error: no STABLE commit found within 500 first-parent commits of $ref" >&2
exit 1
