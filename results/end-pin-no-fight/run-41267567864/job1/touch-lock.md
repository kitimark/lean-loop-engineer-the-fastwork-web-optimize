| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 6 | 0 | {} | {} | 6 | 5 | 2 0 1 1 1 1 | 3 0 2 1 2 2 | 23 1 27 32 2 16 | 23 1 27 32 1 16 | 2 0 1 1 0 1 | 52370 52270 52280 52580 52270 52280 | 23 1 26 32 1 15 | 0 |
| base | 6 | 0 | {} | {"tooShort":1} | 5 | 5 | 1 1 1 1 1 | 1 1 1 1 1 | 16 5 2 25 3 | 16 5 2 25 3 | 1 1 1 1 1 | 51990 52290 52220 52170 52580 | 16 5 2 25 3 | 0 |
| lock | 6 | 0 | {} | {} | 6 | 6 | 1 1 3 1 3 2 | 1 1 6 1 6 3 | 11 2 8 2 61 15 | 11 2 8 2 61 15 | 1 1 3 1 3 2 | 52390 52280 52690 52280 52580 52580 | 11 2 8 2 60 15 | 0 |
| pin | 6 | 6 | {"config":6} | {} | 0 | 0 |  |  |  |  |  |  |  | 0 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 72 | 1 | 1 | 16 | 16 | 51990 |
| 2 | lock | 0 | open |  | 70 | 1 | 1 | 11 | 11 | 52390 |
| 3 | pin | 0 | refused | config |  |  |  |  |  |  |
| 4 | orig | 0 | open |  | 69 | 3 | 2 | 23 | 23 | 52370 |
| 5 | pin | 1 | refused | config |  |  |  |  |  |  |
| 6 | lock | 1 | open |  | 39 | 1 | 1 | 2 | 2 | 52280 |
| 7 | base | 1 | refused | tooShort | 5 |  |  |  |  |  |
| 8 | orig | 1 | open |  | 50 | 0 | 0 | 1 | 1 | 52270 |
| 9 | base | 2 | open |  | 55 | 1 | 1 | 5 | 5 | 52290 |
| 10 | lock | 2 | open |  | 19 | 6 | 3 | 8 | 8 | 52690 |
| 11 | pin | 2 | refused | config |  |  |  |  |  |  |
| 12 | orig | 2 | open |  | 29 | 2 | 1 | 27 | 27 | 52280 |
| 13 | pin | 3 | refused | config |  |  |  |  |  |  |
| 14 | lock | 3 | open |  | 62 | 1 | 1 | 2 | 2 | 52280 |
| 15 | base | 3 | open |  | 66 | 1 | 1 | 2 | 2 | 52220 |
| 16 | orig | 3 | open |  | 50 | 1 | 1 | 32 | 32 | 52580 |
| 17 | base | 4 | open |  | 54 | 1 | 1 | 25 | 25 | 52170 |
| 18 | lock | 4 | open |  | 65 | 6 | 3 | 61 | 61 | 52580 |
| 19 | pin | 4 | refused | config |  |  |  |  |  |  |
| 20 | orig | 4 | open |  | 57 | 2 | 1 | 2 | 1 | 52270 |
| 21 | pin | 5 | refused | config |  |  |  |  |  |  |
| 22 | lock | 5 | open |  | 24 | 3 | 2 | 15 | 15 | 52580 |
| 23 | base | 5 | open |  | 37 | 1 | 1 | 3 | 3 | 52580 |
| 24 | orig | 5 | open |  | 18 | 2 | 1 | 16 | 16 | 52280 |

lock vs base: fights overlap, restores overlap, event fights overlap; base vs orig: fights overlap, restores overlap; look class of the candidate: look change

pin vs base: fights undecided, restores undecided, event fights undecided; pin vs orig: fights undecided; look class of the pin: undecided; pin writes: undecided
