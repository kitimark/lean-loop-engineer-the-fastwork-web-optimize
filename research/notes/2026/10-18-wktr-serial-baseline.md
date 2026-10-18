# WKTR fixture lane: two serial baselines and the run-to-run variance (task wktr-serial-baseline)

Question: `wktr-fixture-speed` reported 12 of 144 class kinds that differed from an earlier run (all `layoutUpdates` or
`compositingUpdates`) and called it run-to-run variance (INFERRED). Is it?

## Method
- Two more serial runs of the same lane on CI, same inputs (`jobs=3 passes=3 mode=auto`, branch `ci/wktr-serial-baseline`, sha
  db41542): **39121950231** (26.2 min wall) and **39121958562** (23.4 min). Both green, lane assertions 15 of 15.
- A key is arm/variant/count type (144 of them); its value is the class kind (deterministic, stable, quarantined) from the passes
  pooled over the run's 3 jobs (9 passes), policy kMax 4, tMax 24.
- Rules in Lean (`lean/Fw/Measure/WktrVariance.lean`): `varying R` = keys whose kind is not the same in every run of R;
  `findings(b, c, R)` = diffs of baseline b and candidate c outside `varying R`; `claim` = measured only with 2 or more baselines
  and no finding. Port `packages/measure-wktr/fixtures/variance.mjs`, checked against 72 Lean golden lines.
- Pre-declared yardstick R = the two new baselines. The count-type yardstick (`findingsBy typeOf`: a diff is explained when its
  count type varies) was added after the key-level result below, so it is a weaker, post-hoc reading and is labelled so.

## Results (MEASURED)
| set | value |
|---|---|
| keys that change kind in any of the 5 serial runs | 13 of 144 |
| of them layoutUpdates / compositingUpdates | 5 / 8 |
| other 11 count types (118 keys) that change kind | 0 |
| diff count of the 10 run pairs | 12, 8, 7, 5, 6, 7, 9, 3, 5, 2 |
| new baseline A vs B | 2 (scroll-timeline-f3/live: layoutUpdates, compositingUpdates) |
| earlier pair 39075991405 vs 39087188153 | 12 (compositingUpdates 7, layoutUpdates 5) |

Verdicts (Lean `claim`, R = A and B):
| candidate vs baseline 39075991405 | diffs | key-level findings | claim | count-type findings | claim |
|---|---|---|---|---|---|
| 39087188153 (auto) | 12 | 10 | unexplained | 0 | measured |
| 39082884332 (k1) | 8 | 6 | unexplained | 0 | measured |

So: the 12 diffs are confined to the two noisy count types (MEASURED), but two baselines do not reproduce the specific keys: the
set of keys that flip changes from run to run. "Run-to-run variance" is MEASURED per count type, not per key; the key-level
claim stays unexplained with two baselines.

## Step time (per-job step "WKTR fixtures", s)
| runs | j1 / j2 / j3 | range |
|---|---|---|
| 39075991405 (before) | 687 / 751 / 874 | 687..874 |
| 39087188153 | 976 / 735 / 572 | 572..976 |
| 39121950231 | 889 / 588 / 809 | 588..889 |
| 39121958562 | 571 / 793 / 652 | 571..793 |

All four ranges overlap pairwise (Lean `overlap`): no per-job change from `wktr-fixture-speed` is detectable; the spread of 12 jobs
is 571..976 s. Wall time of a run with max-parallel 2: 25.1 (39087188153), 26.2, 23.4 min; the earlier serial-job run took 54 min
(API started to updated, including the classes job), not the 45 min of the old handoff.

## Limits
- Pairs are not independent (5 runs, 10 pairs share runs); no confidence interval is claimed.
- The 3 older runs ran at other commits (4e7eb90, 8e9d0bb, 208ef0f; the new ones at db41542). `git diff` between them touches
  the lane driver and spans (cli.mjs, wktr.mjs, spans.mjs) and a harness parameter `cases` that defaults to 0 (the scroll path is
  unchanged); that none of this moves a count is INFERRED, not isolated.
- Class kinds of 9 pooled passes near the policy edges flip by construction; a larger pooled sample per run would shrink the
  noise but is not measured here.
