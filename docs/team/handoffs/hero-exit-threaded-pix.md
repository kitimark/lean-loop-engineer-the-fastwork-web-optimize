branch: worktree-wf_4a8ad90b-552-1 (CI branch ci/hero-exit-threaded-pix)
worktree: .claude/worktrees/wf_4a8ad90b-552-1
last commit: 0cae7da70 (pushed, dispatch 2 head; code at a4df295a3)
CI runs: 39920801675 path-pix (dispatch 1 of 3) success, artifacts webkit-1/2 and chromium-1/2; 39924527942 path-pix (dispatch 2 of 3) queued then running
run 1 findings: Chromium arm A never ran the faithful driver (virtual page clock not advanced after the scroll, boxes constant, hero fully visible at every offset), so Chromium run 1 is not a valid comparison; Simulator: A/A noise (accent word differs per load, next-section animations), P hand-over live in both VMs
fixes for dispatch 2: Chromium advances the page clock after each scroll until boxes settle; driverMoved witness (invalid cells if arm A did not move); cells skipped when the consumer is transparent in both arms; boxes cover descendants
verified: Lean check green, golden up to date, measure-webkit 409 and measure-chromium 72 tests, ci-paths 54, runner land-inputs 56 (before the fixes); pathpix tests 20 after
open: dispatch 2 cells, note, slim cell JSON (run 1 JSON in results/hero-exit-threaded-pix/run-39920801675), dry land, review gate

# hero-exit-threaded-pix

Task: PathPix cells for hero.exit:threaded (arm P) against the faithful hero.exit (arm A, A2 gives the A/A floor).
- Lean: lean/Fw/Gate/PathPix.lean (gradeRel, whyL, region, exitOffsets, exitClaim); golden packages/contracts/golden/gate/path-pix.jsonl.
- Code: packages/measure-webkit/src/pathpix-exit*.mjs, pathpix-cli.mjs --mode exit; Chromium driver packages/measure-chromium/src/pathpix*.mjs.
- Workflow .github/workflows/path-pix.yml (env PP_MODE exit, PP_FLAG hero.exit:threaded); token [ci:path-pix].
- Report: node packages/measure-webkit/src/pathpix-exit-report.mjs --out results/hero-exit-threaded-pix <label>:<artifact>=<laneDir> ...
Conventions: every consumer holds text, so P cells are L by the text hold; read `ifAccepted` and the raw counts. Strips are CI artifacts only.
Read first: research/notes/2026/10-2x-hero-exit-threaded-pix.md (written after the runs).
