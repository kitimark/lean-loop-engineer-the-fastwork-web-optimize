Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39927164863:smoothness-1280-1, 1280px, window hero** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 1.29 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 4.42 | 1.93 | 1 of 7 | 1,0,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 66.7 |
| base | 7 | 1085 | 4.79 | 1.29 | 2 of 7 | 1,0,0,1,0,0,0 | 16.7 | 33.4 | 50.1 | 83.4 |
| aa | 7 | 1085 | 5.06 | 1.29 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 49.9 | 50.1 | 50.1 |
| cand | 7 | 1085 | 4.51 | 1.29 | 3 of 7 | 1,0,1,1,0,0,0 | 16.7 | 33.4 | 50.0 | 83.4 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927164863:smoothness-1280-1, 1280px, window end** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 7.79 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 504 | 17.65 | 4.15 | 7 of 7 | 3,3,4,2,5,4,4 | 33.3 | 50.1 | 66.7 | 83.3 |
| base | 7 | 501 | 18.56 | 7.34 | 7 of 7 | 5,6,2,3,4,3,4 | 33.3 | 66.6 | 66.8 | 100.1 |
| aa | 7 | 510 | 17.84 | 7.79 | 7 of 7 | 4,3,3,3,5,2,3 | 33.3 | 50.1 | 66.7 | 116.7 |
| cand | 7 | 510 | 16.47 | 4.17 | 7 of 7 | 3,4,4,4,4,5,3 | 33.3 | 66.6 | 83.4 | 133.3 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927164863:smoothness-1280-2, 1280px, window hero** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 0.65 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 3.96 | 1.32 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 50.1 |
| base | 7 | 1085 | 4.60 | 0.65 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 50.1 |
| aa | 7 | 1085 | 4.88 | 0.65 | 1 of 7 | 0,0,0,0,0,1,0 | 16.7 | 33.4 | 50.1 | 83.4 |
| cand | 7 | 1086 | 4.97 | 1.25 | 4 of 7 | 1,1,0,1,1,0,0 | 16.7 | 33.5 | 50.1 | 83.4 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: first
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927164863:smoothness-1280-2, 1280px, window end** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 5.85 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 494 | 17.61 | 7.11 | 7 of 7 | 3,4,4,3,1,1,7 | 33.3 | 50.1 | 66.7 | 116.7 |
| base | 7 | 501 | 17.76 | 5.85 | 7 of 7 | 5,4,4,4,4,3,3 | 33.3 | 66.6 | 83.3 | 100.0 |
| aa | 7 | 504 | 19.44 | 5.73 | 7 of 7 | 3,4,3,2,3,3,2 | 33.3 | 50.1 | 66.7 | 116.7 |
| cand | 7 | 511 | 16.24 | 4.85 | 7 of 7 | 3,3,2,3,3,3,3 | 33.3 | 50.1 | 66.7 | 116.6 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927164863:smoothness-1280-3, 1280px, window hero** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 1.29 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 5.25 | 1.29 | 2 of 7 | 0,1,0,1,0,0,0 | 16.7 | 49.9 | 50.0 | 83.4 |
| base | 7 | 1085 | 5.43 | 1.29 | 5 of 7 | 1,1,1,1,0,0,2 | 16.7 | 49.9 | 50.1 | 83.4 |
| aa | 7 | 1085 | 5.71 | 1.29 | 2 of 7 | 1,0,0,0,0,0,1 | 16.7 | 49.9 | 50.1 | 83.3 |
| cand | 7 | 1085 | 5.34 | 0.64 | 3 of 7 | 0,1,1,1,0,0,0 | 16.7 | 49.9 | 50.0 | 83.3 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927164863:smoothness-1280-3, 1280px, window end** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 8.97 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 473 | 19.66 | 5.56 | 7 of 7 | 5,6,5,4,3,3,4 | 33.3 | 66.6 | 83.4 | 116.7 |
| base | 7 | 489 | 18.60 | 8.97 | 7 of 7 | 3,3,5,3,3,4,5 | 33.3 | 66.6 | 83.3 | 116.7 |
| aa | 7 | 485 | 20.82 | 4.95 | 7 of 7 | 2,3,5,4,2,4,3 | 33.3 | 50.1 | 66.7 | 66.7 |
| cand | 7 | 487 | 20.12 | 9.01 | 7 of 7 | 4,4,6,4,3,2,3 | 33.3 | 66.6 | 66.7 | 100.0 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927164863:smoothness-390-1, 390px, window hero** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 0.60 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1209 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 16.8 | 33.4 |
| base | 7 | 1204 | 0.58 | 0.02 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| aa | 7 | 1206 | 0.66 | 0.60 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| cand | 7 | 1205 | 0.58 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.3 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39927164863:smoothness-390-1, 390px, window end** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 0.88 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 832 | 0.96 | 1.68 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.2 | 33.4 | 50.1 |
| base | 7 | 839 | 0.71 | 0.84 | 3 of 7 | 1,0,1,0,0,0,1 | 16.7 | 16.8 | 33.4 | 66.8 |
| aa | 7 | 836 | 0.95 | 0.88 | 4 of 7 | 1,0,1,1,0,0,1 | 16.7 | 16.8 | 33.4 | 83.3 |
| cand | 7 | 837 | 0.83 | 1.69 | 3 of 7 | 0,1,1,0,0,1,0 | 16.7 | 16.8 | 33.4 | 66.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927164863:smoothness-390-2, 390px, window hero** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 0.01 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1207 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.7 | 16.8 | 33.4 |
| base | 7 | 1209 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| aa | 7 | 1208 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |
| cand | 7 | 1210 | 0.66 | 0.59 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |

Rate verdicts: orig vs base: first; base vs cand: first; orig vs cand: first
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39927164863:smoothness-390-2, 390px, window end** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 1.68 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 839 | 0.71 | 1.65 | 2 of 7 | 1,0,0,1,0,0,0 | 16.7 | 16.8 | 33.4 | 66.8 |
| base | 7 | 837 | 0.95 | 1.68 | 1 of 7 | 0,0,0,1,0,0,0 | 16.7 | 16.8 | 33.4 | 66.7 |
| aa | 7 | 837 | 0.59 | 1.68 | 3 of 7 | 0,1,0,1,0,0,1 | 16.7 | 16.8 | 33.4 | 66.8 |
| cand | 7 | 839 | 0.59 | 1.68 | 2 of 7 | 0,0,1,0,1,0,0 | 16.7 | 16.8 | 33.4 | 66.6 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927164863:smoothness-390-3, 390px, window hero** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 0.01 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1209 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 16.8 | 33.4 |
| base | 7 | 1210 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| aa | 7 | 1211 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |
| cand | 7 | 1208 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |

Rate verdicts: orig vs base: first; base vs cand: same; orig vs cand: first
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39927164863:smoothness-390-3, 390px, window end** (CPU throttle 1x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 1.68 points)

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
| 390 | end | orig | base | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | -0.24 | 1.68 |
| 390 | end | base | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 0.12 | 1.68 |
| 390 | end | orig | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | -0.12 | 1.68 |
| 390 | hero | orig | base | 3 | 2 / 2 | 2 / 0 / 1 / 0 | first smoother | 3 / 0 / 0 / 0 | first smoother | 0.57 | 0.01 |
| 390 | hero | base | cand | 3 | 2 / 2 | 1 / 0 / 2 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 0.00 | 0.01 |
| 390 | hero | orig | cand | 3 | 2 / 2 | 2 / 0 / 1 / 0 | first smoother | 3 / 0 / 0 / 0 | first smoother | 0.58 | 0.01 |
| 1280 | end | orig | base | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 0.15 | 7.79 |
| 1280 | end | base | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | -1.52 | 7.79 |
| 1280 | end | orig | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | -1.18 | 7.79 |
| 1280 | hero | orig | base | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 0.37 | 1.29 |
| 1280 | hero | base | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | -0.09 | 1.29 |
| 1280 | hero | orig | cand | 3 | 2 / 2 | 1 / 0 / 2 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 0.09 | 1.29 |

Samples: 39927164863:smoothness-390-1, 39927164863:smoothness-390-2, 39927164863:smoothness-390-3, 39927164863:smoothness-1280-1, 39927164863:smoothness-1280-2, 39927164863:smoothness-1280-3

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39927164863:smoothness-1280-1 | 1280 | hero | orig | 7 | 1 | 66.7 | 1008 | 1 |
| 39927164863:smoothness-1280-1 | 1280 | hero | base | 7 | 2 | 83.4 | 882 | 2 |
| 39927164863:smoothness-1280-1 | 1280 | hero | cand | 7 | 3 | 83.3 | 966 | 3 |
| 39927164863:smoothness-1280-1 | 1280 | end | orig | 7 | 25 | 66.7 | 8269 | 7 |
| 39927164863:smoothness-1280-1 | 1280 | end | base | 7 | 27 | 66.7 | 8269 | 7 |
| 39927164863:smoothness-1280-1 | 1280 | end | aa | 7 | 23 | 66.6 | 8269 | 7 |
| 39927164863:smoothness-1280-1 | 1280 | end | cand | 7 | 27 | 66.7 | 8269 | 7 |
| 39927164863:smoothness-1280-2 | 1280 | hero | aa | 7 | 1 | 83.4 | 798 | 1 |
| 39927164863:smoothness-1280-2 | 1280 | hero | cand | 7 | 4 | 66.6 | 1008 | 4 |
| 39927164863:smoothness-1280-2 | 1280 | end | orig | 7 | 23 | 66.7 | 8269 | 7 |
| 39927164863:smoothness-1280-2 | 1280 | end | base | 7 | 27 | 66.7 | 8269 | 7 |
| 39927164863:smoothness-1280-2 | 1280 | end | aa | 7 | 20 | 66.7 | 8269 | 7 |
| 39927164863:smoothness-1280-2 | 1280 | end | cand | 7 | 20 | 66.7 | 8269 | 7 |
| 39927164863:smoothness-1280-3 | 1280 | hero | orig | 7 | 2 | 83.3 | 840 | 2 |
| 39927164863:smoothness-1280-3 | 1280 | hero | base | 7 | 6 | 83.3 | 882 | 5 |
| 39927164863:smoothness-1280-3 | 1280 | hero | aa | 7 | 2 | 83.3 | 966 | 2 |
| 39927164863:smoothness-1280-3 | 1280 | hero | cand | 7 | 3 | 83.3 | 966 | 3 |
| 39927164863:smoothness-1280-3 | 1280 | end | orig | 7 | 30 | 66.7 | 8269 | 7 |
| 39927164863:smoothness-1280-3 | 1280 | end | base | 7 | 26 | 66.7 | 8269 | 7 |
| 39927164863:smoothness-1280-3 | 1280 | end | aa | 7 | 23 | 66.7 | 8269 | 7 |
| 39927164863:smoothness-1280-3 | 1280 | end | cand | 7 | 26 | 66.7 | 8269 | 7 |
| 39927164863:smoothness-390-1 | 390 | hero | base | 7 | 7 | 83.3 | 672 | 7 |
| 39927164863:smoothness-390-1 | 390 | hero | aa | 7 | 7 | 83.4 | 672 | 7 |
| 39927164863:smoothness-390-1 | 390 | hero | cand | 7 | 7 | 83.3 | 672 | 7 |
| 39927164863:smoothness-390-1 | 390 | end | base | 7 | 3 | 66.7 | 5103 | 1 |
| 39927164863:smoothness-390-1 | 390 | end | aa | 7 | 4 | 66.6 | 5103 | 2 |
| 39927164863:smoothness-390-1 | 390 | end | cand | 7 | 3 | 66.6 | 5103 | 1 |
| 39927164863:smoothness-390-2 | 390 | hero | base | 7 | 7 | 83.3 | 672 | 7 |
| 39927164863:smoothness-390-2 | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39927164863:smoothness-390-2 | 390 | hero | cand | 7 | 7 | 83.3 | 672 | 7 |
| 39927164863:smoothness-390-2 | 390 | end | orig | 7 | 2 | 66.7 | 5103 | 0 |
| 39927164863:smoothness-390-2 | 390 | end | base | 7 | 1 | 66.7 | 5103 | 0 |
| 39927164863:smoothness-390-2 | 390 | end | aa | 7 | 3 | 66.7 | 5103 | 0 |
| 39927164863:smoothness-390-2 | 390 | end | cand | 7 | 2 | 66.6 | 5103 | 0 |
| 39927164863:smoothness-390-3 | 390 | hero | base | 7 | 7 | 83.3 | 672 | 7 |
| 39927164863:smoothness-390-3 | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39927164863:smoothness-390-3 | 390 | hero | cand | 7 | 7 | 66.7 | 672 | 7 |
| 39927164863:smoothness-390-3 | 390 | end | orig | 7 | 1 | 66.7 | 5103 | 0 |
| 39927164863:smoothness-390-3 | 390 | end | base | 7 | 2 | 66.6 | 5103 | 0 |
| 39927164863:smoothness-390-3 | 390 | end | aa | 7 | 3 | 66.7 | 5103 | 0 |
| 39927164863:smoothness-390-3 | 390 | end | cand | 7 | 2 | 66.6 | 5103 | 0 |

### Frames of the page's compositor sink (traced reps, the renderer process of the page only; reported beside the verdict, never in it)

A frame is one `frame_sequence`; `dropped` = any of its pipeline reporters dropped, `dropped (all)` = every reporter dropped, `presented` = the rest with a presented reporter.

| width | window | arm | traced reps | runs | frames | presented | dropped | dropped % | dropped (all) | dropped (all) % | rAF frames in the same reps | presented p95 ms (median of reps) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | 15 | 3 | 1893 | 1821 | 72 | 3.8 | 72 | 3.8 | 1787 | 69.7 |
| 390 | end | base | 15 | 3 | 1892 | 1817 | 75 | 4.0 | 75 | 4.0 | 1777 | 59.0 |
| 390 | end | aa | 15 | 3 | 1891 | 1815 | 76 | 4.0 | 76 | 4.0 | 1778 | 61.4 |
| 390 | end | cand | 15 | 3 | 1892 | 1814 | 78 | 4.1 | 78 | 4.1 | 1780 | 61.9 |
| 390 | hero | orig | 15 | 3 | 2621 | 2362 | 259 | 9.9 | 49 | 1.9 | 2568 | 32.0 |
| 390 | hero | base | 15 | 3 | 2668 | 2339 | 329 | 12.3 | 119 | 4.5 | 2560 | 31.9 |
| 390 | hero | aa | 15 | 3 | 2659 | 2349 | 310 | 11.7 | 115 | 4.3 | 2545 | 31.9 |
| 390 | hero | cand | 15 | 3 | 2657 | 2342 | 315 | 11.9 | 113 | 4.3 | 2545 | 32.0 |
| 1280 | end | orig | 15 | 3 | 1937 | 1067 | 870 | 44.9 | 869 | 44.9 | 1039 | 176.1 |
| 1280 | end | base | 15 | 3 | 1945 | 1071 | 874 | 44.9 | 874 | 44.9 | 1043 | 149.9 |
| 1280 | end | aa | 15 | 3 | 1961 | 1076 | 885 | 45.1 | 885 | 45.1 | 1037 | 183.5 |
| 1280 | end | cand | 15 | 3 | 1960 | 1088 | 872 | 44.5 | 872 | 44.5 | 1051 | 164.0 |
| 1280 | hero | orig | 15 | 3 | 2958 | 2281 | 677 | 22.9 | 647 | 21.9 | 2325 | 79.0 |
| 1280 | hero | base | 15 | 3 | 2965 | 2289 | 676 | 22.8 | 647 | 21.8 | 2325 | 76.1 |
| 1280 | hero | aa | 15 | 3 | 2969 | 2298 | 671 | 22.6 | 644 | 21.7 | 2326 | 77.6 |
| 1280 | hero | cand | 15 | 3 | 2975 | 2296 | 679 | 22.8 | 652 | 21.9 | 2325 | 80.7 |

### Fixed slow-event names of the traced reps (page renderer process; every row is always listed, n = 0 means the event never ran; long = 15 ms or more)

| width | window | arm | traced reps | event | events | long | longest ms | total ms | long durations ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | 15 | BeginMainFrame | 1802 | 25 | 53.9 | 10724.1 | 15.0, 15.3, 15.9, 16.1, 16.2, 16.3, 16.3, 16.5, 16.6, 19.0, 30.1, 31.8, 32.6, 32.9, 33.3, 33.5, 37.3, 38.4, 39.8, 41.4, 44.8, 44.9, 47.0, 52.1, 53.9 |
| 390 | end | orig | 15 | Paint | 15837 | 0 | 3.2 | 2226.6 | - |
| 390 | end | orig | 15 | UpdateLayoutTree | 2941 | 0 | 12.3 | 4381.9 | - |
| 390 | end | orig | 15 | Layout | 2331 | 0 | 1.3 | 411.2 | - |
| 390 | end | orig | 15 | image decode task | 7833 | 0 | 10.9 | 1073.5 | - |
| 390 | end | base | 15 | BeginMainFrame | 1792 | 15 | 51.7 | 11423.5 | 35.1, 37.7, 39.1, 39.9, 40.7, 41.5, 41.9, 43.1, 43.2, 44.5, 46.2, 46.6, 47.2, 49.6, 51.7 |
| 390 | end | base | 15 | Paint | 15784 | 0 | 3.3 | 2261.1 | - |
| 390 | end | base | 15 | UpdateLayoutTree | 2924 | 0 | 6.2 | 3495.5 | - |
| 390 | end | base | 15 | Layout | 2333 | 0 | 0.9 | 446.9 | - |
| 390 | end | base | 15 | image decode task | 7838 | 0 | 9.9 | 1074.5 | - |
| 390 | end | aa | 15 | BeginMainFrame | 1793 | 15 | 57.3 | 11640.0 | 37.5, 37.9, 38.8, 39.0, 40.0, 42.4, 43.6, 44.2, 45.4, 45.4, 47.1, 52.1, 54.0, 57.2, 57.3 |
| 390 | end | aa | 15 | Paint | 15827 | 0 | 3.5 | 2293.2 | - |
| 390 | end | aa | 15 | UpdateLayoutTree | 2926 | 0 | 6.7 | 3563.1 | - |
| 390 | end | aa | 15 | Layout | 2340 | 0 | 2.4 | 462.2 | - |
| 390 | end | aa | 15 | image decode task | 7796 | 0 | 10.1 | 1070.9 | - |
| 390 | end | cand | 15 | BeginMainFrame | 1795 | 15 | 56.0 | 10816.5 | 34.7, 38.0, 39.3, 40.0, 40.2, 40.3, 41.3, 42.6, 42.6, 44.0, 46.4, 46.5, 50.6, 52.0, 56.0 |
| 390 | end | cand | 15 | Paint | 15039 | 0 | 3.2 | 2198.8 | - |
| 390 | end | cand | 15 | UpdateLayoutTree | 2928 | 0 | 6.2 | 3361.4 | - |
| 390 | end | cand | 15 | Layout | 1463 | 0 | 0.8 | 354.3 | - |
| 390 | end | cand | 15 | image decode task | 7840 | 0 | 11.5 | 1069.5 | - |
| 390 | hero | orig | 15 | BeginMainFrame | 2583 | 6 | 15.4 | 10887.7 | 15.0, 15.1, 15.3, 15.3, 15.4, 15.4 |
| 390 | hero | orig | 15 | Paint | 15753 | 0 | 2.4 | 1481.9 | - |
| 390 | hero | orig | 15 | UpdateLayoutTree | 6040 | 0 | 4.8 | 3853.9 | - |
| 390 | hero | orig | 15 | Layout | 2729 | 0 | 2.1 | 425.4 | - |
| 390 | hero | orig | 15 | image decode task | 1729 | 30 | 53.8 | 2255.4 | 30.8, 30.9, 31.0, 31.0, 31.0, 31.2, 31.2, 31.2, 31.3, 31.4, 31.5, 31.5, 31.7, 33.2, 33.6, 51.8, 51.9, 52.1, 52.3, 52.5, 52.5, 52.5, 52.6, 52.6, 52.7, 52.8, 52.9, 53.1, 53.4, 53.8 |
| 390 | hero | base | 15 | BeginMainFrame | 2575 | 12 | 17.9 | 11081.7 | 15.0, 15.2, 15.4, 15.4, 16.1, 16.5, 16.6, 16.6, 16.7, 17.2, 17.5, 17.9 |
| 390 | hero | base | 15 | Paint | 15049 | 0 | 2.8 | 1434.8 | - |
| 390 | hero | base | 15 | UpdateLayoutTree | 5941 | 0 | 3.9 | 3115.4 | - |
| 390 | hero | base | 15 | Layout | 2737 | 0 | 1.7 | 412.7 | - |
| 390 | hero | base | 15 | image decode task | 1862 | 60 | 54.9 | 3178.8 | 30.7, 30.8, 30.9, 31.0, 31.0, 31.0, 31.0, 31.1, 31.1, 31.1, 31.2, 31.2, 31.2, 31.2, 31.2, 31.3, 31.3, 31.4, 31.4, 31.4, 31.4, 31.5, 31.6, 31.6, 31.7, 31.8, 31.8, 31.8, 31.8, 31.8, 33.2, 33.3, 33.5, 33.7, 33.7, 33.7, 33.8, 33.8, 33.8, 33.8, 33.9, 34.0, 34.2, 34.4, 34.4, 51.8, 51.8, 52.0, 52.5, 52.5, 52.7, 52.8, 52.8, 52.8, 53.1, 53.1, 53.4, 53.5, 54.0, 54.9 |
| 390 | hero | aa | 15 | BeginMainFrame | 2560 | 12 | 19.4 | 11022.3 | 15.1, 16.2, 16.5, 16.7, 16.9, 17.0, 17.1, 17.1, 17.5, 17.6, 18.0, 19.4 |
| 390 | hero | aa | 15 | Paint | 15014 | 0 | 3.7 | 1439.2 | - |
| 390 | hero | aa | 15 | UpdateLayoutTree | 5924 | 0 | 4.0 | 3111.5 | - |
| 390 | hero | aa | 15 | Layout | 2735 | 0 | 2.2 | 420.7 | - |
| 390 | hero | aa | 15 | image decode task | 1822 | 60 | 53.0 | 3173.3 | 30.9, 30.9, 30.9, 31.0, 31.1, 31.1, 31.1, 31.2, 31.2, 31.2, 31.3, 31.3, 31.3, 31.3, 31.3, 31.4, 31.4, 31.4, 31.4, 31.5, 31.5, 31.6, 31.6, 31.6, 31.7, 31.7, 31.8, 31.9, 32.1, 32.6, 33.5, 33.6, 33.7, 33.7, 33.7, 33.7, 33.7, 33.8, 34.0, 34.0, 34.0, 34.0, 34.1, 34.3, 39.0, 51.5, 51.7, 51.8, 51.8, 52.1, 52.1, 52.2, 52.2, 52.3, 52.5, 52.6, 52.7, 52.8, 52.9, 53.0 |
| 390 | hero | cand | 15 | BeginMainFrame | 2560 | 12 | 19.6 | 11231.4 | 15.1, 15.3, 15.9, 16.7, 16.7, 16.8, 16.8, 16.9, 17.0, 18.3, 18.6, 19.6 |
| 390 | hero | cand | 15 | Paint | 15024 | 0 | 2.9 | 1452.2 | - |
| 390 | hero | cand | 15 | UpdateLayoutTree | 5932 | 0 | 4.0 | 3158.6 | - |
| 390 | hero | cand | 15 | Layout | 2741 | 0 | 2.3 | 422.6 | - |
| 390 | hero | cand | 15 | image decode task | 1815 | 61 | 53.2 | 3183.2 | 15.5, 30.8, 30.9, 30.9, 31.0, 31.1, 31.1, 31.1, 31.1, 31.1, 31.2, 31.2, 31.2, 31.3, 31.3, 31.3, 31.3, 31.3, 31.3, 31.3, 31.4, 31.4, 31.4, 31.5, 31.6, 31.6, 31.6, 31.7, 32.0, 32.4, 32.7, 33.4, 33.6, 33.6, 33.7, 33.7, 33.7, 33.8, 33.8, 33.8, 33.9, 34.0, 34.1, 34.1, 34.1, 34.2, 51.6, 51.6, 51.7, 52.1, 52.2, 52.2, 52.3, 52.4, 52.6, 52.7, 52.8, 52.9, 53.0, 53.1, 53.2 |
| 1280 | end | orig | 15 | BeginMainFrame | 1054 | 33 | 52.0 | 6970.0 | 15.1, 15.7, 16.1, 16.1, 16.4, 16.7, 16.8, 16.8, 17.2, 17.7, 18.4, 18.7, 18.8, 18.9, 18.9, 19.1, 19.1, 19.2, 19.4, 19.5, 20.0, 20.1, 20.2, 20.8, 20.9, 23.2, 23.6, 24.3, 27.2, 41.3, 43.5, 49.1, 52.0 |
| 1280 | end | orig | 15 | Paint | 13235 | 0 | 3.7 | 1879.0 | - |
| 1280 | end | orig | 15 | UpdateLayoutTree | 1625 | 0 | 11.9 | 2585.9 | - |
| 1280 | end | orig | 15 | Layout | 1176 | 0 | 2.8 | 306.2 | - |
| 1280 | end | orig | 15 | image decode task | 7557 | 3 | 19.5 | 5346.3 | 15.7, 19.1, 19.5 |
| 1280 | end | base | 15 | BeginMainFrame | 1059 | 22 | 51.5 | 7598.9 | 15.2, 15.4, 15.4, 15.5, 15.7, 15.9, 15.9, 16.0, 16.4, 17.3, 17.7, 19.2, 19.7, 20.3, 23.4, 23.5, 28.8, 41.1, 47.8, 48.7, 51.2, 51.5 |
| 1280 | end | base | 15 | Paint | 13297 | 0 | 4.6 | 1977.9 | - |
| 1280 | end | base | 15 | UpdateLayoutTree | 1634 | 0 | 9.0 | 2071.8 | - |
| 1280 | end | base | 15 | Layout | 1159 | 0 | 3.1 | 307.0 | - |
| 1280 | end | base | 15 | image decode task | 7734 | 2 | 18.3 | 5285.1 | 15.7, 18.3 |
| 1280 | end | aa | 15 | BeginMainFrame | 1054 | 42 | 59.2 | 7784.6 | 15.0, 15.0, 15.1, 15.2, 15.2, 15.3, 15.4, 15.4, 15.5, 15.5, 15.6, 15.6, 15.7, 16.0, 16.1, 16.1, 16.3, 16.3, 16.3, 16.3, 16.4, 16.5, 16.8, 17.0, 17.6, 18.1, 18.3, 19.2, 19.5, 19.7, 20.7, 20.9, 21.7, 24.1, 45.3, 47.8, 49.9, 50.5, 51.6, 52.7, 54.9, 59.2 |
| 1280 | end | aa | 15 | Paint | 13267 | 0 | 3.9 | 1998.8 | - |
| 1280 | end | aa | 15 | UpdateLayoutTree | 1621 | 0 | 7.8 | 2083.5 | - |
| 1280 | end | aa | 15 | Layout | 1138 | 0 | 2.5 | 308.5 | - |
| 1280 | end | aa | 15 | image decode task | 7683 | 2 | 16.5 | 5356.5 | 15.4, 16.5 |
| 1280 | end | cand | 15 | BeginMainFrame | 1070 | 25 | 56.9 | 7421.2 | 15.0, 15.1, 15.2, 15.4, 15.4, 15.5, 16.0, 16.8, 17.0, 17.9, 18.2, 18.8, 20.3, 21.0, 21.1, 21.6, 22.3, 24.5, 43.5, 45.4, 45.9, 50.2, 51.1, 51.9, 56.9 |
| 1280 | end | cand | 15 | Paint | 12963 | 0 | 4.5 | 2007.4 | - |
| 1280 | end | cand | 15 | UpdateLayoutTree | 1649 | 0 | 7.7 | 2041.6 | - |
| 1280 | end | cand | 15 | Layout | 821 | 0 | 1.9 | 253.6 | - |
| 1280 | end | cand | 15 | image decode task | 7611 | 1 | 20.3 | 5367.7 | 20.3 |
| 1280 | hero | orig | 15 | BeginMainFrame | 2340 | 0 | 13.8 | 9801.1 | - |
| 1280 | hero | orig | 15 | Paint | 6514 | 0 | 2.6 | 906.5 | - |
| 1280 | hero | orig | 15 | UpdateLayoutTree | 5640 | 0 | 5.9 | 3945.0 | - |
| 1280 | hero | orig | 15 | Layout | 1482 | 0 | 0.7 | 300.2 | - |
| 1280 | hero | orig | 15 | image decode task | 642 | 2 | 18.7 | 1053.3 | 16.7, 18.7 |
| 1280 | hero | base | 15 | BeginMainFrame | 2341 | 0 | 13.9 | 10268.0 | - |
| 1280 | hero | base | 15 | Paint | 6477 | 0 | 2.7 | 970.7 | - |
| 1280 | hero | base | 15 | UpdateLayoutTree | 5624 | 0 | 4.7 | 3142.7 | - |
| 1280 | hero | base | 15 | Layout | 1474 | 0 | 0.8 | 316.3 | - |
| 1280 | hero | base | 15 | image decode task | 505 | 0 | 11.8 | 955.4 | - |
| 1280 | hero | aa | 15 | BeginMainFrame | 2341 | 0 | 13.4 | 10254.2 | - |
| 1280 | hero | aa | 15 | Paint | 6461 | 0 | 2.7 | 968.3 | - |
| 1280 | hero | aa | 15 | UpdateLayoutTree | 5626 | 0 | 4.6 | 3158.9 | - |
| 1280 | hero | aa | 15 | Layout | 1470 | 0 | 0.9 | 318.5 | - |
| 1280 | hero | aa | 15 | image decode task | 519 | 0 | 11.4 | 937.3 | - |
| 1280 | hero | cand | 15 | BeginMainFrame | 2340 | 0 | 13.3 | 10278.4 | - |
| 1280 | hero | cand | 15 | Paint | 6456 | 0 | 2.7 | 976.4 | - |
| 1280 | hero | cand | 15 | UpdateLayoutTree | 5630 | 0 | 4.4 | 3159.8 | - |
| 1280 | hero | cand | 15 | Layout | 1468 | 0 | 0.8 | 321.9 | - |
| 1280 | hero | cand | 15 | image decode task | 508 | 0 | 11.6 | 961.7 | - |
