Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39927164863:leg, 1280px, window hero** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 0.65 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 3.96 | 1.32 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 50.1 |
| base | 7 | 1085 | 4.60 | 0.65 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 50.1 |
| aa | 7 | 1085 | 4.88 | 0.65 | 1 of 7 | 0,0,0,0,0,1,0 | 16.7 | 33.4 | 50.1 | 83.4 |
| cand | 7 | 1086 | 4.97 | 1.25 | 4 of 7 | 1,1,0,1,1,0,0 | 16.7 | 33.5 | 50.1 | 83.4 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: first
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927164863:leg, 1280px, window end** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 5.85 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 494 | 17.61 | 7.11 | 7 of 7 | 3,4,4,3,1,1,7 | 33.3 | 50.1 | 66.7 | 116.7 |
| base | 7 | 501 | 17.76 | 5.85 | 7 of 7 | 5,4,4,4,4,3,3 | 33.3 | 66.6 | 83.3 | 100.0 |
| aa | 7 | 504 | 19.44 | 5.73 | 7 of 7 | 3,4,3,2,3,3,2 | 33.3 | 50.1 | 66.7 | 116.7 |
| cand | 7 | 511 | 16.24 | 4.85 | 7 of 7 | 3,3,2,3,3,3,3 | 33.3 | 50.1 | 66.7 | 116.6 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.15 | 5.85 |
| 1280 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -1.52 | 5.85 |
| 1280 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -1.37 | 5.85 |
| 1280 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.64 | 0.65 |
| 1280 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.37 | 0.65 |
| 1280 | hero | orig | cand | 1 | 1 / 1 | 1 / 0 / 0 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 1.01 | 0.65 |

Samples: 39927164863:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39927164863:leg | 1280 | hero | aa | 7 | 1 | 83.4 | 798 | 1 |
| 39927164863:leg | 1280 | hero | cand | 7 | 4 | 66.6 | 1008 | 4 |
| 39927164863:leg | 1280 | end | orig | 7 | 23 | 66.7 | 8269 | 7 |
| 39927164863:leg | 1280 | end | base | 7 | 27 | 66.7 | 8269 | 7 |
| 39927164863:leg | 1280 | end | aa | 7 | 20 | 66.7 | 8269 | 7 |
| 39927164863:leg | 1280 | end | cand | 7 | 20 | 66.7 | 8269 | 7 |

### Frames of the page's compositor sink (traced reps, the renderer process of the page only; reported beside the verdict, never in it)

A frame is one `frame_sequence`; `dropped` = any of its pipeline reporters dropped, `dropped (all)` = every reporter dropped, `presented` = the rest with a presented reporter.

| width | window | arm | traced reps | runs | frames | presented | dropped | dropped % | dropped (all) | dropped (all) % | rAF frames in the same reps | presented p95 ms (median of reps) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | 5 | 1 | 641 | 358 | 283 | 44.1 | 283 | 44.1 | 352 | 142.8 |
| 1280 | end | base | 5 | 1 | 651 | 364 | 287 | 44.1 | 287 | 44.1 | 355 | 170.0 |
| 1280 | end | aa | 5 | 1 | 655 | 368 | 287 | 43.8 | 287 | 43.8 | 353 | 184.7 |
| 1280 | end | cand | 5 | 1 | 658 | 372 | 286 | 43.5 | 286 | 43.5 | 356 | 157.4 |
| 1280 | hero | orig | 5 | 1 | 983 | 760 | 223 | 22.7 | 213 | 21.7 | 775 | 79.0 |
| 1280 | hero | base | 5 | 1 | 988 | 765 | 223 | 22.6 | 213 | 21.6 | 775 | 81.5 |
| 1280 | hero | aa | 5 | 1 | 981 | 763 | 218 | 22.2 | 209 | 21.3 | 775 | 77.8 |
| 1280 | hero | cand | 5 | 1 | 988 | 765 | 223 | 22.6 | 214 | 21.7 | 775 | 81.3 |

### Fixed slow-event names of the traced reps (page renderer process; every row is always listed, n = 0 means the event never ran; long = 15 ms or more)

| width | window | arm | traced reps | event | events | long | longest ms | total ms | long durations ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | 5 | BeginMainFrame | 357 | 3 | 19.1 | 2174.7 | 15.7, 18.4, 19.1 |
| 1280 | end | orig | 5 | Paint | 4417 | 0 | 3.4 | 601.4 | - |
| 1280 | end | orig | 5 | UpdateLayoutTree | 554 | 0 | 11.1 | 848.4 | - |
| 1280 | end | orig | 5 | Layout | 404 | 0 | 1.8 | 96.7 | - |
| 1280 | end | orig | 5 | image decode task | 2539 | 1 | 19.5 | 1742.8 | 19.5 |
| 1280 | end | base | 5 | BeginMainFrame | 361 | 10 | 51.2 | 2504.8 | 15.5, 15.7, 15.9, 16.4, 17.7, 19.2, 20.3, 23.5, 28.8, 51.2 |
| 1280 | end | base | 5 | Paint | 4463 | 0 | 4.6 | 651.8 | - |
| 1280 | end | base | 5 | UpdateLayoutTree | 555 | 0 | 9.0 | 675.2 | - |
| 1280 | end | base | 5 | Layout | 391 | 0 | 0.9 | 97.6 | - |
| 1280 | end | base | 5 | image decode task | 2645 | 0 | 9.8 | 1702.4 | - |
| 1280 | end | aa | 5 | BeginMainFrame | 358 | 18 | 59.2 | 2616.6 | 15.0, 15.4, 15.5, 15.5, 15.7, 16.0, 16.3, 16.3, 16.5, 17.0, 18.1, 19.2, 19.5, 19.7, 20.7, 47.8, 52.7, 59.2 |
| 1280 | end | aa | 5 | Paint | 4417 | 0 | 3.6 | 638.0 | - |
| 1280 | end | aa | 5 | UpdateLayoutTree | 554 | 0 | 7.8 | 697.6 | - |
| 1280 | end | aa | 5 | Layout | 392 | 0 | 2.5 | 99.5 | - |
| 1280 | end | aa | 5 | image decode task | 2652 | 1 | 15.4 | 1803.0 | 15.4 |
| 1280 | end | cand | 5 | BeginMainFrame | 362 | 11 | 50.2 | 2452.8 | 15.0, 15.1, 15.2, 15.5, 18.2, 18.8, 21.0, 21.1, 21.6, 45.9, 50.2 |
| 1280 | end | cand | 5 | Paint | 4300 | 0 | 4.5 | 650.7 | - |
| 1280 | end | cand | 5 | UpdateLayoutTree | 555 | 0 | 6.7 | 663.0 | - |
| 1280 | end | cand | 5 | Layout | 276 | 0 | 0.9 | 81.4 | - |
| 1280 | end | cand | 5 | image decode task | 2520 | 0 | 14.2 | 1753.9 | - |
| 1280 | hero | orig | 5 | BeginMainFrame | 780 | 0 | 12.6 | 3149.7 | - |
| 1280 | hero | orig | 5 | Paint | 2165 | 0 | 2.5 | 290.7 | - |
| 1280 | hero | orig | 5 | UpdateLayoutTree | 1881 | 0 | 5.6 | 1275.3 | - |
| 1280 | hero | orig | 5 | Layout | 494 | 0 | 0.3 | 96.1 | - |
| 1280 | hero | orig | 5 | image decode task | 225 | 1 | 16.7 | 353.8 | 16.7 |
| 1280 | hero | base | 5 | BeginMainFrame | 780 | 0 | 13.9 | 3347.9 | - |
| 1280 | hero | base | 5 | Paint | 2163 | 0 | 2.7 | 315.1 | - |
| 1280 | hero | base | 5 | UpdateLayoutTree | 1873 | 0 | 4.6 | 1034.6 | - |
| 1280 | hero | base | 5 | Layout | 492 | 0 | 0.7 | 100.2 | - |
| 1280 | hero | base | 5 | image decode task | 173 | 0 | 11.8 | 323.5 | - |
| 1280 | hero | aa | 5 | BeginMainFrame | 780 | 0 | 12.3 | 3306.8 | - |
| 1280 | hero | aa | 5 | Paint | 2150 | 0 | 2.5 | 312.1 | - |
| 1280 | hero | aa | 5 | UpdateLayoutTree | 1874 | 0 | 4.5 | 1033.6 | - |
| 1280 | hero | aa | 5 | Layout | 490 | 0 | 0.9 | 102.3 | - |
| 1280 | hero | aa | 5 | image decode task | 178 | 0 | 11.1 | 303.4 | - |
| 1280 | hero | cand | 5 | BeginMainFrame | 780 | 0 | 12.3 | 3333.7 | - |
| 1280 | hero | cand | 5 | Paint | 2151 | 0 | 2.5 | 312.4 | - |
| 1280 | hero | cand | 5 | UpdateLayoutTree | 1878 | 0 | 4.2 | 1027.5 | - |
| 1280 | hero | cand | 5 | Layout | 489 | 0 | 0.7 | 102.7 | - |
| 1280 | hero | cand | 5 | image decode task | 176 | 0 | 11.3 | 308.0 | - |
