Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39924675073:leg, 1280px, window hero** (CPU throttle 1x, candidate default, A/A spread 1.29 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 2.85 | 0.64 | 1 of 7 | 1,0,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 83.4 |
| base | 7 | 1085 | 3.41 | 1.29 | 1 of 7 | 0,0,0,1,0,0,0 | 16.7 | 33.4 | 50.0 | 83.3 |
| aa | 7 | 1085 | 3.41 | 0.65 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 50.1 |
| cand | 7 | 1085 | 3.59 | 1.94 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 50.1 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924675073:leg, 1280px, window end** (CPU throttle 1x, candidate default, A/A spread 4.47 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 541 | 14.04 | 7.56 | 7 of 7 | 2,2,2,2,2,2,2 | 16.7 | 50.0 | 66.7 | 116.8 |
| base | 7 | 549 | 13.47 | 4.47 | 7 of 7 | 2,4,4,3,4,2,1 | 16.7 | 50.0 | 66.7 | 83.4 |
| aa | 7 | 550 | 13.45 | 1.97 | 7 of 7 | 2,1,2,4,4,2,2 | 16.7 | 50.0 | 66.7 | 116.7 |
| cand | 7 | 540 | 14.62 | 5.35 | 7 of 7 | 4,2,3,3,4,3,1 | 16.7 | 50.0 | 66.7 | 116.8 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.57 | 4.47 |
| 1280 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 1.15 | 4.47 |
| 1280 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.58 | 4.47 |
| 1280 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.56 | 1.29 |
| 1280 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.18 | 1.29 |
| 1280 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.74 | 1.29 |

Samples: 39924675073:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39924675073:leg | 1280 | hero | orig | 7 | 1 | 83.4 | 840 | 1 |
| 39924675073:leg | 1280 | hero | base | 7 | 1 | 83.3 | 840 | 1 |
| 39924675073:leg | 1280 | end | orig | 7 | 14 | 66.6 | 8269 | 7 |
| 39924675073:leg | 1280 | end | base | 7 | 20 | 66.7 | 8269 | 7 |
| 39924675073:leg | 1280 | end | aa | 7 | 17 | 66.7 | 8269 | 7 |
| 39924675073:leg | 1280 | end | cand | 7 | 20 | 66.7 | 8269 | 7 |

### Frames of the page's compositor sink (traced reps, the renderer process of the page only; reported beside the verdict, never in it)

A frame is one `frame_sequence`; `dropped` = any of its pipeline reporters dropped, `dropped (all)` = every reporter dropped, `presented` = the rest with a presented reporter.

| width | window | arm | traced reps | runs | frames | presented | dropped | dropped % | dropped (all) | dropped (all) % | rAF frames in the same reps | presented p95 ms (median of reps) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | 5 | 1 | 640 | 380 | 260 | 40.6 | 260 | 40.6 | 373 | 182.7 |
| 1280 | end | base | 5 | 1 | 652 | 390 | 262 | 40.2 | 262 | 40.2 | 372 | 149.5 |
| 1280 | end | aa | 5 | 1 | 654 | 391 | 263 | 40.2 | 263 | 40.2 | 373 | 183.5 |
| 1280 | end | cand | 5 | 1 | 647 | 382 | 265 | 41.0 | 265 | 41.0 | 373 | 157.7 |
| 1280 | hero | orig | 5 | 1 | 963 | 759 | 204 | 21.2 | 195 | 20.2 | 775 | 73.7 |
| 1280 | hero | base | 5 | 1 | 966 | 762 | 204 | 21.1 | 194 | 20.1 | 775 | 76.8 |
| 1280 | hero | aa | 5 | 1 | 968 | 761 | 207 | 21.4 | 198 | 20.5 | 775 | 78.3 |
| 1280 | hero | cand | 5 | 1 | 964 | 761 | 203 | 21.1 | 193 | 20.0 | 776 | 77.1 |

### Fixed slow-event names of the traced reps (page renderer process; every row is always listed, n = 0 means the event never ran; long = 15 ms or more)

| width | window | arm | traced reps | event | events | long | longest ms | total ms | long durations ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | 5 | BeginMainFrame | 378 | 10 | 27.4 | 2213.9 | 15.8, 16.4, 16.4, 17.5, 17.7, 18.4, 23.8, 24.1, 25.2, 27.4 |
| 1280 | end | orig | 5 | Paint | 4501 | 0 | 3.9 | 577.5 | - |
| 1280 | end | orig | 5 | UpdateLayoutTree | 582 | 0 | 9.9 | 793.6 | - |
| 1280 | end | orig | 5 | Layout | 421 | 0 | 0.4 | 80.1 | - |
| 1280 | end | orig | 5 | image decode task | 2720 | 1 | 15.7 | 1863.0 | 15.7 |
| 1280 | end | base | 5 | BeginMainFrame | 377 | 3 | 19.1 | 2322.1 | 15.7, 18.9, 19.1 |
| 1280 | end | base | 5 | Paint | 4485 | 0 | 3.2 | 617.5 | - |
| 1280 | end | base | 5 | UpdateLayoutTree | 580 | 0 | 6.2 | 647.2 | - |
| 1280 | end | base | 5 | Layout | 418 | 0 | 0.9 | 90.8 | - |
| 1280 | end | base | 5 | image decode task | 2609 | 2 | 18.7 | 1844.3 | 15.8, 18.7 |
| 1280 | end | aa | 5 | BeginMainFrame | 378 | 20 | 60.2 | 2719.2 | 15.5, 16.1, 16.2, 16.6, 16.9, 17.3, 17.7, 18.5, 18.8, 18.9, 19.0, 19.3, 19.5, 20.1, 23.3, 24.0, 24.2, 52.0, 52.9, 60.2 |
| 1280 | end | aa | 5 | Paint | 4491 | 0 | 3.5 | 630.3 | - |
| 1280 | end | aa | 5 | UpdateLayoutTree | 576 | 0 | 8.8 | 680.7 | - |
| 1280 | end | aa | 5 | Layout | 407 | 0 | 1.0 | 91.1 | - |
| 1280 | end | aa | 5 | image decode task | 2698 | 0 | 12.6 | 1820.6 | - |
| 1280 | end | cand | 5 | BeginMainFrame | 378 | 9 | 49.1 | 2486.5 | 16.7, 17.0, 17.2, 17.9, 18.4, 20.2, 20.5, 20.6, 49.1 |
| 1280 | end | cand | 5 | Paint | 4544 | 0 | 4.2 | 626.7 | - |
| 1280 | end | cand | 5 | UpdateLayoutTree | 580 | 0 | 5.8 | 655.9 | - |
| 1280 | end | cand | 5 | Layout | 414 | 0 | 1.0 | 93.0 | - |
| 1280 | end | cand | 5 | image decode task | 2735 | 0 | 10.6 | 1846.9 | - |
| 1280 | hero | orig | 5 | BeginMainFrame | 780 | 0 | 11.9 | 2835.8 | - |
| 1280 | hero | orig | 5 | Paint | 2149 | 0 | 2.5 | 268.3 | - |
| 1280 | hero | orig | 5 | UpdateLayoutTree | 1877 | 0 | 5.0 | 1174.6 | - |
| 1280 | hero | orig | 5 | Layout | 498 | 0 | 0.3 | 88.5 | - |
| 1280 | hero | orig | 5 | image decode task | 238 | 0 | 14.9 | 336.5 | - |
| 1280 | hero | base | 5 | BeginMainFrame | 780 | 0 | 11.3 | 2996.7 | - |
| 1280 | hero | base | 5 | Paint | 2138 | 0 | 2.4 | 292.3 | - |
| 1280 | hero | base | 5 | UpdateLayoutTree | 1872 | 0 | 4.0 | 945.4 | - |
| 1280 | hero | base | 5 | Layout | 489 | 0 | 1.5 | 94.3 | - |
| 1280 | hero | base | 5 | image decode task | 178 | 0 | 10.8 | 300.9 | - |
| 1280 | hero | aa | 5 | BeginMainFrame | 780 | 0 | 12.4 | 2990.7 | - |
| 1280 | hero | aa | 5 | Paint | 2142 | 0 | 2.4 | 293.2 | - |
| 1280 | hero | aa | 5 | UpdateLayoutTree | 1873 | 0 | 4.0 | 929.3 | - |
| 1280 | hero | aa | 5 | Layout | 488 | 0 | 0.7 | 93.5 | - |
| 1280 | hero | aa | 5 | image decode task | 179 | 0 | 10.8 | 303.5 | - |
| 1280 | hero | cand | 5 | BeginMainFrame | 781 | 0 | 11.6 | 3055.4 | - |
| 1280 | hero | cand | 5 | Paint | 2141 | 0 | 2.5 | 298.8 | - |
| 1280 | hero | cand | 5 | UpdateLayoutTree | 1878 | 0 | 4.1 | 966.4 | - |
| 1280 | hero | cand | 5 | Layout | 492 | 0 | 0.7 | 93.4 | - |
| 1280 | hero | cand | 5 | image decode task | 186 | 0 | 10.8 | 301.0 | - |
