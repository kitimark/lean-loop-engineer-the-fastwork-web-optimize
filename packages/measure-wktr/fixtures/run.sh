#!/bin/sh
# wktr-p1p4 fixture lane: run every fixture page of this directory through the WKTR driver (src/cli.mjs) and write
# <out>/<fixture>-f<frames>/counts-<variant>-<pass>.json. Counts only; nothing here is phone time.
#   sh packages/measure-wktr/fixtures/run.sh <extracted archive root> <out dir> [passes]
# Arms (frames = rendering updates sampled per scroll step: 1 is the scroll update alone, 3 adds two idle updates):
#   all fixtures   frames 1, variants live and live-trace (trace adds the ev_animActive gauge: proof the animation runs)
#   control, scroll-timeline, time-accel   also frames 3, variant live
set -eu
ROOT="$1"
OUT="$2"
PASSES="${3:-3}"
HERE="$(cd "$(dirname "$0")" && pwd)"
CLI="$HERE/../src/cli.mjs"
mkdir -p "$OUT"
run() { # fixture frames variants
  node "$CLI" run --keep --root "$ROOT" --site "$HERE/$1" --out "$OUT/$1-f$2" --passes "$PASSES" \
    --step 100 --frames "$2" --settle 2000 --variants "$3" --label "$1"
}
for f in control scroll-timeline scroll-js-transform scroll-js-bg time-accel; do
  run "$f" 1 live,live-trace
done
for f in control scroll-timeline time-accel; do
  run "$f" 3 live
done
