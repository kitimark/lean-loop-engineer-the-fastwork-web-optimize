Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39924675073:leg, 390px, window hero** (CPU throttle 1x, candidate default, A/A spread 0.58 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1204 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 33.3 | 33.4 |
| base | 7 | 1207 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| aa | 7 | 1208 | 0.66 | 0.58 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| cand | 7 | 1209 | 0.66 | 0.59 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: first
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39924675073:leg, 390px, window end** (CPU throttle 1x, candidate default, A/A spread 0.85 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 829 | 0.48 | 1.70 | 1 of 7 | 1,0,0,0,0,0,0 | 16.7 | 33.3 | 33.4 | 66.7 |
| base | 7 | 833 | 0.96 | 0.83 | 3 of 7 | 1,0,1,1,0,0,0 | 16.7 | 16.8 | 33.4 | 66.7 |
| aa | 7 | 829 | 1.20 | 0.85 | 5 of 7 | 1,1,1,0,0,1,1 | 16.7 | 16.8 | 49.9 | 66.8 |
| cand | 7 | 834 | 0.95 | 0.88 | 2 of 7 | 1,0,0,0,1,0,0 | 16.7 | 16.8 | 33.4 | 66.8 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.48 | 0.85 |
| 390 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.01 | 0.85 |
| 390 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.47 | 0.85 |
| 390 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 1 / 0 / 0 / 0 | insufficient | 0.57 | 0.58 |
| 390 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.09 | 0.58 |
| 390 | hero | orig | cand | 1 | 1 / 1 | 1 / 0 / 0 / 0 | insufficient | 1 / 0 / 0 / 0 | insufficient | 0.66 | 0.58 |

Samples: 39924675073:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39924675073:leg | 390 | hero | base | 7 | 7 | 83.3 | 672 | 7 |
| 39924675073:leg | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39924675073:leg | 390 | hero | cand | 7 | 7 | 83.3 | 672 | 7 |
| 39924675073:leg | 390 | end | orig | 7 | 1 | 66.7 | 5103 | 0 |
| 39924675073:leg | 390 | end | base | 7 | 3 | 66.7 | 5103 | 0 |
| 39924675073:leg | 390 | end | aa | 7 | 5 | 66.7 | 5103 | 4 |
| 39924675073:leg | 390 | end | cand | 7 | 2 | 66.7 | 5103 | 0 |

### Frames of the page's compositor sink (traced reps, the renderer process of the page only; reported beside the verdict, never in it)

A frame is one `frame_sequence`; `dropped` = any of its pipeline reporters dropped, `dropped (all)` = every reporter dropped, `presented` = the rest with a presented reporter.

| width | window | arm | traced reps | runs | frames | presented | dropped | dropped % | dropped (all) | dropped (all) % | rAF frames in the same reps | presented p95 ms (median of reps) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | 5 | 1 | 631 | 600 | 31 | 4.9 | 31 | 4.9 | 588 | 63.5 |
| 390 | end | base | 5 | 1 | 630 | 598 | 32 | 5.1 | 32 | 5.1 | 585 | 61.8 |
| 390 | end | aa | 5 | 1 | 629 | 601 | 28 | 4.5 | 28 | 4.5 | 591 | 67.5 |
| 390 | end | cand | 5 | 1 | 629 | 599 | 30 | 4.8 | 30 | 4.8 | 589 | 71.7 |
| 390 | hero | orig | 5 | 1 | 861 | 790 | 71 | 8.2 | 15 | 1.7 | 843 | 32.6 |
| 390 | hero | base | 5 | 1 | 884 | 781 | 103 | 11.7 | 38 | 4.3 | 846 | 32.3 |
| 390 | hero | aa | 5 | 1 | 885 | 783 | 102 | 11.5 | 38 | 4.3 | 848 | 32.8 |
| 390 | hero | cand | 5 | 1 | 887 | 784 | 103 | 11.6 | 39 | 4.4 | 847 | 32.2 |

### Fixed slow-event names of the traced reps (page renderer process; every row is always listed, n = 0 means the event never ran; long = 15 ms or more)

| width | window | arm | traced reps | event | events | long | longest ms | total ms | long durations ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | 5 | BeginMainFrame | 593 | 8 | 52.9 | 3777.7 | 15.7, 16.2, 16.6, 34.4, 38.8, 40.4, 51.6, 52.9 |
| 390 | end | orig | 5 | Paint | 5201 | 0 | 3.6 | 798.6 | - |
| 390 | end | orig | 5 | UpdateLayoutTree | 966 | 0 | 8.8 | 1465.1 | - |
| 390 | end | orig | 5 | Layout | 766 | 0 | 0.4 | 156.3 | - |
| 390 | end | orig | 5 | image decode task | 2577 | 0 | 11.7 | 381.0 | - |
| 390 | end | base | 5 | BeginMainFrame | 590 | 5 | 60.3 | 3974.1 | 40.5, 42.5, 50.7, 58.9, 60.3 |
| 390 | end | base | 5 | Paint | 5214 | 0 | 3.4 | 790.5 | - |
| 390 | end | base | 5 | UpdateLayoutTree | 960 | 0 | 5.8 | 1155.1 | - |
| 390 | end | base | 5 | Layout | 764 | 0 | 0.8 | 155.6 | - |
| 390 | end | base | 5 | image decode task | 2562 | 0 | 10.0 | 359.8 | - |
| 390 | end | aa | 5 | BeginMainFrame | 596 | 5 | 49.0 | 4022.6 | 38.7, 41.9, 46.3, 46.5, 49.0 |
| 390 | end | aa | 5 | Paint | 5251 | 0 | 3.5 | 806.0 | - |
| 390 | end | aa | 5 | UpdateLayoutTree | 971 | 0 | 6.3 | 1179.7 | - |
| 390 | end | aa | 5 | Layout | 772 | 0 | 0.8 | 156.9 | - |
| 390 | end | aa | 5 | image decode task | 2595 | 0 | 10.7 | 362.0 | - |
| 390 | end | cand | 5 | BeginMainFrame | 594 | 5 | 54.8 | 4031.4 | 43.6, 43.8, 46.0, 47.0, 54.8 |
| 390 | end | cand | 5 | Paint | 5256 | 0 | 3.4 | 800.7 | - |
| 390 | end | cand | 5 | UpdateLayoutTree | 968 | 0 | 7.2 | 1181.6 | - |
| 390 | end | cand | 5 | Layout | 771 | 0 | 0.8 | 160.1 | - |
| 390 | end | cand | 5 | image decode task | 2578 | 0 | 9.0 | 359.7 | - |
| 390 | hero | orig | 5 | BeginMainFrame | 848 | 4 | 16.1 | 3962.1 | 15.1, 15.2, 15.9, 16.1 |
| 390 | hero | orig | 5 | Paint | 5188 | 0 | 2.6 | 544.8 | - |
| 390 | hero | orig | 5 | UpdateLayoutTree | 1994 | 0 | 5.8 | 1358.6 | - |
| 390 | hero | orig | 5 | Layout | 908 | 0 | 2.1 | 156.4 | - |
| 390 | hero | orig | 5 | image decode task | 551 | 10 | 54.2 | 764.2 | 31.1, 31.3, 31.5, 33.2, 33.6, 52.3, 52.6, 52.6, 53.1, 54.2 |
| 390 | hero | base | 5 | BeginMainFrame | 851 | 5 | 17.8 | 3923.9 | 16.5, 17.2, 17.5, 17.6, 17.8 |
| 390 | hero | base | 5 | Paint | 5000 | 0 | 2.9 | 517.5 | - |
| 390 | hero | base | 5 | UpdateLayoutTree | 1974 | 0 | 3.7 | 1074.6 | - |
| 390 | hero | base | 5 | Layout | 910 | 0 | 3.8 | 150.0 | - |
| 390 | hero | base | 5 | image decode task | 597 | 20 | 53.1 | 1065.1 | 31.0, 31.2, 31.3, 31.4, 31.4, 31.4, 31.5, 31.6, 31.7, 31.8, 33.3, 33.8, 34.0, 34.0, 34.2, 52.4, 52.5, 52.7, 52.7, 53.1 |
| 390 | hero | aa | 5 | BeginMainFrame | 853 | 5 | 18.2 | 3936.2 | 16.6, 17.0, 17.1, 17.5, 18.2 |
| 390 | hero | aa | 5 | Paint | 4999 | 0 | 2.9 | 513.6 | - |
| 390 | hero | aa | 5 | UpdateLayoutTree | 1979 | 0 | 5.0 | 1079.5 | - |
| 390 | hero | aa | 5 | Layout | 913 | 0 | 1.3 | 146.7 | - |
| 390 | hero | aa | 5 | image decode task | 592 | 20 | 53.8 | 1069.4 | 31.1, 31.2, 31.4, 31.5, 31.5, 31.5, 31.8, 31.8, 32.5, 33.1, 33.5, 33.7, 33.7, 33.9, 34.0, 52.2, 53.2, 53.4, 53.7, 53.8 |
| 390 | hero | cand | 5 | BeginMainFrame | 852 | 5 | 22.1 | 3846.5 | 15.8, 16.6, 17.1, 17.5, 22.1 |
| 390 | hero | cand | 5 | Paint | 5010 | 0 | 2.9 | 505.9 | - |
| 390 | hero | cand | 5 | UpdateLayoutTree | 1973 | 0 | 4.7 | 1055.8 | - |
| 390 | hero | cand | 5 | Layout | 907 | 0 | 2.5 | 148.1 | - |
| 390 | hero | cand | 5 | image decode task | 604 | 20 | 53.5 | 1069.3 | 31.1, 31.1, 31.2, 31.4, 31.5, 31.6, 31.7, 31.8, 31.8, 32.1, 33.6, 33.7, 34.0, 34.5, 34.5, 52.5, 52.5, 52.9, 53.0, 53.5 |
