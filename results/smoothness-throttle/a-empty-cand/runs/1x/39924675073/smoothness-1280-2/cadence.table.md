Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39924675073:leg, 1280px, window hero** (CPU throttle 1x, candidate default, A/A spread 1.29 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 4.51 | 1.93 | 1 of 7 | 0,0,0,0,1,0,0 | 16.7 | 33.4 | 50.0 | 83.2 |
| base | 7 | 1087 | 4.87 | 0.68 | 2 of 7 | 0,0,0,0,0,1,1 | 16.7 | 33.4 | 50.1 | 83.4 |
| aa | 7 | 1085 | 5.16 | 1.29 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 49.9 | 50.0 | 50.1 |
| cand | 7 | 1085 | 4.79 | 0.65 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.4 | 50.1 | 50.1 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924675073:leg, 1280px, window end** (CPU throttle 1x, candidate default, A/A spread 4.95 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 502 | 17.52 | 7.14 | 7 of 7 | 6,4,3,3,4,3,4 | 33.3 | 66.6 | 66.8 | 116.7 |
| base | 7 | 506 | 16.40 | 3.51 | 7 of 7 | 5,5,3,5,5,4,3 | 33.3 | 66.6 | 99.9 | 116.7 |
| aa | 7 | 505 | 17.42 | 4.95 | 7 of 7 | 5,3,3,4,4,5,4 | 33.3 | 66.6 | 66.8 | 116.8 |
| cand | 7 | 506 | 18.37 | 5.85 | 7 of 7 | 4,4,4,4,4,2,4 | 33.3 | 66.6 | 66.8 | 116.6 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -1.12 | 4.95 |
| 1280 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 1.97 | 4.95 |
| 1280 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.85 | 4.95 |
| 1280 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.36 | 1.29 |
| 1280 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.08 | 1.29 |
| 1280 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.28 | 1.29 |

Samples: 39924675073:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39924675073:leg | 1280 | hero | orig | 7 | 1 | 83.2 | 798 | 1 |
| 39924675073:leg | 1280 | hero | base | 7 | 2 | 83.3 | 924 | 2 |
| 39924675073:leg | 1280 | end | orig | 7 | 27 | 66.7 | 8269 | 7 |
| 39924675073:leg | 1280 | end | base | 7 | 30 | 66.7 | 8269 | 7 |
| 39924675073:leg | 1280 | end | aa | 7 | 28 | 66.7 | 8269 | 7 |
| 39924675073:leg | 1280 | end | cand | 7 | 26 | 66.7 | 8269 | 7 |

### Frames of the page's compositor sink (traced reps, the renderer process of the page only; reported beside the verdict, never in it)

A frame is one `frame_sequence`; `dropped` = any of its pipeline reporters dropped, `dropped (all)` = every reporter dropped, `presented` = the rest with a presented reporter.

| width | window | arm | traced reps | runs | frames | presented | dropped | dropped % | dropped (all) | dropped (all) % | rAF frames in the same reps | presented p95 ms (median of reps) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | 5 | 1 | 643 | 358 | 285 | 44.3 | 285 | 44.3 | 343 | 184.3 |
| 1280 | end | base | 5 | 1 | 650 | 361 | 289 | 44.5 | 289 | 44.5 | 346 | 187.4 |
| 1280 | end | aa | 5 | 1 | 655 | 363 | 292 | 44.6 | 292 | 44.6 | 349 | 181.4 |
| 1280 | end | cand | 5 | 1 | 652 | 360 | 292 | 44.8 | 292 | 44.8 | 347 | 157.2 |
| 1280 | hero | orig | 5 | 1 | 978 | 757 | 221 | 22.6 | 211 | 21.6 | 775 | 74.1 |
| 1280 | hero | base | 5 | 1 | 981 | 763 | 218 | 22.2 | 208 | 21.2 | 775 | 91.2 |
| 1280 | hero | aa | 5 | 1 | 991 | 763 | 228 | 23.0 | 218 | 22.0 | 776 | 68.1 |
| 1280 | hero | cand | 5 | 1 | 983 | 760 | 223 | 22.7 | 214 | 21.8 | 775 | 78.9 |

### Fixed slow-event names of the traced reps (page renderer process; every row is always listed, n = 0 means the event never ran; long = 15 ms or more)

| width | window | arm | traced reps | event | events | long | longest ms | total ms | long durations ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | 5 | BeginMainFrame | 348 | 8 | 45.4 | 2206.4 | 15.1, 15.2, 15.3, 15.8, 17.1, 26.1, 41.2, 45.4 |
| 1280 | end | orig | 5 | Paint | 4382 | 0 | 3.6 | 613.5 | - |
| 1280 | end | orig | 5 | UpdateLayoutTree | 535 | 0 | 9.5 | 822.0 | - |
| 1280 | end | orig | 5 | Layout | 385 | 0 | 0.7 | 91.7 | - |
| 1280 | end | orig | 5 | image decode task | 2527 | 1 | 17.5 | 1745.5 | 17.5 |
| 1280 | end | base | 5 | BeginMainFrame | 351 | 10 | 47.1 | 2451.7 | 15.4, 16.0, 16.1, 16.5, 16.7, 17.1, 19.3, 20.4, 35.4, 47.1 |
| 1280 | end | base | 5 | Paint | 4344 | 0 | 4.1 | 636.9 | - |
| 1280 | end | base | 5 | UpdateLayoutTree | 539 | 0 | 7.7 | 666.7 | - |
| 1280 | end | base | 5 | Layout | 374 | 0 | 1.2 | 92.5 | - |
| 1280 | end | base | 5 | image decode task | 2500 | 1 | 15.2 | 1757.7 | 15.2 |
| 1280 | end | aa | 5 | BeginMainFrame | 355 | 8 | 50.7 | 2525.4 | 17.1, 17.6, 18.0, 19.0, 19.3, 23.4, 42.9, 50.7 |
| 1280 | end | aa | 5 | Paint | 4456 | 0 | 3.7 | 646.3 | - |
| 1280 | end | aa | 5 | UpdateLayoutTree | 544 | 0 | 9.0 | 697.1 | - |
| 1280 | end | aa | 5 | Layout | 385 | 0 | 1.8 | 101.1 | - |
| 1280 | end | aa | 5 | image decode task | 2506 | 1 | 21.0 | 1795.5 | 21.0 |
| 1280 | end | cand | 5 | BeginMainFrame | 352 | 8 | 33.7 | 2459.5 | 15.1, 15.3, 16.1, 17.1, 19.6, 21.1, 29.1, 33.7 |
| 1280 | end | cand | 5 | Paint | 4473 | 0 | 3.6 | 666.1 | - |
| 1280 | end | cand | 5 | UpdateLayoutTree | 540 | 0 | 9.6 | 698.9 | - |
| 1280 | end | cand | 5 | Layout | 380 | 0 | 1.1 | 96.6 | - |
| 1280 | end | cand | 5 | image decode task | 2567 | 0 | 14.2 | 1778.8 | - |
| 1280 | hero | orig | 5 | BeginMainFrame | 780 | 0 | 12.6 | 3061.7 | - |
| 1280 | hero | orig | 5 | Paint | 2166 | 0 | 2.6 | 293.9 | - |
| 1280 | hero | orig | 5 | UpdateLayoutTree | 1877 | 0 | 5.9 | 1250.8 | - |
| 1280 | hero | orig | 5 | Layout | 497 | 0 | 0.3 | 93.8 | - |
| 1280 | hero | orig | 5 | image decode task | 223 | 0 | 14.5 | 347.8 | - |
| 1280 | hero | base | 5 | BeginMainFrame | 780 | 0 | 12.7 | 3215.4 | - |
| 1280 | hero | base | 5 | Paint | 2147 | 0 | 2.6 | 314.3 | - |
| 1280 | hero | base | 5 | UpdateLayoutTree | 1878 | 0 | 4.8 | 1003.9 | - |
| 1280 | hero | base | 5 | Layout | 491 | 0 | 0.7 | 98.2 | - |
| 1280 | hero | base | 5 | image decode task | 175 | 0 | 11.4 | 311.9 | - |
| 1280 | hero | aa | 5 | BeginMainFrame | 781 | 0 | 12.8 | 3388.4 | - |
| 1280 | hero | aa | 5 | Paint | 2157 | 0 | 2.7 | 321.4 | - |
| 1280 | hero | aa | 5 | UpdateLayoutTree | 1872 | 0 | 4.7 | 1050.3 | - |
| 1280 | hero | aa | 5 | Layout | 495 | 0 | 0.7 | 105.0 | - |
| 1280 | hero | aa | 5 | image decode task | 174 | 0 | 11.9 | 318.8 | - |
| 1280 | hero | cand | 5 | BeginMainFrame | 780 | 0 | 12.1 | 3339.4 | - |
| 1280 | hero | cand | 5 | Paint | 2152 | 0 | 2.6 | 316.3 | - |
| 1280 | hero | cand | 5 | UpdateLayoutTree | 1875 | 0 | 4.4 | 1031.8 | - |
| 1280 | hero | cand | 5 | Layout | 491 | 0 | 0.7 | 101.1 | - |
| 1280 | hero | cand | 5 | image decode task | 180 | 0 | 11.3 | 311.1 | - |
