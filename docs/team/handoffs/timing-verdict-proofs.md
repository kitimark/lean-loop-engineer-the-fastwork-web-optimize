# timing-verdict-proofs handoff

- Branch `worktree-wf_47509087-1e5-1`; main merged at 2189891e3.
- CI runs: none (accepted limit "no CI run").

## State
- Lean `Fw.Obs.Next`: `verdictsOf_slowSteps_uncontended`, `_no_bucket`, `_of_timing`, `alertsFrom_mem`.
- Lean `Fw.Obs.Timing`: `verdictsOf_sample_at` (a sample verdict indexes a sample of its host, tool and step);
  `ownOfPhases` = own time of a `fw ci wait`: `end − max upd start − min (tick − max upd start) (pollS·1000)` on a
  `done` wait, else none; lemmas `_le_dur`, `_before_start`, `_net_le`, `_within_interval`, `_stall`; golden
  `packages/contracts/golden/obs/timing-own.jsonl` (8 cases, written by `scripts/TimingGolden.lean`).
- Lean `Fw.Wire.Obs`: `ownOfJson` reads `updMs`, `tickMs`, `pollS`; `alertLine_of_mem`.
- TS: `waitSpanExtra` adds `phases.pollS` on a done wait from `pollIntervalS` (fwcore `ci.budget.status`
  `.interval`); `rawOf` forwards `tickMs`/`pollS`.

## Verified
- `lean/scripts/check.sh` green; @fw/runner 3245 tests, @fw/contracts 11, ci-paths green; plan lint 0 errors.
- The 210140 ms c1fdb56 alert: the 6.9 s wait started 203 s after the run's `updatedAt`; old own time counted from
  `updMs`, the start clamp gives 3140 ms (golden row 1). The poller interval is `Fw.Ci.Budget.interval` (≥ 10 s), not
  the 120 s agent poll policy.

## Open
- Spans recorded before this change carry `tickMs` but no `pollS`, so old `fw ci wait` spans get no own time (no verdict).
- `noteSpan` notes stay in the process-wide map after `begin` writes the line; one polish commit per process today.

## Read first
- `lean/Fw/Obs/Timing.lean` `ownOfPhases` (line ~97) and `ownCases`; `apps/runner/src/timing-ci.ts` `waitSpanExtra`.
