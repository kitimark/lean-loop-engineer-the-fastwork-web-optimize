| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 6 | 2 | {"pageLost":2} | {} | 4 | 4 | 3 6 4 2 | 6 11 7 4 | 43 30 31 20 | 42 30 31 20 | 3 6 4 2 | 52330 52440 52910 52450 | 41 30 31 19 | 0 |
| base | 6 | 0 | {} | {"noOpen":3} | 3 | 2 | 2 0 1 | 3 0 1 | 50 5 2 | 50 5 2 | 2 0 1 | 52280 51920 53100 | 50 5 2 | 0 |
| lock | 6 | 0 | {} | {"tooShort":1,"noOpen":3} | 2 | 1 | 1 0 | 1 0 | 27 1 | 27 1 | 1 0 | 52580 52250 | 27 1 | 0 |
| pin | 6 | 0 | {} | {} | 6 | 1 | 0 1 0 0 0 0 | 1 2 0 0 1 0 | 0 65 0 0 0 0 | 0 3 0 0 0 0 | 0 0 0 0 0 0 | none 52580 none none none none | 0 1 0 0 0 0 | 5 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock | rest | gap to goal (px) | settle after lift (ms) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 59 | 3 | 2 | 50 | 50 | 52280 | atEnd | 1 | 0 |
| 2 | lock | 0 | refused | tooShort | 7 |  |  |  |  |  | atEnd | 0 | 105 |
| 3 | pin | 0 | open |  | 62 | 1 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 4 | orig | 0 | open |  | 46 | 6 | 3 | 43 | 42 | 52330 | atEnd | 0 | 0 |
| 5 | pin | 1 | open |  | 66 | 2 | 1 | 65 | 3 | 52580 | atEnd | 0 | 0 |
| 6 | lock | 1 | open |  | 55 | 1 | 1 | 27 | 27 | 52580 | atEnd | 0 | 55 |
| 7 | base | 1 | open |  | 23 | 0 | 0 | 5 | 5 | 51920 | atEnd | 1 | 0 |
| 8 | orig | 1 | open |  | 57 | 11 | 6 | 30 | 30 | 52440 | over | 17 | 0 |
| 9 | base | 2 | refused | noOpen | 0 |  |  |  |  |  | short | 674 | 1145 |
| 10 | lock | 2 | refused | noOpen | 0 |  |  |  |  |  | short | 689 | 1243 |
| 11 | pin | 2 | open |  | 44 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 12 | orig | 2 | open |  | 45 | 7 | 4 | 31 | 31 | 52910 | over | 64 | 0 |
| 13 | pin | 3 | open |  | 26 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 14 | lock | 3 | refused | noOpen | 0 |  |  |  |  |  | short | 674 | 1172 |
| 15 | base | 3 | refused | noOpen | 0 |  |  |  |  |  | notReached | 676 | 1206 |
| 16 | orig | 3 | open |  | 22 | 4 | 2 | 20 | 20 | 52450 | atEnd | 0 | 0 |
| 17 | base | 4 | open |  | 87 | 1 | 1 | 2 | 2 | 53100 | over | 83 | 0 |
| 18 | lock | 4 | refused | noOpen | 0 |  |  |  |  |  | notReached | 677 | 1194 |
| 19 | pin | 4 | open |  | 161 | 1 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 20 | orig | 4 | push failed | pageLost |  |  |  |  |  |  |  |  |  |
| 21 | pin | 5 | open |  | 57 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 22 | lock | 5 | open |  | 47 | 0 | 0 | 1 | 1 | 52250 | atEnd | 2 | 0 |
| 23 | base | 5 | refused | noOpen | 0 |  |  |  |  |  | short | 660 | 1039 |
| 24 | orig | 5 | push failed | pageLost |  |  |  |  |  |  |  |  |  |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | live writes | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 23 | 4 | 4 | 1 | 4 | 0 | 4 | 1 | 2 | 2 | 0 | yes |
| 5 | pin | 24 | 5 | 4 | 2 | 2 | 1 | 3 | 1 | 3 | 2 | 0 | yes |
| 11 | pin | 16 | 1 | 4 | 1 | 3 | 0 | 1 | 1 | 0 | 4 | 0 | yes |
| 13 | pin | 17 | 2 | 4 | 1 | 3 | 0 | 1 | 1 | 0 | 4 | 0 | yes |
| 19 | pin | 27 | 4 | 4 | 2 | 6 | 0 | 4 | 1 | 1 | 4 | 0 | yes |
| 21 | pin | 19 | 3 | 4 | 1 | 3 | 0 | 3 | 0 | 0 | 4 | 0 | yes |

lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out: orig 4 of 4, base 3 of 3, lock 2 of 2, pin 1 of 6

lock vs base: fights undecided, restores undecided, event fights undecided; base vs orig: fights overlap, restores overlap; look class of the candidate: undecided

rest position (Lean restOf; windows that reached the end and rested within 10 px of it, of the windows that reached it): orig 2 of 4, base 2 of 5, lock 3 of 5, pin 6 of 6; pin vs base by position: pinBetter (second)

pin vs base: fights undecided, restores undecided, event fights undecided; pin vs orig: fights undecided; look class of the pin: look change; pin writes: 5 of 6 runs never wrote (their fights are 0 by definition)
