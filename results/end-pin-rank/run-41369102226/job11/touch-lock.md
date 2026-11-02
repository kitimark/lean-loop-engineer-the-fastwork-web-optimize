| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 2 | 0 | {} | {"noOpen":2} | 0 | 0 |  |  |  |  |  |  |  | 0 |
| base | 3 | 0 | {} | {} | 3 | 3 | 2 1 2 | 4 1 4 | 33 4 25 | 33 4 25 | 2 1 2 | 52440 52770 52650 | 32 4 24 | 0 |
| lock | 3 | 0 | {} | {"noOpen":1} | 2 | 2 | 1 5 | 1 9 | 2 39 | 2 39 | 1 5 | 52310 52170 | 2 39 | 0 |
| pin | 3 | 1 | {"pageLost":1} | {"noOpen":2} | 0 | 0 |  |  |  |  |  |  |  | 0 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 35 | 4 | 2 | 33 | 33 | 52440 |
| 2 | lock | 0 | open |  | 64 | 1 | 1 | 2 | 2 | 52310 |
| 3 | pin | 0 | refused | noOpen | 0 |  |  |  |  |  |
| 4 | orig | 0 | refused | noOpen | 0 |  |  |  |  |  |
| 5 | pin | 1 | refused | noOpen | 0 |  |  |  |  |  |
| 6 | lock | 1 | refused | noOpen | 0 |  |  |  |  |  |
| 7 | base | 1 | open |  | 14 | 1 | 1 | 4 | 4 | 52770 |
| 8 | orig | 1 | refused | noOpen | 0 |  |  |  |  |  |
| 9 | base | 2 | open |  | 28 | 4 | 2 | 25 | 25 | 52650 |
| 10 | lock | 2 | open |  | 54 | 9 | 5 | 39 | 39 | 52170 |
| 11 | pin | 2 | push failed | pageLost |  |  |  |  |  |  |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | live writes | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 22 | 17 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | yes |
| 5 | pin | 28 | 23 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | yes |

lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out: orig 0 of 0, base 3 of 3, lock 2 of 2, pin 0 of 0

lock vs base: fights undecided, restores undecided, event fights undecided; base vs orig: fights undecided, restores undecided; look class of the candidate: undecided

pin vs base: fights undecided, restores undecided, event fights undecided; pin vs orig: fights undecided; look class of the pin: undecided; pin writes: undecided
