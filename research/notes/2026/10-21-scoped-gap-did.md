---
id: 2026-10-21-scoped-gap-did
kind: note
title: "Does hero.exit:scoped lengthen the class-removal gap g on macOS WebKit morph? Pre-registered run-level permutation test, 5 scoped vs 5 A/A"
status: final
created: 2026-10-21
authors: [agent:measure-engineer]
topics: [measurement, trajectory-probe, webkit, hero.exit, nav]
---

# Gap g under `hero.exit:scoped`: run-level test

Task `scoped-gap-did` (follow-up B of `10-21-scoped-close-start-cause`). Question: does the scoped exit lengthen the gap
g between the last nav sample with `is-morphing` (i) and the first without (j) on macOS WebKit morph? The earlier
numbers (permutation p 0.12 fresh, 0.013 pooled with the run that raised the question) were blocked by (run, width) and
treated cells as exchangeable; they are not the decision. The decision is the run-level test below, on 10 fresh runs.

## Runs and identification (read from every run's artifacts before any g was computed)

Ten `trajectory-probe` dispatches on `ci/scoped-close-start-cause`, all at one `headSha`
`82b10b3b84a283ee78bf3e9e06d05fc0dd98b96f`, event `workflow_dispatch`, conclusion `success`. The arm of a run is read from
`search`, `hash` and `baseHash` of the artifact `trajectory-apple` (`raw-playwright-webkit.json`), never from run order.
Every file has `reps` 5, widths 390, 640, 641, 1280 and arms `orig` (no config), `base` (no config), `cand` (the run's
`search`).

| run | `search` | `hash` | `baseHash` | arm |
|---|---|---|---|---|
| 39514533027 | `?fw=hero.exit:scoped` | 8d213de6fbdd52fd | ede2c7641aacf2d2 | scoped |
| 39514585897 | `?fw=hero.exit:scoped` | 8d213de6fbdd52fd | ede2c7641aacf2d2 | scoped |
| 39514619612 | `?fw=hero.exit:scoped` | 8d213de6fbdd52fd | ede2c7641aacf2d2 | scoped |
| 39515982760 | `?fw=hero.exit:scoped` | 8d213de6fbdd52fd | ede2c7641aacf2d2 | scoped |
| 39516056860 | `?fw=hero.exit:scoped` | 8d213de6fbdd52fd | ede2c7641aacf2d2 | scoped |
| 39514655614 | `?fw=hero.exit:faithful` | ede2c7641aacf2d2 | ede2c7641aacf2d2 | A/A (faithful) |
| 39514696773 | `?fw=hero.exit:faithful` | ede2c7641aacf2d2 | ede2c7641aacf2d2 | A/A (faithful) |
| 39514734504 | `?fw=hero.exit:faithful` | ede2c7641aacf2d2 | ede2c7641aacf2d2 | A/A (faithful) |
| 39516021307 | `?fw=hero.exit:faithful` | ede2c7641aacf2d2 | ede2c7641aacf2d2 | A/A (faithful) |
| 39516092834 | `?fw=hero.exit:faithful` | ede2c7641aacf2d2 | ede2c7641aacf2d2 | A/A (faithful) |

5 scoped and 5 faithful: the gate "5/5" holds, so the analysis goes ahead. MEASURED (artifacts; the same rule is Lean
`Fw.Gate.RunPerm.identify`, which refuses any other split).

## Pre-registration (fixed before any g statistic was computed; no change after the data)

1. **Cells.** `closeCells` of `packages/gate-breakpoints/src/trajectory/closegap.mjs` on `raw-playwright-webkit.json` of the
   `trajectory-apple` artifact (mac-webkit morph), widths 390, 640, 641 and 1280, arms `orig`, `base`, `cand`, reps 0 to 4.
   A close without a sample that has `is-morphing` or without a following sample is skipped by `closeCells`; no cell is
   added or dropped by us. (Cell counts are in the result section; they were read from the files, not g.)
2. **Statistic per run.** For run r and width w: `d(r,w) = mean ln g over the cand cells - mean ln g over the orig and base
   cells pooled` (g in ms, natural log). `D(r) = mean over the 4 widths of d(r,w)`. This is `blockDiffs` of
   `closegap.mjs`, averaged over widths.
3. **Test statistic.** `T = mean D(r) over the 5 scoped runs - mean D(r) over the 5 faithful runs`.
4. **Reference distribution.** Exact permutation of the arm labels over the 10 runs: all C(10,5) = 252 ways to name 5
   runs "scoped". The observed labeling is one of them.
5. **One-sided alternative.** scoped > faithful. `p = #{labelings L with T(L) >= T_obs} / 252`, the observed labeling
   counted. The `D(r)` are rounded to integers in units of 1e-9 before the permutation, so the comparison is exact in
   integers and carries no float tie.
6. **Threshold.** alpha 0.05. With 252 labelings `p < 0.05` iff the count is at most 12 (12/252 = 0.0476, 13/252 =
   0.0516).
7. **Decision.** `p < 0.05`: perf regression CONFIRMED; open a part-fix task that profiles the class-removal frame. Else:
   "not shown at 5 vs 5", with the minimum detectable effect (MDE) in log g.
8. **MDE method** (fixed now). Pooled within-group SD `s` of `D(r)` (8 degrees of freedom: the two groups' variances
   averaged). `MDE = (t(0.95, 8) + t(0.80, 8)) * s * sqrt(1/5 + 1/5)` with `t(0.95, 8) = 1.8595` and `t(0.80, 8) =
   0.8889`: the effect of a one-sided two-sample t-test at alpha 0.05 that has 80 % power. A normal-theory
   approximation of the permutation test's power (the noncentral t is not used). Reported also as the ratio `exp(MDE)` of
   geometric-mean gaps.
9. **No more runs.** These 10 runs are the whole sample (optional stopping is the threat). No judge or part change here.

## Result

Correction to the identification paragraph (descriptive, not part of the statistic; the pre-registered text stays as committed): the `base` arm carries no search but has config hash = `baseHash` (ede2c764); only `orig` has no config.

**Decision: not shown at 5 vs 5.** `p = 124/252 = 0.492` (one-sided, scoped > faithful). The perf regression is not
confirmed; the test could only have seen a rise of the run-level mean of ln g of about **0.31** (g about 37 % longer) or
more. Computed in Lean (`Fw.Gate.RunPerm`, golden `run-perm.jsonl` lines `real-run` and `real`), MEASURED.

| run | arm | cells | D(r) (ln g, cand minus orig+base) |
|---|---|---|---|
| 39514533027 | scoped | 60 | +0.2026 |
| 39514585897 | scoped | 60 | -0.1349 |
| 39514619612 | scoped | 59 | +0.0920 |
| 39515982760 | scoped | 60 | -0.1489 |
| 39516056860 | scoped | 59 | -0.2574 |
| 39514655614 | faithful | 60 | -0.0512 |
| 39514696773 | faithful | 60 | +0.1650 |
| 39514734504 | faithful | 60 | -0.2990 |
| 39516021307 | faithful | 60 | +0.0312 |
| 39516092834 | faithful | 60 | -0.0988 |

| quantity | value |
|---|---|
| mean D, scoped (5 runs) | -0.0493 (sum -246 635 992 e-9) |
| mean D, faithful (5 runs) | -0.0506 (sum -252 850 405 e-9) |
| T = scoped minus faithful | +0.0012 (25 T = 31 072 065 e-9) |
| labelings with T >= T_obs | 124 of 252 |
| p | 0.492 |
| pooled within-group SD of D (8 df) | 0.181 |
| MDE, 80 % power, one-sided 5 % | 0.314 in ln g (ratio exp = 1.369) |

Two runs have 59 cells, not 60 (`closeCells` found no following sample once: scoped 39514619612 cand at 641, scoped
39516056860 base at 641); the pooled means absorb it.

What the numbers say, and do not:

1. The scoped and the A/A runs have the same mean (T = +0.001). Rejecting needed the observed T to be among the 12
   highest of 252; it is 124th, the middle of the permutation distribution.
2. The earlier per-width rises (scoped minus orig+base 0.68 at 390 in 39508414669, 0.64 in 39466179818) do not reappear.
   Descriptive only, not part of the test: mean of the 5 per-run block differences at 390 is -0.103 scoped against
   -0.134 faithful; at 640 +0.061 against -0.232; at 641 -0.076 against +0.167; at 1280 -0.080 against -0.003. The
   widths differ in sign between the two groups; with run-to-run SD 0.18 that is noise.
3. Geometric-mean gap by arm over all runs (ms): scoped runs orig 45.2, base 47.8, cand 44.1; A/A runs orig 40.7,
   base 49.1, cand 42.5. The scoped candidate has no longer gap than the original arm in the same runs.
4. The MDE is the answer to "what could this sample have caught": a shift of 0.31 in ln g or more. A smaller lengthening
   (say 10 to 20 %) is not excluded by this sample; it was never the pre-registered claim. The MDE is the normal-theory
   t formula of the pre-registration, an approximation of the permutation test's power.
5. The test pools the four widths, so a rise confined to one width is diluted by a factor 4 in D. No such rise is
   visible in point 2.

## What follows

- No part-fix task is opened: the class-removal gap is not shown longer under `hero.exit:scoped`. Perf question (B) of
  `10-21-scoped-close-start-cause` is closed as "not shown at 5 vs 5, MDE 0.31 in ln g".
- The close-start colour (`bgRed(m_prev)`) and the earn start rule (C) are untouched by this result.
- No more runs on this question (optional stopping). A new question (a smaller effect) would need a new pre-registration
  with its own sample size from the SD 0.181 above.

## Lean statements behind the numbers

`Fw.Gate.RunPerm` (all in `lean/Fw/Gate/RunPerm.lean`, golden-checked by `lean/scripts/check.sh`):

- `identify` and its five theorems (`identify_scoped`, `identify_faithful`, `identify_scoped_same_hash`,
  `identify_faithful_other_hash`, `identify_other_search`): the arm comes from `search`, `hash`, `baseHash` only;
  `balanced_false_of_none`: one unidentified run makes the set unbalanced.
- `runNano` (`Float`): D in units of 1e-9. `tScaled_le_iff`: ordering the labelings by T is ordering them by the scoped
  sum, so the permutation runs in exact integers.
- `choose_length`, `total_ten_five`: 252 labelings. `mem_choose`, `count_pos`: the observed labeling is counted, so
  p >= 1/252. `count_le_total`: p <= 1.
- `verdict_confirmed` (count <= 12), `verdict_notShown` (count >= 13), `verdict_min`: the test can reject at 5 vs 5.

The TS file `closegap-did.mjs` parses the raw files to `run-perm-cells.jsonl` (`[width, role, g]` per cell) and holds a TS
stand-in of the same functions; `closegap-did.test.mjs` checks the stand-in and the parse against the golden,
and the stand-in reproduces Lean's per-run D (to 1e-9), count 124, sums, SD and MDE on the 10 real runs.
