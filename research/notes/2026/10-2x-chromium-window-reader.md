# Chromium push-window reader: does the committed reader reproduce the platform-attribution Chromium table?

Tags: MEASURED (CI run id named), CONFIRMED (Lean theorem or source cited), INFERRED (reasoned, not seen).

## Answer

Yes. The committed reader gives the same verdict as `10-2x-platform-attribution.md` in all 24 cells (6 windows x 4 flag
arms), MEASURED on the five existing runs (no new CI run). 18 cells list the same counters with the same numbers. The
other 6 cells differ only in which counters are listed, never in a verdict. The note needs no change for a verdict; the
lead decides whether to fix the listed counters (follow-up below).

| arm | run |
|---|---|
| base | 40203753344 |
| sweep | 40237508223 |
| glint | 40236516819 |
| entries | 40236472868 |
| marquee | 40236462082 |

Each arm is the three artifacts `chromium-counts-rewrite-r1..r3` (profile `swipe-touch-v1`, one end frame 574 in all 15
runs, 771 frames, last frame 741).

## The reader

The original scratch reader was lost, so the window bounds were rebuilt from the note and then checked against it
(CONFIRMED by the 24 verdicts above). With `e` the end frame (first frame at the largest `scrollY`) and `last` = total
frames minus the profile tail (30):

| window | frames |
|---|---|
| approach | e-34 to e |
| end 0-19 | e to e+20 |
| end 20-59 | e+20 to e+60 |
| end 60-119 | e+60 to e+120 |
| end 120+ | e+120 to last |
| finish | e-34 to last |

Cut positions are clipped to `last`. A window's counter is the sum of the counter over its frames. The verdict per window
is the existing `Offscreen` judge: counters are compared as spreads over the 3 runs (slack 0), `gain` needs a `less` and
no `more`, fewer than 3 runs per arm or windows of different length give `noData`.

CLI (reads `gh run download` directories at any depth):

```
node packages/measure-chromium/src/offscreen-windows-cli.mjs --base <dir> --flag sweep=<dir> --flag glint=<dir> [--json f] [--md f]
```

Exit code 2 names the failure: another profile than `swipe-touch-v1`, a tail that differs from 30, a counter in no frame.

Reading `less` and `more`: `less` prints "base min to flag max" (the smallest gap), `more` prints "base max to flag min".
A counter absent from a frame counts 0 in that frame; a counter absent from every frame is an error.

## Table the CLI prints (MEASURED, the five runs above)

| window | sweep | glint | entries | marquee |
|---|---|---|---|---|
| approach | gain; less RasterTask 236 to 61, PaintImage 137 to 1 | gain; less RecalcStyleCount 129 to 120, LayoutCount 6 to 5, RasterTask 236 to 200 | noGain; less RecalcStyleCount 129 to 121, LayoutCount 6 to 1, Paint 114 to 102, RasterTask 236 to 211, PaintImage 137 to 136; more FireAnimationFrame 120 to 122 | noGain |
| end 0-19 | noGain; less RasterTask 517 to 477, PaintImage 495 to 427; more Paint 335 to 352 | gain; less RasterTask 517 to 515 | gain; less Paint 335 to 330, RasterTask 517 to 512 | noGain |
| end 20-59 | noGain; less PaintImage 454 to 294; more Paint 252 to 292 | noGain | noGain | noGain |
| end 60-119 | noGain; less PaintImage 240 to 0; more Paint 120 to 180 | noGain | noGain | noGain |
| end 120+ | noGain; less PaintImage 188 to 0; more Paint 94 to 141 | noGain | noGain | noGain |
| finish | noGain; less RasterTask 1207 to 992, PaintImage 1514 to 722; more Paint 915 to 1079 | gain; less RecalcStyleCount 319 to 310, LayoutCount 52 to 51, RasterTask 1207 to 1169 | noGain; less RecalcStyleCount 319 to 311, LayoutCount 52 to 47, Paint 915 to 898, RasterTask 1207 to 1177, PaintImage 1514 to 1513; more FireAnimationFrame 400 to 402 | noGain; more RecalcStyleCount 319 to 320 |

## Cell by cell against the note

Verdict: 24 of 24 equal. Counters: 18 of 24 equal. The 6 cells that list different counters, none changes a verdict:

| cell | note lists | reader lists | reason |
|---|---|---|---|
| approach / entries | LayoutCount, RasterTask, FireAnimationFrame | also RecalcStyleCount 129 to 121, Paint 114 to 102, PaintImage 137 to 136 | note omitted small cuts (INFERRED) |
| end 0-19 / sweep | RasterTask, Paint | also PaintImage 495 to 427 | note omission |
| end 20-59 / sweep | Paint | also PaintImage 454 to 294 | note omission |
| end 120+ / sweep | (merged into "end 60+") | PaintImage 188 to 0, Paint 94 to 141 | the note has one "end 60+" cell; the reader splits it into 60-119 and 120+, both `noGain` |
| finish / glint | RasterTask, RecalcStyleCount | also LayoutCount 52 to 51 | note omission |
| finish / entries | RecalcStyleCount 319 to 310, LayoutCount, FireAnimationFrame | RecalcStyleCount 319 to 311, also Paint, RasterTask, PaintImage | the note printed the flag minimum (310), the reader prints the flag maximum (311) for `less`; the others are omissions |

## Spread of the 3 runs

Of 180 arm x window x counter cells, 23 have a spread above 0, always 1 (FireAnimationFrame, RecalcStyleCount, Paint).
Every other cell is the same number in all 3 runs, so slack 0 is not what decides the verdicts. The window has the same
frame count in every run (34 / 20 / 40 / 60 / 47 / 201).

## What is proved in Lean and what is not

`lean/Fw/Measure/OffscreenWindows.lean`, golden `packages/contracts/golden/measure/offscreen-windows.jsonl` (generated
by `OffscreenWindowsGolden`, 26 lines, checked in `lean/scripts/check.sh`, trigger row in `Fw/Ci/Trigger.lean`).

- End frame: `endFrame_nil`, `endFrame_isSome`, `endFrame_spec`, `endFrame_eq`.
- Windows: `pushWindows_length`, `pushWindows_abut`, `pushWindows_span`, `pushWindows_ordered`, `finishWin_ordered`,
  `pushWindows_lens`, `finishWin_len`, `pushWindows_unique`, `pushWindows_outside`. The push windows partition the
  finish window.
- Sums: `sumRange_add`, `sumRange_len`, `pushWindows_sum` (the window sums add up to the finish sum), `sumVec_get`,
  `sumVec_n`, `Run.windows_end`, `Run.windows_names`.
- Verdict: `verdictOn_keys` and `usableOn_keys` (the six keys give exactly `Offscreen.verdict`), `verdictOn_of_usable`,
  `usableOn_of_verdict`, `noData_of_fewBase`, `noData_of_fewFlag`, `noData_of_window`, `noData_of_missing`,
  `noGain_of_more`, `gain_sound`, `cell_cmp`, `armVerdicts_names`, `armVerdicts_get`.

The JS twin `packages/measure-chromium/src/offscreen-windows.mjs` copies these functions and is replayed against the
golden by `test/offscreen-windows.test.mjs` (imported from `test/offscreen.test.mjs`).

TS stand-ins (glue, no decision logic): reading `counts.json` (`runFromCounts`, `findCounts`, `readArm`), the profile
tail (`profileTail`), the table text (`cellText`, `summarizeArm`, `markdown`) and the CLI. The tail value is checked
against the Lean constant 30 in the CLI and the test.

## Limits

- `swipe-touch-v1` only; other profiles are refused.
- WebKit VM counting is the separate task `offscreen-vm-count`.
- The bounds are rebuilt, not recovered: the 24 matching verdicts support them, but a window cut by one frame could still
  match the verdicts and change a sum. The counters that match to the digit (18 cells) bound this.
