# Phone morph push at the end of the page, rerun in a Latin-square order (n = 4 per arm)

Question: with every arm taking every position in a round once, do the verdicts of `phone-morph-push` (research/notes/2026/10-2x-phone-morph-push.md)
hold? Review follow-up from that note: the stage arm was always 4th in a round, and the phone's own heat reached Critical under the Serious pin.
Same real iPhone (WebKit), same fixed XCUITest push pattern, end segment, one induced thermal state (Serious). Every number below is in
`results/phone/2026-10-27-morph-push-r2/{summary.json,tables.md}` (raw lanes in `.local/phone/2026-10-27-r2/`, gitignored).

## What changed (CONFIRMED in code)
- Order rule, Lean `lean/Fw/Device/PhoneArms.lean:1091-1124` (`latinIdx`, `latinRows`, `latinOrder`): four rounds, each a row of a Williams square
  over base, morph.geom:on, geom + morph.tween:geom-timed, morph.stage:on. Proved with `decide`: each round holds each arm once
  (`latin_rows_once`), each arm takes each position once (`latin_cols_once`), every ordered pair of distinct arms follows each other once
  inside a round (`latin_carry`), 4 visits per arm (`latin_ok`), no arm twice in a row across round borders (`latin_noRepeat`), base once per
  round (`latin_base_each`), visit i sits in round i/4 at position i%4 (`latin_index`). Golden keys `latin`, `order`, `slots` in
  `packages/contracts/golden/device/phone-arms.jsonl`; the TS twin `device-push.mjs` (`latinOrder`, `slotOf`) reads them.
- Stage recorder: morph.stage writes `data-fw-morph` on the nav (`apps/site/src/parts/morph.stage/index.tsx:69`; Lean op list
  `lean/Fw/Parts/MorphStage.lean:331`). `FRAMES_START_JS` now reads it when the inline `--morph` is empty
  (`packages/measure-webkit/src/device-push-run.mjs:39`), so the stage span ends at its morph end.
- Thermal: `pin.before` (read just before the pin) and `pin.after` (last read-back after the clear) in `summary.json`
  (`device-phone-pin.mjs:26`); each visit carries `round` and `position`; `positions` holds the position and round check.

## Result (MEASURED, 2026-10-27)
16 visits, 4 per arm, all first attempt, none lost. Pin: before Nominal (10:10:05 UTC), 36 readings (4 block starts, 16 between lanes, 16 visit ends)
all Serious with the Lean gate saying go. Cells are median [min-max] over the 4 visits; frame intervals in ms; counts are Timeline records
between each push and its morph end, summed over the 10 pushes of a visit. Label = Lean `pushLabel` against the base.

| arm | n | p95 | p99 | max | frames over 50 ms | style | layout | paint | rAF | label |
|---|---|---|---|---|---|---|---|---|---|---|
| base | 4 | 69 [64-75] | 103 [86-106] | 556 [279-597] | 55 [44-59] | 962 [909-1081] | 833 [796-945] | 10398 [9252-11581] | 174 [165-201] | base |
| morph.geom:on | 4 | 58 [52-66] | 77 [72-93] | 103 [98-130] | 67 [56-164] | 1912 [1296-1920] | 1287 [939-1290] | 8425 [5376-8506] | 247 [178-248] | worse |
| geom + geom-timed | 4 | 78 [72-80] | 117 [102-136] | 145 [133-158] | 65 [54-70] | 1094 [1049-1159] | 877 [850-918] | 9324 [8917-9464] | 170 [151-192] | same |
| morph.stage:on | 4 | 90 [82-109] | 127 [106-153] | 690 [281-854] | 184 [165-204] | 2465 [2448-2540] | 1664 [1651-1712] | 22592 [20590-22686] | 356 [327-361] | worse |

Lean `pushLabel` cell verdicts against the base (a cell is `worse`, `same` or `beats`; an arm is `worse` when a cell is worse and none beats):

| arm | p95 | p99 | max | over 50 ms | style | layout | paint | rAF |
|---|---|---|---|---|---|---|---|---|
| morph.geom:on | same | same | same | same | worse | same | same | same |
| geom + geom-timed | same | same | same | same | same | same | same | same |
| morph.stage:on | same | same | same | worse | worse | worse | worse | worse |

- morph.stage:on: worse again, now with its morph read (maxMorph 946-1000 per mille in its 4 visits). Frames over 50 ms 184 vs 55, every count column
  2.0-2.6x the base (style 2.6x, paint 2.2x, layout 2.0x, rAF 2.0x). p95 90 vs 69 ms (ranges 82-109 vs 64-75), but the rule calls that cell same.
  Its counts moved 1-5% against the round-1 medians (style 2435 to 2465, paint 21597 to 22592), so reading the morph did not change them much.
- morph.geom:on: worse by the rule only through the style count (1912 vs 962). p95, p99 and max medians are lower than the base (58/77/103 vs 69/103/556);
  the rule calls those cells same. Visit 15 (round 3, position 3) is unlike its three siblings: over50 164 (others 56-67), paint 5376 (others 8197-8506),
  style 1296 (others 1850-1920); the summary does not show why.
- geom + geom-timed: same on all eight cells. Round 1 called it better (3 visits, fixed order); with n = 4 and the Latin order its max
  (145 vs 556) is lower but the rule needs a cell that beats, and none does. The round-1 verdict does not reproduce.
- Base max has a wide range (279-597 ms); morph.geom:on and geom + geom-timed stay at 98-158 ms, stage at 281-854.

## Position check (MEASURED)
Each position holds one visit of every arm, so the median over its four visits is arm-balanced. Median (upper of four) [min-max]:

| position | p95 | p99 | max | over 50 ms | style | paint |
|---|---|---|---|---|---|---|
| 0 | 78 [54-90] | 117 [77-136] | 597 [102-690] | 70 [47-184] | 1912 [1067-2448] | 11581 [8506-20590] |
| 1 | 75 [52-82] | 106 [72-109] | 556 [98-854] | 59 [55-173] | 1920 [962-2540] | 10398 [8425-22686] |
| 2 | 80 [58-85] | 117 [76-127] | 340 [103-382] | 67 [44-165] | 1850 [933-2465] | 9621 [8197-22592] |
| 3 | 75 [66-109] | 103 [93-153] | 279 [130-281] | 164 [59-204] | 1296 [909-2450] | 9324 [5376-21171] |

By round (the time axis) the p95 medians are 75, 72, 78, 80 ms and p99 102, 109, 106, 117 ms (`positions.byRound`); over 50 ms is 65, 65, 70, 164.
- p95 and p99 rise a little over the rounds (75 to 80, 102 to 117) with all ranges overlapping: weak, not a drift the data can size.
- The round 3 over50 median of 164 comes from two visits, stage (184) and the last geom visit (164); with one visit per arm and round, heat in the
  last round and that visit cannot be told apart in this data (INFERRED).
- Positions show no systematic order effect on p95 (75-80); position 3 differs on max, over50, style and paint because which arm sits there sets its median.

## Heat (MEASURED)
Before the pin the phone read Nominal. The pin held Serious in all 36 readings, so the phone's own heat is not visible during the run. After our
condition owner stopped and the clear was confirmed, all 25 read-backs over about 5 minutes (10:51:52 to 10:56:47 UTC) read Critical, end `heatRemains`.
From the first reading to the first read-back after the clear took about 42 minutes. INFERRED: the phone's own heat built up during the run; the
Serious pin applies the same condition to every arm and the Latin order spreads the remaining heat across arms.

## Limits
- The push is a fixed XCUITest swipe, not the user's finger path. One induced thermal state (Serious); real heat above it is not visible during the pin.
- n = 4 per arm: ranges for p95 and p99 overlap between arms, so only the count columns and (for stage) over 50 ms separate them under the rule.
- Class L arms (geom-timed, stage) stay the user's visual review and the felt smoothness is the user's; no CI pushes in this task.
- The position medians are an upper median of 4 values and a TS reducer (`positionCheck`), not Lean; the Lean-proved parts are the order, the slot of each visit
  and `pushLabel`.
