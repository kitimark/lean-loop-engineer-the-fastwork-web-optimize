Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39927164863:leg, 390px, window hero** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 0.01 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1209 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 16.8 | 33.4 |
| base | 7 | 1210 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| aa | 7 | 1211 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |
| cand | 7 | 1208 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |

Rate verdicts: orig vs base: first; base vs cand: same; orig vs cand: first
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39927164863:leg, 390px, window end** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 1.68 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 840 | 0.71 | 1.69 | 1 of 7 | 1,0,0,0,0,0,0 | 16.7 | 16.8 | 33.4 | 66.7 |
| base | 7 | 839 | 0.47 | 1.68 | 2 of 7 | 0,0,1,0,0,0,1 | 16.7 | 16.8 | 33.4 | 66.7 |
| aa | 7 | 840 | 0.71 | 1.66 | 3 of 7 | 1,0,0,0,0,1,1 | 16.7 | 16.8 | 33.4 | 66.8 |
| cand | 7 | 840 | 0.71 | 1.66 | 2 of 7 | 0,0,0,0,0,1,1 | 16.7 | 16.8 | 33.4 | 66.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.24 | 1.68 |
| 390 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.24 | 1.68 |
| 390 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.00 | 1.68 |
| 390 | hero | orig | base | 1 | 1 / 1 | 1 / 0 / 0 / 0 | insufficient | 1 / 0 / 0 / 0 | insufficient | 0.57 | 0.01 |
| 390 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.00 | 0.01 |
| 390 | hero | orig | cand | 1 | 1 / 1 | 1 / 0 / 0 / 0 | insufficient | 1 / 0 / 0 / 0 | insufficient | 0.57 | 0.01 |

Samples: 39927164863:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39927164863:leg | 390 | hero | base | 7 | 7 | 83.3 | 672 | 7 |
| 39927164863:leg | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39927164863:leg | 390 | hero | cand | 7 | 7 | 66.7 | 672 | 7 |
| 39927164863:leg | 390 | end | orig | 7 | 1 | 66.7 | 5103 | 0 |
| 39927164863:leg | 390 | end | base | 7 | 2 | 66.6 | 5103 | 0 |
| 39927164863:leg | 390 | end | aa | 7 | 3 | 66.7 | 5103 | 0 |
| 39927164863:leg | 390 | end | cand | 7 | 2 | 66.6 | 5103 | 0 |

### Frames of the page's compositor sink (traced reps, the renderer process of the page only; reported beside the verdict, never in it)

A frame is one `frame_sequence`; `dropped` = any of its pipeline reporters dropped, `dropped (all)` = every reporter dropped, `presented` = the rest with a presented reporter.

| width | window | arm | traced reps | runs | frames | presented | dropped | dropped % | dropped (all) | dropped (all) % | rAF frames in the same reps | presented p95 ms (median of reps) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | 5 | 1 | 632 | 607 | 25 | 4.0 | 25 | 4.0 | 594 | 69.2 |
| 390 | end | base | 5 | 1 | 630 | 605 | 25 | 4.0 | 25 | 4.0 | 593 | 63.8 |
| 390 | end | aa | 5 | 1 | 631 | 604 | 27 | 4.3 | 27 | 4.3 | 590 | 60.8 |
| 390 | end | cand | 5 | 1 | 630 | 604 | 26 | 4.1 | 26 | 4.1 | 595 | 61.9 |
| 390 | hero | orig | 5 | 1 | 874 | 788 | 86 | 9.8 | 16 | 1.8 | 856 | 32.0 |
| 390 | hero | base | 5 | 1 | 895 | 783 | 112 | 12.5 | 40 | 4.5 | 859 | 31.8 |
| 390 | hero | aa | 5 | 1 | 883 | 780 | 103 | 11.7 | 39 | 4.4 | 845 | 32.0 |
| 390 | hero | cand | 5 | 1 | 884 | 782 | 102 | 11.5 | 38 | 4.3 | 846 | 32.1 |

### Fixed slow-event names of the traced reps (page renderer process; every row is always listed, n = 0 means the event never ran; long = 15 ms or more)

| width | window | arm | traced reps | event | events | long | longest ms | total ms | long durations ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | 5 | BeginMainFrame | 599 | 8 | 47.0 | 3625.3 | 15.0, 15.9, 19.0, 31.8, 38.4, 41.4, 44.9, 47.0 |
| 390 | end | orig | 5 | Paint | 5236 | 0 | 3.2 | 749.6 | - |
| 390 | end | orig | 5 | UpdateLayoutTree | 977 | 0 | 12.3 | 1483.6 | - |
| 390 | end | orig | 5 | Layout | 773 | 0 | 1.3 | 142.0 | - |
| 390 | end | orig | 5 | image decode task | 2618 | 0 | 9.3 | 363.0 | - |
| 390 | end | base | 5 | BeginMainFrame | 598 | 5 | 43.2 | 3776.7 | 37.7, 39.1, 40.7, 43.1, 43.2 |
| 390 | end | base | 5 | Paint | 5265 | 0 | 3.3 | 753.8 | - |
| 390 | end | base | 5 | UpdateLayoutTree | 976 | 0 | 6.0 | 1173.1 | - |
| 390 | end | base | 5 | Layout | 776 | 0 | 0.9 | 147.4 | - |
| 390 | end | base | 5 | image decode task | 2611 | 0 | 9.9 | 357.1 | - |
| 390 | end | aa | 5 | BeginMainFrame | 595 | 5 | 54.0 | 3908.6 | 37.9, 42.4, 43.6, 44.2, 54.0 |
| 390 | end | aa | 5 | Paint | 5280 | 0 | 3.3 | 772.2 | - |
| 390 | end | aa | 5 | UpdateLayoutTree | 970 | 0 | 6.2 | 1207.6 | - |
| 390 | end | aa | 5 | Layout | 775 | 0 | 0.8 | 155.4 | - |
| 390 | end | aa | 5 | image decode task | 2561 | 0 | 9.6 | 353.2 | - |
| 390 | end | cand | 5 | BeginMainFrame | 600 | 5 | 44.0 | 3617.7 | 38.0, 40.0, 41.3, 42.6, 44.0 |
| 390 | end | cand | 5 | Paint | 5011 | 0 | 3.1 | 742.2 | - |
| 390 | end | cand | 5 | UpdateLayoutTree | 979 | 0 | 5.7 | 1134.4 | - |
| 390 | end | cand | 5 | Layout | 489 | 0 | 0.8 | 121.4 | - |
| 390 | end | cand | 5 | image decode task | 2631 | 0 | 9.0 | 352.4 | - |
| 390 | hero | orig | 5 | BeginMainFrame | 861 | 2 | 15.4 | 3690.9 | 15.3, 15.4 |
| 390 | hero | orig | 5 | Paint | 5258 | 0 | 2.3 | 497.5 | - |
| 390 | hero | orig | 5 | UpdateLayoutTree | 2012 | 0 | 4.8 | 1317.7 | - |
| 390 | hero | orig | 5 | Layout | 913 | 0 | 2.1 | 143.6 | - |
| 390 | hero | orig | 5 | image decode task | 573 | 10 | 53.4 | 754.5 | 30.8, 31.2, 31.2, 31.3, 33.6, 51.8, 52.6, 52.8, 53.1, 53.4 |
| 390 | hero | base | 5 | BeginMainFrame | 864 | 5 | 17.5 | 3754.8 | 15.2, 15.4, 16.1, 16.6, 17.5 |
| 390 | hero | base | 5 | Paint | 5021 | 0 | 2.8 | 484.1 | - |
| 390 | hero | base | 5 | UpdateLayoutTree | 1987 | 0 | 3.9 | 1064.6 | - |
| 390 | hero | base | 5 | Layout | 913 | 0 | 1.7 | 139.0 | - |
| 390 | hero | base | 5 | image decode task | 632 | 20 | 54.0 | 1058.8 | 30.9, 31.0, 31.1, 31.2, 31.3, 31.4, 31.4, 31.7, 31.8, 31.8, 33.7, 33.8, 33.8, 34.4, 34.4, 51.8, 52.0, 53.1, 53.4, 54.0 |
| 390 | hero | aa | 5 | BeginMainFrame | 850 | 5 | 19.4 | 3700.1 | 16.7, 16.9, 17.0, 17.1, 19.4 |
| 390 | hero | aa | 5 | Paint | 4992 | 0 | 3.7 | 477.7 | - |
| 390 | hero | aa | 5 | UpdateLayoutTree | 1972 | 0 | 4.0 | 1052.8 | - |
| 390 | hero | aa | 5 | Layout | 913 | 0 | 1.7 | 141.7 | - |
| 390 | hero | aa | 5 | image decode task | 602 | 20 | 53.0 | 1069.2 | 31.0, 31.2, 31.2, 31.4, 31.6, 31.6, 31.7, 31.8, 32.1, 32.6, 33.7, 34.0, 34.0, 34.1, 39.0, 52.1, 52.1, 52.2, 52.2, 53.0 |
| 390 | hero | cand | 5 | BeginMainFrame | 851 | 4 | 19.6 | 3868.1 | 16.7, 16.8, 17.0, 19.6 |
| 390 | hero | cand | 5 | Paint | 5001 | 0 | 2.8 | 497.0 | - |
| 390 | hero | cand | 5 | UpdateLayoutTree | 1975 | 0 | 4.0 | 1095.0 | - |
| 390 | hero | cand | 5 | Layout | 911 | 0 | 2.3 | 145.6 | - |
| 390 | hero | cand | 5 | image decode task | 590 | 21 | 53.0 | 1066.1 | 15.5, 31.0, 31.3, 31.3, 31.3, 31.3, 31.6, 31.7, 32.0, 32.4, 32.7, 33.7, 33.8, 33.8, 33.9, 34.1, 51.7, 52.4, 52.6, 52.7, 53.0 |
