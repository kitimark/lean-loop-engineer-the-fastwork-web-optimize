# Phone push with the veil restored: p95 tail of the two flip arms and its cause (16 of 18 visits)

Question: with the veil layer back in the flip look (main at ca812241f), what are the worst frame, p95 and over-50 ms count of the base, `morph.geom:on`
and `morph.geom:on,morph.tween:geom-timed` on the real iPhone, and which kind of work (style, layout, paint, script, commit, idle main thread =
compositor/GPU) owns each over-50 ms frame and the p95 tail of the flip arms? Same phone (WebKit), same fixed XCUITest push pattern as
`research/notes/2026/10-2x-phone-morph-push-r2.md`, end segment, one induced thermal state (Serious), raw per-frame timelines kept.
Every number below is in `results/phone/2026-10-28-flip-p95/{summary.json,attribution.json,tables.md}` (raw lanes in `.local/phone/2026-10-28-flip/`,
gitignored). The session ran 2026-10-27 18:58 to 20:26 UTC.

## What changed (CONFIRMED in code)
- Order rule, Lean `lean/Fw/Device/PhoneArms.lean` section "flip session": `flipIdx` (six rows of a Williams square over the three arms), 18 visits,
  6 per arm, each arm once per round and once per position pair; proved by `decide`. Golden kind `flipcons` and the order/slot keys in
  `packages/contracts/golden/device/phone-arms.jsonl`; TS twin `device-push.mjs` (`FLIP_ARMS`, `flipOrder`, `flipSlotOf`, `flipOk`).
- Attribution rule, Lean `lean/Fw/Device/FlipAttr.lean`: `workOf` maps a Timeline record to script, style, layout, paint or commit; the innermost record
  owns a slice of the frame (`cuts`, `innerIdx`, `workTime`); `busy` is the summed work; `dominant` is idle when busy x 2 is under the interval and
  otherwise the work with most time (ties go to the earliest of script, style, layout, paint, commit); `lead` is the longest record of the dominant work;
  `tailOf` selects frames at or over the visit p95. Theorems on frame cuts and ties by `decide`. TS twin `device-flip-attr.mjs`, checked against the
  golden vectors in `device-flip-attr.test.mjs`.
- Third lane per visit: `tl` (Timeline on plus `document.getAnimations()` snapshot at the start of the pushes), written as `*.tl.json`
  (`device-push-run.mjs` `tlLane`, `ANIM_SNAPSHOT_JS`; `device-phone-run.mjs`). The frames lane and the counts lane are the r2 lanes.
- Report: `device-flip-report.mjs` (`flipAttribution`, `flipTables`), called from `device-push-cli.mjs reduce --set flip`.

## Result (MEASURED, 2026-10-27/28)
16 of 18 visits: base 6, geom 5, geom-timed 5 (visits 0 to 15). Visit 16 (geom-timed) was refused at the visit end (phone Critical and locked) and the
session stopped; visit 17 (geom) never ran. Visit 1 needed two attempts (an orphan driver of my own killed debug run answered the pushes; found by
process age, stopped); visits 5 and 11 were also rerun (heat reading Critical at the visit end; recorder not started with the phone Critical). 61
readings on the kept visits were all Serious with the Lean gate saying go (7 block starts, 38 between lanes, 16 visit ends).
Cells are the median [min-max] over the visits of the arm; intervals in ms; counts are Timeline records between each push and its morph end, summed
over the 10 pushes of a visit. Label = Lean `pushLabel` against the base.

| arm | n | p95 | p99 | max | frames over 50 ms | style | layout | paint | rAF | label |
|---|---|---|---|---|---|---|---|---|---|---|
| base | 6 | 58 [57-85] | 72 [68-106] | 92 [82-198] | 52 [42-57] | 1237 [983-1308] | 1047 [844-1096] | 12613 [8994-13251] | 262 [186-292] | base |
| morph.geom:on | 5 | 62 [56-65] | 92 [90-96] | 109 [103-138] | 36 [26-38] | 834 [810-884] | 565 [553-607] | 3210 [3151-3229] | 275 [272-312] | better |
| geom + geom-timed | 5 | 69 [68-98] | 108 [107-137] | 134 [114-160] | 53 [52-74] | 1102 [966-1160] | 868 [752-894] | 4566 [4172-4680] | 94 [58-136] | better |

Lean cell verdicts against the base:

| arm | p95 | p99 | max | over 50 ms | style | layout | paint | rAF |
|---|---|---|---|---|---|---|---|---|
| morph.geom:on | same | same | same | same | same | same | beats | same |
| geom + geom-timed | same | same | same | same | same | same | beats | same |

- The two flip arms are `better` only through the paint count (3210 and 4566 against 12613, ranges far apart). Every frame-time cell is `same`:
  the p95 of the flip arms (62, 69) is above the base median (58), but the base has one slow visit (visit 0: p95 85, max 198) that makes its spread
  28 ms wide, so the rule cannot call the 4 and 11 ms gaps. Undecided within the base spread, not equal.
- Over 50 ms per 100 intervals, all visits of an arm pooled (frames lane): base 9.0 (296 of 3294), geom 10.2 (164 of 1601), geom-timed 12.1 (291 of
  2414). Worst interval: 198, 138, 160 ms. Geom spans are shorter (median 783 ms against 1476 and 1512), so it has fewer intervals.
- The per-100 rate, not the per-visit count, is the fair comparison: geom has fewer long frames per visit (36 against 52) because it has fewer frames.

## Which work owns the long frames (MEASURED, tl lane)
The tl lane runs with the Timeline on, which inflates it against the frames lane (median p95 73, 77, 81 ms against 58, 62, 69; over 50 ms per visit
72, 69, 81 against 52, 36, 53). Attribution below is for a Timeline-loaded run; the shares, not the counts, are what carries over. Frames are the
intervals between the rAF times of the push spans; the Lean rule decides each one.

| arm | intervals | over 50 ms | script | style | layout | paint | commit | idle | busy share of over-50 time |
|---|---|---|---|---|---|---|---|---|---|
| base | 2706 | 424 | 0 | 1 | 0 | 0 | 422 (100%) | 1 | 83% |
| morph.geom:on | 1354 | 311 | 2 (1%) | 214 (69%) | 0 | 0 | 93 (30%) | 2 | 86% |
| geom + geom-timed | 2312 | 396 | 2 (1%) | 355 (90%) | 0 | 0 | 39 (10%) | 0 | 87% |

p95 tail (frames at or over the visit p95): base 149 frames, all commit; geom 76 frames, style 37 and commit 38 and script 1; geom-timed 125 frames,
style 123 and commit 2.

- Idle main thread (compositor/GPU) owns 3 of 1131 over-50 ms frames. The long frames are main-thread busy time, not waiting for the GPU.
- Layout and paint own none: paint records are many (base 91 per long frame) but short; the commit slice (record `Composite`, 48 ms per long frame in
  the base) or the style slice (`RecalculateStyles`, 36 and 45 ms per long frame in the flip arms) is larger.
- Base: the cost is the Composite record, that is the commit of the paint tree. It carries no element in the Timeline data.
- Flip arms: the cost moves to `RecalculateStyles` and the commit part shrinks (composite 19 and 26 ms per long frame against 48). The record has no
  element either. The worst frames are geom 159 ms (Composite, visit 10), geom-timed 211 ms (RecalculateStyles, visit 14), base 184 ms (Composite,
  visit 0). Script leads are three positions in the minified `entry-client` bundle (one `FunctionCall`, 130 ms in geom visit 8).
- When: base 423 of 424 long frames fall in the first second after the touch start; geom 305 in 0-1 s plus 6 in 1-1.5 s; geom-timed 396 in 0-1 s.
- What runs then: the animation snapshot is the same in the three arms: the sweep `backgroundPosition` and the accent `opacity` animations running
  (3 each), the morph tracks `morph-module_up` and `down` (transform, paused), the deck `profileFade` (paused), about 25 finished entry
  animations. Mean records per long frame against other frames: transition events 6.7 against 1.8 (base), 3.7 against 0.4 (geom), 4.6 against 0.7
  (geom-timed); animation events 0.6 against 0.3, 1.9 against 0.3, 1.8 against 0.4.
- Paint clips of the long frames sit in the visuals section (36 to 38% in the `visuals-module_secureNetworkRingsIn` box; invoice row and card, shield
  next) in all three arms, 26 to 28% in no animated box. In other frames the sweep box and the dash+rings box lead in the flip arms.
- INFERRED: the style cost of the flip arms comes with the transitions and animations that start when the morph opens (the style recalculation that
  starts them), at the same place as the base's commit cost. The Timeline names no element for `RecalculateStyles` or `Composite`, so the element
  cannot be named from this data; the paint clip owners above are the nearest evidence, and they are the same boxes in the three arms.

## Veil cost against r2 (INFERRED)
r2 (`research/notes/2026/10-2x-phone-morph-push-r2.md`) ran the flip look without the veil (p95 base 69, geom 58, geom-timed 78; over 50 ms 55, 67, 65;
paint 10398, 8425, 9324; style 962, 1912, 1094). More than the veil differs (another session, another heat history, four arms in r2), so the comparison is INFERRED.
- The base itself moved between sessions: p95 69 to 58, paint 10.4k to 12.6k, max 556 to 92. Session drift is larger than any arm gap here.
- Flip arms with the veil: paint 3210 (geom) and 4566 (timed), down 62% and 51% against r2, while the base paint rose 21%. Style fell for geom (1912 to
  834). The veil takes the picture work out of the morph.
- Frame times: geom p95 58 to 62 (+4 ms) while the base fell 11 ms; relative to its own base the geom p95 went from -11 to +4 ms. Timed 78 to 69
  (base 69 to 58; relative to its own base +9 to +11 ms). All p95 cells are `same` by the rule, so the veil's p95 cost is not resolved: at most a few ms, inside
  the base spread.

## Position check (MEASURED)
Median over the arms by position in a round: p95 68 [59-98] (position 0), 62 [57-71] (1), 58 [56-69] (2); over 50 ms 53, 42, 53. By round the p95
medians are 68, 61, 58, 65, 64, 59. The first round is higher mainly because base visit 0 (p95 85, max 198) and the first timed visit (68) sit there;
base visits 1 to 5 read 57 to 59. Position 0 holds the first visit of the session, so a warm-up effect and the arm's own cost are not separable (INFERRED).

## Heat (MEASURED)
The pin held Serious in all 61 readings of the kept visits. The phone's own heat reached Critical at the visit end of visits 5 and 16 and while
visit 11 ran its counts lane; those visits were refused or rerun in the next launch (5 launches for 16 visits). Visit 16 ended the session with the
phone locked and Critical, and the clear of the Serious pin could not be confirmed (the DTX channel was closed with the phone locked). INFERRED:
the heat history differs by launch, so a late visit has run in a different state from an early one; the Williams order spreads this across arms but
cannot remove it with n = 5 to 6.

## Limits
- One session, 16 of 18 visits (base 6, geom 5, geom-timed 5); the design is incomplete by visits 16 and 17.
- The push is a fixed XCUITest swipe, not the user's finger. One induced thermal state (Serious); real heat above it is not visible during the pin.
- The tl lane has the Timeline on and is slower than the frames lane; attribution is for that load. Dominance by the innermost record is a rule, not a
  profile of the engine; `RecalculateStyles` and `Composite` carry no element.
- Picture scaling is base-unlike (the object-fit image model is not in the flip look), so paint and commit work is not comparable one to one.
- The look is not judged here; Class L arms stay the user's visual review. Veil cost is INFERRED (another session than r2).
- Stand-ins in TS, not Lean: the Timeline-to-records glue (`recsOf`, `framesOfVisit`, `attributeVisit`), the animation-snapshot owner mapping, the
  report grouping and the `positionCheck` reducer; "busy is at most the interval" is a guard test, not a theorem.
