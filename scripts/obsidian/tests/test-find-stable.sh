#!/usr/bin/env bash
# Tests for scripts/obsidian/find-stable.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../find-stable.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
COUNTER=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }

init_repo() {
  git init -q "$1"
  git -C "$1" config user.name test
  git -C "$1" config user.email test@example.com
  git -C "$1" config commit.gpgsign false
  git -C "$1" config core.autocrlf false
}

commit_channel() { # repo channel
  COUNTER=$((COUNTER + 1))
  printf 'group = io.canvasmc\nchannel = %s\nrev = %s\n' "$2" "$COUNTER" > "$1/gradle.properties"
  git -C "$1" add gradle.properties
  git -C "$1" commit -q -m "channel $2"
}

# Case 1: STABLE, STABLE, BETA -> second commit
R1="$TMP/r1"; init_repo "$R1"
commit_channel "$R1" STABLE
commit_channel "$R1" STABLE
c2="$(git -C "$R1" rev-parse HEAD)"
commit_channel "$R1" BETA
got="$(cd "$R1" && bash "$SCRIPT" HEAD 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$got" = "$c2" ]; then pass "newest STABLE commit found"; else fail "expected $c2, got '$got' (rc=$rc)"; fi

# Case 2: only BETA -> exit 1
R2="$TMP/r2"; init_repo "$R2"
commit_channel "$R2" BETA
commit_channel "$R2" BETA
out="$(cd "$R2" && bash "$SCRIPT" HEAD 2>&1 >/dev/null)"; rc=$?
if [ "$rc" -eq 1 ] && [ -n "$out" ]; then pass "no STABLE commit exits 1 with message"; else fail "expected rc=1 with stderr, got rc=$rc out='$out'"; fi

[ "$fails" -eq 0 ] || { echo "$fails test(s) failed"; exit 1; }
echo "All tests passed"
