# port-fonts-check: visual-diff verdicts per cell, inject baseline vs the none runs

Source: the visual-diff matrix tables of CI runs (workflow visual-diff, branch ci/port-fonts-check): inject baseline 39245980604 (assets=inject) and none run n1 39245919162 at cb49c4d3; none runs n2 39248286394 and n3 39248398577 at 34e6805c (assets=none, the port as built). cb49c4d3..34e6805c changes only scripts/port/fonts.mjs.
Verdicts: P pass, F fail, U unsettled, I invalid, - absent in both arms (nc). Columns: part, probe, inject, n1, n2, n3, flag (one table per engine).
A cell is listed when any none run differs from the inject baseline. Flag "FLIP" marks a cell whose verdict is not the same in the three none runs (run-to-run flip); the other listed cells moved from inject to one stable none verdict.

## chromium

248 cells; 74 listed (45 moved from inject to one stable none verdict, 29 flip between the none runs). Stable cells by inject to none: F->- 8, F->F 47, F->P 22, F->U 13, U->P 2, U->U 127

| part | probe | inject | n1 | n2 | n3 | flag |
|---|---|---|---|---|---|---|
| nav.hitTest | desk-1512 | F | P | P | P |  |
| nav.hitTest | desk-861 | F | P | P | P |  |
| nav.hitTest | touch-1031 | F | P | P | P |  |
| nav.hitTest | touch-401 | F | P | P | P |  |
| nav.hitTest | desk-1100 | F | P | P | P |  |
| nav.hitTest | desk-641 | F | P | P | P |  |
| nav.hitTest | touch-601 | F | P | P | P |  |
| nav.hitTest | touch-320 | F | P | P | P |  |
| hero.countdown | desk-1512 | F | F | F | U | FLIP |
| hero.countdown | touch-1031 | F | U | U | U |  |
| hero.countdown | touch-601 | F | U | U | U |  |
| hero.countdown | touch-320 | F | U | U | U |  |
| morph.countdown | desk-1512 | F | P | P | P |  |
| morph.countdown | desk-861 | F | P | P | P |  |
| morph.countdown | touch-1031 | F | P | P | P |  |
| morph.countdown | desk-1100 | F | P | P | P |  |
| morph.countdown | desk-641 | F | P | P | P |  |
| morph.countdown | touch-320 | F | P | P | P |  |
| morph.columns | desk-1512 | F | F | F | P | FLIP |
| morph.columns | desk-861 | F | P | F | P | FLIP |
| morph.columns | touch-1031 | F | F | F | P | FLIP |
| morph.columns | desk-1100 | F | P | P | F | FLIP |
| morph.columns | desk-641 | F | F | P | F | FLIP |
| morph.panel | desk-1512 | F | F | F | P | FLIP |
| morph.panel | desk-861 | F | P | F | P | FLIP |
| morph.panel | touch-1031 | F | F | F | P | FLIP |
| morph.panel | desk-1100 | F | P | P | F | FLIP |
| morph.panel | desk-641 | F | F | P | F | FLIP |
| overlays.drawer | desk-1512 | F | U | F | P | FLIP |
| overlays.drawer | desk-861 | F | P | P | P |  |
| overlays.drawer | touch-1031 | F | U | F | F | FLIP |
| overlays.drawer | touch-401 | F | P | P | P |  |
| overlays.drawer | desk-1100 | U | P | P | P |  |
| overlays.drawer | desk-641 | F | P | P | P |  |
| overlays.drawer | touch-601 | F | P | P | P |  |
| overlays.drawer | touch-320 | F | P | P | P |  |
| overlays.signup | touch-320 | U | U | F | F | FLIP |
| hero | desk-861 | F | U | U | U |  |
| hero.orbit | touch-401 | F | - | - | - |  |
| hero.orbit | desk-1100 | F | U | U | U |  |
| hero.orbit | touch-320 | F | - | - | - |  |
| hero.deck | desk-1512 | F | - | - | - |  |
| hero.deck | desk-861 | F | - | - | - |  |
| hero.deck | touch-1031 | F | - | - | - |  |
| hero.deck | desk-1100 | F | - | - | - |  |
| hero.deck | desk-641 | F | - | - | - |  |
| hero.deck | touch-601 | F | - | - | - |  |
| hero.accent | desk-1512 | F | F | P | F | FLIP |
| hero.accent | desk-861 | F | F | P | F | FLIP |
| hero.accent | touch-401 | F | U | U | U |  |
| hero.accent | desk-1100 | F | F | P | P | FLIP |
| hero.accent | desk-641 | F | F | P | P | FLIP |
| hero.cue | touch-1031 | F | F | U | F | FLIP |
| hero.cue | touch-401 | F | U | U | U |  |
| people.card | desk-861 | F | U | U | U |  |
| people.card | desk-641 | F | F | F | U | FLIP |
| people.card | touch-601 | F | U | U | F | FLIP |
| people.o | touch-601 | F | P | P | F | FLIP |
| people.carousel | desk-861 | F | U | F | U | FLIP |
| people.carousel | touch-401 | F | U | U | U |  |
| people.carousel | desk-1100 | F | U | F | F | FLIP |
| people.carousel | desk-641 | F | F | U | F | FLIP |
| people.deck | touch-1031 | F | F | U | U | FLIP |
| pain | desk-861 | F | U | U | U |  |
| pain.notes | desk-861 | F | U | U | U |  |
| platform.glint | desk-1512 | F | U | U | U |  |
| platform.glint | desk-861 | U | P | P | P |  |
| platform.glint | touch-1031 | F | P | P | U | FLIP |
| platform.glint | touch-401 | F | P | P | P |  |
| platform.glint | desk-1100 | F | P | P | P |  |
| platform.glint | desk-641 | F | U | U | U |  |
| platform.glint | touch-601 | F | P | P | P |  |
| platform.glint | touch-320 | U | F | U | F | FLIP |
| engine.scene | touch-320 | I | U | I | U | FLIP |

## playwright-webkit

248 cells; 119 listed (85 moved from inject to one stable none verdict, 34 flip between the none runs). Stable cells by inject to none: F->- 9, F->F 30, F->P 55, F->U 14, I->I 3, I->U 4, U->I 3, U->U 96

| part | probe | inject | n1 | n2 | n3 | flag |
|---|---|---|---|---|---|---|
| nav.hitTest | desk-1512 | F | P | P | P |  |
| nav.hitTest | desk-861 | F | P | P | P |  |
| nav.hitTest | touch-1031 | F | P | P | P |  |
| nav.hitTest | touch-401 | F | P | P | P |  |
| nav.hitTest | desk-1100 | F | P | P | P |  |
| nav.hitTest | desk-641 | F | P | P | P |  |
| nav.hitTest | touch-601 | F | P | P | P |  |
| nav.hitTest | touch-320 | F | P | P | P |  |
| morph.mount | touch-1031 | U | I | U | I | FLIP |
| morph.mount | touch-401 | U | I | U | I | FLIP |
| morph.mount | desk-641 | I | U | U | U |  |
| morph.mount | touch-320 | U | I | U | I | FLIP |
| hero.countdown | desk-1100 | U | U | U | F | FLIP |
| morph.countdown | desk-1512 | F | P | P | P |  |
| morph.countdown | desk-861 | F | P | P | P |  |
| morph.countdown | touch-1031 | F | P | P | P |  |
| morph.countdown | touch-401 | F | P | P | P |  |
| morph.countdown | desk-1100 | F | P | P | P |  |
| morph.countdown | desk-641 | F | P | P | P |  |
| morph.countdown | touch-601 | F | P | P | P |  |
| morph.countdown | touch-320 | F | P | P | P |  |
| morph.columns | desk-1512 | F | P | P | P |  |
| morph.columns | desk-861 | F | P | P | P |  |
| morph.columns | touch-1031 | F | P | P | P |  |
| morph.columns | touch-401 | F | P | P | P |  |
| morph.columns | desk-1100 | F | P | P | P |  |
| morph.columns | desk-641 | F | P | P | P |  |
| morph.columns | touch-601 | F | P | P | P |  |
| morph.columns | touch-320 | F | P | P | P |  |
| morph.panel | desk-1512 | F | P | P | P |  |
| morph.panel | desk-861 | F | P | P | P |  |
| morph.panel | touch-1031 | F | P | P | P |  |
| morph.panel | touch-401 | F | P | P | P |  |
| morph.panel | desk-1100 | F | P | P | P |  |
| morph.panel | desk-641 | F | P | P | P |  |
| morph.panel | touch-601 | F | P | P | P |  |
| morph.panel | touch-320 | F | P | P | P |  |
| nav | desk-1512 | F | P | P | P |  |
| nav | desk-861 | F | P | P | P |  |
| nav | touch-1031 | F | P | P | P |  |
| nav | touch-401 | F | P | P | P |  |
| nav | desk-1100 | F | P | P | P |  |
| nav | desk-641 | F | P | P | P |  |
| nav | touch-601 | F | P | P | P |  |
| nav | touch-320 | F | P | P | P |  |
| nav.langMenu | desk-1512 | F | P | P | P |  |
| nav.langMenu | desk-861 | F | P | P | P |  |
| nav.langMenu | touch-1031 | F | P | P | P |  |
| nav.langMenu | touch-401 | F | P | P | P |  |
| nav.langMenu | desk-1100 | F | P | P | P |  |
| nav.langMenu | desk-641 | F | P | P | P |  |
| nav.langMenu | touch-601 | F | P | P | P |  |
| nav.langMenu | touch-320 | F | P | P | P |  |
| commission.typing | desk-861 | F | U | U | U |  |
| commission.typing | touch-1031 | F | U | P | P | FLIP |
| commission.typing | desk-1100 | U | F | U | U | FLIP |
| commission.typing | desk-641 | F | U | U | U |  |
| commission.typing | touch-601 | U | U | U | F | FLIP |
| commission.typing | touch-320 | F | U | F | U | FLIP |
| overlays.drawer | desk-861 | I | U | U | U |  |
| overlays.drawer | touch-1031 | U | U | U | I | FLIP |
| overlays.drawer | touch-401 | F | P | P | P |  |
| overlays.drawer | desk-1100 | I | U | U | U |  |
| overlays.drawer | desk-641 | U | I | U | U | FLIP |
| overlays.drawer | touch-601 | F | P | P | P |  |
| overlays.drawer | touch-320 | F | P | I | I | FLIP |
| overlays.signup | desk-861 | F | U | F | U | FLIP |
| overlays.signup | touch-1031 | U | U | F | U | FLIP |
| overlays.signup | touch-401 | F | F | F | I | FLIP |
| overlays.signup | desk-641 | F | I | I | F | FLIP |
| overlays.signup | touch-601 | F | U | F | F | FLIP |
| overlays.signup | touch-320 | U | I | I | U | FLIP |
| hero.orbit | touch-401 | F | - | - | - |  |
| hero.orbit | touch-320 | F | - | - | - |  |
| hero.deck | desk-1512 | F | - | - | - |  |
| hero.deck | desk-861 | F | - | - | - |  |
| hero.deck | touch-1031 | F | - | - | - |  |
| hero.deck | desk-1100 | F | - | - | - |  |
| hero.deck | desk-641 | F | - | - | - |  |
| hero.deck | touch-601 | F | - | - | - |  |
| hero.accent | desk-861 | F | P | F | F | FLIP |
| hero.accent | touch-1031 | F | U | U | U |  |
| hero.accent | touch-601 | F | P | U | U | FLIP |
| hero.accent | touch-320 | U | F | U | F | FLIP |
| hero.cue | touch-1031 | F | U | U | U |  |
| people.card | desk-861 | U | F | U | U | FLIP |
| people.card | touch-1031 | F | U | U | U |  |
| people.card | desk-1100 | F | U | U | U |  |
| people.o | desk-1512 | F | P | P | P |  |
| people.o | touch-1031 | F | U | U | U |  |
| people.o | desk-1100 | F | P | P | P |  |
| people.o | desk-641 | F | P | P | P |  |
| people.o | touch-601 | F | P | P | P |  |
| people.carousel | desk-1512 | F | U | U | U |  |
| people.carousel | desk-861 | F | U | F | U | FLIP |
| people.carousel | touch-401 | F | U | U | U |  |
| people.carousel | touch-320 | F | U | U | U |  |
| people.deck | touch-1031 | F | U | U | U |  |
| pain.notes | desk-861 | F | U | U | U |  |
| pain.notes | desk-1100 | F | U | U | U |  |
| platform | touch-1031 | U | I | U | U | FLIP |
| platform | touch-401 | U | U | I | I | FLIP |
| platform | desk-1100 | I | I | U | I | FLIP |
| platform | desk-641 | U | I | I | U | FLIP |
| platform.glint | desk-1512 | F | - | - | - |  |
| platform.glint | desk-861 | F | U | P | P | FLIP |
| platform.glint | touch-401 | U | U | P | P | FLIP |
| platform.glint | desk-1100 | F | P | P | P |  |
| platform.glint | desk-641 | F | U | U | P | FLIP |
| platform.glint | touch-601 | F | U | U | P | FLIP |
| platform.glint | touch-320 | F | U | U | U |  |
| platform.marquee | desk-1512 | U | I | U | I | FLIP |
| engine.scene | desk-1512 | I | U | U | U |  |
| engine.scene | desk-861 | U | I | I | I |  |
| engine.scene | touch-401 | U | I | I | I |  |
| engine.scene | desk-1100 | U | I | I | I |  |
| engine.scene | desk-641 | U | U | U | I | FLIP |
| engine.scene | touch-601 | U | U | U | I | FLIP |
| engine.scene | touch-320 | U | I | I | U | FLIP |

## New head 4e62cce1 (round 1, main merged): two runs of the same head

Runs: push 39253450733 (a), dispatch 39256117644 (b), both assets=none. Cells whose verdict differs between a and b.

### chromium

Tally a: {'P': 25, 'U': 147, 'F': 68, '-': 8}; b: {'P': 29, 'U': 148, 'F': 61, 'I': 2, '-': 8}; 14 of 248 cells differ between a and b.

| part | probe | a | b |
|---|---|---|---|
| hero.countdown | desk-1512 | F | U |
| morph.columns | desk-1512 | F | P |
| morph.panel | desk-1512 | F | P |
| overlays.drawer | desk-1512 | U | P |
| overlays.drawer | desk-861 | P | I |
| overlays.signup | touch-401 | F | U |
| hero.accent | desk-1100 | F | P |
| hero.cue | touch-1031 | U | F |
| people.o | touch-601 | F | P |
| people.carousel | desk-641 | F | U |
| platform.glint | touch-1031 | P | U |
| platform.glint | touch-601 | U | P |
| platform.glint | touch-320 | F | U |
| engine.scene | desk-861 | U | I |

### playwright-webkit

Tally a: {'P': 57, 'U': 130, 'I': 16, 'F': 36, '-': 9}; b: {'P': 55, 'U': 126, 'I': 19, 'F': 39, '-': 9}; 16 of 248 cells differ between a and b.

| part | probe | a | b |
|---|---|---|---|
| hero.countdown | desk-1100 | F | U |
| commission.typing | desk-1100 | U | F |
| commission.typing | desk-641 | U | F |
| overlays.signup | desk-1512 | U | F |
| overlays.signup | desk-861 | U | F |
| overlays.signup | desk-1100 | F | I |
| overlays.signup | desk-641 | U | F |
| hero.accent | desk-861 | P | F |
| people.carousel | desk-1512 | F | U |
| platform | touch-1031 | U | I |
| platform | touch-320 | U | I |
| platform.glint | touch-401 | P | U |
| platform.glint | desk-1100 | U | P |
| platform.glint | desk-641 | P | U |
| engine.scene | touch-401 | U | I |
| engine.scene | touch-601 | I | U |

## Check 5 counts per probe, run and engine (real counts; 40 was the old display cap)

Each cell: leaves orig/rewrite, lost/added leaves. New-head runs add: font changes / ownership moves / unpaired lost / unpaired added. All 6 runs, 8 probes, both engines; every cell is the `counts` object of the run artifact.

### chromium

| run | desk-1512 | desk-1100 | desk-861 | desk-641 | touch-1031 | touch-601 | touch-401 | touch-320 |
|---|---|---|---|---|---|---|---|---|
| inject baseline 39245980604 | 408/414 46/52 | 408/414 46/52 | 408/414 46/52 | 462/474 73/85 | 456/468 73/85 | 462/474 73/85 | 462/474 73/85 | 462/474 73/85 |
| none n1 (old reader) 39245919162 | 408/410 53/55 | 408/410 53/55 | 408/414 46/52 | 462/474 73/85 | 456/468 73/85 | 462/474 73/85 | 462/474 73/85 | 462/474 73/85 |
| none n2 (old reader, fix) 39248286394 | 407/405 53/51 | 407/407 46/46 | 407/407 46/46 | 461/461 73/73 | 455/455 73/73 | 461/461 73/73 | 461/461 73/73 | 461/461 73/73 |
| none n3 (dispatch) 39248398577 | 407/407 46/46 | 407/405 53/51 | 407/407 46/46 | 461/461 73/73 | 455/455 73/73 | 461/461 73/73 | 461/461 73/73 | 461/461 73/73 |
| new head a 39253450733 | 408/408 50/50 (45/1/4/4) | 408/408 49/49 (45/1/3/3) | 407/407 48/48 (45/1/2/2) | 461/461 76/76 (72/1/3/3) | 455/455 77/77 (72/1/4/4) | 462/462 77/77 (72/1/4/4) | 461/461 76/76 (72/1/3/3) | 461/461 73/73 (72/1/0/0) |
| new head b 39256117644 | 408/408 50/50 (45/1/4/4) | 407/407 48/48 (45/1/2/2) | 407/407 48/48 (45/1/2/2) | 461/461 77/77 (72/1/4/4) | 455/455 76/76 (72/1/3/3) | 461/461 77/77 (72/1/4/4) | 461/461 77/77 (72/1/4/4) | 461/461 75/75 (72/1/2/2) |

### playwright-webkit

| run | desk-1512 | desk-1100 | desk-861 | desk-641 | touch-1031 | touch-601 | touch-401 | touch-320 |
|---|---|---|---|---|---|---|---|---|
| inject baseline 39245980604 | 406/410 44/48 | 309/410 52/153 | 406/410 44/48 | 463/474 74/85 | 456/468 73/85 | 462/474 73/85 | 364/376 67/79 | 462/474 73/85 |
| none n1 (old reader) 39245919162 | 406/410 44/48 | 406/410 44/48 | 408/410 53/55 | 462/474 73/85 | 456/468 73/85 | 462/390 157/85 | 462/376 165/79 | 462/474 73/85 |
| none n2 (old reader, fix) 39248286394 | 405/405 44/44 | 308/309 52/53 | 405/405 44/44 | 461/462 73/74 | 455/455 73/73 | 363/377 67/81 | 363/363 67/67 | 461/461 73/73 |
| none n3 (dispatch) 39248398577 | 406/406 45/45 | 405/307 136/38 | 408/405 54/51 | 461/462 73/74 | 455/455 73/73 | 461/363 165/67 | 461/363 165/67 | 461/461 73/73 |
| new head a 39253450733 | 408/408 51/51 (45/1/5/5) | 407/408 46/47 (45/1/0/1) | 408/408 50/50 (45/1/4/4) | 462/462 74/74 (72/1/1/1) | 456/455 74/73 (72/1/1/0) | 461/461 77/77 (72/1/4/4) | 462/461 74/73 (72/1/1/0) | 462/462 79/79 (72/1/6/6) |
| new head b 39256117644 | 408/408 47/47 (45/1/1/1) | 408/408 47/47 (45/1/1/1) | 408/408 50/50 (45/1/4/4) | 462/462 76/76 (72/1/3/3) | 456/456 74/74 (72/1/1/1) | 462/462 74/74 (72/1/1/1) | 462/461 74/73 (72/1/1/0) | 462/462 74/74 (72/1/1/1) |
