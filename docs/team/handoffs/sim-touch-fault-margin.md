# sim-touch-fault-margin handoff (checkpoint 2: CI run done, landing checks)

Branch `worktree-wf_8b157c2a-318-1`; CI branch `ci/sim-touch-fault-margin` at 8cf84b94b (empty trigger commit, tags
`[ci:smoothness] [webkit-cadence] [earn-bound] [sim-only]`). Do not push to it again (one dispatch of two used).

## CI result (MEASURED, run 41357917479)
- 10 sim jobs started (rolling pool, 5 at once), 8 with a result file, 3 decisive (jobs 1, 2, 9), across-jobs end touch
  verdict (base, bound) `same`, not insufficient. Run 63 min, 239 job minutes.
- Dominant fault: touch driver not ready or lost, 6 of 10 jobs (jobs 7, 10 never ready in 480 s, early end at 644/761 s).
  Hang 1 (job 5).

## Done
- Lean `WalkBudget`: fault rate input, `jobsNeeded` 10, reach theorems, waves (`never_at_once`), driver fault, run 3 data
  (20 observed jobs, `lateRate` 5/15 -> 12 jobs for 4 in 5), window sample 318 (body 38 s, tail 383 s, `tailEvery` 17 derived).
- Plan boundaries moved with the new windows (3 arms: 6 reps to 17.1 min, 5 reps to 24.75 min). Not run on CI.
- Caps: derived sim row (`basis:"bound"`, measured 17 jobs, p90 39.2 min). Touch-lock `planLock`. Note section written.

## Open
- Final checks: check.sh (green before the window refresh, re-run), package tests, ci-paths, runner land-inputs, merge main,
  `fw plan lint`, dry land, `fw review ready`.
- Follow-up: size the next matrix at 12 jobs from `lateRate`; find why the driver start fails (host load?).

## Read first
`research/notes/2026/10-2x-sim-touch-reliable.md` section "Fault margin"; `lean/Fw/Measure/WalkBudget.lean`.
