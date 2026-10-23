branch: `worktree-wf_85608f68-de1-1`
worktree: `.claude/worktrees/wf_85608f68-de1-1` (under the main checkout)
last commit: see `git log -1` (round 2 results commit 7254f2c43, then this handoff and the note fix)
CI runs: none pushed (local lane, exception (c)); paired CI rows are cited by run id in `results/gpu-safari/lane/ci-pairs.mjs`. All slot tokens released; Simulator `fw-iphone-27` left booted
verified: `node --test results/gpu-safari/lane/lane.test.mjs` (11 pass); one local Simulator run per zone (nav, morph, pain), paired evidence not a gate
open: macOS Safari arms (Mac screen locked); nav webkit-sim CI rows not dispatched; lane code move to `packages/measure-webkit`; people-o has no 430 px zone

## State
- Code under `results/gpu-safari/lane/`: `plan.mjs` arms and states, `sim-capture.mjs`, `mac-capture.mjs` (refuses hidden window or flat screenshot), `pix.mjs`, `reduce.mjs` (Lean `grade`, TS stand-ins `ringSplit`, `glassOf`, `againstLoads`), `iosurface.mjs` (vmmap proxy), `summary.mjs` (table), `quiet-refusal.mjs`, `run.mjs` (clear message on SIGTERM/INT/HUP), `ci-pairs.mjs`, `lane.test.mjs`.
- Results `results/gpu-safari/<arm>.json` (nav x3, morph x2, pain), `people-o-preview-translate.json` (not measurable), `quiet-refusal.json` (18/18 refused). Shots stay in `$TMPDIR/fw-gpu-safari-shots/`.
- Note: `research/notes/2026/10-2x-gpu-safari-lane.md`. Print the tables: `node results/gpu-safari/lane/summary.mjs`.

## Re-run
1. macOS Safari after an unlock: `pnpm -s fw slot acquire --kind measure --lease 3000`, `node results/gpu-safari/lane/run.mjs mac all`.
2. Simulator: `pnpm -s fw slot acquire --kind sim --lease 1700` (under 30 min), run `run.mjs sim <zone>` in its own process group, release. Rebuild `apps/site/dist/aot` first with `node scripts/build.mjs --engine aot --config '?fw=morph.panel:threaded,platform:fade-threaded'` (the bundled morph arm needs it prerendered).
3. Re-reduce a capture: `run.mjs reduce <shots dir> <zone>`.

## Conventions
- Never report a local row alone: cite the CI run ids of `ci-pairs.mjs`. Compare an arm to the nearest later faithful load; the first faithful load is an outlier (note, finding 1).
- Timing arms are refused by the Lean quiet rule (Mac load above 3 with the Simulator booted).
- Round 1 error "connection closed by this tool" was an external SIGTERM, not a lane bug.

## Read first
`research/notes/2026/10-2x-gpu-safari-lane.md`, then `results/gpu-safari/lane/sim-capture.mjs`.
