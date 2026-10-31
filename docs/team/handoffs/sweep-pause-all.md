branch: worktree-wf_5d322fb6-6d3-1 (CI branch ci/sweep-pause-all)
worktree: .claude/worktrees/wf_5d322fb6-6d3-1
last commit: see `git log -1` on the branch
CI runs: none yet (webkit-sim end-floor run to be pushed; breakpoint gate: run id added by the lead)

Verified locally: vitest platform.sweep (3 files), @fw/site typecheck, part-footprint --check after --write.
Open: CI Simulator census (platform sweep running 0 at end for the sweepPause arm, 3 of 3 rounds); gate: run id added by the lead; merge main, regenerate footprint, dry land.

State: `watchSweepPause` (apps/site/src/parts/platform.sweep/pause.ts) reads getAnimations at each hidden report, pauses a pending play on ready, pauses a late loop on animationstart.
Harness: SWEEP_LOOPS_JS and arm `sweepPause` in packages/measure-webkit/src/sim-end-floor.mjs (own function, rows line "sweep loops <arm>").
Finding only: platform:faded-pause conflict (two owners of pause/startTime; could compose with a reason set; new Lean case, follow-up).
Read first: research/notes/2026/10-31-sweep-pause-all.md.
