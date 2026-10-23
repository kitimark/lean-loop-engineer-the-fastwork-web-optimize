Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39924675073:leg, 1280px, window hero** (CPU throttle 1x, candidate default, A/A spread 1.31 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 2.94 | 0.64 | 1 of 7 | 0,1,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 83.3 |
| base | 7 | 1086 | 3.77 | 1.31 | 1 of 7 | 0,1,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 83.3 |
| aa | 7 | 1085 | 3.68 | 0.65 | 1 of 7 | 0,0,0,0,0,0,1 | 16.7 | 33.4 | 50.0 | 83.3 |
| cand | 7 | 1085 | 3.87 | 1.29 | 1 of 7 | 0,0,0,1,0,0,0 | 16.7 | 33.4 | 50.0 | 83.3 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924675073:leg, 1280px, window end** (CPU throttle 1x, candidate default, A/A spread 6.04 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 525 | 13.33 | 5.49 | 7 of 7 | 4,3,3,3,3,2,2 | 33.2 | 50.1 | 66.8 | 116.7 |
| base | 7 | 536 | 15.48 | 5.53 | 7 of 7 | 5,3,3,3,2,2,2 | 16.8 | 50.1 | 66.7 | 116.6 |
| aa | 7 | 536 | 14.55 | 6.04 | 7 of 7 | 3,1,3,3,3,3,3 | 16.8 | 50.0 | 66.8 | 100.0 |
| cand | 7 | 526 | 15.01 | 6.16 | 7 of 7 | 1,4,3,3,2,2,4 | 33.2 | 50.1 | 66.7 | 100.0 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 2.15 | 6.04 |
| 1280 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.47 | 6.04 |
| 1280 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 1.68 | 6.04 |
| 1280 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.83 | 1.31 |
| 1280 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.10 | 1.31 |
| 1280 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.93 | 1.31 |

Samples: 39924675073:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39924675073:leg | 1280 | hero | orig | 7 | 1 | 83.3 | 882 | 1 |
| 39924675073:leg | 1280 | hero | base | 7 | 1 | 83.3 | 840 | 1 |
| 39924675073:leg | 1280 | hero | aa | 7 | 1 | 83.3 | 840 | 1 |
| 39924675073:leg | 1280 | hero | cand | 7 | 1 | 83.3 | 966 | 1 |
| 39924675073:leg | 1280 | end | orig | 7 | 20 | 66.7 | 8269 | 7 |
| 39924675073:leg | 1280 | end | base | 7 | 20 | 66.7 | 8269 | 7 |
| 39924675073:leg | 1280 | end | aa | 7 | 19 | 66.7 | 8269 | 7 |
| 39924675073:leg | 1280 | end | cand | 7 | 19 | 66.7 | 8269 | 7 |

### Frames of the page's compositor sink (traced reps, the renderer process of the page only; reported beside the verdict, never in it)

A frame is one `frame_sequence`; `dropped` = any of its pipeline reporters dropped, `dropped (all)` = every reporter dropped, `presented` = the rest with a presented reporter.

| width | window | arm | traced reps | runs | frames | presented | dropped | dropped % | dropped (all) | dropped (all) % | rAF frames in the same reps | presented p95 ms (median of reps) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | 5 | 1 | 643 | 369 | 274 | 42.6 | 274 | 42.6 | 358 | 183.4 |
| 1280 | end | base | 5 | 1 | 654 | 382 | 272 | 41.6 | 272 | 41.6 | 371 | 154.7 |
| 1280 | end | aa | 5 | 1 | 647 | 373 | 274 | 42.3 | 274 | 42.3 | 362 | 158.4 |
| 1280 | end | cand | 5 | 1 | 651 | 380 | 271 | 41.6 | 271 | 41.6 | 369 | 163.1 |
| 1280 | hero | orig | 5 | 1 | 972 | 761 | 211 | 21.7 | 202 | 20.8 | 775 | 76.0 |
| 1280 | hero | base | 5 | 1 | 971 | 760 | 211 | 21.7 | 202 | 20.8 | 776 | 75.2 |
| 1280 | hero | aa | 5 | 1 | 979 | 766 | 213 | 21.8 | 203 | 20.7 | 775 | 76.6 |
| 1280 | hero | cand | 5 | 1 | 973 | 761 | 212 | 21.8 | 202 | 20.8 | 776 | 67.3 |

### Fixed slow-event names of the traced reps (page renderer process; every row is always listed, n = 0 means the event never ran; long = 15 ms or more)

| width | window | arm | traced reps | event | events | long | longest ms | total ms | long durations ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | 5 | BeginMainFrame | 363 | 15 | 50.9 | 2348.8 | 16.8, 17.0, 18.6, 18.6, 18.8, 19.1, 19.7, 19.8, 19.9, 20.2, 20.7, 27.4, 36.8, 44.1, 50.9 |
| 1280 | end | orig | 5 | Paint | 4441 | 0 | 4.4 | 608.3 | - |
| 1280 | end | orig | 5 | UpdateLayoutTree | 556 | 0 | 11.2 | 811.1 | - |
| 1280 | end | orig | 5 | Layout | 400 | 0 | 0.4 | 86.2 | - |
| 1280 | end | orig | 5 | image decode task | 2672 | 0 | 13.2 | 1747.6 | - |
| 1280 | end | base | 5 | BeginMainFrame | 376 | 4 | 25.3 | 2409.6 | 16.2, 17.2, 23.8, 25.3 |
| 1280 | end | base | 5 | Paint | 4590 | 0 | 3.6 | 640.8 | - |
| 1280 | end | base | 5 | UpdateLayoutTree | 580 | 0 | 9.0 | 685.3 | - |
| 1280 | end | base | 5 | Layout | 411 | 0 | 0.9 | 96.0 | - |
| 1280 | end | base | 5 | image decode task | 2632 | 0 | 9.0 | 1731.2 | - |
| 1280 | end | aa | 5 | BeginMainFrame | 367 | 7 | 56.4 | 2416.7 | 15.2, 15.2, 16.0, 16.8, 18.9, 42.0, 56.4 |
| 1280 | end | aa | 5 | Paint | 4538 | 0 | 3.4 | 641.5 | - |
| 1280 | end | aa | 5 | UpdateLayoutTree | 564 | 0 | 8.1 | 670.7 | - |
| 1280 | end | aa | 5 | Layout | 401 | 0 | 1.0 | 94.1 | - |
| 1280 | end | aa | 5 | image decode task | 2612 | 0 | 12.4 | 1780.2 | - |
| 1280 | end | cand | 5 | BeginMainFrame | 374 | 5 | 53.8 | 2438.9 | 19.4, 19.5, 20.3, 45.3, 53.8 |
| 1280 | end | cand | 5 | Paint | 4536 | 0 | 3.6 | 628.4 | - |
| 1280 | end | cand | 5 | UpdateLayoutTree | 575 | 0 | 6.3 | 659.1 | - |
| 1280 | end | cand | 5 | Layout | 410 | 0 | 1.0 | 95.3 | - |
| 1280 | end | cand | 5 | image decode task | 2578 | 0 | 14.9 | 1745.7 | - |
| 1280 | hero | orig | 5 | BeginMainFrame | 780 | 0 | 11.7 | 2910.5 | - |
| 1280 | hero | orig | 5 | Paint | 2148 | 0 | 2.4 | 277.9 | - |
| 1280 | hero | orig | 5 | UpdateLayoutTree | 1877 | 0 | 5.6 | 1208.0 | - |
| 1280 | hero | orig | 5 | Layout | 493 | 0 | 0.3 | 90.6 | - |
| 1280 | hero | orig | 5 | image decode task | 238 | 0 | 13.5 | 342.2 | - |
| 1280 | hero | base | 5 | BeginMainFrame | 781 | 0 | 11.7 | 3097.9 | - |
| 1280 | hero | base | 5 | Paint | 2136 | 0 | 2.4 | 300.7 | - |
| 1280 | hero | base | 5 | UpdateLayoutTree | 1875 | 0 | 4.3 | 966.2 | - |
| 1280 | hero | base | 5 | Layout | 489 | 0 | 0.8 | 97.0 | - |
| 1280 | hero | base | 5 | image decode task | 181 | 0 | 11.2 | 303.9 | - |
| 1280 | hero | aa | 5 | BeginMainFrame | 780 | 0 | 11.7 | 3104.7 | - |
| 1280 | hero | aa | 5 | Paint | 2142 | 0 | 2.5 | 300.1 | - |
| 1280 | hero | aa | 5 | UpdateLayoutTree | 1875 | 0 | 4.8 | 972.0 | - |
| 1280 | hero | aa | 5 | Layout | 489 | 0 | 0.7 | 95.7 | - |
| 1280 | hero | aa | 5 | image decode task | 174 | 0 | 11.0 | 303.7 | - |
| 1280 | hero | cand | 5 | BeginMainFrame | 781 | 0 | 11.4 | 3099.8 | - |
| 1280 | hero | cand | 5 | Paint | 2143 | 0 | 2.4 | 300.1 | - |
| 1280 | hero | cand | 5 | UpdateLayoutTree | 1876 | 0 | 4.3 | 964.5 | - |
| 1280 | hero | cand | 5 | Layout | 493 | 0 | 0.7 | 96.9 | - |
| 1280 | hero | cand | 5 | image decode task | 181 | 0 | 11.6 | 307.2 | - |
