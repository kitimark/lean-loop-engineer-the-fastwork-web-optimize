# Wave-2 integration: v2-proved gate, counts per profile, part pages with engine-check, F6 pilot

Status: MEASURED on GitHub CI from one pushed commit (branch `ci/integrate-wave-2`, ef8b2cd3, pushed once; every dispatch is `workflow_dispatch --ref` of it).
Verdicts are Lean's (gate `Fw.Gate.Exit`, faithful `Fw.Faithful`, `Fw.Measure.EngineCheck`, all via fwcore). No Mac measurement. Educational study of the public
fastwork.com homepage, not affiliated with Fastwork. Machine-readable output: `results/integrate-wave-2/**`; analysis glue: `packages/engine-check/src/wave2.mjs`.

Unit of decision: the v2-proved gate on both engines, the counts per profile, the per-part engine-check verdicts, the G2 run and the F6 pilot. Items below those are follow-ups.

## Runs

| what | run | result |
|---|---|---|
| gate, v2-proved arm (`preset=v2-proved`), both engines | 39220947437 | Chromium pass, WebKit incomplete |
| gate, default arm, both engines | 39220962049 | Chromium fail (1 probe), WebKit incomplete |
| gate, default arm, Chromium only (re-run) | 39230139617 | pass, failing list empty |
| counts swipe-v1, whole page, base / v2-proved | 39224113958 / 39224078326 | success, 3 shards per arm |
| counts swipe-touch-v1, whole page, base / v2-proved | 39224678606 / 39224091514 | success, 3 shards per arm |
| part pages (`only=`), base / arm | hero.countdown 39225528196 / 39225547720; nav.hitTest 39225578464 / 39226582881; g1 39226593120 / 39226604309 (+ pain.notes arm 39228396423, people.card arm 39228407395); platform 39227563060 / 39227571736; columns 39228387861 / 39229363194 | success, 3 shards per arm |
| G2 (commission, platform, nav, panel), base / arm | 39224697587 / 39224735485 | refused by the viewport gate (below) |
| morph.mount part page, base | 39227583530 | refused by the viewport gate; arm not run |

All counts runs reused the frozen image (`image_run=39049264131`). "3 runs" are the 3 shards of a run, each on its own CI job (separate VMs); the counts
workflow has no per-run repeat beyond that.

## Gate on the v2-proved preset (run 39220947437)

| engine | verdict | readings | pass | excused | bad | universe | unsettled |
|---|---|---|---|---|---|---|---|
| Chromium | pass | 7056 | 7049 | 7 | 0 | identical | 0 |
| WebKit (Playwright, Linux) | incomplete | 7056 | 6763 | 291 | 2 | identical | 0 |

- MEASURED: flags read from the loaded page are `?preset=v2-proved`, config 6762d15c2b8b6d35 (wave 1 could not run this arm; the `preset` input of the workflow fixed that).
- Chromium: 7 excused are the matchMedia =Lean not-comparable cells (4 fractional gaps, 3 touch-1024). The failing-items list is empty. All ten flag rows (engine.scene,
  engine.scroll, hero.countdown, morph.columns, morph.countdown, morph.mount, morph.tween, nav.hitTest, pain.notes, people.card) read pass in every column and sweep.
- WebKit: 291 excused = 144 whole-width fractional + 144 primary-pair cross + 3 touch-1024, and 2 bad cells `matchMedia =Lean | sweep:phone-rotation | phone-rotation#1` and `#3`
  (not-comparable). These are the same cells as wave 1 and main's gate (CONFIRMED against `research/notes/2026/10-19-integrate-wave-1.md`); accepted limit.
- The WebKit verdict is `incomplete`, not `pass`, for the same reason as wave 1: the cells the engine cannot build. It is no `fail`.

## Gate, default arm (runs 39220962049, 39230139617)

| run | engine | verdict | readings | pass | excused | bad |
|---|---|---|---|---|---|---|
| 39220962049 | Chromium | fail | 7056 | 7048 | 7 | 1 |
| 39220962049 | WebKit | incomplete | 7056 | 6763 | 291 | 2 |
| 39230139617 | Chromium | pass | 7056 | 7049 | 7 | 0 |

- The one failing probe of 39220962049 was `commission` style `margin-inline-start/-end` (rows `inner` 0px vs 132px, `rows` 0px vs 8px) at the first stop of
  `sweep:desktop-1512-320-1512`, 1 of 57 comparable probes; 0 unsettled samples. The same arm 76 minutes later (39230139617) reads 0 failing items. MEASURED: a 1 of 2 flake on the
  default arm; the v2-proved arm read clean. INFERRED: a live-resize transient of the commission part (wave 1 excused 57 such readings and then read them all pass); not isolated, follow-up.

## Counts per profile (whole page, v2-proved vs base, Chromium)

R0 = base rewrite, RV = v2-proved rewrite, 3 shards each. Bands are R0's min..max over its 3 shards; "below" means all three RV shards under the R0 band. Classes from the
zone-baseline of each run (`results/integrate-wave-2/counts/*.json`).

| type (class) | swipe-v1 R0 > RV | delta | swipe-touch-v1 R0 > RV | delta |
|---|---|---|---|---|
| metric.RecalcStyleCount (deterministic) | 1827 > 816 | -1011, below | 1859 > 852 | -1007, below |
| trace.UpdateLayoutTree (deterministic) | 1844 > 833 | -1011, below | 1876 > 869 | -1007, below |
| trace.ScheduleStyleRecalculation (deterministic) | 1860 > 850 | -1010, below | 1892 > 886 | -1006, below |
| trace.FireAnimationFrame (quarantined) | 2057 > 1454 | -603 | 2112 > 1503 | -609 |
| trace.Animation.compositeFailedBits (deterministic) | 1831488 > 1757888 | -73600, below | 1905216 > 1905568 | +352, above |
| census.layers (stable) | 25782 > 26833 | +1051, above | 26946 > 28065 | +1119, above |
| census.drawingAreaPx (stable) | 4937894954 > 5030111206 | +92216252, above | 5184338904 > 5282955701 | +98616797, above |
| raster.invalidationAreaPx | 92866835 > 91917497 (stable) | -949338, below | 179275461 > 179840975 (quarantined) | +565514, within |
| trace.cc.Commit | 503 > 503 (deterministic) | 0 | 523 > 520 (stable) | -3, below |

- Off-band types: swipe-v1 41 of 70 (11 above, 30 below); swipe-touch-v1 45 of 70 (15 above, 30 below); the rest are within the R0 band (29 and 25).
- MEASURED: style recalcs fall by about 55 percent on both profiles (-1011 / -1007 recalcs, deterministic, 3 of 3 shards). Layer census rises (+1051 / +1119 layers, +2 percent drawing area):
  the v2-proved set promotes layers (INFERRED: morph.tween:waapi and the hidden-pause flags; not attributed to one flag here). Work counts, not milliseconds.
- Faithful (`Fw.Faithful`, fwcore) of R0 against the frozen original A: FAIL on both profiles, per zone (fail / pass / skipped): swipe-v1 y04000 27/17/10, y04500 14/29/10, tail 15/23/10;
  swipe-touch-v1 y04000 29/15/11, y04500 14/31/10, tail 10/35/10. Frame shapes equal (50/14/30 and 50/13/30). Same family of failures as the wave-1 refreeze (the rewrite is
  not count-identical to the original; that is the premise of the study).
- The control A' (the original arm of the same CI run against A) passes on both profiles (0 failing types in all three zones). The run-to-run noise is inside the frozen bands.
- The RV against A verdict is REFUSED by Lean: `not comparable: preset` (the flags differ from the frozen original, `Fw.Faithful.comparable`). So there is no pass/fail verdict for v2-proved
  against the original; the band table above is descriptive (INFERRED role only).

## Part pages: engine-check per zone (Chromium, `only=<id>`, stage 430x932)

The row files are `packages/contracts/golden/engine/*.jsonl`. Rows are keyed by `meta.variant`; classes are the frozen whole-page table, which is a premise on part pages
(`declared-rows-unverified`). Per-page descriptive deltas are in `results/integrate-wave-2/delta/<page>/delta.json`.

| zone / flag | row type, prediction | base > arm (3 shards) | Lean verdict | run ids |
|---|---|---|---|---|
| nav.hitTest | trace.UpdateLayoutTree `<o` (deterministic) | 1995 > 91 | pass | 39225578464 / 39226582881 |
| nav.hitTest | trace.HitTest `=o` (stable); PrePaint, raster.invalidationAreaPx, cc.Commit `<=o` | equal | pass x4 | same |
| nav.hitTest | FunctionCall, FireAnimationFrame, Layout, Paint | 1944 > 222 (Paint) | unusable (quarantined) x4 | same |
| hero.countdown (+ morph.countdown:strip) | census.layers `<o` (stable) | 12960 > 12960 | unusable (strict `<o` on a non-exact class) | 39225528196 / 39225547720 |
| g1 pain.notes alone | UpdateLayoutTree `<=o`, cc.Commit `=o` | 895 > 895, 713 > 713 | model-bug x2, see below | 39226593120 / 39228396423 |
| g1 pain.notes alone | LayoutCount `<=o`, PrePaint `<=o`, raster.invalidationAreaPx `=o` | equal | pass x3 | same |
| g1 people.card alone | UpdateLayoutTree `<=o` | 895 > 834 | model-bug (see below) | 39226593120 / 39228407395 |
| g1 people.card alone | LayoutCount, raster.invalidationAreaPx `=o`; PrePaint `<=o` | equal | pass x3 | same |
| g1 people.card alone | cc.Commit `=o` | 713 > 713 | model-bug (see below) | same |
| g1 (hero + pain + people together) | UpdateLayoutTree `<=o` | 895 > 844 | model-bug | 39226593120 / 39226604309 |
| g1 together | PrePaint `<=o`; cc.Commit `=o` | 1422 > 1432; 713 > 723 | model-bug x2 | same |
| g1 together | LayoutCount, raster.invalidationAreaPx; census.layers `<o` | equal | pass x2 ; unusable | same |
| platform (engine.scene:hidden-pause) | UpdateLayoutTree `<=o` | 1050 > 1050 | model-bug (premise, below) | 39227563060 / 39227571736 |
| platform | cc.Commit `<=o`; FireAnimationFrame, Layout | equal | pass; unusable x2 | same |
| columns (morph.columns:hidden-pause) | UpdateLayoutTree, cc.Commit `<=o` | 1289 > 1289 | pass x2 | 39228387861 / 39229363194 |
| columns | FireAnimationFrame, Layout | 0 > 0 | unusable (quarantined) x2 | same |
| panel host (morph.mount, morph.countdown, morph.panel) | none | none | not measured: viewport gate | 39227583530 |

Tally (pass / model-bug / unusable): hero.countdown 0/0/1; nav.hitTest 5/0/4; platform 1/1/2; columns 2/0/2; g1 pain.notes 3/2/3; g1 people.card 3/2/3; g1 together 4/6/7.

How to read the 11 model-bug rows (frame-level check of the counts, `results/integrate-wave-2/engine-check/summary.json`):
- pain.notes alone, UpdateLayoutTree and cc.Commit: totals are equal in all runs. Arm shard 2 of 3 (index 01) differs from the other arm shards and from all base shards in 12 frames (698 to 707, commits and recalcs alternating 0/1 with
  equal totals); base runs are identical. MEASURED. INFERRED: the frozen whole-page class `deterministic` is a premise that does not hold at this page's tail (one jittering arm run), so
  Lean's frame-exact `<=o`/`=o` refutes it. This is a class-premise failure, not evidence about the flag; the rows stay unverified here.
- people.card alone, cc.Commit: the arm differs from base in the same 12 tail frames in all 3 of 3 runs while totals are equal. MEASURED: the flag moves commits between frames.
  `=o` is a per-frame claim on a deterministic type, so Lean's refutation stands for this page; INFERRED cause: the card media-query rewrite shifts one layout pass in the tail.
- people.card UpdateLayoutTree `<=o` reads 895 > 834, 73 frames differ in every shard pair (MEASURED); Lean's per-frame `<=o` finds a frame where the arm is above base, so the
  saving of 61 recalcs (6.8 percent) is not a per-frame decrease. The frames are not listed here.
- g1 together (3 flags): cc.Commit 713 > 723 and PrePaint 1422 > 1432 in 3 of 3 shards, +10 each. MEASURED. The single-flag arms do not show +10 (pain.notes alone 713 > 713; people.card alone 713 > 713),
  and recalcs do not add: people.card alone -61, all three -51. INFERRED: an interaction with hero.countdown/morph.countdown (hero.countdown alone is +21 recalcs and +21 commits on its own page).
  Follow-up, listed in open items.
- platform UpdateLayoutTree: one frame jitters in base shard 3 (index 02) and in arm shard 2 (index 01) (shards differ among themselves in 1 frame), so the class premise fails on the base side; the arm vs base reading is not a hidden-pause effect.

### Platform zone: hidden-pause verdict is OPEN

CONFIRMED (handoff finding): `engine.scene:hidden-pause` in v2-proved was proved against a port whose platform faithful arm lacked the original's scene pause; platform-scene-faithful r1 is
re-proving it. On the platform part page the arm equals base in every type (0 off-band cells of 70; FireAnimationFrame 935 > 935), (the stage page may have no hidden state to pause: INFERRED, unchecked). The
platform-zone verdict for this flag is therefore OPEN. The one platform model-bug row above is a class-premise failure (previous section), not a verdict for or against the flag. columns' hidden-pause rows pass but
are weak: the arm equals base in all four rows (1289 > 1289, `<=o`), and the two script rows are quarantined.

## G2 run (commission, platform, nav, panel): refused

Runs 39224697587 and 39224735485 (and the morph.mount base 39227583530) were refused by the driver's viewport gate before any count was taken:
`viewport not faithful: ... real frame 443x961 (pinned 430x932, client 430x932, scrollWidth 443, scale 1)`. The pinned frame is the profile's 430x932, so no profile avoids it.
INFERRED: the panel host's stage page is 443 px wide at a 430 px viewport (it overflows by 13 px), the gate is right to refuse, and the page needs a width fix before it can be measured. The
panel parts (morph.mount, morph.countdown, morph.panel) and G2 (which includes panel) have no measurement in this wave. nav and platform were measured on
their own pages (above), which is how they entered the F6 pilot.

## F6 pilot (units additivity, PLAN 4.8): swipe-v1

Question: a combined run's delta equals the sum of the part deltas within the class margin. Combined = v2-proved vs base on the whole page (39224113958 / 39224078326). Parts = g1 (3 flags
together), nav, platform, columns (39226593120/39226604309; 39225578464/39226582881; 39227563060/39227571736; 39228387861/39229363194). The panel parts and the page-level flags
(engine.scroll, morph.tween) have no part-page coverage, so the sum is incomplete by construction. Margin: deterministic 0, stable k (frozen table), quarantined none.

| type (class) | combined | g1 | nav | platform | columns | sum | residual | verdict |
|---|---|---|---|---|---|---|---|---|
| metric.RecalcStyleCount (det.) | -1011 | -51 | -1904 | 0 | 0 | -1955 | +944 | not additive at totals |
| trace.UpdateLayoutTree (det.) | -1011 | -51 | -1904 | 0 | 0 | -1955 | +944 | not additive at totals |
| trace.Animation.compositeFailedBits (det.) | -73600 | -106496 | 0 | 0 | 0 | -106496 | +32896 | not additive |
| trace.MinorGC (stable, k=4) | -3 | -1 | +1 | 0 | 0 | 0 | -3 | within 4 (strict) |
| metric.LayoutCount (stable, k=4) | -4 | 0 | 0 | 0 | 0 | 0 | -4 | within 4 (strict) |
| census.layers (stable) | +1051 | +1 | 0 | 0 | 0 | +1 | +1050 | not additive |

- Counts of the pilot: 46 types moved on at least one page, 32 have a margin (deterministic or stable), 14 are quarantined (no verdict). Of the 32: 3 additive within the strict margin (LayoutCount, MinorGC, PaintImage),
  5 within the widened margin (margin x (parts + 1): the three plus UpdateLayer and Layout.partial), 27 not additive at totals.
- The page trajectories differ: the whole page has 503 frames, g1 727, nav 992, platform 975, columns 1329. A total over a longer trajectory is bigger; the deltas are per frame work. Per-frame rates (delta / frames, descriptive,
  my threshold of 10 percent, not a class margin): UpdateLayoutTree -2.01 per frame combined vs -1.99 for the parts' sum; compositeFailedBits -146.3 vs -146.5; Animation.instant,
  RecalcStyleCount and ScheduleStyleRecalculation also within 10 percent (5 rows of 32).
- INFERRED: the style saving is additive per frame (nav's -1.9 per frame is the whole page's -2.0 per frame) but not additive per total, because the two trajectories scroll different lengths. The F6 statement as
  PLAN 4.8 writes it ("units add") needs a normalising unit (per frame or per zone), or equal trajectories. Not decided here.
- census.layers is the reverse: the whole page gains 1051 layers, the parts together +1. The layer promotion comes from something the part pages do not contain (the panel parts or the page-level flags
  morph.tween/engine.scroll). INFERRED; a morph.tween page-level run would name it.
- Verdict for the pilot: MEASURED mixed, INFERRED not additive at totals, additive per frame on the style family. It is a TS stand-in (below): the compose-check F6 verdict is not built in Lean.

## TS stand-ins (to move into Lean)

`packages/engine-check/src/wave2.mjs` (glue; every verdict above that is Lean's is fwcore's): `totalsOf`, `median`, `deltaRow`, `bandCells` (descriptive R0 band against RV), `confounds`, `stageAs`
(stage the downloaded counts under the layout `fw engine-check` reads, keyed by `meta.variant`), `f6` (additivity residual against the class margin, per-frame rates) and `zonecmp`; the explicit run-to-variant mapping for the part pages
(`results/integrate-wave-2/plan.json`) and the F6 comparison are not Lean. Tests: `packages/engine-check/test/wave2.test.mjs`. The `f6` pilot has no Lean statement yet; the "10 percent per frame" is mine.

## Limits

- Platform hidden-pause verdict OPEN (above). WebKit phone-rotation cells and the 291 excused cells are identical to wave 1 (accepted).
- The frozen classes are whole-page tables used on part pages: a premise, not measured on those pages. Two shard-level jitters show it can fail (pain.notes tail, platform).
- Panel host and G2 unmeasured (viewport 443 vs 430). Page-level flags (engine.scroll, morph.tween) have no part page.
- Counts are work, not milliseconds; no phone time. 3 shards per arm, one workflow run per arm; the default gate flake is 1 of 2 runs.
