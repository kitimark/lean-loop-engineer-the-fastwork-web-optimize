Cells: median [min-max] over the visits of the arm. p95, p99 and max are frame intervals in ms inside the push spans; over50 is frames over 50 ms;
style, layout, paint and rAF are Timeline records between each push and its morph end (RecalculateStyles, Layout, Paint, FireAnimationFrame), summed over the 10 pushes of a visit.
Label: the Lean rule `pushLabel` against the base (better, worse, same, unresolved); unresolved when either side has fewer than 3 visits.

| arm | n | p95 | p99 | max | over50 | RecalculateStyles | Layout | Paint | FireAnimationFrame | label |
|---|---|---|---|---|---|---|---|---|---|---|
| base | 3 | 71.0 [68.0-75.0] | 103.0 [97.0-112.0] | 368.0 [333.0-371.0] | 56 [54-63] | 898 [860-964] | 777 [767-841] | 9058 [8650-10207] | 148 [131-182] | base |
| morph.geom:on | 3 | 55.0 [54.0-65.0] | 89.0 [80.0-97.0] | 108.0 [102.0-141.0] | 70 [68-86] | 1854 [1682-1893] | 1249 [1163-1277] | 8242 [7519-8317] | 223 [173-237] | mixed |
| morph.tween:geom-timed | 3 | 76.0 [71.0-77.0] | 109.0 [107.0-145.0] | 140.0 [132.0-166.0] | 67 [63-82] | 1120 [1014-1676] | 920 [801-1203] | 8659 [7694-9643] | 155 [115-161] | better |
| morph.stage:on | 3 | 86.0 [66.0-95.0] | 121.0 [90.0-141.0] | 980.0 [109.0-1145.0] | 175 [135-185] | 2435 [2316-2868] | 1662 [1562-1871] | 21597 [19966-27629] | 332 [321-481] | worse |

### Visits

| visit | arm | seconds | pushes | nav | max morph (per mille) | p95 | p99 | max | over50 | RecalculateStyles | Layout | Paint | FireAnimationFrame |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | base | 141 | 10 | yes | 1000 | 75.0 | 112.0 | 371.0 | 63 | 860 | 767 | 8650 | 148 |
| 1 | morph.geom:on | 163 | 10 | yes | 1000 | 65.0 | 97.0 | 141.0 | 86 | 1682 | 1163 | 7519 | 173 |
| 2 | morph.tween:geom-timed | 129 | 10 | yes | 1000 | 71.0 | 145.0 | 166.0 | 82 | 1676 | 1203 | 9643 | 115 |
| 3 | morph.stage:on | 215 | 10 | yes | 0 | 95.0 | 141.0 | 980.0 | 185 | 2316 | 1562 | 19966 | 321 |
| 4 | base | 131 | 10 | yes | 1000 | 68.0 | 103.0 | 333.0 | 54 | 898 | 777 | 9058 | 131 |
| 5 | morph.geom:on | 129 | 10 | yes | 1000 | 54.0 | 80.0 | 102.0 | 68 | 1893 | 1277 | 8317 | 237 |
| 6 | morph.tween:geom-timed | 130 | 10 | yes | 1000 | 76.0 | 107.0 | 132.0 | 67 | 1120 | 920 | 8659 | 155 |
| 7 | morph.stage:on | 157 | 10 | yes | 0 | 86.0 | 121.0 | 1145.0 | 175 | 2435 | 1662 | 21597 | 332 |
| 8 | base | 131 | 10 | yes | 1000 | 71.0 | 97.0 | 368.0 | 56 | 964 | 841 | 10207 | 182 |
| 9 | morph.geom:on | 129 | 10 | yes | 1000 | 55.0 | 89.0 | 108.0 | 70 | 1854 | 1249 | 8242 | 223 |
| 10 | morph.tween:geom-timed | 132 | 10 | yes | 1000 | 77.0 | 109.0 | 140.0 | 63 | 1014 | 801 | 7694 | 161 |
| 11 | morph.stage:on | 150 | 10 | yes | 0 | 66.0 | 90.0 | 109.0 | 135 | 2868 | 1871 | 27629 | 481 |
