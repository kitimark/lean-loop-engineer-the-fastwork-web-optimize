| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 6 | 0 | {} | {} | 6 | 5 | 1 1 0 1 1 1 | 1 3 0 1 1 1 | 20 13 39 21 10 15 | 20 13 39 21 10 15 | 1 1 0 1 1 1 | 52520 52730 52580 52640 52310 52720 |
| base | 6 | 0 | {} | {"noOpen":3} | 3 | 3 | 1 2 1 | 1 5 3 | 2 15 12 | 2 15 12 | 1 2 1 | 52160 52370 52870 |
| lock | 6 | 0 | {} | {"noOpen":4} | 2 | 2 | 1 1 | 2 2 | 11 2 | 11 2 | 1 1 | 51980 52250 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 58 | 1 | 1 | 2 | 2 | 52160 |
| 2 | lock | 0 | refused | noOpen | 0 |  |  |  |  |  |
| 3 | orig | 0 | open |  | 36 | 1 | 1 | 20 | 20 | 52520 |
| 4 | lock | 1 | refused | noOpen | 0 |  |  |  |  |  |
| 5 | base | 1 | refused | noOpen | 0 |  |  |  |  |  |
| 6 | orig | 1 | open |  | 15 | 3 | 1 | 13 | 13 | 52730 |
| 7 | base | 2 | open |  | 18 | 5 | 2 | 15 | 15 | 52370 |
| 8 | lock | 2 | open |  | 13 | 2 | 1 | 11 | 11 | 51980 |
| 9 | orig | 2 | open |  | 39 | 0 | 0 | 39 | 39 | 52580 |
| 10 | lock | 3 | refused | noOpen | 0 |  |  |  |  |  |
| 11 | base | 3 | refused | noOpen | 0 |  |  |  |  |  |
| 12 | orig | 3 | open |  | 33 | 1 | 1 | 21 | 21 | 52640 |
| 13 | base | 4 | open |  | 14 | 3 | 1 | 12 | 12 | 52870 |
| 14 | lock | 4 | refused | noOpen | 0 |  |  |  |  |  |
| 15 | orig | 4 | open |  | 18 | 1 | 1 | 10 | 10 | 52310 |
| 16 | lock | 5 | open |  | 44 | 2 | 1 | 2 | 2 | 52250 |
| 17 | base | 5 | refused | noOpen | 0 |  |  |  |  |  |
| 18 | orig | 5 | open |  | 17 | 1 | 1 | 15 | 15 | 52720 |

lock vs base: fights overlap, restores overlap, event fights overlap; base vs orig: fights overlap, restores overlap; look class of the candidate: look change
