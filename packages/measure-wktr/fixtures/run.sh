#!/bin/sh
# wktr-p1p4 / wktr-fixture-speed fixture lane: run every fixture cell through the WKTR driver (src/cli.mjs) in the layout Lean
# decided and write <out>/<tag>/<fixture>-f<frames>/counts-<variant>-<pass>.json. Counts only; nothing here is phone time.
#   sh packages/measure-wktr/fixtures/run.sh <extracted archive root> <out dir> [passes] [mode] [req]
# mode auto  (default) the production layout: widths from the premise table (Fw.Measure.WktrLayout.heldTable), tag `auto`
# mode probe the premise test: one layout per request in `req` (default 1,2,3: serial, 2 and 3 processes at once), tags k1 k2 k3
# Cells (frames = rendering updates sampled per scroll step: 1 is the scroll update alone, 3 adds two idle updates):
#   all fixtures   frames 1, variants live and live-trace (trace adds the ev_animActive gauge: proof the animation runs)
#   control, scroll-timeline, time-accel   also frames 3, variant live
# The cells, lanes and widths are Lean's (packages/contracts/golden/measure/wktr.fixtures.jsonl); lanes.mjs only reads them.
set -eu
ROOT="$1"
OUT="$2"
PASSES="${3:-3}"
MODE="${4:-auto}"
REQ="${5:-1,2,3}"
HERE="$(cd "$(dirname "$0")" && pwd)"
node "$HERE/lanes.mjs" run --root "$ROOT" --out "$OUT" --passes "$PASSES" --mode "$MODE" --req "$REQ"
