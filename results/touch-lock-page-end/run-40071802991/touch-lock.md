| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 4 | 0 | {} | {"noOpen":1} | 3 | 3 | 1 1 1 | 2 2 1 | 64 14 2 | 64 14 2 | 1 1 1 | 52330 52320 52330 |
| base | 4 | 0 | {} | {"noOpen":2} | 2 | 2 | 4 1 | 7 1 | 9 2 | 9 2 | 4 1 | 52520 52900 |
| lock | 4 | 0 | {} | {"noOpen":1} | 3 | 2 | 0 1 2 | 0 1 4 | 4 16 15 | 4 16 15 | 0 1 2 | 52310 52450 52170 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 90 | 7 | 4 | 9 | 9 | 52520 |
| 2 | lock | 0 | open |  | 46 | 0 | 0 | 4 | 4 | 52310 |
| 3 | orig | 0 | open |  | 66 | 2 | 1 | 64 | 64 | 52330 |
| 4 | lock | 1 | refused | noOpen | 0 |  |  |  |  |  |
| 5 | base | 1 | open |  | 14 | 1 | 1 | 2 | 2 | 52900 |
| 6 | orig | 1 | open |  | 16 | 2 | 1 | 14 | 14 | 52320 |
| 7 | base | 2 | refused | noOpen | 0 |  |  |  |  |  |
| 8 | lock | 2 | open |  | 37 | 1 | 1 | 16 | 16 | 52450 |
| 9 | orig | 2 | open |  | 42 | 1 | 1 | 2 | 2 | 52330 |
| 10 | lock | 3 | open |  | 17 | 4 | 2 | 15 | 15 | 52170 |
| 11 | base | 3 | refused | noOpen | 0 |  |  |  |  |  |
| 12 | orig | 3 | refused | noOpen | 0 |  |  |  |  |  |

lock vs base: fights overlap, restores overlap, event fights overlap; base vs orig: fights overlap, restores overlap; look class of the candidate: look change
