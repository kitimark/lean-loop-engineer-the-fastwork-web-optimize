orig accepted 33 fights sum 63 fights per run 1 0 4 2 1 2 2 3 2 2 1 2 1 0 1 2 2 4 1 1 0 2 4 3 1 3 1 1 1 5 1 4 3 | with lock 33 fights(locked) 1 0 4 2 1 2 2 3 2 2 1 2 1 0 1 2 2 4 1 1 0 2 4 3 1 3 1 1 1 5 1 4 3 | open calls 716
base accepted 30 fights sum 62 fights per run 4 1 1 2 2 3 2 4 1 3 0 1 4 1 1 4 2 5 2 1 2 0 6 1 3 0 1 2 1 2 | with lock 30 fights(locked) 4 1 1 2 2 3 2 4 1 3 0 1 4 1 1 4 2 5 2 1 2 0 6 1 3 0 1 2 1 2 | open calls 779
lock accepted 29 fights sum 40 fights per run 1 1 2 1 1 1 2 1 2 1 1 1 0 0 0 2 1 4 1 1 3 0 1 1 1 2 2 1 5 | with lock 29 fights(locked) 1 1 2 1 1 1 2 1 2 1 1 1 0 0 0 2 1 4 1 1 3 0 1 1 1 2 2 1 5 | open calls 552
pin accepted 29 fights sum 0 fights per run 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 | with lock 4 fights(locked) 0 0 0 0 | open calls 4
pin windows 39 open 29 refused noOpen,tooShort,noOpen,noOpen,tooShort,noOpen,noOpen,noOpen,noOpen
pin trace totals: inactive 233 touches 148 due 42 moved 126 writes 4 touching 99 live 18 onTarget 20 reversal 111 liveWrites 0 ran 38
write window: job 2 window 5 rep 1 state open lock 51850 fights 0 writes 1 live 0 reversal 1
write window: job 2 window 11 rep 2 state open lock 52250 fights 0 writes 1 live 0 reversal 1
write window: job 10 window 11 rep 2 state open lock 52170 fights 0 writes 1 live 0 reversal 0
write window: job 10 window 19 rep 4 state open lock 51890 fights 0 writes 1 live 0 reversal 1
| job | pin vs base fights | verdict (first = base fewer) | base fights | pin fights | base locked | pin locked | pin windows | pin writes | pin live writes |
|---|---|---|---|---|---|---|---|---|---|
| 1 | n/a | insufficient | 4 1 1 2 | 0 0 0 0 0 | 4 of 4 | 0 of 5 | 6 | 0 | 0 |
| 2 | undecided | insufficient | 2 3 2 4 1 | 0 0 0 0 0 0 | 5 of 5 | 2 of 6 | 6 | 2 | 0 |
| 5 | n/a | insufficient | 3 0 1 4 1 1 | 0 0 0 0 0 | 6 of 6 | 0 of 5 | 6 | 0 | 0 |
| 6 | n/a | insufficient | 4 2 5 | 0 0 0 0 0 | 3 of 3 | 0 of 5 | 6 | 0 | 0 |
| 9 | n/a | insufficient | 2 1 2 0 6 | 0 0 0 0 | 5 of 5 | 0 of 4 | 6 | 0 | 0 |
| 10 | undecided | insufficient | 1 3 0 1 | 0 0 0 0 | 4 of 4 | 2 of 4 | 6 | 2 | 0 |
| 11 | undecided | insufficient | 2 1 2 | - | 3 of 3 | 0 of 0 | 2 | 0 | 0 |

across jobs (pin vs base, Lean acrossPin): insufficient; decisive jobs 0 of 7, minSamples 3, agreement needed 0
