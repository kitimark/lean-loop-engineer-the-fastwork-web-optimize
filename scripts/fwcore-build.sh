#!/bin/sh
# The one way to build the fwcore binary (task console-stale; lean/scripts/check.sh and `fw land` build through it).
# After a successful build whose files equal the index it writes the build record next to the binary:
#   lean/.lake/build/bin/fwcore.commit  =  "tree <tree id of the index read before the build> <sha256 of the built binary>"
# console-api (at each child spawn) and `fw watch` accept a record only when the sha256 of the binary now on disk equals
# the recorded one, and take the newest commit of `main` that has the recorded tree as the base (Fw.Obs.chooseBaseTree).
# Nothing is inferred from file times or the reflog: no record, a record of another binary, a dirty build, or a tree no
# commit of `main` has (yet) leaves the core unknown, which the watcher reports as svc.unknown.
#
# - The record names the built TREE (`git write-tree`), not HEAD: `fw land` builds the merged tree before the commit that
#   lands it exists, and that commit has the same tree. A merge, rebase or cherry-pick in progress is no input.
# - The rule (Fw.Obs.recordTree, scripts/fwcore-record-rule.sh): record the tree only when the working files equalled the
#   index before and after the build (tracked changes, untracked files under lean/) and the tree did not change.
#   The old record is NOT removed before the build: a build that changes nothing keeps a record that still matches, and a
#   relink makes the old record mismatch (unknown) until this script writes the new one.
# - After the build the binary is stripped of its symbol table (task lean-bin-slim: 104 -> 75 MB on macOS). `strip -o`
#   writes a new file and `mv` replaces the hard link, so the Lake cache artifact keeps its bytes and Lake still finds
#   the target up to date; the record hashes the stripped binary. No `strip` on PATH, or a failed strip, keeps the
#   unstripped binary (same behaviour, larger file).
# - The binary is stripped once per link: `fwcore.stripped` holds the sha256 of the last strip output, and a binary with
#   that sha256 (Lake did not relink) is kept as it is. MEASURED 2026-10-19 on macOS: stripping a stripped binary again
#   changes its bytes once (sha256 8a4fd2d6ff6f, then 495249a32f9b), so without this the binary of one tree would depend
#   on how often the script ran, and `fw land` compares binaries by sha256 (task land-fwcore-key).
# Run it in the checkout whose binary runs: sh scripts/fwcore-build.sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
bin=lean/.lake/build/bin/fwcore
. "$root/scripts/fwcore-record-rule.sh"
# the facts of Fw.Obs.BuildFacts: the tree id of the index (empty: unmerged paths) and whether the files equal it
tree_now() { git write-tree 2>/dev/null || true; }
clean_now() {
  if git diff --quiet -- . && [ -z "$(git ls-files --others --exclude-standard -- lean)" ]; then echo 1; else echo 0; fi
}
before=$(tree_now)
clean_before=$(clean_now)
sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
. "$root/scripts/lake-slot-lib.sh"
lake_out=$(mktemp "${TMPDIR:-/tmp}/fwlake.XXXXXX")
trap 'rm -f "$lake_out" "$lake_out.rc"' EXIT
{ (cd lean && lake_slot "$root" lake build) || echo $? > "$lake_out.rc"; } | tee "$lake_out"
[ ! -s "$lake_out.rc" ] || exit "$(cat "$lake_out.rc")"
[ -z "${FW_LAKE_BUILT_FILE:-}" ] || lake_built_member "$lake_out" > "$FW_LAKE_BUILT_FILE"
if [ -f "$bin.stripped" ] && [ "$(cat "$bin.stripped")" = "$(sha256_of "$bin")" ]; then
  :
elif command -v strip >/dev/null 2>&1 && strip -o "$bin.strip" "$bin" 2>/dev/null; then
  mv -f "$bin.strip" "$bin"
  sha256_of "$bin" > "$bin.stripped"
else
  rm -f "$bin.strip" "$bin.stripped"
  echo "fwcore built; not stripped (no strip on PATH or strip failed)" >&2
fi
after=$(tree_now)
clean_after=$(clean_now)
t=$(record_rule "$before" "$after" "$clean_before" "$clean_after")
if [ -z "$t" ]; then
  echo "fwcore built; no build record written (the files did not equal one tree: dirty, or the index moved during the build); an older record still names this binary only if it was not relinked" >&2
  exit 0
fi
h=$(sha256_of "$bin")
echo "tree $t $h" > "$bin.commit.tmp" && mv -f "$bin.commit.tmp" "$bin.commit"
echo "fwcore built from tree $t (recorded, sha256 $(echo "$h" | cut -c1-12))"
