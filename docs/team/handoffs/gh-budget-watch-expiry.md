# Handoff: gh-budget-watch-expiry

State: branch worktree-wf_bc899052-656-2, round 2 (commit named in the report). Read first: `research/notes/2026/10-20-gh-budget-watch-expiry.md`.

Verified here: `sh lean/scripts/check.sh` (see report), `pnpm test` in packages/gh-budget (42 tests), ci-paths test, runner land-inputs test.
Not verified: any run against the real `.git/fw-gh-budget` (forbidden; tests use temp dirs). No CI push made.

What changed (round 1 + 2)
- Lean `lean/Fw/Ci/Budget.lean`: `maxAge` 10800 (`workflowChain` 5700 from mutants.yml:119, `maxAge_covers_chain`), `missMax` 3, `maxRun` 10^13;
  `Watch.misses`, `Watch.registeredAt` (stamped by `step .register`); `tooOld` = `now - registeredAt`; `State.incidents`; events `expire`, `listed`
  (`rows, count, pagesRead, since`), `ack`; `isFull` decides "list was cut"; `covers` takes `since`; `judge` keeps a run created before the window;
  theorems `expire_keeps_young`, `register_stamps`, `register_survives_expire`, `listed_kept_covered`, `isFull_iff`.
- Wire: `registeredAt` (default `createdAt` when absent), `listed:{rows,count,pagesRead,createdSince}`; goldens regenerated (`lake test -- --write-ci-budget-golden`).
- TS: `poller.ts` sends the counts, `wait.ts` `dropWaiter` unregisters before unlinking the marker, `cli.ts` writes a failed cleanup to incidents.jsonl.

Finding: the stray id was the sentinel of `fw ci wait --branch ci/cmr-diag --workflow breakpoint-gate` on commit 37c5a5a6 (fnv = 838323, %ct = createdAt).
Mechanism (marker unlinked, unregister lost to a swallowed error) is INFERRED.

Open items (follow-ups)
- A waiter whose watch was dropped is not told (it times out). Let `evaluate` read `incidents.jsonl`.
- A fw watch alert for a stopped poller.
- Accepted limit: sentinels are not coverage-checked under a narrowed list; the age rule bounds them.
- TS stand-ins: none.

Conventions: wire JSON keys sorted; new Event keys go into `eventOf` and the golden cases; `#guard cases.length` counts them.
