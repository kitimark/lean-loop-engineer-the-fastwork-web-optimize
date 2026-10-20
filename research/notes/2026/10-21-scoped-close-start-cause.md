---
id: 2026-10-21-scoped-close-start-cause
kind: note
title: "hero.exit:scoped lengthens the last frames of the nav close on macOS WebKit: a perf finding, not a timing-only difference"
status: final
created: 2026-10-21
authors: [agent:measure-engineer]
topics: [measurement, trajectory-probe, webkit, hero.exit, nav]
---

# Close-start colour of `nav.background-color` under `hero.exit:scoped`

Task `scoped-close-start-cause`, round 2. Question: on macOS WebKit morph the flag-alone candidate starts the close
`nav.background-color` low (red 226.5 at 390 in run 39466179818) while the original passes start at 249 to 252. Is it
(a) a part fix, (b) timing only, or (c) a look change?

## Answer

Decision (a), with a perf finding. Not (b). The start colour is a function of the gap `g` between the last frame with
`is-morphing` and the first without it (proved below), and `scoped` has longer gaps than the original and the A/A
candidate. Pooled over the two flag-alone runs the candidate's mean `g` is high at permutation p 0.011 (mean of log g)
and 0.019 (mean g); the same test on the two A/A runs gives 0.90 and 0.74. The fresh flag-alone run alone gives
p 0.12, so one run does not separate; the pool does. MEASURED (statistics) and INFERRED (iid cells within a block).

## Identity (read from every arm's `search` and hash in the raw files)

| run | candidate arm `?fw` | candidate hash | base hash | original arm |
|---|---|---|---|---|
| 39508414669 (fresh, ci/scoped-close-start-cause @6068371) | `hero.exit:scoped` | 8d213de6fbdd52fd | ede2c7641aacf2d2 | no config |
| 39508421419 (fresh, A/A) | `hero.exit:faithful` | ede2c7641aacf2d2 | ede2c7641aacf2d2 | no config |
| 39466179818 (stored, flag-alone) | `hero.exit:scoped` | 8d213de6fbdd52fd | ede2c7641aacf2d2 | no config |
| 39472217441 (stored, A/A) | `hero.exit:faithful` | ede2c7641aacf2d2 | ede2c7641aacf2d2 | no config |

Both fresh dispatches printed the same id (known bug `fw-run-dispatch-pick`), so each run is named by its arms. Lean
outcome lines (mac-webkit): 39508414669 hero pass, morph FAIL; 39508421419 hero pass, morph PASS; Linux hero pass in
both.

## Mechanism

1. The close tween is `m = (1 - e/680)^3` (`closeAt_cube`). The nav drops `is-morphing` once `m <= 0.001`, at
   `e >= 612`, 68 ms before the end (`morphing_of_lt`, `not_morphing_of_ge`).
2. While the class is on, the background is `color-mix(in srgb, #ffffff1a, #131922)` driven by `--morph`. The mix is
   premultiplied: alpha `26/255 (1-m) + m` (`bgAlpha`), premultiplied red `26 (1-m) + 19 m`, so the red the probe
   reads is `bgRed m` = that over the alpha. `bgRed` falls strictly from 255 at m = 0 to 19 at m = 1 (`bgRed_lt`,
   `bgRed_le_iff`).
3. When the class goes, a `background-color` transition starts. WebKit's before-change style is the style of the
   previous style-change event, so the start colour is `bgRed(m_prev)`, `m_prev` the morph value of the last frame that
   saw the class (`Source/WebCore/style/Styleable.cpp:603-617@862f17d`). CONFIRMED on the pinned clone; the CI
   Playwright WebKit build differs, so for CI it is INFERRED. The ordering of this against the running tween inside
   `StyleTreeResolver` is not claimed.
4. A next frame `g` ms later allows `m_prev <= prevBound g = (0.1 + g/680)^3` (`prev_le_bound`), so the start red is
   at least `redFloor g = bgRed (prevBound g)` (`redFloor_anti`: a longer gap lowers the floor).
5. Over the model `Fw.Parts.HeroExitOpt.frameWrites` (the writes the Lean model lists), the scoped exit writes
   `--exit-opacity` and `--exit-scatter` on hero elements and none the nav background reads
   (`scoped_writes_miss_nav_bg`, `scoped_writes_miss_nav_elements`). The model is not the whole driver: `driver.ts:37`
   also sets `pointerEvents` on the hero (not on the nav). So the part cannot change the nav's style; any effect on the
   start colour goes through frame time.
6. Cost route, INFERRED and untested: the close is a wheel scroll (dy -120), so the `hero.exit` scroll handler runs
   during it. The scoped variant writes the two custom properties inline on every reader element each scroll frame
   (`READER_SELECTOR`), which can lengthen frames. No profile here confirms it.

## Measurements

Per arm, mac-webkit morph, 4 widths x 5 reps = 20 cells per arm per run. `g` = last sample with `is-morphing` to first
without (ms). Script and output: `packages/gate-breakpoints/src/trajectory/closegap.mjs`.

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

- The A/A spread of arm means is 41.2 to 66.0 ms (ten non-scoped arms); both scoped means (78.5, 70.6) lie above all of
  them. The scoped arm has the highest mean in both flag-alone runs; the A/A candidates have the lowest in both A/A runs.
- Close-start readings of the scoped arm, fresh run, by width (red at the first sample without the class, g in
  parentheses): 390 `249.9 (175)  229.3 (249)  212.6 (154)  249.2 (53)  245.6 (60)`; 640 `242.3 (82)  251.0 (32)
  248.0 (54)  252.6 (24)  252.7 (33)`; 641 `238.1 (113)  244.8 (47)  244.3 (51)  252.4 (86)  237.3 (81)`; 1280
  `251.0 (58)  249.6 (59)  251.4 (52)  250.2 (45)  240.4 (63)`. The original and A/A cells are in the script output
  (every arm, every rep). The effect is strongest at 390.
- Earn `opacity` and `max-width` close@0 failures in the scoped runs track the same `g` (same frame-phase reading).

## Checks on the measured channel

Both use `bgRed` / `prevBound` / `floorOk` (Lean `Fw.Parts.HeroExitCloseStart`; the script is the TS stand-in, pinned to
the Lean `#guard` literals in `test/closegap.test.mjs`).

1. Own-gap check: the reading at the first sample without the class is at least `redFloor` of that cell's own sample
   gap. Cells below it: 3, 3, 5, 7 of 60 per run, all within `LAG = 17` ms (one 60 Hz frame; max slack 13.0 ms at 1280
   base rep 2 in 39508414669, since = 18). Explanation of the slack: the sample is read up to one frame after the frame
   that held the class, so the true frame gap is `g_sample - since_j + L` with a read lag `L <= 17`. The 17 ms is
   INFERRED; the slacks are MEASURED. No cell is beyond it. None is open.
2. Original-gap rule (task item 2): a closed rule tied to the original arm's gaps. `floorOk (capOf origGaps) lag r`,
   `capOf` the largest original gap of the width in the same run. Proved: `floorOk_tween` (every start the tween makes at
   gap <= cap + lag passes), `floorOk_orig` (every original cell passes at any lag >= 0, as `capOf_ge` covers its
   gap), `floorOk_below` and `floorOk_reject_gap` (a rejected start came from a gap longer than cap + lag, so the
   cause is frame time), `floorOk_mono` (a larger cap accepts more). Result with 5 original reps per width: it also
   rejects A/A cells (39508421419 faithful 390 rep 0, red 185.6 at g 178 against cap 65 + 17, and base 640 rep 1;
   39472217441 faithful 390 rep 4, red 202.5 at g 202), because 5 original reps do not bound a heavy-tailed gap.
   Scoped violations: 1 cell in the fresh run and 2 in the stored one, all at 390. So no closed per-cell colour rule
   exists at 5 reps; the usable check is the gap distribution above. A cell-level rule needs a cap
   from many more original reps: with n original reps the false-reject rate of an A/A cell that exceeds the maximum is
   about 1/(n+1) (iid, INFERRED).

Violating cells of check 2 (red, g in ms): 39508414669: 390 scoped rep 2 (212.6, 154). 39508421419: 390 faithful rep 0
(185.6, 178), 640 base rep 1 (242.6, 58). 39466179818: 390 scoped rep 0 (226.5, 113), rep 3 (206.1, 157). 39472217441:
390 faithful rep 4 (202.5, 202). Each is a long frame gap; the A/A ones are the same phenomenon at the A/A tail.

## What to do

- (a) Part fix, not applied here: lower the per-scroll-frame inline writes of `scoped` during the nav close (fewer reader
  writes, or none while a nav tween runs), then re-measure `g`. The mechanism in point 6 must be profiled before this.
- Not (c): the colours are the original's for the same `m`; only the sample phase differs.
- The judge (`Trajectory.lean`) is not changed.
- More reps: reps are capped at 5 per run. Four more flag-alone mac-webkit morph runs (6 runs, 120 cells per arm) put
  the standard error of the mean-g difference near 0.06 in log units (INFERRED from the 40-cell spread). Orig and base
  in the same runs are the A/A reference.

## Limits

- WebKit source reading is on the pinned clone @862f17d; CI runs a Playwright WebKit build.
- The permutation test assumes cells are exchangeable within a (run, width) block.
- `LAG` is a fitted bound with an inferred reason.
