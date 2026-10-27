# Push cycles on the Simulator (real touches), dwell 1000 ms, 6 cycles per pass

## rewrite: 5 usable of 6 passes, 5 jobs; excluded: touch driver timed out

| Cycle k | Passes | Frames | Slow >34 ms | Slow >50 ms | Median gap ms | Viewport changes | resize events | visualViewport resizes | Fights | Displaced |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 5 | 2585 | 1307 | 353 | 32 | 10 | 33 | 60 | 11 | 41 |
| 1 | 5 | 2326 | 1047 | 297 | 31 | 10 | 34 | 60 | 14 | 65 |
| 2 | 5 | 1777 | 1259 | 587 | 43 | 14 | 23 | 40 | 17 | 39 |
| 3 | 5 | 2169 | 1978 | 984 | 52 | 12 | 24 | 40 | 15 | 162 |
| 4 | 5 | 2472 | 2302 | 1286 | 53 | 11 | 19 | 32 | 10 | 140 |
| 5 | 5 | 1842 | 1593 | 1245 | 56 | 12 | 16 | 30 | 12 | 138 |
| 6 | 5 | 1368 | 1342 | 823 | 56 | 12 | 23 | 41 | 10 | 162 |
| 7 | 5 | 4170 | 3744 | 2812 | 63 | 16 | 19 | 36 | 7 | 71 |
| 8 | 5 | 1366 | 1352 | 1001 | 73 | 10 | 19 | 28 | 10 | 91 |
| 9 | 5 | 1325 | 1313 | 928 | 63 | 12 | 22 | 35 | 10 | 64 |
| 10 | 5 | 1685 | 1663 | 1097 | 64 | 12 | 25 | 41 | 10 | 64 |
| 11 | 5 | 1831 | 1806 | 1150 | 59 | 12 | 23 | 39 | 8 | 28 |
| 12 | 5 | 1279 | 1258 | 809 | 64 | 14 | 22 | 39 | 7 | 80 |
| 13 | 5 | 1793 | 1760 | 1172 | 65 | 11 | 22 | 37 | 11 | 68 |
| 14 | 5 | 1181 | 1098 | 762 | 93 | 12 | 26 | 42 | 5 | 50 |
| 15 | 5 | 847 | 830 | 672 | 85 | 5 | 3 | 7 | 11 | 70 |

Trend of slow frames over the cycle index: >34 ms rises, >50 ms rises (the Lean model never rises).
H1 (slow frames near a viewport change): >34 ms refuted, >50 ms refuted; inputs {"changes":185,"slowNear":1230,"framesNear":1357,"slowFar":24422,"framesFar":28579}.
H2 (fights per open, later against first): refuted; inputs {"stretchesFirst":5,"fightsFirst":11,"stretchesLater":75,"fightsLater":157}.

## user: 2 usable of 5 passes, 2 jobs; excluded: touch driver timed out

| Cycle k | Passes | Frames | Slow >34 ms | Slow >50 ms | Median gap ms | Viewport changes | resize events | visualViewport resizes | Fights | Displaced |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 2 | 848 | 510 | 172 | 48 | 4 | 13 | 33 | 9 | 79 |
| 1 | 2 | 900 | 509 | 164 | 44 | 4 | 12 | 31 | 14 | 68 |
| 2 | 2 | 823 | 560 | 214 | 46 | 4 | 12 | 28 | 4 | 27 |
| 3 | 2 | 436 | 429 | 263 | 78 | 4 | 10 | 19 | 6 | 11 |
| 4 | 2 | 980 | 966 | 495 | 70 | 4 | 10 | 19 | 4 | 13 |
| 5 | 2 | 691 | 667 | 432 | 67 | 5 | 10 | 20 | 5 | 11 |
| 6 | 2 | 436 | 332 | 188 | 86 | 4 | 10 | 20 | 6 | 22 |
| 7 | 2 | 1085 | 618 | 289 | 67 | 5 | 6 | 11 | 5 | 11 |
| 8 | 2 | 1170 | 1154 | 629 | 70 | 5 | 13 | 22 | 10 | 170 |
| 9 | 2 | 542 | 503 | 246 | 49 | 4 | 12 | 28 | 6 | 25 |
| 10 | 2 | 478 | 444 | 272 | 54 | 5 | 10 | 20 | 5 | 12 |
| 11 | 2 | 641 | 634 | 411 | 60 | 4 | 10 | 19 | 4 | 15 |
| 12 | 2 | 606 | 593 | 295 | 50 | 4 | 11 | 24 | 8 | 21 |
| 13 | 2 | 547 | 516 | 318 | 54 | 4 | 11 | 19 | 9 | 22 |
| 14 | 2 | 399 | 333 | 174 | 52 | 2 | 5 | 11 | 6 | 21 |
| 15 | 1 | 155 | 154 | 96 | 53 | 1 | 0 | 2 | 4 | 10 |

Trend of slow frames over the cycle index: >34 ms rises, >50 ms rises (the Lean model never rises).
H1 (slow frames near a viewport change): >34 ms refuted, >50 ms refuted; inputs {"changes":63,"slowNear":549,"framesNear":589,"slowFar":8373,"framesFar":10117}.
H2 (fights per open, later against first): refuted; inputs {"stretchesFirst":2,"fightsFirst":9,"stretchesLater":29,"fightsLater":96}.

## rewrite@dwell: 2 usable of 3 passes, 2 jobs; excluded: touch driver failed

| Cycle k | Passes | Frames | Slow >34 ms | Slow >50 ms | Median gap ms | Viewport changes | resize events | visualViewport resizes | Fights | Displaced |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 2 | 2485 | 655 | 314 | 57 | 6 | 4 | 12 | 4 | 12 |
| 1 | 2 | 1707 | 1018 | 775 | 81 | 5 | 5 | 9 | 3 | 73 |
| 2 | 2 | 1366 | 746 | 485 | 55 | 6 | 8 | 12 | 8 | 110 |
| 3 | 2 | 1272 | 429 | 339 | 91 | 6 | 12 | 15 | 2 | 6 |
| 4 | 2 | 4881 | 536 | 375 | 71 | 4 | 4 | 12 | 2 | 4 |
| 5 | 2 | 268 | 257 | 183 | 78 | 3 | 4 | 5 | 3 | 17 |

Trend of slow frames over the cycle index: >34 ms flat, >50 ms rises (the Lean model never rises).
H1 (slow frames near a viewport change): >34 ms refuted, >50 ms refuted; inputs {"changes":30,"slowNear":129,"framesNear":133,"slowFar":3512,"framesFar":4210}.
H2 (fights per open, later against first): refuted; inputs {"stretchesFirst":2,"fightsFirst":4,"stretchesLater":10,"fightsLater":18}.

## user@dwell: 3 usable of 3 passes, 3 jobs

| Cycle k | Passes | Frames | Slow >34 ms | Slow >50 ms | Median gap ms | Viewport changes | resize events | visualViewport resizes | Fights | Displaced |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 3 | 5758 | 808 | 181 | 31 | 6 | 10 | 44 | 16 | 46 |
| 1 | 3 | 3415 | 981 | 347 | 38 | 7 | 12 | 30 | 5 | 24 |
| 2 | 3 | 3197 | 796 | 341 | 42 | 7 | 18 | 41 | 19 | 96 |
| 3 | 3 | 3553 | 1155 | 641 | 48 | 7 | 14 | 36 | 19 | 98 |
| 4 | 3 | 2969 | 770 | 193 | 36 | 7 | 14 | 42 | 4 | 13 |
| 5 | 3 | 736 | 389 | 196 | 42 | 4 | 3 | 13 | 16 | 83 |

Trend of slow frames over the cycle index: >34 ms flat, >50 ms rises (the Lean model never rises).
H1 (slow frames near a viewport change): >34 ms refuted, >50 ms refuted; inputs {"changes":38,"slowNear":287,"framesNear":390,"slowFar":4612,"framesFar":8372}.
H2 (fights per open, later against first): refuted; inputs {"stretchesFirst":3,"fightsFirst":16,"stretchesLater":15,"fightsLater":63}.


## Cycle versus clock (Lean Fw.Measure.PushCycle.sepVerdict; slow frames > 50 ms per cycle, cycles 3 to 5, counted window = open stretch + 8 s)

| Arm | Full passes | Dwell passes | Period full ms | Period dwell ms | Stretch r (permille) | Within bound | Rate by cycle index | Rate by clock-matched index | Rate of dwell passes | Verdict (> 50 ms) | Verdict (> 34 ms) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| rewrite | 5 | 2 | 25743 | 72998 | 2835 | yes | 117000 | 133266 | 91000 | undecided:fewDwell | undecided:fewDwell |
| user | 2 | 3 | 22365 | 50112 | 2240 | yes | 168000 | 108666 | 69000 | undecided:fewFull | undecided:fewFull |

Full pass 16 cycles and stretch bound 2988 permille (Lean sepFullCycles, sepStretchBound): within the bound the clock-matched window fits (Lean sep_fits).

Minimum 3 usable passes per side; a side below it is undecided, never a win. Lost passes: rewrite full [p2 job 6 touch driver timed out (failed:touchesFailed)] dwell [p2 job 1 failed pass (failed:restartFailed); p2 job 2 failed pass (failed:restartFailed); p2 job 3 touch driver failed (failed:restartFailed); p2 job 4 not run (the job ended first)], user full [p2 job 1 failed pass (failed:restartFailed); p2 job 3 touch driver timed out (failed:touchesFailed); p2 job 4 touch driver timed out (failed:restartFailed); p2 job 5 touch driver timed out (failed:restartFailed)] dwell [p2 job 1 not run (the job ended first); p2 job 3 not run (the job ended first); p2 job 4 failed pass (failed:notReady)].

### Census after each cycle of the dwell passes (H4: does memory grow per cycle)

| Arm | Layers | Backing bytes | Layers created | Trend per dwell pass: layers / bytes / created | Mean bytes after (full pass) | Mean bytes after (dwell pass) |
|---|---|---|---|---|---|---|
| rewrite | few | few | few | flat,flat / flat,flat / flat,flat | 122232040 | 122015320 |
| user | no | no | no | flat,flat,flat / flat,flat,flat / flat,falls,flat | 100501318 | 106674238 |

Reading: yes = every dwell pass rises (first cycle below the mean of the rest), no = none rises, mixed = some, few = under 3 passes (Lean `across`).

