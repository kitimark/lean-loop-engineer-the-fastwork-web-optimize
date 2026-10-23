# gpu-safari-lane handoff (checkpoint)

branch: `worktree-wf_85608f68-de1-1`
worktree: `.claude/worktrees/wf_85608f68-de1-1` (under the main checkout)
last commit: see `git log -1` (WIP e1ed415ce, results and note follow)
CI runs: none pushed (local lane, exception (c)); paired CI rows are cited by run id in `results/gpu-safari/lane/ci-pairs.mjs`
verified: lane tests `node --test results/gpu-safari/lane/lane.test.mjs` (9 pass); one local Simulator run per zone (not a result, paired evidence)
open: macOS Safari is blocked while the Mac screen is locked (IOConsoleLocked true, `document.visibilityState` hidden, rAF 0 in 600 ms, WebDriver screenshots all black); IOSurface per push needs Instruments on macOS Safari (not run)

## State
- Code (all under `results/gpu-safari/lane/`, the graph writes): `plan.mjs` arms and states, `sim-capture.mjs` Simulator capture (warm-up load, faithful, A/A control, flag arms, faithful again as order probe), `mac-capture.mjs` macOS Safari capture (refuses a hidden window or a flat screenshot), `pix.mjs` and `reduce.mjs` pixel reduction (existing Lean-backed `grade`, plus TS stand-ins `ringSplit`, `glassOf`, `againstLoads`), `run.mjs` command, `ci-pairs.mjs`, `lane.test.mjs`.
- Results: `results/gpu-safari/<arm>.json` (Simulator), `results/gpu-safari/mac-safari-refusal.json` (macOS refusal with reason). JSON only: stats and hashes, never PNGs (the render guard refuses them); shots stay in `$TMPDIR/fw-gpu-safari-shots/<run>/<zone>/`.
- Note: `research/notes/2026/10-2x-gpu-safari-lane.md`.

## Re-run after unlocking the Mac
1. Unlock the Mac and keep the display awake (`caffeinate -d`), close other heavy apps.
2. `pnpm -s fw slot acquire --kind measure --lease 3000`, then `node results/gpu-safari/lane/run.mjs mac all` (add `pass start/stop` around it only if a timing arm is added). Writes `results/gpu-safari/mac-<arm>.json`.
3. Simulator: `pnpm -s fw slot acquire --kind sim --lease 3000`, `node results/gpu-safari/lane/run.mjs sim all` (about 25 min; run it in the background, one zone is about 7 min). Re-reduce an earlier capture with `run.mjs reduce <shots dir> <zone>`.
4. Release every token you acquired.

## Conventions
- Never report a local row alone: cite the CI run ids of `ci-pairs.mjs`.
- `grade` is the Lean `Fw.Gate.PathPix` grade of the cell; `loads.within` says whether the arm lies inside the faithful load-to-load spread (TS stand-in, descriptive).
- Timing arms (morph Composite and render-server ms per push, pain toggle-frame duration, people-o hover scroll) are not measurable here: the Lean quiet rule refuses every Simulator pass (Mac load 300-500 with the Simulator booted) and the macOS window is hidden. people-o needs a window wider than 860 px (the Simulator is 430 wide).

## Read first
`research/notes/2026/10-2x-gpu-safari-lane.md`, then `results/gpu-safari/lane/sim-capture.mjs`.
