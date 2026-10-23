Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39927184622:leg, 1280px, window hero** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 5.99 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1079 | 22.15 | 5.19 | 7 of 7 | 10,9,9,10,10,10,16 | 33.3 | 66.7 | 99.9 | 200.0 |
| base | 7 | 1084 | 24.72 | 1.93 | 7 of 7 | 12,10,8,9,11,8,9 | 33.3 | 66.7 | 83.4 | 116.7 |
| aa | 7 | 1087 | 25.02 | 5.99 | 7 of 7 | 9,12,9,8,12,6,8 | 33.3 | 66.7 | 83.4 | 200.0 |
| cand | 7 | 1088 | 25.27 | 2.57 | 7 of 7 | 8,9,9,9,11,10,9 | 33.3 | 66.7 | 83.4 | 116.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39927184622:leg, 1280px, window end** (CPU throttle 6x, candidate ?fw=morph.tween:scroll-lock,nav:earn-no-transition, A/A spread 7.45 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 331 | 41.08 | 8.44 | 7 of 7 | 15,14,14,14,14,14,12 | 33.4 | 100.0 | 133.2 | 150.0 |
| base | 7 | 318 | 47.48 | 7.45 | 7 of 7 | 13,17,18,15,15,17,16 | 33.4 | 100.0 | 133.3 | 150.1 |
| aa | 7 | 319 | 46.08 | 7.07 | 7 of 7 | 15,18,18,16,16,14,18 | 33.4 | 100.0 | 133.4 | 150.0 |
| cand | 7 | 346 | 43.35 | 6.38 | 7 of 7 | 13,16,13,13,14,10,13 | 33.4 | 99.9 | 116.7 | 166.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 6.40 | 7.45 |
| 1280 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -4.13 | 7.45 |
| 1280 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 2.27 | 7.45 |
| 1280 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 2.57 | 5.99 |
| 1280 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.55 | 5.99 |
| 1280 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 3.12 | 5.99 |

Samples: 39927184622:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39927184622:leg | 1280 | hero | orig | 7 | 74 | 83.3 | 798 | 7 |
| 39927184622:leg | 1280 | hero | base | 7 | 67 | 83.3 | 840 | 7 |
| 39927184622:leg | 1280 | hero | aa | 7 | 64 | 83.3 | 798 | 7 |
| 39927184622:leg | 1280 | hero | cand | 7 | 65 | 83.3 | 840 | 7 |
| 39927184622:leg | 1280 | end | orig | 7 | 97 | 83.3 | 8269 | 7 |
| 39927184622:leg | 1280 | end | base | 7 | 111 | 66.8 | 8269 | 7 |
| 39927184622:leg | 1280 | end | aa | 7 | 115 | 66.8 | 8269 | 7 |
| 39927184622:leg | 1280 | end | cand | 7 | 92 | 66.8 | 8269 | 7 |
