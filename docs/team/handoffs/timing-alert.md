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

Mistake (merge, land-timing-ceiling f51cf4c): two branches correct alone, wrong together, no textual conflict. Main added
Params.ceilings; my obs.timing wire decoder (Fw.Wire.Obs.Timing.paramsOf) did not decode it, so ceilings were dropped
(lock held 5 s read as 30 s noBaseline). Fixed: paramsOf decodes ceilings; test replays every timing.jsonl row incl. ceiling rows.
Lesson: a wire decoder must be checked against the golden of every field of the type it decodes, after each merge.
