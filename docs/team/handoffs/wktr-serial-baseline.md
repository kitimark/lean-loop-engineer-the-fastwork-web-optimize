# wktr-serial-baseline handoff (round 2)

State: branch `worktree-wf_02bb7389-b52-1` (round 1 head b41fbc6b merged, then the fixes). CI branch `ci/wktr-serial-baseline` (db41542);
runs 39121950231 and 39121958562 (dispatched, green, assertions 15/15). No new CI runs in round 2.

## Result (MEASURED, note research/notes/2026/10-18-wktr-serial-baseline.md, ledger entry of the task)
- The `wktr-fixture-speed` claim "12 diffs are variance" is **UNEXPLAINED** at key level (arm, variant, count type): the unit is the key;
  no count-type reading decides. Rule declared first: rivals = 8 green wktr-fixtures runs with fixtures run, 9 passes x 13 cells, lane
  diff touching no measurement code (list with shas in the note); pair b 39075991405, c 39087188153 never in their own set.
- 9 of 12 diff keys vary among the 8 rivals; 3 do not (time-accel-f1: live-trace/layoutUpdates, live/compositingUpdates,
  live/layoutUpdates; quarantined in b and all rivals, stable only in c). Strict reading, rivals = the 2 new runs only: 10 of 12.
- 14 of 144 keys change kind among the 8 rivals (17 among all 10 green runs); 13 other count types hold 118 keys, 2 of them
  (control-f1/live layerFlushes, renderingUpdates) change kind in 39087202079 only. Failed run 39082884332 is out.
- Step time: ranges overlap, job contents differ (per pass and arm vs per pass and cell): no change detectable, not measured equal.
- Old handoff lines of wktr-fixture-speed ("12 differ INFERRED variance", "45 min serial") are superseded by the note.

## Code
- Lean `lean/Fw/Measure/WktrVariance.lean`: differs, varying, findings, Run, rivals, nBaselines (distinct ids), claim, pairDiffs,
  overlap (+ `overlap_iff`), rangeOf, typeOf (label only). Theorems `findings_nil_iff`, `findings_of_mem`, `findings_anti`,
  `claim_measured_iff`, `claim_needs_two`, `claim_repeat_not_measured`, `claim_baseline_free`. `findingsBy`/`claimBy` removed.
- Golden `packages/contracts/golden/measure/wktr.variance.jsonl` (`cd lean && lake env lean --run scripts/WktrVarianceGolden.lean [--check]`).
- JS `packages/measure-wktr/fixtures/variance.mjs` (CLI: `--base <src> --runs <src>,.. --cand <src>,.. --range name=1,2,3`; a source needs
  run.txt for the run id), `fixtures/runset.mjs` (run-set rule, **TS stand-in, no Lean spec**), tests `test/variance.test.mjs`, `test/runset.test.mjs`.
- Scope `--allow`: lean/Fw/Measure/WktrVariance.lean (the decision), lean/Fw/Wire/WktrVarianceGolden.lean and lean/scripts/WktrVarianceGolden.lean
  (golden generator), lean/Fw.lean (import), packages/contracts/golden/measure/wktr.variance.jsonl (generated golden). The task writes list
  has packages/measure-wktr/**, research/notes/**, research/findings/ledger.json only.

## Open
- Lean spec of the run-set rule (path predicate, lane diff) is missing; runset.mjs is the stand-in.
- c's 3 keys: chance (1 run in 10) or the speed code is not decided; more c-vintage runs would tell.
- The golden check is not in lean/scripts/check.sh (same as WktrFixturesGolden); `--check` is manual.
- Work-graph entry not edited (lead): add the paths above to `writes` if it should match.
