---
id: 2026-10-23-hero-copy-floor-sources
kind: note
title: "hero_copy A/A floor sources: hero_copy A/A is 0 in all 6 jobs (Chromium by pins, WebKit by the Lean ownership rule for deck-card corner pixels), occluded cells skipped"
status: measured
created: 2026-10-23
topics: [pathpix, webkit, chromium, hero.accent, hero.countdown, a-a-floor, measurement]
---

# hero_copy A/A floor sources

Task `hero-copy-floor-sources`, branch `ci/hero-copy-floor-sources`, workflow `path-pix`, **run 39985824264** (success, round 1):
3 jobs per engine (WebKit Simulator `webkit-1..3`, Chromium `chromium-1..3`), mode `exit`, flag `hero.exit:threaded`. Every
table below is printed by `packages/measure-webkit/src/pathpix-exit-report.mjs` from the artifacts' `cells.json` and manifests
(no number typed by hand); the prose names only what the tables show. Statuses: CONFIRMED (source or test), MEASURED (run),
INFERRED. Run 39971881582 (round 0, same code without the ownership rule) is the before: its WebKit hero_copy A/A had 48-1 in
webkit-2 and 23-1 in webkit-3 at offset 0. This note replaces the "remaining floor sources" list of
`10-2x-pathpix-accent-pin.md`. The look review is the user's; no phone was used, strips stay CI artifacts.

**Two corrections.** (1) `10-2x-pathpix-accent-pin.md` says the misplaced row was "offset index 7 (y 855)": the row is offset
index 7 with arm A at scrollY 0 and arms A2 and P at 855 (accent re-created). This run has 0 misplaced rows in all 6 jobs, so
the validity rule (Lean `AccentRow.placed`: scrollY must equal the offset) did not fire; a lane test covers it. (2) The
round-0 version of this note called the WebKit y 0 change the "countdown tile top edge". That was wrong: the tiles are at CSS y
364..452 (manifest `div[hero-countdown]`), while the changed box (device px, dpr 3) x 123..1164, y 1607..1626 is CSS y 536, the
top corners of the left and right hero deck cards (cells.json of run 39971881582: `hero.deck_article#0` A/A inside 24-1 at
123,1607,143,1624, `#2` 24-1 at 1144,1607,1164,1624 in webkit-2; webkit-3 `#2` 148-2 and `#3` 47-2). The "three face spans" the
report named were hidden countdown faces: hero_copy's mask is the union of all its element boxes (hidden faces included), so it reaches
into the card corners.

## Source by source

| source | outcome | status |
|---|---|---|
| countdown seconds digit (`hero.countdown` reads `Date.now` at mount; the capture shim's clock is virtual) | `Date.now` pinned to the epoch in exit mode (Chromium and WebKit): constant in every row of all 6 jobs (pin table); Chromium hero_copy A/A is 0-0 in all 3 jobs | MEASURED, pin tested |
| WebKit y 0 (A/A 48-1 and 23-1 in round 0; run 39985824264: hero_copy A/A inside 0-0 in 3 of 3 jobs) | the pixels are the antialiased top corners of the rotated, rounded deck cards, which hero_copy's union mask overlaps. Source read: a rounded `overflow:hidden` layer is clipped by Core Animation, not by WebKit paint (`GraphicsLayerCA::updateClippingStrategy`, `GraphicsLayerCA.cpp:3218-3262@862f17d`: uniform radius sets `masksToBounds` plus `cornerRadius` on the CA layer, otherwise a shape-mask layer), so the corner antialiasing is the render server's, no WebKit or page setting pins it without changing the faithful page (cards stay rotated and rounded). Not pinned. Masked by the Lean ownership rule: hero_copy does not count a changed pixel that lies in the mask of another graded layer; that layer counts it (Lean `foreignMasks`, `countedIn`, `countedIn_shared`, `countedIn_other_layer`, `shared_accounted` in `lean/Fw/Gate/PathPix.lean`; golden kind `foreign` in `path-pix.jsonl`). Reason string used by the report: "pixels inside another graded layer's mask are counted by that layer: hero_copy's mask is the union of its element boxes, hidden countdown faces included, and spans the top corners of the deck cards". In this run webkit-3 shows 41-1 at offset 0 left to the deck cells (their own A/A: 24-1, 33-1, 142-2, 47-2); webkit-1 and webkit-2 show none. The variation itself (CA corner antialiasing differing between two identical arms) is INFERRED; the floor stays above 0 in the deck-card cells, not in hero_copy | CONFIRMED (Lean, test), MEASURED (table), INFERRED (cause of the variation) |
| WebKit y 812/813 avatar art under hero_copy | y 812 (Chromium y 885) skipped as occluded by opaque foreign content in both arms (cover grid, 7x7 per layer) in all 6 jobs; y 813: 0 changed pixels inside the mask in all 3 jobs for A/A. The earlier A/A "outside 2-1" (webkit-1) did not repeat; the P-only 2-1 in webkit-1 is a 1 x 16 px column outside every mask at device x 873, y 118..134 (the pixel is located, its element is not identified), P cell stays L (outside the mask) | MEASURED; element of the 2-1 not identified |
| accent word | site hook `?fwpin=accent` (inert when unset, jsdom hydration test) replaces the capture-side DOM swap; accent-unpinned cells 0 in all 6 jobs | MEASURED, CONFIRMED (test) |

## Where the L comes from (hero_copy P cells)

The summary tables list, per P cell, the grade, its source and the grade if strips were accepted. The source is "strips not
accepted" only when strips would change the grade (the cell would be Q); with an inside change above the floor and none
outside the source is "inside, above the floor"; any change outside the mask labels the cell "outside the mask" first. In
this run no cell is labelled "inside, above the floor" (0 of 15 in both engines). Chromium offset 0 does have an inside change
above the floor 0 (273-1, delta 1) but its row also changes outside the mask (80-1), so the label is "outside the mask" and the
grade if strips were accepted is L. Chromium offset 1: the 87 pixels at delta 12 that round 0 counted inside hero_copy
(`87-12`, A/A 0-0, "L from an inside change above the floor") now lie in other layers' masks, so they are counted by those
layers and hero_copy's own cell is 0-0 (L only because strips are not accepted, Q if accepted).

## webkit

#### webkit: hero_copy summary over 3 jobs

| P cells | E | E1 | Q | L | invalid | L: strips not accepted | L: inside, above the floor | L: outside the mask | A/A cells | A/A with a change inside | A/A with a change outside | skipped (reason) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 15 | 0 | 0 | 0 | 15 | 0 | 8 | 0 | 7 | 15 | 0 | 0 | occluded by opaque foreign content in both arms x6; transparent in both arms x18 |

#### webkit: hero_copy per job and offset

| offset | ask y | webkit-1 A/A in/out | webkit-1 P in/out | webkit-1 P grade (source) [if strips accepted] | webkit-2 A/A in/out | webkit-2 P in/out | webkit-2 P grade (source) [if strips accepted] | webkit-3 A/A in/out | webkit-3 P in/out | webkit-3 P grade (source) [if strips accepted] |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] |
| 1 | 1 | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] |
| 2 | 213 | 0-0/0-0 | 0-0/1833-2 | L (outside the mask) [L] | 0-0/0-0 | 0-0/1833-2 | L (outside the mask) [L] | 0-0/0-0 | 0-0/1833-2 | L (outside the mask) [L] |
| 3 | 427 | 0-0/0-0 | 0-0/2744-1 | L (outside the mask) [L] | 0-0/0-0 | 0-0/2744-1 | L (outside the mask) [L] | 0-0/0-0 | 0-0/2744-1 | L (outside the mask) [L] |
| 4 | 812 | skipped: occluded by opaque foreign content in both arms | skipped: occluded by opaque foreign content in both arms | - | skipped: occluded by opaque foreign content in both arms | skipped: occluded by opaque foreign content in both arms | - | skipped: occluded by opaque foreign content in both arms | skipped: occluded by opaque foreign content in both arms | - |
| 5 | 813 | 0-0/0-0 | 0-0/2-1 | L (outside the mask) [L] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] |
| 6 | 854 | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - |
| 7 | 855 | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - |
| 8 | 856 | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - |

#### webkit: hero_copy changes inside the mask

None: hero_copy A/A and P have no change inside the mask in any WebKit job.

#### webkit: hero_copy pixels counted by another layer

Reason: pixels inside another graded layer's mask are counted by that layer: hero_copy's mask is the union of its element boxes, hidden countdown faces included, and spans the top corners of the deck cards

| job | offset | kind | changed pixels left to other layers (chg-max) | other layers graded in this row | changes outside every mask: box (device px) |
|---|---|---|---|---|---|
| webkit-1 | 2 | P | 0-0 | 5 | 1833-2 at 505,2048,785,2138 |
| webkit-1 | 3 | P | 0-0 | 3 | 2744-1 at 476,2023,804,2155 |
| webkit-1 | 5 | P | 0-0 | 1 | 2-1 at 873,118,874,134 |
| webkit-2 | 2 | P | 0-0 | 5 | 1833-2 at 505,2048,785,2138 |
| webkit-2 | 3 | P | 0-0 | 3 | 2744-1 at 476,2023,804,2155 |
| webkit-3 | 0 | A/A | 41-1 | 5 | - |
| webkit-3 | 2 | P | 0-0 | 5 | 1833-2 at 505,2048,785,2138 |
| webkit-3 | 3 | P | 0-0 | 3 | 2744-1 at 476,2023,804,2155 |

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
| 2 | 233 | 0-0/0-0 | 0-0/82-2 | L (outside the mask) [L] | 0-0/0-0 | 0-0/304-2 | L (outside the mask) [L] | 0-0/0-0 | 0-0/139-1 | L (outside the mask) [L] |
| 3 | 466 | 0-0/0-0 | 0-0/741-1 | L (outside the mask) [L] | 0-0/0-0 | 0-0/607-1 | L (outside the mask) [L] | 0-0/0-0 | 0-0/678-1 | L (outside the mask) [L] |
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

Reason: pixels inside another graded layer's mask are counted by that layer: hero_copy's mask is the union of its element boxes, hidden countdown faces included, and spans the top corners of the deck cards

| job | offset | kind | changed pixels left to other layers (chg-max) | other layers graded in this row | changes outside every mask: box (device px) |
|---|---|---|---|---|---|
| chromium-1 | 0 | P | 153-13 | 5 | 80-1 at 55,745,374,809 |
| chromium-1 | 1 | P | 87-12 | 5 | - |
| chromium-1 | 2 | P | 0-0 | 5 | 82-2 at 10,750,419,850 |
| chromium-1 | 3 | P | 0-0 | 3 | 741-1 at 161,815,268,858 |
| chromium-2 | 0 | P | 153-13 | 5 | 80-1 at 55,745,374,809 |
| chromium-2 | 1 | P | 87-12 | 5 | - |
| chromium-2 | 2 | P | 0-0 | 5 | 304-2 at 10,750,419,852 |
| chromium-2 | 3 | P | 0-0 | 3 | 607-1 at 161,815,268,858 |
| chromium-3 | 0 | P | 153-13 | 5 | 80-1 at 55,745,374,809 |
| chromium-3 | 1 | P | 87-12 | 5 | - |
| chromium-3 | 2 | P | 0-0 | 5 | 139-1 at 10,750,419,851 |
| chromium-3 | 3 | P | 0-0 | 3 | 678-1 at 161,815,268,858 |

#### Page clock, accent pin and row placement per job

| job | run | Date.now in every row | cells | accent-unpinned | misplaced | occluded skips |
|---|---|---|---|---|---|---|
| webkit-1 | 39985824264 | constant (1790787600000) | 48 | 0 | 0 | 4 |
| webkit-2 | 39985824264 | constant (1790787600000) | 48 | 0 | 0 | 4 |
| webkit-3 | 39985824264 | constant (1790787600000) | 48 | 0 | 0 | 4 |
| chromium-1 | 39985824264 | constant (1790787600000) | 48 | 0 | 0 | 4 |
| chromium-2 | 39985824264 | constant (1790787600000) | 48 | 0 | 0 | 4 |
| chromium-3 | 39985824264 | constant (1790787600000) | 48 | 0 | 0 | 4 |

## Follow-up for the user's look review (class look-change)

With `hero.exit:threaded` at rest (offset 0, no scroll), Chromium P differs from A in hero_copy's union mask by 426 changed
pixels with maximum delta 13 (round 0 table: `426-13/80-1` in all 3 jobs). Run 39985824264 splits them by owner: 273 pixels at
delta 1 inside hero_copy proper (h1, accent word, countdown faces, box 70,205,357,648) and 153 pixels at delta 13 that lie in
other graded layers' masks (the deck-card tops; those layers count them, see the "counted by another layer" table). Chromium
offset 1 has the same shape: 87 pixels at delta 12, all in other layers' masks, hero_copy inside 0-0. At rest the exit consumer
therefore changes the look of the page against the faithful arm in both hero_copy and the deck cards, which makes it a
look change at rest: class look-change, for the user's visual review (strips `P_hero_copy_0.png` and the deck strips of this
run's artifacts). Chromium A/A is 0-0 everywhere, so these are real P differences, not floor.

## Open

- WebKit deck-card corner pixels vary between identical arms in about 1 of 3 jobs per run (round 0: 2 of 3; this run: 1 of 3); the cause is INFERRED from the Core Animation clip path; the deck cells carry it as their floor, hero_copy no longer counts it.
- The WebKit P-only 2-1 column at device x 873, y 118..134 (webkit-1, ask y 813) is outside every mask; its element is unidentified.
- Strips are CI artifacts of run 39985824264; the look review is the user's. No phone.
