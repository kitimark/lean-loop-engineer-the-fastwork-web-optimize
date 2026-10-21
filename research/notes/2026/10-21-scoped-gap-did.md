---
id: 2026-10-21-scoped-gap-did
kind: note
title: "Does hero.exit:scoped lengthen the class-removal gap g on macOS WebKit morph? Pre-registered run-level permutation test, 5 scoped vs 5 A/A"
status: draft
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

(to be filled)
