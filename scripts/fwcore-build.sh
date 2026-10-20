#!/bin/sh
# The one way to build the fwcore binary (task console-stale; lean/scripts/check.sh and `fw land` build through it).
# After a successful build on a clean tree it writes the build record next to the binary:
#   lean/.lake/build/bin/fwcore.commit  =  "<sha of HEAD read before the build> <sha256 of the built binary>"
# console-api (at each child spawn) and `fw watch` accept a record only when the sha256 of the binary now on disk equals
# the recorded one (Fw.Obs.chooseBase). Nothing is inferred from file times or the reflog: no record, a record of
# another binary, or a dirty/mid-merge build leaves the core unknown, which the watcher reports as svc.unknown.
#
# - HEAD is read BEFORE `lake build`: if `main` moves during the build, the record names the commit built from.
# - The record is written only after a successful build, only on a tree that is clean before and after the build
#   (tracked changes, untracked files under lean/) and has no merge, rebase or cherry-pick in progress, and only when
#   HEAD did not move. Otherwise the old record is removed; the build itself still runs.
# - After the build the binary is stripped of its symbol table (task lean-bin-slim: 104 -> 75 MB on macOS). `strip -o`
#   writes a new file and `mv` replaces the hard link, so the Lake cache artifact keeps its bytes and Lake still finds
#   the target up to date; the record hashes the stripped binary. No `strip` on PATH, or a failed strip, keeps the
#   unstripped binary (same behaviour, larger file).
# - The binary is stripped once per link: `fwcore.stripped` holds the sha256 of the last strip output, and a binary with
#   that sha256 (Lake did not relink) is kept as it is. MEASURED 2026-10-19 on macOS: stripping a stripped binary again
#   changes its bytes once (sha256 8a4fd2d6ff6f, then 495249a32f9b), so without this the binary of one tree would depend
#   on how often the script ran, and `fw land` compares binaries by sha256 (task land-fwcore-key).
# - `lake build` runs under a machine-wide build slot (scripts/lake-slot.sh, sourced so that no second sh starts).
# Run it in the checkout whose binary runs: sh scripts/fwcore-build.sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
bin=lean/.lake/build/bin/fwcore
rm -f "$bin.commit"
c=$(git rev-parse HEAD)
gitdir=$(git rev-parse --git-dir)
reason=""
state_check() {
  if ! git diff --quiet HEAD -- . || [ -n "$(git ls-files --others --exclude-standard -- lean)" ]; then reason="dirty tree"; fi
  for m in MERGE_HEAD REBASE_HEAD CHERRY_PICK_HEAD rebase-merge rebase-apply; do
    if [ -e "$gitdir/$m" ]; then reason="mid-merge or mid-rebase ($m)"; fi
  done
}
state_check
sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
LAKE_SLOT_LIB=1 . "$root/scripts/lake-slot.sh"
(cd lean && lake_slot "$root" lake build)
if [ -f "$bin.stripped" ] && [ "$(cat "$bin.stripped")" = "$(sha256_of "$bin")" ]; then
  :
elif command -v strip >/dev/null 2>&1 && strip -o "$bin.strip" "$bin" 2>/dev/null; then
  mv -f "$bin.strip" "$bin"
  sha256_of "$bin" > "$bin.stripped"
else
  rm -f "$bin.strip" "$bin.stripped"
  echo "fwcore built; not stripped (no strip on PATH or strip failed)" >&2
fi
if [ -z "$reason" ]; then
  state_check
  [ "$(git rev-parse HEAD)" = "$c" ] || reason="HEAD moved during the build"
fi
if [ -n "$reason" ]; then
  echo "fwcore built; no build record written ($reason): the binary's commit is unknown to the watcher" >&2
  exit 0
fi
h=$(sha256_of "$bin")
echo "$c $h" > "$bin.commit"
echo "fwcore built from $c (recorded, sha256 $(echo "$h" | cut -c1-12))"
