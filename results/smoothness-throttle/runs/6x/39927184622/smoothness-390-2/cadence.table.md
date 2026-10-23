Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39927184622:leg, 390px, window hero** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 15.50 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1052 | 41.63 | 8.61 | 7 of 7 | 12,13,11,22,15,14,13 | 33.4 | 66.7 | 250.0 | 333.3 |
| base | 7 | 1069 | 42.37 | 15.50 | 7 of 7 | 12,17,16,13,18,22,13 | 33.4 | 66.8 | 183.2 | 250.0 |
| aa | 7 | 1072 | 42.25 | 12.90 | 7 of 7 | 15,18,17,17,19,15,19 | 33.4 | 66.8 | 183.3 | 249.9 |
| cand | 7 | 1062 | 43.31 | 4.28 | 7 of 7 | 17,17,14,14,12,20,17 | 33.4 | 66.7 | 183.3 | 250.0 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927184622:leg, 390px, window end** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 16.26 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 397 | 34.25 | 6.52 | 7 of 7 | 11,10,12,12,12,14,11 | 33.2 | 83.4 | 100.0 | 116.7 |
| base | 7 | 389 | 37.78 | 16.26 | 7 of 7 | 13,12,11,10,12,11,10 | 33.3 | 83.3 | 99.9 | 116.8 |
| aa | 7 | 377 | 39.25 | 10.97 | 7 of 7 | 11,12,12,12,13,12,11 | 33.3 | 83.3 | 100.0 | 133.3 |
| cand | 7 | 412 | 31.55 | 11.20 | 7 of 7 | 11,10,11,11,12,12,10 | 33.3 | 83.3 | 99.9 | 116.8 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 3.53 | 16.26 |
| 390 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -6.23 | 16.26 |
| 390 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -2.70 | 16.26 |
| 390 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.74 | 15.50 |
| 390 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.94 | 15.50 |
| 390 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 1.68 | 15.50 |

Samples: 39927184622:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39927184622:leg | 390 | hero | orig | 7 | 100 | 66.7 | 1722 | 7 |
| 39927184622:leg | 390 | hero | base | 7 | 111 | 66.7 | 1596 | 7 |
| 39927184622:leg | 390 | hero | aa | 7 | 120 | 66.7 | 1596 | 7 |
| 39927184622:leg | 390 | hero | cand | 7 | 111 | 66.7 | 1596 | 7 |
| 39927184622:leg | 390 | end | orig | 7 | 82 | 83.3 | 5103 | 7 |
| 39927184622:leg | 390 | end | base | 7 | 79 | 66.8 | 5103 | 7 |
| 39927184622:leg | 390 | end | aa | 7 | 83 | 83.2 | 5103 | 7 |
| 39927184622:leg | 390 | end | cand | 7 | 77 | 66.7 | 5103 | 7 |
