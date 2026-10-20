# Handoff: gh-budget-watch-expiry

State: branch worktree-wf_bc899052-656-2, round 3 (final design round, removal only; commit named in the report). Read first: `research/notes/2026/10-20-gh-budget-watch-expiry.md`.

Verified here: `sh lean/scripts/check.sh`, `pnpm test` in packages/gh-budget, ci-paths test, runner land-inputs test (see report).
Not verified: any run against the real `.git/fw-gh-budget` (forbidden; tests use temp dirs). No CI push made.

What is in the branch
- Lean `lean/Fw/Ci/Budget.lean`: (a) `validWatch` registration refusal; (b) `listed`/`judge`: a real run is dropped when unseen in `missMax` covering
  lists (`unseen`) or uncovered by a full list (`uncovered`); sentinels are not dropped by lists; `isFull`, `covers`; (c) `pageCap`, `pagesOf`,
  `tickCost`, `tick_no_tooBig` (also for a stale stored `pages`: `incident_tick`). No age rule (maxAge, expire, registeredAt are gone).
- Wire: `listed:{rows,count,pagesRead,createdSince}`; a stored `registeredAt` is ignored. Goldens regenerated (`lake test -- --write-ci-budget-golden`, 40 cases).
- TS: `poller.ts` sends the counts and logs incidents, `wait.ts` `dropWaiter` unregisters before unlinking the marker, `cli.ts` writes
  `{cleanupFailed, at}` to incidents.jsonl.

Open items (follow-ups)
- `gh-budget-waiter-liveness`: a sentinel whose waiter died stays registered; it pins the list window (every tick reads pageCap pages).
- A waiter whose watch was dropped times out, not told.
- A list of exactly pagesRead*100 rows counts as cut. Sentinels are not coverage-checked.
- TS stand-ins (two glue rules): next `pages` = floor(count/100)+1; a `completed` run is unregistered.

Conventions: wire JSON keys sorted; new Event keys go into `eventOf` and the golden cases; `#guard cases.length` counts them.
