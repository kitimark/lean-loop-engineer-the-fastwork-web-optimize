branch: worktree-wf_9543f835-e44-1 (CI branch ci/touch-lock-page-end)
worktree: .claude/worktrees/wf_9543f835-e44-1
last commit: see `git log -1` (CI head of the measured run: 7863f2fbd; later commits are local)
CI runs: smoothness 40059669688 failed (nearEndJs); 40060600880 success, 3 windows all noOpen; 40065281372 success (3rd and last dispatch): base window accepted (8 reversals, 0 fights, 72 displaced), lock window pageLost, restart failed (xcresult name reused), orig never ran; lean run on 7863f2fbd success
verified: Lean TouchLock (repOrder, afterWindow), golden 31 lines, measure-webkit test 593 pass, ci-paths 56, runner test; restart tag fix (serve-r<n>) not measured
open: no more dispatches for this task; lock and orig counts need a later task; across-job verdict sim-touch-verdict-jobs; look class change goes to the user review

# touch-lock-page-end

- Read first: `research/notes/2026/10-2x-touch-lock-page-end.md`, then `lean/Fw/Measure/TouchLock.lean` and `packages/measure-webkit/src/touchlock*.mjs`.
- Lane: head commit message tags `[ci:smoothness] [webkit-cadence] [sim-only] [touch-lock]`; one webkit-sim job runs `touchlock-cli.mjs run`; artifact `smoothness-webkit-sim-1`.
- Arms: orig (snapshot), base (rewrite), lock (rewrite plus CSS lock shim while the morph is open).
- Round 2 changes: window order base, lock, orig (even reps) / lock, base, orig (odd reps) so a stall hits the original first; a stalled push server is restarted up to 2 times before the lane ends; PAN = {500 pt, 500 pt/s, hold 0}.
- Verdict: jitter iff the open phase has a reversal ending at the lock position; runs without an open phase are refused.
- Follow-ups: Q2 touchmove deferral, drawn-offset video reversal count, across-job verdict (`sim-touch-verdict-jobs`).
