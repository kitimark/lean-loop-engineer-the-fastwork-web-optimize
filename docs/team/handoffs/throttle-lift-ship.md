# throttle-lift-ship handoff

Branch: worktree-wf_1b734b7c-35a-1 (CI branch ci/throttle-lift-ship). Worktree: .claude/worktrees/wf_1b734b7c-35a-1 (under the repo root)
Last commit: 5fe2545ed (CI tip; later commits are local note/ledger work).

CI runs (id, branch ci/throttle-lift-ship, state, what):
- 40068835905 chromium-counts push (default inputs, baseline arm at the same sha), running
- 40068835920 webkit-sim push: skipped (unchanged guard), no WebKit baseline at this sha
- 40068835988 lean push: success
- 40068851412 chromium-counts dispatch, fw=engine.scroll:unthrottle target rewrite swipe-v1 x3, running (dispatch 1 of 3)
- 40068853873 webkit-sim dispatch, fw=engine.scroll:unthrottle target rewrite, running (dispatch 2 of 3)
- 40068858697 breakpoint-gate dispatch, engines both fw=engine.scroll:unthrottle, running (dispatch 3 of 3)
No dispatches left.

Verified: Lean module `lean/Fw/Parts/EngineScrollUnthrottle.lean` compiles (condition chain, same look, cost bound, generated CSS);
golden `packages/contracts/golden/parts/engine.scroll.unthrottle.jsonl`; TS `unthrottle.ts` + test against it.
Open: check.sh and site tests via slot (queued), read the three dispatches, per-frame cost vs faithful baseline, note
`research/notes/2026/10-2x-throttle-lift-ship.md`, ledger rows, preset proposal, dry land.
