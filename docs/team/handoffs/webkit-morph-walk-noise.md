branch: worktree-wf_8d277336-310-1 (CI branch ci/webkit-morph-walk-noise)
worktree: .claude/worktrees/wf_8d277336-310-1
last commit: dd1b906ed (code); handoff commit follows
CI runs: none finished yet (push 1 of 3 in flight; run id added below once the push run exists)

Verified (local, not a result): Lean `lake build Fw.Gate.Trajectory` green; golden regenerated from Lean (383 lines);
`node --test test/trajectory.test.mjs` 423 pass; one local Playwright WebKit debug run at 390 showed the cand walk adds an extra rep.
Cause (CONFIRMED, run 40099056290, Mac morph): the morph is time driven, a bucket passes in 5-15 ms, Mac frames are p50 22 ms /
p90 66 ms / p99 120 ms, so a pooled 5-rep arm misses an interior bucket at random. Cand (or the control) misses a bucket that base hit
-> fail:coverage, rel new, same step repeats across widths.
Fix: per-width retry. Lean `settle`/`settleWalk` in lean/Fw/Gate/Trajectory.lean (cap `extraCap` 15), TS twin `settleReps` in plan.mjs,
glue in run.mjs `morphPath(... against)` (cand only). Apple job timeout 15 -> 40 min (outside write, yml).
Open: (1) CI Mac morph cell for `engine.scroll:batched` (a ci/* push runs the Mac leg only with `debug=`; the recorder is on base and cand
only, so a clean run needs a lead dispatch: `pnpm -s fw run --trajectory --ref ci/webkit-morph-walk-noise --fw engine.scroll:batched --engines playwright-webkit`);
(2) note research/notes/2026/10-2x-webkit-morph-walk-noise.md; (3) final checks (check.sh, tests, merge main, plan lint, land --dry, review ready).
Read first: the note, then Trajectory.lean section "settle".
