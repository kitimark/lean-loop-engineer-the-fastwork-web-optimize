# wktr-serial-baseline handoff

State: branch `worktree-wf_d00caaf1-127-4`, CI branch `ci/wktr-serial-baseline` (sha db41542, no lane inputs changed).
Runs (wktr-fixtures, dispatched `jobs=3 passes=3 mode=auto`, both green, assertions 15/15): **39121950231**, **39121958562**.

## Result (MEASURED, detail in research/notes/2026/10-18-wktr-serial-baseline.md)
- Over 5 serial runs, 13 of 144 class-kind keys change kind: 5 layoutUpdates, 8 compositingUpdates; the other 11 count types
  (118 keys) never. Run pairs differ at 2..12 keys; the two new baselines at 2.
- Key-level claim "the 12 diffs are variance" with R = the two new baselines: **unexplained** (10 of 12 findings). Count-type
  level: **measured** (0 findings), a weaker reading added after the key-level result.
- Step time: 4 runs x 3 jobs, ranges overlap, spread 571..976 s: no per-job change detectable. Wall with max-parallel 2:
  25.1 / 26.2 / 23.4 min; the old serial-job run took 54 min by API (not 45).
- wktr-fixture-speed handoff lines "12 differ (INFERRED variance)" and "45 min serial" are superseded by the note.

## Code
- Lean `lean/Fw/Measure/WktrVariance.lean` (differs, varying, findings, findingsBy, claim, pairDiffs, overlap, rangeOf; theorems
  `findings_nil_iff`, `findings_of_mem`, `findings_anti`, `findingsBy_sub`, `claim_measured_iff`, `claimBy_of_claim`).
- Golden `packages/contracts/golden/measure/wktr.variance.jsonl` (`cd lean && lake env lean --run scripts/WktrVarianceGolden.lean [--check]`).
- JS port `packages/measure-wktr/fixtures/variance.mjs` (CLI: `--base <src> --runs <src>,.. --cand <src>,.. --range name=1,2,3`),
  test `packages/measure-wktr/test/variance.test.mjs`. Source = `<dir>/premise.json:<tag>` of artifact `wktr-fix-classes`, or a dir of
  `classes-*.txt` (old artifact).
- Scope: `--allow lean/Fw/Measure/WktrVariance.lean --allow lean/scripts/WktrVarianceGolden.lean` (the Lean decision, the task's
  writes list no lean path).

## Open
- A third and fourth baseline would shrink the pair-dependence; not run (no CI minutes spent beyond the two asked).
- The golden check is not in lean/scripts/check.sh (same as WktrFixturesGolden); `--check` is manual.
- Work-graph entry not edited (lead): add evidence and the Lean/golden paths to `writes` if it should match.
