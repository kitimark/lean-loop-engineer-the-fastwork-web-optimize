| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 6 | 0 | {} | {} | 6 | 5 | 1 0 4 2 1 2 | 1 0 8 3 1 4 | 6 1 60 6 2 34 | 6 1 60 6 2 34 | 1 0 4 2 1 2 | 52530 52250 52380 52580 52170 52640 | 6 1 59 6 2 34 | 0 |
| base | 6 | 0 | {} | {"noOpen":1,"tooShort":1} | 4 | 4 | 4 1 1 2 | 7 2 1 4 | 70 2 4 16 | 70 2 4 16 | 4 1 1 2 | 52350 52910 52580 51980 | 70 2 4 16 | 0 |
| lock | 6 | 0 | {} | {"noOpen":2} | 4 | 4 | 1 1 2 1 | 1 1 4 2 | 9 20 46 2 | 9 20 46 2 | 1 1 2 1 | 51920 52580 52280 52210 | 9 20 45 2 | 0 |
| pin | 6 | 0 | {} | {"noOpen":1} | 5 | 0 | 0 0 0 0 0 | 1 1 1 1 1 | 0 0 0 0 0 | 0 0 0 0 0 | 0 0 0 0 0 | none none none none none | 0 0 0 0 0 | 5 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 75 | 7 | 4 | 70 | 70 | 52350 |
| 2 | lock | 0 | open |  | 70 | 1 | 1 | 9 | 9 | 51920 |
| 3 | pin | 0 | open |  | 65 | 1 | 0 | 0 | 0 | none |
| 4 | orig | 0 | open |  | 44 | 1 | 1 | 6 | 6 | 52530 |
| 5 | pin | 1 | open |  | 58 | 1 | 0 | 0 | 0 | none |
| 6 | lock | 1 | refused | noOpen | 0 |  |  |  |  |  |
| 7 | base | 1 | open |  | 40 | 2 | 1 | 2 | 2 | 52910 |
| 8 | orig | 1 | open |  | 24 | 0 | 0 | 1 | 1 | 52250 |
| 9 | base | 2 | open |  | 28 | 1 | 1 | 4 | 4 | 52580 |
| 10 | lock | 2 | open |  | 52 | 1 | 1 | 20 | 20 | 52580 |
| 11 | pin | 2 | open |  | 47 | 1 | 0 | 0 | 0 | none |
| 12 | orig | 2 | open |  | 64 | 8 | 4 | 60 | 60 | 52380 |
| 13 | pin | 3 | refused | noOpen | 0 |  |  |  |  |  |
| 14 | lock | 3 | refused | noOpen | 0 |  |  |  |  |  |
| 15 | base | 3 | open |  | 34 | 4 | 2 | 16 | 16 | 51980 |
| 16 | orig | 3 | open |  | 45 | 3 | 2 | 6 | 6 | 52580 |
| 17 | base | 4 | refused | noOpen | 0 |  |  |  |  |  |
| 18 | lock | 4 | open |  | 49 | 4 | 2 | 46 | 46 | 52280 |
| 19 | pin | 4 | open |  | 76 | 1 | 0 | 0 | 0 | none |
| 20 | orig | 4 | open |  | 68 | 1 | 1 | 2 | 2 | 52170 |
| 21 | pin | 5 | open |  | 46 | 1 | 0 | 0 | 0 | none |
| 22 | lock | 5 | open |  | 60 | 2 | 1 | 2 | 2 | 52210 |
| 23 | base | 5 | refused | tooShort | 6 |  |  |  |  |  |
| 24 | orig | 5 | open |  | 49 | 4 | 2 | 34 | 34 | 52640 |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | live writes | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 24 | 5 | 4 | 2 | 5 | 0 | 3 | 0 | 0 | 4 | 0 | yes |
| 5 | pin | 29 | 4 | 4 | 3 | 7 | 0 | 4 | 1 | 0 | 5 | 0 | yes |
| 11 | pin | 23 | 6 | 4 | 1 | 3 | 0 | 3 | 1 | 0 | 4 | 0 | yes |
| 13 | pin | 27 | 22 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | yes |
| 19 | pin | 23 | 5 | 4 | 0 | 4 | 0 | 4 | 0 | 0 | 5 | 0 | yes |
| 21 | pin | 23 | 6 | 4 | 1 | 3 | 0 | 3 | 1 | 0 | 4 | 0 | yes |

lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out: orig 6 of 6, base 4 of 4, lock 4 of 4, pin 0 of 5

lock vs base: fights overlap, restores overlap, event fights overlap; base vs orig: fights overlap, restores overlap; look class of the candidate: look change

pin vs base: fights n/a, restores n/a, event fights n/a; pin vs orig: fights n/a; look class of the pin: look change; pin writes: 5 of 5 runs never wrote (their fights are 0 by definition)
