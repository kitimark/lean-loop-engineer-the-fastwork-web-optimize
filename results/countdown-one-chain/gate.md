# Breakpoint gate on `?fw=hero.countdown:one-chain` against a no-flag base

MEASURED. Workflow breakpoint-gate, engines both: Chromium 156.0.8078.4 and WebKit 27.2 (playwright-core 1.64.1).
Each run reads its config from the loaded page. Both runs were dispatched with `pnpm fw run --gate --engines both`.

## Verdict run (after the main merge)

The flag arm is the branch head 777c0c5d, which merges main b269d2c8. The base arm is that merge-base, b269d2c8, with no
flag.

| run | ref | sha | flags (config) | Chromium | WebKit | not-ok cells |
|---|---|---|---|---|---|---|
| 39367028590 | ci/countdown-one-chain | 777c0c5d | `hero.countdown:one-chain` (0b068d6eedfb10ad) | pass: 504 cells, 7049 pass, 0 fail, 7 excused | incomplete: 504 cells, 6763 pass, 0 fail, 291 excused, 1 not ok | WebKit `matchMedia =Lean\|sweep:phone-rotation` |
| 39367037943 | ci/countdown-one-chain-base | b269d2c8 | none (ede2c7641aacf2d2) | pass: 504 cells, 7049 pass, 0 fail, 7 excused | incomplete: 504 cells, 6763 pass, 0 fail, 291 excused, 1 not ok | WebKit `matchMedia =Lean\|sweep:phone-rotation` |

The two not-ok sets are equal. Each holds one cell, the WebKit phone-rotation matchMedia cell (`phone-rotation#1` and
`#3` not-comparable), and that cell is not ok on main as well. Every reading count matches between the runs. The
hero.countdown row passes in all 14 columns on Chromium. On WebKit it passes 12 columns, and the other 2
(hover-pointer-cross, fractional-gaps) are UNREACHABLE by the Lean reach rule, the same as in the base.

## Earlier runs (commit 75b08603, before the main merge)

| run | scope | Chromium | WebKit | merged verdict |
|---|---|---|---|---|
| 39313815482 | all parts | hero.countdown passes all 14 columns; commission fails 4 margin items | every row passes | fail (commission) |
| 39318057726 | `parts=hero.countdown` | 301 readings pass, 0 fail, 3 excused | 301 pass, 0 fail, 3 excused | refused: 28 cells per engine are `not-run`, outside the narrowed scope |

The commission margin items came from the Chromium flake that cmr-margin-rect-rule (Lean `Fw.Gate.MarginRule`) fixed on
main. They are gone in the verdict run above.
