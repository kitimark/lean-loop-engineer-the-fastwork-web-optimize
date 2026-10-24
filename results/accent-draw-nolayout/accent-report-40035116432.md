Sources: run 40035116432 commit a3bb8cd67 jobs r1 r2 r3

Jobs counted (3): 120693308041, 120693308091, 120696099405. Records: 3. Arms: faithful = the page without a flag; nolayout = hero.accent:draw-nolayout; full = hero.accent:draw-nolayout-full; faithful-frozen = the default page with the draw-only freeze (path animations and the drawingIn width transition off, idle boil running).

### Units per job

| job | captures run | failed | skipped |
|---|---|---|---|
| 120693308041/p1/lane | 13 | - | - |
| 120693308091/p1/lane | 13 | - | - |
| 120696099405/p1/lane | 13 | - | - |

### Pooled Layout rows (windows with at least 24 rows are busy; rows per capture and median over the pooled windows)

| state | window kind | captures | windows | busy windows | Layout rows per capture | median |
|---|---|---|---|---|---|---|
| faithful | rest | 6 | 42 | 27 of 42 | 223.7 | 45.5 |
| faithful | swap | 6 | 48 | 0 of 48 | 109.0 | 14 |
| nolayout | rest | 3 | 21 | 7 of 21 | 128.3 | 5 |
| nolayout | swap | 3 | 24 | 0 of 24 | 111.7 | 14 |
| full | rest | 3 | 21 | 0 of 21 | 21.7 | 3 |
| full | swap | 3 | 24 | 0 of 24 | 110.7 | 14 |
| faithful-frozen | rest | 3 | 21 | 0 of 21 | 22.0 | 3 |
| faithful-frozen | swap | 3 | 24 | 0 of 24 | 99.7 | 13.5 |

### nolayout against faithful, window by window (Lean cell: needs at least 3 samples in each faithful slot)

Tally of swap windows (win / loss / unresolved of 8 per kind): Layout 0/0/8, Paint 0/0/8, Composite 0/0/8, RecalculateStyles 0/0/8

Tally of rest windows (win / loss / unresolved of 7 per kind): Layout 0/0/7, Paint 0/0/7, Composite 0/0/7, RecalculateStyles 0/0/7

Layout:

| window | faithful a | faithful b (A/A floor) | nolayout | dropped | verdict |
|---|---|---|---|---|---|
| swap:0 | 9-15 (n=3) | 8-15 (n=3) | 13-16 (n=3) | 0 | unresolved:overlap |
| swap:1 | 10-14 (n=3) | 13-15 (n=3) | 14-16 (n=3) | 0 | unresolved:overlap |
| swap:2 | 14-16 (n=3) | 11-15 (n=3) | 13-16 (n=3) | 0 | unresolved:overlap |
| swap:3 | 10-14 (n=3) | 14-16 (n=3) | 6-16 (n=3) | 0 | unresolved:overlap |
| swap:4 | 10-15 (n=3) | 14-16 (n=3) | 13-14 (n=3) | 0 | unresolved:overlap |
| swap:5 | 14-15 (n=3) | 12-15 (n=3) | 13-15 (n=3) | 0 | unresolved:overlap |
| swap:6 | 13-14 (n=3) | 14-16 (n=3) | 14-16 (n=3) | 0 | unresolved:overlap |
| swap:7 | 12-16 (n=3) | 13-15 (n=3) | 13-15 (n=3) | 0 | unresolved:overlap |
| rest:0 | 5-50 (n=3) | 5-46 (n=3) | 3-49 (n=3) | 0 | unresolved:overlap |
| rest:1 | 5-49 (n=3) | 5-45 (n=3) | 3-46 (n=3) | 0 | unresolved:overlap |
| rest:2 | 5-49 (n=3) | 45-48 (n=3) | 3-48 (n=3) | 0 | unresolved:overlap |
| rest:3 | 5-47 (n=3) | 5-48 (n=3) | 2-50 (n=3) | 0 | unresolved:overlap |
| rest:4 | 5-48 (n=3) | 5-47 (n=3) | 3-45 (n=3) | 0 | unresolved:overlap |
| rest:5 | 5-47 (n=3) | 46-50 (n=3) | 3-48 (n=3) | 0 | unresolved:overlap |
| rest:6 | 5-47 (n=3) | 5-48 (n=3) | 1-46 (n=3) | 0 | unresolved:overlap |

Paint:

| window | faithful a | faithful b (A/A floor) | nolayout | dropped | verdict |
|---|---|---|---|---|---|
| swap:0 | 30-37 (n=3) | 20-55 (n=3) | 29-46 (n=3) | 0 | unresolved:overlap |
| swap:1 | 25-45 (n=3) | 28-38 (n=3) | 32-46 (n=3) | 0 | unresolved:overlap |
| swap:2 | 31-50 (n=3) | 31-47 (n=3) | 34-47 (n=3) | 0 | unresolved:overlap |
| swap:3 | 28-41 (n=3) | 29-48 (n=3) | 18-38 (n=3) | 0 | unresolved:overlap |
| swap:4 | 29-32 (n=3) | 30-39 (n=3) | 29-44 (n=3) | 0 | unresolved:overlap |
| swap:5 | 36-41 (n=3) | 32-44 (n=3) | 28-46 (n=3) | 0 | unresolved:overlap |
| swap:6 | 30-40 (n=3) | 30-49 (n=3) | 31-47 (n=3) | 0 | unresolved:overlap |
| swap:7 | 30-51 (n=3) | 31-34 (n=3) | 29-43 (n=3) | 0 | unresolved:overlap |
| rest:0 | 1-63 (n=3) | 15-60 (n=3) | 15-59 (n=3) | 0 | unresolved:overlap |
| rest:1 | 15-66 (n=3) | 15-59 (n=3) | 1-63 (n=3) | 0 | unresolved:overlap |
| rest:2 | 15-62 (n=3) | 57-65 (n=3) | 15-64 (n=3) | 0 | unresolved:overlap |
| rest:3 | 15-61 (n=3) | 15-64 (n=3) | 15-64 (n=3) | 0 | unresolved:overlap |
| rest:4 | 15-62 (n=3) | 15-58 (n=3) | 15-60 (n=3) | 0 | unresolved:overlap |
| rest:5 | 15-61 (n=3) | 50-59 (n=3) | 15-62 (n=3) | 0 | unresolved:overlap |
| rest:6 | 15-68 (n=3) | 1-62 (n=3) | 1-60 (n=3) | 0 | unresolved:overlap |


### full against faithful, window by window (Lean cell: needs at least 3 samples in each faithful slot)

Tally of swap windows (win / loss / unresolved of 8 per kind): Layout 0/0/8, Paint 0/0/8, Composite 0/0/8, RecalculateStyles 0/0/8

Tally of rest windows (win / loss / unresolved of 7 per kind): Layout 2/0/5, Paint 0/0/7, Composite 0/0/7, RecalculateStyles 0/0/7

Layout:

| window | faithful a | faithful b (A/A floor) | full | dropped | verdict |
|---|---|---|---|---|---|
| swap:0 | 9-15 (n=3) | 8-15 (n=3) | 12-15 (n=3) | 0 | unresolved:overlap |
| swap:1 | 10-14 (n=3) | 13-15 (n=3) | 13-14 (n=3) | 0 | unresolved:overlap |
| swap:2 | 14-16 (n=3) | 11-15 (n=3) | 12-14 (n=3) | 0 | unresolved:overlap |
| swap:3 | 10-14 (n=3) | 14-16 (n=3) | 12-15 (n=3) | 0 | unresolved:overlap |
| swap:4 | 10-15 (n=3) | 14-16 (n=3) | 14 (n=3) | 0 | unresolved:overlap |
| swap:5 | 14-15 (n=3) | 12-15 (n=3) | 14 (n=3) | 0 | unresolved:overlap |
| swap:6 | 13-14 (n=3) | 14-16 (n=3) | 14-15 (n=3) | 0 | unresolved:overlap |
| swap:7 | 12-16 (n=3) | 13-15 (n=3) | 13-14 (n=3) | 0 | unresolved:overlap |
| rest:0 | 5-50 (n=3) | 5-46 (n=3) | 3-5 (n=3) | 0 | unresolved:overlap |
| rest:1 | 5-49 (n=3) | 5-45 (n=3) | 1-3 (n=3) | 0 | win |
| rest:2 | 5-49 (n=3) | 45-48 (n=3) | 1-5 (n=3) | 0 | unresolved:overlap |
| rest:3 | 5-47 (n=3) | 5-48 (n=3) | 3-5 (n=3) | 0 | unresolved:overlap |
| rest:4 | 5-48 (n=3) | 5-47 (n=3) | 1-3 (n=3) | 0 | win |
| rest:5 | 5-47 (n=3) | 46-50 (n=3) | 1-5 (n=3) | 0 | unresolved:overlap |
| rest:6 | 5-47 (n=3) | 5-48 (n=3) | 2-5 (n=3) | 0 | unresolved:overlap |

Paint:

| window | faithful a | faithful b (A/A floor) | full | dropped | verdict |
|---|---|---|---|---|---|
| swap:0 | 30-37 (n=3) | 20-55 (n=3) | 26-40 (n=3) | 0 | unresolved:overlap |
| swap:1 | 25-45 (n=3) | 28-38 (n=3) | 34-44 (n=3) | 0 | unresolved:overlap |
| swap:2 | 31-50 (n=3) | 31-47 (n=3) | 39-46 (n=3) | 0 | unresolved:overlap |
| swap:3 | 28-41 (n=3) | 29-48 (n=3) | 26-39 (n=3) | 0 | unresolved:overlap |
| swap:4 | 29-32 (n=3) | 30-39 (n=3) | 33-41 (n=3) | 0 | unresolved:overlap |
| swap:5 | 36-41 (n=3) | 32-44 (n=3) | 34-46 (n=3) | 0 | unresolved:overlap |
| swap:6 | 30-40 (n=3) | 30-49 (n=3) | 35-37 (n=3) | 0 | unresolved:overlap |
| swap:7 | 30-51 (n=3) | 31-34 (n=3) | 32-41 (n=3) | 0 | unresolved:overlap |
| rest:0 | 1-63 (n=3) | 15-60 (n=3) | 15-45 (n=3) | 0 | unresolved:overlap |
| rest:1 | 15-66 (n=3) | 15-59 (n=3) | 49-57 (n=3) | 0 | unresolved:overlap |
| rest:2 | 15-62 (n=3) | 57-65 (n=3) | 15-63 (n=3) | 0 | unresolved:overlap |
| rest:3 | 15-61 (n=3) | 15-64 (n=3) | 1-59 (n=3) | 0 | unresolved:overlap |
| rest:4 | 15-62 (n=3) | 15-58 (n=3) | 46-62 (n=3) | 0 | unresolved:overlap |
| rest:5 | 15-61 (n=3) | 50-59 (n=3) | 15-63 (n=3) | 0 | unresolved:overlap |
| rest:6 | 15-68 (n=3) | 1-62 (n=3) | 1-57 (n=3) | 0 | unresolved:overlap |

### Faithful, draw-only freeze: unfrozen busy samples against frozen samples, window by window (Lean busyFrozen; a rest window uses all unfrozen samples)

Layout:

| window | basis | unfrozen | frozen | cell |
|---|---|---|---|---|
| swap:0 | busy | 9-14 (n=3) | 10-13 (n=3) | overlap |
| swap:1 | busy | 11 (n=1) | 9-14 (n=3) | overlap |
| swap:2 | busy | 11-16 (n=3) | 14 (n=3) | overlap |
| swap:3 | busy | 14-16 (n=2) | 13-16 (n=3) | overlap |
| swap:4 | busy | 10 (n=1) | 5-15 (n=3) | overlap |
| swap:5 | busy | 12-15 (n=3) | 9-16 (n=3) | overlap |
| swap:6 | busy | 13-16 (n=2) | 11-15 (n=3) | overlap |
| swap:7 | busy | 12-16 (n=3) | 7-15 (n=3) | overlap |
| rest:0 | all | 5-50 (n=6) | 3-5 (n=3) | overlap |
| rest:1 | all | 5-49 (n=6) | 1-3 (n=3) | removed |
| rest:2 | all | 5-49 (n=6) | 1-5 (n=3) | overlap |
| rest:3 | all | 5-48 (n=6) | 3-5 (n=3) | overlap |
| rest:4 | all | 5-48 (n=6) | 1-3 (n=3) | removed |
| rest:5 | all | 5-50 (n=6) | 1-5 (n=3) | overlap |
| rest:6 | all | 5-48 (n=6) | 2-6 (n=3) | overlap |

Paint:

| window | basis | unfrozen | frozen | cell |
|---|---|---|---|---|
| swap:0 | busy | 30-55 (n=3) | 25-26 (n=3) | removed |
| swap:1 | busy | 45 (n=1) | 22-29 (n=3) | removed |
| swap:2 | busy | 32-50 (n=3) | 31-34 (n=3) | overlap |
| swap:3 | busy | 41-48 (n=2) | 28-34 (n=3) | removed |
| swap:4 | busy | 29 (n=1) | 13-34 (n=3) | overlap |
| swap:5 | busy | 32-44 (n=3) | 17-35 (n=3) | overlap |
| swap:6 | busy | 40-49 (n=2) | 22-33 (n=3) | removed |
| swap:7 | busy | 30-51 (n=3) | 17-36 (n=3) | overlap |
| rest:0 | all | 1-63 (n=6) | 1-15 (n=3) | overlap |
| rest:1 | all | 15-66 (n=6) | 1-16 (n=3) | overlap |
| rest:2 | all | 15-65 (n=6) | 1-15 (n=3) | overlap |
| rest:3 | all | 15-64 (n=6) | 1-16 (n=3) | overlap |
| rest:4 | all | 15-62 (n=6) | 2-16 (n=3) | overlap |
| rest:5 | all | 15-61 (n=6) | 1-15 (n=3) | overlap |
| rest:6 | all | 1-68 (n=6) | 1-16 (n=3) | overlap |

### hero.exit zone (scroll-A): rows per capture and per scroll frame

aligned = the scroll starts inside a draw; natural = the scroll starts wherever the page is. Per frame = Lean perFrameMilli (rows over frames, thousandths, rounded half up).

| state | group | captures | frames | Layout median (min..max) | Layout per frame | Paint median (min..max) | Paint per frame | draw starts (animations / transitions) |
|---|---|---|---|---|---|---|---|---|
| faithful | all | 6 | 192 | 79 (72..83) | 2.443 | 163 (144..187) | 5.078 | 66 / 10 (6 captures) |
| faithful | aligned | 3 | 96 | 76 (74..82) | 2.417 | 167 (144..187) | 5.188 | 45 / 7 (3 captures) |
| faithful | natural | 3 | 96 | 82 (72..83) | 2.469 | 163 (151..163) | 4.969 | 21 / 3 (3 captures) |
| nolayout | all | 6 | 192 | 54.5 (51..66) | 1.771 | 162.5 (150..184) | 5.099 | 19 / 9 (6 captures) |
| nolayout | aligned | 3 | 96 | 52 (51..56) | 1.656 | 164 (150..166) | 5.000 | 10 / 5 (3 captures) |
| nolayout | natural | 3 | 96 | 62 (53..66) | 1.885 | 161 (154..184) | 5.198 | 9 / 4 (3 captures) |
| full | all | 6 | 192 | 56.5 (50..65) | 1.781 | 174 (115..207) | 5.161 | 96 / 0 (6 captures) |
| full | aligned | 3 | 96 | 54 (53..59) | 1.729 | 185 (181..207) | 5.969 | 25 / 0 (3 captures) |
| full | natural | 3 | 96 | 61 (50..65) | 1.833 | 136 (115..167) | 4.354 | 71 / 0 (3 captures) |
| faithful-frozen | all | 6 | 192 | 59.5 (54..68) | 1.911 | 123.5 (110..166) | 4.094 | 0 / 0 (6 captures) |
| faithful-frozen | aligned | 3 | 96 | 59 (54..67) | 1.875 | 118 (110..129) | 3.719 | 0 / 0 (3 captures) |
| faithful-frozen | natural | 3 | 96 | 60 (59..68) | 1.948 | 147 (116..166) | 4.469 | 0 / 0 (3 captures) |

Verdict = Lean zoneVerdict of the first state against the second (lower = the second is lower, ranges separated). Share = whole percent of the first median that the second removed.

| group | from | to | kind | n | verdict | share |
|---|---|---|---|---|---|---|
| all | faithful | nolayout | Layout | 6+6 | lower | 31% |
| all | faithful | nolayout | Paint | 6+6 | overlap | 0% |
| all | faithful | full | Layout | 6+6 | lower | 28% |
| all | faithful | full | Paint | 6+6 | overlap | -7% |
| all | nolayout | full | Layout | 6+6 | overlap | -4% |
| all | nolayout | full | Paint | 6+6 | overlap | -8% |
| all | faithful | faithful-frozen | Layout | 6+6 | lower | 24% |
| all | faithful | faithful-frozen | Paint | 6+6 | overlap | 24% |
| aligned | faithful | nolayout | Layout | 3+3 | lower | 31% |
| aligned | faithful | nolayout | Paint | 3+3 | overlap | 1% |
| aligned | faithful | full | Layout | 3+3 | lower | 28% |
| aligned | faithful | full | Paint | 3+3 | overlap | -11% |
| aligned | nolayout | full | Layout | 3+3 | overlap | -4% |
| aligned | nolayout | full | Paint | 3+3 | higher | -13% |
| aligned | faithful | faithful-frozen | Layout | 3+3 | lower | 22% |
| aligned | faithful | faithful-frozen | Paint | 3+3 | lower | 29% |
| natural | faithful | nolayout | Layout | 3+3 | lower | 24% |
| natural | faithful | nolayout | Paint | 3+3 | overlap | 1% |
| natural | faithful | full | Layout | 3+3 | lower | 25% |
| natural | faithful | full | Paint | 3+3 | overlap | 16% |
| natural | nolayout | full | Layout | 3+3 | overlap | 1% |
| natural | nolayout | full | Paint | 3+3 | overlap | 15% |
| natural | faithful | faithful-frozen | Layout | 3+3 | lower | 26% |
| natural | faithful | faithful-frozen | Paint | 3+3 | overlap | 9% |
