Arms: original (3/3 passes with the cost counters), rewrite (6/6 passes with the cost counters). Cells are per-pass ranges.

#### Frame cadence (rAF intervals; slot = round((t - t0) / 16.67 ms), skipped when it jumps more than one)

| zone | arm | frames | skipped slots events / 100 frames | slots lost / 100 frames | > 25 ms / 100 frames | > 50 ms / 100 frames | skipped100 vs original |
|---|---|---:|---:|---:|---:|---:|---|
| hero exit (scroll A) | original | 32 | 71.9-84.4 | 191-306 | 75.0-84.4 | 31.3-56.3 |  |
| hero exit (scroll A) | rewrite | 32 | 59.4-87.5 | 213-553 | 59.4-93.8 | 28.1-53.1 | overlap |
| end of page (scroll B) | original | 34 | 44.1-70.6 | 76.5-147 | 44.1-70.6 | 11.8-32.4 |  |
| end of page (scroll B) | rewrite | 32-34 | 47.1-100 | 82.4-532 | 47.1-100 | 8.8-88.2 | overlap |
| calm scroll (baseline) | original | 88 | 33.0-44.3 | 76.1-95.5 | 30.7-37.5 | 10.2-14.8 |  |
| calm scroll (baseline) | rewrite | 86-88 | 36.0-70.5 | 76.7-294 | 26.7-69.3 | 9.1-36.4 | overlap |
| morph idle (baseline) | original | 9-10 | 44.4-88.9 | 44.4-133 | 33.3-88.9 | 0.0 |  |
| morph idle (baseline) | rewrite | 9-10 | 30.0-90.0 | 30.0-211 | 20.0-90.0 | 0.0-22.2 | overlap |
| morph open (push down) | original | 3-4 | 75.0-100 | 475-967 | 100 | 50.0-66.7 |  |
| morph open (push down) | rewrite | 1-4 | 100 | 100-1033 | 100 | 0.0-100 | overlap |
| morph close (push up) | original | 5 | 80.0-100 | 620-740 | 100 | 60.0-80.0 |  |
| morph close (push up) | rewrite | 1-5 | 80.0-100 | 600-1600 | 100 | 50.0-100 | overlap |
| morph rest | original | 29-64 | 68.8-100 | 147-383 | 73.4-100 | 9.4-51.7 |  |
| morph rest | rewrite | 13-56 | 82.6-100 | 177-1462 | 76.1-100 | 12.5-100 | overlap |

#### rAF interval histogram (% of intervals per bin; bin edges from Lean `histEdges`)

| zone | arm | <= 12 ms | 12-20 ms | 20-25 ms | 25-34 ms | 34-50 ms | 50-100 ms | > 100 ms | h6 vs original |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| hero exit (scroll A) | original | 0 | 0-6 | 6-23 | 13-42 | 3-16 | 16-39 | 13-19 |  |
| hero exit (scroll A) | rewrite | 0-6 | 0-23 | 3-16 | 10-39 | 6-32 | 3-26 | 13-35 | overlap |
| end of page (scroll B) | original | 3-12 | 21-35 | 6-15 | 15-18 | 15-21 | 12-32 | 0 |  |
| end of page (scroll B) | rewrite | 0-9 | 0-41 | 0-16 | 0-26 | 12-31 | 9-41 | 0-47 | overlap |
| calm scroll (baseline) | original | 2-7 | 44-50 | 9-18 | 13-14 | 7-10 | 7-11 | 3 |  |
| calm scroll (baseline) | rewrite | 0-8 | 11-45 | 8-21 | 14-24 | 3-20 | 6-20 | 2-16 | overlap |
| morph idle (baseline) | original | 0 | 0-13 | 0-50 | 0-38 | 0-100 | 0 | 0 |  |
| morph idle (baseline) | rewrite | 0 | 0-33 | 0-44 | 0-38 | 0-89 | 0-25 | 0-13 | overlap |
| morph open (push down) | original | 0 | 0 | 0 | 0-25 | 25-50 | 0-25 | 25-67 |  |
| morph open (push down) | rewrite | 0 | 0 | 0 | 0-100 | 0-50 | 0-50 | 0-67 | overlap |
| morph close (push up) | original | 0 | 0 | 0 | 0-40 | 0-20 | 0-20 | 60 |  |
| morph close (push up) | rewrite | 0 | 0 | 0 | 0-50 | 0-50 | 0 | 50-100 | overlap |
| morph rest | original | 0 | 0-8 | 0-19 | 3-55 | 9-45 | 3-38 | 6-14 |  |
| morph rest | rewrite | 0 | 0 | 0-24 | 0-48 | 0-61 | 5-38 | 7-62 | overlap |

#### Paint against Composite per frame (Timeline durations, microseconds; the Inspector files raster under Composite)

| zone | arm | Paint us / frame | Composite us / frame | Composite > Paint, % of frames | compPF vs original |
|---|---|---:|---:|---:|---|
| hero exit (scroll A) | original | 2387-2857 | 28627-41033 | 100 |  |
| hero exit (scroll A) | rewrite | 2194-3691 | 32259-79628 | 100 | overlap |
| end of page (scroll B) | original | 882-1198 | 18156-28411 | 97 |  |
| end of page (scroll B) | rewrite | 823-3626 | 18283-85236 | 97 | overlap |
| calm scroll (baseline) | original | 774-893 | 15974-17930 | 100 |  |
| calm scroll (baseline) | rewrite | 640-1383 | 14731-37906 | 100 | overlap |
| morph idle (baseline) | original | 701-801 | 20094-36800 | 100 |  |
| morph idle (baseline) | rewrite | 816-1856 | 18247-49279 | 100 | overlap |
| morph open (push down) | original | 5755-17600 | 131978-204788 | 100 |  |
| morph open (push down) | rewrite | 4242-52838 | 145246-755624 | 100 | overlap |
| morph close (push up) | original | 1896-2612 | 103319-144682 | 100 |  |
| morph close (push up) | rewrite | 2311-4648 | 99078-374922 | 100 | overlap |
| morph rest | original | 1020-1151 | 26096-54936 | 97-98 |  |
| morph rest | rewrite | 835-6251 | 32246-132859 | 92-98 | overlap |

#### Layers between layer-tree reads (new layer = id not in the previous read; resized = composited width or height changed)

| zone | arm | reads | new layers / 100 reads | resized layers / 100 reads | fresh100 vs original |
|---|---|---:|---:|---:|---|
| hero exit (scroll A) | original | 32 | 109-128 | 87.5-93.8 |  |
| hero exit (scroll A) | rewrite | 32 | 131-222 | 87.5-103 | higher |
| end of page (scroll B) | original | 32-34 | 46.9-90.6 | 0.0-3.1 |  |
| end of page (scroll B) | rewrite | 32-34 | 56.3-84.4 | 0.0 | overlap |
| calm scroll (baseline) | original | 86-88 | 60.2-73.3 | 14.0-22.7 |  |
| calm scroll (baseline) | rewrite | 86-88 | 60.2-93.0 | 5.8-11.4 | overlap |
| morph open (push down) | original | 3-4 | 2075-2767 | 833-975 |  |
| morph open (push down) | rewrite | 1-4 | 2075-8100 | 975-1250 | overlap |
| morph close (push up) | original | 1-3 | 0.0 | 1000-1300 |  |
| morph close (push up) | rewrite | 1 | 0.0 | 1400 | overlap |
| morph rest | original | 9-21 | 0.0-4.8 | 143-267 |  |
| morph rest | rewrite | 1-18 | 0.0-42.9 | 194-867 | overlap |

#### Paint records after a morph ends (early: 0-500 ms after the tween end, late: 500-1000 ms)

| morph | arm | early | late | early vs original |
|---|---|---:|---:|---|
| morph open (push down) | original | 90-111 | 18-41 |  |
| morph open (push down) | rewrite | 44-110 | 22-100 | overlap |
| morph close (push up) | original | 51-90 | 66-86 |  |
| morph close (push up) | rewrite | 40-108 | 41-81 | overlap |

cli: exit 0
