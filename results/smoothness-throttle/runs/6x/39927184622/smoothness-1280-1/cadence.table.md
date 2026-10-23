Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39927184622:leg, 1280px, window hero** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 7.94 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1079 | 19.92 | 4.54 | 7 of 7 | 7,7,6,6,8,7,8 | 33.3 | 50.1 | 83.3 | 100.0 |
| base | 7 | 1080 | 19.25 | 7.94 | 7 of 7 | 6,7,17,6,7,6,5 | 33.3 | 50.1 | 83.4 | 133.4 |
| aa | 7 | 1079 | 18.62 | 3.89 | 7 of 7 | 6,9,7,5,6,6,8 | 33.2 | 50.1 | 83.4 | 100.1 |
| cand | 7 | 1078 | 17.34 | 6.06 | 7 of 7 | 9,4,7,7,5,7,6 | 33.2 | 50.1 | 83.4 | 100.1 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927184622:leg, 1280px, window end** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 10.02 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 388 | 30.92 | 9.69 | 7 of 7 | 11,13,14,13,13,10,12 | 33.3 | 83.4 | 116.8 | 133.3 |
| base | 7 | 375 | 37.86 | 10.02 | 7 of 7 | 14,12,12,11,11,12,13 | 33.3 | 83.4 | 100.1 | 133.3 |
| aa | 7 | 386 | 35.75 | 3.98 | 7 of 7 | 14,13,12,14,12,15,12 | 33.3 | 83.4 | 100.1 | 133.4 |
| cand | 7 | 402 | 34.32 | 9.65 | 7 of 7 | 9,9,11,11,9,10,10 | 33.3 | 83.3 | 100.0 | 150.0 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 6.94 | 10.02 |
| 1280 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -3.54 | 10.02 |
| 1280 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 3.40 | 10.02 |
| 1280 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.67 | 7.94 |
| 1280 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -1.91 | 7.94 |
| 1280 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -2.58 | 7.94 |

Samples: 39927184622:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39927184622:leg | 1280 | hero | orig | 7 | 49 | 83.3 | 840 | 7 |
| 39927184622:leg | 1280 | hero | base | 7 | 54 | 83.2 | 798 | 7 |
| 39927184622:leg | 1280 | hero | aa | 7 | 47 | 83.3 | 840 | 7 |
| 39927184622:leg | 1280 | hero | cand | 7 | 45 | 83.3 | 840 | 7 |
| 39927184622:leg | 1280 | end | orig | 7 | 86 | 66.7 | 8269 | 7 |
| 39927184622:leg | 1280 | end | base | 7 | 85 | 66.7 | 8269 | 7 |
| 39927184622:leg | 1280 | end | aa | 7 | 92 | 66.7 | 8269 | 7 |
| 39927184622:leg | 1280 | end | cand | 7 | 69 | 66.7 | 8269 | 7 |
