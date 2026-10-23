Sources: webkit-sim run 39983630584 at 3bfca9339 on ci/carousel-swap-followups, jobs r1 r2 r3, 2 passes each

Model (INFERRED from the Lean part model): a faithful swap shows 13 Layout frames at 60 Hz, the crop none.
Measured (the crop, Layout rows in a swap window, 96 samples): minimum 2, median 5.5; idle background only (13 samples): minimum 3, median 4.
Jobs counted (3): 39983630584.1/r1, 39983630584.1/r2, 39983630584.1/r3. Cells need at least 3 samples in each faithful slot (unresolved:fewSamples otherwise).

### Layout

| window | faithful a | faithful b (A/A floor) | crop | dropped | verdict |
|---|---|---|---|---|---|
| swap:0 | 12-16 (n=6) | 13-16 (n=6) | 3-14 (n=12) | 0 | unresolved:overlap |
| swap:1 | 15-16 (n=6) | 11-15 (n=6) | 3-16 (n=12) | 0 | unresolved:overlap |
| swap:2 | 14-15 (n=6) | 9-16 (n=6) | 3-15 (n=12) | 0 | unresolved:overlap |
| swap:3 | 10-16 (n=6) | 11-16 (n=6) | 4-15 (n=12) | 0 | unresolved:overlap |
| swap:4 | 10-15 (n=6) | 10-16 (n=6) | 2-16 (n=12) | 0 | unresolved:overlap |
| swap:5 | 13-16 (n=6) | 12-16 (n=6) | 2-16 (n=12) | 0 | unresolved:overlap |
| swap:6 | 11-15 (n=6) | 13-16 (n=6) | 3-15 (n=12) | 0 | unresolved:overlap |
| swap:7 | 6-16 (n=6) | 7-16 (n=6) | 3-15 (n=12) | 0 | unresolved:overlap |
| rest:0 | 5-49 (n=6) | 5-47 (n=6) | 5-50 (n=12) | 0 | unresolved:overlap |
| rest:1 | 5-49 (n=6) | 5-50 (n=6) | 4-49 (n=12) | 0 | unresolved:overlap |
| rest:2 | 5-49 (n=6) | 5-49 (n=6) | 5-50 (n=12) | 0 | unresolved:overlap |
| rest:3 | 5-49 (n=6) | 5-49 (n=6) | 5-49 (n=12) | 0 | unresolved:overlap |
| rest:4 | 5-49 (n=6) | 6-48 (n=6) | 5-50 (n=12) | 0 | unresolved:overlap |
| rest:5 | 5-49 (n=6) | 6-50 (n=6) | 5-50 (n=12) | 0 | unresolved:overlap |
| rest:6 | 5-50 (n=6) | 5-49 (n=6) | 4-50 (n=12) | 0 | unresolved:overlap |

### Paint

| window | faithful a | faithful b (A/A floor) | crop | dropped | verdict |
|---|---|---|---|---|---|
| swap:0 | 34-62 (n=6) | 30-44 (n=6) | 6-69 (n=12) | 0 | unresolved:overlap |
| swap:1 | 32-48 (n=6) | 30-44 (n=6) | 6-22 (n=12) | 0 | win |
| swap:2 | 32-46 (n=6) | 28-48 (n=6) | 6-22 (n=12) | 0 | win |
| swap:3 | 24-48 (n=6) | 25-48 (n=6) | 8-22 (n=12) | 0 | win |
| swap:4 | 23-48 (n=6) | 23-49 (n=6) | 6-22 (n=12) | 0 | win |
| swap:5 | 30-48 (n=6) | 31-49 (n=6) | 6-21 (n=12) | 0 | win |
| swap:6 | 22-48 (n=6) | 31-41 (n=6) | 6-21 (n=12) | 0 | win |
| swap:7 | 15-50 (n=6) | 16-48 (n=6) | 6-22 (n=12) | 0 | unresolved:overlap |
| rest:0 | 15-62 (n=6) | 1-62 (n=6) | 1-66 (n=12) | 0 | unresolved:overlap |
| rest:1 | 1-58 (n=6) | 15-67 (n=6) | 1-51 (n=12) | 0 | unresolved:overlap |
| rest:2 | 1-65 (n=6) | 15-66 (n=6) | 1-52 (n=12) | 0 | unresolved:overlap |
| rest:3 | 15-51 (n=6) | 1-59 (n=6) | 1-52 (n=12) | 0 | unresolved:overlap |
| rest:4 | 1-63 (n=6) | 1-62 (n=6) | 1-49 (n=12) | 0 | unresolved:overlap |
| rest:5 | 15-63 (n=6) | 15-63 (n=6) | 1-50 (n=12) | 0 | unresolved:overlap |
| rest:6 | 1-63 (n=6) | 15-61 (n=6) | 1-50 (n=12) | 0 | unresolved:overlap |

### Composite

| window | faithful a | faithful b (A/A floor) | crop | dropped | verdict |
|---|---|---|---|---|---|
| swap:0 | 10-14 (n=6) | 12-14 (n=6) | 5-13 (n=12) | 0 | unresolved:overlap |
| swap:1 | 13-14 (n=6) | 9-14 (n=6) | 5-14 (n=12) | 0 | unresolved:overlap |
| swap:2 | 13 (n=6) | 7-14 (n=6) | 5-14 (n=12) | 0 | unresolved:overlap |
| swap:3 | 8-14 (n=6) | 9-14 (n=6) | 5-14 (n=12) | 0 | unresolved:overlap |
| swap:4 | 10-13 (n=6) | 9-14 (n=6) | 4-14 (n=12) | 0 | unresolved:overlap |
| swap:5 | 11-14 (n=6) | 10-14 (n=6) | 5-14 (n=12) | 0 | unresolved:overlap |
| swap:6 | 10-13 (n=6) | 13-14 (n=6) | 2-14 (n=12) | 0 | unresolved:overlap |
| swap:7 | 6-14 (n=6) | 6-14 (n=6) | 5-14 (n=12) | 0 | unresolved:overlap |
| rest:0 | 17-48 (n=6) | 18-47 (n=6) | 13-49 (n=12) | 0 | unresolved:overlap |
| rest:1 | 13-48 (n=6) | 17-49 (n=6) | 16-49 (n=12) | 0 | unresolved:overlap |
| rest:2 | 16-49 (n=6) | 14-48 (n=6) | 13-49 (n=12) | 0 | unresolved:overlap |
| rest:3 | 14-48 (n=6) | 14-48 (n=6) | 13-49 (n=12) | 0 | unresolved:overlap |
| rest:4 | 16-48 (n=6) | 17-48 (n=6) | 12-49 (n=12) | 0 | unresolved:overlap |
| rest:5 | 13-49 (n=6) | 14-49 (n=6) | 13-49 (n=12) | 0 | unresolved:overlap |
| rest:6 | 16-48 (n=6) | 12-48 (n=6) | 3-49 (n=12) | 0 | unresolved:overlap |

### RecalculateStyles

| window | faithful a | faithful b (A/A floor) | crop | dropped | verdict |
|---|---|---|---|---|---|
| swap:0 | 12-16 (n=6) | 13-16 (n=6) | 5-15 (n=12) | 0 | unresolved:overlap |
| swap:1 | 15-16 (n=6) | 11-15 (n=6) | 5-16 (n=12) | 0 | unresolved:overlap |
| swap:2 | 14-15 (n=6) | 9-16 (n=6) | 5-16 (n=12) | 0 | unresolved:overlap |
| swap:3 | 10-16 (n=6) | 11-16 (n=6) | 5-16 (n=12) | 0 | unresolved:overlap |
| swap:4 | 11-15 (n=6) | 10-16 (n=6) | 4-16 (n=12) | 0 | unresolved:overlap |
| swap:5 | 13-16 (n=6) | 12-16 (n=6) | 5-16 (n=12) | 0 | unresolved:overlap |
| swap:6 | 11-15 (n=6) | 14-16 (n=6) | 4-15 (n=12) | 0 | unresolved:overlap |
| swap:7 | 7-16 (n=6) | 7-16 (n=6) | 5-16 (n=12) | 0 | unresolved:overlap |
| rest:0 | 11-49 (n=6) | 13-48 (n=6) | 10-50 (n=12) | 0 | unresolved:overlap |
| rest:1 | 10-49 (n=6) | 13-50 (n=6) | 11-50 (n=12) | 0 | unresolved:overlap |
| rest:2 | 12-50 (n=6) | 9-49 (n=6) | 10-51 (n=12) | 0 | unresolved:overlap |
| rest:3 | 10-49 (n=6) | 10-49 (n=6) | 10-50 (n=12) | 0 | unresolved:overlap |
| rest:4 | 12-49 (n=6) | 13-49 (n=6) | 9-51 (n=12) | 0 | unresolved:overlap |
| rest:5 | 9-50 (n=6) | 10-50 (n=6) | 10-51 (n=12) | 0 | unresolved:overlap |
| rest:6 | 12-50 (n=6) | 9-50 (n=6) | 4-51 (n=12) | 0 | unresolved:overlap |

Swap windows decided one by one (win / loss / unresolved of 8 per kind):

| kind | win | loss | unresolved |
|---|---|---|---|
| Layout | 0 | 0 | 8 |
| Paint | 6 | 0 | 2 |
| Composite | 0 | 0 | 8 |
| RecalculateStyles | 0 | 0 | 8 |

### Background of each swap window in the crop captures

| window | busy | idle | mixed | unknown |
|---|---|---|---|---|
| swap:0 | 6 | 6 | 0 | 0 |
| swap:1 | 2 | 0 | 10 | 0 |
| swap:2 | 6 | 0 | 6 | 0 |
| swap:3 | 4 | 0 | 8 | 0 |
| swap:4 | 2 | 0 | 10 | 0 |
| swap:5 | 6 | 0 | 6 | 0 |
| swap:6 | 3 | 0 | 9 | 0 |
| swap:7 | 5 | 7 | 0 | 0 |

### Layout rows of a swap window by background (rest windows next to it: busy = at least 24 Layout rows)

| window | crop idle | crop busy | crop mixed | faithful idle | faithful busy |
|---|---|---|---|---|---|
| swap:0 | 6.5 (n=6) | 11.5 (n=6) | - | 15 (n=6) | 14.5 (n=6) |
| swap:1 | - | 15 (n=2) | 4 (n=10) | - | 13.5 (n=2) |
| swap:2 | - | 14 (n=6) | 3.5 (n=6) | - | 15 (n=6) |
| swap:3 | - | 14 (n=4) | 6 (n=8) | - | 15.5 (n=4) |
| swap:4 | - | 15 (n=2) | 3.5 (n=10) | - | 14 (n=2) |
| swap:5 | - | 15 (n=6) | 3 (n=6) | - | 15.5 (n=6) |
| swap:6 | - | 15 (n=3) | 4 (n=9) | - | 15 (n=4) |
| swap:7 | 3 (n=7) | 12 (n=5) | - | 14 (n=6) | 16 (n=6) |

### Paint rows of a swap window by background (rest windows next to it: busy = at least 24 Layout rows)

| window | crop idle | crop busy | crop mixed | faithful idle | faithful busy |
|---|---|---|---|---|---|
| swap:0 | 13 (n=6) | 34 (n=6) | - | 37.5 (n=6) | 45.5 (n=6) |
| swap:1 | - | 21.5 (n=2) | 8 (n=10) | - | 46 (n=2) |
| swap:2 | - | 21 (n=6) | 8 (n=6) | - | 45 (n=6) |
| swap:3 | - | 21 (n=4) | 12 (n=8) | - | 46 (n=4) |
| swap:4 | - | 21.5 (n=2) | 8.5 (n=10) | - | 48.5 (n=2) |
| swap:5 | - | 21 (n=6) | 8 (n=6) | - | 46.5 (n=6) |
| swap:6 | - | 21 (n=3) | 10 (n=9) | - | 45.5 (n=4) |
| swap:7 | 8 (n=7) | 19 (n=5) | - | 31.5 (n=6) | 36.5 (n=6) |

### Cells on idle-background samples only (each window and kind decided on its own)

| window | Layout | Paint |
|---|---|---|
| swap:0 | unresolved:fewSamples (faithful n=2+4, crop n=6) | unresolved:fewSamples |
| swap:1 | unresolved:noSamples (faithful n=0+0, crop n=0) | unresolved:noSamples |
| swap:2 | unresolved:noSamples (faithful n=0+0, crop n=0) | unresolved:noSamples |
| swap:3 | unresolved:noSamples (faithful n=0+0, crop n=0) | unresolved:noSamples |
| swap:4 | unresolved:noSamples (faithful n=0+0, crop n=0) | unresolved:noSamples |
| swap:5 | unresolved:noSamples (faithful n=0+0, crop n=0) | unresolved:noSamples |
| swap:6 | unresolved:noSamples (faithful n=0+0, crop n=0) | unresolved:noSamples |
| swap:7 | unresolved:fewSamples (faithful n=2+4, crop n=7) | unresolved:fewSamples |

### Cells on busy-background samples only (each window and kind decided on its own)

| window | Layout | Paint |
|---|---|---|
| swap:0 | unresolved:fewSamples (faithful n=4+2, crop n=6) | unresolved:fewSamples |
| swap:1 | unresolved:fewSamples (faithful n=1+1, crop n=2) | unresolved:fewSamples |
| swap:2 | unresolved:fewSamples (faithful n=2+4, crop n=6) | unresolved:fewSamples |
| swap:3 | unresolved:fewSamples (faithful n=3+1, crop n=4) | unresolved:fewSamples |
| swap:4 | unresolved:fewSamples (faithful n=1+1, crop n=2) | unresolved:fewSamples |
| swap:5 | unresolved:fewSamples (faithful n=2+4, crop n=6) | unresolved:fewSamples |
| swap:6 | unresolved:fewSamples (faithful n=3+1, crop n=3) | unresolved:fewSamples |
| swap:7 | unresolved:fewSamples (faithful n=4+2, crop n=5) | unresolved:fewSamples |

### Diagnostic captures (crop arm, no swap marks, 100 ms buckets)

Job 39983630584.1/r1/p1: 70 buckets; scale 1-9 of the bucket maximum (Layout max 7), '.' = 0

```
Layout    9977888888878.3.2.2.2.4.3988888898988888889422.2.2.223.688888889898888
Paint     8995422222272.1.......3.12222222422223222241.1......21.122222224222222
hero-acce ...9..............................9.............................9.....  hero-accent:aria-label (total 3)
hero-acce ...9........9............9........9........9...........9........9.....  hero-accent:class (total 7)
hero-acce ...9..............................9.............................9.....  hero-accent:d (total 9)
hero-acce ...9..............................9.............................9.....  hero-accent:style (total 18)
hero-acce ...9..............................9.............................9.....  hero-accent:viewBox (total 9)
people-ca .9.9.......9..9.......9.9.......9.9.......9.9.......9..9.......9.9....  people-carousel:childList (total 126)
people-ca .9.8.......9..8.......9.8.......9.8.......9.8.......9..8.......9.8....  people-carousel:src (total 63)
```

Running animations (owner | name | kind | state | duration ms | iterations | properties), count before / after:

- commission-card|commission-module_three-frame-one_-3Rext|CSSAnimation|paused|600|Infinity|opacity: 1 / 1
- commission-card|commission-module_three-frame-two_rO-IC0|CSSAnimation|paused|600|Infinity|opacity: 1 / 1
- commission-card|commission-module_three-frame-zero_NB28ic|CSSAnimation|paused|600|Infinity|opacity: 1 / 1
- hero-accent|accent-module_strokeIn_yhJt8D|CSSAnimation|running|900|1|strokeDashoffset: 0 / 3
- hero-accent|accent-module_strokeOut_SDdGZt|CSSAnimation|running|900|1|strokeDashoffset: 3 / 0
- hero-accent|width|CSSTransition|running|900|1|width: 0 / 1
- hero-cue|cue-module_copyIn_j26lO8|CSSAnimation|finished|700|1|: 1 / 1
- hero-cue|cue-module_scrollFloat_6RFPnC|CSSAnimation|running|2200|Infinity|transform: 1 / 1
- nav-earn|nav-module_earn-sheen_BJihYd|CSSAnimation|finished|980|1|transform: 0 / 1
- nav-earn|nav-module_earn-sheen_BJihYd|CSSAnimation|running|980|1|transform: 1 / 0
- nav-earn|nav-module_earn-unmask_ZfvUeY|CSSAnimation|finished|980|1|webkitMaskPositionX,webkitMaskPositionY: 0 / 1
- nav-earn|nav-module_earn-unmask_ZfvUeY|CSSAnimation|running|980|1|webkitMaskPositionX,webkitMaskPositionY: 1 / 0
- people-card|filter|CSSTransition|running|1396.461|1|filter: 1 / 0
- people-sticky|deck-module_vinylSpin_k1msN-|CSSAnimation|running|4000|Infinity|transform: 1 / 1
- platform|sweep-module_sweepDoc_zGc1tE|CSSAnimation|paused|4000|Infinity|backgroundPositionX,backgroundPositionY: 4 / 4

Job 39983630584.1/r2/p1: 70 buckets; scale 1-9 of the bucket maximum (Layout max 8), '.' = 0

```
Layout    977777422.2.2.23226778777787877777778.222.2.2.4.46777776887877776777.3
Paint     54444921.......4..3444444494544644449.1.......4.14444444494544444448.1
hero-acce ...........................9..............................9...........  hero-accent:aria-label (total 2)
hero-acce ......9...........9........9........9............9........9........9..  hero-accent:class (total 7)
hero-acce ...........................9..............................9...........  hero-accent:d (total 6)
hero-acce ...........................9..............................9...........  hero-accent:style (total 12)
hero-acce ...........................9..............................9...........  hero-accent:viewBox (total 6)
people-ca .....9.9.......9..9.......9.9.......9.9.......9.9.......9..9.......9.9  people-carousel:childList (total 126)
people-ca .....9.8.......9..8.......9.8.......9.8.......9.8.......9..8.......9.8  people-carousel:src (total 63)
```

Running animations (owner | name | kind | state | duration ms | iterations | properties), count before / after:

- commission-card|commission-module_three-frame-one_-3Rext|CSSAnimation|paused|600|Infinity|opacity: 1 / 1
- commission-card|commission-module_three-frame-two_rO-IC0|CSSAnimation|paused|600|Infinity|opacity: 1 / 1
- commission-card|commission-module_three-frame-zero_NB28ic|CSSAnimation|paused|600|Infinity|opacity: 1 / 1
- hero-accent|accent-module_idle0_t7SI92|CSSAnimation|running|600|Infinity|opacity: 0 / 1
- hero-accent|accent-module_idle1_a3NQoa|CSSAnimation|running|600|Infinity|opacity: 0 / 1
- hero-accent|accent-module_idle2_Q1MyP3|CSSAnimation|running|600|Infinity|opacity: 0 / 1
- hero-accent|accent-module_strokeIn_yhJt8D|CSSAnimation|running|900|1|strokeDashoffset: 3 / 0
- hero-accent|width|CSSTransition|running|900|1|width: 1 / 0
- hero-cue|cue-module_copyIn_j26lO8|CSSAnimation|finished|700|1|: 1 / 1
- hero-cue|cue-module_scrollFloat_6RFPnC|CSSAnimation|running|2200|Infinity|transform: 1 / 1
- nav-earn|nav-module_earn-sheen_BJihYd|CSSAnimation|finished|980|1|transform: 1 / 1
- nav-earn|nav-module_earn-unmask_ZfvUeY|CSSAnimation|finished|980|1|webkitMaskPositionX,webkitMaskPositionY: 1 / 1
- people-sticky|deck-module_vinylSpin_k1msN-|CSSAnimation|running|4000|Infinity|transform: 1 / 1
- platform|sweep-module_sweepDoc_zGc1tE|CSSAnimation|paused|4000|Infinity|backgroundPositionX,backgroundPositionY: 4 / 4

Job 39983630584.1/r3/p1: 70 buckets; scale 1-9 of the bucket maximum (Layout max 8), '.' = 0

```
Layout    887746778687522.2.2.223.5787777647877676778.222..22.323586868696796776
Paint     89793622222411.......21.122222227322222222311.......2..222222224222222
hero-acce ...9.............................9..............................9.....  hero-accent:aria-label (total 3)
hero-acce ...9........9...........9........9........9............9........9.....  hero-accent:class (total 7)
hero-acce ...9.............................9..............................9.....  hero-accent:d (total 9)
hero-acce ...9.............................9..............................9.....  hero-accent:style (total 18)
hero-acce ...9.............................9..............................9.....  hero-accent:viewBox (total 9)
people-ca .9.9.......9.9.......9..9.......9.9.......9.9.......9.9.......9..9....  people-carousel:childList (total 126)
people-ca .9.8.......9.8.......9..8.......9.8.......9.8.......9.8.......9..8....  people-carousel:src (total 63)
```

Running animations (owner | name | kind | state | duration ms | iterations | properties), count before / after:

- commission-card|commission-module_three-frame-one_-3Rext|CSSAnimation|paused|600|Infinity|opacity: 1 / 1
- commission-card|commission-module_three-frame-two_rO-IC0|CSSAnimation|paused|600|Infinity|opacity: 1 / 1
- commission-card|commission-module_three-frame-zero_NB28ic|CSSAnimation|paused|600|Infinity|opacity: 1 / 1
- hero-accent|accent-module_strokeIn_yhJt8D|CSSAnimation|running|900|1|strokeDashoffset: 0 / 3
- hero-accent|accent-module_strokeOut_SDdGZt|CSSAnimation|running|900|1|strokeDashoffset: 3 / 0
- hero-accent|width|CSSTransition|running|900|1|width: 0 / 1
- hero-cue|cue-module_copyIn_j26lO8|CSSAnimation|finished|700|1|: 1 / 1
- hero-cue|cue-module_scrollFloat_6RFPnC|CSSAnimation|running|2200|Infinity|transform: 1 / 1
- nav-earn|nav-module_earn-sheen_BJihYd|CSSAnimation|finished|980|1|transform: 0 / 1
- nav-earn|nav-module_earn-sheen_BJihYd|CSSAnimation|running|980|1|transform: 1 / 0
- nav-earn|nav-module_earn-unmask_ZfvUeY|CSSAnimation|finished|980|1|webkitMaskPositionX,webkitMaskPositionY: 0 / 1
- nav-earn|nav-module_earn-unmask_ZfvUeY|CSSAnimation|running|980|1|webkitMaskPositionX,webkitMaskPositionY: 1 / 0
- people-card|filter|CSSTransition|running|1413.563|1|filter: 1 / 0
- people-sticky|deck-module_vinylSpin_k1msN-|CSSAnimation|running|4000|Infinity|transform: 1 / 1
- platform|sweep-module_sweepDoc_zGc1tE|CSSAnimation|paused|4000|Infinity|backgroundPositionX,backgroundPositionY: 4 / 4

