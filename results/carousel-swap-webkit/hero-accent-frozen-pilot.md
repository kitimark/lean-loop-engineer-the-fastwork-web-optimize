Sources: run 39996415429 job r3 only (job 120580412344, commit 9997926ab, 2 passes);  a pilot, not pooled with the final run

Jobs counted (1): 120580412344. Passes: 2 unfrozen, 2 frozen. Background of a window: busy = both rest windows next to it have at least 24 Layout rows (i idle, m mixed, b busy, u unknown).

### crop: Layout rows per swap window, frozen against unfrozen

Idle level (largest unfrozen idle-background Layout count of this arm, all windows): 9 (2 samples). Cell = Lean frozenCell: atIdle when twice the frozen median is not above twice that level.

| window | frozen n | frozen median | frozen bg | unfrozen median | unfrozen busy median | unfrozen idle max | frozen Paint median | unfrozen Paint median | cell |
|---|---|---|---|---|---|---|---|---|---|
| swap:0 | 4 | 2.5 | 4i 0m 0b 0u | 6 | 3 | 9 | 8.5 | 10.5 | atIdle |
| swap:1 | 4 | 3 | 4i 0m 0b 0u | 9 | 15 | - | 6.5 | 14 | atIdle |
| swap:2 | 4 | 2.5 | 4i 0m 0b 0u | 8 | 15 | - | 6 | 15 | atIdle |
| swap:3 | 4 | 2.5 | 4i 0m 0b 0u | 5 | 15 | - | 7 | 10.5 | atIdle |
| swap:4 | 4 | 2.5 | 4i 0m 0b 0u | 8.5 | 14 | - | 6.5 | 13.5 | atIdle |
| swap:5 | 4 | 2 | 4i 0m 0b 0u | 10 | 15 | - | 6.5 | 14.5 | atIdle |
| swap:6 | 4 | 2.5 | 4i 0m 0b 0u | 4.5 | 15 | - | 8 | 9 | atIdle |
| swap:7 | 4 | 3 | 4i 0m 0b 0u | 8.5 | 13 | 3 | 7.5 | 13.5 | atIdle |

Rest windows (Layout rows, all of rest:0..6): frozen n=28 max 3 median 1.5; unfrozen n=28 max 50 median 44.5.

### faithful: Layout rows per swap window, frozen against unfrozen

Idle level (largest unfrozen idle-background Layout count of this arm, all windows): 16 (4 samples). Cell = Lean frozenCell: atIdle when twice the frozen median is not above twice that level.

| window | frozen n | frozen median | frozen bg | unfrozen median | unfrozen busy median | unfrozen idle max | frozen Paint median | unfrozen Paint median | cell |
|---|---|---|---|---|---|---|---|---|---|
| swap:0 | 4 | 14.5 | 4i 0m 0b 0u | 13 | 11 | 16 | 31 | 32 | atIdle |
| swap:1 | 4 | 12 | 4i 0m 0b 0u | 12.5 | 12.5 | - | 28.5 | 34.5 | atIdle |
| swap:2 | 4 | 15 | 4i 0m 0b 0u | 15.5 | 16 | - | 32.5 | 39.5 | atIdle |
| swap:3 | 4 | 14.5 | 4i 0m 0b 0u | 13.5 | - | - | 33.5 | 31.5 | atIdle |
| swap:4 | 4 | 14.5 | 4i 0m 0b 0u | 13 | 12.5 | - | 33.5 | 32.5 | atIdle |
| swap:5 | 4 | 14 | 4i 0m 0b 0u | 13 | 14.5 | - | 30 | 36 | atIdle |
| swap:6 | 4 | 13 | 4i 0m 0b 0u | 11 | - | - | 28.5 | 28 | atIdle |
| swap:7 | 4 | 14 | 4i 0m 0b 0u | 11.5 | 13.5 | 11 | 32 | 37.5 | atIdle |

Rest windows (Layout rows, all of rest:0..6): frozen n=28 max 2 median 1.5; unfrozen n=28 max 51 median 44.5.

### Diagnostic captures (7 s, 100 ms buckets): long busy runs = runs of at least 5 buckets with at least 4 Layout rows (Lean longRuns)

| state | arm | job/pass/slot | Layout rows | long busy runs | max per bucket | hero-accent writes | hero-accent animations before / after |
|---|---|---|---|---|---|---|---|
| free | crop | 120580412344/p1/diag | 280 | 3 | 8 | 33 | 4 / 3 |
| free | faithful | 120580412344/p1/diag | 320 | 3 | 8 | 33 | 4 / 3 |
| frozen | crop | 120580412344/p1/diag | 30 | 0 | 3 | 33 | 0 / 0 |
| frozen | faithful | 120580412344/p1/diag | 103 | 0 | 7 | 33 | 0 / 0 |

### hero.exit zone (scroll-A), crop arm: Layout and Paint rows per capture, frozen against unfrozen

Share = whole percent of the unfrozen median that the freeze removed (Lean sharePct on twice the medians). Verdict = Lean verdict of the unfrozen against the frozen samples (lower = frozen is lower, ranges separated).

| group | kind | unfrozen n | unfrozen median (min..max) | frozen n | frozen median (min..max) | verdict | share |
|---|---|---|---|---|---|---|---|
| all | Layout | 4 | 75 (72..80) | 4 | 50.5 (47..54) | lower | 32% |
| all | Paint | 4 | 146.5 (139..168) | 4 | 117.5 (116..124) | lower | 19% |
| aligned (scroll starts in a draw) | Layout | 2 | 74.5 (72..77) | 2 | 51.5 (49..54) | lower | 30% |
| aligned (scroll starts in a draw) | Paint | 2 | 155.5 (143..168) | 2 | 120 (116..124) | lower | 22% |
| natural (start unaligned) | Layout | 2 | 76.5 (73..80) | 2 | 49.5 (47..52) | lower | 35% |
| natural (start unaligned) | Paint | 2 | 144.5 (139..150) | 2 | 117.5 (117..118) | lower | 18% |

Zone captures (every sample):

| state | job/pass/slot | Layout | Paint | accent at start | class changes |
|---|---|---|---|---|---|
| free | 120580412344/p1/aligned | 72 | 143 | out | 0 |
| free | 120580412344/p1/natural | 73 | 139 | out | 1 |
| free | 120580412344/p2/aligned | 77 | 168 | out | 2 |
| free | 120580412344/p2/natural | 80 | 150 | idle | 2 |
| frozen | 120580412344/p1/natural | 47 | 117 | out | 1 |
| frozen | 120580412344/p1/aligned | 49 | 116 | out | 1 |
| frozen | 120580412344/p2/natural | 52 | 118 | idle | 2 |
| frozen | 120580412344/p2/aligned | 54 | 124 | out | 1 |
