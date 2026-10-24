# device-lag-recorder: the felt-lag session on the real iPhone

The lag the user feels is on the phone (WebKit); Chromium at normal speed is smooth, and shows the lag only at 6x CPU throttling.
This tool records one person's swipe passes on the phone, finds the moments the person
marked as laggy, reduces them with Lean, and turns the gesture into a profile CI can replay.

Code: `packages/measure-webkit/src/device-record.mjs` (page recorder, banner flow), `device-session.mjs` (TS twin of
`lean/Fw/Device/Session.lean`), `device-profile.mjs` (export and packaging), `device-cli.mjs` (commands). Golden:
`packages/contracts/golden/device/session.jsonl`. Replay loader: `packages/measure-chromium/src/profile.mjs`.

## What a pass records (`fw.phone.record/1`, page units)

- Per native `requestAnimationFrame`: timestamp (ms), `scrollY` (px) and three part values (per mille, read from the inline custom
  properties the page writes): hero exit `--exit-opacity`, people card shrink `--future-shrink`, end-of-page morph `--morph-fade`.
- Per frame also the visual viewport height `vh` and its `offsetTop` `vt` (0.1 px; `innerHeight` and 0 where there is no
  `visualViewport`). The Safari toolbar collapsing or returning changes the height (815 vs 775 px) while the person swipes; the
  per-pass `viewport.h` is read once at the start and cannot say when. Only `vh` is used by Lean today; `vt` is kept for later.
- Every touch event: time, phase (`s` start, `m` move, `e` end, `c` cancel), x, y, fingers down. Listeners are passive and never call
  `preventDefault`, so the page behaves as without them.
- A triple tap on an empty area is a felt-lag mark. It is not a special event: Lean finds it afterwards (three taps, each at most 300 ms
  long and 10 px travel at most, 0.5 s apart at most, within 40 px of each other).
- No device name, address or id is in a record. The file holds raw timestamps, so it stays local (`.local/phone/<date>/`, gitignored).

Not recorded: the Timeline. `swipe --timeline` (unchanged) is the counts arm; the recorder takes the frame-interval arm because the
Timeline costs time on the page.

Known effects:
1. A touch on a moving page stops its native fling, so the person's taps change the scroll they mark; tell the person to tap and
   carry on.
2. The recorder's own rAF callback and three inline style reads run every frame (inline style reads do not flush layout). The
   `visualViewport` reads do: `scale`, `height` and `offsetTop` each call `updateFrameLayout` (WebKit `VisualViewport.cpp:72-76`,
   `87-94`, `123-130`, `132-141` @ 862f17d), and `scrollY` does when it is not 0 (`LocalDOMWindow.cpp:1476-1480` @ 862f17d). The callback writes no DOM and `scale` and `scrollY`
   were already read every frame, so the layout is already current and `height` and `offsetTop` add no layout work. It runs before
   the page's callbacks of that frame, so the value read in frame i+1 is the one the page wrote in frame i from the position of frame
   i. Lean `partSeries` pairs each value with that earlier position, and the stall rule compares those pairs (the old pairing of a
   value with the position read beside it counted a false stall at every scroll start). All arms and both original passes carry the
   same probe effect, so the comparison is unaffected.
3. The mark must not change the page. The step text says "tap 3 times quickly on an empty area (not on text, a link or a button)". A
   tap on a link navigates away and loses the pass: a passive `pagehide` listener writes `page navigated (a tap hit a link)`, and the
   poll names the same failure when the recorder's page is gone, so the step fails with that reason instead of a timeout. Three taps
   on text can start a text selection, and a double tap can zoom (the viewport does not forbid it): the visual viewport `scale` is
   read every frame, the record carries `zoom {frames, min, max}` for the frames at a scale other than 1, and the CLI prints
   `zoomFrames` and logs a warning. Repeat a step with zoom frames or a navigation.

## Reductions (Lean `Fw.Device.Session`)

Times in hundredths of a ms, positions in tenth px (integers). Per pass and per zone (hero = first two viewports, finish = last
viewport, rest): moving frames over 34 ms and over 50 ms, each per 100 moving frames, longest and median interval; per part the
largest step and the stalls (page moved, value held mid-transition); per felt mark the position, zone and the same counts over its
1.5 s lookback window. The comparison: an arm beats the original in a zone only when its worst pass is below the original's best
pass by more than the original's pass-to-pass spread (verdicts `beats | worse | same | unresolved`; one original pass or no arm
pass is `unresolved`).

### Toolbar class (Lean `Fw.Device.Session` "The toolbar class of a frame", `Fw.Device.StillRuns` "The verdict by toolbar class")

A pass that starts with the Safari toolbar collapsed (viewport height 815 vs 775) is a different page layout from one that starts
expanded; with one height per pass the still-run verdict was `confounded`. Now every frame has a height and a class:

- A frame is `moving` when the viewport height changed (by at least `moveMin` = 1 tenth px) between two frames within `moveWin` = 30
  frames of it (about half a second at 60 Hz); every other frame is `still`. Both constants are named in Lean and read by the twin from
  the golden. The split is a partition (theorems `classes_count`, `index_partition`); a constant height is all still (`classes_const`).
- The reduction by class (`reduceClass`): a frame interval takes the class of its later frame. For each class the same counts as the
  whole pass (total and per zone) plus how many frames the class holds. The two classes together hold exactly today's intervals
  (`reduceClass_total_split`, `_zone_split`, `_frames_split`).
- The comparison within a class (`compareClass`): the verdict rule above over the passes that hold at least one frame of the class (a pass
  without any is not a score). It is never mixed across classes, so a pass that started collapsed is compared on its still frames.
- The still-run counts by class (`armOf`): runs and exit frames of each class are counted separately (a run is `moving` when any of its
  frames, up to the one that ends it, is moving; `countC_split`). The moving class compares counts only (`verdictMoving`; its heights
  differ by definition).
- The still-run verdict by height (`verdictByHeight`): the still class is split by the viewport height of its frames (`Pass.csAt`: a frame
  is in the group of height `g` when it is toolbar-still and at `g`; `Pass.csAt_still_iff`), and each height present in both arms gets its
  own verdict on only those frames (`verdictAt`, never `confounded`: `verdictAt_ne_confounded`, `verdictByHeight_ne_confounded`). A height
  that only one arm has is reported `not-comparable`, not judged. So a collapsed start shorter than `moveWin` frames no longer makes
  the pass `confounded`, and a pass whose toolbar was held collapsed longer than `moveWin` frames (still frames at 815 and at 775) is
  judged at 775 and at 815 separately instead of being `confounded` as a whole. The golden lines `cverdict` hold a 31-frame and a
  60-frame collapse against a lift at 775 (815 `not-comparable`, 775 `lifted`, today `confounded`) and both arms toggling 775/815
  mid-pass (both heights `lifted`).
- Old recordings (no `vh` per frame, or a list of the wrong length) are still at every frame, in the group of their one height:
  `classesOf_noField`, `reduceClass_noField` and `compareClass_noField` prove the still class is today's reduction, and
  `verdictByHeight_noField` and `verdictByHeight_const` prove that when every pass has one height `g` (no field, or a height that never
  changes) the still class is the single group `g` and its verdict is `verdictToday`, which is unchanged and printed beside the groups.
  The TS twins (`reduceClass`, `compareClass`, `compareClasses`, `verdictByHeight`) are replayed on the golden lines `class.*`
  (session) and `cruns`, `cverdict` (stillruns).

Limits (accepted): a height present in only one arm is `not-comparable`, not judged (a base that sat at 815 all pass has no partner in a
lift at 775); `vt` is recorded but not used by the class; the moving class is reported, not judged against the original; the zone
boundaries of `reduceClass` still use the pass's starting height, and `compareClass`'s still-class zone verdict still pools the still
frames of all heights (the still-run verdict above does not). Follow-ups: the zone verdict by height (`reduceClass` and
`compareClass` by height group, with `zoneOf` from the group's height), a `device-cli` subcommand that prints the per-class table
(`device-cli.mjs` is not part of this change), a phone pass to see the classes on a real session, and feeding `verdictByClass` into the
throttle probe report. TS stand-ins: `classes`, `reduceClass`, `compareClasses`, `runsC`, `armOf`, `armAt`, `verdictByHeight`,
`verdictByClass` run in TS, checked against the Lean goldens; they move into `fwcore` with the other reductions.

## Session steps

Before: check what the arms load (`node src/device-cli.mjs plan --search '?fw=<look flags>'` prints the plan and, on stderr, each
dropped arm). The v2-proved preset is resolved at record time; when it resolves to no flags (on main it is `{"fw":{}}`) the v2 arm
loads the same page as the rewrite and Lean's `dedupArms` drops it, so the session has four steps (original, rewrite, look-change,
original) and the user never spends a pass on a duplicate. The same holds for a look-change list equal to v2's or empty. Lean proves
that the first arm is kept, no two kept arms load the same page, and every dropped arm has a kept twin. Every `plan` and `record`
command takes the same `--search` (the look-change flags the lead chose) so that all of them compute the same plan.

The phone is plugged in and unlocked, Light appearance, auto-lock off, no other pass in the last 5 minutes (block <= 15 min,
cool >= 5; each pass is 90 s plus a 6 s countdown: about 9 minutes for five, 7 for four). `sh scripts/sim-lock.sh` is not involved. Output files go to
`.local/phone/<date>/rec-<k>.json`. Run from `packages/measure-webkit` with Node 24; the rewrite is built (`apps/site/dist/aot`).

The banner is drawn on the phone's page; the lead tells the user the same words in the console. Steps below are for the full plan of
five; with the v2 arm dropped, steps 4 and 5 become 3 and 4 and every "of 5" reads "of 4" (the texts come from `plan`).

| step | arm | command (all with `--search '?fw=<look flags>'`) | what the user is told |
|---|---|---|---|
| 1 | original | `node src/device-cli.mjs record --step 1 --target original --out ../../.local/phone/<date>/rec-1.json` | "Step 1 of 5, the original page: swipe top to bottom and back at normal reading speed for 90 s; when it feels laggy, tap 3 times quickly on an empty area (not on text, a link or a button)." |
| 2 | rewrite | `... record --step 2 --target rewrite --site ../../apps/site/dist/aot --out .../rec-2.json` | same, "the faithful rewrite" |
| 3 | rewrite + v2-proved flags (only if the preset is non-empty) | `... record --step 3 --target rewrite --site ../../apps/site/dist/aot --out .../rec-3.json` | same, "the rewrite with the v2-proved flags" |
| 4 | rewrite + look-change flags | `... record --step 4 --target rewrite --site ../../apps/site/dist/aot --out .../rec-4.json`; the lead picks the flags from `packages/contracts/golden/preset/look-change.candidates.jsonl` before the session and puts them in the report | same, "the rewrite with the look-change flags" |
| 5 | original again | `... record --step 5 --target original --out .../rec-5.json` | same, "the original page, again" |

Each command first shows a 6 s countdown banner with the step text, then removes the banner and records 90 s, then shows "DONE". The
lead sends the next step only after the previous command printed its one-line summary (frames, taps, felt marks). A step whose
arm and `--target` disagree, or any command without `--search`, is refused before the phone is touched. If a pass lost frames (summary
`frames` far under 5400), repeat that step alone.

## After the session (no phone)

- `node src/device-cli.mjs reduce --in rec-1.json,rec-2.json,rec-3.json,rec-4.json,rec-5.json` prints the comparison per zone.
- `node src/device-cli.mjs package --kind session --in <all the passes> --date <date> --out ../../results/phone/<date>` writes
  `summary.json` and `summary.md`: reports, comparison and felt marks with position, zone and counts only. No time stamps, no
  per-frame data, no touch points, no device. Commit only that directory.
- Replay the user's finger path in CI (exact positions and timing of the touches; the scroll after each lift-off is Chromium's own
  fling, not iOS momentum, so the replay positions at `feltFrames` are not the phone's: compare zones, not frames): `node src/device-cli.mjs profile --in rec-1.json --id user-<date> --out
  ../measure-chromium/profiles/user-<date>.json` (one profile per pass; taps are dropped, the swipes are replayed one event per
  virtual frame; `input.feltFrames` lists the frames of the marks). Commit it, push `ci/<name>`, then
  `pnpm -s fw run --engines chromium --target both --profile user-<date> --runs 3 --ref ci/<name>`.
  The profile is checked by `parseProfile` (Lean `replayOk`: single finger, two points or more per stroke, inside the viewport,
  strokes in order, at most 12000 frames) before the run; a refused profile names the reason.
- The WebKit lanes have no profile loader (they step the scroll at 50 px), so the replay runs on Chromium only. A WebKit replay
  needs a loader in `scrollrun.mjs`: follow-up.

## Proof on the synthetic session

`session.jsonl` ends with a Lean-built session (480 frames, 5 strokes, 2 triple taps). `test/device-record.test.mjs` checks:
record -> TS reductions equal Lean's report -> replay strokes -> exported profile equals the committed
`packages/measure-chromium/profiles/user-fixture.json` and loads in `parseProfile` -> package without timestamps or device. The
page recorder runs against a stubbed page (passive listeners, no `preventDefault`, one clock for frames and touches).
