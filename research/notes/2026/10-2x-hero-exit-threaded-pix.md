---
id: 2026-10-23-hero-exit-threaded-pix
kind: note
title: "hero.exit:threaded PathPix cells: every threaded cell is L under the Lean rule on both engines (text hold or change outside the masks); the Simulator differences sit at the A/A floor, the Chromium ones do not"
status: draft
created: 2026-10-23
topics: [hero.exit, pathpix, webkit, chromium, scroll-driven, threaded-animations, look-review]
---

# hero.exit:threaded against the faithful exit, PathPix cells

Task `hero-exit-threaded-pix`, branch `ci/hero-exit-threaded-pix` (worktree branch `worktree-wf_4a8ad90b-552-1`), workflow
`path-pix.yml` with `PP_MODE=exit`, `PP_FLAG=hero.exit:threaded`. Arm A is the faithful exit (default page), A2 a second
load of it (the A/A floor), P the same page with `?fw=hero.exit:threaded`. Unit of decision: one cell = lane x scroll
offset x exit consumer box, graded E/Q/L by the Lean PathPix rule (`gradeRel`, `lean/Fw/Gate/PathPix.lean`) against the
same run's A/A cell. Cell JSON: `results/hero-exit-threaded-pix/run-<id>/<label>.json`. No phone, no Mac timing.

## Answer

- MEASURED: no P cell is E or Q under the Lean rule, on either engine, in any of the 8 valid-harness jobs (runs 2 and 3,
  4 jobs per lane). Every P cell that is not invalid is L (webkit 100 of 104 cells, the other 4 invalid in webkit-4;
  chromium 104 of 104). Why: every consumer holds text (claim C1, text hold) and C5 (strips accepted) is
  never closed, so text consumers are L by design; the other cells are L because pixels outside every consumer mask
  change (a 1px blur/aliasing halo or a real shift).
- MEASURED, read next to the A/A floor ("if strips accepted" column of the JSON, `ifAccepted`): on the Simulator the
  only P cells that stay L are the cue and card boxes in the middle of the track (offsets y 213 and 427: 1833 and
  2744 px outside the masks at delta 1 to 2, identical in all four jobs) plus, in single jobs, cells where the
  accent-word noise or the next-section noise differs from the floor (webkit-3: hero_copy y 0 and 1, cue_cue y 812 and
  813); the rest are Q if strips are accepted (webkit: 14 Q / 12 L in webkit-1, -2; 8 Q / 18 L in
  webkit-3; 14 Q / 8 L / 4 invalid in webkit-4). On Chromium 22 of 26 cells stay L (4 Q: the two offsets at and
  past the end of the track, y 885 and 886, where cue and hero_copy are gone in both arms) in all four jobs.
- Verdict for the look review: the threaded exit is not pixel-equal to the faithful exit at the sampled offsets. The
  Chromium differences are small (up to a few thousand px at delta 1 to 16 inside the card and cue boxes; hero_copy at
  y 0 and 1 differs by 387 to 464 px at delta up to 222, where the accent-word noise below may contribute) and the
  start-of-track ones reproduce across all four jobs, but the mid-track outside counts do not (see Chromium spread); the
  Simulator ones are 1833 to 7576 px at delta 1 to 2 mid-track and reproduce in all four jobs. Which L cells are
  visible is the user's look review: strips below.

## Runs

| run | workflow | head | state | note |
|---|---|---|---|---|
| 39920801675 | path-pix | 75d148072 | success | dispatch 1; Chromium arm A never ran the faithful driver, so Chromium run 1 is invalid as a comparison; Simulator cells valid but masks did not cover descendants and consumers transparent in both arms were not skipped |
| 39924527942 | path-pix | 0cae7da70 | success | dispatch 2; labels webkit-1, webkit-2, chromium-1, chromium-2 |
| 39929556147 | path-pix | af3009d51 | success | dispatch 3 (same harness, post-merge tree); labels webkit-3, webkit-4, chromium-3, chromium-4 |

All on branch `ci/hero-exit-threaded-pix`. Three dispatches, the limit. The artifacts are `path-pix-webkit-1`,
`-webkit-2`, `-chromium-1`, `-chromium-2` of each run (strips and screenshots; CI artifacts only, never committed).
Two aborted/short local debug runs happened on the Simulator while changing harness code (one killed full run, one
3-offset run); neither is a result.

## Setup

- MEASURED (manifest): track T 0, h 1630, viewport 775, n 855 on the Simulator (430 CSS px wide, DPR 3, offsets y
  0, 1, 213, 427, 812, 813, 854, 855, 856); Chromium 430x932 at DPR 1, T 0, h 1864, n 932 (offsets 0, 1, 233, 466, 885,
  886, 931, 932, 933), HeadlessChrome/156.0.8078.4, software compositing. Offsets are Lean `exitOffsets`.
- MEASURED: every P row is live in all jobs (`data-exit-live` true, variant threaded, splash done, scroll-driven
  animations supported, 13 non-document animations, no nudge, config hash 5cfc87a3b48c71c0; A hash ede2c7641aacf2d2).
  `driverMoved` (arm A's hero_copy box moved) is true in all 8 jobs.
- Cells per job: 26 P and 26 A/A cells; 52 skipped per kind (22 deck_article off screen, 6 cue_cue and 6 hero_copy
  transparent in both arms, i.e. alpha below 1/255). `hero.orbit_card` is never present at 430 px in either lane.
- Pixels inside an invisible consumer's mask are not judged; outside means outside every mask; a blur halo beyond the 1px
  mask margin counts as outside (L by rule).

## finiteRunning and fonts (checks asked for)

- CONFIRMED (code): the page wait in `packages/gate-breakpoints/src/page.mjs:106-109` counts only finite-iteration
  animations on a `DocumentTimeline` that are running or pending, so scroll-driven (view-timeline) animations cannot hold
  it, and `freezeAnimations` (page.mjs:26-46) skips them. The path-pix lanes do not call that wait: Simulator `HOLD_EXPR`
  waits for hydration, fonts, eager images and 2 rAF; Chromium `loadArm` for readyState, fonts, images and hydration.
  The cells witness liveness per P row instead (`data-exit-live`, variant threaded, `supported`, non-document animations
  above 0); a P row that is not live makes its cells invalid. They guard arm A with `driverMoved`.
- CONFIRMED (artifact manifest of all Chromium jobs): `fonts.systemFonts` = Liberation Mono, Liberation Sans, Liberation
  Sans Narrow, Liberation Serif, so no Thai coverage in the Chromium lane image; page fonts loaded are Google Sans (400,
  700) and Playpen Sans Start Selling (400, 600). The image is not changed here (known follow-up, counts-lane-fonts).

## Cell tables (P cells; runs 2 and 3)

Cell text: grade letter and why (`t` text hold, `o` outside, `i` inside), `[grade if strips accepted]`, then P inside
`changed-maxDelta` / outside `changed-maxDelta` raw counts. Jobs webkit-1, -2, chromium-1, -2 are run 39924527942;
webkit-3, -4, chromium-3, -4 are run 39929556147. Skipped cells are not listed (see Setup). `invalid` means the
capture of A, A2 or P did not stabilise at that offset (two screenshots differ after six tries).

#### webkit

| consumer | offset | y | webkit-1 | webkit-2 | webkit-3 | webkit-4 |
|---|---|---|---|---|---|---|
| hero.cue_cue | 0 | 0 | Lt [L] 2769-56/0-0 | Lt [L] 2769-56/0-0 | Lt [L] 2769-56/0-0 | Lt [L] 2535-56/0-0 |
| hero.cue_cue | 1 | 1 | Lt [L] 2766-56/0-0 | Lt [L] 2766-56/0-0 | Lt [L] 2766-56/0-0 | Lt [L] 2766-56/0-0 |
| hero.cue_cue | 2 | 213 | Lo [L] 7576-2/1833-2 | Lo [L] 7576-2/1833-2 | Lo [L] 7576-2/1833-2 | Lo [L] 7576-2/1833-2 |
| hero.cue_cue | 3 | 427 | Lo [L] 5032-1/2744-1 | Lo [L] 5032-1/2744-1 | Lo [L] 5032-1/2744-1 | invalid [invalid] 5032-1/2744-1 |
| hero.cue_cue | 4 | 812 | Lo [Q] 0-0/2-1 | Lt [Q] 0-0/0-0 | Lo [L] 0-0/2-1 | Lo [Q] 0-0/57825-255 |
| hero.cue_cue | 5 | 813 | Lo [Q] 0-0/2-1 | Lt [Q] 0-0/0-0 | Lo [L] 0-0/2-1 | Lo [Q] 0-0/59127-255 |
| hero.deck_article#0 | 0 | 0 | Lt [Q] 0-0/0-0 | Lt [Q] 24-1/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 |
| hero.deck_article#0 | 1 | 1 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 |
| hero.deck_article#0 | 2 | 213 | Lo [L] 0-0/1833-2 | Lo [L] 0-0/1833-2 | Lo [L] 0-0/1833-2 | Lo [L] 0-0/1833-2 |
| hero.deck_article#1 | 0 | 0 | Lt [Q] 0-0/0-0 | Lt [Q] 33-1/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 |
| hero.deck_article#1 | 1 | 1 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 |
| hero.deck_article#1 | 2 | 213 | Lo [L] 0-0/1833-2 | Lo [L] 0-0/1833-2 | Lo [L] 0-0/1833-2 | Lo [L] 0-0/1833-2 |
| hero.deck_article#1 | 3 | 427 | Lo [L] 0-0/2744-1 | Lo [L] 0-0/2744-1 | Lo [L] 0-0/2744-1 | invalid [invalid] 0-0/2744-1 |
| hero.deck_article#2 | 0 | 0 | Lt [Q] 0-0/0-0 | Lt [Q] 24-1/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 |
| hero.deck_article#2 | 1 | 1 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 |
| hero.deck_article#2 | 2 | 213 | Lo [L] 0-0/1833-2 | Lo [L] 0-0/1833-2 | Lo [L] 0-0/1833-2 | Lo [L] 0-0/1833-2 |
| hero.deck_article#3 | 0 | 0 | Lt [Q] 0-0/0-0 | Lt [Q] 20-1/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 |
| hero.deck_article#3 | 1 | 1 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 |
| hero.deck_article#3 | 2 | 213 | Lo [L] 0-0/1833-2 | Lo [L] 0-0/1833-2 | Lo [L] 0-0/1833-2 | Lo [L] 0-0/1833-2 |
| hero.deck_article#3 | 3 | 427 | Lo [L] 0-0/2744-1 | Lo [L] 0-0/2744-1 | Lo [L] 0-0/2744-1 | invalid [invalid] 0-0/2744-1 |
| hero_copy | 0 | 0 | Lt [Q] 30854-212/0-0 | Lt [Q] 48-1/0-0 | Lt [L] 40483-212/0-0 | Lt [Q] 0-0/0-0 |
| hero_copy | 1 | 1 | Lt [Q] 31174-212/0-0 | Lt [Q] 0-0/0-0 | Lt [L] 40759-212/0-0 | Lt [Q] 0-0/0-0 |
| hero_copy | 2 | 213 | Lo [L] 30128-159/1833-2 | Lo [L] 39-1/1833-2 | Lo [L] 39686-159/1833-2 | Lo [L] 0-0/1833-2 |
| hero_copy | 3 | 427 | Lo [L] 30104-106/2744-1 | Lo [L] 0-0/2744-1 | Lo [L] 39844-106/2744-1 | invalid [invalid] 36359-106/2744-1 |
| hero_copy | 4 | 812 | Lo [Q] 192503-20/2-1 | Lt [Q] 0-0/0-0 | Lo [L] 0-0/2-1 | Lo [Q] 4570-255/57825-255 |
| hero_copy | 5 | 813 | Lo [Q] 192513-20/2-1 | Lt [Q] 0-0/0-0 | Lo [L] 0-0/2-1 | Lo [Q] 3268-253/59127-255 |

#### chromium

| consumer | offset | y | chromium-1 | chromium-2 | chromium-3 | chromium-4 |
|---|---|---|---|---|---|---|
| hero.cue_cue | 0 | 0 | Lo [L] 539-57/80-1 | Lo [L] 539-57/80-1 | Lo [L] 526-35/80-1 | Lo [L] 542-43/80-1 |
| hero.cue_cue | 1 | 1 | Lt [L] 535-50/0-0 | Lt [L] 535-50/0-0 | Lt [L] 526-35/0-0 | Lt [L] 542-43/0-0 |
| hero.cue_cue | 2 | 233 | Lo [L] 0-0/2-1 | Lo [L] 0-0/2-1 | Lo [L] 1975-4/304-2 | Lo [L] 1676-2/139-1 |
| hero.cue_cue | 3 | 466 | Lo [L] 1718-2/796-1 | Lo [L] 1718-2/796-1 | Lo [L] 1325-2/607-1 | Lo [L] 1538-1/678-1 |
| hero.cue_cue | 4 | 885 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 |
| hero.cue_cue | 5 | 886 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 |
| hero.deck_article#0 | 0 | 0 | Lo [L] 1489-15/80-1 | Lo [L] 1489-15/80-1 | Lo [L] 1489-15/80-1 | Lo [L] 1489-15/80-1 |
| hero.deck_article#0 | 1 | 1 | Lt [L] 1061-15/0-0 | Lt [L] 1061-15/0-0 | Lt [L] 1061-15/0-0 | Lt [L] 1061-15/0-0 |
| hero.deck_article#0 | 2 | 233 | Lo [L] 173-10/2-1 | Lo [L] 173-10/2-1 | Lo [L] 173-10/304-2 | Lo [L] 173-10/139-1 |
| hero.deck_article#1 | 0 | 0 | Lo [L] 4049-15/80-1 | Lo [L] 4049-15/80-1 | Lo [L] 4049-15/80-1 | Lo [L] 4049-15/80-1 |
| hero.deck_article#1 | 1 | 1 | Lt [L] 3507-15/0-0 | Lt [L] 3507-15/0-0 | Lt [L] 3507-15/0-0 | Lt [L] 3507-15/0-0 |
| hero.deck_article#1 | 2 | 233 | Lo [L] 1101-14/2-1 | Lo [L] 1101-14/2-1 | Lo [L] 1101-14/304-2 | Lo [L] 1101-14/139-1 |
| hero.deck_article#1 | 3 | 466 | Lo [L] 90-10/796-1 | Lo [L] 90-10/796-1 | Lo [L] 90-10/607-1 | Lo [L] 90-10/678-1 |
| hero.deck_article#2 | 0 | 0 | Lo [L] 1372-15/80-1 | Lo [L] 1372-15/80-1 | Lo [L] 1372-15/80-1 | Lo [L] 1372-15/80-1 |
| hero.deck_article#2 | 1 | 1 | Lt [L] 935-15/0-0 | Lt [L] 935-15/0-0 | Lt [L] 935-15/0-0 | Lt [L] 935-15/0-0 |
| hero.deck_article#2 | 2 | 233 | Lo [L] 110-12/2-1 | Lo [L] 110-12/2-1 | Lo [L] 110-12/304-2 | Lo [L] 110-12/139-1 |
| hero.deck_article#3 | 0 | 0 | Lo [L] 3232-16/80-1 | Lo [L] 3232-16/80-1 | Lo [L] 3232-16/80-1 | Lo [L] 3232-16/80-1 |
| hero.deck_article#3 | 1 | 1 | Lt [L] 2632-16/0-0 | Lt [L] 2632-16/0-0 | Lt [L] 2632-16/0-0 | Lt [L] 2632-16/0-0 |
| hero.deck_article#3 | 2 | 233 | Lo [L] 757-8/2-1 | Lo [L] 757-8/2-1 | Lo [L] 757-8/304-2 | Lo [L] 757-8/139-1 |
| hero.deck_article#3 | 3 | 466 | Lo [L] 73-6/796-1 | Lo [L] 73-6/796-1 | Lo [L] 73-6/607-1 | Lo [L] 73-6/678-1 |
| hero_copy | 0 | 0 | Lo [L] 387-222/80-1 | Lo [L] 416-222/80-1 | Lo [L] 387-222/80-1 | Lo [L] 387-222/80-1 |
| hero_copy | 1 | 1 | Lt [L] 464-213/0-0 | Lt [L] 477-217/0-0 | Lt [L] 464-213/0-0 | Lt [L] 464-213/0-0 |
| hero_copy | 2 | 233 | Lo [L] 290-49/2-1 | Lo [L] 320-68/2-1 | Lo [L] 290-49/304-2 | Lo [L] 290-49/139-1 |
| hero_copy | 3 | 466 | Lo [L] 130-7/796-1 | Lo [L] 130-7/796-1 | Lo [L] 130-7/607-1 | Lo [L] 130-7/678-1 |
| hero_copy | 4 | 885 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 |
| hero_copy | 5 | 886 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 | Lt [Q] 0-0/0-0 |


## What the cells show

- MEASURED, Chromium spread: at the start of the track (y 0, 1) the P-minus-A counts are identical in all four jobs
  (for example deck_article#1 at y 0: 4049 px inside at delta 15, 80 px outside; cue_cue 526 to 542 px at delta 35 to 57).
  A/A is 0 there, so the differences are P's, not noise. In the middle of the track (y 233, 466) the outside counts
  differ between jobs: run 2 gives 2 px and 796 px in both jobs, run 3 gives 304 or 139 px at y 233 and 607 or 678 px at
  y 466. So at least one arm renders the mid-track frame differently from job to job on Chromium software compositing
  (INFERRED: the rAF pump stops when the boxes stay unchanged six times, so the frame it stops on can differ by one
  step). Class stays L in every job; the raw counts are not stable.
- MEASURED, Simulator: the mid-track cells (y 213, 427) are identical in all four jobs (cue_cue 7576 and 5032 px
  inside, 1833 and 2744 px outside; decks 1833 and 2744 px outside; delta at most 2). The A/A floor is 0 there. The
  outside px at delta 1 to 2 are a blur halo or shadow edge beyond the 1px mask margin (INFERRED from the delta; strip
  `FRAME_P_<i>.png` shows where).
- MEASURED, accent-word noise: the hero accent word in the hero copy differs between loads on the Simulator (arm A,
  loaded first, shows a different word than A2 and P in some jobs; strips in the artifacts). A/A floor of hero_copy at
  y 0: 30902 px (webkit-1, webkit-3), 48 (webkit-2), 9434 (webkit-4); the P cell is then within the floor
  (`ifAccepted` Q) or beyond it (webkit-3: 40483 vs 30902 px, still the same word difference plus P). On Chromium the
  floor was 490 to 514 px at y 0 in run 2 and 0 in run 3, so the same effect reaches Chromium at a smaller size.
  Cause INFERRED: the accent timer chain runs until `__wk.hold()`, so the word at hold depends on load timing; the
  aria-label stays "you" for every word, so it is no witness. Follow-up: pin the chain or its cursor in the lanes.
- MEASURED, next section: at y 812 and 813 (the end of the track) the avatar art of the section below changes per load
  (webkit-4: 57825 and 59127 px outside at delta 255 in A/A and P alike; webkit-1: 192503 px inside the hero_copy mask
  at delta 20 in A/A and P alike). The floor covers it where it occurs (Q if strips accepted); where the floor is 0
  and P has 2 px at delta 1 (webkit-3) the cell is L outside.
- MEASURED, invalid cells (webkit-4, run 39929556147, y 427, the 4 P cells of cue_cue, deck_article#1, deck_article#3,
  hero_copy): the cell JSON frames show `sameA` false (arm A's two screenshots at that offset differ after six tries)
  while `sameB` is true for A2 and P, so the floor is invalid and the P cells with it. The A-versus-A2 frame diff there is
  29982 px at delta 106, the size of one accent word. CONFIRMED by eye (strip `AA_hero_copy_3.png` of
  `path-pix-webkit-2`, run 39929556147): arm A shows the accent word, A2 shows an empty accent slot, and the words
  around it shift. INFERRED cause: arm A was captured while the accent chain was mid-cycle (the chain runs until
  `__wk.hold()`, so which frame it is on depends on load timing); this is the same accent-word noise as in the hero_copy
  floor, only here it crossed between A's two shots. No other invalid cells in runs 2 and 3.
- Run 1 (39920801675): Chromium arm A never ran the faithful driver (the page clock `__fwclock` was not advanced
  after the scroll, so the faithful driver's rAF never ticked), so every Chromium cell of run 1 compares P against a
  fully visible hero, not the faithful exit; fixed in a4df295a3 (tick the clock after each scroll and pump frames until
  the boxes stop moving), witnessed by `driverMoved`. The Simulator cells of run 1 are valid but their masks did not
  cover descendants (the cue label overflowed the mask) and transparent consumers were not skipped; they are kept
  in `results/hero-exit-threaded-pix/run-39920801675/` as the earlier harness and not counted.
- Hand-over (CONFIRMED, `apps/site/src/parts/hero.exit/threaded.ts`): live only when the splash is done, the cue
  animations finished, `CSS.supports('animation-timeline','view()')` and not reduced motion; at width up to 600 the orbit
  driver is skipped. The server falls back to index.html on an unknown search, so the variant witness (`data-exit-live`,
  variant threaded) guards that P is the threaded page.

## L cells for the user's look review

Every P cell graded L is named below (a cell with Q in the ifAccepted position would pass if the text hold were
accepted; L there means it fails even then). Job to artifact (CONFIRMED, `artifact` field of each cell JSON): webkit-1
and webkit-2 are `path-pix-webkit-1` and `path-pix-webkit-2` of run 39924527942, webkit-3 and webkit-4 are
`path-pix-webkit-1` and `path-pix-webkit-2` of run 39929556147; chromium-1..-4 map the same way to
`path-pix-chromium-1` and `-2` of those two runs. The strip is `strips/P_<key>_<i>.png` in that artifact
(`gh run download <run> -n <artifact>`; CI artifacts only, 30-day retention), `strips/FRAME_P_<i>.png` is the whole
frame. Per cell, jobs 1..4 of the lane, `t` text hold, `o` outside, `i` inside, then `/` and the ifAccepted grade
(table generated from the cell JSON; strip name from the first job that has one):

| lane | consumer | y | job: why, ifAccepted (Q = would pass if the text hold were accepted) | strip in the job artifact |
|---|---|---|---|---|
| webkit | hero.cue_cue | 0 | 1:Lt/L 2:Lt/L 3:Lt/L 4:Lt/L | strips/P_hero.cue_cue_0.png |
| webkit | hero.cue_cue | 1 | 1:Lt/L 2:Lt/L 3:Lt/L 4:Lt/L | strips/P_hero.cue_cue_1.png |
| webkit | hero.cue_cue | 213 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero.cue_cue_2.png |
| webkit | hero.cue_cue | 427 | 1:Lo/L 2:Lo/L 3:Lo/L 4:invalid | strips/P_hero.cue_cue_3.png |
| webkit | hero.cue_cue | 812 | 1:Lo/Q 2:Lt/Q 3:Lo/L 4:Lo/Q | strips/P_hero.cue_cue_4.png |
| webkit | hero.cue_cue | 813 | 1:Lo/Q 2:Lt/Q 3:Lo/L 4:Lo/Q | strips/P_hero.cue_cue_5.png |
| webkit | hero.deck_article#0 | 0 | 1:Lt/Q 2:Lt/Q 3:Lt/Q 4:Lt/Q | strips/P_hero.deck_article_0_0.png |
| webkit | hero.deck_article#0 | 1 | 1:Lt/Q 2:Lt/Q 3:Lt/Q 4:Lt/Q | none (no pixel change, text hold only) |
| webkit | hero.deck_article#0 | 213 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero.deck_article_0_2.png |
| webkit | hero.deck_article#1 | 0 | 1:Lt/Q 2:Lt/Q 3:Lt/Q 4:Lt/Q | strips/P_hero.deck_article_1_0.png |
| webkit | hero.deck_article#1 | 1 | 1:Lt/Q 2:Lt/Q 3:Lt/Q 4:Lt/Q | none (no pixel change, text hold only) |
| webkit | hero.deck_article#1 | 213 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero.deck_article_1_2.png |
| webkit | hero.deck_article#1 | 427 | 1:Lo/L 2:Lo/L 3:Lo/L 4:invalid | strips/P_hero.deck_article_1_3.png |
| webkit | hero.deck_article#2 | 0 | 1:Lt/Q 2:Lt/Q 3:Lt/Q 4:Lt/Q | strips/P_hero.deck_article_2_0.png |
| webkit | hero.deck_article#2 | 1 | 1:Lt/Q 2:Lt/Q 3:Lt/Q 4:Lt/Q | none (no pixel change, text hold only) |
| webkit | hero.deck_article#2 | 213 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero.deck_article_2_2.png |
| webkit | hero.deck_article#3 | 0 | 1:Lt/Q 2:Lt/Q 3:Lt/Q 4:Lt/Q | strips/P_hero.deck_article_3_0.png |
| webkit | hero.deck_article#3 | 1 | 1:Lt/Q 2:Lt/Q 3:Lt/Q 4:Lt/Q | none (no pixel change, text hold only) |
| webkit | hero.deck_article#3 | 213 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero.deck_article_3_2.png |
| webkit | hero.deck_article#3 | 427 | 1:Lo/L 2:Lo/L 3:Lo/L 4:invalid | strips/P_hero.deck_article_3_3.png |
| webkit | hero_copy | 0 | 1:Lt/Q 2:Lt/Q 3:Lt/L 4:Lt/Q | strips/P_hero_copy_0.png |
| webkit | hero_copy | 1 | 1:Lt/Q 2:Lt/Q 3:Lt/L 4:Lt/Q | strips/P_hero_copy_1.png |
| webkit | hero_copy | 213 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero_copy_2.png |
| webkit | hero_copy | 427 | 1:Lo/L 2:Lo/L 3:Lo/L 4:invalid | strips/P_hero_copy_3.png |
| webkit | hero_copy | 812 | 1:Lo/Q 2:Lt/Q 3:Lo/L 4:Lo/Q | strips/P_hero_copy_4.png |
| webkit | hero_copy | 813 | 1:Lo/Q 2:Lt/Q 3:Lo/L 4:Lo/Q | strips/P_hero_copy_5.png |
| chromium | hero.cue_cue | 0 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero.cue_cue_0.png |
| chromium | hero.cue_cue | 1 | 1:Lt/L 2:Lt/L 3:Lt/L 4:Lt/L | strips/P_hero.cue_cue_1.png |
| chromium | hero.cue_cue | 233 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero.cue_cue_2.png |
| chromium | hero.cue_cue | 466 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero.cue_cue_3.png |
| chromium | hero.cue_cue | 885 | 1:Lt/Q 2:Lt/Q 3:Lt/Q 4:Lt/Q | none (no pixel change, text hold only) |
| chromium | hero.cue_cue | 886 | 1:Lt/Q 2:Lt/Q 3:Lt/Q 4:Lt/Q | none (no pixel change, text hold only) |
| chromium | hero.deck_article#0 | 0 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero.deck_article_0_0.png |
| chromium | hero.deck_article#0 | 1 | 1:Lt/L 2:Lt/L 3:Lt/L 4:Lt/L | strips/P_hero.deck_article_0_1.png |
| chromium | hero.deck_article#0 | 233 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero.deck_article_0_2.png |
| chromium | hero.deck_article#1 | 0 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero.deck_article_1_0.png |
| chromium | hero.deck_article#1 | 1 | 1:Lt/L 2:Lt/L 3:Lt/L 4:Lt/L | strips/P_hero.deck_article_1_1.png |
| chromium | hero.deck_article#1 | 233 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero.deck_article_1_2.png |
| chromium | hero.deck_article#1 | 466 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero.deck_article_1_3.png |
| chromium | hero.deck_article#2 | 0 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero.deck_article_2_0.png |
| chromium | hero.deck_article#2 | 1 | 1:Lt/L 2:Lt/L 3:Lt/L 4:Lt/L | strips/P_hero.deck_article_2_1.png |
| chromium | hero.deck_article#2 | 233 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero.deck_article_2_2.png |
| chromium | hero.deck_article#3 | 0 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero.deck_article_3_0.png |
| chromium | hero.deck_article#3 | 1 | 1:Lt/L 2:Lt/L 3:Lt/L 4:Lt/L | strips/P_hero.deck_article_3_1.png |
| chromium | hero.deck_article#3 | 233 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero.deck_article_3_2.png |
| chromium | hero.deck_article#3 | 466 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero.deck_article_3_3.png |
| chromium | hero_copy | 0 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero_copy_0.png |
| chromium | hero_copy | 1 | 1:Lt/L 2:Lt/L 3:Lt/L 4:Lt/L | strips/P_hero_copy_1.png |
| chromium | hero_copy | 233 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero_copy_2.png |
| chromium | hero_copy | 466 | 1:Lo/L 2:Lo/L 3:Lo/L 4:Lo/L | strips/P_hero_copy_3.png |
| chromium | hero_copy | 885 | 1:Lt/Q 2:Lt/Q 3:Lt/Q 4:Lt/Q | none (no pixel change, text hold only) |
| chromium | hero_copy | 886 | 1:Lt/Q 2:Lt/Q 3:Lt/Q 4:Lt/Q | none (no pixel change, text hold only) |

Priority for the look review:

| lane | offsets (y) | consumers | strip | what to look at |
|---|---|---|---|---|
| Simulator | 213, 427 | cue_cue, deck_article#0..3, hero_copy | `P_<key>_2.png`, `P_<key>_3.png`, `FRAME_P_2.png`, `FRAME_P_3.png` | halo around the moving cards |
| Simulator | 0, 1 | cue_cue, hero_copy (text hold) | `P_<key>_0.png`, `P_<key>_1.png` | text under the threaded translate |
| Chromium | 0, 1 | deck_article#0..3, cue_cue, hero_copy | `P_<key>_0.png`, `P_<key>_1.png` | start of track state |
| Chromium | 233, 466 | all | `P_<key>_2.png`, `P_<key>_3.png` | mid-track frame |

## Accepted limits, stand-ins, follow-ups

- No phone measurement; strips are CI artifacts only; CA blur stays Q; text layers under fractional translate stay L
  for the look review; Simulator vm 2 may fail on infrastructure (A/A is in each run, so one VM's cells suffice).
- TS stand-ins (not proved in Lean, listed per rule): the per-layer p1 census signature, `splitUnion` (checked against
  the golden `region` vectors), `driverMoved`, the transparent-in-both-arms skip (alpha below 1/255), the box union of
  an element and its descendants, the liveness witnesses and the report script. TS twins checked against golden:
  `exitOffsets`, `exitClaim`, `gradeRel`, `whyL`, `region` (`packages/contracts/golden/gate/path-pix.jsonl`).
- Counts: 4 jobs per lane on the final harness (runs 2 and 3, separate CI jobs). The webkit mid-track and Chromium
  start-of-track classes are stable; hero_copy cells on the Simulator and Chromium mid-track raw counts are not.
- Follow-ups: pin the accent-word chain in the lanes (A/A floor then 0 for hero_copy); read the L strips for the
  look review; Chromium image has no Thai fonts (counts-lane-fonts); decide whether the 1px mask margin should grow to
  the halo width.
