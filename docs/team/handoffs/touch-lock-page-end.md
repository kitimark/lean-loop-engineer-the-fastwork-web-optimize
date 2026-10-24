branch: worktree-wf_9543f835-e44-1 (CI branch ci/touch-lock-page-end, pushed at 3ec3348ab)
worktree: .claude/worktrees/wf_9543f835-e44-1
last commit: see `git log -1` on the branch (3ec3348ab is the CI head; later commits are local only, not pushed)
CI runs: smoothness 40059669688 failed (nearEndJs never invoked; fixed); smoothness 40060600880 success but 3 windows, all refused noOpen (lane ended: lock push done at 209 s); lean 40059669748 success
verified: Lean module + golden --check, measure-webkit test, ci-paths test (56), runner land-inputs test (56), check.sh green; one local debug run (not a result) opened the morph with the new PAN {500,500,0}
open: no reversal counts yet; 2 of 2 dispatches used; a 3rd dispatch with the new PAN default is needed (lead decides)

# touch-lock-page-end

- Read first: `research/notes/2026/10-2x-touch-lock-page-end.md`, then `lean/Fw/Measure/TouchLock.lean` and `packages/measure-webkit/src/touchlock*.mjs`.
- Lane: head commit message tags `[ci:smoothness] [webkit-cadence] [sim-only] [touch-lock]`; one webkit-sim job runs `touchlock-cli.mjs run`; artifact `smoothness-webkit-sim-1`; results of run 40060600880 are in `results/touch-lock-page-end/run-40060600880/`.
- Arms: orig (snapshot), base (rewrite), lock (rewrite plus CSS lock shim while the morph is open, one frame late).
- Gesture: `PAN = {dragPt 500, velocity 500, holdMs 0}` from `START_GAP_PX = 250` above the end (the 1800 pt/s flick never opened the morph in the CI run).
- Verdict: a run is jitter iff the open phase has a direction reversal ending at the lock position (`frameFights > 0`); runs without an open phase are refused.
- Follow-ups: Q2 touchmove deferral, drawn-offset video reversal count, across-job verdict (`sim-touch-verdict-jobs`), the stall that ends the touch lane.
