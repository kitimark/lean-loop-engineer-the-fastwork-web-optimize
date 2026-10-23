branch: worktree-wf_4a8ad90b-552-1 (CI branch ci/hero-exit-threaded-pix)
worktree: .claude/worktrees/wf_4a8ad90b-552-1
last commit: 7e01b2bbe (note + cells of run 3), then merge of main 27794977e; dispatch-3 head was af3009d51
CI runs (all on ci/hero-exit-threaded-pix, all 3 dispatches used): 39920801675 path-pix success (run 1, Chromium invalid, Simulator earlier harness); 39924527942 path-pix success (run 2); 39929556147 path-pix success (run 3)
verified at the merge 27794977e: Lean check green, measure-webkit 422, measure-chromium 72, ci-paths 54, runner land-inputs 56
result: no P cell is E or Q under the Lean rule in runs 2 and 3 (4 jobs per lane); all L (text hold or change outside the masks); webkit-4 has 4 invalid cells at y 427
open: land dry run, review gate, look review of the L strips (user), pin the accent-word chain in the lanes

# hero-exit-threaded-pix

Task: PathPix cells for hero.exit:threaded (arm P) against the faithful hero.exit (arm A, A2 gives the A/A floor).
- Lean: lean/Fw/Gate/PathPix.lean (gradeRel, whyL, region, exitOffsets, exitClaim); golden packages/contracts/golden/gate/path-pix.jsonl.
- Code: packages/measure-webkit/src/pathpix-exit*.mjs, pathpix-cli.mjs --mode exit; Chromium driver packages/measure-chromium/src/pathpix*.mjs.
- Workflow .github/workflows/path-pix.yml (env PP_MODE exit, PP_FLAG hero.exit:threaded); token [ci:path-pix].
- Cells: results/hero-exit-threaded-pix/run-<id>/<label>.json (slim: grade, why, ifAccepted, raw counts, floor).
- Report: node packages/measure-webkit/src/pathpix-exit-report.mjs --out <dir> <label>:<artifact>=<laneDir> ...
Conventions: every consumer holds text, so P cells are L by the text hold; read `ifAccepted` and the raw counts. Strips are CI artifacts only.
Read first: research/notes/2026/10-2x-hero-exit-threaded-pix.md (cell tables, finiteRunning and fonts answers, limits).
