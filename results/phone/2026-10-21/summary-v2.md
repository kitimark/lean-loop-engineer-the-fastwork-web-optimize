# Phone session 2026-10-21, second reduction

Reduced by Lean `Fw.Device.Stats.reduceV2` (TS twin checked against golden/device/session.jsonl). Safari draws the page at 60 Hz on this 120 Hz phone; a slot is 1/60 s counted from the first frame, and a skipped slot is an interval that advanced 2 slots or more. Hitch ms/s: time past the pass median interval per second, Apple Organizer bands (good up to 10, warning up to 25, critical up to 50, urgent above). rAF times are when the page started a frame, not when it reached the glass.

## Every interval, per zone

| zone | arm | pass | intervals | skipped / 100 | > 25 ms / 100 | > 34 ms / 100 | > 50 ms / 100 | hitch ms/s | band | p95 ms | longest 30 fps run |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| whole | original | 1 | 3733 | 25.50 | 24.99 | 16.01 | 7.28 | 334.7 | urgent | 63.0 | 53 |
| whole | rewrite | 1 | 5025 | 9.55 | 6.62 | 2.90 | 0.47 | 96.7 | urgent | 29.0 | 13 |
| whole | look | 1 | 5160 | 6.93 | 4.96 | 1.84 | 0.21 | 72.7 | urgent | 25.0 | 9 |
| whole | original | 2 | 4303 | 22.10 | 18.28 | 9.76 | 3.23 | 242.5 | urgent | 45.0 | 19 |
| hero | original | 1 | 2222 | 27.63 | 28.12 | 19.57 | 9.22 | 371.7 | urgent | 69.0 | 52 |
| hero | rewrite | 1 | 1808 | 6.08 | 3.65 | 0.99 | 0.00 | 46.9 | critical | 23.0 | 3 |
| hero | look | 1 | 2004 | 5.13 | 4.34 | 1.24 | 0.00 | 55.1 | urgent | 25.0 | 3 |
| hero | original | 2 | 1771 | 24.05 | 21.68 | 11.74 | 5.02 | 281.4 | urgent | 51.0 | 18 |
| finish | original | 1 | 807 | 21.68 | 18.95 | 8.67 | 1.23 | 219.3 | urgent | 41.0 | 7 |
| finish | rewrite | 1 | 1237 | 21.18 | 16.57 | 8.73 | 1.85 | 213.3 | urgent | 42.0 | 13 |
| finish | look | 1 | 2051 | 9.41 | 6.72 | 2.77 | 0.39 | 96.3 | urgent | 29.0 | 9 |
| finish | original | 2 | 1455 | 18.62 | 14.77 | 7.76 | 1.85 | 194.7 | urgent | 40.0 | 15 |
| rest | original | 1 | 704 | 23.15 | 22.01 | 13.21 | 8.09 | 327.1 | urgent | 62.0 | 28 |
| rest | rewrite | 1 | 1980 | 5.45 | 3.13 | 1.01 | 0.05 | 53.5 | urgent | 24.0 | 3 |
| rest | look | 1 | 1105 | 5.61 | 2.80 | 1.17 | 0.27 | 58.1 | urgent | 23.0 | 2 |
| rest | original | 2 | 1077 | 23.58 | 17.45 | 9.19 | 2.13 | 238.0 | urgent | 43.0 | 15 |

## Intervals in which the page scrolled or a recorded part changed

| zone | arm | pass | intervals | skipped / 100 | > 25 ms / 100 | > 34 ms / 100 | > 50 ms / 100 | hitch ms/s | band | p95 ms | longest 30 fps run |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| whole | original | 1 | 1216 | 45.47 | 45.97 | 30.34 | 16.94 | 500.6 | urgent | 89.0 | 36 |
| whole | rewrite | 1 | 2368 | 11.35 | 7.81 | 3.58 | 0.67 | 113.7 | urgent | 30.0 | 10 |
| whole | look | 1 | 2080 | 9.95 | 7.11 | 2.88 | 0.43 | 102.2 | urgent | 29.0 | 8 |
| whole | original | 2 | 1397 | 42.87 | 39.15 | 23.69 | 9.01 | 406.1 | urgent | 59.0 | 19 |
| hero | original | 1 | 485 | 63.29 | 66.18 | 48.24 | 29.27 | 614.4 | urgent | 99.0 | 35 |
| hero | rewrite | 1 | 841 | 7.72 | 4.16 | 1.30 | 0.00 | 55.0 | urgent | 25.0 | 3 |
| hero | look | 1 | 768 | 7.16 | 4.94 | 2.47 | 0.00 | 75.2 | urgent | 25.0 | 3 |
| hero | original | 2 | 489 | 53.78 | 54.19 | 35.37 | 17.17 | 502.9 | urgent | 71.0 | 18 |
| finish | original | 1 | 266 | 36.84 | 34.21 | 16.54 | 3.00 | 330.9 | urgent | 47.0 | 7 |
| finish | rewrite | 1 | 447 | 28.85 | 24.16 | 13.64 | 3.35 | 280.4 | urgent | 46.0 | 10 |
| finish | look | 1 | 483 | 21.11 | 18.21 | 6.62 | 1.24 | 195.3 | urgent | 38.0 | 8 |
| finish | original | 2 | 353 | 35.97 | 33.71 | 18.13 | 5.38 | 340.4 | urgent | 51.0 | 12 |
| rest | original | 1 | 465 | 31.82 | 31.61 | 19.56 | 12.04 | 407.4 | urgent | 82.0 | 28 |
| rest | rewrite | 1 | 1080 | 6.94 | 3.88 | 1.20 | 0.09 | 67.6 | urgent | 25.0 | 3 |
| rest | look | 1 | 829 | 6.03 | 2.65 | 1.08 | 0.36 | 62.7 | urgent | 24.0 | 2 |
| rest | original | 2 | 555 | 37.65 | 29.36 | 16.93 | 4.14 | 335.4 | urgent | 48.0 | 15 |

## Verdict against the original passes (every interval)

| metric | zone | original | spread | arm | arm passes | verdict |
| --- | --- | --- | --- | --- | --- | --- |
| skipped / 100 | whole | 25.50 / 22.10 | 3.40 | rewrite | 9.55 | beats |
| skipped / 100 | whole | 25.50 / 22.10 | 3.40 | look | 6.93 | beats |
| skipped / 100 | hero | 27.63 / 24.05 | 3.58 | rewrite | 6.08 | beats |
| skipped / 100 | hero | 27.63 / 24.05 | 3.58 | look | 5.13 | beats |
| skipped / 100 | finish | 21.68 / 18.62 | 3.06 | rewrite | 21.18 | same |
| skipped / 100 | finish | 21.68 / 18.62 | 3.06 | look | 9.41 | beats |
| skipped / 100 | rest | 23.15 / 23.58 | 0.43 | rewrite | 5.45 | beats |
| skipped / 100 | rest | 23.15 / 23.58 | 0.43 | look | 5.61 | beats |
| hitch ms/s | whole | 334.7 / 242.5 | 92.2 | rewrite | 96.7 | beats |
| hitch ms/s | whole | 334.7 / 242.5 | 92.2 | look | 72.7 | beats |
| hitch ms/s | hero | 371.7 / 281.4 | 90.3 | rewrite | 46.9 | beats |
| hitch ms/s | hero | 371.7 / 281.4 | 90.3 | look | 55.1 | beats |
| hitch ms/s | finish | 219.3 / 194.7 | 24.6 | rewrite | 213.3 | same |
| hitch ms/s | finish | 219.3 / 194.7 | 24.6 | look | 96.3 | beats |
| hitch ms/s | rest | 327.1 / 238.0 | 89.1 | rewrite | 53.5 | beats |
| hitch ms/s | rest | 327.1 / 238.0 | 89.1 | look | 58.1 | beats |

## First traversal against later ones (every interval)

| arm | pass | part | intervals | skipped / 100 | > 25 ms / 100 | hitch ms/s | p95 ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| original | 1 | first | 1073 | 15.84 | 14.81 | 211.6 | 43.0 |
| original | 1 | later | 2660 | 29.39 | 29.09 | 373.0 | 68.0 |
| rewrite | 1 | first | 1227 | 3.58 | 2.60 | 38.6 | 21.0 |
| rewrite | 1 | later | 3798 | 11.47 | 7.92 | 114.2 | 31.0 |
| look | 1 | first | 501 | 5.18 | 4.39 | 59.7 | 25.0 |
| look | 1 | later | 4659 | 7.12 | 5.02 | 74.1 | 26.0 |
| original | 2 | first | 1458 | 13.44 | 10.08 | 151.2 | 33.0 |
| original | 2 | later | 2845 | 26.53 | 22.49 | 281.3 | 49.0 |

## Felt marks, window of 3 s before the first tap, every interval

| arm | marks | first window counted nothing | new window empty | with a skipped slot | with > 25 ms | with > 34 ms | with > 50 ms | window skipped / 100, median | pass skipped / 100 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| original | 31 | 5 | 0 | 31 | 31 | 31 | 29 | 32.52 | 25.50 / 22.10 |
| rewrite | 10 | 5 | 0 | 10 | 10 | 10 | 3 | 6.85 | 9.55 |
| look | 22 | 10 | 0 | 22 | 22 | 16 | 9 | 7.18 | 6.93 |

## Touch

| arm | pass | drags | from a still page | touch to first moving frame, median ms | p95 ms | max ms | page moved before lift | finger offset median px | p95 px | max px |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| original | 1 | 34 | 9 | 105.0 | 158.0 | 158.0 | 13 | 12.4 | 177.4 | 177.4 |
| rewrite | 1 | 32 | 12 | 117.0 | 158.0 | 158.0 | 17 | 0.0 | 113.6 | 113.6 |
| look | 1 | 33 | 11 | 91.0 | 126.0 | 126.0 | 19 | 24.3 | 171.0 | 171.0 |
| original | 2 | 45 | 13 | 97.0 | 128.0 | 128.0 | 25 | 0.0 | 48.0 | 144.6 |

## Reading notes

- A 3 s felt window holds about 180 intervals. At the pass rates above nearly every window has a skipped slot, so compare the window rate with the pass rate.
- "Animating" keeps a frame when the scroll position or a recorded part (hero, people, fade) changed. The morph tween under scroll lock is not a recorded part; its frames are only in "every interval".
- A drag is a stroke that is not a tap, with one finger. Touch latency counts drags that started on a still page and scrolled it before the finger lifted. The finger offset counts the drags in "page moved before lift".
- The expected interval is the pass median at the 1 ms rAF rounding, so a 16 / 17 ms alternation adds no hitch time.
