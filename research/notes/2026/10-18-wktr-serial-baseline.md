# WKTR fixture lane: run-to-run variance of the class kinds (task wktr-serial-baseline, round 2)

Question: `wktr-fixture-speed` reported 12 of 144 class kinds that differed from an earlier run (all `layoutUpdates` or
`compositingUpdates`) and called it run-to-run variance (INFERRED). Is each of those 12 explained by variance?

**Result: UNEXPLAINED at key level.** 9 of the 12 diff keys also change kind between other same-lane runs; 3 do not
(`time-accel-f1` `live-trace/layoutUpdates`, `live/compositingUpdates`, `live/layoutUpdates`). The earlier "variance is MEASURED per
count type" of round 1 is withdrawn: it explained a key by another key of the same count type, which the rule below forbids.

## Rule

Declared before the round-2 counts (round 1 had already computed counts). The any `ci/*` reading was chosen in round 2;
the lead's strict `ci/wktr-*` reading gives 10 of 12 unexplained, also UNEXPLAINED.

- Unit: a key is arm/variant/count type (144 of them). Its value is the class kind (deterministic, stable, quarantined) from the 9
  passes of one run pooled over its 3 jobs (policy kMax 4, tMax 24). A diff key between base b and candidate c is **explained**
  only when that same key has different kinds among the rival runs. No other key, count type or pooled count explains it.
- Rival runs = every green `wktr-fixtures` run (any `ci/*` branch, all 33 runs of the workflow's history listed) that (a) ran the
  fixtures job (guard did not skip it) and (b) has 9 passes in each of the 13 cells, and (c) whose lane diff touches no measurement
  code. Lane diff = files changed from the merge base of its sha with the newest first-parent `main` commit before the run, to its
  sha. Measurement code = `packages/measure-wktr/**` except tests, README, `variance.mjs`, `runset.mjs`; `lean/Fw/Measure/Classes.lean`,
  `WktrLayout.lean`; `.github/workflows/wktr-fixtures.yml` (`fixtures/runset.mjs`, TS stand-in, no Lean spec yet).
- The pair under test (b, c) is never its own yardstick (Lean `rivals`, `claim_baseline_free`); rivals count once per run id
  (`nBaselines`, `claim_repeat_not_measured`); verdict `measured` only with 2 distinct rivals and no finding.

| run | branch | sha | lane diff touches measurement code | role |
|---|---|---|---|---|
| 39075991405 | ci/wktr-p1p4 | 4e7eb90 | yes (fixture pages, run.sh, summarize.mjs, workflow) | base b |
| 39087188153 | ci/wktr-fixture-speed | 208ef0f | yes (lanes, premise, run.sh, summarize, cli, spans, wktr, WktrLayout, workflow) | candidate c |
| 39087202079 | ci/sim-transient-retry | 9dcc516 | no | rival |
| 39101532073 | ci/integrate-ports-3 | b35b541 | no | rival |
| 39104956987 | ci/webkit-sim-rewrite | 96dcee0 | no | rival |
| 39106417484 | ci/gate-shard-balance | 088315d | no | rival |
| 39106547247 | ci/engine-model-fix | 898c416 | no | rival |
| 39119690413 | ci/gate-shard-balance-r3 | acc2a00 | no | rival |
| 39121950231 | ci/wktr-serial-baseline | db41542 | no | rival (this task, dispatched) |
| 39121958562 | ci/wktr-serial-baseline | db41542 | no | rival (this task, dispatched) |

Left out: 39082884332 (failed: j1 failed, j2 cancelled, no j3; its k1 table pools 6 passes per cell, not 9; its lane diff also
touches measurement code); 39105133788, 39108604579, 39109045346 (green, but the guard skipped plan and fixtures: no data);
8 cancelled and 11 skipped runs. Round 1 had used 39082884332 (13th varying key); it is dropped and every number is recomputed.
Run-set derivation: `node packages/measure-wktr/fixtures/runset.mjs '<id>|<sha>|<created>' ...`; tables: `variance.mjs`.

## Results (MEASURED, from the `wktr-fix-classes` artifacts of the 10 runs; 144 keys in each)
| set | value |
|---|---|
| keys that change kind among the 8 rival runs | 14 of 144 |
| keys that change kind among all 10 green runs | 17 of 144 |
| 28 pairs of the 8 rivals: diff keys per pair | 2 to 12 |
| b vs c | 12 |
| b vs each rival / c vs each rival | 3..10 / 4..14 |
| diff keys of b vs c explained (same key changes kind among the rivals) | 9 of 12 |
| diff keys not explained | 3 of 12: time-accel-f1/live-trace/layoutUpdates, time-accel-f1/live/compositingUpdates, time-accel-f1/live/layoutUpdates |
| claim (Lean `claim`, 8 rivals) | **unexplained** |

The 3 unexplained keys are `quarantined` in b and in all 8 rivals and `stable` only in c: c is the one run of 10 that differs
there. Dropping any one rival leaves 3 findings (5 without 39119690413); the verdict stays unexplained.
Sensitivity, same rule, rivals = only the two runs of this task (the strict `ci/wktr-*` reading): 10 of 12 unexplained.
Rivals without 39087202079 (7 runs): the same 3 unexplained keys. Whether c's 3 keys are chance (1 run in 10) or an effect of the
`wktr-fixture-speed` code is not decided here. 7 of the 8 rivals ran c's measurement code up to `cli.mjs` and `harness.mjs` (the
harness `cases` parameter, default 0, and the unused `premises.sh`; db41542 also differs in the workflow); that this moves no count
is INFERRED, not isolated. 39087202079 ran b's vintage, with a different workflow and summarize.mjs (lane state of main at 9dcc516).

## Descriptive only, not a verdict
Count types of the 144 keys: 15 (`layoutUpdates` and `compositingUpdates` 13 keys each, 13 other types with 118 keys). Keys that
change kind among all 10 green runs: compositingUpdates 8, layoutUpdates 7, layerFlushes 1, renderingUpdates 1. The two keys of the
other types, `control-f1/live` `layerFlushes` and `renderingUpdates`, are `stable` only in 39087202079 (one pass of j3 has 54
rendering updates instead of 53), `deterministic` in the other 9 runs. So the other count types are not constant either; the
earlier "never change kind" is wrong. No claim above reads this table.

## Step time (per-job step "WKTR fixtures", s; the 4 runs of round 1, not extended)
| runs | j1 / j2 / j3 | range |
|---|---|---|
| 39075991405 (b) | 687 / 751 / 874 | 687..874 |
| 39087188153 (c) | 976 / 735 / 572 | 572..976 |
| 39121950231 | 889 / 588 / 809 | 588..889 |
| 39121958562 | 571 / 793 / 652 | 571..793 |

The job contents differ: b's step is "fresh process per pass and arm", the later ones "per pass and cell", with another job split.
All four ranges overlap pairwise (Lean `overlap`, 3 samples each): no change in per-job step time is detectable. That is "no change
detectable", not a measured equality. Wall time of a run with max-parallel 2: 25.1 (39087188153), 26.2, 23.4 min; the earlier
serial-job run took 54 min (API started to updated, including the classes job), not the 45 min of the old handoff.

## Limits
- One run id with two tables is refused by variance.mjs only, not by the Lean claim.
- Pairs share runs and are not independent; no confidence interval is claimed.
- Rivals ran at 7 shas (two runs share db41542), of two code vintages (above). Only the lane-diff rule, not a tree identity, defines
  "same code".
- Class kinds of 9 pooled passes near the policy edges flip by construction; a larger pooled sample per run would shrink the noise.
- Step time is from the API step timestamps of 12 jobs; no phone time.
