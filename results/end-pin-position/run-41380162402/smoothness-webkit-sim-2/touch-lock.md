| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 6 | 1 | {"pageLost":1} | {} | 5 | 5 | 1 1 1 2 3 | 1 3 2 3 5 | 3 10 60 11 9 | 3 4 60 11 9 | 1 2 1 2 3 | 52530 52320 52580 52280 52280 | 3 4 59 11 9 | 0 |
| base | 6 | 0 | {} | {"tooShort":2} | 4 | 3 | 0 2 1 2 | 0 3 2 3 | 41 3 2 6 | 41 3 2 6 | 0 1 1 2 | 52850 52120 52250 52430 | 40 3 2 6 | 0 |
| lock | 6 | 0 | {} | {} | 6 | 6 | 2 2 1 1 2 1 | 3 3 1 1 3 2 | 9 38 3 2 21 32 | 9 36 3 2 21 32 | 2 2 1 1 2 1 | 52530 52520 51920 52280 52170 52580 | 9 36 3 2 21 31 | 0 |
| pin | 6 | 0 | {} | {} | 6 | 0 | 0 0 0 0 0 0 | 0 0 1 1 1 1 | 0 0 0 0 9 0 | 0 0 0 0 4 0 | 0 0 0 0 0 0 | none none none none 51890 none | 0 0 0 0 1 0 | 5 |

| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock | rest | gap to goal (px) | settle after lift (ms) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | base | 0 | refused | tooShort | 6 |  |  |  |  |  | over | 36 |  |
| 2 | lock | 0 | open |  | 36 | 3 | 2 | 9 | 9 | 52530 | atEnd | 0 | 139 |
| 3 | pin | 0 | open |  | 80 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 4 | orig | 0 | open |  | 58 | 1 | 1 | 3 | 3 | 52530 | over | 26 | 0 |
| 5 | pin | 1 | open |  | 88 | 0 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 6 | lock | 1 | open |  | 58 | 3 | 2 | 38 | 36 | 52520 | atEnd | 0 | 429 |
| 7 | base | 1 | open |  | 41 | 0 | 0 | 41 | 41 | 52850 | atEnd | 0 | 0 |
| 8 | orig | 1 | open |  | 78 | 3 | 1 | 10 | 4 | 52320 | atEnd | 5 | 0 |
| 9 | base | 2 | refused | tooShort | 6 |  |  |  |  |  | atEnd | 1 |  |
| 10 | lock | 2 | open |  | 40 | 1 | 1 | 3 | 3 | 51920 | atEnd | 0 | 0 |
| 11 | pin | 2 | open |  | 47 | 1 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 12 | orig | 2 | push failed | pageLost |  |  |  |  |  |  |  |  |  |
| 13 | pin | 3 | open |  | 90 | 1 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 14 | lock | 3 | open |  | 36 | 1 | 1 | 2 | 2 | 52280 | atEnd | 0 | 0 |
| 15 | base | 3 | open |  | 70 | 3 | 2 | 3 | 3 | 52120 | over | 21 | 0 |
| 16 | orig | 3 | open |  | 62 | 2 | 1 | 60 | 60 | 52580 | atEnd | 0 | 0 |
| 17 | base | 4 | open |  | 68 | 2 | 1 | 2 | 2 | 52250 | atEnd | 2 | 0 |
| 18 | lock | 4 | open |  | 74 | 3 | 2 | 21 | 21 | 52170 | atEnd | 0 | 129 |
| 19 | pin | 4 | open |  | 71 | 1 | 0 | 9 | 4 | 51890 | atEnd | 0 | 0 |
| 20 | orig | 4 | open |  | 59 | 3 | 2 | 11 | 11 | 52280 | atEnd | 1 | 0 |
| 21 | pin | 5 | open |  | 75 | 1 | 0 | 0 | 0 | none | atEnd | 0 | 0 |
| 22 | lock | 5 | open |  | 34 | 2 | 1 | 32 | 32 | 52580 | atEnd | 0 | 0 |
| 23 | base | 5 | open |  | 50 | 3 | 2 | 6 | 6 | 52430 | over | 16 | 0 |
| 24 | orig | 5 | open |  | 62 | 5 | 3 | 9 | 9 | 52280 | atEnd | 1 | 0 |

| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | live writes | ran |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | pin | 17 | 1 | 4 | 0 | 3 | 0 | 3 | 0 | 1 | 4 | 0 | yes |
| 5 | pin | 29 | 4 | 4 | 3 | 6 | 0 | 4 | 2 | 2 | 3 | 0 | yes |
| 11 | pin | 21 | 5 | 4 | 0 | 3 | 0 | 4 | 0 | 0 | 4 | 0 | yes |
| 13 | pin | 23 | 5 | 4 | 1 | 4 | 0 | 3 | 0 | 0 | 5 | 0 | yes |
| 19 | pin | 35 | 5 | 4 | 5 | 7 | 1 | 5 | 3 | 3 | 1 | 0 | yes |
| 21 | pin | 30 | 4 | 4 | 3 | 8 | 0 | 5 | 1 | 1 | 3 | 0 | yes |

lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out: orig 5 of 5, base 4 of 4, lock 6 of 6, pin 1 of 6

lock vs base: fights overlap, restores overlap, event fights overlap; base vs orig: fights overlap, restores overlap; look class of the candidate: look change

rest position (Lean restOf; windows that reached the end and rested within 10 px of it, of the windows that reached it): orig 4 of 5, base 3 of 6, lock 6 of 6, pin 6 of 6; pin vs base by position: pinBetter (second)

pin vs base: fights undecided, restores undecided, event fights undecided; pin vs orig: fights undecided; look class of the pin: look change; pin writes: 5 of 6 runs never wrote (their fights are 0 by definition)
