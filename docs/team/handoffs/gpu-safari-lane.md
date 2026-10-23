branch: `worktree-wf_85608f68-de1-1`
worktree: `.claude/worktrees/wf_85608f68-de1-1`
last work commit: 1d1cd48a8 (round 3: morph driven by a real push)
CI runs: none pushed (local lane, exception (c)). Paired CI rows are cited in `results/gpu-safari/lane/ci-pairs.mjs`; nav webkit-sim rows: 39872562267 clip-box (failure; v1/r1 failed, r2 pair usable), 39872566438 bar-fixed (failure; r1/r2 failed, r3 pair usable), 39872570182 logo-3d (success); task nav-fixed-followups reduces them
verified: `node --test results/gpu-safari/lane/lane.test.mjs` (13 pass); one Simulator run of the morph zone (run gpu-safari-sim-2026-10-23T01-50-53-878Z, one sim slot, released; Simulator shut down); nav and pain re-reduced from their round-2 shots with the later-load floor
open: macOS Safari arms (Mac screen locked, followUp); people-o not measurable at 430 wide; lane code move to `packages/measure-webkit`; TS stand-ins to Lean (follow-up)

## State
- Code under `results/gpu-safari/lane/`: `plan.mjs` (arms, states, `elapsedAt`), `sim-capture.mjs` (`PUSH_EXPR`, `STEP_EXPR`: a real wheel push through the page's tween driver, effects paused at currentTime = elapsed of m), `mac-capture.mjs`, `pix.mjs` (`againstLoads`: floor = later-load pair i=1,j=2), `reduce.mjs`, `iosurface.mjs`, `summary.mjs`, `quiet-refusal.mjs`, `run.mjs`, `ci-pairs.mjs`, `lane.test.mjs`.
- Results `results/gpu-safari/<arm>.json` (nav x3, morph x2, pain), `people-o-preview-translate.json`, `quiet-refusal.json` (18/18 refused: available memory 118-432 MB with the Simulator booted; why=avail 18/18).
- Note: `research/notes/2026/10-2x-gpu-safari-lane.md`. Print the tables: `node results/gpu-safari/lane/summary.mjs`.
- Morph (round 3, MEASURED): faithful 0 effects, threaded 2, bundled 3, all paused at progress m. Arms differ from faithful by 29k / 122k / 146k px (max delta 2-3) against the later-load floor 8.6k / 1.6k / 5.3k, so above it; round 2's static rows (77k-158k) were the const-bounds class only. A first round-3 run without the start-lag correction had faithful loads 1.8M px apart (the tween started 11 ms after the wheel); `STEP_EXPR` now corrects the frame time until the published value equals m.

## Re-run
1. macOS Safari after an unlock: `pnpm -s fw slot acquire --kind measure --lease 3000`, `node results/gpu-safari/lane/run.mjs mac all`.
2. Simulator: `pnpm -s fw slot acquire --kind sim --lease 1700`, run `run.mjs sim <zone>` in its own process group (python `start_new_session`; there is no `setsid` here), release, `xcrun simctl shutdown` the device. `apps/site/dist/aot` must hold the morph configs (`node scripts/build.mjs --engine aot --config '?fw=morph.panel:threaded,platform:fade-threaded'`).
3. Re-reduce a capture: `run.mjs reduce <shots dir> <zone>`.

## Conventions
- Never report a local row alone: cite the CI run ids of `ci-pairs.mjs`. The A/A floor is the later-load pair (base2 vs base3); compare an arm to the nearest later load.
- Timing arms are refused by the Lean quiet rule.
- The nav look change (pill edge ring, subpixel shift up to maxDelta 220 at m0.9) is MEASURED and goes to the user look-review class.

## Read first
`research/notes/2026/10-2x-gpu-safari-lane.md`, then `results/gpu-safari/lane/sim-capture.mjs`.
