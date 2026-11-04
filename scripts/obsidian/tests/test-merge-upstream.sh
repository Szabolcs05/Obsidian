#!/usr/bin/env bash
# Tests for scripts/obsidian/merge-upstream.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../merge-upstream.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }

cfg() {
  git -C "$1" config user.name test
  git -C "$1" config user.email test@example.com
  git -C "$1" config commit.gpgsign false
  git -C "$1" config core.autocrlf false
}

# new_pair <name>: creates $TMP/<name>-up (upstream) and $TMP/<name>-fork (clone)
new_pair() {
  UP="$TMP/$1-up"; FORK="$TMP/$1-fork"
  git init -q -b main "$UP"; cfg "$UP"
  printf 'group = io.canvasmc\nchannel = STABLE\nmcVersion = 26.3\n' > "$UP/gradle.properties"
  printf 'line1\nshared\nline3\n' > "$UP/shared.txt"
  git -C "$UP" add -A; git -C "$UP" commit -q -m base
  git clone -q -c core.autocrlf=false "$UP" "$FORK"; cfg "$FORK"
}

up_commit() { # file content msg
  printf '%s\n' "$2" > "$UP/$1"
  git -C "$UP" add -A; git -C "$UP" commit -q -m "$3"
}

run_merge() { # runs in fork; sets OUT, RC
  git -C "$FORK" fetch -q origin
  OUT="$(cd "$FORK" && env -u GITHUB_OUTPUT bash "$SCRIPT" origin/main 2>"$TMP/stderr")"; RC=$?
}

# Case 1: already merged -> up-to-date, no new commit
new_pair c1
before="$(git -C "$FORK" rev-parse HEAD)"
run_merge
after="$(git -C "$FORK" rev-parse HEAD)"
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -qx 'status=up-to-date' && [ "$before" = "$after" ]; then
  pass "up-to-date: no new commit"
else fail "up-to-date (rc=$RC out='$OUT')"; fi

# Case 2: clean merge keeps Obsidian-only file
new_pair c2
printf 'obsidian only\n' > "$FORK/dev-obsidian.txt"
git -C "$FORK" add -A; git -C "$FORK" commit -q -m "obsidian change"
cp "$FORK/dev-obsidian.txt" "$TMP/dev-obsidian.expected"
up_commit upstream-new.txt "new upstream" "upstream change"
up_sha="$(git -C "$UP" rev-parse HEAD)"
run_merge
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -qx 'status=merged' \
   && echo "$OUT" | grep -qx "sha=$up_sha" \
   && echo "$OUT" | grep -qx "short=${up_sha:0:7}" \
   && echo "$OUT" | grep -qx 'mc=26.3' \
   && cmp -s "$FORK/dev-obsidian.txt" "$TMP/dev-obsidian.expected" \
   && [ -f "$FORK/upstream-new.txt" ] \
   && git -C "$FORK" merge-base --is-ancestor "$up_sha" HEAD \
   && [ "$(git -C "$FORK" log -1 --format=%s)" = "Merge Canvas ${up_sha:0:7} (26.3)" ] \
   && [ -z "$(git -C "$FORK" status --porcelain)" ]; then
  pass "clean merge keeps Obsidian file and brings upstream change"
else fail "clean merge (rc=$RC out='$OUT')"; fi

# Case 3: conflict -> exit 2, main untouched, upstream-sync branch has markers
new_pair c3
printf 'line1\nfork-edit\nline3\n' > "$FORK/shared.txt"
git -C "$FORK" add -A; git -C "$FORK" commit -q -m "fork edit"
printf 'line1\nupstream-edit\nline3\n' > "$UP/shared.txt"
git -C "$UP" add -A; git -C "$UP" commit -q -m "upstream edit"
up_sha="$(git -C "$UP" rev-parse HEAD)"; short="${up_sha:0:7}"
main_before="$(git -C "$FORK" rev-parse HEAD)"
run_merge
branch="upstream-sync/$short"
if [ "$RC" -eq 2 ] && echo "$OUT" | grep -qx 'status=conflict' \
   && [ "$(git -C "$FORK" rev-parse HEAD)" = "$main_before" ] \
   && [ "$(git -C "$FORK" symbolic-ref --short HEAD)" = "main" ] \
   && [ -z "$(git -C "$FORK" status --porcelain)" ] \
   && git -C "$FORK" show "$branch:shared.txt" | grep -q '^<<<<<<<' \
   && [ "$(git -C "$FORK" log -1 --format=%s "$branch")" = "Merge Canvas $short (26.3) [CONFLICTS]" ] \
   && git -C "$FORK" merge-base --is-ancestor "$main_before" "$branch"; then
  pass "conflict: exit 2, main unchanged, conflicted branch created"
else fail "conflict (rc=$RC out='$OUT')"; fi

# Case 4: rerun for same sha overwrites the branch
run_merge
if [ "$RC" -eq 2 ] && [ "$(git -C "$FORK" rev-parse HEAD)" = "$main_before" ] \
   && git -C "$FORK" show "$branch:shared.txt" | grep -q '^<<<<<<<'; then
  pass "conflict rerun overwrites existing branch"
else fail "conflict rerun (rc=$RC out='$OUT')"; fi

# Case 5: dirty tree refused with exit 1
new_pair c5
up_commit upstream-new.txt "x" "upstream change"
echo dirty >> "$FORK/shared.txt"
run_merge
if [ "$RC" -eq 1 ] && [ -s "$TMP/stderr" ]; then pass "dirty tree refused"; else fail "dirty tree (rc=$RC)"; fi

# Case 6: outputs go to GITHUB_OUTPUT when set
new_pair c6
up_commit upstream-new.txt "x" "upstream change"
git -C "$FORK" fetch -q origin
GO="$TMP/gh_out"; : > "$GO"
OUT="$(cd "$FORK" && GITHUB_OUTPUT="$GO" bash "$SCRIPT" origin/main 2>/dev/null)"; RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && grep -qx 'status=merged' "$GO" && grep -q '^short=' "$GO"; then
  pass "writes to GITHUB_OUTPUT"
else fail "GITHUB_OUTPUT (rc=$RC out='$OUT')"; fi

# Case 7: no stable commit -> exit 1
rm -rf "$TMP/c7b"; git init -q -b main "$TMP/c7b"; cfg "$TMP/c7b"
printf 'channel = BETA\nmcVersion = 26.3\n' > "$TMP/c7b/gradle.properties"
git -C "$TMP/c7b" add -A; git -C "$TMP/c7b" commit -q -m beta
FORK="$TMP/c7b"
OUT="$(cd "$FORK" && env -u GITHUB_OUTPUT bash "$SCRIPT" HEAD 2>"$TMP/stderr")"; RC=$?
if [ "$RC" -eq 1 ] && [ -s "$TMP/stderr" ]; then pass "no stable commit exits 1"; else fail "no stable (rc=$RC)"; fi

# Case 8: conflict + commit failure -> original branch restored, no MERGING state
new_pair c8
printf 'line1\nfork-edit\nline3\n' > "$FORK/shared.txt"
git -C "$FORK" add -A; git -C "$FORK" commit -q -m "fork edit"
printf 'line1\nupstream-edit\nline3\n' > "$UP/shared.txt"
git -C "$UP" add -A; git -C "$UP" commit -q -m "upstream edit"
main_before="$(git -C "$FORK" rev-parse HEAD)"
git -C "$FORK" config commit.gpgsign true
git -C "$FORK" config gpg.program /nonexistent/gpg
run_merge
if [ "$RC" -ne 0 ] && [ "$RC" -ne 2 ] \
   && [ "$(git -C "$FORK" rev-parse HEAD)" = "$main_before" ] \
   && [ "$(git -C "$FORK" symbolic-ref --short HEAD)" = "main" ] \
   && [ -z "$(git -C "$FORK" status --porcelain)" ] \
   && [ ! -e "$FORK/.git/MERGE_HEAD" ]; then
  pass "commit failure on conflict path restores branch"
else fail "commit failure (rc=$RC out='$OUT')"; fi

# Case 9: missing git identity -> exit 1 before touching anything
new_pair c9
up_commit upstream-new.txt "x" "upstream change"
git -C "$FORK" fetch -q origin
git -C "$FORK" config --unset user.name; git -C "$FORK" config --unset user.email
before="$(git -C "$FORK" rev-parse HEAD)"
OUT="$(cd "$FORK" && env -u GITHUB_OUTPUT HOME="$TMP/nohome" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 bash "$SCRIPT" origin/main 2>"$TMP/stderr")"; RC=$?
if [ "$RC" -eq 1 ] && grep -qi "identity" "$TMP/stderr" \
   && [ "$(git -C "$FORK" rev-parse HEAD)" = "$before" ]; then
  pass "missing identity refused"
else fail "missing identity (rc=$RC)"; fi

# Case 10: usage error exits 64 (never 2, which the workflow reads as "conflict")
OUT="$(cd "$TMP/c9-fork" && env -u GITHUB_OUTPUT bash "$SCRIPT" 2>"$TMP/stderr")"; RC=$?
if [ "$RC" -eq 64 ] && grep -q "usage" "$TMP/stderr"; then
  pass "usage error exits 64"
else fail "usage error (rc=$RC)"; fi

# Case 11: stable commit without mcVersion -> exit 1, nothing merged, no outputs
new_pair c11
printf 'group = io.canvasmc\nchannel = STABLE\n' > "$UP/gradle.properties"
git -C "$UP" add -A; git -C "$UP" commit -q -m "drop mcVersion"
before="$(git -C "$FORK" rev-parse HEAD)"
run_merge
if [ "$RC" -eq 1 ] && grep -q "mcVersion" "$TMP/stderr" && [ -z "$OUT" ] \
   && [ "$(git -C "$FORK" rev-parse HEAD)" = "$before" ] \
   && [ -z "$(git -C "$FORK" status --porcelain)" ]; then
  pass "missing mcVersion refused"
else fail "missing mcVersion (rc=$RC out='$OUT')"; fi

[ "$fails" -eq 0 ] || { echo "$fails test(s) failed"; exit 1; }
echo "All tests passed"
