| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 6 | 0 | {} | {"noOpen":1} | 5 | 5 | 1 5 1 4 3 | 2 9 1 7 5 | 48 16 3 49 37 | 48 16 3 49 37 | 1 5 1 4 3 | 52530 53100 52520 52370 52370 | 47 16 3 49 37 | 0 |
| base | 6 | 0 | {} | {"tooShort":1,"noOpen":1} | 4 | 3 | 1 3 0 1 | 1 5 2 2 | 19 34 3 2 | 19 34 2 2 | 1 3 1 1 | 52460 52170 51890 52280 | 19 34 2 2 | 0 |
| lock | 6 | 0 | {} | {"tooShort":1,"noOpen":1} | 4 | 4 | 1 1 2 2 | 1 2 3 3 | 3 19 10 12 | 3 19 10 12 | 1 1 2 2 | 52230 52120 52200 52220 | 3 18 10 12 | 0 |
| pin | 6 | 0 | {} | {"noOpen":2} | 4 | 0 | 0 0 0 0 | 0 0 0 1 | 2 0 4 0 | 1 0 3 0 | 0 0 0 0 | 52170 none 51890 none | 1 0 1 0 | 2 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | refused | tooShort | 7 |  |  |  |  |  |
| 2 | lock | 0 | refused | tooShort | 5 |  |  |  |  |  |
| 3 | pin | 0 | refused | noOpen | 0 |  |  |  |  |  |
| 4 | orig | 0 | refused | noOpen | 0 |  |  |  |  |  |
| 5 | pin | 1 | refused | noOpen | 0 |  |  |  |  |  |
| 6 | lock | 1 | refused | noOpen | 0 |  |  |  |  |  |
| 7 | base | 1 | open |  | 60 | 1 | 1 | 19 | 19 | 52460 |
| 8 | orig | 1 | open |  | 50 | 2 | 1 | 48 | 48 | 52530 |
| 9 | base | 2 | refused | noOpen | 0 |  |  |  |  |  |
| 10 | lock | 2 | open |  | 70 | 1 | 1 | 3 | 3 | 52230 |
| 11 | pin | 2 | open |  | 10 | 0 | 0 | 2 | 1 | 52170 |
| 12 | orig | 2 | open |  | 70 | 9 | 5 | 16 | 16 | 53100 |
| 13 | pin | 3 | open |  | 39 | 0 | 0 | 0 | 0 | none |
| 14 | lock | 3 | open |  | 21 | 2 | 1 | 19 | 19 | 52120 |
| 15 | base | 3 | open |  | 49 | 5 | 3 | 34 | 34 | 52170 |
| 16 | orig | 3 | open |  | 25 | 1 | 1 | 3 | 3 | 52520 |
| 17 | base | 4 | open |  | 68 | 2 | 0 | 3 | 2 | 51890 |
| 18 | lock | 4 | open |  | 57 | 3 | 2 | 10 | 10 | 52200 |
| 19 | pin | 4 | open |  | 52 | 0 | 0 | 4 | 3 | 51890 |
| 20 | orig | 4 | open |  | 53 | 7 | 4 | 49 | 49 | 52370 |
| 21 | pin | 5 | open |  | 58 | 1 | 0 | 0 | 0 | none |
| 22 | lock | 5 | open |  | 42 | 3 | 2 | 12 | 12 | 52220 |
| 23 | base | 5 | open |  | 70 | 2 | 1 | 2 | 2 | 52280 |
| 24 | orig | 5 | open |  | 45 | 5 | 3 | 37 | 37 | 52370 |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | live writes | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 17 | 12 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | yes |
| 5 | pin | 18 | 13 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | yes |
| 11 | pin | 18 | 5 | 4 | 1 | 0 | 1 | 1 | 1 | 4 | 0 | 0 | yes |
| 13 | pin | 24 | 5 | 4 | 2 | 5 | 0 | 3 | 0 | 0 | 4 | 0 | yes |
| 19 | pin | 27 | 4 | 4 | 3 | 4 | 1 | 4 | 1 | 4 | 1 | 0 | yes |
| 21 | pin | 22 | 5 | 4 | 1 | 3 | 0 | 3 | 1 | 0 | 4 | 0 | yes |

lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out: orig 5 of 5, base 4 of 4, lock 4 of 4, pin 2 of 4

lock vs base: fights overlap, restores overlap, event fights overlap; base vs orig: fights overlap, restores overlap; look class of the candidate: look change

pin vs base: fights undecided, restores undecided, event fights undecided; pin vs orig: fights undecided; look class of the pin: look change; pin writes: 2 of 4 runs never wrote (their fights are 0 by definition)
