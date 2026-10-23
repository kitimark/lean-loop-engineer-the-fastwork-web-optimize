Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39927164863:leg, 1280px, window hero** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 1.29 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 4.42 | 1.93 | 1 of 7 | 1,0,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 66.7 |
| base | 7 | 1085 | 4.79 | 1.29 | 2 of 7 | 1,0,0,1,0,0,0 | 16.7 | 33.4 | 50.1 | 83.4 |
| aa | 7 | 1085 | 5.06 | 1.29 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 49.9 | 50.1 | 50.1 |
| cand | 7 | 1085 | 4.51 | 1.29 | 3 of 7 | 1,0,1,1,0,0,0 | 16.7 | 33.4 | 50.0 | 83.4 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927164863:leg, 1280px, window end** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 7.79 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 504 | 17.65 | 4.15 | 7 of 7 | 3,3,4,2,5,4,4 | 33.3 | 50.1 | 66.7 | 83.3 |
| base | 7 | 501 | 18.56 | 7.34 | 7 of 7 | 5,6,2,3,4,3,4 | 33.3 | 66.6 | 66.8 | 100.1 |
| aa | 7 | 510 | 17.84 | 7.79 | 7 of 7 | 4,3,3,3,5,2,3 | 33.3 | 50.1 | 66.7 | 116.7 |
| cand | 7 | 510 | 16.47 | 4.17 | 7 of 7 | 3,4,4,4,4,5,3 | 33.3 | 66.6 | 83.4 | 133.3 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.91 | 7.79 |
| 1280 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -2.09 | 7.79 |
| 1280 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -1.18 | 7.79 |
| 1280 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.37 | 1.29 |
| 1280 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.28 | 1.29 |
| 1280 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.09 | 1.29 |

Samples: 39927164863:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39927164863:leg | 1280 | hero | orig | 7 | 1 | 66.7 | 1008 | 1 |
| 39927164863:leg | 1280 | hero | base | 7 | 2 | 83.4 | 882 | 2 |
| 39927164863:leg | 1280 | hero | cand | 7 | 3 | 83.3 | 966 | 3 |
| 39927164863:leg | 1280 | end | orig | 7 | 25 | 66.7 | 8269 | 7 |
| 39927164863:leg | 1280 | end | base | 7 | 27 | 66.7 | 8269 | 7 |
| 39927164863:leg | 1280 | end | aa | 7 | 23 | 66.6 | 8269 | 7 |
| 39927164863:leg | 1280 | end | cand | 7 | 27 | 66.7 | 8269 | 7 |

### Frames of the page's compositor sink (traced reps, the renderer process of the page only; reported beside the verdict, never in it)

A frame is one `frame_sequence`; `dropped` = any of its pipeline reporters dropped, `dropped (all)` = every reporter dropped, `presented` = the rest with a presented reporter.

| width | window | arm | traced reps | runs | frames | presented | dropped | dropped % | dropped (all) | dropped (all) % | rAF frames in the same reps | presented p95 ms (median of reps) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | 5 | 1 | 646 | 361 | 285 | 44.1 | 285 | 44.1 | 351 | 178.0 |
| 1280 | end | base | 5 | 1 | 647 | 363 | 284 | 43.9 | 284 | 43.9 | 352 | 135.6 |
| 1280 | end | aa | 5 | 1 | 650 | 362 | 288 | 44.3 | 288 | 44.3 | 351 | 165.8 |
| 1280 | end | cand | 5 | 1 | 647 | 362 | 285 | 44.0 | 285 | 44.0 | 350 | 167.4 |
| 1280 | hero | orig | 5 | 1 | 979 | 760 | 219 | 22.4 | 209 | 21.3 | 775 | 77.7 |
| 1280 | hero | base | 5 | 1 | 980 | 761 | 219 | 22.3 | 210 | 21.4 | 775 | 76.0 |
| 1280 | hero | aa | 5 | 1 | 986 | 768 | 218 | 22.1 | 210 | 21.3 | 776 | 74.1 |
| 1280 | hero | cand | 5 | 1 | 983 | 762 | 221 | 22.5 | 211 | 21.5 | 775 | 76.6 |

### Fixed slow-event names of the traced reps (page renderer process; every row is always listed, n = 0 means the event never ran; long = 15 ms or more)

| width | window | arm | traced reps | event | events | long | longest ms | total ms | long durations ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | 5 | BeginMainFrame | 356 | 18 | 41.3 | 2379.6 | 16.1, 16.1, 16.8, 16.8, 17.2, 18.7, 18.9, 18.9, 19.1, 19.2, 19.4, 20.1, 20.2, 20.9, 23.2, 23.6, 24.3, 41.3 |
| 1280 | end | orig | 5 | Paint | 4433 | 0 | 3.6 | 631.8 | - |
| 1280 | end | orig | 5 | UpdateLayoutTree | 548 | 0 | 11.9 | 881.1 | - |
| 1280 | end | orig | 5 | Layout | 395 | 0 | 1.0 | 96.2 | - |
| 1280 | end | orig | 5 | image decode task | 2512 | 2 | 19.1 | 1766.1 | 15.7, 19.1 |
| 1280 | end | base | 5 | BeginMainFrame | 357 | 5 | 51.5 | 2537.4 | 15.4, 17.3, 23.4, 47.8, 51.5 |
| 1280 | end | base | 5 | Paint | 4462 | 0 | 3.7 | 666.4 | - |
| 1280 | end | base | 5 | UpdateLayoutTree | 553 | 0 | 8.2 | 691.8 | - |
| 1280 | end | base | 5 | Layout | 395 | 0 | 0.9 | 98.1 | - |
| 1280 | end | base | 5 | image decode task | 2630 | 0 | 10.8 | 1784.4 | - |
| 1280 | end | aa | 5 | BeginMainFrame | 357 | 7 | 54.9 | 2540.4 | 15.4, 16.3, 16.8, 17.6, 24.1, 51.6, 54.9 |
| 1280 | end | aa | 5 | Paint | 4483 | 0 | 3.6 | 688.9 | - |
| 1280 | end | aa | 5 | UpdateLayoutTree | 545 | 0 | 7.5 | 668.0 | - |
| 1280 | end | aa | 5 | Layout | 383 | 0 | 2.5 | 102.0 | - |
| 1280 | end | aa | 5 | image decode task | 2626 | 0 | 10.8 | 1795.3 | - |
| 1280 | end | cand | 5 | BeginMainFrame | 356 | 5 | 56.9 | 2411.5 | 15.4, 17.0, 51.1, 51.9, 56.9 |
| 1280 | end | cand | 5 | Paint | 4350 | 0 | 3.6 | 665.2 | - |
| 1280 | end | cand | 5 | UpdateLayoutTree | 548 | 0 | 6.8 | 643.9 | - |
| 1280 | end | cand | 5 | Layout | 273 | 0 | 1.3 | 80.8 | - |
| 1280 | end | cand | 5 | image decode task | 2544 | 0 | 9.3 | 1726.4 | - |
| 1280 | hero | orig | 5 | BeginMainFrame | 780 | 0 | 12.2 | 3182.8 | - |
| 1280 | hero | orig | 5 | Paint | 2165 | 0 | 2.5 | 300.8 | - |
| 1280 | hero | orig | 5 | UpdateLayoutTree | 1881 | 0 | 5.2 | 1273.8 | - |
| 1280 | hero | orig | 5 | Layout | 496 | 0 | 0.5 | 97.9 | - |
| 1280 | hero | orig | 5 | image decode task | 217 | 1 | 18.7 | 345.1 | 18.7 |
| 1280 | hero | base | 5 | BeginMainFrame | 780 | 0 | 12.3 | 3326.9 | - |
| 1280 | hero | base | 5 | Paint | 2148 | 0 | 2.6 | 321.1 | - |
| 1280 | hero | base | 5 | UpdateLayoutTree | 1874 | 0 | 4.1 | 1016.5 | - |
| 1280 | hero | base | 5 | Layout | 491 | 0 | 0.7 | 102.9 | - |
| 1280 | hero | base | 5 | image decode task | 171 | 0 | 11.3 | 305.8 | - |
| 1280 | hero | aa | 5 | BeginMainFrame | 781 | 0 | 12.0 | 3349.9 | - |
| 1280 | hero | aa | 5 | Paint | 2154 | 0 | 2.6 | 322.3 | - |
| 1280 | hero | aa | 5 | UpdateLayoutTree | 1874 | 0 | 4.0 | 1023.4 | - |
| 1280 | hero | aa | 5 | Layout | 494 | 0 | 0.7 | 103.9 | - |
| 1280 | hero | aa | 5 | image decode task | 177 | 0 | 11.1 | 306.2 | - |
| 1280 | hero | cand | 5 | BeginMainFrame | 780 | 0 | 12.5 | 3310.0 | - |
| 1280 | hero | cand | 5 | Paint | 2139 | 0 | 2.6 | 323.8 | - |
| 1280 | hero | cand | 5 | UpdateLayoutTree | 1879 | 0 | 4.1 | 1009.5 | - |
| 1280 | hero | cand | 5 | Layout | 491 | 0 | 0.7 | 102.3 | - |
| 1280 | hero | cand | 5 | image decode task | 174 | 0 | 11.0 | 318.3 | - |
