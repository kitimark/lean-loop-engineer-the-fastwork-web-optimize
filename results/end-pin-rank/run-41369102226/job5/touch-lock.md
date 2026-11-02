| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 6 | 0 | {} | {} | 6 | 5 | 1 0 1 2 2 4 | 1 0 1 3 3 7 | 5 13 3 5 17 51 | 5 13 3 5 17 51 | 1 0 1 2 2 4 | 53180 53150 52580 52580 52580 52610 | 5 12 3 5 17 51 | 0 |
| base | 6 | 0 | {} | {} | 6 | 5 | 3 0 1 4 1 1 | 5 0 2 8 1 1 | 28 16 2 11 5 14 | 28 16 2 11 5 14 | 3 0 1 4 1 1 | 52080 52530 51870 52320 52530 52530 | 28 15 2 11 5 14 | 0 |
| lock | 6 | 0 | {} | {"noOpen":2} | 4 | 3 | 1 1 1 0 | 1 2 1 0 | 11 2 2 1 | 11 2 2 1 | 1 1 1 0 | 52280 52250 52220 51920 | 11 2 2 1 | 0 |
| pin | 6 | 0 | {} | {"tooShort":1} | 5 | 0 | 0 0 0 0 0 | 0 0 1 1 1 | 0 0 0 0 0 | 0 0 0 0 0 | 0 0 0 0 0 | none none none none none | 0 0 0 0 0 | 5 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 63 | 5 | 3 | 28 | 28 | 52080 |
| 2 | lock | 0 | refused | noOpen | 0 |  |  |  |  |  |
| 3 | pin | 0 | open |  | 13 | 0 | 0 | 0 | 0 | none |
| 4 | orig | 0 | open |  | 57 | 1 | 1 | 5 | 5 | 53180 |
| 5 | pin | 1 | refused | tooShort | 6 |  |  |  |  |  |
| 6 | lock | 1 | open |  | 182 | 1 | 1 | 11 | 11 | 52280 |
| 7 | base | 1 | open |  | 17 | 0 | 0 | 16 | 16 | 52530 |
| 8 | orig | 1 | open |  | 13 | 0 | 0 | 13 | 13 | 53150 |
| 9 | base | 2 | open |  | 83 | 2 | 1 | 2 | 2 | 51870 |
| 10 | lock | 2 | refused | noOpen | 0 |  |  |  |  |  |
| 11 | pin | 2 | open |  | 67 | 0 | 0 | 0 | 0 | none |
| 12 | orig | 2 | open |  | 58 | 1 | 1 | 3 | 3 | 52580 |
| 13 | pin | 3 | open |  | 75 | 1 | 0 | 0 | 0 | none |
| 14 | lock | 3 | open |  | 82 | 2 | 1 | 2 | 2 | 52250 |
| 15 | base | 3 | open |  | 86 | 8 | 4 | 11 | 11 | 52320 |
| 16 | orig | 3 | open |  | 36 | 3 | 2 | 5 | 5 | 52580 |
| 17 | base | 4 | open |  | 43 | 1 | 1 | 5 | 5 | 52530 |
| 18 | lock | 4 | open |  | 40 | 1 | 1 | 2 | 2 | 52220 |
| 19 | pin | 4 | open |  | 88 | 1 | 0 | 0 | 0 | none |
| 20 | orig | 4 | open |  | 63 | 3 | 2 | 17 | 17 | 52580 |
| 21 | pin | 5 | open |  | 71 | 1 | 0 | 0 | 0 | none |
| 22 | lock | 5 | open |  | 43 | 0 | 0 | 1 | 1 | 51920 |
| 23 | base | 5 | open |  | 46 | 1 | 1 | 14 | 14 | 52530 |
| 24 | orig | 5 | open |  | 57 | 7 | 4 | 51 | 51 | 52610 |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | live writes | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 15 | 2 | 4 | 0 | 2 | 0 | 1 | 1 | 1 | 3 | 0 | yes |
| 5 | pin | 15 | 0 | 2 | 0 | 0 | 0 | 1 | 0 | 0 | 1 | 0 | yes |
| 11 | pin | 24 | 3 | 4 | 2 | 5 | 0 | 3 | 1 | 0 | 5 | 0 | yes |
| 13 | pin | 23 | 5 | 4 | 0 | 4 | 0 | 4 | 0 | 0 | 5 | 0 | yes |
| 19 | pin | 28 | 4 | 4 | 2 | 6 | 0 | 5 | 1 | 2 | 3 | 0 | yes |
| 21 | pin | 26 | 6 | 4 | 1 | 5 | 0 | 4 | 0 | 0 | 5 | 0 | yes |

lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out: orig 6 of 6, base 6 of 6, lock 4 of 4, pin 0 of 5

lock vs base: fights overlap, restores overlap, event fights overlap; base vs orig: fights overlap, restores overlap; look class of the candidate: look change

pin vs base: fights n/a, restores n/a, event fights n/a; pin vs orig: fights n/a; look class of the pin: look change; pin writes: 5 of 5 runs never wrote (their fights are 0 by definition)
