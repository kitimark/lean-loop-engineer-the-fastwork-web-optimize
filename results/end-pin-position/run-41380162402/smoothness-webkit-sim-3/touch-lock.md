| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 4 | 0 | {} | {} | 4 | 4 | 2 2 1 1 | 3 3 1 2 | 22 12 3 40 | 22 6 3 39 | 2 2 1 1 | 52530 52280 52580 52220 | 22 6 3 38 | 0 |
| base | 5 | 0 | {} | {"noOpen":1} | 4 | 4 | 4 1 5 3 | 7 1 10 5 | 19 3 56 43 | 19 3 56 43 | 4 1 5 3 | 52220 52280 52420 51970 | 19 3 55 43 | 0 |
| lock | 5 | 0 | {} | {"noOpen":1} | 4 | 4 | 1 1 2 3 | 1 2 3 5 | 43 65 81 38 | 43 65 81 38 | 1 1 2 3 | 52530 52330 52220 52280 | 43 64 81 38 | 0 |
| pin | 4 | 0 | {} | {} | 4 | 0 | 0 0 0 0 | 0 1 1 1 | 0 0 0 0 | 0 0 0 0 | 0 0 0 0 | none none none none | 0 0 0 0 | 4 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock | rest | gap to goal (px) | settle after lift (ms) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | refused | noOpen | 0 |  |  |  |  |  | notReached | 677 | 1190 |
| 2 | lock | 0 | refused | noOpen | 0 |  |  |  |  |  | short | 676 | 1203 |
| 3 | pin | 0 | open |  | 49 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 4 | orig | 0 | open |  | 41 | 3 | 2 | 22 | 22 | 52530 | over | 26 | 0 |
| 5 | pin | 1 | open |  | 67 | 1 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 6 | lock | 1 | open |  | 47 | 1 | 1 | 43 | 43 | 52530 | atEnd | 0 | 47 |
| 7 | base | 1 | open |  | 66 | 7 | 4 | 19 | 19 | 52220 | over | 31 | 0 |
| 8 | orig | 1 | open |  | 60 | 3 | 2 | 12 | 6 | 52280 | atEnd | 1 | 0 |
| 9 | base | 2 | open |  | 53 | 1 | 1 | 3 | 3 | 52280 | atEnd | 1 | 0 |
| 10 | lock | 2 | open |  | 67 | 2 | 1 | 65 | 65 | 52330 | atEnd | 0 | 0 |
| 11 | pin | 2 | open |  | 577 | 1 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 12 | orig | 2 | open |  | 69 | 1 | 1 | 3 | 3 | 52580 | over | 31 | 0 |
| 13 | pin | 3 | open |  | 66 | 1 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 14 | lock | 3 | open |  | 86 | 3 | 2 | 81 | 81 | 52220 | atEnd | 0 | 44 |
| 15 | base | 3 | open |  | 61 | 10 | 5 | 56 | 56 | 52420 | atEnd | 0 | 0 |
| 16 | orig | 3 | open |  | 42 | 2 | 1 | 40 | 39 | 52220 | atEnd | 0 | 0 |
| 17 | base | 4 | open |  | 49 | 5 | 3 | 43 | 43 | 51970 | atEnd | 6 | 0 |
| 18 | lock | 4 | open |  | 1626 | 5 | 3 | 38 | 38 | 52280 | atEnd | 0 | 0 |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | live writes | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 18 | 5 | 4 | 1 | 1 | 0 | 1 | 2 | 0 | 3 | 0 | yes |
| 5 | pin | 25 | 6 | 4 | 1 | 4 | 0 | 3 | 1 | 0 | 5 | 0 | yes |
| 11 | pin | 25 | 4 | 4 | 2 | 5 | 0 | 4 | 1 | 0 | 4 | 0 | yes |
| 13 | pin | 32 | 6 | 4 | 3 | 9 | 0 | 5 | 0 | 1 | 3 | 0 | yes |

lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out: orig 4 of 4, base 4 of 4, lock 4 of 4, pin 0 of 4

lock vs base: fights overlap, restores overlap, event fights overlap; base vs orig: fights overlap, restores overlap; look class of the candidate: look change

rest position (Lean restOf; windows that reached the end and rested within 10 px of it, of the windows that reached it): orig 2 of 4, base 3 of 4, lock 4 of 5, pin 4 of 4; pin vs base by position: same (same)

pin vs base: fights n/a, restores n/a, event fights n/a; pin vs orig: fights n/a; look class of the pin: look change; pin writes: 4 of 4 runs never wrote (their fights are 0 by definition)
