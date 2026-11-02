| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 6 | 0 | {} | {"noOpen":1} | 5 | 5 | 1 1 4 3 2 | 1 1 7 5 3 | 4 2 40 29 8 | 4 2 40 29 7 | 1 1 4 3 2 | 52310 52390 52310 52610 52580 | 4 2 40 29 7 | 0 |
| base | 6 | 0 | {} | {"noOpen":1,"tooShort":1} | 4 | 3 | 0 2 3 4 | 0 3 5 7 | 1 31 37 41 | 1 25 37 41 | 0 2 3 3 | 52270 52280 52320 52170 | 1 25 37 41 | 0 |
| lock | 6 | 0 | {} | {} | 6 | 5 | 1 1 0 1 2 5 | 1 1 0 1 3 9 | 6 2 1 4 30 68 | 6 2 1 4 30 68 | 1 1 0 1 2 5 | 52320 52340 52250 52470 51920 52170 | 6 2 1 4 30 68 | 0 |
| pin | 6 | 0 | {} | {"noOpen":1} | 5 | 0 | 0 0 0 0 0 | 0 0 0 1 1 | 0 0 0 0 0 | 0 0 0 0 0 | 0 0 0 0 0 | none none none none none | 0 0 0 0 0 | 5 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock | rest | gap to goal (px) | settle after lift (ms) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 70 | 0 | 0 | 1 | 1 | 52270 | atEnd | 0 | 0 |
| 2 | lock | 0 | open |  | 79 | 1 | 1 | 6 | 6 | 52320 | atEnd | 0 | 52 |
| 3 | pin | 0 | open |  | 30 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 4 | orig | 0 | refused | noOpen | 0 |  |  |  |  |  | short | 676 | 1185 |
| 5 | pin | 1 | open |  | 20 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 6 | lock | 1 | open |  | 36 | 1 | 1 | 2 | 2 | 52340 | atEnd | 0 | 231 |
| 7 | base | 1 | refused | noOpen | 0 |  |  |  |  |  | notReached | 676 | 1222 |
| 8 | orig | 1 | open |  | 48 | 1 | 1 | 4 | 4 | 52310 | atEnd | 4 | 0 |
| 9 | base | 2 | open |  | 52 | 3 | 2 | 31 | 25 | 52280 | atEnd | 1 | 0 |
| 10 | lock | 2 | open |  | 87 | 0 | 0 | 1 | 1 | 52250 | atEnd | 2 | 0 |
| 11 | pin | 2 | open |  | 26 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 12 | orig | 2 | open |  | 55 | 1 | 1 | 2 | 2 | 52390 | over | 12 | 0 |
| 13 | pin | 3 | refused | noOpen | 0 |  |  |  |  |  | short | 676 | 1123 |
| 14 | lock | 3 | open |  | 27 | 1 | 1 | 4 | 4 | 52470 | atEnd | 0 | 0 |
| 15 | base | 3 | open |  | 44 | 5 | 3 | 37 | 37 | 52320 | atEnd | 5 | 0 |
| 16 | orig | 3 | open |  | 70 | 7 | 4 | 40 | 40 | 52310 | atEnd | 4 | 0 |
| 17 | base | 4 | refused | tooShort | 7 |  |  |  |  |  | atEnd | 2 |  |
| 18 | lock | 4 | open |  | 42 | 3 | 2 | 30 | 30 | 51920 | atEnd | 0 | 0 |
| 19 | pin | 4 | open |  | 60 | 1 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 20 | orig | 4 | open |  | 35 | 5 | 3 | 29 | 29 | 52610 | over | 34 | 0 |
| 21 | pin | 5 | open |  | 53 | 1 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 22 | lock | 5 | open |  | 76 | 9 | 5 | 68 | 68 | 52170 | atEnd | 0 | 44 |
| 23 | base | 5 | open |  | 54 | 7 | 4 | 41 | 41 | 52170 | over | 26 | 0 |
| 24 | orig | 5 | open |  | 53 | 3 | 2 | 8 | 7 | 52580 | over | 31 | 0 |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | live writes | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 18 | 2 | 4 | 0 | 3 | 0 | 3 | 0 | 1 | 4 | 0 | yes |
| 5 | pin | 15 | 2 | 4 | 1 | 2 | 0 | 1 | 1 | 0 | 3 | 0 | yes |
| 11 | pin | 16 | 4 | 4 | 0 | 1 | 0 | 3 | 0 | 1 | 2 | 0 | yes |
| 13 | pin | 25 | 20 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | yes |
| 19 | pin | 27 | 4 | 4 | 2 | 7 | 0 | 5 | 0 | 1 | 3 | 0 | yes |
| 21 | pin | 22 | 4 | 4 | 0 | 4 | 0 | 4 | 0 | 0 | 5 | 0 | yes |

lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out: orig 5 of 5, base 4 of 4, lock 6 of 6, pin 0 of 5

lock vs base: fights overlap, restores overlap, event fights overlap; base vs orig: fights overlap, restores overlap; look class of the candidate: look change

rest position (Lean restOf; windows that reached the end and rested within 10 px of it, of the windows that reached it): orig 2 of 6, base 4 of 5, lock 6 of 6, pin 5 of 6; pin vs base by position: same (same)

pin vs base: fights n/a, restores n/a, event fights n/a; pin vs orig: fights n/a; look class of the pin: look change; pin writes: 5 of 5 runs never wrote (their fights are 0 by definition)
