---
id: 2026-10-23-hero-copy-floor-sources
kind: note
title: "hero_copy A/A floor sources: hero_copy A/A inside the mask is 0 in all 6 jobs (Chromium by pins, WebKit by the Lean ownership rule for deck-card corner pixels), occluded cells skipped"
status: measured
created: 2026-10-23
topics: [pathpix, webkit, chromium, hero.accent, hero.countdown, a-a-floor, measurement]
---

# hero_copy A/A floor sources

Tasks `hero-copy-floor-sources` (run 39985824264, branch `ci/hero-copy-floor-sources`) and its follow-ups
`hero-copy-floor-followups` (branch `ci/hero-copy-floor-followups`, workflow `path-pix`, **run 40007968162**, success after the
failed job `sim (2)` was re-run once: its first attempt died in `simctl list devices` with ETIMEDOUT, a runner fault before any
page ran). Every table below is from run 40007968162. 3 jobs per engine (WebKit Simulator `webkit-1..3`, Chromium `chromium-1..3`), mode `exit`, flag `hero.exit:threaded`. Every
table below is printed by `packages/measure-webkit/src/pathpix-exit-report.mjs` from the artifacts' `cells.json` and manifests
(no number typed by hand). Statuses: CONFIRMED (source or test), MEASURED (run),
INFERRED. Run 39971881582 (round 0, same code without the ownership rule) is the before: its WebKit hero_copy A/A had 48-1 in
webkit-2 and 23-1 in webkit-3 at offset 0. This note replaces the "remaining floor sources" list of
`10-2x-pathpix-accent-pin.md`. The look review is the user's; no phone was used, strips stay CI artifacts.

**Two corrections.** (1) `10-2x-pathpix-accent-pin.md` says the misplaced row was "offset index 7 (y 855)": the row is offset
index 7 with arm A at scrollY 0 and arms A2 and P at 855 (accent re-created). This run has 0 misplaced rows in all 6 jobs, so
the validity rule (Lean `AccentRow.placed`: scrollY must equal the offset) did not fire; a lane test covers it. (2) The
round-0 version of this note called the WebKit y 0 change the "countdown tile top edge". The tiles are at CSS y
364..452 (manifest `div[hero-countdown]`), while the changed box (device px, dpr 3) x 123..1164, y 1607..1626 is CSS y 536, the
top corners of the left and right hero deck cards (cells.json of run 39971881582: `hero.deck_article#0` A/A inside 24-1 at
123,1607,143,1624, `#2` 24-1 at 1144,1607,1164,1624 in webkit-2; webkit-3 `#2` 148-2 and `#3` 47-2). The "three face spans" the
report named were hidden countdown faces: hero_copy's mask is the union of all its element boxes (hidden faces included), so it reaches
into the card corners.

## Source by source

| source | outcome | status |
|---|---|---|
| countdown seconds digit (`hero.countdown` reads `Date.now` at mount; the capture shim's clock is virtual) | `Date.now` pinned to the epoch in exit mode (Chromium and WebKit): constant in every row of all 6 jobs (pin table); Chromium hero_copy A/A is 0-0 in all 3 jobs | MEASURED, pin tested |
| WebKit y 0 (A/A 48-1 and 23-1 in round 0; runs 39985824264 and 40007968162: hero_copy A/A inside 0-0 in 6 of 6 jobs) | the pixels are the antialiased top corners of the rotated, rounded deck cards, which hero_copy's union mask overlaps. Source read: a rounded `overflow:hidden` layer is clipped by Core Animation, not by WebKit paint (`GraphicsLayerCA::updateClippingStrategy`, `GraphicsLayerCA.cpp:3218-3262@862f17d`: uniform radius sets `masksToBounds` plus `cornerRadius` on the CA layer, otherwise a shape-mask layer), so the corner antialiasing is the render server's, no WebKit or page setting pins it without changing the faithful page (cards stay rotated and rounded). Not pinned. Masked by the Lean ownership rule: hero_copy does not count a changed pixel that lies in the mask of another graded layer; that layer counts it (Lean `foreignMasks`, `countedIn`, `countedIn_shared`, `countedIn_other_layer`, `shared_accounted` in `lean/Fw/Gate/PathPix.lean`; golden kind `foreign` in `path-pix.jsonl`). Follow-up 1 (a receiving cell counts the yielded pixel): `receiver_counts`, `hero_yields_to_receiver`, `yielded_counted_by_receiver` (hero_copy's cell does not count it and the receiver's key is in `countedBy`) and `inside_some_mask_counted` (no pixel inside any mask is counted by nobody) in `lean/Fw/Gate/PathPix.lean`, `yieldCases` with a `#guard`, golden kind `yield` in `path-pix.jsonl` replayed by `test/pathpix.test.mjs`; the receiving cells' P grade is printed beside the "counted by another layer" tables. In run 40007968162 webkit-1 and webkit-3 show A/A 48-1 at offset 0 left to the deck cells, which count them (receiving cells in the "counted by another layer" table: `hero.deck_article#0` A/A inside 24-1 and `#2` 24-1 in both jobs, grade L); webkit-2 shows no A/A change there (its P is 16703-42 left to the deck cells, receivers `#0` 35675-45 and `#2` 24-1). The cause of the variation is INFERRED. Follow-up 4 (sourced negative): contentsScale is `pageScale * deviceScaleFactor * limitingFactor` (`GraphicsLayerCA::updateContentsScale`, `GraphicsLayerCA.cpp:4411-4430@862f17d`); the limiting factor applies only above `cMaxScaledTiledLayerMemorySize` = 156 MiB (`GraphicsLayerCA.cpp:115`, `1739-1767@862f17d`) and the deck layers are about 1.3 MB; root-relative scale updates are off unless `setShouldUpdateRootRelativeScaleFactor(true)`, which only layout-based SVG layers set (`RenderLayerBacking.cpp:452-453`, `GraphicsLayerCA.cpp:4380-4386@862f17d`); the `customContentsScale` client hook is not overridden in WebCore. The clip itself is the CA layer's `masksToBounds` plus `cornerRadius` (`PlatformCALayerCocoa.mm`, `setCornerRadius`, `setAntialiasesEdges`), antialiased by the render server. The committed artifacts of run 39985824264 show the same DOM box values, deck layer bounds, memory estimates, layer count 110, compositing reasons, dpr 3.000 and `tries` 2 in arms A and A2 and in all three jobs, including webkit-3 where the deck corners differ (24-1, 33-1, 142-2, 47-2). The harness already requires two identical consecutive screenshots (`captureArm` in `pathpix-exit-webkit.mjs`). So no page-side or capture-side input differs and no pin exists; the remaining variation lies in the Simulator render server (INFERRED). Masked by ownership, not pinned. The floor stays above 0 in the deck-card cells, not in hero_copy | CONFIRMED (Lean, test, source), MEASURED (table), INFERRED (cause of the variation) |
| WebKit y 812/813 avatar art under hero_copy | y 812 (Chromium y 885) skipped as occluded by opaque foreign content in both arms (cover grid, 7x7 per layer) in all 6 jobs; y 813: 0 changed pixels inside the mask for A/A in all 3 jobs. Follow-up 3, the P-only 2-1 column of run 39985824264 (webkit-1, 1 x 16 px at device x 873, y 118..134, outside every mask): its element is the language switch `button.switch` of `[data-fw="nav-lang"]` in the `nav_bar` layer. At scrollY 813 the recorded boxes (manifest.json samples A, A2 and P at scrollY 813, probes["nav-lang button"], all 3 WebKit jobs of run 40007968162, micro-CSS px; read from the artifacts, not printed by the report script, whose probe table shows arm A at scrollY 0, device x 999..1218) put it at CSS x 218.59..291.59, y 24..60, i.e. device x 655.8..874.8, y 72..180 at dpr 3, so x 873 is the right-edge arc of its 1 px translucent border and the y 118..134 pixels sit at the vertical middle; the next button (`nav-earn`) starts at device x 886.8. The element is INFERRED (box MEASURED in run 40007968162, where the column did not recur; the match assumes the same nav layout at scrollY 813 in run 39985824264), the arc and the P-only cause (the pill has `backdrop-filter: blur(12px)` over a translucent background, so content under it can change one level) are INFERRED. The 2-1 did not recur in this run (webkit-1 P 0-0 at offset 5); instead webkit-3 shows an A/A outside change at offset 5, 4478-2 at device 887,72,1218,180, the box of `nav-earn` (probe-touch column: nav and nav-earn), outside every mask. So the nav row at scrollY 813 varied in 2 of the 6 WebKit jobs of the two runs (1 per run), by 1 or 2 levels, at the nav-lang and nav-earn buttons | MEASURED (boxes), INFERRED (element match, arc, cause) |
| accent word | site hook `?fwpin=accent` (inert when unset, jsdom hydration test) replaces the capture-side DOM swap; accent-unpinned cells 0 in all 6 jobs | MEASURED, CONFIRMED (test) |

## Where the L comes from (hero_copy P cells)

The summary tables list, per P cell, the grade, its source and the grade if strips were accepted. The source is "strips not
accepted" only when strips would change the grade (the cell would be Q); with an inside change above the floor and none
outside the source is "inside, above the floor"; any change outside the mask labels the cell "outside the mask" first. In
this run one cell is labelled "inside, above the floor": webkit-3 offset 5 (ask y 813), 192513-20 inside hero_copy's mask with
A/A inside 0-0 (0 of 15 in Chromium, 1 of 15 in WebKit; webkit-1 and webkit-2 are 0-0 at that offset). The strip
`strips/P_hero_copy_5.png` of artifact `path-pix-webkit-3` shows the changed pixels on the red deck-card artwork (the
"MUSIC COMPOSER" lettering) in the lower part of the mask; no deck cell is graded at offset 5 (only `hero.cue_cue` and
hero_copy are), so no other layer receives them and hero_copy counts them. Cause INFERRED (a differently rasterised card
artwork in P in one job of three); it does not repeat in the other two jobs, so it is not stable and needs an A3 arm or a
second run to classify. Chromium offset 0 does have an inside change
above the floor 0 (273-1, delta 1) but its row also changes outside the mask (80-1), so the label is "outside the mask" and the
grade if strips were accepted is L. Chromium offset 1: the 87 pixels at delta 12 that round 0 counted inside hero_copy
(`87-12`, A/A 0-0, "L from an inside change above the floor") now lie in other layers' masks, so they are counted by those
layers and hero_copy's own cell is 0-0 (L only because strips are not accepted, Q if accepted).

## webkit

#### webkit: hero_copy summary over 3 jobs

| P cells | E | E1 | Q | L | invalid | L: strips not accepted | L: inside, above the floor | L: outside the mask | A/A cells | A/A with a change inside | A/A with a change outside | skipped (reason) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 15 | 0 | 0 | 0 | 15 | 0 | 8 | 1 | 6 | 15 | 0 | 1 | occluded by opaque foreign content in both arms x6; transparent in both arms x18 |

#### webkit: hero_copy per job and offset

| offset | ask y | webkit-1 A/A in/out | webkit-1 P in/out | webkit-1 P grade (source) [if strips accepted] | webkit-2 A/A in/out | webkit-2 P in/out | webkit-2 P grade (source) [if strips accepted] | webkit-3 A/A in/out | webkit-3 P in/out | webkit-3 P grade (source) [if strips accepted] |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] |
| 1 | 1 | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] |
| 2 | 213 | 0-0/0-0 | 0-0/1833-2 | L (outside the mask) [L] | 0-0/0-0 | 0-0/1833-2 | L (outside the mask) [L] | 0-0/0-0 | 0-0/1833-2 | L (outside the mask) [L] |
| 3 | 427 | 0-0/0-0 | 0-0/2744-1 | L (outside the mask) [L] | 0-0/0-0 | 0-0/2744-1 | L (outside the mask) [L] | 0-0/0-0 | 0-0/2744-1 | L (outside the mask) [L] |
| 4 | 812 | skipped: occluded by opaque foreign content in both arms | skipped: occluded by opaque foreign content in both arms | - | skipped: occluded by opaque foreign content in both arms | skipped: occluded by opaque foreign content in both arms | - | skipped: occluded by opaque foreign content in both arms | skipped: occluded by opaque foreign content in both arms | - |
| 5 | 813 | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/4478-2 | 192513-20/0-0 | L (inside, above the floor) [L] |
| 6 | 854 | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - |
| 7 | 855 | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - |
| 8 | 856 | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - |

#### webkit: hero_copy changes inside the mask

| job | offset | kind | inside chg-max | box (device px) | parts the box touches |
|---|---|---|---|---|---|
| webkit-3 | 5 | P | 192513-20 | 63,1112,1227,1658 | div[hero-countdown].hero-module_countdown_HKvRcv, span.hero-module_face_B0Q0e9 x23 |

#### webkit: hero_copy pixels counted by another layer

Reason: a pixel inside another graded layer's mask is counted by that layer's cell, not by hero_copy: hero_copy's mask is the union of all its element boxes, hidden countdown faces included, and can overlap the masks of other layers

| job | offset | kind | changed pixels left to other layers (chg-max) | receiving cells in the same job, offset and kind: grade (source), inside chg-max | changes outside every mask: box (device px) | probe elements the outside box touches |
|---|---|---|---|---|---|---|
| webkit-1 | 0 | A/A | 48-1 | hero.deck_article#0: L, inside 24-1; hero.deck_article#2: L, inside 24-1 | - | none |
| webkit-1 | 2 | P | 0-0 | - | 1833-2 at 505,2048,785,2138 | none |
| webkit-1 | 3 | P | 0-0 | - | 2744-1 at 476,2023,804,2155 | none |
| webkit-2 | 0 | P | 16703-42 | hero.deck_article#0: L (inside, above the floor), inside 35675-45; hero.deck_article#2: L (strips not accepted), inside 24-1 | - | none |
| webkit-2 | 2 | P | 0-0 | - | 1833-2 at 505,2048,785,2138 | none |
| webkit-2 | 3 | P | 0-0 | - | 2744-1 at 476,2023,804,2155 | none |
| webkit-3 | 0 | A/A | 48-1 | hero.deck_article#0: L, inside 24-1; hero.deck_article#2: L, inside 24-1 | - | none |
| webkit-3 | 2 | P | 0-0 | - | 1833-2 at 505,2048,785,2138 | none |
| webkit-3 | 3 | P | 0-0 | - | 2744-1 at 476,2023,804,2155 | none |
| webkit-3 | 5 | A/A | 0-0 | - | 4478-2 at 887,72,1218,180 | nav 48,48,1242,204; nav-earn 886.8,72,1218,180 |

## chromium

#### chromium: hero_copy summary over 3 jobs

| P cells | E | E1 | Q | L | invalid | L: strips not accepted | L: inside, above the floor | L: outside the mask | A/A cells | A/A with a change inside | A/A with a change outside | skipped (reason) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 15 | 0 | 0 | 0 | 15 | 0 | 6 | 0 | 9 | 15 | 0 | 0 | occluded by opaque foreign content in both arms x6; transparent in both arms x18 |

#### chromium: hero_copy per job and offset

| offset | ask y | chromium-1 A/A in/out | chromium-1 P in/out | chromium-1 P grade (source) [if strips accepted] | chromium-2 A/A in/out | chromium-2 P in/out | chromium-2 P grade (source) [if strips accepted] | chromium-3 A/A in/out | chromium-3 P in/out | chromium-3 P grade (source) [if strips accepted] |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0-0/0-0 | 273-1/80-1 | L (outside the mask) [L] | 0-0/0-0 | 273-1/80-1 | L (outside the mask) [L] | 0-0/0-0 | 273-1/80-1 | L (outside the mask) [L] |
| 1 | 1 | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] |
| 2 | 233 | 0-0/0-0 | 0-0/2-1 | L (outside the mask) [L] | 0-0/0-0 | 0-0/2-1 | L (outside the mask) [L] | 0-0/0-0 | 0-0/82-2 | L (outside the mask) [L] |
| 3 | 466 | 0-0/0-0 | 0-0/796-1 | L (outside the mask) [L] | 0-0/0-0 | 0-0/796-1 | L (outside the mask) [L] | 0-0/0-0 | 0-0/741-1 | L (outside the mask) [L] |
| 4 | 885 | skipped: occluded by opaque foreign content in both arms | skipped: occluded by opaque foreign content in both arms | - | skipped: occluded by opaque foreign content in both arms | skipped: occluded by opaque foreign content in both arms | - | skipped: occluded by opaque foreign content in both arms | skipped: occluded by opaque foreign content in both arms | - |
| 5 | 886 | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] |
| 6 | 931 | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - |
| 7 | 932 | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - |
| 8 | 933 | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - |

#### chromium: hero_copy changes inside the mask

| job | offset | kind | inside chg-max | box (device px) | parts the box touches |
|---|---|---|---|---|---|
| chromium-1 | 0 | P | 273-1 | 70,205,357,648 | h1.hero-module_title_4Q4gSp, em[hero-accent].accent-module_accent_whUL9E, svg x3, p, div[hero-countdown].hero-module_countdown_HKvRcv, span.hero-module_face_B0Q0e9 x33 |
| chromium-2 | 0 | P | 273-1 | 70,205,357,648 | h1.hero-module_title_4Q4gSp, em[hero-accent].accent-module_accent_whUL9E, svg x3, p, div[hero-countdown].hero-module_countdown_HKvRcv, span.hero-module_face_B0Q0e9 x33 |
| chromium-3 | 0 | P | 273-1 | 70,205,357,648 | h1.hero-module_title_4Q4gSp, em[hero-accent].accent-module_accent_whUL9E, svg x3, p, div[hero-countdown].hero-module_countdown_HKvRcv, span.hero-module_face_B0Q0e9 x33 |

#### chromium: hero_copy pixels counted by another layer

Reason: a pixel inside another graded layer's mask is counted by that layer's cell, not by hero_copy: hero_copy's mask is the union of all its element boxes, hidden countdown faces included, and can overlap the masks of other layers

| job | offset | kind | changed pixels left to other layers (chg-max) | receiving cells in the same job, offset and kind: grade (source), inside chg-max | changes outside every mask: box (device px) | probe elements the outside box touches |
|---|---|---|---|---|---|---|
| chromium-1 | 0 | P | 153-13 | hero.deck_article#0: L (outside the mask), inside 1489-15; hero.deck_article#2: L (outside the mask), inside 1372-15 | 80-1 at 55,745,374,809 | none |
| chromium-1 | 1 | P | 87-12 | hero.deck_article#0: L (inside, above the floor), inside 1061-15; hero.deck_article#2: L (inside, above the floor), inside 935-15 | - | none |
| chromium-1 | 2 | P | 0-0 | - | 2-1 at 10,750,419,753 | none |
| chromium-1 | 3 | P | 0-0 | - | 796-1 at 161,815,268,858 | none |
| chromium-2 | 0 | P | 153-13 | hero.deck_article#0: L (outside the mask), inside 1489-15; hero.deck_article#2: L (outside the mask), inside 1372-15 | 80-1 at 55,745,374,809 | none |
| chromium-2 | 1 | P | 87-12 | hero.deck_article#0: L (inside, above the floor), inside 1061-15; hero.deck_article#2: L (inside, above the floor), inside 935-15 | - | none |
| chromium-2 | 2 | P | 0-0 | - | 2-1 at 10,750,419,753 | none |
| chromium-2 | 3 | P | 0-0 | - | 796-1 at 161,815,268,858 | none |
| chromium-3 | 0 | P | 153-13 | hero.deck_article#0: L (outside the mask), inside 1489-15; hero.deck_article#2: L (outside the mask), inside 1372-15 | 80-1 at 55,745,374,809 | none |
| chromium-3 | 1 | P | 87-12 | hero.deck_article#0: L (inside, above the floor), inside 1061-15; hero.deck_article#2: L (inside, above the floor), inside 935-15 | - | none |
| chromium-3 | 2 | P | 0-0 | - | 82-2 at 10,750,419,850 | none |
| chromium-3 | 3 | P | 0-0 | - | 741-1 at 161,815,268,858 | none |

#### Page clock, accent pin and row placement per job

| job | run | Date.now in every row | cells | accent-unpinned | misplaced | occluded skips |
|---|---|---|---|---|---|---|
| webkit-1 | 40007968162 | constant (1790787600000) | 48 | 0 | 0 | 4 |
| webkit-2 | 40007968162 | constant (1790787600000) | 48 | 0 | 0 | 4 |
| webkit-3 | 40007968162 | constant (1790787600000) | 48 | 0 | 0 | 4 |
| chromium-1 | 40007968162 | constant (1790787600000) | 48 | 0 | 0 | 4 |
| chromium-2 | 40007968162 | constant (1790787600000) | 48 | 0 | 0 | 4 |
| chromium-3 | 40007968162 | constant (1790787600000) | 48 | 0 | 0 | 4 |

#### Probe elements outside the graded layers

| job | probe element | device box x0,y0,x1,y1 (arm A, first offset) |
|---|---|---|
| webkit-1 | nav | 48,48,1242,204 |
| webkit-1 | nav-lang | 999,72,1218,180 |
| webkit-1 | nav-lang button | 999,72,1218,180 |
| webkit-1 | nav-earn | 1218,72,1218,180 |
| webkit-1 | nav logo | 96,91.1,370.5,160.9 |
| webkit-2 | nav | 48,48,1242,204 |
| webkit-2 | nav-lang | 999,72,1218,180 |
| webkit-2 | nav-lang button | 999,72,1218,180 |
| webkit-2 | nav-earn | 1218,72,1218,180 |
| webkit-2 | nav logo | 96,91.1,370.5,160.9 |
| webkit-3 | nav | 48,48,1242,204 |
| webkit-3 | nav-lang | 999,72,1218,180 |
| webkit-3 | nav-lang button | 999,72,1218,180 |
| webkit-3 | nav-earn | 1218,72,1218,180 |
| webkit-3 | nav logo | 96,91.1,370.5,160.9 |

## Consensus capture (task pathpix-consensus-capture, run 40026419647)

Branch `ci/pathpix-consensus-capture`, workflow `path-pix`, commit `eae3bfab5`, success at the first attempt (no re-run), 3 jobs per
engine. Every table in this section is printed by `packages/measure-webkit/src/pathpix-exit-report.mjs` from the artifacts of that
run (`consensusSummary`, `consensusCells`, `probeTable`); no number is typed by hand. Statuses as above.

**Rule (CONFIRMED, Lean).** WebKit now captures three identical arms before P: A, A2, A3 (`pinArms` in `lean/Fw/Gate/PathPix.lean`).
Per P cell and per zone (outside every mask, inside the layer's mask) a zone is `counted` when P differs from A there and A vs A2
and A vs A3 both changed 0 pixels there (`Zone.agree`, `Zone.seen`); `varied` when P differs and an identical-arm pair also differs;
`quiet` when P matches A. A cell with a `varied` zone gets the verdict `varied` and is not graded; otherwise it keeps its grade
(`verdict`, `consensus`, theorems `verdict_varied_iff`, `verdict_graded_iff`, `seen_varied_of_a2`, `seen_varied_of_a3`,
`seen_dropping_a3`; 78 golden lines of kind `consensus`, plus kinds `seen` and `probeHit`, replayed by `test/pathpix.test.mjs`). A cell
without A3 (Chromium) is decided by A2 alone. `probesHit` has a Lean twin now (`probeHit`, `probesHit`, `probeHit_iff`,
`probesHit_mem`, golden kind `probeHit`); the TS version uses integer micro-CSS px so it matches the Lean `Int` boxes.

**Result per job (MEASURED, run 40026419647).**

| job | A3 captured | P cells | counted | varied | quiet | E | E1 | Q | L | invalid | varied | no consensus data |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| webkit-1 | yes | 24 | 11 | 3 | 10 | 0 | 0 | 0 | 21 | 0 | 3 | 0 |
| webkit-2 | yes | 24 | 13 | 0 | 11 | 0 | 0 | 0 | 24 | 0 | 0 | 0 |
| webkit-3 | yes | 24 | 12 | 2 | 10 | 0 | 0 | 0 | 22 | 0 | 2 | 0 |

| job | A3 captured | P cells | counted | varied | quiet | E | E1 | Q | L | invalid | varied | no consensus data |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| chromium-1 | no | 24 | 21 | 0 | 3 | 0 | 0 | 0 | 24 | 0 | 0 | 0 |
| chromium-2 | no | 24 | 21 | 0 | 3 | 0 | 0 | 0 | 24 | 0 | 0 | 0 |
| chromium-3 | no | 24 | 21 | 0 | 3 | 0 | 0 | 0 | 24 | 0 | 0 | 0 |

Chromium has no A3 yet (its capture is `packages/measure-chromium/src/pathpix.mjs`, outside this task's writes; the arm list there
needs one more entry), so its table is decided by A2 alone; its A/A is 0-0 everywhere, so every changed cell is `counted`.

**Cells whose verdict is not their grade, and the offset 5 hero_copy cells (MEASURED).** Columns: P grade, verdict, P inside / outside
(changed pixels - max delta), A vs A2, A vs A3, zone seen.

| job | consumer | offset | ask y | P grade | verdict | P inside / out (chg-max) | A vs A2 inside / out | A vs A3 inside / out | inside | outside |
|---|---|---|---|---|---|---|---|---|---|---|
| webkit-1 | hero.cue_cue | 0 | 0 | L | varied | 2769-56 / 0-0 | 1965-6 / 0-0 | 1965-6 / 0-0 | varied | quiet |
| webkit-1 | hero.cue_cue | 5 | 813 | L | varied | 0-0 / 2015-5 | 0-0 / 2015-5 | 0-0 / 2017-5 | quiet | varied |
| webkit-1 | hero_copy | 5 | 813 | L | varied | 192513-20 / 2015-5 | 192513-20 / 2015-5 | 192513-20 / 2017-5 | varied | varied |
| webkit-2 | hero_copy | 5 | 813 | L | L | 192513-20 / 0-0 | 0-0 / 0-0 | 0-0 / 0-0 | counted | quiet |
| webkit-3 | hero.deck_article#0 | 0 | 0 | L | varied | 35651-45 / 0-0 | 24-1 / 0-0 | 24-1 / 0-0 | varied | quiet |
| webkit-3 | hero.deck_article#1 | 0 | 0 | L | varied | 2004-11 / 0-0 | 33-1 / 0-0 | 33-1 / 0-0 | varied | quiet |

- **webkit-1, offset 5 (hero_copy and hero.cue_cue):** the identical arms differ by the amount P differs (hero_copy inside 192513-20
  in A vs A2 and A vs A3; outside 2015-5 vs A2 and 2017-5 vs A3), so the verdict is `varied` and the cell is not graded. A2 and A3
  differ from each other outside (2015 vs 2017 pixels), so the three identical arms do not even agree on one image. P shows the same
  inside count and delta as the identical arms, so A is the odd one out (INFERRED from the equal counts; the report has no pixel-level
  A2 vs P column).
- **webkit-2, offset 5, hero_copy:** P differs inside by 192513-20 while A, A2 and A3 agree (0-0), so the cell is `counted` and keeps
  grade L. The same 192513-20 appears as A/A in webkit-1: one changed-pixel count and delta in two jobs, once as A/A and once as
  P-only, suggests an alternate raster of the red deck-card artwork that any arm can land on (INFERRED). With A as the only reference, a
  P cell that lands on the alternate while A, A2 and A3 do not is counted.
- **webkit-3, offset 5:** 0-0 in all arms and zones (quiet). The cells the task named there (hero_copy P 192513-20 inside, and the
  A/A 4478-2 outside every mask at nav-earn) did not recur in webkit-3 of this run: the first moved to webkit-1 (as A/A and P) and
  webkit-2 (as P), the second appears in no job (no 4478 in any table). So these two cells could not be classed in the same job they
  were seen in; the class of the 192513-20 raster is shown per job above, and the 4478-2 nav-earn change stays open.
- **webkit-1 offset 0 hero.cue_cue; webkit-3 offset 0 hero.deck_article#0 and #1:** A vs A2 and A vs A3 change by the same small count
  (1965-6, 24-1, 33-1) while P changes by more (2769-56, 35651-45, 2004-11). The verdict `varied` hides the part of P above that floor
  (accepted limit 2 below).
- The outside change at offset 5 (2015-5 / 2017-5) lies at device x 1239..1290, y 1125..1658 (the "counted by another layer" table of
  the report shows `none` for probe elements there); the nav probes are at y 72..180, so it is not the nav row.

**Probe boxes at the asked scrollY (MEASURED).** For each job the report prints the offsets that have a change outside every mask, with
the asked y, the recorded scrollY and the box of every probe element at that scrollY (arm A of that offset). Here the asked y equals
the scrollY in every WebKit row. The nav-earn box is 1218,72,1218,180 (zero width) at scrollY 213 and 427 and 886.8,72,1218,180 at
scrollY 813 (webkit-1 rows shown; all other rows are in the report):

| job | offset | ask y | scrollY | probe element | device box x0,y0,x1,y1 (arm A at that offset) |
|---|---|---|---|---|---|
| webkit-1 | 5 | 813 | 813 | nav | 48,48,1242,204 |
| webkit-1 | 5 | 813 | 813 | nav-lang | 655.8,72,874.8,180 |
| webkit-1 | 5 | 813 | 813 | nav-lang button | 655.8,72,874.8,180 |
| webkit-1 | 5 | 813 | 813 | nav-earn | 886.8,72,1218,180 |
| webkit-1 | 5 | 813 | 813 | nav logo | 96,91.1,370.5,160.9 |

**Accepted limits (CONFIRMED by the rule; the consequences INFERRED).** (1) No majority reference: A stays the reference, so a cell
where A is the odd one out is `varied`, not re-referenced to A2 = A3. (2) A cell whose only P differences lie where the identical arms
disagree is not counted, even when P changes more than the identical arms do (the three cells above); the report prints the old grade
next to the verdict. (3) Chromium has no A3 until its arm list gets one entry. (4) `partsHit` (the CSS-px part lookup behind the
"parts the box touches" column) remains a TS stand-in with no Lean twin; `probesHit` has one. (5) One run, 3 jobs per engine: the
class of the 192513-20 raster state needs another run or a majority reference. No phone; the look review is the user's.

## Follow-up for the user's look review (class look-change)

With `hero.exit:threaded` at rest (offset 0, no scroll), Chromium P differs from A in hero_copy's union mask by 426 changed
pixels with maximum delta 13 (round 0 table: `426-13/80-1` in all 3 jobs). Runs 39985824264 and 40007968162 (same numbers) split them by owner: 273 pixels at
delta 1 inside hero_copy proper (h1, accent word, countdown faces, box 70,205,357,648) and 153 pixels at delta 13 that lie in
other graded layers' masks (the deck-card tops; those layers count them, see the "counted by another layer" table). Chromium
offset 1 has the same shape: 87 pixels at delta 12, all in other layers' masks, hero_copy inside 0-0. At rest the exit consumer
therefore changes the look of the page against the faithful arm in both hero_copy and the deck cards, which makes it a
look change at rest: class look-change, for the user's visual review (strips `P_hero_copy_0.png` and the deck strips of this
run's artifacts). Chromium A/A is 0-0 everywhere, so these are real P differences, not floor.

## Open

- WebKit deck-card corner pixels vary between identical arms in 2 of 3 jobs of run 40007968162 (webkit-1, webkit-3; round 0: 2 of 3; run 39985824264: 1 of 3). Pinning is closed as a sourced negative (see the y 0 row): no page-side or capture-side input differs, the variation is in the Simulator render server (INFERRED). The deck cells carry it as their floor; hero_copy does not count it. The consensus capture (A, A2, A3) of run 40026419647 now separates these cells per job (section "Consensus capture").
- Follow-up 3 is closed at box level (the language switch `button.switch`, `nav_bar` layer); the arc and the one-level cause are INFERRED, and the 2-1 did not recur, so the identification rests on the recorded box and the earlier strip.
- hero_copy P 192513-20 inside at offset 5: in run 40026419647 it is `varied` in webkit-1 (A, A2 and A3 disagree by the same amount), `counted` in webkit-2 (A, A2, A3 agree) and absent in webkit-3. Needs another run or a majority-reference rule to class; the A/A 4478-2 nav-earn change did not recur. Chromium has no A3 (one-entry edit in `packages/measure-chromium/src/pathpix.mjs`, outside the task writes).
- Strips are CI artifacts of runs 39985824264 and 40007968162; the look review is the user's. No phone.
