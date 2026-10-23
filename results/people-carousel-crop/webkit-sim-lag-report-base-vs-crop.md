### Inputs

- original: 2 sessions, 3 scroll passes, 3 morph passes; viewport 430x775, maxY 5231; stopped early: session 2: pass 2 scroll: Runtime.evaluate timed out after 120000 ms
- faithful: 3 sessions, 6 scroll passes, 6 morph passes; viewport 430x775, maxY 5231

Ratio = counter per frame in the region over counter per frame in the baseline (unit-free; Lean `ratio_scale`). The range is over passes (each pass against its own baseline). "Difference" is stated only when every pass of one arm is on one side of every pass of the other (Lean `verdict`).

### Region A (scroll), ratio to the calm scroll baseline

original: 16.0 steps per pass in the region, 43.3 calm steps per pass; faithful: 16.0 steps per pass in the region, 43.5 calm steps per pass. Per-step values.

| counter | per step original / faithful | baseline original / faithful | ratio original (per-pass range) | rank original | ratio faithful (per-pass range) | rank faithful | difference of the ratio | difference of the per step value |
|---|---|---|---|---|---|---|---|---|
| TimerInstall | 0.54 / 0.54 | 0.21 / 0.15 | 2.61 (2.20-3.14) (*) | 1 | 3.72 (2.75-6.88) (*) | 1 | not stated (rare baseline) | no difference shown (ranges overlap) |
| Paint (us) | 5,182 / 5,042 | 2,447 / 1,768 | 2.12 (1.58-4.46) | 2 | 2.85 (2.26-4.08) | 2 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Paint | 19.4 / 19.6 | 9.54 / 9.61 | 2.04 (2.00-2.09) | 3 | 2.04 (1.96-2.12) | 4 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| ObserverCallback | 0.88 / 0.88 | 0.50 / 0.49 | 1.75 (1.71-1.79) | 4 | 1.77 (1.71-1.83) | 6 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| InvalidateLayout | 7.25 / 6.77 | 4.29 / 4.24 | 1.69 (1.64-1.74) | 5 | 1.60 (1.24-1.88) | 9 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Composite (us) | 87,374 / 75,736 | 58,245 / 45,614 | 1.50 (1.30-2.33) | 6 | 1.66 (1.20-2.83) | 8 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| RecalculateStyles (us) | 16,019 / 21,113 | 11,225 / 11,005 | 1.43 (1.24-1.70) | 7 | 1.92 (1.65-2.56) | 5 | no difference shown (ranges overlap) | faithful higher |
| EventDispatch | 15.9 / 16.6 | 12.2 / 11.4 | 1.30 (1.26-1.34) | 8 | 1.45 (1.25-1.66) | 10 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| paintArea (px^2) | 919,729 / 936,700 | 735,974 / 757,491 | 1.25 (1.17-1.32) | 9 | 1.24 (1.18-1.27) | 14 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| FunctionCall | 21.2 / 21.9 | 17.1 / 16.3 | 1.24 (1.21-1.27) | 10 | 1.35 (1.23-1.49) | 13 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Layout | 7.42 / 7.23 | 6.02 / 5.94 | 1.23 (1.21-1.26) | 11 | 1.22 (1.15-1.30) | 15 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| TimerFire | 0.54 / 0.56 | 0.47 / 0.34 | 1.15 (0.97-1.32) | 12 | 1.67 (1.12-3.30) | 7 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| ScheduleStyleRecalculation | 7.06 / 6.96 | 6.26 / 6.21 | 1.13 (1.11-1.15) | 13 | 1.12 (1.07-1.17) | 16 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Layout (us) | 4,376 / 5,719 | 3,904 / 2,759 | 1.12 (0.95-1.73) | 14 | 2.07 (1.38-3.71) | 3 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| RecalculateStyles | 7.13 / 7.06 | 6.39 / 6.33 | 1.11 (1.10-1.13) | 15 | 1.12 (1.07-1.15) | 17 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| TimerRemove | 0.29 / 0.29 | 0.28 / 0.21 | 1.05 (0.90-1.27) (*) | 16 | 1.38 (1.01-2.36) (*) | 12 | not stated (rare baseline) | no difference shown (ranges overlap) |
| FunctionCall (us) | 18,801 / 21,861 | 18,384 / 15,749 | 1.02 (0.78-1.26) | 17 | 1.39 (1.19-1.78) | 11 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| FireAnimationFrame | 6.69 / 6.69 | 6.77 / 6.77 | 0.99 (0.99) | 18 | 0.99 (0.99) | 18 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Composite | 1.94 / 1.94 | 2.00 / 2.00 | 0.97 (0.97) | 19 | 0.97 (0.97) | 19 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| RequestAnimationFrame | 6.88 / 6.88 | 7.10 / 7.10 | 0.97 (0.97) | 20 | 0.97 (0.97) | 20 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| RenderingFrame | 0.00 / 0.00 | 0.00 / 0.00 | no baseline | - | no baseline | - | - | no difference shown (ranges overlap) |

The ratio compares a window with the same arm's calm baseline, so an arm difference of the ratio can come from the baseline; the last column decides on the per-pass value itself. (*) the baseline of that arm has fewer than 10 events of the counter in at least one pass (Lean rareBase, event counts only), so its ratio and rank are unstable and no difference of the ratio is stated for the row. Duration columns (us) are Simulator-host microseconds summed over the records of the type; records nest (a Layout inside a FunctionCall), so durations are not additive across types.

Counters with no calm baseline (not ranked): original RenderingFrame; faithful RenderingFrame.

Paint area by part (css px^2 per pass; coarse part names, leaf parts below). The two arms have different part tables (the original a selector table, the rewrite its data-fw elements): a part in one table only is not compared, and the share of a part in both tables can move to a part of the other, so read neighbouring parts together.

| part | original px^2 per pass (range) | share original | faithful px^2 per pass (range) | share faithful | difference |
|---|---|---|---|---|---|
| pain | 4,622,738 (4,539,530-4,775,554) | 31% | 4,605,787 (4,404,653-4,778,559) | 31% | no difference shown (ranges overlap) |
| (none) | 4,016,916 (3,816,250-4,121,216) | 27% | 4,014,347 (3,816,250-4,172,609) | 27% | no difference shown (ranges overlap) |
| hero | 3,493,528 (3,482,788-3,500,442) | 24% | 3,557,386 (3,362,650-4,064,897) | 24% | no difference shown (ranges overlap) |
| people | 2,080,739 (1,794,272-2,401,549) | 14% | 2,318,908 (2,041,341-2,732,031) | 15% | no difference shown (ranges overlap) |
| nav | 531,973 (519,378-545,162) | 4% | 524,229 (512,122-537,606) | 3% | no difference shown (ranges overlap) |

- original, leaf parts: pain-notes 4,622,738 (31%), (none) 4,016,916 (27%), hero 2,520,888 (17%), people 1,554,017 (11%), hero-deck 739,570 (5%), people-deck 511,712 (3%), nav 472,897 (3%), hero-accent 101,632 (1%)
- faithful, leaf parts: pain-notes 4,605,787 (31%), (none) 4,014,347 (27%), hero 2,600,368 (17%), people 1,750,325 (12%), hero-deck 776,418 (5%), people-deck 547,408 (4%), nav 464,139 (3%), hero-exit 84,913 (1%)

Top 5 steps of Region A, original (by paint area, all passes pooled):

| rank | pass | y or frame | Paint | paintArea px^2 | Layout | RecalculateStyles | owning part |
|---|---|---|---|---|---|---|---|
| 1 | s1p2 | 50 | 67 | 3,568,074 | 12 | 7 | (none) |
| 2 | s1p2 | 650 | 30 | 3,344,251 | 7 | 8 | (none) |
| 3 | s1p1 | 650 | 30 | 3,342,201 | 8 | 8 | (none) |
| 4 | s2p1 | 650 | 30 | 3,342,201 | 8 | 8 | (none) |
| 5 | s1p1 | 50 | 65 | 3,296,994 | 12 | 7 | (none) |

Top 5 steps of Region A, faithful (by paint area, all passes pooled):

| rank | pass | y or frame | Paint | paintArea px^2 | Layout | RecalculateStyles | owning part |
|---|---|---|---|---|---|---|---|
| 1 | s2p2 | 50 | 61 | 3,556,425 | 12 | 7 | (none) |
| 2 | s1p2 | 50 | 65 | 3,531,364 | 12 | 7 | (none) |
| 3 | s3p2 | 50 | 58 | 3,515,754 | 12 | 7 | (none) |
| 4 | s3p2 | 650 | 30 | 3,401,451 | 8 | 8 | (none) |
| 5 | s1p1 | 650 | 30 | 3,348,351 | 8 | 8 | (none) |

### Region B (scroll), ratio to the calm scroll baseline

original: 16.3 steps per pass in the region, 43.3 calm steps per pass; faithful: 16.5 steps per pass in the region, 43.5 calm steps per pass. Per-step values.

| counter | per step original / faithful | baseline original / faithful | ratio original (per-pass range) | rank original | ratio faithful (per-pass range) | rank faithful | difference of the ratio | difference of the per step value |
|---|---|---|---|---|---|---|---|---|
| Paint (us) | 6,295 / 2,939 | 2,447 / 1,768 | 2.57 (1.56-2.87) | 1 | 1.66 (1.33-2.04) | 4 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| ObserverCallback | 0.86 / 0.85 | 0.50 / 0.49 | 1.71 (1.65-1.79) | 2 | 1.72 (1.65-1.79) | 3 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Composite (us) | 98,971 / 81,898 | 58,245 / 45,614 | 1.70 (1.25-1.94) | 3 | 1.80 (1.34-3.16) | 2 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Paint | 13.0 / 12.5 | 9.54 / 9.61 | 1.36 (1.10-1.50) | 4 | 1.30 (1.14-1.43) | 5 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| InvalidateLayout | 5.51 / 4.92 | 4.29 / 4.24 | 1.28 (0.73-1.69) | 5 | 1.16 (0.85-1.41) | 6 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| FunctionCall (us) | 21,044 / 15,945 | 18,384 / 15,749 | 1.14 (0.80-1.27) | 6 | 1.01 (0.69-2.40) | 7 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| RecalculateStyles (us) | 12,052 / 8,631 | 11,225 / 11,005 | 1.07 (0.80-1.21) | 7 | 0.78 (0.69-0.96) | 13 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Composite | 2.00 / 2.00 | 2.00 / 2.00 | 1.00 (1.00) | 8 | 1.00 (1.00) | 8 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| EventDispatch | 12.1 / 10.7 | 12.2 / 11.4 | 0.99 (0.82-1.08) | 9 | 0.93 (0.83-1.04) | 9 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| FunctionCall | 16.0 / 14.7 | 17.1 / 16.3 | 0.94 (0.84-1.00) | 10 | 0.90 (0.85-0.98) | 10 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Layout | 5.41 / 5.04 | 6.02 / 5.94 | 0.90 (0.63-1.10) | 11 | 0.85 (0.72-0.97) | 11 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| RecalculateStyles | 5.49 / 5.27 | 6.39 / 6.33 | 0.86 (0.73-0.94) | 12 | 0.83 (0.72-0.89) | 12 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| ScheduleStyleRecalculation | 4.65 / 4.64 | 6.26 / 6.21 | 0.74 (0.73-0.76) | 13 | 0.75 (0.72-0.76) | 14 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| FireAnimationFrame | 5.02 / 5.01 | 6.77 / 6.77 | 0.74 (0.72-0.78) | 14 | 0.74 (0.72-0.78) | 15 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Layout (us) | 2,857 / 5,496 | 3,904 / 2,759 | 0.73 (0.69-0.76) | 15 | 1.99 (0.69-8.78) | 1 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| RequestAnimationFrame | 5.06 / 5.01 | 7.10 / 7.10 | 0.71 (0.69-0.74) | 16 | 0.71 (0.69-0.74) | 16 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| TimerFire | 0.29 / 0.21 | 0.47 / 0.34 | 0.61 (0.41-0.68) | 17 | 0.63 (0.43-1.04) | 17 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| paintArea (px^2) | 234,756 / 261,239 | 735,974 / 757,491 | 0.32 (0.25-0.36) | 18 | 0.34 (0.30-0.39) | 18 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| TimerInstall | 0.00 / 0.00 | 0.21 / 0.15 | 0.00 (0.00) (*) | 19 | 0.00 (0.00) (*) | 19 | not stated (rare baseline) | no difference shown (ranges overlap) |
| TimerRemove | 0.00 / 0.00 | 0.28 / 0.21 | 0.00 (0.00) (*) | 20 | 0.00 (0.00) (*) | 20 | not stated (rare baseline) | no difference shown (ranges overlap) |
| RenderingFrame | 0.00 / 0.00 | 0.00 / 0.00 | no baseline | - | no baseline | - | - | no difference shown (ranges overlap) |

The ratio compares a window with the same arm's calm baseline, so an arm difference of the ratio can come from the baseline; the last column decides on the per-pass value itself. (*) the baseline of that arm has fewer than 10 events of the counter in at least one pass (Lean rareBase, event counts only), so its ratio and rank are unstable and no difference of the ratio is stated for the row. Duration columns (us) are Simulator-host microseconds summed over the records of the type; records nest (a Layout inside a FunctionCall), so durations are not additive across types.

Counters with no calm baseline (not ranked): original RenderingFrame; faithful RenderingFrame.

Paint area by part (css px^2 per pass; coarse part names, leaf parts below). The two arms have different part tables (the original a selector table, the rewrite its data-fw elements): a part in one table only is not compared, and the share of a part in both tables can move to a part of the other, so read neighbouring parts together.

| part | original px^2 per pass (range) | share original | faithful px^2 per pass (range) | share faithful | difference |
|---|---|---|---|---|---|
| platform | 3,447,325 (2,873,858-3,766,186) | 90% | 3,917,688 (3,535,405-4,328,557) | 91% | no difference shown (ranges overlap) |
| morph | 382,194 (352,976-438,034) | 10% | 376,531 (353,549-410,850) | 9% | no difference shown (ranges overlap) |
| nav | 4,758 (4,758) | 0% | 16,442 (4,758-39,809) | 0% | no difference shown (ranges overlap) |
| (none) | 0 (0) | 0% | 0 (0) | 0% | not compared (zero in one arm) |

- original, leaf parts: platform 3,447,325 (90%), morph-panel 349,820 (9%), morph-countdown 32,374 (1%), nav-lang 4,758 (0%), (none) 0 (0%)
- faithful, leaf parts: platform 3,917,688 (91%), morph-panel 364,876 (8%), nav 11,684 (0%), morph-countdown 11,655 (0%), nav-lang 4,758 (0%), (none) 0 (0%)

Top 5 steps of Region B, original (by paint area, all passes pooled):

| rank | pass | y or frame | Paint | paintArea px^2 | Layout | RecalculateStyles | owning part |
|---|---|---|---|---|---|---|---|
| 1 | s1p2 | 4950 | 12 | 700,308 | 3 | 6 | platform |
| 2 | s1p1 | 4700 | 16 | 661,382 | 5 | 5 | platform |
| 3 | s2p1 | 4550 | 22 | 597,037 | 8 | 6 | platform |
| 4 | s1p1 | 4950 | 19 | 539,146 | 8 | 8 | platform |
| 5 | s2p1 | 4600 | 20 | 516,470 | 5 | 4 | platform |

Top 5 steps of Region B, faithful (by paint area, all passes pooled):

| rank | pass | y or frame | Paint | paintArea px^2 | Layout | RecalculateStyles | owning part |
|---|---|---|---|---|---|---|---|
| 1 | s3p1 | 4750 | 18 | 878,109 | 6 | 4 | platform |
| 2 | s1p1 | 4700 | 16 | 840,792 | 6 | 5 | platform |
| 3 | s1p2 | 4950 | 18 | 705,019 | 5 | 6 | platform |
| 4 | s1p1 | 4750 | 11 | 687,042 | 5 | 5 | platform |
| 5 | s1p2 | 4850 | 17 | 640,209 | 6 | 4 | platform |

### Region B morph, open push (60 frames), ratio to the calm scroll baseline

Per-frame values. The calm baseline is the calm scroll steps of the same pass divided by 2 frames per step. The nav box differs from the idle tail in 60 (original), 40 (faithful) of the frames.

| counter | per frame original / faithful | baseline original / faithful | ratio original (per-pass range) | rank original | ratio faithful (per-pass range) | rank faithful | difference of the ratio | difference of the per frame value |
|---|---|---|---|---|---|---|---|---|
| Composite (us) | 44,290 / 53,443 | 29,122 / 22,807 | 1.52 (1.16-2.62) | 1 | 2.34 (1.08-3.93) | 1 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Paint | 6.42 / 7.55 | 4.77 / 4.81 | 1.35 (1.15-1.70) | 2 | 1.57 (1.13-1.79) | 3 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| InvalidateLayout | 2.28 / 2.25 | 2.15 / 2.12 | 1.06 (1.00-1.14) | 3 | 1.06 (0.86-1.23) | 4 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Composite | 1.00 / 1.00 | 1.00 / 1.00 | 1.00 (1.00) | 4 | 1.00 (1.00) | 5 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Paint (us) | 1,181 / 1,460 | 1,224 / 884 | 0.97 (0.60-1.77) | 5 | 1.65 (1.16-2.24) | 2 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| RecalculateStyles | 2.00 / 2.00 | 3.20 / 3.16 | 0.63 (0.61-0.65) | 6 | 0.63 (0.61-0.65) | 7 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| RecalculateStyles (us) | 2,707 / 2,843 | 5,613 / 5,502 | 0.48 (0.42-0.56) | 7 | 0.52 (0.45-0.68) | 8 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| TimerFire | 0.11 / 0.13 | 0.23 / 0.17 | 0.47 (0.34-0.66) | 8 | 0.76 (0.40-1.35) | 6 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Layout | 1.25 / 1.21 | 3.01 / 2.97 | 0.42 (0.39-0.43) | 9 | 0.41 (0.35-0.44) | 11 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| ObserverCallback | 0.09 / 0.12 | 0.25 / 0.25 | 0.36 (0.26-0.55) | 10 | 0.49 (0.28-0.68) | 9 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| ScheduleStyleRecalculation | 1.00 / 1.00 | 3.13 / 3.11 | 0.32 (0.31-0.33) | 11 | 0.32 (0.31-0.33) | 12 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| FireAnimationFrame | 1.04 / 1.06 | 3.38 / 3.39 | 0.31 (0.31-0.32) | 12 | 0.31 (0.31-0.32) | 13 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| RequestAnimationFrame | 1.04 / 1.06 | 3.55 / 3.55 | 0.29 (0.29-0.30) | 13 | 0.30 (0.29-0.31) | 14 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Layout (us) | 565 / 597 | 1,952 / 1,379 | 0.29 (0.22-0.51) | 14 | 0.43 (0.30-0.61) | 10 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| FunctionCall | 2.21 / 2.32 | 8.55 / 8.14 | 0.26 (0.19-0.31) | 15 | 0.29 (0.25-0.31) | 15 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| paintArea (px^2) | 64,529 / 79,519 | 367,987 / 378,745 | 0.18 (0.14-0.22) | 16 | 0.21 (0.15-0.25) | 16 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| EventDispatch | 0.97 / 1.01 | 6.12 / 5.72 | 0.16 (0.08-0.21) | 17 | 0.18 (0.11-0.21) | 17 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| FunctionCall (us) | 396 / 396 | 9,192 / 7,874 | 0.04 (0.03-0.06) | 18 | 0.05 (0.03-0.07) | 18 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| TimerInstall | 0.00 / 0.00 | 0.10 / 0.07 | 0.00 (0.00) (*) | 19 | 0.00 (0.00) (*) | 19 | not stated (rare baseline) | no difference shown (ranges overlap) |
| TimerRemove | 0.00 / 0.00 | 0.14 / 0.11 | 0.00 (0.00) (*) | 20 | 0.00 (0.00) (*) | 20 | not stated (rare baseline) | no difference shown (ranges overlap) |
| RenderingFrame | 0.00 / 0.00 | 0.00 / 0.00 | no baseline | - | no baseline | - | - | no difference shown (ranges overlap) |

The ratio compares a window with the same arm's calm baseline, so an arm difference of the ratio can come from the baseline; the last column decides on the per-pass value itself. (*) the baseline of that arm has fewer than 10 events of the counter in at least one pass (Lean rareBase, event counts only), so its ratio and rank are unstable and no difference of the ratio is stated for the row. Duration columns (us) are Simulator-host microseconds summed over the records of the type; records nest (a Layout inside a FunctionCall), so durations are not additive across types.

Counters with no calm baseline (not ranked): original RenderingFrame; faithful RenderingFrame.

Against the idle page tail (the 10 frames before the push, nothing moving) instead; ratio, rank 1-3; (*) as above, the idle baseline of that arm has fewer than 10 events of the counter in at least one pass:

- original: paintArea (px^2) x7.55 (5.88-10.4), EventDispatch x3.63 (2.50-6.50) (*), Composite (us) x2.16 (2.02-2.38); no idle baseline: RenderingFrame, TimerFire, ObserverCallback, TimerInstall, TimerRemove
- faithful: paintArea (px^2) x9.29 (6.41-10.9), Paint x2.10 (1.50-2.32), EventDispatch x1.90 (0.97-5.50) (*); no idle baseline: RenderingFrame, ObserverCallback, TimerInstall, TimerRemove

Paint area by part (css px^2 per pass; the two arms have different part tables, see Region A):

| part | original px^2 per pass (range) | share original | faithful px^2 per pass (range) | share faithful | difference |
|---|---|---|---|---|---|
| nav | 2,767,059 (1,585,001-3,855,115) | 71% | 1,945,207 (26,239-5,003,436) | 41% | no difference shown (ranges overlap) |
| platform | 229,918 (102,248-310,692) | 6% | 1,798,905 (101,845-5,224,348) | 38% | no difference shown (ranges overlap) |
| morph | 699,059 (11,345-1,054,842) | 18% | 904,895 (11,345-2,490,168) | 19% | no difference shown (ranges overlap) |
| (none) | 123,665 (87,952-160,724) | 3% | 95,634 (75,060-147,866) | 2% | no difference shown (ranges overlap) |
| hero | 51,345 (0-154,036) | 1% | 25,673 (0-154,036) | 1% | no difference shown (ranges overlap) |

- original, leaf parts: nav 2,754,637 (71%), morph-panel 675,301 (17%), platform 229,918 (6%), (none) 123,665 (3%), hero 51,345 (1%), morph-countdown 23,758 (1%), nav-lang 5,892 (0%), nav-actions 5,256 (0%)
- faithful, leaf parts: nav 1,929,109 (40%), platform 1,798,905 (38%), morph-panel 836,664 (18%), (none) 95,634 (2%), morph-countdown 68,231 (1%), hero 25,673 (1%), nav-actions 6,968 (0%), nav-lang 5,228 (0%)

Top 5 frames of the open push, original (by paint area; "y or frame" is the frame in the phase):

| rank | pass | y or frame | Paint | paintArea px^2 | Layout | RecalculateStyles | owning part |
|---|---|---|---|---|---|---|---|
| 1 | s2p1 | 2 | 100 | 1,647,274 | 2 | 2 | nav |
| 2 | s1p2 | 3 | 97 | 1,508,847 | 2 | 2 | nav |
| 3 | s1p1 | 2 | 96 | 1,401,297 | 2 | 2 | nav |
| 4 | s1p2 | 4 | 96 | 1,396,789 | 2 | 2 | nav |
| 5 | s2p1 | 1 | 94 | 1,196,831 | 3 | 2 | nav |

Top 5 frames of the open push, faithful (by paint area; "y or frame" is the frame in the phase):

| rank | pass | y or frame | Paint | paintArea px^2 | Layout | RecalculateStyles | owning part |
|---|---|---|---|---|---|---|---|
| 1 | s2p1 | 2 | 100 | 1,648,654 | 2 | 2 | nav |
| 2 | s3p2 | 3 | 98 | 1,521,849 | 2 | 2 | nav |
| 3 | s3p1 | 3 | 97 | 1,517,549 | 2 | 2 | nav |
| 4 | s1p2 | 3 | 98 | 1,515,261 | 2 | 2 | platform |
| 5 | s1p1 | 3 | 98 | 1,497,868 | 2 | 2 | platform |

### Region B morph, close push (60 frames), ratio to the calm scroll baseline

Per-frame values. The calm baseline is the calm scroll steps of the same pass divided by 2 frames per step. The nav box differs from the idle tail in 4 (original), 4 (faithful) of the frames.

| counter | per frame original / faithful | baseline original / faithful | ratio original (per-pass range) | rank original | ratio faithful (per-pass range) | rank faithful | difference of the ratio | difference of the per frame value |
|---|---|---|---|---|---|---|---|---|
| Paint | 10.2 / 9.01 | 4.77 / 4.81 | 2.15 (2.01-2.27) | 1 | 1.88 (1.28-2.26) | 2 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Composite (us) | 33,217 / 45,550 | 29,122 / 22,807 | 1.14 (0.96-2.00) | 2 | 2.00 (1.07-2.84) | 1 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| InvalidateLayout | 2.42 / 2.33 | 2.15 / 2.12 | 1.13 (1.05-1.22) | 3 | 1.10 (0.84-1.31) | 4 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Composite | 1.00 / 1.00 | 1.00 / 1.00 | 1.00 (1.00) | 4 | 1.00 (1.00) | 5 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Paint (us) | 1,149 / 1,349 | 1,224 / 884 | 0.94 (0.71-1.75) | 5 | 1.53 (1.19-2.10) | 3 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| ObserverCallback | 0.16 / 0.12 | 0.25 / 0.25 | 0.62 (0.53-0.68) | 6 | 0.49 (0.27-0.65) | 8 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| RecalculateStyles | 1.98 / 1.98 | 3.20 / 3.16 | 0.62 (0.60-0.64) | 7 | 0.63 (0.60-0.65) | 6 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Layout | 1.42 / 1.33 | 3.01 / 2.97 | 0.47 (0.44-0.50) | 8 | 0.45 (0.35-0.52) | 10 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| RecalculateStyles (us) | 2,410 / 2,580 | 5,613 / 5,502 | 0.43 (0.40-0.45) | 9 | 0.47 (0.35-0.52) | 9 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| paintArea (px^2) | 132,000 / 100,842 | 367,987 / 378,745 | 0.36 (0.28-0.41) | 10 | 0.27 (0.17-0.32) | 16 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| TimerFire | 0.08 / 0.11 | 0.23 / 0.17 | 0.36 (0.29-0.55) | 11 | 0.63 (0.32-0.93) | 7 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| FunctionCall | 2.96 / 2.64 | 8.55 / 8.14 | 0.35 (0.32-0.41) | 12 | 0.32 (0.26-0.36) | 12 | no difference shown (ranges overlap) | faithful lower |
| ScheduleStyleRecalculation | 1.00 / 1.00 | 3.13 / 3.11 | 0.32 (0.31-0.33) | 13 | 0.32 (0.31-0.33) | 13 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| FireAnimationFrame | 1.08 / 1.06 | 3.38 / 3.39 | 0.32 (0.31-0.32) | 14 | 0.31 (0.31-0.32) | 14 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| RequestAnimationFrame | 1.06 / 1.04 | 3.55 / 3.55 | 0.30 (0.30) | 15 | 0.29 (0.29-0.30) | 15 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| Layout (us) | 529 / 535 | 1,952 / 1,379 | 0.27 (0.23-0.42) | 16 | 0.39 (0.31-0.48) | 11 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| EventDispatch | 1.64 / 1.35 | 6.12 / 5.72 | 0.27 (0.23-0.34) | 17 | 0.24 (0.14-0.28) | 17 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| FunctionCall (us) | 238 / 281 | 9,192 / 7,874 | 0.03 (0.02-0.03) | 18 | 0.04 (0.02-0.08) | 18 | no difference shown (ranges overlap) | no difference shown (ranges overlap) |
| TimerInstall | 0.00 / 0.00 | 0.10 / 0.07 | 0.00 (0.00) (*) | 19 | 0.00 (0.00) (*) | 19 | not stated (rare baseline) | no difference shown (ranges overlap) |
| TimerRemove | 0.00 / 0.00 | 0.14 / 0.11 | 0.00 (0.00) (*) | 20 | 0.00 (0.00) (*) | 20 | not stated (rare baseline) | no difference shown (ranges overlap) |
| RenderingFrame | 0.00 / 0.00 | 0.00 / 0.00 | no baseline | - | no baseline | - | - | no difference shown (ranges overlap) |

The ratio compares a window with the same arm's calm baseline, so an arm difference of the ratio can come from the baseline; the last column decides on the per-pass value itself. (*) the baseline of that arm has fewer than 10 events of the counter in at least one pass (Lean rareBase, event counts only), so its ratio and rank are unstable and no difference of the ratio is stated for the row. Duration columns (us) are Simulator-host microseconds summed over the records of the type; records nest (a Layout inside a FunctionCall), so durations are not additive across types.

Counters with no calm baseline (not ranked): original RenderingFrame; faithful RenderingFrame.

Against the idle page tail (the 10 frames before the push, nothing moving) instead; ratio, rank 1-3; (*) as above, the idle baseline of that arm has fewer than 10 events of the counter in at least one pass:

- original: paintArea (px^2) x15.5 (11.5-17.7), EventDispatch x6.17 (4.50-8.00) (*), Paint x2.90 (2.65-3.11); no idle baseline: RenderingFrame, TimerFire, ObserverCallback, TimerInstall, TimerRemove
- faithful: paintArea (px^2) x11.8 (7.41-13.9), EventDispatch x2.53 (1.47-7.17) (*), Paint x2.50 (1.65-3.08); no idle baseline: RenderingFrame, ObserverCallback, TimerInstall, TimerRemove

Paint area by part (css px^2 per pass; the two arms have different part tables, see Region A):

| part | original px^2 per pass (range) | share original | faithful px^2 per pass (range) | share faithful | difference |
|---|---|---|---|---|---|
| platform | 6,400,434 (4,938,085-7,279,865) | 81% | 5,021,924 (2,588,126-6,077,226) | 83% | no difference shown (ranges overlap) |
| morph | 1,338,704 (813,539-1,661,703) | 17% | 793,924 (495,978-943,327) | 13% | no difference shown (ranges overlap) |
| nav | 179,836 (160,081-203,086) | 2% | 201,390 (86,125-523,770) | 3% | no difference shown (ranges overlap) |
| hero | not in this arm | - | 25,673 (0-154,036) | 0% | not compared (part absent in one arm) |
| (none) | not in this arm | - | 6,401 (0-38,404) | 0% | not compared (part absent in one arm) |

- original, leaf parts: platform 6,400,434 (81%), morph-panel 1,299,168 (16%), nav-earn 123,979 (2%), morph-countdown 39,536 (0%), nav-lang 27,492 (0%), nav 17,023 (0%), nav-actions 11,343 (0%)
- faithful, leaf parts: platform 5,021,924 (83%), morph-panel 732,681 (12%), nav 93,766 (2%), nav-earn 91,936 (2%), morph-countdown 61,243 (1%), hero 25,673 (0%), nav-lang 13,463 (0%), (none) 6,401 (0%)

Top 5 frames of the close push, original (by paint area; "y or frame" is the frame in the phase):

| rank | pass | y or frame | Paint | paintArea px^2 | Layout | RecalculateStyles | owning part |
|---|---|---|---|---|---|---|---|
| 1 | s1p1 | 1 | 95 | 1,259,465 | 2 | 2 | platform |
| 2 | s2p1 | 1 | 95 | 1,235,428 | 2 | 2 | platform |
| 3 | s1p2 | 1 | 95 | 1,230,426 | 2 | 2 | platform |
| 4 | s1p1 | 2 | 92 | 1,031,695 | 2 | 2 | platform |
| 5 | s1p2 | 5 | 13 | 1,029,353 | 2 | 2 | platform |

Top 5 frames of the close push, faithful (by paint area; "y or frame" is the frame in the phase):

| rank | pass | y or frame | Paint | paintArea px^2 | Layout | RecalculateStyles | owning part |
|---|---|---|---|---|---|---|---|
| 1 | s3p1 | 2 | 19 | 1,278,620 | 2 | 2 | platform |
| 2 | s1p2 | 1 | 95 | 1,275,041 | 2 | 2 | platform |
| 3 | s2p1 | 1 | 95 | 1,275,041 | 2 | 2 | platform |
| 4 | s2p2 | 1 | 95 | 1,266,835 | 2 | 2 | platform |
| 5 | s1p1 | 1 | 95 | 1,262,189 | 2 | 2 | platform |

### Idle page tail (the 10 frames before the push)

- original: Paint per frame 3.40-3.60 per pass, paint area per frame 8,514-8,555 px^2 per pass; by part platform 8,178 (96%), morph-countdown 347 (4%); first-pass clips 140.0x39.0 at 244,675; 57.3x3.5 at 104,68; 57.3x3.5 at 269,68; 93.0x39.0 at 20,248
- faithful: Paint per frame 3.60 per pass, paint area per frame 8,555 px^2 per pass; by part platform 8,178 (96%), morph-countdown 361 (4%); first-pass clips 93.0x39.0 at 20,249; 140.0x39.0 at 244,676; 57.3x3.5 at 104,69; 57.3x3.5 at 269,69

### Filter and backdrop-filter elements (geometry pass, per scanned step)

| region | arm | scanned / steps (per session) | visible filter layers per step (range over sessions) | visible area px^2 | area x radius |
|---|---|---|---|---|---|
| A | original | 16/16, 16/16 | 4.00-4.13 | 143,355-143,670 | 1,398,064-1,478,228 |
| A | faithful | 16/16, 16/16, 16/16 | 4.00-4.13 | 142,361-143,603 | 1,413,275-1,445,064 |
| B | original | 17/17, 17/17 | 6.94 | 456,936-457,276 | 1,683,334 |
| B | faithful | 16/16, 17/17, 17/17 | 6.94-7.00 | 457,166-461,260 | 1,683,334-1,746,376 |
| calm | original | 6/44, 6/44 | 4.33 | 70,707 | 733,957 |
| calm | faithful | 6/43, 6/44, 6/44 | 4.33 | 70,707 | 733,957 |

- A: filter layers per step: no difference shown (ranges overlap); visible filter area: no difference shown (ranges overlap); area x radius: no difference shown (ranges overlap)
- B: filter layers per step: no difference shown (ranges overlap); visible filter area: no difference shown (ranges overlap); area x radius: no difference shown (ranges overlap)
- calm: filter layers per step: no difference shown (ranges overlap); visible filter area: no difference shown (ranges overlap); area x radius: no difference shown (ranges overlap)

The calm baseline scans every eighth step only (the scan reads the computed style of every element); the "scanned / steps" column states how many steps each average is over.

### Layer census (LayerTree, untimed, four scroll states, one value per session)

| state | y (px) | layers (range over sessions) | backing MB | filter or backdrop layers |
|---|---|---|---|---|
| 1 | 0 | original 122 | 52.2 | 3-4 |
| 1 | 0 | faithful 118-122 | 52.0-57.4 | 3-4 |
| 1 | | layers: no difference shown (ranges overlap) | MB: no difference shown (ranges overlap) | filter layers: no difference shown (ranges overlap) |
| 2 | 388 | original 121-122 | 51.6-51.9 | 3 |
| 2 | 388 | faithful 121-125 | 51.6-51.8 | 3-4 |
| 2 | | layers: no difference shown (ranges overlap) | MB: no difference shown (ranges overlap) | filter layers: no difference shown (ranges overlap) |
| 3 | 2,634 | original 139 | 83.7 | 4 |
| 3 | 2,616-2,634 | faithful 143-145 | 76.0-83.9 | 4-5 |
| 3 | | layers: faithful higher | MB: no difference shown (ranges overlap) | filter layers: no difference shown (ranges overlap) |
| 4 | 5,267 | original 124 | 97.9 | 4 |
| 4 | 5,231-5,267 | faithful 128 | 97.9-105.8 | 4 |
| 4 | | layers: faithful higher | MB: no difference shown (ranges overlap) | filter layers: no difference shown (ranges overlap) |

Layer count change between consecutive states (mean over sessions): original -0, 18, -15; faithful 3, 22, -16

Compositing reasons at the last state (layers per session, range):

| reason | original | faithful |
|---|---|---|
| animation | 5 | 8 |
| clipsCompositingDescendants | 6 | 6 |
| filterWithCompositedDescendants | 2 | 2 |
| filters | 2 | 2 |
| maskWithCompositedDescendants | 1 | 1 |
| opacityWithCompositedDescendants | 2 | 2 |
| overflowScrollingTouch | 2 | 2 |
| overlap | 5 | 5 |
| positionFixed | 1 | 1 |
| positionSticky | 1 | 1 |
| root | 1 | 1 |
| stacking | 87 | 90 |
| transformWithCompositedDescendants | 8 | 9 |
| willChange | 90 | 90 |

### Morph validity

- original: wheel pushes taken (default prevented) in 3 of 3 passes, scrollTo calls 0, --morph before/after ["0","0"], platform box before 1881
- faithful: wheel pushes taken (default prevented) in 6 of 6 passes, scrollTo calls 0, --morph before/after ["0","0"], platform box before 1881
cli: exit 0
