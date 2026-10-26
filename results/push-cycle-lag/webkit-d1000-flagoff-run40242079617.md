# Push cycles on the Simulator (real touches), dwell 1000 ms, 6 cycles per pass

## user: 3 usable of 3 passes, 3 jobs

| Cycle k | Passes | Frames | Slow >34 ms | Slow >50 ms | Median gap ms | Viewport changes | resize events | visualViewport resizes | Fights | Displaced |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 3 | 1213 | 786 | 271 | 39 | 6 | 20 | 50 | 5 | 25 |
| 1 | 3 | 1211 | 865 | 263 | 44 | 6 | 20 | 53 | 14 | 43 |
| 2 | 3 | 1115 | 794 | 294 | 43 | 6 | 17 | 46 | 13 | 37 |
| 3 | 3 | 647 | 630 | 419 | 58 | 6 | 15 | 30 | 9 | 30 |
| 4 | 3 | 684 | 571 | 452 | 74 | 5 | 12 | 29 | 6 | 20 |
| 5 | 3 | 876 | 645 | 541 | 69 | 2 | 2 | 8 | 8 | 21 |

Trend of slow frames over the cycle index: >34 ms flat, >50 ms rises (the Lean model never rises).
H1 (slow frames near a viewport change): >34 ms refuted, >50 ms refuted; inputs {"changes":31,"slowNear":312,"framesNear":366,"slowFar":3979,"framesFar":5362}.
H2 (fights per open, later against first): holds; inputs {"stretchesFirst":3,"fightsFirst":5,"stretchesLater":15,"fightsLater":50}.

## off-engine.scroll:unthrottle: 3 usable of 3 passes, 3 jobs

| Cycle k | Passes | Frames | Slow >34 ms | Slow >50 ms | Median gap ms | Viewport changes | resize events | visualViewport resizes | Fights | Displaced |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 3 | 1242 | 1112 | 391 | 45 | 6 | 16 | 33 | 9 | 29 |
| 1 | 3 | 980 | 806 | 352 | 46 | 6 | 15 | 26 | 7 | 28 |
| 2 | 3 | 1231 | 1024 | 419 | 46 | 6 | 17 | 30 | 11 | 35 |
| 3 | 3 | 561 | 547 | 452 | 73 | 8 | 13 | 22 | 7 | 22 |
| 4 | 3 | 1187 | 1178 | 893 | 65 | 9 | 10 | 19 | 8 | 19 |
| 5 | 3 | 615 | 611 | 558 | 77 | 5 | 2 | 5 | 8 | 154 |

Trend of slow frames over the cycle index: >34 ms falls, >50 ms rises (the Lean model never rises).
H1 (slow frames near a viewport change): >34 ms refuted, >50 ms refuted; inputs {"changes":40,"slowNear":268,"framesNear":281,"slowFar":5010,"framesFar":5517}.
H2 (fights per open, later against first): refuted; inputs {"stretchesFirst":3,"fightsFirst":9,"stretchesLater":15,"fightsLater":41}.

## off-hero.countdown:strip: 3 usable of 3 passes, 3 jobs

| Cycle k | Passes | Frames | Slow >34 ms | Slow >50 ms | Median gap ms | Viewport changes | resize events | visualViewport resizes | Fights | Displaced |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 3 | 1093 | 530 | 241 | 34 | 5 | 15 | 33 | 3 | 8 |
| 1 | 3 | 1152 | 570 | 268 | 34 | 4 | 12 | 34 | 4 | 27 |
| 2 | 3 | 1216 | 702 | 217 | 37 | 5 | 15 | 38 | 9 | 39 |
| 3 | 3 | 1143 | 601 | 276 | 34 | 7 | 18 | 38 | 10 | 90 |
| 4 | 3 | 1086 | 864 | 609 | 53 | 7 | 14 | 29 | 3 | 8 |
| 5 | 3 | 1260 | 1248 | 920 | 56 | 3 | 1 | 7 | 8 | 127 |

Trend of slow frames over the cycle index: >34 ms rises, >50 ms rises (the Lean model never rises).
H1 (slow frames near a viewport change): >34 ms refuted, >50 ms refuted; inputs {"changes":31,"slowNear":269,"framesNear":302,"slowFar":4246,"framesFar":6630}.
H2 (fights per open, later against first): holds; inputs {"stretchesFirst":3,"fightsFirst":3,"stretchesLater":15,"fightsLater":34}.

## off-morph.countdown:strip: 2 usable of 3 passes, 2 jobs; excluded: touch driver timed out

| Cycle k | Passes | Frames | Slow >34 ms | Slow >50 ms | Median gap ms | Viewport changes | resize events | visualViewport resizes | Fights | Displaced |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 2 | 828 | 463 | 168 | 48 | 4 | 13 | 32 | 4 | 18 |
| 1 | 2 | 822 | 569 | 215 | 47 | 4 | 11 | 26 | 2 | 13 |
| 2 | 2 | 866 | 549 | 173 | 42 | 4 | 11 | 30 | 3 | 9 |
| 3 | 2 | 640 | 359 | 205 | 64 | 4 | 10 | 24 | 4 | 19 |
| 4 | 2 | 660 | 649 | 446 | 69 | 4 | 6 | 11 | 2 | 11 |
| 5 | 2 | 841 | 832 | 572 | 66 | 0 | 1 | 0 | 7 | 98 |

Trend of slow frames over the cycle index: >34 ms rises, >50 ms rises (the Lean model never rises).
H1 (slow frames near a viewport change): >34 ms refuted, >50 ms refuted; inputs {"changes":20,"slowNear":198,"framesNear":221,"slowFar":3223,"framesFar":4424}.
H2 (fights per open, later against first): refuted; inputs {"stretchesFirst":2,"fightsFirst":4,"stretchesLater":10,"fightsLater":18}.

