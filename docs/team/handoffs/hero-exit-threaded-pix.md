branch: worktree-wf_4a8ad90b-552-1 (CI branch ci/hero-exit-threaded-pix)
worktree: .claude/worktrees/wf_4a8ad90b-552-1
last commit: set after the first push (see git log)
CI runs: none dispatched yet (the push of ci/hero-exit-threaded-pix with [ci:path-pix] starts the first)
verified: Lean check green, golden up to date, measure-webkit 409 and measure-chromium 72 tests, ci-paths 54, runner land-inputs 56
verified: one local 3-offset Simulator debug run (not a result): P hand-over live, pipeline to cells.json works
open: CI cells (webkit vm1/vm2, chromium 1/2), note, slim cell JSON, dry land, review gate

# hero-exit-threaded-pix

Task: PathPix cells for hero.exit:threaded (arm P) against the faithful hero.exit (arm A, A2 gives the A/A floor).
- Lean: lean/Fw/Gate/PathPix.lean (gradeRel, whyL, region, exitOffsets, exitClaim); golden packages/contracts/golden/gate/path-pix.jsonl.
- Code: packages/measure-webkit/src/pathpix-exit*.mjs, pathpix-cli.mjs --mode exit; Chromium driver packages/measure-chromium/src/pathpix*.mjs.
- Workflow .github/workflows/path-pix.yml (env PP_MODE exit, PP_FLAG hero.exit:threaded); token [ci:path-pix].
- Report: node packages/measure-webkit/src/pathpix-exit-report.mjs --out results/hero-exit-threaded-pix <label>:<artifact>=<laneDir> ...
Conventions: every consumer holds text, so P cells are L by the text hold; read `ifAccepted` and the raw counts. Strips are CI artifacts only.
Read first: research/notes/2026/10-2x-hero-exit-threaded-pix.md (written after the runs).
