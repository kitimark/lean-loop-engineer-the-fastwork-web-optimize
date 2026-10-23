# watch-ci-stale: a failed `gh run list` made finished runs read as in_progress

Status: CONFIRMED from `.fw-console/health.jsonl` (the watch's own inputs per pass).

## Cause
- `collectSystem` (apps/runner/src/watch-collect.ts, `gh run list --limit 20`, 10 s) goes through `chargedRunner`
  (watch-collect.ts:522-534). Any non-run result (budget `wait`/`stop`, `busy` after the 3 s lock wait, gh failure)
  returns `null`.
- On `null` the list is carried from the previous pass for up to `SCOPE.carryMs` = 1 h (watch-collect.ts:745-751), and
  only `system.stale` gets "ci". The carried runs keep `status: in_progress`; `ciSlowB` (Health.lean) measures
  `now - startedAt`, so the age keeps growing.
- Timestamps (UTC, land 39869394814 and lean 39869394794, started 23:04:46, both completed about 23:10):
  pass 23:06:13 stale=[docker] (fresh list, in_progress); passes 23:11:39, 23:16:44, 23:21:48, 23:27:01, 23:30:52 all
  stale=[docker, ci] with the same two runs still in_progress. ci.slow at 22 min (23:27) and 26 min (23:30).
- Why the call failed on every pass is not recorded (wait, stop and busy all give null). The dispatch-latency note
  names the gh-budget lock held across a whole gh process as the long wait; that fits but is INFERRED.

## Rule (Lean: Fw.Obs.GhStatus `ciAgeNote`, `ciFreshMs` = 240 s; Fw.Obs.Health `sCiSlow`)
A ci.slow detail ends with " (CI data N min old)" when the run list is older than two passes. Theorems
`ciAgeNote_fresh`, `ciAgeNote_old`, `ciSlowAlert_ages`; goldens "ci data age" in packages/contracts/golden/obs/health.jsonl.
TS: `SystemSnap.ciAt` (read time), `gh.ciAgeMs = now - ciAt` in `collectSnapshot`.

## Limits
GitHub list latency and the lock wait are outside this task. A finished run cannot close its alert while the list
cannot be read; the alert states the age instead. Follow-up: record the null reason per pass (wait/stop/busy).
