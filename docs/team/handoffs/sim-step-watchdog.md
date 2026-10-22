branch: worktree-wf_3501c97f-bb1-1 (CI branch: ci/sim-step-watchdog)
worktree: .claude/worktrees/wf_3501c97f-bb1-1 (under the repository root)
last commit: e0edaefd (code); the CI request commit follows it
CI runs: none pushed yet (updated after the push)

State
- Wrapper: packages/measure-webkit/src/watchdog.mjs `run` (runBounded, endGroup): child in its own process group, TERM, grace,
  KILL, one `watchdog:` line (session, last `pass i/n` line, last output line, outcome), exit 6; also forwards SIGINT/SIGTERM
  to the group (exit 130) and ends leftovers of a command that exited. `hang` / `hang-child` is the fault stub (ignores
  SIGINT, SIGTERM, SIGHUP; has a child; never exits).
- Lean: lean/Fw/Measure/SimBound.lean section "The watchdog inside the measuring step": marginMin 2, termGraceMs 20000,
  killWaitMs 5000, killMin 1, logTailMin 5, watchdogExit 6, watchdogMin = stepMin - marginMin; theorems
  watchdog_before_step_limit, watchdog_before_job_limit (each with a determinism and a quiet branch theorem), kill_fits,
  healthy_sessions_fit, setup_slack, watchdog_exit_distinct.
- Plan: Wire.lean measure.simPlan adds watchdogMin, termGraceMs; measure.simBounds adds watchdogExit, killWaitMs; goldens
  regenerated (MeasureGolden.lean); simplan.mjs outputs watchdog_min, term_grace_ms.
- Workflow: .github/workflows/webkit-sim.yml, step Determinism sessions: `wd` wraps every session command (determinism,
  quiet, lag); fault input `hang` (also commit token [fault:hang]) runs the stub under a 120 s deadline.

Limits: a VM that freezes completely stops the watchdog too and stays unobservable. The step timeout-minutes stays as the
backstop. logTailMin 5 is INFERRED until the fault run shows the tail time.

Open: see the report (files outside the task writes: Wire.lean, the two goldens, simplan.mjs, simplan.test.mjs).
Read first: SimBound.lean watchdog section, watchdog.mjs `runBounded`, webkit-sim.yml `wd()`.
