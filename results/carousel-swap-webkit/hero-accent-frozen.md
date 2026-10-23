Sources: run 40006432997 jobs 120597721629 (r1), 120597721732 (r2), 120603368909 (r3), commit f2dec2e2b, 1 pass each

Jobs counted (3): 120597721629, 120597721732, 120603368909. Passes: 3 unfrozen, 3 frozen. Background of a window: busy = both rest windows next to it have at least 24 Layout rows (i idle, m mixed, b busy, u unknown).

### crop: Layout rows per swap window, frozen against unfrozen

Idle level (largest unfrozen idle-background Layout count of this arm, all windows): 9 (6 samples). Cell = Lean frozenCell: atIdle when twice the frozen median is not above twice that level.

| window | frozen n | frozen median | frozen bg | unfrozen median | unfrozen busy median | unfrozen idle max | frozen Paint median | unfrozen Paint median | cell |
|---|---|---|---|---|---|---|---|---|---|
| swap:0 | 6 | 3 | 6i 0m 0b 0u | 6 | 4 | 9 | 7 | 11.5 | atIdle |
| swap:1 | 6 | 2 | 6i 0m 0b 0u | 9 | 15 | - | 8 | 13 | atIdle |
| swap:2 | 6 | 3 | 6i 0m 0b 0u | 9.5 | 14 | - | 7 | 16 | atIdle |
| swap:3 | 6 | 3 | 6i 0m 0b 0u | 6 | - | - | 7 | 10.5 | atIdle |
| swap:4 | 6 | 2.5 | 6i 0m 0b 0u | 8.5 | 15 | - | 7 | 14 | atIdle |
| swap:5 | 6 | 3 | 6i 0m 0b 0u | 9 | 14 | - | 7.5 | 15 | atIdle |
| swap:6 | 6 | 3 | 6i 0m 0b 0u | 4.5 | - | - | 7 | 10.5 | atIdle |
| swap:7 | 6 | 2 | 6i 0m 0b 0u | 9 | 15 | 3 | 6 | 14 | atIdle |

Rest windows (Layout rows, all of rest:0..6): frozen n=42 max 2 median 1; unfrozen n=42 max 50 median 47.

### faithful: Layout rows per swap window, frozen against unfrozen

Idle level (largest unfrozen idle-background Layout count of this arm, all windows): 16 (6 samples). Cell = Lean frozenCell: atIdle when twice the frozen median is not above twice that level.

| window | frozen n | frozen median | frozen bg | unfrozen median | unfrozen busy median | unfrozen idle max | frozen Paint median | unfrozen Paint median | cell |
|---|---|---|---|---|---|---|---|---|---|
| swap:0 | 6 | 12.5 | 6i 0m 0b 0u | 12.5 | 11 | 16 | 31 | 32 | atIdle |
| swap:1 | 6 | 14 | 6i 0m 0b 0u | 14 | 13 | - | 31 | 35 | atIdle |
| swap:2 | 6 | 14.5 | 6i 0m 0b 0u | 15 | 15 | - | 31.5 | 37 | atIdle |
| swap:3 | 6 | 15 | 6i 0m 0b 0u | 14 | 12 | - | 35.5 | 34.5 | atIdle |
| swap:4 | 6 | 13 | 6i 0m 0b 0u | 13.5 | 12 | - | 30.5 | 32 | atIdle |
| swap:5 | 6 | 14.5 | 6i 0m 0b 0u | 12 | 16 | - | 33 | 28.5 | atIdle |
| swap:6 | 6 | 14.5 | 6i 0m 0b 0u | 11.5 | 11 | - | 32 | 30.5 | atIdle |
| swap:7 | 6 | 12.5 | 6i 0m 0b 0u | 12.5 | 12 | 14 | 30.5 | 32 | atIdle |

Rest windows (Layout rows, all of rest:0..6): frozen n=42 max 2 median 1; unfrozen n=42 max 51 median 42.

### Diagnostic captures (7 s, 100 ms buckets): long busy runs = runs of at least 5 buckets with at least 4 Layout rows (Lean longRuns)

| state | arm | job/pass/slot | Layout rows | long busy runs | max per bucket | hero-accent writes | hero-accent animations before / after |
|---|---|---|---|---|---|---|---|
| free | crop | 120597721629/p1/diag | 297 | 3 | 7 | 46 | 3 / 4 |
| free | faithful | 120597721629/p1/diag | 337 | 3 | 8 | 33 | 4 / 3 |
| free | crop | 120597721732/p1/diag | 253 | 2 | 7 | 32 | 3 / 3 |
| free | faithful | 120597721732/p1/diag | 289 | 3 | 7 | 33 | 3 / 3 |
| free | crop | 120603368909/p1/diag | 264 | 2 | 7 | 33 | 4 / 3 |
| free | faithful | 120603368909/p1/diag | 298 | 2 | 7 | 32 | 3 / 3 |
| frozen | crop | 120597721629/p1/diag | 30 | 0 | 3 | 46 | 0 / 0 |
| frozen | faithful | 120597721629/p1/diag | 112 | 0 | 7 | 46 | 0 / 0 |
| frozen | crop | 120597721732/p1/diag | 30 | 0 | 3 | 33 | 0 / 0 |
| frozen | faithful | 120597721732/p1/diag | 85 | 0 | 7 | 33 | 0 / 0 |
| frozen | crop | 120603368909/p1/diag | 30 | 0 | 3 | 33 | 0 / 0 |
| frozen | faithful | 120603368909/p1/diag | 86 | 0 | 8 | 46 | 0 / 0 |

### hero.exit zone (scroll-A), crop arm: Layout and Paint rows per capture, frozen against unfrozen

Share = whole percent of the unfrozen median that the freeze removed (Lean sharePct on twice the medians). Verdict = Lean verdict of the unfrozen against the frozen samples (lower = frozen is lower, ranges separated).

| group | kind | unfrozen n | unfrozen median (min..max) | frozen n | frozen median (min..max) | verdict | share |
|---|---|---|---|---|---|---|---|
| all | Layout | 6 | 76.5 (51..79) | 6 | 53.5 (43..61) | overlap | 30% |
| all | Paint | 6 | 164 (120..179) | 6 | 115 (109..165) | overlap | 29% |
| aligned (scroll starts in a draw) | Layout | 3 | 78 (77..79) | 3 | 50 (43..54) | lower | 35% |
| aligned (scroll starts in a draw) | Paint | 3 | 176 (172..179) | 3 | 113 (111..136) | lower | 35% |
| natural (start unaligned) | Layout | 3 | 65 (51..76) | 3 | 60 (53..61) | overlap | 7% |
| natural (start unaligned) | Paint | 3 | 150 (120..156) | 3 | 117 (109..165) | overlap | 22% |

Zone captures (every sample):

| state | job/pass/slot | Layout | Paint | accent at start | class changes |
|---|---|---|---|---|---|
| free | 120597721629/p1/aligned | 77 | 176 | out | 1 |
| free | 120597721629/p1/natural | 51 | 120 | idle | 1 |
| free | 120597721732/p1/aligned | 78 | 179 | out | 1 |
| free | 120597721732/p1/natural | 76 | 150 | in | 1 |
| free | 120603368909/p1/aligned | 79 | 172 | out | 1 |
| free | 120603368909/p1/natural | 65 | 156 | idle | 2 |
| frozen | 120597721629/p1/natural | 61 | 117 | idle | 1 |
| frozen | 120597721629/p1/aligned | 43 | 113 | out | 0 |
| frozen | 120597721732/p1/natural | 60 | 165 | out | 2 |
| frozen | 120597721732/p1/aligned | 54 | 136 | out | 1 |
| frozen | 120603368909/p1/natural | 53 | 109 | in | 1 |
| frozen | 120603368909/p1/aligned | 50 | 111 | out | 1 |
