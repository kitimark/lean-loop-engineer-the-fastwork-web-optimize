Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39927184622:leg, 1280px, window hero** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 6.58 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1075 | 25.48 | 7.74 | 7 of 7 | 17,11,13,11,13,7,15 | 33.3 | 66.7 | 99.9 | 133.4 |
| base | 7 | 1081 | 27.10 | 6.58 | 7 of 7 | 10,9,10,9,7,8,12 | 33.3 | 66.7 | 100.0 | 116.7 |
| aa | 7 | 1080 | 25.83 | 4.39 | 7 of 7 | 9,8,10,11,7,10,10 | 33.3 | 66.6 | 99.9 | 150.0 |
| cand | 7 | 1086 | 25.87 | 5.49 | 7 of 7 | 9,8,11,10,9,9,8 | 33.3 | 66.6 | 100.0 | 150.1 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927184622:leg, 1280px, window end** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 11.80 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 324 | 42.59 | 15.07 | 7 of 7 | 15,14,15,16,13,15,13 | 33.4 | 100.0 | 116.7 | 133.3 |
| base | 7 | 317 | 47.94 | 11.80 | 7 of 7 | 18,15,17,14,16,17,17 | 33.4 | 100.0 | 133.2 | 149.9 |
| aa | 7 | 302 | 51.32 | 9.43 | 7 of 7 | 15,16,16,16,16,18,15 | 49.9 | 100.0 | 116.7 | 133.3 |
| cand | 7 | 325 | 46.76 | 10.37 | 7 of 7 | 16,15,15,15,12,17,14 | 33.4 | 100.0 | 133.2 | 150.1 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 5.35 | 11.80 |
| 1280 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -1.18 | 11.80 |
| 1280 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 4.17 | 11.80 |
| 1280 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 1.62 | 6.58 |
| 1280 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -1.23 | 6.58 |
| 1280 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.39 | 6.58 |

Samples: 39927184622:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39927184622:leg | 1280 | hero | orig | 7 | 87 | 66.7 | 756 | 7 |
| 39927184622:leg | 1280 | hero | base | 7 | 65 | 83.3 | 840 | 7 |
| 39927184622:leg | 1280 | hero | aa | 7 | 65 | 83.3 | 798 | 7 |
| 39927184622:leg | 1280 | hero | cand | 7 | 64 | 83.3 | 840 | 7 |
| 39927184622:leg | 1280 | end | orig | 7 | 101 | 83.3 | 8269 | 7 |
| 39927184622:leg | 1280 | end | base | 7 | 114 | 66.8 | 8269 | 7 |
| 39927184622:leg | 1280 | end | aa | 7 | 112 | 83.3 | 8269 | 7 |
| 39927184622:leg | 1280 | end | cand | 7 | 104 | 66.7 | 8269 | 7 |
