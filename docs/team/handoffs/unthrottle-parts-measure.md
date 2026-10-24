Branch: worktree-wf_3b6992a9-795-1
Worktree: .claude/worktrees/wf_3b6992a9-795-1 (under the repo root)
Last commit: see git log (note, results and handoff committed together; the reducer is at 8d9f7dbfa)
CI runs (toolbar-throttle lane, ci-only commit bd492dcf3 = yml edit, not on this branch):
- 40098348176 on ci/unthrottle-parts-measure-drags (drags, dispatch 1 of 3): success, 6/6 usable passes per arm, hero verdict lifted
- 40101695202 on ci/unthrottle-parts-measure-finish (dispatch 2 of 3): failure; VM 1 gave original and rewrite, lift/unthrottle touch driver timeout, VM 2 original timeout, VM 3 failed at start
- 40101702393 on ci/unthrottle-parts-measure-rest (dispatch 3 of 3): failure; VM 1 gave 8 usable passes, VM 2 and 3 stalled in warm-up
Verified: reducer checked against the Lean golden in test/throttle-parts.test.mjs; package tests pass through the slot, ci-paths and runner land-inputs tests pass (see final report).
Open: finish and rest are below 3 jobs; platform series never mid; commission rewrite borderline at exactly 10; permanent yml change (lead); optional gh run rerun --failed.

## State
- src/throttle/parts.mjs reducer (twins reach/predicted; TS stand-ins: judge, bandFor cadence band, noData reasons, capture reversals).
- src/throttle/parts-recorder.mjs (page side, six series), parts-probe.mjs (modes drags|finish|rest), parts-cli.mjs (run|build-driver|report).
- The lane yml still runs throttle/cli.mjs with three arms. The CI branches carry an extra ci-only commit that points the run step at
  parts-cli.mjs with arms original,rewrite,lift,unthrottle, adds [throttle:rest] (3 rounds), longer timeouts, report via parts-cli.
- A ci branch commit message must contain [ci:toolbar-throttle] and, for finish, [throttle:finish]; for rest, [throttle:rest].
- results/unthrottle-parts/ holds the three summaries re-reduced with the current reducer (stalls columns).

## Read first
research/notes/2026/10-2x-unthrottle-parts-measure.md (answer, tables), then 10-2x-unthrottle-parts.md (Lean predictions).
