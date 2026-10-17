#!/bin/sh
# Math-view lint + export, computed once per source state (improvement W1-B).
#   scripts/mathview-cached.sh [--build]
# The key is the SHA-256 of the Lean sources, lakefile, manifest and toolchain pin (lean/Fw/**, Fw.lean,
# MathView*.lean, lakefile.toml, lake-manifest.json, lean-toolchain). On a hit it replays the stored lint text and
# prints the stored export path; on a miss it runs `lake exe mathview --lint --out <tmp>` once, stores both
# (only when the lint passes) under .lake/mathview-cache/, and keeps the 5 newest entries.
# stdout: the export path only. stderr: the lint text. Exit 1: the lint failed (nothing cached).
# --build: run `lake build` first on a miss (check.sh has already built; build-math-view.mjs has not).
set -eu
cd "$(dirname "$0")/.."
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
[ "${1:-}" = "--build" ] && lake build >&2
tmp="$dir/.tmp.$$"
trap 'rm -f "$tmp.json" "$tmp.lint"' EXIT
if lake exe mathview --lint --out "$tmp.json" >"$tmp.lint" 2>&1; then
  mv "$tmp.json" "$json"
  mv "$tmp.lint" "$lint"
  # keep the 5 newest keys
  ls -t "$dir"/*.json 2>/dev/null | tail -n +6 | while read -r old; do rm -f "$old" "${old%.json}.lint"; done
  cat "$lint" >&2
  echo "mathview-cached: miss $key (stored)" >&2
  echo "$json"
else
  cat "$tmp.lint" >&2
  exit 1
fi
