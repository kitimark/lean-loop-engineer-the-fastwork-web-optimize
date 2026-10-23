Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39924675073:leg, 390px, window hero** (CPU throttle 1x, candidate default, A/A spread 0.59 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1205 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 33.2 | 33.4 |
| base | 7 | 1208 | 0.66 | 0.59 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.5 |
| aa | 7 | 1208 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |
| cand | 7 | 1200 | 0.58 | 0.02 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |

Rate verdicts: orig vs base: first; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39924675073:leg, 390px, window end** (CPU throttle 1x, candidate default, A/A spread 0.83 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 837 | 0.47 | 1.69 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.2 | 33.4 | 50.1 |
| base | 7 | 833 | 0.96 | 0.82 | 6 of 7 | 1,1,1,1,1,0,1 | 16.7 | 16.8 | 33.4 | 66.8 |
| aa | 7 | 836 | 0.95 | 0.83 | 3 of 7 | 0,0,1,0,0,1,1 | 16.7 | 16.8 | 33.4 | 66.6 |
| cand | 7 | 832 | 1.20 | 0.85 | 5 of 7 | 0,1,1,1,1,0,1 | 16.7 | 16.8 | 50.0 | 66.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.49 | 0.83 |
| 390 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.24 | 0.83 |
| 390 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.73 | 0.83 |
| 390 | hero | orig | base | 1 | 1 / 1 | 1 / 0 / 0 / 0 | insufficient | 1 / 0 / 0 / 0 | insufficient | 0.66 | 0.59 |
| 390 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.08 | 0.59 |
| 390 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 1 / 0 / 0 / 0 | insufficient | 0.58 | 0.59 |

Samples: 39924675073:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39924675073:leg | 390 | hero | base | 7 | 7 | 83.4 | 672 | 7 |
| 39924675073:leg | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39924675073:leg | 390 | hero | cand | 7 | 7 | 83.3 | 672 | 7 |
| 39924675073:leg | 390 | end | base | 7 | 6 | 66.6 | 5103 | 2 |
| 39924675073:leg | 390 | end | aa | 7 | 3 | 66.6 | 5103 | 2 |
| 39924675073:leg | 390 | end | cand | 7 | 5 | 66.7 | 5103 | 2 |

### Frames of the page's compositor sink (traced reps, the renderer process of the page only; reported beside the verdict, never in it)

A frame is one `frame_sequence`; `dropped` = any of its pipeline reporters dropped, `dropped (all)` = every reporter dropped, `presented` = the rest with a presented reporter.

| width | window | arm | traced reps | runs | frames | presented | dropped | dropped % | dropped (all) | dropped (all) % | rAF frames in the same reps | presented p95 ms (median of reps) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | 5 | 1 | 630 | 602 | 28 | 4.4 | 28 | 4.4 | 589 | 67.5 |
| 390 | end | base | 5 | 1 | 626 | 596 | 30 | 4.8 | 30 | 4.8 | 589 | 74.9 |
| 390 | end | aa | 5 | 1 | 627 | 595 | 32 | 5.1 | 32 | 5.1 | 584 | 79.8 |
| 390 | end | cand | 5 | 1 | 629 | 597 | 32 | 5.1 | 32 | 5.1 | 585 | 75.5 |
| 390 | hero | orig | 5 | 1 | 867 | 792 | 75 | 8.7 | 15 | 1.7 | 849 | 32.6 |
| 390 | hero | base | 5 | 1 | 889 | 785 | 104 | 11.7 | 39 | 4.4 | 852 | 32.6 |
| 390 | hero | aa | 5 | 1 | 881 | 781 | 100 | 11.4 | 38 | 4.3 | 842 | 32.5 |
| 390 | hero | cand | 5 | 1 | 890 | 784 | 106 | 11.9 | 39 | 4.4 | 852 | 32.6 |

### Fixed slow-event names of the traced reps (page renderer process; every row is always listed, n = 0 means the event never ran; long = 15 ms or more)

| width | window | arm | traced reps | event | events | long | longest ms | total ms | long durations ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | 5 | BeginMainFrame | 594 | 10 | 50.9 | 3726.0 | 15.1, 15.4, 15.7, 15.8, 16.6, 36.5, 37.6, 37.9, 46.7, 50.9 |
| 390 | end | orig | 5 | Paint | 5237 | 0 | 3.2 | 766.7 | - |
| 390 | end | orig | 5 | UpdateLayoutTree | 968 | 0 | 10.6 | 1469.9 | - |
| 390 | end | orig | 5 | Layout | 767 | 0 | 0.4 | 158.9 | - |
| 390 | end | orig | 5 | image decode task | 2598 | 0 | 9.1 | 367.5 | - |
| 390 | end | base | 5 | BeginMainFrame | 594 | 5 | 61.2 | 4220.7 | 45.5, 46.7, 48.7, 58.3, 61.2 |
| 390 | end | base | 5 | Paint | 5244 | 0 | 3.3 | 786.2 | - |
| 390 | end | base | 5 | UpdateLayoutTree | 968 | 0 | 6.6 | 1242.7 | - |
| 390 | end | base | 5 | Layout | 772 | 0 | 1.2 | 169.7 | - |
| 390 | end | base | 5 | image decode task | 2573 | 0 | 9.3 | 355.2 | - |
| 390 | end | aa | 5 | BeginMainFrame | 589 | 6 | 58.8 | 4182.9 | 15.5, 45.3, 46.6, 46.8, 56.8, 58.8 |
| 390 | end | aa | 5 | Paint | 5235 | 0 | 3.4 | 789.1 | - |
| 390 | end | aa | 5 | UpdateLayoutTree | 960 | 0 | 5.9 | 1221.5 | - |
| 390 | end | aa | 5 | Layout | 768 | 0 | 0.9 | 167.6 | - |
| 390 | end | aa | 5 | image decode task | 2550 | 0 | 12.0 | 378.7 | - |
| 390 | end | cand | 5 | BeginMainFrame | 590 | 6 | 59.3 | 4101.1 | 15.1, 41.1, 43.4, 46.3, 58.7, 59.3 |
| 390 | end | cand | 5 | Paint | 5264 | 0 | 3.4 | 788.4 | - |
| 390 | end | cand | 5 | UpdateLayoutTree | 960 | 0 | 6.8 | 1223.2 | - |
| 390 | end | cand | 5 | Layout | 766 | 0 | 0.8 | 166.0 | - |
| 390 | end | cand | 5 | image decode task | 2562 | 0 | 9.2 | 353.9 | - |
| 390 | hero | orig | 5 | BeginMainFrame | 854 | 3 | 16.1 | 3989.5 | 15.2, 15.3, 16.1 |
| 390 | hero | orig | 5 | Paint | 5214 | 0 | 2.7 | 533.7 | - |
| 390 | hero | orig | 5 | UpdateLayoutTree | 2004 | 0 | 4.6 | 1370.7 | - |
| 390 | hero | orig | 5 | Layout | 906 | 0 | 2.1 | 156.7 | - |
| 390 | hero | orig | 5 | image decode task | 566 | 10 | 55.5 | 779.3 | 31.3, 31.4, 31.8, 32.5, 32.9, 52.6, 53.1, 53.1, 53.2, 55.5 |
| 390 | hero | base | 5 | BeginMainFrame | 857 | 5 | 17.6 | 4083.4 | 16.4, 16.8, 16.8, 17.3, 17.6 |
| 390 | hero | base | 5 | Paint | 5026 | 0 | 3.0 | 517.0 | - |
| 390 | hero | base | 5 | UpdateLayoutTree | 1983 | 0 | 3.8 | 1138.7 | - |
| 390 | hero | base | 5 | Layout | 908 | 0 | 1.7 | 151.5 | - |
| 390 | hero | base | 5 | image decode task | 596 | 20 | 54.5 | 1062.9 | 31.3, 31.3, 31.3, 31.5, 31.5, 31.5, 31.6, 31.8, 32.0, 32.1, 33.8, 33.9, 34.1, 34.1, 34.1, 52.4, 52.5, 52.6, 53.6, 54.5 |
| 390 | hero | aa | 5 | BeginMainFrame | 847 | 5 | 18.2 | 4097.6 | 17.6, 17.7, 17.8, 18.1, 18.2 |
| 390 | hero | aa | 5 | Paint | 4999 | 0 | 3.3 | 522.8 | - |
| 390 | hero | aa | 5 | UpdateLayoutTree | 1971 | 0 | 3.9 | 1134.6 | - |
| 390 | hero | aa | 5 | Layout | 910 | 0 | 1.9 | 154.2 | - |
| 390 | hero | aa | 5 | image decode task | 597 | 20 | 57.8 | 1104.2 | 31.1, 31.3, 31.4, 31.5, 31.7, 31.7, 31.9, 31.9, 33.5, 34.0, 34.2, 34.2, 34.5, 35.6, 36.8, 52.4, 52.8, 54.1, 54.5, 57.8 |
| 390 | hero | cand | 5 | BeginMainFrame | 857 | 6 | 19.4 | 4133.8 | 16.9, 17.6, 17.9, 18.1, 19.4, 19.4 |
| 390 | hero | cand | 5 | Paint | 5003 | 0 | 3.3 | 524.6 | - |
| 390 | hero | cand | 5 | UpdateLayoutTree | 1979 | 0 | 11.3 | 1149.3 | - |
| 390 | hero | cand | 5 | Layout | 909 | 0 | 1.5 | 153.5 | - |
| 390 | hero | cand | 5 | image decode task | 607 | 20 | 53.5 | 1065.6 | 31.0, 31.1, 31.2, 31.2, 31.3, 31.3, 31.4, 31.4, 31.5, 31.5, 33.5, 33.7, 33.8, 34.1, 34.3, 52.3, 52.5, 52.6, 53.4, 53.5 |
