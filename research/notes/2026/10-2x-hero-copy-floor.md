---
id: 2026-10-23-hero-copy-floor-sources
kind: note
title: "hero_copy A/A floor sources: Chromium floor is 0, WebKit floor stays above 0 at y 0 (countdown tile edge), occluded cells skipped"
status: measured
created: 2026-10-23
topics: [pathpix, webkit, chromium, hero.accent, hero.countdown, a-a-floor, measurement]
---

# hero_copy A/A floor sources

Task `hero-copy-floor-sources`, branch `ci/hero-copy-floor-sources`, workflow `path-pix`, **run 39971881582** (success): 3
jobs per engine (WebKit Simulator `webkit-1..3`, Chromium `chromium-1..3`), mode `exit`, flag `hero.exit:threaded`. Every table
below is printed by `packages/measure-webkit/src/pathpix-exit-report.mjs` from the artifacts' `cells.json` and manifests (no
number typed by hand); the prose names only what the tables show. Statuses: CONFIRMED (source), MEASURED (run), INFERRED.
This note replaces the "remaining floor sources" list of `10-2x-pathpix-accent-pin.md`. The look review is the user's; no
phone was used, strips stay CI artifacts.

**Correction to `10-2x-pathpix-accent-pin.md`:** it says the misplaced row was "offset index 7 (y 855)". The row is offset
index 7 with arm A at scrollY 0 and arms A2 and P at 855 (manifest row `A[7]`: scrollY 0 vs y 855, accent re-created). This run
has 0 misplaced rows in all 6 jobs (the pin table), so the validity rule (Lean `AccentRow.placed`, scrollY must equal the offset) did
not fire here; it is covered by the lane test.

## Source by source

| source | outcome | status |
|---|---|---|
| countdown seconds digit, Chromium (`hero.countdown` `dateNow: Date.now` at mount; the shim's `Date.now` is virtual) | `Date.now` pinned to the epoch in exit mode: the page clock is constant in every row of all 6 jobs and the Chromium hero_copy A/A cells show 0 changed pixels inside and outside in all 15 cells | MEASURED (shim untouched, pin appended after it) |
| WebKit y 0 (48 px, delta 1) | not removed: A/A inside 48-1 in webkit-2 and 23-1 in webkit-3, 0 in webkit-1 (whose P cell has 48-1). The changed box (device px, dpr 3) is x 123..1164, y 1607..1624 in webkit-1/2, touching three countdown face spans; in webkit-3 it is x 1145..1164, y 1607..1626, no named part. The A/A strip (webkit-2, offset 0) shows the countdown tiles near that height, so the box is probably the tile top edge | MEASURED box; cause INFERRED (anti-aliased edge of composited tiles, `will-change: transform` faces), not pinned, floor stays above 0 |
| WebKit y 812/813 avatar art under hero_copy | y 812 (and Chromium y 885) is skipped as occluded by opaque foreign content in both arms (cover grid, 7x7 per layer) in all 6 jobs; y 813 has 0 changed pixels inside the mask in all 3 WebKit jobs, a 2 px delta-1 change outside the mask in 2 of 3 (L: outside the mask, not floor) | MEASURED (the skip rule needs every grid point covered; y 813 was not fully covered, so it is graded) |
| accent word | site hook `?fwpin=accent` (inert when unset, jsdom hydration test) replaces the capture-side DOM swap; accent-unpinned cells 0 in all 6 jobs | MEASURED, CONFIRMED (test) |

## Where the L comes from (hero_copy P cells)

The engine tables below list, per P cell, the grade, its source (floor, outside the mask, strips not accepted) and the grade if
strips were accepted. L from the floor is 0 in both engines; the L cells come from the strips not being accepted and from
changes outside the mask (the P arm differs there from the faithful arm), see each summary row.

## webkit

#### webkit: hero_copy summary over 3 jobs

| P cells | E | E1 | Q | L | invalid | L: strips not accepted | L: floor | L: outside the mask | A/A cells | A/A with a change inside | A/A with a change outside | skipped (reason) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 15 | 0 | 0 | 0 | 15 | 0 | 7 | 0 | 8 | 15 | 2 | 1 | occluded by opaque foreign content in both arms x6; transparent in both arms x18 |

#### webkit: hero_copy per job and offset

| offset | ask y | webkit-1 A/A in/out | webkit-1 P in/out | webkit-1 P grade (source) [if strips accepted] | webkit-2 A/A in/out | webkit-2 P in/out | webkit-2 P grade (source) [if strips accepted] | webkit-3 A/A in/out | webkit-3 P in/out | webkit-3 P grade (source) [if strips accepted] |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0-0/0-0 | 48-1/0-0 | L (strips not accepted) [Q] | 48-1/0-0 | 48-1/0-0 | L (strips not accepted) [Q] | 23-1/0-0 | 23-1/0-0 | L (strips not accepted) [Q] |
| 1 | 1 | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] |
| 2 | 213 | 0-0/0-0 | 0-0/1833-2 | L (outside the mask) [L] | 0-0/0-0 | 0-0/1833-2 | L (outside the mask) [L] | 0-0/0-0 | 0-0/1833-2 | L (outside the mask) [L] |
| 3 | 427 | 0-0/0-0 | 0-0/2744-1 | L (outside the mask) [L] | 0-0/0-0 | 0-0/2744-1 | L (outside the mask) [L] | 0-0/0-0 | 0-0/2744-1 | L (outside the mask) [L] |
| 4 | 812 | skipped: occluded by opaque foreign content in both arms | skipped: occluded by opaque foreign content in both arms | - | skipped: occluded by opaque foreign content in both arms | skipped: occluded by opaque foreign content in both arms | - | skipped: occluded by opaque foreign content in both arms | skipped: occluded by opaque foreign content in both arms | - |
| 5 | 813 | 0-0/2-1 | 0-0/2-1 | L (outside the mask) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/2-1 | L (outside the mask) [L] |
| 6 | 854 | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - |
| 7 | 855 | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - |
| 8 | 856 | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - |

#### webkit: hero_copy changes inside the mask

| job | offset | kind | inside chg-max | box (device px) | parts the box touches |
|---|---|---|---|---|---|
| webkit-1 | 0 | P | 48-1 | 123,1607,1164,1624 | span.hero-module_face_B0Q0e9 x3 |
| webkit-2 | 0 | A/A | 48-1 | 123,1607,1164,1624 | span.hero-module_face_B0Q0e9 x3 |
| webkit-2 | 0 | P | 48-1 | 123,1607,1164,1624 | span.hero-module_face_B0Q0e9 x3 |
| webkit-3 | 0 | A/A | 23-1 | 1145,1607,1164,1626 | none named |
| webkit-3 | 0 | P | 23-1 | 1145,1607,1164,1626 | none named |

#### Page clock, accent pin and row placement per job

| job | run | Date.now in every row | cells | accent-unpinned | misplaced | occluded skips |
|---|---|---|---|---|---|---|
| webkit-1 | 39971881582 | constant (1790787600000) | 48 | 0 | 0 | 4 |
| webkit-2 | 39971881582 | constant (1790787600000) | 48 | 0 | 0 | 4 |
| webkit-3 | 39971881582 | constant (1790787600000) | 48 | 0 | 0 | 4 |

## chromium

#### chromium: hero_copy summary over 3 jobs

| P cells | E | E1 | Q | L | invalid | L: strips not accepted | L: floor | L: outside the mask | A/A cells | A/A with a change inside | A/A with a change outside | skipped (reason) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 15 | 0 | 0 | 0 | 15 | 0 | 6 | 0 | 9 | 15 | 0 | 0 | occluded by opaque foreign content in both arms x6; transparent in both arms x18 |

#### chromium: hero_copy per job and offset

| offset | ask y | chromium-1 A/A in/out | chromium-1 P in/out | chromium-1 P grade (source) [if strips accepted] | chromium-2 A/A in/out | chromium-2 P in/out | chromium-2 P grade (source) [if strips accepted] | chromium-3 A/A in/out | chromium-3 P in/out | chromium-3 P grade (source) [if strips accepted] |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0-0/0-0 | 426-13/80-1 | L (outside the mask) [L] | 0-0/0-0 | 426-13/80-1 | L (outside the mask) [L] | 0-0/0-0 | 426-13/80-1 | L (outside the mask) [L] |
| 1 | 1 | 0-0/0-0 | 87-12/0-0 | L (strips not accepted) [L] | 0-0/0-0 | 87-12/0-0 | L (strips not accepted) [L] | 0-0/0-0 | 87-12/0-0 | L (strips not accepted) [L] |
| 2 | 233 | 0-0/0-0 | 0-0/82-2 | L (outside the mask) [L] | 0-0/0-0 | 0-0/304-2 | L (outside the mask) [L] | 0-0/0-0 | 0-0/2-1 | L (outside the mask) [L] |
| 3 | 466 | 0-0/0-0 | 0-0/741-1 | L (outside the mask) [L] | 0-0/0-0 | 0-0/607-1 | L (outside the mask) [L] | 0-0/0-0 | 0-0/796-1 | L (outside the mask) [L] |
| 4 | 885 | skipped: occluded by opaque foreign content in both arms | skipped: occluded by opaque foreign content in both arms | - | skipped: occluded by opaque foreign content in both arms | skipped: occluded by opaque foreign content in both arms | - | skipped: occluded by opaque foreign content in both arms | skipped: occluded by opaque foreign content in both arms | - |
| 5 | 886 | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] | 0-0/0-0 | 0-0/0-0 | L (strips not accepted) [Q] |
| 6 | 931 | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - |
| 7 | 932 | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - |
| 8 | 933 | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - | skipped: transparent in both arms | skipped: transparent in both arms | - |

#### chromium: hero_copy changes inside the mask

| job | offset | kind | inside chg-max | box (device px) | parts the box touches |
|---|---|---|---|---|---|
| chromium-1 | 0 | P | 426-13 | 17,205,413,653 | h1.hero-module_title_4Q4gSp, em[hero-accent].accent-module_accent_whUL9E, svg x3, p, div[hero-countdown].hero-module_countdown_HKvRcv, span.hero-module_face_B0Q0e9 x33 |
| chromium-1 | 1 | P | 87-12 | 17,643,413,653 | none named |
| chromium-2 | 0 | P | 426-13 | 17,205,413,653 | h1.hero-module_title_4Q4gSp, em[hero-accent].accent-module_accent_whUL9E, svg x3, p, div[hero-countdown].hero-module_countdown_HKvRcv, span.hero-module_face_B0Q0e9 x33 |
| chromium-2 | 1 | P | 87-12 | 17,643,413,653 | none named |
| chromium-3 | 0 | P | 426-13 | 17,205,413,653 | h1.hero-module_title_4Q4gSp, em[hero-accent].accent-module_accent_whUL9E, svg x3, p, div[hero-countdown].hero-module_countdown_HKvRcv, span.hero-module_face_B0Q0e9 x33 |
| chromium-3 | 1 | P | 87-12 | 17,643,413,653 | none named |

#### Page clock, accent pin and row placement per job

| job | run | Date.now in every row | cells | accent-unpinned | misplaced | occluded skips |
|---|---|---|---|---|---|---|
| chromium-1 | 39971881582 | constant (1790787600000) | 48 | 0 | 0 | 4 |
| chromium-2 | 39971881582 | constant (1790787600000) | 48 | 0 | 0 | 4 |
| chromium-3 | 39971881582 | constant (1790787600000) | 48 | 0 | 0 | 4 |

## Open

- WebKit y 0 floor (countdown tile edge) stays above 0; cause not pinned (follow-up: a capture that freezes the tile layers or masks the tile top rows with a Lean-stated reason).
- Chromium P cells differ from A well above the floor (floor 0), so Chromium hero_copy grades are real P differences.
- Strips are CI artifacts of run 39971881582; the look review is the user's.
