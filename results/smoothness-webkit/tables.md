<!-- gen:runs -->
| job | leg | engine | version / runtime | arms | dropped by flags | windows | kept | refused (reason) | wall s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 39634194664:smoothness-webkit-mac-1 | mac | playwright-webkit | 27.2 | orig, base, aa, look | v2 = rewrite | 48 | 48 | 0 | 594 |
| 39634194664:smoothness-webkit-mac-2 | mac | playwright-webkit | 27.2 | orig, base, aa, look | v2 = rewrite | 48 | 48 | 0 | 507 |
| 39634194664:smoothness-webkit-sim-2 | sim | mobile-safari | com.apple.CoreSimulator.SimRuntime.iOS-27-0 | orig, base, aa, look | v2 = rewrite | 40 | 40 | 0 | 1642 |
| 39634194664:smoothness-webkit-sim-3 | sim | mobile-safari | com.apple.CoreSimulator.SimRuntime.iOS-27-0 | orig, base, aa, look | v2 = rewrite | 9 | 9 | 0 | 1216 |
<!-- /gen:runs -->

<!-- gen:mac-headline -->
**hero**

| arm | jobs | windows | frames | render work ms / window (median) | render work us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 2 | 12 | 72 | 3661.74 | 50857 (26012-73989) | 206 | 152 | 441 | 72 | 452 | 300 |
| base | 2 | 12 | 77 | 628.40 | 8519 (5749-8834) | 210 | 150 | 420 | 77 | 725 | 303 |
| aa | 2 | 12 | 82 | 650.85 | 8218 (5574-8822) | 218 | 153 | 472 | 82 | 747 | 307 |
| look | 2 | 12 | 82 | 699.85 | 8207 (5913-8899) | 214 | 159 | 442 | 82 | 737 | 308 |

**finish**

| arm | jobs | windows | frames | render work ms / window (median) | render work us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 2 | 12 | 67 | 1284.65 | 28547 (8649-29494) | 174 | 152 | 2914 | 67 | 119 | 107 |
| base | 2 | 12 | 71 | 604.67 | 13112 (7945-15921) | 180 | 159 | 2625 | 71 | 445 | 109 |
| aa | 2 | 12 | 67 | 582.82 | 12553 (7756-14874) | 167 | 148 | 2556 | 67 | 389 | 104 |
| look | 2 | 12 | 71 | 567.71 | 11262 (7233-11420) | 178 | 133 | 2761 | 71 | 318 | 109 |

**rest**

| arm | jobs | windows | frames | render work ms / window (median) | render work us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 2 | 12 | 68 | 2286.32 | 37480 (19373-43896) | 126 | 114 | 174 | 68 | 318 | 210 |
| base | 2 | 12 | 69 | 300.77 | 4296 (3025-5052) | 130 | 116 | 264 | 69 | 397 | 181 |
| aa | 2 | 12 | 71 | 287.29 | 4045 (3086-5208) | 132 | 118 | 275 | 71 | 382 | 186 |
| look | 2 | 12 | 66 | 284.62 | 4312 (3238-4851) | 130 | 116 | 277 | 66 | 380 | 175 |

<!-- /gen:mac-headline -->

<!-- gen:mac-ratios -->
**hero**

| metric | orig | base | aa | look | orig / base | base / aa |
| --- | --- | --- | --- | --- | --- | --- |
| frames in zone | 72 | 77 | 82 | 82 | 0.9 | 0.9 |
| window span ms | 7236.00 | 3213.00 | 3202.00 | 3498.00 | 2.3 | 1.0 |
| render work ms / window | 3661.74 | 628.40 | 650.85 | 699.85 | 5.8 | 1.0 |
| render work share of the window span % | 46.8 | 19.5 | 20.3 | 18.9 | 2.4 | 1.0 |
| render work us / frame | 50857 | 8519 | 8218 | 8207 | 6.0 | 1.0 |
| RecalculateStyles n | 206 | 210 | 218 | 214 | 1.0 | 1.0 |
| RecalculateStyles ms | 481.33 | 423.14 | 416.43 | 457.40 | 1.1 | 1.0 |
| Layout n | 152 | 150 | 153 | 159 | 1.0 | 1.0 |
| Layout ms | 3135.80 | 109.21 | 116.30 | 127.89 | 28.7 | 0.9 |
| Paint n | 441 | 420 | 472 | 442 | 1.1 | 0.9 |
| Paint ms | 114.54 | 125.79 | 146.30 | 141.01 | 0.9 | 0.9 |
| Composite n | 72 | 77 | 82 | 82 | 0.9 | 0.9 |
| FunctionCall n | 452 | 725 | 747 | 737 | 0.6 | 1.0 |
| FunctionCall ms | 2509.67 | 515.26 | 493.45 | 542.76 | 4.9 | 1.0 |
| FireAnimationFrame n | 300 | 303 | 307 | 308 | 1.0 | 1.0 |
| FireAnimationFrame ms | 2399.48 | 449.62 | 450.77 | 484.28 | 5.3 | 1.0 |

**finish**

| metric | orig | base | aa | look | orig / base | base / aa |
| --- | --- | --- | --- | --- | --- | --- |
| frames in zone | 67 | 71 | 67 | 71 | 0.9 | 1.1 |
| window span ms | 2365.00 | 2077.00 | 2055.00 | 2064.00 | 1.1 | 1.0 |
| render work ms / window | 1284.65 | 604.67 | 582.82 | 567.71 | 2.1 | 1.0 |
| render work share of the window span % | 53.9 | 29.7 | 27.5 | 27.7 | 1.8 | 1.1 |
| render work us / frame | 28547 | 13112 | 12553 | 11262 | 2.2 | 1.0 |
| RecalculateStyles n | 174 | 180 | 167 | 178 | 1.0 | 1.1 |
| RecalculateStyles ms | 472.14 | 440.13 | 421.27 | 397.62 | 1.1 | 1.0 |
| Layout n | 152 | 159 | 148 | 133 | 1.0 | 1.1 |
| Layout ms | 738.68 | 77.17 | 68.17 | 63.97 | 9.6 | 1.1 |
| Paint n | 2914 | 2625 | 2556 | 2761 | 1.1 | 1.0 |
| Paint ms | 159.71 | 133.03 | 136.58 | 129.41 | 1.2 | 1.0 |
| Composite n | 67 | 71 | 67 | 71 | 0.9 | 1.1 |
| FunctionCall n | 119 | 445 | 389 | 318 | 0.3 | 1.1 |
| FunctionCall ms | 857.43 | 170.09 | 154.79 | 140.59 | 5.0 | 1.1 |
| FireAnimationFrame n | 107 | 109 | 104 | 109 | 1.0 | 1.0 |
| FireAnimationFrame ms | 857.43 | 163.42 | 149.12 | 135.97 | 5.2 | 1.1 |

**rest**

| metric | orig | base | aa | look | orig / base | base / aa |
| --- | --- | --- | --- | --- | --- | --- |
| frames in zone | 68 | 69 | 71 | 66 | 1.0 | 1.0 |
| window span ms | 7236.00 | 3213.00 | 3202.00 | 3498.00 | 2.3 | 1.0 |
| render work ms / window | 2286.32 | 300.77 | 287.29 | 284.62 | 7.6 | 1.0 |
| render work share of the window span % | 33.7 | 9.3 | 9.4 | 9.4 | 3.6 | 1.0 |
| render work us / frame | 37480 | 4296 | 4045 | 4312 | 8.7 | 1.1 |
| RecalculateStyles n | 126 | 130 | 132 | 130 | 1.0 | 1.0 |
| RecalculateStyles ms | 298.88 | 234.10 | 217.77 | 221.55 | 1.3 | 1.1 |
| Layout n | 114 | 116 | 118 | 116 | 1.0 | 1.0 |
| Layout ms | 2047.62 | 51.02 | 46.53 | 45.65 | 40.1 | 1.1 |
| Paint n | 174 | 264 | 275 | 277 | 0.7 | 1.0 |
| Paint ms | 22.22 | 22.89 | 24.45 | 20.12 | 1.0 | 0.9 |
| Composite n | 68 | 69 | 71 | 66 | 1.0 | 1.0 |
| FunctionCall n | 318 | 397 | 382 | 380 | 0.8 | 1.0 |
| FunctionCall ms | 1949.27 | 313.33 | 267.82 | 279.62 | 6.2 | 1.2 |
| FireAnimationFrame n | 210 | 181 | 186 | 175 | 1.2 | 1.0 |
| FireAnimationFrame ms | 1936.65 | 295.07 | 249.38 | 268.17 | 6.6 | 1.2 |

<!-- /gen:mac-ratios -->

<!-- gen:mac-verdict -->
| zone | pair (first, second) | jobs | first | second | same | insufficient | verdict over jobs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| hero | orig, base | 2 | 0 | 2 | 0 | 0 | insufficient |
| hero | base, look | 2 | 0 | 0 | 2 | 0 | insufficient |
| hero | orig, look | 2 | 0 | 2 | 0 | 0 | insufficient |
| finish | orig, base | 2 | 0 | 1 | 1 | 0 | insufficient |
| finish | base, look | 2 | 0 | 0 | 2 | 0 | insufficient |
| finish | orig, look | 2 | 0 | 1 | 1 | 0 | insufficient |
| rest | orig, base | 2 | 0 | 2 | 0 | 0 | insufficient |
| rest | base, look | 2 | 0 | 0 | 2 | 0 | insufficient |
| rest | orig, look | 2 | 0 | 2 | 0 | 0 | insufficient |
<!-- /gen:mac-verdict -->

<!-- gen:mac-class -->
| zone | arm | jobs | deterministic | stable | quarantined |
| --- | --- | --- | --- | --- | --- |
| hero | orig | 2 | - | - | - |
| hero | base | 2 | - | - | - |
| hero | aa | 2 | - | - | - |
| hero | look | 2 | - | - | - |
| finish | orig | 2 | - | - | - |
| finish | base | 2 | - | - | - |
| finish | aa | 2 | - | - | - |
| finish | look | 2 | - | - | - |
| rest | orig | 2 | - | - | - |
| rest | base | 2 | - | - | - |
| rest | aa | 2 | - | - | - |
| rest | look | 2 | - | - | - |
<!-- /gen:mac-class -->

<!-- gen:mac-kinds -->
**hero** (median count / median covered ms per window; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| RecalculateStyles | 206 / 481.33 | 210 / 423.14 | 218 / 416.43 | 214 / 457.40 |
| Layout | 152 / 3135.80 | 150 / 109.21 | 153 / 116.30 | 159 / 127.89 |
| Paint | 441 / 114.54 | 420 / 125.79 | 472 / 146.30 | 442 / 141.01 |
| Composite | 72 / count only | 77 / count only | 82 / count only | 82 / count only |
| FunctionCall | 452 / 2509.67 | 725 / 515.26 | 747 / 493.45 | 737 / 542.76 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 39 / 20.37 | 8 / 3.09 | 9 / 3.32 | 10 / 3.26 |
| FireAnimationFrame | 300 / 2399.48 | 303 / 449.62 | 307 / 450.77 | 308 / 484.28 |
| EventDispatch | 85 / 7.55 | 507 / 56.27 | 530 / 49.93 | 513 / 53.75 |
| ObserverCallback | 36 / 124.52 | 12 / 9.32 | 12 / 9.07 | 12 / 10.44 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**finish** (median count / median covered ms per window; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| RecalculateStyles | 174 / 472.14 | 180 / 440.13 | 167 / 421.27 | 178 / 397.62 |
| Layout | 152 / 738.68 | 159 / 77.17 | 148 / 68.17 | 133 / 63.97 |
| Paint | 2914 / 159.71 | 2625 / 133.03 | 2556 / 136.58 | 2761 / 129.41 |
| Composite | 67 / count only | 71 / count only | 67 / count only | 71 / count only |
| FunctionCall | 119 / 857.43 | 445 / 170.09 | 389 / 154.79 | 318 / 140.59 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 5 / 0.26 | 4 / 0.42 | 4 / 0.35 | 4 / 0.46 |
| FireAnimationFrame | 107 / 857.43 | 109 / 163.42 | 104 / 149.12 | 109 / 135.97 |
| EventDispatch | 4 / 0.88 | 250 / 9.22 | 218 / 7.63 | 132 / 6.25 |
| ObserverCallback | 6 / 0.15 | 72 / 3.33 | 70 / 3.24 | 74 / 2.98 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**rest** (median count / median covered ms per window; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| RecalculateStyles | 126 / 298.88 | 130 / 234.10 | 132 / 217.77 | 130 / 221.55 |
| Layout | 114 / 2047.62 | 116 / 51.02 | 118 / 46.53 | 116 / 45.65 |
| Paint | 174 / 22.22 | 264 / 22.89 | 275 / 24.45 | 277 / 20.12 |
| Composite | 68 / count only | 69 / count only | 71 / count only | 66 / count only |
| FunctionCall | 318 / 1949.27 | 397 / 313.33 | 382 / 267.82 | 380 / 279.62 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 25 / 9.51 | 5 / 0.94 | 5 / 1.26 | 6 / 1.00 |
| FireAnimationFrame | 210 / 1936.65 | 181 / 295.07 | 186 / 249.38 | 175 / 268.17 |
| EventDispatch | 81 / 5.86 | 260 / 18.12 | 245 / 19.71 | 248 / 18.84 |
| ObserverCallback | 15 / 1.76 | 6 / 1.02 | 6 / 1.08 | 6 / 1.31 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

<!-- /gen:mac-kinds -->

<!-- gen:mac-cadence -->
| window | timeline | arm | jobs | reps | hitches per rep (median) | p50 ms | p95 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig | 2 | 12 | 43 | 41.0 | 167.0 | 484.0 |
| hero | on | base | 2 | 12 | 4 | 17.0 | 65.0 | 167.0 |
| hero | on | aa | 2 | 12 | 5 | 17.0 | 64.0 | 242.0 |
| hero | on | look | 2 | 12 | 5 | 17.0 | 62.0 | 227.0 |
| hero | off | orig | 2 | 10 | 24 | 38.0 | 143.0 | 422.0 |
| hero | off | base | 2 | 10 | 7 | 17.0 | 71.0 | 313.0 |
| hero | off | aa | 2 | 10 | 6 | 17.0 | 68.0 | 125.0 |
| hero | off | look | 2 | 10 | 11 | 17.0 | 73.0 | 210.0 |
| end | on | orig | 2 | 12 | 7 | 44.0 | 111.0 | 194.0 |
| end | on | base | 2 | 12 | 10 | 34.0 | 105.0 | 153.0 |
| end | on | aa | 2 | 12 | 9 | 35.0 | 100.0 | 220.0 |
| end | on | look | 2 | 12 | 9 | 31.0 | 108.0 | 193.0 |
| end | off | orig | 2 | 10 | 11 | 42.0 | 114.0 | 162.0 |
| end | off | base | 2 | 10 | 8 | 27.0 | 96.0 | 279.0 |
| end | off | aa | 2 | 10 | 8 | 32.0 | 103.0 | 145.0 |
| end | off | look | 2 | 10 | 9 | 31.0 | 105.0 | 157.0 |
<!-- /gen:mac-cadence -->

<!-- gen:mac-cadence-verdict -->
| window | timeline | pair (first, second) | jobs | first | second | same | insufficient | verdict over jobs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig, base | 2 | 0 | 2 | 0 | 0 | insufficient |
| hero | on | base, look | 2 | 0 | 0 | 2 | 0 | insufficient |
| hero | on | orig, look | 2 | 0 | 2 | 0 | 0 | insufficient |
| hero | off | orig, base | 2 | 0 | 1 | 1 | 0 | insufficient |
| hero | off | base, look | 2 | 0 | 0 | 2 | 0 | insufficient |
| hero | off | orig, look | 2 | 0 | 2 | 0 | 0 | insufficient |
| end | on | orig, base | 2 | 0 | 0 | 2 | 0 | insufficient |
| end | on | base, look | 2 | 0 | 0 | 2 | 0 | insufficient |
| end | on | orig, look | 2 | 0 | 0 | 2 | 0 | insufficient |
| end | off | orig, base | 2 | 0 | 0 | 2 | 0 | insufficient |
| end | off | base, look | 2 | 0 | 0 | 2 | 0 | insufficient |
| end | off | orig, look | 2 | 0 | 0 | 2 | 0 | insufficient |
<!-- /gen:mac-cadence-verdict -->

<!-- gen:sim-headline -->
**hero**

| arm | jobs | windows | frames | render work ms / window (median) | render work us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 0 | 0 | - | - | - (-) | - | - | - | - | - | - |
| base | 2 | 7 | 7 | 257.77 | 42961 (20402-42961) | 35 | 89 | 137 | 7 | 195 | 36 |
| aa | 2 | 6 | 6 | 227.19 | 40500 (22772-45438) | 30 | 83 | 105 | 6 | 173 | 27 |
| look | 2 | 6 | 7 | 183.69 | 30558 (20878-39292) | 32 | 81 | 102 | 7 | 159 | 36 |

**finish**

| arm | jobs | windows | frames | render work ms / window (median) | render work us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 2 | 6 | 6 | 668.06 | 116323 (102832-137864) | 24 | 27 | 423 | 6 | 26 | 18 |
| base | 2 | 6 | 6 | 260.05 | 43341 (22421-56460) | 30 | 35 | 425 | 6 | 153 | 17 |
| aa | 2 | 6 | 5 | 234.78 | 46956 (33248-92177) | 18 | 18 | 406 | 5 | 107 | 15 |
| look | 2 | 6 | 7 | 170.70 | 28078 (22507-76970) | 22 | 22 | 427 | 7 | 137 | 13 |

**rest**

| arm | jobs | windows | frames | render work ms / window (median) | render work us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 2 | 6 | 3 | 2823.18 | 1432690 (624023-2823180) | 26 | 88 | 64 | 3 | 43 | 21 |
| base | 2 | 6 | 4 | 114.80 | 114800 (27070-114800) | 25 | 26 | 57 | 4 | 105 | 24 |
| aa | 2 | 5 | 3 | 125.62 | 57010 (31830-111270) | 25 | 25 | 52 | 3 | 77 | 23 |
| look | 2 | 6 | 3 | 118.67 | 44365 (29667-109620) | 23 | 28 | 64 | 3 | 104 | 21 |

<!-- /gen:sim-headline -->

<!-- gen:sim-ratios -->
**hero**

| metric | orig | base | aa | look | orig / base | base / aa |
| --- | --- | --- | --- | --- | --- | --- |
| frames in zone | - | 7 | 6 | 7 | - | 1.2 |
| window span ms | - | 1585.00 | 1592.00 | 1569.00 | - | 1.0 |
| render work ms / window | - | 257.77 | 227.19 | 183.69 | - | 1.1 |
| render work share of the window span % | - | 16.2 | 14.4 | 11.7 | - | 1.1 |
| render work us / frame | - | 42961 | 40500 | 30558 | - | 1.1 |
| RecalculateStyles n | - | 35 | 30 | 32 | - | 1.2 |
| RecalculateStyles ms | - | 102.27 | 83.39 | 76.17 | - | 1.2 |
| Layout n | - | 89 | 83 | 81 | - | 1.1 |
| Layout ms | - | 63.31 | 69.53 | 52.25 | - | 0.9 |
| Paint n | - | 137 | 105 | 102 | - | 1.3 |
| Paint ms | - | 101.64 | 96.43 | 68.34 | - | 1.1 |
| Composite n | - | 7 | 6 | 7 | - | 1.2 |
| FunctionCall n | - | 195 | 173 | 159 | - | 1.1 |
| FunctionCall ms | - | 269.12 | 280.52 | 243.77 | - | 1.0 |
| FireAnimationFrame n | - | 36 | 27 | 36 | - | 1.3 |
| FireAnimationFrame ms | - | 101.16 | 99.03 | 89.70 | - | 1.0 |

**finish**

| metric | orig | base | aa | look | orig / base | base / aa |
| --- | --- | --- | --- | --- | --- | --- |
| frames in zone | 6 | 6 | 5 | 7 | 1.0 | 1.2 |
| window span ms | 2088.00 | 2027.00 | 2023.00 | 2005.00 | 1.0 | 1.0 |
| render work ms / window | 668.06 | 260.05 | 234.78 | 170.70 | 2.6 | 1.1 |
| render work share of the window span % | 32.2 | 12.8 | 11.2 | 8.5 | 2.5 | 1.1 |
| render work us / frame | 116323 | 43341 | 46956 | 28078 | 2.7 | 0.9 |
| RecalculateStyles n | 24 | 30 | 18 | 22 | 0.8 | 1.7 |
| RecalculateStyles ms | 124.18 | 185.61 | 157.23 | 127.55 | 0.7 | 1.2 |
| Layout n | 27 | 35 | 18 | 22 | 0.8 | 1.9 |
| Layout ms | 528.39 | 78.90 | 27.59 | 28.62 | 6.7 | 2.9 |
| Paint n | 423 | 425 | 406 | 427 | 1.0 | 1.0 |
| Paint ms | 37.75 | 51.70 | 71.33 | 44.92 | 0.7 | 0.7 |
| Composite n | 6 | 6 | 5 | 7 | 1.0 | 1.2 |
| FunctionCall n | 26 | 153 | 107 | 137 | 0.2 | 1.4 |
| FunctionCall ms | 569.13 | 50.65 | 45.36 | 35.96 | 11.2 | 1.1 |
| FireAnimationFrame n | 18 | 17 | 15 | 13 | 1.1 | 1.1 |
| FireAnimationFrame ms | 569.31 | 33.44 | 39.07 | 31.18 | 17.0 | 0.9 |

**rest**

| metric | orig | base | aa | look | orig / base | base / aa |
| --- | --- | --- | --- | --- | --- | --- |
| frames in zone | 3 | 4 | 3 | 3 | 0.8 | 1.3 |
| window span ms | 3051.00 | 1585.00 | 1592.00 | 1569.00 | 1.9 | 1.0 |
| render work ms / window | 2823.18 | 114.80 | 125.62 | 118.67 | 24.6 | 0.9 |
| render work share of the window span % | 91.2 | 7.2 | 8.0 | 7.5 | 12.7 | 0.9 |
| render work us / frame | 1432690 | 114800 | 57010 | 44365 | 12.5 | 2.0 |
| RecalculateStyles n | 26 | 25 | 25 | 23 | 1.0 | 1.0 |
| RecalculateStyles ms | 164.00 | 90.65 | 86.16 | 85.88 | 1.8 | 1.1 |
| Layout n | 88 | 26 | 25 | 28 | 3.4 | 1.0 |
| Layout ms | 2746.00 | 47.20 | 42.85 | 39.02 | 58.2 | 1.1 |
| Paint n | 64 | 57 | 52 | 64 | 1.1 | 1.1 |
| Paint ms | 14.40 | 18.31 | 21.32 | 28.34 | 0.8 | 0.9 |
| Composite n | 3 | 4 | 3 | 3 | 0.8 | 1.3 |
| FunctionCall n | 43 | 105 | 77 | 104 | 0.4 | 1.4 |
| FunctionCall ms | 2579.21 | 68.36 | 87.94 | 73.25 | 37.7 | 0.8 |
| FireAnimationFrame n | 21 | 24 | 23 | 21 | 0.9 | 1.0 |
| FireAnimationFrame ms | 224.41 | 44.57 | 51.68 | 50.70 | 5.0 | 0.9 |

<!-- /gen:sim-ratios -->

<!-- gen:sim-verdict -->
| zone | pair (first, second) | jobs | first | second | same | insufficient | verdict over jobs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| hero | orig, base | 2 | 0 | 0 | 0 | 2 | insufficient |
| hero | base, look | 2 | 0 | 0 | 1 | 1 | insufficient |
| hero | orig, look | 2 | 0 | 0 | 0 | 2 | insufficient |
| finish | orig, base | 2 | 0 | 1 | 0 | 1 | insufficient |
| finish | base, look | 2 | 0 | 0 | 1 | 1 | insufficient |
| finish | orig, look | 2 | 0 | 1 | 0 | 1 | insufficient |
| rest | orig, base | 2 | 0 | 0 | 0 | 2 | insufficient |
| rest | base, look | 2 | 0 | 0 | 0 | 2 | insufficient |
| rest | orig, look | 2 | 0 | 0 | 0 | 2 | insufficient |
<!-- /gen:sim-verdict -->

<!-- gen:sim-class -->
| zone | arm | jobs | deterministic | stable | quarantined |
| --- | --- | --- | --- | --- | --- |
| hero | orig | 0 | - | - | - |
| hero | base | 2 | - | - | - |
| hero | aa | 2 | - | - | - |
| hero | look | 2 | - | - | - |
| finish | orig | 2 | - | - | - |
| finish | base | 2 | - | - | - |
| finish | aa | 2 | - | - | - |
| finish | look | 2 | - | - | - |
| rest | orig | 2 | - | - | - |
| rest | base | 2 | - | - | - |
| rest | aa | 2 | - | - | - |
| rest | look | 2 | - | - | - |
<!-- /gen:sim-class -->

<!-- gen:sim-kinds -->
**hero** (median count / median covered ms per window; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| RecalculateStyles | - / - | 35 / 102.27 | 30 / 83.39 | 32 / 76.17 |
| Layout | - / - | 89 / 63.31 | 83 / 69.53 | 81 / 52.25 |
| Paint | - / - | 137 / 101.64 | 105 / 96.43 | 102 / 68.34 |
| Composite | - / count only | 7 / count only | 6 / count only | 7 / count only |
| FunctionCall | - / - | 195 / 269.12 | 173 / 280.52 | 159 / 243.77 |
| EvaluateScript | - / - | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | - / - | 58 / 158.89 | 55 / 161.81 | 54 / 148.93 |
| FireAnimationFrame | - / - | 36 / 101.16 | 27 / 99.03 | 36 / 89.70 |
| EventDispatch | - / - | 131 / 12.56 | 101 / 14.52 | 92 / 8.68 |
| ObserverCallback | - / - | 7 / 6.94 | 6 / 3.62 | 8 / 2.90 |
| RenderingFrame | - / - | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**finish** (median count / median covered ms per window; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| RecalculateStyles | 24 / 124.18 | 30 / 185.61 | 18 / 157.23 | 22 / 127.55 |
| Layout | 27 / 528.39 | 35 / 78.90 | 18 / 27.59 | 22 / 28.62 |
| Paint | 423 / 37.75 | 425 / 51.70 | 406 / 71.33 | 427 / 44.92 |
| Composite | 6 / count only | 6 / count only | 5 / count only | 7 / count only |
| FunctionCall | 26 / 569.13 | 153 / 50.65 | 107 / 45.36 | 137 / 35.96 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 6 / 1.52 | 6 / 1.68 | 6 / 4.85 | 6 / 2.32 |
| FireAnimationFrame | 18 / 569.31 | 17 / 33.44 | 15 / 39.07 | 13 / 31.18 |
| EventDispatch | 4 / 2.87 | 137 / 16.80 | 78 / 11.45 | 113 / 5.56 |
| ObserverCallback | 0 / 0.00 | 12 / 1.97 | 10 / 2.77 | 12 / 2.34 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**rest** (median count / median covered ms per window; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| RecalculateStyles | 26 / 164.00 | 25 / 90.65 | 25 / 86.16 | 23 / 85.88 |
| Layout | 88 / 2746.00 | 26 / 47.20 | 25 / 42.85 | 28 / 39.02 |
| Paint | 64 / 14.40 | 57 / 18.31 | 52 / 21.32 | 64 / 28.34 |
| Composite | 3 / count only | 4 / count only | 3 / count only | 3 / count only |
| FunctionCall | 43 / 2579.21 | 105 / 68.36 | 77 / 87.94 | 104 / 73.25 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 5 / 2352.11 | 1 / 0.52 | 5 / 1.76 | 2 / 2.62 |
| FireAnimationFrame | 21 / 224.41 | 24 / 44.57 | 23 / 51.68 | 21 / 50.70 |
| EventDispatch | 1 / 0.13 | 83 / 40.84 | 77 / 31.04 | 100 / 23.45 |
| ObserverCallback | 14 / 107.62 | 7 / 4.62 | 8 / 7.82 | 8 / 4.71 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

<!-- /gen:sim-kinds -->

<!-- gen:sim-cadence -->
| window | timeline | arm | jobs | reps | hitches per rep (median) | p50 ms | p95 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig | 2 | 6 | 1 | 465.0 | 474.0 | 474.0 |
| hero | on | base | 2 | 7 | 4 | 136.0 | 791.0 | 791.0 |
| hero | on | aa | 2 | 6 | 5 | 180.0 | 549.0 | 759.0 |
| hero | on | look | 2 | 6 | 6 | 207.0 | 573.0 | 638.0 |
| end | on | orig | 2 | 6 | 4 | 455.0 | 627.0 | 805.0 |
| end | on | base | 2 | 6 | 5 | 466.0 | 576.0 | 780.0 |
| end | on | aa | 2 | 6 | 4 | 440.0 | 781.0 | 781.0 |
| end | on | look | 2 | 6 | 5 | 389.0 | 520.0 | 1023.0 |
<!-- /gen:sim-cadence -->

<!-- gen:sim-cadence-verdict -->
| window | timeline | pair (first, second) | jobs | first | second | same | insufficient | verdict over jobs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig, base | 2 | 1 | 0 | 0 | 1 | insufficient |
| hero | on | base, look | 2 | 0 | 0 | 1 | 1 | insufficient |
| hero | on | orig, look | 2 | 1 | 0 | 0 | 1 | insufficient |
| end | on | orig, base | 2 | 0 | 0 | 1 | 1 | insufficient |
| end | on | base, look | 2 | 0 | 0 | 1 | 1 | insufficient |
| end | on | orig, look | 2 | 0 | 0 | 1 | 1 | insufficient |
<!-- /gen:sim-cadence-verdict -->

<!-- gen:minutes -->
| run | leg | job | result | wall min | billed min |
| --- | --- | --- | --- | --- | --- |
| 39634194664 | mac | webkit mac (playwright-webkit, macos-26) job 1 | success | 10.7 | 11 |
| 39634194664 | sim | webkit sim (mobile safari, xcode-27) job 1 | failure | 23.2 | 24 |
| 39634194664 | mac | webkit mac (playwright-webkit, macos-26) job 2 | success | 9.1 | 10 |
| 39634194664 | mac | webkit mac (playwright-webkit, macos-26) job 3 | cancelled | 15 | 15 |
| 39634194664 | sim | webkit sim (mobile safari, xcode-27) job 2 | success | 37.7 | 38 |
| 39634194664 | sim | webkit sim (mobile safari, xcode-27) job 3 | success | 31.8 | 32 |
| median of successes | mac |  | n=2 | 9.9 |  |
| longest success | mac |  |  | 10.7 |  |
| all jobs billed | mac |  | n=3 |  | 36 |
| median of successes | sim |  | n=2 | 34.8 |  |
| longest success | sim |  |  | 37.7 |  |
| all jobs billed | sim |  | n=3 |  | 94 |
<!-- /gen:minutes -->
