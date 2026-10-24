# pathpix-consensus-followups (measure-engineer)

- Branch `worktree-wf_9aacdd20-f29-1`; CI branch `ci/pathpix-consensus-followups`; worktree `.claude/worktrees/wf_9aacdd20-f29-1`.
- Measured commit `f69f8cb29` (code = `0612ef447` + merge of main; empty tip carries `[ci:path-pix]`). Later commits are analysis, note and results only.
- CI run 40037992429 (path-pix): success. Attempt 1 failed only `sim-draw (3)` (infrastructure: Safari tab took ~7 min, then `simctl screenshot` failed); `gh run rerun --failed` once (attempt 2) succeeded. Jobs: sim x3, sim-draw x3, chromium x3, report.

## Built (committed)
- Lean `lean/Fw/Gate/PathPix.lean`: `MZone`, `zoned`, `Verdict.listed`, `drawTimes`, `Draw`, `drawOf`, `Draw.worst`; golden kinds `zoned`, `drawTimes`, `draw`, `drawWorst` (`--check` clean).
- TS `pathpix-exit.mjs` / `pathpix-exit-report.mjs`: zoned consensus; `lookList` shows verdict and leaves varied cells out (falls back to `c.why` on older artifacts).
- Chromium A3 arm (`packages/measure-chromium/src/pathpix.mjs`: A, A2, A3, P).
- Draw window, WebKit only: `pathpix-exit-draw-webkit.mjs` (lane), `pathpix-exit-draw-page.mjs`, `pathpix-exit-draw.mjs` (analysis, band and rest read apart), `pathpix-exit-draw-zones.mjs` (table over jobs), `pathpix-cli.mjs --mode draw`, job `sim-draw`.

## Verified
- Lean check green; measure-webkit 545/545; measure-chromium 78/78. Results in `results/accent-draw-nolayout-pixels/run-40037992429/`; note section "Follow-ups" in `research/notes/2026/10-2x-hero-copy-floor.md`.
- Draw: band counts identical in 3 jobs and both arms (up to 7298 px, delta 212, band floor 0); F shifts layout at draw-in (17622 px at in-0); outside-band baseline per arm and job is unpinned page state.
- 192513-20 raster classed as a floor raster (second-run evidence); nav-earn 4478-2 did not recur, stays open.

## Open
- Chromium draw frames (native sampling, no seeking); pin the outside-band baseline of the draw lane; a rule that names the 192513-20 signature.
- Dry land, `fw review ready`, final report (lead).

## Conventions
- Never hand-edit the golden: `lake build Fw.Gate.PathPix`, then `lake env lean --run scripts/PathPixGolden.lean` from `lean/`.
- Read first: the note section "Follow-ups" and `lean/Fw/Gate/PathPix.lean` (`zoned`, `drawOf`).
