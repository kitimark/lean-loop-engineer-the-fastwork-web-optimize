Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms. Over 25 / 34 / 50 ms = intervals above that line; skipped slot = an interval that advances the 60 Hz slot count (rounded from the first frame) by more than 1 (Lean `Fw.Gate.Smooth.over25`, `skips`).

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39924675073:smoothness-1280-1, 1280px, window hero** (CPU throttle 1x, candidate default, A/A spread 1.29 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 2.85 | 0.64 | 1 of 7 | 1,0,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 83.4 |
| base | 7 | 1085 | 3.41 | 1.29 | 1 of 7 | 0,0,0,1,0,0,0 | 16.7 | 33.4 | 50.0 | 83.3 |
| aa | 7 | 1085 | 3.41 | 0.65 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 50.1 |
| cand | 7 | 1085 | 3.59 | 1.94 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 50.1 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924675073:smoothness-1280-1, 1280px, window end** (CPU throttle 1x, candidate default, A/A spread 4.47 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 541 | 14.04 | 7.56 | 7 of 7 | 2,2,2,2,2,2,2 | 16.7 | 50.0 | 66.7 | 116.8 |
| base | 7 | 549 | 13.47 | 4.47 | 7 of 7 | 2,4,4,3,4,2,1 | 16.7 | 50.0 | 66.7 | 83.4 |
| aa | 7 | 550 | 13.45 | 1.97 | 7 of 7 | 2,1,2,4,4,2,2 | 16.7 | 50.0 | 66.7 | 116.7 |
| cand | 7 | 540 | 14.62 | 5.35 | 7 of 7 | 4,2,3,3,4,3,1 | 16.7 | 50.0 | 66.7 | 116.8 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924675073:smoothness-1280-2, 1280px, window hero** (CPU throttle 1x, candidate default, A/A spread 1.29 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 4.51 | 1.93 | 1 of 7 | 0,0,0,0,1,0,0 | 16.7 | 33.4 | 50.0 | 83.2 |
| base | 7 | 1087 | 4.87 | 0.68 | 2 of 7 | 0,0,0,0,0,1,1 | 16.7 | 33.4 | 50.1 | 83.4 |
| aa | 7 | 1085 | 5.16 | 1.29 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 49.9 | 50.0 | 50.1 |
| cand | 7 | 1085 | 4.79 | 0.65 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.4 | 50.1 | 50.1 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924675073:smoothness-1280-2, 1280px, window end** (CPU throttle 1x, candidate default, A/A spread 4.95 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 502 | 17.52 | 7.14 | 7 of 7 | 6,4,3,3,4,3,4 | 33.3 | 66.6 | 66.8 | 116.7 |
| base | 7 | 506 | 16.40 | 3.51 | 7 of 7 | 5,5,3,5,5,4,3 | 33.3 | 66.6 | 99.9 | 116.7 |
| aa | 7 | 505 | 17.42 | 4.95 | 7 of 7 | 5,3,3,4,4,5,4 | 33.3 | 66.6 | 66.8 | 116.8 |
| cand | 7 | 506 | 18.37 | 5.85 | 7 of 7 | 4,4,4,4,4,2,4 | 33.3 | 66.6 | 66.8 | 116.6 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924675073:smoothness-1280-3, 1280px, window hero** (CPU throttle 1x, candidate default, A/A spread 1.31 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1085 | 2.94 | 0.64 | 1 of 7 | 0,1,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 83.3 |
| base | 7 | 1086 | 3.77 | 1.31 | 1 of 7 | 0,1,0,0,0,0,0 | 16.7 | 33.4 | 50.0 | 83.3 |
| aa | 7 | 1085 | 3.68 | 0.65 | 1 of 7 | 0,0,0,0,0,0,1 | 16.7 | 33.4 | 50.0 | 83.3 |
| cand | 7 | 1085 | 3.87 | 1.29 | 1 of 7 | 0,0,0,1,0,0,0 | 16.7 | 33.4 | 50.0 | 83.3 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924675073:smoothness-1280-3, 1280px, window end** (CPU throttle 1x, candidate default, A/A spread 6.04 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 525 | 13.33 | 5.49 | 7 of 7 | 4,3,3,3,3,2,2 | 33.2 | 50.1 | 66.8 | 116.7 |
| base | 7 | 536 | 15.48 | 5.53 | 7 of 7 | 5,3,3,3,2,2,2 | 16.8 | 50.1 | 66.7 | 116.6 |
| aa | 7 | 536 | 14.55 | 6.04 | 7 of 7 | 3,1,3,3,3,3,3 | 16.8 | 50.0 | 66.8 | 100.0 |
| cand | 7 | 526 | 15.01 | 6.16 | 7 of 7 | 1,4,3,3,2,2,4 | 33.2 | 50.1 | 66.7 | 100.0 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924675073:smoothness-390-1, 390px, window hero** (CPU throttle 1x, candidate default, A/A spread 0.58 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1204 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 33.3 | 33.4 |
| base | 7 | 1207 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| aa | 7 | 1208 | 0.66 | 0.58 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| cand | 7 | 1209 | 0.66 | 0.59 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: first
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39924675073:smoothness-390-1, 390px, window end** (CPU throttle 1x, candidate default, A/A spread 0.85 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 829 | 0.48 | 1.70 | 1 of 7 | 1,0,0,0,0,0,0 | 16.7 | 33.3 | 33.4 | 66.7 |
| base | 7 | 833 | 0.96 | 0.83 | 3 of 7 | 1,0,1,1,0,0,0 | 16.7 | 16.8 | 33.4 | 66.7 |
| aa | 7 | 829 | 1.20 | 0.85 | 5 of 7 | 1,1,1,0,0,1,1 | 16.7 | 16.8 | 49.9 | 66.8 |
| cand | 7 | 834 | 0.95 | 0.88 | 2 of 7 | 1,0,0,0,1,0,0 | 16.7 | 16.8 | 33.4 | 66.8 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924675073:smoothness-390-2, 390px, window hero** (CPU throttle 1x, candidate default, A/A spread 0.59 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1205 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 33.2 | 33.4 |
| base | 7 | 1208 | 0.66 | 0.59 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.5 |
| aa | 7 | 1208 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |
| cand | 7 | 1200 | 0.58 | 0.02 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |

Rate verdicts: orig vs base: first; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39924675073:smoothness-390-2, 390px, window end** (CPU throttle 1x, candidate default, A/A spread 0.83 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 837 | 0.47 | 1.69 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 33.2 | 33.4 | 50.1 |
| base | 7 | 833 | 0.96 | 0.82 | 6 of 7 | 1,1,1,1,1,0,1 | 16.7 | 16.8 | 33.4 | 66.8 |
| aa | 7 | 836 | 0.95 | 0.83 | 3 of 7 | 0,0,1,0,0,1,1 | 16.7 | 16.8 | 33.4 | 66.6 |
| cand | 7 | 832 | 1.20 | 0.85 | 5 of 7 | 0,1,1,1,1,0,1 | 16.7 | 16.8 | 50.0 | 66.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924675073:smoothness-390-3, 390px, window hero** (CPU throttle 1x, candidate default, A/A spread 0.01 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1208 | 0.00 | 0.00 | 0 of 7 | 0,0,0,0,0,0,0 | 16.7 | 16.8 | 33.2 | 33.4 |
| base | 7 | 1208 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.4 | 83.4 |
| aa | 7 | 1213 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.5 |
| cand | 7 | 1212 | 0.57 | 0.01 | 7 of 7 | 1,1,1,1,1,1,1 | 16.7 | 16.8 | 33.3 | 83.4 |

Rate verdicts: orig vs base: first; base vs cand: same; orig vs cand: first
Hitch verdicts: orig vs base: first; base vs cand: same; orig vs cand: first

**run 39924675073:smoothness-390-3, 390px, window end** (CPU throttle 1x, candidate default, A/A spread 1.68 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 837 | 1.07 | 1.68 | 2 of 7 | 1,1,0,0,0,0,0 | 16.7 | 16.8 | 49.9 | 66.7 |
| base | 7 | 832 | 1.32 | 0.85 | 4 of 7 | 1,0,0,1,1,0,1 | 16.7 | 16.8 | 49.9 | 66.7 |
| aa | 7 | 834 | 0.95 | 1.68 | 3 of 7 | 1,1,1,0,0,0,0 | 16.7 | 16.8 | 33.4 | 66.7 |
| cand | 7 | 832 | 0.84 | 1.69 | 6 of 7 | 1,1,1,1,1,0,1 | 16.7 | 16.8 | 33.4 | 66.8 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | base | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 0.48 | 0.85 |
| 390 | end | base | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | -0.01 | 0.85 |
| 390 | end | orig | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 0.47 | 0.85 |
| 390 | hero | orig | base | 3 | 2 / 2 | 2 / 0 / 1 / 0 | first smoother | 3 / 0 / 0 / 0 | first smoother | 0.57 | 0.58 |
| 390 | hero | base | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 0.00 | 0.58 |
| 390 | hero | orig | cand | 3 | 2 / 2 | 2 / 0 / 1 / 0 | first smoother | 3 / 0 / 0 / 0 | first smoother | 0.58 | 0.58 |
| 1280 | end | orig | base | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | -0.57 | 4.95 |
| 1280 | end | base | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 1.15 | 4.95 |
| 1280 | end | orig | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 0.85 | 4.95 |
| 1280 | hero | orig | base | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 0.56 | 1.29 |
| 1280 | hero | base | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 0.10 | 1.29 |
| 1280 | hero | orig | cand | 3 | 2 / 2 | 0 / 0 / 3 / 0 | not told apart | 0 / 0 / 3 / 0 | not told apart | 0.74 | 1.29 |

Samples: 39924675073:smoothness-390-1, 39924675073:smoothness-390-2, 39924675073:smoothness-390-3, 39924675073:smoothness-1280-1, 39924675073:smoothness-1280-2, 39924675073:smoothness-1280-3

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39924675073:smoothness-1280-1 | 1280 | hero | orig | 7 | 1 | 83.4 | 840 | 1 |
| 39924675073:smoothness-1280-1 | 1280 | hero | base | 7 | 1 | 83.3 | 840 | 1 |
| 39924675073:smoothness-1280-1 | 1280 | end | orig | 7 | 14 | 66.6 | 8269 | 7 |
| 39924675073:smoothness-1280-1 | 1280 | end | base | 7 | 20 | 66.7 | 8269 | 7 |
| 39924675073:smoothness-1280-1 | 1280 | end | aa | 7 | 17 | 66.7 | 8269 | 7 |
| 39924675073:smoothness-1280-1 | 1280 | end | cand | 7 | 20 | 66.7 | 8269 | 7 |
| 39924675073:smoothness-1280-2 | 1280 | hero | orig | 7 | 1 | 83.2 | 798 | 1 |
| 39924675073:smoothness-1280-2 | 1280 | hero | base | 7 | 2 | 83.3 | 924 | 2 |
| 39924675073:smoothness-1280-2 | 1280 | end | orig | 7 | 27 | 66.7 | 8269 | 7 |
| 39924675073:smoothness-1280-2 | 1280 | end | base | 7 | 30 | 66.7 | 8269 | 7 |
| 39924675073:smoothness-1280-2 | 1280 | end | aa | 7 | 28 | 66.7 | 8269 | 7 |
| 39924675073:smoothness-1280-2 | 1280 | end | cand | 7 | 26 | 66.7 | 8269 | 7 |
| 39924675073:smoothness-1280-3 | 1280 | hero | orig | 7 | 1 | 83.3 | 882 | 1 |
| 39924675073:smoothness-1280-3 | 1280 | hero | base | 7 | 1 | 83.3 | 840 | 1 |
| 39924675073:smoothness-1280-3 | 1280 | hero | aa | 7 | 1 | 83.3 | 840 | 1 |
| 39924675073:smoothness-1280-3 | 1280 | hero | cand | 7 | 1 | 83.3 | 966 | 1 |
| 39924675073:smoothness-1280-3 | 1280 | end | orig | 7 | 20 | 66.7 | 8269 | 7 |
| 39924675073:smoothness-1280-3 | 1280 | end | base | 7 | 20 | 66.7 | 8269 | 7 |
| 39924675073:smoothness-1280-3 | 1280 | end | aa | 7 | 19 | 66.7 | 8269 | 7 |
| 39924675073:smoothness-1280-3 | 1280 | end | cand | 7 | 19 | 66.7 | 8269 | 7 |
| 39924675073:smoothness-390-1 | 390 | hero | base | 7 | 7 | 83.3 | 672 | 7 |
| 39924675073:smoothness-390-1 | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39924675073:smoothness-390-1 | 390 | hero | cand | 7 | 7 | 83.3 | 672 | 7 |
| 39924675073:smoothness-390-1 | 390 | end | orig | 7 | 1 | 66.7 | 5103 | 0 |
| 39924675073:smoothness-390-1 | 390 | end | base | 7 | 3 | 66.7 | 5103 | 0 |
| 39924675073:smoothness-390-1 | 390 | end | aa | 7 | 5 | 66.7 | 5103 | 4 |
| 39924675073:smoothness-390-1 | 390 | end | cand | 7 | 2 | 66.7 | 5103 | 0 |
| 39924675073:smoothness-390-2 | 390 | hero | base | 7 | 7 | 83.4 | 672 | 7 |
| 39924675073:smoothness-390-2 | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39924675073:smoothness-390-2 | 390 | hero | cand | 7 | 7 | 83.3 | 672 | 7 |
| 39924675073:smoothness-390-2 | 390 | end | base | 7 | 6 | 66.6 | 5103 | 2 |
| 39924675073:smoothness-390-2 | 390 | end | aa | 7 | 3 | 66.6 | 5103 | 2 |
| 39924675073:smoothness-390-2 | 390 | end | cand | 7 | 5 | 66.7 | 5103 | 2 |
| 39924675073:smoothness-390-3 | 390 | hero | base | 7 | 7 | 83.3 | 672 | 7 |
| 39924675073:smoothness-390-3 | 390 | hero | aa | 7 | 7 | 83.3 | 672 | 7 |
| 39924675073:smoothness-390-3 | 390 | hero | cand | 7 | 7 | 83.4 | 672 | 7 |
| 39924675073:smoothness-390-3 | 390 | end | orig | 7 | 2 | 66.6 | 5103 | 0 |
| 39924675073:smoothness-390-3 | 390 | end | base | 7 | 4 | 66.6 | 5103 | 0 |
| 39924675073:smoothness-390-3 | 390 | end | aa | 7 | 3 | 66.7 | 5103 | 0 |
| 39924675073:smoothness-390-3 | 390 | end | cand | 7 | 6 | 66.6 | 5103 | 2 |

Chromium histograms (`Browser.getHistograms`, delta per window): none reported a sample in these windows.

### Frames of the page's compositor sink (traced reps, the renderer process of the page only; reported beside the verdict, never in it)

A frame is one `frame_sequence`; `dropped` = any of its pipeline reporters dropped, `dropped (all)` = every reporter dropped, `presented` = the rest with a presented reporter.

| width | window | arm | traced reps | runs | frames | presented | dropped | dropped % | dropped (all) | dropped (all) % | rAF frames in the same reps | presented p95 ms (median of reps) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | 15 | 3 | 1898 | 1815 | 83 | 4.4 | 83 | 4.4 | 1774 | 67.5 |
| 390 | end | base | 15 | 3 | 1890 | 1804 | 86 | 4.6 | 86 | 4.6 | 1768 | 66.0 |
| 390 | end | aa | 15 | 3 | 1888 | 1802 | 86 | 4.6 | 86 | 4.6 | 1767 | 64.4 |
| 390 | end | cand | 15 | 3 | 1892 | 1806 | 86 | 4.5 | 86 | 4.5 | 1766 | 70.1 |
| 390 | hero | orig | 15 | 3 | 2596 | 2366 | 230 | 8.9 | 46 | 1.8 | 2543 | 32.3 |
| 390 | hero | base | 15 | 3 | 2663 | 2357 | 306 | 11.5 | 114 | 4.3 | 2551 | 32.3 |
| 390 | hero | aa | 15 | 3 | 2654 | 2350 | 304 | 11.5 | 115 | 4.3 | 2543 | 32.5 |
| 390 | hero | cand | 15 | 3 | 2671 | 2347 | 324 | 12.1 | 117 | 4.4 | 2556 | 32.1 |
| 1280 | end | orig | 15 | 3 | 1926 | 1107 | 819 | 42.5 | 819 | 42.5 | 1074 | 183.4 |
| 1280 | end | base | 15 | 3 | 1956 | 1133 | 823 | 42.1 | 823 | 42.1 | 1089 | 159.6 |
| 1280 | end | aa | 15 | 3 | 1956 | 1127 | 829 | 42.4 | 829 | 42.4 | 1084 | 181.1 |
| 1280 | end | cand | 15 | 3 | 1950 | 1122 | 828 | 42.5 | 828 | 42.5 | 1089 | 157.7 |
| 1280 | hero | orig | 15 | 3 | 2913 | 2277 | 636 | 21.8 | 608 | 20.9 | 2325 | 75.5 |
| 1280 | hero | base | 15 | 3 | 2918 | 2285 | 633 | 21.7 | 604 | 20.7 | 2326 | 76.8 |
| 1280 | hero | aa | 15 | 3 | 2938 | 2290 | 648 | 22.1 | 619 | 21.1 | 2326 | 76.0 |
| 1280 | hero | cand | 15 | 3 | 2920 | 2282 | 638 | 21.8 | 609 | 20.9 | 2327 | 77.1 |

### Fixed slow-event names of the traced reps (page renderer process; every row is always listed, n = 0 means the event never ran; long = 15 ms or more)

| width | window | arm | traced reps | event | events | long | longest ms | total ms | long durations ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | 15 | BeginMainFrame | 1789 | 25 | 52.9 | 10912.1 | 15.1, 15.4, 15.6, 15.7, 15.7, 15.8, 16.0, 16.2, 16.6, 16.6, 31.8, 33.8, 34.4, 36.5, 36.7, 37.6, 37.9, 38.8, 39.1, 40.4, 44.8, 46.7, 50.9, 51.6, 52.9 |
| 390 | end | orig | 15 | Paint | 15706 | 0 | 3.6 | 2271.8 | - |
| 390 | end | orig | 15 | UpdateLayoutTree | 2915 | 0 | 10.6 | 4309.9 | - |
| 390 | end | orig | 15 | Layout | 2309 | 0 | 0.4 | 445.1 | - |
| 390 | end | orig | 15 | image decode task | 7799 | 0 | 11.7 | 1101.2 | - |
| 390 | end | base | 15 | BeginMainFrame | 1783 | 15 | 61.2 | 11946.9 | 35.7, 39.2, 40.5, 42.5, 43.9, 45.5, 46.7, 48.7, 50.7, 50.7, 57.7, 58.3, 58.9, 60.3, 61.2 |
| 390 | end | base | 15 | Paint | 15724 | 0 | 3.4 | 2307.6 | - |
| 390 | end | base | 15 | UpdateLayoutTree | 2905 | 0 | 6.6 | 3535.0 | - |
| 390 | end | base | 15 | Layout | 2311 | 0 | 1.2 | 472.6 | - |
| 390 | end | base | 15 | image decode task | 7740 | 0 | 10.0 | 1067.7 | - |
| 390 | end | aa | 15 | BeginMainFrame | 1782 | 16 | 58.8 | 11883.0 | 15.5, 38.7, 39.1, 41.1, 41.9, 41.9, 45.3, 46.3, 46.5, 46.6, 46.8, 49.0, 51.3, 53.2, 56.8, 58.8 |
| 390 | end | aa | 15 | Paint | 15756 | 0 | 3.5 | 2318.4 | - |
| 390 | end | aa | 15 | UpdateLayoutTree | 2905 | 0 | 6.3 | 3516.2 | - |
| 390 | end | aa | 15 | Layout | 2321 | 0 | 0.9 | 466.5 | - |
| 390 | end | aa | 15 | image decode task | 7756 | 0 | 12.0 | 1090.7 | - |
| 390 | end | cand | 15 | BeginMainFrame | 1781 | 16 | 59.3 | 11891.6 | 15.1, 37.4, 41.1, 41.4, 43.0, 43.4, 43.6, 43.8, 44.3, 46.0, 46.3, 47.0, 51.1, 54.8, 58.7, 59.3 |
| 390 | end | cand | 15 | Paint | 15808 | 0 | 3.4 | 2321.9 | - |
| 390 | end | cand | 15 | UpdateLayoutTree | 2903 | 0 | 7.2 | 3548.7 | - |
| 390 | end | cand | 15 | Layout | 2318 | 0 | 0.8 | 473.7 | - |
| 390 | end | cand | 15 | image decode task | 7736 | 0 | 9.2 | 1062.2 | - |
| 390 | hero | orig | 15 | BeginMainFrame | 2558 | 7 | 16.1 | 11444.7 | 15.1, 15.2, 15.2, 15.3, 15.9, 16.1, 16.1 |
| 390 | hero | orig | 15 | Paint | 15640 | 0 | 2.7 | 1553.3 | - |
| 390 | hero | orig | 15 | UpdateLayoutTree | 6008 | 0 | 5.8 | 3952.9 | - |
| 390 | hero | orig | 15 | Layout | 2720 | 0 | 2.1 | 455.3 | - |
| 390 | hero | orig | 15 | image decode task | 1677 | 30 | 55.5 | 2295.6 | 30.7, 31.1, 31.1, 31.2, 31.3, 31.3, 31.3, 31.3, 31.4, 31.5, 31.8, 32.5, 32.9, 33.2, 33.6, 52.3, 52.4, 52.6, 52.6, 52.6, 52.8, 52.8, 52.9, 53.1, 53.1, 53.1, 53.2, 53.3, 54.2, 55.5 |
| 390 | hero | base | 15 | BeginMainFrame | 2566 | 12 | 17.8 | 11606.2 | 16.4, 16.4, 16.5, 16.8, 16.8, 16.8, 17.2, 17.3, 17.5, 17.6, 17.6, 17.8 |
| 390 | hero | base | 15 | Paint | 15050 | 0 | 3.0 | 1498.4 | - |
| 390 | hero | base | 15 | UpdateLayoutTree | 5937 | 0 | 4.3 | 3231.1 | - |
| 390 | hero | base | 15 | Layout | 2727 | 0 | 3.8 | 437.9 | - |
| 390 | hero | base | 15 | image decode task | 1814 | 60 | 54.5 | 3182.7 | 30.9, 30.9, 31.0, 31.0, 31.0, 31.1, 31.2, 31.2, 31.3, 31.3, 31.3, 31.3, 31.4, 31.4, 31.4, 31.4, 31.5, 31.5, 31.5, 31.5, 31.6, 31.6, 31.7, 31.7, 31.8, 31.8, 31.8, 32.0, 32.0, 32.1, 33.3, 33.4, 33.5, 33.8, 33.8, 33.8, 33.9, 33.9, 34.0, 34.0, 34.1, 34.1, 34.1, 34.2, 34.2, 51.9, 52.0, 52.4, 52.4, 52.5, 52.5, 52.6, 52.6, 52.7, 52.7, 53.0, 53.1, 53.3, 53.6, 54.5 |
| 390 | hero | aa | 15 | BeginMainFrame | 2558 | 14 | 18.2 | 11638.2 | 15.1, 15.7, 16.3, 16.6, 17.0, 17.1, 17.5, 17.5, 17.6, 17.7, 17.8, 18.1, 18.2, 18.2 |
| 390 | hero | aa | 15 | Paint | 15012 | 0 | 3.3 | 1505.4 | - |
| 390 | hero | aa | 15 | UpdateLayoutTree | 5933 | 0 | 5.0 | 3224.7 | - |
| 390 | hero | aa | 15 | Layout | 2735 | 0 | 1.9 | 437.4 | - |
| 390 | hero | aa | 15 | image decode task | 1800 | 60 | 57.8 | 3227.7 | 30.8, 30.9, 31.1, 31.1, 31.1, 31.2, 31.2, 31.3, 31.3, 31.3, 31.4, 31.4, 31.5, 31.5, 31.5, 31.5, 31.5, 31.6, 31.6, 31.7, 31.7, 31.8, 31.8, 31.8, 31.9, 31.9, 32.5, 33.1, 33.3, 33.5, 33.5, 33.7, 33.7, 33.9, 34.0, 34.0, 34.0, 34.0, 34.0, 34.2, 34.2, 34.3, 34.5, 35.6, 36.8, 51.5, 52.2, 52.4, 52.5, 52.7, 52.8, 53.1, 53.1, 53.2, 53.4, 53.7, 53.8, 54.1, 54.5, 57.8 |
| 390 | hero | cand | 15 | BeginMainFrame | 2571 | 15 | 22.1 | 11572.0 | 15.6, 15.8, 16.4, 16.6, 16.8, 16.8, 16.9, 17.1, 17.5, 17.6, 17.9, 18.1, 19.4, 19.4, 22.1 |
| 390 | hero | cand | 15 | Paint | 15046 | 0 | 3.3 | 1495.9 | - |
| 390 | hero | cand | 15 | UpdateLayoutTree | 5939 | 0 | 11.3 | 3214.0 | - |
| 390 | hero | cand | 15 | Layout | 2733 | 0 | 2.5 | 440.0 | - |
| 390 | hero | cand | 15 | image decode task | 1842 | 60 | 53.5 | 3187.8 | 30.9, 31.0, 31.1, 31.1, 31.1, 31.1, 31.2, 31.2, 31.2, 31.2, 31.2, 31.3, 31.3, 31.3, 31.3, 31.4, 31.4, 31.4, 31.5, 31.5, 31.5, 31.5, 31.5, 31.6, 31.6, 31.7, 31.7, 31.8, 31.8, 32.1, 33.4, 33.5, 33.6, 33.6, 33.7, 33.7, 33.7, 33.8, 33.8, 34.0, 34.0, 34.1, 34.3, 34.5, 34.5, 51.3, 52.3, 52.5, 52.5, 52.5, 52.5, 52.6, 52.6, 52.6, 52.9, 53.0, 53.0, 53.4, 53.5, 53.5 |
| 1280 | end | orig | 15 | BeginMainFrame | 1089 | 33 | 50.9 | 6769.1 | 15.1, 15.2, 15.3, 15.8, 15.8, 16.4, 16.4, 16.8, 17.0, 17.1, 17.5, 17.7, 18.4, 18.6, 18.6, 18.8, 19.1, 19.7, 19.8, 19.9, 20.2, 20.7, 23.8, 24.1, 25.2, 26.1, 27.4, 27.4, 36.8, 41.2, 44.1, 45.4, 50.9 |
| 1280 | end | orig | 15 | Paint | 13324 | 0 | 4.4 | 1799.3 | - |
| 1280 | end | orig | 15 | UpdateLayoutTree | 1673 | 0 | 11.2 | 2426.7 | - |
| 1280 | end | orig | 15 | Layout | 1206 | 0 | 0.7 | 258.0 | - |
| 1280 | end | orig | 15 | image decode task | 7919 | 2 | 17.5 | 5356.1 | 15.7, 17.5 |
| 1280 | end | base | 15 | BeginMainFrame | 1104 | 17 | 47.1 | 7183.4 | 15.4, 15.7, 16.0, 16.1, 16.2, 16.5, 16.7, 17.1, 17.2, 18.9, 19.1, 19.3, 20.4, 23.8, 25.3, 35.4, 47.1 |
| 1280 | end | base | 15 | Paint | 13419 | 0 | 4.1 | 1895.2 | - |
| 1280 | end | base | 15 | UpdateLayoutTree | 1699 | 0 | 9.0 | 1999.2 | - |
| 1280 | end | base | 15 | Layout | 1203 | 0 | 1.2 | 279.3 | - |
| 1280 | end | base | 15 | image decode task | 7741 | 3 | 18.7 | 5333.2 | 15.2, 15.8, 18.7 |
| 1280 | end | aa | 15 | BeginMainFrame | 1100 | 35 | 60.2 | 7661.3 | 15.2, 15.2, 15.5, 16.0, 16.1, 16.2, 16.6, 16.8, 16.9, 17.1, 17.3, 17.6, 17.7, 18.0, 18.5, 18.8, 18.9, 18.9, 19.0, 19.0, 19.3, 19.3, 19.5, 20.1, 23.3, 23.4, 24.0, 24.2, 42.0, 42.9, 50.7, 52.0, 52.9, 56.4, 60.2 |
| 1280 | end | aa | 15 | Paint | 13485 | 0 | 3.7 | 1918.1 | - |
| 1280 | end | aa | 15 | UpdateLayoutTree | 1684 | 0 | 9.0 | 2048.5 | - |
| 1280 | end | aa | 15 | Layout | 1193 | 0 | 1.8 | 286.3 | - |
| 1280 | end | aa | 15 | image decode task | 7816 | 1 | 21.0 | 5396.3 | 21.0 |
| 1280 | end | cand | 15 | BeginMainFrame | 1104 | 22 | 53.8 | 7384.9 | 15.1, 15.3, 16.1, 16.7, 17.0, 17.1, 17.2, 17.9, 18.4, 19.4, 19.5, 19.6, 20.2, 20.3, 20.5, 20.6, 21.1, 29.1, 33.7, 45.3, 49.1, 53.8 |
| 1280 | end | cand | 15 | Paint | 13553 | 0 | 4.2 | 1921.2 | - |
| 1280 | end | cand | 15 | UpdateLayoutTree | 1695 | 0 | 9.6 | 2013.9 | - |
| 1280 | end | cand | 15 | Layout | 1204 | 0 | 1.1 | 284.9 | - |
| 1280 | end | cand | 15 | image decode task | 7880 | 0 | 14.9 | 5371.4 | - |
| 1280 | hero | orig | 15 | BeginMainFrame | 2340 | 0 | 12.6 | 8808.0 | - |
| 1280 | hero | orig | 15 | Paint | 6463 | 0 | 2.6 | 840.1 | - |
| 1280 | hero | orig | 15 | UpdateLayoutTree | 5631 | 0 | 5.9 | 3633.4 | - |
| 1280 | hero | orig | 15 | Layout | 1488 | 0 | 0.3 | 272.9 | - |
| 1280 | hero | orig | 15 | image decode task | 699 | 0 | 14.9 | 1026.5 | - |
| 1280 | hero | base | 15 | BeginMainFrame | 2341 | 0 | 12.7 | 9310.0 | - |
| 1280 | hero | base | 15 | Paint | 6421 | 0 | 2.6 | 907.3 | - |
| 1280 | hero | base | 15 | UpdateLayoutTree | 5625 | 0 | 4.8 | 2915.5 | - |
| 1280 | hero | base | 15 | Layout | 1469 | 0 | 1.5 | 289.5 | - |
| 1280 | hero | base | 15 | image decode task | 534 | 0 | 11.4 | 916.7 | - |
| 1280 | hero | aa | 15 | BeginMainFrame | 2341 | 0 | 12.8 | 9483.8 | - |
| 1280 | hero | aa | 15 | Paint | 6441 | 0 | 2.7 | 914.7 | - |
| 1280 | hero | aa | 15 | UpdateLayoutTree | 5620 | 0 | 4.8 | 2951.6 | - |
| 1280 | hero | aa | 15 | Layout | 1472 | 0 | 0.7 | 294.2 | - |
| 1280 | hero | aa | 15 | image decode task | 527 | 0 | 11.9 | 926.0 | - |
| 1280 | hero | cand | 15 | BeginMainFrame | 2342 | 0 | 12.1 | 9494.6 | - |
| 1280 | hero | cand | 15 | Paint | 6436 | 0 | 2.6 | 915.2 | - |
| 1280 | hero | cand | 15 | UpdateLayoutTree | 5629 | 0 | 4.4 | 2962.7 | - |
| 1280 | hero | cand | 15 | Layout | 1476 | 0 | 0.7 | 291.4 | - |
| 1280 | hero | cand | 15 | image decode task | 547 | 0 | 11.6 | 919.3 | - |
