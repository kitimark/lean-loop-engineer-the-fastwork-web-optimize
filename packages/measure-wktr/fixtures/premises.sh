#!/bin/sh
# Engine premise lane, WebKit arm (task engine-premise-measure): run the generated premise page through the WKTR driver in
# "cases" mode (one rendering update per golden step; the page acts once per update from window.__fwStep(k)) and write
# <out>/premises-f1/counts-live-<pass>.json. Counts only; nothing here is phone time.
#   node packages/measure-chromium/src/premise-fixture.mjs --engine webkit --out <page dir>
#   sh packages/measure-wktr/fixtures/premises.sh <extracted archive root> <out dir> <page dir> <steps> [passes]
set -eu
ROOT="$1"
OUT="$2"
PAGE="$3"
STEPS="$4"
PASSES="${5:-3}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT"
node "$HERE/../src/cli.mjs" run --keep --root "$ROOT" --site "$PAGE" --out "$OUT/premises-f1" --passes "$PASSES" \
  --step 100 --frames 1 --settle 2000 --variants live --label premises --cases "$STEPS"
