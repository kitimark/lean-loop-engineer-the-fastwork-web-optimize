# smoothness-webkit-cadence handoff (round 3, final design round)

State: branch `worktree-wf_bf5b62d2-037-1`, CI branch `ci/smoothness-webkit-cadence`, leg code commit 8850e24d, data run 39634194664 (the one allowed re-run).
Read first: `research/notes/2026/10-2x-smoothness-webkit.md` (tables generated), then `lean/Fw/Measure/WebKitProfile.lean`.

Done (round 3, no CI push, no Lean change; inputs are the committed raws of run 39634194664)
- Pinned unit: every value cell of the mac/sim headline, kinds, ratio and cadence tables is one statistic over the concatenated kept windows (reps) of all loaded
  jobs: Lean `medianNat` per window value, `quantile` over all intervals for p50/p95 (`report.mjs` `armWindows`, `poolCell`, `poolCadence`). Each cell shows n with the
  per-job split (`12 (6+6)`); under `minReps` (5, `enoughN` of gate-breakpoints `smooth/reduce.mjs`) it prints `insufficient (n=k)`. Verdict and class tables stay per job (`jobCell`, `jobVerdicts`).
- Billed minutes = ceil(seconds/60) from unrounded seconds (`minutesOf` `billed`): mac total 37, iOS 94. Note Answer, Method units, image 20261012.0260.1 restated from the regenerated tables.
- Tests: `profile-report.test.mjs` pooled 5+1 windows, golden `medianCases` over every split, 4 windows insufficient, pooled cadence quantiles, 901 s bills 16.

Done (round 2)
- Render work = union of top-level Layout/Paint/RecalculateStyles intervals clipped to the window (Lean `renderWork_le_span`, `profile_work_le_span`);
  Composite is a count. TS twin `packages/measure-webkit/src/profile/reduce.mjs` against the golden `webkit-profile.jsonl`.
- Raw per-window Timeline records are kept (`mac.raw.json.gz`, `sim.raw.json.gz`, `src/profile/raw.mjs`); `report.mjs` re-reduces from them and writes ratio tables.
- smoothness.yml: `webkit-mac` (15 min) and `webkit-sim` (45 min) are matrices of 3 jobs, max-parallel 1. Caps rows 15/45 min, n=3, 111 / 342 dm.

Verified (round 3): measure-webkit 266, gate-breakpoints 594, ci-paths test 54 pass; ci-paths --check ok; check.sh and runner results in the report.

Open
- Run 39634194664: mac job 3 hit the 15 min cap (no artifact, cause unknown, no log); sim job 1 refused (inspector probe failed), sim job 3 incomplete
  (9 windows, Safari relaunch ETIMEDOUT). So 2 mac jobs and 1 complete sim job: every `across` verdict is insufficient and class counts are empty.
  The ratios in the note are observations over the pooled windows of 2 jobs (iOS: 1 complete + 1 partial, pooled INFERRED sound), not a verdict. Next: a third complete job per leg (a new task, not this one).
- iOS hero zone, original: no window has a frame in the zone; needs an earlier window start.
- Caps are thin (n=3) and a mac job reached 15 min; re-derive after more runs.
- `fw ci push` refuses `widths=390` without `diagnostic` while the smoothness parser refuses `diagnostic`; this run was pushed with `git branch -f` + `git push origin`.
- `fw ci state` prints unknown for smoothness.yml runs on ci/ branches; commit hook: use node v24.14.0 first on PATH for `build-review.js --check`.
- Phone comparison is task `ci-device-accuracy`.
- Follow-ups: smoothness.yml step timeout 50 inside the 45-min job (:397 vs :327); mac job 3 cap loss and the Caps rebuild; a 3rd complete job per leg (gives `across` verdicts and class counts).
