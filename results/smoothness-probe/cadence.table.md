Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39580977630:smoothness-1280, 1280px, window hero** (candidate ?preset=v2-proved, A/A spread 1.94 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 3.96 | 1.29 | 2 of 7 | 1,0,0,0,1,0,0 | 16.7 | 33.4 | 50.0 | 83.3 |
| base | 7 | 1086 | 4.32 | 0.64 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 50.1 |
| aa | 7 | 1085 | 4.33 | 1.94 | 1 of 7 | 0,0,0,0,2,0,0 | 16.7 | 33.4 | 50.1 | 83.3 |
| cand | 7 | 1085 | 4.33 | 1.29 | 2 of 7 | 0,0,0,0,1,0,1 | 16.7 | 33.4 | 50.0 | 83.3 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39580977630:smoothness-1280, 1280px, window end** (candidate ?preset=v2-proved, A/A spread 6.64 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 510 | 15.29 | 6.25 | 7 of 7 | 3,2,3,2,3,3,3 | 33.3 | 50.1 | 66.7 | 116.7 |
| base | 7 | 517 | 17.79 | 5.64 | 7 of 7 | 4,3,3,4,3,3,1 | 33.3 | 50.1 | 66.8 | 116.7 |
| aa | 7 | 519 | 17.53 | 6.64 | 7 of 7 | 3,3,2,4,3,4,4 | 33.3 | 50.1 | 66.7 | 83.3 |
| cand | 7 | 524 | 15.83 | 5.66 | 7 of 7 | 2,1,2,4,3,3,3 | 33.2 | 50.1 | 66.7 | 116.8 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39580977630:smoothness-390, 390px, window hero** (candidate ?preset=v2-proved, A/A spread 0.02 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1208 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 33.3 | 33.4 |
| base | 7 | 1207 | 0.57 | 0.02 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| aa | 7 | 1205 | 0.58 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| cand | 7 | 1212 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.3 |

Rate verdicts: orig vs base: first; base vs cand: same; orig vs cand: first
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39580977630:smoothness-390, 390px, window end** (candidate ?preset=v2-proved, A/A spread 1.69 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 833 | 0.60 | 1.69 | 1 of 7 | 1,0,0,0,0,0,0 | 16.7 | 33.3 | 33.4 | 66.7 |
| base | 7 | 835 | 0.95 | 1.68 | 1 of 7 | 0,0,0,1,0,0,0 | 16.7 | 16.8 | 33.4 | 66.7 |
| aa | 7 | 831 | 0.96 | 1.69 | 5 of 7 | 0,1,1,1,1,0,1 | 16.7 | 16.8 | 33.4 | 66.7 |
| cand | 7 | 831 | 0.84 | 0.00 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 66.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39583122954:smoothness-1280-1, 1280px, window hero** (candidate ?preset=v2-proved, A/A spread 1.94 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 3.22 | 1.29 | 1 of 7 | 0,0,0,0,0,1,0 | 16.7 | 33.4 | 50.0 | 83.4 |
| base | 7 | 1085 | 4.33 | 1.94 | 2 of 7 | 0,0,0,0,2,0,1 | 16.7 | 33.4 | 50.0 | 83.3 |
| aa | 7 | 1085 | 4.70 | 0.65 | 1 of 7 | 0,0,0,0,1,0,0 | 16.7 | 33.4 | 50.0 | 66.6 |
| cand | 7 | 1086 | 4.32 | 1.96 | 2 of 7 | 0,1,0,1,0,0,0 | 16.7 | 33.4 | 50.1 | 83.3 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39583122954:smoothness-1280-1, 1280px, window end** (candidate ?preset=v2-proved, A/A spread 5.76 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 513 | 15.98 | 7.07 | 7 of 7 | 2,5,3,2,3,3,3 | 33.3 | 50.1 | 66.7 | 83.4 |
| base | 7 | 520 | 15.38 | 5.76 | 7 of 7 | 4,1,4,3,2,3,3 | 33.2 | 50.1 | 66.7 | 116.7 |
| aa | 7 | 527 | 16.31 | 3.70 | 7 of 7 | 2,2,2,2,2,3,2 | 33.2 | 50.1 | 66.7 | 83.4 |
| cand | 7 | 523 | 16.25 | 6.38 | 7 of 7 | 4,3,2,2,4,3,1 | 33.2 | 50.1 | 66.7 | 116.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39583122954:smoothness-1280-2, 1280px, window hero** (candidate ?preset=v2-proved, A/A spread 0.64 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 3.41 | 1.93 | 1 of 7 | 0,1,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 66.6 |
| base | 7 | 1086 | 3.95 | 0.61 | 1 of 7 | 1,0,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 66.6 |
| aa | 7 | 1085 | 4.23 | 0.64 | 2 of 7 | 1,0,0,0,0,1,0 | 16.7 | 33.4 | 50.1 | 83.4 |
| cand | 7 | 1085 | 4.33 | 1.94 | 3 of 7 | 1,1,0,0,0,1,0 | 16.7 | 33.4 | 50.0 | 66.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: first
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39583122954:smoothness-1280-2, 1280px, window end** (candidate ?preset=v2-proved, A/A spread 7.23 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 520 | 15.00 | 3.06 | 7 of 7 | 4,3,2,3,5,2,2 | 33.2 | 50.1 | 66.7 | 116.7 |
| base | 7 | 526 | 15.77 | 7.23 | 7 of 7 | 3,3,1,3,3,2,3 | 16.8 | 50.1 | 66.7 | 116.7 |
| aa | 7 | 531 | 16.38 | 6.08 | 7 of 7 | 4,3,2,5,2,2,2 | 16.8 | 50.1 | 66.7 | 83.3 |
| cand | 7 | 533 | 15.38 | 7.08 | 7 of 7 | 3,3,4,3,2,3,2 | 16.8 | 50.1 | 66.7 | 83.3 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39583122954:smoothness-1280-3, 1280px, window hero** (candidate ?preset=v2-proved, A/A spread 1.29 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 5.43 | 0.64 | 4 of 7 | 1,0,1,1,0,1,0 | 16.7 | 49.9 | 50.0 | 83.4 |
| base | 7 | 1085 | 5.99 | 1.29 | 2 of 7 | 1,0,0,1,0,0,0 | 16.7 | 49.9 | 50.1 | 83.3 |
| aa | 7 | 1085 | 5.52 | 1.29 | 3 of 7 | 0,0,1,0,1,1,0 | 16.7 | 49.9 | 50.1 | 100.0 |
| cand | 7 | 1085 | 6.08 | 2.58 | 1 of 7 | 0,0,0,0,2,0,0 | 16.7 | 50.0 | 50.0 | 66.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39583122954:smoothness-1280-3, 1280px, window end** (candidate ?preset=v2-proved, A/A spread 9.90 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 469 | 21.96 | 7.58 | 7 of 7 | 4,5,5,5,7,3,4 | 33.3 | 66.6 | 83.2 | 133.3 |
| base | 7 | 481 | 20.99 | 9.90 | 7 of 7 | 4,4,6,5,4,3,3 | 33.3 | 66.6 | 66.8 | 116.7 |
| aa | 7 | 479 | 20.45 | 3.48 | 7 of 7 | 4,4,3,5,5,3,3 | 33.3 | 66.6 | 66.7 | 150.0 |
| cand | 7 | 481 | 21.20 | 7.45 | 7 of 7 | 5,3,4,5,4,4,5 | 33.3 | 66.6 | 66.7 | 116.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39583122954:smoothness-390-1, 390px, window hero** (candidate ?preset=v2-proved, A/A spread 0.58 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1200 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 33.3 | 33.4 |
| base | 7 | 1213 | 0.82 | 0.57 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| aa | 7 | 1207 | 0.74 | 0.58 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.3 |
| cand | 7 | 1203 | 0.66 | 0.58 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |

Rate verdicts: orig vs base: first; base vs cand: same; orig vs cand: first
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39583122954:smoothness-390-1, 390px, window end** (candidate ?preset=v2-proved, A/A spread 0.89 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 808 | 1.36 | 0.86 | 5 of 7 | 0,1,1,1,0,1,1 | 16.7 | 33.3 | 50.0 | 66.7 |
| base | 7 | 812 | 1.47 | 0.89 | 6 of 7 | 1,1,1,1,0,1,1 | 16.7 | 33.3 | 50.0 | 83.4 |
| aa | 7 | 811 | 1.35 | 0.88 | 1 of 7 | 0,1,0,0,0,0,0 | 16.7 | 33.3 | 49.9 | 66.6 |
| cand | 7 | 813 | 1.59 | 1.76 | 2 of 7 | 0,1,0,1,0,0,0 | 16.7 | 33.3 | 50.0 | 66.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39583122954:smoothness-390-2, 390px, window hero** (candidate ?preset=v2-proved, A/A spread 0.59 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1199 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 33.3 | 33.4 |
| base | 7 | 1205 | 0.66 | 0.59 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.5 |
| aa | 7 | 1211 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| cand | 7 | 1199 | 0.66 | 0.59 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |

Rate verdicts: orig vs base: first; base vs cand: same; orig vs cand: first
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39583122954:smoothness-390-2, 390px, window end** (candidate ?preset=v2-proved, A/A spread 0.89 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 811 | 1.23 | 0.91 | 5 of 7 | 1,1,1,0,1,1,0 | 16.7 | 33.3 | 50.0 | 83.3 |
| base | 7 | 819 | 1.46 | 0.88 | 4 of 7 | 1,0,1,0,1,0,1 | 16.7 | 33.3 | 50.0 | 66.7 |
| aa | 7 | 815 | 1.47 | 0.89 | 4 of 7 | 1,0,1,1,1,0,0 | 16.7 | 33.3 | 50.0 | 83.4 |
| cand | 7 | 815 | 1.22 | 0.88 | 3 of 7 | 0,0,0,1,1,0,1 | 16.7 | 33.3 | 49.9 | 83.3 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39583122954:smoothness-390-3, 390px, window hero** (candidate ?preset=v2-proved, A/A spread 0.60 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1205 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 33.2 | 33.4 |
| base | 7 | 1201 | 0.74 | 0.60 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| aa | 7 | 1202 | 0.66 | 0.57 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| cand | 7 | 1209 | 0.66 | 0.57 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |

Rate verdicts: orig vs base: first; base vs cand: same; orig vs cand: first
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39583122954:smoothness-390-3, 390px, window end** (candidate ?preset=v2-proved, A/A spread 0.88 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 813 | 0.98 | 0.92 | 6 of 7 | 1,1,1,1,1,0,1 | 16.7 | 33.3 | 33.4 | 83.4 |
| base | 7 | 818 | 0.97 | 0.86 | 5 of 7 | 1,0,1,1,1,1,0 | 16.7 | 33.3 | 33.4 | 83.3 |
| aa | 7 | 820 | 1.34 | 0.88 | 5 of 7 | 1,1,1,0,0,1,1 | 16.7 | 33.3 | 50.0 | 66.7 |
| cand | 7 | 821 | 1.21 | 0.88 | 5 of 7 | 1,0,1,0,1,1,1 | 16.7 | 33.2 | 50.0 | 116.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39585007706:smoothness-1280-1, 1280px, window hero** (candidate ?preset=v2-proved, A/A spread 1.29 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 4.88 | 1.29 | 4 of 7 | 0,1,1,1,0,1,0 | 16.7 | 33.4 | 50.0 | 83.4 |
| base | 7 | 1085 | 5.34 | 0.64 | 1 of 7 | 1,0,0,0,0,0,0 | 16.7 | 49.9 | 50.0 | 66.7 |
| aa | 7 | 1085 | 5.80 | 1.29 | 1 of 7 | 0,0,1,0,0,0,0 | 16.7 | 49.9 | 50.0 | 83.3 |
| cand | 7 | 1085 | 5.52 | 1.29 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 49.9 | 50.1 | 50.1 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39585007706:smoothness-1280-1, 1280px, window end** (candidate ?preset=v2-proved, A/A spread 6.47 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 477 | 20.33 | 3.81 | 7 of 7 | 3,4,4,5,6,3,3 | 33.3 | 66.6 | 83.3 | 133.3 |
| base | 7 | 485 | 22.06 | 6.47 | 7 of 7 | 5,4,4,5,4,3,2 | 33.3 | 66.6 | 66.7 | 116.6 |
| aa | 7 | 484 | 20.86 | 4.95 | 7 of 7 | 5,4,3,4,2,2,2 | 33.3 | 50.1 | 66.7 | 83.4 |
| cand | 7 | 472 | 22.45 | 14.52 | 7 of 7 | 4,3,4,4,4,4,7 | 33.3 | 66.7 | 66.8 | 116.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39585007706:smoothness-1280-2, 1280px, window hero** (candidate ?preset=v2-proved, A/A spread 1.29 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1086 | 2.11 | 0.65 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 50.1 |
| base | 7 | 1085 | 2.85 | 1.29 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 50.1 |
| aa | 7 | 1085 | 2.94 | 1.29 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 50.1 |
| cand | 7 | 1085 | 2.67 | 0.64 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 50.1 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39585007706:smoothness-1280-2, 1280px, window end** (candidate ?preset=v2-proved, A/A spread 6.17 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 553 | 11.75 | 4.10 | 6 of 7 | 2,2,2,2,0,1,1 | 16.7 | 50.0 | 66.7 | 116.6 |
| base | 7 | 574 | 12.02 | 5.48 | 7 of 7 | 2,1,2,2,2,2,1 | 16.7 | 50.0 | 66.7 | 116.6 |
| aa | 7 | 567 | 12.52 | 6.17 | 7 of 7 | 1,2,3,2,1,3,3 | 16.7 | 50.0 | 83.4 | 116.6 |
| cand | 7 | 570 | 11.40 | 7.69 | 7 of 7 | 2,2,2,1,2,1,1 | 16.7 | 50.0 | 66.7 | 116.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39585007706:smoothness-1280-3, 1280px, window hero** (candidate ?preset=v2-proved, A/A spread 1.93 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 5.43 | 1.29 | 1 of 7 | 0,0,0,0,1,0,0 | 16.7 | 49.9 | 50.1 | 83.3 |
| base | 7 | 1085 | 6.08 | 1.29 | 3 of 7 | 1,0,0,1,1,0,0 | 16.7 | 49.9 | 50.1 | 83.4 |
| aa | 7 | 1086 | 6.26 | 1.93 | 1 of 7 | 0,0,0,0,0,3,0 | 16.7 | 49.9 | 50.1 | 83.4 |
| cand | 7 | 1086 | 5.89 | 1.29 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 49.9 | 50.0 | 50.1 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39585007706:smoothness-1280-3, 1280px, window end** (candidate ?preset=v2-proved, A/A spread 7.45 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 451 | 22.17 | 12.40 | 7 of 7 | 4,7,6,4,6,5,3 | 33.3 | 66.7 | 83.3 | 150.0 |
| base | 7 | 461 | 23.64 | 5.77 | 7 of 7 | 4,3,5,5,5,5,5 | 33.3 | 66.6 | 83.3 | 83.4 |
| aa | 7 | 471 | 22.71 | 7.45 | 7 of 7 | 4,5,3,6,8,5,4 | 33.3 | 66.6 | 83.3 | 116.7 |
| cand | 7 | 464 | 22.19 | 7.16 | 7 of 7 | 3,2,4,5,5,5,4 | 33.3 | 66.6 | 83.4 | 116.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39585007706:smoothness-390-1, 390px, window hero** (candidate ?preset=v2-proved, A/A spread 0.01 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1199 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 33.3 | 33.4 |
| base | 7 | 1206 | 0.58 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |
| aa | 7 | 1204 | 0.58 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |
| cand | 7 | 1200 | 0.75 | 0.60 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |

Rate verdicts: orig vs base: first; base vs cand: first; orig vs cand: first
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39585007706:smoothness-390-1, 390px, window end** (candidate ?preset=v2-proved, A/A spread 0.84 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 833 | 0.72 | 1.69 | 3 of 7 | 1,0,1,0,1,0,0 | 16.7 | 33.3 | 33.4 | 66.8 |
| base | 7 | 832 | 0.72 | 0.84 | 4 of 7 | 0,0,1,1,0,1,1 | 16.7 | 16.8 | 33.4 | 66.7 |
| aa | 7 | 832 | 0.96 | 0.84 | 6 of 7 | 0,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 66.8 |
| cand | 7 | 830 | 1.20 | 1.70 | 5 of 7 | 0,1,1,1,1,0,1 | 16.7 | 16.8 | 50.0 | 66.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39585007706:smoothness-390-2, 390px, window hero** (candidate ?preset=v2-proved, A/A spread 0.59 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1199 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 33.3 | 33.4 |
| base | 7 | 1202 | 0.58 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| aa | 7 | 1199 | 0.75 | 0.59 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| cand | 7 | 1203 | 0.58 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39585007706:smoothness-390-2, 390px, window end** (candidate ?preset=v2-proved, A/A spread 0.89 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 812 | 1.60 | 1.74 | 5 of 7 | 0,0,1,1,1,1,1 | 16.7 | 33.3 | 50.0 | 66.7 |
| base | 7 | 819 | 1.46 | 0.88 | 6 of 7 | 1,1,0,1,1,1,1 | 16.7 | 33.3 | 50.0 | 66.7 |
| aa | 7 | 819 | 1.22 | 0.89 | 3 of 7 | 0,1,1,0,1,0,0 | 16.7 | 33.3 | 49.9 | 83.3 |
| cand | 7 | 817 | 1.22 | 0.87 | 2 of 7 | 0,0,0,0,1,1,0 | 16.7 | 33.3 | 49.9 | 66.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39585007706:smoothness-390-3, 390px, window hero** (candidate ?preset=v2-proved, A/A spread 0.58 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1207 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 33.3 | 33.4 |
| base | 7 | 1207 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| aa | 7 | 1202 | 0.66 | 0.58 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.5 |
| cand | 7 | 1203 | 0.74 | 0.59 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: first
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39585007706:smoothness-390-3, 390px, window end** (candidate ?preset=v2-proved, A/A spread 0.87 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 823 | 1.21 | 0.89 | 4 of 7 | 0,1,1,0,0,1,1 | 16.7 | 33.3 | 50.0 | 66.7 |
| base | 7 | 814 | 1.35 | 0.87 | 4 of 7 | 1,1,1,0,0,1,0 | 16.7 | 33.3 | 50.0 | 66.7 |
| aa | 7 | 815 | 1.47 | 0.87 | 4 of 7 | 0,0,1,1,1,1,0 | 16.7 | 33.3 | 50.0 | 83.4 |
| cand | 7 | 819 | 1.09 | 0.88 | 2 of 7 | 0,0,0,1,0,0,1 | 16.7 | 33.3 | 49.9 | 66.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39589237987:smoothness-1280-1, 1280px, window hero** (candidate ?preset=v2-proved, A/A spread 1.29 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 5.52 | 1.93 | 2 of 7 | 0,1,0,0,0,0,1 | 16.7 | 49.9 | 50.1 | 83.4 |
| base | 7 | 1085 | 6.35 | 1.29 | 2 of 7 | 0,1,0,0,1,0,0 | 16.7 | 50.0 | 50.0 | 83.4 |
| aa | 7 | 1085 | 6.17 | 1.29 | 1 of 7 | 1,0,0,0,0,0,0 | 16.7 | 50.0 | 50.0 | 83.3 |
| cand | 7 | 1085 | 5.99 | 1.93 | 3 of 7 | 1,0,1,0,0,1,0 | 16.7 | 50.0 | 50.1 | 83.4 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39589237987:smoothness-1280-1, 1280px, window end** (candidate ?preset=v2-proved, A/A spread 8.16 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 467 | 20.12 | 5.97 | 7 of 7 | 3,3,5,4,3,4,4 | 33.3 | 66.6 | 83.3 | 133.3 |
| base | 7 | 475 | 20.84 | 5.94 | 7 of 7 | 4,5,3,2,4,4,5 | 33.3 | 66.6 | 83.3 | 116.7 |
| aa | 7 | 473 | 21.77 | 8.16 | 7 of 7 | 4,5,6,4,4,2,4 | 33.3 | 66.6 | 83.3 | 83.4 |
| cand | 7 | 474 | 22.57 | 4.61 | 7 of 7 | 5,4,4,5,4,5,6 | 33.3 | 66.6 | 66.8 | 83.4 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39589237987:smoothness-1280-2, 1280px, window hero** (candidate ?preset=v2-proved, A/A spread 1.29 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 5.71 | 1.29 | 3 of 7 | 0,1,0,1,0,1,0 | 16.7 | 49.9 | 50.1 | 83.3 |
| base | 7 | 1085 | 6.45 | 1.29 | 2 of 7 | 1,1,0,0,0,0,0 | 16.7 | 50.0 | 50.1 | 83.4 |
| aa | 7 | 1086 | 6.62 | 0.68 | 3 of 7 | 0,1,1,0,0,1,0 | 16.7 | 50.0 | 50.1 | 83.3 |
| cand | 7 | 1085 | 6.63 | 1.29 | 2 of 7 | 2,0,2,0,0,0,0 | 16.7 | 50.0 | 50.1 | 83.4 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39589237987:smoothness-1280-2, 1280px, window end** (candidate ?preset=v2-proved, A/A spread 7.68 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 451 | 23.50 | 5.68 | 7 of 7 | 5,4,4,4,7,4,4 | 33.3 | 66.6 | 83.4 | 133.3 |
| base | 7 | 448 | 24.10 | 7.68 | 7 of 7 | 4,5,5,5,4,5,6 | 33.3 | 66.7 | 83.4 | 116.7 |
| aa | 7 | 452 | 24.55 | 6.19 | 7 of 7 | 5,5,3,4,7,7,5 | 33.3 | 66.7 | 83.4 | 116.6 |
| cand | 7 | 456 | 23.68 | 8.00 | 7 of 7 | 4,5,4,5,6,4,4 | 33.3 | 66.6 | 83.3 | 116.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39589237987:smoothness-1280-3, 1280px, window hero** (candidate ?preset=v2-proved, A/A spread 2.58 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 5.99 | 2.58 | 2 of 7 | 1,0,0,1,0,0,0 | 16.7 | 49.9 | 50.1 | 83.4 |
| base | 7 | 1085 | 7.09 | 2.58 | 3 of 7 | 0,1,0,1,1,0,0 | 16.7 | 50.0 | 50.1 | 83.3 |
| aa | 7 | 1085 | 6.72 | 2.58 | 1 of 7 | 0,0,0,0,0,0,1 | 16.7 | 50.0 | 50.1 | 83.3 |
| cand | 7 | 1085 | 6.45 | 1.29 | 1 of 7 | 0,0,0,1,0,0,0 | 16.7 | 50.0 | 50.0 | 83.3 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39589237987:smoothness-1280-3, 1280px, window end** (candidate ?preset=v2-proved, A/A spread 5.88 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 441 | 25.85 | 8.37 | 7 of 7 | 6,6,6,6,7,4,4 | 33.3 | 66.7 | 83.3 | 133.3 |
| base | 7 | 454 | 24.44 | 5.88 | 7 of 7 | 4,5,4,4,5,6,6 | 33.3 | 66.6 | 83.3 | 150.0 |
| aa | 7 | 451 | 24.83 | 5.35 | 7 of 7 | 4,4,4,5,5,5,4 | 33.3 | 66.6 | 66.8 | 133.4 |
| cand | 7 | 445 | 23.82 | 8.12 | 7 of 7 | 6,5,7,4,6,4,7 | 33.3 | 66.7 | 100.0 | 150.1 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39589237987:smoothness-390-1, 390px, window hero** (candidate ?preset=v2-proved, A/A spread 0.59 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1204 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 16.8 | 33.4 |
| base | 7 | 1202 | 0.58 | 0.02 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |
| aa | 7 | 1206 | 0.66 | 0.59 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| cand | 7 | 1207 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39589237987:smoothness-390-1, 390px, window end** (candidate ?preset=v2-proved, A/A spread 1.68 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 837 | 0.83 | 1.69 | 3 of 7 | 1,1,0,0,0,0,1 | 16.7 | 16.8 | 33.4 | 66.7 |
| base | 7 | 833 | 0.84 | 1.68 | 6 of 7 | 1,1,1,1,1,0,1 | 16.7 | 16.8 | 33.4 | 66.7 |
| aa | 7 | 834 | 0.95 | 1.68 | 4 of 7 | 1,0,1,0,0,1,1 | 16.7 | 16.8 | 33.4 | 66.7 |
| cand | 7 | 837 | 0.95 | 1.68 | 3 of 7 | 0,1,1,1,0,0,0 | 16.7 | 16.8 | 33.4 | 66.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39589237987:smoothness-390-2, 390px, window hero** (candidate ?preset=v2-proved, A/A spread 0.01 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1196 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 33.3 | 33.5 |
| base | 7 | 1201 | 0.58 | 0.00 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |
| aa | 7 | 1205 | 0.58 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |
| cand | 7 | 1208 | 0.74 | 1.17 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |

Rate verdicts: orig vs base: first; base vs cand: first; orig vs cand: first
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39589237987:smoothness-390-2, 390px, window end** (candidate ?preset=v2-proved, A/A spread 0.88 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 820 | 1.21 | 0.86 | 5 of 7 | 1,1,0,0,1,1,1 | 16.7 | 33.3 | 50.0 | 66.7 |
| base | 7 | 822 | 1.33 | 0.86 | 5 of 7 | 0,0,1,1,1,1,1 | 16.7 | 33.2 | 50.0 | 99.9 |
| aa | 7 | 824 | 1.21 | 0.88 | 4 of 7 | 0,1,1,0,1,0,1 | 16.7 | 33.3 | 49.9 | 66.8 |
| cand | 7 | 826 | 1.21 | 0.89 | 3 of 7 | 0,1,1,1,0,0,0 | 16.7 | 33.3 | 50.0 | 66.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39589237987:smoothness-390-3, 390px, window hero** (candidate ?preset=v2-proved, A/A spread 0.59 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1198 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 16.8 | 33.4 |
| base | 7 | 1203 | 0.58 | 0.02 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.3 |
| aa | 7 | 1196 | 0.66 | 0.59 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.3 |
| cand | 7 | 1204 | 0.58 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39589237987:smoothness-390-3, 390px, window end** (candidate ?preset=v2-proved, A/A spread 1.69 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 837 | 0.47 | 0.84 | 2 of 7 | 1,0,0,0,0,0,1 | 16.7 | 33.3 | 33.4 | 66.7 |
| base | 7 | 832 | 0.84 | 0.00 | 6 of 7 | 1,1,1,1,1,1,0 | 16.7 | 16.8 | 33.4 | 66.7 |
| aa | 7 | 831 | 0.72 | 1.69 | 4 of 7 | 0,0,0,1,1,1,1 | 16.7 | 16.8 | 33.4 | 66.8 |
| cand | 7 | 831 | 0.96 | 0.85 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 66.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `across` with `agreeNeeded n` = two thirds of n, none disagreeing)

| width | window | first | second | samples n | need | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | base | 10 | 7 | 0 / 0 / 10 / 0 | not told apart | 0 / 0 / 10 / 0 | not told apart | 0.11 | 0.89 |
| 390 | end | base | cand | 10 | 7 | 0 / 0 / 10 / 0 | not told apart | 0 / 0 / 10 / 0 | not told apart | -0.11 | 0.89 |
| 390 | end | orig | cand | 10 | 7 | 0 / 0 / 10 / 0 | not told apart | 0 / 0 / 10 / 0 | not told apart | 0.12 | 0.89 |
| 390 | hero | orig | base | 10 | 7 | 6 / 0 / 4 / 0 | not told apart | 10 / 0 / 0 / 0 | first smoother | 0.58 | 0.58 |
| 390 | hero | base | cand | 10 | 7 | 2 / 0 / 8 / 0 | not told apart | 0 / 0 / 10 / 0 | not told apart | 0.00 | 0.58 |
| 390 | hero | orig | cand | 10 | 7 | 7 / 0 / 3 / 0 | first smoother | 10 / 0 / 0 / 0 | first smoother | 0.66 | 0.58 |
| 1280 | end | orig | base | 10 | 7 | 0 / 0 / 10 / 0 | not told apart | 0 / 0 / 10 / 0 | not told apart | 0.60 | 6.64 |
| 1280 | end | base | cand | 10 | 7 | 0 / 0 / 10 / 0 | not told apart | 0 / 0 / 10 / 0 | not told apart | -0.42 | 6.64 |
| 1280 | end | orig | cand | 10 | 7 | 0 / 0 / 10 / 0 | not told apart | 0 / 0 / 10 / 0 | not told apart | 0.18 | 6.64 |
| 1280 | hero | orig | base | 10 | 7 | 0 / 0 / 10 / 0 | not told apart | 0 / 0 / 10 / 0 | not told apart | 0.65 | 1.29 |
| 1280 | hero | base | cand | 10 | 7 | 0 / 0 / 10 / 0 | not told apart | 0 / 0 / 10 / 0 | not told apart | -0.01 | 1.29 |
| 1280 | hero | orig | cand | 10 | 7 | 1 / 0 / 9 / 0 | not told apart | 0 / 0 / 10 / 0 | not told apart | 0.56 | 1.29 |

Samples: 39580977630:smoothness-390, 39583122954:smoothness-390-1, 39583122954:smoothness-390-2, 39583122954:smoothness-390-3, 39585007706:smoothness-390-1, 39585007706:smoothness-390-2, 39585007706:smoothness-390-3, 39589237987:smoothness-390-1, 39589237987:smoothness-390-2, 39589237987:smoothness-390-3, 39580977630:smoothness-1280, 39583122954:smoothness-1280-1, 39583122954:smoothness-1280-2, 39583122954:smoothness-1280-3, 39585007706:smoothness-1280-1, 39585007706:smoothness-1280-2, 39585007706:smoothness-1280-3, 39589237987:smoothness-1280-1, 39589237987:smoothness-1280-2, 39589237987:smoothness-1280-3

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39580977630:smoothness-1280 | 1280 | hero | orig | 7 | 2 | 66.7 | - | 0 |
| 39580977630:smoothness-1280 | 1280 | hero | aa | 7 | 2 | 66.7 | - | 0 |
| 39580977630:smoothness-1280 | 1280 | hero | cand | 7 | 2 | 66.7 | - | 0 |
| 39580977630:smoothness-1280 | 1280 | end | orig | 7 | 19 | 66.7 | - | 0 |
| 39580977630:smoothness-1280 | 1280 | end | base | 7 | 21 | 66.7 | - | 0 |
| 39580977630:smoothness-1280 | 1280 | end | aa | 7 | 23 | 66.7 | - | 0 |
| 39580977630:smoothness-1280 | 1280 | end | cand | 7 | 18 | 66.7 | - | 0 |
| 39580977630:smoothness-390 | 390 | hero | base | 7 | 7 | 83.4 | - | 0 |
| 39580977630:smoothness-390 | 390 | hero | aa | 7 | 7 | 83.3 | - | 0 |
| 39580977630:smoothness-390 | 390 | hero | cand | 7 | 7 | 83.3 | - | 0 |
| 39580977630:smoothness-390 | 390 | end | orig | 7 | 1 | 66.7 | - | 0 |
| 39580977630:smoothness-390 | 390 | end | base | 7 | 1 | 66.7 | - | 0 |
| 39580977630:smoothness-390 | 390 | end | aa | 7 | 5 | 66.6 | - | 0 |
| 39580977630:smoothness-390 | 390 | end | cand | 7 | 7 | 66.7 | - | 0 |
| 39583122954:smoothness-1280-1 | 1280 | hero | orig | 7 | 1 | 83.4 | 924 | 1 |
| 39583122954:smoothness-1280-1 | 1280 | hero | base | 7 | 3 | 83.3 | 882 | 2 |
| 39583122954:smoothness-1280-1 | 1280 | hero | aa | 7 | 1 | 66.6 | 1050 | 1 |
| 39583122954:smoothness-1280-1 | 1280 | hero | cand | 7 | 2 | 83.2 | 882 | 2 |
| 39583122954:smoothness-1280-1 | 1280 | end | orig | 7 | 21 | 66.7 | 8269 | 7 |
| 39583122954:smoothness-1280-1 | 1280 | end | base | 7 | 20 | 66.7 | 8269 | 7 |
| 39583122954:smoothness-1280-1 | 1280 | end | aa | 7 | 15 | 66.7 | 8269 | 7 |
| 39583122954:smoothness-1280-1 | 1280 | end | cand | 7 | 19 | 66.7 | 8269 | 7 |
| 39583122954:smoothness-1280-2 | 1280 | hero | orig | 7 | 1 | 66.6 | 1092 | 1 |
| 39583122954:smoothness-1280-2 | 1280 | hero | base | 7 | 1 | 66.6 | 714 | 1 |
| 39583122954:smoothness-1280-2 | 1280 | hero | aa | 7 | 2 | 83.3 | 840 | 2 |
| 39583122954:smoothness-1280-2 | 1280 | hero | cand | 7 | 3 | 66.7 | 1008 | 3 |
| 39583122954:smoothness-1280-2 | 1280 | end | orig | 7 | 21 | 66.7 | 8269 | 7 |
| 39583122954:smoothness-1280-2 | 1280 | end | base | 7 | 18 | 66.7 | 8269 | 7 |
| 39583122954:smoothness-1280-2 | 1280 | end | aa | 7 | 20 | 66.7 | 8269 | 7 |
| 39583122954:smoothness-1280-2 | 1280 | end | cand | 7 | 20 | 66.7 | 8269 | 7 |
| 39583122954:smoothness-1280-3 | 1280 | hero | orig | 7 | 4 | 83.3 | 966 | 4 |
| 39583122954:smoothness-1280-3 | 1280 | hero | base | 7 | 2 | 83.2 | 840 | 2 |
| 39583122954:smoothness-1280-3 | 1280 | hero | aa | 7 | 3 | 83.4 | 966 | 3 |
| 39583122954:smoothness-1280-3 | 1280 | hero | cand | 7 | 2 | 66.6 | 714 | 1 |
| 39583122954:smoothness-1280-3 | 1280 | end | orig | 7 | 33 | 66.7 | 8269 | 7 |
| 39583122954:smoothness-1280-3 | 1280 | end | base | 7 | 29 | 66.7 | 8269 | 7 |
| 39583122954:smoothness-1280-3 | 1280 | end | aa | 7 | 27 | 66.7 | 8269 | 7 |
| 39583122954:smoothness-1280-3 | 1280 | end | cand | 7 | 30 | 66.7 | 8269 | 7 |
| 39583122954:smoothness-390-1 | 390 | hero | base | 7 | 7 | 83.3 | 672 | 7 |
| 39583122954:smoothness-390-1 | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39583122954:smoothness-390-1 | 390 | hero | cand | 7 | 7 | 83.3 | 672 | 7 |
| 39583122954:smoothness-390-1 | 390 | end | orig | 7 | 5 | 66.7 | 5103 | 3 |
| 39583122954:smoothness-390-1 | 390 | end | base | 7 | 6 | 66.7 | 5103 | 5 |
| 39583122954:smoothness-390-1 | 390 | end | aa | 7 | 1 | 66.6 | 5103 | 1 |
| 39583122954:smoothness-390-1 | 390 | end | cand | 7 | 2 | 66.6 | 5103 | 2 |
| 39583122954:smoothness-390-2 | 390 | hero | base | 7 | 7 | 83.4 | 672 | 7 |
| 39583122954:smoothness-390-2 | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39583122954:smoothness-390-2 | 390 | hero | cand | 7 | 7 | 83.4 | 672 | 7 |
| 39583122954:smoothness-390-2 | 390 | end | orig | 7 | 5 | 66.7 | 5103 | 3 |
| 39583122954:smoothness-390-2 | 390 | end | base | 7 | 4 | 66.6 | 5103 | 4 |
| 39583122954:smoothness-390-2 | 390 | end | aa | 7 | 4 | 66.7 | 5103 | 4 |
| 39583122954:smoothness-390-2 | 390 | end | cand | 7 | 3 | 66.7 | 5103 | 3 |
| 39583122954:smoothness-390-3 | 390 | hero | base | 7 | 7 | 83.3 | 672 | 7 |
| 39583122954:smoothness-390-3 | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39583122954:smoothness-390-3 | 390 | hero | cand | 7 | 7 | 83.3 | 672 | 7 |
| 39583122954:smoothness-390-3 | 390 | end | orig | 7 | 6 | 66.7 | 5103 | 1 |
| 39583122954:smoothness-390-3 | 390 | end | base | 7 | 5 | 66.6 | 5103 | 5 |
| 39583122954:smoothness-390-3 | 390 | end | aa | 7 | 5 | 66.7 | 5103 | 5 |
| 39583122954:smoothness-390-3 | 390 | end | cand | 7 | 5 | 66.8 | 5103 | 4 |
| 39585007706:smoothness-1280-1 | 1280 | hero | orig | 7 | 4 | 83.3 | 840 | 4 |
| 39585007706:smoothness-1280-1 | 1280 | hero | base | 7 | 1 | 66.7 | 714 | 1 |
| 39585007706:smoothness-1280-1 | 1280 | hero | aa | 7 | 1 | 83.3 | 798 | 1 |
| 39585007706:smoothness-1280-1 | 1280 | end | orig | 7 | 28 | 66.7 | 8269 | 7 |
| 39585007706:smoothness-1280-1 | 1280 | end | base | 7 | 27 | 66.7 | 8269 | 7 |
| 39585007706:smoothness-1280-1 | 1280 | end | aa | 7 | 22 | 66.7 | 8269 | 7 |
| 39585007706:smoothness-1280-1 | 1280 | end | cand | 7 | 30 | 66.7 | 8269 | 7 |
| 39585007706:smoothness-1280-2 | 1280 | end | orig | 7 | 10 | 66.7 | 8269 | 6 |
| 39585007706:smoothness-1280-2 | 1280 | end | base | 7 | 12 | 66.7 | 8269 | 7 |
| 39585007706:smoothness-1280-2 | 1280 | end | aa | 7 | 15 | 66.7 | 8269 | 7 |
| 39585007706:smoothness-1280-2 | 1280 | end | cand | 7 | 11 | 66.7 | 8269 | 7 |
| 39585007706:smoothness-1280-3 | 1280 | hero | orig | 7 | 1 | 83.3 | 882 | 1 |
| 39585007706:smoothness-1280-3 | 1280 | hero | base | 7 | 3 | 83.4 | 840 | 3 |
| 39585007706:smoothness-1280-3 | 1280 | hero | aa | 7 | 3 | 83.2 | 924 | 1 |
| 39585007706:smoothness-1280-3 | 1280 | end | orig | 7 | 35 | 66.7 | 8269 | 7 |
| 39585007706:smoothness-1280-3 | 1280 | end | base | 7 | 32 | 66.7 | 8269 | 7 |
| 39585007706:smoothness-1280-3 | 1280 | end | aa | 7 | 35 | 66.7 | 8269 | 7 |
| 39585007706:smoothness-1280-3 | 1280 | end | cand | 7 | 28 | 66.7 | 8269 | 7 |
| 39585007706:smoothness-390-1 | 390 | hero | base | 7 | 7 | 83.3 | 672 | 7 |
| 39585007706:smoothness-390-1 | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39585007706:smoothness-390-1 | 390 | hero | cand | 7 | 7 | 83.3 | 672 | 7 |
| 39585007706:smoothness-390-1 | 390 | end | orig | 7 | 3 | 66.7 | 5103 | 2 |
| 39585007706:smoothness-390-1 | 390 | end | base | 7 | 4 | 66.7 | 5103 | 2 |
| 39585007706:smoothness-390-1 | 390 | end | aa | 7 | 6 | 66.7 | 5103 | 2 |
| 39585007706:smoothness-390-1 | 390 | end | cand | 7 | 5 | 66.7 | 5103 | 1 |
| 39585007706:smoothness-390-2 | 390 | hero | base | 7 | 7 | 83.3 | 672 | 7 |
| 39585007706:smoothness-390-2 | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39585007706:smoothness-390-2 | 390 | hero | cand | 7 | 7 | 83.3 | 672 | 7 |
| 39585007706:smoothness-390-2 | 390 | end | orig | 7 | 5 | 66.6 | 5103 | 3 |
| 39585007706:smoothness-390-2 | 390 | end | base | 7 | 6 | 66.7 | 5103 | 6 |
| 39585007706:smoothness-390-2 | 390 | end | aa | 7 | 3 | 66.7 | 5103 | 3 |
| 39585007706:smoothness-390-2 | 390 | end | cand | 7 | 2 | 66.7 | 5103 | 1 |
| 39585007706:smoothness-390-3 | 390 | hero | base | 7 | 7 | 83.4 | 672 | 7 |
| 39585007706:smoothness-390-3 | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39585007706:smoothness-390-3 | 390 | hero | cand | 7 | 7 | 83.3 | 672 | 7 |
| 39585007706:smoothness-390-3 | 390 | end | orig | 7 | 4 | 66.6 | 5103 | 2 |
| 39585007706:smoothness-390-3 | 390 | end | base | 7 | 4 | 66.6 | 5103 | 3 |
| 39585007706:smoothness-390-3 | 390 | end | aa | 7 | 4 | 66.6 | 5103 | 4 |
| 39585007706:smoothness-390-3 | 390 | end | cand | 7 | 2 | 66.6 | 5103 | 2 |
| 39589237987:smoothness-1280-1 | 1280 | hero | orig | 7 | 2 | 83.3 | 882 | 2 |
| 39589237987:smoothness-1280-1 | 1280 | hero | base | 7 | 2 | 83.3 | 840 | 2 |
| 39589237987:smoothness-1280-1 | 1280 | hero | aa | 7 | 1 | 83.3 | 882 | 1 |
| 39589237987:smoothness-1280-1 | 1280 | hero | cand | 7 | 3 | 83.2 | 1050 | 3 |
| 39589237987:smoothness-1280-1 | 1280 | end | orig | 7 | 26 | 66.7 | 8269 | 7 |
| 39589237987:smoothness-1280-1 | 1280 | end | base | 7 | 27 | 66.7 | 8269 | 7 |
| 39589237987:smoothness-1280-1 | 1280 | end | aa | 7 | 29 | 66.7 | 8269 | 7 |
| 39589237987:smoothness-1280-1 | 1280 | end | cand | 7 | 33 | 66.7 | 8269 | 7 |
| 39589237987:smoothness-1280-2 | 1280 | hero | orig | 7 | 3 | 83.3 | 966 | 3 |
| 39589237987:smoothness-1280-2 | 1280 | hero | base | 7 | 2 | 83.3 | 798 | 2 |
| 39589237987:smoothness-1280-2 | 1280 | hero | aa | 7 | 3 | 83.3 | 882 | 3 |
| 39589237987:smoothness-1280-2 | 1280 | hero | cand | 7 | 4 | 66.7 | 798 | 2 |
| 39589237987:smoothness-1280-2 | 1280 | end | orig | 7 | 32 | 66.7 | 8269 | 7 |
| 39589237987:smoothness-1280-2 | 1280 | end | base | 7 | 34 | 66.7 | 8269 | 7 |
| 39589237987:smoothness-1280-2 | 1280 | end | aa | 7 | 36 | 66.7 | 8269 | 7 |
| 39589237987:smoothness-1280-2 | 1280 | end | cand | 7 | 32 | 66.7 | 8269 | 7 |
| 39589237987:smoothness-1280-3 | 1280 | hero | orig | 7 | 2 | 83.3 | 798 | 2 |
| 39589237987:smoothness-1280-3 | 1280 | hero | base | 7 | 3 | 83.3 | 924 | 3 |
| 39589237987:smoothness-1280-3 | 1280 | hero | aa | 7 | 1 | 83.3 | 840 | 1 |
| 39589237987:smoothness-1280-3 | 1280 | hero | cand | 7 | 1 | 83.3 | 840 | 1 |
| 39589237987:smoothness-1280-3 | 1280 | end | orig | 7 | 39 | 66.7 | 8269 | 7 |
| 39589237987:smoothness-1280-3 | 1280 | end | base | 7 | 34 | 66.7 | 8269 | 7 |
| 39589237987:smoothness-1280-3 | 1280 | end | aa | 7 | 31 | 66.7 | 8269 | 7 |
| 39589237987:smoothness-1280-3 | 1280 | end | cand | 7 | 39 | 66.7 | 8269 | 7 |
| 39589237987:smoothness-390-1 | 390 | hero | base | 7 | 7 | 83.3 | 672 | 7 |
| 39589237987:smoothness-390-1 | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39589237987:smoothness-390-1 | 390 | hero | cand | 7 | 7 | 83.3 | 672 | 7 |
| 39589237987:smoothness-390-1 | 390 | end | orig | 7 | 3 | 66.7 | 5103 | 1 |
| 39589237987:smoothness-390-1 | 390 | end | base | 7 | 6 | 66.6 | 5103 | 1 |
| 39589237987:smoothness-390-1 | 390 | end | aa | 7 | 4 | 66.7 | 5103 | 0 |
| 39589237987:smoothness-390-1 | 390 | end | cand | 7 | 3 | 66.6 | 5103 | 1 |
| 39589237987:smoothness-390-2 | 390 | hero | base | 7 | 7 | 83.4 | 672 | 7 |
| 39589237987:smoothness-390-2 | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39589237987:smoothness-390-2 | 390 | hero | cand | 7 | 7 | 83.3 | 672 | 7 |
| 39589237987:smoothness-390-2 | 390 | end | orig | 7 | 5 | 66.7 | 5103 | 2 |
| 39589237987:smoothness-390-2 | 390 | end | base | 7 | 5 | 66.7 | 5103 | 4 |
| 39589237987:smoothness-390-2 | 390 | end | aa | 7 | 4 | 66.7 | 5103 | 4 |
| 39589237987:smoothness-390-2 | 390 | end | cand | 7 | 3 | 66.6 | 5103 | 3 |
| 39589237987:smoothness-390-3 | 390 | hero | base | 7 | 7 | 83.3 | 672 | 7 |
| 39589237987:smoothness-390-3 | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39589237987:smoothness-390-3 | 390 | hero | cand | 7 | 7 | 83.3 | 672 | 7 |
| 39589237987:smoothness-390-3 | 390 | end | orig | 7 | 2 | 66.6 | 5103 | 1 |
| 39589237987:smoothness-390-3 | 390 | end | base | 7 | 6 | 66.7 | 5103 | 1 |
| 39589237987:smoothness-390-3 | 390 | end | aa | 7 | 4 | 66.7 | 5103 | 0 |
| 39589237987:smoothness-390-3 | 390 | end | cand | 7 | 7 | 66.7 | 5103 | 0 |

### Frames of the page's compositor sink (traced reps, the renderer process of the page only; reported beside the verdict, never in it)

A frame is one `frame_sequence`; `dropped` = any of its pipeline reporters dropped, `dropped (all)` = every reporter dropped, `presented` = the rest with a presented reporter.

| width | window | arm | traced reps | runs | frames | presented | dropped | dropped % | dropped (all) | dropped (all) % | rAF frames in the same reps | presented p95 ms (median of reps) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | 15 | 3 | 1897 | 1809 | 88 | 4.6 | 88 | 4.6 | 1772 | 71.6 |
| 390 | end | base | 15 | 3 | 1893 | 1806 | 87 | 4.6 | 87 | 4.6 | 1765 | 64.6 |
| 390 | end | aa | 15 | 3 | 1892 | 1810 | 82 | 4.3 | 82 | 4.3 | 1769 | 61.8 |
| 390 | end | cand | 15 | 3 | 1891 | 1806 | 85 | 4.5 | 85 | 4.5 | 1763 | 62.6 |
| 390 | hero | orig | 15 | 3 | 2614 | 2359 | 255 | 9.8 | 49 | 1.9 | 2562 | 32.2 |
| 390 | hero | base | 15 | 3 | 2678 | 2343 | 335 | 12.5 | 115 | 4.3 | 2570 | 32.2 |
| 390 | hero | aa | 15 | 3 | 2674 | 2337 | 337 | 12.6 | 118 | 4.4 | 2563 | 32.5 |
| 390 | hero | cand | 15 | 3 | 2664 | 2346 | 318 | 11.9 | 114 | 4.3 | 2555 | 32.2 |
| 1280 | end | orig | 15 | 3 | 1955 | 982 | 973 | 49.8 | 971 | 49.7 | 940 | 187.1 |
| 1280 | end | base | 15 | 3 | 1965 | 992 | 973 | 49.5 | 973 | 49.5 | 960 | 179.9 |
| 1280 | end | aa | 15 | 3 | 1978 | 992 | 986 | 49.8 | 986 | 49.8 | 963 | 178.1 |
| 1280 | end | cand | 15 | 3 | 1964 | 998 | 966 | 49.2 | 966 | 49.2 | 967 | 183.7 |
| 1280 | hero | orig | 15 | 3 | 3019 | 2279 | 740 | 24.5 | 713 | 23.6 | 2325 | 78.1 |
| 1280 | hero | base | 15 | 3 | 3036 | 2292 | 744 | 24.5 | 716 | 23.6 | 2325 | 84.2 |
| 1280 | hero | aa | 15 | 3 | 3035 | 2290 | 745 | 24.5 | 716 | 23.6 | 2328 | 75.5 |
| 1280 | hero | cand | 15 | 3 | 3031 | 2295 | 736 | 24.3 | 708 | 23.4 | 2325 | 82.7 |

### Fixed slow-event names of the traced reps (page renderer process; every row is always listed, n = 0 means the event never ran; long = 15 ms or more)

| width | window | arm | traced reps | event | events | long | longest ms | total ms | long durations ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | 15 | BeginMainFrame | 1787 | 19 | 57.7 | 10285.5 | 15.2, 15.6, 16.8, 18.5, 32.0, 33.0, 34.1, 35.0, 36.3, 36.4, 40.9, 42.6, 43.6, 45.3, 45.7, 46.8, 48.2, 51.2, 57.7 |
| 390 | end | orig | 15 | Paint | 15788 | 0 | 3.4 | 2168.7 | - |
| 390 | end | orig | 15 | UpdateLayoutTree | 2910 | 0 | 9.7 | 4135.4 | - |
| 390 | end | orig | 15 | Layout | 2298 | 0 | 0.6 | 385.9 | - |
| 390 | end | orig | 15 | image decode task | 7751 | 0 | 10.3 | 1100.3 | - |
| 390 | end | base | 15 | BeginMainFrame | 1780 | 15 | 60.5 | 10987.0 | 34.2, 36.8, 37.8, 41.2, 42.6, 42.8, 42.9, 46.1, 46.4, 47.8, 49.2, 51.8, 55.1, 59.1, 60.5 |
| 390 | end | base | 15 | Paint | 15728 | 0 | 3.3 | 2197.8 | - |
| 390 | end | base | 15 | UpdateLayoutTree | 2899 | 0 | 6.2 | 3308.7 | - |
| 390 | end | base | 15 | Layout | 2304 | 0 | 0.9 | 410.5 | - |
| 390 | end | base | 15 | image decode task | 7723 | 0 | 14.0 | 1089.2 | - |
| 390 | end | aa | 15 | BeginMainFrame | 1784 | 15 | 61.3 | 11012.6 | 39.1, 39.4, 40.4, 40.6, 42.8, 43.1, 43.3, 46.1, 48.8, 49.6, 49.6, 49.8, 53.5, 54.2, 61.3 |
| 390 | end | aa | 15 | Paint | 15708 | 0 | 3.4 | 2195.3 | - |
| 390 | end | aa | 15 | UpdateLayoutTree | 2908 | 0 | 6.2 | 3315.1 | - |
| 390 | end | aa | 15 | Layout | 2316 | 0 | 0.9 | 412.2 | - |
| 390 | end | aa | 15 | image decode task | 7781 | 0 | 10.8 | 1096.0 | - |
| 390 | end | cand | 15 | BeginMainFrame | 1778 | 15 | 62.4 | 11067.8 | 36.7, 37.0, 39.6, 40.6, 42.5, 43.5, 44.5, 45.2, 45.9, 47.7, 53.7, 55.8, 56.5, 61.9, 62.4 |
| 390 | end | cand | 15 | Paint | 15684 | 0 | 3.3 | 2213.8 | - |
| 390 | end | cand | 15 | UpdateLayoutTree | 2896 | 0 | 6.8 | 3305.9 | - |
| 390 | end | cand | 15 | Layout | 2306 | 0 | 1.0 | 419.0 | - |
| 390 | end | cand | 15 | image decode task | 7734 | 0 | 11.9 | 1102.9 | - |
| 390 | hero | orig | 15 | BeginMainFrame | 2577 | 6 | 16.3 | 10741.9 | 15.2, 15.2, 15.3, 15.5, 15.9, 16.3 |
| 390 | hero | orig | 15 | Paint | 15709 | 0 | 2.9 | 1496.0 | - |
| 390 | hero | orig | 15 | UpdateLayoutTree | 6026 | 0 | 4.9 | 3787.5 | - |
| 390 | hero | orig | 15 | Layout | 2728 | 0 | 2.2 | 417.6 | - |
| 390 | hero | orig | 15 | image decode task | 1714 | 30 | 54.9 | 2296.8 | 30.7, 30.9, 31.0, 31.3, 31.3, 31.4, 31.4, 31.5, 31.8, 31.8, 31.8, 32.3, 32.6, 32.8, 33.0, 52.0, 52.2, 52.5, 52.6, 53.1, 53.3, 53.6, 53.6, 53.7, 53.7, 53.9, 54.0, 54.1, 54.1, 54.9 |
| 390 | hero | base | 15 | BeginMainFrame | 2585 | 11 | 18.1 | 10637.1 | 15.0, 15.5, 15.9, 16.2, 16.4, 16.9, 17.0, 17.2, 17.4, 17.5, 18.1 |
| 390 | hero | base | 15 | Paint | 15065 | 0 | 3.1 | 1400.0 | - |
| 390 | hero | base | 15 | UpdateLayoutTree | 5950 | 0 | 4.5 | 3004.5 | - |
| 390 | hero | base | 15 | Layout | 2740 | 0 | 1.9 | 388.5 | - |
| 390 | hero | base | 15 | image decode task | 1866 | 60 | 57.0 | 3197.5 | 30.8, 30.8, 30.9, 31.0, 31.1, 31.1, 31.1, 31.1, 31.3, 31.3, 31.4, 31.4, 31.5, 31.5, 31.6, 31.6, 31.6, 31.7, 31.7, 31.7, 31.8, 31.8, 31.8, 31.9, 32.0, 32.0, 32.1, 32.1, 32.2, 32.3, 33.4, 33.6, 33.7, 33.9, 34.0, 34.2, 34.2, 34.3, 34.3, 34.3, 34.4, 34.4, 34.8, 35.1, 37.4, 52.3, 52.4, 52.4, 52.5, 52.5, 52.7, 53.0, 53.2, 53.2, 53.8, 53.8, 53.9, 54.1, 54.3, 57.0 |
| 390 | hero | aa | 15 | BeginMainFrame | 2578 | 11 | 17.8 | 10828.7 | 15.3, 16.4, 16.6, 16.8, 17.0, 17.1, 17.4, 17.5, 17.5, 17.5, 17.8 |
| 390 | hero | aa | 15 | Paint | 15062 | 0 | 3.1 | 1430.2 | - |
| 390 | hero | aa | 15 | UpdateLayoutTree | 5946 | 0 | 3.9 | 3040.4 | - |
| 390 | hero | aa | 15 | Layout | 2744 | 0 | 1.8 | 402.9 | - |
| 390 | hero | aa | 15 | image decode task | 1856 | 60 | 54.7 | 3225.7 | 31.0, 31.2, 31.2, 31.2, 31.3, 31.3, 31.3, 31.3, 31.4, 31.4, 31.4, 31.4, 31.6, 31.6, 31.6, 31.6, 31.7, 31.7, 31.7, 31.8, 31.9, 31.9, 31.9, 31.9, 32.0, 32.1, 32.2, 32.2, 32.2, 32.3, 33.1, 33.4, 33.6, 33.9, 34.1, 34.2, 34.2, 34.2, 34.3, 34.3, 34.5, 34.6, 34.6, 35.0, 35.7, 51.9, 52.2, 52.5, 52.6, 52.7, 53.0, 53.1, 53.2, 53.7, 53.9, 54.0, 54.0, 54.1, 54.4, 54.7 |
| 390 | hero | cand | 15 | BeginMainFrame | 2570 | 6 | 17.3 | 10739.7 | 15.5, 16.0, 17.0, 17.1, 17.1, 17.3 |
| 390 | hero | cand | 15 | Paint | 15046 | 0 | 3.1 | 1419.0 | - |
| 390 | hero | cand | 15 | UpdateLayoutTree | 5935 | 0 | 3.8 | 3032.8 | - |
| 390 | hero | cand | 15 | Layout | 2732 | 0 | 1.8 | 392.6 | - |
| 390 | hero | cand | 15 | image decode task | 1825 | 60 | 54.6 | 3231.0 | 31.1, 31.1, 31.2, 31.3, 31.3, 31.3, 31.4, 31.5, 31.5, 31.5, 31.5, 31.5, 31.6, 31.6, 31.6, 31.6, 31.7, 31.7, 31.8, 31.8, 31.8, 31.9, 32.0, 32.0, 32.1, 32.2, 32.3, 32.4, 32.4, 32.9, 33.3, 33.5, 33.7, 33.8, 34.0, 34.2, 34.5, 34.5, 34.5, 34.5, 34.5, 34.6, 34.7, 34.7, 34.7, 52.7, 52.9, 53.0, 53.4, 53.4, 53.5, 53.6, 53.7, 53.8, 53.8, 53.8, 54.0, 54.1, 54.6, 54.6 |
| 1280 | end | orig | 15 | BeginMainFrame | 960 | 29 | 69.9 | 6428.5 | 15.1, 15.2, 15.2, 15.4, 16.1, 16.2, 16.2, 16.5, 16.5, 17.0, 17.0, 18.0, 18.2, 18.3, 19.6, 20.5, 20.9, 20.9, 21.4, 21.6, 22.1, 22.1, 22.6, 44.3, 46.3, 46.8, 47.2, 56.2, 69.9 |
| 1280 | end | orig | 15 | Paint | 12546 | 0 | 3.9 | 1769.8 | - |
| 1280 | end | orig | 15 | UpdateLayoutTree | 1484 | 0 | 11.7 | 2361.7 | - |
| 1280 | end | orig | 15 | Layout | 1063 | 0 | 3.3 | 269.5 | - |
| 1280 | end | orig | 15 | image decode task | 6931 | 3 | 18.7 | 5253.5 | 15.0, 18.3, 18.7 |
| 1280 | end | base | 15 | BeginMainFrame | 976 | 27 | 61.1 | 7017.8 | 15.0, 15.1, 15.1, 15.2, 15.5, 15.9, 15.9, 16.0, 16.0, 16.1, 16.6, 16.9, 16.9, 17.0, 17.0, 17.6, 18.3, 19.0, 20.2, 20.6, 20.9, 21.2, 23.4, 41.6, 46.0, 48.5, 61.1 |
| 1280 | end | base | 15 | Paint | 12540 | 0 | 3.8 | 1872.9 | - |
| 1280 | end | base | 15 | UpdateLayoutTree | 1512 | 0 | 9.7 | 1946.9 | - |
| 1280 | end | base | 15 | Layout | 1057 | 0 | 2.8 | 276.7 | - |
| 1280 | end | base | 15 | image decode task | 7039 | 3 | 17.9 | 5310.9 | 15.1, 15.6, 17.9 |
| 1280 | end | aa | 15 | BeginMainFrame | 981 | 17 | 51.9 | 6867.4 | 15.0, 15.2, 15.6, 16.0, 16.6, 16.6, 16.7, 16.8, 17.1, 17.3, 17.6, 23.8, 34.1, 39.6, 46.0, 49.4, 51.9 |
| 1280 | end | aa | 15 | Paint | 12815 | 0 | 3.7 | 1875.8 | - |
| 1280 | end | aa | 15 | UpdateLayoutTree | 1509 | 0 | 7.6 | 1873.1 | - |
| 1280 | end | aa | 15 | Layout | 1051 | 0 | 2.4 | 268.5 | - |
| 1280 | end | aa | 15 | image decode task | 7048 | 0 | 12.4 | 5338.9 | - |
| 1280 | end | cand | 15 | BeginMainFrame | 986 | 27 | 51.9 | 6895.2 | 15.2, 15.2, 15.5, 15.6, 15.6, 15.9, 16.1, 16.2, 16.3, 16.4, 16.4, 16.7, 16.8, 18.0, 18.5, 19.1, 22.8, 23.1, 33.5, 33.7, 35.0, 35.5, 38.9, 39.5, 42.9, 47.6, 51.9 |
| 1280 | end | cand | 15 | Paint | 12820 | 0 | 8.0 | 1888.6 | - |
| 1280 | end | cand | 15 | UpdateLayoutTree | 1517 | 0 | 9.3 | 1846.3 | - |
| 1280 | end | cand | 15 | Layout | 1054 | 0 | 1.6 | 261.8 | - |
| 1280 | end | cand | 15 | image decode task | 7184 | 3 | 18.4 | 5490.2 | 16.3, 16.8, 18.4 |
| 1280 | hero | orig | 15 | BeginMainFrame | 2340 | 1 | 19.5 | 9326.9 | 19.5 |
| 1280 | hero | orig | 15 | Paint | 6590 | 0 | 2.5 | 876.3 | - |
| 1280 | hero | orig | 15 | UpdateLayoutTree | 5652 | 0 | 8.3 | 3806.3 | - |
| 1280 | hero | orig | 15 | Layout | 1474 | 0 | 0.5 | 279.9 | - |
| 1280 | hero | orig | 15 | image decode task | 596 | 0 | 14.8 | 1100.6 | - |
| 1280 | hero | base | 15 | BeginMainFrame | 2340 | 0 | 14.8 | 9988.4 | - |
| 1280 | hero | base | 15 | Paint | 6553 | 0 | 2.9 | 962.8 | - |
| 1280 | hero | base | 15 | UpdateLayoutTree | 5637 | 0 | 7.1 | 3088.5 | - |
| 1280 | hero | base | 15 | Layout | 1459 | 0 | 0.8 | 305.7 | - |
| 1280 | hero | base | 15 | image decode task | 432 | 0 | 13.9 | 1001.3 | - |
| 1280 | hero | aa | 15 | BeginMainFrame | 2343 | 0 | 13.6 | 9873.5 | - |
| 1280 | hero | aa | 15 | Paint | 6548 | 0 | 2.8 | 950.7 | - |
| 1280 | hero | aa | 15 | UpdateLayoutTree | 5632 | 0 | 4.9 | 3028.6 | - |
| 1280 | hero | aa | 15 | Layout | 1458 | 0 | 0.8 | 301.8 | - |
| 1280 | hero | aa | 15 | image decode task | 447 | 0 | 12.6 | 1011.9 | - |
| 1280 | hero | cand | 15 | BeginMainFrame | 2340 | 1 | 15.2 | 9602.5 | 15.2 |
| 1280 | hero | cand | 15 | Paint | 6532 | 0 | 2.7 | 938.0 | - |
| 1280 | hero | cand | 15 | UpdateLayoutTree | 5641 | 0 | 8.2 | 2966.2 | - |
| 1280 | hero | cand | 15 | Layout | 1462 | 0 | 0.7 | 290.8 | - |
| 1280 | hero | cand | 15 | image decode task | 436 | 0 | 12.5 | 1019.2 | - |

336 traced windows from runs before the page-sink filter hold counts over every process; they are not shown (see the handoff).
