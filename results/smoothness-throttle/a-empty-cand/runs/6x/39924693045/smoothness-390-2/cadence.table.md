Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39924693045:leg, 390px, window hero** (CPU throttle 6x, candidate default, A/A spread 25.65 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1067 | 38.98 | 20.27 | 7 of 7 | 15,16,8,11,11,9,8 | 33.4 | 66.7 | 216.7 | 283.4 |
| base | 7 | 1068 | 38.76 | 25.65 | 7 of 7 | 14,18,9,12,17,11,17 | 33.4 | 66.7 | 166.7 | 250.0 |
| aa | 7 | 1064 | 41.63 | 14.36 | 7 of 7 | 19,20,17,10,15,15,12 | 33.4 | 66.7 | 183.3 | 250.0 |
| cand | 7 | 1074 | 37.70 | 30.47 | 7 of 7 | 19,21,11,8,13,13,11 | 33.4 | 66.7 | 166.6 | 250.0 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924693045:leg, 390px, window end** (CPU throttle 6x, candidate default, A/A spread 12.86 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 409 | 34.22 | 11.46 | 7 of 7 | 12,12,11,13,12,13,14 | 16.7 | 83.4 | 100.0 | 100.1 |
| base | 7 | 390 | 37.43 | 12.86 | 7 of 7 | 14,11,10,11,11,10,12 | 33.3 | 83.3 | 100.0 | 100.0 |
| aa | 7 | 401 | 34.66 | 11.66 | 7 of 7 | 10,12,10,10,10,12,11 | 33.3 | 83.3 | 83.4 | 100.0 |
| cand | 7 | 399 | 35.08 | 13.73 | 7 of 7 | 13,11,10,11,11,13,11 | 33.3 | 83.3 | 99.9 | 116.6 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 3.21 | 12.86 |
| 390 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -2.35 | 12.86 |
| 390 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.86 | 12.86 |
| 390 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.22 | 25.65 |
| 390 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -1.06 | 25.65 |
| 390 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -1.28 | 25.65 |

Samples: 39924693045:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39924693045:leg | 390 | hero | orig | 7 | 78 | 83.2 | 1680 | 7 |
| 39924693045:leg | 390 | hero | base | 7 | 98 | 66.8 | 1596 | 7 |
| 39924693045:leg | 390 | hero | aa | 7 | 108 | 66.7 | 1596 | 7 |
| 39924693045:leg | 390 | hero | cand | 7 | 96 | 66.7 | 1596 | 7 |
| 39924693045:leg | 390 | end | orig | 7 | 87 | 83.3 | 5103 | 7 |
| 39924693045:leg | 390 | end | base | 7 | 79 | 66.8 | 5103 | 7 |
| 39924693045:leg | 390 | end | aa | 7 | 75 | 66.7 | 5103 | 7 |
| 39924693045:leg | 390 | end | cand | 7 | 80 | 66.7 | 5103 | 7 |
