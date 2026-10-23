Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39927164863:leg, 390px, window hero** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 0.60 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1209 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 16.8 | 33.4 |
| base | 7 | 1204 | 0.58 | 0.02 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| aa | 7 | 1206 | 0.66 | 0.60 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| cand | 7 | 1205 | 0.58 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.3 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39927164863:leg, 390px, window end** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 0.88 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 832 | 0.96 | 1.68 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.2 | 33.4 | 50.1 |
| base | 7 | 839 | 0.71 | 0.84 | 3 of 7 | 1,0,1,0,0,0,1 | 16.7 | 16.8 | 33.4 | 66.8 |
| aa | 7 | 836 | 0.95 | 0.88 | 4 of 7 | 1,0,1,1,0,0,1 | 16.7 | 16.8 | 33.4 | 83.3 |
| cand | 7 | 837 | 0.83 | 1.69 | 3 of 7 | 0,1,1,0,0,1,0 | 16.7 | 16.8 | 33.4 | 66.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.25 | 0.88 |
| 390 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.12 | 0.88 |
| 390 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.13 | 0.88 |
| 390 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 1 / 0 / 0 / 0 | insufficient | 0.58 | 0.60 |
| 390 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.00 | 0.60 |
| 390 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 1 / 0 / 0 / 0 | insufficient | 0.58 | 0.60 |

Samples: 39927164863:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39927164863:leg | 390 | hero | base | 7 | 7 | 83.3 | 672 | 7 |
| 39927164863:leg | 390 | hero | aa | 7 | 7 | 83.4 | 672 | 7 |
| 39927164863:leg | 390 | hero | cand | 7 | 7 | 83.3 | 672 | 7 |
| 39927164863:leg | 390 | end | base | 7 | 3 | 66.7 | 5103 | 1 |
| 39927164863:leg | 390 | end | aa | 7 | 4 | 66.6 | 5103 | 2 |
| 39927164863:leg | 390 | end | cand | 7 | 3 | 66.6 | 5103 | 1 |

### Frames of the page's compositor sink (traced reps, the renderer process of the page only; reported beside the verdict, never in it)

A frame is one `frame_sequence`; `dropped` = any of its pipeline reporters dropped, `dropped (all)` = every reporter dropped, `presented` = the rest with a presented reporter.

| width | window | arm | traced reps | runs | frames | presented | dropped | dropped % | dropped (all) | dropped (all) % | rAF frames in the same reps | presented p95 ms (median of reps) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | 5 | 1 | 632 | 609 | 23 | 3.6 | 23 | 3.6 | 595 | 63.6 |
| 390 | end | base | 5 | 1 | 631 | 605 | 26 | 4.1 | 26 | 4.1 | 591 | 63.9 |
| 390 | end | aa | 5 | 1 | 630 | 604 | 26 | 4.1 | 26 | 4.1 | 592 | 62.1 |
| 390 | end | cand | 5 | 1 | 632 | 604 | 28 | 4.4 | 28 | 4.4 | 589 | 62.3 |
| 390 | hero | orig | 5 | 1 | 875 | 788 | 87 | 9.9 | 15 | 1.7 | 856 | 32.0 |
| 390 | hero | base | 5 | 1 | 880 | 781 | 99 | 11.3 | 39 | 4.4 | 843 | 32.4 |
| 390 | hero | aa | 5 | 1 | 881 | 786 | 95 | 10.8 | 37 | 4.2 | 843 | 32.2 |
| 390 | hero | cand | 5 | 1 | 878 | 782 | 96 | 10.9 | 36 | 4.1 | 839 | 32.2 |

### Fixed slow-event names of the traced reps (page renderer process; every row is always listed, n = 0 means the event never ran; long = 15 ms or more)

| width | window | arm | traced reps | event | events | long | longest ms | total ms | long durations ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | 5 | BeginMainFrame | 600 | 10 | 53.9 | 3685.1 | 16.1, 16.2, 16.3, 16.5, 16.6, 33.5, 37.3, 39.8, 52.1, 53.9 |
| 390 | end | orig | 5 | Paint | 5276 | 0 | 3.2 | 759.6 | - |
| 390 | end | orig | 5 | UpdateLayoutTree | 979 | 0 | 10.9 | 1512.2 | - |
| 390 | end | orig | 5 | Layout | 778 | 0 | 0.5 | 144.7 | - |
| 390 | end | orig | 5 | image decode task | 2590 | 0 | 10.9 | 363.4 | - |
| 390 | end | base | 5 | BeginMainFrame | 596 | 5 | 46.6 | 4057.4 | 41.5, 41.9, 44.5, 46.2, 46.6 |
| 390 | end | base | 5 | Paint | 5255 | 0 | 3.2 | 787.7 | - |
| 390 | end | base | 5 | UpdateLayoutTree | 972 | 0 | 6.2 | 1232.3 | - |
| 390 | end | base | 5 | Layout | 781 | 0 | 0.8 | 165.2 | - |
| 390 | end | base | 5 | image decode task | 2622 | 0 | 9.8 | 363.5 | - |
| 390 | end | aa | 5 | BeginMainFrame | 597 | 5 | 57.3 | 4080.9 | 45.4, 47.1, 52.1, 57.2, 57.3 |
| 390 | end | aa | 5 | Paint | 5241 | 0 | 3.2 | 782.4 | - |
| 390 | end | aa | 5 | UpdateLayoutTree | 974 | 0 | 6.7 | 1240.8 | - |
| 390 | end | aa | 5 | Layout | 779 | 0 | 0.9 | 162.4 | - |
| 390 | end | aa | 5 | image decode task | 2609 | 0 | 10.0 | 356.5 | - |
| 390 | end | cand | 5 | BeginMainFrame | 594 | 5 | 56.0 | 3765.4 | 40.2, 42.6, 46.5, 52.0, 56.0 |
| 390 | end | cand | 5 | Paint | 5001 | 0 | 3.1 | 749.1 | - |
| 390 | end | cand | 5 | UpdateLayoutTree | 968 | 0 | 5.7 | 1158.8 | - |
| 390 | end | cand | 5 | Layout | 484 | 0 | 0.8 | 124.5 | - |
| 390 | end | cand | 5 | image decode task | 2583 | 0 | 11.5 | 362.7 | - |
| 390 | hero | orig | 5 | BeginMainFrame | 861 | 3 | 15.4 | 3795.8 | 15.1, 15.3, 15.4 |
| 390 | hero | orig | 5 | Paint | 5253 | 0 | 2.4 | 508.6 | - |
| 390 | hero | orig | 5 | UpdateLayoutTree | 2013 | 0 | 4.8 | 1344.8 | - |
| 390 | hero | orig | 5 | Layout | 912 | 0 | 2.1 | 148.1 | - |
| 390 | hero | orig | 5 | image decode task | 584 | 10 | 53.8 | 751.3 | 30.9, 31.0, 31.2, 31.5, 31.5, 52.3, 52.5, 52.6, 52.7, 53.8 |
| 390 | hero | base | 5 | BeginMainFrame | 848 | 5 | 17.9 | 3890.6 | 15.0, 16.5, 16.7, 17.2, 17.9 |
| 390 | hero | base | 5 | Paint | 4990 | 0 | 2.8 | 496.7 | - |
| 390 | hero | base | 5 | UpdateLayoutTree | 1970 | 0 | 3.9 | 1098.1 | - |
| 390 | hero | base | 5 | Layout | 910 | 0 | 1.7 | 144.8 | - |
| 390 | hero | base | 5 | image decode task | 604 | 20 | 54.9 | 1076.9 | 31.0, 31.1, 31.2, 31.2, 31.4, 31.6, 31.6, 31.8, 31.8, 31.8, 33.5, 33.7, 33.9, 34.0, 34.2, 51.8, 52.5, 52.8, 53.1, 54.9 |
| 390 | hero | aa | 5 | BeginMainFrame | 848 | 4 | 18.0 | 3889.8 | 16.5, 17.1, 17.5, 18.0 |
| 390 | hero | aa | 5 | Paint | 4994 | 0 | 2.8 | 502.7 | - |
| 390 | hero | aa | 5 | UpdateLayoutTree | 1967 | 0 | 4.0 | 1095.9 | - |
| 390 | hero | aa | 5 | Layout | 907 | 0 | 1.6 | 146.1 | - |
| 390 | hero | aa | 5 | image decode task | 599 | 20 | 52.8 | 1064.6 | 30.9, 30.9, 31.2, 31.3, 31.3, 31.4, 31.4, 31.6, 31.7, 31.9, 33.7, 33.7, 34.0, 34.0, 34.3, 51.7, 51.8, 51.8, 52.6, 52.8 |
| 390 | hero | cand | 5 | BeginMainFrame | 844 | 5 | 18.6 | 3866.0 | 15.1, 15.3, 16.7, 18.3, 18.6 |
| 390 | hero | cand | 5 | Paint | 4989 | 0 | 2.9 | 492.1 | - |
| 390 | hero | cand | 5 | UpdateLayoutTree | 1970 | 0 | 3.9 | 1092.5 | - |
| 390 | hero | cand | 5 | Layout | 911 | 0 | 1.7 | 143.4 | - |
| 390 | hero | cand | 5 | image decode task | 582 | 20 | 53.1 | 1068.6 | 31.1, 31.1, 31.2, 31.2, 31.3, 31.4, 31.4, 31.5, 31.6, 31.6, 33.4, 33.7, 33.8, 34.0, 34.1, 52.1, 52.2, 52.3, 52.9, 53.1 |
