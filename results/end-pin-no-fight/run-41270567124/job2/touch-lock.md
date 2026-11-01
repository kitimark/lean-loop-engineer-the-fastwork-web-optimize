| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 3 | 0 | {} | {} | 3 | 3 | 1 1 2 | 1 3 3 | 12 13 24 | 12 13 24 | 1 1 2 | 52170 51920 52530 | 12 13 24 | 0 |
| base | 3 | 0 | {} | {} | 3 | 3 | 2 2 1 | 3 3 2 | 9 3 2 | 9 3 2 | 2 2 1 | 52330 52280 51890 | 9 3 2 | 0 |
| lock | 3 | 0 | {} | {} | 3 | 3 | 2 1 2 | 3 1 4 | 4 2 102 | 4 2 102 | 2 1 2 | 52280 52280 52180 | 4 2 101 | 0 |
| pin | 4 | 1 | {"pageLost":1} | {} | 3 | 0 | 0 0 0 | 0 1 1 | 0 0 0 | 0 0 0 | 0 0 0 | none none none | 0 0 0 | 3 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 62 | 3 | 2 | 9 | 9 | 52330 |
| 2 | lock | 0 | open |  | 57 | 3 | 2 | 4 | 4 | 52280 |
| 3 | pin | 0 | open |  | 241 | 0 | 0 | 0 | 0 | none |
| 4 | orig | 0 | open |  | 55 | 1 | 1 | 12 | 12 | 52170 |
| 5 | pin | 1 | open |  | 63 | 1 | 0 | 0 | 0 | none |
| 6 | lock | 1 | open |  | 32 | 1 | 1 | 2 | 2 | 52280 |
| 7 | base | 1 | open |  | 78 | 3 | 2 | 3 | 3 | 52280 |
| 8 | orig | 1 | open |  | 47 | 3 | 1 | 13 | 13 | 51920 |
| 9 | base | 2 | open |  | 63 | 2 | 1 | 2 | 2 | 51890 |
| 10 | lock | 2 | open |  | 105 | 4 | 2 | 102 | 102 | 52180 |
| 11 | pin | 2 | open |  | 41 | 1 | 0 | 0 | 0 | none |
| 12 | orig | 2 | open |  | 44 | 3 | 2 | 24 | 24 | 52530 |
| 13 | pin | 3 | push failed | pageLost |  |  |  |  |  |  |

lock vs base: fights overlap, restores overlap, event fights overlap; base vs orig: fights overlap, restores lower; look class of the candidate: look change

pin vs base: fights lower, restores lower, event fights lower; pin vs orig: fights lower; look class of the pin: look change; pin writes: 3 of 3 runs never wrote (their fights are 0 by definition)
