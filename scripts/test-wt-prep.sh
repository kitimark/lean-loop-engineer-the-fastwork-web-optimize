#!/bin/sh
# test-wt-prep.sh: scratch worktree -> wt-prep -> `lake build` must be a no-op (< 5 s) -> remove worktree.
set -eu
top=$(git rev-parse --show-toplevel)
main=$(cd "$(git rev-parse --git-common-dir)/.." && pwd -P)
wt="$main/.claude/worktrees/wt-prep-test-$$"
trap 'git -C "$main" worktree remove --force "$wt" >/dev/null 2>&1 || true; git -C "$main" branch -D "wt-prep-test-$$" >/dev/null 2>&1 || true' EXIT
git -C "$top" worktree add -q -b "wt-prep-test-$$" "$wt" HEAD
(cd "$wt" && sh "$top/scripts/wt-prep.sh")
now() { perl -MTime::HiRes=time -e 'printf "%.2f\n", time()'; }
s=$(now)
(cd "$wt/lean" && lake build > "$wt/build.log" 2>&1)
d=$(now)
t=$(echo "$d - $s" | bc)
echo "test-wt-prep: first lake build after clone took $t s; rebuilt jobs:"
grep -v ' (0\.[0-9]*s)$' "$wt/build.log" | grep '^[^B]' | head -5 || true
s=$(now); (cd "$wt/lean" && lake build >/dev/null 2>&1); d=$(now)
echo "test-wt-prep: second lake build took $(echo "$d - $s" | bc) s"
[ "$(echo "$t < 5" | bc)" = 1 ] && echo PASS || { echo "FAIL (>= 5 s)"; exit 1; }
