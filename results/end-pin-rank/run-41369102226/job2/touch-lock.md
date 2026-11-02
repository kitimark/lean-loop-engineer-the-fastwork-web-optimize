| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 6 | 0 | {} | {} | 6 | 6 | 2 3 2 2 1 2 | 3 6 3 3 1 3 | 13 64 49 5 3 20 | 13 64 49 5 3 20 | 2 3 2 2 1 2 | 52930 52290 52580 52280 52280 52530 | 13 63 49 5 3 20 | 0 |
| base | 6 | 1 | {"pageLost":1} | {} | 5 | 5 | 2 3 2 4 1 | 4 6 3 7 1 | 55 55 6 21 39 | 55 55 6 21 39 | 2 3 2 4 1 | 52540 52580 52530 52280 52610 | 54 54 6 21 39 | 0 |
| lock | 6 | 0 | {} | {"tooShort":1} | 5 | 5 | 1 1 2 1 2 | 1 1 3 1 4 | 6 13 58 5 59 | 6 13 58 5 59 | 1 1 2 1 2 | 52580 52480 52580 52280 52220 | 6 13 58 5 58 | 0 |
| pin | 6 | 0 | {} | {} | 6 | 0 | 0 0 0 0 0 0 | 0 0 1 1 1 0 | 0 3 9 0 0 0 | 0 3 5 0 0 0 | 0 0 0 0 0 0 | none 51850 52250 none none none | 0 1 1 0 0 0 | 4 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 58 | 4 | 2 | 55 | 55 | 52540 |
| 2 | lock | 0 | open |  | 78 | 1 | 1 | 6 | 6 | 52580 |
| 3 | pin | 0 | open |  | 77 | 0 | 0 | 0 | 0 | none |
| 4 | orig | 0 | open |  | 56 | 3 | 2 | 13 | 13 | 52930 |
| 5 | pin | 1 | open |  | 202 | 0 | 0 | 3 | 3 | 51850 |
| 6 | lock | 1 | refused | tooShort | 6 |  |  |  |  |  |
| 7 | base | 1 | push failed | pageLost |  |  |  |  |  |  |
| 8 | orig | 1 | open |  | 68 | 6 | 3 | 64 | 64 | 52290 |
| 9 | base | 2 | open |  | 59 | 6 | 3 | 55 | 55 | 52580 |
| 10 | lock | 2 | open |  | 46 | 1 | 1 | 13 | 13 | 52480 |
| 11 | pin | 2 | open |  | 52 | 1 | 0 | 9 | 5 | 52250 |
| 12 | orig | 2 | open |  | 54 | 3 | 2 | 49 | 49 | 52580 |
| 13 | pin | 3 | open |  | 61 | 1 | 0 | 0 | 0 | none |
| 14 | lock | 3 | open |  | 62 | 3 | 2 | 58 | 58 | 52580 |
| 15 | base | 3 | open |  | 67 | 3 | 2 | 6 | 6 | 52530 |
| 16 | orig | 3 | open |  | 49 | 3 | 2 | 5 | 5 | 52280 |
| 17 | base | 4 | open |  | 76 | 7 | 4 | 21 | 21 | 52280 |
| 18 | lock | 4 | open |  | 61 | 1 | 1 | 5 | 5 | 52280 |
| 19 | pin | 4 | open |  | 58 | 1 | 0 | 0 | 0 | none |
| 20 | orig | 4 | open |  | 27 | 1 | 1 | 3 | 3 | 52280 |
| 21 | pin | 5 | open |  | 60 | 0 | 0 | 0 | 0 | none |
| 22 | lock | 5 | open |  | 61 | 4 | 2 | 59 | 59 | 52220 |
| 23 | base | 5 | open |  | 47 | 1 | 1 | 39 | 39 | 52610 |
| 24 | orig | 5 | open |  | 57 | 3 | 2 | 20 | 20 | 52530 |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | live writes | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 21 | 2 | 4 | 2 | 4 | 0 | 3 | 1 | 0 | 4 | 0 | yes |
| 5 | pin | 22 | 5 | 4 | 1 | 2 | 1 | 3 | 1 | 3 | 1 | 0 | yes |
| 11 | pin | 30 | 4 | 4 | 4 | 6 | 1 | 4 | 2 | 3 | 1 | 0 | yes |
| 13 | pin | 26 | 4 | 4 | 1 | 6 | 0 | 5 | 0 | 0 | 5 | 0 | yes |
| 19 | pin | 25 | 5 | 4 | 0 | 5 | 0 | 5 | 0 | 0 | 5 | 0 | yes |
| 21 | pin | 23 | 5 | 4 | 1 | 4 | 0 | 4 | 0 | 0 | 4 | 0 | yes |

lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out: orig 6 of 6, base 5 of 5, lock 5 of 5, pin 2 of 6

lock vs base: fights overlap, restores overlap, event fights overlap; base vs orig: fights overlap, restores overlap; look class of the candidate: look change

pin vs base: fights undecided, restores undecided, event fights undecided; pin vs orig: fights undecided; look class of the pin: look change; pin writes: 4 of 6 runs never wrote (their fights are 0 by definition)
