# throttle-lift-ship handoff

Branch: worktree-wf_1b734b7c-35a-1 (CI branch ci/throttle-lift-ship, tip 5fe2545ed; later commits local). Worktree: .claude/worktrees/wf_1b734b7c-35a-1 (under the repo root)

CI runs (id, state, what), all on ci/throttle-lift-ship at 5fe2545:
- 40068835905 chromium-counts push, success: default inputs, faithful rewrite + original, the baseline at the same sha
- 40068835920 webkit-sim push: skipped (unchanged guard), no WebKit baseline at this sha
- 40068835988 lean push: success
- 40068851412 chromium-counts dispatch, fw=engine.scroll:unthrottle rewrite swipe-v1 x3: success (dispatch 1 of 3)
- 40068858697 breakpoint-gate dispatch, engines both, fw=engine.scroll:unthrottle: success, no failing item on either engine (dispatch 3 of 3)
- 40068853873 webkit-sim dispatch, fw=engine.scroll:unthrottle rewrite: RUNNING at last write (dispatch 2 of 3)
No dispatches left.

Verified: check.sh green at the golden commit (before the goldenPath move; re-run at the final commit); site vitest 6562 pass;
ci-paths test pass. Chromium counts (535 swipe frames x 3 runs): +1 element restyled in 511/525/530 frames, 0 extra layouts,
0 extra style-recalc events in >= 532, +2 layers (1 drawing layer) in ~530 frames.
Open: WebKit count read (40068853873) vs a store baseline, note `research/notes/2026/10-2x-throttle-lift-ship.md`, ledger
rows (row 41 update + new engine.scroll.unthrottle), preset proposal text, runner tests, final check.sh, dry land.
