branch: worktree-wf_f2de22e3-753-1 (CI branch ci/profile-end-tail at commit d244cdb1a)
worktree: .claude/worktrees/wf_f2de22e3-753-1 (under the repo root)
last commit: b888eda14 (CI request commit d244cdb1a)
CI runs: chromium-counts 40355794611 (swipe-touch-v1, rewrite = base, 2 runs, the workflow refuses fewer) success
verified: Lean SwipeEnd + golden build; test/profile-swipe-end.test.mjs; package test 107 pass; CI run 40355794611: both runs stalled, stop frame 740 = end 575 + tail 165, 771 frames (same as before), end windows 20/40/60/47 frames; check.sh green after merging main; plan lint no writesClosure error for this task; ci-paths test 56 pass; land-inputs test 73 pass
open: dry land result, review ready (see the report)

## State
- Lean: lean/Fw/Measure/SwipeEnd.lean (tail = max (windowReach 120 + endWinFrames 40) (idleFrames + holdFrames + 1); swipe-touch-v1 tail 165), SwipeEndGolden.lean, golden packages/contracts/golden/measure/swipe-end.jsonl.
- TS twins in packages/measure-chromium/src/profile.mjs (swipeTail, swipeEndFrame, swipeEndReason, swipeStopAt, swipeStops); run.mjs uses them; counts.json meta.input gains endFrame and tailFrames.
- Wiring: Fw.lean, check.sh job "swipe-end golden check", Trigger.lean lean row + triggers.jsonl.
- Note: research/notes/2026/10-2x-profile-end-tail.md; results: results/profile-end-tail/ (windows.json, windows.mjs).
- Flag arm (limit end, morph.stage) belongs to the morph-stage task's rerun.
