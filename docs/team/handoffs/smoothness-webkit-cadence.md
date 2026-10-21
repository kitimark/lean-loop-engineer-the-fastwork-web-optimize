# smoothness-webkit-cadence handoff (round 2)

State: branch `worktree-wf_bf5b62d2-037-1`, CI branch `ci/smoothness-webkit-cadence`, leg code commit 8850e24d, data run 39634194664 (the one allowed re-run).
Read first: `research/notes/2026/10-2x-smoothness-webkit.md` (tables generated), then `lean/Fw/Measure/WebKitProfile.lean`.

Done (round 2)
- Render work = union of top-level Layout/Paint/RecalculateStyles intervals clipped to the window (Lean `renderWork_le_span`, `profile_work_le_span`);
  Composite is a count. TS twin `packages/measure-webkit/src/profile/reduce.mjs` against the golden `webkit-profile.jsonl`.
- Raw per-window Timeline records are kept (`mac.raw.json.gz`, `sim.raw.json.gz`, `src/profile/raw.mjs`); `report.mjs` re-reduces from them and writes ratio tables.
- smoothness.yml: `webkit-mac` (15 min) and `webkit-sim` (45 min) are matrices of 3 jobs, max-parallel 1. Caps rows 15/45 min, n=3, 111 / 342 dm.
- Old runs 39612238445, 39617081415, 39624728525 removed from `results/` (summed-Composite metrics, no raw); they stay in git history.

Verified: lean check.sh exit 0; measure-webkit 261, gate-breakpoints 594, ci-paths test 54 pass; ci-paths --check ok; runner tsc ok, land tests 62 pass.

Open
- Run 39634194664: mac job 3 hit the 15 min cap (no artifact, cause unknown, no log); sim job 1 refused (inspector probe failed), sim job 3 incomplete
  (9 windows, Safari relaunch ETIMEDOUT). So 2 mac jobs and 1 complete sim job: every `across` verdict is insufficient and class counts are empty.
  The ratios in the note are observations over 2 jobs, not a verdict. Next: a third complete job per leg (a new task, not this one).
- iOS hero zone, original: no window has a frame in the zone; needs an earlier window start.
- Caps are thin (n=3) and a mac job reached 15 min; re-derive after more runs.
- `fw ci push` refuses `widths=390` without `diagnostic` while the smoothness parser refuses `diagnostic`; this run was pushed with `git branch -f` + `git push origin`.
- `fw ci state` prints unknown for smoothness.yml runs on ci/ branches.
- Commit hook: node v24.22.0 `--check` rejects `.claude/workflows/build-review.js` (top-level return); commit with node v24.14.0 first on PATH.
- Phone comparison is task `ci-device-accuracy`.
