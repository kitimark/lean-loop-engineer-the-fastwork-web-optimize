| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 4 | 0 | {} | {} | 4 | 4 | 2 1 1 2 | 3 1 2 3 | 15 21 38 14 | 15 21 38 14 | 2 1 1 2 | 52810 52480 52480 52320 | 15 21 37 14 | 0 |
| base | 5 | 0 | {} | {} | 5 | 5 | 1 2 1 1 3 | 1 4 1 1 6 | 2 30 29 8 46 | 2 30 29 8 46 | 1 2 1 1 3 | 52510 52530 52000 53040 52290 | 2 31 29 8 45 | 0 |
| lock | 5 | 1 | {"pageLost":1} | {} | 4 | 4 | 1 3 2 4 | 1 5 3 7 | 3 66 8 81 | 3 66 8 81 | 1 3 2 4 | 52660 52380 52570 52180 | 3 66 8 81 | 0 |
| pin | 4 | 0 | {} | {} | 4 | 0 | 0 0 0 0 | 0 0 0 0 | 0 0 0 0 | 0 0 0 0 | 0 0 0 0 | none none none none | 0 0 0 0 | 4 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock | rest | gap to goal (px) | settle after lift (ms) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 63 | 1 | 1 | 2 | 2 | 52510 | over | 24 | 0 |
| 2 | lock | 0 | open |  | 58 | 1 | 1 | 3 | 3 | 52660 | atEnd | 0 | 45 |
| 3 | pin | 0 | open |  | 44 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 4 | orig | 0 | open |  | 52 | 3 | 2 | 15 | 15 | 52810 | over | 54 | 0 |
| 5 | pin | 1 | open |  | 61 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 6 | lock | 1 | open |  | 72 | 5 | 3 | 66 | 66 | 52380 | atEnd | 0 | 14 |
| 7 | base | 1 | open |  | 44 | 4 | 2 | 30 | 30 | 52530 | over | 26 | 0 |
| 8 | orig | 1 | open |  | 65 | 1 | 1 | 21 | 21 | 52480 | over | 21 | 0 |
| 9 | base | 2 | open |  | 34 | 1 | 1 | 29 | 29 | 52000 | atEnd | 9 | 0 |
| 10 | lock | 2 | open |  | 129 | 3 | 2 | 8 | 8 | 52570 | atEnd | 0 | 655 |
| 11 | pin | 2 | open |  | 62 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 12 | orig | 2 | open |  | 40 | 2 | 1 | 38 | 38 | 52480 | atEnd | 0 | 0 |
| 13 | pin | 3 | open |  | 83 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 14 | lock | 3 | open |  | 108 | 7 | 4 | 81 | 81 | 52180 | atEnd | 0 | 68 |
| 15 | base | 3 | open |  | 13 | 1 | 1 | 8 | 8 | 53040 | over | 77 | 0 |
| 16 | orig | 3 | open |  | 109 | 3 | 2 | 14 | 14 | 52320 | atEnd | 5 | 0 |
| 17 | base | 4 | open |  | 50 | 6 | 3 | 46 | 46 | 52290 | atEnd | 0 | 0 |
| 18 | lock | 4 | push failed | pageLost |  |  |  |  |  |  |  |  |  |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | live writes | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 20 | 4 | 4 | 0 | 3 | 0 | 4 | 0 | 0 | 4 | 0 | yes |
| 5 | pin | 21 | 2 | 4 | 2 | 5 | 0 | 3 | 0 | 0 | 4 | 0 | yes |
| 11 | pin | 24 | 5 | 4 | 2 | 4 | 0 | 3 | 1 | 0 | 4 | 0 | yes |
| 13 | pin | 24 | 5 | 4 | 2 | 5 | 0 | 3 | 0 | 0 | 4 | 0 | yes |

lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out: orig 4 of 4, base 5 of 5, lock 4 of 4, pin 0 of 4

lock vs base: fights overlap, restores overlap, event fights overlap; base vs orig: fights overlap, restores overlap; look class of the candidate: look change

rest position (Lean restOf; windows that reached the end and rested within 10 px of it, of the windows that reached it): orig 2 of 4, base 2 of 5, lock 4 of 4, pin 4 of 4; pin vs base by position: pinBetter (second)

pin vs base: fights n/a, restores n/a, event fights n/a; pin vs orig: fights n/a; look class of the pin: look change; pin writes: 4 of 4 runs never wrote (their fights are 0 by definition)
