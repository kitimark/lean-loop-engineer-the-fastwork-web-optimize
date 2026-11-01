| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 2 | 0 | {} | {"noOpen":1} | 1 | 1 | 1 | 2 | 21 | 21 | 1 | 52280 | 22 | 0 |
| base | 2 | 0 | {} | {} | 2 | 1 | 1 0 | 1 0 | 2 18 | 2 18 | 1 0 | 52300 52250 | 2 17 | 0 |
| lock | 2 | 0 | {} | {"tooShort":1} | 1 | 0 | 0 | 0 | 2 | 2 | 0 | 52250 | 2 | 0 |
| pin | 2 | 0 | {} | {"tooShort":1} | 1 | 0 | 0 | 0 | 0 | 0 | 0 | none | 0 | 1 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 12 | 1 | 1 | 2 | 2 | 52300 |
| 2 | lock | 0 | open |  | 55 | 0 | 0 | 2 | 2 | 52250 |
| 3 | pin | 0 | open |  | 35 | 0 | 0 | 0 | 0 | none |
| 4 | orig | 0 | open |  | 35 | 2 | 1 | 21 | 21 | 52280 |
| 5 | pin | 1 | refused | tooShort | 2 |  |  |  |  |  |
| 6 | lock | 1 | refused | tooShort | 1 |  |  |  |  |  |
| 7 | base | 1 | open |  | 18 | 0 | 0 | 18 | 18 | 52250 |
| 8 | orig | 1 | refused | noOpen | 0 |  |  |  |  |  |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 26 | 4 | 4 | 2 | 5 | 0 | 4 | 1 | 2 | 3 | yes |
| 5 | pin | 16 | 0 | 2 | 0 | 0 | 0 | 1 | 0 | 0 | 1 | yes |

lock vs base: fights undecided, restores undecided, event fights undecided; base vs orig: fights undecided, restores undecided; look class of the candidate: undecided

pin vs base: fights n/a, restores n/a, event fights n/a; pin vs orig: fights n/a; look class of the pin: undecided; pin writes: 1 of 1 runs never wrote (their fights are 0 by definition)
