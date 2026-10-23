branch: worktree-wf_4a8ad90b-552-1 (CI branch ci/hero-exit-threaded-pix)
worktree: .claude/worktrees/wf_4a8ad90b-552-1
last commit: pushed head of dispatch 3 (main merged; measured code unchanged since a4df295a3)
CI runs: 39920801675 path-pix (dispatch 1 of 3) success; 39924527942 path-pix (dispatch 2 of 3) success; dispatch 3 of 3 is the head of this push (replicates 3 and 4 per lane, same harness)
run 1: Chromium arm A never ran the faithful driver (page clock not ticked after scroll), Chromium run 1 invalid as a comparison; Simulator run 1 cells valid but masks did not cover descendants and consumers transparent in both arms were not skipped
run 2: all 4 jobs succeed; P hand-over live in all; P cells all L by Lean rule (text hold, outside change), if-accepted Q for part of the Simulator cells; accent word noise in the Simulator hero_copy cells (arm A loaded first)
cells JSON: results/hero-exit-threaded-pix/run-<id>/<lane>-<n>.json (slim: grade, why, ifAccepted, raw counts, floor)
verified before dispatch 3: Lean check green, golden up to date, measure-webkit 409, measure-chromium 72, ci-paths 54, runner land-inputs 56, pathpix tests 20 (after the merge of main)
open: dispatch 3 cells, note, final handoff, dry land, review gate

# hero-exit-threaded-pix

Task: PathPix cells for hero.exit:threaded (arm P) against the faithful hero.exit (arm A, A2 gives the A/A floor).
- Lean: lean/Fw/Gate/PathPix.lean (gradeRel, whyL, region, exitOffsets, exitClaim); golden packages/contracts/golden/gate/path-pix.jsonl.
- Code: packages/measure-webkit/src/pathpix-exit*.mjs, pathpix-cli.mjs --mode exit; Chromium driver packages/measure-chromium/src/pathpix*.mjs.
- Workflow .github/workflows/path-pix.yml (env PP_MODE exit, PP_FLAG hero.exit:threaded); token [ci:path-pix].
- Report: node packages/measure-webkit/src/pathpix-exit-report.mjs --out <dir> <label>:<artifact>=<laneDir> ...
Conventions: every consumer holds text, so P cells are L by the text hold; read `ifAccepted` and the raw counts. Strips are CI artifacts only.
Read first: research/notes/2026/10-2x-hero-exit-threaded-pix.md (written after the runs).
