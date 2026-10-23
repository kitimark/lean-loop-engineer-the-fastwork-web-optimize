Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39927164863:leg, 1280px, window hero** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 1.29 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 5.25 | 1.29 | 2 of 7 | 0,1,0,1,0,0,0 | 16.7 | 49.9 | 50.0 | 83.4 |
| base | 7 | 1085 | 5.43 | 1.29 | 5 of 7 | 1,1,1,1,0,0,2 | 16.7 | 49.9 | 50.1 | 83.4 |
| aa | 7 | 1085 | 5.71 | 1.29 | 2 of 7 | 1,0,0,0,0,0,1 | 16.7 | 49.9 | 50.1 | 83.3 |
| cand | 7 | 1085 | 5.34 | 0.64 | 3 of 7 | 0,1,1,1,0,0,0 | 16.7 | 49.9 | 50.0 | 83.3 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927164863:leg, 1280px, window end** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 8.97 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 473 | 19.66 | 5.56 | 7 of 7 | 5,6,5,4,3,3,4 | 33.3 | 66.6 | 83.4 | 116.7 |
| base | 7 | 489 | 18.60 | 8.97 | 7 of 7 | 3,3,5,3,3,4,5 | 33.3 | 66.6 | 83.3 | 116.7 |
| aa | 7 | 485 | 20.82 | 4.95 | 7 of 7 | 2,3,5,4,2,4,3 | 33.3 | 50.1 | 66.7 | 66.7 |
| cand | 7 | 487 | 20.12 | 9.01 | 7 of 7 | 4,4,6,4,3,2,3 | 33.3 | 66.6 | 66.7 | 100.0 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -1.06 | 8.97 |
| 1280 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 1.52 | 8.97 |
| 1280 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.46 | 8.97 |
| 1280 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.18 | 1.29 |
| 1280 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.09 | 1.29 |
| 1280 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.09 | 1.29 |

Samples: 39927164863:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39927164863:leg | 1280 | hero | orig | 7 | 2 | 83.3 | 840 | 2 |
| 39927164863:leg | 1280 | hero | base | 7 | 6 | 83.3 | 882 | 5 |
| 39927164863:leg | 1280 | hero | aa | 7 | 2 | 83.3 | 966 | 2 |
| 39927164863:leg | 1280 | hero | cand | 7 | 3 | 83.3 | 966 | 3 |
| 39927164863:leg | 1280 | end | orig | 7 | 30 | 66.7 | 8269 | 7 |
| 39927164863:leg | 1280 | end | base | 7 | 26 | 66.7 | 8269 | 7 |
| 39927164863:leg | 1280 | end | aa | 7 | 23 | 66.7 | 8269 | 7 |
| 39927164863:leg | 1280 | end | cand | 7 | 26 | 66.7 | 8269 | 7 |

### Frames of the page's compositor sink (traced reps, the renderer process of the page only; reported beside the verdict, never in it)

A frame is one `frame_sequence`; `dropped` = any of its pipeline reporters dropped, `dropped (all)` = every reporter dropped, `presented` = the rest with a presented reporter.

| width | window | arm | traced reps | runs | frames | presented | dropped | dropped % | dropped (all) | dropped (all) % | rAF frames in the same reps | presented p95 ms (median of reps) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | 5 | 1 | 650 | 348 | 302 | 46.5 | 301 | 46.3 | 336 | 182.8 |
| 1280 | end | base | 5 | 1 | 647 | 344 | 303 | 46.8 | 303 | 46.8 | 336 | 165.1 |
| 1280 | end | aa | 5 | 1 | 656 | 346 | 310 | 47.3 | 310 | 47.3 | 333 | 208.8 |
| 1280 | end | cand | 5 | 1 | 655 | 354 | 301 | 46.0 | 301 | 46.0 | 345 | 164.0 |
| 1280 | hero | orig | 5 | 1 | 996 | 761 | 235 | 23.6 | 225 | 22.6 | 775 | 81.6 |
| 1280 | hero | base | 5 | 1 | 997 | 763 | 234 | 23.5 | 224 | 22.5 | 775 | 69.0 |
| 1280 | hero | aa | 5 | 1 | 1002 | 767 | 235 | 23.5 | 225 | 22.5 | 775 | 81.7 |
| 1280 | hero | cand | 5 | 1 | 1004 | 769 | 235 | 23.4 | 227 | 22.6 | 775 | 81.2 |

### Fixed slow-event names of the traced reps (page renderer process; every row is always listed, n = 0 means the event never ran; long = 15 ms or more)

| width | window | arm | traced reps | event | events | long | longest ms | total ms | long durations ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | 5 | BeginMainFrame | 341 | 12 | 52.0 | 2415.7 | 15.1, 16.4, 16.7, 17.7, 18.8, 19.5, 20.0, 20.8, 27.2, 43.5, 49.1, 52.0 |
| 1280 | end | orig | 5 | Paint | 4385 | 0 | 3.7 | 645.8 | - |
| 1280 | end | orig | 5 | UpdateLayoutTree | 523 | 0 | 11.0 | 856.4 | - |
| 1280 | end | orig | 5 | Layout | 377 | 0 | 2.8 | 113.3 | - |
| 1280 | end | orig | 5 | image decode task | 2506 | 0 | 9.3 | 1837.4 | - |
| 1280 | end | base | 5 | BeginMainFrame | 341 | 7 | 48.7 | 2556.7 | 15.2, 15.4, 15.9, 16.0, 19.7, 41.1, 48.7 |
| 1280 | end | base | 5 | Paint | 4372 | 0 | 3.9 | 659.7 | - |
| 1280 | end | base | 5 | UpdateLayoutTree | 526 | 0 | 6.5 | 704.8 | - |
| 1280 | end | base | 5 | Layout | 373 | 0 | 3.1 | 111.3 | - |
| 1280 | end | base | 5 | image decode task | 2459 | 2 | 18.3 | 1798.3 | 15.7, 18.3 |
| 1280 | end | aa | 5 | BeginMainFrame | 339 | 17 | 50.5 | 2627.6 | 15.0, 15.1, 15.2, 15.2, 15.3, 15.6, 15.6, 16.1, 16.1, 16.3, 16.4, 18.3, 20.9, 21.7, 45.3, 49.9, 50.5 |
| 1280 | end | aa | 5 | Paint | 4367 | 0 | 3.9 | 671.9 | - |
| 1280 | end | aa | 5 | UpdateLayoutTree | 522 | 0 | 6.8 | 717.9 | - |
| 1280 | end | aa | 5 | Layout | 363 | 0 | 1.0 | 107.0 | - |
| 1280 | end | aa | 5 | image decode task | 2405 | 1 | 16.5 | 1758.2 | 16.5 |
| 1280 | end | cand | 5 | BeginMainFrame | 352 | 9 | 45.4 | 2556.9 | 15.4, 16.0, 16.8, 17.9, 20.3, 22.3, 24.5, 43.5, 45.4 |
| 1280 | end | cand | 5 | Paint | 4313 | 0 | 3.7 | 691.5 | - |
| 1280 | end | cand | 5 | UpdateLayoutTree | 546 | 0 | 7.7 | 734.7 | - |
| 1280 | end | cand | 5 | Layout | 272 | 0 | 1.9 | 91.4 | - |
| 1280 | end | cand | 5 | image decode task | 2547 | 1 | 20.3 | 1887.4 | 20.3 |
| 1280 | hero | orig | 5 | BeginMainFrame | 780 | 0 | 13.8 | 3468.6 | - |
| 1280 | hero | orig | 5 | Paint | 2184 | 0 | 2.6 | 315.0 | - |
| 1280 | hero | orig | 5 | UpdateLayoutTree | 1878 | 0 | 5.9 | 1395.9 | - |
| 1280 | hero | orig | 5 | Layout | 492 | 0 | 0.7 | 106.2 | - |
| 1280 | hero | orig | 5 | image decode task | 200 | 0 | 11.5 | 354.4 | - |
| 1280 | hero | base | 5 | BeginMainFrame | 781 | 0 | 13.3 | 3593.2 | - |
| 1280 | hero | base | 5 | Paint | 2166 | 0 | 2.6 | 334.5 | - |
| 1280 | hero | base | 5 | UpdateLayoutTree | 1877 | 0 | 4.7 | 1091.6 | - |
| 1280 | hero | base | 5 | Layout | 491 | 0 | 0.8 | 113.2 | - |
| 1280 | hero | base | 5 | image decode task | 161 | 0 | 11.7 | 326.1 | - |
| 1280 | hero | aa | 5 | BeginMainFrame | 780 | 0 | 13.4 | 3597.5 | - |
| 1280 | hero | aa | 5 | Paint | 2157 | 0 | 2.7 | 333.9 | - |
| 1280 | hero | aa | 5 | UpdateLayoutTree | 1878 | 0 | 4.6 | 1101.9 | - |
| 1280 | hero | aa | 5 | Layout | 486 | 0 | 0.8 | 112.3 | - |
| 1280 | hero | aa | 5 | image decode task | 164 | 0 | 11.4 | 327.7 | - |
| 1280 | hero | cand | 5 | BeginMainFrame | 780 | 0 | 13.3 | 3634.7 | - |
| 1280 | hero | cand | 5 | Paint | 2166 | 0 | 2.7 | 340.2 | - |
| 1280 | hero | cand | 5 | UpdateLayoutTree | 1873 | 0 | 4.4 | 1122.8 | - |
| 1280 | hero | cand | 5 | Layout | 488 | 0 | 0.8 | 116.9 | - |
| 1280 | hero | cand | 5 | image decode task | 158 | 0 | 11.6 | 335.4 | - |
