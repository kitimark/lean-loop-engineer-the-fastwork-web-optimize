#!/bin/sh
# Run the WebKit lane against apps/site's prerendered build for the four configs of the handoff.
# Build first:  pnpm --filter @fw/site build    (dist/aot, one HTML per config hash)
# Output (gitignored out/): site-<name>-ps.json (perstep: base + hold, 3 runs) and site-<name>-det.json
# (determinism: census at y 0, 1500, max + scroll, 2 runs, no seek fixture). Run from packages/measure-webkit.
set -e
SITE="${SITE:-../../apps/site/dist/aot}"
run() { # name search
  node src/cli.mjs perstep --site "$SITE" --search "$2" --modes base,hold --runs 3 --out "out/site-$1-ps.json" > "out/site-$1-ps.log" 2>&1
  node src/cli.mjs determinism --site "$SITE" --search "$2" --runs 2 --no-seek --state 0,1500,max --out "out/site-$1-det.json" > "out/site-$1-det.log" 2>&1
}
mkdir -p out
run default ""
run batched "?fw=engine.scroll:batched"
run hitskip "?fw=nav.hitTest:hit-skip"
run strip "?fw=hero.countdown:strip"
echo finished
