# timing-poll-interval-observed handoff

- Branch `worktree-wf_85cef3fb-941-1`, worktree `.claude/worktrees/wf_85cef3fb-941-1`; work at 652e8bfcd, main merged.
- CI runs: none (accepted limit "no CI run").

## State
- Lean `Fw.Obs.Timing`: `netSrc tickMs prevTickMs` = `observed` when the earlier tick precedes the deciding one, else
  `state`; `netMsOf` nets `tickMs − prevTickMs` (observed) or `pollS·1000` (state). `ownOfPhases` takes
  `prevTickMs` and is `ownOfNet … (netMsOf …)`. Theorems: `netSrc_observed_iff`, `_no_prev`, `_no_tick`,
  `_not_before`, `netMsOf_observed`, `_state`, `_observed_ignores_poll`, `ownOfPhases_observed`, `_state`,
  `_observed_unfinished`, `_state_within`, `_state_stall`, `_observed_net_le`, `_state_net_le`, `_le_dur`, and
  `_not_done`/`_no_upd`/`_no_tick`/`_no_interval`/`_after_end`/`_before_start`.
- Golden `packages/contracts/golden/obs/timing-own.jsonl`: 13 rows carrying `netSrc`/`netMs`; c1fdb56 first wait with
  `prevTickMs` 12 s before `tickMs`: observed, 57709 ms (state alone: 58709); a 60 s backoff gap row (200000).
- Wire `ownOfJson` reads `prevTickMs`. TS `rawOf` forwards `prevTickMs`; `waitSpanExtra` asks the interval at the
  deciding tick's time (`now = tickMs/1000`) instead of the span-write time.

## Verified
- `lean/scripts/check.sh` green; @fw/runner 3259 tests (golden replay through fwcore), @fw/contracts 11, ci-paths 56.

## Open
- The state case evaluates `Budget.interval` on the state file read at span write, at the tick's time; recording it
  inside `noteDecided` needs `packages/gh-budget/src/wait.ts` (outside this task's writes).
- Older spans with `prevTickMs` get an own time from the observed gap; those with neither
  `prevTickMs` nor `pollS` keep none.

## Read first
- `lean/Fw/Obs/Timing.lean` `netSrc`/`netMsOf`/`ownOfPhases` (~line 95) and `ownCases`.
