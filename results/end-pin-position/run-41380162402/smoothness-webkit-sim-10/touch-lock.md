| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 6 | 0 | {} | {} | 6 | 5 | 8 4 1 4 1 0 | 15 7 1 8 3 0 | 70 115 11 51 7 32 | 70 115 11 51 7 32 | 8 4 1 4 1 0 | 52530 52350 52280 52580 52280 52580 | 70 115 11 50 7 31 | 0 |
| base | 6 | 0 | {} | {"tooShort":1} | 5 | 4 | 2 0 1 3 4 | 3 0 1 4 7 | 23 1 21 40 17 | 23 1 21 40 17 | 2 0 1 3 4 | 52590 52560 52530 52280 52170 | 24 1 21 40 17 | 0 |
| lock | 6 | 0 | {} | {"tooShort":1} | 5 | 5 | 4 2 1 1 4 | 7 3 2 1 7 | 73 4 2 4 67 | 73 4 2 4 67 | 4 2 1 1 4 | 52430 52220 52250 52530 51920 | 73 4 2 4 67 | 0 |
| pin | 6 | 0 | {} | {"noOpen":1} | 5 | 0 | 0 0 0 0 0 | 1 1 1 1 1 | 0 0 10 0 0 | 0 0 5 0 0 | 0 0 0 0 0 | none none 52250 none none | 0 0 1 0 0 | 4 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock | rest | gap to goal (px) | settle after lift (ms) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 69 | 3 | 2 | 23 | 23 | 52590 | over | 32 | 0 |
| 2 | lock | 0 | open |  | 98 | 7 | 4 | 73 | 73 | 52430 | atEnd | 0 | 80 |
| 3 | pin | 0 | open |  | 84 | 1 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 4 | orig | 0 | open |  | 86 | 15 | 8 | 70 | 70 | 52530 | over | 26 | 0 |
| 5 | pin | 1 | refused | noOpen | 0 |  |  |  |  |  | short | 676 | 1172 |
| 6 | lock | 1 | refused | tooShort | 6 |  |  |  |  |  | atEnd | 0 | 0 |
| 7 | base | 1 | open |  | 71 | 0 | 0 | 1 | 1 | 52560 | over | 65 | 0 |
| 8 | orig | 1 | open |  | 584 | 7 | 4 | 115 | 115 | 52350 | over | 44 | 0 |
| 9 | base | 2 | refused | tooShort | 7 |  |  |  |  |  | atEnd | 8 |  |
| 10 | lock | 2 | open |  | 63 | 3 | 2 | 4 | 4 | 52220 | atEnd | 0 | 0 |
| 11 | pin | 2 | open |  | 67 | 1 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 12 | orig | 2 | open |  | 66 | 1 | 1 | 11 | 11 | 52280 | atEnd | 1 | 0 |
| 13 | pin | 3 | open |  | 50 | 1 | 0 | 10 | 5 | 52250 | atEnd | 0 | 0 |
| 14 | lock | 3 | open |  | 21 | 2 | 1 | 2 | 2 | 52250 | atEnd | 2 | 0 |
| 15 | base | 3 | open |  | 44 | 1 | 1 | 21 | 21 | 52530 | over | 26 | 0 |
| 16 | orig | 3 | open |  | 56 | 8 | 4 | 51 | 51 | 52580 | atEnd | 0 | 0 |
| 17 | base | 4 | open |  | 56 | 4 | 3 | 40 | 40 | 52280 | atEnd | 1 | 0 |
| 18 | lock | 4 | open |  | 52 | 1 | 1 | 4 | 4 | 52530 | atEnd | 0 | 0 |
| 19 | pin | 4 | open |  | 85 | 1 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 20 | orig | 4 | open |  | 40 | 3 | 1 | 7 | 7 | 52280 | atEnd | 1 | 0 |
| 21 | pin | 5 | open |  | 74 | 1 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 22 | lock | 5 | open |  | 72 | 7 | 4 | 67 | 67 | 51920 | atEnd | 0 | 0 |
| 23 | base | 5 | open |  | 60 | 7 | 4 | 17 | 17 | 52170 | over | 26 | 0 |
| 24 | orig | 5 | open |  | 32 | 0 | 0 | 32 | 32 | 52580 | atEnd | 0 | 0 |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | live writes | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 22 | 2 | 4 | 1 | 5 | 0 | 4 | 0 | 0 | 5 | 0 | yes |
| 5 | pin | 20 | 15 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | yes |
| 11 | pin | 24 | 5 | 4 | 2 | 5 | 0 | 3 | 0 | 0 | 4 | 0 | yes |
| 13 | pin | 30 | 4 | 4 | 4 | 5 | 1 | 4 | 3 | 3 | 1 | 0 | yes |
| 19 | pin | 26 | 6 | 4 | 0 | 5 | 0 | 4 | 0 | 0 | 6 | 0 | yes |
| 21 | pin | 24 | 6 | 4 | 0 | 4 | 0 | 4 | 0 | 0 | 5 | 0 | yes |

lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out: orig 6 of 6, base 5 of 5, lock 5 of 5, pin 1 of 5

lock vs base: fights overlap, restores overlap, event fights overlap; base vs orig: fights overlap, restores overlap; look class of the candidate: look change

rest position (Lean restOf; windows that reached the end and rested within 10 px of it, of the windows that reached it): orig 4 of 6, base 2 of 6, lock 6 of 6, pin 5 of 6; pin vs base by position: pinBetter (second)

pin vs base: fights undecided, restores undecided, event fights undecided; pin vs orig: fights undecided; look class of the pin: look change; pin writes: 4 of 5 runs never wrote (their fights are 0 by definition)
