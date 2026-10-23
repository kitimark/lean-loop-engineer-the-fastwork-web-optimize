Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39924675073:leg, 390px, window hero** (CPU throttle 1x, candidate default, A/A spread 0.01 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1208 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 33.2 | 33.4 |
| base | 7 | 1208 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| aa | 7 | 1213 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.5 |
| cand | 7 | 1212 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |

Rate verdicts: orig vs base: first; base vs cand: same; orig vs cand: first
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39924675073:leg, 390px, window end** (CPU throttle 1x, candidate default, A/A spread 1.68 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 837 | 1.07 | 1.68 | 2 of 7 | 1,1,0,0,0,0,0 | 16.7 | 16.8 | 49.9 | 66.7 |
| base | 7 | 832 | 1.32 | 0.85 | 4 of 7 | 1,0,0,1,1,0,1 | 16.7 | 16.8 | 49.9 | 66.7 |
| aa | 7 | 834 | 0.95 | 1.68 | 3 of 7 | 1,1,1,0,0,0,0 | 16.7 | 16.8 | 33.4 | 66.7 |
| cand | 7 | 832 | 0.84 | 1.69 | 6 of 7 | 1,1,1,1,1,0,1 | 16.7 | 16.8 | 33.4 | 66.8 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.25 | 1.68 |
| 390 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.48 | 1.68 |
| 390 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.23 | 1.68 |
| 390 | hero | orig | base | 1 | 1 / 1 | 1 / 0 / 0 / 0 | insufficient | 1 / 0 / 0 / 0 | insufficient | 0.57 | 0.01 |
| 390 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.00 | 0.01 |
| 390 | hero | orig | cand | 1 | 1 / 1 | 1 / 0 / 0 / 0 | insufficient | 1 / 0 / 0 / 0 | insufficient | 0.57 | 0.01 |

Samples: 39924675073:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39924675073:leg | 390 | hero | base | 7 | 7 | 83.3 | 672 | 7 |
| 39924675073:leg | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39924675073:leg | 390 | hero | cand | 7 | 7 | 83.4 | 672 | 7 |
| 39924675073:leg | 390 | end | orig | 7 | 2 | 66.6 | 5103 | 0 |
| 39924675073:leg | 390 | end | base | 7 | 4 | 66.6 | 5103 | 0 |
| 39924675073:leg | 390 | end | aa | 7 | 3 | 66.7 | 5103 | 0 |
| 39924675073:leg | 390 | end | cand | 7 | 6 | 66.6 | 5103 | 2 |

### Frames of the page's compositor sink (traced reps, the renderer process of the page only; reported beside the verdict, never in it)

A frame is one `frame_sequence`; `dropped` = any of its pipeline reporters dropped, `dropped (all)` = every reporter dropped, `presented` = the rest with a presented reporter.

| width | window | arm | traced reps | runs | frames | presented | dropped | dropped % | dropped (all) | dropped (all) % | rAF frames in the same reps | presented p95 ms (median of reps) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | 5 | 1 | 637 | 613 | 24 | 3.8 | 24 | 3.8 | 597 | 67.6 |
| 390 | end | base | 5 | 1 | 634 | 610 | 24 | 3.8 | 24 | 3.8 | 594 | 59.8 |
| 390 | end | aa | 5 | 1 | 632 | 606 | 26 | 4.1 | 26 | 4.1 | 592 | 57.0 |
| 390 | end | cand | 5 | 1 | 634 | 610 | 24 | 3.8 | 24 | 3.8 | 592 | 62.8 |
| 390 | hero | orig | 5 | 1 | 868 | 784 | 84 | 9.7 | 16 | 1.8 | 851 | 31.6 |
| 390 | hero | base | 5 | 1 | 890 | 791 | 99 | 11.1 | 37 | 4.2 | 853 | 31.9 |
| 390 | hero | aa | 5 | 1 | 888 | 786 | 102 | 11.5 | 39 | 4.4 | 853 | 31.7 |
| 390 | hero | cand | 5 | 1 | 894 | 779 | 115 | 12.9 | 39 | 4.4 | 857 | 31.7 |

### Fixed slow-event names of the traced reps (page renderer process; every row is always listed, n = 0 means the event never ran; long = 15 ms or more)

| width | window | arm | traced reps | event | events | long | longest ms | total ms | long durations ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | 5 | BeginMainFrame | 602 | 7 | 44.8 | 3408.4 | 15.6, 16.0, 31.8, 33.8, 36.7, 39.1, 44.8 |
| 390 | end | orig | 5 | Paint | 5268 | 0 | 3.1 | 706.5 | - |
| 390 | end | orig | 5 | UpdateLayoutTree | 981 | 0 | 9.8 | 1374.9 | - |
| 390 | end | orig | 5 | Layout | 776 | 0 | 0.3 | 129.9 | - |
| 390 | end | orig | 5 | image decode task | 2624 | 0 | 9.7 | 352.7 | - |
| 390 | end | base | 5 | BeginMainFrame | 599 | 5 | 57.7 | 3752.1 | 35.7, 39.2, 43.9, 50.7, 57.7 |
| 390 | end | base | 5 | Paint | 5266 | 0 | 3.1 | 730.9 | - |
| 390 | end | base | 5 | UpdateLayoutTree | 977 | 0 | 5.9 | 1137.2 | - |
| 390 | end | base | 5 | Layout | 775 | 0 | 0.8 | 147.3 | - |
| 390 | end | base | 5 | image decode task | 2605 | 0 | 9.5 | 352.7 | - |
| 390 | end | aa | 5 | BeginMainFrame | 597 | 5 | 53.2 | 3677.5 | 39.1, 41.1, 41.9, 51.3, 53.2 |
| 390 | end | aa | 5 | Paint | 5270 | 0 | 3.0 | 723.3 | - |
| 390 | end | aa | 5 | UpdateLayoutTree | 974 | 0 | 5.7 | 1115.0 | - |
| 390 | end | aa | 5 | Layout | 781 | 0 | 0.8 | 142.0 | - |
| 390 | end | aa | 5 | image decode task | 2611 | 0 | 9.3 | 350.0 | - |
| 390 | end | cand | 5 | BeginMainFrame | 597 | 5 | 51.1 | 3759.1 | 37.4, 41.4, 43.0, 44.3, 51.1 |
| 390 | end | cand | 5 | Paint | 5288 | 0 | 3.1 | 732.8 | - |
| 390 | end | cand | 5 | UpdateLayoutTree | 975 | 0 | 6.1 | 1143.9 | - |
| 390 | end | cand | 5 | Layout | 781 | 0 | 0.8 | 147.6 | - |
| 390 | end | cand | 5 | image decode task | 2596 | 0 | 8.7 | 348.6 | - |
| 390 | hero | orig | 5 | BeginMainFrame | 856 | 0 | 14.8 | 3493.1 | - |
| 390 | hero | orig | 5 | Paint | 5238 | 0 | 2.2 | 474.8 | - |
| 390 | hero | orig | 5 | UpdateLayoutTree | 2010 | 0 | 4.6 | 1223.6 | - |
| 390 | hero | orig | 5 | Layout | 906 | 0 | 2.1 | 142.2 | - |
| 390 | hero | orig | 5 | image decode task | 560 | 10 | 53.3 | 752.1 | 30.7, 31.1, 31.2, 31.3, 31.3, 52.4, 52.8, 52.8, 52.9, 53.3 |
| 390 | hero | base | 5 | BeginMainFrame | 858 | 2 | 16.8 | 3598.9 | 16.4, 16.8 |
| 390 | hero | base | 5 | Paint | 5024 | 0 | 2.8 | 463.9 | - |
| 390 | hero | base | 5 | UpdateLayoutTree | 1980 | 0 | 4.3 | 1017.8 | - |
| 390 | hero | base | 5 | Layout | 909 | 0 | 1.7 | 136.4 | - |
| 390 | hero | base | 5 | image decode task | 621 | 20 | 53.3 | 1054.7 | 30.9, 30.9, 31.0, 31.0, 31.1, 31.2, 31.4, 31.7, 31.8, 32.0, 33.4, 33.5, 33.8, 33.9, 34.2, 51.9, 52.0, 52.6, 53.0, 53.3 |
| 390 | hero | aa | 5 | BeginMainFrame | 858 | 4 | 17.5 | 3604.4 | 15.1, 15.7, 16.3, 17.5 |
| 390 | hero | aa | 5 | Paint | 5014 | 0 | 2.8 | 469.0 | - |
| 390 | hero | aa | 5 | UpdateLayoutTree | 1983 | 0 | 3.7 | 1010.6 | - |
| 390 | hero | aa | 5 | Layout | 912 | 0 | 1.9 | 136.5 | - |
| 390 | hero | aa | 5 | image decode task | 611 | 20 | 53.1 | 1054.1 | 30.8, 30.9, 31.1, 31.2, 31.3, 31.3, 31.5, 31.6, 31.6, 31.8, 33.3, 34.0, 34.0, 34.0, 34.3, 51.5, 52.5, 52.7, 53.1, 53.1 |
| 390 | hero | cand | 5 | BeginMainFrame | 862 | 4 | 16.8 | 3591.7 | 15.6, 16.4, 16.8, 16.8 |
| 390 | hero | cand | 5 | Paint | 5033 | 0 | 2.7 | 465.4 | - |
| 390 | hero | cand | 5 | UpdateLayoutTree | 1987 | 0 | 3.7 | 1008.9 | - |
| 390 | hero | cand | 5 | Layout | 917 | 0 | 1.8 | 138.4 | - |
| 390 | hero | cand | 5 | image decode task | 631 | 20 | 53.0 | 1052.9 | 30.9, 31.1, 31.2, 31.2, 31.3, 31.3, 31.5, 31.5, 31.6, 31.7, 33.4, 33.6, 33.7, 33.8, 34.0, 51.3, 52.5, 52.6, 52.6, 53.0 |
