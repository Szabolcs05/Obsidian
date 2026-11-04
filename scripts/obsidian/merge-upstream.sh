#!/usr/bin/env bash
# Safely merge the newest STABLE upstream commit reachable from <upstream-ref>
# into the currently checked-out branch (never uses strategy options).
#
# Outputs key=value lines (to $GITHUB_OUTPUT if set, else stdout):
#   status=up-to-date|merged|conflict, sha=<full>, short=<7>, mc=<mcVersion>
# Exit codes: 0 up-to-date/merged, 2 conflict, 1 any other failure.
#
# On conflict the checked-out branch is left untouched; the conflicted merge
# commit lives only on branch upstream-sync/<short> (overwritten if present).
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <upstream-ref>" >&2
  exit 2
fi
ref="$1"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "error: $*" >&2; exit 1; }

emit() { # status
  {
    echo "status=$1"
    echo "sha=$sha"
    echo "short=$short"
    echo "mc=$mc"
  } >> "${GITHUB_OUTPUT:-/dev/stdout}"
}

orig="$(git symbolic-ref --short -q HEAD)" || die "HEAD is detached; check out a branch first"
[ -z "$(git status --porcelain)" ] || die "working tree is not clean; refusing to merge"

sha="$("$here/find-stable.sh" "$ref")" || die "could not determine a stable upstream commit from $ref"
short="${sha:0:7}"
mc="$(git show "$sha:gradle.properties" | tr -d '\r' \
  | sed -n 's/^mcVersion[[:space:]]*=[[:space:]]*\([^[:space:]]*\).*$/\1/p' | head -n1)"

if git merge-base --is-ancestor "$sha" HEAD; then
  emit up-to-date
  exit 0
fi

pre="$(git rev-parse HEAD)"
msg="Merge Canvas $short ($mc)"

if git merge --no-ff --no-edit -m "$msg" "$sha" >&2; then
  emit merged
  exit 0
fi

# Merge failed: distinguish a real content conflict from other errors.
if [ -z "$(git ls-files -u)" ]; then
  git merge --abort 2>/dev/null || true
  git reset -q --hard "$pre"
  die "merge of $sha failed without conflicts"
fi

branch="upstream-sync/$short"
git add -A
git commit -q --no-verify -m "$msg [CONFLICTS]"
git branch -f "$branch" HEAD
git reset -q --hard "$pre"

emit conflict
exit 2
