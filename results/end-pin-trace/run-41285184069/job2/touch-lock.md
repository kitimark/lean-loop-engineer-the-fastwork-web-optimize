| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 1 | 0 | {} | {"noOpen":1} | 0 | 0 |  |  |  |  |  |  |  | 0 |
| base | 1 | 0 | {} | {} | 1 | 1 | 1 | 1 | 9 | 9 | 1 | 52320 | 9 | 0 |
| lock | 1 | 0 | {} | {"noOpen":1} | 0 | 0 |  |  |  |  |  |  |  | 0 |
| pin | 2 | 0 | {} | {"noOpen":1} | 1 | 0 | 0 | 0 | 0 | 0 | 0 | none | 0 | 1 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 36 | 1 | 1 | 9 | 9 | 52320 |
| 2 | lock | 0 | refused | noOpen | 0 |  |  |  |  |  |
| 3 | pin | 0 | refused | noOpen | 0 |  |  |  |  |  |
| 4 | orig | 0 | refused | noOpen | 0 |  |  |  |  |  |
| 5 | pin | 1 | open |  | 56 | 0 | 0 | 0 | 0 | none |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 24 | 19 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | yes |
| 5 | pin | 10 | 2 | 4 | 0 | 2 | 0 | 1 | 0 | 0 | 0 | yes |

lock vs base: fights undecided, restores undecided, event fights undecided; base vs orig: fights undecided, restores undecided; look class of the candidate: undecided

pin vs base: fights n/a, restores n/a, event fights n/a; pin vs orig: fights undecided; look class of the pin: undecided; pin writes: 1 of 1 runs never wrote (their fights are 0 by definition)
