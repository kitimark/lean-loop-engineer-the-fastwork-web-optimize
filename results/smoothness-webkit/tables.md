<!-- gen:runs -->
| job | leg | engine | version / runtime | arms | dropped by flags | windows | kept | refused (reason) | wall s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39612238445:smoothness-webkit-mac | mac | playwright-webkit | 27.2 | orig, base, aa, look | v2 = rewrite | 48 | 48 | 0 | 523 |
| 39612238445:smoothness-webkit-sim | sim | mobile-safari | com.apple.CoreSimulator.SimRuntime.iOS-27-0 | orig, base, aa, look | v2 = rewrite | 40 | 40 | 0 | 1546 |
| 39617081415:smoothness-webkit-mac | mac | playwright-webkit | 27.2 | orig, base, aa, look | v2 = rewrite | 48 | 48 | 0 | 615 |
| 39617081415:smoothness-webkit-sim | sim | mobile-safari | com.apple.CoreSimulator.SimRuntime.iOS-27-0 | orig, base, aa, look | v2 = rewrite | 40 | 40 | 0 | 1343 |
| 39624728525:smoothness-webkit-mac | mac | playwright-webkit | 27.2 | orig, base, aa, look | v2 = rewrite | 48 | 48 | 0 | 577 |
| 39624728525:smoothness-webkit-sim | sim | mobile-safari | com.apple.CoreSimulator.SimRuntime.iOS-27-0 | orig, base, aa, look | v2 = rewrite | 29 | 29 | 0 | 1754 |
<!-- /gen:runs -->

<!-- gen:mac-headline -->
**hero**

| arm | jobs | windows | frames | render us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 3 | 18 | 76 | 814926 (586461-1107032) | 213 | 161 | 451 | 76 | 447 | 306 |
| base | 3 | 18 | 82 | 237815 (151881-448718) | 219 | 157 | 449 | 82 | 746 | 308 |
| aa | 3 | 18 | 80 | 271786 (120151-487064) | 217 | 161 | 468 | 80 | 752 | 308 |
| look | 3 | 18 | 76 | 255779 (69405-454162) | 208 | 153 | 434 | 76 | 723 | 299 |

**finish**

| arm | jobs | windows | frames | render us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 3 | 18 | 45 | 72621 (36333-148317) | 128 | 111 | 1745 | 45 | 92 | 80 |
| base | 3 | 18 | 48 | 125674 (32916-229473) | 122 | 102 | 1913 | 48 | 312 | 74 |
| aa | 3 | 18 | 50 | 100742 (36412-206491) | 125 | 107 | 1838 | 50 | 319 | 76 |
| look | 3 | 18 | 51 | 145799 (52744-170181) | 134 | 99 | 1928 | 51 | 253 | 79 |

**rest**

| arm | jobs | windows | frames | render us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 3 | 18 | 66 | 166742 (67295-306276) | 132 | 118 | 177 | 66 | 295 | 210 |
| base | 3 | 18 | 67 | 58579 (16231-113526) | 131 | 116 | 173 | 67 | 374 | 178 |
| aa | 3 | 18 | 71 | 71182 (15180-94198) | 124 | 107 | 144 | 71 | 387 | 183 |
| look | 3 | 18 | 70 | 75297 (18365-93935) | 135 | 117 | 184 | 70 | 378 | 183 |

<!-- /gen:mac-headline -->

<!-- gen:mac-verdict -->
| zone | pair (first, second) | jobs | first | second | same | insufficient | verdict over jobs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| hero | orig, base | 3 | 0 | 3 | 0 | 0 | second |
| hero | base, look | 3 | 0 | 0 | 3 | 0 | same |
| hero | orig, look | 3 | 0 | 3 | 0 | 0 | second |
| finish | orig, base | 3 | 0 | 0 | 3 | 0 | same |
| finish | base, look | 3 | 0 | 0 | 3 | 0 | same |
| finish | orig, look | 3 | 0 | 0 | 3 | 0 | same |
| rest | orig, base | 3 | 0 | 2 | 1 | 0 | second |
| rest | base, look | 3 | 0 | 0 | 3 | 0 | same |
| rest | orig, look | 3 | 0 | 2 | 1 | 0 | second |
<!-- /gen:mac-verdict -->

<!-- gen:mac-class -->
| zone | arm | jobs | deterministic | stable | quarantined |
| --- | --- | --- | --- | --- | --- |
| hero | orig | 3 | 2 | 8 | 1 |
| hero | base | 3 | 3 | 5 | 3 |
| hero | aa | 3 | 3 | 3 | 5 |
| hero | look | 3 | 4 | 4 | 3 |
| finish | orig | 3 | 4 | 6 | 1 |
| finish | base | 3 | 3 | 6 | 2 |
| finish | aa | 3 | 3 | 5 | 3 |
| finish | look | 3 | 3 | 4 | 4 |
| rest | orig | 3 | 2 | 9 | 0 |
| rest | base | 3 | 3 | 7 | 1 |
| rest | aa | 3 | 3 | 7 | 1 |
| rest | look | 3 | 3 | 6 | 2 |
<!-- /gen:mac-class -->

<!-- gen:mac-kinds -->
**hero** (median count / median summed ms per window)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| RecalculateStyles | 213 / 443.73 | 219 / 462.55 | 217 / 459.46 | 208 / 446.88 |
| Layout | 161 / 2456.59 | 157 / 114.80 | 161 / 114.90 | 153 / 107.82 |
| Paint | 451 / 105.03 | 449 / 128.73 | 468 / 144.89 | 434 / 125.70 |
| Composite | 76 / 55617.74 | 82 / 17008.08 | 80 / 22132.94 | 76 / 19915.16 |
| FunctionCall | 447 / 2218.16 | 746 / 543.80 | 752 / 493.69 | 723 / 495.65 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 35 / 18.74 | 8 / 3.69 | 10 / 3.50 | 8 / 3.38 |
| FireAnimationFrame | 306 / 2090.71 | 308 / 486.14 | 308 / 442.59 | 299 / 432.60 |
| EventDispatch | 76 / 7.04 | 509 / 59.90 | 532 / 53.06 | 501 / 53.17 |
| ObserverCallback | 33 / 113.32 | 12 / 8.10 | 12 / 8.01 | 12 / 7.60 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**finish** (median count / median summed ms per window)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| RecalculateStyles | 128 / 419.86 | 122 / 397.27 | 125 / 382.89 | 134 / 402.94 |
| Layout | 111 / 764.48 | 102 / 67.39 | 107 / 67.10 | 99 / 65.77 |
| Paint | 1745 / 124.02 | 1913 / 125.45 | 1838 / 128.09 | 1928 / 127.96 |
| Composite | 45 / 1989.84 | 48 / 5532.99 | 50 / 4760.03 | 51 / 7281.32 |
| FunctionCall | 92 / 890.30 | 312 / 157.69 | 319 / 153.24 | 253 / 155.55 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 5 / 0.25 | 4 / 0.36 | 4 / 0.50 | 4 / 0.36 |
| FireAnimationFrame | 80 / 889.86 | 74 / 151.03 | 76 / 145.50 | 79 / 146.35 |
| EventDispatch | 4 / 0.77 | 188 / 8.31 | 190 / 8.03 | 124 / 6.48 |
| ObserverCallback | 6 / 0.12 | 48 / 2.55 | 48 / 2.96 | 50 / 3.07 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**rest** (median count / median summed ms per window)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| RecalculateStyles | 132 / 297.96 | 131 / 219.27 | 124 / 243.89 | 135 / 239.83 |
| Layout | 118 / 1915.09 | 116 / 48.50 | 107 / 47.93 | 117 / 54.09 |
| Paint | 177 / 21.61 | 173 / 26.38 | 144 / 23.94 | 184 / 26.00 |
| Composite | 66 / 8708.18 | 67 / 3713.13 | 71 / 4534.42 | 70 / 4953.42 |
| FunctionCall | 295 / 1859.34 | 374 / 291.82 | 387 / 309.97 | 378 / 304.21 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 19 / 7.63 | 5 / 0.59 | 5 / 0.86 | 5 / 0.85 |
| FireAnimationFrame | 210 / 1846.59 | 178 / 277.25 | 183 / 291.32 | 183 / 289.41 |
| EventDispatch | 73 / 5.10 | 247 / 16.78 | 256 / 17.49 | 244 / 16.83 |
| ObserverCallback | 14 / 1.52 | 6 / 1.15 | 6 / 1.28 | 6 / 1.16 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

<!-- /gen:mac-kinds -->

<!-- gen:mac-cadence -->
| window | timeline | arm | jobs | reps | hitches per rep (median) | p50 ms | p95 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig | 3 | 18 | 48 | 26.0 | 141.0 | 575.0 |
| hero | on | base | 3 | 18 | 7 | 17.0 | 55.0 | 205.0 |
| hero | on | aa | 3 | 18 | 7 | 17.0 | 61.0 | 198.0 |
| hero | on | look | 3 | 18 | 6 | 17.0 | 56.0 | 180.0 |
| hero | off | orig | 3 | 15 | 34 | 34.0 | 128.0 | 286.0 |
| hero | off | base | 3 | 15 | 6 | 17.0 | 60.0 | 186.0 |
| hero | off | aa | 3 | 15 | 7 | 17.0 | 64.0 | 226.0 |
| hero | off | look | 3 | 15 | 7 | 17.0 | 65.0 | 189.0 |
| end | on | orig | 3 | 18 | 16 | 49.0 | 106.0 | 222.0 |
| end | on | base | 3 | 18 | 12 | 33.0 | 116.0 | 290.0 |
| end | on | aa | 3 | 18 | 12 | 32.0 | 104.0 | 193.0 |
| end | on | look | 3 | 18 | 10 | 32.0 | 112.0 | 197.0 |
| end | off | orig | 3 | 15 | 10 | 33.0 | 99.0 | 260.0 |
| end | off | base | 3 | 15 | 7 | 25.0 | 88.0 | 220.0 |
| end | off | aa | 3 | 15 | 9 | 25.0 | 79.0 | 451.0 |
| end | off | look | 3 | 15 | 8 | 24.0 | 92.0 | 345.0 |
<!-- /gen:mac-cadence -->

<!-- gen:mac-cadence-verdict -->
| window | timeline | pair (first, second) | jobs | first | second | same | insufficient | verdict over jobs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig, base | 3 | 0 | 3 | 0 | 0 | second |
| hero | on | base, look | 3 | 0 | 0 | 3 | 0 | same |
| hero | on | orig, look | 3 | 0 | 3 | 0 | 0 | second |
| hero | off | orig, base | 3 | 0 | 3 | 0 | 0 | second |
| hero | off | base, look | 3 | 0 | 0 | 3 | 0 | same |
| hero | off | orig, look | 3 | 0 | 3 | 0 | 0 | second |
| end | on | orig, base | 3 | 0 | 0 | 3 | 0 | same |
| end | on | base, look | 3 | 0 | 0 | 3 | 0 | same |
| end | on | orig, look | 3 | 0 | 0 | 3 | 0 | same |
| end | off | orig, base | 3 | 0 | 0 | 3 | 0 | same |
| end | off | base, look | 3 | 0 | 0 | 3 | 0 | same |
| end | off | orig, look | 3 | 0 | 0 | 3 | 0 | same |
<!-- /gen:mac-cadence-verdict -->

<!-- gen:sim-headline -->
**hero**

| arm | jobs | windows | frames | render us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 3 | 6 | 2 | 2602515 (989380-2846850) | 9 | 67 | 45 | 2 | 16 | 7 |
| base | 3 | 14 | 8 | 120551 (42012-203945) | 38 | 84 | 111 | 8 | 185 | 46 |
| aa | 3 | 13 | 8 | 108092 (54495-521063) | 33 | 81 | 110 | 8 | 160 | 37 |
| look | 3 | 14 | 8 | 131484 (39006-277816) | 34 | 84 | 106 | 8 | 174 | 37 |

**finish**

| arm | jobs | windows | frames | render us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 3 | 14 | 6 | 293618 (113906-489115) | 25 | 28 | 420 | 6 | 26 | 18 |
| base | 3 | 13 | 6 | 273250 (156115-540520) | 23 | 24 | 421 | 6 | 96 | 14 |
| aa | 3 | 13 | 7 | 237862 (112781-309601) | 23 | 25 | 500 | 7 | 140 | 17 |
| look | 3 | 14 | 7 | 235245 (95642-439767) | 25 | 25 | 516 | 7 | 110 | 15 |

**rest**

| arm | jobs | windows | frames | render us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 3 | 13 | 2 | 1338760 (162885-3490060) | 21 | 79 | 49 | 2 | 36 | 16 |
| base | 3 | 14 | 4 | 121980 (29940-369590) | 33 | 42 | 94 | 4 | 116 | 29 |
| aa | 3 | 12 | 7 | 136850 (23920-294026) | 35 | 49 | 113 | 7 | 171 | 34 |
| look | 3 | 14 | 8 | 125412 (29574-774450) | 38 | 39 | 99 | 8 | 139 | 39 |

<!-- /gen:sim-headline -->

<!-- gen:sim-verdict -->
| zone | pair (first, second) | jobs | first | second | same | insufficient | verdict over jobs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| hero | orig, base | 3 | 0 | 0 | 0 | 3 | same |
| hero | base, look | 3 | 0 | 0 | 2 | 1 | same |
| hero | orig, look | 3 | 0 | 0 | 0 | 3 | same |
| finish | orig, base | 3 | 0 | 0 | 2 | 1 | same |
| finish | base, look | 3 | 0 | 0 | 2 | 1 | same |
| finish | orig, look | 3 | 0 | 1 | 1 | 1 | same |
| rest | orig, base | 3 | 0 | 1 | 0 | 2 | same |
| rest | base, look | 3 | 0 | 0 | 1 | 2 | same |
| rest | orig, look | 3 | 0 | 1 | 0 | 2 | same |
<!-- /gen:sim-verdict -->

<!-- gen:sim-class -->
| zone | arm | jobs | deterministic | stable | quarantined |
| --- | --- | --- | --- | --- | --- |
| hero | orig | 3 | 2 | 9 | 0 |
| hero | base | 3 | 2 | 9 | 0 |
| hero | aa | 3 | 4 | 7 | 0 |
| hero | look | 3 | 2 | 8 | 1 |
| finish | orig | 3 | 5 | 5 | 1 |
| finish | base | 3 | 3 | 5 | 3 |
| finish | aa | 3 | 3 | 6 | 2 |
| finish | look | 3 | 3 | 5 | 3 |
| rest | orig | 3 | 6 | 4 | 1 |
| rest | base | 3 | 2 | 6 | 3 |
| rest | aa | 3 | 2 | 8 | 1 |
| rest | look | 3 | 2 | 4 | 5 |
<!-- /gen:sim-class -->

<!-- gen:sim-kinds -->
**hero** (median count / median summed ms per window)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| RecalculateStyles | 9 / 21.08 | 38 / 81.95 | 33 / 75.50 | 34 / 83.54 |
| Layout | 67 / 2534.81 | 84 / 55.36 | 81 / 44.37 | 84 / 58.45 |
| Paint | 45 / 2.98 | 111 / 70.15 | 110 / 56.86 | 106 / 49.55 |
| Composite | 2 / 2595.92 | 8 / 709.34 | 8 / 653.00 | 8 / 724.97 |
| FunctionCall | 16 / 2373.82 | 185 / 250.36 | 160 / 215.86 | 174 / 247.50 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 5 / 2349.21 | 52 / 137.01 | 49 / 115.93 | 53 / 142.39 |
| FireAnimationFrame | 7 / 40.27 | 46 / 102.02 | 37 / 91.24 | 37 / 95.56 |
| EventDispatch | 2 / 0.24 | 117 / 8.49 | 92 / 6.06 | 99 / 7.40 |
| ObserverCallback | 2 / 0.72 | 7 / 3.45 | 7 / 1.98 | 7 / 3.98 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**finish** (median count / median summed ms per window)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| RecalculateStyles | 25 / 129.12 | 23 / 135.95 | 23 / 138.22 | 25 / 112.80 |
| Layout | 28 / 499.51 | 24 / 33.40 | 25 / 23.53 | 25 / 20.45 |
| Paint | 420 / 38.27 | 421 / 37.44 | 500 / 38.35 | 516 / 38.07 |
| Composite | 6 / 1214.02 | 6 / 1471.03 | 7 / 1526.07 | 7 / 1452.50 |
| FunctionCall | 26 / 539.41 | 96 / 40.10 | 140 / 45.58 | 110 / 42.16 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 6 / 3.02 | 6 / 2.99 | 6 / 3.28 | 6 / 3.03 |
| FireAnimationFrame | 18 / 535.75 | 14 / 24.80 | 17 / 30.52 | 15 / 32.10 |
| EventDispatch | 4 / 1.71 | 86 / 6.30 | 115 / 6.43 | 80 / 5.32 |
| ObserverCallback | 0 / 0.00 | 10 / 1.82 | 12 / 1.51 | 12 / 1.73 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**rest** (median count / median summed ms per window)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| RecalculateStyles | 21 / 134.71 | 33 / 118.57 | 35 / 96.99 | 38 / 139.39 |
| Layout | 79 / 2219.83 | 42 / 45.84 | 49 / 43.04 | 39 / 57.41 |
| Paint | 49 / 13.40 | 94 / 21.72 | 113 / 30.20 | 99 / 22.62 |
| Composite | 2 / 261.88 | 4 / 458.30 | 7 / 460.11 | 8 / 429.40 |
| FunctionCall | 36 / 2255.01 | 116 / 105.76 | 171 / 99.18 | 139 / 116.57 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 3 / 1930.84 | 7 / 6.02 | 11 / 19.64 | 5 / 16.20 |
| FireAnimationFrame | 16 / 175.57 | 29 / 60.65 | 34 / 48.79 | 39 / 60.50 |
| EventDispatch | 1 / 0.13 | 89 / 26.13 | 139 / 21.56 | 116 / 27.55 |
| ObserverCallback | 12 / 87.41 | 8 / 6.08 | 9 / 5.48 | 8 / 5.76 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

<!-- /gen:sim-kinds -->

<!-- gen:sim-cadence -->
| window | timeline | arm | jobs | reps | hitches per rep (median) | p50 ms | p95 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig | 3 | 14 | 1 | 335.0 | 2447.0 | 2700.0 |
| hero | on | base | 3 | 14 | 7 | 29.0 | 332.0 | 628.0 |
| hero | on | aa | 3 | 13 | 7 | 34.0 | 324.0 | 430.0 |
| hero | on | look | 3 | 14 | 7 | 38.0 | 291.0 | 687.0 |
| end | on | orig | 3 | 14 | 5 | 354.0 | 575.0 | 664.0 |
| end | on | base | 3 | 13 | 5 | 316.0 | 605.0 | 763.0 |
| end | on | aa | 3 | 13 | 6 | 328.0 | 502.0 | 598.0 |
| end | on | look | 3 | 14 | 7 | 244.0 | 499.0 | 535.0 |
<!-- /gen:sim-cadence -->

<!-- gen:sim-cadence-verdict -->
| window | timeline | pair (first, second) | jobs | first | second | same | insufficient | verdict over jobs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig, base | 3 | 1 | 0 | 1 | 1 | same |
| hero | on | base, look | 3 | 0 | 0 | 2 | 1 | same |
| hero | on | orig, look | 3 | 1 | 0 | 1 | 1 | same |
| end | on | orig, base | 3 | 0 | 0 | 2 | 1 | same |
| end | on | base, look | 3 | 0 | 0 | 2 | 1 | same |
| end | on | orig, look | 3 | 1 | 0 | 1 | 1 | same |
<!-- /gen:sim-cadence-verdict -->

<!-- gen:minutes -->
| run | leg | job | result | wall min | billed min |
| --- | --- | --- | --- | --- | --- |
| 39612238445 | mac | webkit mac (playwright-webkit, macos-26) | success | 9.4 | 10 |
| 39612238445 | sim | webkit sim (mobile safari, xcode-27) | success | 34.1 | 35 |
| 39617081415 | mac | webkit mac (playwright-webkit, macos-26) | success | 11.2 | 12 |
| 39617081415 | sim | webkit sim (mobile safari, xcode-27) | success | 29.1 | 30 |
| 39624728525 | mac | webkit mac (playwright-webkit, macos-26) | success | 10.4 | 11 |
| 39624728525 | sim | webkit sim (mobile safari, xcode-27) | success | 34.2 | 35 |
| median of successes | mac |  | n=3 | 10.4 |  |
| longest success | mac |  |  | 11.2 |  |
| all jobs billed | mac |  | n=3 |  | 33 |
| median of successes | sim |  | n=3 | 34.1 |  |
| longest success | sim |  |  | 34.2 |  |
| all jobs billed | sim |  | n=3 |  | 100 |
<!-- /gen:minutes -->
