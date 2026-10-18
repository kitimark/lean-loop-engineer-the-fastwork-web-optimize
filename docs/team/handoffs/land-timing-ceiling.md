# land-timing-ceiling handoff

State: committed on branch worktree-agent-aa9f20269b17156a7 (see `git log -1`). check.sh green, runner tests 285/285, contracts tests green, `pnpm fw incidents lint` 0 errors.

## What changed
- `lean/Fw/Obs/Timing.lean`: new `Params.ceilings : List (tool, step, ms)` (first match wins), `ceilingOf`, `ceilingBreach`, `budgetFor`, `landCeilings` (fw land / total 30 s, fw land / lock held 5 s), `landParams`.
  A non-noisy sample over its ceiling is `slow` with no window (fixes the "slow from day one never alerts" gap). `judge` reports `budgetFor` as `budgetMs`.
- Theorems: new `ceilingBreach_iff`, `codeOf_slow_iff` (the old relative rule), `land_budget_alert`; changed `slow_iff` (breach OR relative rule), `no_alert_within_budget` (uses `budgetFor`), `noBaseline_iff` and `noBaseline_below_nmin` (extra `ceilingBreach = false`), `slow_mono_dur`.
- Golden `packages/contracts/golden/obs/timing.jsonl` regenerated (params gain `ceilings`; 6 new land cases; the #guard replays the 3 measured check.sh spans as lock-held samples).
- `apps/runner/src/land.ts`: span `fw land / lock held` (take to release, inside `release`) and a `total` wrapper: `land` now wraps `landRun` in span `fw land / total` (nested `via` lands skip it). The wrapper goes beyond the lock span the task named; without it the 30 s ceiling has no sample.
- `docs/team/incidents/ledger.json`: `inc-slow-land` (fix task mathview-axreach, also land-timing-ceiling, mathview-module-cache, check-dag, land-prelock).

## Open
- No TS consumer of `obs.timing` exists yet (timing-alert); the ceilings reach the alert only when that wiring passes `landCeilings`/`landParams`-style params.
- Ceilings are not applied to noisy local samples (load > 16), by design.
- Other land.ts tasks (checksfor-inputs, check-dag, land-prelock) may rebase over the two small edits above.
- Math view: docstrings of the changed theorems need the math-reviewer pass.

Read first: `research/notes/2026/10-18-land-speed.md`, then `lean/Fw/Obs/Timing.lean` (`ceilingBreach`, `land_budget_alert`).
