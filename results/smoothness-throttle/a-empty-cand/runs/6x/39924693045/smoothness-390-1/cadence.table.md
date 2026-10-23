Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39924693045:leg, 390px, window hero** (CPU throttle 6x, candidate default, A/A spread 10.66 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1073 | 37.55 | 9.60 | 7 of 7 | 10,11,11,9,10,12,11 | 33.4 | 66.7 | 233.3 | 266.7 |
| base | 7 | 1079 | 40.50 | 10.51 | 7 of 7 | 14,10,11,14,17,10,12 | 33.4 | 66.7 | 166.7 | 233.4 |
| aa | 7 | 1085 | 38.43 | 10.66 | 7 of 7 | 12,15,11,13,16,14,13 | 33.4 | 66.7 | 166.7 | 233.4 |
| cand | 7 | 1080 | 37.22 | 12.83 | 7 of 7 | 14,14,14,13,12,14,11 | 33.4 | 66.7 | 150.1 | 233.3 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924693045:leg, 390px, window end** (CPU throttle 6x, candidate default, A/A spread 16.97 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 414 | 32.60 | 4.80 | 7 of 7 | 12,11,13,13,13,10,13 | 16.7 | 83.4 | 100.0 | 100.1 |
| base | 7 | 399 | 33.83 | 7.11 | 7 of 7 | 11,14,12,11,11,12,9 | 33.3 | 83.3 | 100.0 | 116.7 |
| aa | 7 | 392 | 38.01 | 16.97 | 7 of 7 | 12,11,8,14,12,12,11 | 33.3 | 83.3 | 100.0 | 133.3 |
| cand | 7 | 417 | 33.09 | 19.87 | 7 of 7 | 10,12,11,10,11,9,9 | 33.3 | 83.3 | 99.9 | 100.0 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 1.23 | 16.97 |
| 390 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.74 | 16.97 |
| 390 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.49 | 16.97 |
| 390 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 2.95 | 10.66 |
| 390 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -3.28 | 10.66 |
| 390 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.33 | 10.66 |

Samples: 39924693045:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39924693045:leg | 390 | hero | orig | 7 | 74 | 83.3 | 1722 | 7 |
| 39924693045:leg | 390 | hero | base | 7 | 88 | 83.3 | 1596 | 7 |
| 39924693045:leg | 390 | hero | aa | 7 | 94 | 66.7 | 1596 | 7 |
| 39924693045:leg | 390 | hero | cand | 7 | 92 | 83.2 | 1596 | 7 |
| 39924693045:leg | 390 | end | orig | 7 | 85 | 83.3 | 5103 | 7 |
| 39924693045:leg | 390 | end | base | 7 | 80 | 66.7 | 5103 | 7 |
| 39924693045:leg | 390 | end | aa | 7 | 80 | 66.7 | 5103 | 7 |
| 39924693045:leg | 390 | end | cand | 7 | 72 | 66.7 | 5103 | 7 |
