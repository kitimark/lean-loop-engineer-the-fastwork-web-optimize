# Handoff: sim-transient-retry

State: branch `worktree-agent-abe56fcd3837a3f16` (CI branch `ci/sim-transient-retry`). Task: transient `simctl` errors
(ETIMEDOUT, device not ready, ...) are asked again by a Lean policy; permanent ones are not.

Read first: `lean/Fw/Measure/Retry.lean` (docstring), then `packages/measure-webkit/src/simretry.mjs`.

## What is there
- `lean/Fw/Measure/Retry.lean`: `classify` (lower-case marker list `transientMarkers`), `shouldRetry c a n` (transient and
  a < n), `wait a` = min(30000, 2000 * 2^(a-1)) ms, `plan`/`outcome` over a failure sequence. Proved: `retry_terminates`
  (retries <= n - a), `permanent_never_retried`, `plan_permanent`, `plan_transient_exact`, `delay_le_cap`,
  `delay_ge_base`, `delay_mono`, `plan_wait_le` (total wait <= 30000 (n - a)), `classify_transient_iff`.
- Ops `measure.retry` and `measure.retryPlan` in `lean/Fw/Measure/Wire.lean`; goldens
  `packages/contracts/golden/measure/measure.retry.jsonl`, `measure.retryPlan.jsonl` (from `Golden.lean`;
  regenerate: `cd lean && lake env lean --run scripts/MeasureGolden.lean`).
- TS stand-in `src/simretry.mjs` (rule copy, checked against the goldens in `test/fwcore.test.mjs`; loop `withRetry`
  tested in `test/simretry.test.mjs`). `src/sim.mjs`: `simctlRetry` wraps boot, bootstatus, launch (replaces the
  blind 3x loop), openurl (max 2), shutdown; waits with `Atomics.wait`.
- Workflow `.github/workflows/webkit-sim.yml` untouched (it already triggers on `packages/measure-webkit/**`).

## Facts
- The real ETIMEDOUT text is `r.error.code` of a killed `spawnSync` (`tail()` in sim.mjs returns it). The log of run
  39068024107 holds no simctl text (the step ran into its 50 min limit); the marker list is from simctl behaviour
  (INFERRED), not from that log.
- A retried `simctl boot` after a timeout may answer "Unable to boot device in current state: Booted": transient by
  the list, so it costs 2 s + 4 s before the existing state check passes. Accepted.

## Open
- TS stand-in of `classify`/`wait` stays until `fwcore` is callable from the harness at run time.
- CI shows no regression only; a real transient error is rare on CI, so the retry path is covered by tests, not by a run.
