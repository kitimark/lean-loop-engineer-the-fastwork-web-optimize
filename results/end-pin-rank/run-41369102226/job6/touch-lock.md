| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 6 | 0 | {} | {"noOpen":1} | 5 | 4 | 1 1 0 2 4 | 2 2 0 4 7 | 2 2 28 68 19 | 2 2 28 68 19 | 1 1 0 2 4 | 52250 52210 52220 52280 52310 | 2 2 27 67 19 | 0 |
| base | 6 | 0 | {} | {"tooShort":2,"noOpen":1} | 3 | 3 | 4 2 5 | 7 3 9 | 27 38 51 | 27 38 51 | 4 2 5 | 52580 52580 52220 | 27 38 51 | 0 |
| lock | 6 | 0 | {} | {"noOpen":2} | 4 | 2 | 0 0 2 1 | 0 0 4 1 | 2 1 62 3 | 2 1 62 3 | 0 0 2 1 | 52250 52280 52480 51920 | 2 1 61 3 | 0 |
| pin | 6 | 0 | {} | {"noOpen":1} | 5 | 0 | 0 0 0 0 0 | 0 0 0 1 0 | 0 0 0 0 0 | 0 0 0 0 0 | 0 0 0 0 0 | none none none none none | 0 0 0 0 0 | 5 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | refused | tooShort | 5 |  |  |  |  |  |
| 2 | lock | 0 | open |  | 50 | 0 | 0 | 2 | 2 | 52250 |
| 3 | pin | 0 | open |  | 77 | 0 | 0 | 0 | 0 | none |
| 4 | orig | 0 | open |  | 61 | 2 | 1 | 2 | 2 | 52250 |
| 5 | pin | 1 | refused | noOpen | 0 |  |  |  |  |  |
| 6 | lock | 1 | refused | noOpen | 0 |  |  |  |  |  |
| 7 | base | 1 | refused | noOpen | 0 |  |  |  |  |  |
| 8 | orig | 1 | open |  | 83 | 2 | 1 | 2 | 2 | 52210 |
| 9 | base | 2 | refused | tooShort | 6 |  |  |  |  |  |
| 10 | lock | 2 | refused | noOpen | 0 |  |  |  |  |  |
| 11 | pin | 2 | open |  | 70 | 0 | 0 | 0 | 0 | none |
| 12 | orig | 2 | refused | noOpen | 0 |  |  |  |  |  |
| 13 | pin | 3 | open |  | 42 | 0 | 0 | 0 | 0 | none |
| 14 | lock | 3 | open |  | 47 | 0 | 0 | 1 | 1 | 52280 |
| 15 | base | 3 | open |  | 54 | 7 | 4 | 27 | 27 | 52580 |
| 16 | orig | 3 | open |  | 29 | 0 | 0 | 28 | 28 | 52220 |
| 17 | base | 4 | open |  | 64 | 3 | 2 | 38 | 38 | 52580 |
| 18 | lock | 4 | open |  | 65 | 4 | 2 | 62 | 62 | 52480 |
| 19 | pin | 4 | open |  | 56 | 1 | 0 | 0 | 0 | none |
| 20 | orig | 4 | open |  | 71 | 4 | 2 | 68 | 68 | 52280 |
| 21 | pin | 5 | open |  | 17 | 0 | 0 | 0 | 0 | none |
| 22 | lock | 5 | open |  | 62 | 1 | 1 | 3 | 3 | 51920 |
| 23 | base | 5 | open |  | 57 | 9 | 5 | 51 | 51 | 52220 |
| 24 | orig | 5 | open |  | 63 | 7 | 4 | 19 | 19 | 52310 |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | live writes | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 23 | 3 | 4 | 1 | 5 | 0 | 4 | 0 | 0 | 5 | 0 | yes |
| 5 | pin | 22 | 17 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | yes |
| 11 | pin | 21 | 2 | 4 | 2 | 4 | 0 | 3 | 1 | 0 | 4 | 0 | yes |
| 13 | pin | 17 | 2 | 4 | 1 | 3 | 0 | 1 | 1 | 0 | 4 | 0 | yes |
| 19 | pin | 26 | 5 | 4 | 2 | 6 | 0 | 3 | 0 | 0 | 5 | 0 | yes |
| 21 | pin | 17 | 2 | 4 | 1 | 3 | 0 | 1 | 1 | 0 | 4 | 0 | yes |

lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out: orig 5 of 5, base 3 of 3, lock 4 of 4, pin 0 of 5

lock vs base: fights overlap, restores overlap, event fights overlap; base vs orig: fights overlap, restores overlap; look class of the candidate: look change

pin vs base: fights n/a, restores n/a, event fights n/a; pin vs orig: fights n/a; look class of the pin: look change; pin writes: 5 of 5 runs never wrote (their fights are 0 by definition)
