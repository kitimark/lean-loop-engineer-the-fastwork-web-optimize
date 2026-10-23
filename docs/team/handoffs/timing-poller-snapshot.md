# timing-poller-snapshot handoff

- Branch `worktree-wf_8eb150d8-112-1`, worktree `.claude/worktrees/wf_8eb150d8-112-1`; main merged.
- CI runs: none (accepted limit "no CI run").

## State
- Poller (`poller.ts` `pollTick`): each tick's status carries `interval` (`ci.budget.status` on the state after the
  tick) and `retryUntil` (the state's value when fwcore issued the tick, so at most the tick time). Type `TickStatus`.
- `wait.ts` `noteDecided` copies them (`tickBudget`): `pollS`, `retryUntilS` from the deciding tick's status,
  `prevPollS` from the earlier tick's status. No state read at decide time (`budgetAt` is gone).
- Lean `Fw.Obs.Timing`: `gapCapMs p q r w` = `max q w · 1000 + backoffMs` (`w` = `prevPollS`, 0 when absent, so old
  spans keep their verdicts: `gapCapMs_no_prev_poll`). `netMsOf`/`ownOfPhases` take `prevPollS` last.
  Theorems: `gapCapMs_shrunk`/`_grew`/`_prev_le`, `netMsOf_shrunk_within`, `_shrunk_no_prev_poll`,
  `ownOfPhases_shrunk_within`; generic ones (`_capped`, `_gap_within`, `_gap_stall`, `_gap_stall_counts`) take the cap
  `c` with `gapCapMs … = some c`.
- Item (3): `capNets : Fw.Ci.Budget.Reason → Bool` (exhaustive match): `interval`, `retryAfter` are in the cap; floor,
  hour, minute (and the stop reasons) are own time (`capNets_iff`, `capNets_floor/_hour/_minute`), docstring cites
  `Fw.Ci.Budget.interval_sound`.
- Golden `timing-own.jsonl`: 20 rows; new: interval shrank 60→10 s (55 s gap nets, own 205000), same without
  `prevPollS` (240000), interval grew 10→30 s (220000), stall past the earlier 60 s (190000). Wire reads `prevPollS`.

## Verified
- See the report; tests: wait.test.ts "a failed call after the deciding tick…" (2 waiters, 403 on the holder's view
  raises state retryUntil to +600 s, the late reader still records 0) and "an interval that shrank…" (drain before a
  reset: prevPollS 250, pollS 10).

## Open
- The recorded interval is the state's before the tick's `listed`/`pages` events; a pages change shows in the
  deciding tick's interval, which the max takes.

## Read first
- `lean/Fw/Obs/Timing.lean` `gapCapMs`/`capNets`/`netMsOf` (~line 105), `ownCases`; `poller.ts` `tickBudget`.
