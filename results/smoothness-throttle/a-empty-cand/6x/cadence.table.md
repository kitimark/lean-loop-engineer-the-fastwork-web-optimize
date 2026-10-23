Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39924693045:smoothness-1280-1, 1280px, window hero** (CPU throttle 6x, candidate default, A/A spread 4.84 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1079 | 24.37 | 7.65 | 7 of 7 | 12,14,12,14,14,13,9 | 33.3 | 66.7 | 83.4 | 149.9 |
| base | 7 | 1093 | 25.70 | 3.85 | 7 of 7 | 9,9,9,10,7,7,8 | 33.3 | 66.6 | 83.4 | 133.3 |
| aa | 7 | 1090 | 25.41 | 4.84 | 7 of 7 | 8,8,10,9,9,11,9 | 33.3 | 66.6 | 83.4 | 133.3 |
| cand | 7 | 1093 | 24.42 | 3.68 | 7 of 7 | 8,12,9,11,10,7,11 | 33.3 | 66.7 | 83.4 | 116.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924693045:smoothness-1280-1, 1280px, window end** (CPU throttle 6x, candidate default, A/A spread 15.00 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 345 | 37.97 | 7.05 | 7 of 7 | 13,14,14,14,14,15,14 | 33.3 | 100.0 | 133.3 | 149.9 |
| base | 7 | 320 | 46.87 | 15.00 | 7 of 7 | 16,17,14,17,15,14,17 | 33.4 | 100.0 | 133.3 | 133.4 |
| aa | 7 | 319 | 48.90 | 7.59 | 7 of 7 | 15,18,12,17,14,16,17 | 33.4 | 100.0 | 116.6 | 133.3 |
| cand | 7 | 317 | 47.63 | 10.35 | 7 of 7 | 14,14,15,18,19,18,16 | 33.4 | 100.0 | 133.4 | 150.1 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924693045:smoothness-1280-2, 1280px, window hero** (CPU throttle 6x, candidate default, A/A spread 4.98 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1078 | 22.91 | 4.41 | 7 of 7 | 12,8,7,13,12,10,12 | 33.3 | 66.7 | 83.4 | 116.7 |
| base | 7 | 1087 | 24.47 | 4.98 | 7 of 7 | 10,8,9,7,8,8,9 | 33.3 | 66.6 | 83.4 | 116.7 |
| aa | 7 | 1087 | 23.55 | 4.87 | 7 of 7 | 8,9,8,10,9,10,8 | 33.3 | 66.6 | 83.4 | 116.7 |
| cand | 7 | 1086 | 23.29 | 4.67 | 7 of 7 | 11,10,8,10,9,8,8 | 33.3 | 66.7 | 99.9 | 116.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924693045:smoothness-1280-2, 1280px, window end** (CPU throttle 6x, candidate default, A/A spread 14.54 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 346 | 37.86 | 13.23 | 7 of 7 | 12,13,13,14,14,13,11 | 33.3 | 100.0 | 133.3 | 150.1 |
| base | 7 | 327 | 46.78 | 14.54 | 7 of 7 | 14,14,15,18,15,15,16 | 33.4 | 100.0 | 116.6 | 133.4 |
| aa | 7 | 335 | 42.38 | 8.93 | 7 of 7 | 16,17,16,13,13,14,16 | 33.4 | 100.0 | 133.3 | 150.0 |
| cand | 7 | 325 | 46.76 | 12.34 | 7 of 7 | 15,16,14,15,13,16,17 | 33.4 | 100.0 | 116.7 | 166.6 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924693045:smoothness-1280-3, 1280px, window hero** (CPU throttle 6x, candidate default, A/A spread 4.96 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1068 | 29.58 | 4.69 | 7 of 7 | 24,17,26,21,24,24,17 | 33.3 | 66.7 | 100.0 | 133.4 |
| base | 7 | 1072 | 29.47 | 3.24 | 7 of 7 | 10,12,9,9,11,8,13 | 33.3 | 66.7 | 83.4 | 133.4 |
| aa | 7 | 1070 | 29.71 | 4.96 | 7 of 7 | 14,15,11,10,12,8,11 | 33.3 | 66.7 | 83.4 | 150.0 |
| cand | 7 | 1069 | 29.56 | 5.85 | 7 of 7 | 8,11,14,13,11,11,12 | 33.3 | 66.7 | 99.9 | 166.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: second; base vs cand: same; orig vs cand: second

**run 39924693045:smoothness-1280-3, 1280px, window end** (CPU throttle 6x, candidate default, A/A spread 9.91 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 311 | 47.26 | 14.91 | 7 of 7 | 16,15,16,15,16,16,13 | 33.4 | 100.0 | 116.7 | 133.3 |
| base | 7 | 293 | 55.29 | 7.86 | 7 of 7 | 17,16,16,13,16,16,16 | 50.0 | 116.6 | 133.3 | 183.3 |
| aa | 7 | 312 | 53.84 | 9.91 | 7 of 7 | 17,16,13,16,16,14,14 | 50.0 | 100.0 | 133.4 | 149.9 |
| cand | 7 | 307 | 50.81 | 12.32 | 7 of 7 | 15,17,17,16,15,14,18 | 49.9 | 100.1 | 133.3 | 133.4 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924693045:smoothness-390-1, 390px, window hero** (CPU throttle 6x, candidate default, A/A spread 10.66 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1073 | 37.55 | 9.60 | 7 of 7 | 10,11,11,9,10,12,11 | 33.4 | 66.7 | 233.3 | 266.7 |
| base | 7 | 1079 | 40.50 | 10.51 | 7 of 7 | 14,10,11,14,17,10,12 | 33.4 | 66.7 | 166.7 | 233.4 |
| aa | 7 | 1085 | 38.43 | 10.66 | 7 of 7 | 12,15,11,13,16,14,13 | 33.4 | 66.7 | 166.7 | 233.4 |
| cand | 7 | 1080 | 37.22 | 12.83 | 7 of 7 | 14,14,14,13,12,14,11 | 33.4 | 66.7 | 150.1 | 233.3 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924693045:smoothness-390-1, 390px, window end** (CPU throttle 6x, candidate default, A/A spread 16.97 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 414 | 32.60 | 4.80 | 7 of 7 | 12,11,13,13,13,10,13 | 16.7 | 83.4 | 100.0 | 100.1 |
| base | 7 | 399 | 33.83 | 7.11 | 7 of 7 | 11,14,12,11,11,12,9 | 33.3 | 83.3 | 100.0 | 116.7 |
| aa | 7 | 392 | 38.01 | 16.97 | 7 of 7 | 12,11,8,14,12,12,11 | 33.3 | 83.3 | 100.0 | 133.3 |
| cand | 7 | 417 | 33.09 | 19.87 | 7 of 7 | 10,12,11,10,11,9,9 | 33.3 | 83.3 | 99.9 | 100.0 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924693045:smoothness-390-2, 390px, window hero** (CPU throttle 6x, candidate default, A/A spread 25.65 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1067 | 38.98 | 20.27 | 7 of 7 | 15,16,8,11,11,9,8 | 33.4 | 66.7 | 216.7 | 283.4 |
| base | 7 | 1068 | 38.76 | 25.65 | 7 of 7 | 14,18,9,12,17,11,17 | 33.4 | 66.7 | 166.7 | 250.0 |
| aa | 7 | 1064 | 41.63 | 14.36 | 7 of 7 | 19,20,17,10,15,15,12 | 33.4 | 66.7 | 183.3 | 250.0 |
| cand | 7 | 1074 | 37.70 | 30.47 | 7 of 7 | 19,21,11,8,13,13,11 | 33.4 | 66.7 | 166.6 | 250.0 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924693045:smoothness-390-2, 390px, window end** (CPU throttle 6x, candidate default, A/A spread 12.86 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 409 | 34.22 | 11.46 | 7 of 7 | 12,12,11,13,12,13,14 | 16.7 | 83.4 | 100.0 | 100.1 |
| base | 7 | 390 | 37.43 | 12.86 | 7 of 7 | 14,11,10,11,11,10,12 | 33.3 | 83.3 | 100.0 | 100.0 |
| aa | 7 | 401 | 34.66 | 11.66 | 7 of 7 | 10,12,10,10,10,12,11 | 33.3 | 83.3 | 83.4 | 100.0 |
| cand | 7 | 399 | 35.08 | 13.73 | 7 of 7 | 13,11,10,11,11,13,11 | 33.3 | 83.3 | 99.9 | 116.6 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924693045:smoothness-390-3, 390px, window hero** (CPU throttle 6x, candidate default, A/A spread 16.27 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1081 | 31.54 | 7.10 | 7 of 7 | 9,11,9,9,9,10,10 | 33.3 | 66.7 | 216.7 | 250.0 |
| base | 7 | 1089 | 31.40 | 16.27 | 7 of 7 | 10,11,9,9,12,10,10 | 33.3 | 66.7 | 150.0 | 216.7 |
| aa | 7 | 1087 | 34.13 | 9.68 | 7 of 7 | 15,11,14,9,12,10,10 | 33.4 | 66.7 | 150.1 | 233.4 |
| cand | 7 | 1075 | 34.79 | 10.52 | 7 of 7 | 11,12,9,9,12,7,10 | 33.4 | 66.7 | 150.0 | 233.2 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924693045:smoothness-390-3, 390px, window end** (CPU throttle 6x, candidate default, A/A spread 14.37 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 430 | 30.69 | 7.44 | 7 of 7 | 12,13,12,11,13,14,13 | 16.7 | 83.3 | 99.9 | 100.1 |
| base | 7 | 423 | 31.91 | 14.37 | 7 of 7 | 12,10,11,10,12,11,10 | 33.3 | 83.3 | 100.0 | 100.0 |
| aa | 7 | 413 | 34.86 | 2.95 | 7 of 7 | 12,13,10,10,11,10,10 | 33.3 | 83.3 | 83.4 | 100.1 |
| cand | 7 | 420 | 32.38 | 12.94 | 7 of 7 | 13,12,11,11,9,10,10 | 33.3 | 66.7 | 83.4 | 116.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | base | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 1.23 | 14.37 |
| 390 | end | base | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | -0.74 | 14.37 |
| 390 | end | orig | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 0.86 | 14.37 |
| 390 | hero | orig | base | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | -0.14 | 16.27 |
| 390 | hero | base | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | -1.06 | 16.27 |
| 390 | hero | orig | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | -0.33 | 16.27 |
| 1280 | end | orig | base | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 8.90 | 14.54 |
| 1280 | end | base | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | -0.02 | 14.54 |
| 1280 | end | orig | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 8.90 | 14.54 |
| 1280 | hero | orig | base | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 1 / 2 / 0 | not told apart | 1.33 | 4.96 |
| 1280 | hero | base | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | -1.18 | 4.96 |
| 1280 | hero | orig | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 1 / 2 / 0 | not told apart | 0.05 | 4.96 |

Samples: 39924693045:smoothness-390-1, 39924693045:smoothness-390-2, 39924693045:smoothness-390-3, 39924693045:smoothness-1280-1, 39924693045:smoothness-1280-2, 39924693045:smoothness-1280-3

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39924693045:smoothness-1280-1 | 1280 | hero | orig | 7 | 88 | 66.7 | 756 | 7 |
| 39924693045:smoothness-1280-1 | 1280 | hero | base | 7 | 59 | 83.3 | 840 | 7 |
| 39924693045:smoothness-1280-1 | 1280 | hero | aa | 7 | 64 | 83.3 | 840 | 7 |
| 39924693045:smoothness-1280-1 | 1280 | hero | cand | 7 | 68 | 83.3 | 840 | 7 |
| 39924693045:smoothness-1280-1 | 1280 | end | orig | 7 | 98 | 83.3 | 8269 | 7 |
| 39924693045:smoothness-1280-1 | 1280 | end | base | 7 | 110 | 66.7 | 8269 | 7 |
| 39924693045:smoothness-1280-1 | 1280 | end | aa | 7 | 109 | 83.3 | 8269 | 7 |
| 39924693045:smoothness-1280-1 | 1280 | end | cand | 7 | 114 | 66.7 | 8269 | 7 |
| 39924693045:smoothness-1280-2 | 1280 | hero | orig | 7 | 74 | 83.2 | 840 | 7 |
| 39924693045:smoothness-1280-2 | 1280 | hero | base | 7 | 59 | 83.3 | 840 | 7 |
| 39924693045:smoothness-1280-2 | 1280 | hero | aa | 7 | 62 | 83.3 | 840 | 7 |
| 39924693045:smoothness-1280-2 | 1280 | hero | cand | 7 | 64 | 83.3 | 840 | 7 |
| 39924693045:smoothness-1280-2 | 1280 | end | orig | 7 | 90 | 83.3 | 8269 | 7 |
| 39924693045:smoothness-1280-2 | 1280 | end | base | 7 | 107 | 66.8 | 8269 | 7 |
| 39924693045:smoothness-1280-2 | 1280 | end | aa | 7 | 105 | 83.2 | 8269 | 7 |
| 39924693045:smoothness-1280-2 | 1280 | end | cand | 7 | 106 | 66.8 | 8269 | 7 |
| 39924693045:smoothness-1280-3 | 1280 | hero | orig | 7 | 153 | 66.7 | 630 | 7 |
| 39924693045:smoothness-1280-3 | 1280 | hero | base | 7 | 72 | 83.3 | 840 | 7 |
| 39924693045:smoothness-1280-3 | 1280 | hero | aa | 7 | 81 | 83.3 | 798 | 7 |
| 39924693045:smoothness-1280-3 | 1280 | hero | cand | 7 | 80 | 83.3 | 798 | 7 |
| 39924693045:smoothness-1280-3 | 1280 | end | orig | 7 | 107 | 83.3 | 8269 | 7 |
| 39924693045:smoothness-1280-3 | 1280 | end | base | 7 | 110 | 83.3 | 8269 | 7 |
| 39924693045:smoothness-1280-3 | 1280 | end | aa | 7 | 106 | 66.8 | 8269 | 7 |
| 39924693045:smoothness-1280-3 | 1280 | end | cand | 7 | 112 | 83.3 | 8269 | 7 |
| 39924693045:smoothness-390-1 | 390 | hero | orig | 7 | 74 | 83.3 | 1722 | 7 |
| 39924693045:smoothness-390-1 | 390 | hero | base | 7 | 88 | 83.3 | 1596 | 7 |
| 39924693045:smoothness-390-1 | 390 | hero | aa | 7 | 94 | 66.7 | 1596 | 7 |
| 39924693045:smoothness-390-1 | 390 | hero | cand | 7 | 92 | 83.2 | 1596 | 7 |
| 39924693045:smoothness-390-1 | 390 | end | orig | 7 | 85 | 83.3 | 5103 | 7 |
| 39924693045:smoothness-390-1 | 390 | end | base | 7 | 80 | 66.7 | 5103 | 7 |
| 39924693045:smoothness-390-1 | 390 | end | aa | 7 | 80 | 66.7 | 5103 | 7 |
| 39924693045:smoothness-390-1 | 390 | end | cand | 7 | 72 | 66.7 | 5103 | 7 |
| 39924693045:smoothness-390-2 | 390 | hero | orig | 7 | 78 | 83.2 | 1680 | 7 |
| 39924693045:smoothness-390-2 | 390 | hero | base | 7 | 98 | 66.8 | 1596 | 7 |
| 39924693045:smoothness-390-2 | 390 | hero | aa | 7 | 108 | 66.7 | 1596 | 7 |
| 39924693045:smoothness-390-2 | 390 | hero | cand | 7 | 96 | 66.7 | 1596 | 7 |
| 39924693045:smoothness-390-2 | 390 | end | orig | 7 | 87 | 83.3 | 5103 | 7 |
| 39924693045:smoothness-390-2 | 390 | end | base | 7 | 79 | 66.8 | 5103 | 7 |
| 39924693045:smoothness-390-2 | 390 | end | aa | 7 | 75 | 66.7 | 5103 | 7 |
| 39924693045:smoothness-390-2 | 390 | end | cand | 7 | 80 | 66.7 | 5103 | 7 |
| 39924693045:smoothness-390-3 | 390 | hero | orig | 7 | 67 | 83.3 | 2058 | 7 |
| 39924693045:smoothness-390-3 | 390 | hero | base | 7 | 71 | 83.3 | 1596 | 7 |
| 39924693045:smoothness-390-3 | 390 | hero | aa | 7 | 81 | 83.3 | 1596 | 7 |
| 39924693045:smoothness-390-3 | 390 | hero | cand | 7 | 70 | 83.3 | 1596 | 7 |
| 39924693045:smoothness-390-3 | 390 | end | orig | 7 | 88 | 66.7 | 5103 | 7 |
| 39924693045:smoothness-390-3 | 390 | end | base | 7 | 76 | 66.7 | 5103 | 7 |
| 39924693045:smoothness-390-3 | 390 | end | aa | 7 | 76 | 66.7 | 5103 | 7 |
| 39924693045:smoothness-390-3 | 390 | end | cand | 7 | 76 | 66.7 | 5103 | 7 |
