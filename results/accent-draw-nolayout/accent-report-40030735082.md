Sources: run 40030735082 commit 7e3e5fc96 jobs r1 r2 r3

Jobs counted (3): 120679004422, 120679004505, 120684273999. Records: 3. Arms: faithful = the page without a flag; nolayout = hero.accent:draw-nolayout; full = hero.accent:draw-nolayout-full; faithful-frozen = the default page with the draw-only freeze (path animations and the drawingIn width transition off, idle boil running).

### Units per job

| job | captures run | failed | skipped |
|---|---|---|---|
| 120679004422/p1/lane | 13 | - | - |
| 120679004505/p1/lane | 13 | - | - |
| 120684273999/p1/lane | 13 | - | - |

### Pooled Layout rows (windows with at least 24 rows are busy; rows per capture and median over the pooled windows)

| state | window kind | captures | windows | busy windows | Layout rows per capture | median |
|---|---|---|---|---|---|---|
| faithful | rest | 6 | 42 | 27 of 42 | 218.5 | 43 |
| faithful | swap | 6 | 48 | 0 of 48 | 75.8 | 9.5 |
| nolayout | rest | 3 | 21 | 6 of 21 | 109.0 | 5 |
| nolayout | swap | 3 | 24 | 0 of 24 | 83.0 | 10 |
| full | rest | 3 | 21 | 0 of 21 | 19.7 | 2 |
| full | swap | 3 | 24 | 0 of 24 | 73.3 | 9 |
| faithful-frozen | rest | 3 | 21 | 0 of 21 | 21.0 | 3 |
| faithful-frozen | swap | 3 | 24 | 0 of 24 | 94.7 | 12.5 |

### nolayout against faithful, window by window (Lean cell: needs at least 3 samples in each faithful slot)

Tally of swap windows (win / loss / unresolved of 8 per kind): Layout 0/0/8, Paint 0/0/8, Composite 0/0/8, RecalculateStyles 0/0/8

Tally of rest windows (win / loss / unresolved of 7 per kind): Layout 3/0/4, Paint 0/0/7, Composite 0/0/7, RecalculateStyles 0/0/7

Layout:

| window | faithful a | faithful b (A/A floor) | nolayout | dropped | verdict |
|---|---|---|---|---|---|
| swap:0 | 4-14 (n=3) | 7-11 (n=3) | 6-14 (n=3) | 0 | unresolved:overlap |
| swap:1 | 6-14 (n=3) | 10-13 (n=3) | 4-12 (n=3) | 0 | unresolved:overlap |
| swap:2 | 9-13 (n=3) | 6-14 (n=3) | 9-15 (n=3) | 0 | unresolved:overlap |
| swap:3 | 3-15 (n=3) | 10-12 (n=3) | 5-14 (n=3) | 0 | unresolved:overlap |
| swap:4 | 6-15 (n=3) | 6-9 (n=3) | 8-14 (n=3) | 0 | unresolved:overlap |
| swap:5 | 3-14 (n=3) | 10-13 (n=3) | 10-15 (n=3) | 0 | unresolved:overlap |
| swap:6 | 5-14 (n=3) | 3-11 (n=3) | 7-14 (n=3) | 0 | unresolved:overlap |
| swap:7 | 8-14 (n=3) | 8-11 (n=3) | 6-9 (n=3) | 0 | unresolved:overlap |
| rest:0 | 5-46 (n=3) | 5-47 (n=3) | 1-3 (n=3) | 0 | win |
| rest:1 | 43-50 (n=3) | 43-49 (n=3) | 45-49 (n=3) | 0 | unresolved:overlap |
| rest:2 | 5-47 (n=3) | 5-42 (n=3) | 5 (n=3) | 0 | unresolved:overlap |
| rest:3 | 5-45 (n=3) | 5-49 (n=3) | 1-3 (n=3) | 0 | win |
| rest:4 | 45-49 (n=3) | 45-50 (n=3) | 43-49 (n=3) | 0 | unresolved:overlap |
| rest:5 | 5-49 (n=3) | 4-47 (n=3) | 5 (n=3) | 0 | unresolved:overlap |
| rest:6 | 5-43 (n=3) | 5-45 (n=3) | 2-3 (n=3) | 0 | win |

Paint:

| window | faithful a | faithful b (A/A floor) | nolayout | dropped | verdict |
|---|---|---|---|---|---|
| swap:0 | 9-34 (n=3) | 15-27 (n=3) | 26-33 (n=3) | 0 | unresolved:overlap |
| swap:1 | 18-29 (n=3) | 21-36 (n=3) | 7-38 (n=3) | 0 | unresolved:overlap |
| swap:2 | 23-40 (n=3) | 11-33 (n=3) | 31-40 (n=3) | 0 | unresolved:overlap |
| swap:3 | 6-32 (n=3) | 22-26 (n=3) | 12-30 (n=3) | 0 | unresolved:overlap |
| swap:4 | 19-35 (n=3) | 15-18 (n=3) | 21-48 (n=3) | 0 | unresolved:floorBroken |
| swap:5 | 8-43 (n=3) | 23-40 (n=3) | 22-37 (n=3) | 0 | unresolved:overlap |
| swap:6 | 11-35 (n=3) | 19-29 (n=3) | 16-30 (n=3) | 0 | unresolved:overlap |
| swap:7 | 27-31 (n=3) | 17-30 (n=3) | 14-28 (n=3) | 0 | unresolved:overlap |
| rest:0 | 15-44 (n=3) | 1-45 (n=3) | 45-61 (n=3) | 0 | unresolved:overlap |
| rest:1 | 43-58 (n=3) | 42-64 (n=3) | 45-61 (n=3) | 0 | unresolved:overlap |
| rest:2 | 1-61 (n=3) | 1-60 (n=3) | 15 (n=3) | 0 | unresolved:overlap |
| rest:3 | 8-44 (n=3) | 15-61 (n=3) | 51-59 (n=3) | 0 | unresolved:overlap |
| rest:4 | 49-60 (n=3) | 43-64 (n=3) | 49-60 (n=3) | 0 | unresolved:overlap |
| rest:5 | 1-62 (n=3) | 1-47 (n=3) | 1-15 (n=3) | 0 | unresolved:overlap |
| rest:6 | 11-41 (n=3) | 15-59 (n=3) | 51-60 (n=3) | 0 | unresolved:overlap |


### full against faithful, window by window (Lean cell: needs at least 3 samples in each faithful slot)

Tally of swap windows (win / loss / unresolved of 8 per kind): Layout 0/0/8, Paint 0/0/8, Composite 0/0/8, RecalculateStyles 0/0/8

Tally of rest windows (win / loss / unresolved of 7 per kind): Layout 5/0/2, Paint 0/0/7, Composite 0/0/7, RecalculateStyles 0/0/7

Layout:

| window | faithful a | faithful b (A/A floor) | full | dropped | verdict |
|---|---|---|---|---|---|
| swap:0 | 4-14 (n=3) | 7-11 (n=3) | 8-9 (n=3) | 0 | unresolved:overlap |
| swap:1 | 6-14 (n=3) | 10-13 (n=3) | 3-13 (n=3) | 0 | unresolved:overlap |
| swap:2 | 9-13 (n=3) | 6-14 (n=3) | 9-14 (n=3) | 0 | unresolved:overlap |
| swap:3 | 3-15 (n=3) | 10-12 (n=3) | 4-10 (n=3) | 0 | unresolved:overlap |
| swap:4 | 6-15 (n=3) | 6-9 (n=3) | 6-15 (n=3) | 0 | unresolved:overlap |
| swap:5 | 3-14 (n=3) | 10-13 (n=3) | 7-13 (n=3) | 0 | unresolved:overlap |
| swap:6 | 5-14 (n=3) | 3-11 (n=3) | 2-12 (n=3) | 0 | unresolved:overlap |
| swap:7 | 8-14 (n=3) | 8-11 (n=3) | 5-13 (n=3) | 0 | unresolved:overlap |
| rest:0 | 5-46 (n=3) | 5-47 (n=3) | 1-3 (n=3) | 0 | win |
| rest:1 | 43-50 (n=3) | 43-49 (n=3) | 1-2 (n=3) | 0 | win |
| rest:2 | 5-47 (n=3) | 5-42 (n=3) | 5-6 (n=3) | 0 | unresolved:overlap |
| rest:3 | 5-45 (n=3) | 5-49 (n=3) | 1-3 (n=3) | 0 | win |
| rest:4 | 45-49 (n=3) | 45-50 (n=3) | 1-2 (n=3) | 0 | win |
| rest:5 | 5-49 (n=3) | 4-47 (n=3) | 5 (n=3) | 0 | unresolved:overlap |
| rest:6 | 5-43 (n=3) | 5-45 (n=3) | 1-3 (n=3) | 0 | win |

Paint:

| window | faithful a | faithful b (A/A floor) | full | dropped | verdict |
|---|---|---|---|---|---|
| swap:0 | 9-34 (n=3) | 15-27 (n=3) | 17-20 (n=3) | 0 | unresolved:overlap |
| swap:1 | 18-29 (n=3) | 21-36 (n=3) | 22-38 (n=3) | 0 | unresolved:overlap |
| swap:2 | 23-40 (n=3) | 11-33 (n=3) | 19-34 (n=3) | 0 | unresolved:overlap |
| swap:3 | 6-32 (n=3) | 22-26 (n=3) | 9-29 (n=3) | 0 | unresolved:overlap |
| swap:4 | 19-35 (n=3) | 15-18 (n=3) | 13-43 (n=3) | 0 | unresolved:floorBroken |
| swap:5 | 8-43 (n=3) | 23-40 (n=3) | 17-32 (n=3) | 0 | unresolved:overlap |
| swap:6 | 11-35 (n=3) | 19-29 (n=3) | 16-30 (n=3) | 0 | unresolved:overlap |
| swap:7 | 27-31 (n=3) | 17-30 (n=3) | 16-37 (n=3) | 0 | unresolved:overlap |
| rest:0 | 15-44 (n=3) | 1-45 (n=3) | 45-55 (n=3) | 0 | unresolved:overlap |
| rest:1 | 43-58 (n=3) | 42-64 (n=3) | 44-59 (n=3) | 0 | unresolved:overlap |
| rest:2 | 1-61 (n=3) | 1-60 (n=3) | 1-15 (n=3) | 0 | unresolved:overlap |
| rest:3 | 8-44 (n=3) | 15-61 (n=3) | 48-61 (n=3) | 0 | unresolved:overlap |
| rest:4 | 49-60 (n=3) | 43-64 (n=3) | 44-49 (n=3) | 0 | unresolved:overlap |
| rest:5 | 1-62 (n=3) | 1-47 (n=3) | 1 (n=3) | 0 | unresolved:overlap |
| rest:6 | 11-41 (n=3) | 15-59 (n=3) | 42-48 (n=3) | 0 | unresolved:overlap |

### Faithful, draw-only freeze: unfrozen busy samples against frozen samples, window by window (Lean busyFrozen; a rest window uses all unfrozen samples)

Layout:

| window | basis | unfrozen | frozen | cell |
|---|---|---|---|---|
| swap:0 | busy | 7-11 (n=3) | 10-12 (n=3) | overlap |
| swap:1 | busy | 8-13 (n=3) | 13-15 (n=3) | overlap |
| swap:2 | busy | 6-13 (n=3) | 10-14 (n=3) | overlap |
| swap:3 | busy | - | 11-15 (n=3) | noBusy |
| swap:4 | busy | 6-9 (n=3) | 9-15 (n=3) | overlap |
| swap:5 | busy | 3-14 (n=3) | 14-15 (n=3) | overlap |
| swap:6 | busy | - | 3-10 (n=3) | noBusy |
| swap:7 | busy | 9-11 (n=3) | 11-14 (n=3) | overlap |
| rest:0 | all | 5-47 (n=6) | 2-5 (n=3) | overlap |
| rest:1 | all | 43-50 (n=6) | 1-3 (n=3) | removed |
| rest:2 | all | 5-47 (n=6) | 1-5 (n=3) | overlap |
| rest:3 | all | 5-49 (n=6) | 2-5 (n=3) | overlap |
| rest:4 | all | 45-50 (n=6) | 1-3 (n=3) | removed |
| rest:5 | all | 4-49 (n=6) | 1-5 (n=3) | overlap |
| rest:6 | all | 5-45 (n=6) | 2-6 (n=3) | overlap |

Paint:

| window | basis | unfrozen | frozen | cell |
|---|---|---|---|---|
| swap:0 | busy | 15-27 (n=3) | 20-27 (n=3) | overlap |
| swap:1 | busy | 20-36 (n=3) | 30-33 (n=3) | overlap |
| swap:2 | busy | 28-40 (n=3) | 19-29 (n=3) | overlap |
| swap:3 | busy | - | 25-31 (n=3) | noBusy |
| swap:4 | busy | 15-25 (n=3) | 18-34 (n=3) | overlap |
| swap:5 | busy | 8-43 (n=3) | 29-31 (n=3) | overlap |
| swap:6 | busy | - | 4-24 (n=3) | noBusy |
| swap:7 | busy | 25-30 (n=3) | 23-34 (n=3) | overlap |
| rest:0 | all | 1-45 (n=6) | 1-2 (n=3) | overlap |
| rest:1 | all | 42-64 (n=6) | 1-16 (n=3) | removed |
| rest:2 | all | 1-61 (n=6) | 1 (n=3) | overlap |
| rest:3 | all | 8-61 (n=6) | 2-16 (n=3) | overlap |
| rest:4 | all | 43-64 (n=6) | 1-2 (n=3) | removed |
| rest:5 | all | 1-62 (n=6) | 1-15 (n=3) | overlap |
| rest:6 | all | 11-59 (n=6) | 1-2 (n=3) | removed |

### hero.exit zone (scroll-A): rows per capture and per scroll frame

aligned = the scroll starts inside a draw; natural = the scroll starts wherever the page is. Per frame = Lean perFrameMilli (rows over frames, thousandths, rounded half up).

| state | group | captures | frames | Layout median (min..max) | Layout per frame | Paint median (min..max) | Paint per frame | draw starts (animations / transitions) |
|---|---|---|---|---|---|---|---|---|
| faithful | all | 6 | 192 | 81.5 (56..85) | 2.385 | 169.5 (123..197) | 5.120 | 0 / 28 (6 captures) |
| faithful | aligned | 3 | 96 | 85 (85..85) | 2.656 | 172 (167..193) | 5.542 | 0 / 6 (3 captures) |
| faithful | natural | 3 | 96 | 69 (56..78) | 2.115 | 131 (123..197) | 4.698 | 0 / 22 (3 captures) |
| nolayout | all | 6 | 192 | 58 (51..65) | 1.807 | 162.5 (127..197) | 5.089 | 0 / 11 (6 captures) |
| nolayout | aligned | 3 | 96 | 57 (55..65) | 1.844 | 160 (138..190) | 5.083 | 0 / 6 (3 captures) |
| nolayout | natural | 3 | 96 | 59 (51..60) | 1.771 | 165 (127..197) | 5.094 | 0 / 5 (3 captures) |
| full | all | 6 | 192 | 55.5 (53..71) | 1.807 | 173.5 (121..188) | 5.224 | 0 / 0 (6 captures) |
| full | aligned | 3 | 96 | 54 (54..57) | 1.719 | 177 (163..188) | 5.500 | 0 / 0 (3 captures) |
| full | natural | 3 | 96 | 58 (53..71) | 1.896 | 170 (121..184) | 4.948 | 0 / 0 (3 captures) |
| faithful-frozen | all | 6 | 192 | 61 (53..78) | 1.990 | 144 (106..171) | 4.401 | 0 / 0 (6 captures) |
| faithful-frozen | aligned | 3 | 96 | 58 (53..78) | 1.969 | 159 (129..161) | 4.677 | 0 / 0 (3 captures) |
| faithful-frozen | natural | 3 | 96 | 63 (59..71) | 2.010 | 119 (106..171) | 4.125 | 0 / 0 (3 captures) |

Verdict = Lean zoneVerdict of the first state against the second (lower = the second is lower, ranges separated). Share = whole percent of the first median that the second removed.

| group | from | to | kind | n | verdict | share |
|---|---|---|---|---|---|---|
| all | faithful | nolayout | Layout | 6+6 | overlap | 28% |
| all | faithful | nolayout | Paint | 6+6 | overlap | 4% |
| all | faithful | full | Layout | 6+6 | overlap | 31% |
| all | faithful | full | Paint | 6+6 | overlap | -3% |
| all | nolayout | full | Layout | 6+6 | overlap | 4% |
| all | nolayout | full | Paint | 6+6 | overlap | -7% |
| all | faithful | faithful-frozen | Layout | 6+6 | overlap | 25% |
| all | faithful | faithful-frozen | Paint | 6+6 | overlap | 15% |
| aligned | faithful | nolayout | Layout | 3+3 | lower | 32% |
| aligned | faithful | nolayout | Paint | 3+3 | overlap | 6% |
| aligned | faithful | full | Layout | 3+3 | lower | 36% |
| aligned | faithful | full | Paint | 3+3 | overlap | -3% |
| aligned | nolayout | full | Layout | 3+3 | overlap | 5% |
| aligned | nolayout | full | Paint | 3+3 | overlap | -11% |
| aligned | faithful | faithful-frozen | Layout | 3+3 | lower | 31% |
| aligned | faithful | faithful-frozen | Paint | 3+3 | lower | 7% |
| natural | faithful | nolayout | Layout | 3+3 | overlap | 14% |
| natural | faithful | nolayout | Paint | 3+3 | overlap | -26% |
| natural | faithful | full | Layout | 3+3 | overlap | 15% |
| natural | faithful | full | Paint | 3+3 | overlap | -30% |
| natural | nolayout | full | Layout | 3+3 | overlap | 1% |
| natural | nolayout | full | Paint | 3+3 | overlap | -4% |
| natural | faithful | faithful-frozen | Layout | 3+3 | overlap | 8% |
| natural | faithful | faithful-frozen | Paint | 3+3 | overlap | 9% |
