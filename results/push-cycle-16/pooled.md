# Push cycles on the Simulator (real touches), dwell 1000 ms, 6 cycles per pass

## rewrite: 7 usable of 10 passes, 7 jobs; excluded: touch driver timed out

| Cycle k | Passes | Frames | Slow >34 ms | Slow >50 ms | Median gap ms | Viewport changes | resize events | visualViewport resizes | Fights | Displaced |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 7 | 3306 | 1870 | 531 | 36 | 14 | 44 | 82 | 13 | 45 |
| 1 | 7 | 3161 | 1566 | 432 | 36 | 14 | 49 | 85 | 18 | 79 |
| 2 | 7 | 2680 | 1729 | 718 | 39 | 18 | 37 | 64 | 22 | 60 |
| 3 | 7 | 2643 | 2380 | 1187 | 51 | 16 | 37 | 62 | 24 | 278 |
| 4 | 7 | 3297 | 3120 | 1964 | 58 | 16 | 22 | 39 | 14 | 157 |
| 5 | 7 | 3954 | 3684 | 2569 | 56 | 19 | 23 | 43 | 24 | 381 |
| 6 | 7 | 2344 | 2304 | 1418 | 56 | 20 | 30 | 54 | 15 | 246 |
| 7 | 7 | 5056 | 4614 | 3418 | 63 | 22 | 32 | 57 | 17 | 190 |
| 8 | 7 | 1751 | 1732 | 1300 | 73 | 15 | 26 | 42 | 12 | 94 |
| 9 | 7 | 1812 | 1790 | 1266 | 63 | 16 | 33 | 51 | 12 | 67 |
| 10 | 7 | 2147 | 2111 | 1419 | 64 | 17 | 32 | 55 | 14 | 81 |
| 11 | 7 | 2315 | 2274 | 1459 | 59 | 15 | 30 | 51 | 12 | 45 |
| 12 | 7 | 1604 | 1579 | 1080 | 70 | 17 | 27 | 49 | 10 | 88 |
| 13 | 7 | 2309 | 2273 | 1601 | 68 | 17 | 32 | 56 | 16 | 105 |
| 14 | 7 | 1836 | 1743 | 1180 | 89 | 17 | 32 | 53 | 6 | 52 |
| 15 | 7 | 1114 | 1095 | 933 | 84 | 8 | 6 | 10 | 14 | 160 |

Trend of slow frames over the cycle index: >34 ms rises, >50 ms rises (the Lean model never rises).
H1 (slow frames near a viewport change): >34 ms refuted, >50 ms refuted; inputs {"changes":261,"slowNear":1728,"framesNear":1880,"slowFar":34136,"framesFar":39337}.
H2 (fights per open, later against first): holds; inputs {"stretchesFirst":7,"fightsFirst":13,"stretchesLater":105,"fightsLater":230}.

## user: 7 usable of 11 passes, 7 jobs; excluded: touch driver timed out

| Cycle k | Passes | Frames | Slow >34 ms | Slow >50 ms | Median gap ms | Viewport changes | resize events | visualViewport resizes | Fights | Displaced |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 7 | 4410 | 2753 | 739 | 34 | 14 | 49 | 122 | 29 | 144 |
| 1 | 7 | 3250 | 1726 | 508 | 36 | 14 | 48 | 121 | 39 | 140 |
| 2 | 7 | 3130 | 2026 | 738 | 36 | 15 | 41 | 102 | 27 | 88 |
| 3 | 7 | 3185 | 2750 | 1781 | 49 | 14 | 34 | 74 | 27 | 157 |
| 4 | 7 | 2341 | 2304 | 1319 | 55 | 14 | 26 | 46 | 15 | 52 |
| 5 | 7 | 2937 | 2892 | 1896 | 61 | 15 | 28 | 50 | 18 | 63 |
| 6 | 7 | 1974 | 1717 | 1050 | 59 | 14 | 33 | 62 | 16 | 54 |
| 7 | 7 | 3103 | 2593 | 1539 | 53 | 16 | 27 | 53 | 15 | 61 |
| 8 | 7 | 5919 | 4555 | 1585 | 52 | 15 | 45 | 82 | 18 | 216 |
| 9 | 7 | 4112 | 3805 | 1603 | 52 | 14 | 40 | 78 | 18 | 54 |
| 10 | 7 | 1913 | 1828 | 1183 | 54 | 17 | 32 | 64 | 18 | 45 |
| 11 | 7 | 1631 | 1546 | 1089 | 60 | 16 | 34 | 59 | 17 | 49 |
| 12 | 7 | 1977 | 1718 | 1071 | 52 | 14 | 37 | 72 | 18 | 52 |
| 13 | 7 | 2210 | 2119 | 1423 | 54 | 15 | 26 | 49 | 20 | 58 |
| 14 | 7 | 5359 | 5201 | 3425 | 54 | 11 | 22 | 36 | 18 | 95 |
| 15 | 6 | 1994 | 1957 | 1423 | 56 | 4 | 2 | 11 | 14 | 79 |

Trend of slow frames over the cycle index: >34 ms flat, >50 ms rises (the Lean model never rises).
H1 (slow frames near a viewport change): >34 ms refuted, >50 ms refuted; inputs {"changes":222,"slowNear":1754,"framesNear":1953,"slowFar":39736,"framesFar":47381}.
H2 (fights per open, later against first): refuted; inputs {"stretchesFirst":7,"fightsFirst":29,"stretchesLater":104,"fightsLater":298}.

## rewrite@dwell: 6 usable of 8 passes, 6 jobs; excluded: touch driver failed

| Cycle k | Passes | Frames | Slow >34 ms | Slow >50 ms | Median gap ms | Viewport changes | resize events | visualViewport resizes | Fights | Displaced |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 6 | 6794 | 2782 | 1199 | 51 | 16 | 20 | 46 | 8 | 25 |
| 1 | 6 | 5250 | 2755 | 1623 | 57 | 17 | 20 | 41 | 9 | 112 |
| 2 | 6 | 6046 | 4092 | 3071 | 56 | 16 | 19 | 33 | 16 | 155 |
| 3 | 6 | 8238 | 3688 | 2107 | 79 | 17 | 28 | 43 | 8 | 63 |
| 4 | 6 | 9126 | 3266 | 2846 | 71 | 15 | 11 | 28 | 10 | 89 |
| 5 | 6 | 735 | 717 | 569 | 107 | 5 | 6 | 7 | 5 | 29 |

Trend of slow frames over the cycle index: >34 ms flat, >50 ms rises (the Lean model never rises).
H1 (slow frames near a viewport change): >34 ms refuted, >50 ms refuted; inputs {"changes":86,"slowNear":422,"framesNear":440,"slowFar":16878,"framesFar":19540}.
H2 (fights per open, later against first): holds; inputs {"stretchesFirst":6,"fightsFirst":8,"stretchesLater":30,"fightsLater":48}.

## user@dwell: 8 usable of 8 passes, 8 jobs

| Cycle k | Passes | Frames | Slow >34 ms | Slow >50 ms | Median gap ms | Viewport changes | resize events | visualViewport resizes | Fights | Displaced |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 8 | 12474 | 3110 | 772 | 33 | 18 | 32 | 107 | 36 | 101 |
| 1 | 8 | 7869 | 2273 | 1105 | 38 | 17 | 27 | 78 | 26 | 211 |
| 2 | 8 | 6830 | 2107 | 1261 | 60 | 20 | 29 | 65 | 28 | 161 |
| 3 | 8 | 10003 | 3142 | 1508 | 50 | 16 | 28 | 63 | 24 | 144 |
| 4 | 8 | 7379 | 2461 | 967 | 41 | 23 | 25 | 75 | 17 | 81 |
| 5 | 8 | 1890 | 1381 | 786 | 63 | 9 | 9 | 24 | 25 | 136 |

Trend of slow frames over the cycle index: >34 ms falls, >50 ms rises (the Lean model never rises).
H1 (slow frames near a viewport change): >34 ms refuted, >50 ms refuted; inputs {"changes":103,"slowNear":586,"framesNear":748,"slowFar":13888,"framesFar":21738}.
H2 (fights per open, later against first): refuted; inputs {"stretchesFirst":8,"fightsFirst":36,"stretchesLater":40,"fightsLater":120}.


## Cycle versus clock (Lean Fw.Measure.PushCycle.sepVerdict; slow frames > 50 ms per cycle, cycles 3 to 5, counted window = open stretch + 8 s)

| Arm | Full passes | Dwell passes | Period full ms | Period dwell ms | Stretch r (permille) | Within bound | Rate by cycle index | Rate by clock-matched index | Rate of dwell passes | Verdict (> 50 ms) | Verdict (> 34 ms) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| rewrite | 7 | 6 | 24525 | 80677 | 3289 | no | 145000 | 150357 | 140777 | undecided:noRoom | undecided:noRoom |
| user | 7 | 8 | 25100 | 53599 | 2135 | yes | 167142 | 145523 | 85666 | undecided:inseparable | undecided:inseparable |

Full pass 16 cycles and stretch bound 2988 permille (Lean sepFullCycles, sepStretchBound): within the bound the clock-matched window fits (Lean sep_fits).

Minimum 3 usable passes per side; a side below it is undecided, never a win. Lost passes: rewrite full [p1 job 2 not run (the job ended first); p1 job 4 touch driver timed out (failed:restartFailed); p1 job 5 touch driver timed out (failed:touchesFailed); p1 job 6 failed pass (failed:restartFailed); p2 job 6 touch driver timed out (failed:touchesFailed)] dwell [p1 job 2 not run (the job ended first); p1 job 6 touch driver failed (failed:restartFailed); p2 job 1 failed pass (failed:restartFailed); p2 job 2 failed pass (failed:restartFailed); p2 job 3 touch driver failed (failed:restartFailed); p2 job 4 not run (the job ended first)], user full [p1 job 3 touch driver timed out (failed:restartFailed); p2 job 1 failed pass (failed:restartFailed); p2 job 3 touch driver timed out (failed:touchesFailed); p2 job 4 touch driver timed out (failed:restartFailed); p2 job 5 touch driver timed out (failed:restartFailed)] dwell [p1 job 5 not run (the job ended first); p2 job 1 not run (the job ended first); p2 job 3 not run (the job ended first); p2 job 4 failed pass (failed:notReady)].

### Census after each cycle of the dwell passes (H4: does memory grow per cycle)

| Arm | Layers | Backing bytes | Layers created | Trend per dwell pass: layers / bytes / created | Mean bytes after (full pass) | Mean bytes after (dwell pass) |
|---|---|---|---|---|---|---|
| rewrite | no | no | no | flat,flat,flat,flat,flat,flat / flat,flat,flat,flat,flat,flat / flat,flat,flat,flat,flat,flat | 122247520 | 118666073 |
| user | no | no | no | flat,flat,flat,flat,flat,flat,flat,flat / flat,flat,flat,flat,flat,flat,flat,flat / flat,flat,flat,flat,flat,flat,falls,flat | 104833147 | 105366908 |

Reading: yes = every dwell pass rises (first cycle below the mean of the rest), no = none rises, mixed = some, few = under 3 passes (Lean `across`).

