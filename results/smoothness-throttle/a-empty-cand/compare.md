Rate = bad frames (gap above 34 ms between rAF callbacks) per frame, percent, median over the job samples (range in brackets). Hitches = frames over 60 ms per repeat (median over all repeats). p50 and p95 are interval quantiles in ms (median over jobs).

| width | window | arm | jobs | rate % 1x | rate % 6x | hitches/rep 1x | hitches/rep 6x | p50 ms 1x / 6x | p95 ms 1x / 6x |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | hero | orig | 3 / 3 | 0.0 (0.0-0.0) | 37.5 (31.5-39.0) | 0 | 10 | 16.7 / 33.4 | 16.8 / 66.7 |
| 390 | hero | base | 3 / 3 | 0.6 (0.6-0.7) | 38.8 (31.4-40.5) | 1 | 11 | 16.7 / 33.4 | 16.8 / 66.7 |
| 390 | hero | aa | 3 / 3 | 0.6 (0.6-0.7) | 38.4 (34.1-41.6) | 1 | 13 | 16.7 / 33.4 | 16.8 / 66.7 |
| 390 | hero | cand | 3 / 3 | 0.6 (0.6-0.7) | 37.2 (34.8-37.7) | 1 | 12 | 16.7 / 33.4 | 16.8 / 66.7 |
| 390 | end | orig | 3 / 3 | 0.5 (0.5-1.1) | 32.6 (30.7-34.2) | 0 | 13 | 16.7 / 16.7 | 33.2 / 83.4 |
| 390 | end | base | 3 / 3 | 1.0 (1.0-1.3) | 33.8 (31.9-37.4) | 1 | 11 | 16.7 / 33.3 | 16.8 / 83.3 |
| 390 | end | aa | 3 / 3 | 0.9 (0.9-1.2) | 34.9 (34.7-38.0) | 1 | 11 | 16.7 / 33.3 | 16.8 / 83.3 |
| 390 | end | cand | 3 / 3 | 0.9 (0.8-1.2) | 33.1 (32.4-35.1) | 1 | 11 | 16.7 / 33.3 | 16.8 / 83.3 |
| 1280 | hero | orig | 3 / 3 | 2.9 (2.9-4.5) | 24.4 (22.9-29.6) | 0 | 13 | 16.7 / 33.3 | 33.4 / 66.7 |
| 1280 | hero | base | 3 / 3 | 3.8 (3.4-4.9) | 25.7 (24.5-29.5) | 0 | 9 | 16.7 / 33.3 | 33.4 / 66.6 |
| 1280 | hero | aa | 3 / 3 | 3.7 (3.4-5.2) | 25.4 (23.6-29.7) | 0 | 9 | 16.7 / 33.3 | 33.4 / 66.6 |
| 1280 | hero | cand | 3 / 3 | 3.9 (3.6-4.8) | 24.4 (23.3-29.6) | 0 | 10 | 16.7 / 33.3 | 33.4 / 66.7 |
| 1280 | end | orig | 3 / 3 | 14.0 (13.3-17.5) | 38.0 (37.9-47.3) | 3 | 14 | 33.2 / 33.3 | 50.1 / 100.0 |
| 1280 | end | base | 3 / 3 | 15.5 (13.5-16.4) | 46.9 (46.8-55.3) | 3 | 16 | 16.8 / 33.4 | 50.1 / 100.0 |
| 1280 | end | aa | 3 / 3 | 14.6 (13.4-17.4) | 48.9 (42.4-53.8) | 3 | 16 | 16.8 / 33.4 | 50.0 / 100.0 |
| 1280 | end | cand | 3 / 3 | 15.0 (14.6-18.4) | 47.6 (46.8-50.8) | 3 | 16 | 33.2 / 33.4 | 50.1 / 100.0 |

Pair verdicts over the job samples (Lean `acrossDecisive`; rate rule and hitch rule; the A/A spread is the larger of base against aa and the spread inside either, in points):

| width | window | pair | 1x rate rule | 1x hitch rule | 1x A/A spread | 6x rate rule | 6x hitch rule | 6x A/A spread |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig vs base | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 0.8 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 14.4 |
| 390 | end | base vs cand | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 0.8 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 14.4 |
| 390 | end | orig vs cand | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 0.8 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 14.4 |
| 390 | hero | orig vs base | first smoother (2/0/1/0) | first smoother (3/0/0/0) | 0.6 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 16.3 |
| 390 | hero | base vs cand | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 0.6 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 16.3 |
| 390 | hero | orig vs cand | first smoother (2/0/1/0) | first smoother (3/0/0/0) | 0.6 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 16.3 |
| 1280 | end | orig vs base | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 5.0 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 14.5 |
| 1280 | end | base vs cand | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 5.0 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 14.5 |
| 1280 | end | orig vs cand | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 5.0 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 14.5 |
| 1280 | hero | orig vs base | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 1.3 | not told apart (0/0/3/0) | not told apart (0/1/2/0) | 5.0 |
| 1280 | hero | base vs cand | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 1.3 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 5.0 |
| 1280 | hero | orig vs cand | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 1.3 | not told apart (0/0/3/0) | not told apart (0/1/2/0) | 5.0 |

Counts in brackets: samples saying first / second / same / insufficient.
