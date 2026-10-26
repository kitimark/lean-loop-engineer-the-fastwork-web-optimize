branch: worktree-wf_f2de22e3-753-1 (CI branch ci/profile-end-tail at commit d244cdb1a)
worktree: .claude/worktrees/wf_f2de22e3-753-1 (under the repo root)
last commit: d244cdb1a (CI request commit; work commit b888eda14)
CI runs: chromium-counts swipe-touch-v1 rewrite (base), 2 runs (the workflow refuses runs < 2): pushed, run id not read yet, running
verified: Lean SwipeEnd + SwipeEndGolden build (lake build Fw), golden swipe-end.jsonl written, test/profile-swipe-end.test.mjs passes (4 tests), ci-paths check ok
open: read CI counts (every end window has frames), note research/notes/2026/10-2x-profile-end-tail.md, results/profile-end-tail/, check.sh via fw slot, package test, dry land

## State
- Lean: lean/Fw/Measure/SwipeEnd.lean (tail = max (windowReach 120 + endWinFrames 40) (idleFrames + holdFrames + 1); swipe-touch-v1 tail 165), SwipeEndGolden.lean, golden packages/contracts/golden/measure/swipe-end.jsonl.
- TS twins in packages/measure-chromium/src/profile.mjs (swipeTail, swipeEndFrame, swipeEndReason, swipeStopAt, swipeStops); run.mjs uses them; counts.json meta.input gains endFrame and tailFrames.
- Wiring: Fw.lean, check.sh job "swipe-end golden check", Trigger.lean lean row + triggers.jsonl.
- Read first: research/notes/2026/10-2x-window-own-end.md, then this branch's diff.
