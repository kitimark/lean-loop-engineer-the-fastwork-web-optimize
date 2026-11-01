| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 3 | 0 | {} | {"noOpen":1} | 2 | 2 | 4 1 | 7 2 | 53 21 | 53 21 | 4 1 | 52280 52380 | 53 20 | 0 |
| base | 3 | 0 | {} | {"noOpen":1} | 2 | 2 | 5 2 | 10 4 | 95 39 | 95 39 | 5 2 | 52550 52740 | 94 38 | 0 |
| lock | 3 | 0 | {} | {"tooShort":2,"noOpen":1} | 0 | 0 |  |  |  |  |  |  |  | 0 |
| pin | 4 | 1 | {"pageLost":1} | {"tooShort":1,"noOpen":1} | 1 | 0 | 0 | 1 | 0 | 0 | 0 | none | 0 | 1 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 101 | 10 | 5 | 95 | 95 | 52550 |
| 2 | lock | 0 | refused | tooShort | 4 |  |  |  |  |  |
| 3 | pin | 0 | refused | tooShort | 6 |  |  |  |  |  |
| 4 | orig | 0 | open |  | 65 | 7 | 4 | 53 | 53 | 52280 |
| 5 | pin | 1 | open |  | 52 | 1 | 0 | 0 | 0 | none |
| 6 | lock | 1 | refused | tooShort | 7 |  |  |  |  |  |
| 7 | base | 1 | refused | noOpen | 0 |  |  |  |  |  |
| 8 | orig | 1 | refused | noOpen | 0 |  |  |  |  |  |
| 9 | base | 2 | open |  | 41 | 4 | 2 | 39 | 39 | 52740 |
| 10 | lock | 2 | refused | noOpen | 0 |  |  |  |  |  |
| 11 | pin | 2 | refused | noOpen | 0 |  |  |  |  |  |
| 12 | orig | 2 | open |  | 23 | 2 | 1 | 21 | 21 | 52380 |
| 13 | pin | 3 | push failed | pageLost |  |  |  |  |  |  |

lock vs base: fights undecided, restores undecided, event fights undecided; base vs orig: fights undecided, restores undecided; look class of the candidate: undecided

pin vs base: fights undecided, restores undecided, event fights undecided; pin vs orig: fights undecided; look class of the pin: undecided; pin writes: 1 of 1 runs never wrote (their fights are 0 by definition)
