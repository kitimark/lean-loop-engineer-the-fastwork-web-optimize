Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39927184622:leg, 390px, window hero** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 11.47 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1102 | 26.40 | 4.21 | 7 of 7 | 9,9,6,8,9,9,8 | 33.3 | 66.6 | 200.0 | 250.0 |
| base | 7 | 1093 | 25.70 | 8.08 | 7 of 7 | 10,8,9,8,9,9,10 | 33.3 | 66.7 | 149.9 | 233.3 |
| aa | 7 | 1090 | 27.61 | 11.47 | 7 of 7 | 9,14,9,8,13,8,9 | 33.3 | 66.6 | 150.0 | 233.3 |
| cand | 7 | 1091 | 26.30 | 15.61 | 7 of 7 | 13,8,8,10,11,8,9 | 33.3 | 66.6 | 150.0 | 200.1 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927184622:leg, 390px, window end** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 13.19 points)

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
| 390 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 3.08 | 13.19 |
| 390 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -7.85 | 13.19 |
| 390 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -4.77 | 13.19 |
| 390 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.70 | 11.47 |
| 390 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.60 | 11.47 |
| 390 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.10 | 11.47 |

Samples: 39927184622:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39927184622:leg | 390 | hero | orig | 7 | 58 | 83.3 | 2058 | 7 |
| 39927184622:leg | 390 | hero | base | 7 | 63 | 83.3 | 1596 | 7 |
| 39927184622:leg | 390 | hero | aa | 7 | 70 | 83.2 | 1596 | 7 |
| 39927184622:leg | 390 | hero | cand | 7 | 67 | 83.3 | 1596 | 7 |
| 39927184622:leg | 390 | end | orig | 7 | 84 | 66.7 | 5103 | 7 |
| 39927184622:leg | 390 | end | base | 7 | 71 | 66.7 | 5103 | 7 |
| 39927184622:leg | 390 | end | aa | 7 | 74 | 66.7 | 5103 | 7 |
| 39927184622:leg | 390 | end | cand | 7 | 69 | 66.7 | 5103 | 7 |
