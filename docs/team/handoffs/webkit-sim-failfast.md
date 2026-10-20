# Handoff: webkit-sim-failfast (branch worktree-wf_d864cd42-ccc-2, CI branch ci/webkit-sim-failfast)

Task: a dead Simulator inspector ends a webkit-sim job fast; per-session step timeout; cancelled jobs skip trailing steps.
Read first: research/notes/2026/10-20-macos-pool-v2.md (fixes 3, 4, 5, 6).

State
- Lean `lean/Fw/Measure/SimBound.lean` (new, imported in Fw.lean and Fw/Measure/Wire.lean): `perSessionMin` 35, `quietStepMin` 50,
  `tailMin` 10, `stallMs` 360000, `stepMin`, `jobMin`; `dead`, `act` (proceed / relaunch / giveUp), `run`, `deadExit` 4.
  Theorems: step follows sessions, mono, one session < 50, job <= 6 h, relaunch at most once, giveUp is last, relaunch time <= one relaunch.
- Wire: `measure.simPlan` reply gained `stepTimeoutMin`, `jobTimeoutMin`, `stallMs`; new op `measure.inspector`. Goldens regenerated
  (`measure.simPlan.jsonl`, new `measure.inspector.jsonl`) with `lake env lean --run scripts/MeasureGolden.lean`.
- TS: `packages/measure-webkit/src/inspector.mjs` (stand-in of `act`, checked against the golden in test/fwcore.test.mjs);
  `session.mjs` `ensureProxy` (socket check, refusal count, relaunch once via `sim.mjs` `launchSafari`, then InspectorDeadError);
  `cli.mjs` exits with `e.exitCode` (4 for a dead inspector, 3 for the stall watchdog, 1 otherwise); `simplan.mjs` outputs `step_min`, `job_min`, `stall_ms`.
- Workflow `webkit-sim.yml`: job and step `timeout-minutes` from the plan outputs; `FW_WK_STALL_MS` from the plan (6 min);
  Keep logs, Shut down and upload steps use `!cancelled()` instead of `always()`. Telemetry `finish` steps still use `always()`.

TS stand-ins (not Lean-checked): the refusal counter and the relaunch sequence in `session.mjs` (glue; the decision is Lean's).
Not tested locally: the relaunch path itself (needs a dying inspector); the CI pair shows the unchanged green path only.
Accepted limits: why the inspector dies is undiagnosed; one CI pair.

CI (push runs, default config: target original, 1 VM, 1 session)
- Reference green run 39102911639 (main push, 10-18): sim job 18.1 min. Two more green originals for spread: 39101532190, 39087202086.
- 39426562165 (head 183100a2): determinism step failed at 23 min (cause unknown, no log: the job ended by its timeout, so GitHub kept none);
  then "Keep logs" hung 28 min on a wedged CoreSimulator. Job timeout 45 (from the plan) fired, cancel took 10 min more. Fix: 3-min step
  timeouts on Keep logs and Shut down, logs copied before host commands, `simctl list` bounded by an alarm (head 056de8de).
- 39435518921 (head 056de8de): green, sim job 19.0 min (determinism 14.7 min). Class tally 30 quarantined / 59 deterministic / 14 stable
  (103 rows); the three older greens: 33-35 / 57-58 / 11-15 (103-104 rows). Not equal: single-session tables vary run to run
  (7 of 103 rows change class vs 39102911639, only 1 into deterministic; the "(gone)" row exists in 2 of 3 baselines).
  Needs >= 3 runs on separate jobs before any class claim.
- The relaunch and give-up paths did not fire in 39435518921 (no "relaunching" or "stalled" line in the session log).
