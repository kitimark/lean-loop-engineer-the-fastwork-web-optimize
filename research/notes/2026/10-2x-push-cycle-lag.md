---
id: 2026-10-2x-push-cycle-lag
kind: note
title: "Push cycles: on the Simulator the slow-frame share rises with the cycle index in every arm and is worst in the user's composition; H1 and H3 are refuted, H2 refuted for the composition, H4 open; the flag-off attribution was lost to an artifact upload bug"
status: review
created: 2026-10-26
topics: [morph, end-of-page, touch, simulator, webkit, chromium, push-cycle, ci]
---

# Push cycles: what repeats when the finger pulls the page end in and out

## Answer

- MEASURED (Simulator, real touches, 6 drag-past-the-end cycles per pass): the share of frames slower than 50 ms rises with the cycle index in all three arms. At dwell 1 s (run 40218625611, 3 jobs): original 12% at k=0 to 47% at k=4, rewrite 9% to 48%, the user's composition 14% to 81%. At dwell 0.3 s (run 40206864819, 2 usable jobs): original 24% to 41%, rewrite 18% to 74%, user 19% to 89%. The user's composition is the worst arm from k=3 on in both dwells (k=3, dwell 0.3 s: 86% against 18% and 41%).
- So the felt "more lag when I pull in and out than when I open once" has a Simulator counterpart: cycle 0 (the one open) is the cheapest, later cycles cost more. MEASURED: it is also in `original`, so the rise is not something the rewrite added; the user's composition adds about 1.7 times the slow share of rewrite and original at k=4 (81% against 47 to 48%, dwell 1 s).
- INFERRED: the rise is partly time in the pass, not only the cycle index (the index is also the pass clock); the arm order was rotated per job, so the arm gap is not an order effect, but a pass-time effect common to all arms cannot be separated on this lane.
- Hypotheses (Lean verdict functions, `Fw.Measure.PushCycle`): H1 refuted, H2 refuted for the user's composition (open for original and rewrite), H3 refuted on the Chromium proxy and open on WebKit, H4 open. Table below.
- NOT DELIVERED: the flag-off attribution (push 3: user composition against the composition without `hero.countdown:strip` (and with it `morph.countdown:strip`, which requires it), without `morph.countdown:strip`, without `engine.scroll:unthrottle`, dwell 1 s). All three Simulator jobs ran their touch step to success (jobs 1 and 2 wrote 4 passes each, with one Simulator restart in job 1 and two in job 2; job 3's log has no pass lines) but the artifact upload refused the driver log `1-driver-off-engine.scroll:unthrottle-r1.log`: GitHub's upload rejects `:` in a file name (CONFIRMED, run 40232266467, sim (1) log, "Contains the following character: Colon :"; the same for sims 2 and 3). The result files were lost with the runner. The fix is committed (`uploadName` in `packages/measure-webkit/src/throttle/push-cycle.mjs`, applied in `push-cycle-cli.mjs`, test in `push-cycle.test.mjs`); the task allowed one re-push of push 3 and it was spent, so a second push needs the lead.
- Chromium (proxy, counts in virtual time): the per-cycle work does not rise. Layout falls (81 to 19 per window), Paint rises 281 to 359 from k=0 to k=3 and equally in `original`, raster invalidation falls after k=0 (14.1M px to 2.3 to 3.1M), layers stay constant after k=1 (107 rewrite, 35 user), `Layer.created` is 0 from k=2. No Chromium stage explains the Simulator rise.
- Fix candidates are in the last section; none is supported by a measured stage yet.

## Method

- Lean: `lean/Fw/Measure/PushCycle.lean` (cost model: first open pays `first + promo + run`, a released layer pays `promo` again each cycle, a kept layer does not; trend rule; H1 to H4 premises with source lines; verdict functions; the cycle plan; the phone profile). Golden `packages/contracts/golden/measure/push-cycle.jsonl`, replayed by `packages/measure-webkit/test/push-cycle.test.mjs`. TS stand-ins (no Lean golden for them): `recordCycles`, `verdictInputs`, `indexSeries`, `searchOf`, `uploadName`, the Chromium `windowSums`, `perRun`, `armTable`, `reportMd`.
- WebKit: Simulator touch lane (XCUITest real touches), page 300 px above the end, 6 cycles of drag past the end, drag back, short drag so the toolbar returns, dwell 0.3 s or 1 s after each press. Arms original, rewrite, user (`?fw=` the nine flags of the task), one pass per arm per job, 3 jobs, the order rotated by the job number. Table by `push-cycle-cli.mjs report`.
- Chromium: CDP touch with the same cycle plan, 3 runs per arm, counts per window (`packages/measure-chromium/src/push-cycle.mjs report`), spread rule of `Fw.Measure.Offscreen`.
- The Simulator runs on the Mac GPU and Mac memory; the phone is not measured here (`results/push-cycle-lag/phone-profile-d300.json` and `-d1000.json` are the replay profiles for phone-compose-counts).

## Runs

| Run | What | State |
|---|---|---|
| 40206864819 | push 1, toolbar-throttle, dwell 0.3 s | failure: sim 1 and sim 3 gave 3 usable passes each (rewrite needed one restart); sim 2 lost (touch step hit its 90 min limit, no artifact) |
| 40206864910 | push 1, chromium-counts, dwell 0.3 s | success |
| 40218625611 | push 2, toolbar-throttle, dwell 1 s | success, 3 jobs, 9 usable passes |
| 40218625602 | push 2, chromium-counts, dwell 1 s | success |
| 40232266467 | push 3, toolbar-throttle, dwell 1 s, flag-off arms | failure at artifact upload in sims 1 to 3; no data |

## WebKit Simulator: slow >50 ms share of frames per cycle index

Summed over the usable passes of the runs above (frames and slow counts in the run artifacts `toolbar-throttle-table`). Cycle k is the k-th press-and-return.

| Dwell | Arm | k=0 | k=1 | k=2 | k=3 | k=4 | k=5 |
|---|---|---|---|---|---|---|---|
| 1 s | original | 12% | 9% | 11% | 29% | 47% | 39% |
| 1 s | rewrite | 9% | 8% | 15% | 28% | 48% | 53% |
| 1 s | user | 14% | 21% | 22% | 40% | 81% | 79% |
| 0.3 s | original | 24% | 18% | 12% | 18% | 41% | 42% |
| 0.3 s | rewrite | 18% | 15% | 13% | 41% | 74% | 19% |
| 0.3 s | user | 19% | 23% | 28% | 86% | 89% | 85% |

- The rewrite k=5 at 0.3 s (19%) rests on 1393 frames against 600 to 850 in the other cycles of that arm; the cycle-5 cells are the least reliable (the pass ends there and the frame count differs by arm).
- Viewport changes (the Safari toolbar moving), summed over the 3 passes of an arm, are 6 to 8 per cycle at k=0 to 4 (2 to 3 per pass, flat) and 2 to 4 at k=5; resize events fall from 19 to 24 at k=0 to 1 to 3 at k=5. The slow share rises 4 to 6 times over the same cycles while the toolbar changes stay flat.
- Slow frames over 34 ms: flat in original and user at 1 s, rising in rewrite; the >50 ms series is the one that rises in every arm.

## Chromium proxy: counts per window, open half (dwell 1 s, run 40218625602; spread rule against k=0)

| Counter | k=0 | k=1 | k=3 | k=5 | Arm |
|---|---|---|---|---|---|
| LayoutCount | 81 | 70 | 40 | 19 | rewrite and user |
| trace.Paint | 281 | 325 | 359 | 334 | rewrite and user (original 280, 328, 358, 333) |
| trace.RasterTask | 78 | 88 | 79 | 49 | all |
| raster.invalidationAreaPx | 14.1M | 3.06M | 2.51M | 2.30M | all |
| census.layers | 35 (user), 107 (rewrite, original) | same | same | same | |
| trace.Layer.created | 4 | 4 | 0 | 0 | all |

At dwell 0.3 s (run 40206864910) the open-half counts alternate between windows (Paint 222, 135, 231, 134, 253, 164 in the user arm) and raster invalidation is 12.2M at k=0 against 1.06 to 1.27M later. The alternation is the plan's window cut at a short dwell, not a rise.

## Per hypothesis

| H | Verdict | Measured part and stage |
|---|---|---|
| H1 toolbar resize (visible-rect throttle 100 ms, `WKWebViewIOS.mm:3256-3268@862f17d`) | refuted for rewrite and user (Lean `h1Verdict` over >34 ms and >50 ms, both pushes); original holds at >50 ms in both pushes and refuted at >34 ms | Viewport changes stay flat at 2 to 3 per pass and cycle (k=0 to 4) while the slow share rises 4 to 6 times, so toolbar changes do not drive the rise. Limit: the far-from-change slow share is 55 to 75% in these passes, so a 2 times higher near-change rate is unreachable; the test cannot show a per-change cost, only that the rise does not follow the changes. Stage: not Layout from the resize. |
| H2 async scroll fights (UI process owns the scroll) | user composition refuted in both pushes (fights per open fall: 4.5 to 3.4 per stretch at 0.3 s, 5.0 to 3.3 at 1 s); original and rewrite flip between pushes (original holds at 0.3 s and refutes at 1 s, rewrite the reverse): open | Fights and displaced frames per cycle are flat or fall with k; the rise is not a growing fight with the native scroll. |
| H3 DPR 3 re-raster of re-promoted layers | refuted on the Chromium proxy (Lean `h3Verdict`: the later cycles repaint under half of k=0 at DPR 3, 2.3 to 3.1M px against 14.1M, and 1.06 to 1.27M against 12.2M); open on WebKit | The 9/4 pixel ratio of DPR 3 over DPR 2 is arithmetic (`dpr3_over_dpr2`). Chromium keeps its layers (`Layer.created` 0 from k=2), so it cannot show whether WebKit re-promotes; the WebKit lane has no raster counts. |
| H4 IOSurface pool (64 MiB iOS, 256 MiB Mac, `IOSurfacePool.h:85-89@862f17d`) | open | Freed bytes at a close are not countable on CI (Lean `h4Verdict` needs them). Premise only: the morph backing census of 90 to 106 MB (run 39897807511) is in the gap 64 to 256 MiB (`census_in_gap`), so a full release would re-allocate on iOS and reuse on the Mac. The Simulator uses Mac memory and cannot show it. |

## Fix candidates (follow-up tasks, with their premise)

1. Keep the promoted tween layers alive across a cycle (will-change held while the finger is near the end). Premise: Lean `kept_saves`, a kept layer saves `promo` per cycle after k=0, and `kept_falls`. Open: whether WebKit re-promotes at all (Chromium does not); a WebKit layer count per cycle is the first thing to measure.
2. Find the part behind the user composition's extra slow share (push 3 lost): rerun the three flag-off arms, with the fixed log names. Premise: attribution by toggling off in turn, the rule of the task.
3. Hold one pixel budget instead of releasing backing stores at the close (H4 premise): only worth building if the phone replay (phone-compose-counts, profiles above) shows the close freeing between 64 and 256 MiB.
4. No fix is proposed for the toolbar (H1 refuted) or the scroll fights (H2).

## Losses

- Push 1: sim 2 lost (touch step 90 min limit). Push 2: no loss. Push 3: all three jobs lost their result at the upload (colon in a file name), a harness bug, fixed on this branch and not re-run.
- Chromium dwell 0.3 s windows alternate; read the 1 s run for the trend.
