# timing-wait-state-interval handoff

- Branch `worktree-wf_6ebfcfaf-042-1`, worktree `.claude/worktrees/wf_6ebfcfaf-042-1`; main merged.
- CI runs: none (accepted limit "no CI run").

## State
- Lean `Fw.Obs.Timing`: `backoffMs prevTickMs retryUntilS` = `retryUntilS·1000 − prevTickMs` (0 without either);
  `gapCapMs prevTickMs pollS retryUntilS` = `pollS·1000 + backoffMs` when both `pollS` and `retryUntilS` are recorded,
  else none. `netMsOf t p q r` nets `min (t − p) cap` in the observed case (`t − p` when there is no cap), the state
  case is unchanged. `ownOfPhases` takes `retryUntilS` last.
- Theorems: `backoffMs_before`, `gapCapMs_no_retry`/`_no_poll`/`_some`, `netMsOf_observed` (no cap: old spans),
  `netMsOf_capped`, `_gap_within`, `_gap_stall`, `_state`, `_le_cap`, `ownOfPhases_capped`, `_capped_net_le`,
  `_capped_within`, `_gap_stall`, `_gap_stall_counts` (capped own = uncapped own + stall excess); older theorems take `r`.
- Golden `timing-own.jsonl`: 16 rows with `capMs`; new: stalled gap 217 s at 10 s (own 240000), the same span without
  `retryUntilS` (43000, old verdict), a backoff until 110 s within the cap (189000).
- Wire `ownOfJson` reads `retryUntilS`. TS `wait.ts` `noteDecided` asks fwcore `ci.budget.status` at `now = tickAt`
  on the state file and records `pollS` (interval) and `retryUntilS`; `timing-ci.ts` no longer reads the state;
  `rawOf` forwards `retryUntilS`.

## Verified
- See the report: `lean/scripts/check.sh`, @fw/gh-budget and @fw/runner tests, ci-paths, land-inputs.

## Open
- The cap counts only interval and retryUntil; floor-guard and share waits (`charge` `.floor`/`.hour`/`.minute`) are
  not in it, so such a wait counts as own time.

## Read first
- `lean/Fw/Obs/Timing.lean` `backoffMs`/`gapCapMs`/`netMsOf` (~line 100) and `ownCases`.
