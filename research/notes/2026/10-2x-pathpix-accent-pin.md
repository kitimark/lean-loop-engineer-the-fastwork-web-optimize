---
id: 2026-10-23-pathpix-accent-pin
kind: note
title: "PathPix accent pin: the pin works but does not bring the hero_copy A/A floor to 0 (closed as a finding)"
status: closed-finding
created: 2026-10-23
topics: [pathpix, webkit, chromium, hero.accent, a-a-floor, measurement]
---

# Pinning the hero accent word in PathPix

Task `pathpix-accent-pin`, branch `ci/pathpix-accent-pin` (worktree branch `worktree-wf_6d52745a-a7b-1`), workflow
`path-pix`. Premise from `hero-exit-threaded-pix`: the hero accent word differs between arms (A, A2, P), which gave the
hero_copy A/A cells a floor above 0 and four invalid WebKit cells at y 427. This task pins the word. Statuses:
CONFIRMED (source or proof), MEASURED (CI artifact), INFERRED.

**Finding (round 2, closed): pinning the accent does not bring the hero_copy A/A floor to 0.** The pin works (the accent
shows the served word in every recorded row of 3 of the 4 jobs of run 2 and in all but one row of the fourth), but the floor sources are other
elements, listed under "Remaining floor sources" and re-planned as graph task `hero-copy-floor-sources`.

## Mechanism (CONFIRMED, source)

- Capture-side only, no site change. `PIN_ACCENT_EXPR` (`packages/measure-webkit/src/pathpix-exit-page.mjs`) makes a
  synchronous request of the same URL, parses it, and replaces the live `[data-fw="hero-accent"]` element by the element
  of the page as served (the base word, idle). The live chain (`apps/site/src/parts/hero.accent/driver.ts`, real
  interval timers from `getClock()`) keeps writing to the detached old element, so nothing it does is visible.
- Applied in all three arms: after `__wk.hold()` (WebKit) or at the end of `loadArm` (Chromium), and again before every
  freeze, so a re-created element cannot slip in between offsets (round 2). The element carries a mark so the next pin
  can tell a still-pinned element from a fresh live one.
- Per row the lanes record `accent`: `drift` (state just before the pin, whether it was still pinned), `shotStart` and
  `shotEnd` (element count, signature) around the two screenshots. The manifest holds `handover.pin.<arm>`.

## Lean statement and golden (CONFIRMED, proved)

`lean/Fw/Gate/PathPix.lean`, section "Accent pin": `armPin` is `ssr` for every arm (`armPin_same`, `armPin_all`),
`pinAt` gives the same pin at every offset (`pinAt_same`, `pinAt_all`), a pinned arm shows `{cursor -1, idle}` whatever the
live state (`shown_ssr`, `shown_arm_independent`), an unpinned arm shows the live state (`shown_none`), the pin changes no
mask (`pinMasks_eq`, `region_pin`). Golden kinds `accentPin` (3 arms x 3 live cases, with `perOffset`) and `pinRegion`
in `packages/contracts/golden/gate/path-pix.jsonl`, replayed by `packages/measure-webkit/test/pathpix.test.mjs`; the
Chromium `armPin` and `pinAt` are tested equal to the WebKit twin. The injected expressions are checked on a fake DOM
(`pathpix-lane.test.mjs`), a TS stand-in for the browser.

## Runs

| run | commit | pin | state |
|---|---|---|---|
| 39943789128 | 32d2316b3 | once per arm | complete, success |
| 39947605395 | 968f4a27b | once per arm and before every freeze | complete, success |

Each run has 2 Simulator jobs and 2 Chromium jobs (not the 3-job bar of the project rule; see limits). No new run in
round 2: the tables below are read from the committed `cells.json` and `manifest.json` of the two runs (artifacts
`path-pix-chromium-1/2`, `path-pix-webkit-1/2`).

## hero_copy A/A at all 9 offsets, per job (MEASURED)

Cell = changed px / max delta inside the hero_copy mask : outside the mask (0 = no changed pixel). `skip` = the cell
does not exist: hero_copy is transparent in both arms at that offset (the exit track has faded it out; webkit-1 run 2,
offset index 7, is the exception, see below). `invalid` = A2's own two shots differ (the cell cannot be read). The y
column lists the scroll offsets of the job.

| job | y offsets | i0 | i1 | i2 | i3 | i4 | i5 | i6 | i7 | i8 |
|---|---|---|---|---|---|---|---|---|---|---|
| chromium-1 r1 | 0 1 233 466 885 886 931 932 933 | 490/222 : 0 | 377/213 : 0 | 142/20 : 0 | 0 : 0 | 0 : 0 | 0 : 0 | skip | skip | skip |
| chromium-2 r1 | 0 1 233 466 885 886 931 932 933 | 0 : 0 | 0 : 0 | 0 : 0 | 0 : 0 | 0 : 0 | 0 : 0 | skip | skip | skip |
| webkit-1 r1 | 0 1 213 427 812 813 854 855 856 | 48/1 : 0 | 0 : 0 | 0 : 0 | 0 : 0 | 0 : 2/1 | 0 : 2/1 | skip | skip | skip |
| webkit-2 r1 | 0 1 213 427 812 813 854 855 856 | 48/1 : 0 | 0 : 0 | 0 : 0 | 41589/106 : 0 invalid | 197073/255 : 59840/255 | 195781/253 : 61142/255 | skip | skip | skip |
| chromium-1 r2 | 0 1 233 466 885 886 931 932 933 | 0 : 0 | 0 : 0 | 0 : 0 | 0 : 0 | 0 : 0 | 0 : 0 | skip | skip | skip |
| chromium-2 r2 | 0 1 233 466 885 886 931 932 933 | 0 : 0 | 0 : 0 | 0 : 0 | 0 : 0 | 0 : 0 | 0 : 0 | skip | skip | skip |
| webkit-1 r2 | 0 1 213 427 812 813 854 855 856 | 48/1 : 0 | 0 : 0 | 0 : 0 | 0 : 0 | 0 : 2/1 | 0 : 2/1 | skip | 66/1 : 63775/255 | skip |
| webkit-2 r2 | 0 1 213 427 812 813 854 855 856 | 48/1 : 0 | 0 : 0 | 0 : 0 | 0 : 0 | 192503/20 : 2015/5 | 192513/20 : 2015/5 | skip | skip | skip |

Reading (MEASURED, the wording of round 1 corrected):

- Chromium: run 1 had a floor in chromium-1 only (490 px at delta 222 at y 0, 377 px delta 213 at y 1, 142 px delta 20 at
  y 233, all inside the mask); chromium-2 of run 1 and both Chromium jobs of run 2 are 0 at every cell. The pin replaced the
  Chromium accent (live 517919cd, served 22a26c2a) the same way in all arms; the live word was already the same in all arms under the virtual clock, so run 1 chromium-1 and run 2 differ for
  a reason not isolated (see the countdown digit below).
- WebKit y 0: 48 px at delta 1 inside the mask in all 4 WebKit jobs of both runs, pinned or not.
- WebKit y 812 and 813 (i4, i5): these are hero_copy cells with change, not cells outside the hero zone. webkit-1 has 2 px
  at delta 1 outside the mask in both runs. webkit-2 run 2 has 192503 px at delta 20 inside the hero_copy mask and 2015 px
  at delta 5 outside (run 1: about 197000 inside at delta 255 and about 60000 outside). INFERRED: the avatar art of the
  next section is painted under the mask at that scroll position and moves between the two arms, so these cells measure
  art noise, not hero_copy exit.
- WebKit y 427 (i3) of webkit-2 run 1: the cell was `invalid` (41589 px, A2's own shots differ); in run 2 it is 0.
- WebKit i7 (y 855) of webkit-1 run 2: arm A had scrollY 0 instead of 855 in that row (the page was back at the top; its
  accent was a fresh live element, signature e1380ab3 at shot start, a7ccf8cf at shot end). The cell compares a page at
  the top with one at 855, hence 63775 px at delta 255 outside the mask. It is not a hero_copy floor and is now marked
  `accent-unpinned` (below).

## hero_copy P cells with their grade, per job and offset (MEASURED)

Grades as recorded by the runs, before the per-row accent rule. Under that rule the webkit-1 run 2 offset 7 row is invalid (accent-unpinned), so run 2 has 24 L (15 above the floor, 9 strips not accepted), and every run 1 cell is invalid (no row record).

Same units. P = the threaded arm against arm A. `floor` = the A/A cell of the same offset. `why` = reason of the
absolute grade L. `if strips accepted` = the grade the cell would get if the strips were reviewed and accepted
(`stripsAccepted` is false for every cell here: nobody has accepted the strips). `L from`: `above floor` = P differs from
A by more than the floor, so L stays even with strips accepted (the exit motion itself, the P arm is the experiment);
`strips not accepted` = P is within the floor, and the cell is L only because a text claim needs accepted strips
(`textHold`: premise C1 and no accepted strips).

| job | offset | P inside : out | floor inside : out | grade | why | if strips accepted | L from |
|---|---|---|---|---|---|---|---|
| chromium-1 r1 | 0 (y 0) | 925/222 : 80/1 | 490/222 : 0 | L | outside | L | above floor |
| chromium-1 r1 | 1 (y 1) | 526/222 : 0 | 377/213 : 0 | L | text | L | above floor |
| chromium-1 r1 | 2 (y 233) | 319/88 : 82/2 | 142/20 : 0 | L | outside | L | above floor |
| chromium-1 r1 | 3 (y 466) | 130/7 : 741/1 | 0 : 0 | L | outside | L | above floor |
| chromium-1 r1 | 4 (y 885) | 0 : 0 | 0 : 0 | L | text | Q | strips not accepted |
| chromium-1 r1 | 5 (y 886) | 0 : 0 | 0 : 0 | L | text | Q | strips not accepted |
| chromium-2 r1 | 0 (y 0) | 430/222 : 80/1 | 0 : 0 | L | outside | L | above floor |
| chromium-2 r1 | 1 (y 1) | 464/213 : 0 | 0 : 0 | L | text | L | above floor |
| chromium-2 r1 | 2 (y 233) | 290/49 : 139/1 | 0 : 0 | L | outside | L | above floor |
| chromium-2 r1 | 3 (y 466) | 130/7 : 678/1 | 0 : 0 | L | outside | L | above floor |
| chromium-2 r1 | 4 (y 885) | 0 : 0 | 0 : 0 | L | text | Q | strips not accepted |
| chromium-2 r1 | 5 (y 886) | 0 : 0 | 0 : 0 | L | text | Q | strips not accepted |
| webkit-1 r1 | 0 (y 0) | 0 : 0 | 48/1 : 0 | L | text | Q | strips not accepted |
| webkit-1 r1 | 1 (y 1) | 0 : 0 | 0 : 0 | L | text | Q | strips not accepted |
| webkit-1 r1 | 2 (y 213) | 0 : 1833/2 | 0 : 0 | L | outside | L | above floor |
| webkit-1 r1 | 3 (y 427) | 0 : 2744/1 | 0 : 0 | L | outside | L | above floor |
| webkit-1 r1 | 4 (y 812) | 0 : 2/1 | 0 : 2/1 | L | outside | Q | strips not accepted |
| webkit-1 r1 | 5 (y 813) | 0 : 2/1 | 0 : 2/1 | L | outside | Q | strips not accepted |
| webkit-2 r1 | 0 (y 0) | 0 : 0 | 48/1 : 0 | L | text | Q | strips not accepted |
| webkit-2 r1 | 1 (y 1) | 0 : 0 | 0 : 0 | L | text | Q | strips not accepted |
| webkit-2 r1 | 2 (y 213) | 0 : 1833/2 | 0 : 0 | L | outside | L | above floor |
| webkit-2 r1 | 3 (y 427) | 39/1 : 2744/1 | invalid 41589/106 : 0 | L | outside | L | above floor |
| webkit-2 r1 | 4 (y 812) | 0 : 0 | 197073/255 : 59840/255 | L | text | Q | strips not accepted |
| webkit-2 r1 | 5 (y 813) | 0 : 0 | 195781/253 : 61142/255 | L | text | Q | strips not accepted |
| chromium-1 r2 | 0 (y 0) | 430/222 : 80/1 | 0 : 0 | L | outside | L | above floor |
| chromium-1 r2 | 1 (y 1) | 464/213 : 0 | 0 : 0 | L | text | L | above floor |
| chromium-1 r2 | 2 (y 233) | 290/49 : 139/1 | 0 : 0 | L | outside | L | above floor |
| chromium-1 r2 | 3 (y 466) | 130/7 : 678/1 | 0 : 0 | L | outside | L | above floor |
| chromium-1 r2 | 4 (y 885) | 0 : 0 | 0 : 0 | L | text | Q | strips not accepted |
| chromium-1 r2 | 5 (y 886) | 0 : 0 | 0 : 0 | L | text | Q | strips not accepted |
| chromium-2 r2 | 0 (y 0) | 430/222 : 80/1 | 0 : 0 | L | outside | L | above floor |
| chromium-2 r2 | 1 (y 1) | 464/213 : 0 | 0 : 0 | L | text | L | above floor |
| chromium-2 r2 | 2 (y 233) | 290/49 : 139/1 | 0 : 0 | L | outside | L | above floor |
| chromium-2 r2 | 3 (y 466) | 130/7 : 678/1 | 0 : 0 | L | outside | L | above floor |
| chromium-2 r2 | 4 (y 885) | 0 : 0 | 0 : 0 | L | text | Q | strips not accepted |
| chromium-2 r2 | 5 (y 886) | 0 : 0 | 0 : 0 | L | text | Q | strips not accepted |
| webkit-1 r2 | 0 (y 0) | 16655/42 : 0 | 48/1 : 0 | L | text | L | above floor |
| webkit-1 r2 | 1 (y 1) | 0 : 0 | 0 : 0 | L | text | Q | strips not accepted |
| webkit-1 r2 | 2 (y 213) | 0 : 1833/2 | 0 : 0 | L | outside | L | above floor |
| webkit-1 r2 | 3 (y 427) | 0 : 2744/1 | 0 : 0 | L | outside | L | above floor |
| webkit-1 r2 | 4 (y 812) | 0 : 0 | 0 : 2/1 | L | text | Q | strips not accepted |
| webkit-1 r2 | 5 (y 813) | 0 : 0 | 0 : 2/1 | L | text | Q | strips not accepted |
| webkit-1 r2 | 7 (A at y 0, P at 855) | 0 : 63756/255 | 66/1 : 63775/255 | L (now invalid: accent-unpinned) | outside | Q (now invalid: accent-unpinned) | strips not accepted |
| webkit-2 r2 | 0 (y 0) | 0 : 0 | 48/1 : 0 | L | text | Q | strips not accepted |
| webkit-2 r2 | 1 (y 1) | 0 : 0 | 0 : 0 | L | text | Q | strips not accepted |
| webkit-2 r2 | 2 (y 213) | 0 : 1833/2 | 0 : 0 | L | outside | L | above floor |
| webkit-2 r2 | 3 (y 427) | 0 : 2744/1 | 0 : 0 | L | outside | L | above floor |
| webkit-2 r2 | 4 (y 812) | 192503/20 : 6493/5 | 192503/20 : 2015/5 | L | outside | L | above floor |
| webkit-2 r2 | 5 (y 813) | 192513/20 : 6493/5 | 192513/20 : 2015/5 | L | outside | L | above floor |

Counts of L cells: run 1 recorded 24 (all invalid under the rule), 12 above the floor and 12 from strips not accepted; run 2 recorded 25 (24 under the rule), 15 above the floor and
10 from strips not accepted. Every L is one of these two; none comes from the floor alone. In the 10 + 12 recorded `strips not
accepted` rows (9 + 0 under the rule) P is within its floor (0 changed, or inside a larger floor), so with accepted strips they would be Q. The
`above floor` cells are P changes with floor 0 (130 to 925 px inside in Chromium, 1833 and 2744 px outside in WebKit),
except webkit-2 run 2 at y 812 and 813 where the floor is itself art noise. webkit-1 run 2 at y 0 has 16655 px at delta
42 inside in P (0 in the other three WebKit jobs and in run 1) over the usual 48 px A/A floor: a P-versus-A difference
seen in one job of two.

## What the pin did and did not do (MEASURED)

- Pin applied (`same: true`) in all 3 arms of all 8 jobs. In run 2, 0 invalid A/A cells (run 1, webkit-2: the A/A cells
  of hero_copy, hero.cue_cue and hero.deck_article at y 427).
- The live accent was mid-cycle at hold in WebKit arm A2 in all 4 WebKit jobs (before-signature differs from the served
  one: e1380ab3 in run 1 and webkit-1 of run 2, 6c352725 in webkit-2 of run 2); after the pin it equals the served
  signature (22a26c2a). In Chromium the live word was the same in all arms (virtual clock), so the accent never was the
  Chromium noise.
- In run 2 all rows of A2 and P (9 offsets, 2 arms, 2 WebKit jobs) and 8 of 9 rows of arm A in webkit-1 (all 9 in
  webkit-2) show start signature = end signature = served. The one row that does not is webkit-1 arm A at offset index 7.

## Conclusion

**Pinning the accent does not bring the hero_copy A/A floor to 0.** Chromium reached 0 in run 2, but its floor in run 1
chromium-1 was not the accent (the live word was identical in all arms there). WebKit keeps 48 px at y 0 in all 4 jobs
with the accent pinned, and has avatar-art noise at y 812 and 813 in webkit-2 in both runs. The pin removed one real
disturbance (the WebKit A2 arm was mid-cycle at hold in every WebKit job; the invalid y 427 cell of webkit-2 run 1 did not
recur in run 2) but the floor of the hero_copy cells stays above 0 in WebKit.

## Remaining floor sources (re-planned in graph task `hero-copy-floor-sources`)

| source | evidence | status |
|---|---|---|
| countdown seconds digit (Chromium y 0, 1, 233) | strip `AA_hero_copy_0.png` of chromium-1 run 1 (digit mid-roll); the same code path gave 0 in run 2 | MEASURED once, cause of the change not isolated |
| call-to-action area, 48 px at delta 1 at y 0 (WebKit) | same 48 px in 4 of 4 WebKit jobs, both runs, bbox css y about 536-659 (run 1), accent signatures equal | MEASURED, cause INFERRED raster noise |
| next-section avatar art at y 812 and 813 (WebKit) | webkit-2: 192503 px delta 20 inside plus 2015 px outside (run 2); webkit-1: 2 px outside | MEASURED, cause INFERRED art animation |
| arm A page at scrollY 0 at offset index 7 (webkit-1 run 2) | manifest row A[7]: scrollY 0 vs y 855, accent re-created (e1380ab3 then a7ccf8cf) | MEASURED, cause unknown (INFERRED re-mount or scroll reset) |
| React re-creation of the swapped accent node | the pin replaces the DOM node; a site-side re-render can re-create it | INFERRED, needs a site-side hook (`hero-copy-floor-sources`) |

## Accent pin enforced per measured row (CONFIRMED, proved, replayed)

A pin applied before the freeze is not a pin at the shot. A cell is now graded only when every arm row it uses shows
the served accent, once, at the start and at the end of its two screenshots.

- Lean `lean/Fw/Gate/PathPix.lean`, "The pin per measured row": `accentPinned served start stop n := n = 1 && start =
  served && stop = served` (`end` is a Lean keyword, so `stop`), `rowsPinned`, `gradePinned` (invalid when a row is
  unpinned, else `gradeRel`), `unpinnedWhy` ("accent-unpinned"), `floorPinned` (an A/A floor whose rows are unpinned is
  not valid). Theorems: `accentPinned_iff`, one theorem per way to be unpinned (`accentPinned_false_of_n`,
  `_of_start`, `_of_stop`), `rowsPinned_iff`, `gradePinned_of_pinned`, `gradePinned_invalid_of_unpinned`,
  `gradePinned_valid_only_if` (a cell is valid only if `accentPinned` holds for every arm row it uses),
  `gradePinned_invalid_iff`, `unpinnedWhy_iff`, `floorPinned_valid_only_if`.
- Golden kinds `accentRow` (6 cases) and `accentGrade` (5 row sets times the 13 `rel` cases) in
  `packages/contracts/golden/gate/path-pix.jsonl`, replayed by `packages/measure-webkit/test/pathpix.test.mjs`.
- TS: `accentPinned`, `rowsPinned`, `gradePinned`, `unpinnedWhy`, `floorPinned` in
  `packages/measure-webkit/src/pathpix-exit.mjs`. `analyzeExit` marks the cell `accentPinned: false`, grade, absGrade and
  if-accepted `invalid`, `invalidWhy: 'accent-unpinned'`, `why: null`, and its A/A floor invalid. The served signature
  is `handover.pin.A.ssr` for all arms. A row without an accent record (older manifests) is unpinned. The exit table
  prints the count. The Chromium lane writes the same manifest rows and is analysed by the same function; its
  `accentPinned` in `packages/measure-chromium/src/pathpix-pure.mjs` is tested equal. `accentRowOf` (record to Lean's
  row; n taken as 0 when the start and end counts differ) is glue, a TS stand-in.
- Dev check: the pin rule applied to the committed `manifest.json` rows of the two runs (no shots needed).

| run | cells | marked accent-unpinned |
|---|---|---|
| 39947605395 (row records exist) | 220 (52 + 52 + 64 + 52) | **12**: webkit-1, offset index 7 (y 855): 6 A/A + 6 P cells (hero_copy, hero.cue_cue, 4 hero.deck_article) |
| 39943789128 (single pin, no per-row record) | 208 | 208 (all: no row record, so no proof the accent was pinned at the shot) |

## Open

- The React re-creation of the swapped node needs a site-side hook (`hero-copy-floor-sources`).
- The 3-job bar: both runs have 2 jobs per engine; a repeat with 3 or more jobs (`hero-copy-floor-sources`).
- A row whose `scrollY` differs from its offset (webkit-1 run 2, index 7) is not yet its own validity rule.

## Limits

- No phone; the strips stay CI artifacts (`path-pix-webkit-N/.../strips`); no local timing is reported.
- 2 jobs per engine per run, below the project's 3 separate-job bar. No new CI run in round 2.
- All committed cells.json grades predate the per-row rule; under it the 12 run 2 cells above and all 208 run 1 cells are invalid; no cell was regraded here.
- A P cell whose A2 row alone is unpinned grades L through its invalid floor, not invalid; it can never grade Q.
