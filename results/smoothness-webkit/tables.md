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

| arm | n windows (per job) | frames | render work ms / window (median) | render work us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 12 (6+6) | 72 | 2998.32 | 42229 (26012-73989) | 202 | 147 | 433 | 72 | 409 | 297 |
| base | 12 (6+6) | 69 | 529.99 | 7098 (5749-8834) | 200 | 138 | 391 | 69 | 686 | 291 |
| aa | 12 (6+6) | 70 | 439.32 | 6764 (5574-8822) | 202 | 143 | 406 | 70 | 679 | 293 |
| look | 12 (6+6) | 68 | 511.68 | 7524 (5913-8899) | 204 | 148 | 402 | 68 | 686 | 290 |

**finish**

| arm | n windows (per job) | frames | render work ms / window (median) | render work us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 12 (6+6) | 64 | 992.92 | 17730 (8649-29494) | 164 | 141 | 2708 | 64 | 110 | 100 |
| base | 12 (6+6) | 57 | 600.67 | 10470 (7945-15921) | 146 | 124 | 2263 | 57 | 376 | 88 |
| aa | 12 (6+6) | 59 | 564.92 | 10201 (7756-14874) | 145 | 125 | 2215 | 59 | 373 | 89 |
| look | 12 (6+6) | 60 | 551.87 | 9133 (7233-11420) | 149 | 115 | 2287 | 60 | 279 | 89 |

**rest**

| arm | n windows (per job) | frames | render work ms / window (median) | render work us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 12 (6+6) | 66 | 1926.87 | 25240 (19373-43896) | 123 | 111 | 173 | 66 | 283 | 209 |
| base | 12 (6+6) | 68 | 239.22 | 3797 (3025-5052) | 129 | 114 | 235 | 68 | 374 | 180 |
| aa | 12 (6+6) | 63 | 253.85 | 3830 (3086-5208) | 132 | 114 | 234 | 63 | 375 | 170 |
| look | 12 (6+6) | 65 | 245.52 | 3816 (3238-4851) | 129 | 116 | 253 | 65 | 373 | 172 |

<!-- /gen:mac-headline -->

<!-- gen:mac-ratios -->
**hero**

| metric | orig | base | aa | look | orig / base | base / aa |
| --- | --- | --- | --- | --- | --- | --- |
| n windows (per job) | 12 (6+6) | 12 (6+6) | 12 (6+6) | 12 (6+6) |  |  |
| frames in zone | 72 | 69 | 70 | 68 | 1.0 | 1.0 |
| window span ms | 6829.00 | 2752.00 | 2880.00 | 2796.00 | 2.5 | 1.0 |
| render work ms / window | 2998.32 | 529.99 | 439.32 | 511.68 | 5.7 | 1.2 |
| render work share of the window span % | 42.6 | 18.6 | 16.7 | 18.4 | 2.3 | 1.1 |
| render work us / frame | 42229 | 7098 | 6764 | 7524 | 5.9 | 1.0 |
| RecalculateStyles n | 202 | 200 | 202 | 204 | 1.0 | 1.0 |
| RecalculateStyles ms | 421.61 | 344.26 | 294.22 | 320.14 | 1.2 | 1.2 |
| Layout n | 147 | 138 | 143 | 148 | 1.1 | 1.0 |
| Layout ms | 2491.18 | 85.99 | 77.65 | 92.12 | 29.0 | 1.1 |
| Paint n | 433 | 391 | 406 | 402 | 1.1 | 1.0 |
| Paint ms | 96.01 | 107.30 | 99.90 | 106.07 | 0.9 | 1.1 |
| Composite n | 72 | 69 | 70 | 68 | 1.0 | 1.0 |
| FunctionCall n | 409 | 686 | 679 | 686 | 0.6 | 1.0 |
| FunctionCall ms | 2194.21 | 420.82 | 349.30 | 375.87 | 5.2 | 1.2 |
| FireAnimationFrame n | 297 | 291 | 293 | 290 | 1.0 | 1.0 |
| FireAnimationFrame ms | 2055.29 | 367.87 | 303.74 | 321.77 | 5.6 | 1.2 |

**finish**

| metric | orig | base | aa | look | orig / base | base / aa |
| --- | --- | --- | --- | --- | --- | --- |
| n windows (per job) | 12 (6+6) | 12 (6+6) | 12 (6+6) | 12 (6+6) |  |  |
| frames in zone | 64 | 57 | 59 | 60 | 1.1 | 1.0 |
| window span ms | 2233.00 | 2054.00 | 2048.00 | 2051.00 | 1.1 | 1.0 |
| render work ms / window | 992.92 | 600.67 | 564.92 | 551.87 | 1.7 | 1.1 |
| render work share of the window span % | 43.8 | 28.7 | 27.5 | 26.2 | 1.5 | 1.0 |
| render work us / frame | 17730 | 10470 | 10201 | 9133 | 1.7 | 1.0 |
| RecalculateStyles n | 164 | 146 | 145 | 149 | 1.1 | 1.0 |
| RecalculateStyles ms | 430.88 | 422.76 | 408.41 | 369.68 | 1.0 | 1.0 |
| Layout n | 141 | 124 | 125 | 115 | 1.1 | 1.0 |
| Layout ms | 452.90 | 72.92 | 66.70 | 59.68 | 6.2 | 1.1 |
| Paint n | 2708 | 2263 | 2215 | 2287 | 1.2 | 1.0 |
| Paint ms | 143.21 | 132.45 | 125.97 | 128.54 | 1.1 | 1.1 |
| Composite n | 64 | 57 | 59 | 60 | 1.1 | 1.0 |
| FunctionCall n | 110 | 376 | 373 | 279 | 0.3 | 1.0 |
| FunctionCall ms | 543.90 | 166.53 | 153.40 | 138.95 | 3.3 | 1.1 |
| FireAnimationFrame n | 100 | 88 | 89 | 89 | 1.1 | 1.0 |
| FireAnimationFrame ms | 543.96 | 159.85 | 149.05 | 134.64 | 3.4 | 1.1 |

**rest**

| metric | orig | base | aa | look | orig / base | base / aa |
| --- | --- | --- | --- | --- | --- | --- |
| n windows (per job) | 12 (6+6) | 12 (6+6) | 12 (6+6) | 12 (6+6) |  |  |
| frames in zone | 66 | 68 | 63 | 65 | 1.0 | 1.1 |
| window span ms | 6829.00 | 2752.00 | 2880.00 | 2796.00 | 2.5 | 1.0 |
| render work ms / window | 1926.87 | 239.22 | 253.85 | 245.52 | 8.1 | 0.9 |
| render work share of the window span % | 33.3 | 8.9 | 8.8 | 9.0 | 3.7 | 1.0 |
| render work us / frame | 25240 | 3797 | 3830 | 3816 | 6.6 | 1.0 |
| RecalculateStyles n | 123 | 129 | 132 | 129 | 1.0 | 1.0 |
| RecalculateStyles ms | 267.15 | 168.03 | 167.97 | 187.21 | 1.6 | 1.0 |
| Layout n | 111 | 114 | 114 | 116 | 1.0 | 1.0 |
| Layout ms | 1667.93 | 45.60 | 46.27 | 45.40 | 36.6 | 1.0 |
| Paint n | 173 | 235 | 234 | 253 | 0.7 | 1.0 |
| Paint ms | 20.58 | 21.66 | 21.09 | 19.98 | 1.0 | 1.0 |
| Composite n | 66 | 68 | 63 | 65 | 1.0 | 1.1 |
| FunctionCall n | 283 | 374 | 375 | 373 | 0.8 | 1.0 |
| FunctionCall ms | 1721.08 | 245.33 | 231.74 | 254.88 | 7.0 | 1.1 |
| FireAnimationFrame n | 209 | 180 | 170 | 172 | 1.2 | 1.1 |
| FireAnimationFrame ms | 1711.33 | 231.28 | 217.75 | 240.32 | 7.4 | 1.1 |

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
**hero** (median count / median covered ms per window over all kept windows of all jobs; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| n windows (per job) | 12 (6+6) | 12 (6+6) | 12 (6+6) | 12 (6+6) |
| RecalculateStyles | 202 / 421.61 | 200 / 344.26 | 202 / 294.22 | 204 / 320.14 |
| Layout | 147 / 2491.18 | 138 / 85.99 | 143 / 77.65 | 148 / 92.12 |
| Paint | 433 / 96.01 | 391 / 107.30 | 406 / 99.90 | 402 / 106.07 |
| Composite | 72 / count only | 69 / count only | 70 / count only | 68 / count only |
| FunctionCall | 409 / 2194.21 | 686 / 420.82 | 679 / 349.30 | 686 / 375.87 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 25 / 15.34 | 8 / 2.62 | 8 / 2.59 | 8 / 2.85 |
| FireAnimationFrame | 297 / 2055.29 | 291 / 367.87 | 293 / 303.74 | 290 / 321.77 |
| EventDispatch | 59 / 5.68 | 475 / 40.22 | 465 / 44.17 | 477 / 51.05 |
| ObserverCallback | 31 / 82.24 | 12 / 5.44 | 12 / 6.90 | 12 / 5.26 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**finish** (median count / median covered ms per window over all kept windows of all jobs; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| n windows (per job) | 12 (6+6) | 12 (6+6) | 12 (6+6) | 12 (6+6) |
| RecalculateStyles | 164 / 430.88 | 146 / 422.76 | 145 / 408.41 | 149 / 369.68 |
| Layout | 141 / 452.90 | 124 / 72.92 | 125 / 66.70 | 115 / 59.68 |
| Paint | 2708 / 143.21 | 2263 / 132.45 | 2215 / 125.97 | 2287 / 128.54 |
| Composite | 64 / count only | 57 / count only | 59 / count only | 60 / count only |
| FunctionCall | 110 / 543.90 | 376 / 166.53 | 373 / 153.40 | 279 / 138.95 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 5 / 0.24 | 4 / 0.36 | 4 / 0.32 | 4 / 0.39 |
| FireAnimationFrame | 100 / 543.96 | 88 / 159.85 | 89 / 149.05 | 89 / 134.64 |
| EventDispatch | 4 / 0.78 | 228 / 8.31 | 206 / 6.51 | 132 / 4.76 |
| ObserverCallback | 5 / 0.13 | 58 / 3.14 | 56 / 2.90 | 54 / 2.93 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**rest** (median count / median covered ms per window over all kept windows of all jobs; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| n windows (per job) | 12 (6+6) | 12 (6+6) | 12 (6+6) | 12 (6+6) |
| RecalculateStyles | 123 / 267.15 | 129 / 168.03 | 132 / 167.97 | 129 / 187.21 |
| Layout | 111 / 1667.93 | 114 / 45.60 | 114 / 46.27 | 116 / 45.40 |
| Paint | 173 / 20.58 | 235 / 21.66 | 234 / 21.09 | 253 / 19.98 |
| Composite | 66 / count only | 68 / count only | 63 / count only | 65 / count only |
| FunctionCall | 283 / 1721.08 | 374 / 245.33 | 375 / 231.74 | 373 / 254.88 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 16 / 6.26 | 4 / 0.70 | 5 / 0.96 | 4 / 0.99 |
| FireAnimationFrame | 209 / 1711.33 | 180 / 231.28 | 170 / 217.75 | 172 / 240.32 |
| EventDispatch | 69 / 4.64 | 241 / 16.64 | 243 / 15.07 | 245 / 15.38 |
| ObserverCallback | 12 / 1.29 | 6 / 0.83 | 6 / 0.84 | 6 / 0.98 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

<!-- /gen:mac-kinds -->

<!-- gen:mac-cadence -->
| window | timeline | arm | reps n (per job) | hitches per rep (median) | p50 ms | p95 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig | 12 (6+6) | 43 | 34.0 | 136.0 | 484.0 |
| hero | on | base | 12 (6+6) | 4 | 17.0 | 52.0 | 167.0 |
| hero | on | aa | 12 (6+6) | 5 | 17.0 | 50.0 | 242.0 |
| hero | on | look | 12 (6+6) | 5 | 17.0 | 50.0 | 227.0 |
| hero | off | orig | 10 (5+5) | 24 | 34.0 | 122.0 | 422.0 |
| hero | off | base | 10 (5+5) | 7 | 17.0 | 64.0 | 313.0 |
| hero | off | aa | 10 (5+5) | 6 | 17.0 | 63.0 | 125.0 |
| hero | off | look | 10 (5+5) | 11 | 17.0 | 70.0 | 210.0 |
| end | on | orig | 12 (6+6) | 7 | 32.0 | 93.0 | 194.0 |
| end | on | base | 12 (6+6) | 10 | 27.0 | 92.0 | 153.0 |
| end | on | aa | 12 (6+6) | 9 | 27.0 | 93.0 | 220.0 |
| end | on | look | 12 (6+6) | 9 | 25.0 | 86.0 | 193.0 |
| end | off | orig | 10 (5+5) | 11 | 32.0 | 92.0 | 162.0 |
| end | off | base | 10 (5+5) | 8 | 25.0 | 84.0 | 279.0 |
| end | off | aa | 10 (5+5) | 8 | 24.0 | 84.0 | 145.0 |
| end | off | look | 10 (5+5) | 9 | 23.0 | 81.0 | 157.0 |
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

| arm | n windows (per job) | frames | render work ms / window (median) | render work us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 0 (0+0) | insufficient (n=0) | insufficient (n=0) | insufficient (n=0) | insufficient (n=0) | insufficient (n=0) | insufficient (n=0) | insufficient (n=0) | insufficient (n=0) | insufficient (n=0) |
| base | 7 (5+2) | 7 | 216.95 | 30992 (20402-42961) | 33 | 84 | 116 | 7 | 178 | 32 |
| aa | 6 (5+1) | 6 | 227.19 | 40500 (22772-45438) | 30 | 83 | 105 | 6 | 173 | 27 |
| look | 6 (5+1) | 7 | 183.69 | 30558 (20878-39292) | 32 | 81 | 102 | 7 | 159 | 36 |

**finish**

| arm | n windows (per job) | frames | render work ms / window (median) | render work us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 6 (5+1) | 5 | 668.06 | 116323 (102832-137864) | 21 | 24 | 400 | 5 | 23 | 15 |
| base | 6 (5+1) | 6 | 225.84 | 43341 (22421-56460) | 26 | 28 | 425 | 6 | 142 | 16 |
| aa | 6 (5+1) | 5 | 234.78 | 46956 (33248-92177) | 18 | 18 | 406 | 5 | 107 | 15 |
| look | 6 (5+1) | 6 | 168.84 | 28078 (22507-76970) | 18 | 18 | 409 | 6 | 91 | 13 |

**rest**

| arm | n windows (per job) | frames | render work ms / window (median) | render work us/frame (median, range) | RecalculateStyles n | Layout n | Paint n | Composite n | FunctionCall n | FireAnimationFrame n |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| orig | 6 (5+1) | 2 | 2823.18 | 1432690 (624023-2823180) | 22 | 81 | 49 | 2 | 37 | 16 |
| base | 6 (5+1) | 4 | 114.80 | 40250 (27070-114800) | 25 | 26 | 57 | 4 | 105 | 24 |
| aa | 5 (4+1) | 2 | 114.02 | 44756 (31830-111270) | 14 | 13 | 44 | 2 | 77 | 11 |
| look | 6 (5+1) | 3 | 118.67 | 44365 (29667-109620) | 23 | 28 | 64 | 3 | 104 | 21 |

<!-- /gen:sim-headline -->

<!-- gen:sim-ratios -->
**hero**

| metric | orig | base | aa | look | orig / base | base / aa |
| --- | --- | --- | --- | --- | --- | --- |
| n windows (per job) | 0 (0+0) | 7 (5+2) | 6 (5+1) | 6 (5+1) |  |  |
| frames in zone | insufficient (n=0) | 7 | 6 | 7 | - | 1.2 |
| window span ms | insufficient (n=0) | 1569.00 | 1571.00 | 1569.00 | - | 1.0 |
| render work ms / window | insufficient (n=0) | 216.95 | 227.19 | 183.69 | - | 1.0 |
| render work share of the window span % | insufficient (n=0) | 13.8 | 14.4 | 11.7 | - | 1.0 |
| render work us / frame | insufficient (n=0) | 30992 | 40500 | 30558 | - | 0.8 |
| RecalculateStyles n | insufficient (n=0) | 33 | 30 | 32 | - | 1.1 |
| RecalculateStyles ms | insufficient (n=0) | 89.43 | 83.39 | 76.17 | - | 1.1 |
| Layout n | insufficient (n=0) | 84 | 83 | 81 | - | 1.0 |
| Layout ms | insufficient (n=0) | 59.01 | 69.53 | 52.25 | - | 0.8 |
| Paint n | insufficient (n=0) | 116 | 105 | 102 | - | 1.1 |
| Paint ms | insufficient (n=0) | 67.78 | 96.43 | 65.35 | - | 0.7 |
| Composite n | insufficient (n=0) | 7 | 6 | 7 | - | 1.2 |
| FunctionCall n | insufficient (n=0) | 178 | 173 | 159 | - | 1.0 |
| FunctionCall ms | insufficient (n=0) | 250.60 | 280.52 | 243.77 | - | 0.9 |
| FireAnimationFrame n | insufficient (n=0) | 32 | 27 | 36 | - | 1.2 |
| FireAnimationFrame ms | insufficient (n=0) | 99.97 | 96.74 | 89.70 | - | 1.0 |

**finish**

| metric | orig | base | aa | look | orig / base | base / aa |
| --- | --- | --- | --- | --- | --- | --- |
| n windows (per job) | 6 (5+1) | 6 (5+1) | 6 (5+1) | 6 (5+1) |  |  |
| frames in zone | 5 | 6 | 5 | 6 | 0.8 | 1.2 |
| window span ms | 2088.00 | 2024.00 | 2023.00 | 2005.00 | 1.0 | 1.0 |
| render work ms / window | 668.06 | 225.84 | 234.78 | 168.84 | 3.0 | 1.0 |
| render work share of the window span % | 32.2 | 11.1 | 11.2 | 8.4 | 2.9 | 1.0 |
| render work us / frame | 116323 | 43341 | 46956 | 28078 | 2.7 | 0.9 |
| RecalculateStyles n | 21 | 26 | 18 | 18 | 0.8 | 1.4 |
| RecalculateStyles ms | 124.18 | 177.14 | 157.23 | 127.55 | 0.7 | 1.1 |
| Layout n | 24 | 28 | 18 | 18 | 0.9 | 1.6 |
| Layout ms | 502.31 | 35.61 | 27.59 | 25.63 | 14.1 | 1.3 |
| Paint n | 400 | 425 | 406 | 409 | 0.9 | 1.0 |
| Paint ms | 37.75 | 44.77 | 71.33 | 44.92 | 0.8 | 0.6 |
| Composite n | 5 | 6 | 5 | 6 | 0.8 | 1.2 |
| FunctionCall n | 23 | 142 | 107 | 91 | 0.2 | 1.3 |
| FunctionCall ms | 529.93 | 39.82 | 45.36 | 35.96 | 13.3 | 0.9 |
| FireAnimationFrame n | 15 | 16 | 15 | 13 | 0.9 | 1.1 |
| FireAnimationFrame ms | 528.02 | 33.44 | 39.07 | 29.94 | 15.8 | 0.9 |

**rest**

| metric | orig | base | aa | look | orig / base | base / aa |
| --- | --- | --- | --- | --- | --- | --- |
| n windows (per job) | 6 (5+1) | 6 (5+1) | 5 (4+1) | 6 (5+1) |  |  |
| frames in zone | 2 | 4 | 2 | 3 | 0.5 | 2.0 |
| window span ms | 3051.00 | 1570.00 | 1570.00 | 1569.00 | 1.9 | 1.0 |
| render work ms / window | 2823.18 | 114.80 | 114.02 | 118.67 | 24.6 | 1.0 |
| render work share of the window span % | 91.2 | 7.2 | 7.2 | 7.5 | 12.7 | 1.0 |
| render work us / frame | 1432690 | 40250 | 44756 | 44365 | 35.6 | 0.9 |
| RecalculateStyles n | 22 | 25 | 14 | 23 | 0.9 | 1.8 |
| RecalculateStyles ms | 164.00 | 85.97 | 83.84 | 85.88 | 1.9 | 1.0 |
| Layout n | 81 | 26 | 13 | 28 | 3.1 | 2.0 |
| Layout ms | 2746.00 | 40.96 | 40.73 | 39.02 | 67.0 | 1.0 |
| Paint n | 49 | 57 | 44 | 64 | 0.9 | 1.3 |
| Paint ms | 14.40 | 18.31 | 18.81 | 28.34 | 0.8 | 1.0 |
| Composite n | 2 | 4 | 2 | 3 | 0.5 | 2.0 |
| FunctionCall n | 37 | 105 | 77 | 104 | 0.4 | 1.4 |
| FunctionCall ms | 2579.21 | 68.36 | 76.62 | 73.25 | 37.7 | 0.9 |
| FireAnimationFrame n | 16 | 24 | 11 | 21 | 0.7 | 2.2 |
| FireAnimationFrame ms | 133.47 | 44.57 | 47.65 | 50.70 | 3.0 | 0.9 |

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
**hero** (median count / median covered ms per window over all kept windows of all jobs; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| n windows (per job) | 0 (0+0) | 7 (5+2) | 6 (5+1) | 6 (5+1) |
| RecalculateStyles | insufficient (n=0) | 33 / 89.43 | 30 / 83.39 | 32 / 76.17 |
| Layout | insufficient (n=0) | 84 / 59.01 | 83 / 69.53 | 81 / 52.25 |
| Paint | insufficient (n=0) | 116 / 67.78 | 105 / 96.43 | 102 / 65.35 |
| Composite | insufficient (n=0) | 7 / count only | 6 / count only | 7 / count only |
| FunctionCall | insufficient (n=0) | 178 / 250.60 | 173 / 280.52 | 159 / 243.77 |
| EvaluateScript | insufficient (n=0) | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | insufficient (n=0) | 52 / 156.04 | 54 / 161.81 | 54 / 148.93 |
| FireAnimationFrame | insufficient (n=0) | 32 / 99.97 | 27 / 96.74 | 36 / 89.70 |
| EventDispatch | insufficient (n=0) | 113 / 8.82 | 101 / 14.52 | 92 / 8.68 |
| ObserverCallback | insufficient (n=0) | 7 / 2.83 | 6 / 3.62 | 8 / 2.90 |
| RenderingFrame | insufficient (n=0) | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**finish** (median count / median covered ms per window over all kept windows of all jobs; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| n windows (per job) | 6 (5+1) | 6 (5+1) | 6 (5+1) | 6 (5+1) |
| RecalculateStyles | 21 / 124.18 | 26 / 177.14 | 18 / 157.23 | 18 / 127.55 |
| Layout | 24 / 502.31 | 28 / 35.61 | 18 / 27.59 | 18 / 25.63 |
| Paint | 400 / 37.75 | 425 / 44.77 | 406 / 71.33 | 409 / 44.92 |
| Composite | 5 / count only | 6 / count only | 5 / count only | 6 / count only |
| FunctionCall | 23 / 529.93 | 142 / 39.82 | 107 / 45.36 | 91 / 35.96 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 6 / 1.52 | 6 / 1.68 | 6 / 4.85 | 6 / 2.32 |
| FireAnimationFrame | 15 / 528.02 | 16 / 33.44 | 15 / 39.07 | 13 / 29.94 |
| EventDispatch | 4 / 2.87 | 137 / 6.94 | 78 / 11.45 | 69 / 5.56 |
| ObserverCallback | 0 / 0.00 | 12 / 1.97 | 10 / 2.77 | 10 / 2.34 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

**rest** (median count / median covered ms per window over all kept windows of all jobs; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)

| kind | orig | base | aa | look |
| --- | --- | --- | --- | --- |
| n windows (per job) | 6 (5+1) | 6 (5+1) | 5 (4+1) | 6 (5+1) |
| RecalculateStyles | 22 / 164.00 | 25 / 85.97 | 14 / 83.84 | 23 / 85.88 |
| Layout | 81 / 2746.00 | 26 / 40.96 | 13 / 40.73 | 28 / 39.02 |
| Paint | 49 / 14.40 | 57 / 18.31 | 44 / 18.81 | 64 / 28.34 |
| Composite | 2 / count only | 4 / count only | 2 / count only | 3 / count only |
| FunctionCall | 37 / 2579.21 | 105 / 68.36 | 77 / 76.62 | 104 / 73.25 |
| EvaluateScript | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |
| TimerFire | 5 / 2352.11 | 1 / 0.52 | 2 / 0.93 | 2 / 2.62 |
| FireAnimationFrame | 16 / 133.47 | 24 / 44.57 | 11 / 47.65 | 21 / 50.70 |
| EventDispatch | 1 / 0.13 | 83 / 32.82 | 59 / 27.67 | 100 / 23.45 |
| ObserverCallback | 12 / 107.62 | 7 / 4.62 | 8 / 2.90 | 8 / 4.71 |
| RenderingFrame | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 | 0 / 0.00 |

<!-- /gen:sim-kinds -->

<!-- gen:sim-cadence -->
| window | timeline | arm | reps n (per job) | hitches per rep (median) | p50 ms | p95 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| hero | on | orig | 6 (5+1) | 1 | 375.0 | 474.0 | 474.0 |
| hero | on | base | 7 (5+2) | 4 | 136.0 | 531.0 | 791.0 |
| hero | on | aa | 6 (5+1) | 5 | 165.0 | 529.0 | 759.0 |
| hero | on | look | 6 (5+1) | 6 | 156.0 | 573.0 | 638.0 |
| end | on | orig | 6 (5+1) | 4 | 437.0 | 627.0 | 805.0 |
| end | on | base | 6 (5+1) | 5 | 360.0 | 576.0 | 780.0 |
| end | on | aa | 6 (5+1) | 4 | 440.0 | 713.0 | 781.0 |
| end | on | look | 6 (5+1) | 5 | 388.0 | 520.0 | 1023.0 |
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
| 39634194664 | mac | webkit mac (playwright-webkit, macos-26) job 3 | cancelled | 15 | 16 |
| 39634194664 | sim | webkit sim (mobile safari, xcode-27) job 2 | success | 37.7 | 38 |
| 39634194664 | sim | webkit sim (mobile safari, xcode-27) job 3 | success | 31.8 | 32 |
| median of successes | mac |  | n=2 | 9.9 |  |
| longest success | mac |  |  | 10.7 |  |
| all jobs billed | mac |  | n=3 |  | 37 |
| median of successes | sim |  | n=2 | 34.8 |  |
| longest success | sim |  |  | 37.7 |  |
| all jobs billed | sim |  | n=3 |  | 94 |
<!-- /gen:minutes -->
