| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 6 | 0 | {} | {"tooShort":1} | 5 | 5 | 2 1 2 5 1 | 4 1 3 10 1 | 10 2 26 52 11 | 10 2 19 52 11 | 2 1 2 5 1 | 53000 52290 52330 52530 52530 | 10 2 19 51 11 | 0 |
| base | 6 | 0 | {} | {"noOpen":1} | 5 | 5 | 3 2 2 3 2 | 5 3 4 4 3 | 28 3 14 23 29 | 20 3 14 18 29 | 3 2 2 2 2 | 52330 52530 52470 51920 52280 | 20 3 13 18 29 | 0 |
| lock | 6 | 0 | {} | {"tooShort":1,"noOpen":1} | 4 | 4 | 1 2 1 1 | 1 3 2 2 | 3 6 2 2 | 3 6 2 2 | 1 2 1 1 | 52220 52330 52230 52250 | 3 6 2 2 | 0 |
| pin | 6 | 0 | {} | {} | 6 | 0 | 0 0 0 0 0 0 | 0 1 0 1 1 1 | 0 0 0 0 0 0 | 0 0 0 0 0 0 | 0 0 0 0 0 0 | none none none none none none | 0 0 0 0 0 0 | 6 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock | rest | gap to goal (px) | settle after lift (ms) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | open |  | 77 | 5 | 3 | 28 | 20 | 52330 | atEnd | 6 | 0 |
| 2 | lock | 0 | open |  | 72 | 1 | 1 | 3 | 3 | 52220 | atEnd | 0 | 0 |
| 3 | pin | 0 | open |  | 42 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 4 | orig | 0 | open |  | 77 | 4 | 2 | 10 | 10 | 53000 | over | 73 | 0 |
| 5 | pin | 1 | open |  | 35 | 1 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 6 | lock | 1 | refused | tooShort | 5 |  |  |  |  |  | atEnd | 0 | 246 |
| 7 | base | 1 | open |  | 61 | 3 | 2 | 3 | 3 | 52530 | over | 26 | 0 |
| 8 | orig | 1 | open |  | 49 | 1 | 1 | 2 | 2 | 52290 | atEnd | 2 | 0 |
| 9 | base | 2 | refused | noOpen | 0 |  |  |  |  |  |  |  |  |
| 10 | lock | 2 | refused | noOpen | 0 |  |  |  |  |  |  |  |  |
| 11 | pin | 2 | open |  | 13 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 12 | orig | 2 | refused | tooShort | 4 |  |  |  |  |  | atEnd | 0 | 0 |
| 13 | pin | 3 | open |  | 62 | 1 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 14 | lock | 3 | open |  | 33 | 3 | 2 | 6 | 6 | 52330 | atEnd | 0 | 0 |
| 15 | base | 3 | open |  | 17 | 4 | 2 | 14 | 14 | 52470 | atEnd | 0 | 0 |
| 16 | orig | 3 | open |  | 52 | 3 | 2 | 26 | 19 | 52330 | atEnd | 6 | 0 |
| 17 | base | 4 | open |  | 72 | 4 | 3 | 23 | 18 | 51920 | atEnd | 1 | 0 |
| 18 | lock | 4 | open |  | 53 | 2 | 1 | 2 | 2 | 52230 | atEnd | 4 | 0 |
| 19 | pin | 4 | open |  | 71 | 1 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 20 | orig | 4 | open |  | 57 | 10 | 5 | 52 | 52 | 52530 | atEnd | 0 | 0 |
| 21 | pin | 5 | open |  | 58 | 1 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 22 | lock | 5 | open |  | 54 | 2 | 1 | 2 | 2 | 52250 | atEnd | 2 | 0 |
| 23 | base | 5 | open |  | 75 | 3 | 2 | 29 | 29 | 52280 | atEnd | 1 | 0 |
| 24 | orig | 5 | open |  | 43 | 1 | 1 | 11 | 11 | 52530 | over | 26 | 0 |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | live writes | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 15 | 1 | 4 | 0 | 2 | 0 | 3 | 0 | 1 | 3 | 0 | yes |
| 5 | pin | 29 | 4 | 4 | 3 | 7 | 0 | 5 | 1 | 0 | 4 | 0 | yes |
| 11 | pin | 15 | 1 | 4 | 0 | 2 | 0 | 3 | 0 | 1 | 3 | 0 | yes |
| 13 | pin | 28 | 6 | 4 | 3 | 5 | 0 | 4 | 2 | 0 | 3 | 0 | yes |
| 19 | pin | 27 | 6 | 4 | 2 | 6 | 0 | 3 | 0 | 0 | 5 | 0 | yes |
| 21 | pin | 29 | 5 | 4 | 3 | 7 | 0 | 4 | 1 | 1 | 3 | 0 | yes |

lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out: orig 5 of 5, base 5 of 5, lock 4 of 4, pin 0 of 6

lock vs base: fights overlap, restores overlap, event fights overlap; base vs orig: fights overlap, restores overlap; look class of the candidate: look change

rest position (Lean restOf; windows that reached the end and rested within 10 px of it, of the windows that reached it): orig 4 of 6, base 4 of 5, lock 5 of 5, pin 6 of 6; pin vs base by position: same (same)

pin vs base: fights n/a, restores n/a, event fights n/a; pin vs orig: fights n/a; look class of the pin: look change; pin writes: 6 of 6 runs never wrote (their fights are 0 by definition)
