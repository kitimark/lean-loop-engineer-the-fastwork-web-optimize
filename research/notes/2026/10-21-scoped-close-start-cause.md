---
id: 2026-10-21-scoped-close-start-cause
kind: note
title: "The nav close starts at bgRed(m_prev) in every arm: the close-start colour is an identity, and the bg and earn close@0 failures appear in A/A too"
status: final
created: 2026-10-21
authors: [agent:measure-engineer]
topics: [measurement, trajectory-probe, webkit, hero.exit, nav]
---

# Close-start colour of `nav.background-color` under `hero.exit:scoped`

Task `scoped-close-start-cause`, round 3 (final design round). Question: on macOS WebKit morph the flag-alone candidate
starts the close `nav.background-color` low (red 226.5 at 390 in run 39466179818) while the original passes start at 249
to 252. Is it (a) a part fix, (b) timing only, or (c) a look change? Each claim below is judged on its own.

## Answer

1. **The close-start colour is `bgRed(m_prev)`, an identity in every arm.** In 240 of 240 cells (4 runs x 3 arms x 4
   widths x 5 reps) the red at the first sample without `is-morphing` (sample j) is within 0.38 red of `bgRed m`, `m`
   the morph value of the last sample with the class (sample i). MEASURED. The rule is `closeStartOk reading m :=
   |reading - bgRed m| <= 1/2` (Lean `Fw.Parts.HeroExitCloseStart`); `closegap.mjs` check 3 applies it to every cell
   and is golden-checked against Lean. Output of the 4 runs, committed:
   `10-21-scoped-close-start-cause.closegap-output.txt`.
2. **The bg and earn close@0 failures appear in A/A too.** The start is bgRed(m_prev). A longer g permits a darker start
   (m_prev <= prevBound g, Lean prev_le_bound / redFloor_anti) but does not fix it: 185.6 at g 178 (A/A 390 rep 0, m_i
   407e-4); 249.9 at g 175 vs 212.6 at g 154 (scoped 390 reps 0 and 2). bg close@0 fails in A/A as new (390); earn
   close@0 fails in A/A only as both (640 max-width, base fails too).
3. **This task takes none of (a), (b), (c).**
   - (a) part fix: waits on the perf question (B), below.
   - (b) timing only: refuted for the judge as written. The judge's close@0 comparison fails the A/A candidate at 390
     (bg `new`) and, in the scoped run, fails the base arm too (bg 390 `both`), so "timing only, the judge passes it" does
     not hold; a judge rule is its own task (A).
   - (c) is excluded at equal m_prev: the start is the same function bgRed of m_prev in every arm (identity, 240/240).
     Whether scoped shifts m_prev (through g or frame timing) is B.
4. **Perf question (B): INFERRED, open.** See the Perf section. Not answered here.
5. **Earn.** `earn.opacity` and `earn.max-width` close@0 are what fail the scoped run (`new` at 390 and 641). They are
   not an identity in `m`. INFERRED: mostly `g`-driven, with exceptions (Earn section). The earn start rule (C) is not
   derived here.

## Identity of the runs (read from every arm's `search` and hash in the raw files)

| run | candidate arm `?fw` | candidate hash | base hash | original arm |
|---|---|---|---|---|
| 39508414669 (fresh, ci/scoped-close-start-cause @6068371) | `hero.exit:scoped` | 8d213de6fbdd52fd | ede2c7641aacf2d2 | no config |
| 39508421419 (fresh, A/A) | `hero.exit:faithful` | ede2c7641aacf2d2 | ede2c7641aacf2d2 | no config |
| 39466179818 (stored, flag-alone; the run that raised the question) | `hero.exit:scoped` | 8d213de6fbdd52fd | ede2c7641aacf2d2 | no config |
| 39472217441 (stored, A/A) | `hero.exit:faithful` | ede2c7641aacf2d2 | ede2c7641aacf2d2 | no config |

Both fresh dispatches printed the same id (known bug `fw-run-dispatch-pick`), so each run is named by its arms. Lean
outcome lines (mac-webkit): 39508414669 hero pass, morph FAIL; 39508421419 hero pass, morph PASS; Linux hero pass in
both. In 39508414669 bg `close@0` at 390 is `both` (the base fails it too) and `new` only at 641; the FAIL comes from
`earn.opacity` and `earn.max-width` close@0 `new` at 390 and 641 (`units-playwright-webkit.json`; outcome rule
`Fw.Gate.Trajectory`: a group is `new` at 2 or more widths).

## Mechanism

1. The close tween is `m = (1 - e/680)^3` (`closeAt_cube`). The nav drops `is-morphing` once `m <= 0.001`, at
   `e >= 612`, 68 ms before the end (`morphing_of_lt`, `not_morphing_of_ge`).
2. The background colour is `color-mix(in srgb, #ffffff1a, #131922)` driven by `--morph`, declared on `.nav` without a
   condition (`apps/site/src/parts/nav/nav.module.css:22-26`). The mix is premultiplied: alpha `26/255 (1-m) + m`
   (`bgAlpha`), premultiplied red `26 (1-m) + 19 m`, so the red the probe reads is `bgRed m`. `bgRed` falls strictly from
   255 at m = 0 to 19 at m = 1 (`bgRed_lt`, `bgRed_le_iff`). A `background-color` transition (0.7 s) exists only on
   `.nav:not(.is-morphing)` (lines 41-48). Above 640 px and when not is-on-dark, that rule's target switches to `#ffffff7a` / `#ffffff38`
   (media block, nav.module.css:55-62); otherwise the target stays the color-mix and keeps following --morph.
3. When the class goes, the transition starts. WebKit's before-change style is the style of the previous style-change
   event, so the start colour is `bgRed(m_prev)`, `m_prev` the morph value of the last frame that saw the class
   (`Source/WebCore/style/Styleable.cpp:603-617@862f17d`). CONFIRMED on the pinned clone; the CI Playwright WebKit build
   differs, so for CI it is INFERRED. The ordering of this against the running tween inside `StyleTreeResolver` is not
   claimed.
4. A longer g lets the last morphing frame lie earlier on the tween, so it bounds m_prev from above (prevBound g); the
   start is darker only when m_prev actually is larger.
5. Over the model `Fw.Parts.HeroExitOpt.frameWrites`, the scoped exit writes `--exit-opacity` and `--exit-scatter` on
   hero elements and none the nav background reads (`scoped_writes_miss_nav_bg`, `scoped_writes_miss_nav_elements`). The
   model is not the whole driver: `driver.ts:37` also sets `pointerEvents` on the hero (not on the nav). The model gives
   the part no way to change the nav's style; whether it changes frame time is the perf question.

## Check 3: the identity, per cell

`closeStartOk (red_j) (m_i / 10000)` over every cell of every arm (the raw files hold m in units of 1e-4):

| run | cells passing | max abs(red_j - bgRed m_i) | max abs(red_i - bgRed m_i) | max abs(red_j - red_i) |
|---|---|---|---|---|
| 39466179818 (stored) | 60 of 60 | 0.365 | 0.109 | 0.315 |
| 39472217441 (stored) | 60 of 60 | 0.379 | 0.109 | 0.329 |
| 39508414669 (fresh) | 60 of 60 | 0.109 | 0.109 | 0.001 |
| 39508421419 (fresh) | 60 of 60 | 0.109 | 0.109 | 0.001 |

Every cell is listed in the committed output file (check 3 section of each run). Lean (`HeroExitCloseStart.lean`):
`closeStartOk_self` (the previous frame's own colour passes), `closeStartOk_rejects_target` (the reading at the target,
`bgRed 0 = 255`, is rejected whenever `bgRed m < 254.5`), `closeStartOk_rejects_below` and `closeStartOk_rejects_above`
(a reading more than half a unit off, either way). `closeStartCases` is a golden list of 11 cases checked by `#guard`;
`closeStartOk` in `closegap.mjs` is a TS stand-in tested against the same literals in `test/closegap.test.mjs`.

Why 0.5 red. Sample j reads the before-change style at transition progress 0: in the fresh runs red_j = red_i within
0.001 in 120 of 120 cells (MEASURED), so the start is the previous frame's colour with no progress yet. About 0.11 red of
the 0.5 is the quantisation of m to 1e-4 (`max abs(red_i - bgRed m_i)` is 0.109 in all four runs). In the two stored
runs red_j differs from red_i by up to 0.33 and `max abs(red_j - bgRed m_i)` reaches 0.38; that excess is unexplained.
The half unit is a fixed constant, not scaled to the candidate.

Accepted limits of the identity: it depends on the probe reading sample j at transition progress 0 (a harness cadence
change could break it); m is rounded to 1e-4, so `m_i = 10` is ambiguous at the 0.001 cut (the minimum `m_i` in all
runs is 10); the WebKit before-change reading is CONFIRMED on the pinned clone and INFERRED for the CI build; a longer
`g` passes by design, which is why the identity cannot settle (B).

Checks 1 and 2 of round 2 (own-gap floor with `LAG = 17`, original-gap cap) are superseded by check 3 and are not claims
here. The code and Lean lemmas remain and the output file still prints them.

## Measurements

Per arm, mac-webkit morph, 4 widths x 5 reps = 20 cells per arm per run. `g` = last sample with `is-morphing` to first
without (ms). Script and full output: `packages/gate-breakpoints/src/trajectory/closegap.mjs`, output file above.

| run | arm | mean g | median | p90 | max | cells g > 150 |
|---|---|---|---|---|---|---|
| 39508414669 | orig | 66.0 | 56.0 | 97.5 | 189 | 1 |
| | base | 60.4 | 45.5 | 120.2 | 176 | 1 |
| | scoped | 78.5 | 58.5 | 156.1 | 249 | 3 |
| 39466179818 | orig | 55.0 | 47.5 | 100.4 | 121 | 0 |
| | base | 55.0 | 45.5 | 87.3 | 141 | 0 |
| | scoped | 70.6 | 56.5 | 116.1 | 157 | 1 |
| 39508421419 (A/A) | orig | 56.6 | 49.5 | 112.0 | 164 | 1 |
| | base | 53.9 | 44.5 | 65.1 | 282 | 1 |
| | faithful | 51.5 | 38.5 | 89.0 | 178 | 1 |
| 39472217441 (A/A) | orig | 49.4 | 43.0 | 88.9 | 146 | 0 |
| | base | 42.6 | 33.0 | 64.1 | 141 | 0 |
| | faithful | 41.2 | 30.0 | 60.9 | 202 | 1 |

Close-start readings of the scoped arm, fresh run, by width (red at sample j, g in parentheses): 390 `249.9 (175)
229.3 (249)  212.6 (154)  249.2 (53)  245.6 (60)`; 640 `242.3 (82)  251.0 (32)  248.0 (54)  252.6 (24)  252.7 (33)`; 641
`238.1 (113)  244.8 (47)  244.3 (51)  252.4 (86)  237.3 (81)`; 1280 `251.0 (58)  249.6 (59)  251.4 (52)  250.2 (45)
240.4 (63)`. Every other arm and rep is in the output file.

## Perf question (B): INFERRED, not answered

- The fresh flag-alone run alone gives permutation p 0.12 (mean of log g, blocked by width; 0.11 for mean g). That is
  the confirmatory number. The fresh A/A run gives 0.69.
- The pooled p 0.013 (mean log g; 0.020 for mean g; 20000 seeded draws, so the third digit moves) includes 39466179818,
  the run that raised the question (its own p is 0.018); it is not confirmatory. The pooled A/A is 0.89.
- The effect is largest at 390, where the A/A candidate is also high (0.24 fresh, 0.09 stored); fresh 641 is +0.35 vs A/A
  -0.30. Block difference per width (candidate minus orig+base, mean of log g):

  | run | 390 | 640 | 641 | 1280 |
  |---|---|---|---|---|
  | 39508414669 scoped (fresh) | 0.68 | -0.23 | 0.35 | -0.12 |
  | 39508421419 A/A (fresh) | 0.24 | -0.11 | -0.30 | -0.06 |
  | 39466179818 scoped (stored) | 0.64 | 0.15 | 0.15 | 0.08 |
  | 39472217441 A/A (stored) | 0.09 | -0.09 | -0.45 | -0.10 |

- Close-phase frame intervals (mean / median ms over all consecutive samples of a rep) are within 2.4 ms (mean) and 2 ms
  (median) of each other within each run, no test run: 39508414669 orig 40.1 / 31, base 42.5 / 30, scoped 42.0 / 32; 39508421419 31.3 / 23, 32.0 / 22, 33.3 / 24;
  39466179818 39.8 / 31, 40.5 / 29.5, 41.8 / 31; 39472217441 28.8 / 22, 29.2 / 21.5, 28.1 / 21. Across runs they differ
  by up to 14 ms. No frame-time difference during the close is visible at this size; no cause of the class-removal gap
  is claimed.
- The statistics assume cells are exchangeable within a (run, width) block. The decision needs a run-level test on more
  fresh runs at one `headSha` (follow-up B, not this task).

## Earn `opacity` and `max-width` at close@0

`close@0` here is the reading at sample j (INFERRED to be the units' `close@0`; the bg identity holds there). Every cell
of the two fresh runs, `opacity (max-width px, g ms)`, reps 0 to 4; the committed output has the same for the stored
runs. The scoped run's `close@0=apart` earn groups are at 390 and 641 (`new`, both properties); the A/A run has no `new`
earn close@0 group (its 640 `max-width` close@0 is `both`: the base arm fails it too).

Scoped run 39508414669:

```
  390   orig  0.000 (21.1, 102)  0.000 (13.7, 55)  0.000 (11.1, 42)  0.000 (13.7, 41)  0.000 (16.3, 76)
  390   base  0.004 (36.7, 131)  0.000 (26.2, 72)  0.000 (18.3, 43)  0.000 (15.8, 57)  0.000 (11.7, 30)
  390   cand  0.088 (58.6, 175)  0.636 (92.2, 249)  0.015 (33.7, 154)  0.000 (15.9, 53)  0.000 (14.5, 60)
  640   orig  0.000 (9.1, 32)  0.000 (13.0, 57)  0.159 (48.6, 189)  0.000 (13.0, 37)  0.000 (13.2, 45)
  640   base  0.000 (21.6, 75)  0.000 (11.8, 37)  0.000 (12.8, 24)  0.084 (54.2, 119)  0.000 (9.9, 29)
  640   cand  0.000 (18.3, 82)  0.000 (11.1, 32)  0.000 (15.5, 54)  0.000 (12.3, 24)  0.000 (11.5, 33)
  641   orig  0.000 (12.3, 33)  0.000 (20.6, 78)  0.000 (15.1, 66)  0.000 (27.9, 80)  0.000 (17.8, 63)
  641   base  0.000 (17.0, 49)  0.000 (19.8, 55)  0.000 (11.2, 28)  0.000 (22.9, 40)  0.003 (33.7, 43)
  641   cand  0.026 (41.6, 113)  0.000 (12.8, 47)  0.000 (23.3, 51)  0.017 (28.1, 86)  0.000 (27.5, 81)
  1280  orig  0.000 (23.2, 70)  0.000 (17.2, 53)  0.041 (34.3, 97)  0.000 (17.3, 55)  0.000 (17.0, 49)
  1280  base  0.000 (16.7, 38)  0.000 (25.6, 81)  0.000 (16.3, 33)  0.000 (21.0, 48)  0.131 (63.8, 176)
  1280  cand  0.000 (20.9, 58)  0.000 (23.7, 59)  0.000 (15.4, 52)  0.000 (18.7, 45)  0.000 (22.3, 63)
```

A/A run 39508421419:

```
  390   orig  0.000 (11.4, 59)  0.000 (16.6, 65)  0.000 (15.5, 51)  0.000 (12.4, 51)  0.000 (14.1, 60)
  390   base  0.000 (16.0, 51)  0.000 (13.5, 46)  0.000 (13.8, 45)  0.000 (13.4, 42)  0.000 (18.1, 65)
  390   cand  0.225 (53.5, 178)  0.021 (30.4, 70)  0.000 (21.4, 86)  0.000 (19.3, 34)  0.000 (12.5, 37)
  640   orig  0.000 (5.9, 14)  0.000 (6.9, 20)  0.000 (8.0, 27)  0.000 (5.4, 21)  0.000 (7.2, 12)
  640   base  0.000 (7.1, 24)  0.002 (23.4, 58)  0.000 (9.1, 24)  0.000 (19.7, 22)  0.000 (8.9, 38)
  640   cand  0.000 (19.4, 16)  0.000 (7.2, 26)  0.000 (7.7, 19)  0.000 (10.8, 32)  0.000 (9.4, 17)
  641   orig  0.000 (24.6, 88)  0.000 (27.0, 111)  0.000 (34.4, 121)  0.073 (69.5, 164)  0.000 (29.2, 95)
  641   base  0.000 (20.5, 44)  0.601 (90.6, 282)  0.000 (21.7, 66)  0.000 (15.9, 55)  0.027 (45.9, 51)
  641   cand  0.000 (27.1, 51)  0.000 (35.0, 107)  0.000 (24.5, 66)  0.000 (31.0, 87)  0.000 (19.5, 46)
  1280  orig  0.000 (9.6, 30)  0.000 (9.6, 33)  0.000 (9.9, 48)  0.000 (11.4, 41)  0.000 (9.0, 22)
  1280  base  0.000 (8.1, 23)  0.000 (8.6, 24)  0.000 (10.5, 31)  0.000 (10.4, 31)  0.000 (11.5, 55)
  1280  cand  0.000 (11.0, 40)  0.000 (9.2, 27)  0.000 (10.9, 20)  0.000 (11.8, 41)  0.000 (10.1, 29)
```

- INFERRED: earn at close@0 is mostly `g`-driven. The earn transition began at an earlier class change, so a longer `g`
  moves it further by sample j. All 7 cells with g of at least 164 read opacity 0.073 or more (0.636 at g 249 and 0.601
  at g 282 the largest), and opacity above 0.1 occurs only at g of at least 176.
- Exceptions, so this is not a threshold in `g`: `max-width` 33.7 px occurs at g 43 (scoped run, base 641 rep 4, opacity
  0.003) and at g 154 (scoped 390 rep 2, opacity 0.015); opacity 0.027 at g 51 (A/A, base 641 rep 4) while g 111 reads 0
  (A/A, orig 641 rep 1); `max-width` also depends on the width (A/A at 641, orig and cand: 24.6 to 35.0 px with opacity 0 at g 87 to 121;
  A/A orig at 640: 5.4 to 8.0 px at g 12 to 27); and the A/A 640 `max-width` cells at g 16 (19.4 px, cand rep 0) and g 22
  (19.7 px, base rep 3) read above that 5.4 to 8.0 px at similar g.
- The earn start rule (C) is not derived here.

## What this task does

- Takes none of (a), (b), (c). No judge change (`Trajectory.lean` is untouched) and no part change.
- Follow-ups: B (run-level permutation on 5 vs 5 fresh runs at one `headSha`), C (earn close-start rule), A (identity
  judge rule, after B and C).

## Limits

- WebKit source reading is on the pinned clone @862f17d; CI runs a Playwright WebKit build.
- The permutation test assumes cells are exchangeable within a (run, width) block.
- The identity has the limits listed under Check 3.
