#!/bin/sh
# Math-view lint + export, computed once per source state (W1-B) and per module (task mathview-module-cache).
#   scripts/mathview-cached.sh [--build]
#   scripts/mathview-cached.sh --diff <store> <outdir>     (differential test, see below)
# Fast path: the whole-tree key is the SHA-256 of the Lean sources, lakefile, manifest and toolchain pin (lean/Fw/**,
# Fw.lean, MathView*.lean, lakefile.toml, lake-manifest.json, lean-toolchain). On a hit it replays the stored lint text
# and prints the stored export path (.lake/mathview-cache/, 5 newest keys).
# Miss: one run of .lake/build/bin/mathview --lint --out <tmp> --store <module store>. The module store is shared by
# every worktree of this clone (<git common dir>/mathview-cache/mod/; MATHVIEW_STORE overrides, MATHVIEW_STORE=none
# disables it): each module's export is kept under its key K(m) = H(m, .olean of m, tool hash, [K(i) for its imports])
# and only the modules whose key missed are exported again (lean/MathViewMain.lean, `cachedEntries`). The lint text and
# the export are the same bytes as a full run, except the `heartbeats` field of a reused entry.
# stdout: the export path only. stderr: the lint text. Exit 1: the lint failed (nothing cached in the whole-tree cache).
# --build: run `lake build` first on a miss (check.sh has already built; build-math-view.mjs has not).
# --diff <store> <outdir>: run the full lint and the cached lint over <store> on the current build, write
#   <outdir>/{full,cached}.{json,lint,rc} and cached.stats, and exit 1 unless exit codes, lint text and export (without
#   `heartbeats` lines) are identical. Used by the mathview-differential job in .github/workflows/lean.yml.
set -eu
cd "$(dirname "$0")/.."
bin=.lake/build/bin/mathview

if [ "${1:-}" = "--diff" ]; then
  store=$2; out=$3
  mkdir -p "$out" "$store"
  set +e
  "$bin" --lint --out "$out/full.json" >"$out/full.lint" 2>&1; echo $? >"$out/full.rc"
  "$bin" --lint --out "$out/cached.json" --store "$store" --stats "$out/cached.stats" >"$out/cached.lint" 2>&1
  echo $? >"$out/cached.rc"
  set -e
  grep -v '"heartbeats":' "$out/full.json" >"$out/full.nohb"
  grep -v '"heartbeats":' "$out/cached.json" >"$out/cached.nohb"
  sed -n '1,5p' "$out/cached.stats" | tr '\n' ' ' >&2; echo >&2
  if cmp -s "$out/full.rc" "$out/cached.rc" && cmp -s "$out/full.lint" "$out/cached.lint" \
    && cmp -s "$out/full.nohb" "$out/cached.nohb"; then
    echo "mathview-cached --diff: identical (exit $(cat "$out/full.rc"), $(wc -l <"$out/full.nohb" | tr -d ' ') export lines)" >&2
    exit 0
  fi
  echo "mathview-cached --diff: DIFFERENT" >&2
  diff "$out/full.rc" "$out/cached.rc" >&2 || true
  diff "$out/full.lint" "$out/cached.lint" | head -20 >&2 || true
  diff "$out/full.nohb" "$out/cached.nohb" | head -40 >&2 || true
  exit 1
fi

dir=.lake/mathview-cache
mkdir -p "$dir"
key=$({
  shasum -a 256 lean-toolchain lake-manifest.json lakefile.toml Fw.lean MathView.lean MathViewMain.lean
  find Fw -name '*.lean' -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256
} | shasum -a 256 | cut -c1-16)
json="$dir/$key.json"
lint="$dir/$key.lint"
if [ -s "$json" ] && [ -s "$lint" ]; then
  cat "$lint" >&2
  echo "mathview-cached: hit $key" >&2
  echo "$json"
  exit 0
fi
# the binary directly (no `lake exe`, so no Lake lock in check.sh's parallel group); a stale binary is harmless to the
# module store, whose tool hash is the hash of the sources the binary was compiled from (MathViewMain.toolSources)
if [ "${1:-}" = "--build" ] || [ ! -x "$bin" ]; then lake build >&2; fi
store=${MATHVIEW_STORE:-}
if [ -z "$store" ]; then
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  [ -n "$common" ] && store="$common/mathview-cache/mod"
fi
[ "$store" = none ] && store=""
tmp="$dir/.tmp.$$"
trap 'rm -f "$tmp.json" "$tmp.lint" "$tmp.stats"' EXIT
set -- --lint --out "$tmp.json"
[ -n "$store" ] && set -- "$@" --store "$store" --stats "$tmp.stats"
if "$bin" "$@" >"$tmp.lint" 2>&1; then
  mv "$tmp.json" "$json"
  mv "$tmp.lint" "$lint"
  # keep the 5 newest whole-tree keys
  ls -t "$dir"/*.json 2>/dev/null | tail -n +6 | while read -r old; do rm -f "$old" "${old%.json}.lint"; done
  cat "$lint" >&2
  stats=""
  [ -s "$tmp.stats" ] && stats=", modules: $(sed -n '1,5p' "$tmp.stats" | tr '\n' ' ' | sed 's/ $//')"
  echo "mathview-cached: miss $key (stored$stats)" >&2
  echo "$json"
else
  cat "$tmp.lint" >&2
  exit 1
fi
# keep the module store bounded: the 2000 newest entries (a pruned module is recomputed, never wrong)
if [ -n "$store" ] && [ -d "$store" ]; then
  ls -t "$store" | grep '\.json$' | tail -n +2001 | while read -r old; do rm -f "$store/$old"; done
  find "$store" -name '.tmp.*' -mmin +60 -exec rm -f {} + 2>/dev/null || true  # left by a killed run
fi
