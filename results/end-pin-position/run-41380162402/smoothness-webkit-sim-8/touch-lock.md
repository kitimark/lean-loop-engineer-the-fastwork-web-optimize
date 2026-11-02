| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 3 | 0 | {} | {} | 3 | 2 | 0 1 4 | 0 2 7 | 35 6 105 | 35 6 105 | 0 1 4 | 52330 52760 52400 | 34 6 105 | 0 |
| base | 3 | 0 | {} | {"noOpen":1} | 2 | 2 | 2 3 | 3 6 | 10 43 | 10 42 | 2 3 | 52570 52580 | 10 42 | 0 |
| lock | 3 | 0 | {} | {} | 3 | 2 | 0 1 1 | 0 1 2 | 14 15 45 | 14 15 45 | 0 1 1 | 52800 52460 51970 | 13 15 44 | 0 |
| pin | 4 | 0 | {} | {} | 4 | 0 | 0 0 0 0 | 0 0 0 0 | 0 0 0 0 | 0 0 0 0 | 0 0 0 0 | none none none none | 0 0 0 0 | 4 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock | rest | gap to goal (px) | settle after lift (ms) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 51 | 3 | 2 | 10 | 10 | 52570 | over | 30 | 0 |
| 2 | lock | 0 | open |  | 14 | 0 | 0 | 14 | 14 | 52800 | atEnd | 0 | 0 |
| 3 | pin | 0 | open |  | 31 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 4 | orig | 0 | open |  | 35 | 0 | 0 | 35 | 35 | 52330 | atEnd | 0 | 0 |
| 5 | pin | 1 | open |  | 288 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 6 | lock | 1 | open |  | 58 | 1 | 1 | 15 | 15 | 52460 | atEnd | 0 | 530 |
| 7 | base | 1 | refused | noOpen | 0 |  |  |  |  |  | short | 676 | 1436 |
| 8 | orig | 1 | open |  | 32 | 2 | 1 | 6 | 6 | 52760 | over | 49 | 0 |
| 9 | base | 2 | open |  | 47 | 6 | 3 | 43 | 42 | 52580 | atEnd | 0 | 0 |
| 10 | lock | 2 | open |  | 46 | 2 | 1 | 45 | 45 | 51970 | atEnd | 0 | 0 |
| 11 | pin | 2 | open |  | 18 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 12 | orig | 2 | open |  | 137 | 7 | 4 | 105 | 105 | 52400 | over | 13 | 0 |
| 13 | pin | 3 | open |  | 12 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | live writes | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 17 | 4 | 4 | 1 | 1 | 0 | 1 | 1 | 0 | 4 | 0 | yes |
| 5 | pin | 15 | 3 | 4 | 0 | 1 | 0 | 3 | 0 | 1 | 2 | 0 | yes |
| 11 | pin | 18 | 3 | 4 | 1 | 3 | 0 | 1 | 1 | 0 | 4 | 0 | yes |
| 13 | pin | 14 | 1 | 4 | 0 | 2 | 0 | 1 | 1 | 1 | 3 | 0 | yes |

lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out: orig 3 of 3, base 2 of 2, lock 3 of 3, pin 0 of 4

lock vs base: fights undecided, restores undecided, event fights undecided; base vs orig: fights undecided, restores undecided; look class of the candidate: undecided

rest position (Lean restOf; windows that reached the end and rested within 10 px of it, of the windows that reached it): orig 1 of 3, base 1 of 3, lock 3 of 3, pin 4 of 4; pin vs base by position: pinBetter (second)

pin vs base: fights n/a, restores n/a, event fights n/a; pin vs orig: fights n/a; look class of the pin: undecided; pin writes: 4 of 4 runs never wrote (their fights are 0 by definition)
