# timing-alert handoff
State: committed on branch worktree-agent-ac8aadcd3f9849905 (see git log). Runner 318 tests, console-web build, lean check.sh green.

Done
- Lean (lean/Fw/Obs/Next.lean): Branch.onMain/landLock, settled/locked; theorems no_unlanded_once_on_main,
  no_unlanded_while_locked, alert_suppressed_iff_locked; slowSteps (+ dedupL, slowLatest_sound, slowSteps_nodup,
  slowSteps_latest, slowSteps_of_timing). Wire (lean/Fw/Wire/Obs.lean): ops obs.timing, obs.slow; branch codec carries
  onMain/landLock; next.jsonl golden regenerated (55 cases).
- Glue: apps/runner/src/next.ts (landCommitOnMain, liveLandLockBranch, slowAlerts, slowNextLines), watch.ts (slowFor),
  watch-collect.ts (parseSamples/readSamples). Tests: apps/runner/test/timing-alert.test.ts (23).
- Console: Timings card in apps/console-web/src/Health.tsx renders timing.slow alerts from the health payload.
- Ledger: inc-watch-unlanded-after-land, inc-watch-alert-during-land (status fixing).

Open / limits
- A task respawned with new commits after an earlier land counts as onMain (Task: trailer matches) until it lands again.
- Panel shows only slow steps (no per-step history): a per-step table needs a console-api route (outside this task).
- Regenerate next.jsonl via Fw.Wire.Obs.NextGolden.run when the Branch codec changes.
Read first: lean/Fw/Obs/Next.lean (timing-alert section), apps/runner/src/next.ts.
