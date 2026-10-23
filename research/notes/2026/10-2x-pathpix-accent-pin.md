---
id: 2026-10-23-pathpix-accent-pin
kind: note
title: "PathPix accent pin: the hero accent word pinned to the served word in every arm; Chromium hero_copy A/A floor 0, WebKit 0 except 48 px at y 0"
status: draft
created: 2026-10-23
topics: [pathpix, webkit, chromium, hero.accent, a-a-floor, measurement]
---

# Pinning the hero accent word in PathPix

Task `pathpix-accent-pin`, branch `ci/pathpix-accent-pin` (worktree branch `worktree-wf_6d52745a-a7b-1`), workflow
`path-pix`. Premise from `hero-exit-threaded-pix`: the hero accent word differs between arms (A, A2, P), which gave the
hero_copy A/A cells a floor above 0 and four invalid WebKit cells at y 427. This task pins the word. Statuses:
CONFIRMED (source or proof), MEASURED (CI artifact), INFERRED.

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
(`pathpix-lane.test.mjs`); that fake-DOM check is the TS stand-in for the browser behaviour.

## Runs

| run | commit | pin | state |
|---|---|---|---|
| 39943789128 | 32d2316b3 | once per arm | complete, success |
| 39947605395 | 968f4a27b | once per arm and before every freeze | complete, success |

Each run has 2 Simulator jobs and 2 Chromium jobs (not the 3-job bar of the project rule; see limits).

## hero_copy A/A floor, changed px - max delta (inside mask / outside mask)

| job | y 0 | y 1 | y 213 or 233 | y 427 or 466 |
|---|---|---|---|---|
| chromium-1, run 1 | 490-222 / 0 | 377-213 / 0 | 142-20 / 0 | 0 |
| chromium-2, run 1 | 0 | 0 | 0 | 0 |
| chromium-1, run 2 | 0 | 0 | 0 | 0 |
| chromium-2, run 2 | 0 | 0 | 0 | 0 |
| webkit-1, run 1 | 48-1 / 0 | 0 | 0 | 0 |
| webkit-2, run 1 | 48-1 / 0 | 0 | 0 | invalid (A2 own shots differ) |
| webkit-1, run 2 | 48-1 / 0 | 0 | 0 | 0 |
| webkit-2, run 2 | 48-1 / 0 | 0 | 0 | 0 |

- MEASURED: pin applied (`same: true`) in all 3 arms of all 8 jobs. Invalid cells: 0 in run 2 (run 1, webkit-2: the
  A/A cells of hero_copy, hero.cue_cue and hero.deck_article at y 427).
- MEASURED: the live accent was mid-cycle at hold in WebKit arm A2 in all 4 WebKit jobs (before-signature differs from the
  served one: e1380ab3 in runs 1 and webkit-1 of run 2, 6c352725 in webkit-2 of run 2); after the pin it equals the served
  signature (22a26c2a). In Chromium the live word was the same in all arms (virtual clock), so the accent never was the
  Chromium noise.
- MEASURED, refutes an INFERRED cause: the Chromium floor of `hero-exit-threaded-pix` (hero_copy y 0, 1, 233) was the
  countdown seconds digit (spring mid-roll, strip `AA_hero_copy_0.png` of chromium-1 run 1), not the accent word. In run 2
  both Chromium jobs have floor 0 at every hero_copy cell; the cause of the change between the two chromium-1 runs is
  not isolated (the same code path for the countdown ran in both), so the 0 is a measured outcome, not a proved one.
- INFERRED: the invalid y 427 cell of webkit-2 run 1 (A2's own shots differing, accent slot wider with a different word
  mid-draw) was an accent element moving after the single pin. In run 2, with the pin re-applied before every freeze,
  all 36 rows of A2 and P (9 offsets, 2 arms, 2 jobs) show start signature = end signature = served in both WebKit jobs. The cause of the first
  movement is not known; it did not recur in 2 jobs.

## What is still not 0

- WebKit hero_copy A/A at y 0: 48 px at delta 1 inside the mask in all 4 WebKit jobs of both runs (same 48 px each time;
  bbox in the button area, css y about 536-659, from run 1). Not the accent (pinned, equal signatures). INFERRED
  raster noise in the call-to-action area; not pinned here (follow-up).
- Countdown seconds digit: needs its own pin if the Chromium floor of earlier runs recurs (follow-up).
- Next-section art at y 812 and 813 (WebKit A/A out of the hero zone): 2-1 px in webkit-1 run 2 but 192503 px at delta 20
  in webkit-2 run 2, avatar art, as in earlier runs. Not hero_copy exit evidence (follow-up).
- webkit-1 run 2, arm A only, at y 855 and 856: the accent element was a fresh live one (signature e1380ab3 at
  shot start, a7ccf8cf at shot end at y 855; an unpinned element at the pin of y 856). Something re-created the hero
  accent between the pin and the shot at the end of the track; A2 and P did not show it. The A/A cell at y 855 (row 7)
  differs by 63775 px at delta 255 (also P vs A 63756 px), so that offset must not be used as hero_copy evidence.
  Cause unknown (INFERRED: the hero part re-mounts at the end of its track in arm A, which is the longest-running page).

## Limits

- No phone; the strips stay CI artifacts (`path-pix-webkit-N/.../strips`); no local timing is reported.
- 2 jobs per engine per run, below the project's 3 separate-job bar: floor 0 in Chromium (both jobs of run 2; in run 1 only
  chromium-2 was at 0) and the WebKit pattern are reported as measured on those jobs; a repeat of
  the workflow with 3 or more jobs is a follow-up.
- Cells for other consumers (other layers than hero_copy) keep their earlier grades.
