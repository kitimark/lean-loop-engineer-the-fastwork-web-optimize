Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39927184622:smoothness-1280-1, 1280px, window hero** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 7.94 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1079 | 19.92 | 4.54 | 7 of 7 | 7,7,6,6,8,7,8 | 33.3 | 50.1 | 83.3 | 100.0 |
| base | 7 | 1080 | 19.25 | 7.94 | 7 of 7 | 6,7,17,6,7,6,5 | 33.3 | 50.1 | 83.4 | 133.4 |
| aa | 7 | 1079 | 18.62 | 3.89 | 7 of 7 | 6,9,7,5,6,6,8 | 33.2 | 50.1 | 83.4 | 100.1 |
| cand | 7 | 1078 | 17.34 | 6.06 | 7 of 7 | 9,4,7,7,5,7,6 | 33.2 | 50.1 | 83.4 | 100.1 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927184622:smoothness-1280-1, 1280px, window end** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 10.02 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 388 | 30.92 | 9.69 | 7 of 7 | 11,13,14,13,13,10,12 | 33.3 | 83.4 | 116.8 | 133.3 |
| base | 7 | 375 | 37.86 | 10.02 | 7 of 7 | 14,12,12,11,11,12,13 | 33.3 | 83.4 | 100.1 | 133.3 |
| aa | 7 | 386 | 35.75 | 3.98 | 7 of 7 | 14,13,12,14,12,15,12 | 33.3 | 83.4 | 100.1 | 133.4 |
| cand | 7 | 402 | 34.32 | 9.65 | 7 of 7 | 9,9,11,11,9,10,10 | 33.3 | 83.3 | 100.0 | 150.0 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927184622:smoothness-1280-2, 1280px, window hero** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 5.99 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1079 | 22.15 | 5.19 | 7 of 7 | 10,9,9,10,10,10,16 | 33.3 | 66.7 | 99.9 | 200.0 |
| base | 7 | 1084 | 24.72 | 1.93 | 7 of 7 | 12,10,8,9,11,8,9 | 33.3 | 66.7 | 83.4 | 116.7 |
| aa | 7 | 1087 | 25.02 | 5.99 | 7 of 7 | 9,12,9,8,12,6,8 | 33.3 | 66.7 | 83.4 | 200.0 |
| cand | 7 | 1088 | 25.27 | 2.57 | 7 of 7 | 8,9,9,9,11,10,9 | 33.3 | 66.7 | 83.4 | 116.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927184622:smoothness-1280-2, 1280px, window end** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 7.45 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 331 | 41.08 | 8.44 | 7 of 7 | 15,14,14,14,14,14,12 | 33.4 | 100.0 | 133.2 | 150.0 |
| base | 7 | 318 | 47.48 | 7.45 | 7 of 7 | 13,17,18,15,15,17,16 | 33.4 | 100.0 | 133.3 | 150.1 |
| aa | 7 | 319 | 46.08 | 7.07 | 7 of 7 | 15,18,18,16,16,14,18 | 33.4 | 100.0 | 133.4 | 150.0 |
| cand | 7 | 346 | 43.35 | 6.38 | 7 of 7 | 13,16,13,13,14,10,13 | 33.4 | 99.9 | 116.7 | 166.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927184622:smoothness-1280-3, 1280px, window hero** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 6.58 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1075 | 25.48 | 7.74 | 7 of 7 | 17,11,13,11,13,7,15 | 33.3 | 66.7 | 99.9 | 133.4 |
| base | 7 | 1081 | 27.10 | 6.58 | 7 of 7 | 10,9,10,9,7,8,12 | 33.3 | 66.7 | 100.0 | 116.7 |
| aa | 7 | 1080 | 25.83 | 4.39 | 7 of 7 | 9,8,10,11,7,10,10 | 33.3 | 66.6 | 99.9 | 150.0 |
| cand | 7 | 1086 | 25.87 | 5.49 | 7 of 7 | 9,8,11,10,9,9,8 | 33.3 | 66.6 | 100.0 | 150.1 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927184622:smoothness-1280-3, 1280px, window end** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 11.80 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 324 | 42.59 | 15.07 | 7 of 7 | 15,14,15,16,13,15,13 | 33.4 | 100.0 | 116.7 | 133.3 |
| base | 7 | 317 | 47.94 | 11.80 | 7 of 7 | 18,15,17,14,16,17,17 | 33.4 | 100.0 | 133.2 | 149.9 |
| aa | 7 | 302 | 51.32 | 9.43 | 7 of 7 | 15,16,16,16,16,18,15 | 49.9 | 100.0 | 116.7 | 133.3 |
| cand | 7 | 325 | 46.76 | 10.37 | 7 of 7 | 16,15,15,15,12,17,14 | 33.4 | 100.0 | 133.2 | 150.1 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927184622:smoothness-390-1, 390px, window hero** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 9.49 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1107 | 11.65 | 10.06 | 7 of 7 | 4,8,7,6,7,5,7 | 33.3 | 50.0 | 183.3 | 216.7 |
| base | 7 | 1086 | 11.32 | 6.34 | 7 of 7 | 5,5,7,7,6,6,5 | 33.3 | 50.0 | 150.0 | 200.1 |
| aa | 7 | 1079 | 12.51 | 9.49 | 7 of 7 | 6,7,7,7,7,6,6 | 33.3 | 50.1 | 150.0 | 233.3 |
| cand | 7 | 1083 | 12.18 | 11.34 | 7 of 7 | 6,5,6,5,8,7,5 | 33.3 | 50.0 | 133.4 | 200.0 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927184622:smoothness-390-1, 390px, window end** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 14.85 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 509 | 23.37 | 7.41 | 7 of 7 | 9,9,8,9,11,9,9 | 16.7 | 66.7 | 83.3 | 83.4 |
| base | 7 | 512 | 22.26 | 6.87 | 7 of 7 | 3,5,6,5,8,8,6 | 16.7 | 66.7 | 66.7 | 83.3 |
| aa | 7 | 515 | 20.38 | 14.85 | 7 of 7 | 4,6,6,6,9,5,7 | 16.7 | 66.7 | 83.3 | 83.4 |
| cand | 7 | 532 | 18.98 | 2.79 | 7 of 7 | 5,1,3,6,5,6,6 | 16.7 | 66.6 | 66.7 | 83.4 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: second

**run 39927184622:smoothness-390-2, 390px, window hero** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 15.50 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1052 | 41.63 | 8.61 | 7 of 7 | 12,13,11,22,15,14,13 | 33.4 | 66.7 | 250.0 | 333.3 |
| base | 7 | 1069 | 42.37 | 15.50 | 7 of 7 | 12,17,16,13,18,22,13 | 33.4 | 66.8 | 183.2 | 250.0 |
| aa | 7 | 1072 | 42.25 | 12.90 | 7 of 7 | 15,18,17,17,19,15,19 | 33.4 | 66.8 | 183.3 | 249.9 |
| cand | 7 | 1062 | 43.31 | 4.28 | 7 of 7 | 17,17,14,14,12,20,17 | 33.4 | 66.7 | 183.3 | 250.0 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927184622:smoothness-390-2, 390px, window end** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 16.26 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 397 | 34.25 | 6.52 | 7 of 7 | 11,10,12,12,12,14,11 | 33.2 | 83.4 | 100.0 | 116.7 |
| base | 7 | 389 | 37.78 | 16.26 | 7 of 7 | 13,12,11,10,12,11,10 | 33.3 | 83.3 | 99.9 | 116.8 |
| aa | 7 | 377 | 39.25 | 10.97 | 7 of 7 | 11,12,12,12,13,12,11 | 33.3 | 83.3 | 100.0 | 133.3 |
| cand | 7 | 412 | 31.55 | 11.20 | 7 of 7 | 11,10,11,11,12,12,10 | 33.3 | 83.3 | 99.9 | 116.8 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927184622:smoothness-390-3, 390px, window hero** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 11.47 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1102 | 26.40 | 4.21 | 7 of 7 | 9,9,6,8,9,9,8 | 33.3 | 66.6 | 200.0 | 250.0 |
| base | 7 | 1093 | 25.70 | 8.08 | 7 of 7 | 10,8,9,8,9,9,10 | 33.3 | 66.7 | 149.9 | 233.3 |
| aa | 7 | 1090 | 27.61 | 11.47 | 7 of 7 | 9,14,9,8,13,8,9 | 33.3 | 66.6 | 150.0 | 233.3 |
| cand | 7 | 1091 | 26.30 | 15.61 | 7 of 7 | 13,8,8,10,11,8,9 | 33.3 | 66.6 | 150.0 | 200.1 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927184622:smoothness-390-3, 390px, window end** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 13.19 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 446 | 28.92 | 11.82 | 7 of 7 | 13,12,11,12,12,12,12 | 16.7 | 83.3 | 83.4 | 116.7 |
| base | 7 | 450 | 32.00 | 11.34 | 7 of 7 | 9,11,10,8,10,11,12 | 16.7 | 66.7 | 83.4 | 100.0 |
| aa | 7 | 460 | 26.52 | 13.19 | 7 of 7 | 12,11,10,10,12,8,11 | 16.7 | 66.7 | 83.3 | 83.5 |
| cand | 7 | 476 | 24.15 | 6.15 | 7 of 7 | 10,11,9,10,10,10,9 | 16.7 | 66.7 | 83.3 | 83.4 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | base | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 3.08 | 14.85 |
| 390 | end | base | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | -6.23 | 14.85 |
| 390 | end | orig | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 1 / 2 / 0 | not told apart | -4.39 | 14.85 |
| 390 | hero | orig | base | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | -0.33 | 11.47 |
| 390 | hero | base | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 0.86 | 11.47 |
| 390 | hero | orig | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 0.53 | 11.47 |
| 1280 | end | orig | base | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 6.40 | 10.02 |
| 1280 | end | base | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | -3.54 | 10.02 |
| 1280 | end | orig | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 3.40 | 10.02 |
| 1280 | hero | orig | base | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 1.62 | 6.58 |
| 1280 | hero | base | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | -1.23 | 6.58 |
| 1280 | hero | orig | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 0.39 | 6.58 |

Samples: 39927184622:smoothness-390-1, 39927184622:smoothness-390-2, 39927184622:smoothness-390-3, 39927184622:smoothness-1280-1, 39927184622:smoothness-1280-2, 39927184622:smoothness-1280-3

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39927184622:smoothness-1280-1 | 1280 | hero | orig | 7 | 49 | 83.3 | 840 | 7 |
| 39927184622:smoothness-1280-1 | 1280 | hero | base | 7 | 54 | 83.2 | 798 | 7 |
| 39927184622:smoothness-1280-1 | 1280 | hero | aa | 7 | 47 | 83.3 | 840 | 7 |
| 39927184622:smoothness-1280-1 | 1280 | hero | cand | 7 | 45 | 83.3 | 840 | 7 |
| 39927184622:smoothness-1280-1 | 1280 | end | orig | 7 | 86 | 66.7 | 8269 | 7 |
| 39927184622:smoothness-1280-1 | 1280 | end | base | 7 | 85 | 66.7 | 8269 | 7 |
| 39927184622:smoothness-1280-1 | 1280 | end | aa | 7 | 92 | 66.7 | 8269 | 7 |
| 39927184622:smoothness-1280-1 | 1280 | end | cand | 7 | 69 | 66.7 | 8269 | 7 |
| 39927184622:smoothness-1280-2 | 1280 | hero | orig | 7 | 74 | 83.3 | 798 | 7 |
| 39927184622:smoothness-1280-2 | 1280 | hero | base | 7 | 67 | 83.3 | 840 | 7 |
| 39927184622:smoothness-1280-2 | 1280 | hero | aa | 7 | 64 | 83.3 | 798 | 7 |
| 39927184622:smoothness-1280-2 | 1280 | hero | cand | 7 | 65 | 83.3 | 840 | 7 |
| 39927184622:smoothness-1280-2 | 1280 | end | orig | 7 | 97 | 83.3 | 8269 | 7 |
| 39927184622:smoothness-1280-2 | 1280 | end | base | 7 | 111 | 66.8 | 8269 | 7 |
| 39927184622:smoothness-1280-2 | 1280 | end | aa | 7 | 115 | 66.8 | 8269 | 7 |
| 39927184622:smoothness-1280-2 | 1280 | end | cand | 7 | 92 | 66.8 | 8269 | 7 |
| 39927184622:smoothness-1280-3 | 1280 | hero | orig | 7 | 87 | 66.7 | 756 | 7 |
| 39927184622:smoothness-1280-3 | 1280 | hero | base | 7 | 65 | 83.3 | 840 | 7 |
| 39927184622:smoothness-1280-3 | 1280 | hero | aa | 7 | 65 | 83.3 | 798 | 7 |
| 39927184622:smoothness-1280-3 | 1280 | hero | cand | 7 | 64 | 83.3 | 840 | 7 |
| 39927184622:smoothness-1280-3 | 1280 | end | orig | 7 | 101 | 83.3 | 8269 | 7 |
| 39927184622:smoothness-1280-3 | 1280 | end | base | 7 | 114 | 66.8 | 8269 | 7 |
| 39927184622:smoothness-1280-3 | 1280 | end | aa | 7 | 112 | 83.3 | 8269 | 7 |
| 39927184622:smoothness-1280-3 | 1280 | end | cand | 7 | 104 | 66.7 | 8269 | 7 |
| 39927184622:smoothness-390-1 | 390 | hero | orig | 7 | 44 | 83.3 | 2100 | 7 |
| 39927184622:smoothness-390-1 | 390 | hero | base | 7 | 41 | 116.6 | 1596 | 7 |
| 39927184622:smoothness-390-1 | 390 | hero | aa | 7 | 46 | 83.3 | 1596 | 7 |
| 39927184622:smoothness-390-1 | 390 | hero | cand | 7 | 42 | 100.0 | 1596 | 7 |
| 39927184622:smoothness-390-1 | 390 | end | orig | 7 | 64 | 66.7 | 5103 | 7 |
| 39927184622:smoothness-390-1 | 390 | end | base | 7 | 41 | 66.7 | 5103 | 7 |
| 39927184622:smoothness-390-1 | 390 | end | aa | 7 | 43 | 66.7 | 5103 | 7 |
| 39927184622:smoothness-390-1 | 390 | end | cand | 7 | 32 | 66.7 | 5103 | 7 |
| 39927184622:smoothness-390-2 | 390 | hero | orig | 7 | 100 | 66.7 | 1722 | 7 |
| 39927184622:smoothness-390-2 | 390 | hero | base | 7 | 111 | 66.7 | 1596 | 7 |
| 39927184622:smoothness-390-2 | 390 | hero | aa | 7 | 120 | 66.7 | 1596 | 7 |
| 39927184622:smoothness-390-2 | 390 | hero | cand | 7 | 111 | 66.7 | 1596 | 7 |
| 39927184622:smoothness-390-2 | 390 | end | orig | 7 | 82 | 83.3 | 5103 | 7 |
| 39927184622:smoothness-390-2 | 390 | end | base | 7 | 79 | 66.8 | 5103 | 7 |
| 39927184622:smoothness-390-2 | 390 | end | aa | 7 | 83 | 83.2 | 5103 | 7 |
| 39927184622:smoothness-390-2 | 390 | end | cand | 7 | 77 | 66.7 | 5103 | 7 |
| 39927184622:smoothness-390-3 | 390 | hero | orig | 7 | 58 | 83.3 | 2058 | 7 |
| 39927184622:smoothness-390-3 | 390 | hero | base | 7 | 63 | 83.3 | 1596 | 7 |
| 39927184622:smoothness-390-3 | 390 | hero | aa | 7 | 70 | 83.2 | 1596 | 7 |
| 39927184622:smoothness-390-3 | 390 | hero | cand | 7 | 67 | 83.3 | 1596 | 7 |
| 39927184622:smoothness-390-3 | 390 | end | orig | 7 | 84 | 66.7 | 5103 | 7 |
| 39927184622:smoothness-390-3 | 390 | end | base | 7 | 71 | 66.7 | 5103 | 7 |
| 39927184622:smoothness-390-3 | 390 | end | aa | 7 | 74 | 66.7 | 5103 | 7 |
| 39927184622:smoothness-390-3 | 390 | end | cand | 7 | 69 | 66.7 | 5103 | 7 |
