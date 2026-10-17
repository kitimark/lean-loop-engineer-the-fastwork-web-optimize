#!/bin/sh
# Load-stamped runs on ONE kept-alive Simulator (--keep: no reboot between runs; shut it down with `sim down`).
# Every pass records host load1 and CPU idle at its start and end (src/load.mjs). Run from packages/measure-webkit.
set -e
SITE="${SITE:-../../apps/site/dist/aot}"
mkdir -p out
# 1. the rewrite config that failed to launch under load
node src/cli.mjs determinism --keep --site "$SITE" --search "?fw=hero.countdown:strip" --runs 2 --no-seek --state 0,1500,max --out out/site-strip-det.json > out/site-strip-det.log 2>&1
# 2. the original, stamped: base and hold, 3 runs each (replaces the unstamped batches as the quoted table)
node src/cli.mjs perstep --keep --modes base,hold --runs 3 --out out/ps3-a.json > out/ps3-a.log 2>&1
node src/cli.mjs perstep --keep --modes base,hold --runs 3 --out out/ps3-b.json > out/ps3-b.log 2>&1
echo finished
