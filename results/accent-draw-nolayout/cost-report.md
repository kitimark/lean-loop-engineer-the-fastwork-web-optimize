Arms: original (6/6 passes with the cost counters), rewrite (4/4 passes with the cost counters). Cells are per-pass ranges.

#### Frame cadence (rAF intervals; slot = round((t - t0) / 16.67 ms), skipped when it jumps more than one)

| zone | arm | frames | skipped slots events / 100 frames | slots lost / 100 frames | > 25 ms / 100 frames | > 50 ms / 100 frames | skipped100 vs original |
|---|---|---:|---:|---:|---:|---:|---|
| hero exit (scroll A) | original | 32 | 34.4-50.0 | 96.9-241 | 34.4-43.8 | 15.6-25.0 |  |
| hero exit (scroll A) | rewrite | 32 | 31.3-53.1 | 87.5-197 | 28.1-43.8 | 15.6-28.1 | overlap |
| end of page (scroll B) | original | 32-34 | 50.0-88.2 | 73.5-300 | 47.1-88.2 | 11.8-55.9 |  |
| end of page (scroll B) | rewrite | 32-34 | 59.4-97.1 | 84.4-368 | 43.8-97.1 | 12.5-52.9 | overlap |
| calm scroll (baseline) | original | 86-88 | 40.9-63.6 | 87.5-169 | 31.8-63.6 | 11.4-25.0 |  |
| calm scroll (baseline) | rewrite | 86-88 | 43.2-68.2 | 100-141 | 39.8-63.6 | 17.0-22.7 | overlap |
| morph idle (baseline) | original | 9-10 | 33.3-90.0 | 33.3-167 | 0.0-88.9 | 0.0-33.3 |  |
| morph idle (baseline) | rewrite | 9-10 | 60.0-88.9 | 60.0-144 | 60.0-88.9 | 0.0-11.1 | overlap |
| morph open (push down) | original | 3-4 | 75.0-100 | 550-900 | 75.0-100 | 50.0-75.0 |  |
| morph open (push down) | rewrite | 3-4 | 100 | 867-1067 | 100 | 50.0-100 | overlap |
| morph close (push up) | original | 5-6 | 80.0-100 | 560-740 | 80.0-100 | 60.0-80.0 |  |
| morph close (push up) | rewrite | 3-5 | 100 | 680-833 | 80.0-100 | 60.0-80.0 | overlap |
| morph rest | original | 54-65 | 66.1-85.2 | 131-196 | 64.5-96.3 | 8.1-13.0 |  |
| morph rest | rewrite | 27-60 | 75.0-100 | 145-463 | 78.3-100 | 10.0-59.3 | overlap |

#### rAF interval histogram (% of intervals per bin; bin edges from Lean `histEdges`)

| zone | arm | <= 12 ms | 12-20 ms | 20-25 ms | 25-34 ms | 34-50 ms | 50-100 ms | > 100 ms | h6 vs original |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| hero exit (scroll A) | original | 0-13 | 29-52 | 10-13 | 3-13 | 6-10 | 6-19 | 6-16 |  |
| hero exit (scroll A) | rewrite | 3-10 | 29-58 | 10-26 | 3-16 | 3-10 | 6-13 | 6-19 | overlap |
| end of page (scroll B) | original | 0-12 | 3-26 | 3-16 | 6-29 | 21-47 | 12-41 | 0-21 |  |
| end of page (scroll B) | rewrite | 0-6 | 3-34 | 0-16 | 12-32 | 12-32 | 13-41 | 0-12 | overlap |
| calm scroll (baseline) | original | 2-6 | 18-40 | 10-23 | 10-25 | 8-17 | 8-18 | 3-7 |  |
| calm scroll (baseline) | rewrite | 1-7 | 20-42 | 14-26 | 16-22 | 2-20 | 9-18 | 5-9 | overlap |
| morph idle (baseline) | original | 0 | 0-13 | 0-88 | 0-75 | 0-63 | 0-38 | 0 |  |
| morph idle (baseline) | rewrite | 0 | 0 | 0-33 | 0-78 | 0-88 | 0-13 | 0 | overlap |
| morph open (push down) | original | 0 | 0 | 0-25 | 0-50 | 0-50 | 0 | 50-75 |  |
| morph open (push down) | rewrite | 0 | 0 | 0 | 0-33 | 0-50 | 0-33 | 50-67 | overlap |
| morph close (push up) | original | 0 | 0 | 0-20 | 0-40 | 0-17 | 0-20 | 50-80 |  |
| morph close (push up) | rewrite | 0 | 0 | 0-20 | 0-20 | 0-33 | 0-33 | 33-60 | overlap |
| morph rest | original | 0 | 0-7 | 4-34 | 36-59 | 8-26 | 4-6 | 3-7 |  |
| morph rest | rewrite | 0 | 0-2 | 0-20 | 0-58 | 10-41 | 5-41 | 5-19 | overlap |

#### Paint against Composite per frame (Timeline durations, microseconds; the Inspector files raster under Composite)

| zone | arm | Paint us / frame | Composite us / frame | Composite > Paint, % of frames | compPF vs original |
|---|---|---:|---:|---:|---|
| hero exit (scroll A) | original | 1329-2025 | 20715-40219 | 100 |  |
| hero exit (scroll A) | rewrite | 1148-2173 | 18952-33077 | 100 | overlap |
| end of page (scroll B) | original | 558-3251 | 17842-48207 | 97 |  |
| end of page (scroll B) | rewrite | 600-26710 | 17031-64071 | 97 | overlap |
| calm scroll (baseline) | original | 754-1252 | 16699-27474 | 100 |  |
| calm scroll (baseline) | rewrite | 745-1134 | 17226-22760 | 100 | overlap |
| morph idle (baseline) | original | 746-1143 | 17807-40906 | 100 |  |
| morph idle (baseline) | rewrite | 700-1070 | 22396-38393 | 100 | overlap |
| morph open (push down) | original | 3674-24062 | 123880-191310 | 100 |  |
| morph open (push down) | rewrite | 3790-12295 | 162065-196162 | 100 | overlap |
| morph close (push up) | original | 1673-2363 | 89190-121989 | 100 |  |
| morph close (push up) | rewrite | 2020-2522 | 105219-197866 | 100 | overlap |
| morph rest | original | 975-1135 | 26626-32603 | 98 |  |
| morph rest | rewrite | 899-1168 | 26944-61753 | 96-98 | overlap |

#### Layers between layer-tree reads (new layer = id not in the previous read; resized = composited width or height changed)

| zone | arm | reads | new layers / 100 reads | resized layers / 100 reads | fresh100 vs original |
|---|---|---:|---:|---:|---|
| hero exit (scroll A) | original | 32 | 106-144 | 81.3-106 |  |
| hero exit (scroll A) | rewrite | 32 | 122-125 | 75.0-113 | overlap |
| end of page (scroll B) | original | 32-34 | 52.9-85.3 | 0.0 |  |
| end of page (scroll B) | rewrite | 32-34 | 44.1-106 | 0.0 | overlap |
| calm scroll (baseline) | original | 86-88 | 59.1-84.9 | 5.8-12.5 |  |
| calm scroll (baseline) | rewrite | 86-88 | 54.7-62.8 | 12.8-22.7 | overlap |
| morph open (push down) | original | 2-4 | 2075-4150 | 833-1300 |  |
| morph open (push down) | rewrite | 1-3 | 2767-8100 | 1100-1250 | overlap |
| morph close (push up) | original | 1-2 | 0.0 | 1050-1400 |  |
| morph close (push up) | rewrite | 1 | 0.0 | 1400 | overlap |
| morph rest | original | 4-19 | 0.0-27.3 | 165-650 |  |
| morph rest | rewrite | 1-3 | 0.0-200 | 1100-1400 | overlap |

#### Paint records after a morph ends (early: 0-500 ms after the tween end, late: 500-1000 ms)

| morph | arm | early | late | early vs original |
|---|---|---:|---:|---|
| morph open (push down) | original | 93-111 | 30-40 |  |
| morph open (push down) | rewrite | 90-110 | 12-36 | overlap |
| morph close (push up) | original | 70-124 | 86-101 |  |
| morph close (push up) | rewrite | 59-98 | 62-94 | overlap |

cli: exit 0
