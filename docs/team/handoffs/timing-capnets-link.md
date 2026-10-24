# timing-capnets-link handoff

- Branch `worktree-wf_bfce93db-100-1`, worktree `.claude/worktrees/wf_bfce93db-100-1`; main merged. No CI runs (accepted limit).
## State
- (1) Lean `Fw.Obs.Timing`: `waitsMs net ws` sums the waits of a gap whose reason has `capNets = net`.
  `netMsOf_capNets`: a gap made of netting waits (interval, retryAfter) that fit the cap `c` and other waits
  (floor, hour, minute) leaves `others - (c - netting)` of own time; `netMsOf_capNets_full` (netting waits fill the
  cap: every other ms is own time); `netMsOf_own_wait` (one interval wait `q · 1000`, no backoff, then a wait with
  `capNets = false`); `floor_row_own` instantiates it on the floor golden row, `floor_row_is_golden` pins that row.
- Golden `timing-capnets.jsonl` (new, `capNetsCases`, 3 rows: floor wait, backoff + hour wait, minute wait absorbed by
  the cap's slack), each row checked by `CapNetsCase.holds` (the theorem's equation). `timing-own.jsonl` is unchanged:
  `apps/runner/test/timing-own.test.ts` pins its 20 rows and is outside this task's writes. Replay test:
  `packages/gh-budget/test/timing-capnets.test.ts` (fwcore `obs.timing` gives each row's `ownMs`).
- (2) Picked the code fix, not the Lean max theorem: the max over the two ticks' pre-event intervals is false in
  general (`pre_pages_max_misses`: pages 1 to 2 under a leading spread gap, 100 s scheduled, recorded 50 and 12).
  `poller.ts` now sends the `pages` event before writing the status and records `ci.budget.status` of the state it
  returns. Lean: `next_waits_interval` (that interval is the next wait), `interval_step_listed`/`_unregister`/`_register`
  (the later events keep it). Test `wait.test.ts` "a tick whose full list raised the pages ..." (fails on the old code
  with prevPollS 10 for a 12 s gap).
## Verified
- See the report: check.sh, @fw/gh-budget tests, plan lint, dry land.
## Open (follow-ups)
- `gapCapMs` keeps `max q w`: with post-event intervals `w` alone schedules the gap, so `q > w` (the deciding tick grew
  the interval) over-nets by `q - w`.
- A one-off call's response between ticks can lengthen the spread gap after the status was written; not in the cap.
## Read first
- `lean/Fw/Obs/Timing.lean` `waitsMs` .. `pre_pages_max_misses` (~line 232); `poller.ts` `pollTick`.
