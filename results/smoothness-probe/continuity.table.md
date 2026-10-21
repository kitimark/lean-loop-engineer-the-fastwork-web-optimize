Runs are cited by code; the index is at the end. Per node (property): the median over runs of the per-run median over pushes, with the min-max of the per-run medians in brackets. `defects` = stalls + jumps + reversals; `tail` = late tail steps; `peak` = peak shown step over peak ideal step (1000 = equal). Measured values, not thresholds.

### Cells where the faithful rewrite (base) differs from the original beyond the original's run-to-run range

| engine, width, window, ideal | property | measure | orig (range) | base | direction | orig runs | base runs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| chromium 1280px, hero, ideal line | (window total) | defectsPerPush | 0 | 12 | higher | 29 runs (see Runs per arm) | 29 runs (see Runs per arm) |
| chromium 390px, end-close, ideal ref | (window total) | defectsPerPush | 20 (17-25) | 29 | higher | 33 runs (see Runs per arm) | 33 runs (see Runs per arm) |
| chromium 390px, end-open, ideal ref | (window total) | defectsPerPush | 0 (0-9) | 16 | higher | 33 runs (see Runs per arm) | 33 runs (see Runs per arm) |
| chromium 390px, end-open, ideal ref | logo | defects | 0 (0-4) | 5 | higher | 33 runs (see Runs per arm) | 33 runs (see Runs per arm) |
| chromium 390px, end-open, ideal ref | panel | defects | 0 (0-1) | 5 | higher | 33 runs (see Runs per arm) | 33 runs (see Runs per arm) |
| chromium 390px, hero, ideal line | (window total) | flaggedNodes | 6 | 8 | higher | 33 runs (see Runs per arm) | 33 runs (see Runs per arm) |
| chromium 390px, hero, ideal line | (window total) | nodes moving | 7 | 9 | higher | 33 runs (see Runs per arm) | 33 runs (see Runs per arm) |
| chromium 390px, hero, ideal line | hero.stage | moved | not moving | 16/33 runs | arm moving | 33 runs (see Runs per arm) | 33 runs (see Runs per arm) |
| chromium 390px, hero, ideal line | hero.deck | moved | not moving | 16/33 runs | arm moving | 33 runs (see Runs per arm) | 33 runs (see Runs per arm) |

### Cells where a flagged rewrite differs from the faithful rewrite (base) beyond base's run-to-run range

| engine, width, window, ideal | property | measure | base (range) | arm | arm value | direction | arm runs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| chromium 1280px, end-close, ideal line | earn | tail | 16 (14-18) | cand:?preset=v2-proved | 13 | lower | R4,R7 |
| chromium 1280px, end-close, ideal line | panel | defects | 6 (5-7) | cand:hero:scene-pause | 8 | higher | R42 |
| chromium 1280px, end-close, ideal line | earn | tail | 16 (14-18) | cand:morph.tween:scroll-lock | 13 | lower | R21,R22,R25 |
| chromium 1280px, end-close, ideal line | (window total) | tailPerPush | 47 (39-98) | cand:morph.tween:waapi | 29 | lower | R2,R5,R19,R24,R39 |
| chromium 1280px, end-close, ideal line | nav | tail | 15 (13-17) | cand:morph.tween:waapi | 1 | lower | R2,R5,R19,R24,R39 |
| chromium 1280px, end-close, ideal line | (window total) | tailPerPush | 47 (39-98) | cand:morph.tween:waapi-scoped | 24 | lower | R10,R12 |
| chromium 1280px, end-close, ideal line | nav | defects | 10 (8-11) | cand:morph.tween:waapi-scoped | 7 | lower | R10,R12 |
| chromium 1280px, end-close, ideal line | nav | tail | 15 (13-17) | cand:morph.tween:waapi-scoped | 1 | lower | R10,R12 |
| chromium 1280px, end-close, ideal line | actions | tail | 13 (12-16) | cand:morph.tween:waapi-scoped | 9 | lower | R10,R12 |
| chromium 1280px, end-close, ideal line | (window total) | defectsPerPush | 49 (43-101) | cand:nav:earn-no-transition | 37 | lower | R13,R15 |
| chromium 1280px, end-close, ideal line | earn | defects | 20 (18-22) | cand:nav:earn-no-transition | 11 | lower | R13,R15 |
| chromium 1280px, end-close, ideal line | earn | tail | 16 (14-18) | cand:nav:earn-no-transition | 13 | lower | R13,R15 |
| chromium 1280px, end-close, ideal ref | earn | tail | 16 (14-18) | cand:?preset=v2-proved | 13 | lower | R4,R7 |
| chromium 1280px, end-close, ideal ref | earn | tail | 16 (14-18) | cand:morph.tween:scroll-lock | 13 | lower | R21,R22,R25 |
| chromium 1280px, end-close, ideal ref | (window total) | tailPerPush | 46 (38-97) | cand:morph.tween:waapi | 31 | lower | R2,R5,R19,R24,R39 |
| chromium 1280px, end-close, ideal ref | nav | tail | 15 (13-17) | cand:morph.tween:waapi | 3 | lower | R2,R5,R19,R24,R39 |
| chromium 1280px, end-close, ideal ref | (window total) | tailPerPush | 46 (38-97) | cand:morph.tween:waapi-scoped | 23 | lower | R10,R12 |
| chromium 1280px, end-close, ideal ref | nav | defects | 1 (0-3) | cand:morph.tween:waapi-scoped | 4 | higher | R10,R12 |
| chromium 1280px, end-close, ideal ref | nav | tail | 15 (13-17) | cand:morph.tween:waapi-scoped | 1 | lower | R10,R12 |
| chromium 1280px, end-close, ideal ref | actions | tail | 13 (12-16) | cand:morph.tween:waapi-scoped | 9 | lower | R10,R12 |
| chromium 1280px, end-close, ideal ref | earn | tail | 16 (14-18) | cand:nav:earn-no-transition | 13 | lower | R13,R15 |
| chromium 1280px, end-open, ideal line | nav | defects | 11 (10-13) | cand:morph.tween:waapi | 9 | lower | R2,R5,R19,R24,R39 |
| chromium 1280px, end-open, ideal line | nav | defects | 11 (10-13) | cand:morph.tween:waapi-scoped | 9 | lower | R10,R12 |
| chromium 1280px, end-open, ideal line | panel | defects | 10 (8-11) | cand:morph.tween:waapi-scoped | 7 | lower | R10,R12 |
| chromium 1280px, end-open, ideal line | (window total) | tailPerPush | 5 (2-10) | cand:nav:earn-no-transition | 0 | lower | R13,R15 |
| chromium 1280px, end-open, ideal line | earn | tail | 3 (2-4) | cand:nav:earn-no-transition | 0 | lower | R13,R15 |
| chromium 1280px, end-open, ideal ref | (window total) | defectsPerPush | 2 (0-7) | cand:nav:earn-no-transition | 18 | higher | R13,R15 |
| chromium 1280px, end-open, ideal ref | (window total) | tailPerPush | 5 (2-10) | cand:nav:earn-no-transition | 0 | lower | R13,R15 |
| chromium 1280px, end-open, ideal ref | earn | defects | 1 (0-5) | cand:nav:earn-no-transition | 16 | higher | R13,R15 |
| chromium 1280px, end-open, ideal ref | earn | tail | 3 (2-4) | cand:nav:earn-no-transition | 0 | lower | R13,R15 |
| chromium 1280px, hero, ideal line | (window total) | flaggedNodes | 6 (6-12) | cand:?preset=v2-proved | 4 | lower | R4,R7 |
| chromium 1280px, hero, ideal line | hero.copy | defects | 2 (1-2) | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| chromium 1280px, hero, ideal line | hero.cue | defects | 2 (1-2) | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| chromium 1280px, hero, ideal line | hero.orbit.card | defects | 2 | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| chromium 1280px, hero, ideal line | hero.deck.card | defects | 2 | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| chromium 1280px, hero, ideal ref | hero.copy | defects | 3 (0-3) | cand:?preset=v2-proved | 4 | higher | R4,R7 |
| chromium 1280px, hero, ideal ref | hero.cta | defects | 3 (0-3) | cand:?preset=v2-proved | 4 | higher | R4,R7 |
| chromium 1280px, hero, ideal ref | hero.countdown.unit | defects | 3 (0-3) | cand:?preset=v2-proved | 4 | higher | R4,R7 |
| chromium 1280px, hero, ideal ref | hero.cue | defects | 3 (0-3) | cand:?preset=v2-proved | 4 | higher | R4,R7 |
| chromium 1280px, hero, ideal ref | hero.orbit.card | defects | 3 (0-3) | cand:?preset=v2-proved | 4 | higher | R4,R7 |
| chromium 1280px, hero, ideal ref | hero.deck.card | defects | 3 (0-3) | cand:?preset=v2-proved | 4 | higher | R4,R7 |
| chromium 390px, end-close, ideal line | (window total) | defectsPerPush | 98 (92-198) | cand:morph.tween:waapi | 89 | lower | R2,R5,R19,R24,R39 |
| chromium 390px, end-close, ideal line | (window total) | tailPerPush | 57 (56-115) | cand:morph.tween:waapi | 34 | lower | R2,R5,R19,R24,R39 |
| chromium 390px, end-close, ideal line | nav | tail | 19 (19-20) | cand:morph.tween:waapi | 1 | lower | R2,R5,R19,R24,R39 |
| chromium 390px, end-close, ideal line | actions | defects | 19 (18-21) | cand:morph.tween:waapi | 17 | lower | R2,R5,R19,R24,R39 |
| chromium 390px, end-close, ideal line | actions | tail | 16 (16-17) | cand:morph.tween:waapi | 12 | lower | R2,R5,R19,R24,R39 |
| chromium 390px, end-close, ideal line | earn | defects | 32 (31-35) | cand:morph.tween:waapi | 30 | lower | R2,R5,R19,R24,R39 |
| chromium 390px, end-close, ideal line | (window total) | defectsPerPush | 98 (92-198) | cand:morph.tween:waapi-scoped | 86 | lower | R10,R12 |
| chromium 390px, end-close, ideal line | (window total) | tailPerPush | 57 (56-115) | cand:morph.tween:waapi-scoped | 34 | lower | R10,R12 |
| chromium 390px, end-close, ideal line | nav | tail | 19 (19-20) | cand:morph.tween:waapi-scoped | 1 | lower | R10,R12 |
| chromium 390px, end-close, ideal line | logo | defects | 29 (24-33) | cand:morph.tween:waapi-scoped | 23 | lower | R10,R12 |
| chromium 390px, end-close, ideal line | actions | defects | 19 (18-21) | cand:morph.tween:waapi-scoped | 17 | lower | R10,R12 |
| chromium 390px, end-close, ideal line | actions | tail | 16 (16-17) | cand:morph.tween:waapi-scoped | 12 | lower | R10,R12 |
| chromium 390px, end-close, ideal line | (window total) | defectsPerPush | 98 (92-198) | cand:nav:earn-no-transition | 80 | lower | R13,R15 |
| chromium 390px, end-close, ideal line | earn | defects | 32 (31-35) | cand:nav:earn-no-transition | 18 | lower | R13,R15 |
| chromium 390px, end-close, ideal ref | (window total) | tailPerPush | 56 (55-114) | cand:morph.tween:waapi | 38 | lower | R2,R5,R19,R24,R39 |
| chromium 390px, end-close, ideal ref | nav | defects | 0 | cand:morph.tween:waapi | 5 | higher | R2,R5,R19,R24,R39 |
| chromium 390px, end-close, ideal ref | nav | tail | 19 (19-20) | cand:morph.tween:waapi | 4 | lower | R2,R5,R19,R24,R39 |
| chromium 390px, end-close, ideal ref | actions | tail | 16 (16-17) | cand:morph.tween:waapi | 12 | lower | R2,R5,R19,R24,R39 |
| chromium 390px, end-close, ideal ref | earn | defects | 17 (17-18) | cand:morph.tween:waapi | 20 | higher | R2,R5,R19,R24,R39 |
| chromium 390px, end-close, ideal ref | panel | defects | 0 | cand:morph.tween:waapi | 3 | higher | R2,R5,R19,R24,R39 |
| chromium 390px, end-close, ideal ref | panel | tail | 0 | cand:morph.tween:waapi | 1 | higher | R2,R5,R19,R24,R39 |
| chromium 390px, end-close, ideal ref | (window total) | tailPerPush | 56 (55-114) | cand:morph.tween:waapi-scoped | 37 | lower | R10,R12 |
| chromium 390px, end-close, ideal ref | nav | defects | 0 | cand:morph.tween:waapi-scoped | 5 | higher | R10,R12 |
| chromium 390px, end-close, ideal ref | nav | tail | 19 (19-20) | cand:morph.tween:waapi-scoped | 4 | lower | R10,R12 |
| chromium 390px, end-close, ideal ref | actions | tail | 16 (16-17) | cand:morph.tween:waapi-scoped | 12 | lower | R10,R12 |
| chromium 390px, end-close, ideal ref | earn | defects | 17 (17-18) | cand:morph.tween:waapi-scoped | 19 | higher | R10,R12 |
| chromium 390px, end-close, ideal ref | panel | defects | 0 | cand:morph.tween:waapi-scoped | 4 | higher | R10,R12 |
| chromium 390px, end-close, ideal ref | panel | tail | 0 | cand:morph.tween:waapi-scoped | 1 | higher | R10,R12 |
| chromium 390px, end-close, ideal ref | earn | defects | 17 (17-18) | cand:nav:earn-no-transition | 20 | higher | R13,R15 |
| chromium 390px, end-open, ideal line | (window total) | defectsPerPush | 118 (113-243) | cand:morph.tween:waapi | 112 | lower | R2,R5,R19,R24,R39 |
| chromium 390px, end-open, ideal line | (window total) | defectsPerPush | 118 (113-243) | cand:morph.tween:waapi-scoped | 112 | lower | R10,R12 |
| chromium 390px, end-open, ideal line | logo | defects | 28 (26-31) | cand:morph.tween:waapi-scoped | 25 | lower | R10,R12 |
| chromium 390px, end-open, ideal line | (window total) | defectsPerPush | 118 (113-243) | cand:nav:earn-no-transition | 112 | lower | R13,R15 |
| chromium 390px, end-open, ideal line | (window total) | tailPerPush | 9 (6-19) | cand:nav:earn-no-transition | 2 | lower | R13,R15 |
| chromium 390px, end-open, ideal line | earn | defects | 31 (29-31) | cand:nav:earn-no-transition | 27 | lower | R13,R15 |
| chromium 390px, end-open, ideal line | earn | tail | 7 (4-8) | cand:nav:earn-no-transition | 0 | lower | R13,R15 |
| chromium 390px, end-open, ideal ref | (window total) | flaggedNodes | 5 (4-10) | cand:morph.tween:waapi | 3 | lower | R2,R5,R19,R24,R39 |
| chromium 390px, end-open, ideal ref | panel | defects | 5 (1-5) | cand:morph.tween:waapi | 0 | lower | R2,R5,R19,R24,R39 |
| chromium 390px, end-open, ideal ref | (window total) | flaggedNodes | 5 (4-10) | cand:morph.tween:waapi-scoped | 3 | lower | R10,R12 |
| chromium 390px, end-open, ideal ref | panel | defects | 5 (1-5) | cand:morph.tween:waapi-scoped | 0 | lower | R10,R12 |
| chromium 390px, end-open, ideal ref | (window total) | defectsPerPush | 16 (5-40) | cand:nav:earn-no-transition | 42 | higher | R13,R15 |
| chromium 390px, end-open, ideal ref | (window total) | tailPerPush | 9 (6-19) | cand:nav:earn-no-transition | 2 | lower | R13,R15 |
| chromium 390px, end-open, ideal ref | earn | defects | 1 (0-3) | cand:nav:earn-no-transition | 26 | higher | R13,R15 |
| chromium 390px, end-open, ideal ref | earn | tail | 7 (4-8) | cand:nav:earn-no-transition | 0 | lower | R13,R15 |
| chromium 390px, hero, ideal line | hero.copy | defects | 3 (2-3) | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| chromium 390px, hero, ideal line | hero.cta | defects | 2 | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| chromium 390px, hero, ideal line | hero.countdown.unit | defects | 2 | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| chromium 390px, hero, ideal line | hero.cue | defects | 3 (2-3) | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| chromium 390px, hero, ideal line | hero.orbit.card | defects | 3 (2-3) | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| chromium 390px, hero, ideal line | hero.deck.card | defects | 3 (2-3) | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| chromium 390px, hero, ideal line | (window total) | nodes moving | 9 | cand:hero:scene-pause | 7 | lower | R42,R43,R44 |
| chromium 390px, hero, ideal line | hero.stage | moved | 16/33 runs | cand:hero:scene-pause | not moving | arm not moving | R42,R43,R44 |
| chromium 390px, hero, ideal line | hero.deck | moved | 16/33 runs | cand:hero:scene-pause | not moving | arm not moving | R42,R43,R44 |
| chromium 390px, hero, ideal line | (window total) | nodes moving | 9 | cand:hero.exit:faithful | 7 | lower | R6,R8,R9,R20,R28 |
| chromium 390px, hero, ideal line | (window total) | nodes moving | 9 | cand:morph.tween:scroll-lock | 7 | lower | R21,R22,R25 |
| chromium 390px, hero, ideal line | hero.stage | moved | 16/33 runs | cand:morph.tween:scroll-lock | not moving | arm not moving | R21,R22,R25 |
| chromium 390px, hero, ideal line | hero.deck | moved | 16/33 runs | cand:morph.tween:scroll-lock | not moving | arm not moving | R21,R22,R25 |
| chromium 390px, hero, ideal line | (window total) | nodes moving | 9 | cand:morph.tween:waapi | 7 | lower | R2,R5,R19,R24,R39 |
| chromium 390px, hero, ideal ref | hero.copy | defects | 0 (0-3) | cand:?preset=v2-proved | 4 | higher | R4,R7 |
| chromium 390px, hero, ideal ref | hero.cta | defects | 0 (0-3) | cand:?preset=v2-proved | 4 | higher | R4,R7 |
| chromium 390px, hero, ideal ref | hero.countdown.unit | defects | 0 (0-3) | cand:?preset=v2-proved | 4 | higher | R4,R7 |
| chromium 390px, hero, ideal ref | hero.cue | defects | 0 (0-3) | cand:?preset=v2-proved | 4 | higher | R4,R7 |
| chromium 390px, hero, ideal ref | hero.orbit.card | defects | 0 (0-3) | cand:?preset=v2-proved | 4 | higher | R4,R7 |
| chromium 390px, hero, ideal ref | hero.deck.card | defects | 0 (0-3) | cand:?preset=v2-proved | 4 | higher | R4,R7 |
| macos-webkit 1280px, end-close, ideal line | nav | tail | 12 (6-20) | cand:morph.tween:waapi | 0 | lower | R19,R24 |
| macos-webkit 1280px, end-close, ideal ref | nav | tail | 12 (6-20) | cand:morph.tween:waapi | 1 | lower | R19,R24 |
| macos-webkit 1280px, end-open, ideal line | (window total) | flaggedNodes | 5 (5-9) | cand:?preset=v2-proved | 4 | lower | R4,R7 |
| macos-webkit 1280px, hero, ideal line | (window total) | defectsPerPush | 12 | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| macos-webkit 1280px, hero, ideal line | (window total) | flaggedNodes | 6 | cand:?preset=v2-proved | 4 | lower | R4,R7 |
| macos-webkit 1280px, hero, ideal line | hero.copy | defects | 2 | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| macos-webkit 1280px, hero, ideal line | hero.cta | defects | 2 | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| macos-webkit 1280px, hero, ideal line | hero.countdown.unit | defects | 2 | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| macos-webkit 1280px, hero, ideal line | hero.cue | defects | 2 | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| macos-webkit 1280px, hero, ideal line | hero.orbit.card | defects | 2 | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| macos-webkit 1280px, hero, ideal line | hero.deck.card | defects | 2 | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| macos-webkit 390px, end-close, ideal line | nav | tail | 10 (6-17) | cand:morph.tween:waapi | 0 | lower | R19,R24 |
| macos-webkit 390px, end-close, ideal ref | nav | tail | 10 (6-17) | cand:morph.tween:waapi | 1 | lower | R19,R24 |
| macos-webkit 390px, end-open, ideal line | nav | defects | 8 (6-13) | cand:morph.tween:scroll-lock | 5 | lower | R21,R22,R25 |
| macos-webkit 390px, end-open, ideal line | logo | defects | 10 (7-15) | cand:morph.tween:scroll-lock | 6 | lower | R21,R22,R25 |
| macos-webkit 390px, end-open, ideal line | actions | defects | 10 (7-15) | cand:morph.tween:scroll-lock | 6 | lower | R21,R22,R25 |
| macos-webkit 390px, end-open, ideal line | panel | defects | 8 (5-11) | cand:morph.tween:scroll-lock | 4 | lower | R21,R22,R25 |
| macos-webkit 390px, hero, ideal line | (window total) | defectsPerPush | 12 | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| macos-webkit 390px, hero, ideal line | hero.copy | defects | 2 | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| macos-webkit 390px, hero, ideal line | hero.cta | defects | 2 | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| macos-webkit 390px, hero, ideal line | hero.countdown.unit | defects | 2 | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| macos-webkit 390px, hero, ideal line | hero.cue | defects | 2 | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| macos-webkit 390px, hero, ideal line | hero.orbit.card | defects | 2 | cand:?preset=v2-proved | 0 | lower | R4,R7 |
| macos-webkit 390px, hero, ideal line | hero.deck.card | defects | 2 | cand:?preset=v2-proved | 0 | lower | R4,R7 |

### Per window, property and arm

**chromium 1280px, end-close, ideal line**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nav | nav | base | 29 / 29 | 10 (8-11) | 4 | 5 | 1 | 15 (13-17) | 7372 (1024-8410) | 29 runs (see Runs per arm) |
| nav | nav | cand:?preset=v2-proved | 2 / 2 | 10 (10-11) | 4 | 5 | 1 | 13 (13-15) | 6698 (6698-6870) | R4,R7 |
| nav | nav | cand:hero:scene-pause | 1 / 1 | 8 | 4 | 4 | 0 | 16 | 1183 | R42 |
| nav | nav | cand:hero.exit:faithful | 5 / 5 | 11 (8-11) | 4 | 6 | 1 | 16 (16-17) | 7742 (1137-8554) | R6,R8,R9,R20,R28 |
| nav | nav | cand:hero.exit:scoped | 4 / 4 | 10 (9-10) | 4 | 5 | 1 | 15 (14-16) | 6614 (1323-8115) | R1,R3,R17,R27 |
| nav | nav | cand:morph.tween:scroll-lock | 3 / 3 | 11 (8-11) | 4 | 6 | 1 | 13 (13-16) | 6843 (1034-7760) | R21,R22,R25 |
| nav | nav | cand:morph.tween:waapi | 5 / 5 | 8 (7-9) | 4 | 4 | 0 | 1 (1-18) | 1203 (1150-1271) | R2,R5,R19,R24,R39 |
| nav | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 7 (7-8) | 3 | 4 | 0 | 1 | 1014 (1014-1902) | R10,R12 |
| nav | nav | cand:nav:earn-no-transition | 2 / 2 | 10 | 3 | 5 | 1 | 13 (13-15) | 5879 (5879-7314) | R13,R15 |
| nav | nav | orig | 29 / 29 | 9 (7-12) | 4 | 5 | 1 | 15 (13-17) | 6763 (1009-9406) | 29 runs (see Runs per arm) |
| logo | nav | base | 29 / 29 | 0 | 0 | 0 | 0 | 0 | 1110 (1000-1188) | 29 runs (see Runs per arm) |
| logo | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1114 (1114-1118) | R4,R7 |
| logo | nav | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1087 | R42 |
| logo | nav | cand:hero.exit:faithful | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1047 (1025-1180) | R6,R8,R9,R20,R28 |
| logo | nav | cand:hero.exit:scoped | 4 / 4 | 0 | 0 | 0 | 0 | 0 | 1087 (1015-1129) | R1,R3,R17,R27 |
| logo | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1101 (1021-1109) | R21,R22,R25 |
| logo | nav | cand:morph.tween:waapi | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1127 (999-1146) | R2,R5,R19,R24,R39 |
| logo | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1114 (1114-1142) | R10,R12 |
| logo | nav | cand:nav:earn-no-transition | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1018 (1018-1091) | R13,R15 |
| logo | nav | orig | 29 / 29 | 0 | 0 | 0 | 0 | 0 | 1091 (1032-1182) | 29 runs (see Runs per arm) |
| actions | nav | base | 29 / 29 | 12 (10-13) | 8 | 4 | 0 | 13 (12-16) | 2456 (1613-2867) | 29 runs (see Runs per arm) |
| actions | nav | cand:?preset=v2-proved | 2 / 2 | 11 | 7 | 4 | 0 | 12 (12-13) | 2040 (2040-2243) | R4,R7 |
| actions | nav | cand:hero:scene-pause | 1 / 1 | 11 | 7 | 4 | 0 | 13 | 1837 | R42 |
| actions | nav | cand:hero.exit:faithful | 5 / 5 | 12 (12-13) | 8 | 4 | 0 | 15 (14-16) | 2633 (2298-2789) | R6,R8,R9,R20,R28 |
| actions | nav | cand:hero.exit:scoped | 4 / 4 | 12 (11-13) | 8 | 4 | 0 | 14 (13-15) | 2328 (2043-2937) | R1,R3,R17,R27 |
| actions | nav | cand:morph.tween:scroll-lock | 3 / 3 | 11 (11-12) | 7 | 4 | 0 | 12 (12-13) | 2282 (1998-2527) | R21,R22,R25 |
| actions | nav | cand:morph.tween:waapi | 5 / 5 | 11 (10-12) | 7 | 4 | 0 | 12 (11-16) | 2358 (1950-2609) | R2,R5,R19,R24,R39 |
| actions | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 11 | 7 | 4 | 0 | 9 (9-12) | 1826 (1826-4130) | R10,R12 |
| actions | nav | cand:nav:earn-no-transition | 2 / 2 | 11 (11-13) | 7 | 4 | 0 | 13 (13-15) | 1743 (1743-2351) | R13,R15 |
| actions | nav | orig | 29 / 29 | 11 (10-14) | 7 | 4 | 0 | 14 (12-16) | 2417 (1883-3650) | 29 runs (see Runs per arm) |
| earn | nav | base | 29 / 29 | 20 (18-22) | 13 | 7 | 0 | 16 (14-18) | 2456 (1614-2867) | 29 runs (see Runs per arm) |
| earn | nav | cand:?preset=v2-proved | 2 / 2 | 18 (18-20) | 12 | 6 | 0 | 13 (13-16) | 2040 (2040-2277) | R4,R7 |
| earn | nav | cand:hero:scene-pause | 1 / 1 | 20 | 13 | 7 | 0 | 16 | 1837 | R42 |
| earn | nav | cand:hero.exit:faithful | 5 / 5 | 21 (20-21) | 14 | 7 | 0 | 17 (16-17) | 2633 (2300-2790) | R6,R8,R9,R20,R28 |
| earn | nav | cand:hero.exit:scoped | 4 / 4 | 20 (19-20) | 13 | 7 | 0 | 15 (14-17) | 2328 (2043-2937) | R1,R3,R17,R27 |
| earn | nav | cand:morph.tween:scroll-lock | 3 / 3 | 19 (18-21) | 13 | 6 | 0 | 13 (13-16) | 2282 (1998-2527) | R21,R22,R25 |
| earn | nav | cand:morph.tween:waapi | 5 / 5 | 19 (19-22) | 12 | 7 | 0 | 15 (14-18) | 2358 (1950-2610) | R2,R5,R19,R24,R39 |
| earn | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 19 (19-20) | 12 | 7 | 0 | 14 (14-15) | 1827 (1827-4131) | R10,R12 |
| earn | nav | cand:nav:earn-no-transition | 2 / 2 | 11 (11-13) | 7 | 4 | 0 | 13 (13-15) | 1743 (1743-2351) | R13,R15 |
| earn | nav | orig | 29 / 29 | 20 (19-22) | 13 | 7 | 0 | 16 (14-18) | 2417 (1883-3651) | 29 runs (see Runs per arm) |
| panel | morph.panel | base | 29 / 29 | 6 (5-7) | 5 | 1 | 0 | 1 (0-1) | 1388 (1253-1391) | 29 runs (see Runs per arm) |
| panel | morph.panel | cand:?preset=v2-proved | 2 / 2 | 6 | 5 | 1 | 0 | 1 | 1283 (1283-1388) | R4,R7 |
| panel | morph.panel | cand:hero:scene-pause | 1 / 1 | 8 | 6 | 2 | 0 | 1 | 1389 | R42 |
| panel | morph.panel | cand:hero.exit:faithful | 5 / 5 | 7 (6-7) | 6 | 1 | 0 | 1 (0-1) | 1389 (1334-1393) | R6,R8,R9,R20,R28 |
| panel | morph.panel | cand:hero.exit:scoped | 4 / 4 | 6 (5-6) | 5 | 1 | 0 | 1 (0-1) | 1388 (1264-1392) | R1,R3,R17,R27 |
| panel | morph.panel | cand:morph.tween:scroll-lock | 3 / 3 | 7 (6-7) | 5 | 1 | 0 | 1 | 1388 (1387-1388) | R21,R22,R25 |
| panel | morph.panel | cand:morph.tween:waapi | 5 / 5 | 7 (6-7) | 5 | 2 | 0 | 1 | 1388 (1378-1389) | R2,R5,R19,R24,R39 |
| panel | morph.panel | cand:morph.tween:waapi-scoped | 2 / 2 | 5 (5-7) | 4 | 1 | 0 | 0 (0-1) | 1046 (1046-1391) | R10,R12 |
| panel | morph.panel | cand:nav:earn-no-transition | 2 / 2 | 6 (6-7) | 5 | 1 | 0 | 1 | 1355 (1355-1390) | R13,R15 |
| panel | morph.panel | orig | 29 / 29 | 6 (5-8) | 5 | 1 | 0 | 1 (0-1) | 1389 (1245-1395) | 29 runs (see Runs per arm) |

**chromium 1280px, end-close, ideal ref**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nav | nav | base | 29 / 29 | 1 (0-3) | 1 | 0 | 0 | 15 (13-17) | 1007 (1000-1574) | 29 runs (see Runs per arm) |
| nav | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 13 (13-15) | 1000 | R4,R7 |
| nav | nav | cand:hero:scene-pause | 1 / 1 | 1 | 1 | 0 | 0 | 16 | 1006 | R42 |
| nav | nav | cand:hero.exit:faithful | 5 / 5 | 1 (0-2) | 0 | 0 | 0 | 16 (16-17) | 1001 (1000-1100) | R6,R8,R9,R20,R28 |
| nav | nav | cand:hero.exit:scoped | 4 / 4 | 1 (0-2) | 1 | 0 | 0 | 15 (14-16) | 1010 (1002-1200) | R1,R3,R17,R27 |
| nav | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 (0-2) | 0 | 0 | 0 | 13 (13-16) | 1003 (1000-1006) | R21,R22,R25 |
| nav | nav | cand:morph.tween:waapi | 5 / 5 | 3 (1-4) | 1 | 0 | 1 | 3 (2-18) | 1000 (1000-1006) | R2,R5,R19,R24,R39 |
| nav | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 4 | 2 | 0 | 2 | 1 (1-2) | 1001 (1001-1010) | R10,R12 |
| nav | nav | cand:nav:earn-no-transition | 2 / 2 | 0 | 0 | 0 | 0 | 13 (13-15) | 1000 (1000-1010) | R13,R15 |
| nav | nav | orig | 29 / 29 | 1 (0-2) | 1 | 1 | 0 | 15 (13-17) | 1014 (1000-1755) | 29 runs (see Runs per arm) |
| logo | nav | base | 29 / 29 | 0 | 0 | 0 | 0 | 0 | 1000 (999-1003) | 29 runs (see Runs per arm) |
| logo | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 999 (999-1000) | R4,R7 |
| logo | nav | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1000 | R42 |
| logo | nav | cand:hero.exit:faithful | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1000 (999-1002) | R6,R8,R9,R20,R28 |
| logo | nav | cand:hero.exit:scoped | 4 / 4 | 0 | 0 | 0 | 0 | 0 | 1000 (999-1000) | R1,R3,R17,R27 |
| logo | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 (999-1000) | R21,R22,R25 |
| logo | nav | cand:morph.tween:waapi | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1000 (999-1003) | R2,R5,R19,R24,R39 |
| logo | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1001 | R10,R12 |
| logo | nav | cand:nav:earn-no-transition | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 999 (999-1001) | R13,R15 |
| logo | nav | orig | 29 / 29 | 0 | 0 | 0 | 0 | 0 | 1000 (999-1003) | 29 runs (see Runs per arm) |
| actions | nav | base | 29 / 29 | 1 (0-2) | 1 | 0 | 0 | 13 (12-16) | 1000 (999-1141) | 29 runs (see Runs per arm) |
| actions | nav | cand:?preset=v2-proved | 2 / 2 | 0 (0-1) | 0 | 0 | 0 | 12 (12-13) | 1000 (1000-1001) | R4,R7 |
| actions | nav | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 13 | 999 | R42 |
| actions | nav | cand:hero.exit:faithful | 5 / 5 | 1 (0-2) | 1 | 0 | 0 | 15 (14-16) | 1000 (999-1007) | R6,R8,R9,R20,R28 |
| actions | nav | cand:hero.exit:scoped | 4 / 4 | 0 (0-2) | 0 | 0 | 0 | 14 (13-15) | 1000 | R1,R3,R17,R27 |
| actions | nav | cand:morph.tween:scroll-lock | 3 / 3 | 2 (0-3) | 2 | 0 | 0 | 12 (12-13) | 1007 (1000-1010) | R21,R22,R25 |
| actions | nav | cand:morph.tween:waapi | 5 / 5 | 1 (1-2) | 1 | 0 | 0 | 12 (11-16) | 1000 (999-1000) | R2,R5,R19,R24,R39 |
| actions | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 0 (0-1) | 0 | 0 | 0 | 9 (9-12) | 1000 (1000-1057) | R10,R12 |
| actions | nav | cand:nav:earn-no-transition | 2 / 2 | 1 (1-2) | 1 | 0 | 0 | 13 (13-15) | 1000 | R13,R15 |
| actions | nav | orig | 29 / 29 | 1 (0-2) | 1 | 0 | 0 | 14 (12-16) | 1000 (999-1061) | 29 runs (see Runs per arm) |
| earn | nav | base | 29 / 29 | 15 (12-18) | 2 | 13 | 0 | 16 (14-18) | 35666 (6484-43500) | 29 runs (see Runs per arm) |
| earn | nav | cand:?preset=v2-proved | 2 / 2 | 13 (13-15) | 1 | 12 | 0 | 13 (13-16) | 35833 (35833-43500) | R4,R7 |
| earn | nav | cand:hero:scene-pause | 1 / 1 | 16 | 3 | 13 | 0 | 16 | 37333 | R42 |
| earn | nav | cand:hero.exit:faithful | 5 / 5 | 15 (15-18) | 2 | 14 | 0 | 17 (16-17) | 25666 (4666-43500) | R6,R8,R9,R20,R28 |
| earn | nav | cand:hero.exit:scoped | 4 / 4 | 14 (14-18) | 2 | 13 | 0 | 15 (14-17) | 6757 (6484-29166) | R1,R3,R17,R27 |
| earn | nav | cand:morph.tween:scroll-lock | 3 / 3 | 15 (14-16) | 2 | 12 | 0 | 13 (13-16) | 41833 (41833-43500) | R21,R22,R25 |
| earn | nav | cand:morph.tween:waapi | 5 / 5 | 18 (17-22) | 5 | 12 | 0 | 15 (14-18) | 35833 (22166-41833) | R2,R5,R19,R24,R39 |
| earn | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 16 (16-19) | 5 | 11 | 0 | 14 (14-15) | 7878 (7878-37166) | R10,R12 |
| earn | nav | cand:nav:earn-no-transition | 2 / 2 | 12 (12-15) | 2 | 9 | 0 | 13 (13-15) | 10393 (10393-58833) | R13,R15 |
| earn | nav | orig | 29 / 29 | 15 (12-18) | 2 | 13 | 0 | 16 (14-18) | 35666 (3911-43500) | 29 runs (see Runs per arm) |
| panel | morph.panel | base | 29 / 29 | 0 (0-1) | 0 | 0 | 0 | 0 (0-1) | 1000 (1000-1142) | 29 runs (see Runs per arm) |
| panel | morph.panel | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 (1000-1142) | R4,R7 |
| panel | morph.panel | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1005 | R42 |
| panel | morph.panel | cand:hero.exit:faithful | 5 / 5 | 0 (0-1) | 0 | 0 | 0 | 0 | 1000 (1000-1005) | R6,R8,R9,R20,R28 |
| panel | morph.panel | cand:hero.exit:scoped | 4 / 4 | 0 (0-1) | 0 | 0 | 0 | 0 | 1000 (1000-1004) | R1,R3,R17,R27 |
| panel | morph.panel | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 (0-1) | 1000 | R21,R22,R25 |
| panel | morph.panel | cand:morph.tween:waapi | 5 / 5 | 0 (0-1) | 0 | 0 | 0 | 0 (0-1) | 1000 (1000-1021) | R2,R5,R19,R24,R39 |
| panel | morph.panel | cand:morph.tween:waapi-scoped | 2 / 2 | 0 (0-1) | 0 | 0 | 0 | 0 (0-1) | 1000 (1000-1006) | R10,R12 |
| panel | morph.panel | cand:nav:earn-no-transition | 2 / 2 | 1 | 1 | 0 | 0 | 0 | 1004 (1004-1020) | R13,R15 |
| panel | morph.panel | orig | 29 / 29 | 0 (0-1) | 0 | 0 | 0 | 0 | 1004 (1000-1200) | 29 runs (see Runs per arm) |

**chromium 1280px, end-open, ideal line**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nav | nav | base | 29 / 29 | 11 (10-13) | 8 | 2 | 0 | 1 (0-1) | 2175 (1524-2859) | 29 runs (see Runs per arm) |
| nav | nav | cand:?preset=v2-proved | 2 / 2 | 11 | 8 | 3 | 0 | 1 | 1939 (1939-2130) | R4,R7 |
| nav | nav | cand:hero:scene-pause | 1 / 1 | 11 | 8 | 3 | 0 | 1 | 1742 | R42 |
| nav | nav | cand:hero.exit:faithful | 5 / 5 | 12 (11-12) | 9 | 3 | 0 | 1 (0-1) | 2148 (2058-2492) | R6,R8,R9,R20,R28 |
| nav | nav | cand:hero.exit:scoped | 4 / 4 | 11 (11-12) | 8 | 3 | 0 | 1 | 2244 (2127-2892) | R1,R3,R17,R27 |
| nav | nav | cand:morph.tween:scroll-lock | 3 / 3 | 10 (9-12) | 8 | 2 | 0 | 1 | 2327 (2222-2355) | R21,R22,R25 |
| nav | nav | cand:morph.tween:waapi | 5 / 5 | 9 (8-12) | 8 | 1 | 0 | 0 (0-1) | 3519 (2751-3654) | R2,R5,R19,R24,R39 |
| nav | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 9 | 8 | 1 | 0 | 1 | 3233 (3233-3932) | R10,R12 |
| nav | nav | cand:nav:earn-no-transition | 2 / 2 | 10 (10-13) | 8 | 2 | 0 | 0 (0-1) | 1893 (1893-2237) | R13,R15 |
| nav | nav | orig | 29 / 29 | 11 (9-12) | 8 | 2 | 0 | 1 (0-1) | 2252 (1603-3351) | 29 runs (see Runs per arm) |
| logo | nav | base | 29 / 29 | 0 | 0 | 0 | 0 | 1 (0-1) | 1000 (999-1045) | 29 runs (see Runs per arm) |
| logo | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 1 | 1000 | R4,R7 |
| logo | nav | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 1 | 1000 | R42 |
| logo | nav | cand:hero.exit:faithful | 5 / 5 | 0 | 0 | 0 | 0 | 1 (0-1) | 1000 (999-1034) | R6,R8,R9,R20,R28 |
| logo | nav | cand:hero.exit:scoped | 4 / 4 | 0 | 0 | 0 | 0 | 1 | 1000 | R1,R3,R17,R27 |
| logo | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 1 | 1000 (999-1036) | R21,R22,R25 |
| logo | nav | cand:morph.tween:waapi | 5 / 5 | 0 | 0 | 0 | 0 | 0 (0-1) | 1000 (999-1000) | R2,R5,R19,R24,R39 |
| logo | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 0 | 0 | 0 | 0 | 1 | 999 | R10,R12 |
| logo | nav | cand:nav:earn-no-transition | 2 / 2 | 0 | 0 | 0 | 0 | 0 (0-1) | 999 (999-1000) | R13,R15 |
| logo | nav | orig | 29 / 29 | 0 | 0 | 0 | 0 | 1 (0-1) | 1000 (999-1056) | 29 runs (see Runs per arm) |
| actions | nav | base | 29 / 29 | 14 (13-15) | 11 | 3 | 0 | 0 | 2452 (1896-4021) | 29 runs (see Runs per arm) |
| actions | nav | cand:?preset=v2-proved | 2 / 2 | 13 (13-14) | 10 | 3 | 0 | 0 | 1960 (1960-2317) | R4,R7 |
| actions | nav | cand:hero:scene-pause | 1 / 1 | 13 | 10 | 3 | 0 | 0 | 2309 | R42 |
| actions | nav | cand:hero.exit:faithful | 5 / 5 | 15 (14-15) | 12 | 3 | 0 | 0 | 2454 (2188-2477) | R6,R8,R9,R20,R28 |
| actions | nav | cand:hero.exit:scoped | 4 / 4 | 14 (14-15) | 11 | 3 | 0 | 0 | 2283 (2203-2469) | R1,R3,R17,R27 |
| actions | nav | cand:morph.tween:scroll-lock | 3 / 3 | 13 (13-15) | 10 | 3 | 0 | 0 | 2222 (2081-2595) | R21,R22,R25 |
| actions | nav | cand:morph.tween:waapi | 5 / 5 | 14 (12-15) | 12 | 2 | 0 | 0 | 4009 (2294-4154) | R2,R5,R19,R24,R39 |
| actions | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 13 (13-14) | 11 | 2 | 0 | 0 | 3685 (3685-4485) | R10,R12 |
| actions | nav | cand:nav:earn-no-transition | 2 / 2 | 14 (14-15) | 11 | 3 | 0 | 0 | 2175 (2175-2712) | R13,R15 |
| actions | nav | orig | 29 / 29 | 14 (12-15) | 11 | 3 | 0 | 0 | 2463 (2017-4571) | 29 runs (see Runs per arm) |
| earn | nav | base | 29 / 29 | 15 (13-17) | 11 | 4 | 0 | 3 (2-4) | 2790 (1896-4021) | 29 runs (see Runs per arm) |
| earn | nav | cand:?preset=v2-proved | 2 / 2 | 14 (14-15) | 10 | 4 | 0 | 3 | 2232 (2232-2993) | R4,R7 |
| earn | nav | cand:hero:scene-pause | 1 / 1 | 14 | 10 | 4 | 0 | 3 | 2741 | R42 |
| earn | nav | cand:hero.exit:faithful | 5 / 5 | 16 (15-16) | 12 | 4 | 0 | 3 (3-4) | 2491 (2394-3404) | R6,R8,R9,R20,R28 |
| earn | nav | cand:hero.exit:scoped | 4 / 4 | 15 | 11 | 4 | 0 | 3 (2-3) | 2911 (2440-3253) | R1,R3,R17,R27 |
| earn | nav | cand:morph.tween:scroll-lock | 3 / 3 | 14 (13-16) | 10 | 4 | 0 | 3 (2-3) | 2724 (2208-3233) | R21,R22,R25 |
| earn | nav | cand:morph.tween:waapi | 5 / 5 | 15 (13-16) | 12 | 4 | 0 | 3 (2-3) | 4007 (2429-4207) | R2,R5,R19,R24,R39 |
| earn | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 15 | 11 | 3 | 0 | 2 | 3685 (3685-4480) | R10,R12 |
| earn | nav | cand:nav:earn-no-transition | 2 / 2 | 14 (14-15) | 11 | 3 | 0 | 0 | 2178 (2178-2713) | R13,R15 |
| earn | nav | orig | 29 / 29 | 15 (13-16) | 11 | 4 | 0 | 3 (2-4) | 2733 (2211-4572) | 29 runs (see Runs per arm) |
| panel | morph.panel | base | 29 / 29 | 10 (8-11) | 8 | 2 | 0 | 0 | 1389 (1388-1391) | 29 runs (see Runs per arm) |
| panel | morph.panel | cand:?preset=v2-proved | 2 / 2 | 9 (9-10) | 7 | 2 | 0 | 0 | 1389 (1389-1391) | R4,R7 |
| panel | morph.panel | cand:hero:scene-pause | 1 / 1 | 9 | 7 | 2 | 0 | 0 | 1389 | R42 |
| panel | morph.panel | cand:hero.exit:faithful | 5 / 5 | 10 (9-10) | 8 | 2 | 0 | 0 | 1389 (1388-1392) | R6,R8,R9,R20,R28 |
| panel | morph.panel | cand:hero.exit:scoped | 4 / 4 | 10 (9-11) | 8 | 2 | 0 | 0 | 1389 (1388-1389) | R1,R3,R17,R27 |
| panel | morph.panel | cand:morph.tween:scroll-lock | 3 / 3 | 11 (10-11) | 8 | 3 | 0 | 0 | 1389 (1388-1390) | R21,R22,R25 |
| panel | morph.panel | cand:morph.tween:waapi | 5 / 5 | 8 (6-11) | 6 | 2 | 0 | 0 | 1388 (1381-1391) | R2,R5,R19,R24,R39 |
| panel | morph.panel | cand:morph.tween:waapi-scoped | 2 / 2 | 7 (7-8) | 6 | 1 | 0 | 0 | 1388 (1388-1389) | R10,R12 |
| panel | morph.panel | cand:nav:earn-no-transition | 2 / 2 | 10 (10-12) | 7 | 3 | 0 | 0 | 1388 | R13,R15 |
| panel | morph.panel | orig | 29 / 29 | 10 (8-12) | 7 | 2 | 0 | 0 | 1389 (1142-1392) | 29 runs (see Runs per arm) |

**chromium 1280px, end-open, ideal ref**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nav | nav | base | 29 / 29 | 0 | 0 | 0 | 0 | 1 (0-1) | 1006 (1000-1036) | 29 runs (see Runs per arm) |
| nav | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 1 | 1010 (1010-1014) | R4,R7 |
| nav | nav | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 1 | 1006 | R42 |
| nav | nav | cand:hero.exit:faithful | 5 / 5 | 0 | 0 | 0 | 0 | 1 (0-1) | 1011 (1004-1025) | R6,R8,R9,R20,R28 |
| nav | nav | cand:hero.exit:scoped | 4 / 4 | 0 | 0 | 0 | 0 | 1 | 1007 (1000-1023) | R1,R3,R17,R27 |
| nav | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 1 | 1009 (1006-1024) | R21,R22,R25 |
| nav | nav | cand:morph.tween:waapi | 5 / 5 | 0 | 0 | 0 | 0 | 0 (0-1) | 1005 (1000-1008) | R2,R5,R19,R24,R39 |
| nav | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 0 | 0 | 0 | 0 | 1 | 1013 (1013-1019) | R10,R12 |
| nav | nav | cand:nav:earn-no-transition | 2 / 2 | 0 | 0 | 0 | 0 | 0 (0-1) | 1004 (1004-1006) | R13,R15 |
| nav | nav | orig | 29 / 29 | 0 | 0 | 0 | 0 | 1 (0-1) | 1012 (1000-1028) | 29 runs (see Runs per arm) |
| logo | nav | base | 29 / 29 | 0 | 0 | 0 | 0 | 1 (0-1) | 1000 (999-1004) | 29 runs (see Runs per arm) |
| logo | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 1 | 1000 | R4,R7 |
| logo | nav | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 1 | 1000 | R42 |
| logo | nav | cand:hero.exit:faithful | 5 / 5 | 0 | 0 | 0 | 0 | 1 (0-1) | 1000 (999-1001) | R6,R8,R9,R20,R28 |
| logo | nav | cand:hero.exit:scoped | 4 / 4 | 0 | 0 | 0 | 0 | 1 | 1000 (1000-1001) | R1,R3,R17,R27 |
| logo | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 1 | 1000 | R21,R22,R25 |
| logo | nav | cand:morph.tween:waapi | 5 / 5 | 0 | 0 | 0 | 0 | 0 (0-1) | 1000 (999-1000) | R2,R5,R19,R24,R39 |
| logo | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 0 | 0 | 0 | 0 | 1 | 1000 (1000-1001) | R10,R12 |
| logo | nav | cand:nav:earn-no-transition | 2 / 2 | 0 | 0 | 0 | 0 | 0 (0-1) | 1000 (1000-1002) | R13,R15 |
| logo | nav | orig | 29 / 29 | 0 | 0 | 0 | 0 | 1 (0-1) | 1000 (999-1000) | 29 runs (see Runs per arm) |
| actions | nav | base | 29 / 29 | 0 (0-2) | 0 | 0 | 0 | 0 | 1000 (998-1095) | 29 runs (see Runs per arm) |
| actions | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 999 (999-1000) | R4,R7 |
| actions | nav | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 999 | R42 |
| actions | nav | cand:hero.exit:faithful | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1000 | R6,R8,R9,R20,R28 |
| actions | nav | cand:hero.exit:scoped | 4 / 4 | 0 (0-2) | 0 | 0 | 0 | 0 | 1000 | R1,R3,R17,R27 |
| actions | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 (999-1000) | R21,R22,R25 |
| actions | nav | cand:morph.tween:waapi | 5 / 5 | 1 (0-2) | 1 | 0 | 0 | 0 | 1000 (1000-1002) | R2,R5,R19,R24,R39 |
| actions | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 1 (1-2) | 1 | 0 | 0 | 0 | 1001 (1001-1037) | R10,R12 |
| actions | nav | cand:nav:earn-no-transition | 2 / 2 | 1 | 0 | 0 | 0 | 0 | 1000 (1000-1027) | R13,R15 |
| actions | nav | orig | 29 / 29 | 0 | 0 | 0 | 0 | 0 | 1000 (999-1046) | 29 runs (see Runs per arm) |
| earn | nav | base | 29 / 29 | 1 (0-5) | 0 | 1 | 0 | 3 (2-4) | 1040 (999-1196) | 29 runs (see Runs per arm) |
| earn | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 3 | 1007 (1007-1023) | R4,R7 |
| earn | nav | cand:hero:scene-pause | 1 / 1 | 1 | 0 | 1 | 0 | 3 | 1071 | R42 |
| earn | nav | cand:hero.exit:faithful | 5 / 5 | 1 (1-2) | 0 | 1 | 0 | 3 (3-4) | 1003 (1000-1048) | R6,R8,R9,R20,R28 |
| earn | nav | cand:hero.exit:scoped | 4 / 4 | 1 (1-2) | 0 | 1 | 0 | 3 (2-3) | 1044 (1000-1072) | R1,R3,R17,R27 |
| earn | nav | cand:morph.tween:scroll-lock | 3 / 3 | 1 (1-2) | 0 | 1 | 0 | 3 (2-3) | 1000 (1000-1091) | R21,R22,R25 |
| earn | nav | cand:morph.tween:waapi | 5 / 5 | 2 (1-3) | 1 | 1 | 0 | 3 (2-3) | 1049 (1000-1145) | R2,R5,R19,R24,R39 |
| earn | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 2 | 1 | 1 | 0 | 2 | 1047 (1047-1057) | R10,R12 |
| earn | nav | cand:nav:earn-no-transition | 2 / 2 | 16 (16-18) | 13 | 3 | 0 | 0 | 1612 (1612-2030) | R13,R15 |
| earn | nav | orig | 29 / 29 | 1 (0-3) | 0 | 1 | 0 | 3 (2-4) | 1052 (1000-1200) | 29 runs (see Runs per arm) |
| panel | morph.panel | base | 29 / 29 | 0 (0-2) | 0 | 0 | 0 | 0 | 1000 (1000-1166) | 29 runs (see Runs per arm) |
| panel | morph.panel | cand:?preset=v2-proved | 2 / 2 | 1 | 1 | 0 | 0 | 0 | 1000 | R4,R7 |
| panel | morph.panel | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1000 | R42 |
| panel | morph.panel | cand:hero.exit:faithful | 5 / 5 | 0 (0-2) | 0 | 0 | 0 | 0 | 1000 (1000-1004) | R6,R8,R9,R20,R28 |
| panel | morph.panel | cand:hero.exit:scoped | 4 / 4 | 0 (0-1) | 0 | 0 | 0 | 0 | 1000 (1000-1166) | R1,R3,R17,R27 |
| panel | morph.panel | cand:morph.tween:scroll-lock | 3 / 3 | 1 (0-1) | 1 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| panel | morph.panel | cand:morph.tween:waapi | 5 / 5 | 0 (0-1) | 0 | 0 | 0 | 0 | 1000 | R2,R5,R19,R24,R39 |
| panel | morph.panel | cand:morph.tween:waapi-scoped | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R10,R12 |
| panel | morph.panel | cand:nav:earn-no-transition | 2 / 2 | 0 (0-1) | 0 | 0 | 0 | 0 | 1003 (1003-1004) | R13,R15 |
| panel | morph.panel | orig | 29 / 29 | 1 (0-1) | 1 | 0 | 0 | 0 | 1003 (1000-1166) | 29 runs (see Runs per arm) |

**chromium 1280px, hero, ideal line**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero.track | hero.exit | base | 29 / 29 | 0 | 0 | 0 | 0 | 0 | 1000 | 29 runs (see Runs per arm) |
| hero.track | hero.exit | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.track | hero.exit | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1000 | R42 |
| hero.track | hero.exit | cand:hero.exit:faithful | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1000 | R6,R8,R9,R20,R28 |
| hero.track | hero.exit | cand:hero.exit:scoped | 4 / 4 | 0 | 0 | 0 | 0 | 0 | 1000 | R1,R3,R17,R27 |
| hero.track | hero.exit | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.track | hero.exit | cand:morph.tween:waapi | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1000 | R2,R5,R19,R24,R39 |
| hero.track | hero.exit | cand:morph.tween:waapi-scoped | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R10,R12 |
| hero.track | hero.exit | cand:nav:earn-no-transition | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R13,R15 |
| hero.track | hero.exit | orig | 29 / 29 | 0 | 0 | 0 | 0 | 0 | 1000 | 29 runs (see Runs per arm) |
| hero.stage | hero.exit | base | 29 / 29 | 0 | 0 | 0 | 0 | 0 | 1099 (1099-1138) | 29 runs (see Runs per arm) |
| hero.stage | hero.exit | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R4,R7 |
| hero.stage | hero.exit | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1138 | R42 |
| hero.stage | hero.exit | cand:hero.exit:faithful | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1138 (1099-1138) | R6,R8,R9,R20,R28 |
| hero.stage | hero.exit | cand:hero.exit:scoped | 4 / 4 | 0 | 0 | 0 | 0 | 0 | 1099 (1099-1138) | R1,R3,R17,R27 |
| hero.stage | hero.exit | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1138 | R21,R22,R25 |
| hero.stage | hero.exit | cand:morph.tween:waapi | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1138 (1099-1138) | R2,R5,R19,R24,R39 |
| hero.stage | hero.exit | cand:morph.tween:waapi-scoped | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R10,R12 |
| hero.stage | hero.exit | cand:nav:earn-no-transition | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R13,R15 |
| hero.stage | hero.exit | orig | 29 / 29 | 0 | 0 | 0 | 0 | 0 | 1138 | 29 runs (see Runs per arm) |
| hero.copy | hero | base | 29 / 29 | 2 (1-2) | 1 | 1 | 0 | 0 | 2000 (1137-2000) | 29 runs (see Runs per arm) |
| hero.copy | hero | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1015 | R4,R7 |
| hero.copy | hero | cand:hero:scene-pause | 1 / 1 | 1 | 1 | 0 | 0 | 0 | 1137 | R42 |
| hero.copy | hero | cand:hero.exit:faithful | 5 / 5 | 1 (1-2) | 1 | 0 | 0 | 0 | 1137 (1137-2000) | R6,R8,R9,R20,R28 |
| hero.copy | hero | cand:hero.exit:scoped | 4 / 4 | 2 (1-2) | 1 | 1 | 0 | 0 | 2000 (1137-2000) | R1,R3,R17,R27 |
| hero.copy | hero | cand:morph.tween:scroll-lock | 3 / 3 | 2 (1-2) | 1 | 1 | 0 | 0 | 2000 (1137-2000) | R21,R22,R25 |
| hero.copy | hero | cand:morph.tween:waapi | 5 / 5 | 1 (1-2) | 1 | 0 | 0 | 0 | 1137 (1137-2000) | R2,R5,R19,R24,R39 |
| hero.copy | hero | cand:morph.tween:waapi-scoped | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 2000 | R10,R12 |
| hero.copy | hero | cand:nav:earn-no-transition | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 2000 | R13,R15 |
| hero.copy | hero | orig | 29 / 29 | 1 (1-2) | 1 | 0 | 0 | 0 | 1137 (1137-2000) | 29 runs (see Runs per arm) |
| hero.cta | hero | base | 29 / 29 | 2 (0-2) | 1 | 1 | 0 | 0 | 1966 (1137-1966) | 29 runs (see Runs per arm) |
| hero.cta | hero | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.cta | hero | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1137 | R42 |
| hero.cta | hero | cand:hero.exit:faithful | 5 / 5 | 0 (0-2) | 0 | 0 | 0 | 0 | 1137 (1137-1966) | R6,R8,R9,R20,R28 |
| hero.cta | hero | cand:hero.exit:scoped | 4 / 4 | 2 (0-2) | 1 | 1 | 0 | 0 | 1966 (1137-1966) | R1,R3,R17,R27 |
| hero.cta | hero | cand:morph.tween:scroll-lock | 3 / 3 | 2 (0-2) | 1 | 1 | 0 | 0 | 1941 (1137-1941) | R21,R22,R25 |
| hero.cta | hero | cand:morph.tween:waapi | 5 / 5 | 0 (0-2) | 0 | 0 | 0 | 0 | 1137 (1137-1966) | R2,R5,R19,R24,R39 |
| hero.cta | hero | cand:morph.tween:waapi-scoped | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 1966 | R10,R12 |
| hero.cta | hero | cand:nav:earn-no-transition | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 1966 | R13,R15 |
| hero.cta | hero | orig | 29 / 29 | 0 (0-2) | 0 | 0 | 0 | 0 | 1137 (1137-1941) | 29 runs (see Runs per arm) |
| hero.countdown.unit | hero.countdown | base | 29 / 29 | 2 (0-2) | 1 | 1 | 0 | 0 | 1966 (1137-1966) | 29 runs (see Runs per arm) |
| hero.countdown.unit | hero.countdown | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.countdown.unit | hero.countdown | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1137 | R42 |
| hero.countdown.unit | hero.countdown | cand:hero.exit:faithful | 5 / 5 | 0 (0-2) | 0 | 0 | 0 | 0 | 1137 (1137-1966) | R6,R8,R9,R20,R28 |
| hero.countdown.unit | hero.countdown | cand:hero.exit:scoped | 4 / 4 | 2 (0-2) | 1 | 1 | 0 | 0 | 1966 (1137-1966) | R1,R3,R17,R27 |
| hero.countdown.unit | hero.countdown | cand:morph.tween:scroll-lock | 3 / 3 | 2 (0-2) | 1 | 1 | 0 | 0 | 1941 (1137-1941) | R21,R22,R25 |
| hero.countdown.unit | hero.countdown | cand:morph.tween:waapi | 5 / 5 | 0 (0-2) | 0 | 0 | 0 | 0 | 1137 (1137-1966) | R2,R5,R19,R24,R39 |
| hero.countdown.unit | hero.countdown | cand:morph.tween:waapi-scoped | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 1966 | R10,R12 |
| hero.countdown.unit | hero.countdown | cand:nav:earn-no-transition | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 1966 | R13,R15 |
| hero.countdown.unit | hero.countdown | orig | 29 / 29 | 0 (0-2) | 0 | 0 | 0 | 0 | 1137 (1137-1941) | 29 runs (see Runs per arm) |
| hero.cue | hero.cue | base | 29 / 29 | 2 (1-2) | 1 | 1 | 0 | 0 | 2000 (1138-2000) | 29 runs (see Runs per arm) |
| hero.cue | hero.cue | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1015 | R4,R7 |
| hero.cue | hero.cue | cand:hero:scene-pause | 1 / 1 | 1 | 1 | 0 | 0 | 0 | 1138 | R42 |
| hero.cue | hero.cue | cand:hero.exit:faithful | 5 / 5 | 1 (1-2) | 1 | 0 | 0 | 0 | 1138 (1138-2000) | R6,R8,R9,R20,R28 |
| hero.cue | hero.cue | cand:hero.exit:scoped | 4 / 4 | 2 (1-2) | 1 | 1 | 0 | 0 | 2000 (1138-2000) | R1,R3,R17,R27 |
| hero.cue | hero.cue | cand:morph.tween:scroll-lock | 3 / 3 | 2 (1-2) | 1 | 1 | 0 | 0 | 2000 (1138-2000) | R21,R22,R25 |
| hero.cue | hero.cue | cand:morph.tween:waapi | 5 / 5 | 1 (1-2) | 1 | 0 | 0 | 0 | 1138 (1138-2000) | R2,R5,R19,R24,R39 |
| hero.cue | hero.cue | cand:morph.tween:waapi-scoped | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 2000 | R10,R12 |
| hero.cue | hero.cue | cand:nav:earn-no-transition | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 2000 | R13,R15 |
| hero.cue | hero.cue | orig | 29 / 29 | 1 (1-2) | 1 | 0 | 0 | 0 | 1138 (1138-2000) | 29 runs (see Runs per arm) |
| hero.orbit | hero.orbit | base | 29 / 29 | 0 | 0 | 0 | 0 | 0 | 1099 (1099-1138) | 29 runs (see Runs per arm) |
| hero.orbit | hero.orbit | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R4,R7 |
| hero.orbit | hero.orbit | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1138 | R42 |
| hero.orbit | hero.orbit | cand:hero.exit:faithful | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1138 (1099-1138) | R6,R8,R9,R20,R28 |
| hero.orbit | hero.orbit | cand:hero.exit:scoped | 4 / 4 | 0 | 0 | 0 | 0 | 0 | 1099 (1099-1138) | R1,R3,R17,R27 |
| hero.orbit | hero.orbit | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1138 | R21,R22,R25 |
| hero.orbit | hero.orbit | cand:morph.tween:waapi | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1138 (1099-1138) | R2,R5,R19,R24,R39 |
| hero.orbit | hero.orbit | cand:morph.tween:waapi-scoped | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R10,R12 |
| hero.orbit | hero.orbit | cand:nav:earn-no-transition | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R13,R15 |
| hero.orbit | hero.orbit | orig | 29 / 29 | 0 | 0 | 0 | 0 | 0 | 1138 | 29 runs (see Runs per arm) |
| hero.orbit.stage | hero.orbit | base | 29 / 29 | 0 | 0 | 0 | 0 | 0 | 1099 (1099-1138) | 29 runs (see Runs per arm) |
| hero.orbit.stage | hero.orbit | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R4,R7 |
| hero.orbit.stage | hero.orbit | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1138 | R42 |
| hero.orbit.stage | hero.orbit | cand:hero.exit:faithful | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1138 (1099-1138) | R6,R8,R9,R20,R28 |
| hero.orbit.stage | hero.orbit | cand:hero.exit:scoped | 4 / 4 | 0 | 0 | 0 | 0 | 0 | 1099 (1099-1138) | R1,R3,R17,R27 |
| hero.orbit.stage | hero.orbit | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1138 | R21,R22,R25 |
| hero.orbit.stage | hero.orbit | cand:morph.tween:waapi | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1138 (1099-1138) | R2,R5,R19,R24,R39 |
| hero.orbit.stage | hero.orbit | cand:morph.tween:waapi-scoped | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R10,R12 |
| hero.orbit.stage | hero.orbit | cand:nav:earn-no-transition | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R13,R15 |
| hero.orbit.stage | hero.orbit | orig | 29 / 29 | 0 | 0 | 0 | 0 | 0 | 1138 | 29 runs (see Runs per arm) |
| hero.orbit.card | hero.orbit | base | 29 / 29 | 2 | 1 | 1 | 0 | 0 | 1982 (1191-2000) | 29 runs (see Runs per arm) |
| hero.orbit.card | hero.orbit | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.orbit.card | hero.orbit | cand:hero:scene-pause | 1 / 1 | 2 | 1 | 1 | 0 | 0 | 1191 | R42 |
| hero.orbit.card | hero.orbit | cand:hero.exit:faithful | 5 / 5 | 2 | 1 | 1 | 0 | 0 | 1191 (1191-1982) | R6,R8,R9,R20,R28 |
| hero.orbit.card | hero.orbit | cand:hero.exit:scoped | 4 / 4 | 2 | 1 | 1 | 0 | 0 | 1982 (1191-1982) | R1,R3,R17,R27 |
| hero.orbit.card | hero.orbit | cand:morph.tween:scroll-lock | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 2000 (1191-2000) | R21,R22,R25 |
| hero.orbit.card | hero.orbit | cand:morph.tween:waapi | 5 / 5 | 2 | 1 | 1 | 0 | 0 | 1191 (1191-1982) | R2,R5,R19,R24,R39 |
| hero.orbit.card | hero.orbit | cand:morph.tween:waapi-scoped | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 1982 | R10,R12 |
| hero.orbit.card | hero.orbit | cand:nav:earn-no-transition | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 1982 | R13,R15 |
| hero.orbit.card | hero.orbit | orig | 29 / 29 | 2 | 1 | 1 | 0 | 0 | 1191 (1191-2000) | 29 runs (see Runs per arm) |
| hero.deck.card | hero.deck | base | 29 / 29 | 2 | 1 | 1 | 0 | 0 | 2000 (1000-2000) | 29 runs (see Runs per arm) |
| hero.deck.card | hero.deck | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.deck.card | hero.deck | cand:hero:scene-pause | 1 / 1 | 2 | 1 | 1 | 0 | 0 | 1000 | R42 |
| hero.deck.card | hero.deck | cand:hero.exit:faithful | 5 / 5 | 2 | 1 | 1 | 0 | 0 | 1000 (1000-2000) | R6,R8,R9,R20,R28 |
| hero.deck.card | hero.deck | cand:hero.exit:scoped | 4 / 4 | 2 | 1 | 1 | 0 | 0 | 2000 (1000-2000) | R1,R3,R17,R27 |
| hero.deck.card | hero.deck | cand:morph.tween:scroll-lock | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.deck.card | hero.deck | cand:morph.tween:waapi | 5 / 5 | 2 | 1 | 1 | 0 | 0 | 1000 (1000-2000) | R2,R5,R19,R24,R39 |
| hero.deck.card | hero.deck | cand:morph.tween:waapi-scoped | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 2000 | R10,R12 |
| hero.deck.card | hero.deck | cand:nav:earn-no-transition | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 2000 | R13,R15 |
| hero.deck.card | hero.deck | orig | 29 / 29 | 2 | 1 | 1 | 0 | 0 | 1000 | 29 runs (see Runs per arm) |

**chromium 1280px, hero, ideal ref**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero.track | hero.exit | base | 29 / 29 | 4 (0-4) | 0 | 4 | 0 | 0 | 19000 (0-19000) | 29 runs (see Runs per arm) |
| hero.track | hero.exit | cand:?preset=v2-proved | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 19000 | R4,R7 |
| hero.track | hero.exit | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1000 | R42 |
| hero.track | hero.exit | cand:hero.exit:faithful | 5 / 5 | 0 (0-4) | 0 | 0 | 0 | 0 | 1000 (1000-19000) | R6,R8,R9,R20,R28 |
| hero.track | hero.exit | cand:hero.exit:scoped | 4 / 4 | 4 (0-4) | 0 | 4 | 0 | 0 | 19000 (1000-19000) | R1,R3,R17,R27 |
| hero.track | hero.exit | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.track | hero.exit | cand:morph.tween:waapi | 5 / 5 | 0 (0-4) | 0 | 0 | 0 | 0 | 1000 (0-19000) | R2,R5,R19,R24,R39 |
| hero.track | hero.exit | cand:morph.tween:waapi-scoped | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 19000 | R10,R12 |
| hero.track | hero.exit | cand:nav:earn-no-transition | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 19000 | R13,R15 |
| hero.stage | hero.exit | base | 29 / 29 | 4 (0-4) | 0 | 4 | 0 | 0 | 461000 (1000-461000) | 29 runs (see Runs per arm) |
| hero.stage | hero.exit | cand:?preset=v2-proved | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 461000 | R4,R7 |
| hero.stage | hero.exit | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1000 | R42 |
| hero.stage | hero.exit | cand:hero.exit:faithful | 5 / 5 | 0 (0-4) | 0 | 0 | 0 | 0 | 1000 (1000-461000) | R6,R8,R9,R20,R28 |
| hero.stage | hero.exit | cand:hero.exit:scoped | 4 / 4 | 4 (0-4) | 0 | 4 | 0 | 0 | 461000 (1000-461000) | R1,R3,R17,R27 |
| hero.stage | hero.exit | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.stage | hero.exit | cand:morph.tween:waapi | 5 / 5 | 0 (0-4) | 0 | 0 | 0 | 0 | 1000 (1000-461000) | R2,R5,R19,R24,R39 |
| hero.stage | hero.exit | cand:morph.tween:waapi-scoped | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 461000 | R10,R12 |
| hero.stage | hero.exit | cand:nav:earn-no-transition | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 461000 | R13,R15 |
| hero.copy | hero | base | 29 / 29 | 3 (0-3) | 0 | 3 | 0 | 0 | 18833 (0-18833) | 29 runs (see Runs per arm) |
| hero.copy | hero | cand:?preset=v2-proved | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 9500 | R4,R7 |
| hero.copy | hero | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1000 | R42 |
| hero.copy | hero | cand:hero.exit:faithful | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-18833) | R6,R8,R9,R20,R28 |
| hero.copy | hero | cand:hero.exit:scoped | 4 / 4 | 3 (0-3) | 0 | 3 | 0 | 0 | 18833 (1000-18833) | R1,R3,R17,R27 |
| hero.copy | hero | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.copy | hero | cand:morph.tween:waapi | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (0-18833) | R2,R5,R19,R24,R39 |
| hero.copy | hero | cand:morph.tween:waapi-scoped | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 18833 | R10,R12 |
| hero.copy | hero | cand:nav:earn-no-transition | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 18833 | R13,R15 |
| hero.cta | hero | base | 29 / 29 | 3 (0-3) | 0 | 3 | 0 | 0 | 19015 (0-19015) | 29 runs (see Runs per arm) |
| hero.cta | hero | cand:?preset=v2-proved | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 9590 | R4,R7 |
| hero.cta | hero | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1000 | R42 |
| hero.cta | hero | cand:hero.exit:faithful | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-19015) | R6,R8,R9,R20,R28 |
| hero.cta | hero | cand:hero.exit:scoped | 4 / 4 | 3 (0-3) | 0 | 3 | 0 | 0 | 19015 (1000-19015) | R1,R3,R17,R27 |
| hero.cta | hero | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.cta | hero | cand:morph.tween:waapi | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (0-19015) | R2,R5,R19,R24,R39 |
| hero.cta | hero | cand:morph.tween:waapi-scoped | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 19015 | R10,R12 |
| hero.cta | hero | cand:nav:earn-no-transition | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 19015 | R13,R15 |
| hero.countdown.unit | hero.countdown | base | 29 / 29 | 3 (0-3) | 0 | 3 | 0 | 0 | 19015 (0-19015) | 29 runs (see Runs per arm) |
| hero.countdown.unit | hero.countdown | cand:?preset=v2-proved | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 9590 | R4,R7 |
| hero.countdown.unit | hero.countdown | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1000 | R42 |
| hero.countdown.unit | hero.countdown | cand:hero.exit:faithful | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-19015) | R6,R8,R9,R20,R28 |
| hero.countdown.unit | hero.countdown | cand:hero.exit:scoped | 4 / 4 | 3 (0-3) | 0 | 3 | 0 | 0 | 19015 (1000-19015) | R1,R3,R17,R27 |
| hero.countdown.unit | hero.countdown | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.countdown.unit | hero.countdown | cand:morph.tween:waapi | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (0-19015) | R2,R5,R19,R24,R39 |
| hero.countdown.unit | hero.countdown | cand:morph.tween:waapi-scoped | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 19015 | R10,R12 |
| hero.countdown.unit | hero.countdown | cand:nav:earn-no-transition | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 19015 | R13,R15 |
| hero.cue | hero.cue | base | 29 / 29 | 3 (0-3) | 0 | 3 | 0 | 0 | 18833 (0-18833) | 29 runs (see Runs per arm) |
| hero.cue | hero.cue | cand:?preset=v2-proved | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 9500 | R4,R7 |
| hero.cue | hero.cue | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1000 | R42 |
| hero.cue | hero.cue | cand:hero.exit:faithful | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-18833) | R6,R8,R9,R20,R28 |
| hero.cue | hero.cue | cand:hero.exit:scoped | 4 / 4 | 3 (0-3) | 0 | 3 | 0 | 0 | 18833 (1000-18833) | R1,R3,R17,R27 |
| hero.cue | hero.cue | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.cue | hero.cue | cand:morph.tween:waapi | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (0-18833) | R2,R5,R19,R24,R39 |
| hero.cue | hero.cue | cand:morph.tween:waapi-scoped | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 18833 | R10,R12 |
| hero.cue | hero.cue | cand:nav:earn-no-transition | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 18833 | R13,R15 |
| hero.orbit | hero.orbit | base | 29 / 29 | 4 (0-4) | 0 | 4 | 0 | 0 | 461000 (1000-461000) | 29 runs (see Runs per arm) |
| hero.orbit | hero.orbit | cand:?preset=v2-proved | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 461000 | R4,R7 |
| hero.orbit | hero.orbit | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1000 | R42 |
| hero.orbit | hero.orbit | cand:hero.exit:faithful | 5 / 5 | 0 (0-4) | 0 | 0 | 0 | 0 | 1000 (1000-461000) | R6,R8,R9,R20,R28 |
| hero.orbit | hero.orbit | cand:hero.exit:scoped | 4 / 4 | 4 (0-4) | 0 | 4 | 0 | 0 | 461000 (1000-461000) | R1,R3,R17,R27 |
| hero.orbit | hero.orbit | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.orbit | hero.orbit | cand:morph.tween:waapi | 5 / 5 | 0 (0-4) | 0 | 0 | 0 | 0 | 1000 (1000-461000) | R2,R5,R19,R24,R39 |
| hero.orbit | hero.orbit | cand:morph.tween:waapi-scoped | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 461000 | R10,R12 |
| hero.orbit | hero.orbit | cand:nav:earn-no-transition | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 461000 | R13,R15 |
| hero.orbit.stage | hero.orbit | base | 29 / 29 | 4 (0-4) | 0 | 4 | 0 | 0 | 461000 (1000-461000) | 29 runs (see Runs per arm) |
| hero.orbit.stage | hero.orbit | cand:?preset=v2-proved | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 461000 | R4,R7 |
| hero.orbit.stage | hero.orbit | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1000 | R42 |
| hero.orbit.stage | hero.orbit | cand:hero.exit:faithful | 5 / 5 | 0 (0-4) | 0 | 0 | 0 | 0 | 1000 (1000-461000) | R6,R8,R9,R20,R28 |
| hero.orbit.stage | hero.orbit | cand:hero.exit:scoped | 4 / 4 | 4 (0-4) | 0 | 4 | 0 | 0 | 461000 (1000-461000) | R1,R3,R17,R27 |
| hero.orbit.stage | hero.orbit | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.orbit.stage | hero.orbit | cand:morph.tween:waapi | 5 / 5 | 0 (0-4) | 0 | 0 | 0 | 0 | 1000 (1000-461000) | R2,R5,R19,R24,R39 |
| hero.orbit.stage | hero.orbit | cand:morph.tween:waapi-scoped | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 461000 | R10,R12 |
| hero.orbit.stage | hero.orbit | cand:nav:earn-no-transition | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 461000 | R13,R15 |
| hero.orbit.card | hero.orbit | base | 29 / 29 | 3 (0-3) | 0 | 3 | 0 | 0 | 22000 (0-22000) | 29 runs (see Runs per arm) |
| hero.orbit.card | hero.orbit | cand:?preset=v2-proved | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 11000 | R4,R7 |
| hero.orbit.card | hero.orbit | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1000 | R42 |
| hero.orbit.card | hero.orbit | cand:hero.exit:faithful | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-22000) | R6,R8,R9,R20,R28 |
| hero.orbit.card | hero.orbit | cand:hero.exit:scoped | 4 / 4 | 3 (0-3) | 0 | 3 | 0 | 0 | 22000 (1000-22000) | R1,R3,R17,R27 |
| hero.orbit.card | hero.orbit | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.orbit.card | hero.orbit | cand:morph.tween:waapi | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (0-22000) | R2,R5,R19,R24,R39 |
| hero.orbit.card | hero.orbit | cand:morph.tween:waapi-scoped | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 22000 | R10,R12 |
| hero.orbit.card | hero.orbit | cand:nav:earn-no-transition | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 22000 | R13,R15 |
| hero.deck.card | hero.deck | base | 29 / 29 | 3 (0-3) | 0 | 3 | 0 | 0 | 22000 (0-22000) | 29 runs (see Runs per arm) |
| hero.deck.card | hero.deck | cand:?preset=v2-proved | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 11000 | R4,R7 |
| hero.deck.card | hero.deck | cand:hero:scene-pause | 1 / 1 | 0 | 0 | 0 | 0 | 0 | 1000 | R42 |
| hero.deck.card | hero.deck | cand:hero.exit:faithful | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-22000) | R6,R8,R9,R20,R28 |
| hero.deck.card | hero.deck | cand:hero.exit:scoped | 4 / 4 | 3 (0-3) | 0 | 3 | 0 | 0 | 22000 (1000-22000) | R1,R3,R17,R27 |
| hero.deck.card | hero.deck | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.deck.card | hero.deck | cand:morph.tween:waapi | 5 / 5 | 2 (0-3) | 0 | 0 | 0 | 0 | 1000 (0-22000) | R2,R5,R19,R24,R39 |
| hero.deck.card | hero.deck | cand:morph.tween:waapi-scoped | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 22000 | R10,R12 |
| hero.deck.card | hero.deck | cand:nav:earn-no-transition | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 22000 | R13,R15 |

**chromium 390px, end-close, ideal line**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nav | nav | base | 33 / 33 | 8 (6-9) | 6 | 1 | 1 | 19 (19-20) | 7717 (1000-14454) | 33 runs (see Runs per arm) |
| nav | nav | cand:?preset=v2-proved | 2 / 2 | 8 (8-9) | 6 | 1 | 1 | 19 | 9952 (9952-14473) | R4,R7 |
| nav | nav | cand:hero:scene-pause | 3 / 3 | 7 (6-7) | 6 | 1 | 0 | 20 | 1008 (1007-1008) | R42,R43,R44 |
| nav | nav | cand:hero.exit:faithful | 5 / 5 | 9 (7-9) | 6 | 2 | 1 | 19 (19-20) | 9942 (1188-9969) | R6,R8,R9,R20,R28 |
| nav | nav | cand:hero.exit:scoped | 5 / 5 | 8 (7-9) | 6 | 1 | 1 | 19 (19-20) | 7717 (1008-9952) | R1,R3,R17,R27,R40 |
| nav | nav | cand:morph.tween:scroll-lock | 3 / 3 | 8 (7-9) | 6 | 1 | 1 | 20 | 9962 (1119-14453) | R21,R22,R25 |
| nav | nav | cand:morph.tween:waapi | 5 / 5 | 7 (5-7) | 5 | 2 | 0 | 1 (1-20) | 1000 (1000-1017) | R2,R5,R19,R24,R39 |
| nav | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 6 | 5 | 1 | 0 | 1 | 1000 (1000-1017) | R10,R12 |
| nav | nav | cand:nav:earn-no-transition | 2 / 2 | 9 | 6 | 2 | 1 | 19 (19-20) | 7721 (7721-7728) | R13,R15 |
| nav | nav | orig | 33 / 33 | 8 (6-9) | 6 | 1 | 1 | 20 (19-20) | 7734 (1006-14454) | 33 runs (see Runs per arm) |
| logo | nav | base | 33 / 33 | 29 (24-33) | 24 | 6 | 0 | 0 | 8732 (6779-12705) | 33 runs (see Runs per arm) |
| logo | nav | cand:?preset=v2-proved | 2 / 2 | 26 (26-27) | 25 | 1 | 0 | 0 | 8749 (8749-12721) | R4,R7 |
| logo | nav | cand:hero:scene-pause | 3 / 3 | 31 (31-33) | 24 | 7 | 0 | 0 | 6793 (6793-8764) | R42,R43,R44 |
| logo | nav | cand:hero.exit:faithful | 5 / 5 | 30 (25-32) | 25 | 6 | 0 | 0 | 8749 (8732-12724) | R6,R8,R9,R20,R28 |
| logo | nav | cand:hero.exit:scoped | 5 / 5 | 27 (24-31) | 25 | 1 | 0 | 0 | 8749 (6784-12689) | R1,R3,R17,R27,R40 |
| logo | nav | cand:morph.tween:scroll-lock | 3 / 3 | 32 (31-33) | 25 | 7 | 0 | 0 | 12705 (8756-12724) | R21,R22,R25 |
| logo | nav | cand:morph.tween:waapi | 5 / 5 | 27 (22-30) | 21 | 6 | 0 | 0 | 7142 (6369-7518) | R2,R5,R19,R24,R39 |
| logo | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 23 (23-24) | 22 | 1 | 0 | 0 | 6365 (6365-7518) | R10,R12 |
| logo | nav | cand:nav:earn-no-transition | 2 / 2 | 25 (25-26) | 24 | 1 | 0 | 0 | 6788 (6788-6793) | R13,R15 |
| logo | nav | orig | 33 / 33 | 31 (29-33) | 25 | 7 | 0 | 0 | 8740 (6784-12721) | 33 runs (see Runs per arm) |
| actions | nav | base | 33 / 33 | 19 (18-21) | 13 | 6 | 0 | 16 (16-17) | 1842 (1304-2685) | 33 runs (see Runs per arm) |
| actions | nav | cand:?preset=v2-proved | 2 / 2 | 19 (19-20) | 14 | 5 | 0 | 16 | 1840 (1840-2894) | R4,R7 |
| actions | nav | cand:hero:scene-pause | 3 / 3 | 18 (18-20) | 13 | 5 | 0 | 16 (16-17) | 1570 (1570-2026) | R42,R43,R44 |
| actions | nav | cand:hero.exit:faithful | 5 / 5 | 19 (19-20) | 14 | 6 | 0 | 16 | 2013 (1524-2690) | R6,R8,R9,R20,R28 |
| actions | nav | cand:hero.exit:scoped | 5 / 5 | 19 (18-20) | 13 | 6 | 0 | 16 (16-17) | 1864 (1565-2676) | R1,R3,R17,R27,R40 |
| actions | nav | cand:morph.tween:scroll-lock | 3 / 3 | 20 | 14 | 6 | 0 | 16 | 2679 (1849-2923) | R21,R22,R25 |
| actions | nav | cand:morph.tween:waapi | 5 / 5 | 17 (16-18) | 10 | 6 | 0 | 12 (12-17) | 1237 (1103-1724) | R2,R5,R19,R24,R39 |
| actions | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 17 | 11 | 5 | 0 | 12 | 1422 (1422-1727) | R10,R12 |
| actions | nav | cand:nav:earn-no-transition | 2 / 2 | 18 | 13 | 5 | 0 | 16 (16-17) | 1564 (1564-1686) | R13,R15 |
| actions | nav | orig | 33 / 33 | 19 (17-21) | 14 | 6 | 0 | 16 (16-17) | 1673 (1183-2452) | 33 runs (see Runs per arm) |
| earn | nav | base | 33 / 33 | 32 (31-35) | 24 | 8 | 0 | 20 | 1842 (1305-2687) | 33 runs (see Runs per arm) |
| earn | nav | cand:?preset=v2-proved | 2 / 2 | 33 (33-34) | 25 | 8 | 0 | 20 | 1841 (1841-2898) | R4,R7 |
| earn | nav | cand:hero:scene-pause | 3 / 3 | 32 (32-35) | 24 | 8 | 0 | 20 | 1571 (1571-2028) | R42,R43,R44 |
| earn | nav | cand:hero.exit:faithful | 5 / 5 | 33 (32-34) | 25 | 8 | 0 | 20 | 2015 (1524-2691) | R6,R8,R9,R20,R28 |
| earn | nav | cand:hero.exit:scoped | 5 / 5 | 33 (31-34) | 25 | 8 | 0 | 20 | 1866 (1565-2674) | R1,R3,R17,R27,R40 |
| earn | nav | cand:morph.tween:scroll-lock | 3 / 3 | 34 (33-34) | 26 | 8 | 0 | 20 | 2685 (1852-2928) | R21,R22,R25 |
| earn | nav | cand:morph.tween:waapi | 5 / 5 | 30 (30-33) | 22 | 8 | 0 | 20 | 1237 (1103-1725) | R2,R5,R19,R24,R39 |
| earn | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 31 (31-32) | 23 | 8 | 0 | 20 | 1423 (1423-1727) | R10,R12 |
| earn | nav | cand:nav:earn-no-transition | 2 / 2 | 18 | 13 | 5 | 0 | 20 | 1565 (1565-1693) | R13,R15 |
| earn | nav | orig | 33 / 33 | 33 (31-35) | 25 | 8 | 0 | 20 | 1674 (1183-2447) | 33 runs (see Runs per arm) |
| panel | morph.panel | base | 33 / 33 | 9 (8-10) | 9 | 0 | 0 | 1 | 1389 (1388-1394) | 33 runs (see Runs per arm) |
| panel | morph.panel | cand:?preset=v2-proved | 2 / 2 | 9 | 9 | 0 | 0 | 1 | 1388 (1388-1394) | R4,R7 |
| panel | morph.panel | cand:hero:scene-pause | 3 / 3 | 10 (9-10) | 9 | 1 | 0 | 1 | 1388 | R42,R43,R44 |
| panel | morph.panel | cand:hero.exit:faithful | 5 / 5 | 9 (8-9) | 9 | 0 | 0 | 1 | 1389 (1388-1397) | R6,R8,R9,R20,R28 |
| panel | morph.panel | cand:hero.exit:scoped | 5 / 5 | 9 (8-10) | 9 | 0 | 0 | 1 | 1388 (1388-1394) | R1,R3,R17,R27,R40 |
| panel | morph.panel | cand:morph.tween:scroll-lock | 3 / 3 | 9 | 9 | 0 | 0 | 1 | 1388 (1388-1397) | R21,R22,R25 |
| panel | morph.panel | cand:morph.tween:waapi | 5 / 5 | 9 (8-9) | 9 | 0 | 0 | 1 | 1271 (958-1389) | R2,R5,R19,R24,R39 |
| panel | morph.panel | cand:morph.tween:waapi-scoped | 2 / 2 | 9 (9-10) | 9 | 0 | 0 | 1 | 1388 | R10,R12 |
| panel | morph.panel | cand:nav:earn-no-transition | 2 / 2 | 10 | 9 | 1 | 0 | 1 | 1389 (1389-1394) | R13,R15 |
| panel | morph.panel | orig | 33 / 33 | 9 (8-10) | 9 | 0 | 0 | 1 | 1388 (1388-1410) | 33 runs (see Runs per arm) |

**chromium 390px, end-close, ideal ref**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nav | nav | base | 33 / 33 | 0 | 0 | 0 | 0 | 19 (19-20) | 1000 (1000-1004) | 33 runs (see Runs per arm) |
| nav | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 19 | 1000 (1000-1003) | R4,R7 |
| nav | nav | cand:hero:scene-pause | 3 / 3 | 0 | 0 | 0 | 0 | 20 | 1000 (1000-1001) | R42,R43,R44 |
| nav | nav | cand:hero.exit:faithful | 5 / 5 | 0 | 0 | 0 | 0 | 19 (19-20) | 1000 (1000-1002) | R6,R8,R9,R20,R28 |
| nav | nav | cand:hero.exit:scoped | 5 / 5 | 0 | 0 | 0 | 0 | 19 (19-20) | 1002 (1000-1015) | R1,R3,R17,R27,R40 |
| nav | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 20 | 1000 (1000-1006) | R21,R22,R25 |
| nav | nav | cand:morph.tween:waapi | 5 / 5 | 5 (0-5) | 2 | 1 | 2 | 4 (4-20) | 1000 (1000-1025) | R2,R5,R19,R24,R39 |
| nav | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 5 (5-6) | 2 | 1 | 2 | 4 | 1001 (1001-1033) | R10,R12 |
| nav | nav | cand:nav:earn-no-transition | 2 / 2 | 0 | 0 | 0 | 0 | 19 (19-20) | 1000 (1000-1008) | R13,R15 |
| nav | nav | orig | 33 / 33 | 0 | 0 | 0 | 0 | 20 (19-20) | 1000 (1000-1010) | 33 runs (see Runs per arm) |
| logo | nav | base | 33 / 33 | 7 (1-14) | 4 | 0 | 0 | 0 (0-1) | 1000 (1000-1333) | 33 runs (see Runs per arm) |
| logo | nav | cand:?preset=v2-proved | 2 / 2 | 12 (12-15) | 12 | 0 | 0 | 0 | 1000 | R4,R7 |
| logo | nav | cand:hero:scene-pause | 3 / 3 | 3 (2-5) | 1 | 1 | 0 | 0 (0-1) | 1000 | R42,R43,R44 |
| logo | nav | cand:hero.exit:faithful | 5 / 5 | 5 (2-13) | 2 | 1 | 0 | 0 | 1000 (1000-1026) | R6,R8,R9,R20,R28 |
| logo | nav | cand:hero.exit:scoped | 5 / 5 | 11 (1-14) | 11 | 0 | 0 | 0 (0-1) | 1000 (1000-1313) | R1,R3,R17,R27,R40 |
| logo | nav | cand:morph.tween:scroll-lock | 3 / 3 | 6 (1-7) | 2 | 3 | 0 | 1 (0-2) | 1000 (1000-1124) | R21,R22,R25 |
| logo | nav | cand:morph.tween:waapi | 5 / 5 | 6 (2-12) | 1 | 1 | 0 | 0 (0-1) | 1125 | R2,R5,R19,R24,R39 |
| logo | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 12 (12-13) | 11 | 1 | 0 | 0 | 1125 | R10,R12 |
| logo | nav | cand:nav:earn-no-transition | 2 / 2 | 12 (12-14) | 12 | 0 | 0 | 0 | 1000 | R13,R15 |
| logo | nav | orig | 33 / 33 | 3 (0-8) | 1 | 1 | 0 | 0 (0-2) | 1000 (1000-1027) | 33 runs (see Runs per arm) |
| actions | nav | base | 33 / 33 | 0 | 0 | 0 | 0 | 16 (16-17) | 1000 (998-1006) | 33 runs (see Runs per arm) |
| actions | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 16 | 1000 (1000-1001) | R4,R7 |
| actions | nav | cand:hero:scene-pause | 3 / 3 | 0 | 0 | 0 | 0 | 16 (16-17) | 1000 | R42,R43,R44 |
| actions | nav | cand:hero.exit:faithful | 5 / 5 | 0 | 0 | 0 | 0 | 16 | 1000 (1000-1001) | R6,R8,R9,R20,R28 |
| actions | nav | cand:hero.exit:scoped | 5 / 5 | 0 | 0 | 0 | 0 | 16 (16-17) | 1000 (998-1001) | R1,R3,R17,R27,R40 |
| actions | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 16 | 1000 (1000-1001) | R21,R22,R25 |
| actions | nav | cand:morph.tween:waapi | 5 / 5 | 0 | 0 | 0 | 0 | 12 (12-17) | 1001 (998-1002) | R2,R5,R19,R24,R39 |
| actions | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 0 | 0 | 0 | 0 | 12 | 1000 | R10,R12 |
| actions | nav | cand:nav:earn-no-transition | 2 / 2 | 0 | 0 | 0 | 0 | 16 (16-17) | 1000 (1000-1007) | R13,R15 |
| actions | nav | orig | 33 / 33 | 0 | 0 | 0 | 0 | 16 (16-17) | 1000 (998-1001) | 33 runs (see Runs per arm) |
| earn | nav | base | 33 / 33 | 17 (17-18) | 1 | 16 | 0 | 20 | 3941 (3911-4060) | 33 runs (see Runs per arm) |
| earn | nav | cand:?preset=v2-proved | 2 / 2 | 17 | 1 | 16 | 0 | 20 | 3911 | R4,R7 |
| earn | nav | cand:hero:scene-pause | 3 / 3 | 17 | 1 | 16 | 0 | 20 | 4030 (3911-4030) | R42,R43,R44 |
| earn | nav | cand:hero.exit:faithful | 5 / 5 | 17 | 1 | 16 | 0 | 20 | 4030 (3911-4030) | R6,R8,R9,R20,R28 |
| earn | nav | cand:hero.exit:scoped | 5 / 5 | 17 | 1 | 16 | 0 | 20 | 3911 | R1,R3,R17,R27,R40 |
| earn | nav | cand:morph.tween:scroll-lock | 3 / 3 | 17 | 1 | 16 | 0 | 20 | 3911 (3911-4030) | R21,R22,R25 |
| earn | nav | cand:morph.tween:waapi | 5 / 5 | 20 (18-20) | 4 | 16 | 0 | 20 | 4030 (3911-4030) | R2,R5,R19,R24,R39 |
| earn | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 19 (19-20) | 3 | 16 | 0 | 20 | 3941 (3941-4030) | R10,R12 |
| earn | nav | cand:nav:earn-no-transition | 2 / 2 | 20 | 3 | 17 | 0 | 20 | 6764 (6764-7545) | R13,R15 |
| earn | nav | orig | 33 / 33 | 17 (17-18) | 1 | 16 | 0 | 20 | 4030 (3911-4060) | 33 runs (see Runs per arm) |
| panel | morph.panel | base | 33 / 33 | 0 | 0 | 0 | 0 | 0 | 1000 (1000-1006) | 33 runs (see Runs per arm) |
| panel | morph.panel | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| panel | morph.panel | cand:hero:scene-pause | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 (1000-1004) | R42,R43,R44 |
| panel | morph.panel | cand:hero.exit:faithful | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1000 | R6,R8,R9,R20,R28 |
| panel | morph.panel | cand:hero.exit:scoped | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1000 (1000-1004) | R1,R3,R17,R27,R40 |
| panel | morph.panel | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| panel | morph.panel | cand:morph.tween:waapi | 5 / 5 | 3 (3-4) | 3 | 0 | 0 | 1 | 1000 (1000-1004) | R2,R5,R19,R24,R39 |
| panel | morph.panel | cand:morph.tween:waapi-scoped | 2 / 2 | 4 | 4 | 0 | 0 | 1 | 1000 (1000-1004) | R10,R12 |
| panel | morph.panel | cand:nav:earn-no-transition | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 (1000-1004) | R13,R15 |
| panel | morph.panel | orig | 33 / 33 | 0 (0-1) | 0 | 0 | 0 | 0 | 1000 (1000-1004) | 33 runs (see Runs per arm) |

**chromium 390px, end-open, ideal line**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nav | nav | base | 33 / 33 | 19 (18-21) | 18 | 1 | 0 | 1 | 3556 (3544-4342) | 33 runs (see Runs per arm) |
| nav | nav | cand:?preset=v2-proved | 2 / 2 | 19 | 18 | 1 | 0 | 1 | 3549 (3549-3554) | R4,R7 |
| nav | nav | cand:hero:scene-pause | 3 / 3 | 19 (18-19) | 18 | 1 | 0 | 1 | 3549 (3544-3554) | R42,R43,R44 |
| nav | nav | cand:hero.exit:faithful | 5 / 5 | 19 (18-20) | 18 | 1 | 0 | 1 | 3556 (3549-3817) | R6,R8,R9,R20,R28 |
| nav | nav | cand:hero.exit:scoped | 5 / 5 | 19 (19-20) | 18 | 1 | 0 | 1 | 3554 (3549-3566) | R1,R3,R17,R27,R40 |
| nav | nav | cand:morph.tween:scroll-lock | 3 / 3 | 19 | 18 | 1 | 0 | 1 | 3554 (3549-3566) | R21,R22,R25 |
| nav | nav | cand:morph.tween:waapi | 5 / 5 | 19 (17-19) | 18 | 1 | 0 | 1 | 3500 (3491-3788) | R2,R5,R19,R24,R39 |
| nav | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 19 | 17 | 1 | 0 | 1 | 3496 (3496-4359) | R10,R12 |
| nav | nav | cand:nav:earn-no-transition | 2 / 2 | 19 (19-20) | 18 | 1 | 0 | 1 | 3556 (3556-3561) | R13,R15 |
| nav | nav | orig | 33 / 33 | 19 (18-21) | 18 | 1 | 0 | 1 | 3535 (3523-4363) | 33 runs (see Runs per arm) |
| logo | nav | base | 33 / 33 | 28 (26-31) | 25 | 3 | 0 | 1 | 5012 (4995-10504) | 33 runs (see Runs per arm) |
| logo | nav | cand:?preset=v2-proved | 2 / 2 | 26 | 25 | 1 | 0 | 1 | 4995 (4995-5005) | R4,R7 |
| logo | nav | cand:hero:scene-pause | 3 / 3 | 28 (28-29) | 25 | 4 | 0 | 1 | 4995 (4985-5005) | R42,R43,R44 |
| logo | nav | cand:hero.exit:faithful | 5 / 5 | 27 (26-29) | 25 | 3 | 0 | 1 | 5012 (4995-9364) | R6,R8,R9,R20,R28 |
| logo | nav | cand:hero.exit:scoped | 5 / 5 | 27 (26-29) | 25 | 1 | 0 | 1 | 5005 (4995-8182) | R1,R3,R17,R27,R40 |
| logo | nav | cand:morph.tween:scroll-lock | 3 / 3 | 29 (28-29) | 25 | 4 | 0 | 1 | 5005 (4995-5033) | R21,R22,R25 |
| logo | nav | cand:morph.tween:waapi | 5 / 5 | 26 (25-29) | 24 | 3 | 0 | 1 | 4887 (4883-8826) | R2,R5,R19,R24,R39 |
| logo | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 25 (25-27) | 24 | 1 | 0 | 1 | 4880 (4880-10121) | R10,R12 |
| logo | nav | cand:nav:earn-no-transition | 2 / 2 | 26 (26-27) | 25 | 1 | 0 | 1 | 5022 (5022-7650) | R13,R15 |
| logo | nav | orig | 33 / 33 | 29 (27-30) | 25 | 4 | 0 | 1 | 4965 (4938-10493) | 33 runs (see Runs per arm) |
| actions | nav | base | 33 / 33 | 26 (25-29) | 25 | 1 | 0 | 0 | 4993 (3575-4998) | 33 runs (see Runs per arm) |
| actions | nav | cand:?preset=v2-proved | 2 / 2 | 26 (26-27) | 25 | 1 | 0 | 0 | 4993 (4993-4996) | R4,R7 |
| actions | nav | cand:hero:scene-pause | 3 / 3 | 26 | 25 | 1 | 0 | 0 | 4993 (4981-4996) | R42,R43,R44 |
| actions | nav | cand:hero.exit:faithful | 5 / 5 | 26 (26-28) | 25 | 1 | 0 | 0 | 4993 (3202-4996) | R6,R8,R9,R20,R28 |
| actions | nav | cand:hero.exit:scoped | 5 / 5 | 27 (26-28) | 25 | 1 | 0 | 0 | 4981 (3575-4996) | R1,R3,R17,R27,R40 |
| actions | nav | cand:morph.tween:scroll-lock | 3 / 3 | 26 (26-27) | 25 | 1 | 0 | 0 | 4981 (4981-4994) | R21,R22,R25 |
| actions | nav | cand:morph.tween:waapi | 5 / 5 | 25 (23-26) | 24 | 1 | 0 | 0 | 4884 (3337-4884) | R2,R5,R19,R24,R39 |
| actions | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 25 (25-27) | 24 | 1 | 0 | 0 | 3768 (3768-4878) | R10,R12 |
| actions | nav | cand:nav:earn-no-transition | 2 / 2 | 27 | 24 | 1 | 0 | 0 | 3575 (3575-4993) | R13,R15 |
| actions | nav | orig | 33 / 33 | 26 (25-28) | 25 | 1 | 0 | 0 | 4962 (3589-4975) | 33 runs (see Runs per arm) |
| earn | nav | base | 33 / 33 | 31 (29-31) | 25 | 6 | 0 | 7 (4-8) | 4995 (3573-5001) | 33 runs (see Runs per arm) |
| earn | nav | cand:?preset=v2-proved | 2 / 2 | 31 | 25 | 6 | 0 | 4 (4-5) | 4995 (4995-5001) | R4,R7 |
| earn | nav | cand:hero:scene-pause | 3 / 3 | 31 (30-31) | 25 | 6 | 0 | 7 (7-8) | 4995 (4985-5001) | R42,R43,R44 |
| earn | nav | cand:hero.exit:faithful | 5 / 5 | 31 (30-31) | 25 | 6 | 0 | 7 (4-8) | 4995 (3205-4999) | R6,R8,R9,R20,R28 |
| earn | nav | cand:hero.exit:scoped | 5 / 5 | 31 | 25 | 6 | 0 | 5 (5-7) | 4985 (3573-5001) | R1,R3,R17,R27,R40 |
| earn | nav | cand:morph.tween:scroll-lock | 3 / 3 | 31 | 25 | 6 | 0 | 7 (7-8) | 4985 (4985-4999) | R21,R22,R25 |
| earn | nav | cand:morph.tween:waapi | 5 / 5 | 29 (26-31) | 24 | 6 | 0 | 6 (4-7) | 4879 (3334-4879) | R2,R5,R19,R24,R39 |
| earn | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 29 | 24 | 5 | 0 | 4 | 3768 (3768-4880) | R10,R12 |
| earn | nav | cand:nav:earn-no-transition | 2 / 2 | 27 (27-28) | 25 | 1 | 0 | 0 | 3575 (3575-4995) | R13,R15 |
| earn | nav | orig | 33 / 33 | 31 (29-31) | 25 | 6 | 0 | 7 (6-7) | 4965 (3584-4975) | 33 runs (see Runs per arm) |
| panel | morph.panel | base | 33 / 33 | 13 (13-14) | 13 | 0 | 0 | 0 | 1142 (1000-1400) | 33 runs (see Runs per arm) |
| panel | morph.panel | cand:?preset=v2-proved | 2 / 2 | 13 | 13 | 0 | 0 | 0 | 1000 (1000-1142) | R4,R7 |
| panel | morph.panel | cand:hero:scene-pause | 3 / 3 | 13 | 13 | 0 | 0 | 0 | 1000 (1000-1142) | R42,R43,R44 |
| panel | morph.panel | cand:hero.exit:faithful | 5 / 5 | 13 (13-14) | 13 | 0 | 0 | 0 | 1142 (1000-1389) | R6,R8,R9,R20,R28 |
| panel | morph.panel | cand:hero.exit:scoped | 5 / 5 | 13 (13-14) | 13 | 0 | 0 | 0 | 1142 (1000-1389) | R1,R3,R17,R27,R40 |
| panel | morph.panel | cand:morph.tween:scroll-lock | 3 / 3 | 13 | 13 | 0 | 0 | 0 | 1142 (1000-1142) | R21,R22,R25 |
| panel | morph.panel | cand:morph.tween:waapi | 5 / 5 | 14 (13-14) | 14 | 0 | 0 | 0 | 1000 (1000-1389) | R2,R5,R19,R24,R39 |
| panel | morph.panel | cand:morph.tween:waapi-scoped | 2 / 2 | 14 (14-15) | 14 | 0 | 0 | 0 | 1000 (1000-1389) | R10,R12 |
| panel | morph.panel | cand:nav:earn-no-transition | 2 / 2 | 13 (13-14) | 13 | 0 | 0 | 0 | 1142 (1142-1389) | R13,R15 |
| panel | morph.panel | orig | 33 / 33 | 13 (12-14) | 13 | 0 | 0 | 0 | 1000 (1000-1389) | 33 runs (see Runs per arm) |

**chromium 390px, end-open, ideal ref**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nav | nav | base | 33 / 33 | 0 (0-1) | 0 | 0 | 0 | 1 | 1007 (1000-1685) | 33 runs (see Runs per arm) |
| nav | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 1 | 1004 | R4,R7 |
| nav | nav | cand:hero:scene-pause | 3 / 3 | 0 | 0 | 0 | 0 | 1 | 1004 (1003-1004) | R42,R43,R44 |
| nav | nav | cand:hero.exit:faithful | 5 / 5 | 0 (0-1) | 0 | 0 | 0 | 1 | 1007 (1002-1674) | R6,R8,R9,R20,R28 |
| nav | nav | cand:hero.exit:scoped | 5 / 5 | 0 | 0 | 0 | 0 | 1 | 1007 (1004-1013) | R1,R3,R17,R27,R40 |
| nav | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 1 | 1004 (1002-1007) | R21,R22,R25 |
| nav | nav | cand:morph.tween:waapi | 5 / 5 | 0 | 0 | 0 | 0 | 1 | 1002 (1000-1006) | R2,R5,R19,R24,R39 |
| nav | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 0 (0-1) | 0 | 0 | 0 | 1 | 1001 (1001-1690) | R10,R12 |
| nav | nav | cand:nav:earn-no-transition | 2 / 2 | 0 (0-1) | 0 | 0 | 0 | 1 | 1002 (1002-1667) | R13,R15 |
| nav | nav | orig | 33 / 33 | 0 | 0 | 0 | 0 | 1 | 1000 (1000-1007) | 33 runs (see Runs per arm) |
| logo | nav | base | 33 / 33 | 5 (0-13) | 3 | 0 | 0 | 1 | 1019 (1000-2930) | 33 runs (see Runs per arm) |
| logo | nav | cand:?preset=v2-proved | 2 / 2 | 12 | 12 | 0 | 0 | 1 | 1003 (1003-1004) | R4,R7 |
| logo | nav | cand:hero:scene-pause | 3 / 3 | 0 (0-3) | 0 | 0 | 0 | 1 | 1014 (1006-1299) | R42,R43,R44 |
| logo | nav | cand:hero.exit:faithful | 5 / 5 | 5 (1-12) | 3 | 1 | 0 | 1 | 1013 (1000-2918) | R6,R8,R9,R20,R28 |
| logo | nav | cand:hero.exit:scoped | 5 / 5 | 11 (1-12) | 11 | 0 | 0 | 1 | 1015 (1000-1038) | R1,R3,R17,R27,R40 |
| logo | nav | cand:morph.tween:scroll-lock | 3 / 3 | 2 (1-3) | 1 | 1 | 0 | 1 | 1037 (1000-1313) | R21,R22,R25 |
| logo | nav | cand:morph.tween:waapi | 5 / 5 | 3 (0-11) | 1 | 0 | 0 | 1 | 1000 (1000-1330) | R2,R5,R19,R24,R39 |
| logo | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 9 (9-11) | 9 | 0 | 0 | 1 | 1000 (1000-2789) | R10,R12 |
| logo | nav | cand:nav:earn-no-transition | 2 / 2 | 11 (11-12) | 11 | 0 | 0 | 1 | 1000 (1000-2931) | R13,R15 |
| logo | nav | orig | 33 / 33 | 0 (0-4) | 0 | 0 | 0 | 1 | 1000 (1000-1393) | 33 runs (see Runs per arm) |
| actions | nav | base | 33 / 33 | 0 (0-1) | 0 | 0 | 0 | 0 | 1003 (1000-1007) | 33 runs (see Runs per arm) |
| actions | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1003 | R4,R7 |
| actions | nav | cand:hero:scene-pause | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1003 | R42,R43,R44 |
| actions | nav | cand:hero.exit:faithful | 5 / 5 | 0 (0-1) | 0 | 0 | 0 | 0 | 1002 (1001-1007) | R6,R8,R9,R20,R28 |
| actions | nav | cand:hero.exit:scoped | 5 / 5 | 0 (0-1) | 0 | 0 | 0 | 0 | 1004 (1000-1007) | R1,R3,R17,R27,R40 |
| actions | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1003 (1000-1006) | R21,R22,R25 |
| actions | nav | cand:morph.tween:waapi | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1000 | R2,R5,R19,R24,R39 |
| actions | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 (1000-1002) | R10,R12 |
| actions | nav | cand:nav:earn-no-transition | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 (1000-1001) | R13,R15 |
| actions | nav | orig | 33 / 33 | 0 | 0 | 0 | 0 | 0 | 1000 (1000-1003) | 33 runs (see Runs per arm) |
| earn | nav | base | 33 / 33 | 1 (0-3) | 1 | 0 | 0 | 7 (4-8) | 1007 (1000-1629) | 33 runs (see Runs per arm) |
| earn | nav | cand:?preset=v2-proved | 2 / 2 | 1 (1-2) | 1 | 0 | 0 | 4 (4-5) | 1315 (1315-1464) | R4,R7 |
| earn | nav | cand:hero:scene-pause | 3 / 3 | 0 (0-1) | 0 | 0 | 0 | 7 (7-8) | 1004 (1003-1005) | R42,R43,R44 |
| earn | nav | cand:hero.exit:faithful | 5 / 5 | 1 (1-4) | 1 | 0 | 0 | 7 (4-8) | 1007 (1003-1400) | R6,R8,R9,R20,R28 |
| earn | nav | cand:hero.exit:scoped | 5 / 5 | 1 (1-4) | 1 | 0 | 0 | 5 (5-7) | 1111 (1004-1349) | R1,R3,R17,R27,R40 |
| earn | nav | cand:morph.tween:scroll-lock | 3 / 3 | 1 (0-2) | 1 | 0 | 0 | 7 (7-8) | 1006 (1002-1009) | R21,R22,R25 |
| earn | nav | cand:morph.tween:waapi | 5 / 5 | 1 (0-2) | 1 | 0 | 0 | 6 (4-7) | 1061 (999-1243) | R2,R5,R19,R24,R39 |
| earn | nav | cand:morph.tween:waapi-scoped | 2 / 2 | 1 (1-2) | 1 | 0 | 0 | 4 | 1063 (1063-1267) | R10,R12 |
| earn | nav | cand:nav:earn-no-transition | 2 / 2 | 26 (26-33) | 25 | 1 | 0 | 0 | 4054 (4054-8201) | R13,R15 |
| earn | nav | orig | 33 / 33 | 0 (0-4) | 0 | 0 | 0 | 7 (6-7) | 1002 (1000-1103) | 33 runs (see Runs per arm) |
| panel | morph.panel | base | 33 / 33 | 5 (1-5) | 5 | 0 | 0 | 0 | 1142 (1000-1142) | 33 runs (see Runs per arm) |
| panel | morph.panel | cand:?preset=v2-proved | 2 / 2 | 2 (2-5) | 2 | 0 | 0 | 0 | 1142 | R4,R7 |
| panel | morph.panel | cand:hero:scene-pause | 3 / 3 | 5 | 5 | 0 | 0 | 0 | 1142 | R42,R43,R44 |
| panel | morph.panel | cand:hero.exit:faithful | 5 / 5 | 4 (4-5) | 4 | 0 | 0 | 0 | 1142 (1000-1142) | R6,R8,R9,R20,R28 |
| panel | morph.panel | cand:hero.exit:scoped | 5 / 5 | 5 (4-5) | 5 | 0 | 0 | 0 | 1142 (1007-1142) | R1,R3,R17,R27,R40 |
| panel | morph.panel | cand:morph.tween:scroll-lock | 3 / 3 | 4 (0-5) | 4 | 0 | 0 | 0 | 1142 (1008-1142) | R21,R22,R25 |
| panel | morph.panel | cand:morph.tween:waapi | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1000 (1000-1005) | R2,R5,R19,R24,R39 |
| panel | morph.panel | cand:morph.tween:waapi-scoped | 2 / 2 | 0 (0-1) | 0 | 0 | 0 | 0 | 1000 (1000-1005) | R10,R12 |
| panel | morph.panel | cand:nav:earn-no-transition | 2 / 2 | 4 (4-5) | 4 | 0 | 0 | 0 | 1000 (1000-1142) | R13,R15 |
| panel | morph.panel | orig | 33 / 33 | 0 (0-1) | 0 | 0 | 0 | 0 | 1000 (1000-1142) | 33 runs (see Runs per arm) |

**chromium 390px, hero, ideal line**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero.track | hero.exit | base | 33 / 33 | 0 | 0 | 0 | 0 | 0 | 1000 | 33 runs (see Runs per arm) |
| hero.track | hero.exit | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.track | hero.exit | cand:hero:scene-pause | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R42,R43,R44 |
| hero.track | hero.exit | cand:hero.exit:faithful | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1000 | R6,R8,R9,R20,R28 |
| hero.track | hero.exit | cand:hero.exit:scoped | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1000 | R1,R3,R17,R27,R40 |
| hero.track | hero.exit | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.track | hero.exit | cand:morph.tween:waapi | 5 / 5 | 0 | 0 | 0 | 0 | 0 | 1000 | R2,R5,R19,R24,R39 |
| hero.track | hero.exit | cand:morph.tween:waapi-scoped | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R10,R12 |
| hero.track | hero.exit | cand:nav:earn-no-transition | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R13,R15 |
| hero.track | hero.exit | orig | 33 / 33 | 0 | 0 | 0 | 0 | 0 | 1000 | 33 runs (see Runs per arm) |
| hero.stage | hero.exit | base | 16 / 33 | 0 | 0 | 0 | 0 | 0 | 1099 | 16 runs (see Runs per arm) |
| hero.stage | hero.exit | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R4,R7 |
| hero.stage | hero.exit | cand:hero:scene-pause | 0 / 3 | - | - | - | - | - | - | |
| hero.stage | hero.exit | cand:hero.exit:faithful | 2 / 5 | 0 | 0 | 0 | 0 | 0 | 1099 | R8,R20 |
| hero.stage | hero.exit | cand:hero.exit:scoped | 3 / 5 | 0 | 0 | 0 | 0 | 0 | 1099 | R1,R3,R17 |
| hero.stage | hero.exit | cand:morph.tween:scroll-lock | 0 / 3 | - | - | - | - | - | - | |
| hero.stage | hero.exit | cand:morph.tween:waapi | 2 / 5 | 0 | 0 | 0 | 0 | 0 | 1099 | R2,R5 |
| hero.stage | hero.exit | cand:morph.tween:waapi-scoped | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R10,R12 |
| hero.stage | hero.exit | cand:nav:earn-no-transition | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R13,R15 |
| hero.stage | hero.exit | orig | 0 / 33 | - | - | - | - | - | - | |
| hero.copy | hero | base | 33 / 33 | 3 (2-3) | 1 | 2 | 0 | 0 | 1965 (1965-1987) | 33 runs (see Runs per arm) |
| hero.copy | hero | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.copy | hero | cand:hero:scene-pause | 3 / 3 | 3 | 1 | 2 | 0 | 0 | 1965 | R42,R43,R44 |
| hero.copy | hero | cand:hero.exit:faithful | 5 / 5 | 3 (2-3) | 1 | 2 | 0 | 0 | 1965 (1965-1987) | R6,R8,R9,R20,R28 |
| hero.copy | hero | cand:hero.exit:scoped | 5 / 5 | 2 (2-3) | 1 | 1 | 0 | 0 | 1987 (1965-1987) | R1,R3,R17,R27,R40 |
| hero.copy | hero | cand:morph.tween:scroll-lock | 3 / 3 | 3 | 1 | 2 | 0 | 0 | 1965 | R21,R22,R25 |
| hero.copy | hero | cand:morph.tween:waapi | 5 / 5 | 3 (2-3) | 1 | 2 | 0 | 0 | 1965 (1965-1987) | R2,R5,R19,R24,R39 |
| hero.copy | hero | cand:morph.tween:waapi-scoped | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 1987 | R10,R12 |
| hero.copy | hero | cand:nav:earn-no-transition | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 1987 | R13,R15 |
| hero.copy | hero | orig | 33 / 33 | 3 | 1 | 2 | 0 | 0 | 1965 | 33 runs (see Runs per arm) |
| hero.cta | hero | base | 33 / 33 | 2 | 1 | 1 | 0 | 0 | 1965 (1965-1978) | 33 runs (see Runs per arm) |
| hero.cta | hero | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.cta | hero | cand:hero:scene-pause | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1965 | R42,R43,R44 |
| hero.cta | hero | cand:hero.exit:faithful | 5 / 5 | 2 | 1 | 1 | 0 | 0 | 1965 (1965-1978) | R6,R8,R9,R20,R28 |
| hero.cta | hero | cand:hero.exit:scoped | 5 / 5 | 2 | 1 | 1 | 0 | 0 | 1978 (1965-1978) | R1,R3,R17,R27,R40 |
| hero.cta | hero | cand:morph.tween:scroll-lock | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1965 | R21,R22,R25 |
| hero.cta | hero | cand:morph.tween:waapi | 5 / 5 | 2 | 1 | 1 | 0 | 0 | 1965 (1965-1978) | R2,R5,R19,R24,R39 |
| hero.cta | hero | cand:morph.tween:waapi-scoped | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 1978 | R10,R12 |
| hero.cta | hero | cand:nav:earn-no-transition | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 1978 | R13,R15 |
| hero.cta | hero | orig | 33 / 33 | 2 | 1 | 1 | 0 | 0 | 1965 | 33 runs (see Runs per arm) |
| hero.countdown.unit | hero.countdown | base | 33 / 33 | 2 | 1 | 1 | 0 | 0 | 1965 (1965-1978) | 33 runs (see Runs per arm) |
| hero.countdown.unit | hero.countdown | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.countdown.unit | hero.countdown | cand:hero:scene-pause | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1965 | R42,R43,R44 |
| hero.countdown.unit | hero.countdown | cand:hero.exit:faithful | 5 / 5 | 2 | 1 | 1 | 0 | 0 | 1965 (1965-1978) | R6,R8,R9,R20,R28 |
| hero.countdown.unit | hero.countdown | cand:hero.exit:scoped | 5 / 5 | 2 | 1 | 1 | 0 | 0 | 1978 (1965-1978) | R1,R3,R17,R27,R40 |
| hero.countdown.unit | hero.countdown | cand:morph.tween:scroll-lock | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1965 | R21,R22,R25 |
| hero.countdown.unit | hero.countdown | cand:morph.tween:waapi | 5 / 5 | 2 | 1 | 1 | 0 | 0 | 1965 (1965-1978) | R2,R5,R19,R24,R39 |
| hero.countdown.unit | hero.countdown | cand:morph.tween:waapi-scoped | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 1978 | R10,R12 |
| hero.countdown.unit | hero.countdown | cand:nav:earn-no-transition | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 1978 | R13,R15 |
| hero.countdown.unit | hero.countdown | orig | 33 / 33 | 2 | 1 | 1 | 0 | 0 | 1965 | 33 runs (see Runs per arm) |
| hero.cue | hero.cue | base | 33 / 33 | 3 (2-3) | 1 | 2 | 0 | 0 | 2000 (1987-2000) | 33 runs (see Runs per arm) |
| hero.cue | hero.cue | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.cue | hero.cue | cand:hero:scene-pause | 3 / 3 | 3 | 1 | 2 | 0 | 0 | 2000 | R42,R43,R44 |
| hero.cue | hero.cue | cand:hero.exit:faithful | 5 / 5 | 3 (2-3) | 1 | 2 | 0 | 0 | 2000 (1987-2000) | R6,R8,R9,R20,R28 |
| hero.cue | hero.cue | cand:hero.exit:scoped | 5 / 5 | 2 (2-3) | 1 | 1 | 0 | 0 | 1987 (1987-2000) | R1,R3,R17,R27,R40 |
| hero.cue | hero.cue | cand:morph.tween:scroll-lock | 3 / 3 | 3 | 1 | 2 | 0 | 0 | 2000 | R21,R22,R25 |
| hero.cue | hero.cue | cand:morph.tween:waapi | 5 / 5 | 3 (2-3) | 1 | 2 | 0 | 0 | 2000 (1987-2000) | R2,R5,R19,R24,R39 |
| hero.cue | hero.cue | cand:morph.tween:waapi-scoped | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 1987 | R10,R12 |
| hero.cue | hero.cue | cand:nav:earn-no-transition | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 1987 | R13,R15 |
| hero.cue | hero.cue | orig | 33 / 33 | 3 | 1 | 2 | 0 | 0 | 2000 | 33 runs (see Runs per arm) |
| hero.orbit.card | hero.orbit | base | 33 / 33 | 3 (2-3) | 1 | 2 | 0 | 0 | 2000 | 33 runs (see Runs per arm) |
| hero.orbit.card | hero.orbit | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.orbit.card | hero.orbit | cand:hero:scene-pause | 3 / 3 | 3 | 1 | 2 | 0 | 0 | 2000 | R42,R43,R44 |
| hero.orbit.card | hero.orbit | cand:hero.exit:faithful | 5 / 5 | 3 (2-3) | 1 | 2 | 0 | 0 | 2000 | R6,R8,R9,R20,R28 |
| hero.orbit.card | hero.orbit | cand:hero.exit:scoped | 5 / 5 | 2 (2-3) | 1 | 1 | 0 | 0 | 2000 | R1,R3,R17,R27,R40 |
| hero.orbit.card | hero.orbit | cand:morph.tween:scroll-lock | 3 / 3 | 3 | 1 | 2 | 0 | 0 | 2000 | R21,R22,R25 |
| hero.orbit.card | hero.orbit | cand:morph.tween:waapi | 5 / 5 | 3 (2-3) | 1 | 2 | 0 | 0 | 2000 | R2,R5,R19,R24,R39 |
| hero.orbit.card | hero.orbit | cand:morph.tween:waapi-scoped | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 2000 | R10,R12 |
| hero.orbit.card | hero.orbit | cand:nav:earn-no-transition | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 2000 | R13,R15 |
| hero.orbit.card | hero.orbit | orig | 33 / 33 | 3 | 1 | 2 | 0 | 0 | 2000 | 33 runs (see Runs per arm) |
| hero.deck | hero.deck | base | 16 / 33 | 0 | 0 | 0 | 0 | 0 | 1099 | 16 runs (see Runs per arm) |
| hero.deck | hero.deck | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R4,R7 |
| hero.deck | hero.deck | cand:hero:scene-pause | 0 / 3 | - | - | - | - | - | - | |
| hero.deck | hero.deck | cand:hero.exit:faithful | 2 / 5 | 0 | 0 | 0 | 0 | 0 | 1099 | R8,R20 |
| hero.deck | hero.deck | cand:hero.exit:scoped | 3 / 5 | 0 | 0 | 0 | 0 | 0 | 1099 | R1,R3,R17 |
| hero.deck | hero.deck | cand:morph.tween:scroll-lock | 0 / 3 | - | - | - | - | - | - | |
| hero.deck | hero.deck | cand:morph.tween:waapi | 2 / 5 | 0 | 0 | 0 | 0 | 0 | 1099 | R2,R5 |
| hero.deck | hero.deck | cand:morph.tween:waapi-scoped | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R10,R12 |
| hero.deck | hero.deck | cand:nav:earn-no-transition | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R13,R15 |
| hero.deck | hero.deck | orig | 0 / 33 | - | - | - | - | - | - | |
| hero.deck.card | hero.deck | base | 33 / 33 | 3 (2-3) | 1 | 2 | 0 | 0 | 2001 (1988-2001) | 33 runs (see Runs per arm) |
| hero.deck.card | hero.deck | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.deck.card | hero.deck | cand:hero:scene-pause | 3 / 3 | 3 | 1 | 2 | 0 | 0 | 2001 | R42,R43,R44 |
| hero.deck.card | hero.deck | cand:hero.exit:faithful | 5 / 5 | 3 (2-3) | 1 | 2 | 0 | 0 | 2001 (1988-2001) | R6,R8,R9,R20,R28 |
| hero.deck.card | hero.deck | cand:hero.exit:scoped | 5 / 5 | 2 (2-3) | 1 | 1 | 0 | 0 | 1988 (1988-2001) | R1,R3,R17,R27,R40 |
| hero.deck.card | hero.deck | cand:morph.tween:scroll-lock | 3 / 3 | 3 | 1 | 2 | 0 | 0 | 2001 | R21,R22,R25 |
| hero.deck.card | hero.deck | cand:morph.tween:waapi | 5 / 5 | 3 (2-3) | 1 | 2 | 0 | 0 | 2001 (1988-2001) | R2,R5,R19,R24,R39 |
| hero.deck.card | hero.deck | cand:morph.tween:waapi-scoped | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 1988 | R10,R12 |
| hero.deck.card | hero.deck | cand:nav:earn-no-transition | 2 / 2 | 2 | 1 | 1 | 0 | 0 | 1988 | R13,R15 |
| hero.deck.card | hero.deck | orig | 33 / 33 | 3 | 1 | 2 | 0 | 0 | 2001 | 33 runs (see Runs per arm) |

**chromium 390px, hero, ideal ref**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero.track | hero.exit | base | 33 / 33 | 0 (0-4) | 0 | 0 | 0 | 0 | 1000 (1000-17666) | 33 runs (see Runs per arm) |
| hero.track | hero.exit | cand:?preset=v2-proved | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 17666 | R4,R7 |
| hero.track | hero.exit | cand:hero:scene-pause | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R42,R43,R44 |
| hero.track | hero.exit | cand:hero.exit:faithful | 5 / 5 | 0 (0-4) | 0 | 0 | 0 | 0 | 1000 (1000-17666) | R6,R8,R9,R20,R28 |
| hero.track | hero.exit | cand:hero.exit:scoped | 5 / 5 | 4 (0-4) | 0 | 4 | 0 | 0 | 17666 (1000-17666) | R1,R3,R17,R27,R40 |
| hero.track | hero.exit | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.track | hero.exit | cand:morph.tween:waapi | 5 / 5 | 0 (0-4) | 0 | 0 | 0 | 0 | 1000 (1000-17666) | R2,R5,R19,R24,R39 |
| hero.track | hero.exit | cand:morph.tween:waapi-scoped | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 17666 | R10,R12 |
| hero.track | hero.exit | cand:nav:earn-no-transition | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 17666 | R13,R15 |
| hero.copy | hero | base | 33 / 33 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-18000) | 33 runs (see Runs per arm) |
| hero.copy | hero | cand:?preset=v2-proved | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 9000 | R4,R7 |
| hero.copy | hero | cand:hero:scene-pause | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R42,R43,R44 |
| hero.copy | hero | cand:hero.exit:faithful | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-18000) | R6,R8,R9,R20,R28 |
| hero.copy | hero | cand:hero.exit:scoped | 5 / 5 | 3 (0-3) | 0 | 3 | 0 | 0 | 18000 (1000-18000) | R1,R3,R17,R27,R40 |
| hero.copy | hero | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.copy | hero | cand:morph.tween:waapi | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-18000) | R2,R5,R19,R24,R39 |
| hero.copy | hero | cand:morph.tween:waapi-scoped | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 18000 | R10,R12 |
| hero.copy | hero | cand:nav:earn-no-transition | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 18000 | R13,R15 |
| hero.cta | hero | base | 33 / 33 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-17631) | 33 runs (see Runs per arm) |
| hero.cta | hero | cand:?preset=v2-proved | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 8824 | R4,R7 |
| hero.cta | hero | cand:hero:scene-pause | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R42,R43,R44 |
| hero.cta | hero | cand:hero.exit:faithful | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-17631) | R6,R8,R9,R20,R28 |
| hero.cta | hero | cand:hero.exit:scoped | 5 / 5 | 3 (0-3) | 0 | 3 | 0 | 0 | 17631 (1000-17631) | R1,R3,R17,R27,R40 |
| hero.cta | hero | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.cta | hero | cand:morph.tween:waapi | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-17631) | R2,R5,R19,R24,R39 |
| hero.cta | hero | cand:morph.tween:waapi-scoped | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 17631 | R10,R12 |
| hero.cta | hero | cand:nav:earn-no-transition | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 17631 | R13,R15 |
| hero.countdown.unit | hero.countdown | base | 33 / 33 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-17631) | 33 runs (see Runs per arm) |
| hero.countdown.unit | hero.countdown | cand:?preset=v2-proved | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 8824 | R4,R7 |
| hero.countdown.unit | hero.countdown | cand:hero:scene-pause | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R42,R43,R44 |
| hero.countdown.unit | hero.countdown | cand:hero.exit:faithful | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-17631) | R6,R8,R9,R20,R28 |
| hero.countdown.unit | hero.countdown | cand:hero.exit:scoped | 5 / 5 | 3 (0-3) | 0 | 3 | 0 | 0 | 17631 (1000-17631) | R1,R3,R17,R27,R40 |
| hero.countdown.unit | hero.countdown | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.countdown.unit | hero.countdown | cand:morph.tween:waapi | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-17631) | R2,R5,R19,R24,R39 |
| hero.countdown.unit | hero.countdown | cand:morph.tween:waapi-scoped | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 17631 | R10,R12 |
| hero.countdown.unit | hero.countdown | cand:nav:earn-no-transition | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 17631 | R13,R15 |
| hero.cue | hero.cue | base | 33 / 33 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-18000) | 33 runs (see Runs per arm) |
| hero.cue | hero.cue | cand:?preset=v2-proved | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 9000 | R4,R7 |
| hero.cue | hero.cue | cand:hero:scene-pause | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R42,R43,R44 |
| hero.cue | hero.cue | cand:hero.exit:faithful | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-18000) | R6,R8,R9,R20,R28 |
| hero.cue | hero.cue | cand:hero.exit:scoped | 5 / 5 | 3 (0-3) | 0 | 3 | 0 | 0 | 18000 (1000-18000) | R1,R3,R17,R27,R40 |
| hero.cue | hero.cue | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.cue | hero.cue | cand:morph.tween:waapi | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-18000) | R2,R5,R19,R24,R39 |
| hero.cue | hero.cue | cand:morph.tween:waapi-scoped | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 18000 | R10,R12 |
| hero.cue | hero.cue | cand:nav:earn-no-transition | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 18000 | R13,R15 |
| hero.orbit.card | hero.orbit | base | 33 / 33 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-22000) | 33 runs (see Runs per arm) |
| hero.orbit.card | hero.orbit | cand:?preset=v2-proved | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 11000 | R4,R7 |
| hero.orbit.card | hero.orbit | cand:hero:scene-pause | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R42,R43,R44 |
| hero.orbit.card | hero.orbit | cand:hero.exit:faithful | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-22000) | R6,R8,R9,R20,R28 |
| hero.orbit.card | hero.orbit | cand:hero.exit:scoped | 5 / 5 | 3 (0-3) | 0 | 3 | 0 | 0 | 22000 (1000-22000) | R1,R3,R17,R27,R40 |
| hero.orbit.card | hero.orbit | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.orbit.card | hero.orbit | cand:morph.tween:waapi | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-22000) | R2,R5,R19,R24,R39 |
| hero.orbit.card | hero.orbit | cand:morph.tween:waapi-scoped | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 22000 | R10,R12 |
| hero.orbit.card | hero.orbit | cand:nav:earn-no-transition | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 22000 | R13,R15 |
| hero.deck.card | hero.deck | base | 33 / 33 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-22000) | 33 runs (see Runs per arm) |
| hero.deck.card | hero.deck | cand:?preset=v2-proved | 2 / 2 | 4 | 0 | 4 | 0 | 0 | 11000 | R4,R7 |
| hero.deck.card | hero.deck | cand:hero:scene-pause | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R42,R43,R44 |
| hero.deck.card | hero.deck | cand:hero.exit:faithful | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-22000) | R6,R8,R9,R20,R28 |
| hero.deck.card | hero.deck | cand:hero.exit:scoped | 5 / 5 | 3 (0-3) | 0 | 3 | 0 | 0 | 22000 (1000-22000) | R1,R3,R17,R27,R40 |
| hero.deck.card | hero.deck | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| hero.deck.card | hero.deck | cand:morph.tween:waapi | 5 / 5 | 0 (0-3) | 0 | 0 | 0 | 0 | 1000 (1000-22000) | R2,R5,R19,R24,R39 |
| hero.deck.card | hero.deck | cand:morph.tween:waapi-scoped | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 22000 | R10,R12 |
| hero.deck.card | hero.deck | cand:nav:earn-no-transition | 2 / 2 | 3 | 0 | 3 | 0 | 0 | 22000 | R13,R15 |

**macos-webkit 1280px, end-close, ideal line**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nav | nav | base | 23 / 23 | 8 (5-10) | 3 | 5 | 0 | 12 (6-20) | 1005 (1000-5317) | 23 runs (see Runs per arm) |
| nav | nav | cand:?preset=v2-proved | 2 / 2 | 8 (8-9) | 2 | 5 | 1 | 10 (10-14) | 3879 (3879-4296) | R4,R7 |
| nav | nav | cand:hero.exit:faithful | 7 / 7 | 8 (7-9) | 3 | 5 | 0 | 18 (6-20) | 1008 (1003-6584) | 7 runs (see Runs per arm) |
| nav | nav | cand:hero.exit:scoped | 7 / 7 | 8 (7-8) | 3 | 5 | 0 | 11 (6-20) | 1004 (1001-3691) | 7 runs (see Runs per arm) |
| nav | nav | cand:morph.tween:scroll-lock | 3 / 3 | 9 (7-10) | 3 | 5 | 1 | 11 (5-14) | 3009 (1001-3557) | R21,R22,R25 |
| nav | nav | cand:morph.tween:waapi | 2 / 2 | 5 (5-8) | 2 | 3 | 0 | 0 (0-10) | 1002 (1002-1005) | R19,R24 |
| nav | nav | orig | 23 / 23 | 8 (5-11) | 3 | 5 | 0 | 12 (5-20) | 1007 (1000-5160) | 23 runs (see Runs per arm) |
| logo | nav | base | 23 / 23 | 0 | 0 | 0 | 0 | 0 | 1143 (1084-1162) | 23 runs (see Runs per arm) |
| logo | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1122 (1122-1148) | R4,R7 |
| logo | nav | cand:hero.exit:faithful | 7 / 7 | 0 | 0 | 0 | 0 | 0 | 1154 (1102-1167) | 7 runs (see Runs per arm) |
| logo | nav | cand:hero.exit:scoped | 7 / 7 | 0 | 0 | 0 | 0 | 0 | 1128 (1104-1164) | 7 runs (see Runs per arm) |
| logo | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1135 (1082-1141) | R21,R22,R25 |
| logo | nav | cand:morph.tween:waapi | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1075 (1075-1099) | R19,R24 |
| logo | nav | orig | 23 / 23 | 0 | 0 | 0 | 0 | 0 | 1134 (1066-1156) | 23 runs (see Runs per arm) |
| actions | nav | base | 23 / 23 | 10 (8-15) | 5 | 5 | 0 | 11 (6-18) | 1124 (880-1628) | 23 runs (see Runs per arm) |
| actions | nav | cand:?preset=v2-proved | 2 / 2 | 9 (9-11) | 5 | 4 | 0 | 9 (9-13) | 1080 (1080-1160) | R4,R7 |
| actions | nav | cand:hero.exit:faithful | 7 / 7 | 12 (10-15) | 7 | 6 | 0 | 17 (6-18) | 1092 (977-1430) | 7 runs (see Runs per arm) |
| actions | nav | cand:hero.exit:scoped | 7 / 7 | 10 (9-13) | 6 | 4 | 0 | 11 (6-17) | 1119 (1007-2018) | 7 runs (see Runs per arm) |
| actions | nav | cand:morph.tween:scroll-lock | 3 / 3 | 9 (9-11) | 5 | 4 | 0 | 10 (5-13) | 1224 (986-1262) | R21,R22,R25 |
| actions | nav | cand:morph.tween:waapi | 2 / 2 | 8 (8-11) | 5 | 3 | 0 | 10 (10-15) | 1047 (1047-1555) | R19,R24 |
| actions | nav | orig | 23 / 23 | 9 (7-15) | 5 | 4 | 0 | 11 (5-18) | 1080 (850-1542) | 23 runs (see Runs per arm) |
| earn | nav | base | 23 / 23 | 18 (12-26) | 12 | 7 | 0 | 12 (6-20) | 1171 (880-1629) | 23 runs (see Runs per arm) |
| earn | nav | cand:?preset=v2-proved | 2 / 2 | 17 (17-19) | 11 | 6 | 0 | 10 (10-14) | 1160 (1160-1210) | R4,R7 |
| earn | nav | cand:hero.exit:faithful | 7 / 7 | 22 (15-26) | 15 | 8 | 0 | 18 (6-20) | 1093 (977-1430) | 7 runs (see Runs per arm) |
| earn | nav | cand:hero.exit:scoped | 7 / 7 | 17 (14-24) | 11 | 6 | 0 | 11 (6-20) | 1119 (1007-2018) | 7 runs (see Runs per arm) |
| earn | nav | cand:morph.tween:scroll-lock | 3 / 3 | 16 (13-20) | 10 | 6 | 0 | 11 (5-14) | 1260 (1049-1262) | R21,R22,R25 |
| earn | nav | cand:morph.tween:waapi | 2 / 2 | 16 (16-20) | 9 | 7 | 0 | 10 (10-15) | 1047 (1047-1717) | R19,R24 |
| earn | nav | orig | 23 / 23 | 18 (13-26) | 11 | 7 | 0 | 12 (5-20) | 1131 (850-1542) | 23 runs (see Runs per arm) |
| panel | morph.panel | base | 23 / 23 | 7 (5-8) | 5 | 2 | 0 | 1 (0-1) | 1100 (1000-1157) | 23 runs (see Runs per arm) |
| panel | morph.panel | cand:?preset=v2-proved | 2 / 2 | 6 (6-7) | 4 | 2 | 0 | 1 | 1000 | R4,R7 |
| panel | morph.panel | cand:hero.exit:faithful | 7 / 7 | 7 (6-8) | 5 | 2 | 0 | 1 | 1041 (1000-1100) | 7 runs (see Runs per arm) |
| panel | morph.panel | cand:hero.exit:scoped | 7 / 7 | 6 (5-8) | 5 | 2 | 0 | 1 (0-1) | 1076 (1000-1100) | 7 runs (see Runs per arm) |
| panel | morph.panel | cand:morph.tween:scroll-lock | 3 / 3 | 7 | 5 | 2 | 0 | 1 | 1110 (1000-1246) | R21,R22,R25 |
| panel | morph.panel | cand:morph.tween:waapi | 2 / 2 | 6 (6-7) | 4 | 2 | 0 | 0 (0-1) | 1148 (1148-1359) | R19,R24 |
| panel | morph.panel | orig | 23 / 23 | 7 (5-7) | 5 | 2 | 0 | 1 (0-1) | 1083 (1000-1269) | 23 runs (see Runs per arm) |

**macos-webkit 1280px, end-close, ideal ref**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nav | nav | base | 23 / 23 | 1 (0-2) | 1 | 0 | 0 | 12 (6-20) | 1004 (1000-1186) | 23 runs (see Runs per arm) |
| nav | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 10 (10-14) | 1007 (1007-1015) | R4,R7 |
| nav | nav | cand:hero.exit:faithful | 7 / 7 | 1 (0-2) | 1 | 0 | 0 | 18 (6-20) | 1008 (1003-1027) | 7 runs (see Runs per arm) |
| nav | nav | cand:hero.exit:scoped | 7 / 7 | 1 (0-2) | 1 | 0 | 0 | 11 (6-20) | 1005 (1001-1009) | 7 runs (see Runs per arm) |
| nav | nav | cand:morph.tween:scroll-lock | 3 / 3 | 2 (0-2) | 2 | 0 | 0 | 11 (5-14) | 1005 (1002-1005) | R21,R22,R25 |
| nav | nav | cand:morph.tween:waapi | 2 / 2 | 1 (1-2) | 1 | 0 | 0 | 1 (1-10) | 1004 (1004-1006) | R19,R24 |
| nav | nav | orig | 23 / 23 | 1 (0-2) | 1 | 0 | 0 | 12 (5-20) | 1004 (1000-1012) | 23 runs (see Runs per arm) |
| logo | nav | base | 23 / 23 | 0 | 0 | 0 | 0 | 0 | 1000 (999-1005) | 23 runs (see Runs per arm) |
| logo | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| logo | nav | cand:hero.exit:faithful | 7 / 7 | 0 | 0 | 0 | 0 | 0 | 1000 (1000-1005) | 7 runs (see Runs per arm) |
| logo | nav | cand:hero.exit:scoped | 7 / 7 | 0 | 0 | 0 | 0 | 0 | 1000 (999-1007) | 7 runs (see Runs per arm) |
| logo | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| logo | nav | cand:morph.tween:waapi | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R19,R24 |
| logo | nav | orig | 23 / 23 | 0 | 0 | 0 | 0 | 0 | 1000 (999-1001) | 23 runs (see Runs per arm) |
| actions | nav | base | 23 / 23 | 1 (0-2) | 1 | 0 | 0 | 11 (6-18) | 1000 (999-1116) | 23 runs (see Runs per arm) |
| actions | nav | cand:?preset=v2-proved | 2 / 2 | 0 (0-1) | 0 | 0 | 0 | 9 (9-13) | 1000 | R4,R7 |
| actions | nav | cand:hero.exit:faithful | 7 / 7 | 1 (0-2) | 1 | 0 | 0 | 17 (6-18) | 1000 (1000-1026) | 7 runs (see Runs per arm) |
| actions | nav | cand:hero.exit:scoped | 7 / 7 | 1 (0-1) | 1 | 0 | 0 | 11 (6-17) | 1001 (1000-1078) | 7 runs (see Runs per arm) |
| actions | nav | cand:morph.tween:scroll-lock | 3 / 3 | 2 (0-2) | 2 | 0 | 0 | 10 (5-13) | 1000 | R21,R22,R25 |
| actions | nav | cand:morph.tween:waapi | 2 / 2 | 1 | 1 | 0 | 0 | 10 (10-15) | 1000 | R19,R24 |
| actions | nav | orig | 23 / 23 | 1 (0-2) | 1 | 0 | 0 | 11 (5-18) | 1000 (999-1001) | 23 runs (see Runs per arm) |
| earn | nav | base | 23 / 23 | 13 (7-17) | 1 | 11 | 0 | 12 (6-20) | 4351 (1737-30700) | 23 runs (see Runs per arm) |
| earn | nav | cand:?preset=v2-proved | 2 / 2 | 9 (9-14) | 1 | 8 | 0 | 10 (10-14) | 4649 (4649-16300) | R4,R7 |
| earn | nav | cand:hero.exit:faithful | 7 / 7 | 17 (7-19) | 1 | 15 | 0 | 18 (6-20) | 3564 (1448-21571) | 7 runs (see Runs per arm) |
| earn | nav | cand:hero.exit:scoped | 7 / 7 | 12 (7-17) | 1 | 9 | 0 | 11 (6-20) | 5035 (2518-13166) | 7 runs (see Runs per arm) |
| earn | nav | cand:morph.tween:scroll-lock | 3 / 3 | 13 (5-13) | 1 | 10 | 0 | 11 (5-14) | 5204 (3193-6085) | R21,R22,R25 |
| earn | nav | cand:morph.tween:waapi | 2 / 2 | 12 (12-16) | 1 | 11 | 0 | 10 (10-15) | 1609 (1609-8466) | R19,R24 |
| earn | nav | orig | 23 / 23 | 11 (5-17) | 1 | 10 | 0 | 12 (5-20) | 4981 (1147-40916) | 23 runs (see Runs per arm) |
| panel | morph.panel | base | 23 / 23 | 0 (0-1) | 0 | 0 | 0 | 0 (0-1) | 1003 (1000-1133) | 23 runs (see Runs per arm) |
| panel | morph.panel | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| panel | morph.panel | cand:hero.exit:faithful | 7 / 7 | 0 (0-1) | 0 | 0 | 0 | 0 | 1005 (1000-1146) | 7 runs (see Runs per arm) |
| panel | morph.panel | cand:hero.exit:scoped | 7 / 7 | 0 (0-1) | 0 | 0 | 0 | 0 | 1001 (1000-1132) | 7 runs (see Runs per arm) |
| panel | morph.panel | cand:morph.tween:scroll-lock | 3 / 3 | 0 (0-1) | 0 | 0 | 0 | 0 | 1004 (1000-1051) | R21,R22,R25 |
| panel | morph.panel | cand:morph.tween:waapi | 2 / 2 | 1 | 1 | 0 | 0 | 0 | 1000 (1000-1030) | R19,R24 |
| panel | morph.panel | orig | 23 / 23 | 0 (0-1) | 0 | 0 | 0 | 0 | 1000 (1000-1036) | 23 runs (see Runs per arm) |

**macos-webkit 1280px, end-open, ideal line**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nav | nav | base | 23 / 23 | 10 (6-14) | 8 | 2 | 0 | 0 (0-1) | 1280 (1004-1624) | 23 runs (see Runs per arm) |
| nav | nav | cand:?preset=v2-proved | 2 / 2 | 9 (9-10) | 7 | 2 | 0 | 0 (0-1) | 1092 (1092-1232) | R4,R7 |
| nav | nav | cand:hero.exit:faithful | 7 / 7 | 12 (6-15) | 10 | 2 | 0 | 1 (0-1) | 1383 (1217-1665) | 7 runs (see Runs per arm) |
| nav | nav | cand:hero.exit:scoped | 7 / 7 | 9 (7-13) | 7 | 2 | 0 | 0 (0-1) | 1227 (1036-1520) | 7 runs (see Runs per arm) |
| nav | nav | cand:morph.tween:scroll-lock | 3 / 3 | 6 (5-9) | 5 | 1 | 0 | 0 (0-1) | 2098 (1697-2437) | R21,R22,R25 |
| nav | nav | cand:morph.tween:waapi | 2 / 2 | 6 (6-8) | 4 | 2 | 0 | 0 (0-1) | 1194 (1194-1200) | R19,R24 |
| nav | nav | orig | 23 / 23 | 9 (6-14) | 7 | 2 | 0 | 0 (0-1) | 1255 (1007-1598) | 23 runs (see Runs per arm) |
| logo | nav | base | 23 / 23 | 0 | 0 | 0 | 0 | 0 (0-1) | 999 (999-1013) | 23 runs (see Runs per arm) |
| logo | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 (0-1) | 1000 | R4,R7 |
| logo | nav | cand:hero.exit:faithful | 7 / 7 | 0 | 0 | 0 | 0 | 1 (0-1) | 1000 (999-1005) | 7 runs (see Runs per arm) |
| logo | nav | cand:hero.exit:scoped | 7 / 7 | 0 | 0 | 0 | 0 | 0 (0-1) | 1000 (999-1000) | 7 runs (see Runs per arm) |
| logo | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 (0-1) | 999 (999-1000) | R21,R22,R25 |
| logo | nav | cand:morph.tween:waapi | 2 / 2 | 0 | 0 | 0 | 0 | 0 (0-1) | 999 (999-1002) | R19,R24 |
| logo | nav | orig | 23 / 23 | 0 | 0 | 0 | 0 | 0 (0-1) | 1000 (999-1032) | 23 runs (see Runs per arm) |
| actions | nav | base | 23 / 23 | 10 (6-17) | 8 | 2 | 0 | 0 | 1863 (1486-2554) | 23 runs (see Runs per arm) |
| actions | nav | cand:?preset=v2-proved | 2 / 2 | 9 (9-11) | 7 | 2 | 0 | 0 | 1383 (1383-1653) | R4,R7 |
| actions | nav | cand:hero.exit:faithful | 7 / 7 | 13 (7-18) | 11 | 2 | 0 | 0 | 1914 (1634-2593) | 7 runs (see Runs per arm) |
| actions | nav | cand:hero.exit:scoped | 7 / 7 | 9 (8-15) | 7 | 2 | 0 | 0 | 1765 (1396-2245) | 7 runs (see Runs per arm) |
| actions | nav | cand:morph.tween:scroll-lock | 3 / 3 | 7 (6-11) | 6 | 1 | 0 | 0 | 2396 (1843-3000) | R21,R22,R25 |
| actions | nav | cand:morph.tween:waapi | 2 / 2 | 7 (7-9) | 5 | 2 | 0 | 0 | 1467 (1467-1496) | R19,R24 |
| actions | nav | orig | 23 / 23 | 9 (7-16) | 7 | 2 | 0 | 0 | 1698 (1358-2473) | 23 runs (see Runs per arm) |
| earn | nav | base | 23 / 23 | 13 (7-20) | 8 | 5 | 0 | 4 (1-6) | 1892 (1486-2554) | 23 runs (see Runs per arm) |
| earn | nav | cand:?preset=v2-proved | 2 / 2 | 12 (12-14) | 7 | 5 | 0 | 3 (3-6) | 1397 (1397-1654) | R4,R7 |
| earn | nav | cand:hero.exit:faithful | 7 / 7 | 16 (9-21) | 11 | 5 | 0 | 5 (2-7) | 1914 (1634-2593) | 7 runs (see Runs per arm) |
| earn | nav | cand:hero.exit:scoped | 7 / 7 | 12 (10-18) | 7 | 5 | 0 | 3 (2-5) | 1765 (1396-2245) | 7 runs (see Runs per arm) |
| earn | nav | cand:morph.tween:scroll-lock | 3 / 3 | 10 (9-15) | 6 | 4 | 0 | 2 (1-3) | 2396 (1843-3001) | R21,R22,R25 |
| earn | nav | cand:morph.tween:waapi | 2 / 2 | 8 (8-12) | 5 | 3 | 0 | 2 (2-3) | 1497 (1497-1532) | R19,R24 |
| earn | nav | orig | 23 / 23 | 13 (8-20) | 7 | 5 | 0 | 3 (1-7) | 1698 (1358-2474) | 23 runs (see Runs per arm) |
| panel | morph.panel | base | 23 / 23 | 8 (4-11) | 6 | 2 | 0 | 0 | 1330 (1268-1389) | 23 runs (see Runs per arm) |
| panel | morph.panel | cand:?preset=v2-proved | 2 / 2 | 8 (8-9) | 6 | 2 | 0 | 0 | 1290 (1290-1304) | R4,R7 |
| panel | morph.panel | cand:hero.exit:faithful | 7 / 7 | 10 (6-12) | 8 | 2 | 0 | 0 | 1290 (1258-1388) | 7 runs (see Runs per arm) |
| panel | morph.panel | cand:hero.exit:scoped | 7 / 7 | 7 (6-11) | 6 | 1 | 0 | 0 | 1313 (1273-1388) | 7 runs (see Runs per arm) |
| panel | morph.panel | cand:morph.tween:scroll-lock | 3 / 3 | 5 (4-8) | 4 | 1 | 0 | 0 | 1190 (1139-1388) | R21,R22,R25 |
| panel | morph.panel | cand:morph.tween:waapi | 2 / 2 | 6 (6-8) | 4 | 2 | 0 | 0 | 1363 (1363-1388) | R19,R24 |
| panel | morph.panel | orig | 23 / 23 | 8 (5-12) | 6 | 2 | 0 | 0 | 1320 (1286-1390) | 23 runs (see Runs per arm) |

**macos-webkit 1280px, end-open, ideal ref**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nav | nav | base | 23 / 23 | 0 (0-1) | 0 | 0 | 0 | 0 (0-1) | 1004 (1000-1109) | 23 runs (see Runs per arm) |
| nav | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 (0-1) | 1000 (1000-1003) | R4,R7 |
| nav | nav | cand:hero.exit:faithful | 7 / 7 | 0 | 0 | 0 | 0 | 1 (0-1) | 1005 (1001-1011) | 7 runs (see Runs per arm) |
| nav | nav | cand:hero.exit:scoped | 7 / 7 | 0 (0-1) | 0 | 0 | 0 | 0 (0-1) | 1004 (1000-1099) | 7 runs (see Runs per arm) |
| nav | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 (0-1) | 1029 (1007-1029) | R21,R22,R25 |
| nav | nav | cand:morph.tween:waapi | 2 / 2 | 0 (0-1) | 0 | 0 | 0 | 0 (0-1) | 1003 (1003-1078) | R19,R24 |
| nav | nav | orig | 23 / 23 | 0 | 0 | 0 | 0 | 0 (0-1) | 1003 (1000-1019) | 23 runs (see Runs per arm) |
| logo | nav | base | 23 / 23 | 0 | 0 | 0 | 0 | 0 (0-1) | 1000 (999-1013) | 23 runs (see Runs per arm) |
| logo | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 (0-1) | 1000 | R4,R7 |
| logo | nav | cand:hero.exit:faithful | 7 / 7 | 0 | 0 | 0 | 0 | 1 (0-1) | 1000 (999-1000) | 7 runs (see Runs per arm) |
| logo | nav | cand:hero.exit:scoped | 7 / 7 | 0 | 0 | 0 | 0 | 0 (0-1) | 1000 (999-1013) | 7 runs (see Runs per arm) |
| logo | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 (0-1) | 1000 (1000-1009) | R21,R22,R25 |
| logo | nav | cand:morph.tween:waapi | 2 / 2 | 0 | 0 | 0 | 0 | 0 (0-1) | 1000 (1000-1001) | R19,R24 |
| logo | nav | orig | 23 / 23 | 0 | 0 | 0 | 0 | 0 (0-1) | 1000 (999-1000) | 23 runs (see Runs per arm) |
| actions | nav | base | 23 / 23 | 0 (0-2) | 0 | 0 | 0 | 0 | 1000 (999-1302) | 23 runs (see Runs per arm) |
| actions | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| actions | nav | cand:hero.exit:faithful | 7 / 7 | 0 | 0 | 0 | 0 | 0 | 1000 (999-1000) | 7 runs (see Runs per arm) |
| actions | nav | cand:hero.exit:scoped | 7 / 7 | 0 (0-2) | 0 | 0 | 0 | 0 | 1000 (1000-1250) | 7 runs (see Runs per arm) |
| actions | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| actions | nav | cand:morph.tween:waapi | 2 / 2 | 0 (0-1) | 0 | 0 | 0 | 0 | 942 (942-994) | R19,R24 |
| actions | nav | orig | 23 / 23 | 0 | 0 | 0 | 0 | 0 | 1000 | 23 runs (see Runs per arm) |
| earn | nav | base | 23 / 23 | 4 (1-8) | 2 | 2 | 0 | 4 (1-6) | 1048 (1000-1599) | 23 runs (see Runs per arm) |
| earn | nav | cand:?preset=v2-proved | 2 / 2 | 2 (2-6) | 1 | 1 | 0 | 3 (3-6) | 1000 (1000-1201) | R4,R7 |
| earn | nav | cand:hero.exit:faithful | 7 / 7 | 2 (1-9) | 1 | 1 | 0 | 5 (2-7) | 1000 (999-1136) | 7 runs (see Runs per arm) |
| earn | nav | cand:hero.exit:scoped | 7 / 7 | 4 (2-9) | 2 | 2 | 1 | 3 (2-5) | 1032 (1000-1483) | 7 runs (see Runs per arm) |
| earn | nav | cand:morph.tween:scroll-lock | 3 / 3 | 3 (3-7) | 2 | 1 | 0 | 2 (1-3) | 1000 (1000-1059) | R21,R22,R25 |
| earn | nav | cand:morph.tween:waapi | 2 / 2 | 3 (3-4) | 1 | 2 | 0 | 2 (2-3) | 994 (994-1243) | R19,R24 |
| earn | nav | orig | 23 / 23 | 4 (1-8) | 1 | 2 | 0 | 3 (1-7) | 1023 (1000-1441) | 23 runs (see Runs per arm) |
| panel | morph.panel | base | 23 / 23 | 0 (0-1) | 0 | 0 | 0 | 0 | 1001 (1000-1071) | 23 runs (see Runs per arm) |
| panel | morph.panel | cand:?preset=v2-proved | 2 / 2 | 1 | 1 | 0 | 0 | 0 | 1001 (1001-1058) | R4,R7 |
| panel | morph.panel | cand:hero.exit:faithful | 7 / 7 | 1 (0-1) | 1 | 0 | 0 | 0 | 1004 (1000-1090) | 7 runs (see Runs per arm) |
| panel | morph.panel | cand:hero.exit:scoped | 7 / 7 | 0 (0-1) | 0 | 0 | 0 | 0 | 1002 (1000-1058) | 7 runs (see Runs per arm) |
| panel | morph.panel | cand:morph.tween:scroll-lock | 3 / 3 | 0 (0-1) | 0 | 0 | 0 | 0 | 1047 (1002-1058) | R21,R22,R25 |
| panel | morph.panel | cand:morph.tween:waapi | 2 / 2 | 1 | 1 | 0 | 0 | 0 | 1020 (1020-1030) | R19,R24 |
| panel | morph.panel | orig | 23 / 23 | 1 (0-1) | 1 | 0 | 0 | 0 | 1010 (1000-1045) | 23 runs (see Runs per arm) |

**macos-webkit 1280px, hero, ideal line**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero.track | hero.exit | base | 8 / 8 | 0 | 0 | 0 | 0 | 0 | 1000 | 8 runs (see Runs per arm) |
| hero.track | hero.exit | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.track | hero.exit | cand:hero.exit:faithful | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R8,R11,R20 |
| hero.track | hero.exit | cand:hero.exit:scoped | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R1,R3,R17 |
| hero.stage | hero.exit | base | 8 / 8 | 0 | 0 | 0 | 0 | 0 | 1099 | 8 runs (see Runs per arm) |
| hero.stage | hero.exit | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R4,R7 |
| hero.stage | hero.exit | cand:hero.exit:faithful | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1099 | R8,R11,R20 |
| hero.stage | hero.exit | cand:hero.exit:scoped | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1099 | R1,R3,R17 |
| hero.copy | hero | base | 8 / 8 | 2 | 1 | 1 | 0 | 0 | 2000 | 8 runs (see Runs per arm) |
| hero.copy | hero | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1015 | R4,R7 |
| hero.copy | hero | cand:hero.exit:faithful | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 2000 | R8,R11,R20 |
| hero.copy | hero | cand:hero.exit:scoped | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 2000 | R1,R3,R17 |
| hero.cta | hero | base | 8 / 8 | 2 | 1 | 1 | 0 | 0 | 1966 | 8 runs (see Runs per arm) |
| hero.cta | hero | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.cta | hero | cand:hero.exit:faithful | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1966 | R8,R11,R20 |
| hero.cta | hero | cand:hero.exit:scoped | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1966 | R1,R3,R17 |
| hero.countdown.unit | hero.countdown | base | 8 / 8 | 2 | 1 | 1 | 0 | 0 | 1966 | 8 runs (see Runs per arm) |
| hero.countdown.unit | hero.countdown | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.countdown.unit | hero.countdown | cand:hero.exit:faithful | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1966 | R8,R11,R20 |
| hero.countdown.unit | hero.countdown | cand:hero.exit:scoped | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1966 | R1,R3,R17 |
| hero.cue | hero.cue | base | 8 / 8 | 2 | 1 | 1 | 0 | 0 | 2000 | 8 runs (see Runs per arm) |
| hero.cue | hero.cue | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1015 | R4,R7 |
| hero.cue | hero.cue | cand:hero.exit:faithful | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 2000 | R8,R11,R20 |
| hero.cue | hero.cue | cand:hero.exit:scoped | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 2000 | R1,R3,R17 |
| hero.orbit | hero.orbit | base | 8 / 8 | 0 | 0 | 0 | 0 | 0 | 1099 | 8 runs (see Runs per arm) |
| hero.orbit | hero.orbit | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R4,R7 |
| hero.orbit | hero.orbit | cand:hero.exit:faithful | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1099 | R8,R11,R20 |
| hero.orbit | hero.orbit | cand:hero.exit:scoped | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1099 | R1,R3,R17 |
| hero.orbit.stage | hero.orbit | base | 8 / 8 | 0 | 0 | 0 | 0 | 0 | 1099 | 8 runs (see Runs per arm) |
| hero.orbit.stage | hero.orbit | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R4,R7 |
| hero.orbit.stage | hero.orbit | cand:hero.exit:faithful | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1099 | R8,R11,R20 |
| hero.orbit.stage | hero.orbit | cand:hero.exit:scoped | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1099 | R1,R3,R17 |
| hero.orbit.card | hero.orbit | base | 8 / 8 | 2 | 1 | 1 | 0 | 0 | 1982 | 8 runs (see Runs per arm) |
| hero.orbit.card | hero.orbit | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.orbit.card | hero.orbit | cand:hero.exit:faithful | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1982 | R8,R11,R20 |
| hero.orbit.card | hero.orbit | cand:hero.exit:scoped | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1982 | R1,R3,R17 |
| hero.deck.card | hero.deck | base | 8 / 8 | 2 | 1 | 1 | 0 | 0 | 2000 | 8 runs (see Runs per arm) |
| hero.deck.card | hero.deck | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.deck.card | hero.deck | cand:hero.exit:faithful | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 2000 | R8,R11,R20 |
| hero.deck.card | hero.deck | cand:hero.exit:scoped | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 2000 | R1,R3,R17 |

**macos-webkit 390px, end-close, ideal line**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nav | nav | base | 24 / 24 | 8 (5-11) | 4 | 4 | 0 | 10 (6-17) | 1220 (1000-7503) | 24 runs (see Runs per arm) |
| nav | nav | cand:?preset=v2-proved | 2 / 2 | 10 | 3 | 5 | 1 | 15 (15-18) | 5183 (5183-5344) | R4,R7 |
| nav | nav | cand:hero.exit:faithful | 7 / 7 | 8 (7-10) | 4 | 4 | 0 | 10 (6-13) | 1193 (1059-4648) | 7 runs (see Runs per arm) |
| nav | nav | cand:hero.exit:scoped | 7 / 7 | 7 (6-8) | 3 | 4 | 0 | 10 (7-16) | 1288 (1044-4406) | 7 runs (see Runs per arm) |
| nav | nav | cand:morph.tween:scroll-lock | 3 / 3 | 7 (6-8) | 3 | 3 | 1 | 6 (4-11) | 4168 (1291-4452) | R21,R22,R25 |
| nav | nav | cand:morph.tween:waapi | 2 / 2 | 6 (6-7) | 3 | 3 | 0 | 0 (0-6) | 1026 (1026-1544) | R19,R24 |
| nav | nav | orig | 24 / 24 | 8 (6-12) | 3 | 5 | 0 | 10 (6-17) | 1101 (1001-5909) | 24 runs (see Runs per arm) |
| logo | nav | base | 24 / 24 | 13 (9-15) | 10 | 3 | 0 | 0 | 4685 (3478-6631) | 24 runs (see Runs per arm) |
| logo | nav | cand:?preset=v2-proved | 2 / 2 | 13 | 12 | 1 | 0 | 0 | 4599 (4599-4802) | R4,R7 |
| logo | nav | cand:hero.exit:faithful | 7 / 7 | 13 (10-15) | 10 | 3 | 0 | 0 | 4314 (4115-5146) | 7 runs (see Runs per arm) |
| logo | nav | cand:hero.exit:scoped | 7 / 7 | 13 (10-15) | 10 | 2 | 0 | 0 | 4422 (3782-5347) | 7 runs (see Runs per arm) |
| logo | nav | cand:morph.tween:scroll-lock | 3 / 3 | 11 (10-12) | 9 | 2 | 0 | 0 | 4098 (3270-4786) | R21,R22,R25 |
| logo | nav | cand:morph.tween:waapi | 2 / 2 | 10 (10-13) | 8 | 2 | 0 | 0 | 3866 (3866-4340) | R19,R24 |
| logo | nav | orig | 24 / 24 | 15 (10-21) | 12 | 4 | 0 | 0 | 4239 (3089-5347) | 24 runs (see Runs per arm) |
| actions | nav | base | 24 / 24 | 10 (8-12) | 6 | 4 | 0 | 10 (6-15) | 1872 (1510-2561) | 24 runs (see Runs per arm) |
| actions | nav | cand:?preset=v2-proved | 2 / 2 | 11 | 7 | 4 | 0 | 13 (13-15) | 1556 (1556-1774) | R4,R7 |
| actions | nav | cand:hero.exit:faithful | 7 / 7 | 9 (9-11) | 6 | 4 | 0 | 10 (6-12) | 2061 (1781-2710) | 7 runs (see Runs per arm) |
| actions | nav | cand:hero.exit:scoped | 7 / 7 | 9 (8-10) | 6 | 3 | 0 | 9 (7-14) | 1979 (1638-2497) | 7 runs (see Runs per arm) |
| actions | nav | cand:morph.tween:scroll-lock | 3 / 3 | 9 (8-10) | 6 | 3 | 0 | 6 (4-10) | 1993 (1765-2120) | R21,R22,R25 |
| actions | nav | cand:morph.tween:waapi | 2 / 2 | 9 | 5 | 3 | 0 | 6 (6-11) | 1649 (1649-1915) | R19,R24 |
| actions | nav | orig | 24 / 24 | 10 (8-14) | 6 | 4 | 0 | 9 (6-15) | 1486 (1085-1888) | 24 runs (see Runs per arm) |
| earn | nav | base | 24 / 24 | 18 (13-22) | 11 | 7 | 0 | 11 (6-17) | 1872 (1529-2559) | 24 runs (see Runs per arm) |
| earn | nav | cand:?preset=v2-proved | 2 / 2 | 20 (20-21) | 12 | 8 | 0 | 15 (15-18) | 1556 (1556-1775) | R4,R7 |
| earn | nav | cand:hero.exit:faithful | 7 / 7 | 17 (15-20) | 10 | 6 | 0 | 10 (6-13) | 2082 (1782-2710) | 7 runs (see Runs per arm) |
| earn | nav | cand:hero.exit:scoped | 7 / 7 | 18 (15-19) | 10 | 7 | 0 | 10 (7-16) | 1979 (1636-2497) | 7 runs (see Runs per arm) |
| earn | nav | cand:morph.tween:scroll-lock | 3 / 3 | 15 (11-17) | 10 | 5 | 0 | 6 (4-11) | 2032 (1889-2120) | R21,R22,R25 |
| earn | nav | cand:morph.tween:waapi | 2 / 2 | 14 (14-16) | 8 | 6 | 0 | 6 (6-11) | 1651 (1651-2295) | R19,R24 |
| earn | nav | orig | 24 / 24 | 19 (14-25) | 12 | 7 | 0 | 10 (6-17) | 1516 (1084-1888) | 24 runs (see Runs per arm) |
| panel | morph.panel | base | 24 / 24 | 6 (4-8) | 4 | 2 | 0 | 1 (0-1) | 1254 (1000-1388) | 24 runs (see Runs per arm) |
| panel | morph.panel | cand:?preset=v2-proved | 2 / 2 | 5 (5-6) | 4 | 1 | 0 | 1 | 1121 (1121-1125) | R4,R7 |
| panel | morph.panel | cand:hero.exit:faithful | 7 / 7 | 6 (6-7) | 4 | 2 | 0 | 0 (0-1) | 1368 (1100-1389) | 7 runs (see Runs per arm) |
| panel | morph.panel | cand:hero.exit:scoped | 7 / 7 | 6 (6-7) | 4 | 2 | 0 | 1 (0-1) | 1242 (1111-1389) | 7 runs (see Runs per arm) |
| panel | morph.panel | cand:morph.tween:scroll-lock | 3 / 3 | 6 | 4 | 2 | 0 | 0 | 1161 (1100-1389) | R21,R22,R25 |
| panel | morph.panel | cand:morph.tween:waapi | 2 / 2 | 6 (6-7) | 4 | 2 | 0 | 0 (0-1) | 1345 (1345-1355) | R19,R24 |
| panel | morph.panel | orig | 24 / 24 | 7 (6-8) | 5 | 2 | 0 | 1 (0-1) | 1244 (1061-1388) | 24 runs (see Runs per arm) |

**macos-webkit 390px, end-close, ideal ref**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nav | nav | base | 24 / 24 | 2 (0-3) | 1 | 0 | 0 | 10 (6-17) | 1014 (1000-1252) | 24 runs (see Runs per arm) |
| nav | nav | cand:?preset=v2-proved | 2 / 2 | 1 (1-2) | 1 | 0 | 0 | 15 (15-18) | 1153 (1153-1206) | R4,R7 |
| nav | nav | cand:hero.exit:faithful | 7 / 7 | 1 (1-2) | 1 | 0 | 0 | 10 (6-13) | 1006 (1001-1013) | 7 runs (see Runs per arm) |
| nav | nav | cand:hero.exit:scoped | 7 / 7 | 1 (1-2) | 1 | 0 | 0 | 10 (7-16) | 1007 (1004-1079) | 7 runs (see Runs per arm) |
| nav | nav | cand:morph.tween:scroll-lock | 3 / 3 | 1 (0-2) | 1 | 0 | 0 | 6 (4-11) | 1012 (1008-1046) | R21,R22,R25 |
| nav | nav | cand:morph.tween:waapi | 2 / 2 | 1 (1-4) | 1 | 0 | 0 | 1 (1-6) | 1000 (1000-1039) | R19,R24 |
| nav | nav | orig | 24 / 24 | 2 (1-3) | 1 | 0 | 0 | 10 (6-17) | 1015 (1000-1259) | 24 runs (see Runs per arm) |
| logo | nav | base | 24 / 24 | 2 (1-5) | 1 | 1 | 0 | 0 | 1025 (1000-1499) | 24 runs (see Runs per arm) |
| logo | nav | cand:?preset=v2-proved | 2 / 2 | 5 (5-6) | 5 | 0 | 0 | 0 | 1000 (1000-1199) | R4,R7 |
| logo | nav | cand:hero.exit:faithful | 7 / 7 | 2 (1-4) | 1 | 1 | 0 | 0 (0-1) | 1040 (1000-1181) | 7 runs (see Runs per arm) |
| logo | nav | cand:hero.exit:scoped | 7 / 7 | 2 (2-4) | 1 | 1 | 0 | 0 | 1090 (1000-1375) | 7 runs (see Runs per arm) |
| logo | nav | cand:morph.tween:scroll-lock | 3 / 3 | 2 | 1 | 1 | 0 | 0 (0-1) | 1000 (1000-1001) | R21,R22,R25 |
| logo | nav | cand:morph.tween:waapi | 2 / 2 | 2 (2-3) | 1 | 1 | 0 | 0 | 1032 (1032-1197) | R19,R24 |
| logo | nav | orig | 24 / 24 | 2 (1-6) | 1 | 1 | 0 | 0 | 1133 (1000-1521) | 24 runs (see Runs per arm) |
| actions | nav | base | 24 / 24 | 1 (0-2) | 1 | 0 | 0 | 10 (6-15) | 1000 (999-1010) | 24 runs (see Runs per arm) |
| actions | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 13 (13-15) | 1000 | R4,R7 |
| actions | nav | cand:hero.exit:faithful | 7 / 7 | 1 (0-2) | 1 | 0 | 0 | 10 (6-12) | 1000 | 7 runs (see Runs per arm) |
| actions | nav | cand:hero.exit:scoped | 7 / 7 | 1 (0-1) | 1 | 0 | 0 | 9 (7-14) | 1000 | 7 runs (see Runs per arm) |
| actions | nav | cand:morph.tween:scroll-lock | 3 / 3 | 1 (1-2) | 1 | 0 | 0 | 6 (4-10) | 1000 (999-1000) | R21,R22,R25 |
| actions | nav | cand:morph.tween:waapi | 2 / 2 | 1 | 1 | 0 | 0 | 6 (6-11) | 999 (999-1000) | R19,R24 |
| actions | nav | orig | 24 / 24 | 1 (0-2) | 1 | 0 | 0 | 9 (6-15) | 1000 (1000-1001) | 24 runs (see Runs per arm) |
| earn | nav | base | 24 / 24 | 11 (7-17) | 1 | 10 | 0 | 11 (6-17) | 1955 (1000-4940) | 24 runs (see Runs per arm) |
| earn | nav | cand:?preset=v2-proved | 2 / 2 | 15 (15-17) | 1 | 14 | 0 | 15 (15-18) | 1797 (1797-2180) | R4,R7 |
| earn | nav | cand:hero.exit:faithful | 7 / 7 | 11 (8-14) | 1 | 9 | 0 | 10 (6-13) | 2085 (1254-4583) | 7 runs (see Runs per arm) |
| earn | nav | cand:hero.exit:scoped | 7 / 7 | 10 (8-16) | 1 | 9 | 0 | 10 (7-16) | 1270 (999-3786) | 7 runs (see Runs per arm) |
| earn | nav | cand:morph.tween:scroll-lock | 3 / 3 | 8 (5-12) | 1 | 7 | 0 | 6 (4-11) | 7428 (2008-8936) | R21,R22,R25 |
| earn | nav | cand:morph.tween:waapi | 2 / 2 | 8 (8-11) | 1 | 6 | 0 | 6 (6-11) | 1254 (1254-6508) | R19,R24 |
| earn | nav | orig | 24 / 24 | 10 (7-17) | 1 | 9 | 0 | 10 (6-17) | 1944 (1000-8808) | 24 runs (see Runs per arm) |
| panel | morph.panel | base | 24 / 24 | 0 (0-1) | 0 | 0 | 0 | 0 (0-1) | 1002 (1000-1111) | 24 runs (see Runs per arm) |
| panel | morph.panel | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| panel | morph.panel | cand:hero.exit:faithful | 7 / 7 | 0 | 0 | 0 | 0 | 0 | 1000 (1000-1005) | 7 runs (see Runs per arm) |
| panel | morph.panel | cand:hero.exit:scoped | 7 / 7 | 0 | 0 | 0 | 0 | 0 | 1003 (1000-1076) | 7 runs (see Runs per arm) |
| panel | morph.panel | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 (1000-1020) | R21,R22,R25 |
| panel | morph.panel | cand:morph.tween:waapi | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1001 (1001-1002) | R19,R24 |
| panel | morph.panel | orig | 24 / 24 | 0 (0-1) | 0 | 0 | 0 | 0 | 1003 (1000-1071) | 24 runs (see Runs per arm) |

**macos-webkit 390px, end-open, ideal line**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nav | nav | base | 24 / 24 | 8 (6-13) | 6 | 2 | 0 | 1 (0-1) | 1192 (1027-1496) | 24 runs (see Runs per arm) |
| nav | nav | cand:?preset=v2-proved | 2 / 2 | 12 (12-13) | 10 | 2 | 0 | 1 | 1463 (1463-1530) | R4,R7 |
| nav | nav | cand:hero.exit:faithful | 7 / 7 | 9 (8-10) | 7 | 2 | 0 | 1 (0-1) | 1328 (1091-1412) | 7 runs (see Runs per arm) |
| nav | nav | cand:hero.exit:scoped | 7 / 7 | 9 (6-11) | 7 | 2 | 0 | 1 (0-1) | 1136 (1089-1313) | 7 runs (see Runs per arm) |
| nav | nav | cand:morph.tween:scroll-lock | 3 / 3 | 5 (5-10) | 4 | 1 | 0 | 0 (0-1) | 2039 (1324-2274) | R21,R22,R25 |
| nav | nav | cand:morph.tween:waapi | 2 / 2 | 8 (8-10) | 6 | 2 | 0 | 0 (0-1) | 1371 (1371-1407) | R19,R24 |
| nav | nav | orig | 24 / 24 | 8 (6-11) | 6 | 2 | 0 | 1 (0-1) | 1123 (1010-1453) | 24 runs (see Runs per arm) |
| logo | nav | base | 24 / 24 | 10 (7-15) | 8 | 1 | 0 | 1 (0-1) | 2742 (2365-3249) | 24 runs (see Runs per arm) |
| logo | nav | cand:?preset=v2-proved | 2 / 2 | 14 (14-15) | 13 | 1 | 0 | 1 | 3034 (3034-3088) | R4,R7 |
| logo | nav | cand:hero.exit:faithful | 7 / 7 | 11 (9-13) | 9 | 2 | 0 | 1 (0-1) | 2804 (2512-3117) | 7 runs (see Runs per arm) |
| logo | nav | cand:hero.exit:scoped | 7 / 7 | 10 (7-15) | 9 | 1 | 0 | 0 (0-1) | 2651 (2439-3430) | 7 runs (see Runs per arm) |
| logo | nav | cand:morph.tween:scroll-lock | 3 / 3 | 6 (6-14) | 5 | 1 | 0 | 0 | 2489 (2312-3140) | R21,R22,R25 |
| logo | nav | cand:morph.tween:waapi | 2 / 2 | 9 (9-12) | 8 | 1 | 0 | 0 (0-1) | 2133 (2133-3030) | R19,R24 |
| logo | nav | orig | 24 / 24 | 10 (7-15) | 8 | 2 | 0 | 0 (0-1) | 2649 (2161-3346) | 24 runs (see Runs per arm) |
| actions | nav | base | 24 / 24 | 10 (7-15) | 8 | 2 | 0 | 0 | 1886 (1501-2323) | 24 runs (see Runs per arm) |
| actions | nav | cand:?preset=v2-proved | 2 / 2 | 13 (13-15) | 11 | 2 | 0 | 0 | 2024 (2024-2181) | R4,R7 |
| actions | nav | cand:hero.exit:faithful | 7 / 7 | 10 (9-11) | 8 | 2 | 0 | 0 | 1829 (1770-2014) | 7 runs (see Runs per arm) |
| actions | nav | cand:hero.exit:scoped | 7 / 7 | 10 (7-12) | 8 | 2 | 0 | 0 | 1907 (1754-2181) | 7 runs (see Runs per arm) |
| actions | nav | cand:morph.tween:scroll-lock | 3 / 3 | 6 (6-11) | 5 | 1 | 0 | 0 | 2312 (2251-2489) | R21,R22,R25 |
| actions | nav | cand:morph.tween:waapi | 2 / 2 | 9 (9-11) | 7 | 2 | 0 | 0 | 1556 (1556-1768) | R19,R24 |
| actions | nav | orig | 24 / 24 | 9 (7-12) | 7 | 2 | 0 | 0 | 1758 (1349-2142) | 24 runs (see Runs per arm) |
| earn | nav | base | 24 / 24 | 11 (8-18) | 8 | 4 | 0 | 3 (2-8) | 1886 (1501-2323) | 24 runs (see Runs per arm) |
| earn | nav | cand:?preset=v2-proved | 2 / 2 | 15 (15-18) | 11 | 4 | 0 | 7 | 2025 (2025-2180) | R4,R7 |
| earn | nav | cand:hero.exit:faithful | 7 / 7 | 12 (10-14) | 8 | 4 | 0 | 2 (1-7) | 1830 (1771-2013) | 7 runs (see Runs per arm) |
| earn | nav | cand:hero.exit:scoped | 7 / 7 | 12 (8-15) | 8 | 4 | 0 | 3 (2-7) | 1908 (1753-2180) | 7 runs (see Runs per arm) |
| earn | nav | cand:morph.tween:scroll-lock | 3 / 3 | 10 (8-13) | 5 | 4 | 0 | 2 (2-4) | 2312 (2251-2489) | R21,R22,R25 |
| earn | nav | cand:morph.tween:waapi | 2 / 2 | 10 (10-14) | 7 | 3 | 0 | 2 (2-6) | 1753 (1753-1768) | R19,R24 |
| earn | nav | orig | 24 / 24 | 11 (7-15) | 7 | 4 | 0 | 2 (1-6) | 1768 (1542-2143) | 24 runs (see Runs per arm) |
| panel | morph.panel | base | 24 / 24 | 8 (5-11) | 6 | 2 | 0 | 0 | 1389 (1296-1390) | 24 runs (see Runs per arm) |
| panel | morph.panel | cand:?preset=v2-proved | 2 / 2 | 9 (9-11) | 7 | 2 | 0 | 0 | 1291 (1291-1311) | R4,R7 |
| panel | morph.panel | cand:hero.exit:faithful | 7 / 7 | 7 (7-9) | 5 | 2 | 0 | 0 | 1389 (1388-1390) | 7 runs (see Runs per arm) |
| panel | morph.panel | cand:hero.exit:scoped | 7 / 7 | 8 (6-11) | 6 | 2 | 0 | 0 | 1389 (1388-1391) | 7 runs (see Runs per arm) |
| panel | morph.panel | cand:morph.tween:scroll-lock | 3 / 3 | 4 (4-9) | 3 | 1 | 0 | 0 | 1204 (1172-1389) | R21,R22,R25 |
| panel | morph.panel | cand:morph.tween:waapi | 2 / 2 | 7 (7-9) | 5 | 2 | 0 | 0 | 1388 (1388-1389) | R19,R24 |
| panel | morph.panel | orig | 24 / 24 | 7 (5-10) | 5 | 2 | 0 | 0 | 1389 (1323-1390) | 24 runs (see Runs per arm) |

**macos-webkit 390px, end-open, ideal ref**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| nav | nav | base | 24 / 24 | 1 (0-2) | 1 | 0 | 0 | 1 (0-1) | 1015 (1000-1117) | 24 runs (see Runs per arm) |
| nav | nav | cand:?preset=v2-proved | 2 / 2 | 0 (0-1) | 0 | 0 | 0 | 1 | 1003 (1003-1005) | R4,R7 |
| nav | nav | cand:hero.exit:faithful | 7 / 7 | 1 (0-2) | 1 | 0 | 0 | 1 (0-1) | 1009 (1003-1078) | 7 runs (see Runs per arm) |
| nav | nav | cand:hero.exit:scoped | 7 / 7 | 1 (0-1) | 1 | 0 | 0 | 0 (0-1) | 1038 (1002-1121) | 7 runs (see Runs per arm) |
| nav | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 (0-1) | 0 | 0 | 0 | 0 | 1007 (1004-1035) | R21,R22,R25 |
| nav | nav | cand:morph.tween:waapi | 2 / 2 | 0 (0-1) | 0 | 0 | 0 | 0 (0-1) | 1012 (1012-1024) | R19,R24 |
| nav | nav | orig | 24 / 24 | 1 (0-3) | 0 | 0 | 0 | 0 (0-1) | 1025 (1004-1090) | 24 runs (see Runs per arm) |
| logo | nav | base | 24 / 24 | 2 (1-7) | 1 | 1 | 0 | 1 (0-1) | 1061 (1000-1544) | 24 runs (see Runs per arm) |
| logo | nav | cand:?preset=v2-proved | 2 / 2 | 6 (6-7) | 6 | 0 | 0 | 1 | 1000 | R4,R7 |
| logo | nav | cand:hero.exit:faithful | 7 / 7 | 2 (2-4) | 1 | 1 | 0 | 1 (0-1) | 1112 (1000-1532) | 7 runs (see Runs per arm) |
| logo | nav | cand:hero.exit:scoped | 7 / 7 | 2 (2-4) | 1 | 1 | 0 | 1 (0-1) | 1077 (1000-1279) | 7 runs (see Runs per arm) |
| logo | nav | cand:morph.tween:scroll-lock | 3 / 3 | 2 (0-2) | 1 | 1 | 0 | 0 (0-1) | 1195 (1009-1242) | R21,R22,R25 |
| logo | nav | cand:morph.tween:waapi | 2 / 2 | 3 | 1 | 1 | 0 | 0 (0-1) | 1000 (1000-1088) | R19,R24 |
| logo | nav | orig | 24 / 24 | 2 (0-3) | 1 | 1 | 0 | 0 (0-1) | 1068 (1000-1527) | 24 runs (see Runs per arm) |
| actions | nav | base | 24 / 24 | 0 (0-1) | 0 | 0 | 0 | 0 | 1000 (999-1111) | 24 runs (see Runs per arm) |
| actions | nav | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| actions | nav | cand:hero.exit:faithful | 7 / 7 | 0 (0-1) | 0 | 0 | 0 | 0 | 1000 (1000-1082) | 7 runs (see Runs per arm) |
| actions | nav | cand:hero.exit:scoped | 7 / 7 | 0 | 0 | 0 | 0 | 0 | 1000 (999-1028) | 7 runs (see Runs per arm) |
| actions | nav | cand:morph.tween:scroll-lock | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R21,R22,R25 |
| actions | nav | cand:morph.tween:waapi | 2 / 2 | 0 (0-1) | 0 | 0 | 0 | 0 | 1007 (1007-1038) | R19,R24 |
| actions | nav | orig | 24 / 24 | 0 | 0 | 0 | 0 | 0 | 1000 (999-1000) | 24 runs (see Runs per arm) |
| earn | nav | base | 24 / 24 | 4 (1-7) | 1 | 2 | 1 | 3 (2-8) | 1034 (1000-1349) | 24 runs (see Runs per arm) |
| earn | nav | cand:?preset=v2-proved | 2 / 2 | 2 | 0 | 1 | 0 | 7 | 1018 (1018-1026) | R4,R7 |
| earn | nav | cand:hero.exit:faithful | 7 / 7 | 3 (2-6) | 2 | 2 | 0 | 2 (1-7) | 1090 (1000-1227) | 7 runs (see Runs per arm) |
| earn | nav | cand:hero.exit:scoped | 7 / 7 | 5 (1-6) | 2 | 2 | 1 | 3 (2-7) | 1016 (1000-1264) | 7 runs (see Runs per arm) |
| earn | nav | cand:morph.tween:scroll-lock | 3 / 3 | 3 | 2 | 1 | 0 | 2 (2-4) | 1002 (1000-1023) | R21,R22,R25 |
| earn | nav | cand:morph.tween:waapi | 2 / 2 | 4 (4-6) | 2 | 1 | 0 | 2 (2-6) | 1079 (1079-1122) | R19,R24 |
| earn | nav | orig | 24 / 24 | 3 (1-5) | 1 | 2 | 0 | 2 (1-6) | 1047 (1000-1430) | 24 runs (see Runs per arm) |
| panel | morph.panel | base | 24 / 24 | 0 (0-1) | 0 | 0 | 0 | 0 | 1001 (1000-1083) | 24 runs (see Runs per arm) |
| panel | morph.panel | cand:?preset=v2-proved | 2 / 2 | 0 (0-1) | 0 | 0 | 0 | 0 | 1000 (1000-1076) | R4,R7 |
| panel | morph.panel | cand:hero.exit:faithful | 7 / 7 | 0 (0-1) | 0 | 0 | 0 | 0 | 1001 (1000-1062) | 7 runs (see Runs per arm) |
| panel | morph.panel | cand:hero.exit:scoped | 7 / 7 | 1 (0-1) | 1 | 0 | 0 | 0 | 1001 (1000-1076) | 7 runs (see Runs per arm) |
| panel | morph.panel | cand:morph.tween:scroll-lock | 3 / 3 | 0 (0-1) | 0 | 0 | 0 | 0 | 1002 (1000-1011) | R21,R22,R25 |
| panel | morph.panel | cand:morph.tween:waapi | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R19,R24 |
| panel | morph.panel | orig | 24 / 24 | 0 (0-1) | 0 | 0 | 0 | 0 | 1001 (1000-1041) | 24 runs (see Runs per arm) |

**macos-webkit 390px, hero, ideal line**

| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hero.track | hero.exit | base | 8 / 8 | 0 | 0 | 0 | 0 | 0 | 1000 | 8 runs (see Runs per arm) |
| hero.track | hero.exit | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.track | hero.exit | cand:hero.exit:faithful | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R8,R11,R20 |
| hero.track | hero.exit | cand:hero.exit:scoped | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1000 | R1,R3,R17 |
| hero.stage | hero.exit | base | 8 / 8 | 0 | 0 | 0 | 0 | 0 | 1099 | 8 runs (see Runs per arm) |
| hero.stage | hero.exit | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R4,R7 |
| hero.stage | hero.exit | cand:hero.exit:faithful | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1099 | R8,R11,R20 |
| hero.stage | hero.exit | cand:hero.exit:scoped | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1099 | R1,R3,R17 |
| hero.copy | hero | base | 8 / 8 | 2 | 1 | 1 | 0 | 0 | 1987 | 8 runs (see Runs per arm) |
| hero.copy | hero | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.copy | hero | cand:hero.exit:faithful | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1987 | R8,R11,R20 |
| hero.copy | hero | cand:hero.exit:scoped | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1987 | R1,R3,R17 |
| hero.cta | hero | base | 8 / 8 | 2 | 1 | 1 | 0 | 0 | 1978 | 8 runs (see Runs per arm) |
| hero.cta | hero | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.cta | hero | cand:hero.exit:faithful | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1978 | R8,R11,R20 |
| hero.cta | hero | cand:hero.exit:scoped | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1978 | R1,R3,R17 |
| hero.countdown.unit | hero.countdown | base | 8 / 8 | 2 | 1 | 1 | 0 | 0 | 1978 | 8 runs (see Runs per arm) |
| hero.countdown.unit | hero.countdown | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.countdown.unit | hero.countdown | cand:hero.exit:faithful | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1978 | R8,R11,R20 |
| hero.countdown.unit | hero.countdown | cand:hero.exit:scoped | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1978 | R1,R3,R17 |
| hero.cue | hero.cue | base | 8 / 8 | 2 | 1 | 1 | 0 | 0 | 1987 | 8 runs (see Runs per arm) |
| hero.cue | hero.cue | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.cue | hero.cue | cand:hero.exit:faithful | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1987 | R8,R11,R20 |
| hero.cue | hero.cue | cand:hero.exit:scoped | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1987 | R1,R3,R17 |
| hero.orbit.card | hero.orbit | base | 8 / 8 | 2 | 1 | 1 | 0 | 0 | 2000 | 8 runs (see Runs per arm) |
| hero.orbit.card | hero.orbit | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.orbit.card | hero.orbit | cand:hero.exit:faithful | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 2000 | R8,R11,R20 |
| hero.orbit.card | hero.orbit | cand:hero.exit:scoped | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 2000 | R1,R3,R17 |
| hero.deck | hero.deck | base | 8 / 8 | 0 | 0 | 0 | 0 | 0 | 1099 | 8 runs (see Runs per arm) |
| hero.deck | hero.deck | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1099 | R4,R7 |
| hero.deck | hero.deck | cand:hero.exit:faithful | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1099 | R8,R11,R20 |
| hero.deck | hero.deck | cand:hero.exit:scoped | 3 / 3 | 0 | 0 | 0 | 0 | 0 | 1099 | R1,R3,R17 |
| hero.deck.card | hero.deck | base | 8 / 8 | 2 | 1 | 1 | 0 | 0 | 1988 | 8 runs (see Runs per arm) |
| hero.deck.card | hero.deck | cand:?preset=v2-proved | 2 / 2 | 0 | 0 | 0 | 0 | 0 | 1000 | R4,R7 |
| hero.deck.card | hero.deck | cand:hero.exit:faithful | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1988 | R8,R11,R20 |
| hero.deck.card | hero.deck | cand:hero.exit:scoped | 3 / 3 | 2 | 1 | 1 | 0 | 0 | 1988 | R1,R3,R17 |

### Window totals per arm (all properties of the window summed per push)

| engine, width, window, ideal | arm | runs | nodes moving | nodes flagged | defects per push | tail steps per push |
| --- | --- | --- | --- | --- | --- | --- |
| chromium 1280px, end-close, ideal line | base | 29 | 5 | 4 (4-8) | 49 (43-101) | 47 (39-98) |
| chromium 1280px, end-close, ideal line | cand:?preset=v2-proved | 2 | 5 | 4 | 43 (43-47) | 39 (39-45) |
| chromium 1280px, end-close, ideal line | cand:hero:scene-pause | 1 | 5 | 4 | 47 | 45 |
| chromium 1280px, end-close, ideal line | cand:hero.exit:faithful | 5 | 5 | 4 | 50 (48-51) | 49 (46-52) |
| chromium 1280px, end-close, ideal line | cand:hero.exit:scoped | 4 | 5 | 4 | 47 (45-49) | 44 (42-48) |
| chromium 1280px, end-close, ideal line | cand:morph.tween:scroll-lock | 3 | 5 | 4 | 47 (45-51) | 39 (39-47) |
| chromium 1280px, end-close, ideal line | cand:morph.tween:waapi | 5 | 5 | 4 | 44 (43-48) | 29 (27-55) |
| chromium 1280px, end-close, ideal line | cand:morph.tween:waapi-scoped | 2 | 5 | 4 | 43 (43-47) | 24 (24-29) |
| chromium 1280px, end-close, ideal line | cand:nav:earn-no-transition | 2 | 5 | 4 | 37 (37-44) | 39 (39-46) |
| chromium 1280px, end-close, ideal line | orig | 29 | 5 | 4 | 47 (42-53) | 45 (40-52) |
| chromium 1280px, end-close, ideal ref | base | 29 | 5 | 4 (3-8) | 18 (13-38) | 46 (38-97) |
| chromium 1280px, end-close, ideal ref | cand:?preset=v2-proved | 2 | 5 | 3 (3-4) | 13 (13-15) | 38 (38-45) |
| chromium 1280px, end-close, ideal ref | cand:hero:scene-pause | 1 | 5 | 3 | 18 | 45 |
| chromium 1280px, end-close, ideal ref | cand:hero.exit:faithful | 5 | 5 | 3 (3-4) | 18 (18-20) | 48 (45-51) |
| chromium 1280px, end-close, ideal ref | cand:hero.exit:scoped | 4 | 5 | 4 | 18 (16-20) | 43 (42-48) |
| chromium 1280px, end-close, ideal ref | cand:morph.tween:scroll-lock | 3 | 5 | 4 | 17 (17-19) | 39 (38-47) |
| chromium 1280px, end-close, ideal ref | cand:morph.tween:waapi | 5 | 5 | 4 (4-5) | 23 (18-26) | 31 (29-54) |
| chromium 1280px, end-close, ideal ref | cand:morph.tween:waapi-scoped | 2 | 5 | 4 | 23 (23-24) | 23 (23-30) |
| chromium 1280px, end-close, ideal ref | cand:nav:earn-no-transition | 2 | 5 | 4 | 15 (15-17) | 39 (39-45) |
| chromium 1280px, end-close, ideal ref | orig | 29 | 5 | 4 | 18 (15-22) | 45 (39-51) |
| chromium 1280px, end-open, ideal line | base | 29 | 5 | 5 (4-10) | 50 (45-102) | 5 (2-10) |
| chromium 1280px, end-open, ideal line | cand:?preset=v2-proved | 2 | 5 | 5 | 48 | 5 |
| chromium 1280px, end-open, ideal line | cand:hero:scene-pause | 1 | 5 | 5 | 47 | 5 |
| chromium 1280px, end-open, ideal line | cand:hero.exit:faithful | 5 | 5 | 5 | 52 (50-53) | 5 (3-6) |
| chromium 1280px, end-open, ideal line | cand:hero.exit:scoped | 4 | 5 | 5 | 48 (48-51) | 5 (4-5) |
| chromium 1280px, end-open, ideal line | cand:morph.tween:scroll-lock | 3 | 5 | 5 | 47 (45-53) | 5 (4-5) |
| chromium 1280px, end-open, ideal line | cand:morph.tween:waapi | 5 | 5 | 5 (4-5) | 46 (40-54) | 3 (2-5) |
| chromium 1280px, end-open, ideal line | cand:morph.tween:waapi-scoped | 2 | 5 | 5 | 45 | 4 |
| chromium 1280px, end-open, ideal line | cand:nav:earn-no-transition | 2 | 5 | 5 | 48 (48-54) | 0 (0-2) |
| chromium 1280px, end-open, ideal line | orig | 29 | 5 | 5 | 49 (44-54) | 5 (2-6) |
| chromium 1280px, end-open, ideal ref | base | 29 | 5 | 4 (3-10) | 2 (0-7) | 5 (2-10) |
| chromium 1280px, end-open, ideal ref | cand:?preset=v2-proved | 2 | 5 | 5 | 1 (1-2) | 5 |
| chromium 1280px, end-open, ideal ref | cand:hero:scene-pause | 1 | 5 | 4 | 1 | 5 |
| chromium 1280px, end-open, ideal ref | cand:hero.exit:faithful | 5 | 5 | 4 | 2 (1-3) | 5 (3-6) |
| chromium 1280px, end-open, ideal ref | cand:hero.exit:scoped | 4 | 5 | 4 (4-5) | 1 (1-5) | 5 (4-5) |
| chromium 1280px, end-open, ideal ref | cand:morph.tween:scroll-lock | 3 | 5 | 4 (4-5) | 2 (1-2) | 5 (4-5) |
| chromium 1280px, end-open, ideal ref | cand:morph.tween:waapi | 5 | 5 | 3 (3-5) | 4 (1-4) | 3 (2-5) |
| chromium 1280px, end-open, ideal ref | cand:morph.tween:waapi-scoped | 2 | 5 | 4 (4-5) | 3 (3-4) | 4 |
| chromium 1280px, end-open, ideal ref | cand:nav:earn-no-transition | 2 | 5 | 5 | 18 (18-19) | 0 (0-2) |
| chromium 1280px, end-open, ideal ref | orig | 29 | 5 | 5 (4-5) | 2 (1-5) | 5 (2-6) |
| chromium 1280px, hero, ideal line | base | 29 | 10 | 6 (6-12) | 12 (0-24) | 0 |
| chromium 1280px, hero, ideal line | cand:?preset=v2-proved | 2 | 10 | 4 | 0 | 0 |
| chromium 1280px, hero, ideal line | cand:hero:scene-pause | 1 | 10 | 6 | 0 | 0 |
| chromium 1280px, hero, ideal line | cand:hero.exit:faithful | 5 | 10 | 6 | 0 (0-12) | 0 |
| chromium 1280px, hero, ideal line | cand:hero.exit:scoped | 4 | 10 | 6 | 12 (0-12) | 0 |
| chromium 1280px, hero, ideal line | cand:morph.tween:scroll-lock | 3 | 10 | 6 | 0 | 0 |
| chromium 1280px, hero, ideal line | cand:morph.tween:waapi | 5 | 10 | 6 | 0 (0-12) | 0 |
| chromium 1280px, hero, ideal line | cand:morph.tween:waapi-scoped | 2 | 10 | 6 | 12 | 0 |
| chromium 1280px, hero, ideal line | cand:nav:earn-no-transition | 2 | 10 | 6 | 12 | 0 |
| chromium 1280px, hero, ideal line | orig | 29 | 10 | 6 | 0 | 0 |
| chromium 1280px, hero, ideal ref | base | 29 | 10 | 10 (0-20) | 0 | 0 |
| chromium 1280px, hero, ideal ref | cand:?preset=v2-proved | 2 | 10 | 10 | 0 | 0 |
| chromium 1280px, hero, ideal ref | cand:hero:scene-pause | 1 | 10 | 0 | 0 | 0 |
| chromium 1280px, hero, ideal ref | cand:hero.exit:faithful | 5 | 10 | 0 (0-10) | 0 | 0 |
| chromium 1280px, hero, ideal ref | cand:hero.exit:scoped | 4 | 10 | 10 (0-10) | 0 | 0 |
| chromium 1280px, hero, ideal ref | cand:morph.tween:scroll-lock | 3 | 10 | 0 | 0 | 0 |
| chromium 1280px, hero, ideal ref | cand:morph.tween:waapi | 5 | 10 | 7 (0-10) | 0 | 0 |
| chromium 1280px, hero, ideal ref | cand:morph.tween:waapi-scoped | 2 | 10 | 10 | 0 | 0 |
| chromium 1280px, hero, ideal ref | cand:nav:earn-no-transition | 2 | 10 | 10 | 0 | 0 |
| chromium 390px, end-close, ideal line | base | 33 | 5 | 5 (5-10) | 98 (92-198) | 57 (56-115) |
| chromium 390px, end-close, ideal line | cand:?preset=v2-proved | 2 | 5 | 5 | 96 (96-98) | 56 (56-57) |
| chromium 390px, end-close, ideal line | cand:hero:scene-pause | 3 | 5 | 5 | 97 (97-103) | 57 (57-58) |
| chromium 390px, end-close, ideal line | cand:hero.exit:faithful | 5 | 5 | 5 | 99 (93-102) | 57 (56-57) |
| chromium 390px, end-close, ideal line | cand:hero.exit:scoped | 5 | 5 | 5 | 97 (92-100) | 57 (56-57) |
| chromium 390px, end-close, ideal line | cand:morph.tween:scroll-lock | 3 | 5 | 5 | 102 (101-104) | 57 |
| chromium 390px, end-close, ideal line | cand:morph.tween:waapi | 5 | 5 | 5 | 89 (84-95) | 34 (34-58) |
| chromium 390px, end-close, ideal line | cand:morph.tween:waapi-scoped | 2 | 5 | 5 | 86 (86-90) | 34 |
| chromium 390px, end-close, ideal line | cand:nav:earn-no-transition | 2 | 5 | 5 | 80 (80-82) | 57 |
| chromium 390px, end-close, ideal line | orig | 33 | 5 | 5 | 101 (97-105) | 57 (56-58) |
| chromium 390px, end-close, ideal ref | base | 33 | 5 | 4 (4-9) | 29 (19-60) | 56 (55-114) |
| chromium 390px, end-close, ideal ref | cand:?preset=v2-proved | 2 | 5 | 5 | 29 (29-33) | 55 (55-56) |
| chromium 390px, end-close, ideal ref | cand:hero:scene-pause | 3 | 5 | 4 (4-5) | 21 (20-22) | 57 |
| chromium 390px, end-close, ideal ref | cand:hero.exit:faithful | 5 | 5 | 4 | 22 (19-30) | 56 (55-56) |
| chromium 390px, end-close, ideal ref | cand:hero.exit:scoped | 5 | 5 | 4 (4-5) | 28 (18-31) | 56 (55-57) |
| chromium 390px, end-close, ideal ref | cand:morph.tween:scroll-lock | 3 | 5 | 4 (4-5) | 23 (19-25) | 57 (56-58) |
| chromium 390px, end-close, ideal ref | cand:morph.tween:waapi | 5 | 5 | 5 | 36 (25-40) | 38 (37-58) |
| chromium 390px, end-close, ideal ref | cand:morph.tween:waapi-scoped | 2 | 5 | 5 | 41 (41-42) | 37 |
| chromium 390px, end-close, ideal ref | cand:nav:earn-no-transition | 2 | 5 | 4 | 33 (33-34) | 56 |
| chromium 390px, end-close, ideal ref | orig | 33 | 5 | 5 (4-5) | 20 (17-25) | 56 (55-58) |
| chromium 390px, end-open, ideal line | base | 33 | 5 | 5 (5-10) | 118 (113-243) | 9 (6-19) |
| chromium 390px, end-open, ideal line | cand:?preset=v2-proved | 2 | 5 | 5 | 115 (115-116) | 6 (6-7) |
| chromium 390px, end-open, ideal line | cand:hero:scene-pause | 3 | 5 | 5 | 117 (115-118) | 9 (9-10) |
| chromium 390px, end-open, ideal line | cand:hero.exit:faithful | 5 | 5 | 5 | 118 (115-119) | 9 (6-10) |
| chromium 390px, end-open, ideal line | cand:hero.exit:scoped | 5 | 5 | 5 | 118 (115-119) | 7 (7-9) |
| chromium 390px, end-open, ideal line | cand:morph.tween:scroll-lock | 3 | 5 | 5 | 119 (118-119) | 9 (9-10) |
| chromium 390px, end-open, ideal line | cand:morph.tween:waapi | 5 | 5 | 5 | 112 (106-119) | 8 (6-9) |
| chromium 390px, end-open, ideal line | cand:morph.tween:waapi-scoped | 2 | 5 | 5 | 112 (112-117) | 6 |
| chromium 390px, end-open, ideal line | cand:nav:earn-no-transition | 2 | 5 | 5 | 112 (112-116) | 2 |
| chromium 390px, end-open, ideal line | orig | 33 | 5 | 5 | 118 (112-124) | 9 (8-9) |
| chromium 390px, end-open, ideal ref | base | 33 | 5 | 5 (4-10) | 16 (5-40) | 9 (6-19) |
| chromium 390px, end-open, ideal ref | cand:?preset=v2-proved | 2 | 5 | 4 | 16 (16-18) | 6 (6-7) |
| chromium 390px, end-open, ideal ref | cand:hero:scene-pause | 3 | 5 | 5 (4-5) | 5 (5-9) | 9 (9-10) |
| chromium 390px, end-open, ideal ref | cand:hero.exit:faithful | 5 | 5 | 4 (4-5) | 13 (8-18) | 9 (6-10) |
| chromium 390px, end-open, ideal ref | cand:hero.exit:scoped | 5 | 5 | 5 | 18 (9-19) | 7 (7-9) |
| chromium 390px, end-open, ideal ref | cand:morph.tween:scroll-lock | 3 | 5 | 4 (4-5) | 7 (2-10) | 9 (9-10) |
| chromium 390px, end-open, ideal ref | cand:morph.tween:waapi | 5 | 5 | 3 (3-4) | 5 (0-12) | 8 (6-9) |
| chromium 390px, end-open, ideal ref | cand:morph.tween:waapi-scoped | 2 | 5 | 3 (3-4) | 11 (11-14) | 6 |
| chromium 390px, end-open, ideal ref | cand:nav:earn-no-transition | 2 | 5 | 4 | 42 (42-51) | 2 |
| chromium 390px, end-open, ideal ref | orig | 33 | 5 | 4 (3-5) | 0 (0-9) | 9 (8-9) |
| chromium 390px, hero, ideal line | base | 33 | 9 | 8 (6-16) | 0 (0-24) | 0 |
| chromium 390px, hero, ideal line | cand:?preset=v2-proved | 2 | 9 | 8 | 0 | 0 |
| chromium 390px, hero, ideal line | cand:hero:scene-pause | 3 | 7 | 6 | 0 | 0 |
| chromium 390px, hero, ideal line | cand:hero.exit:faithful | 5 | 7 | 6 (6-8) | 0 (0-12) | 0 |
| chromium 390px, hero, ideal line | cand:hero.exit:scoped | 5 | 9 | 8 (6-8) | 12 (0-12) | 0 |
| chromium 390px, hero, ideal line | cand:morph.tween:scroll-lock | 3 | 7 | 6 | 0 | 0 |
| chromium 390px, hero, ideal line | cand:morph.tween:waapi | 5 | 7 | 6 (6-8) | 0 (0-12) | 0 |
| chromium 390px, hero, ideal line | cand:morph.tween:waapi-scoped | 2 | 9 | 8 | 12 | 0 |
| chromium 390px, hero, ideal line | cand:nav:earn-no-transition | 2 | 9 | 8 | 12 | 0 |
| chromium 390px, hero, ideal line | orig | 33 | 7 | 6 | 0 | 0 |
| chromium 390px, hero, ideal ref | base | 33 | 7 | 0 (0-14) | 0 | 0 |
| chromium 390px, hero, ideal ref | cand:?preset=v2-proved | 2 | 7 | 7 | 0 | 0 |
| chromium 390px, hero, ideal ref | cand:hero:scene-pause | 3 | 7 | 0 | 0 | 0 |
| chromium 390px, hero, ideal ref | cand:hero.exit:faithful | 5 | 7 | 0 (0-7) | 0 | 0 |
| chromium 390px, hero, ideal ref | cand:hero.exit:scoped | 5 | 7 | 7 (0-7) | 0 | 0 |
| chromium 390px, hero, ideal ref | cand:morph.tween:scroll-lock | 3 | 7 | 0 | 0 | 0 |
| chromium 390px, hero, ideal ref | cand:morph.tween:waapi | 5 | 7 | 0 (0-7) | 0 | 0 |
| chromium 390px, hero, ideal ref | cand:morph.tween:waapi-scoped | 2 | 7 | 7 | 0 | 0 |
| chromium 390px, hero, ideal ref | cand:nav:earn-no-transition | 2 | 7 | 7 | 0 | 0 |
| macos-webkit 1280px, end-close, ideal line | base | 23 | 5 | 4 (4-8) | 44 (31-88) | 37 (18-73) |
| macos-webkit 1280px, end-close, ideal line | cand:?preset=v2-proved | 2 | 5 | 4 | 41 (41-46) | 30 (30-41) |
| macos-webkit 1280px, end-close, ideal line | cand:hero.exit:faithful | 7 | 5 | 4 | 48 (37-57) | 54 (19-59) |
| macos-webkit 1280px, end-close, ideal line | cand:hero.exit:scoped | 7 | 5 | 4 | 42 (36-51) | 33 (19-58) |
| macos-webkit 1280px, end-close, ideal line | cand:morph.tween:scroll-lock | 3 | 5 | 4 | 38 (37-46) | 33 (16-42) |
| macos-webkit 1280px, end-close, ideal line | cand:morph.tween:waapi | 2 | 5 | 4 | 34 (34-44) | 31 |
| macos-webkit 1280px, end-close, ideal line | orig | 23 | 5 | 4 (4-5) | 42 (31-53) | 36 (15-59) |
| macos-webkit 1280px, end-close, ideal ref | base | 23 | 5 | 4 (3-8) | 16 (8-33) | 37 (18-72) |
| macos-webkit 1280px, end-close, ideal ref | cand:?preset=v2-proved | 2 | 5 | 4 | 11 (11-17) | 29 (29-41) |
| macos-webkit 1280px, end-close, ideal ref | cand:hero.exit:faithful | 7 | 5 | 4 (3-4) | 19 (12-22) | 53 (18-58) |
| macos-webkit 1280px, end-close, ideal ref | cand:hero.exit:scoped | 7 | 5 | 4 (3-4) | 15 (11-20) | 33 (18-58) |
| macos-webkit 1280px, end-close, ideal ref | cand:morph.tween:scroll-lock | 3 | 5 | 4 | 13 (8-19) | 32 (15-41) |
| macos-webkit 1280px, end-close, ideal ref | cand:morph.tween:waapi | 2 | 5 | 4 | 16 (16-20) | 30 (30-32) |
| macos-webkit 1280px, end-close, ideal ref | orig | 23 | 5 | 4 (4-5) | 16 (8-21) | 35 (15-58) |
| macos-webkit 1280px, end-open, ideal line | base | 23 | 5 | 5 (5-9) | 43 (26-79) | 4 (1-15) |
| macos-webkit 1280px, end-open, ideal line | cand:?preset=v2-proved | 2 | 5 | 4 (4-5) | 38 (38-45) | 3 (3-8) |
| macos-webkit 1280px, end-open, ideal line | cand:hero.exit:faithful | 7 | 5 | 5 | 50 (27-66) | 7 (4-9) |
| macos-webkit 1280px, end-open, ideal line | cand:hero.exit:scoped | 7 | 5 | 5 | 37 (32-58) | 5 (3-5) |
| macos-webkit 1280px, end-open, ideal line | cand:morph.tween:scroll-lock | 3 | 5 | 5 (4-5) | 30 (24-43) | 2 (1-5) |
| macos-webkit 1280px, end-open, ideal line | cand:morph.tween:waapi | 2 | 5 | 5 | 27 (27-35) | 2 (2-5) |
| macos-webkit 1280px, end-open, ideal line | orig | 23 | 5 | 5 (4-5) | 38 (26-62) | 5 (1-8) |
| macos-webkit 1280px, end-open, ideal ref | base | 23 | 5 | 5 (3-8) | 4 (1-10) | 4 (1-15) |
| macos-webkit 1280px, end-open, ideal ref | cand:?preset=v2-proved | 2 | 5 | 3 (3-4) | 3 (3-6) | 3 (3-8) |
| macos-webkit 1280px, end-open, ideal ref | cand:hero.exit:faithful | 7 | 5 | 4 (4-5) | 3 (1-10) | 7 (4-9) |
| macos-webkit 1280px, end-open, ideal ref | cand:hero.exit:scoped | 7 | 5 | 4 (4-5) | 6 (2-10) | 5 (3-5) |
| macos-webkit 1280px, end-open, ideal ref | cand:morph.tween:scroll-lock | 3 | 5 | 3 (2-4) | 4 (4-7) | 2 (1-5) |
| macos-webkit 1280px, end-open, ideal ref | cand:morph.tween:waapi | 2 | 5 | 4 (4-5) | 5 (5-6) | 2 (2-5) |
| macos-webkit 1280px, end-open, ideal ref | orig | 23 | 5 | 5 (4-5) | 4 (2-10) | 5 (1-8) |
| macos-webkit 1280px, hero, ideal line | base | 8 | 10 | 6 | 12 | 0 |
| macos-webkit 1280px, hero, ideal line | cand:?preset=v2-proved | 2 | 10 | 4 | 0 | 0 |
| macos-webkit 1280px, hero, ideal line | cand:hero.exit:faithful | 3 | 10 | 6 | 12 | 0 |
| macos-webkit 1280px, hero, ideal line | cand:hero.exit:scoped | 3 | 10 | 6 | 12 | 0 |
| macos-webkit 390px, end-close, ideal line | base | 24 | 5 | 5 (5-10) | 55 (40-117) | 32 (18-72) |
| macos-webkit 390px, end-close, ideal line | cand:?preset=v2-proved | 2 | 5 | 5 | 59 (59-61) | 44 (44-53) |
| macos-webkit 390px, end-close, ideal line | cand:hero.exit:faithful | 7 | 5 | 5 | 51 (49-60) | 30 (20-38) |
| macos-webkit 390px, end-close, ideal line | cand:hero.exit:scoped | 7 | 5 | 5 | 54 (49-61) | 31 (22-48) |
| macos-webkit 390px, end-close, ideal line | cand:morph.tween:scroll-lock | 3 | 5 | 5 | 50 (43-53) | 18 (12-32) |
| macos-webkit 390px, end-close, ideal line | cand:morph.tween:waapi | 2 | 5 | 5 | 45 (45-50) | 18 (18-23) |
| macos-webkit 390px, end-close, ideal line | orig | 24 | 5 | 5 | 60 (45-80) | 30 (19-50) |
| macos-webkit 390px, end-close, ideal ref | base | 24 | 5 | 5 (4-10) | 16 (11-36) | 31 (18-71) |
| macos-webkit 390px, end-close, ideal ref | cand:?preset=v2-proved | 2 | 5 | 4 (4-5) | 23 (23-24) | 43 (43-52) |
| macos-webkit 390px, end-close, ideal ref | cand:hero.exit:faithful | 7 | 5 | 5 (4-5) | 17 (13-22) | 30 (21-38) |
| macos-webkit 390px, end-close, ideal ref | cand:hero.exit:scoped | 7 | 5 | 5 (4-5) | 16 (14-23) | 30 (22-47) |
| macos-webkit 390px, end-close, ideal ref | cand:morph.tween:scroll-lock | 3 | 5 | 5 | 14 (10-18) | 18 (12-33) |
| macos-webkit 390px, end-close, ideal ref | cand:morph.tween:waapi | 2 | 5 | 5 | 14 (14-19) | 18 (18-23) |
| macos-webkit 390px, end-close, ideal ref | orig | 24 | 5 | 5 | 17 (13-23) | 31 (18-49) |
| macos-webkit 390px, end-open, ideal line | base | 24 | 5 | 5 (5-10) | 50 (34-107) | 5 (2-15) |
| macos-webkit 390px, end-open, ideal line | cand:?preset=v2-proved | 2 | 5 | 5 | 62 (62-72) | 9 |
| macos-webkit 390px, end-open, ideal line | cand:hero.exit:faithful | 7 | 5 | 5 | 48 (44-56) | 4 (2-9) |
| macos-webkit 390px, end-open, ideal line | cand:hero.exit:scoped | 7 | 5 | 5 | 49 (34-64) | 4 (2-9) |
| macos-webkit 390px, end-open, ideal line | cand:morph.tween:scroll-lock | 3 | 5 | 5 | 34 (32-57) | 2 (2-5) |
| macos-webkit 390px, end-open, ideal line | cand:morph.tween:waapi | 2 | 5 | 5 | 42 (42-56) | 2 (2-8) |
| macos-webkit 390px, end-open, ideal line | orig | 24 | 5 | 5 | 45 (34-62) | 4 (1-8) |
| macos-webkit 390px, end-open, ideal ref | base | 24 | 5 | 5 (3-10) | 8 (3-19) | 5 (2-15) |
| macos-webkit 390px, end-open, ideal ref | cand:?preset=v2-proved | 2 | 5 | 4 (4-5) | 9 (9-10) | 9 |
| macos-webkit 390px, end-open, ideal ref | cand:hero.exit:faithful | 7 | 5 | 5 (4-5) | 7 (6-11) | 4 (2-9) |
| macos-webkit 390px, end-open, ideal ref | cand:hero.exit:scoped | 7 | 5 | 4 (3-5) | 9 (4-11) | 4 (2-9) |
| macos-webkit 390px, end-open, ideal ref | cand:morph.tween:scroll-lock | 3 | 5 | 4 (3-4) | 5 (4-7) | 3 (2-5) |
| macos-webkit 390px, end-open, ideal ref | cand:morph.tween:waapi | 2 | 5 | 4 (4-5) | 10 (10-12) | 2 (2-8) |
| macos-webkit 390px, end-open, ideal ref | orig | 24 | 5 | 5 (4-5) | 7 (2-11) | 4 (1-8) |
| macos-webkit 390px, hero, ideal line | base | 8 | 9 | 8 | 12 | 0 |
| macos-webkit 390px, hero, ideal line | cand:?preset=v2-proved | 2 | 9 | 8 | 0 | 0 |
| macos-webkit 390px, hero, ideal line | cand:hero.exit:faithful | 3 | 9 | 8 | 12 | 0 |
| macos-webkit 390px, hero, ideal line | cand:hero.exit:scoped | 3 | 9 | 8 | 12 | 0 |

### Runs per arm (every run behind the counts above)

| engine, width, window, ideal | arm | run codes |
| --- | --- | --- |
| chromium 1280px, end-close, ideal line | base | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R42 |
| chromium 1280px, end-close, ideal line | cand:?preset=v2-proved | R4,R7 |
| chromium 1280px, end-close, ideal line | cand:hero:scene-pause | R42 |
| chromium 1280px, end-close, ideal line | cand:hero.exit:faithful | R6,R8,R9,R20,R28 |
| chromium 1280px, end-close, ideal line | cand:hero.exit:scoped | R1,R3,R17,R27 |
| chromium 1280px, end-close, ideal line | cand:morph.tween:scroll-lock | R21,R22,R25 |
| chromium 1280px, end-close, ideal line | cand:morph.tween:waapi | R2,R5,R19,R24,R39 |
| chromium 1280px, end-close, ideal line | cand:morph.tween:waapi-scoped | R10,R12 |
| chromium 1280px, end-close, ideal line | cand:nav:earn-no-transition | R13,R15 |
| chromium 1280px, end-close, ideal line | orig | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R42 |
| chromium 1280px, end-close, ideal ref | base | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R42 |
| chromium 1280px, end-close, ideal ref | cand:?preset=v2-proved | R4,R7 |
| chromium 1280px, end-close, ideal ref | cand:hero:scene-pause | R42 |
| chromium 1280px, end-close, ideal ref | cand:hero.exit:faithful | R6,R8,R9,R20,R28 |
| chromium 1280px, end-close, ideal ref | cand:hero.exit:scoped | R1,R3,R17,R27 |
| chromium 1280px, end-close, ideal ref | cand:morph.tween:scroll-lock | R21,R22,R25 |
| chromium 1280px, end-close, ideal ref | cand:morph.tween:waapi | R2,R5,R19,R24,R39 |
| chromium 1280px, end-close, ideal ref | cand:morph.tween:waapi-scoped | R10,R12 |
| chromium 1280px, end-close, ideal ref | cand:nav:earn-no-transition | R13,R15 |
| chromium 1280px, end-close, ideal ref | orig | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R42 |
| chromium 1280px, end-open, ideal line | base | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R42 |
| chromium 1280px, end-open, ideal line | cand:?preset=v2-proved | R4,R7 |
| chromium 1280px, end-open, ideal line | cand:hero:scene-pause | R42 |
| chromium 1280px, end-open, ideal line | cand:hero.exit:faithful | R6,R8,R9,R20,R28 |
| chromium 1280px, end-open, ideal line | cand:hero.exit:scoped | R1,R3,R17,R27 |
| chromium 1280px, end-open, ideal line | cand:morph.tween:scroll-lock | R21,R22,R25 |
| chromium 1280px, end-open, ideal line | cand:morph.tween:waapi | R2,R5,R19,R24,R39 |
| chromium 1280px, end-open, ideal line | cand:morph.tween:waapi-scoped | R10,R12 |
| chromium 1280px, end-open, ideal line | cand:nav:earn-no-transition | R13,R15 |
| chromium 1280px, end-open, ideal line | orig | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R42 |
| chromium 1280px, end-open, ideal ref | base | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R42 |
| chromium 1280px, end-open, ideal ref | cand:?preset=v2-proved | R4,R7 |
| chromium 1280px, end-open, ideal ref | cand:hero:scene-pause | R42 |
| chromium 1280px, end-open, ideal ref | cand:hero.exit:faithful | R6,R8,R9,R20,R28 |
| chromium 1280px, end-open, ideal ref | cand:hero.exit:scoped | R1,R3,R17,R27 |
| chromium 1280px, end-open, ideal ref | cand:morph.tween:scroll-lock | R21,R22,R25 |
| chromium 1280px, end-open, ideal ref | cand:morph.tween:waapi | R2,R5,R19,R24,R39 |
| chromium 1280px, end-open, ideal ref | cand:morph.tween:waapi-scoped | R10,R12 |
| chromium 1280px, end-open, ideal ref | cand:nav:earn-no-transition | R13,R15 |
| chromium 1280px, end-open, ideal ref | orig | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R42 |
| chromium 1280px, hero, ideal line | base | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R42 |
| chromium 1280px, hero, ideal line | cand:?preset=v2-proved | R4,R7 |
| chromium 1280px, hero, ideal line | cand:hero:scene-pause | R42 |
| chromium 1280px, hero, ideal line | cand:hero.exit:faithful | R6,R8,R9,R20,R28 |
| chromium 1280px, hero, ideal line | cand:hero.exit:scoped | R1,R3,R17,R27 |
| chromium 1280px, hero, ideal line | cand:morph.tween:scroll-lock | R21,R22,R25 |
| chromium 1280px, hero, ideal line | cand:morph.tween:waapi | R2,R5,R19,R24,R39 |
| chromium 1280px, hero, ideal line | cand:morph.tween:waapi-scoped | R10,R12 |
| chromium 1280px, hero, ideal line | cand:nav:earn-no-transition | R13,R15 |
| chromium 1280px, hero, ideal line | orig | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R42 |
| chromium 1280px, hero, ideal ref | base | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R42 |
| chromium 1280px, hero, ideal ref | cand:?preset=v2-proved | R4,R7 |
| chromium 1280px, hero, ideal ref | cand:hero:scene-pause | R42 |
| chromium 1280px, hero, ideal ref | cand:hero.exit:faithful | R6,R8,R9,R20,R28 |
| chromium 1280px, hero, ideal ref | cand:hero.exit:scoped | R1,R3,R17,R27 |
| chromium 1280px, hero, ideal ref | cand:morph.tween:scroll-lock | R21,R22,R25 |
| chromium 1280px, hero, ideal ref | cand:morph.tween:waapi | R2,R5,R19,R24,R39 |
| chromium 1280px, hero, ideal ref | cand:morph.tween:waapi-scoped | R10,R12 |
| chromium 1280px, hero, ideal ref | cand:nav:earn-no-transition | R13,R15 |
| chromium 390px, end-close, ideal line | base | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R40,R42,R43,R44,R45 |
| chromium 390px, end-close, ideal line | cand:?preset=v2-proved | R4,R7 |
| chromium 390px, end-close, ideal line | cand:hero:scene-pause | R42,R43,R44 |
| chromium 390px, end-close, ideal line | cand:hero.exit:faithful | R6,R8,R9,R20,R28 |
| chromium 390px, end-close, ideal line | cand:hero.exit:scoped | R1,R3,R17,R27,R40 |
| chromium 390px, end-close, ideal line | cand:morph.tween:scroll-lock | R21,R22,R25 |
| chromium 390px, end-close, ideal line | cand:morph.tween:waapi | R2,R5,R19,R24,R39 |
| chromium 390px, end-close, ideal line | cand:morph.tween:waapi-scoped | R10,R12 |
| chromium 390px, end-close, ideal line | cand:nav:earn-no-transition | R13,R15 |
| chromium 390px, end-close, ideal line | orig | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R40,R42,R43,R44,R45 |
| chromium 390px, end-close, ideal ref | base | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R40,R42,R43,R44,R45 |
| chromium 390px, end-close, ideal ref | cand:?preset=v2-proved | R4,R7 |
| chromium 390px, end-close, ideal ref | cand:hero:scene-pause | R42,R43,R44 |
| chromium 390px, end-close, ideal ref | cand:hero.exit:faithful | R6,R8,R9,R20,R28 |
| chromium 390px, end-close, ideal ref | cand:hero.exit:scoped | R1,R3,R17,R27,R40 |
| chromium 390px, end-close, ideal ref | cand:morph.tween:scroll-lock | R21,R22,R25 |
| chromium 390px, end-close, ideal ref | cand:morph.tween:waapi | R2,R5,R19,R24,R39 |
| chromium 390px, end-close, ideal ref | cand:morph.tween:waapi-scoped | R10,R12 |
| chromium 390px, end-close, ideal ref | cand:nav:earn-no-transition | R13,R15 |
| chromium 390px, end-close, ideal ref | orig | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R40,R42,R43,R44,R45 |
| chromium 390px, end-open, ideal line | base | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R40,R42,R43,R44,R45 |
| chromium 390px, end-open, ideal line | cand:?preset=v2-proved | R4,R7 |
| chromium 390px, end-open, ideal line | cand:hero:scene-pause | R42,R43,R44 |
| chromium 390px, end-open, ideal line | cand:hero.exit:faithful | R6,R8,R9,R20,R28 |
| chromium 390px, end-open, ideal line | cand:hero.exit:scoped | R1,R3,R17,R27,R40 |
| chromium 390px, end-open, ideal line | cand:morph.tween:scroll-lock | R21,R22,R25 |
| chromium 390px, end-open, ideal line | cand:morph.tween:waapi | R2,R5,R19,R24,R39 |
| chromium 390px, end-open, ideal line | cand:morph.tween:waapi-scoped | R10,R12 |
| chromium 390px, end-open, ideal line | cand:nav:earn-no-transition | R13,R15 |
| chromium 390px, end-open, ideal line | orig | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R40,R42,R43,R44,R45 |
| chromium 390px, end-open, ideal ref | base | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R40,R42,R43,R44,R45 |
| chromium 390px, end-open, ideal ref | cand:?preset=v2-proved | R4,R7 |
| chromium 390px, end-open, ideal ref | cand:hero:scene-pause | R42,R43,R44 |
| chromium 390px, end-open, ideal ref | cand:hero.exit:faithful | R6,R8,R9,R20,R28 |
| chromium 390px, end-open, ideal ref | cand:hero.exit:scoped | R1,R3,R17,R27,R40 |
| chromium 390px, end-open, ideal ref | cand:morph.tween:scroll-lock | R21,R22,R25 |
| chromium 390px, end-open, ideal ref | cand:morph.tween:waapi | R2,R5,R19,R24,R39 |
| chromium 390px, end-open, ideal ref | cand:morph.tween:waapi-scoped | R10,R12 |
| chromium 390px, end-open, ideal ref | cand:nav:earn-no-transition | R13,R15 |
| chromium 390px, end-open, ideal ref | orig | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R40,R42,R43,R44,R45 |
| chromium 390px, hero, ideal line | base | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R40,R42,R43,R44,R45 |
| chromium 390px, hero, ideal line | cand:?preset=v2-proved | R4,R7 |
| chromium 390px, hero, ideal line | cand:hero:scene-pause | R42,R43,R44 |
| chromium 390px, hero, ideal line | cand:hero.exit:faithful | R6,R8,R9,R20,R28 |
| chromium 390px, hero, ideal line | cand:hero.exit:scoped | R1,R3,R17,R27,R40 |
| chromium 390px, hero, ideal line | cand:morph.tween:scroll-lock | R21,R22,R25 |
| chromium 390px, hero, ideal line | cand:morph.tween:waapi | R2,R5,R19,R24,R39 |
| chromium 390px, hero, ideal line | cand:morph.tween:waapi-scoped | R10,R12 |
| chromium 390px, hero, ideal line | cand:nav:earn-no-transition | R13,R15 |
| chromium 390px, hero, ideal line | orig | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R40,R42,R43,R44,R45 |
| chromium 390px, hero, ideal ref | base | R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R12,R13,R14,R15,R16,R17,R18,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R39,R40,R42,R43,R44,R45 |
| chromium 390px, hero, ideal ref | cand:?preset=v2-proved | R4,R7 |
| chromium 390px, hero, ideal ref | cand:hero:scene-pause | R42,R43,R44 |
| chromium 390px, hero, ideal ref | cand:hero.exit:faithful | R6,R8,R9,R20,R28 |
| chromium 390px, hero, ideal ref | cand:hero.exit:scoped | R1,R3,R17,R27,R40 |
| chromium 390px, hero, ideal ref | cand:morph.tween:scroll-lock | R21,R22,R25 |
| chromium 390px, hero, ideal ref | cand:morph.tween:waapi | R2,R5,R19,R24,R39 |
| chromium 390px, hero, ideal ref | cand:morph.tween:waapi-scoped | R10,R12 |
| chromium 390px, hero, ideal ref | cand:nav:earn-no-transition | R13,R15 |
| macos-webkit 1280px, end-close, ideal line | base | R4,R7,R17,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R29,R30,R31,R32,R33,R34,R35,R36,R37,R38 |
| macos-webkit 1280px, end-close, ideal line | cand:?preset=v2-proved | R4,R7 |
| macos-webkit 1280px, end-close, ideal line | cand:hero.exit:faithful | R20,R28,R32,R33,R34,R36,R38 |
| macos-webkit 1280px, end-close, ideal line | cand:hero.exit:scoped | R17,R27,R29,R30,R31,R35,R37 |
| macos-webkit 1280px, end-close, ideal line | cand:morph.tween:scroll-lock | R21,R22,R25 |
| macos-webkit 1280px, end-close, ideal line | cand:morph.tween:waapi | R19,R24 |
| macos-webkit 1280px, end-close, ideal line | orig | R4,R7,R17,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R29,R30,R31,R32,R33,R34,R35,R36,R37,R38 |
| macos-webkit 1280px, end-close, ideal ref | base | R4,R7,R17,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R29,R30,R31,R32,R33,R34,R35,R36,R37,R38 |
| macos-webkit 1280px, end-close, ideal ref | cand:?preset=v2-proved | R4,R7 |
| macos-webkit 1280px, end-close, ideal ref | cand:hero.exit:faithful | R20,R28,R32,R33,R34,R36,R38 |
| macos-webkit 1280px, end-close, ideal ref | cand:hero.exit:scoped | R17,R27,R29,R30,R31,R35,R37 |
| macos-webkit 1280px, end-close, ideal ref | cand:morph.tween:scroll-lock | R21,R22,R25 |
| macos-webkit 1280px, end-close, ideal ref | cand:morph.tween:waapi | R19,R24 |
| macos-webkit 1280px, end-close, ideal ref | orig | R4,R7,R17,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R29,R30,R31,R32,R33,R34,R35,R36,R37,R38 |
| macos-webkit 1280px, end-open, ideal line | base | R4,R7,R17,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R29,R30,R31,R32,R33,R34,R35,R36,R37,R38 |
| macos-webkit 1280px, end-open, ideal line | cand:?preset=v2-proved | R4,R7 |
| macos-webkit 1280px, end-open, ideal line | cand:hero.exit:faithful | R20,R28,R32,R33,R34,R36,R38 |
| macos-webkit 1280px, end-open, ideal line | cand:hero.exit:scoped | R17,R27,R29,R30,R31,R35,R37 |
| macos-webkit 1280px, end-open, ideal line | cand:morph.tween:scroll-lock | R21,R22,R25 |
| macos-webkit 1280px, end-open, ideal line | cand:morph.tween:waapi | R19,R24 |
| macos-webkit 1280px, end-open, ideal line | orig | R4,R7,R17,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R29,R30,R31,R32,R33,R34,R35,R36,R37,R38 |
| macos-webkit 1280px, end-open, ideal ref | base | R4,R7,R17,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R29,R30,R31,R32,R33,R34,R35,R36,R37,R38 |
| macos-webkit 1280px, end-open, ideal ref | cand:?preset=v2-proved | R4,R7 |
| macos-webkit 1280px, end-open, ideal ref | cand:hero.exit:faithful | R20,R28,R32,R33,R34,R36,R38 |
| macos-webkit 1280px, end-open, ideal ref | cand:hero.exit:scoped | R17,R27,R29,R30,R31,R35,R37 |
| macos-webkit 1280px, end-open, ideal ref | cand:morph.tween:scroll-lock | R21,R22,R25 |
| macos-webkit 1280px, end-open, ideal ref | cand:morph.tween:waapi | R19,R24 |
| macos-webkit 1280px, end-open, ideal ref | orig | R4,R7,R17,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R29,R30,R31,R32,R33,R34,R35,R36,R37,R38 |
| macos-webkit 1280px, hero, ideal line | base | R1,R3,R4,R7,R8,R11,R17,R20 |
| macos-webkit 1280px, hero, ideal line | cand:?preset=v2-proved | R4,R7 |
| macos-webkit 1280px, hero, ideal line | cand:hero.exit:faithful | R8,R11,R20 |
| macos-webkit 1280px, hero, ideal line | cand:hero.exit:scoped | R1,R3,R17 |
| macos-webkit 390px, end-close, ideal line | base | R4,R7,R17,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R29,R30,R31,R32,R33,R34,R35,R36,R37,R38,R41 |
| macos-webkit 390px, end-close, ideal line | cand:?preset=v2-proved | R4,R7 |
| macos-webkit 390px, end-close, ideal line | cand:hero.exit:faithful | R20,R28,R32,R33,R34,R36,R38 |
| macos-webkit 390px, end-close, ideal line | cand:hero.exit:scoped | R17,R27,R29,R30,R31,R35,R37 |
| macos-webkit 390px, end-close, ideal line | cand:morph.tween:scroll-lock | R21,R22,R25 |
| macos-webkit 390px, end-close, ideal line | cand:morph.tween:waapi | R19,R24 |
| macos-webkit 390px, end-close, ideal line | orig | R4,R7,R17,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R29,R30,R31,R32,R33,R34,R35,R36,R37,R38,R41 |
| macos-webkit 390px, end-close, ideal ref | base | R4,R7,R17,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R29,R30,R31,R32,R33,R34,R35,R36,R37,R38,R41 |
| macos-webkit 390px, end-close, ideal ref | cand:?preset=v2-proved | R4,R7 |
| macos-webkit 390px, end-close, ideal ref | cand:hero.exit:faithful | R20,R28,R32,R33,R34,R36,R38 |
| macos-webkit 390px, end-close, ideal ref | cand:hero.exit:scoped | R17,R27,R29,R30,R31,R35,R37 |
| macos-webkit 390px, end-close, ideal ref | cand:morph.tween:scroll-lock | R21,R22,R25 |
| macos-webkit 390px, end-close, ideal ref | cand:morph.tween:waapi | R19,R24 |
| macos-webkit 390px, end-close, ideal ref | orig | R4,R7,R17,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R29,R30,R31,R32,R33,R34,R35,R36,R37,R38,R41 |
| macos-webkit 390px, end-open, ideal line | base | R4,R7,R17,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R29,R30,R31,R32,R33,R34,R35,R36,R37,R38,R41 |
| macos-webkit 390px, end-open, ideal line | cand:?preset=v2-proved | R4,R7 |
| macos-webkit 390px, end-open, ideal line | cand:hero.exit:faithful | R20,R28,R32,R33,R34,R36,R38 |
| macos-webkit 390px, end-open, ideal line | cand:hero.exit:scoped | R17,R27,R29,R30,R31,R35,R37 |
| macos-webkit 390px, end-open, ideal line | cand:morph.tween:scroll-lock | R21,R22,R25 |
| macos-webkit 390px, end-open, ideal line | cand:morph.tween:waapi | R19,R24 |
| macos-webkit 390px, end-open, ideal line | orig | R4,R7,R17,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R29,R30,R31,R32,R33,R34,R35,R36,R37,R38,R41 |
| macos-webkit 390px, end-open, ideal ref | base | R4,R7,R17,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R29,R30,R31,R32,R33,R34,R35,R36,R37,R38,R41 |
| macos-webkit 390px, end-open, ideal ref | cand:?preset=v2-proved | R4,R7 |
| macos-webkit 390px, end-open, ideal ref | cand:hero.exit:faithful | R20,R28,R32,R33,R34,R36,R38 |
| macos-webkit 390px, end-open, ideal ref | cand:hero.exit:scoped | R17,R27,R29,R30,R31,R35,R37 |
| macos-webkit 390px, end-open, ideal ref | cand:morph.tween:scroll-lock | R21,R22,R25 |
| macos-webkit 390px, end-open, ideal ref | cand:morph.tween:waapi | R19,R24 |
| macos-webkit 390px, end-open, ideal ref | orig | R4,R7,R17,R19,R20,R21,R22,R23,R24,R25,R26,R27,R28,R29,R30,R31,R32,R33,R34,R35,R36,R37,R38,R41 |
| macos-webkit 390px, hero, ideal line | base | R1,R3,R4,R7,R8,R11,R17,R20 |
| macos-webkit 390px, hero, ideal line | cand:?preset=v2-proved | R4,R7 |
| macos-webkit 390px, hero, ideal line | cand:hero.exit:faithful | R8,R11,R20 |
| macos-webkit 390px, hero, ideal line | cand:hero.exit:scoped | R1,R3,R17 |

### Run index

R1 = 39448209903; R2 = 39449092483; R3 = 39452631146; R4 = 39453181962; R5 = 39453458295; R6 = 39453764374; R7 = 39455284967; R8 = 39456741492; R9 = 39457063232; R10 = 39457767229; R11 = 39461484608; R12 = 39462241403; R13 = 39463486725; R14 = 39464294630; R15 = 39464309993; R16 = 39464322751; R17 = 39466179818; R18 = 39466378530; R19 = 39471466367; R20 = 39472217441; R21 = 39496271199; R22 = 39498373119; R23 = 39500347224; R24 = 39504209400; R25 = 39505188144; R26 = 39505203727; R27 = 39508414669; R28 = 39508421419; R29 = 39514533027; R30 = 39514585897; R31 = 39514619612; R32 = 39514655614; R33 = 39514696773; R34 = 39514734504; R35 = 39515982760; R36 = 39516021307; R37 = 39516056860; R38 = 39516092834; R39 = 39520317047; R40 = 39522707053; R41 = 39542978747; R42 = 39548822269; R43 = 39553952680; R44 = 39556935431; R45 = 39557718020
