Cells: median [min-max] over the visits of the arm. p95, p99 and max are frame intervals in ms inside the push spans; over50 is frames over 50 ms;
style, layout, paint and rAF are Timeline records between each push and its morph end (RecalculateStyles, Layout, Paint, FireAnimationFrame), summed over the 10 pushes of a visit.
Label: the Lean rule `pushLabel` against the base (better, worse, same, unresolved); unresolved when either side has fewer than 3 visits.

| arm | n | p95 | p99 | max | over50 | RecalculateStyles | Layout | Paint | FireAnimationFrame | label |
|---|---|---|---|---|---|---|---|---|---|---|
| base | 4 | 61.0 [55.0-67.0] | 98.0 [67.0-105.0] | 127.0 [78.0-297.0] | 47 [38-60] | 1249 [1057-1265] | 1047 [888-1069] | 12716 [9600-13104] | 264 [194-275] | base |
| cols-off | 4 | 67.0 [52.0-77.0] | 84.0 [64.0-98.0] | 382.0 [83.0-734.0] | 52 [32-57] | 1222 [976-1275] | 1021 [852-1072] | 11751 [10355-13053] | 259 [181-290] | same |
| flip | 4 | 70.0 [68.0-88.0] | 106.0 [99.0-124.0] | 119.0 [115.0-151.0] | 54 [51-87] | 1143 [993-1180] | 890 [797-909] | 4700 [4211-4724] | 121 [95-139] | better |
| flip+cols-off | 4 | 67.0 [63.0-73.0] | 127.0 [83.0-134.0] | 202.0 [97.0-324.0] | 53 [44-56] | 1144 [866-1207] | 898 [733-927] | 4703 [3805-4713] | 109 [30-136] | better |

### Lean cell verdicts against the base

| arm | p95 | p99 | max | over50 | RecalculateStyles | Layout | Paint | FireAnimationFrame |
|---|---|---|---|---|---|---|---|---|
| cols-off | same | same | same | same | same | same | same | same |
| flip | same | same | same | same | same | same | beats | same |
| flip+cols-off | same | same | same | same | same | same | beats | same |

### Pair contrasts (arm with the pictures hidden against its reference; beats = hiding lowers the value)

| reference | arm | n | label | p95 | p99 | max | over50 | RecalculateStyles | Layout | Paint | FireAnimationFrame |
|---|---|---|---|---|---|---|---|---|---|---|---|
| base | cols-off | 4/4 | same | same (overlap) | same (overlap) | same (overlap) | same (overlap) | same (overlap) | same (overlap) | same (overlap) | same (overlap) |
| base spread | | | | 12.0 | 38.0 | 219.0 | 22 | 208 | 181 | 3504 | 81 |
| flip | flip+cols-off | 4/4 | same | same (overlap) | same (overlap) | same (overlap) | same (overlap) | same (overlap) | same (overlap) | same (overlap) | same (overlap) |
| flip spread | | | | 20.0 | 25.0 | 36.0 | 36 | 187 | 112 | 513 | 44 |

### Take share (driver trace window.__fwTakeTrace; base arms have no trace)

| arm | visits | frames lane: driver pushes | taken | touches | touches with a take | counts lane: driver pushes | taken | touches | touches with a take |
|---|---|---|---|---|---|---|---|---|---|
| base | 4 | 0 | 0 | 40 | 0 | 0 | 0 | 40 | 0 |
| cols-off | 4 | 0 | 0 | 40 | 0 | 0 | 0 | 40 | 0 |
| flip | 4 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 40 |
| flip+cols-off | 4 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 40 |

### Median over the arms by position in the round

| position | n | p95 | p99 | max | over50 | RecalculateStyles | Layout | Paint | FireAnimationFrame |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 4 | 68.0 [61.0-77.0] | 98.0 [83.0-102.0] | 297.0 [97.0-382.0] | 54 [43-57] | 1057 [866-1131] | 888 [733-888] | 9600 [3805-10355] | 181 [30-194] |
| 1 | 4 | 69.0 [56.0-73.0] | 106.0 [67.0-134.0] | 202.0 [78.0-734.0] | 52 [47-56] | 1207 [1036-1265] | 927 [908-1069] | 11751 [4703-13104] | 194 [136-275] |
| 2 | 4 | 67.0 [52.0-70.0] | 91.0 [68.0-99.0] | 115.0 [80.0-117.0] | 52 [32-53] | 1249 [1143-1275] | 1047 [890-1072] | 11889 [4617-13053] | 264 [104-290] |
| 3 | 4 | 67.0 [56.0-88.0] | 124.0 [64.0-127.0] | 151.0 [83.0-324.0] | 60 [40-87] | 1187 [993-1222] | 1018 [797-1021] | 11696 [4211-12716] | 197 [95-259] |

### Median over the arms by round

| round | n | p95 | p99 | max | over50 | RecalculateStyles | Layout | Paint | FireAnimationFrame |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 4 | 67.0 [61.0-88.0] | 98.0 [84.0-124.0] | 297.0 [117.0-734.0] | 53 [43-87] | 1057 [993-1144] | 898 [797-908] | 9600 [4211-11751] | 194 [95-194] |
| 1 | 4 | 69.0 [55.0-77.0] | 106.0 [69.0-127.0] | 324.0 [80.0-382.0] | 51 [38-57] | 1180 [976-1249] | 909 [852-1047] | 10355 [4713-11889] | 181 [109-264] |
| 2 | 4 | 68.0 [52.0-73.0] | 105.0 [68.0-134.0] | 127.0 [86.0-202.0] | 56 [32-60] | 1207 [1131-1275] | 1018 [888-1072] | 12716 [4700-13053] | 197 [110-290] |
| 3 | 4 | 63.0 [56.0-70.0] | 83.0 [64.0-99.0] | 97.0 [78.0-115.0] | 47 [40-52] | 1222 [866-1265] | 1021 [733-1069] | 11696 [3805-13104] | 259 [30-275] |

### Visits

| visit | arm | round | position | seconds | pushes | nav | max morph (per mille) | p95 | p99 | max | over50 | RecalculateStyles | Layout | Paint | FireAnimationFrame |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | base | 0 | 0 | 146 | 10 | yes | 1000 | 61.0 | 98.0 | 297.0 | 43 | 1057 | 888 | 9600 | 194 |
| 1 | cols-off | 0 | 1 | 133 | 10 | yes | 1000 | 67.0 | 84.0 | 734.0 | 52 | 1036 | 908 | 11751 | 194 |
| 2 | flip+cols-off | 0 | 2 | 146 | 10 | yes | 1000 | 67.0 | 91.0 | 117.0 | 53 | 1144 | 898 | 4675 | 104 |
| 3 | flip | 0 | 3 | 129 | 10 | yes | 1000 | 88.0 | 124.0 | 151.0 | 87 | 993 | 797 | 4211 | 95 |
| 4 | cols-off | 1 | 0 | 132 | 10 | yes | 1000 | 77.0 | 98.0 | 382.0 | 57 | 976 | 852 | 10355 | 181 |
| 5 | flip | 1 | 1 | 144 | 10 | yes | 1000 | 69.0 | 106.0 | 116.0 | 51 | 1180 | 909 | 4724 | 139 |
| 6 | base | 1 | 2 | 127 | 10 | yes | 1000 | 55.0 | 69.0 | 80.0 | 38 | 1249 | 1047 | 11889 | 264 |
| 7 | flip+cols-off | 1 | 3 | 182 | 10 | yes | 1000 | 67.0 | 127.0 | 324.0 | 44 | 1136 | 898 | 4713 | 109 |
| 8 | flip | 2 | 0 | 124 | 10 | yes | 1000 | 68.0 | 102.0 | 119.0 | 54 | 1131 | 888 | 4700 | 110 |
| 9 | flip+cols-off | 2 | 1 | 127 | 10 | yes | 1000 | 73.0 | 134.0 | 202.0 | 56 | 1207 | 927 | 4703 | 136 |
| 10 | cols-off | 2 | 2 | 127 | 10 | yes | 1000 | 52.0 | 68.0 | 86.0 | 32 | 1275 | 1072 | 13053 | 290 |
| 11 | base | 2 | 3 | 127 | 10 | yes | 1000 | 67.0 | 105.0 | 127.0 | 60 | 1187 | 1018 | 12716 | 197 |
| 12 | flip+cols-off | 3 | 0 | 123 | 10 | yes | 1000 | 63.0 | 83.0 | 97.0 | 45 | 866 | 733 | 3805 | 30 |
| 13 | base | 3 | 1 | 126 | 10 | yes | 1000 | 56.0 | 67.0 | 78.0 | 47 | 1265 | 1069 | 13104 | 275 |
| 14 | flip | 3 | 2 | 126 | 10 | yes | 1000 | 70.0 | 99.0 | 115.0 | 52 | 1143 | 890 | 4617 | 121 |
| 15 | cols-off | 3 | 3 | 130 | 10 | yes | 1000 | 56.0 | 64.0 | 83.0 | 40 | 1222 | 1021 | 11696 | 259 |
