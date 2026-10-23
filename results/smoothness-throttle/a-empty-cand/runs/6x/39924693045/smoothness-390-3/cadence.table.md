Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39924693045:leg, 390px, window hero** (CPU throttle 6x, candidate default, A/A spread 16.27 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1081 | 31.54 | 7.10 | 7 of 7 | 9,11,9,9,9,10,10 | 33.3 | 66.7 | 216.7 | 250.0 |
| base | 7 | 1089 | 31.40 | 16.27 | 7 of 7 | 10,11,9,9,12,10,10 | 33.3 | 66.7 | 150.0 | 216.7 |
| aa | 7 | 1087 | 34.13 | 9.68 | 7 of 7 | 15,11,14,9,12,10,10 | 33.4 | 66.7 | 150.1 | 233.4 |
| cand | 7 | 1075 | 34.79 | 10.52 | 7 of 7 | 11,12,9,9,12,7,10 | 33.4 | 66.7 | 150.0 | 233.2 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924693045:leg, 390px, window end** (CPU throttle 6x, candidate default, A/A spread 14.37 points)

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
| 390 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 1.22 | 14.37 |
| 390 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.47 | 14.37 |
| 390 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 1.69 | 14.37 |
| 390 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.14 | 16.27 |
| 390 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 3.39 | 16.27 |
| 390 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 3.25 | 16.27 |

Samples: 39924693045:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39924693045:leg | 390 | hero | orig | 7 | 67 | 83.3 | 2058 | 7 |
| 39924693045:leg | 390 | hero | base | 7 | 71 | 83.3 | 1596 | 7 |
| 39924693045:leg | 390 | hero | aa | 7 | 81 | 83.3 | 1596 | 7 |
| 39924693045:leg | 390 | hero | cand | 7 | 70 | 83.3 | 1596 | 7 |
| 39924693045:leg | 390 | end | orig | 7 | 88 | 66.7 | 5103 | 7 |
| 39924693045:leg | 390 | end | base | 7 | 76 | 66.7 | 5103 | 7 |
| 39924693045:leg | 390 | end | aa | 7 | 76 | 66.7 | 5103 | 7 |
| 39924693045:leg | 390 | end | cand | 7 | 76 | 66.7 | 5103 | 7 |
