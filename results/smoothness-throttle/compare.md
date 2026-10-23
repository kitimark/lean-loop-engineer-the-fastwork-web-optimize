Rate = bad frames (gap above 34 ms between rAF callbacks) per frame, percent, median over the job samples (range in brackets). Hitches = frames over 60 ms per repeat (median over all repeats). p50 and p95 are interval quantiles in ms (median over jobs).

| width | window | arm | jobs | rate % 1x | rate % 6x | hitches/rep 1x | hitches/rep 6x | p50 ms 1x / 6x | p95 ms 1x / 6x |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | hero | orig | 3 / 3 | 0.0 (0.0-0.0) | 26.4 (11.7-41.6) | 0 | 9 | 16.7 / 33.3 | 16.8 / 66.6 |
| 390 | hero | base | 3 / 3 | 0.6 (0.6-0.6) | 25.7 (11.3-42.4) | 1 | 9 | 16.7 / 33.3 | 16.8 / 66.7 |
| 390 | hero | aa | 3 / 3 | 0.6 (0.6-0.7) | 27.6 (12.5-42.3) | 1 | 9 | 16.7 / 33.3 | 16.8 / 66.6 |
| 390 | hero | cand | 3 / 3 | 0.6 (0.6-0.7) | 26.3 (12.2-43.3) | 1 | 9 | 16.7 / 33.3 | 16.8 / 66.6 |
| 390 | end | orig | 3 / 3 | 0.7 (0.7-1.0) | 28.9 (23.4-34.3) | 0 | 11 | 16.7 / 16.7 | 16.8 / 83.3 |
| 390 | end | base | 3 / 3 | 0.7 (0.5-0.9) | 32.0 (22.3-37.8) | 0 | 10 | 16.7 / 16.7 | 16.8 / 66.7 |
| 390 | end | aa | 3 / 3 | 0.7 (0.6-0.9) | 26.5 (20.4-39.3) | 0 | 11 | 16.7 / 16.7 | 16.8 / 66.7 |
| 390 | end | cand | 3 / 3 | 0.7 (0.6-0.8) | 24.1 (19.0-31.6) | 0 | 10 | 16.7 / 16.7 | 16.8 / 66.7 |
| 1280 | hero | orig | 3 / 3 | 4.4 (4.0-5.3) | 22.1 (19.9-25.5) | 0 | 10 | 16.7 / 33.3 | 33.4 / 66.7 |
| 1280 | hero | base | 3 / 3 | 4.8 (4.6-5.4) | 24.7 (19.3-27.1) | 0 | 9 | 16.7 / 33.3 | 33.4 / 66.7 |
| 1280 | hero | aa | 3 / 3 | 5.1 (4.9-5.7) | 25.0 (18.6-25.8) | 0 | 8 | 16.7 / 33.3 | 49.9 / 66.6 |
| 1280 | hero | cand | 3 / 3 | 5.0 (4.5-5.3) | 25.3 (17.3-25.9) | 0 | 9 | 16.7 / 33.3 | 33.5 / 66.6 |
| 1280 | end | orig | 3 / 3 | 17.6 (17.6-19.7) | 41.1 (30.9-42.6) | 4 | 14 | 33.3 / 33.4 | 50.1 / 100.0 |
| 1280 | end | base | 3 / 3 | 18.6 (17.8-18.6) | 47.5 (37.9-47.9) | 4 | 15 | 33.3 / 33.4 | 66.6 / 100.0 |
| 1280 | end | aa | 3 / 3 | 19.4 (17.8-20.8) | 46.1 (35.8-51.3) | 3 | 15 | 33.3 / 33.4 | 50.1 / 100.0 |
| 1280 | end | cand | 3 / 3 | 16.5 (16.2-20.1) | 43.4 (34.3-46.8) | 3 | 13 | 33.3 / 33.4 | 66.6 / 99.9 |

Pair verdicts over the job samples (Lean `acrossDecisive`; rate rule and hitch rule; the A/A spread is the larger of base against aa and the spread inside either, in points):

| width | window | pair | 1x rate rule | 1x hitch rule | 1x A/A spread | 6x rate rule | 6x hitch rule | 6x A/A spread |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 390 | end | orig vs base | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 1.7 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 14.8 |
| 390 | end | base vs cand | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 1.7 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 14.8 |
| 390 | end | orig vs cand | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 1.7 | not told apart (0/0/3/0) | not told apart (0/1/2/0) | 14.8 |
| 390 | hero | orig vs base | first smoother (2/0/1/0) | first smoother (3/0/0/0) | 0.0 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 11.5 |
| 390 | hero | base vs cand | not told apart (1/0/2/0) | not told apart (0/0/3/0) | 0.0 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 11.5 |
| 390 | hero | orig vs cand | first smoother (2/0/1/0) | first smoother (3/0/0/0) | 0.0 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 11.5 |
| 1280 | end | orig vs base | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 7.8 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 10.0 |
| 1280 | end | base vs cand | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 7.8 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 10.0 |
| 1280 | end | orig vs cand | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 7.8 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 10.0 |
| 1280 | hero | orig vs base | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 1.3 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 6.6 |
| 1280 | hero | base vs cand | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 1.3 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 6.6 |
| 1280 | hero | orig vs cand | not told apart (1/0/2/0) | not told apart (0/0/3/0) | 1.3 | not told apart (0/0/3/0) | not told apart (0/0/3/0) | 6.6 |

Counts in brackets: samples saying first / second / same / insufficient.
