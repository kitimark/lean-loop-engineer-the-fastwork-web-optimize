| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 12 | 0 | {} | {"noOpen":1} | 11 | 10 | 2 0 1 1 1 1 1 1 2 4 1 | 3 0 2 1 2 2 1 3 3 7 2 | 23 1 27 32 2 16 12 13 24 53 21 | 23 1 27 32 1 16 12 13 24 53 21 | 2 0 1 1 0 1 1 1 2 4 1 | 52370 52270 52280 52580 52270 52280 52170 51920 52530 52280 52380 | 23 1 26 32 1 15 12 13 24 53 20 | 0 |
| base | 13 | 0 | {} | {"tooShort":1,"noOpen":1} | 11 | 11 | 1 1 1 1 1 1 2 2 1 5 2 | 1 1 1 1 1 1 3 3 2 10 4 | 16 5 2 25 3 15 9 3 2 95 39 | 16 5 2 25 3 15 9 3 2 95 39 | 1 1 1 1 1 1 2 2 1 5 2 | 51990 52290 52220 52170 52580 52240 52330 52280 51890 52550 52740 | 16 5 2 25 3 15 9 3 2 94 38 | 0 |
| lock | 13 | 1 | {"pageLost":1} | {"tooShort":2,"noOpen":1} | 9 | 9 | 1 1 3 1 3 2 2 1 2 | 1 1 6 1 6 3 3 1 4 | 11 2 8 2 61 15 4 2 102 | 11 2 8 2 61 15 4 2 102 | 1 1 3 1 3 2 2 1 2 | 52390 52280 52690 52280 52580 52580 52280 52280 52180 | 11 2 8 2 60 15 4 2 101 | 0 |
| pin | 14 | 8 | {"config":6,"pageLost":2} | {"tooShort":1,"noOpen":1} | 4 | 0 | 0 0 0 0 | 0 1 1 1 | 0 0 0 0 | 0 0 0 0 | 0 0 0 0 | none none none none | 0 0 0 0 | 4 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 72 | 1 | 1 | 16 | 16 | 51990 |
| 2 | lock | 0 | open |  | 70 | 1 | 1 | 11 | 11 | 52390 |
| 3 | pin | 0 | refused | config |  |  |  |  |  |  |
| 4 | orig | 0 | open |  | 69 | 3 | 2 | 23 | 23 | 52370 |
| 5 | pin | 1 | refused | config |  |  |  |  |  |  |
| 6 | lock | 1 | open |  | 39 | 1 | 1 | 2 | 2 | 52280 |
| 7 | base | 1 | refused | tooShort | 5 |  |  |  |  |  |
| 8 | orig | 1 | open |  | 50 | 0 | 0 | 1 | 1 | 52270 |
| 9 | base | 2 | open |  | 55 | 1 | 1 | 5 | 5 | 52290 |
| 10 | lock | 2 | open |  | 19 | 6 | 3 | 8 | 8 | 52690 |
| 11 | pin | 2 | refused | config |  |  |  |  |  |  |
| 12 | orig | 2 | open |  | 29 | 2 | 1 | 27 | 27 | 52280 |
| 13 | pin | 3 | refused | config |  |  |  |  |  |  |
| 14 | lock | 3 | open |  | 62 | 1 | 1 | 2 | 2 | 52280 |
| 15 | base | 3 | open |  | 66 | 1 | 1 | 2 | 2 | 52220 |
| 16 | orig | 3 | open |  | 50 | 1 | 1 | 32 | 32 | 52580 |
| 17 | base | 4 | open |  | 54 | 1 | 1 | 25 | 25 | 52170 |
| 18 | lock | 4 | open |  | 65 | 6 | 3 | 61 | 61 | 52580 |
| 19 | pin | 4 | refused | config |  |  |  |  |  |  |
| 20 | orig | 4 | open |  | 57 | 2 | 1 | 2 | 1 | 52270 |
| 21 | pin | 5 | refused | config |  |  |  |  |  |  |
| 22 | lock | 5 | open |  | 24 | 3 | 2 | 15 | 15 | 52580 |
| 23 | base | 5 | open |  | 37 | 1 | 1 | 3 | 3 | 52580 |
| 24 | orig | 5 | open |  | 18 | 2 | 1 | 16 | 16 | 52280 |
| 25 | base | 0 | open |  | 78 | 1 | 1 | 15 | 15 | 52240 |
| 26 | lock | 0 | push failed | pageLost |  |  |  |  |  |  |
| 27 | base | 0 | open |  | 62 | 3 | 2 | 9 | 9 | 52330 |
| 28 | lock | 0 | open |  | 57 | 3 | 2 | 4 | 4 | 52280 |
| 29 | pin | 0 | open |  | 241 | 0 | 0 | 0 | 0 | none |
| 30 | orig | 0 | open |  | 55 | 1 | 1 | 12 | 12 | 52170 |
| 31 | pin | 1 | open |  | 63 | 1 | 0 | 0 | 0 | none |
| 32 | lock | 1 | open |  | 32 | 1 | 1 | 2 | 2 | 52280 |
| 33 | base | 1 | open |  | 78 | 3 | 2 | 3 | 3 | 52280 |
| 34 | orig | 1 | open |  | 47 | 3 | 1 | 13 | 13 | 51920 |
| 35 | base | 2 | open |  | 63 | 2 | 1 | 2 | 2 | 51890 |
| 36 | lock | 2 | open |  | 105 | 4 | 2 | 102 | 102 | 52180 |
| 37 | pin | 2 | open |  | 41 | 1 | 0 | 0 | 0 | none |
| 38 | orig | 2 | open |  | 44 | 3 | 2 | 24 | 24 | 52530 |
| 39 | pin | 3 | push failed | pageLost |  |  |  |  |  |  |
| 40 | base | 0 | open |  | 101 | 10 | 5 | 95 | 95 | 52550 |
| 41 | lock | 0 | refused | tooShort | 4 |  |  |  |  |  |
| 42 | pin | 0 | refused | tooShort | 6 |  |  |  |  |  |
| 43 | orig | 0 | open |  | 65 | 7 | 4 | 53 | 53 | 52280 |
| 44 | pin | 1 | open |  | 52 | 1 | 0 | 0 | 0 | none |
| 45 | lock | 1 | refused | tooShort | 7 |  |  |  |  |  |
| 46 | base | 1 | refused | noOpen | 0 |  |  |  |  |  |
| 47 | orig | 1 | refused | noOpen | 0 |  |  |  |  |  |
| 48 | base | 2 | open |  | 41 | 4 | 2 | 39 | 39 | 52740 |
| 49 | lock | 2 | refused | noOpen | 0 |  |  |  |  |  |
| 50 | pin | 2 | refused | noOpen | 0 |  |  |  |  |  |
| 51 | orig | 2 | open |  | 23 | 2 | 1 | 21 | 21 | 52380 |
| 52 | pin | 3 | push failed | pageLost |  |  |  |  |  |  |

lock vs base: fights overlap, restores overlap, event fights overlap; base vs orig: fights overlap, restores overlap; look class of the candidate: look change

pin vs base: fights lower, restores lower, event fights lower; pin vs orig: fights overlap; look class of the pin: look change; pin writes: 4 of 4 runs never wrote (their fights are 0 by definition)
