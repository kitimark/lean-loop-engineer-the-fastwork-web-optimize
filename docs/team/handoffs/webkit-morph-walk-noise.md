branch: worktree-wf_8d277336-310-1 (CI branch ci/webkit-morph-walk-noise)
worktree: .claude/worktrees/wf_8d277336-310-1
last commit: code a9b1e951a (pushed); later commits are handoff and note only
CI runs (trajectory-probe, fw=engine.scroll:batched engines=playwright-webkit debug=nav-transition, no widths), all 3 pushes used:
- 40122382227 push 1, sha a8c25507 (first rule, cap 15, apple timeout 40): success; Mac morph outcome pass
- 40125557073 push 2, sha a9b1e951a (final rule): success; coverage new 0 at all widths; outcome FAIL on a content group
  nav.background-color at 640 and 641 (colour transition in flight at the end of close)
- 40127042262 push 3, sha 1aeb1923d (same final code): success; Mac morph outcome PASS (641 hit the cap of 8 extra, no repeat)
Verified locally (not results): trajectory.test.mjs 422 pass, gate-breakpoints test 767 pass, check.sh green, ci-paths 56, land-inputs 73.
Cause (CONFIRMED, run 40099056290): the morph is time driven and Mac frames are slow, so a 5-rep pool misses an interior bucket at
random; a candidate miss that the faithful arm hit is a fail:coverage `new` unit that repeats across widths.
Fix: Lean `settle`/`settleWalk` (Fw/Gate/Trajectory.lean, cap `extraCap` 8), TS twin `settleReps` in plan.mjs, glue in run.mjs.
Open: content noise at close@0 / close-hold@0 (nav.background-color, logo.color): follow-up. Final gates: land --dry, review ready.
A clean run (no recorder) needs a lead dispatch:
`pnpm -s fw run --trajectory --ref ci/webkit-morph-walk-noise --fw engine.scroll:batched --engines playwright-webkit`.
Read first: research/notes/2026/10-2x-webkit-morph-walk-noise.md.
