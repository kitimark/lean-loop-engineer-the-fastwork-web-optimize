| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 6 | 0 | {} | {"tooShort":1} | 5 | 5 | 3 1 3 1 1 | 5 1 6 1 1 | 56 2 30 4 2 | 56 2 30 4 2 | 3 1 3 1 1 | 52860 52520 52560 52530 52520 | 56 2 29 4 2 | 0 |
| base | 6 | 0 | {} | {"noOpen":1} | 5 | 4 | 2 1 2 0 6 | 3 1 3 2 12 | 3 45 58 40 61 | 3 45 58 40 61 | 2 1 2 0 6 | 52060 52530 52280 51920 52200 | 3 45 58 39 60 | 0 |
| lock | 6 | 0 | {} | {} | 6 | 5 | 4 1 1 3 0 1 | 7 2 1 6 0 2 | 86 2 19 30 2 32 | 86 2 19 30 2 32 | 4 1 1 3 0 1 | 52390 52230 51920 52530 52250 52530 | 86 2 19 29 2 31 | 0 |
| pin | 6 | 0 | {} | {"noOpen":1,"tooShort":1} | 4 | 0 | 0 0 0 0 | 0 0 1 1 | 0 0 0 0 | 0 0 0 0 | 0 0 0 0 | none none none none | 0 0 0 0 | 4 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 86 | 3 | 2 | 3 | 3 | 52060 |
| 2 | lock | 0 | open |  | 94 | 7 | 4 | 86 | 86 | 52390 |
| 3 | pin | 0 | refused | noOpen | 0 |  |  |  |  |  |
| 4 | orig | 0 | open |  | 61 | 5 | 3 | 56 | 56 | 52860 |
| 5 | pin | 1 | open |  | 60 | 0 | 0 | 0 | 0 | none |
| 6 | lock | 1 | open |  | 77 | 2 | 1 | 2 | 2 | 52230 |
| 7 | base | 1 | open |  | 68 | 1 | 1 | 45 | 45 | 52530 |
| 8 | orig | 1 | refused | tooShort | 7 |  |  |  |  |  |
| 9 | base | 2 | refused | noOpen | 0 |  |  |  |  |  |
| 10 | lock | 2 | open |  | 33 | 1 | 1 | 19 | 19 | 51920 |
| 11 | pin | 2 | open |  | 48 | 0 | 0 | 0 | 0 | none |
| 12 | orig | 2 | open |  | 46 | 1 | 1 | 2 | 2 | 52520 |
| 13 | pin | 3 | open |  | 71 | 1 | 0 | 0 | 0 | none |
| 14 | lock | 3 | open |  | 34 | 6 | 3 | 30 | 30 | 52530 |
| 15 | base | 3 | open |  | 69 | 3 | 2 | 58 | 58 | 52280 |
| 16 | orig | 3 | open |  | 34 | 6 | 3 | 30 | 30 | 52560 |
| 17 | base | 4 | open |  | 41 | 2 | 0 | 40 | 40 | 51920 |
| 18 | lock | 4 | open |  | 52 | 0 | 0 | 2 | 2 | 52250 |
| 19 | pin | 4 | refused | tooShort | 6 |  |  |  |  |  |
| 20 | orig | 4 | open |  | 53 | 1 | 1 | 4 | 4 | 52530 |
| 21 | pin | 5 | open |  | 47 | 1 | 0 | 0 | 0 | none |
| 22 | lock | 5 | open |  | 33 | 2 | 1 | 32 | 32 | 52530 |
| 23 | base | 5 | open |  | 67 | 12 | 6 | 61 | 61 | 52200 |
| 24 | orig | 5 | open |  | 50 | 1 | 1 | 2 | 2 | 52520 |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | live writes | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 14 | 9 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | yes |
| 5 | pin | 21 | 3 | 4 | 1 | 4 | 0 | 4 | 0 | 0 | 4 | 0 | yes |
| 11 | pin | 26 | 5 | 4 | 2 | 5 | 0 | 3 | 1 | 0 | 5 | 0 | yes |
| 13 | pin | 30 | 4 | 4 | 3 | 9 | 0 | 5 | 0 | 1 | 3 | 0 | yes |
| 19 | pin | 24 | 0 | 2 | 0 | 0 | 0 | 1 | 0 | 0 | 1 | 0 | yes |
| 21 | pin | 24 | 4 | 4 | 1 | 4 | 0 | 4 | 1 | 2 | 3 | 0 | yes |

lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out: orig 5 of 5, base 5 of 5, lock 6 of 6, pin 0 of 4

lock vs base: fights overlap, restores overlap, event fights overlap; base vs orig: fights overlap, restores overlap; look class of the candidate: look change

pin vs base: fights n/a, restores n/a, event fights n/a; pin vs orig: fights n/a; look class of the pin: look change; pin writes: 4 of 4 runs never wrote (their fights are 0 by definition)
