branch: worktree-wf_8d277336-310-1 (CI branch ci/webkit-morph-walk-noise)
worktree: .claude/worktrees/wf_8d277336-310-1
last commit: a9b1e951a code (pushed as ci/webkit-morph-walk-noise); handoff commits after it
CI runs (trajectory-probe, fw=engine.scroll:batched engines=playwright-webkit debug=nav-transition, no widths):
- 40122382227 push 1 of 3, sha a8c25507 (first rule, cap 15, apple timeout 40): success; Mac morph outcome pass
  (390: 1 content unit, 640: 5 content, 641: 0, 1280: 42 coverage at open@3; no node property at 2+ widths)
- 40125557073 push 2 of 3, sha a9b1e951a (final rule: faithful arm only, cap 8, apple timeout 15): success; coverage new 0 at all
  widths (candidate extra passes 0/0/0/1), but outcome FAIL: content group nav.background-color at 640 (close-hold@0) and 641 (close@0),
  `fail:apart`, the colour transition in flight at the end of the close push (rows at m 0..70 with `since` 24..60 ms)
- push 3 of 3 (same code, replication): see the note
Verified locally (not results): trajectory.test.mjs 422 pass, gate-breakpoints test 767 pass, check.sh green, ci-paths 56, land-inputs 73.
Cause (CONFIRMED, run 40099056290): the morph is time driven and Mac frames are slow, so a 5-rep pool misses an interior bucket at
random; a candidate miss that the faithful arm hit is a fail:coverage `new` unit that repeats across widths.
Fix: Lean `settle`/`settleWalk` (Fw/Gate/Trajectory.lean, cap `extraCap` 8), TS twin `settleReps` in plan.mjs, glue in run.mjs.
Open: the content noise at close@0 (nav.background-color, logo.color) is a second noise class; a follow-up task. Final gates (land --dry,
review ready). A clean run (no recorder) needs a lead dispatch:
`pnpm -s fw run --trajectory --ref ci/webkit-morph-walk-noise --fw engine.scroll:batched --engines playwright-webkit`.
Read first: research/notes/2026/10-2x-webkit-morph-walk-noise.md.
