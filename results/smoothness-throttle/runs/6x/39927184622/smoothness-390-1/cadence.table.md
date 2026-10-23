Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39927184622:leg, 390px, window hero** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 9.49 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1107 | 11.65 | 10.06 | 7 of 7 | 4,8,7,6,7,5,7 | 33.3 | 50.0 | 183.3 | 216.7 |
| base | 7 | 1086 | 11.32 | 6.34 | 7 of 7 | 5,5,7,7,6,6,5 | 33.3 | 50.0 | 150.0 | 200.1 |
| aa | 7 | 1079 | 12.51 | 9.49 | 7 of 7 | 6,7,7,7,7,6,6 | 33.3 | 50.1 | 150.0 | 233.3 |
| cand | 7 | 1083 | 12.18 | 11.34 | 7 of 7 | 6,5,6,5,8,7,5 | 33.3 | 50.0 | 133.4 | 200.0 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927184622:leg, 390px, window end** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 14.85 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 509 | 23.37 | 7.41 | 7 of 7 | 9,9,8,9,11,9,9 | 16.7 | 66.7 | 83.3 | 83.4 |
| base | 7 | 512 | 22.26 | 6.87 | 7 of 7 | 3,5,6,5,8,8,6 | 16.7 | 66.7 | 66.7 | 83.3 |
| aa | 7 | 515 | 20.38 | 14.85 | 7 of 7 | 4,6,6,6,9,5,7 | 16.7 | 66.7 | 83.3 | 83.4 |
| cand | 7 | 532 | 18.98 | 2.79 | 7 of 7 | 5,1,3,6,5,6,6 | 16.7 | 66.6 | 66.7 | 83.4 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: second

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -1.11 | 14.85 |
| 390 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -3.28 | 14.85 |
| 390 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 1 / 0 / 0 | insufficient | -4.39 | 14.85 |
| 390 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.33 | 9.49 |
| 390 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.86 | 9.49 |
| 390 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.53 | 9.49 |

Samples: 39927184622:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39927184622:leg | 390 | hero | orig | 7 | 44 | 83.3 | 2100 | 7 |
| 39927184622:leg | 390 | hero | base | 7 | 41 | 116.6 | 1596 | 7 |
| 39927184622:leg | 390 | hero | aa | 7 | 46 | 83.3 | 1596 | 7 |
| 39927184622:leg | 390 | hero | cand | 7 | 42 | 100.0 | 1596 | 7 |
| 39927184622:leg | 390 | end | orig | 7 | 64 | 66.7 | 5103 | 7 |
| 39927184622:leg | 390 | end | base | 7 | 41 | 66.7 | 5103 | 7 |
| 39927184622:leg | 390 | end | aa | 7 | 43 | 66.7 | 5103 | 7 |
| 39927184622:leg | 390 | end | cand | 7 | 32 | 66.7 | 5103 | 7 |
