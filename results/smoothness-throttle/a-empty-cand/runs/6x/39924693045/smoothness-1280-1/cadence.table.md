Bad frame = a gap between rAF callbacks above 34 ms. Rate = bad frames per frame, pooled over the repeats of an arm (percent). Hitch = a gap over 60 ms.

Verdicts (rate rule `Fw.Gate.Smooth.verdict`, hitch rule `hitchVerdict`) are main-thread rAF cadence. The compositor frame counts further down come from the trace of the page's own frame sink and are reported beside them; they never enter a verdict.

### Per run

**run 39924693045:leg, 1280px, window hero** (CPU throttle 6x, candidate default, A/A spread 4.84 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 1079 | 24.37 | 7.65 | 7 of 7 | 12,14,12,14,14,13,9 | 33.3 | 66.7 | 83.4 | 149.9 |
| base | 7 | 1093 | 25.70 | 3.85 | 7 of 7 | 9,9,9,10,7,7,8 | 33.3 | 66.6 | 83.4 | 133.3 |
| aa | 7 | 1090 | 25.41 | 4.84 | 7 of 7 | 8,8,10,9,9,11,9 | 33.3 | 66.6 | 83.4 | 133.3 |
| cand | 7 | 1093 | 24.42 | 3.68 | 7 of 7 | 8,12,9,11,10,7,11 | 33.3 | 66.7 | 83.4 | 116.7 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

**run 39924693045:leg, 1280px, window end** (CPU throttle 6x, candidate default, A/A spread 15.00 points)

| arm | reps | frames | bad-frame rate % | range of reps (points) | reps with a hitch | hitches per rep | p50 ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 7 | 345 | 37.97 | 7.05 | 7 of 7 | 13,14,14,14,14,15,14 | 33.3 | 100.0 | 133.3 | 149.9 |
| base | 7 | 320 | 46.87 | 15.00 | 7 of 7 | 16,17,14,17,15,14,17 | 33.4 | 100.0 | 133.3 | 133.4 |
| aa | 7 | 319 | 48.90 | 7.59 | 7 of 7 | 15,18,12,17,14,16,17 | 33.4 | 100.0 | 116.6 | 133.3 |
| cand | 7 | 317 | 47.63 | 10.35 | 7 of 7 | 14,14,15,18,19,18,16 | 33.4 | 100.0 | 133.4 | 150.1 |

Rate verdicts: orig vs base: same; base vs cand: same; orig vs cand: same
Hitch verdicts: orig vs base: same; base vs cand: same; orig vs cand: same

### Across samples (one CI job is one sample; Lean `acrossDecisive`: two thirds of the decisive samples, none disagreeing)

| width | window | first | second | samples n | need rate / hitch | rate rule: first / second / same / insufficient | rate: across | hitch rule: first / second / same / insufficient | hitch: across | median rate difference second-first (points) | median A/A spread (points) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280 | end | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 8.90 | 15.00 |
| 1280 | end | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.76 | 15.00 |
| 1280 | end | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 9.66 | 15.00 |
| 1280 | hero | orig | base | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 1.33 | 4.84 |
| 1280 | hero | base | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | -1.28 | 4.84 |
| 1280 | hero | orig | cand | 1 | 1 / 1 | 0 / 0 / 1 / 0 | insufficient | 0 / 0 / 1 / 0 | insufficient | 0.05 | 4.84 |

Samples: 39924693045:leg

### Hitches (gaps over 60 ms, placement; the verdict on the per-repeat counts is above)

| run | width | window | arm | reps | hitches | median gap ms | median scroll y px | reps with a long animation frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39924693045:leg | 1280 | hero | orig | 7 | 88 | 66.7 | 756 | 7 |
| 39924693045:leg | 1280 | hero | base | 7 | 59 | 83.3 | 840 | 7 |
| 39924693045:leg | 1280 | hero | aa | 7 | 64 | 83.3 | 840 | 7 |
| 39924693045:leg | 1280 | hero | cand | 7 | 68 | 83.3 | 840 | 7 |
| 39924693045:leg | 1280 | end | orig | 7 | 98 | 83.3 | 8269 | 7 |
| 39924693045:leg | 1280 | end | base | 7 | 110 | 66.7 | 8269 | 7 |
| 39924693045:leg | 1280 | end | aa | 7 | 109 | 83.3 | 8269 | 7 |
| 39924693045:leg | 1280 | end | cand | 7 | 114 | 66.7 | 8269 | 7 |
