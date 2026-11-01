| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 6 | 0 | {} | {} | 6 | 6 | 7 2 3 3 4 6 | 13 3 5 5 8 12 | 48 4 70 22 41 56 | 48 4 70 22 41 56 | 7 2 3 3 4 6 | 52480 52580 52690 52280 52480 52280 | 48 4 70 22 41 55 | 0 |
| base | 6 | 0 | {} | {"tooShort":1} | 5 | 5 | 1 3 1 3 3 | 1 6 1 7 5 | 2 31 5 55 28 | 2 31 4 49 20 | 1 3 1 4 3 | 51980 52530 52170 51920 52280 | 2 31 4 49 20 | 0 |
| lock | 6 | 0 | {} | {} | 6 | 6 | 4 1 5 1 1 1 | 7 1 10 1 1 2 | 36 2 73 23 2 30 | 36 2 73 23 2 30 | 4 1 5 1 1 1 | 52240 52280 52320 51920 52220 52280 | 36 2 72 23 2 29 | 0 |
| pin | 6 | 0 | {} | {} | 6 | 0 | 0 0 0 0 0 0 | 1 0 0 0 1 1 | 0 0 0 0 0 9 | 0 0 0 0 0 5 | 0 0 0 0 0 0 | none none none none none 51890 | 0 0 0 0 0 1 | 5 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 53 | 1 | 1 | 2 | 2 | 51980 |
| 2 | lock | 0 | open |  | 67 | 7 | 4 | 36 | 36 | 52240 |
| 3 | pin | 0 | open |  | 46 | 1 | 0 | 0 | 0 | none |
| 4 | orig | 0 | open |  | 66 | 13 | 7 | 48 | 48 | 52480 |
| 5 | pin | 1 | open |  | 63 | 0 | 0 | 0 | 0 | none |
| 6 | lock | 1 | open |  | 72 | 1 | 1 | 2 | 2 | 52280 |
| 7 | base | 1 | refused | tooShort | 8 |  |  |  |  |  |
| 8 | orig | 1 | open |  | 65 | 3 | 2 | 4 | 4 | 52580 |
| 9 | base | 2 | open |  | 39 | 6 | 3 | 31 | 31 | 52530 |
| 10 | lock | 2 | open |  | 78 | 10 | 5 | 73 | 73 | 52320 |
| 11 | pin | 2 | open |  | 58 | 0 | 0 | 0 | 0 | none |
| 12 | orig | 2 | open |  | 77 | 5 | 3 | 70 | 70 | 52690 |
| 13 | pin | 3 | open |  | 11 | 0 | 0 | 0 | 0 | none |
| 14 | lock | 3 | open |  | 42 | 1 | 1 | 23 | 23 | 51920 |
| 15 | base | 3 | open |  | 41 | 1 | 1 | 5 | 4 | 52170 |
| 16 | orig | 3 | open |  | 27 | 5 | 3 | 22 | 22 | 52280 |
| 17 | base | 4 | open |  | 62 | 7 | 3 | 55 | 49 | 51920 |
| 18 | lock | 4 | open |  | 48 | 1 | 1 | 2 | 2 | 52220 |
| 19 | pin | 4 | open |  | 60 | 1 | 0 | 0 | 0 | none |
| 20 | orig | 4 | open |  | 47 | 8 | 4 | 41 | 41 | 52480 |
| 21 | pin | 5 | open |  | 68 | 1 | 0 | 9 | 5 | 51890 |
| 22 | lock | 5 | open |  | 31 | 2 | 1 | 30 | 30 | 52280 |
| 23 | base | 5 | open |  | 71 | 5 | 3 | 28 | 20 | 52280 |
| 24 | orig | 5 | open |  | 63 | 12 | 6 | 56 | 56 | 52280 |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 24 | 4 | 4 | 1 | 5 | 0 | 4 | 0 | 0 | 5 | yes |
| 5 | pin | 27 | 6 | 4 | 2 | 5 | 0 | 3 | 1 | 0 | 5 | yes |
| 11 | pin | 18 | 2 | 4 | 0 | 3 | 0 | 4 | 0 | 0 | 4 | yes |
| 13 | pin | 17 | 2 | 4 | 1 | 3 | 0 | 1 | 1 | 0 | 4 | yes |
| 19 | pin | 22 | 6 | 4 | 0 | 3 | 0 | 4 | 0 | 0 | 4 | yes |
| 21 | pin | 33 | 5 | 4 | 5 | 6 | 1 | 4 | 3 | 3 | 1 | yes |

lock vs base: fights overlap, restores overlap, event fights overlap; base vs orig: fights overlap, restores overlap; look class of the candidate: look change

pin vs base: fights undecided, restores undecided, event fights undecided; pin vs orig: fights undecided; look class of the pin: look change; pin writes: 5 of 6 runs never wrote (their fights are 0 by definition)
