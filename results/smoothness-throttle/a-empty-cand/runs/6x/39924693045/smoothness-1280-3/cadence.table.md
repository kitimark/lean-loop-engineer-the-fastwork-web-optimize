Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39924693045:leg, 1280px, window hero** (CPU throttle 6x, candidate default, A/A spread 4.96 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1068 | 29.58 | 4.69 | 7 of 7 | 24,17,26,21,24,24,17 | 33.3 | 66.7 | 100.0 | 133.4 |
| base | 7 | 1072 | 29.47 | 3.24 | 7 of 7 | 10,12,9,9,11,8,13 | 33.3 | 66.7 | 83.4 | 133.4 |
| aa | 7 | 1070 | 29.71 | 4.96 | 7 of 7 | 14,15,11,10,12,8,11 | 33.3 | 66.7 | 83.4 | 150.0 |
| cand | 7 | 1069 | 29.56 | 5.85 | 7 of 7 | 8,11,14,13,11,11,12 | 33.3 | 66.7 | 99.9 | 166.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: second; base vs cand: same; orig vs cand: second

**run 39924693045:leg, 1280px, window end** (CPU throttle 6x, candidate default, A/A spread 9.91 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 311 | 47.26 | 14.91 | 7 of 7 | 16,15,16,15,16,16,13 | 33.4 | 100.0 | 116.7 | 133.3 |
| base | 7 | 293 | 55.29 | 7.86 | 7 of 7 | 17,16,16,13,16,16,16 | 50.0 | 116.6 | 133.3 | 183.3 |
| aa | 7 | 312 | 53.84 | 9.91 | 7 of 7 | 17,16,13,16,16,14,14 | 50.0 | 100.0 | 133.4 | 149.9 |
| cand | 7 | 307 | 50.81 | 12.32 | 7 of 7 | 15,17,17,16,15,14,18 | 49.9 | 100.1 | 133.3 | 133.4 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 8.03 | 9.91 |
| 1280 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -4.48 | 9.91 |
| 1280 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 3.55 | 9.91 |
| 1280 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 1 / 0 / 0 | insufficient | -0.11 | 4.96 |
| 1280 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.09 | 4.96 |
| 1280 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 1 / 0 / 0 | insufficient | -0.02 | 4.96 |

Samples: 39924693045:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39924693045:leg | 1280 | hero | orig | 7 | 153 | 66.7 | 630 | 7 |
| 39924693045:leg | 1280 | hero | base | 7 | 72 | 83.3 | 840 | 7 |
| 39924693045:leg | 1280 | hero | aa | 7 | 81 | 83.3 | 798 | 7 |
| 39924693045:leg | 1280 | hero | cand | 7 | 80 | 83.3 | 798 | 7 |
| 39924693045:leg | 1280 | end | orig | 7 | 107 | 83.3 | 8269 | 7 |
| 39924693045:leg | 1280 | end | base | 7 | 110 | 83.3 | 8269 | 7 |
| 39924693045:leg | 1280 | end | aa | 7 | 106 | 66.8 | 8269 | 7 |
| 39924693045:leg | 1280 | end | cand | 7 | 112 | 83.3 | 8269 | 7 |
