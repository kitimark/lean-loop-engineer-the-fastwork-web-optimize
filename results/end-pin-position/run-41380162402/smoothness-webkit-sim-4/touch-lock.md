| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 3 | 0 | {} | {"noOpen":1} | 2 | 2 | 4 2 | 7 3 | 8 21 | 8 21 | 4 2 | 52530 52710 | 8 21 | 0 |
| base | 3 | 0 | {} | {"noOpen":1} | 2 | 2 | 2 1 | 5 1 | 12 24 | 12 24 | 2 1 | 51920 52080 | 12 24 | 0 |
| lock | 4 | 0 | {} | {"noOpen":2,"tooShort":1} | 1 | 1 | 2 | 3 | 45 | 45 | 2 | 52170 | 45 | 0 |
| pin | 4 | 0 | {} | {"noOpen":1} | 3 | 0 | 0 0 0 | 0 0 0 | 23 0 0 | 2 0 0 | 0 0 0 | 52720 none none | 1 0 0 | 2 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock | rest | gap to goal (px) | settle after lift (ms) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 68 | 5 | 2 | 12 | 12 | 51920 | atEnd | 1 | 0 |
| 2 | lock | 0 | open |  | 76 | 3 | 2 | 45 | 45 | 52170 | atEnd | 0 | 49 |
| 3 | pin | 0 | open |  | 23 | 0 | 0 | 23 | 2 | 52720 | atEnd | 0 | 0 |
| 4 | orig | 0 | open |  | 68 | 7 | 4 | 8 | 8 | 52530 | over | 26 | 0 |
| 5 | pin | 1 | open |  | 25 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 6 | lock | 1 | refused | noOpen | 0 |  |  |  |  |  |  |  |  |
| 7 | base | 1 | open |  | 57 | 1 | 1 | 24 | 24 | 52080 | over | 17 | 0 |
| 8 | orig | 1 | open |  | 66 | 3 | 2 | 21 | 21 | 52710 | over | 44 | 0 |
| 9 | base | 2 | refused | noOpen | 0 |  |  |  |  |  |  |  |  |
| 10 | lock | 2 | refused | tooShort | 7 |  |  |  |  |  | atEnd | 0 | 0 |
| 11 | pin | 2 | open |  | 55 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 12 | orig | 2 | refused | noOpen | 0 |  |  |  |  |  | short | 676 | 1143 |
| 13 | pin | 3 | refused | noOpen | 0 |  |  |  |  |  | notReached | 501 | 1071 |
| 14 | lock | 3 | refused | noOpen | 0 |  |  |  |  |  | notReached | 628 | 1183 |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | live writes | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 15 | 2 | 4 | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 0 | yes |
| 5 | pin | 17 | 2 | 4 | 1 | 3 | 0 | 1 | 1 | 0 | 4 | 0 | yes |
| 11 | pin | 16 | 1 | 4 | 1 | 3 | 0 | 1 | 1 | 0 | 4 | 0 | yes |
| 13 | pin | 21 | 16 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | yes |

lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out: orig 2 of 2, base 2 of 2, lock 1 of 1, pin 1 of 3

lock vs base: fights undecided, restores undecided, event fights undecided; base vs orig: fights undecided, restores undecided; look class of the candidate: undecided

rest position (Lean restOf; windows that reached the end and rested within 10 px of it, of the windows that reached it): orig 0 of 3, base 1 of 2, lock 2 of 2, pin 3 of 3; pin vs base by position: undecided (insufficient)

pin vs base: fights undecided, restores undecided, event fights undecided; pin vs orig: fights undecided; look class of the pin: undecided; pin writes: 2 of 3 runs never wrote (their fights are 0 by definition)
