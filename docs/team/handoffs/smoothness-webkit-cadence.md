# smoothness-webkit-cadence handoff

State: branch `worktree-wf_bf5b62d2-037-1`, CI branch `ci/smoothness-webkit-cadence`. Final leg code = commit 03941815 (runs 39612238445,
39617081415, 39624728525 ran it unchanged; the later commits only touch the report). No CircleCI.
Read first: `research/notes/2026/10-2x-smoothness-webkit.md` (tables are generated), then `lean/Fw/Measure/WebKitProfile.lean`.

Done
- Lean `Fw.Measure.WebKitProfile` + golden; TS twin `packages/measure-webkit/src/profile/{reduce,recorder,sim-cadence,report,cli}.mjs`;
  macOS leg `packages/gate-breakpoints/src/smooth/webkit-cadence.mjs`; smoothness.yml jobs `webkit-mac`, `webkit-sim` (only on `[webkit-cadence]`).
- Caps rows `smoothness-webkit-mac` (26 min) and `smoothness-webkit-sim` (65 min); measured wall 10.4 / 34.1 min median over 3 runs.
- Overflow width of smoothness.yml raised 12 -> 14 (`lean/Fw/Ci/Overflow.lean`, outside the graph writes: needed by apps/runner land-overflow-widths test).
- Results: `results/smoothness-webkit/` (raw leg files per run, `jobs/`, generated `tables.md`, `summary.json`). Regenerate with the command in the note's Method.

Verified (final commit): `sh lean/scripts/check.sh` exit 0; measure-webkit tests 185 pass; gate-breakpoints tests 594 pass; ci-paths test and `--check` ok;
apps/runner tsc and land-inputs + land-overflow-widths tests pass (full runner suite: only the widths test failed before the Overflow fix).

Open
- iOS hero zone, original: 6 of 14 windows have a frame in the zone (at most 3 per job), per-job verdict insufficient. Needs a hero window that
  lands >= 5 frames per job on the original, or more jobs.
- iOS job of run 39624728525 died in its fourth rep (Safari relaunch failed, simulator Shutdown); 29 of 40 windows kept.
- `fw ci push` refuses `widths=390` without `diagnostic`, but the smoothness line parser refuses `diagnostic`; push with `git branch -f ci/<x> HEAD` + `git push origin ci/<x>`.
- Phone comparison is task `ci-device-accuracy`.
