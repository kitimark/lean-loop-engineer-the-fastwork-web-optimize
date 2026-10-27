# Push cycles on the Simulator (real touches), dwell 1000 ms, 6 cycles per pass

## rewrite: 2 usable of 4 passes, 2 jobs; excluded: touch driver timed out

| Cycle k | Passes | Frames | Slow >34 ms | Slow >50 ms | Median gap ms | Viewport changes | resize events | visualViewport resizes | Fights | Displaced |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 2 | 721 | 563 | 178 | 42 | 4 | 11 | 22 | 2 | 4 |
| 1 | 2 | 835 | 519 | 135 | 37 | 4 | 15 | 25 | 4 | 14 |
| 2 | 2 | 903 | 470 | 131 | 36 | 4 | 14 | 24 | 5 | 21 |
| 3 | 2 | 474 | 402 | 203 | 51 | 4 | 13 | 22 | 9 | 116 |
| 4 | 2 | 825 | 818 | 678 | 67 | 5 | 3 | 7 | 4 | 17 |
| 5 | 2 | 2112 | 2091 | 1324 | 54 | 7 | 7 | 13 | 12 | 243 |
| 6 | 2 | 976 | 962 | 595 | 75 | 8 | 7 | 13 | 5 | 84 |
| 7 | 2 | 886 | 870 | 606 | 71 | 6 | 13 | 21 | 10 | 119 |
| 8 | 2 | 385 | 380 | 299 | 103 | 5 | 7 | 14 | 2 | 3 |
| 9 | 2 | 487 | 477 | 338 | 82 | 4 | 11 | 16 | 2 | 3 |
| 10 | 2 | 462 | 448 | 322 | 76 | 5 | 7 | 14 | 4 | 17 |
| 11 | 2 | 484 | 468 | 309 | 75 | 3 | 7 | 12 | 4 | 17 |
| 12 | 2 | 325 | 321 | 271 | 71 | 3 | 5 | 10 | 3 | 8 |
| 13 | 2 | 516 | 513 | 429 | 77 | 6 | 10 | 19 | 5 | 37 |
| 14 | 2 | 655 | 645 | 418 | 89 | 5 | 6 | 11 | 1 | 2 |
| 15 | 2 | 267 | 265 | 261 | 84 | 3 | 3 | 3 | 3 | 90 |

Trend of slow frames over the cycle index: >34 ms rises, >50 ms rises (the Lean model never rises).
H1 (slow frames near a viewport change): >34 ms refuted, >50 ms refuted; inputs {"changes":76,"slowNear":498,"framesNear":523,"slowFar":9714,"framesFar":10758}.
H2 (fights per open, later against first): holds; inputs {"stretchesFirst":2,"fightsFirst":2,"stretchesLater":30,"fightsLater":73}.

## user: 5 usable of 6 passes, 5 jobs; excluded: touch driver timed out

| Cycle k | Passes | Frames | Slow >34 ms | Slow >50 ms | Median gap ms | Viewport changes | resize events | visualViewport resizes | Fights | Displaced |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 5 | 3562 | 2243 | 567 | 34 | 10 | 36 | 89 | 20 | 65 |
| 1 | 5 | 2350 | 1217 | 344 | 36 | 10 | 36 | 90 | 25 | 72 |
| 2 | 5 | 2307 | 1466 | 524 | 34 | 11 | 29 | 74 | 23 | 61 |
| 3 | 5 | 2749 | 2321 | 1518 | 46 | 10 | 24 | 55 | 21 | 146 |
| 4 | 5 | 1361 | 1338 | 824 | 55 | 10 | 16 | 27 | 11 | 39 |
| 5 | 5 | 2246 | 2225 | 1464 | 61 | 10 | 18 | 30 | 13 | 52 |
| 6 | 5 | 1538 | 1385 | 862 | 59 | 10 | 23 | 42 | 10 | 32 |
| 7 | 5 | 2018 | 1975 | 1250 | 53 | 11 | 21 | 42 | 10 | 50 |
| 8 | 5 | 4749 | 3401 | 956 | 52 | 10 | 32 | 60 | 8 | 46 |
| 9 | 5 | 3570 | 3302 | 1357 | 54 | 10 | 28 | 50 | 12 | 29 |
| 10 | 5 | 1435 | 1384 | 911 | 57 | 12 | 22 | 44 | 13 | 33 |
| 11 | 5 | 990 | 912 | 678 | 64 | 12 | 24 | 40 | 13 | 34 |
| 12 | 5 | 1371 | 1125 | 776 | 72 | 10 | 26 | 48 | 10 | 31 |
| 13 | 5 | 1663 | 1603 | 1105 | 63 | 11 | 15 | 30 | 11 | 36 |
| 14 | 5 | 4960 | 4868 | 3251 | 56 | 9 | 17 | 25 | 12 | 74 |
| 15 | 5 | 1839 | 1803 | 1327 | 56 | 3 | 2 | 9 | 10 | 69 |

Trend of slow frames over the cycle index: >34 ms falls, >50 ms rises (the Lean model never rises).
H1 (slow frames near a viewport change): >34 ms refuted, >50 ms refuted; inputs {"changes":159,"slowNear":1205,"framesNear":1364,"slowFar":31363,"framesFar":37264}.
H2 (fights per open, later against first): refuted; inputs {"stretchesFirst":5,"fightsFirst":20,"stretchesLater":75,"fightsLater":202}.

## rewrite@dwell: 4 usable of 5 passes, 4 jobs; excluded: touch driver failed

| Cycle k | Passes | Frames | Slow >34 ms | Slow >50 ms | Median gap ms | Viewport changes | resize events | visualViewport resizes | Fights | Displaced |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 4 | 4309 | 2127 | 885 | 51 | 10 | 16 | 34 | 4 | 13 |
| 1 | 4 | 3543 | 1737 | 848 | 57 | 12 | 15 | 32 | 6 | 39 |
| 2 | 4 | 4680 | 3346 | 2586 | 66 | 10 | 11 | 21 | 8 | 45 |
| 3 | 4 | 6966 | 3259 | 1768 | 79 | 11 | 16 | 28 | 6 | 57 |
| 4 | 4 | 4245 | 2730 | 2471 | 71 | 11 | 7 | 16 | 8 | 85 |
| 5 | 4 | 467 | 460 | 386 | 125 | 2 | 2 | 2 | 2 | 12 |

Trend of slow frames over the cycle index: >34 ms flat, >50 ms rises (the Lean model never rises).
H1 (slow frames near a viewport change): >34 ms refuted, >50 ms refuted; inputs {"changes":56,"slowNear":293,"framesNear":307,"slowFar":13366,"framesFar":15330}.
H2 (fights per open, later against first): holds; inputs {"stretchesFirst":4,"fightsFirst":4,"stretchesLater":20,"fightsLater":30}.

## user@dwell: 5 usable of 5 passes, 5 jobs

| Cycle k | Passes | Frames | Slow >34 ms | Slow >50 ms | Median gap ms | Viewport changes | resize events | visualViewport resizes | Fights | Displaced |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 5 | 6716 | 2302 | 591 | 33 | 12 | 22 | 63 | 20 | 55 |
| 1 | 5 | 4454 | 1292 | 758 | 47 | 10 | 15 | 48 | 21 | 187 |
| 2 | 5 | 3633 | 1311 | 920 | 61 | 13 | 11 | 24 | 9 | 65 |
| 3 | 5 | 6450 | 1987 | 867 | 61 | 9 | 14 | 27 | 5 | 46 |
| 4 | 5 | 4410 | 1691 | 774 | 45 | 16 | 11 | 33 | 13 | 68 |
| 5 | 5 | 1154 | 992 | 590 | 69 | 5 | 6 | 11 | 9 | 53 |

Trend of slow frames over the cycle index: >34 ms falls, >50 ms rises (the Lean model never rises).
H1 (slow frames near a viewport change): >34 ms refuted, >50 ms refuted; inputs {"changes":65,"slowNear":299,"framesNear":358,"slowFar":9276,"framesFar":13366}.
H2 (fights per open, later against first): refuted; inputs {"stretchesFirst":5,"fightsFirst":20,"stretchesLater":25,"fightsLater":57}.


## Cycle versus clock (Lean Fw.Measure.PushCycle.sepVerdict; slow frames > 50 ms per cycle, cycles 3 to 5, counted window = open stretch + 8 s)

| Arm | Full passes | Dwell passes | Period full ms | Period dwell ms | Stretch r (permille) | Within bound | Rate by cycle index | Rate by clock-matched index | Rate of dwell passes | Verdict (> 50 ms) | Verdict (> 34 ms) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| rewrite | 2 | 4 | 21483 | 84516 | 3934 | no | 215000 | 105500 | 165666 | undecided:fewFull | undecided:fewFull |
| user | 5 | 5 | 26194 | 55691 | 2126 | yes | 166800 | 159666 | 95666 | undecided:inseparable | undecided:inseparable |

Full pass 16 cycles and stretch bound 2988 permille (Lean sepFullCycles, sepStretchBound): within the bound the clock-matched window fits (Lean sep_fits).

Minimum 3 usable passes per side; a side below it is undecided, never a win. Lost passes: rewrite full [job 2 not run (the job ended first); job 4 touch driver timed out (failed:restartFailed); job 5 touch driver timed out (failed:touchesFailed); job 6 failed pass (failed:restartFailed)] dwell [job 2 not run (the job ended first); job 6 touch driver failed (failed:restartFailed)], user full [job 3 touch driver timed out (failed:restartFailed)] dwell [job 5 not run (the job ended first)].

### Census after each cycle of the dwell passes (H4: does memory grow per cycle)

| Arm | Layers | Backing bytes | Layers created | Trend per dwell pass: layers / bytes / created | Mean bytes after (full pass) | Mean bytes after (dwell pass) |
|---|---|---|---|---|---|---|
| rewrite | no | no | no | flat,flat,flat,flat / flat,flat,flat,flat / flat,flat,flat,flat | 122286220 | 116991449 |
| user | no | no | no | flat,flat,flat,flat,flat / flat,flat,flat,flat,flat / flat,flat,flat,flat,flat | 106565878 | 104582509 |

Reading: yes = every dwell pass rises (first cycle below the mean of the rest), no = none rises, mixed = some, few = under 3 passes (Lean `across`).
