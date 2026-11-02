| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 4 | 0 | {} | {"noOpen":1} | 3 | 3 | 2 1 1 | 4 1 2 | 39 3 2 | 39 3 2 | 2 1 1 | 52580 52790 52250 | 38 3 2 | 0 |
| base | 4 | 0 | {} | {"noOpen":1} | 3 | 3 | 3 1 4 | 5 2 7 | 39 2 44 | 39 2 44 | 3 1 4 | 51970 51890 52160 | 39 2 44 | 0 |
| lock | 4 | 0 | {} | {"noOpen":3} | 1 | 0 | 0 | 1 | 14 | 14 | 0 | 53230 | 13 | 0 |
| pin | 4 | 0 | {} | {"noOpen":3,"tooShort":1} | 0 | 0 |  |  |  |  |  |  |  | 0 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock | rest | gap to goal (px) | settle after lift (ms) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | refused | noOpen | 0 |  |  |  |  |  | notReached | 743 | 1133 |
| 2 | lock | 0 | refused | noOpen | 0 |  |  |  |  |  | short | 676 | 1124 |
| 3 | pin | 0 | refused | noOpen | 0 |  |  |  |  |  | notReached | 735 | 1439 |
| 4 | orig | 0 | refused | noOpen | 0 |  |  |  |  |  | notReached | 726 | 1306 |
| 5 | pin | 1 | refused | tooShort | 6 |  |  |  |  |  | atEnd | 0 | 0 |
| 6 | lock | 1 | refused | noOpen | 0 |  |  |  |  |  | short | 678 | 1274 |
| 7 | base | 1 | open |  | 45 | 5 | 3 | 39 | 39 | 51970 | atEnd | 6 | 0 |
| 8 | orig | 1 | open |  | 42 | 4 | 2 | 39 | 39 | 52580 | atEnd | 0 | 0 |
| 9 | base | 2 | open |  | 21 | 2 | 1 | 2 | 2 | 51890 | atEnd | 2 | 0 |
| 10 | lock | 2 | refused | noOpen | 0 |  |  |  |  |  | notReached | 676 | 1120 |
| 11 | pin | 2 | refused | noOpen | 0 |  |  |  |  |  |  |  |  |
| 12 | orig | 2 | open |  | 20 | 1 | 1 | 3 | 3 | 52790 | over | 52 | 0 |
| 13 | pin | 3 | refused | noOpen | 0 |  |  |  |  |  | short | 677 | 1006 |
| 14 | lock | 3 | open |  | 15 | 1 | 0 | 14 | 14 | 53230 | atEnd | 0 | 0 |
| 15 | base | 3 | open |  | 48 | 7 | 4 | 44 | 44 | 52160 | atEnd | 0 | 96 |
| 16 | orig | 3 | open |  | 44 | 2 | 1 | 2 | 2 | 52250 | atEnd | 2 | 0 |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | live writes | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 23 | 18 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | yes |
| 5 | pin | 15 | 2 | 4 | 1 | 1 | 1 | 2 | 1 | 1 | 1 | 0 | yes |
| 11 | pin | 15 | 3 | 4 | 1 | 2 | 0 | 1 | 1 | 0 | 3 | 0 | yes |
| 13 | pin | 22 | 17 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | yes |

lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out: orig 3 of 3, base 3 of 3, lock 1 of 1, pin 0 of 0

lock vs base: fights undecided, restores undecided, event fights undecided; base vs orig: fights overlap, restores overlap; look class of the candidate: undecided

rest position (Lean restOf; windows that reached the end and rested within 10 px of it, of the windows that reached it): orig 2 of 3, base 3 of 3, lock 1 of 3, pin 1 of 2; pin vs base by position: undecided (insufficient)

pin vs base: fights undecided, restores undecided, event fights undecided; pin vs orig: fights undecided; look class of the pin: undecided; pin writes: undecided
