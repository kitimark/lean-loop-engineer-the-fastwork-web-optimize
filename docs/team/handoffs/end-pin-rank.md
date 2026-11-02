Branch `worktree-wf_29839f53-3e5-1`; worktree `.claude/worktrees/wf_29839f53-3e5-1` (under the main checkout); work commit 684cc6ad0, CI trigger 797214995 on `ci/end-pin-rank` (tags `[ci:smoothness] [webkit-cadence] [sim-only] [touch-lock] [trajectory fw=morph.tween:end-pin]`); the final commit is this branch's head.

## CI runs (1 of 2 dispatches used; do not push `ci/end-pin-rank` again for the same question)
- 41369102226 smoothness: failed (fw ci state; gh conclusion failure), 72 min wall. 12 jobs: success 1, 2, 5, 6, 9, 10, 11; failure 3, 7, 8, 12 (touch-driver-not-ready, no ready file after 240 s, 0 windows); cancelled 4 (walk step ran past the walk deadline, no artifact).

## Result (MEASURED)
- Across-jobs pin vs base (Lean `acrossPin`): insufficient, 0 of 12 jobs decisive (minSamples 3). The pin stored a lock in 4 of 29 accepted runs (jobs 2 and 10, 2 each), so pin vs base is `n/a` (4 jobs) or `undecided` (3 jobs).
- Pin: 4 writes in 29 runs, 0 live writes, fights 0 in 29 of 29 (25 by definition). Base: 779 open calls in 30 runs, fights 62.
- Faults by name: touch-driver-not-ready 4, lost-mid-walk 1 (job 11), no result file 1 (job 4), none 6.
- Files: `results/end-pin-rank/run-41369102226/` (jobN/touch-lock.json, across.md), note `research/notes/2026/11-02-end-pin-rank.md`, ledger row morph.tween:end-pin updated.

## Verified
- Lean `check.sh` green; measure-webkit 1121 tests; ci-paths 56; runner land-inputs 73; plan lint 0 errors (writesClosure warnings only); `fw land --dry` ends `VERDICT dry end-pin-rank`.

## Open
- Pass `readyMs: READY_ALLOW_MS` in `touchlock-run.mjs` `startServer` (the lane waits 240 s, Lean allows 480 s).
- A walk that ends the pan on the target side (or a position metric) so the pin stores locks and the across rule can decide.
- Look class L: the user's review is pending; no preset change.

## Read first
`research/notes/2026/11-02-end-pin-rank.md`, `lean/Fw/Measure/TouchLock.lean` (acrossPin), `lean/Fw/Measure/FaultNames.lean`.
