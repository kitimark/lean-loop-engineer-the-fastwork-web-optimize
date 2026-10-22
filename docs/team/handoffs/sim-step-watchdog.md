branch: worktree-wf_3501c97f-bb1-1 (CI branch: ci/sim-step-watchdog)
worktree: .claude/worktrees/wf_3501c97f-bb1-1 (under the repository root)
last commit: see `git log -1` on the branch (the CI request commit is the tip when a run is pending)
CI runs (webkit-sim, fault=hang by commit token):
- 39764068998 failure (expected, exit 6): watchdog line printed, Keep logs / Host state / upload-artifact / telemetry all ran, artifact
  webkit-sim-v1 has v1-session-1.log/.md and v1-host.txt. Found: the script's clock started 47 s after GitHub's step start (host
  load 552) and the grace loop counted iterations, not time (kill took 43 s, not 25 s).
- second run: see the report (after the fixes below).

State
- Wrapper: packages/measure-webkit/src/watchdog.mjs `run` (runBounded, endGroup): child in its own process group, TERM, grace,
  KILL (real-time waits), one `watchdog:` line (session, last `pass i/n` line, last output line, outcome; also appended to the
  stderr file), exit 6; forwards SIGINT/SIGTERM to the group (exit 130); ends leftovers of a command that exited. `hang` /
  `hang-child` is the fault stub (ignores SIGINT, SIGTERM, SIGHUP; has a child; never exits).
- Lean: lean/Fw/Measure/SimBound.lean section "The watchdog inside the measuring step": marginMin 3, stepStartMin 1 (Seen.stepStartS
  47), termGraceMs 20000, killWaitMs 5000, killMin 1, logTailMin 5, watchdogExit 6, watchdogMin = stepMin - marginMin; theorems
  watchdog_before_step_limit, watchdog_before_job_limit (each with a determinism and a quiet branch theorem), margin_covers_step_start,
  kill_fits, healthy_sessions_fit, setup_slack, watchdog_exit_distinct.
- Plan: Wire.lean measure.simPlan adds watchdogMin, termGraceMs; measure.simBounds adds watchdogExit, killWaitMs; goldens
  regenerated (lean/scripts/MeasureGolden.lean); simplan.mjs outputs watchdog_min, term_grace_ms; inspector.mjs BOUNDS (TS
  stand-in, golden-checked) holds watchdogExit and killWaitMs.
- Workflow: .github/workflows/webkit-sim.yml, step Determinism sessions: `wd` wraps every session command (determinism, quiet,
  lag); fault input `hang` (also commit token [fault:hang]) runs the stub under a 120 s deadline (the fault's own clock).

Limits: a VM that freezes completely stops the watchdog too and stays unobservable. The step timeout-minutes stays as the
backstop. logTailMin 5 is INFERRED; run 39764068998 ran its tail (Keep logs to telemetry) in 18 s.

Files outside the task writes: lean/Fw/Measure/Wire.lean, packages/contracts/golden/measure/measure.simPlan.jsonl and
measure.simBounds.jsonl (generated), packages/measure-webkit/src/simplan.mjs, src/inspector.mjs, test/simplan.test.mjs.
Read first: SimBound.lean watchdog section, watchdog.mjs `runBounded`, webkit-sim.yml `wd()`.
