# wktr-fixture-speed handoff

State: branch `worktree-agent-a2e0fff4749babb7b` (CI branch `ci/wktr-fixture-speed`), runs 39082884332 (probe k1 k2 k3, 2 jobs)
and 39087188153 (auto, 3 jobs, max-parallel 2). Both MEASURED on macos-26, 3 cores.

## Result
- Spans (per pass mean, k1): connect (launch) 2-4 s, run 6-7 s (2 s of it the settle), teardown 2-4 s: about 13 s per pass, 39
  passes = 520 s of a 570-970 s step. The rest: cold first boot 150-190 s + first install 7-57 s, then about 7 s per cell
  (ensureDevice, boot, install, teardown) x 13. Launch does not dominate; the cold boot is the biggest single item.
- k=2 processes in one VM LOSE: layout 1967 s against 903 s serial (job j2), per cell about 4.4x slower; in j1 the launch timed
  out (120 s) and the GPU process crashed. Class kinds also moved (layoutUpdates, compositingUpdates in live; ev_animTimelineInv,
  compositingUpdates in live-trace). So `heldTable` = only k=1; Lean: `parallel_no_gain` (k lanes that slow each other by >= k never win).
  k=3 never ran (j2 hit its 60 min limit); it can only be worse.
- Step time per job (WKTR step): before 687 / 751 / 874 s (run 39075991405); after 976 / 735 / 572 s (auto, run 39087188153): no
  per-job change, VM variance is +-200 s. Wall time of the 3 jobs: 45 min serial -> 24 min with max-parallel 2 (Lean: 5 - 2 webkit-sim - 1 gate-gaps).
- Counts: k1 and auto assert 15/15 (control 0, scroll-timeline 1, time-accel 0 recalcs/update, JS arms quarantined). Class kinds
  vs baseline: 132 of 144 equal; the 12 that differ are layoutUpdates / compositingUpdates (noisy types, INFERRED run-to-run variance).
- Item 5: launch is 3 s of 13; a cheaper launch (one process for several passes) would break "fresh process per pass": left alone.
  Open idea, not done: boot the device during the archive-extract step (up to ~50 s per job).

## Conventions
- Lean first: `lean/Fw/Measure/WktrLayout.lean` (layout, width gate, `layout_perm`, `layout_classes_eq`, `maxParallel`, `expects`);
  golden `packages/contracts/golden/measure/wktr.fixtures.jsonl` (`cd lean && lake env lean --run scripts/WktrFixturesGolden.lean [--check]`).
- Lane: `packages/measure-wktr/fixtures/lanes.mjs` (reads the golden), `premise.mjs` (assertions + premise + spans, in the classes
  job), `summarize.mjs --assert` (coordinator's line; ignores tags k2 k3). Dispatch inputs `mode` auto|probe, `req`.
- After editing the workflow: `cd lean && lake test -- --write-ci-trigger-golden` then `node scripts/ci-paths.mjs --write`.
- The work-graph `writes` of this task now list the Lean module, goldens, Trigger.lean and premise.test.mjs. Open: none.

