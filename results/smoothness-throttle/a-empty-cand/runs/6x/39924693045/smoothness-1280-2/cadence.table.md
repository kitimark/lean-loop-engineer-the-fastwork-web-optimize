Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39924693045:leg, 1280px, window hero** (CPU throttle 6x, candidate default, A/A spread 4.98 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1078 | 22.91 | 4.41 | 7 of 7 | 12,8,7,13,12,10,12 | 33.3 | 66.7 | 83.4 | 116.7 |
| base | 7 | 1087 | 24.47 | 4.98 | 7 of 7 | 10,8,9,7,8,8,9 | 33.3 | 66.6 | 83.4 | 116.7 |
| aa | 7 | 1087 | 23.55 | 4.87 | 7 of 7 | 8,9,8,10,9,10,8 | 33.3 | 66.6 | 83.4 | 116.7 |
| cand | 7 | 1086 | 23.29 | 4.67 | 7 of 7 | 11,10,8,10,9,8,8 | 33.3 | 66.7 | 99.9 | 116.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924693045:leg, 1280px, window end** (CPU throttle 6x, candidate default, A/A spread 14.54 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 346 | 37.86 | 13.23 | 7 of 7 | 12,13,13,14,14,13,11 | 33.3 | 100.0 | 133.3 | 150.1 |
| base | 7 | 327 | 46.78 | 14.54 | 7 of 7 | 14,14,15,18,15,15,16 | 33.4 | 100.0 | 116.6 | 133.4 |
| aa | 7 | 335 | 42.38 | 8.93 | 7 of 7 | 16,17,16,13,13,14,16 | 33.4 | 100.0 | 133.3 | 150.0 |
| cand | 7 | 325 | 46.76 | 12.34 | 7 of 7 | 15,16,14,15,13,16,17 | 33.4 | 100.0 | 116.7 | 166.6 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 8.92 | 14.54 |
| 1280 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -0.02 | 14.54 |
| 1280 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 8.90 | 14.54 |
| 1280 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 1.56 | 4.98 |
| 1280 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -1.18 | 4.98 |
| 1280 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.38 | 4.98 |

Samples: 39924693045:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39924693045:leg | 1280 | hero | orig | 7 | 74 | 83.2 | 840 | 7 |
| 39924693045:leg | 1280 | hero | base | 7 | 59 | 83.3 | 840 | 7 |
| 39924693045:leg | 1280 | hero | aa | 7 | 62 | 83.3 | 840 | 7 |
| 39924693045:leg | 1280 | hero | cand | 7 | 64 | 83.3 | 840 | 7 |
| 39924693045:leg | 1280 | end | orig | 7 | 90 | 83.3 | 8269 | 7 |
| 39924693045:leg | 1280 | end | base | 7 | 107 | 66.8 | 8269 | 7 |
| 39924693045:leg | 1280 | end | aa | 7 | 105 | 83.2 | 8269 | 7 |
| 39924693045:leg | 1280 | end | cand | 7 | 106 | 66.8 | 8269 | 7 |
