| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orig | 0 | 0 | {} | {} | 0 | 0 |  |  |  |  |  |  |  | 0 |
| base | 0 | 0 | {} | {} | 0 | 0 |  |  |  |  |  |  |  | 0 |
| lock | 0 | 0 | {} | {} | 0 | 0 |  |  |  |  |  |  |  | 0 |
| pin | 0 | 0 | {} | {} | 0 | 0 |  |  |  |  |  |  |  | 0 |

lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out: orig 0 of 0, base 0 of 0, lock 0 of 0, pin 0 of 0

lock vs base: fights undecided, restores undecided, event fights undecided; base vs orig: fights undecided, restores undecided; look class of the candidate: undecided

pin vs base: fights undecided, restores undecided, event fights undecided; pin vs orig: fights undecided; look class of the pin: undecided; pin writes: undecided
