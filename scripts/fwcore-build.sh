#!/bin/sh
# The one way to build the fwcore binary (task console-stale). It records the commit the binary was built from next to
# it (lean/.lake/build/bin/fwcore.commit), read by console-api (at each child spawn) and `fw watch`.
#
# - The commit is read BEFORE `lake build`: if `main` moves during the build, the record names the commit built from.
# - The record is written only after a successful build, and only on a clean tree that is not mid-merge or
#   mid-rebase: otherwise the binary has no record (an unidentifiable build, which `fw watch` reports as svc.unknown
#   unless the reflog of main identifies it). The build itself still runs.
# - A plain `lake build` writes no record; its binary is newer than any old record, which then counts for nothing.
# Run it in the checkout whose binary runs: sh scripts/fwcore-build.sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
c=$(git rev-parse HEAD)
gitdir=$(git rev-parse --git-dir)
clean=1
reason=""
if ! git diff --quiet HEAD -- . || [ -n "$(git ls-files --others --exclude-standard -- lean)" ]; then clean=0; reason="dirty tree"; fi
for m in MERGE_HEAD REBASE_HEAD CHERRY_PICK_HEAD rebase-merge rebase-apply; do
  if [ -e "$gitdir/$m" ]; then clean=0; reason="mid-merge or mid-rebase ($m)"; fi
done
(cd lean && lake build)
if [ "$clean" = 1 ]; then
  echo "$c" > lean/.lake/build/bin/fwcore.commit
  echo "fwcore built from $c (recorded)"
else
  rm -f lean/.lake/build/bin/fwcore.commit
  echo "fwcore built; no build record written ($reason): the binary's commit is unknown to the watcher" >&2
fi
