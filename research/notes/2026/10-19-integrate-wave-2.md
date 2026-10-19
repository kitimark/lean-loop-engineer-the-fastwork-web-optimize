# Wave-2 integration, round 1: v2-proved gate, counts per profile, single-flag part pages, totals pilot

Status: MEASURED on GitHub CI from one pushed commit (branch `ci/integrate-wave-2-r1`, c6912998 = round-0 branch merged with main at 8276822d, pushed once; every dispatch is a
`workflow_dispatch --ref` of it). Verdicts are Lean's (gate `Fw.Gate.Exit`, faithful `Fw.Faithful`, `Fw.Measure.EngineCheck`, all via fwcore). No Mac measurement.
Educational study of the public fastwork.com homepage, not affiliated with Fastwork. Machine-readable output: `results/integrate-wave-2/**`; analysis glue:
`packages/engine-check/src/wave2.mjs`. This round supersedes round 0 (built from ef8b2cd3; its run ids are in the appendix, its numbers are void).

Unit of decision: the v2-proved gate on both engines, the default-arm gate, the counts per profile, each single-flag per-part verdict, G2, and the per-flag C3 decision.
Anything below that is a follow-up.

## Answer

| item | result |
|---|---|
| v2-proved gate, Chromium | FAIL: 248 bad readings, all `platform.stageBg` / `platform.marquee` `will-change` ("transform" original, "auto" rewrite) |
| v2-proved gate, WebKit | incomplete (0 fail; 2 bad = the wave-1 phone-rotation cells, 291 excused) |
| default-arm gate, Chromium | FAIL: the same 248 plus 1 commission probe (249) |
| default-arm gate, WebKit | incomplete, table identical to the v2-proved one |
| counts per profile, style recalcs | 1832 > 821 (swipe-v1) and 1864 > 856 (swipe-touch-v1), deterministic, 3 of 3 shards |
| single-flag part pages | 7 pairs, Chromium only: 20 pass, 4 model-bug, 18 unusable rows; the 4 model-bug rows are class-premise failures |
| G2, base vs `preset=v2-proved` | measured (no refusal this round); descriptive, no row variants |
| C3 per flag | keep all 10 flags in v2-proved; the gate failure is not a flag effect (below) |

The gate failure is a main regression, not a v2-proved result: the default arm fails on the same 248 readings, and the commit that adds the rule (8276822d,
platform-scene-faithful) is in c6912998 but not in ef8b2cd3, whose platform rows read pass. It is reported here and not fixed in this branch.

## Runs

All counts runs reuse the frozen image (`image_run=39049264131`). "3 runs" are the 3 shards of one counts run, each on its own CI job (separate VMs). Search strings are
`meta.search` of the counts files (the identity of the arm), read after the run.

| what | run | search / inputs | result |
|---|---|---|---|
| gate, v2-proved, both engines | 39253059266 | `preset=v2-proved` | Chromium fail; WebKit job j2 failed at the engine smoke test ("orig 430px open: no answer in 30 s", infra) |
| gate, v2-proved, WebKit only (re-run) | 39257945326 | `preset=v2-proved engines=playwright-webkit` | incomplete |
| gate, default arm, both engines | 39253066988 | (none) | Chromium fail; WebKit incomplete |
| counts swipe-v1 base / v2-proved | 39253166643 / 39253172750 | `` / `?preset=v2-proved` | success, 3 shards per arm |
| counts swipe-touch-v1 base / v2-proved | 39253177864 / 39253184136 | same | success, 3 shards per arm |
| nav.hitTest base / arm | 39253271676 / 39253292170 | `?only=nav.hitTest&stage=vw:430,vh:932` / `?fw=nav.hitTest:elements-skip&only=nav.hitTest&stage=vw:430,vh:932` | success |
| g1 base | 39253313203 | `?only=g1&stage=vw:430,vh:932` | success |
| pain.notes arm | 39257459959 | `?fw=pain.notes:visible&only=g1&stage=vw:430,vh:932` | success |
| people.card arm | 39257496442 | `?fw=people.card:mq&only=g1&stage=vw:430,vh:932` | success |
| hero.countdown base / arm | 39257533380 / 39259074927 | `?only=hero.countdown&stage=vw:430,vh:932` / `?fw=hero.countdown:strip,morph.countdown:strip&only=hero.countdown&stage=vw:430,vh:932` | success |
| morph.columns base / arm | 39259109607 / 39259146065 | `?only=morph.columns&stage=...` / `?fw=morph.columns:hidden-pause&only=morph.columns&stage=...` | success |
| morph.mount base / arm | 39259991865 / 39260576409 | `?only=morph.mount&stage=...` / `?fw=morph.mount:shift&only=morph.mount&stage=...` | success (arm: attempt 2) |
| engine.scene base / arm | 39260614233 / 39260841413 | `?only=engine.scene&stage=...` / `?fw=engine.scene:hidden-pause&only=engine.scene&stage=...` | success (base: attempt 2) |
| G2 base / arm | 39261906990 / 39262007729 | `?only=g2&stage=vw:430,vh:932` / `?preset=v2-proved&only=g2&stage=vw:430,vh:932` | success |

Infra: runs 39260031147 and 39260070268 (and the first attempts of 39260576409 and 39260614233) failed in the `fwcore` / `site` jobs at `setup-lean` with
`could not download file from 'https://releases.lean-lang.org/...'` (TLS connect error), before any measurement. The re-run (`gh run rerun --failed`, same sha) of the two
latter runs passed; the two former were replaced by new dispatches (same inputs). MEASURED log text; cause INFERRED: a transient download failure.

## Gate on the v2-proved preset

| engine | run | verdict | readings | pass | fail / bad | excused | universe |
|---|---|---|---|---|---|---|---|
| Chromium | 39253059266 | fail | 7056 | 6801 | 248 | 7 | identical |
| WebKit (Playwright, Linux) | 39257945326 | incomplete | 7056 | 6763 | 0 fail, 2 bad | 291 | identical |

- MEASURED: flags read from the loaded page are `?preset=v2-proved`, config 6762d15c2b8b6d35.
- Chromium failing items (20 cells): `platform.stageBg` style `artboard` `will-change` 496 probes (first at `desk-319`) and `platform.marquee` style `track` `will-change` 124 probes, original
  "transform", rewrite "auto"; every probe of the 10 non-sweep rows (desk, desk-rm, touch, touch-rm, phone-landscape, dw-arm-isolate, hover-pointer-cross, dark, fractional-gaps, height-probes; 124 probes per part, 2 x 124 = 248 readings), none in the 4 sweeps. The 7 excused are the matchMedia =Lean not-comparable cells (4 fractional gaps, 3 touch-1024).
- INFERRED cause: the rewrite's `[data-fw-scene='paused']` rule (`will-change: auto !important`, platform.module.css, added by 8276822d) is in force at the probe states while the original's section reads
  "transform"; the original carries the same rule under `data-start-selling-scene=paused` (CONFIRMED in the snapshot CSS), so the two differ in the scene state, not in the rule. The platform-scene handoff lists the original's frame-callback gate (`iE`) as not ported;
  that is the likely difference, unchecked. The rule does not depend on a flag (`scene.ts` binds it in every arm).
- WebKit: 291 excused = 144 whole-width fractional + 144 primary-pair cross + 3 touch-1024; 2 bad cells `matchMedia =Lean | sweep:phone-rotation | phone-rotation#1` and `#3` (not-comparable). They are the same cells as wave 1
  (`research/notes/2026/10-19-integrate-wave-1.md`) and round 0: excused as an accepted limit, since identical to wave 1. WebKit passes `platform.stageBg` and `platform.marquee` in every reachable cell.
- Verdict lines: `results/integrate-wave-2/gate/verdicts.txt`; summaries `results/integrate-wave-2/gate/*.md`.

## Gate, default arm (run 39253066988)

| engine | verdict | readings | pass | fail / bad | excused |
|---|---|---|---|---|---|
| Chromium | fail | 7056 | 6800 | 249 | 7 |
| WebKit | incomplete | 7056 | 6763 | 0 fail, 2 bad | 291 |

- The 248 platform readings are identical to the v2-proved arm (same two parts, same keys, same values). MEASURED: the platform failure is independent of the v2-proved flags.
- The WebKit readings table has the same sha256 in both arms (67393f1b196e4cc80514b44a9b8218a94c2e45e80b2858ca03d1df6d63775431).

## Commission probe flake

The one extra failing probe of the default arm is `commission` style `margin-inline-start/-end` (`inner` "132px" vs "0px", `rows` "8px" vs "0px") at `desktop-1512-320-1512#0@1512x900`, 1 of 57 comparable probes, 0 unsettled
samples. Round 0 read the default arm twice, runs 39220962049 and 39230139617: it failed 1 of 2 runs; cause unknown. Round 1 reads it again in 39253066988 (default arm, fail) and not in the
v2-proved arm (39253059266, and round 0's 39220947437: 0 of 2). INFERRED: a live-resize transient of the commission part (wave 1 excused 57 such readings and then read them all pass). Not isolated; follow-up. Default arm overall: failed 2 of 3 runs, v2-proved arm 0 of 2; cause unknown (INFERRED).

## Counts per profile (whole page, v2-proved vs base, Chromium)

R0 = base rewrite, RV = v2-proved rewrite, 3 shards each (actual values per shard for the deterministic types). "below" means all three RV shards under the R0 band. Classes from the zone baseline of each run
(`results/integrate-wave-2/counts/*.json`).

| type (class) | swipe-v1 R0 > RV | delta | swipe-touch-v1 R0 > RV | delta |
|---|---|---|---|---|
| metric.RecalcStyleCount (deterministic) | [1832,1832,1832] > [821,821,821] | -1011, below | [1864,1864,1864] > [856,856,856] | -1008, below |
| trace.UpdateLayoutTree (deterministic) | [1849,1849,1849] > [838,838,838] | -1011, below | [1881,1881,1881] > [873,873,873] | -1008, below |
| trace.ScheduleStyleRecalculation (deterministic) | [1865,1865,1865] > [855,855,855] | -1010, below | [1897,1897,1897] > [890,890,890] | -1007, below |
| trace.Animation.compositeFailedBits (deterministic) | [2011936 x3] > [1938336 x3] | -73600, below | [2085664 x3] > [2086016 x3] | +352, above |
| trace.cc.Commit | [503,503,503] > [503,503,503] (deterministic) | 0 | [523,523,523] > [520,520,519] (stable) | -3, below |
| trace.FireAnimationFrame (quarantined) | [2057,2057,2058] > [1454 x3] | -603 | [2112 x3] > [1503 x3] | -609 |
| census.layers (stable) | [25782,25781,25780] > [26835 x3] | +1054, above | [26945,26946,26944] > [28062,28065,28064] | +1119, above |
| census.drawingAreaPx (stable) | 4.939e9 > 5.028e9 (3 shards each) | +88129420, above | 5.186e9 > 5.283e9 | +96574907, above |
| raster.invalidationAreaPx | [93482093 x3] > [92916938 x3] (stable) | -565155, below | 177.0e6 > 180.8e6 (quarantined) | +3723024 |

- Off-band types: swipe-v1 42 of 70 (12 above, 30 below); swipe-touch-v1 47 of 70 (17 above, 30 below). MEASURED.
- MEASURED: style recalcs fall by about 55 percent on both profiles (deterministic, 3 of 3 shards). The layer census rises (+1054 / +1119 layers): the v2-proved set promotes layers (INFERRED, not attributed
  to one flag; morph.tween:waapi and the hidden-pause flags are the candidates). Work counts, not milliseconds.
- Faithful (`Fw.Faithful`, fwcore) of R0 against the frozen original A, failing / passing / skipped types per zone: swipe-v1 y04000 27/17/10, y04500 14/29/10, tail 14/24/10;
  swipe-touch-v1 y04000 28/16/11, y04500 14/31/10, tail 9/36/10. The control (the original arm of the same run against A) passes on both profiles (0 failing types in every zone). The rewrite is
  not count-identical to the original; that is the premise of the study.
- RV against A is REFUSED by Lean: `not comparable: preset` (`Fw.Faithful.comparable`), so the band table is descriptive (INFERRED role only).

## Single-flag part pages: Lean verdicts per flag (Chromium only)

Each pair is base against one flag (`only=<part page>`, stage 430x932), 3 shards per arm. Chromium only: the harness runs the per-part counts in Chromium, so WebKit per-part rows are not measured (accepted limit).
There are no per-part rows for engine.scroll and morph.tween (accepted limit). Attribution is MEASURED for every pair: `stageAs` (packages/engine-check/src/wave2.mjs) refuses a page unless every row `part:variant` pair is in the arm's
`meta.rewrite.config.variants` and stages `MEASURED` only when the arm's non-faithful set equals the pair set and the base has none. Classes are the frozen whole-page table, a premise on part pages (`declared-rows-unverified`).

| flag | row, prediction (class) | base > arm, 3 shards each | Lean verdict | runs (base / arm) |
|---|---|---|---|---|
| nav.hitTest:elements-skip | UpdateLayoutTree `<o` (det.) | [2060,2059,2059] > [155,155,155] | pass | 39253271676 / 39253292170 |
| nav.hitTest | PrePaint, HitTest, raster.invalidationAreaPx, cc.Commit (stable/det.) | equal (2868, 1904, 16717200, 963) | pass x4 | same |
| nav.hitTest | FunctionCall, FireAnimationFrame, Layout, Paint (quarantined) | Paint 1977 > 410 | unusable x4 | same |
| pain.notes:visible | UpdateLayoutTree `<=o`, cc.Commit `=o` (det.) | 895 > 895, 713 > 713 | model-bug x2 | 39253313203 / 39257459959 |
| pain.notes | LayoutCount `<=o`, PrePaint `<=o`, raster.invalidationAreaPx `=o` | 198, 1422, 96887306 equal | pass x3 | same |
| pain.notes | FunctionCall, Layout, Layout.dirtyObjects | 3590 / 203 / 4633 equal | unusable x3 | same |
| people.card:mq | UpdateLayoutTree `<=o` (det.) | [895 x3] > [834 x3] | model-bug | 39253313203 / 39257496442 |
| people.card | cc.Commit `=o` (det.) | 713 > 713 | model-bug | same |
| people.card | LayoutCount `=o`, PrePaint `<=o`, raster.invalidationAreaPx `=o` | equal | pass x3 | same |
| people.card | FunctionCall, Layout, Layout.dirtyObjects | quarantined | unusable x3 | same |
| hero.countdown:strip + morph.countdown:strip | census.layers `<o` (stable k=2) | [12960 x3] > [12960 x3] | unusable (strict `<o` on a non-exact class) | 39257533380 / 39259074927 |
| morph.columns:hidden-pause | UpdateLayoutTree, cc.Commit `<=o` (det.) | [1289 x3] > [1289 x3] both | pass x2 | 39259109607 / 39259146065 |
| morph.columns | FireAnimationFrame, Layout `=o` | 0 > 0 | unusable x2 | same |
| morph.mount:shift | LayoutCount `=o`, PrePaint, raster.invalidationAreaPx `=o`, UpdateLayoutTree, cc.Commit | 0, 1939, 386416920, 0, 953 equal | pass x5 (3 of them `any`) | 39259991865 / 39260576409 |
| morph.mount | FunctionCall `any`, Layout, Layout.dirtyObjects | FunctionCall 2471 > 3423 | unusable x3 | same |
| engine.scene:hidden-pause | UpdateLayoutTree `<=o` (460 > 460), cc.Commit `<=o` (935 > 935) (det.) | equal | pass x2 | 39260614233 / 39260841413 |
| engine.scene | FireAnimationFrame `=o` (935), Layout `=o` (128) | equal | unusable x2 | same |
| G2 base vs `preset=v2-proved` | no row variants | see G2 section | not rated | 39261906990 / 39262007729 |

Tally (pass / model-bug / unusable): nav.hitTest 5/0/4; pain.notes 3/2/3; people.card 3/2/3; hero.countdown 0/0/1; morph.columns 2/0/2; morph.mount 5/0/3; engine.scene 2/0/2. Total 20/4/18.

Descriptive readings (MEASURED, no Lean verdict): hero.countdown arm +21 recalcs and +21 commits (UpdateLayoutTree 1161 > 1182), FireAnimationFrame 2649 > 2130, FunctionCall 3813 > 3294; morph.mount arm FunctionCall +952 and no
other off-band type; engine.scene arm equals base in every type but FunctionCall (+3), so the stage page has no hidden state that hidden-pause could act on (INFERRED); morph.columns arm equals base (1 of 57 types, FunctionCall +1).

### Model-bug rows filed, with the C3 consequence

C3 rule: "0 mismatches or each filed as a model bug"; "a falsified prediction that cannot be fixed by C3 drops that flag from v2-proved". Frame lists: `results/integrate-wave-2/engine-check/<page>/frames.json`.

| flag | row | what the frames show (MEASURED) | cause (INFERRED) | C3 consequence |
|---|---|---|---|---|
| pain.notes:visible | UpdateLayoutTree `<=o` | totals equal in all 6 shards; arm shards identical to each other; base shard 0 differs from base shards 1 and 2 (which are identical) in 12 tail frames (698 to 713), 6 above and 6 below | the frozen class `deterministic` does not hold at this page's tail: the base itself has two states there; the flag has no measured effect (0 off-band types) | keep in v2-proved; row filed as class-premise model bug; C3 repairs the class table (tail zone), not the flag |
| pain.notes:visible | cc.Commit `=o` | same 12 frames, totals 713 equal | same | same |
| people.card:mq | UpdateLayoutTree `<=o` | 895 > 834; in the 5 shard pairs where the odd shards (base 0, arm 2) are both present or both absent, the arm is below in 61 frames (145 to 206) and above in none; pairs that include a jittering shard add 12 tail frames (6 above) | the 61-recalc saving is a flag effect in the predicted direction; the 6 "above" frames are the tail jitter (base shard 0 or arm shard 2 is the odd one) | keep; filed as class-premise model bug; C3 repairs the tail-zone class |
| people.card:mq | cc.Commit `=o` | totals 713 equal; only tail frames 698 to 713 differ, and only in shard pairs where exactly one of base shard 0 and arm shard 2 (the two odd shards) is present | same | keep; same |

The jitter is two-state, equal in totals and alternating above and below, and it appears in base shard 0 and in people.card arm shard 2, so it is not a flag effect. A hand-rewritten class would be a decision for C3; this round does not edit the frozen table.

The people.card and g1 rows, recounted after staging: each page now stages only its own single-flag arm (the 3-flag g1 arm of round 0 is not run), so pain.notes reads 3 pass / 2 model-bug / 3 unusable and people.card
3 pass / 2 model-bug / 3 unusable, 8 rows each, with the arms 39257459959 and 39257496442 and the shared base 39253313203.

### Per-flag C3 decision

| flag | decision | basis |
|---|---|---|
| nav.hitTest:elements-skip | keep | 5 pass; UpdateLayoutTree 2060 > 155 deterministic, MEASURED |
| pain.notes:visible | keep | 2 model-bug rows filed (class premise), no effect measured; the prediction `<=o` is met by equality |
| people.card:mq | keep | 2 model-bug rows filed (class premise); recalcs fall by 61 |
| hero.countdown:strip + morph.countdown:strip | keep, prediction unchecked | no usable row; `census.layers <o` reads 12960 = 12960 in every shard, which a frame-exact class could refute; stable k=2 cannot. The lead decides if equality drops it. Strip arm also measured (runs 39257533380 / 39259074927): UpdateLayoutTree, RecalcStyleCount, ScheduleStyleRecalculation 1161 > 1182; cc.Commit, Commit, Layerize, cc.Activate 1064 > 1085; UpdateLayoutTree.elementCount 11264 > 22445; Layout.totalObjects 47161 > 53433; FireAnimationFrame 2649 > 2130. No row predicts these types: descriptive MEASURED, not a Lean verdict |
| morph.columns:hidden-pause | keep | 2 pass, equal to base (weak) |
| morph.mount:shift | keep | 5 pass (3 `any`); arm adds 952 FunctionCall (quarantined, no claim) |
| engine.scene:hidden-pause | keep | 2 pass, weak (no hidden state on the stage page); the platform gate failure is not this flag (default arm identical) |
| engine.scroll, morph.tween | keep, unmeasured per part | no part page (accepted limit) |

No flag meets the drop rule: no prediction is falsified by a flag effect. The gate failure (platform will-change) must be resolved on main before C3 can read the gate as pass; that is not a flag decision.

## G2 (commission, platform, nav, panel), base vs `preset=v2-proved`

Round 0 was refused by the viewport gate (443 px frame at a 430 px viewport); with main's host-frame change (eed1eb1a, overflow-430) both runs are measured: base 39261906990 (`?only=g2&stage=vw:430,vh:932`), arm 39262007729
(`?preset=v2-proved&only=g2&stage=vw:430,vh:932`). Attribution INFERRED (a preset arm; PLAN 10.7 open bridge). Attribution INFERRED written by hand: the check path skips pages without row variants before stageAs (follow-up). 862 frames in both. 11 of 71 types are off-band (4 above, 7 below):

| type | base > arm | where |
|---|---|---|
| trace.UpdateLayoutTree | 2476 > 833 | below |
| metric.RecalcStyleCount | 2458 > 815 | below |
| trace.ScheduleStyleRecalculation | 2492 > 849 | below |
| trace.Paint | 2338 > 1369 | below |
| trace.FunctionCall | 2872 > 3697 | above |
| trace.Animation.compositeFailedBits | 1245536 > 1278432 | above |

No row variants exist for the preset arm, so no Lean verdict: descriptive. cc.Commit 834 = 834, census.layers 16306 = 16306, FireAnimationFrame 1382 = 1382 (within band). Per-part rows are not summed from this page.

## Totals pilot (descriptive, not F6; PLAN 4.8 limit 4)

INFERRED. Combined = v2-proved against base on the whole page, swipe-v1 (39253166643 / 39253172750, 503 frames); parts = the 7 single-flag pairs above. Raw whole-run deltas, summed. PLAN 4.8: units compose and
passes do not; F6 is per (part, stage, zone) on units only and is `compose-check` after C3, so this pilot is not the F6 verdict. Parts cover 8 of 10 flags (no engine.scroll, morph.tween), and the part pages run
different trajectories (503 frames whole page; 1085, 992, 727, 727, 1329, 992, 975 for the parts).

- 48 types moved on at least one page: 11 are pass types (UpdateLayoutTree, RecalcStyleCount, ScheduleStyleRecalculation, LayoutCount, Layout, Layout.partial, PrePaint, Paint, cc.Commit, FireAnimationFrame, UpdateLayer;
  a TS stand-in name list, not covered by F6) and 37 are other. Of the 37, 24 have a class margin and 13 are quarantined.
- Of the 24 with a margin: 1 additive within the strict margin (trace.MinorGC, stable k=4: combined -2, sum +2, residual -4), 2 within the widened margin (margin x (parts + 1): MinorGC and trace.PaintImage, combined +4, sum 0),
  22 not additive at totals (11 deterministic: Animation.compositeFailedBits -73600 vs -106496, Animation.instant -9 vs -13, Animation.begin -3 vs 0, Commit/CullRectUpdate/Layerize/cc.Activate 0 vs +21, ...; 11 stable: the census, raster and metric.Resources rows). compositeFailedBits matches on the per-frame rate (rateWithin10pct true), not only the style family.
- Pass types, actual deterministic values: UpdateLayoutTree combined -1011, parts [+21, -1904, 0, -61, 0, 0, 0] (sum -1944, residual +933); RecalcStyleCount same; cc.Commit combined 0, parts [+21, 0, 0, 0, 0, 0, 0] (sum +21).
  Per frame, the style family reads -2.01 combined against -1.98 for the parts' sum (within 10 percent, my threshold, not a class margin).
- census.layers combined +1054, parts [0, 0, 0, -1, 0, 0, +2] (sum +1): the layer promotion comes from something the part pages do not contain (engine.scroll or morph.tween, or the interaction of flags), INFERRED.
- Compose-check after C3 is the verdict that counts; the pilot only says totals over unequal trajectories do not add, and per-frame rates do on the style family.

## Staging guard and attribution

`stageAs(baseFiles, armFiles, armVariants, part)` stages a page only when every row `part:variant` pair (bare variants such as `hidden-pause` expanded with the page's `part`) is in each arm file's
`meta.rewrite.config.variants`, otherwise it throws (`arm file <path> did not run <pair>; not staged`). It writes attribution itself: MEASURED when the arm's non-faithful set equals the pair set and the base has none, INFERRED for
a preset arm. One guard, one test (`packages/engine-check/test/wave2.test.mjs`). The 7 pages above all read MEASURED.

## TS stand-ins (to move into Lean)

`packages/engine-check/src/wave2.mjs` (every verdict above marked Lean's is fwcore's): `totalsOf`, `median`, `deltaRow`, `bandCells`, `confounds`, `stageAs` and its helpers `pairsOf` and `nonFaithful` (the guard and the attribution tag),
`PASS_TYPES` (a regex name list of the pass types), `frameDiff`, the `f6` totals pilot, and the run-to-variant mapping (`results/integrate-wave-2/plan.json`). No Lean twin exists for any of them.

## Limits

- WebKit per-part rows not measured. No per-part rows for engine.scroll or morph.tween. The F6 verdict is compose-check after C3. WebKit phone-rotation cells and the 291 excused cells are identical to wave 1 (excused only for that reason).
- The frozen classes are a premise on part pages; the tail of the g1 page shows two states in the base itself (base shard 0 of 39253313203).
- Counts are work, not milliseconds; no phone time. 3 shards per arm, one workflow run per arm.
- plan.json: `zones/` and `faithful/runs-*` hold the same baseline blobs twice on purpose (zones/ feeds zonecmp, faithful/runs-* feeds `Fw.Faithful`; each directory stands alone).

## Appendix: round 0 (built from ef8b2cd3), superseded

Run ids only; the numbers in the round-0 note are void. Gate v2-proved 39220947437, gate default 39220962049 and 39230139617; counts swipe-v1 base / v2-proved 39224113958 / 39224078326, swipe-touch-v1
39224678606 / 39224091514; part pages hero.countdown 39225528196 / 39225547720, nav.hitTest 39225578464 / 39226582881, g1 39226593120 (arms 39226604309 3-flag, 39228396423 pain.notes, 39228407395 people.card),
platform 39227563060 / 39227571736, columns 39228387861 / 39229363194; G2 39224697587 / 39224735485 and morph.mount base 39227583530 (both refused by the viewport gate).
