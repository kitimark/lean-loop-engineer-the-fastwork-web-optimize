Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39927164863:leg, 390px, window hero** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 0.01 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1207 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.7 | 16.8 | 33.4 |
| base | 7 | 1209 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| aa | 7 | 1208 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |
| cand | 7 | 1210 | 0.66 | 0.59 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |

Rate verdicts: orig vs base: first; base vs cand: first; orig vs cand: first
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39927164863:leg, 390px, window end** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 1.68 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 839 | 0.71 | 1.65 | 2 of 7 | 1,0,0,1,0,0,0 | 16.7 | 16.8 | 33.4 | 66.8 |
| base | 7 | 837 | 0.95 | 1.68 | 1 of 7 | 0,0,0,1,0,0,0 | 16.7 | 16.8 | 33.4 | 66.7 |
| aa | 7 | 837 | 0.59 | 1.68 | 3 of 7 | 0,1,0,1,0,0,1 | 16.7 | 16.8 | 33.4 | 66.8 |
| cand | 7 | 839 | 0.59 | 1.68 | 2 of 7 | 0,0,1,0,1,0,0 | 16.7 | 16.8 | 33.4 | 66.6 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.24 | 1.68 |
| 390 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.36 | 1.68 |
| 390 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.12 | 1.68 |
| 390 | hero | orig | base | 1 | 1 / 1 | 1 / 0 / 0 / 0 | insufficient | 1 / 0 / 0 / 0 | insufficient | 0.57 | 0.01 |
| 390 | hero | base | cand | 1 | 1 / 1 | 1 / 0 / 0 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.09 | 0.01 |
| 390 | hero | orig | cand | 1 | 1 / 1 | 1 / 0 / 0 / 0 | insufficient | 1 / 0 / 0 / 0 | insufficient | 0.66 | 0.01 |

Samples: 39927164863:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39927164863:leg | 390 | hero | base | 7 | 7 | 83.3 | 672 | 7 |
| 39927164863:leg | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39927164863:leg | 390 | hero | cand | 7 | 7 | 83.3 | 672 | 7 |
| 39927164863:leg | 390 | end | orig | 7 | 2 | 66.7 | 5103 | 0 |
| 39927164863:leg | 390 | end | base | 7 | 1 | 66.7 | 5103 | 0 |
| 39927164863:leg | 390 | end | aa | 7 | 3 | 66.7 | 5103 | 0 |
| 39927164863:leg | 390 | end | cand | 7 | 2 | 66.6 | 5103 | 0 |

### Frames of the page's compositor sink (traced reps, the renderer process of the page only; reported beside the verdict, never in it)

A frame is one `frame_sequence`; `dropped` = any of its pipeline reporters dropped, `dropped (all)` = every reporter dropped, `presented` = the rest with a presented reporter.

| width | window | arm | traced reps | runs | frames | presented | dropped | dropped % | dropped (all) | dropped (all) % | rAF frames in the same reps | presented p95 ms (median of reps) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | 5 | 1 | 629 | 605 | 24 | 3.8 | 24 | 3.8 | 598 | 76.9 |
| 390 | end | base | 5 | 1 | 631 | 607 | 24 | 3.8 | 24 | 3.8 | 593 | 56.7 |
| 390 | end | aa | 5 | 1 | 630 | 607 | 23 | 3.7 | 23 | 3.7 | 596 | 59.8 |
| 390 | end | cand | 5 | 1 | 630 | 606 | 24 | 3.8 | 24 | 3.8 | 596 | 61.2 |
| 390 | hero | orig | 5 | 1 | 872 | 786 | 86 | 9.9 | 18 | 2.1 | 856 | 31.5 |
| 390 | hero | base | 5 | 1 | 893 | 775 | 118 | 13.2 | 40 | 4.5 | 858 | 31.5 |
| 390 | hero | aa | 5 | 1 | 895 | 783 | 112 | 12.5 | 39 | 4.4 | 857 | 31.6 |
| 390 | hero | cand | 5 | 1 | 895 | 778 | 117 | 13.1 | 39 | 4.4 | 860 | 31.7 |

### Fixed slow-event names of the traced reps (page renderer process; every row is always listed, n = 0 means the event never ran; long = 15 ms or more)

| width | window | arm | traced reps | event | events | long | longest ms | total ms | long durations ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | 5 | BeginMainFrame | 603 | 7 | 44.8 | 3413.7 | 15.3, 16.3, 30.1, 32.6, 32.9, 33.3, 44.8 |
| 390 | end | orig | 5 | Paint | 5325 | 0 | 3.0 | 717.4 | - |
| 390 | end | orig | 5 | UpdateLayoutTree | 985 | 0 | 8.4 | 1386.1 | - |
| 390 | end | orig | 5 | Layout | 780 | 0 | 0.3 | 124.5 | - |
| 390 | end | orig | 5 | image decode task | 2625 | 0 | 10.7 | 347.1 | - |
| 390 | end | base | 5 | BeginMainFrame | 598 | 5 | 51.7 | 3589.4 | 35.1, 39.9, 47.2, 49.6, 51.7 |
| 390 | end | base | 5 | Paint | 5264 | 0 | 3.1 | 719.6 | - |
| 390 | end | base | 5 | UpdateLayoutTree | 976 | 0 | 5.9 | 1090.1 | - |
| 390 | end | base | 5 | Layout | 776 | 0 | 0.8 | 134.3 | - |
| 390 | end | base | 5 | image decode task | 2605 | 0 | 9.2 | 353.9 | - |
| 390 | end | aa | 5 | BeginMainFrame | 601 | 5 | 45.4 | 3650.5 | 37.5, 38.8, 39.0, 40.0, 45.4 |
| 390 | end | aa | 5 | Paint | 5306 | 0 | 3.5 | 738.6 | - |
| 390 | end | aa | 5 | UpdateLayoutTree | 982 | 0 | 6.0 | 1114.7 | - |
| 390 | end | aa | 5 | Layout | 786 | 0 | 2.4 | 144.4 | - |
| 390 | end | aa | 5 | image decode task | 2626 | 0 | 10.1 | 361.2 | - |
| 390 | end | cand | 5 | BeginMainFrame | 601 | 5 | 50.6 | 3433.4 | 34.7, 39.3, 40.3, 46.4, 50.6 |
| 390 | end | cand | 5 | Paint | 5027 | 0 | 3.2 | 707.5 | - |
| 390 | end | cand | 5 | UpdateLayoutTree | 981 | 0 | 6.2 | 1068.2 | - |
| 390 | end | cand | 5 | Layout | 490 | 0 | 0.8 | 108.4 | - |
| 390 | end | cand | 5 | image decode task | 2626 | 0 | 8.7 | 354.4 | - |
| 390 | hero | orig | 5 | BeginMainFrame | 861 | 1 | 15.0 | 3401.0 | 15.0 |
| 390 | hero | orig | 5 | Paint | 5242 | 0 | 2.4 | 475.8 | - |
| 390 | hero | orig | 5 | UpdateLayoutTree | 2015 | 0 | 4.7 | 1191.4 | - |
| 390 | hero | orig | 5 | Layout | 904 | 0 | 2.0 | 133.7 | - |
| 390 | hero | orig | 5 | image decode task | 572 | 10 | 52.9 | 749.6 | 31.0, 31.0, 31.4, 31.7, 33.2, 51.9, 52.1, 52.5, 52.5, 52.9 |
| 390 | hero | base | 5 | BeginMainFrame | 863 | 2 | 16.6 | 3436.3 | 15.4, 16.6 |
| 390 | hero | base | 5 | Paint | 5038 | 0 | 2.8 | 454.0 | - |
| 390 | hero | base | 5 | UpdateLayoutTree | 1984 | 0 | 3.6 | 952.7 | - |
| 390 | hero | base | 5 | Layout | 914 | 0 | 1.7 | 128.9 | - |
| 390 | hero | base | 5 | image decode task | 626 | 20 | 53.5 | 1043.1 | 30.7, 30.8, 31.0, 31.0, 31.1, 31.2, 31.2, 31.3, 31.4, 31.5, 33.2, 33.3, 33.7, 33.8, 33.8, 52.5, 52.7, 52.8, 52.8, 53.5 |
| 390 | hero | aa | 5 | BeginMainFrame | 862 | 3 | 17.6 | 3432.4 | 15.1, 16.2, 17.6 |
| 390 | hero | aa | 5 | Paint | 5028 | 0 | 2.8 | 458.8 | - |
| 390 | hero | aa | 5 | UpdateLayoutTree | 1985 | 0 | 3.4 | 962.8 | - |
| 390 | hero | aa | 5 | Layout | 915 | 0 | 2.2 | 132.9 | - |
| 390 | hero | aa | 5 | image decode task | 621 | 20 | 52.9 | 1039.5 | 30.9, 31.1, 31.1, 31.1, 31.3, 31.3, 31.3, 31.4, 31.5, 31.5, 33.5, 33.6, 33.7, 33.7, 33.8, 51.5, 52.3, 52.5, 52.7, 52.9 |
| 390 | hero | cand | 5 | BeginMainFrame | 865 | 3 | 16.9 | 3497.3 | 15.9, 16.8, 16.9 |
| 390 | hero | cand | 5 | Paint | 5034 | 0 | 2.8 | 463.1 | - |
| 390 | hero | cand | 5 | UpdateLayoutTree | 1987 | 0 | 3.6 | 971.1 | - |
| 390 | hero | cand | 5 | Layout | 919 | 0 | 1.7 | 133.6 | - |
| 390 | hero | cand | 5 | image decode task | 643 | 20 | 53.2 | 1048.5 | 30.8, 30.9, 30.9, 31.1, 31.1, 31.1, 31.2, 31.3, 31.3, 31.4, 33.6, 33.6, 33.7, 34.1, 34.2, 51.6, 51.6, 52.2, 52.8, 53.2 |
