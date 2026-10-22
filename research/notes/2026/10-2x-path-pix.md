# Path-pix lanes: the first calibration on the original, per lane

Question: when only one declared layer is forced onto its own compositing layer (`?fwl=<layer>:c`, arm P), does a device
frame at a Lean-chosen scroll offset stay pixel-equal to the page as it is (arm A)? A calibration first checks that the
lane itself is quiet: two loads of the same page (A and A2, the A/A cells) must be equal before a P cell means anything.
Tags: MEASURED (a CI run id named), INFERRED (reasoned, not seen), CONFIRMED (source read).

## Answer

| lane | what it is | A/A cells | P cells | verdict of the lane |
|---|---|---|---|---|
| Linux Chromium, begin-frame screenshots | software compositing (`--disable-gpu`), secondary | 29 of 29 E | 28 E, 1 L | quiet and reproducible (4 runs x 2 jobs identical) |
| iOS 27 Simulator, `simctl io screenshot` | the verdict lane; the Simulator has no real GPU | 0 E, 21 L, 6 invalid of 27 | 1 E, 8 L, 4 invalid of 13 | not quiet: the page itself changes between loads (below) |

- MEASURED, Chromium: runs 39778557659, 39786950659, 39797455671, 39805943152 (jobs `chromium (1)` and `(2)` of each), frame 430x932 CSS px
  (the page runs at dpr 3, a begin-frame screenshot is in CSS px), 6 declared layers, 9 offsets. The one L cell is
  `hero.deck_article` P at offset 0: 2 pixels inside the mask and 1 outside differ by 1 level (max delta 1). It is the same
  cell in all eight jobs. Chromium is software compositing here, so it says nothing about GPU compositing (accepted limit).
- MEASURED, Simulator: run 39805943152 `sim (1)` (the final harness, commit 90bdc8e3) and run 39797455671 `sim (1)` (commit 39200598).
  The other Simulator jobs failed before a cell: 39797455671 `sim (2)` (`simctl list runtimes` aborted, exit 134, CoreSimulator not
  up), 39805943152 `sim (2)` (Safari never listed a tab in 240 s, twice), 39786950659 both (the 45 min step timeout; the old
  harness wrote its manifest only at the end), 39778557659 `sim (1)` (Safari tab lost). Run 39778557659 sim (2) (first harness, 1aa0944d, all six P layers) also produced cells: A/A 27 (17 L, 10 invalid), P 27 (1 E nav_bar@1,
  1 Q nav_bar@4, 14 L, 11 invalid); three runs have Simulator cells. The Chromium calibration has four.

## Simulator cells (run 39805943152, vm 1, frame 1290x2325 device px, offsets 0,658,1316,1975,2633,3291,3950,4608,5267)

Offsets are indices 0-8. A P arm is captured only where arm A shows its layer, so a layer has fewer cells than offsets.

| layer | kind | offset index: verdict |
|---|---|---|
| hero.countdown_face | A/A | 0:L 1:L |
| hero.cue_cue | A/A | 0:L 1:L 2:L |
| hero.cue_cue | P | 0:L 1:L 2:L |
| hero.deck_article | A/A | 0:L |
| hero.deck_article | P | 0:L |
| hero_copy | A/A | 0:L 1:L 2:L |
| nav_bar | A/A | 0:L 1:L 2:L 3:L 4:L 5:invalid 6:L 7:invalid 8:invalid |
| nav_bar | P | 0:L 1:L 2:invalid 3:L 4:L 5:invalid 6:E 7:invalid 8:invalid |
| nav_earn | A/A | 0:L 1:L 2:L 3:L 4:L 5:invalid 6:L 7:invalid 8:invalid |

`hero.countdown_face`, `hero_copy` and `nav_earn` have no P cells here: vm 2 never got a tab (run 39805943152) and vm 2 of the
earlier run failed before the capture. They are measured only in run 39778557659 sim (2), first harness.

## Why the Simulator A/A is not E (MEASURED strips, INFERRED causes)

The strips are in the CI artifacts `path-pix-webkit-1` of both runs: `strips/AA_<layer>_<i>.png`, `P_<layer>_<i>.png` (A | B | 32x
amplified difference, red outside the mask) and `strips/FRAME_A2_<i>.png` (whole frame, A | A2 | difference). The whole-frame
difference of A and A2 shows content that moved, not rendering that differs:

| offset | what differs between the two loads | cause (INFERRED) |
|---|---|---|
| 0 | the hero headline word ("คุณ" in one load, "you" in the other) | the word chain runs on timers from hydration (first change after 2200 ms, `hero.accent/logic.ts` FIRST_WAIT); the harness holds the timers after hydration, fonts and images, 2.7 to 6.5 s after navigation on the runner (log lines `timers held`), so the phase differs per load |
| 2 (run 39797455671) | portfolio image tiles at pixel level, the avatar stack order | image decode finishing late; avatar rotation |
| 5 | the chat bubble typed text and the fee card fading in | JS motion on rAF time; both captures of one load differ too, so the cell is `invalid` |
| 7 | the demo search field text and card text | same |

- The within-load instability (P4: two captures of one load must be equal) went from 12 invalid of 27 A/A cells (39797455671)
  to 6 invalid (39805943152) after the harness shot until two captures agree (at most 6), paused videos, and waited for images
  near the fold. The page has no `<video>` element in view (the `video` field of every row is empty), so the pauses did nothing.
  What is left is JS motion that the frozen-clock pass (CSS animations only, `Fw.Gate.Freeze`) does not stop.
- The nav pill (`nav_bar`) is a translucent blur over page content, so its inside pixels change when the content behind it changes
  (inside max delta 14 in A/A). It is not a rendering difference of the pill.
- This is the WebKit load variance of undeclared page content that `census-load-variance` owns; this task reports it, it does not
  fix it. No Simulator P cell can be E while A/A is not, except where the frame happens to be static: `nav_bar` P at offset 6 is
  the one E (the frame difference is 0 pixels there, `FRAME` line of the log).

## What the lanes do (CONFIRMED from the code)

- Offsets, masks and grades come from Lean (`lean/Fw/Gate/PathPix.lean`); the TS twin `packages/measure-webkit/src/pathpix.mjs` is
  checked line by line against `packages/contracts/golden/gate/path-pix.jsonl` in `test/pathpix.test.mjs`.
- Simulator lane: `packages/measure-webkit/src/pathpix-{cli,webkit,page,analyze,png}.mjs`. Timers are held and CSS animations frozen
  per arm; each offset is a `simctl io screenshot`, cropped to the layout viewport (found with a magenta marker box). A P arm is
  captured only at the offsets where arm A shows its layer: the analysis masks the box of arm A, so any other frame would never be
  read (`inViewPositions`, a TS composition of the golden-checked `mask` and `maskEmpty`, a TS stand-in for the capture list).
- Chromium lane: `packages/measure-chromium/src/pathpix*.mjs`, driver in the container, analysis on the host with the same
  `analyzeLane`. Workflow `.github/workflows/path-pix.yml`, token `[ci:path-pix]` in the commit message.
- P arms client-render while arm A hydrates (`?fwl=` searches are not prerendered): both end in the same DOM, but a hydration-only
  difference would not show as a cell by itself.
- CI cost on the runner: A 11 min and A2 7 min (39797455671), A 6 min and A2 14 min with one Safari relaunch (39805943152). The
  runner (3 vCPU, load average up to 72 while the Simulator booted) is slow; the two Simulator jobs split the P arms so each fits
  45 min, and the loop stops starting P arms after 34 min.

## Follow-ups (outside the unit)

1. Hold the page timers one frame after hydration, before waiting for fonts and images, so the headline chain starts from the same
   phase in every load. Needs a check that no image fade-in then stays hidden (a timer made after the hold never fires). Tried in 3fd97967 and reverted in 90bdc8e3 before a dispatch (never measured on CI);
   90bdc8e3 went back to the hold after hydration and fonts and logs the hold time and headline word, and its message states no other reason.
2. Pin the rAF timestamp the page sees (a constant, or a virtual clock stepped by the harness) so JS motion (avatar rotation, demo
   typing, chat bubbles) does not advance between loads. Without it the Simulator A/A stays L.
3. A second Simulator job per run keeps failing at start (CoreSimulator abort, no Safari tab); a retry of the job, or a start probe
   with a bounded retry before the capture, would turn one result per run into two.
4. Text layers under fractional translate stay L until the user sees strips; CA blur is Q (task limits, unchanged).
