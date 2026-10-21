### Runs (run 39527779967, commit f3ee5ee0)

- chromium r1-s1 (156.0.8078.4): 8 probes
- chromium r1-s2 (156.0.8078.4): 7 probes
- chromium r1-s3 (156.0.8078.4): 7 probes
- chromium r2-s1 (156.0.8078.4): 8 probes
- chromium r2-s2 (156.0.8078.4): 7 probes
- chromium r2-s3 (156.0.8078.4): 7 probes
- chromium r3-s1 (156.0.8078.4): 8 probes
- chromium r3-s2 (156.0.8078.4): 7 probes
- chromium r3-s3 (156.0.8078.4): 7 probes
- playwright-webkit r1-s1 (WebKit 27.2 (playwright-core 1.64.1)): 8 probes
- playwright-webkit r1-s2 (WebKit 27.2 (playwright-core 1.64.1)): 7 probes
- playwright-webkit r1-s3 (WebKit 27.2 (playwright-core 1.64.1)): 7 probes
- playwright-webkit r2-s1 (WebKit 27.2 (playwright-core 1.64.1)): 8 probes
- playwright-webkit r2-s2 (WebKit 27.2 (playwright-core 1.64.1)): 7 probes
- playwright-webkit r2-s3 (WebKit 27.2 (playwright-core 1.64.1)): 7 probes
- playwright-webkit r3-s1 (WebKit 27.2 (playwright-core 1.64.1)): 8 probes
- playwright-webkit r3-s2 (WebKit 27.2 (playwright-core 1.64.1)): 7 probes
- playwright-webkit r3-s3 (WebKit 27.2 (playwright-core 1.64.1)): 7 probes

### Coverage (run 39527779967, commit f3ee5ee0)

Probed width x DPR pairs: 22 of 68 in the gate matrix (124 probes). Every verdict below holds at the 22 probe ids of arm-probes.json only; other gate probes at a probed pair (reduced motion, hover/pointer crosses, other heights) are not probed.

- probed: DPR 1: 320 401 481 601 721 861 1031 1101 1201 1280 1512; DPR 2: 601 861 1024 1031 1200 1201 1512; DPR 3: 320 401 481 932
- not probed: DPR 1: 319 400 461 462 480 600 640 641 720 860 960 961 1000 1001 1030 1100 1200 1279 1440 1511; DPR 2: 600 600.5 640 640.5 641 720 721 860 860.5 960 961 1000 1000.5 1001 1030 1100 1101 1279 1280 1511; DPR 3: 319 400 430 461 462 480

### Decision per part, policy exact (run 39527779967, commit f3ee5ee0)

| part | chromium (cells with a copy of all, worst ppm) | playwright-webkit (cells with a copy of all, worst ppm) | both engines |
|---|---|---|---|
| hero | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |
| hero.deck | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |
| hero.exit | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |
| hero.orbit | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |
| morph.columns | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |
| morph.panel | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |
| people.card | shippedFails (46 of 66, 4349) | shippedFails (35 of 66, 2649) | shippedFails |
| people.carousel | shippedFails (46 of 66, 33739) | shippedFails (35 of 66, 126609) | shippedFails |
| people.deck | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |
| people.o | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |

### Decision per part, policy fit (run 39527779967, commit f3ee5ee0)

| part | chromium (cells with a copy of all, worst ppm) | playwright-webkit (cells with a copy of all, worst ppm) | both engines |
|---|---|---|---|
| hero | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |
| hero.deck | undecided (18 of 66, 2722) | undecided (18 of 66, 18267) | undecided |
| hero.exit | undecided (66 of 66, 10185) | undecided (66 of 66, 38009) | undecided |
| hero.orbit | undecided (48 of 66, 12109) | undecided (48 of 66, 38382) | undecided |
| morph.columns | lookChange (66 of 66, 1239) | lookChange (66 of 66, 24684) | lookChange |
| morph.panel | lookChange (66 of 66, 1125) | lookChange (66 of 66, 22547) | lookChange |
| people.card | lookChange (66 of 66, 27870) | shippedFails (66 of 66, 32499) | lookChange |
| people.carousel | lookChange (66 of 66, 124036) | lookChange (66 of 66, 185489) | lookChange |
| people.deck | shippedFails (66 of 66, 65573) | lookChange (66 of 66, 168244) | lookChange |
| people.o | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |

### What the cells did (run 39527779967, commit f3ee5ee0) (base verdict > drawn verdict; open = unsettled, invalid, nc or error; disputed = the reps did not agree on the file's copy, left out of the columns)

| policy | engine | part | cells with a copy | pass>pass | pass>fail | fail>pass | fail>fail | pass>open | fail>open | open>pass | open>fail | open>open | disputed | error | mean saving KiB per cell |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| exact | chromium | people.card | 46 | 1 | 0 | 0 | 25 | 0 | 0 | 0 | 0 | 0 | 20 | 0 | 1700.3 |
| exact | chromium | people.carousel | 46 | 0 | 0 | 0 | 12 | 1 | 0 | 0 | 0 | 13 | 20 | 0 | 1700.3 |
| exact | playwright-webkit | people.card | 35 | 0 | 0 | 0 | 8 | 0 | 0 | 0 | 0 | 0 | 27 | 0 | 1442.0 |
| exact | playwright-webkit | people.carousel | 35 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 6 | 27 | 0 | 1442.0 |
| fit | chromium | hero.deck | 18 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 18 | 0 | 0 | 15418.4 |
| fit | chromium | hero.exit | 66 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 66 | 0 | 0 | 36682.0 |
| fit | chromium | hero.orbit | 48 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 48 | 0 | 0 | 44655.9 |
| fit | chromium | morph.columns | 66 | 34 | 11 | 6 | 15 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 41169.2 |
| fit | chromium | morph.panel | 66 | 34 | 11 | 7 | 14 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 41169.2 |
| fit | chromium | people.card | 66 | 0 | 3 | 0 | 39 | 0 | 0 | 0 | 0 | 24 | 0 | 0 | 94859.9 |
| fit | chromium | people.carousel | 66 | 5 | 4 | 4 | 17 | 2 | 3 | 4 | 0 | 27 | 0 | 0 | 7101.8 |
| fit | chromium | people.deck | 66 | 0 | 0 | 0 | 3 | 0 | 0 | 0 | 0 | 63 | 0 | 0 | 91951.0 |
| fit | playwright-webkit | hero.deck | 18 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 18 | 0 | 0 | 15417.8 |
| fit | playwright-webkit | hero.exit | 66 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 66 | 0 | 0 | 34063.9 |
| fit | playwright-webkit | hero.orbit | 48 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 48 | 0 | 0 | 41056.2 |
| fit | playwright-webkit | morph.columns | 66 | 21 | 45 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 41169.5 |
| fit | playwright-webkit | morph.panel | 66 | 27 | 39 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 41169.5 |
| fit | playwright-webkit | people.card | 66 | 0 | 0 | 0 | 66 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 93937.4 |
| fit | playwright-webkit | people.carousel | 66 | 0 | 2 | 0 | 1 | 1 | 13 | 1 | 16 | 32 | 0 | 0 | 7108.7 |
| fit | playwright-webkit | people.deck | 66 | 3 | 3 | 0 | 33 | 0 | 0 | 0 | 0 | 27 | 0 | 0 | 90908.0 |

### Cells where the copy fails and the baseline passes (run 39527779967, commit f3ee5ee0) (reps with that / reps with a copy; per rep: base>drawn initials, drawn ppm / delta, ~ = disputed)

| policy | engine | probe | width@dpr | part | reps | per rep | files |
|---|---|---|---|---|---|---|---|
| fit | chromium | desk-1031 | 1031@1 | morph.columns | 1/3 | p>p 403/53, p>f 806/102, p>p 113/51 | 21 |
| fit | chromium | desk-1031 | 1031@1 | morph.panel | 1/3 | p>p 375/52, p>f 683/106, p>p 34/39 | 21 |
| fit | chromium | desk-1031 | 1031@1 | people.carousel | 2/3 | p>f 5750/200, p>f 5493/200, u>p 0/0 | 6 |
| fit | chromium | desk-1101 | 1101@1 | morph.columns | 1/3 | p>p 820/51, p>f 1013/103, f>f 997/103 | 21 |
| fit | chromium | desk-1101 | 1101@1 | morph.panel | 1/3 | p>p 461/52, p>f 751/104, f>f 700/104 | 21 |
| fit | chromium | desk-1201 | 1201@1 | morph.columns | 1/3 | p>f 1174/103, f>f 1142/103, p>p 96/59 | 21 |
| fit | chromium | desk-1201 | 1201@1 | morph.panel | 1/3 | p>f 819/104, f>f 939/104, p>p 0/0 | 21 |
| fit | chromium | desk-861 | 861@1 | morph.columns | 2/3 | p>f 1051/106, p>f 1109/106, p>p 272/51 | 21 |
| fit | chromium | desk-861 | 861@1 | morph.panel | 2/3 | p>f 640/101, p>f 702/101, p>p 103/51 | 21 |
| fit | chromium | desk-861 | 861@1 | people.carousel | 1/3 | f>p 0/0, f>p 0/0, p>f 8933/203 | 6 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.columns | 1/3 | f>f 394/201, f>f 32/102, p>f 483/201 | 16 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.panel | 1/3 | f>f 234/203, f>f 21/92, p>f 324/203 | 16 |
| fit | chromium | touch-1031 | 1031@2 | morph.columns | 1/3 | p>f 117/84, f>f 185/183, f>f 60/101 | 17 |
| fit | chromium | touch-1031 | 1031@2 | morph.panel | 1/3 | p>f 90/84, f>f 218/183, f>f 51/101 | 17 |
| fit | chromium | touch-1201 | 1201@2 | morph.columns | 1/3 | f>f 362/201, p>p 165/44, p>f 257/84 | 16 |
| fit | chromium | touch-1201 | 1201@2 | morph.panel | 1/3 | f>f 205/203, p>p 4/31, p>f 55/84 | 16 |
| fit | chromium | touch-1512 | 1512@2 | morph.columns | 1/3 | f>p 366/58, p>f 543/185, f>f 306/201 | 16 |
| fit | chromium | touch-1512 | 1512@2 | morph.panel | 1/3 | f>p 21/33, p>f 68/147, f>f 209/210 | 16 |
| fit | chromium | touch-1512 | 1512@2 | people.carousel | 1/3 | f>f 12358/173, u>u 115/46, p>f 61725/244 | 6 |
| fit | chromium | touch-320 | 320@3 | people.card | 3/3 | p>f 9956/125, p>f 9954/125, p>f 9954/125 | 13 |
| fit | chromium | touch-481 | 481@3 | morph.columns | 1/3 | f>p 0/0, f>p 5/29, p>f 24/151 | 8 |
| fit | chromium | touch-481 | 481@3 | morph.panel | 1/3 | f>p 0/0, f>p 5/29, p>f 26/151 | 8 |
| fit | chromium | touch-601 | 601@2 | morph.columns | 1/3 | f>f 457/139, p>p 207/37, p>f 336/77 | 9 |
| fit | chromium | touch-601 | 601@2 | morph.panel | 1/3 | f>f 411/136, p>p 0/0, p>f 219/75 | 9 |
| fit | playwright-webkit | desk-1031 | 1031@1 | morph.columns | 3/3 | p>f 23654/100, p>f 20012/103, p>f 20012/103 | 21 |
| fit | playwright-webkit | desk-1031 | 1031@1 | morph.panel | 3/3 | p>f 22547/89, p>f 17836/90, p>f 17836/90 | 21 |
| fit | playwright-webkit | desk-1101 | 1101@1 | morph.columns | 3/3 | p>f 24684/104, p>f 24009/101, p>f 24459/116 | 21 |
| fit | playwright-webkit | desk-1101 | 1101@1 | morph.panel | 3/3 | p>f 20993/92, p>f 20157/95, p>f 20601/96 | 21 |
| fit | playwright-webkit | desk-1101 | 1101@1 | people.carousel | 1/3 | f>u 75922/255, u>f 67038/218, p>f 23921/255 | 6 |
| fit | playwright-webkit | desk-1201 | 1201@1 | morph.columns | 3/3 | p>f 9600/82, p>f 9600/82, p>f 9600/82 | 21 |
| fit | playwright-webkit | desk-1201 | 1201@1 | morph.panel | 3/3 | p>f 7049/75, p>f 7049/75, p>f 7049/75 | 21 |
| fit | playwright-webkit | desk-1280 | 1280@1 | morph.columns | 3/3 | p>f 22375/99, p>f 21570/105, p>f 22246/99 | 21 |
| fit | playwright-webkit | desk-1280 | 1280@1 | morph.panel | 3/3 | p>f 17902/92, p>f 17220/87, p>f 17936/92 | 21 |
| fit | playwright-webkit | desk-1512 | 1512@1 | morph.columns | 3/3 | p>f 4749/80, p>f 4749/80, p>f 4749/80 | 21 |
| fit | playwright-webkit | desk-601 | 601@1 | morph.columns | 3/3 | p>f 23661/111, p>f 22625/107, p>f 23661/111 | 13 |
| fit | playwright-webkit | desk-601 | 601@1 | morph.panel | 3/3 | p>f 12724/101, p>f 12102/103, p>f 12724/101 | 13 |
| fit | playwright-webkit | desk-721 | 721@1 | morph.columns | 3/3 | p>f 11114/76, p>f 20155/89, p>f 10407/77 | 21 |
| fit | playwright-webkit | desk-721 | 721@1 | morph.panel | 3/3 | p>f 7977/93, p>f 13362/99, p>f 7130/91 | 21 |
| fit | playwright-webkit | desk-861 | 861@1 | morph.columns | 3/3 | p>f 22588/101, p>f 11985/84, p>f 21674/101 | 21 |
| fit | playwright-webkit | desk-861 | 861@1 | morph.panel | 3/3 | p>f 16336/90, p>f 9004/82, p>f 16377/90 | 21 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | morph.columns | 3/3 | p>f 6146/126, p>f 6146/126, p>f 6146/126 | 17 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | morph.panel | 3/3 | p>f 3018/99, p>f 3018/99, p>f 3018/99 | 17 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.columns | 3/3 | p>f 15139/112, p>f 15139/112, p>f 15139/112 | 16 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.panel | 3/3 | p>f 10835/97, p>f 10835/97, p>f 10835/97 | 16 |
| fit | playwright-webkit | touch-1031 | 1031@2 | morph.columns | 3/3 | p>f 15646/110, p>f 15646/110, p>f 15646/110 | 17 |
| fit | playwright-webkit | touch-1031 | 1031@2 | morph.panel | 3/3 | p>f 12600/99, p>f 12600/99, p>f 12600/99 | 17 |
| fit | playwright-webkit | touch-1031 | 1031@2 | people.deck | 3/3 | p>f 5375/85, p>f 2194/70, p>f 2433/70 | 8 |
| fit | playwright-webkit | touch-1201 | 1201@2 | morph.columns | 3/3 | p>f 15148/114, p>f 15148/114, p>f 15148/114 | 16 |
| fit | playwright-webkit | touch-1201 | 1201@2 | morph.panel | 3/3 | p>f 10744/97, p>f 10744/97, p>f 10744/97 | 16 |
| fit | playwright-webkit | touch-1512 | 1512@2 | morph.columns | 3/3 | p>f 5739/115, p>f 5739/115, p>f 5739/115 | 16 |
| fit | playwright-webkit | touch-601 | 601@2 | morph.columns | 3/3 | p>f 15492/120, p>f 15492/120, p>f 15492/120 | 9 |
| fit | playwright-webkit | touch-601 | 601@2 | morph.panel | 3/3 | p>f 8492/118, p>f 8492/118, p>f 8492/118 | 9 |
| fit | playwright-webkit | touch-861 | 861@2 | morph.columns | 3/3 | p>f 16859/120, p>f 16859/120, p>f 16859/120 | 21 |
| fit | playwright-webkit | touch-861 | 861@2 | morph.panel | 3/3 | p>f 11250/108, p>f 11250/108, p>f 11250/108 | 21 |
| fit | playwright-webkit | touch-861 | 861@2 | people.carousel | 1/3 | p>u 71868/227, u>f 78606/234, p>f 1224/72 | 6 |

### Decoded saving per part and probe (run 39527779967, commit f3ee5ee0) (KiB, 4 bytes per pixel, natural size minus copy size; decision of the part in brackets)

| policy | engine | part | decision | files (max) | KiB min | KiB median | KiB max | probes |
|---|---|---|---|---|---|---|---|---|
| exact | chromium | people.card | shippedFails | 2 | 884.0 | 1768.0 | 1792.0 | 11 |
| exact | chromium | people.carousel | shippedFails | 2 | 884.0 | 1768.0 | 1792.0 | 11 |
| exact | playwright-webkit | people.card | shippedFails | 2 | 864.0 | 1768.0 | 1792.0 | 4 |
| exact | playwright-webkit | people.carousel | shippedFails | 2 | 864.0 | 1768.0 | 1792.0 | 4 |
| fit | chromium | hero.deck | undecided | 8 | 13690.7 | 17146.0 | 17146.0 | 6 |
| fit | chromium | hero.exit | undecided | 20 | 13690.7 | 43300.5 | 46630.7 | 22 |
| fit | chromium | hero.orbit | undecided | 20 | 38541.4 | 46433.4 | 46630.7 | 16 |
| fit | chromium | morph.columns | lookChange | 21 | 19691.0 | 43913.2 | 58645.0 | 22 |
| fit | chromium | morph.panel | lookChange | 21 | 19691.0 | 43913.2 | 58645.0 | 22 |
| fit | chromium | people.card | lookChange | 41 | 12500.9 | 43257.8 | 187105.3 | 22 |
| fit | chromium | people.carousel | lookChange | 6 | 6914.9 | 7197.8 | 7246.0 | 22 |
| fit | chromium | people.deck | shippedFails | 39 | 9044.9 | 39673.8 | 184613.3 | 22 |
| fit | playwright-webkit | hero.deck | undecided | 8 | 13689.6 | 17146.0 | 17146.0 | 6 |
| fit | playwright-webkit | hero.exit | undecided | 20 | 13689.6 | 37181.1 | 47131.7 | 22 |
| fit | playwright-webkit | hero.orbit | undecided | 20 | 24829.8 | 45095.2 | 47131.7 | 16 |
| fit | playwright-webkit | morph.columns | lookChange | 21 | 19691.0 | 43913.2 | 58645.0 | 22 |
| fit | playwright-webkit | morph.panel | lookChange | 21 | 19691.0 | 43913.2 | 58645.0 | 22 |
| fit | playwright-webkit | people.card | shippedFails | 41 | 12508.8 | 48455.4 | 187091.8 | 22 |
| fit | playwright-webkit | people.carousel | lookChange | 6 | 6922.3 | 7196.6 | 7246.0 | 22 |
| fit | playwright-webkit | people.deck | lookChange | 39 | 9052.8 | 44871.4 | 184599.8 | 22 |

### Cells (run 39527779967, commit f3ee5ee0) (probe, base verdict, drawn verdict, ppm of the drawn run, files with a copy, decoded saving KiB)

| policy | engine | probe | width@dpr | part | rep | base | drawn | drawn ppm / delta | files | saving KiB |
|---|---|---|---|---|---|---|---|---|---|---|
| exact | chromium | desk-1512 | 1512@1 | people.card | r1 | unsettled | **unsettled** ~ | 2604 / 186 | 1 | 896.0 |
| exact | chromium | desk-1512 | 1512@1 | people.carousel | r1 | fail | **fail** ~ | 21463 / 212 | 1 | 896.0 |
| fit | chromium | desk-1512 | 1512@1 | hero.orbit | r1 | unsettled | **unsettled** | 5090 / 124 | 20 | 46450.5 |
| fit | chromium | desk-1512 | 1512@1 | hero.exit | r1 | unsettled | **unsettled** | 5007 / 124 | 20 | 46450.5 |
| fit | chromium | desk-1512 | 1512@1 | morph.panel | r1 | fail | **pass** | 0 / 0 | 21 | 53541.6 |
| fit | chromium | desk-1512 | 1512@1 | morph.columns | r1 | fail | **pass** | 451 / 50 | 21 | 53541.6 |
| fit | chromium | desk-1512 | 1512@1 | people.card | r1 | unsettled | **unsettled** | 15268 / 177 | 41 | 182580.4 |
| fit | chromium | desk-1512 | 1512@1 | people.carousel | r1 | fail | **unsettled** | 18594 / 209 | 6 | 7197.8 |
| fit | chromium | desk-1512 | 1512@1 | people.deck | r1 | unsettled | **unsettled** | 38048 / 196 | 39 | 180088.4 |
| exact | chromium | touch-1031 | 1031@2 | people.card | r1 | fail | **fail** ~ | 1810 / 140 | 2 | 1768.0 |
| exact | chromium | touch-1031 | 1031@2 | people.carousel | r1 | unsettled | **unsettled** ~ | 23100 / 206 | 2 | 1768.0 |
| fit | chromium | touch-1031 | 1031@2 | hero.orbit | r1 | unsettled | **unsettled** | 4882 / 179 | 20 | 43300.5 |
| fit | chromium | touch-1031 | 1031@2 | hero.exit | r1 | unsettled | **unsettled** | 4668 / 179 | 20 | 43300.5 |
| fit | chromium | touch-1031 | 1031@2 | morph.panel | r1 | pass | **fail** | 90 / 84 | 17 | 47108.7 |
| fit | chromium | touch-1031 | 1031@2 | morph.columns | r1 | pass | **fail** | 117 / 84 | 17 | 47108.7 |
| fit | chromium | touch-1031 | 1031@2 | people.card | r1 | fail | **fail** | 2438 / 116 | 11 | 23626.8 |
| fit | chromium | touch-1031 | 1031@2 | people.carousel | r1 | unsettled | **unsettled** | 281 / 55 | 6 | 7121.8 |
| fit | chromium | touch-1031 | 1031@2 | people.deck | r1 | unsettled | **unsettled** | 12689 / 236 | 7 | 20090.8 |
| exact | chromium | desk-721 | 721@1 | people.card | r1 | fail | **fail** | 453 / 68 | 2 | 1792.0 |
| exact | chromium | desk-721 | 721@1 | people.carousel | r1 | fail | **fail** | 901 / 77 | 2 | 1792.0 |
| fit | chromium | desk-721 | 721@1 | hero.orbit | r1 | unsettled | **unsettled** | 7329 / 114 | 20 | 46630.7 |
| fit | chromium | desk-721 | 721@1 | hero.exit | r1 | unsettled | **unsettled** | 6944 / 91 | 20 | 46630.7 |
| fit | chromium | desk-721 | 721@1 | morph.panel | r1 | pass | **pass** | 524 / 53 | 21 | 58645.0 |
| fit | chromium | desk-721 | 721@1 | morph.columns | r1 | pass | **pass** | 942 / 52 | 21 | 58645.0 |
| fit | chromium | desk-721 | 721@1 | people.card | r1 | fail | **fail** | 27550 / 137 | 13 | 40738.4 |
| fit | chromium | desk-721 | 721@1 | people.carousel | r1 | fail | **fail** | 1126 / 77 | 6 | 7246.0 |
| fit | chromium | desk-721 | 721@1 | people.deck | r1 | unsettled | **unsettled** | 31119 / 137 | 9 | 37154.4 |
| exact | chromium | touch-481 | 481@3 | people.card | r1 | fail | **fail** | 1762 / 118 | 2 | 1728.0 |
| exact | chromium | touch-481 | 481@3 | people.carousel | r1 | pass | **unsettled** | 238 / 44 | 2 | 1728.0 |
| fit | chromium | touch-481 | 481@3 | hero.deck | r1 | unsettled | **unsettled** | 1466 / 212 | 8 | 13690.7 |
| fit | chromium | touch-481 | 481@3 | hero.exit | r1 | unsettled | **unsettled** | 88 / 56 | 8 | 13690.7 |
| fit | chromium | touch-481 | 481@3 | morph.panel | r1 | fail | **pass** | 0 / 0 | 8 | 19691.0 |
| fit | chromium | touch-481 | 481@3 | morph.columns | r1 | fail | **pass** | 0 / 0 | 8 | 19691.0 |
| fit | chromium | touch-481 | 481@3 | people.card | r1 | fail | **fail** | 6072 / 117 | 13 | 33012.6 |
| fit | chromium | touch-481 | 481@3 | people.carousel | r1 | pass | **unsettled** | 68332 / 216 | 6 | 6914.9 |
| fit | chromium | touch-481 | 481@3 | people.deck | r1 | unsettled | **unsettled** | 13449 / 227 | 9 | 29556.6 |
| exact | chromium | desk-401 | 401@1 | people.card | r1 | fail | **fail** | 2037 / 77 | 2 | 1792.0 |
| exact | chromium | desk-401 | 401@1 | people.carousel | r1 | fail | **fail** | 478 / 71 | 2 | 1792.0 |
| fit | chromium | desk-401 | 401@1 | hero.deck | r1 | unsettled | **unsettled** | 529 / 71 | 8 | 17146.0 |
| fit | chromium | desk-401 | 401@1 | hero.exit | r1 | unsettled | **unsettled** | 103 / 52 | 8 | 17146.0 |
| fit | chromium | desk-401 | 401@1 | morph.panel | r1 | pass | **pass** | 0 / 0 | 13 | 28474.2 |
| fit | chromium | desk-401 | 401@1 | morph.columns | r1 | pass | **pass** | 0 / 0 | 13 | 28474.2 |
| fit | chromium | desk-401 | 401@1 | people.card | r1 | fail | **fail** | 22574 / 157 | 13 | 42932.1 |
| fit | chromium | desk-401 | 401@1 | people.carousel | r1 | fail | **fail** | 541 / 70 | 6 | 7246.0 |
| fit | chromium | desk-401 | 401@1 | people.deck | r1 | unsettled | **unsettled** | 28119 / 157 | 9 | 39348.1 |
| fit | chromium | desk-1101 | 1101@1 | hero.orbit | r1 | unsettled | **unsettled** | 5118 / 124 | 20 | 46440.1 |
| fit | chromium | desk-1101 | 1101@1 | hero.exit | r1 | unsettled | **unsettled** | 4893 / 124 | 20 | 46440.1 |
| fit | chromium | desk-1101 | 1101@1 | morph.panel | r1 | pass | **pass** | 461 / 52 | 21 | 56258.6 |
| fit | chromium | desk-1101 | 1101@1 | morph.columns | r1 | pass | **pass** | 820 / 51 | 21 | 56258.6 |
| fit | chromium | desk-1101 | 1101@1 | people.card | r1 | unsettled | **unsettled** | 13139 / 181 | 41 | 186457.4 |
| fit | chromium | desk-1101 | 1101@1 | people.carousel | r1 | fail | **fail** | 5719 / 203 | 6 | 7197.8 |
| fit | chromium | desk-1101 | 1101@1 | people.deck | r1 | unsettled | **unsettled** | 21740 / 173 | 39 | 183965.4 |
| exact | chromium | touch-1512 | 1512@2 | people.card | r1 | unsettled | **unsettled** ~ | 4050 / 218 | 1 | 884.0 |
| exact | chromium | touch-1512 | 1512@2 | people.carousel | r1 | fail | **unsettled** ~ | 111281 / 255 | 1 | 884.0 |
| fit | chromium | touch-1512 | 1512@2 | hero.orbit | r1 | unsettled | **unsettled** | 5473 / 201 | 20 | 43410.1 |
| fit | chromium | touch-1512 | 1512@2 | hero.exit | r1 | unsettled | **unsettled** | 5329 / 205 | 20 | 43410.1 |
| fit | chromium | touch-1512 | 1512@2 | morph.panel | r1 | fail | **pass** | 21 / 33 | 16 | 38693.8 |
| fit | chromium | touch-1512 | 1512@2 | morph.columns | r1 | fail | **pass** | 366 / 58 | 16 | 38693.8 |
| fit | chromium | touch-1512 | 1512@2 | people.card | r1 | unsettled | **unsettled** | 9789 / 214 | 41 | 162442.1 |
| fit | chromium | touch-1512 | 1512@2 | people.carousel | r1 | fail | **fail** | 12358 / 173 | 6 | 6930.2 |
| fit | chromium | touch-1512 | 1512@2 | people.deck | r1 | unsettled | **unsettled** | 25431 / 234 | 39 | 159974.1 |
| exact | chromium | phone-landscape-no-preference | 932@3 | people.card | r1 | fail | **fail** ~ | 542 / 117 | 2 | 1728.0 |
| exact | chromium | phone-landscape-no-preference | 932@3 | people.carousel | r1 | unsettled | **unsettled** ~ | 156 / 51 | 2 | 1728.0 |
| fit | chromium | phone-landscape-no-preference | 932@3 | hero.orbit | r1 | unsettled | **unsettled** | 7977 / 212 | 19 | 38541.4 |
| fit | chromium | phone-landscape-no-preference | 932@3 | hero.exit | r1 | unsettled | **unsettled** | 7367 / 196 | 19 | 38541.4 |
| fit | chromium | phone-landscape-no-preference | 932@3 | morph.panel | r1 | pass | **pass** | 0 / 0 | 15 | 40267.4 |
| fit | chromium | phone-landscape-no-preference | 932@3 | morph.columns | r1 | pass | **pass** | 0 / 0 | 15 | 40267.4 |
| fit | chromium | phone-landscape-no-preference | 932@3 | people.card | r1 | fail | **fail** | 554 / 117 | 9 | 12500.9 |
| fit | chromium | phone-landscape-no-preference | 932@3 | people.carousel | r1 | unsettled | **unsettled** | 161 / 51 | 6 | 6914.9 |
| fit | chromium | phone-landscape-no-preference | 932@3 | people.deck | r1 | unsettled | **unsettled** | 75 / 72 | 5 | 9044.9 |
| exact | chromium | touch-401 | 401@3 | people.card | r1 | fail | **fail** | 4349 / 202 | 2 | 1728.0 |
| exact | chromium | touch-401 | 401@3 | people.carousel | r1 | unsettled | **unsettled** | 19412 / 227 | 2 | 1728.0 |
| fit | chromium | touch-401 | 401@3 | hero.deck | r1 | unsettled | **unsettled** | 292 / 212 | 8 | 13690.7 |
| fit | chromium | touch-401 | 401@3 | hero.exit | r1 | unsettled | **unsettled** | 178 / 198 | 8 | 13690.7 |
| fit | chromium | touch-401 | 401@3 | morph.panel | r1 | pass | **pass** | 0 / 0 | 9 | 21834.7 |
| fit | chromium | touch-401 | 401@3 | morph.columns | r1 | pass | **pass** | 0 / 0 | 9 | 21834.7 |
| fit | chromium | touch-401 | 401@3 | people.card | r1 | fail | **fail** | 7751 / 127 | 13 | 36708.4 |
| fit | chromium | touch-401 | 401@3 | people.carousel | r1 | unsettled | **unsettled** | 99 / 52 | 6 | 6914.9 |
| fit | chromium | touch-401 | 401@3 | people.deck | r1 | unsettled | **unsettled** | 14057 / 211 | 9 | 33252.4 |
| exact | chromium | desk-481 | 481@1 | people.card | r1 | fail | **fail** | 698 / 68 | 2 | 1792.0 |
| exact | chromium | desk-481 | 481@1 | people.carousel | r1 | fail | **fail** | 880 / 71 | 2 | 1792.0 |
| fit | chromium | desk-481 | 481@1 | hero.deck | r1 | unsettled | **unsettled** | 453 / 79 | 8 | 17146.0 |
| fit | chromium | desk-481 | 481@1 | hero.exit | r1 | unsettled | **unsettled** | 395 / 94 | 8 | 17146.0 |
| fit | chromium | desk-481 | 481@1 | morph.panel | r1 | pass | **pass** | 739 / 54 | 13 | 28025.4 |
| fit | chromium | desk-481 | 481@1 | morph.columns | r1 | pass | **pass** | 700 / 54 | 13 | 28025.4 |
| fit | chromium | desk-481 | 481@1 | people.card | r1 | fail | **fail** | 23985 / 143 | 13 | 42519.5 |
| fit | chromium | desk-481 | 481@1 | people.carousel | r1 | fail | **fail** | 990 / 70 | 6 | 7246.0 |
| fit | chromium | desk-481 | 481@1 | people.deck | r1 | unsettled | **unsettled** | 28619 / 143 | 9 | 38935.5 |
| exact | chromium | touch-320 | 320@3 | people.card | r1 | pass | **pass** | 33 / 55 | 2 | 1728.0 |
| exact | chromium | touch-320 | 320@3 | people.carousel | r1 | unsettled | **unsettled** | 33739 / 226 | 2 | 1728.0 |
| fit | chromium | touch-320 | 320@3 | hero.deck | r1 | unsettled | **unsettled** | 2325 / 212 | 8 | 13690.7 |
| fit | chromium | touch-320 | 320@3 | hero.exit | r1 | unsettled | **unsettled** | 202 / 197 | 8 | 13690.7 |
| fit | chromium | touch-320 | 320@3 | morph.panel | r1 | pass | **pass** | 0 / 0 | 13 | 24521.0 |
| fit | chromium | touch-320 | 320@3 | morph.columns | r1 | pass | **pass** | 0 / 0 | 13 | 24521.0 |
| fit | chromium | touch-320 | 320@3 | people.card | r1 | pass | **fail** | 9956 / 125 | 13 | 39649.6 |
| fit | chromium | touch-320 | 320@3 | people.carousel | r1 | unsettled | **unsettled** | 254 / 57 | 6 | 6914.9 |
| fit | chromium | touch-320 | 320@3 | people.deck | r1 | unsettled | **unsettled** | 15664 / 126 | 9 | 36193.6 |
| fit | chromium | desk-1201 | 1201@1 | hero.orbit | r1 | unsettled | **unsettled** | 8645 / 135 | 20 | 46593.4 |
| fit | chromium | desk-1201 | 1201@1 | hero.exit | r1 | unsettled | **unsettled** | 8675 / 135 | 20 | 46593.4 |
| fit | chromium | desk-1201 | 1201@1 | morph.panel | r1 | pass | **fail** | 819 / 104 | 21 | 55534.9 |
| fit | chromium | desk-1201 | 1201@1 | morph.columns | r1 | pass | **fail** | 1174 / 103 | 21 | 55534.9 |
| fit | chromium | desk-1201 | 1201@1 | people.card | r1 | unsettled | **unsettled** | 14609 / 179 | 41 | 185380.4 |
| fit | chromium | desk-1201 | 1201@1 | people.carousel | r1 | pass | **pass** | 0 / 0 | 6 | 7197.8 |
| fit | chromium | desk-1201 | 1201@1 | people.deck | r1 | unsettled | **unsettled** | 24727 / 178 | 39 | 182888.4 |
| exact | chromium | desk-601 | 601@1 | people.card | r1 | fail | **fail** | 636 / 83 | 2 | 1792.0 |
| exact | chromium | desk-601 | 601@1 | people.carousel | r1 | fail | **fail** | 901 / 77 | 2 | 1792.0 |
| fit | chromium | desk-601 | 601@1 | hero.orbit | r1 | unsettled | **unsettled** | 5676 / 94 | 20 | 46457.9 |
| fit | chromium | desk-601 | 601@1 | hero.exit | r1 | unsettled | **unsettled** | 5676 / 94 | 20 | 46457.9 |
| fit | chromium | desk-601 | 601@1 | morph.panel | r1 | pass | **pass** | 0 / 0 | 13 | 27209.5 |
| fit | chromium | desk-601 | 601@1 | morph.columns | r1 | pass | **pass** | 172 / 33 | 13 | 27209.5 |
| fit | chromium | desk-601 | 601@1 | people.card | r1 | fail | **fail** | 24707 / 123 | 13 | 41734.1 |
| fit | chromium | desk-601 | 601@1 | people.carousel | r1 | fail | **fail** | 1126 / 77 | 6 | 7246.0 |
| fit | chromium | desk-601 | 601@1 | people.deck | r1 | unsettled | **unsettled** | 29245 / 134 | 9 | 38150.1 |
| fit | chromium | desk-1280 | 1280@1 | hero.orbit | r1 | unsettled | **unsettled** | 8842 / 137 | 20 | 46593.1 |
| fit | chromium | desk-1280 | 1280@1 | hero.exit | r1 | unsettled | **unsettled** | 8628 / 137 | 20 | 46593.1 |
| fit | chromium | desk-1280 | 1280@1 | morph.panel | r1 | fail | **pass** | 0 / 0 | 21 | 54897.1 |
| fit | chromium | desk-1280 | 1280@1 | morph.columns | r1 | fail | **pass** | 274 / 42 | 21 | 54897.1 |
| fit | chromium | desk-1280 | 1280@1 | people.card | r1 | unsettled | **unsettled** | 18260 / 174 | 41 | 184470.4 |
| fit | chromium | desk-1280 | 1280@1 | people.carousel | r1 | pass | **pass** | 0 / 0 | 6 | 7197.8 |
| fit | chromium | desk-1280 | 1280@1 | people.deck | r1 | unsettled | **unsettled** | 36585 / 171 | 39 | 181978.4 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | hero.orbit | r1 | unsettled | **unsettled** | 9099 / 212 | 20 | 42557.6 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | hero.exit | r1 | unsettled | **unsettled** | 5398 / 179 | 20 | 42557.6 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | morph.panel | r1 | fail | **pass** | 0 / 0 | 17 | 47444.2 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | morph.columns | r1 | fail | **fail** | 819 / 67 | 17 | 47444.2 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.card | r1 | fail | **fail** | 4696 / 126 | 32 | 93937.1 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.carousel | r1 | unsettled | **unsettled** | 35294 / 255 | 6 | 6991.7 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.deck | r1 | fail | **fail** | 5562 / 134 | 31 | 93053.1 |
| exact | chromium | desk-320 | 320@1 | people.card | r1 | fail | **fail** ~ | 295 / 67 | 3 | 2688.0 |
| exact | chromium | desk-320 | 320@1 | people.carousel | r1 | fail | **fail** ~ | 748 / 70 | 3 | 2688.0 |
| fit | chromium | desk-320 | 320@1 | hero.deck | r1 | unsettled | **unsettled** | 288 / 67 | 8 | 17146.0 |
| fit | chromium | desk-320 | 320@1 | hero.exit | r1 | unsettled | **unsettled** | 816 / 93 | 8 | 17146.0 |
| fit | chromium | desk-320 | 320@1 | morph.panel | r1 | pass | **pass** | 0 / 0 | 13 | 28824.1 |
| fit | chromium | desk-320 | 320@1 | morph.columns | r1 | pass | **pass** | 0 / 0 | 13 | 28824.1 |
| fit | chromium | desk-320 | 320@1 | people.card | r1 | fail | **fail** | 18174 / 168 | 13 | 43257.8 |
| fit | chromium | desk-320 | 320@1 | people.carousel | r1 | fail | **fail** | 831 / 70 | 6 | 7246.0 |
| fit | chromium | desk-320 | 320@1 | people.deck | r1 | unsettled | **unsettled** | 27992 / 168 | 9 | 39673.8 |
| exact | chromium | touch-601 | 601@2 | people.card | r1 | fail | **fail** | 1773 / 112 | 2 | 1768.0 |
| exact | chromium | touch-601 | 601@2 | people.carousel | r1 | unsettled | **unsettled** | 0 / 0 | 2 | 1768.0 |
| fit | chromium | touch-601 | 601@2 | hero.orbit | r1 | unsettled | **unsettled** | 5228 / 212 | 20 | 43375.9 |
| fit | chromium | touch-601 | 601@2 | hero.exit | r1 | unsettled | **unsettled** | 4546 / 101 | 20 | 43375.9 |
| fit | chromium | touch-601 | 601@2 | morph.panel | r1 | fail | **fail** | 411 / 136 | 9 | 21463.9 |
| fit | chromium | touch-601 | 601@2 | morph.columns | r1 | fail | **fail** | 457 / 139 | 9 | 21463.9 |
| fit | chromium | touch-601 | 601@2 | people.card | r1 | fail | **fail** | 11400 / 128 | 13 | 35803.2 |
| fit | chromium | touch-601 | 601@2 | people.carousel | r1 | unsettled | **unsettled** | 0 / 0 | 6 | 7121.8 |
| fit | chromium | touch-601 | 601@2 | people.deck | r1 | unsettled | **unsettled** | 16906 / 209 | 9 | 32267.2 |
| fit | chromium | desk-1031 | 1031@1 | hero.orbit | r1 | unsettled | **unsettled** | 4713 / 106 | 20 | 46433.4 |
| fit | chromium | desk-1031 | 1031@1 | hero.exit | r1 | unsettled | **unsettled** | 4472 / 106 | 20 | 46433.4 |
| fit | chromium | desk-1031 | 1031@1 | morph.panel | r1 | pass | **pass** | 375 / 52 | 21 | 56738.6 |
| fit | chromium | desk-1031 | 1031@1 | morph.columns | r1 | pass | **pass** | 403 / 53 | 21 | 56738.6 |
| fit | chromium | desk-1031 | 1031@1 | people.card | r1 | unsettled | **unsettled** | 12312 / 193 | 41 | 187105.3 |
| fit | chromium | desk-1031 | 1031@1 | people.carousel | r1 | pass | **fail** | 5750 / 200 | 6 | 7197.8 |
| fit | chromium | desk-1031 | 1031@1 | people.deck | r1 | unsettled | **unsettled** | 13799 / 193 | 39 | 184613.3 |
| exact | chromium | touch-861 | 861@2 | people.card | r1 | fail | **fail** | 1595 / 136 | 2 | 1768.0 |
| exact | chromium | touch-861 | 861@2 | people.carousel | r1 | unsettled | **unsettled** | 26952 / 251 | 2 | 1768.0 |
| fit | chromium | touch-861 | 861@2 | hero.orbit | r1 | unsettled | **unsettled** | 6993 / 212 | 20 | 42656.4 |
| fit | chromium | touch-861 | 861@2 | hero.exit | r1 | unsettled | **unsettled** | 4628 / 137 | 20 | 42656.4 |
| fit | chromium | touch-861 | 861@2 | morph.panel | r1 | pass | **pass** | 21 / 33 | 21 | 50851.7 |
| fit | chromium | touch-861 | 861@2 | morph.columns | r1 | pass | **pass** | 151 / 38 | 21 | 50851.7 |
| fit | chromium | touch-861 | 861@2 | people.card | r1 | fail | **fail** | 4613 / 160 | 12 | 29448.1 |
| fit | chromium | touch-861 | 861@2 | people.carousel | r1 | unsettled | **unsettled** | 227 / 42 | 6 | 7121.8 |
| fit | chromium | touch-861 | 861@2 | people.deck | r1 | unsettled | **unsettled** | 8404 / 186 | 8 | 25912.1 |
| fit | chromium | desk-861 | 861@1 | hero.orbit | r1 | unsettled | **unsettled** | 6983 / 105 | 20 | 46467.0 |
| fit | chromium | desk-861 | 861@1 | hero.exit | r1 | unsettled | **unsettled** | 6745 / 105 | 20 | 46467.0 |
| fit | chromium | desk-861 | 861@1 | morph.panel | r1 | pass | **fail** | 640 / 101 | 21 | 57871.1 |
| fit | chromium | desk-861 | 861@1 | morph.columns | r1 | pass | **fail** | 1051 / 106 | 21 | 57871.1 |
| fit | chromium | desk-861 | 861@1 | people.card | r1 | fail | **fail** | 15919 / 139 | 33 | 136032.3 |
| fit | chromium | desk-861 | 861@1 | people.carousel | r1 | fail | **pass** | 0 / 0 | 6 | 7213.0 |
| fit | chromium | desk-861 | 861@1 | people.deck | r1 | unsettled | **unsettled** | 18681 / 138 | 32 | 135136.3 |
| fit | chromium | touch-1201 | 1201@2 | hero.orbit | r1 | unsettled | **unsettled** | 6281 / 179 | 20 | 43147.2 |
| fit | chromium | touch-1201 | 1201@2 | hero.exit | r1 | unsettled | **unsettled** | 6135 / 194 | 20 | 43147.2 |
| fit | chromium | touch-1201 | 1201@2 | morph.panel | r1 | fail | **fail** | 205 / 203 | 16 | 43913.2 |
| fit | chromium | touch-1201 | 1201@2 | morph.columns | r1 | fail | **fail** | 362 / 201 | 16 | 43913.2 |
| fit | chromium | touch-1201 | 1201@2 | people.card | r1 | unsettled | **unsettled** | 11424 / 208 | 41 | 173626.8 |
| fit | chromium | touch-1201 | 1201@2 | people.carousel | r1 | unsettled | **unsettled** | 74247 / 251 | 6 | 6930.2 |
| fit | chromium | touch-1201 | 1201@2 | people.deck | r1 | unsettled | **unsettled** | 16140 / 197 | 39 | 171158.8 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | hero.orbit | r1 | unsettled | **unsettled** | 5497 / 179 | 20 | 42574.4 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | hero.exit | r1 | unsettled | **unsettled** | 5324 / 191 | 20 | 42574.4 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.panel | r1 | fail | **fail** | 234 / 203 | 16 | 43913.2 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.columns | r1 | fail | **fail** | 394 / 201 | 16 | 43913.2 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.card | r1 | unsettled | **unsettled** | 7969 / 207 | 41 | 172944.6 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.carousel | r1 | unsettled | **unsettled** | 54938 / 186 | 6 | 6930.2 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.deck | r1 | unsettled | **unsettled** | 9688 / 212 | 39 | 170476.6 |
| fit | chromium | desk-1512 | 1512@1 | hero.orbit | r2 | unsettled | **unsettled** | 8196 / 124 | 20 | 46650.6 |
| fit | chromium | desk-1512 | 1512@1 | hero.exit | r2 | unsettled | **unsettled** | 7845 / 124 | 20 | 46650.6 |
| fit | chromium | desk-1512 | 1512@1 | morph.panel | r2 | fail | **fail** | 938 / 103 | 21 | 53541.6 |
| fit | chromium | desk-1512 | 1512@1 | morph.columns | r2 | fail | **fail** | 1127 / 101 | 21 | 53541.6 |
| fit | chromium | desk-1512 | 1512@1 | people.card | r2 | unsettled | **unsettled** | 15076 / 190 | 41 | 182583.3 |
| fit | chromium | desk-1512 | 1512@1 | people.carousel | r2 | fail | **unsettled** | 0 / 0 | 6 | 7197.8 |
| fit | chromium | desk-1512 | 1512@1 | people.deck | r2 | unsettled | **unsettled** | 65573 / 255 | 39 | 180091.3 |
| exact | chromium | touch-1031 | 1031@2 | people.card | r2 | fail | **fail** | 1795 / 140 | 1 | 884.0 |
| exact | chromium | touch-1031 | 1031@2 | people.carousel | r2 | unsettled | **unsettled** | 270 / 54 | 1 | 884.0 |
| fit | chromium | touch-1031 | 1031@2 | hero.orbit | r2 | unsettled | **unsettled** | 5015 / 179 | 20 | 43120.2 |
| fit | chromium | touch-1031 | 1031@2 | hero.exit | r2 | unsettled | **unsettled** | 4892 / 179 | 20 | 43120.2 |
| fit | chromium | touch-1031 | 1031@2 | morph.panel | r2 | fail | **fail** | 218 / 183 | 17 | 47108.7 |
| fit | chromium | touch-1031 | 1031@2 | morph.columns | r2 | fail | **fail** | 185 / 183 | 17 | 47108.7 |
| fit | chromium | touch-1031 | 1031@2 | people.card | r2 | fail | **fail** | 3050 / 116 | 11 | 23630.0 |
| fit | chromium | touch-1031 | 1031@2 | people.carousel | r2 | unsettled | **unsettled** | 281 / 55 | 6 | 7121.8 |
| fit | chromium | touch-1031 | 1031@2 | people.deck | r2 | unsettled | **unsettled** | 13264 / 236 | 7 | 20094.0 |
| exact | chromium | desk-721 | 721@1 | people.card | r2 | fail | **fail** | 453 / 68 | 2 | 1792.0 |
| exact | chromium | desk-721 | 721@1 | people.carousel | r2 | fail | **fail** | 901 / 77 | 2 | 1792.0 |
| fit | chromium | desk-721 | 721@1 | hero.orbit | r2 | unsettled | **unsettled** | 5888 / 113 | 20 | 46521.0 |
| fit | chromium | desk-721 | 721@1 | hero.exit | r2 | unsettled | **unsettled** | 5790 / 113 | 20 | 46521.0 |
| fit | chromium | desk-721 | 721@1 | morph.panel | r2 | pass | **pass** | 474 / 52 | 21 | 58645.0 |
| fit | chromium | desk-721 | 721@1 | morph.columns | r2 | pass | **pass** | 871 / 52 | 21 | 58645.0 |
| fit | chromium | desk-721 | 721@1 | people.card | r2 | fail | **fail** | 27550 / 137 | 13 | 40738.4 |
| fit | chromium | desk-721 | 721@1 | people.carousel | r2 | fail | **fail** | 1126 / 77 | 6 | 7246.0 |
| fit | chromium | desk-721 | 721@1 | people.deck | r2 | unsettled | **unsettled** | 31109 / 137 | 9 | 37154.4 |
| exact | chromium | touch-481 | 481@3 | people.card | r2 | fail | **fail** | 1762 / 118 | 2 | 1728.0 |
| exact | chromium | touch-481 | 481@3 | people.carousel | r2 | unsettled | **unsettled** | 238 / 44 | 2 | 1728.0 |
| fit | chromium | touch-481 | 481@3 | hero.deck | r2 | unsettled | **unsettled** | 1106 / 212 | 8 | 13690.7 |
| fit | chromium | touch-481 | 481@3 | hero.exit | r2 | unsettled | **unsettled** | 88 / 56 | 8 | 13690.7 |
| fit | chromium | touch-481 | 481@3 | morph.panel | r2 | fail | **pass** | 5 / 29 | 8 | 19691.0 |
| fit | chromium | touch-481 | 481@3 | morph.columns | r2 | fail | **pass** | 5 / 29 | 8 | 19691.0 |
| fit | chromium | touch-481 | 481@3 | people.card | r2 | fail | **fail** | 5820 / 117 | 13 | 33011.8 |
| fit | chromium | touch-481 | 481@3 | people.carousel | r2 | unsettled | **pass** | 269 / 45 | 6 | 6914.9 |
| fit | chromium | touch-481 | 481@3 | people.deck | r2 | unsettled | **unsettled** | 12192 / 211 | 9 | 29555.8 |
| exact | chromium | desk-401 | 401@1 | people.card | r2 | fail | **fail** | 2037 / 77 | 2 | 1792.0 |
| exact | chromium | desk-401 | 401@1 | people.carousel | r2 | fail | **fail** | 478 / 71 | 2 | 1792.0 |
| fit | chromium | desk-401 | 401@1 | hero.deck | r2 | unsettled | **unsettled** | 291 / 123 | 8 | 17146.0 |
| fit | chromium | desk-401 | 401@1 | hero.exit | r2 | unsettled | **unsettled** | 116 / 52 | 8 | 17146.0 |
| fit | chromium | desk-401 | 401@1 | morph.panel | r2 | pass | **pass** | 0 / 0 | 13 | 28474.2 |
| fit | chromium | desk-401 | 401@1 | morph.columns | r2 | pass | **pass** | 0 / 0 | 13 | 28474.2 |
| fit | chromium | desk-401 | 401@1 | people.card | r2 | fail | **fail** | 22574 / 157 | 13 | 42932.1 |
| fit | chromium | desk-401 | 401@1 | people.carousel | r2 | fail | **fail** | 541 / 70 | 6 | 7246.0 |
| fit | chromium | desk-401 | 401@1 | people.deck | r2 | unsettled | **unsettled** | 28129 / 157 | 9 | 39348.1 |
| exact | chromium | desk-1101 | 1101@1 | people.card | r2 | unsettled | **unsettled** ~ | 1937 / 175 | 1 | 896.0 |
| exact | chromium | desk-1101 | 1101@1 | people.carousel | r2 | pass | **fail** ~ | 5669 / 203 | 1 | 896.0 |
| fit | chromium | desk-1101 | 1101@1 | hero.orbit | r2 | unsettled | **unsettled** | 7681 / 124 | 20 | 46442.6 |
| fit | chromium | desk-1101 | 1101@1 | hero.exit | r2 | unsettled | **unsettled** | 7190 / 124 | 20 | 46442.6 |
| fit | chromium | desk-1101 | 1101@1 | morph.panel | r2 | pass | **fail** | 751 / 104 | 21 | 56258.6 |
| fit | chromium | desk-1101 | 1101@1 | morph.columns | r2 | pass | **fail** | 1013 / 103 | 21 | 56258.6 |
| fit | chromium | desk-1101 | 1101@1 | people.card | r2 | unsettled | **unsettled** | 12400 / 181 | 41 | 186459.8 |
| fit | chromium | desk-1101 | 1101@1 | people.carousel | r2 | pass | **pass** | 0 / 0 | 6 | 7197.8 |
| fit | chromium | desk-1101 | 1101@1 | people.deck | r2 | unsettled | **unsettled** | 15904 / 178 | 39 | 183967.8 |
| exact | chromium | touch-1512 | 1512@2 | people.card | r2 | unsettled | **unsettled** ~ | 4102 / 221 | 1 | 884.0 |
| exact | chromium | touch-1512 | 1512@2 | people.carousel | r2 | unsettled | **fail** ~ | 69511 / 220 | 1 | 884.0 |
| fit | chromium | touch-1512 | 1512@2 | hero.orbit | r2 | unsettled | **unsettled** | 4765 / 212 | 20 | 44154.9 |
| fit | chromium | touch-1512 | 1512@2 | hero.exit | r2 | unsettled | **unsettled** | 4462 / 179 | 20 | 44154.9 |
| fit | chromium | touch-1512 | 1512@2 | morph.panel | r2 | pass | **fail** | 68 / 147 | 16 | 38693.8 |
| fit | chromium | touch-1512 | 1512@2 | morph.columns | r2 | pass | **fail** | 543 / 185 | 16 | 38693.8 |
| fit | chromium | touch-1512 | 1512@2 | people.card | r2 | unsettled | **unsettled** | 9827 / 214 | 41 | 162442.1 |
| fit | chromium | touch-1512 | 1512@2 | people.carousel | r2 | unsettled | **unsettled** | 115 / 46 | 6 | 6930.2 |
| fit | chromium | touch-1512 | 1512@2 | people.deck | r2 | unsettled | **unsettled** | 37173 / 252 | 39 | 159974.1 |
| fit | chromium | phone-landscape-no-preference | 932@3 | hero.orbit | r2 | unsettled | **unsettled** | 1710 / 212 | 19 | 39704.9 |
| fit | chromium | phone-landscape-no-preference | 932@3 | hero.exit | r2 | unsettled | **unsettled** | 1737 / 196 | 19 | 39704.9 |
| fit | chromium | phone-landscape-no-preference | 932@3 | morph.panel | r2 | pass | **pass** | 0 / 0 | 15 | 40267.4 |
| fit | chromium | phone-landscape-no-preference | 932@3 | morph.columns | r2 | pass | **pass** | 2 / 25 | 15 | 40267.4 |
| fit | chromium | phone-landscape-no-preference | 932@3 | people.card | r2 | fail | **fail** | 554 / 117 | 9 | 12500.9 |
| fit | chromium | phone-landscape-no-preference | 932@3 | people.carousel | r2 | unsettled | **unsettled** | 161 / 51 | 6 | 6914.9 |
| fit | chromium | phone-landscape-no-preference | 932@3 | people.deck | r2 | unsettled | **unsettled** | 75 / 72 | 5 | 9044.9 |
| exact | chromium | touch-401 | 401@3 | people.card | r2 | fail | **fail** | 4349 / 202 | 2 | 1728.0 |
| exact | chromium | touch-401 | 401@3 | people.carousel | r2 | unsettled | **unsettled** | 99 / 51 | 2 | 1728.0 |
| fit | chromium | touch-401 | 401@3 | hero.deck | r2 | unsettled | **unsettled** | 1856 / 212 | 8 | 13690.7 |
| fit | chromium | touch-401 | 401@3 | hero.exit | r2 | unsettled | **unsettled** | 214 / 198 | 8 | 13690.7 |
| fit | chromium | touch-401 | 401@3 | morph.panel | r2 | pass | **pass** | 0 / 0 | 9 | 21834.7 |
| fit | chromium | touch-401 | 401@3 | morph.columns | r2 | pass | **pass** | 0 / 0 | 9 | 21834.7 |
| fit | chromium | touch-401 | 401@3 | people.card | r2 | fail | **fail** | 7753 / 127 | 13 | 36708.4 |
| fit | chromium | touch-401 | 401@3 | people.carousel | r2 | unsettled | **unsettled** | 19115 / 218 | 6 | 6914.9 |
| fit | chromium | touch-401 | 401@3 | people.deck | r2 | unsettled | **unsettled** | 14172 / 210 | 9 | 33252.4 |
| exact | chromium | desk-481 | 481@1 | people.card | r2 | fail | **fail** | 698 / 68 | 2 | 1792.0 |
| exact | chromium | desk-481 | 481@1 | people.carousel | r2 | fail | **fail** | 880 / 71 | 2 | 1792.0 |
| fit | chromium | desk-481 | 481@1 | hero.deck | r2 | unsettled | **unsettled** | 316 / 52 | 8 | 17146.0 |
| fit | chromium | desk-481 | 481@1 | hero.exit | r2 | unsettled | **unsettled** | 210 / 52 | 8 | 17146.0 |
| fit | chromium | desk-481 | 481@1 | morph.panel | r2 | pass | **pass** | 0 / 0 | 13 | 28025.4 |
| fit | chromium | desk-481 | 481@1 | morph.columns | r2 | pass | **pass** | 0 / 0 | 13 | 28025.4 |
| fit | chromium | desk-481 | 481@1 | people.card | r2 | fail | **fail** | 23985 / 143 | 13 | 42519.5 |
| fit | chromium | desk-481 | 481@1 | people.carousel | r2 | fail | **fail** | 990 / 70 | 6 | 7246.0 |
| fit | chromium | desk-481 | 481@1 | people.deck | r2 | unsettled | **unsettled** | 28541 / 143 | 9 | 38935.5 |
| exact | chromium | touch-320 | 320@3 | people.card | r2 | pass | **pass** ~ | 44 / 55 | 4 | 3456.0 |
| exact | chromium | touch-320 | 320@3 | people.carousel | r2 | unsettled | **unsettled** ~ | 27215 / 249 | 4 | 3456.0 |
| fit | chromium | touch-320 | 320@3 | hero.deck | r2 | unsettled | **unsettled** | 590 / 212 | 8 | 13690.7 |
| fit | chromium | touch-320 | 320@3 | hero.exit | r2 | unsettled | **unsettled** | 205 / 197 | 8 | 13690.7 |
| fit | chromium | touch-320 | 320@3 | morph.panel | r2 | pass | **pass** | 0 / 0 | 13 | 24521.0 |
| fit | chromium | touch-320 | 320@3 | morph.columns | r2 | pass | **pass** | 0 / 0 | 13 | 24521.0 |
| fit | chromium | touch-320 | 320@3 | people.card | r2 | pass | **fail** | 9954 / 125 | 13 | 39649.6 |
| fit | chromium | touch-320 | 320@3 | people.carousel | r2 | unsettled | **unsettled** | 175 / 50 | 6 | 6914.9 |
| fit | chromium | touch-320 | 320@3 | people.deck | r2 | unsettled | **unsettled** | 15707 / 125 | 9 | 36193.6 |
| exact | chromium | desk-1201 | 1201@1 | people.card | r2 | unsettled | **unsettled** ~ | 2863 / 185 | 1 | 896.0 |
| exact | chromium | desk-1201 | 1201@1 | people.carousel | r2 | pass | **pass** ~ | 0 / 0 | 1 | 896.0 |
| fit | chromium | desk-1201 | 1201@1 | hero.orbit | r2 | unsettled | **unsettled** | 10462 / 137 | 20 | 46593.1 |
| fit | chromium | desk-1201 | 1201@1 | hero.exit | r2 | unsettled | **unsettled** | 10185 / 137 | 20 | 46593.1 |
| fit | chromium | desk-1201 | 1201@1 | morph.panel | r2 | fail | **fail** | 939 / 104 | 21 | 55534.9 |
| fit | chromium | desk-1201 | 1201@1 | morph.columns | r2 | fail | **fail** | 1142 / 103 | 21 | 55534.9 |
| fit | chromium | desk-1201 | 1201@1 | people.card | r2 | unsettled | **unsettled** | 13701 / 176 | 41 | 185374.3 |
| fit | chromium | desk-1201 | 1201@1 | people.carousel | r2 | pass | **pass** | 0 / 0 | 6 | 7197.8 |
| fit | chromium | desk-1201 | 1201@1 | people.deck | r2 | unsettled | **unsettled** | 21154 / 170 | 39 | 182882.3 |
| exact | chromium | desk-601 | 601@1 | people.card | r2 | fail | **fail** ~ | 654 / 83 | 3 | 2688.0 |
| exact | chromium | desk-601 | 601@1 | people.carousel | r2 | fail | **fail** ~ | 1126 / 77 | 3 | 2688.0 |
| fit | chromium | desk-601 | 601@1 | hero.orbit | r2 | unsettled | **unsettled** | 5957 / 94 | 20 | 46456.0 |
| fit | chromium | desk-601 | 601@1 | hero.exit | r2 | unsettled | **unsettled** | 5679 / 94 | 20 | 46456.0 |
| fit | chromium | desk-601 | 601@1 | morph.panel | r2 | pass | **pass** | 951 / 51 | 13 | 27209.5 |
| fit | chromium | desk-601 | 601@1 | morph.columns | r2 | pass | **pass** | 1103 / 51 | 13 | 27209.5 |
| fit | chromium | desk-601 | 601@1 | people.card | r2 | fail | **fail** | 24182 / 125 | 13 | 41733.8 |
| fit | chromium | desk-601 | 601@1 | people.carousel | r2 | fail | **fail** | 1126 / 77 | 6 | 7246.0 |
| fit | chromium | desk-601 | 601@1 | people.deck | r2 | unsettled | **unsettled** | 28386 / 125 | 9 | 38149.8 |
| exact | chromium | desk-1280 | 1280@1 | people.card | r2 | unsettled | **unsettled** ~ | 6497 / 192 | 1 | 896.0 |
| exact | chromium | desk-1280 | 1280@1 | people.carousel | r2 | pass | **fail** ~ | 25151 / 208 | 1 | 896.0 |
| fit | chromium | desk-1280 | 1280@1 | hero.orbit | r2 | unsettled | **unsettled** | 7874 / 154 | 20 | 46937.8 |
| fit | chromium | desk-1280 | 1280@1 | hero.exit | r2 | unsettled | **unsettled** | 7830 / 154 | 20 | 46937.8 |
| fit | chromium | desk-1280 | 1280@1 | morph.panel | r2 | fail | **fail** | 1125 / 151 | 21 | 54897.1 |
| fit | chromium | desk-1280 | 1280@1 | morph.columns | r2 | fail | **fail** | 1239 / 151 | 21 | 54897.1 |
| fit | chromium | desk-1280 | 1280@1 | people.card | r2 | unsettled | **unsettled** | 18053 / 169 | 41 | 184471.1 |
| fit | chromium | desk-1280 | 1280@1 | people.carousel | r2 | pass | **unsettled** | 0 / 0 | 6 | 7197.8 |
| fit | chromium | desk-1280 | 1280@1 | people.deck | r2 | unsettled | **unsettled** | 29056 / 189 | 39 | 181979.1 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | hero.orbit | r2 | unsettled | **unsettled** | 4211 / 179 | 20 | 42578.7 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | hero.exit | r2 | unsettled | **unsettled** | 4033 / 179 | 20 | 42578.7 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | morph.panel | r2 | fail | **fail** | 374 / 200 | 17 | 47444.2 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | morph.columns | r2 | fail | **fail** | 1075 / 196 | 17 | 47444.2 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.card | r2 | fail | **fail** | 4696 / 126 | 32 | 93937.1 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.carousel | r2 | unsettled | **unsettled** | 77489 / 255 | 6 | 6991.7 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.deck | r2 | fail | **fail** | 5732 / 121 | 31 | 93053.1 |
| exact | chromium | desk-320 | 320@1 | people.card | r2 | fail | **fail** ~ | 295 / 67 | 3 | 2688.0 |
| exact | chromium | desk-320 | 320@1 | people.carousel | r2 | fail | **fail** ~ | 748 / 70 | 3 | 2688.0 |
| fit | chromium | desk-320 | 320@1 | hero.deck | r2 | unsettled | **unsettled** | 618 / 100 | 8 | 17146.0 |
| fit | chromium | desk-320 | 320@1 | hero.exit | r2 | unsettled | **unsettled** | 389 / 52 | 8 | 17146.0 |
| fit | chromium | desk-320 | 320@1 | morph.panel | r2 | pass | **pass** | 0 / 0 | 13 | 28824.1 |
| fit | chromium | desk-320 | 320@1 | morph.columns | r2 | pass | **pass** | 0 / 0 | 13 | 28824.1 |
| fit | chromium | desk-320 | 320@1 | people.card | r2 | fail | **fail** | 18174 / 168 | 13 | 43257.8 |
| fit | chromium | desk-320 | 320@1 | people.carousel | r2 | fail | **fail** | 831 / 70 | 6 | 7246.0 |
| fit | chromium | desk-320 | 320@1 | people.deck | r2 | unsettled | **unsettled** | 28024 / 168 | 9 | 39673.8 |
| exact | chromium | touch-601 | 601@2 | people.card | r2 | fail | **fail** | 1773 / 112 | 2 | 1768.0 |
| exact | chromium | touch-601 | 601@2 | people.carousel | r2 | unsettled | **unsettled** | 0 / 0 | 2 | 1768.0 |
| fit | chromium | touch-601 | 601@2 | hero.orbit | r2 | unsettled | **unsettled** | 4523 / 101 | 20 | 43370.0 |
| fit | chromium | touch-601 | 601@2 | hero.exit | r2 | unsettled | **unsettled** | 4558 / 131 | 20 | 43370.0 |
| fit | chromium | touch-601 | 601@2 | morph.panel | r2 | pass | **pass** | 0 / 0 | 9 | 21463.9 |
| fit | chromium | touch-601 | 601@2 | morph.columns | r2 | pass | **pass** | 207 / 37 | 9 | 21463.9 |
| fit | chromium | touch-601 | 601@2 | people.card | r2 | fail | **fail** | 11400 / 128 | 13 | 35803.2 |
| fit | chromium | touch-601 | 601@2 | people.carousel | r2 | unsettled | **pass** | 0 / 0 | 6 | 7121.8 |
| fit | chromium | touch-601 | 601@2 | people.deck | r2 | unsettled | **unsettled** | 16868 / 213 | 9 | 32267.2 |
| exact | chromium | desk-1031 | 1031@1 | people.card | r2 | unsettled | **unsettled** ~ | 3909 / 146 | 1 | 896.0 |
| exact | chromium | desk-1031 | 1031@1 | people.carousel | r2 | pass | **pass** ~ | 0 / 0 | 1 | 896.0 |
| fit | chromium | desk-1031 | 1031@1 | hero.orbit | r2 | unsettled | **unsettled** | 9098 / 139 | 20 | 46732.6 |
| fit | chromium | desk-1031 | 1031@1 | hero.exit | r2 | unsettled | **unsettled** | 9136 / 139 | 20 | 46732.6 |
| fit | chromium | desk-1031 | 1031@1 | morph.panel | r2 | pass | **fail** | 683 / 106 | 21 | 56738.6 |
| fit | chromium | desk-1031 | 1031@1 | morph.columns | r2 | pass | **fail** | 806 / 102 | 21 | 56738.6 |
| fit | chromium | desk-1031 | 1031@1 | people.card | r2 | unsettled | **unsettled** | 12242 / 193 | 41 | 187105.3 |
| fit | chromium | desk-1031 | 1031@1 | people.carousel | r2 | pass | **fail** | 5493 / 200 | 6 | 7197.8 |
| fit | chromium | desk-1031 | 1031@1 | people.deck | r2 | unsettled | **unsettled** | 13719 / 193 | 39 | 184613.3 |
| exact | chromium | touch-861 | 861@2 | people.card | r2 | fail | **fail** | 1595 / 136 | 2 | 1768.0 |
| exact | chromium | touch-861 | 861@2 | people.carousel | r2 | unsettled | **unsettled** | 140 / 38 | 2 | 1768.0 |
| fit | chromium | touch-861 | 861@2 | hero.orbit | r2 | unsettled | **unsettled** | 5543 / 212 | 20 | 43681.3 |
| fit | chromium | touch-861 | 861@2 | hero.exit | r2 | unsettled | **unsettled** | 4436 / 131 | 20 | 43681.3 |
| fit | chromium | touch-861 | 861@2 | morph.panel | r2 | pass | **pass** | 21 / 33 | 21 | 50851.7 |
| fit | chromium | touch-861 | 861@2 | morph.columns | r2 | pass | **pass** | 195 / 47 | 21 | 50851.7 |
| fit | chromium | touch-861 | 861@2 | people.card | r2 | fail | **fail** | 4712 / 160 | 12 | 29451.6 |
| fit | chromium | touch-861 | 861@2 | people.carousel | r2 | unsettled | **unsettled** | 248 / 42 | 6 | 7121.8 |
| fit | chromium | touch-861 | 861@2 | people.deck | r2 | unsettled | **unsettled** | 8500 / 186 | 8 | 25915.6 |
| fit | chromium | desk-861 | 861@1 | hero.orbit | r2 | unsettled | **unsettled** | 5495 / 94 | 20 | 46454.1 |
| fit | chromium | desk-861 | 861@1 | hero.exit | r2 | unsettled | **unsettled** | 5219 / 94 | 20 | 46454.1 |
| fit | chromium | desk-861 | 861@1 | morph.panel | r2 | pass | **fail** | 702 / 101 | 21 | 57871.1 |
| fit | chromium | desk-861 | 861@1 | morph.columns | r2 | pass | **fail** | 1109 / 106 | 21 | 57871.1 |
| fit | chromium | desk-861 | 861@1 | people.card | r2 | fail | **fail** | 15922 / 139 | 33 | 136033.7 |
| fit | chromium | desk-861 | 861@1 | people.carousel | r2 | fail | **pass** | 0 / 0 | 6 | 7213.4 |
| fit | chromium | desk-861 | 861@1 | people.deck | r2 | unsettled | **unsettled** | 18632 / 152 | 32 | 135137.7 |
| fit | chromium | touch-1201 | 1201@2 | hero.orbit | r2 | unsettled | **unsettled** | 11522 / 212 | 20 | 43166.3 |
| fit | chromium | touch-1201 | 1201@2 | hero.exit | r2 | unsettled | **unsettled** | 6051 / 179 | 20 | 43166.3 |
| fit | chromium | touch-1201 | 1201@2 | morph.panel | r2 | pass | **pass** | 4 / 31 | 16 | 43913.2 |
| fit | chromium | touch-1201 | 1201@2 | morph.columns | r2 | pass | **pass** | 165 / 44 | 16 | 43913.2 |
| fit | chromium | touch-1201 | 1201@2 | people.card | r2 | unsettled | **unsettled** | 11792 / 222 | 41 | 173626.8 |
| fit | chromium | touch-1201 | 1201@2 | people.carousel | r2 | unsettled | **unsettled** | 104998 / 250 | 6 | 6930.2 |
| fit | chromium | touch-1201 | 1201@2 | people.deck | r2 | unsettled | **unsettled** | 16040 / 202 | 39 | 171158.8 |
| exact | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.card | r2 | unsettled | **unsettled** ~ | 1127 / 222 | 1 | 884.0 |
| exact | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.carousel | r2 | fail | **unsettled** ~ | 150036 / 255 | 1 | 884.0 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | hero.orbit | r2 | unsettled | **unsettled** | 6414 / 179 | 20 | 44531.3 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | hero.exit | r2 | unsettled | **unsettled** | 6409 / 191 | 20 | 44531.3 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.panel | r2 | fail | **fail** | 21 / 92 | 16 | 43913.2 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.columns | r2 | fail | **fail** | 32 / 102 | 16 | 43913.2 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.card | r2 | unsettled | **unsettled** | 7836 / 208 | 41 | 172944.6 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.carousel | r2 | fail | **unsettled** | 166 / 47 | 6 | 6930.2 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.deck | r2 | unsettled | **unsettled** | 10254 / 205 | 39 | 170476.6 |
| fit | chromium | desk-1512 | 1512@1 | hero.orbit | r3 | unsettled | **unsettled** | 6218 / 124 | 20 | 46734.8 |
| fit | chromium | desk-1512 | 1512@1 | hero.exit | r3 | unsettled | **unsettled** | 6198 / 124 | 20 | 46734.8 |
| fit | chromium | desk-1512 | 1512@1 | morph.panel | r3 | fail | **pass** | 0 / 0 | 21 | 53541.6 |
| fit | chromium | desk-1512 | 1512@1 | morph.columns | r3 | fail | **pass** | 451 / 50 | 21 | 53541.6 |
| fit | chromium | desk-1512 | 1512@1 | people.card | r3 | unsettled | **unsettled** | 15054 / 181 | 41 | 182580.4 |
| fit | chromium | desk-1512 | 1512@1 | people.carousel | r3 | unsettled | **unsettled** | 0 / 0 | 6 | 7197.8 |
| fit | chromium | desk-1512 | 1512@1 | people.deck | r3 | unsettled | **unsettled** | 34737 / 209 | 39 | 180088.4 |
| exact | chromium | touch-1031 | 1031@2 | people.card | r3 | fail | **fail** | 1795 / 140 | 1 | 884.0 |
| exact | chromium | touch-1031 | 1031@2 | people.carousel | r3 | unsettled | **unsettled** | 270 / 54 | 1 | 884.0 |
| fit | chromium | touch-1031 | 1031@2 | hero.orbit | r3 | unsettled | **unsettled** | 3996 / 212 | 20 | 42455.9 |
| fit | chromium | touch-1031 | 1031@2 | hero.exit | r3 | unsettled | **unsettled** | 3764 / 179 | 20 | 42455.9 |
| fit | chromium | touch-1031 | 1031@2 | morph.panel | r3 | fail | **fail** | 51 / 101 | 17 | 47108.7 |
| fit | chromium | touch-1031 | 1031@2 | morph.columns | r3 | fail | **fail** | 60 / 101 | 17 | 47108.7 |
| fit | chromium | touch-1031 | 1031@2 | people.card | r3 | fail | **fail** | 3057 / 116 | 11 | 23637.4 |
| fit | chromium | touch-1031 | 1031@2 | people.carousel | r3 | unsettled | **unsettled** | 23143 / 206 | 6 | 7121.8 |
| fit | chromium | touch-1031 | 1031@2 | people.deck | r3 | unsettled | **unsettled** | 4021 / 135 | 7 | 20101.4 |
| exact | chromium | desk-721 | 721@1 | people.card | r3 | fail | **fail** | 453 / 68 | 2 | 1792.0 |
| exact | chromium | desk-721 | 721@1 | people.carousel | r3 | fail | **fail** | 901 / 77 | 2 | 1792.0 |
| fit | chromium | desk-721 | 721@1 | hero.orbit | r3 | unsettled | **unsettled** | 6308 / 105 | 20 | 46514.6 |
| fit | chromium | desk-721 | 721@1 | hero.exit | r3 | unsettled | **unsettled** | 6215 / 105 | 20 | 46514.6 |
| fit | chromium | desk-721 | 721@1 | morph.panel | r3 | pass | **pass** | 548 / 53 | 21 | 58645.0 |
| fit | chromium | desk-721 | 721@1 | morph.columns | r3 | pass | **pass** | 895 / 52 | 21 | 58645.0 |
| fit | chromium | desk-721 | 721@1 | people.card | r3 | fail | **fail** | 27870 / 139 | 13 | 40740.6 |
| fit | chromium | desk-721 | 721@1 | people.carousel | r3 | fail | **fail** | 1126 / 77 | 6 | 7246.0 |
| fit | chromium | desk-721 | 721@1 | people.deck | r3 | unsettled | **unsettled** | 31475 / 139 | 9 | 37156.6 |
| exact | chromium | touch-481 | 481@3 | people.card | r3 | fail | **fail** | 1762 / 118 | 2 | 1728.0 |
| exact | chromium | touch-481 | 481@3 | people.carousel | r3 | unsettled | **unsettled** | 238 / 44 | 2 | 1728.0 |
| fit | chromium | touch-481 | 481@3 | hero.deck | r3 | unsettled | **unsettled** | 474 / 212 | 8 | 13690.7 |
| fit | chromium | touch-481 | 481@3 | hero.exit | r3 | unsettled | **unsettled** | 176 / 198 | 8 | 13690.7 |
| fit | chromium | touch-481 | 481@3 | morph.panel | r3 | pass | **fail** | 26 / 151 | 8 | 19691.0 |
| fit | chromium | touch-481 | 481@3 | morph.columns | r3 | pass | **fail** | 24 / 151 | 8 | 19691.0 |
| fit | chromium | touch-481 | 481@3 | people.card | r3 | fail | **fail** | 6065 / 117 | 13 | 33014.7 |
| fit | chromium | touch-481 | 481@3 | people.carousel | r3 | unsettled | **pass** | 208 / 46 | 6 | 6914.9 |
| fit | chromium | touch-481 | 481@3 | people.deck | r3 | unsettled | **unsettled** | 12611 / 217 | 9 | 29558.7 |
| exact | chromium | desk-401 | 401@1 | people.card | r3 | fail | **fail** | 2037 / 77 | 2 | 1792.0 |
| exact | chromium | desk-401 | 401@1 | people.carousel | r3 | fail | **fail** | 478 / 71 | 2 | 1792.0 |
| fit | chromium | desk-401 | 401@1 | hero.deck | r3 | unsettled | **unsettled** | 593 / 123 | 8 | 17146.0 |
| fit | chromium | desk-401 | 401@1 | hero.exit | r3 | unsettled | **unsettled** | 177 / 94 | 8 | 17146.0 |
| fit | chromium | desk-401 | 401@1 | morph.panel | r3 | pass | **pass** | 0 / 0 | 13 | 28474.2 |
| fit | chromium | desk-401 | 401@1 | morph.columns | r3 | pass | **pass** | 0 / 0 | 13 | 28474.2 |
| fit | chromium | desk-401 | 401@1 | people.card | r3 | fail | **fail** | 22574 / 157 | 13 | 42932.1 |
| fit | chromium | desk-401 | 401@1 | people.carousel | r3 | fail | **fail** | 541 / 70 | 6 | 7246.0 |
| fit | chromium | desk-401 | 401@1 | people.deck | r3 | unsettled | **unsettled** | 28619 / 157 | 9 | 39348.1 |
| exact | chromium | desk-1101 | 1101@1 | people.card | r3 | unsettled | **unsettled** ~ | 1732 / 145 | 1 | 896.0 |
| exact | chromium | desk-1101 | 1101@1 | people.carousel | r3 | pass | **pass** ~ | 0 / 0 | 1 | 896.0 |
| fit | chromium | desk-1101 | 1101@1 | hero.orbit | r3 | unsettled | **unsettled** | 8355 / 124 | 20 | 46963.2 |
| fit | chromium | desk-1101 | 1101@1 | hero.exit | r3 | unsettled | **unsettled** | 8260 / 124 | 20 | 46963.2 |
| fit | chromium | desk-1101 | 1101@1 | morph.panel | r3 | fail | **fail** | 700 / 104 | 21 | 56258.6 |
| fit | chromium | desk-1101 | 1101@1 | morph.columns | r3 | fail | **fail** | 997 / 103 | 21 | 56258.6 |
| fit | chromium | desk-1101 | 1101@1 | people.card | r3 | unsettled | **unsettled** | 13137 / 173 | 41 | 186457.4 |
| fit | chromium | desk-1101 | 1101@1 | people.carousel | r3 | pass | **pass** | 0 / 0 | 6 | 7197.8 |
| fit | chromium | desk-1101 | 1101@1 | people.deck | r3 | unsettled | **unsettled** | 14788 / 173 | 39 | 183965.4 |
| fit | chromium | touch-1512 | 1512@2 | hero.orbit | r3 | unsettled | **unsettled** | 11853 / 212 | 20 | 44580.7 |
| fit | chromium | touch-1512 | 1512@2 | hero.exit | r3 | unsettled | **unsettled** | 5641 / 205 | 20 | 44580.7 |
| fit | chromium | touch-1512 | 1512@2 | morph.panel | r3 | fail | **fail** | 209 / 210 | 16 | 38693.8 |
| fit | chromium | touch-1512 | 1512@2 | morph.columns | r3 | fail | **fail** | 306 / 201 | 16 | 38693.8 |
| fit | chromium | touch-1512 | 1512@2 | people.card | r3 | unsettled | **unsettled** | 10142 / 230 | 41 | 162449.6 |
| fit | chromium | touch-1512 | 1512@2 | people.carousel | r3 | pass | **fail** | 61725 / 244 | 6 | 6930.2 |
| fit | chromium | touch-1512 | 1512@2 | people.deck | r3 | unsettled | **unsettled** | 14033 / 232 | 39 | 159981.6 |
| exact | chromium | phone-landscape-no-preference | 932@3 | people.card | r3 | fail | **fail** ~ | 546 / 117 | 2 | 1728.0 |
| exact | chromium | phone-landscape-no-preference | 932@3 | people.carousel | r3 | unsettled | **unsettled** ~ | 156 / 51 | 2 | 1728.0 |
| fit | chromium | phone-landscape-no-preference | 932@3 | hero.orbit | r3 | unsettled | **unsettled** | 12109 / 212 | 19 | 38557.0 |
| fit | chromium | phone-landscape-no-preference | 932@3 | hero.exit | r3 | unsettled | **unsettled** | 7291 / 196 | 19 | 38557.0 |
| fit | chromium | phone-landscape-no-preference | 932@3 | morph.panel | r3 | pass | **pass** | 0 / 0 | 15 | 40267.4 |
| fit | chromium | phone-landscape-no-preference | 932@3 | morph.columns | r3 | pass | **pass** | 0 / 0 | 15 | 40267.4 |
| fit | chromium | phone-landscape-no-preference | 932@3 | people.card | r3 | fail | **fail** | 554 / 117 | 9 | 12500.9 |
| fit | chromium | phone-landscape-no-preference | 932@3 | people.carousel | r3 | unsettled | **unsettled** | 161 / 51 | 6 | 6914.9 |
| fit | chromium | phone-landscape-no-preference | 932@3 | people.deck | r3 | unsettled | **unsettled** | 75 / 72 | 5 | 9044.9 |
| exact | chromium | touch-401 | 401@3 | people.card | r3 | fail | **fail** | 4349 / 202 | 2 | 1728.0 |
| exact | chromium | touch-401 | 401@3 | people.carousel | r3 | unsettled | **unsettled** | 24319 / 249 | 2 | 1728.0 |
| fit | chromium | touch-401 | 401@3 | hero.deck | r3 | unsettled | **unsettled** | 2722 / 212 | 8 | 13690.7 |
| fit | chromium | touch-401 | 401@3 | hero.exit | r3 | unsettled | **unsettled** | 106 / 56 | 8 | 13690.7 |
| fit | chromium | touch-401 | 401@3 | morph.panel | r3 | pass | **pass** | 0 / 0 | 9 | 21834.7 |
| fit | chromium | touch-401 | 401@3 | morph.columns | r3 | pass | **pass** | 0 / 0 | 9 | 21834.7 |
| fit | chromium | touch-401 | 401@3 | people.card | r3 | fail | **fail** | 7751 / 127 | 13 | 36708.4 |
| fit | chromium | touch-401 | 401@3 | people.carousel | r3 | unsettled | **unsettled** | 99 / 52 | 6 | 6914.9 |
| fit | chromium | touch-401 | 401@3 | people.deck | r3 | unsettled | **unsettled** | 14013 / 210 | 9 | 33252.4 |
| exact | chromium | desk-481 | 481@1 | people.card | r3 | fail | **fail** | 700 / 68 | 2 | 1792.0 |
| exact | chromium | desk-481 | 481@1 | people.carousel | r3 | fail | **fail** | 880 / 71 | 2 | 1792.0 |
| fit | chromium | desk-481 | 481@1 | hero.deck | r3 | unsettled | **unsettled** | 185 / 123 | 8 | 17146.0 |
| fit | chromium | desk-481 | 481@1 | hero.exit | r3 | unsettled | **unsettled** | 162 / 94 | 8 | 17146.0 |
| fit | chromium | desk-481 | 481@1 | morph.panel | r3 | pass | **pass** | 0 / 0 | 13 | 28025.4 |
| fit | chromium | desk-481 | 481@1 | morph.columns | r3 | pass | **pass** | 0 / 0 | 13 | 28025.4 |
| fit | chromium | desk-481 | 481@1 | people.card | r3 | fail | **fail** | 23987 / 143 | 13 | 42519.5 |
| fit | chromium | desk-481 | 481@1 | people.carousel | r3 | fail | **fail** | 990 / 70 | 6 | 7246.0 |
| fit | chromium | desk-481 | 481@1 | people.deck | r3 | unsettled | **unsettled** | 28619 / 143 | 9 | 38935.5 |
| exact | chromium | touch-320 | 320@3 | people.card | r3 | pass | **pass** ~ | 42 / 55 | 4 | 3456.0 |
| exact | chromium | touch-320 | 320@3 | people.carousel | r3 | unsettled | **unsettled** ~ | 175 / 50 | 4 | 3456.0 |
| fit | chromium | touch-320 | 320@3 | hero.deck | r3 | unsettled | **unsettled** | 188 / 212 | 8 | 13690.7 |
| fit | chromium | touch-320 | 320@3 | hero.exit | r3 | unsettled | **unsettled** | 202 / 197 | 8 | 13690.7 |
| fit | chromium | touch-320 | 320@3 | morph.panel | r3 | pass | **pass** | 0 / 0 | 13 | 24521.0 |
| fit | chromium | touch-320 | 320@3 | morph.columns | r3 | pass | **pass** | 0 / 0 | 13 | 24521.0 |
| fit | chromium | touch-320 | 320@3 | people.card | r3 | pass | **fail** | 9954 / 125 | 13 | 39649.6 |
| fit | chromium | touch-320 | 320@3 | people.carousel | r3 | unsettled | **unsettled** | 175 / 50 | 6 | 6914.9 |
| fit | chromium | touch-320 | 320@3 | people.deck | r3 | unsettled | **unsettled** | 15670 / 125 | 9 | 36193.6 |
| fit | chromium | desk-1201 | 1201@1 | hero.orbit | r3 | unsettled | **unsettled** | 9493 / 126 | 20 | 47016.1 |
| fit | chromium | desk-1201 | 1201@1 | hero.exit | r3 | unsettled | **unsettled** | 9236 / 126 | 20 | 47016.1 |
| fit | chromium | desk-1201 | 1201@1 | morph.panel | r3 | pass | **pass** | 0 / 0 | 21 | 55534.9 |
| fit | chromium | desk-1201 | 1201@1 | morph.columns | r3 | pass | **pass** | 96 / 59 | 21 | 55534.9 |
| fit | chromium | desk-1201 | 1201@1 | people.card | r3 | unsettled | **unsettled** | 13789 / 191 | 41 | 185374.3 |
| fit | chromium | desk-1201 | 1201@1 | people.carousel | r3 | fail | **pass** | 0 / 0 | 6 | 7197.8 |
| fit | chromium | desk-1201 | 1201@1 | people.deck | r3 | unsettled | **unsettled** | 17596 / 176 | 39 | 182882.3 |
| exact | chromium | desk-601 | 601@1 | people.card | r3 | fail | **fail** | 636 / 83 | 2 | 1792.0 |
| exact | chromium | desk-601 | 601@1 | people.carousel | r3 | fail | **fail** | 901 / 77 | 2 | 1792.0 |
| fit | chromium | desk-601 | 601@1 | hero.orbit | r3 | unsettled | **unsettled** | 9551 / 130 | 20 | 46646.5 |
| fit | chromium | desk-601 | 601@1 | hero.exit | r3 | unsettled | **unsettled** | 9551 / 130 | 20 | 46646.5 |
| fit | chromium | desk-601 | 601@1 | morph.panel | r3 | pass | **pass** | 951 / 51 | 13 | 27209.5 |
| fit | chromium | desk-601 | 601@1 | morph.columns | r3 | pass | **pass** | 1000 / 51 | 13 | 27209.5 |
| fit | chromium | desk-601 | 601@1 | people.card | r3 | fail | **fail** | 24182 / 125 | 13 | 41733.8 |
| fit | chromium | desk-601 | 601@1 | people.carousel | r3 | fail | **fail** | 1126 / 77 | 6 | 7246.0 |
| fit | chromium | desk-601 | 601@1 | people.deck | r3 | unsettled | **unsettled** | 28386 / 125 | 9 | 38149.8 |
| exact | chromium | desk-1280 | 1280@1 | people.card | r3 | unsettled | **unsettled** ~ | 6364 / 178 | 1 | 896.0 |
| exact | chromium | desk-1280 | 1280@1 | people.carousel | r3 | fail | **fail** ~ | 5942 / 203 | 1 | 896.0 |
| fit | chromium | desk-1280 | 1280@1 | hero.orbit | r3 | unsettled | **unsettled** | 10062 / 134 | 20 | 47071.0 |
| fit | chromium | desk-1280 | 1280@1 | hero.exit | r3 | unsettled | **unsettled** | 9902 / 134 | 20 | 47071.0 |
| fit | chromium | desk-1280 | 1280@1 | morph.panel | r3 | pass | **pass** | 17 / 52 | 21 | 54897.1 |
| fit | chromium | desk-1280 | 1280@1 | morph.columns | r3 | pass | **pass** | 274 / 51 | 21 | 54897.1 |
| fit | chromium | desk-1280 | 1280@1 | people.card | r3 | unsettled | **unsettled** | 18260 / 174 | 41 | 184470.4 |
| fit | chromium | desk-1280 | 1280@1 | people.carousel | r3 | fail | **pass** | 0 / 0 | 6 | 7197.8 |
| fit | chromium | desk-1280 | 1280@1 | people.deck | r3 | unsettled | **unsettled** | 24713 / 174 | 39 | 181978.4 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | hero.orbit | r3 | unsettled | **unsettled** | 7957 / 212 | 20 | 43716.0 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | hero.exit | r3 | unsettled | **unsettled** | 6312 / 179 | 20 | 43716.0 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | morph.panel | r3 | fail | **fail** | 90 / 84 | 17 | 47444.2 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | morph.columns | r3 | fail | **fail** | 795 / 82 | 17 | 47444.2 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.card | r3 | fail | **fail** | 4696 / 126 | 32 | 93937.1 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.carousel | r3 | unsettled | **unsettled** | 75133 / 255 | 6 | 6991.7 |
| fit | chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.deck | r3 | fail | **fail** | 5714 / 121 | 31 | 93053.1 |
| exact | chromium | desk-320 | 320@1 | people.card | r3 | fail | **fail** | 260 / 67 | 2 | 1792.0 |
| exact | chromium | desk-320 | 320@1 | people.carousel | r3 | fail | **fail** | 748 / 70 | 2 | 1792.0 |
| fit | chromium | desk-320 | 320@1 | hero.deck | r3 | unsettled | **unsettled** | 542 / 71 | 8 | 17146.0 |
| fit | chromium | desk-320 | 320@1 | hero.exit | r3 | unsettled | **unsettled** | 139 / 52 | 8 | 17146.0 |
| fit | chromium | desk-320 | 320@1 | morph.panel | r3 | pass | **pass** | 0 / 0 | 13 | 28824.1 |
| fit | chromium | desk-320 | 320@1 | morph.columns | r3 | pass | **pass** | 0 / 0 | 13 | 28824.1 |
| fit | chromium | desk-320 | 320@1 | people.card | r3 | fail | **fail** | 18174 / 168 | 13 | 43257.8 |
| fit | chromium | desk-320 | 320@1 | people.carousel | r3 | fail | **fail** | 831 / 70 | 6 | 7246.0 |
| fit | chromium | desk-320 | 320@1 | people.deck | r3 | unsettled | **unsettled** | 28024 / 168 | 9 | 39673.8 |
| exact | chromium | touch-601 | 601@2 | people.card | r3 | fail | **fail** ~ | 1779 / 112 | 3 | 2652.0 |
| exact | chromium | touch-601 | 601@2 | people.carousel | r3 | unsettled | **pass** ~ | 70 / 33 | 3 | 2652.0 |
| fit | chromium | touch-601 | 601@2 | hero.orbit | r3 | unsettled | **unsettled** | 4512 / 111 | 20 | 42657.9 |
| fit | chromium | touch-601 | 601@2 | hero.exit | r3 | unsettled | **unsettled** | 4530 / 131 | 20 | 42657.9 |
| fit | chromium | touch-601 | 601@2 | morph.panel | r3 | pass | **fail** | 219 / 75 | 9 | 21463.9 |
| fit | chromium | touch-601 | 601@2 | morph.columns | r3 | pass | **fail** | 336 / 77 | 9 | 21463.9 |
| fit | chromium | touch-601 | 601@2 | people.card | r3 | fail | **fail** | 10727 / 128 | 13 | 35799.5 |
| fit | chromium | touch-601 | 601@2 | people.carousel | r3 | unsettled | **unsettled** | 0 / 0 | 6 | 7121.8 |
| fit | chromium | touch-601 | 601@2 | people.deck | r3 | unsettled | **unsettled** | 16165 / 212 | 9 | 32263.5 |
| fit | chromium | desk-1031 | 1031@1 | hero.orbit | r3 | unsettled | **unsettled** | 4472 / 104 | 20 | 46414.6 |
| fit | chromium | desk-1031 | 1031@1 | hero.exit | r3 | unsettled | **unsettled** | 4472 / 104 | 20 | 46414.6 |
| fit | chromium | desk-1031 | 1031@1 | morph.panel | r3 | pass | **pass** | 34 / 39 | 21 | 56738.6 |
| fit | chromium | desk-1031 | 1031@1 | morph.columns | r3 | pass | **pass** | 113 / 51 | 21 | 56738.6 |
| fit | chromium | desk-1031 | 1031@1 | people.card | r3 | unsettled | **unsettled** | 12227 / 193 | 41 | 187103.4 |
| fit | chromium | desk-1031 | 1031@1 | people.carousel | r3 | unsettled | **pass** | 0 / 0 | 6 | 7197.8 |
| fit | chromium | desk-1031 | 1031@1 | people.deck | r3 | unsettled | **unsettled** | 15462 / 232 | 39 | 184611.4 |
| exact | chromium | touch-861 | 861@2 | people.card | r3 | fail | **fail** | 1595 / 136 | 2 | 1768.0 |
| exact | chromium | touch-861 | 861@2 | people.carousel | r3 | unsettled | **unsettled** | 140 / 38 | 2 | 1768.0 |
| fit | chromium | touch-861 | 861@2 | hero.orbit | r3 | unsettled | **unsettled** | 6744 / 212 | 20 | 42655.3 |
| fit | chromium | touch-861 | 861@2 | hero.exit | r3 | unsettled | **unsettled** | 3884 / 131 | 20 | 42655.3 |
| fit | chromium | touch-861 | 861@2 | morph.panel | r3 | fail | **fail** | 77 / 102 | 21 | 50851.7 |
| fit | chromium | touch-861 | 861@2 | morph.columns | r3 | fail | **fail** | 219 / 101 | 21 | 50851.7 |
| fit | chromium | touch-861 | 861@2 | people.card | r3 | fail | **fail** | 5435 / 160 | 12 | 29449.1 |
| fit | chromium | touch-861 | 861@2 | people.carousel | r3 | unsettled | **unsettled** | 227 / 42 | 6 | 7121.8 |
| fit | chromium | touch-861 | 861@2 | people.deck | r3 | unsettled | **unsettled** | 9315 / 186 | 8 | 25913.1 |
| fit | chromium | desk-861 | 861@1 | hero.orbit | r3 | unsettled | **unsettled** | 4779 / 105 | 20 | 46465.3 |
| fit | chromium | desk-861 | 861@1 | hero.exit | r3 | unsettled | **unsettled** | 4679 / 105 | 20 | 46465.3 |
| fit | chromium | desk-861 | 861@1 | morph.panel | r3 | pass | **pass** | 103 / 51 | 21 | 57871.1 |
| fit | chromium | desk-861 | 861@1 | morph.columns | r3 | pass | **pass** | 272 / 51 | 21 | 57871.1 |
| fit | chromium | desk-861 | 861@1 | people.card | r3 | fail | **fail** | 15922 / 139 | 33 | 136033.7 |
| fit | chromium | desk-861 | 861@1 | people.carousel | r3 | pass | **fail** | 8933 / 203 | 6 | 7213.4 |
| fit | chromium | desk-861 | 861@1 | people.deck | r3 | unsettled | **unsettled** | 18660 / 138 | 32 | 135137.7 |
| fit | chromium | touch-1201 | 1201@2 | hero.orbit | r3 | unsettled | **unsettled** | 9566 / 212 | 20 | 42595.5 |
| fit | chromium | touch-1201 | 1201@2 | hero.exit | r3 | unsettled | **unsettled** | 4400 / 212 | 20 | 42595.5 |
| fit | chromium | touch-1201 | 1201@2 | morph.panel | r3 | pass | **fail** | 55 / 84 | 16 | 43913.2 |
| fit | chromium | touch-1201 | 1201@2 | morph.columns | r3 | pass | **fail** | 257 / 84 | 16 | 43913.2 |
| fit | chromium | touch-1201 | 1201@2 | people.card | r3 | unsettled | **unsettled** | 11595 / 210 | 41 | 173638.5 |
| fit | chromium | touch-1201 | 1201@2 | people.carousel | r3 | unsettled | **unsettled** | 82686 / 255 | 6 | 6930.2 |
| fit | chromium | touch-1201 | 1201@2 | people.deck | r3 | unsettled | **unsettled** | 15771 / 199 | 39 | 171170.5 |
| exact | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.card | r3 | unsettled | **unsettled** ~ | 1100 / 224 | 1 | 884.0 |
| exact | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.carousel | r3 | unsettled | **unsettled** ~ | 131570 / 255 | 1 | 884.0 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | hero.orbit | r3 | unsettled | **unsettled** | 11650 / 212 | 20 | 43713.6 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | hero.exit | r3 | unsettled | **unsettled** | 6122 / 179 | 20 | 43713.6 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.panel | r3 | pass | **fail** | 324 / 203 | 16 | 43913.2 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.columns | r3 | pass | **fail** | 483 / 201 | 16 | 43913.2 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.card | r3 | unsettled | **unsettled** | 8269 / 221 | 41 | 172944.6 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.carousel | r3 | unsettled | **unsettled** | 124036 / 255 | 6 | 6930.2 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.deck | r3 | unsettled | **unsettled** | 9280 / 208 | 39 | 170476.6 |
| fit | playwright-webkit | desk-1512 | 1512@1 | hero.orbit | r1 | unsettled | **unsettled** | 16380 / 212 | 20 | 45095.2 |
| fit | playwright-webkit | desk-1512 | 1512@1 | hero.exit | r1 | unsettled | **unsettled** | 15714 / 174 | 20 | 45095.2 |
| fit | playwright-webkit | desk-1512 | 1512@1 | morph.panel | r1 | pass | **pass** | 0 / 0 | 21 | 53541.6 |
| fit | playwright-webkit | desk-1512 | 1512@1 | morph.columns | r1 | pass | **fail** | 4749 / 80 | 21 | 53541.6 |
| fit | playwright-webkit | desk-1512 | 1512@1 | people.card | r1 | fail | **fail** | 30121 / 255 | 41 | 182544.6 |
| fit | playwright-webkit | desk-1512 | 1512@1 | people.carousel | r1 | fail | **unsettled** | 152576 / 255 | 6 | 7196.6 |
| fit | playwright-webkit | desk-1512 | 1512@1 | people.deck | r1 | unsettled | **unsettled** | 97565 / 255 | 39 | 180052.6 |
| exact | playwright-webkit | touch-1031 | 1031@2 | people.card | r1 | fail | **fail** ~ | 399 / 183 | 3 | 2652.0 |
| exact | playwright-webkit | touch-1031 | 1031@2 | people.carousel | r1 | unsettled | **unsettled** ~ | 72356 / 226 | 3 | 2652.0 |
| fit | playwright-webkit | touch-1031 | 1031@2 | hero.orbit | r1 | unsettled | **unsettled** | 13235 / 212 | 20 | 37181.1 |
| fit | playwright-webkit | touch-1031 | 1031@2 | hero.exit | r1 | unsettled | **unsettled** | 8292 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | touch-1031 | 1031@2 | morph.panel | r1 | pass | **fail** | 12600 / 99 | 17 | 47099.6 |
| fit | playwright-webkit | touch-1031 | 1031@2 | morph.columns | r1 | pass | **fail** | 15646 / 110 | 17 | 47099.6 |
| fit | playwright-webkit | touch-1031 | 1031@2 | people.card | r1 | fail | **fail** | 4888 / 150 | 12 | 25203.0 |
| fit | playwright-webkit | touch-1031 | 1031@2 | people.carousel | r1 | unsettled | **unsettled** | 72626 / 247 | 6 | 7125.3 |
| fit | playwright-webkit | touch-1031 | 1031@2 | people.deck | r1 | pass | **fail** | 5375 / 85 | 8 | 21667.0 |
| fit | playwright-webkit | desk-721 | 721@1 | hero.orbit | r1 | unsettled | **unsettled** | 19689 / 212 | 20 | 45562.1 |
| fit | playwright-webkit | desk-721 | 721@1 | hero.exit | r1 | unsettled | **unsettled** | 19541 / 139 | 20 | 45562.1 |
| fit | playwright-webkit | desk-721 | 721@1 | morph.panel | r1 | pass | **fail** | 7977 / 93 | 21 | 58645.0 |
| fit | playwright-webkit | desk-721 | 721@1 | morph.columns | r1 | pass | **fail** | 11114 / 76 | 21 | 58645.0 |
| fit | playwright-webkit | desk-721 | 721@1 | people.card | r1 | fail | **fail** | 29542 / 151 | 14 | 45855.5 |
| fit | playwright-webkit | desk-721 | 721@1 | people.carousel | r1 | unsettled | **unsettled** | 101641 / 245 | 6 | 7246.0 |
| fit | playwright-webkit | desk-721 | 721@1 | people.deck | r1 | fail | **fail** | 35856 / 154 | 10 | 42271.5 |
| exact | playwright-webkit | touch-481 | 481@3 | people.card | r1 | fail | **fail** ~ | 739 / 154 | 3 | 2592.0 |
| exact | playwright-webkit | touch-481 | 481@3 | people.carousel | r1 | unsettled | **unsettled** ~ | 112336 / 249 | 3 | 2592.0 |
| fit | playwright-webkit | touch-481 | 481@3 | hero.deck | r1 | unsettled | **unsettled** | 2023 / 177 | 8 | 13689.6 |
| fit | playwright-webkit | touch-481 | 481@3 | hero.exit | r1 | unsettled | **unsettled** | 1239 / 177 | 8 | 13689.6 |
| fit | playwright-webkit | touch-481 | 481@3 | morph.panel | r1 | pass | **pass** | 0 / 0 | 8 | 19691.0 |
| fit | playwright-webkit | touch-481 | 481@3 | morph.columns | r1 | pass | **pass** | 0 / 0 | 8 | 19691.0 |
| fit | playwright-webkit | touch-481 | 481@3 | people.card | r1 | fail | **fail** | 7066 / 115 | 14 | 36766.6 |
| fit | playwright-webkit | touch-481 | 481@3 | people.carousel | r1 | unsettled | **unsettled** | 117722 / 247 | 6 | 6922.8 |
| fit | playwright-webkit | touch-481 | 481@3 | people.deck | r1 | fail | **fail** | 9250 / 185 | 10 | 33310.6 |
| exact | playwright-webkit | desk-401 | 401@1 | people.card | r1 | fail | **fail** | 1239 / 121 | 2 | 1792.0 |
| exact | playwright-webkit | desk-401 | 401@1 | people.carousel | r1 | unsettled | **unsettled** | 69793 / 246 | 2 | 1792.0 |
| fit | playwright-webkit | desk-401 | 401@1 | hero.deck | r1 | unsettled | **unsettled** | 14539 / 212 | 8 | 17146.0 |
| fit | playwright-webkit | desk-401 | 401@1 | hero.exit | r1 | unsettled | **unsettled** | 9817 / 212 | 8 | 17146.0 |
| fit | playwright-webkit | desk-401 | 401@1 | morph.panel | r1 | pass | **pass** | 0 / 0 | 13 | 28474.2 |
| fit | playwright-webkit | desk-401 | 401@1 | morph.columns | r1 | pass | **pass** | 0 / 0 | 13 | 28474.2 |
| fit | playwright-webkit | desk-401 | 401@1 | people.card | r1 | fail | **fail** | 32499 / 184 | 14 | 48455.4 |
| fit | playwright-webkit | desk-401 | 401@1 | people.carousel | r1 | unsettled | **unsettled** | 70398 / 240 | 6 | 7246.0 |
| fit | playwright-webkit | desk-401 | 401@1 | people.deck | r1 | fail | **fail** | 40306 / 184 | 10 | 44871.4 |
| fit | playwright-webkit | desk-1101 | 1101@1 | hero.orbit | r1 | unsettled | **unsettled** | 36880 / 212 | 20 | 47126.3 |
| fit | playwright-webkit | desk-1101 | 1101@1 | hero.exit | r1 | unsettled | **unsettled** | 36519 / 206 | 20 | 47126.3 |
| fit | playwright-webkit | desk-1101 | 1101@1 | morph.panel | r1 | pass | **fail** | 20993 / 92 | 21 | 56258.6 |
| fit | playwright-webkit | desk-1101 | 1101@1 | morph.columns | r1 | pass | **fail** | 24684 / 104 | 21 | 56258.6 |
| fit | playwright-webkit | desk-1101 | 1101@1 | people.card | r1 | fail | **fail** | 17720 / 184 | 41 | 186449.8 |
| fit | playwright-webkit | desk-1101 | 1101@1 | people.carousel | r1 | fail | **unsettled** | 75922 / 255 | 6 | 7197.2 |
| fit | playwright-webkit | desk-1101 | 1101@1 | people.deck | r1 | unsettled | **unsettled** | 29374 / 243 | 39 | 183957.8 |
| fit | playwright-webkit | touch-1512 | 1512@2 | hero.orbit | r1 | unsettled | **unsettled** | 6070 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | touch-1512 | 1512@2 | hero.exit | r1 | unsettled | **unsettled** | 6071 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | touch-1512 | 1512@2 | morph.panel | r1 | pass | **pass** | 0 / 0 | 16 | 38693.8 |
| fit | playwright-webkit | touch-1512 | 1512@2 | morph.columns | r1 | pass | **fail** | 5739 / 115 | 16 | 38693.8 |
| fit | playwright-webkit | touch-1512 | 1512@2 | people.card | r1 | fail | **fail** | 7105 / 121 | 41 | 162033.3 |
| fit | playwright-webkit | touch-1512 | 1512@2 | people.carousel | r1 | fail | **unsettled** | 61051 / 131 | 6 | 6922.3 |
| fit | playwright-webkit | touch-1512 | 1512@2 | people.deck | r1 | unsettled | **unsettled** | 132523 / 255 | 39 | 159565.3 |
| exact | playwright-webkit | phone-landscape-no-preference | 932@3 | people.card | r1 | fail | **fail** | 704 / 189 | 1 | 864.0 |
| exact | playwright-webkit | phone-landscape-no-preference | 932@3 | people.carousel | r1 | unsettled | **fail** | 73696 / 249 | 1 | 864.0 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | hero.orbit | r1 | unsettled | **unsettled** | 3677 / 212 | 18 | 24829.8 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | hero.exit | r1 | unsettled | **unsettled** | 2632 / 212 | 18 | 24829.8 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | morph.panel | r1 | pass | **pass** | 89 / 53 | 15 | 40267.4 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | morph.columns | r1 | pass | **pass** | 133 / 54 | 15 | 40267.4 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | people.card | r1 | fail | **fail** | 647 / 154 | 9 | 12508.8 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | people.carousel | r1 | unsettled | **unsettled** | 76412 / 247 | 6 | 6922.8 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | people.deck | r1 | pass | **pass** | 14 / 48 | 5 | 9052.8 |
| fit | playwright-webkit | touch-401 | 401@3 | hero.deck | r1 | unsettled | **unsettled** | 11437 / 212 | 8 | 13689.6 |
| fit | playwright-webkit | touch-401 | 401@3 | hero.exit | r1 | unsettled | **unsettled** | 10307 / 212 | 8 | 13689.6 |
| fit | playwright-webkit | touch-401 | 401@3 | morph.panel | r1 | pass | **pass** | 0 / 0 | 9 | 21834.7 |
| fit | playwright-webkit | touch-401 | 401@3 | morph.columns | r1 | pass | **pass** | 0 / 0 | 9 | 21834.7 |
| fit | playwright-webkit | touch-401 | 401@3 | people.card | r1 | fail | **fail** | 7870 / 119 | 14 | 41146.2 |
| fit | playwright-webkit | touch-401 | 401@3 | people.carousel | r1 | unsettled | **unsettled** | 68484 / 239 | 6 | 6922.8 |
| fit | playwright-webkit | touch-401 | 401@3 | people.deck | r1 | fail | **fail** | 10958 / 196 | 10 | 37690.2 |
| exact | playwright-webkit | desk-481 | 481@1 | people.card | r1 | fail | **fail** ~ | 5879 / 151 | 2 | 1792.0 |
| exact | playwright-webkit | desk-481 | 481@1 | people.carousel | r1 | unsettled | **unsettled** ~ | 120864 / 246 | 2 | 1792.0 |
| fit | playwright-webkit | desk-481 | 481@1 | hero.deck | r1 | unsettled | **unsettled** | 11857 / 212 | 8 | 17146.0 |
| fit | playwright-webkit | desk-481 | 481@1 | hero.exit | r1 | unsettled | **unsettled** | 8187 / 212 | 8 | 17146.0 |
| fit | playwright-webkit | desk-481 | 481@1 | morph.panel | r1 | pass | **pass** | 0 / 0 | 13 | 28025.4 |
| fit | playwright-webkit | desk-481 | 481@1 | morph.columns | r1 | pass | **pass** | 0 / 0 | 13 | 28025.4 |
| fit | playwright-webkit | desk-481 | 481@1 | people.card | r1 | fail | **fail** | 31058 / 157 | 14 | 47970.3 |
| fit | playwright-webkit | desk-481 | 481@1 | people.carousel | r1 | unsettled | **unsettled** | 115948 / 244 | 6 | 7246.0 |
| fit | playwright-webkit | desk-481 | 481@1 | people.deck | r1 | fail | **fail** | 41237 / 222 | 10 | 44386.3 |
| exact | playwright-webkit | touch-320 | 320@3 | people.card | r1 | fail | **fail** ~ | 3414 / 174 | 2 | 1728.0 |
| exact | playwright-webkit | touch-320 | 320@3 | people.carousel | r1 | unsettled | **unsettled** ~ | 78733 / 238 | 2 | 1728.0 |
| fit | playwright-webkit | touch-320 | 320@3 | hero.deck | r1 | unsettled | **unsettled** | 2614 / 177 | 8 | 13689.6 |
| fit | playwright-webkit | touch-320 | 320@3 | hero.exit | r1 | unsettled | **unsettled** | 2599 / 177 | 8 | 13689.6 |
| fit | playwright-webkit | touch-320 | 320@3 | morph.panel | r1 | pass | **pass** | 0 / 0 | 13 | 24521.0 |
| fit | playwright-webkit | touch-320 | 320@3 | morph.columns | r1 | pass | **pass** | 0 / 0 | 13 | 24521.0 |
| fit | playwright-webkit | touch-320 | 320@3 | people.card | r1 | fail | **fail** | 10157 / 135 | 14 | 44632.9 |
| fit | playwright-webkit | touch-320 | 320@3 | people.carousel | r1 | unsettled | **unsettled** | 86591 / 239 | 6 | 6922.8 |
| fit | playwright-webkit | touch-320 | 320@3 | people.deck | r1 | fail | **fail** | 14972 / 135 | 10 | 41176.9 |
| fit | playwright-webkit | desk-1201 | 1201@1 | hero.orbit | r1 | unsettled | **unsettled** | 27281 / 212 | 20 | 46302.0 |
| fit | playwright-webkit | desk-1201 | 1201@1 | hero.exit | r1 | unsettled | **unsettled** | 26787 / 205 | 20 | 46302.0 |
| fit | playwright-webkit | desk-1201 | 1201@1 | morph.panel | r1 | pass | **fail** | 7049 / 75 | 21 | 55534.9 |
| fit | playwright-webkit | desk-1201 | 1201@1 | morph.columns | r1 | pass | **fail** | 9600 / 82 | 21 | 55534.9 |
| fit | playwright-webkit | desk-1201 | 1201@1 | people.card | r1 | fail | **fail** | 22058 / 205 | 41 | 185367.3 |
| fit | playwright-webkit | desk-1201 | 1201@1 | people.carousel | r1 | unsettled | **fail** | 133671 / 255 | 6 | 7197.2 |
| fit | playwright-webkit | desk-1201 | 1201@1 | people.deck | r1 | unsettled | **unsettled** | 82718 / 255 | 39 | 182875.3 |
| exact | playwright-webkit | desk-601 | 601@1 | people.card | r1 | fail | **fail** | 2649 / 164 | 1 | 896.0 |
| exact | playwright-webkit | desk-601 | 601@1 | people.carousel | r1 | unsettled | **unsettled** | 126609 / 232 | 1 | 896.0 |
| fit | playwright-webkit | desk-601 | 601@1 | hero.orbit | r1 | unsettled | **unsettled** | 34448 / 212 | 20 | 47005.5 |
| fit | playwright-webkit | desk-601 | 601@1 | hero.exit | r1 | unsettled | **unsettled** | 34400 / 212 | 20 | 47005.5 |
| fit | playwright-webkit | desk-601 | 601@1 | morph.panel | r1 | pass | **fail** | 12724 / 101 | 13 | 27209.5 |
| fit | playwright-webkit | desk-601 | 601@1 | morph.columns | r1 | pass | **fail** | 23661 / 111 | 13 | 27209.5 |
| fit | playwright-webkit | desk-601 | 601@1 | people.card | r1 | fail | **fail** | 32150 / 151 | 14 | 47034.4 |
| fit | playwright-webkit | desk-601 | 601@1 | people.carousel | r1 | unsettled | **unsettled** | 126167 / 225 | 6 | 7246.0 |
| fit | playwright-webkit | desk-601 | 601@1 | people.deck | r1 | fail | **fail** | 38360 / 181 | 10 | 43450.4 |
| exact | playwright-webkit | desk-1280 | 1280@1 | people.card | r1 | fail | **fail** ~ | 17172 / 239 | 1 | 1596.0 |
| exact | playwright-webkit | desk-1280 | 1280@1 | people.carousel | r1 | unsettled | **fail** ~ | 119684 / 255 | 1 | 1596.0 |
| fit | playwright-webkit | desk-1280 | 1280@1 | hero.orbit | r1 | unsettled | **unsettled** | 35415 / 212 | 20 | 47131.7 |
| fit | playwright-webkit | desk-1280 | 1280@1 | hero.exit | r1 | unsettled | **unsettled** | 35210 / 206 | 20 | 47131.7 |
| fit | playwright-webkit | desk-1280 | 1280@1 | morph.panel | r1 | pass | **fail** | 17902 / 92 | 21 | 54897.1 |
| fit | playwright-webkit | desk-1280 | 1280@1 | morph.columns | r1 | pass | **fail** | 22375 / 99 | 21 | 54897.1 |
| fit | playwright-webkit | desk-1280 | 1280@1 | people.card | r1 | fail | **fail** | 25832 / 222 | 41 | 184460.3 |
| fit | playwright-webkit | desk-1280 | 1280@1 | people.carousel | r1 | unsettled | **unsettled** | 72777 / 255 | 6 | 7197.2 |
| fit | playwright-webkit | desk-1280 | 1280@1 | people.deck | r1 | unsettled | **unsettled** | 98687 / 255 | 39 | 181968.3 |
| exact | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.card | r1 | fail | **fail** ~ | 3708 / 166 | 1 | 884.0 |
| exact | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.carousel | r1 | fail | **unsettled** ~ | 74533 / 226 | 1 | 884.0 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | hero.orbit | r1 | unsettled | **unsettled** | 7304 / 212 | 20 | 37181.1 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | hero.exit | r1 | unsettled | **unsettled** | 7472 / 124 | 20 | 37181.1 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | morph.panel | r1 | pass | **fail** | 3018 / 99 | 17 | 47460.5 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | morph.columns | r1 | pass | **fail** | 6146 / 126 | 17 | 47460.5 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.card | r1 | fail | **fail** | 2762 / 125 | 12 | 25503.0 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.carousel | r1 | fail | **unsettled** | 82317 / 233 | 6 | 7125.3 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.deck | r1 | fail | **fail** | 4681 / 166 | 8 | 21967.0 |
| exact | playwright-webkit | desk-320 | 320@1 | people.card | r1 | fail | **fail** ~ | 13955 / 204 | 3 | 2688.0 |
| exact | playwright-webkit | desk-320 | 320@1 | people.carousel | r1 | fail | **fail** ~ | 89204 / 240 | 3 | 2688.0 |
| fit | playwright-webkit | desk-320 | 320@1 | hero.deck | r1 | unsettled | **unsettled** | 8052 / 133 | 8 | 17146.0 |
| fit | playwright-webkit | desk-320 | 320@1 | hero.exit | r1 | unsettled | **unsettled** | 9101 / 133 | 8 | 17146.0 |
| fit | playwright-webkit | desk-320 | 320@1 | morph.panel | r1 | pass | **pass** | 0 / 0 | 13 | 28824.1 |
| fit | playwright-webkit | desk-320 | 320@1 | morph.columns | r1 | pass | **pass** | 0 / 0 | 13 | 28824.1 |
| fit | playwright-webkit | desk-320 | 320@1 | people.card | r1 | fail | **fail** | 28288 / 183 | 14 | 48842.4 |
| fit | playwright-webkit | desk-320 | 320@1 | people.carousel | r1 | fail | **unsettled** | 81445 / 229 | 6 | 7246.0 |
| fit | playwright-webkit | desk-320 | 320@1 | people.deck | r1 | fail | **fail** | 41593 / 183 | 10 | 45258.4 |
| exact | playwright-webkit | touch-601 | 601@2 | people.card | r1 | fail | **fail** ~ | 1643 / 119 | 4 | 3536.0 |
| exact | playwright-webkit | touch-601 | 601@2 | people.carousel | r1 | unsettled | **unsettled** ~ | 117662 / 249 | 4 | 3536.0 |
| fit | playwright-webkit | touch-601 | 601@2 | hero.orbit | r1 | unsettled | **unsettled** | 14709 / 212 | 20 | 37181.1 |
| fit | playwright-webkit | touch-601 | 601@2 | hero.exit | r1 | unsettled | **unsettled** | 15205 / 212 | 20 | 37181.1 |
| fit | playwright-webkit | touch-601 | 601@2 | morph.panel | r1 | pass | **fail** | 8492 / 118 | 9 | 21463.9 |
| fit | playwright-webkit | touch-601 | 601@2 | morph.columns | r1 | pass | **fail** | 15492 / 120 | 9 | 21463.9 |
| fit | playwright-webkit | touch-601 | 601@2 | people.card | r1 | fail | **fail** | 10352 / 119 | 14 | 40023.6 |
| fit | playwright-webkit | touch-601 | 601@2 | people.carousel | r1 | unsettled | **unsettled** | 11636 / 208 | 6 | 7125.3 |
| fit | playwright-webkit | touch-601 | 601@2 | people.deck | r1 | fail | **fail** | 11684 / 136 | 10 | 36487.6 |
| fit | playwright-webkit | desk-1031 | 1031@1 | hero.orbit | r1 | unsettled | **unsettled** | 37063 / 212 | 20 | 47114.7 |
| fit | playwright-webkit | desk-1031 | 1031@1 | hero.exit | r1 | unsettled | **unsettled** | 36530 / 205 | 20 | 47114.7 |
| fit | playwright-webkit | desk-1031 | 1031@1 | morph.panel | r1 | pass | **fail** | 22547 / 89 | 21 | 56738.6 |
| fit | playwright-webkit | desk-1031 | 1031@1 | morph.columns | r1 | pass | **fail** | 23654 / 100 | 21 | 56738.6 |
| fit | playwright-webkit | desk-1031 | 1031@1 | people.card | r1 | fail | **fail** | 16586 / 205 | 41 | 187091.8 |
| fit | playwright-webkit | desk-1031 | 1031@1 | people.carousel | r1 | unsettled | **pass** | 1035 / 63 | 6 | 7196.6 |
| fit | playwright-webkit | desk-1031 | 1031@1 | people.deck | r1 | unsettled | **unsettled** | 69688 / 255 | 39 | 184599.8 |
| exact | playwright-webkit | touch-861 | 861@2 | people.card | r1 | fail | **fail** ~ | 3569 / 119 | 3 | 2652.0 |
| exact | playwright-webkit | touch-861 | 861@2 | people.carousel | r1 | pass | **unsettled** ~ | 76797 / 249 | 3 | 2652.0 |
| fit | playwright-webkit | touch-861 | 861@2 | hero.orbit | r1 | unsettled | **unsettled** | 12863 / 212 | 20 | 37181.1 |
| fit | playwright-webkit | touch-861 | 861@2 | hero.exit | r1 | unsettled | **unsettled** | 13013 / 212 | 20 | 37181.1 |
| fit | playwright-webkit | touch-861 | 861@2 | morph.panel | r1 | pass | **fail** | 11250 / 108 | 21 | 50851.7 |
| fit | playwright-webkit | touch-861 | 861@2 | morph.columns | r1 | pass | **fail** | 16859 / 120 | 21 | 50851.7 |
| fit | playwright-webkit | touch-861 | 861@2 | people.card | r1 | fail | **fail** | 4763 / 119 | 13 | 32483.0 |
| fit | playwright-webkit | touch-861 | 861@2 | people.carousel | r1 | pass | **unsettled** | 71868 / 227 | 6 | 7125.3 |
| fit | playwright-webkit | touch-861 | 861@2 | people.deck | r1 | fail | **fail** | 7807 / 144 | 9 | 28947.0 |
| fit | playwright-webkit | desk-861 | 861@1 | hero.orbit | r1 | unsettled | **unsettled** | 23994 / 161 | 20 | 46052.7 |
| fit | playwright-webkit | desk-861 | 861@1 | hero.exit | r1 | unsettled | **unsettled** | 23810 / 161 | 20 | 46052.7 |
| fit | playwright-webkit | desk-861 | 861@1 | morph.panel | r1 | pass | **fail** | 16336 / 90 | 21 | 57871.1 |
| fit | playwright-webkit | desk-861 | 861@1 | morph.columns | r1 | pass | **fail** | 22588 / 101 | 21 | 57871.1 |
| fit | playwright-webkit | desk-861 | 861@1 | people.card | r1 | fail | **fail** | 22693 / 161 | 33 | 136029.9 |
| fit | playwright-webkit | desk-861 | 861@1 | people.carousel | r1 | unsettled | **unsettled** | 128293 / 255 | 6 | 7212.5 |
| fit | playwright-webkit | desk-861 | 861@1 | people.deck | r1 | unsettled | **unsettled** | 34130 / 212 | 32 | 135133.9 |
| fit | playwright-webkit | touch-1201 | 1201@2 | hero.orbit | r1 | unsettled | **unsettled** | 7251 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | touch-1201 | 1201@2 | hero.exit | r1 | unsettled | **unsettled** | 7177 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | touch-1201 | 1201@2 | morph.panel | r1 | pass | **fail** | 10744 / 97 | 16 | 43913.2 |
| fit | playwright-webkit | touch-1201 | 1201@2 | morph.columns | r1 | pass | **fail** | 15148 / 114 | 16 | 43913.2 |
| fit | playwright-webkit | touch-1201 | 1201@2 | people.card | r1 | fail | **fail** | 8809 / 145 | 41 | 173413.8 |
| fit | playwright-webkit | touch-1201 | 1201@2 | people.carousel | r1 | unsettled | **fail** | 57666 / 133 | 6 | 6924.5 |
| fit | playwright-webkit | touch-1201 | 1201@2 | people.deck | r1 | unsettled | **unsettled** | 116589 / 255 | 39 | 170945.8 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | hero.orbit | r1 | unsettled | **unsettled** | 13626 / 212 | 20 | 37181.1 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | hero.exit | r1 | unsettled | **unsettled** | 7369 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.panel | r1 | pass | **fail** | 10835 / 97 | 16 | 43913.2 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.columns | r1 | pass | **fail** | 15139 / 112 | 16 | 43913.2 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.card | r1 | fail | **fail** | 10516 / 176 | 41 | 172804.2 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.carousel | r1 | fail | **unsettled** | 161007 / 255 | 6 | 6925.7 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.deck | r1 | unsettled | **unsettled** | 147433 / 255 | 39 | 170336.2 |
| fit | playwright-webkit | desk-1512 | 1512@1 | hero.orbit | r2 | unsettled | **unsettled** | 15840 / 212 | 20 | 45095.2 |
| fit | playwright-webkit | desk-1512 | 1512@1 | hero.exit | r2 | unsettled | **unsettled** | 15715 / 174 | 20 | 45095.2 |
| fit | playwright-webkit | desk-1512 | 1512@1 | morph.panel | r2 | pass | **pass** | 0 / 0 | 21 | 53541.6 |
| fit | playwright-webkit | desk-1512 | 1512@1 | morph.columns | r2 | pass | **fail** | 4749 / 80 | 21 | 53541.6 |
| fit | playwright-webkit | desk-1512 | 1512@1 | people.card | r2 | fail | **fail** | 29258 / 255 | 41 | 182517.9 |
| fit | playwright-webkit | desk-1512 | 1512@1 | people.carousel | r2 | unsettled | **fail** | 151548 / 255 | 6 | 7196.1 |
| fit | playwright-webkit | desk-1512 | 1512@1 | people.deck | r2 | unsettled | **unsettled** | 96485 / 255 | 39 | 180025.9 |
| exact | playwright-webkit | touch-1031 | 1031@2 | people.card | r2 | fail | **fail** ~ | 399 / 183 | 3 | 2652.0 |
| exact | playwright-webkit | touch-1031 | 1031@2 | people.carousel | r2 | unsettled | **unsettled** ~ | 84142 / 226 | 3 | 2652.0 |
| fit | playwright-webkit | touch-1031 | 1031@2 | hero.orbit | r2 | unsettled | **unsettled** | 8454 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | touch-1031 | 1031@2 | hero.exit | r2 | unsettled | **unsettled** | 8171 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | touch-1031 | 1031@2 | morph.panel | r2 | pass | **fail** | 12600 / 99 | 17 | 47099.6 |
| fit | playwright-webkit | touch-1031 | 1031@2 | morph.columns | r2 | pass | **fail** | 15646 / 110 | 17 | 47099.6 |
| fit | playwright-webkit | touch-1031 | 1031@2 | people.card | r2 | fail | **fail** | 2055 / 150 | 12 | 25199.9 |
| fit | playwright-webkit | touch-1031 | 1031@2 | people.carousel | r2 | unsettled | **unsettled** | 73157 / 226 | 6 | 7125.3 |
| fit | playwright-webkit | touch-1031 | 1031@2 | people.deck | r2 | pass | **fail** | 2194 / 70 | 8 | 21663.9 |
| exact | playwright-webkit | desk-721 | 721@1 | people.card | r2 | fail | **fail** ~ | 3612 / 151 | 2 | 1792.0 |
| exact | playwright-webkit | desk-721 | 721@1 | people.carousel | r2 | unsettled | **fail** ~ | 7678 / 107 | 2 | 1792.0 |
| fit | playwright-webkit | desk-721 | 721@1 | hero.orbit | r2 | unsettled | **unsettled** | 34616 / 212 | 20 | 46989.0 |
| fit | playwright-webkit | desk-721 | 721@1 | hero.exit | r2 | unsettled | **unsettled** | 32515 / 212 | 20 | 46989.0 |
| fit | playwright-webkit | desk-721 | 721@1 | morph.panel | r2 | pass | **fail** | 13362 / 99 | 21 | 58645.0 |
| fit | playwright-webkit | desk-721 | 721@1 | morph.columns | r2 | pass | **fail** | 20155 / 89 | 21 | 58645.0 |
| fit | playwright-webkit | desk-721 | 721@1 | people.card | r2 | fail | **fail** | 29419 / 151 | 14 | 45854.3 |
| fit | playwright-webkit | desk-721 | 721@1 | people.carousel | r2 | unsettled | **fail** | 102359 / 248 | 6 | 7246.0 |
| fit | playwright-webkit | desk-721 | 721@1 | people.deck | r2 | fail | **fail** | 35725 / 154 | 10 | 42270.3 |
| exact | playwright-webkit | touch-481 | 481@3 | people.card | r2 | fail | **fail** ~ | 685 / 154 | 2 | 1728.0 |
| exact | playwright-webkit | touch-481 | 481@3 | people.carousel | r2 | unsettled | **fail** ~ | 115566 / 247 | 2 | 1728.0 |
| fit | playwright-webkit | touch-481 | 481@3 | hero.deck | r2 | unsettled | **unsettled** | 1825 / 212 | 8 | 13689.6 |
| fit | playwright-webkit | touch-481 | 481@3 | hero.exit | r2 | unsettled | **unsettled** | 1106 / 177 | 8 | 13689.6 |
| fit | playwright-webkit | touch-481 | 481@3 | morph.panel | r2 | pass | **pass** | 0 / 0 | 8 | 19691.0 |
| fit | playwright-webkit | touch-481 | 481@3 | morph.columns | r2 | pass | **pass** | 0 / 0 | 8 | 19691.0 |
| fit | playwright-webkit | touch-481 | 481@3 | people.card | r2 | fail | **fail** | 6645 / 115 | 14 | 36796.0 |
| fit | playwright-webkit | touch-481 | 481@3 | people.carousel | r2 | unsettled | **unsettled** | 110502 / 238 | 6 | 6922.8 |
| fit | playwright-webkit | touch-481 | 481@3 | people.deck | r2 | fail | **fail** | 8791 / 185 | 10 | 33340.0 |
| exact | playwright-webkit | desk-401 | 401@1 | people.card | r2 | fail | **fail** | 1239 / 121 | 2 | 1792.0 |
| exact | playwright-webkit | desk-401 | 401@1 | people.carousel | r2 | unsettled | **unsettled** | 69793 / 246 | 2 | 1792.0 |
| fit | playwright-webkit | desk-401 | 401@1 | hero.deck | r2 | unsettled | **unsettled** | 14361 / 212 | 8 | 17146.0 |
| fit | playwright-webkit | desk-401 | 401@1 | hero.exit | r2 | unsettled | **unsettled** | 9817 / 212 | 8 | 17146.0 |
| fit | playwright-webkit | desk-401 | 401@1 | morph.panel | r2 | pass | **pass** | 0 / 0 | 13 | 28474.2 |
| fit | playwright-webkit | desk-401 | 401@1 | morph.columns | r2 | pass | **pass** | 0 / 0 | 13 | 28474.2 |
| fit | playwright-webkit | desk-401 | 401@1 | people.card | r2 | fail | **fail** | 30266 / 183 | 14 | 48455.1 |
| fit | playwright-webkit | desk-401 | 401@1 | people.carousel | r2 | unsettled | **fail** | 69793 / 245 | 6 | 7246.0 |
| fit | playwright-webkit | desk-401 | 401@1 | people.deck | r2 | fail | **fail** | 37657 / 183 | 10 | 44871.1 |
| exact | playwright-webkit | desk-1101 | 1101@1 | people.card | r2 | fail | **fail** ~ | 4963 / 216 | 1 | 1596.0 |
| exact | playwright-webkit | desk-1101 | 1101@1 | people.carousel | r2 | unsettled | **fail** ~ | 212277 / 255 | 1 | 1596.0 |
| fit | playwright-webkit | desk-1101 | 1101@1 | hero.orbit | r2 | unsettled | **unsettled** | 38382 / 212 | 20 | 47150.0 |
| fit | playwright-webkit | desk-1101 | 1101@1 | hero.exit | r2 | unsettled | **unsettled** | 38009 / 207 | 20 | 47150.0 |
| fit | playwright-webkit | desk-1101 | 1101@1 | morph.panel | r2 | pass | **fail** | 20157 / 95 | 21 | 56258.6 |
| fit | playwright-webkit | desk-1101 | 1101@1 | morph.columns | r2 | pass | **fail** | 24009 / 101 | 21 | 56258.6 |
| fit | playwright-webkit | desk-1101 | 1101@1 | people.card | r2 | fail | **fail** | 17730 / 181 | 41 | 186450.5 |
| fit | playwright-webkit | desk-1101 | 1101@1 | people.carousel | r2 | unsettled | **fail** | 67038 / 218 | 6 | 7197.2 |
| fit | playwright-webkit | desk-1101 | 1101@1 | people.deck | r2 | unsettled | **unsettled** | 81484 / 255 | 39 | 183958.5 |
| fit | playwright-webkit | touch-1512 | 1512@2 | hero.orbit | r2 | unsettled | **unsettled** | 6247 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | touch-1512 | 1512@2 | hero.exit | r2 | unsettled | **unsettled** | 6079 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | touch-1512 | 1512@2 | morph.panel | r2 | pass | **pass** | 0 / 0 | 16 | 38693.8 |
| fit | playwright-webkit | touch-1512 | 1512@2 | morph.columns | r2 | pass | **fail** | 5739 / 115 | 16 | 38693.8 |
| fit | playwright-webkit | touch-1512 | 1512@2 | people.card | r2 | fail | **fail** | 6694 / 123 | 41 | 162031.0 |
| fit | playwright-webkit | touch-1512 | 1512@2 | people.carousel | r2 | unsettled | **unsettled** | 912 / 77 | 6 | 6922.3 |
| fit | playwright-webkit | touch-1512 | 1512@2 | people.deck | r2 | unsettled | **unsettled** | 168244 / 255 | 39 | 159563.0 |
| exact | playwright-webkit | phone-landscape-no-preference | 932@3 | people.card | r2 | fail | **fail** | 704 / 189 | 1 | 864.0 |
| exact | playwright-webkit | phone-landscape-no-preference | 932@3 | people.carousel | r2 | fail | **unsettled** | 76996 / 230 | 1 | 864.0 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | hero.orbit | r2 | unsettled | **unsettled** | 12177 / 212 | 18 | 24829.8 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | hero.exit | r2 | unsettled | **unsettled** | 11592 / 212 | 18 | 24829.8 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | morph.panel | r2 | pass | **pass** | 89 / 53 | 15 | 40267.4 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | morph.columns | r2 | pass | **pass** | 133 / 54 | 15 | 40267.4 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | people.card | r2 | fail | **fail** | 647 / 154 | 9 | 12508.8 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | people.carousel | r2 | fail | **unsettled** | 74661 / 245 | 6 | 6922.8 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | people.deck | r2 | pass | **pass** | 14 / 48 | 5 | 9052.8 |
| exact | playwright-webkit | touch-401 | 401@3 | people.card | r2 | fail | **fail** ~ | 2045 / 154 | 2 | 1728.0 |
| exact | playwright-webkit | touch-401 | 401@3 | people.carousel | r2 | unsettled | **unsettled** ~ | 453 / 67 | 2 | 1728.0 |
| fit | playwright-webkit | touch-401 | 401@3 | hero.deck | r2 | unsettled | **unsettled** | 2527 / 212 | 8 | 13689.6 |
| fit | playwright-webkit | touch-401 | 401@3 | hero.exit | r2 | unsettled | **unsettled** | 1821 / 212 | 8 | 13689.6 |
| fit | playwright-webkit | touch-401 | 401@3 | morph.panel | r2 | pass | **pass** | 0 / 0 | 9 | 21834.7 |
| fit | playwright-webkit | touch-401 | 401@3 | morph.columns | r2 | pass | **pass** | 0 / 0 | 9 | 21834.7 |
| fit | playwright-webkit | touch-401 | 401@3 | people.card | r2 | fail | **fail** | 7860 / 119 | 14 | 41143.8 |
| fit | playwright-webkit | touch-401 | 401@3 | people.carousel | r2 | unsettled | **unsettled** | 68742 / 239 | 6 | 6922.8 |
| fit | playwright-webkit | touch-401 | 401@3 | people.deck | r2 | fail | **fail** | 10945 / 196 | 10 | 37687.8 |
| exact | playwright-webkit | desk-481 | 481@1 | people.card | r2 | fail | **fail** ~ | 6091 / 151 | 3 | 2688.0 |
| exact | playwright-webkit | desk-481 | 481@1 | people.carousel | r2 | unsettled | **fail** ~ | 120809 / 246 | 3 | 2688.0 |
| fit | playwright-webkit | desk-481 | 481@1 | hero.deck | r2 | unsettled | **unsettled** | 11973 / 212 | 8 | 17146.0 |
| fit | playwright-webkit | desk-481 | 481@1 | hero.exit | r2 | unsettled | **unsettled** | 8189 / 212 | 8 | 17146.0 |
| fit | playwright-webkit | desk-481 | 481@1 | morph.panel | r2 | pass | **pass** | 0 / 0 | 13 | 28025.4 |
| fit | playwright-webkit | desk-481 | 481@1 | morph.columns | r2 | pass | **pass** | 0 / 0 | 13 | 28025.4 |
| fit | playwright-webkit | desk-481 | 481@1 | people.card | r2 | fail | **fail** | 28991 / 164 | 14 | 47966.8 |
| fit | playwright-webkit | desk-481 | 481@1 | people.carousel | r2 | unsettled | **unsettled** | 116169 / 236 | 6 | 7246.0 |
| fit | playwright-webkit | desk-481 | 481@1 | people.deck | r2 | fail | **fail** | 38982 / 222 | 10 | 44382.8 |
| exact | playwright-webkit | touch-320 | 320@3 | people.card | r2 | fail | **fail** ~ | 3505 / 174 | 3 | 2592.0 |
| exact | playwright-webkit | touch-320 | 320@3 | people.carousel | r2 | unsettled | **fail** ~ | 85327 / 249 | 3 | 2592.0 |
| fit | playwright-webkit | touch-320 | 320@3 | hero.deck | r2 | unsettled | **unsettled** | 2077 / 212 | 8 | 13689.6 |
| fit | playwright-webkit | touch-320 | 320@3 | hero.exit | r2 | unsettled | **unsettled** | 3177 / 212 | 8 | 13689.6 |
| fit | playwright-webkit | touch-320 | 320@3 | morph.panel | r2 | pass | **pass** | 0 / 0 | 13 | 24521.0 |
| fit | playwright-webkit | touch-320 | 320@3 | morph.columns | r2 | pass | **pass** | 0 / 0 | 13 | 24521.0 |
| fit | playwright-webkit | touch-320 | 320@3 | people.card | r2 | fail | **fail** | 10157 / 135 | 14 | 44632.9 |
| fit | playwright-webkit | touch-320 | 320@3 | people.carousel | r2 | unsettled | **unsettled** | 80126 / 238 | 6 | 6922.8 |
| fit | playwright-webkit | touch-320 | 320@3 | people.deck | r2 | fail | **fail** | 14972 / 135 | 10 | 41176.9 |
| fit | playwright-webkit | desk-1201 | 1201@1 | hero.orbit | r2 | unsettled | **unsettled** | 26887 / 212 | 20 | 46292.7 |
| fit | playwright-webkit | desk-1201 | 1201@1 | hero.exit | r2 | unsettled | **unsettled** | 26740 / 212 | 20 | 46292.7 |
| fit | playwright-webkit | desk-1201 | 1201@1 | morph.panel | r2 | pass | **fail** | 7049 / 75 | 21 | 55534.9 |
| fit | playwright-webkit | desk-1201 | 1201@1 | morph.columns | r2 | pass | **fail** | 9600 / 82 | 21 | 55534.9 |
| fit | playwright-webkit | desk-1201 | 1201@1 | people.card | r2 | fail | **fail** | 22058 / 205 | 41 | 185367.3 |
| fit | playwright-webkit | desk-1201 | 1201@1 | people.carousel | r2 | fail | **unsettled** | 149224 / 255 | 6 | 7197.2 |
| fit | playwright-webkit | desk-1201 | 1201@1 | people.deck | r2 | unsettled | **unsettled** | 93526 / 255 | 39 | 182875.3 |
| exact | playwright-webkit | desk-601 | 601@1 | people.card | r2 | fail | **fail** ~ | 2830 / 164 | 2 | 1792.0 |
| exact | playwright-webkit | desk-601 | 601@1 | people.carousel | r2 | fail | **unsettled** ~ | 117605 / 246 | 2 | 1792.0 |
| fit | playwright-webkit | desk-601 | 601@1 | hero.orbit | r2 | unsettled | **unsettled** | 33015 / 212 | 20 | 46965.5 |
| fit | playwright-webkit | desk-601 | 601@1 | hero.exit | r2 | unsettled | **unsettled** | 30285 / 212 | 20 | 46965.5 |
| fit | playwright-webkit | desk-601 | 601@1 | morph.panel | r2 | pass | **fail** | 12102 / 103 | 13 | 27209.5 |
| fit | playwright-webkit | desk-601 | 601@1 | morph.columns | r2 | pass | **fail** | 22625 / 107 | 13 | 27209.5 |
| fit | playwright-webkit | desk-601 | 601@1 | people.card | r2 | fail | **fail** | 29902 / 151 | 14 | 47034.1 |
| fit | playwright-webkit | desk-601 | 601@1 | people.carousel | r2 | fail | **unsettled** | 117660 / 245 | 6 | 7246.0 |
| fit | playwright-webkit | desk-601 | 601@1 | people.deck | r2 | fail | **fail** | 35950 / 181 | 10 | 43450.1 |
| fit | playwright-webkit | desk-1280 | 1280@1 | hero.orbit | r2 | unsettled | **unsettled** | 36217 / 212 | 20 | 47167.4 |
| fit | playwright-webkit | desk-1280 | 1280@1 | hero.exit | r2 | unsettled | **unsettled** | 35708 / 207 | 20 | 47167.4 |
| fit | playwright-webkit | desk-1280 | 1280@1 | morph.panel | r2 | pass | **fail** | 17220 / 87 | 21 | 54897.1 |
| fit | playwright-webkit | desk-1280 | 1280@1 | morph.columns | r2 | pass | **fail** | 21570 / 105 | 21 | 54897.1 |
| fit | playwright-webkit | desk-1280 | 1280@1 | people.card | r2 | fail | **fail** | 25897 / 222 | 41 | 184443.2 |
| fit | playwright-webkit | desk-1280 | 1280@1 | people.carousel | r2 | unsettled | **unsettled** | 124042 / 255 | 6 | 7197.2 |
| fit | playwright-webkit | desk-1280 | 1280@1 | people.deck | r2 | unsettled | **unsettled** | 98599 / 255 | 39 | 181951.2 |
| exact | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.card | r2 | fail | **fail** ~ | 3708 / 166 | 1 | 884.0 |
| exact | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.carousel | r2 | fail | **unsettled** ~ | 72340 / 197 | 1 | 884.0 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | hero.orbit | r2 | unsettled | **unsettled** | 7555 / 124 | 20 | 37181.1 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | hero.exit | r2 | unsettled | **unsettled** | 7545 / 124 | 20 | 37181.1 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | morph.panel | r2 | pass | **fail** | 3018 / 99 | 17 | 47460.5 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | morph.columns | r2 | pass | **fail** | 6146 / 126 | 17 | 47460.5 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.card | r2 | fail | **fail** | 2949 / 125 | 12 | 25514.7 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.carousel | r2 | fail | **unsettled** | 74338 / 222 | 6 | 7125.3 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.deck | r2 | fail | **fail** | 4891 / 166 | 8 | 21978.7 |
| exact | playwright-webkit | desk-320 | 320@1 | people.card | r2 | fail | **fail** ~ | 13493 / 204 | 2 | 1792.0 |
| exact | playwright-webkit | desk-320 | 320@1 | people.carousel | r2 | fail | **unsettled** ~ | 80255 / 232 | 2 | 1792.0 |
| fit | playwright-webkit | desk-320 | 320@1 | hero.deck | r2 | unsettled | **unsettled** | 18267 / 212 | 8 | 17146.0 |
| fit | playwright-webkit | desk-320 | 320@1 | hero.exit | r2 | unsettled | **unsettled** | 12247 / 212 | 8 | 17146.0 |
| fit | playwright-webkit | desk-320 | 320@1 | morph.panel | r2 | pass | **pass** | 0 / 0 | 13 | 28824.1 |
| fit | playwright-webkit | desk-320 | 320@1 | morph.columns | r2 | pass | **pass** | 0 / 0 | 13 | 28824.1 |
| fit | playwright-webkit | desk-320 | 320@1 | people.card | r2 | fail | **fail** | 28288 / 183 | 14 | 48842.4 |
| fit | playwright-webkit | desk-320 | 320@1 | people.carousel | r2 | fail | **fail** | 86535 / 245 | 6 | 7246.0 |
| fit | playwright-webkit | desk-320 | 320@1 | people.deck | r2 | fail | **fail** | 41593 / 183 | 10 | 45258.4 |
| exact | playwright-webkit | touch-601 | 601@2 | people.card | r2 | fail | **fail** | 1522 / 119 | 2 | 1768.0 |
| exact | playwright-webkit | touch-601 | 601@2 | people.carousel | r2 | unsettled | **unsettled** | 121437 / 249 | 2 | 1768.0 |
| fit | playwright-webkit | touch-601 | 601@2 | hero.orbit | r2 | unsettled | **unsettled** | 15192 / 212 | 20 | 37181.1 |
| fit | playwright-webkit | touch-601 | 601@2 | hero.exit | r2 | unsettled | **unsettled** | 15341 / 212 | 20 | 37181.1 |
| fit | playwright-webkit | touch-601 | 601@2 | morph.panel | r2 | pass | **fail** | 8492 / 118 | 9 | 21463.9 |
| fit | playwright-webkit | touch-601 | 601@2 | morph.columns | r2 | pass | **fail** | 15492 / 120 | 9 | 21463.9 |
| fit | playwright-webkit | touch-601 | 601@2 | people.card | r2 | fail | **fail** | 10564 / 119 | 14 | 40022.9 |
| fit | playwright-webkit | touch-601 | 601@2 | people.carousel | r2 | unsettled | **unsettled** | 123091 / 240 | 6 | 7125.3 |
| fit | playwright-webkit | touch-601 | 601@2 | people.deck | r2 | fail | **fail** | 11911 / 136 | 10 | 36486.9 |
| fit | playwright-webkit | desk-1031 | 1031@1 | hero.orbit | r2 | unsettled | **unsettled** | 28898 / 212 | 20 | 46432.4 |
| fit | playwright-webkit | desk-1031 | 1031@1 | hero.exit | r2 | unsettled | **unsettled** | 28748 / 205 | 20 | 46432.4 |
| fit | playwright-webkit | desk-1031 | 1031@1 | morph.panel | r2 | pass | **fail** | 17836 / 90 | 21 | 56738.6 |
| fit | playwright-webkit | desk-1031 | 1031@1 | morph.columns | r2 | pass | **fail** | 20012 / 103 | 21 | 56738.6 |
| fit | playwright-webkit | desk-1031 | 1031@1 | people.card | r2 | fail | **fail** | 16474 / 195 | 41 | 187099.7 |
| fit | playwright-webkit | desk-1031 | 1031@1 | people.carousel | r2 | unsettled | **unsettled** | 129344 / 255 | 6 | 7197.2 |
| fit | playwright-webkit | desk-1031 | 1031@1 | people.deck | r2 | unsettled | **unsettled** | 22995 / 248 | 39 | 184607.7 |
| exact | playwright-webkit | touch-861 | 861@2 | people.card | r2 | fail | **fail** ~ | 3607 / 119 | 4 | 3536.0 |
| exact | playwright-webkit | touch-861 | 861@2 | people.carousel | r2 | unsettled | **unsettled** ~ | 81564 / 226 | 4 | 3536.0 |
| fit | playwright-webkit | touch-861 | 861@2 | hero.orbit | r2 | unsettled | **unsettled** | 8982 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | touch-861 | 861@2 | hero.exit | r2 | unsettled | **unsettled** | 8777 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | touch-861 | 861@2 | morph.panel | r2 | pass | **fail** | 11250 / 108 | 21 | 50851.7 |
| fit | playwright-webkit | touch-861 | 861@2 | morph.columns | r2 | pass | **fail** | 16859 / 120 | 21 | 50851.7 |
| fit | playwright-webkit | touch-861 | 861@2 | people.card | r2 | fail | **fail** | 4748 / 119 | 13 | 32450.3 |
| fit | playwright-webkit | touch-861 | 861@2 | people.carousel | r2 | unsettled | **fail** | 78606 / 234 | 6 | 7125.3 |
| fit | playwright-webkit | touch-861 | 861@2 | people.deck | r2 | fail | **fail** | 7791 / 144 | 9 | 28914.3 |
| fit | playwright-webkit | desk-861 | 861@1 | hero.orbit | r2 | unsettled | **unsettled** | 32029 / 180 | 20 | 46596.5 |
| fit | playwright-webkit | desk-861 | 861@1 | hero.exit | r2 | unsettled | **unsettled** | 31851 / 180 | 20 | 46596.5 |
| fit | playwright-webkit | desk-861 | 861@1 | morph.panel | r2 | pass | **fail** | 9004 / 82 | 21 | 57871.1 |
| fit | playwright-webkit | desk-861 | 861@1 | morph.columns | r2 | pass | **fail** | 11985 / 84 | 21 | 57871.1 |
| fit | playwright-webkit | desk-861 | 861@1 | people.card | r2 | fail | **fail** | 21150 / 159 | 33 | 136018.4 |
| fit | playwright-webkit | desk-861 | 861@1 | people.carousel | r2 | unsettled | **fail** | 120270 / 255 | 6 | 7212.5 |
| fit | playwright-webkit | desk-861 | 861@1 | people.deck | r2 | unsettled | **unsettled** | 97876 / 255 | 32 | 135122.4 |
| fit | playwright-webkit | touch-1201 | 1201@2 | hero.orbit | r2 | unsettled | **unsettled** | 7325 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | touch-1201 | 1201@2 | hero.exit | r2 | unsettled | **unsettled** | 7165 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | touch-1201 | 1201@2 | morph.panel | r2 | pass | **fail** | 10744 / 97 | 16 | 43913.2 |
| fit | playwright-webkit | touch-1201 | 1201@2 | morph.columns | r2 | pass | **fail** | 15148 / 114 | 16 | 43913.2 |
| fit | playwright-webkit | touch-1201 | 1201@2 | people.card | r2 | fail | **fail** | 8690 / 146 | 41 | 173406.3 |
| fit | playwright-webkit | touch-1201 | 1201@2 | people.carousel | r2 | unsettled | **unsettled** | 68098 / 133 | 6 | 6923.4 |
| fit | playwright-webkit | touch-1201 | 1201@2 | people.deck | r2 | unsettled | **unsettled** | 116553 / 255 | 39 | 170938.3 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | hero.orbit | r2 | unsettled | **unsettled** | 7588 / 212 | 20 | 37181.1 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | hero.exit | r2 | unsettled | **unsettled** | 7434 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.panel | r2 | pass | **fail** | 10835 / 97 | 16 | 43913.2 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.columns | r2 | pass | **fail** | 15139 / 112 | 16 | 43913.2 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.card | r2 | fail | **fail** | 10466 / 176 | 41 | 172714.9 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.carousel | r2 | unsettled | **unsettled** | 619 / 60 | 6 | 6923.4 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.deck | r2 | unsettled | **unsettled** | 118501 / 255 | 39 | 170246.9 |
| fit | playwright-webkit | desk-1512 | 1512@1 | hero.orbit | r3 | unsettled | **unsettled** | 16440 / 212 | 20 | 45095.2 |
| fit | playwright-webkit | desk-1512 | 1512@1 | hero.exit | r3 | unsettled | **unsettled** | 15822 / 174 | 20 | 45095.2 |
| fit | playwright-webkit | desk-1512 | 1512@1 | morph.panel | r3 | pass | **pass** | 0 / 0 | 21 | 53541.6 |
| fit | playwright-webkit | desk-1512 | 1512@1 | morph.columns | r3 | pass | **fail** | 4749 / 80 | 21 | 53541.6 |
| fit | playwright-webkit | desk-1512 | 1512@1 | people.card | r3 | fail | **fail** | 29561 / 255 | 41 | 182528.4 |
| fit | playwright-webkit | desk-1512 | 1512@1 | people.carousel | r3 | unsettled | **fail** | 118056 / 255 | 6 | 7196.6 |
| fit | playwright-webkit | desk-1512 | 1512@1 | people.deck | r3 | unsettled | **unsettled** | 50209 / 255 | 39 | 180036.4 |
| fit | playwright-webkit | touch-1031 | 1031@2 | hero.orbit | r3 | unsettled | **unsettled** | 8085 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | touch-1031 | 1031@2 | hero.exit | r3 | unsettled | **unsettled** | 8078 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | touch-1031 | 1031@2 | morph.panel | r3 | pass | **fail** | 12600 / 99 | 17 | 47099.6 |
| fit | playwright-webkit | touch-1031 | 1031@2 | morph.columns | r3 | pass | **fail** | 15646 / 110 | 17 | 47099.6 |
| fit | playwright-webkit | touch-1031 | 1031@2 | people.card | r3 | fail | **fail** | 2289 / 150 | 12 | 25230.6 |
| fit | playwright-webkit | touch-1031 | 1031@2 | people.carousel | r3 | unsettled | **unsettled** | 73710 / 234 | 6 | 7125.3 |
| fit | playwright-webkit | touch-1031 | 1031@2 | people.deck | r3 | pass | **fail** | 2433 / 70 | 8 | 21694.6 |
| exact | playwright-webkit | desk-721 | 721@1 | people.card | r3 | fail | **fail** ~ | 3413 / 145 | 1 | 896.0 |
| exact | playwright-webkit | desk-721 | 721@1 | people.carousel | r3 | unsettled | **unsettled** ~ | 96282 / 224 | 1 | 896.0 |
| fit | playwright-webkit | desk-721 | 721@1 | hero.orbit | r3 | unsettled | **unsettled** | 20114 / 212 | 20 | 46049.1 |
| fit | playwright-webkit | desk-721 | 721@1 | hero.exit | r3 | unsettled | **unsettled** | 19704 / 156 | 20 | 46049.1 |
| fit | playwright-webkit | desk-721 | 721@1 | morph.panel | r3 | pass | **fail** | 7130 / 91 | 21 | 58645.0 |
| fit | playwright-webkit | desk-721 | 721@1 | morph.columns | r3 | pass | **fail** | 10407 / 77 | 21 | 58645.0 |
| fit | playwright-webkit | desk-721 | 721@1 | people.card | r3 | fail | **fail** | 29616 / 151 | 14 | 45857.0 |
| fit | playwright-webkit | desk-721 | 721@1 | people.carousel | r3 | unsettled | **unsettled** | 103077 / 229 | 6 | 7246.0 |
| fit | playwright-webkit | desk-721 | 721@1 | people.deck | r3 | fail | **fail** | 35934 / 154 | 10 | 42273.0 |
| exact | playwright-webkit | touch-481 | 481@3 | people.card | r3 | fail | **fail** ~ | 551 / 154 | 1 | 864.0 |
| exact | playwright-webkit | touch-481 | 481@3 | people.carousel | r3 | unsettled | **fail** ~ | 113178 / 250 | 1 | 864.0 |
| fit | playwright-webkit | touch-481 | 481@3 | hero.deck | r3 | unsettled | **unsettled** | 2036 / 177 | 8 | 13689.6 |
| fit | playwright-webkit | touch-481 | 481@3 | hero.exit | r3 | unsettled | **unsettled** | 5896 / 212 | 8 | 13689.6 |
| fit | playwright-webkit | touch-481 | 481@3 | morph.panel | r3 | pass | **pass** | 0 / 0 | 8 | 19691.0 |
| fit | playwright-webkit | touch-481 | 481@3 | morph.columns | r3 | pass | **pass** | 0 / 0 | 8 | 19691.0 |
| fit | playwright-webkit | touch-481 | 481@3 | people.card | r3 | fail | **fail** | 6974 / 115 | 14 | 36757.8 |
| fit | playwright-webkit | touch-481 | 481@3 | people.carousel | r3 | unsettled | **unsettled** | 7616 / 221 | 6 | 6922.8 |
| fit | playwright-webkit | touch-481 | 481@3 | people.deck | r3 | fail | **fail** | 9149 / 185 | 10 | 33301.8 |
| exact | playwright-webkit | desk-401 | 401@1 | people.card | r3 | fail | **fail** | 1239 / 121 | 2 | 1792.0 |
| exact | playwright-webkit | desk-401 | 401@1 | people.carousel | r3 | unsettled | **unsettled** | 69984 / 249 | 2 | 1792.0 |
| fit | playwright-webkit | desk-401 | 401@1 | hero.deck | r3 | unsettled | **unsettled** | 14339 / 212 | 8 | 17146.0 |
| fit | playwright-webkit | desk-401 | 401@1 | hero.exit | r3 | unsettled | **unsettled** | 9823 / 212 | 8 | 17146.0 |
| fit | playwright-webkit | desk-401 | 401@1 | morph.panel | r3 | pass | **pass** | 0 / 0 | 13 | 28474.2 |
| fit | playwright-webkit | desk-401 | 401@1 | morph.columns | r3 | pass | **pass** | 0 / 0 | 13 | 28474.2 |
| fit | playwright-webkit | desk-401 | 401@1 | people.card | r3 | fail | **fail** | 30266 / 183 | 14 | 48455.1 |
| fit | playwright-webkit | desk-401 | 401@1 | people.carousel | r3 | unsettled | **unsettled** | 69793 / 245 | 6 | 7246.0 |
| fit | playwright-webkit | desk-401 | 401@1 | people.deck | r3 | fail | **fail** | 37657 / 183 | 10 | 44871.1 |
| fit | playwright-webkit | desk-1101 | 1101@1 | hero.orbit | r3 | unsettled | **unsettled** | 36918 / 212 | 20 | 47116.5 |
| fit | playwright-webkit | desk-1101 | 1101@1 | hero.exit | r3 | unsettled | **unsettled** | 36534 / 206 | 20 | 47116.5 |
| fit | playwright-webkit | desk-1101 | 1101@1 | morph.panel | r3 | pass | **fail** | 20601 / 96 | 21 | 56258.6 |
| fit | playwright-webkit | desk-1101 | 1101@1 | morph.columns | r3 | pass | **fail** | 24459 / 116 | 21 | 56258.6 |
| fit | playwright-webkit | desk-1101 | 1101@1 | people.card | r3 | fail | **fail** | 17720 / 184 | 41 | 186449.8 |
| fit | playwright-webkit | desk-1101 | 1101@1 | people.carousel | r3 | pass | **fail** | 23921 / 255 | 6 | 7197.2 |
| fit | playwright-webkit | desk-1101 | 1101@1 | people.deck | r3 | unsettled | **unsettled** | 81609 / 255 | 39 | 183957.8 |
| fit | playwright-webkit | touch-1512 | 1512@2 | hero.orbit | r3 | unsettled | **unsettled** | 12859 / 212 | 20 | 37181.1 |
| fit | playwright-webkit | touch-1512 | 1512@2 | hero.exit | r3 | unsettled | **unsettled** | 6070 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | touch-1512 | 1512@2 | morph.panel | r3 | pass | **pass** | 0 / 0 | 16 | 38693.8 |
| fit | playwright-webkit | touch-1512 | 1512@2 | morph.columns | r3 | pass | **fail** | 5739 / 115 | 16 | 38693.8 |
| fit | playwright-webkit | touch-1512 | 1512@2 | people.card | r3 | fail | **fail** | 7263 / 115 | 41 | 162163.0 |
| fit | playwright-webkit | touch-1512 | 1512@2 | people.carousel | r3 | unsettled | **unsettled** | 65881 / 133 | 6 | 6923.4 |
| fit | playwright-webkit | touch-1512 | 1512@2 | people.deck | r3 | unsettled | **unsettled** | 132874 / 255 | 39 | 159695.0 |
| exact | playwright-webkit | phone-landscape-no-preference | 932@3 | people.card | r3 | fail | **fail** ~ | 749 / 169 | 3 | 2592.0 |
| exact | playwright-webkit | phone-landscape-no-preference | 932@3 | people.carousel | r3 | unsettled | **unsettled** ~ | 70111 / 219 | 3 | 2592.0 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | hero.orbit | r3 | unsettled | **unsettled** | 12034 / 212 | 18 | 24829.8 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | hero.exit | r3 | unsettled | **unsettled** | 11592 / 212 | 18 | 24829.8 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | morph.panel | r3 | pass | **pass** | 89 / 53 | 15 | 40267.4 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | morph.columns | r3 | pass | **pass** | 133 / 54 | 15 | 40267.4 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | people.card | r3 | fail | **fail** | 647 / 154 | 9 | 12508.8 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | people.carousel | r3 | unsettled | **unsettled** | 76890 / 231 | 6 | 6922.8 |
| fit | playwright-webkit | phone-landscape-no-preference | 932@3 | people.deck | r3 | pass | **pass** | 14 / 48 | 5 | 9052.8 |
| fit | playwright-webkit | touch-401 | 401@3 | hero.deck | r3 | unsettled | **unsettled** | 11498 / 212 | 8 | 13689.6 |
| fit | playwright-webkit | touch-401 | 401@3 | hero.exit | r3 | unsettled | **unsettled** | 2068 / 212 | 8 | 13689.6 |
| fit | playwright-webkit | touch-401 | 401@3 | morph.panel | r3 | pass | **pass** | 0 / 0 | 9 | 21834.7 |
| fit | playwright-webkit | touch-401 | 401@3 | morph.columns | r3 | pass | **pass** | 0 / 0 | 9 | 21834.7 |
| fit | playwright-webkit | touch-401 | 401@3 | people.card | r3 | fail | **fail** | 8438 / 119 | 14 | 41144.5 |
| fit | playwright-webkit | touch-401 | 401@3 | people.carousel | r3 | fail | **unsettled** | 64914 / 251 | 6 | 6922.8 |
| fit | playwright-webkit | touch-401 | 401@3 | people.deck | r3 | fail | **fail** | 11631 / 196 | 10 | 37688.5 |
| fit | playwright-webkit | desk-481 | 481@1 | hero.deck | r3 | unsettled | **unsettled** | 11989 / 212 | 8 | 17146.0 |
| fit | playwright-webkit | desk-481 | 481@1 | hero.exit | r3 | unsettled | **unsettled** | 8184 / 212 | 8 | 17146.0 |
| fit | playwright-webkit | desk-481 | 481@1 | morph.panel | r3 | pass | **pass** | 0 / 0 | 13 | 28025.4 |
| fit | playwright-webkit | desk-481 | 481@1 | morph.columns | r3 | pass | **pass** | 0 / 0 | 13 | 28025.4 |
| fit | playwright-webkit | desk-481 | 481@1 | people.card | r3 | fail | **fail** | 30483 / 172 | 14 | 47971.0 |
| fit | playwright-webkit | desk-481 | 481@1 | people.carousel | r3 | fail | **unsettled** | 136110 / 250 | 6 | 7246.0 |
| fit | playwright-webkit | desk-481 | 481@1 | people.deck | r3 | fail | **fail** | 40610 / 222 | 10 | 44387.0 |
| exact | playwright-webkit | touch-320 | 320@3 | people.card | r3 | fail | **fail** ~ | 3618 / 174 | 3 | 2592.0 |
| exact | playwright-webkit | touch-320 | 320@3 | people.carousel | r3 | unsettled | **fail** ~ | 78751 / 238 | 3 | 2592.0 |
| fit | playwright-webkit | touch-320 | 320@3 | hero.deck | r3 | unsettled | **unsettled** | 2436 / 212 | 8 | 13689.6 |
| fit | playwright-webkit | touch-320 | 320@3 | hero.exit | r3 | unsettled | **unsettled** | 2266 / 177 | 8 | 13689.6 |
| fit | playwright-webkit | touch-320 | 320@3 | morph.panel | r3 | pass | **pass** | 0 / 0 | 13 | 24521.0 |
| fit | playwright-webkit | touch-320 | 320@3 | morph.columns | r3 | pass | **pass** | 0 / 0 | 13 | 24521.0 |
| fit | playwright-webkit | touch-320 | 320@3 | people.card | r3 | fail | **fail** | 10157 / 135 | 14 | 44632.9 |
| fit | playwright-webkit | touch-320 | 320@3 | people.carousel | r3 | unsettled | **fail** | 85710 / 247 | 6 | 6922.8 |
| fit | playwright-webkit | touch-320 | 320@3 | people.deck | r3 | fail | **fail** | 14972 / 135 | 10 | 41176.9 |
| fit | playwright-webkit | desk-1201 | 1201@1 | hero.orbit | r3 | unsettled | **unsettled** | 26439 / 212 | 20 | 46302.4 |
| fit | playwright-webkit | desk-1201 | 1201@1 | hero.exit | r3 | unsettled | **unsettled** | 26230 / 205 | 20 | 46302.4 |
| fit | playwright-webkit | desk-1201 | 1201@1 | morph.panel | r3 | pass | **fail** | 7049 / 75 | 21 | 55534.9 |
| fit | playwright-webkit | desk-1201 | 1201@1 | morph.columns | r3 | pass | **fail** | 9600 / 82 | 21 | 55534.9 |
| fit | playwright-webkit | desk-1201 | 1201@1 | people.card | r3 | fail | **fail** | 22263 / 205 | 41 | 185366.7 |
| fit | playwright-webkit | desk-1201 | 1201@1 | people.carousel | r3 | unsettled | **unsettled** | 1194 / 63 | 6 | 7197.2 |
| fit | playwright-webkit | desk-1201 | 1201@1 | people.deck | r3 | unsettled | **unsettled** | 83538 / 255 | 39 | 182874.7 |
| exact | playwright-webkit | desk-601 | 601@1 | people.card | r3 | fail | **fail** ~ | 2814 / 164 | 2 | 1792.0 |
| exact | playwright-webkit | desk-601 | 601@1 | people.carousel | r3 | unsettled | **fail** ~ | 121195 / 229 | 2 | 1792.0 |
| fit | playwright-webkit | desk-601 | 601@1 | hero.orbit | r3 | unsettled | **unsettled** | 34602 / 212 | 20 | 47005.5 |
| fit | playwright-webkit | desk-601 | 601@1 | hero.exit | r3 | unsettled | **unsettled** | 34653 / 212 | 20 | 47005.5 |
| fit | playwright-webkit | desk-601 | 601@1 | morph.panel | r3 | pass | **fail** | 12724 / 101 | 13 | 27209.5 |
| fit | playwright-webkit | desk-601 | 601@1 | morph.columns | r3 | pass | **fail** | 23661 / 111 | 13 | 27209.5 |
| fit | playwright-webkit | desk-601 | 601@1 | people.card | r3 | fail | **fail** | 30105 / 151 | 14 | 47036.2 |
| fit | playwright-webkit | desk-601 | 601@1 | people.carousel | r3 | unsettled | **fail** | 118433 / 248 | 6 | 7246.0 |
| fit | playwright-webkit | desk-601 | 601@1 | people.deck | r3 | fail | **fail** | 36170 / 181 | 10 | 43452.2 |
| fit | playwright-webkit | desk-1280 | 1280@1 | hero.orbit | r3 | unsettled | **unsettled** | 35397 / 212 | 20 | 47127.3 |
| fit | playwright-webkit | desk-1280 | 1280@1 | hero.exit | r3 | unsettled | **unsettled** | 34689 / 206 | 20 | 47127.3 |
| fit | playwright-webkit | desk-1280 | 1280@1 | morph.panel | r3 | pass | **fail** | 17936 / 92 | 21 | 54897.1 |
| fit | playwright-webkit | desk-1280 | 1280@1 | morph.columns | r3 | pass | **fail** | 22246 / 99 | 21 | 54897.1 |
| fit | playwright-webkit | desk-1280 | 1280@1 | people.card | r3 | fail | **fail** | 25897 / 222 | 41 | 184459.6 |
| fit | playwright-webkit | desk-1280 | 1280@1 | people.carousel | r3 | unsettled | **fail** | 185489 / 255 | 6 | 7197.2 |
| fit | playwright-webkit | desk-1280 | 1280@1 | people.deck | r3 | unsettled | **unsettled** | 57015 / 255 | 39 | 181967.6 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | hero.orbit | r3 | unsettled | **unsettled** | 7540 / 124 | 20 | 37181.1 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | hero.exit | r3 | unsettled | **unsettled** | 7394 / 124 | 20 | 37181.1 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | morph.panel | r3 | pass | **fail** | 3018 / 99 | 17 | 47460.5 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | morph.columns | r3 | pass | **fail** | 6146 / 126 | 17 | 47460.5 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.card | r3 | fail | **fail** | 6193 / 125 | 12 | 25571.2 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.carousel | r3 | unsettled | **unsettled** | 82317 / 233 | 6 | 7125.3 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | people.deck | r3 | fail | **fail** | 8534 / 166 | 8 | 22035.2 |
| exact | playwright-webkit | desk-320 | 320@1 | people.card | r3 | fail | **fail** ~ | 13163 / 204 | 1 | 896.0 |
| exact | playwright-webkit | desk-320 | 320@1 | people.carousel | r3 | fail | **fail** ~ | 88875 / 249 | 1 | 896.0 |
| fit | playwright-webkit | desk-320 | 320@1 | hero.deck | r3 | unsettled | **unsettled** | 17969 / 212 | 8 | 17146.0 |
| fit | playwright-webkit | desk-320 | 320@1 | hero.exit | r3 | unsettled | **unsettled** | 12205 / 212 | 8 | 17146.0 |
| fit | playwright-webkit | desk-320 | 320@1 | morph.panel | r3 | pass | **pass** | 0 / 0 | 13 | 28824.1 |
| fit | playwright-webkit | desk-320 | 320@1 | morph.columns | r3 | pass | **pass** | 0 / 0 | 13 | 28824.1 |
| fit | playwright-webkit | desk-320 | 320@1 | people.card | r3 | fail | **fail** | 28288 / 183 | 14 | 48842.4 |
| fit | playwright-webkit | desk-320 | 320@1 | people.carousel | r3 | fail | **unsettled** | 89491 / 240 | 6 | 7246.0 |
| fit | playwright-webkit | desk-320 | 320@1 | people.deck | r3 | fail | **fail** | 41593 / 183 | 10 | 45258.4 |
| exact | playwright-webkit | touch-601 | 601@2 | people.card | r3 | fail | **fail** | 1522 / 119 | 2 | 1768.0 |
| exact | playwright-webkit | touch-601 | 601@2 | people.carousel | r3 | unsettled | **unsettled** | 118680 / 250 | 2 | 1768.0 |
| fit | playwright-webkit | touch-601 | 601@2 | hero.orbit | r3 | unsettled | **unsettled** | 10811 / 212 | 20 | 37181.1 |
| fit | playwright-webkit | touch-601 | 601@2 | hero.exit | r3 | unsettled | **unsettled** | 9408 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | touch-601 | 601@2 | morph.panel | r3 | pass | **fail** | 8492 / 118 | 9 | 21463.9 |
| fit | playwright-webkit | touch-601 | 601@2 | morph.columns | r3 | pass | **fail** | 15492 / 120 | 9 | 21463.9 |
| fit | playwright-webkit | touch-601 | 601@2 | people.card | r3 | fail | **fail** | 11920 / 126 | 14 | 40031.6 |
| fit | playwright-webkit | touch-601 | 601@2 | people.carousel | r3 | unsettled | **fail** | 118496 / 249 | 6 | 7125.3 |
| fit | playwright-webkit | touch-601 | 601@2 | people.deck | r3 | fail | **fail** | 13363 / 136 | 10 | 36495.6 |
| fit | playwright-webkit | desk-1031 | 1031@1 | hero.orbit | r3 | unsettled | **unsettled** | 28432 / 212 | 20 | 46433.6 |
| fit | playwright-webkit | desk-1031 | 1031@1 | hero.exit | r3 | unsettled | **unsettled** | 28308 / 205 | 20 | 46433.6 |
| fit | playwright-webkit | desk-1031 | 1031@1 | morph.panel | r3 | pass | **fail** | 17836 / 90 | 21 | 56738.6 |
| fit | playwright-webkit | desk-1031 | 1031@1 | morph.columns | r3 | pass | **fail** | 20012 / 103 | 21 | 56738.6 |
| fit | playwright-webkit | desk-1031 | 1031@1 | people.card | r3 | fail | **fail** | 16583 / 205 | 41 | 187100.8 |
| fit | playwright-webkit | desk-1031 | 1031@1 | people.carousel | r3 | unsettled | **fail** | 125904 / 255 | 6 | 7197.2 |
| fit | playwright-webkit | desk-1031 | 1031@1 | people.deck | r3 | unsettled | **unsettled** | 31178 / 236 | 39 | 184608.8 |
| exact | playwright-webkit | touch-861 | 861@2 | people.card | r3 | fail | **fail** ~ | 3447 / 111 | 1 | 884.0 |
| exact | playwright-webkit | touch-861 | 861@2 | people.carousel | r3 | pass | **fail** ~ | 82062 / 233 | 1 | 884.0 |
| fit | playwright-webkit | touch-861 | 861@2 | hero.orbit | r3 | unsettled | **unsettled** | 8700 / 212 | 20 | 37181.1 |
| fit | playwright-webkit | touch-861 | 861@2 | hero.exit | r3 | unsettled | **unsettled** | 8778 / 138 | 20 | 37181.1 |
| fit | playwright-webkit | touch-861 | 861@2 | morph.panel | r3 | pass | **fail** | 11250 / 108 | 21 | 50851.7 |
| fit | playwright-webkit | touch-861 | 861@2 | morph.columns | r3 | pass | **fail** | 16859 / 120 | 21 | 50851.7 |
| fit | playwright-webkit | touch-861 | 861@2 | people.card | r3 | fail | **fail** | 7283 / 119 | 13 | 32473.9 |
| fit | playwright-webkit | touch-861 | 861@2 | people.carousel | r3 | pass | **fail** | 1224 / 72 | 6 | 7125.3 |
| fit | playwright-webkit | touch-861 | 861@2 | people.deck | r3 | fail | **fail** | 10704 / 144 | 9 | 28937.9 |
| fit | playwright-webkit | desk-861 | 861@1 | hero.orbit | r3 | unsettled | **unsettled** | 24708 / 161 | 20 | 46194.8 |
| fit | playwright-webkit | desk-861 | 861@1 | hero.exit | r3 | unsettled | **unsettled** | 24284 / 161 | 20 | 46194.8 |
| fit | playwright-webkit | desk-861 | 861@1 | morph.panel | r3 | pass | **fail** | 16377 / 90 | 21 | 57871.1 |
| fit | playwright-webkit | desk-861 | 861@1 | morph.columns | r3 | pass | **fail** | 21674 / 101 | 21 | 57871.1 |
| fit | playwright-webkit | desk-861 | 861@1 | people.card | r3 | fail | **fail** | 22693 / 161 | 33 | 136029.9 |
| fit | playwright-webkit | desk-861 | 861@1 | people.carousel | r3 | unsettled | **fail** | 130917 / 255 | 6 | 7212.5 |
| fit | playwright-webkit | desk-861 | 861@1 | people.deck | r3 | unsettled | **unsettled** | 75999 / 255 | 32 | 135133.9 |
| fit | playwright-webkit | touch-1201 | 1201@2 | hero.orbit | r3 | unsettled | **unsettled** | 13216 / 212 | 20 | 37181.1 |
| fit | playwright-webkit | touch-1201 | 1201@2 | hero.exit | r3 | unsettled | **unsettled** | 12935 / 212 | 20 | 37181.1 |
| fit | playwright-webkit | touch-1201 | 1201@2 | morph.panel | r3 | pass | **fail** | 10744 / 97 | 16 | 43913.2 |
| fit | playwright-webkit | touch-1201 | 1201@2 | morph.columns | r3 | pass | **fail** | 15148 / 114 | 16 | 43913.2 |
| fit | playwright-webkit | touch-1201 | 1201@2 | people.card | r3 | fail | **fail** | 8958 / 133 | 41 | 173424.7 |
| fit | playwright-webkit | touch-1201 | 1201@2 | people.carousel | r3 | unsettled | **fail** | 60742 / 132 | 6 | 6924.5 |
| fit | playwright-webkit | touch-1201 | 1201@2 | people.deck | r3 | unsettled | **unsettled** | 12773 / 218 | 39 | 170956.7 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | hero.orbit | r3 | unsettled | **unsettled** | 13449 / 212 | 20 | 37181.1 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | hero.exit | r3 | unsettled | **unsettled** | 13096 / 212 | 20 | 37181.1 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.panel | r3 | pass | **fail** | 10835 / 97 | 16 | 43913.2 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.columns | r3 | pass | **fail** | 15139 / 112 | 16 | 43913.2 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.card | r3 | fail | **fail** | 10521 / 176 | 41 | 172742.3 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.carousel | r3 | unsettled | **unsettled** | 153289 / 255 | 6 | 6923.4 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | people.deck | r3 | unsettled | **unsettled** | 118316 / 255 | 39 | 170274.3 |

### Why a file has no exact copy (run 39527779967, commit f3ee5ee0) (files per engine and probe; all reps together, `disputed` = the reps differ)

| engine | probe | width@dpr | ok | cropped | disputed | external | format:avif | format:svg | fractional | notImg | scaled |
|---|---|---|---|---|---|---|---|---|---|---|---|
| chromium | desk-1031 | 1031@1 | 0 | 49 | 1 | 1 | 3 | 21 | 0 | 41 | 2 |
| chromium | desk-1101 | 1101@1 | 0 | 49 | 2 | 1 | 3 | 21 | 0 | 41 | 1 |
| chromium | desk-1201 | 1201@1 | 0 | 49 | 1 | 1 | 3 | 21 | 0 | 41 | 2 |
| chromium | desk-1280 | 1280@1 | 0 | 49 | 1 | 1 | 3 | 21 | 0 | 41 | 2 |
| chromium | desk-1512 | 1512@1 | 1 | 49 | 2 | 1 | 3 | 21 | 0 | 41 | 0 |
| chromium | desk-320 | 320@1 | 2 | 25 | 2 | 1 | 3 | 20 | 0 | 11 | 4 |
| chromium | desk-401 | 401@1 | 2 | 26 | 0 | 1 | 3 | 20 | 1 | 11 | 4 |
| chromium | desk-481 | 481@1 | 2 | 26 | 0 | 1 | 3 | 20 | 0 | 11 | 5 |
| chromium | desk-601 | 601@1 | 2 | 40 | 2 | 1 | 3 | 20 | 0 | 11 | 1 |
| chromium | desk-721 | 721@1 | 2 | 52 | 0 | 1 | 3 | 20 | 0 | 11 | 2 |
| chromium | desk-861 | 861@1 | 0 | 51 | 1 | 1 | 3 | 20 | 0 | 34 | 1 |
| chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | 0 | 49 | 1 | 1 | 3 | 20 | 0 | 34 | 1 |
| chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | 0 | 49 | 2 | 1 | 3 | 21 | 0 | 41 | 1 |
| chromium | phone-landscape-no-preference | 932@3 | 0 | 48 | 3 | 1 | 3 | 20 | 0 | 12 | 3 |
| chromium | touch-1031 | 1031@2 | 1 | 50 | 1 | 1 | 3 | 20 | 0 | 11 | 2 |
| chromium | touch-1201 | 1201@2 | 0 | 50 | 0 | 1 | 3 | 21 | 0 | 41 | 2 |
| chromium | touch-1512 | 1512@2 | 1 | 49 | 2 | 1 | 3 | 21 | 0 | 41 | 0 |
| chromium | touch-320 | 320@3 | 2 | 25 | 2 | 1 | 3 | 20 | 0 | 11 | 4 |
| chromium | touch-401 | 401@3 | 2 | 26 | 0 | 1 | 3 | 20 | 0 | 11 | 5 |
| chromium | touch-481 | 481@3 | 2 | 26 | 2 | 1 | 3 | 20 | 0 | 11 | 3 |
| chromium | touch-601 | 601@2 | 2 | 40 | 1 | 1 | 3 | 20 | 0 | 11 | 2 |
| chromium | touch-861 | 861@2 | 2 | 50 | 0 | 1 | 3 | 20 | 0 | 11 | 2 |
| playwright-webkit | desk-1031 | 1031@1 | 0 | 50 | 1 | 1 | 3 | 21 | 0 | 41 | 1 |
| playwright-webkit | desk-1101 | 1101@1 | 0 | 49 | 2 | 1 | 3 | 21 | 0 | 41 | 1 |
| playwright-webkit | desk-1201 | 1201@1 | 0 | 49 | 2 | 1 | 3 | 21 | 0 | 41 | 1 |
| playwright-webkit | desk-1280 | 1280@1 | 0 | 49 | 2 | 1 | 3 | 21 | 0 | 41 | 1 |
| playwright-webkit | desk-1512 | 1512@1 | 1 | 43 | 1 | 1 | 3 | 21 | 0 | 41 | 7 |
| playwright-webkit | desk-320 | 320@1 | 0 | 25 | 4 | 1 | 3 | 20 | 0 | 12 | 4 |
| playwright-webkit | desk-401 | 401@1 | 2 | 26 | 1 | 1 | 3 | 20 | 0 | 12 | 4 |
| playwright-webkit | desk-481 | 481@1 | 0 | 25 | 3 | 1 | 3 | 20 | 0 | 12 | 5 |
| playwright-webkit | desk-601 | 601@1 | 1 | 40 | 3 | 1 | 3 | 20 | 0 | 12 | 1 |
| playwright-webkit | desk-721 | 721@1 | 0 | 48 | 7 | 1 | 3 | 20 | 0 | 12 | 1 |
| playwright-webkit | desk-861 | 861@1 | 0 | 51 | 1 | 1 | 3 | 20 | 0 | 34 | 1 |
| playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | 0 | 44 | 3 | 1 | 3 | 20 | 0 | 12 | 7 |
| playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | 0 | 43 | 2 | 1 | 3 | 21 | 0 | 41 | 7 |
| playwright-webkit | phone-landscape-no-preference | 932@3 | 1 | 44 | 2 | 1 | 3 | 20 | 0 | 13 | 7 |
| playwright-webkit | touch-1031 | 1031@2 | 0 | 43 | 4 | 1 | 3 | 20 | 0 | 12 | 7 |
| playwright-webkit | touch-1201 | 1201@2 | 0 | 43 | 2 | 1 | 3 | 21 | 0 | 41 | 7 |
| playwright-webkit | touch-1512 | 1512@2 | 1 | 43 | 0 | 1 | 3 | 21 | 0 | 41 | 8 |
| playwright-webkit | touch-320 | 320@3 | 1 | 25 | 3 | 1 | 3 | 20 | 0 | 12 | 4 |
| playwright-webkit | touch-401 | 401@3 | 0 | 28 | 3 | 1 | 3 | 20 | 0 | 12 | 4 |
| playwright-webkit | touch-481 | 481@3 | 0 | 25 | 4 | 1 | 3 | 20 | 0 | 12 | 4 |
| playwright-webkit | touch-601 | 601@2 | 2 | 34 | 3 | 1 | 3 | 20 | 0 | 12 | 6 |
| playwright-webkit | touch-861 | 861@2 | 0 | 43 | 4 | 1 | 3 | 20 | 0 | 12 | 7 |

