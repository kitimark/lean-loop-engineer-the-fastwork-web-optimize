| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 6 | 0 | {} | {} | 6 | 6 | 2 2 1 2 4 2 | 4 3 1 3 8 4 | 16 47 2 36 42 67 | 16 47 2 29 42 67 | 2 2 1 2 4 2 | 52870 52540 52480 52280 52550 52280 |
| base | 6 | 0 | {} | {"noOpen":2} | 4 | 4 | 2 2 2 2 | 3 3 3 5 | 3 3 14 33 | 3 3 14 33 | 2 2 2 2 | 52340 52420 52580 52120 |
| lock | 6 | 0 | {} | {"tooShort":1,"noOpen":1} | 4 | 4 | 1 1 1 1 | 1 2 1 1 | 4 2 2 2 | 4 2 2 2 | 1 1 1 1 | 52520 51870 52580 52390 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 49 | 3 | 2 | 3 | 3 | 52340 |
| 2 | lock | 0 | open |  | 71 | 1 | 1 | 4 | 4 | 52520 |
| 3 | orig | 0 | open |  | 38 | 4 | 2 | 16 | 16 | 52870 |
| 4 | lock | 1 | open |  | 54 | 2 | 1 | 2 | 2 | 51870 |
| 5 | base | 1 | open |  | 82 | 3 | 2 | 3 | 3 | 52420 |
| 6 | orig | 1 | open |  | 51 | 3 | 2 | 47 | 47 | 52540 |
| 7 | base | 2 | refused | noOpen | 0 |  |  |  |  |  |
| 8 | lock | 2 | refused | tooShort | 4 |  |  |  |  |  |
| 9 | orig | 2 | open |  | 19 | 1 | 1 | 2 | 2 | 52480 |
| 10 | lock | 3 | open |  | 37 | 1 | 1 | 2 | 2 | 52580 |
| 11 | base | 3 | open |  | 67 | 3 | 2 | 14 | 14 | 52580 |
| 12 | orig | 3 | open |  | 43 | 3 | 2 | 36 | 29 | 52280 |
| 13 | base | 4 | open |  | 53 | 5 | 2 | 33 | 33 | 52120 |
| 14 | lock | 4 | open |  | 76 | 1 | 1 | 2 | 2 | 52390 |
| 15 | orig | 4 | open |  | 46 | 8 | 4 | 42 | 42 | 52550 |
| 16 | lock | 5 | refused | noOpen | 0 |  |  |  |  |  |
| 17 | base | 5 | refused | noOpen | 0 |  |  |  |  |  |
| 18 | orig | 5 | open |  | 70 | 4 | 2 | 67 | 67 | 52280 |

lock vs base: fights lower, restores overlap, event fights lower; base vs orig: fights overlap, restores overlap; look class of the candidate: look change
