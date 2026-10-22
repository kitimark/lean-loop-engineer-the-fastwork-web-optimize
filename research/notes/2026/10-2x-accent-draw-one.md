# accent-draw-one: run the headline scribble draw on the visible copy only

Flag `hero.accent:draw-one`, class E (exact). Task accent-draw-one, ledger row n=43.

## Change
During the draw window (`.drawingOut` / `.drawingIn`, 0.9 s each, every 3.05 s) the accent's three SVG copies all run the
`strokeIn` / `strokeOut` dash-offset animation (`accent.module.css:52-61`), while copies 1 and 2 are opacity 0 for the whole window
(`:79-86`). The variant adds one rule that sets `animation: none` on the path of every copy except `frame0` while the host has
`data-fw-draw="one"`. The idle boil and the faithful page are untouched.

## Proof (Lean `Fw.Parts.HeroAccentOpt`, section 7)
- CONFIRMED premise: `drawAlpha j` is 1 for copy 0, 0 otherwise; `drawTmpl_hidden`: each copy is constant in the hidden dash
  offset or dropped by `visible`.
- `draw_one_eq`, `drawOne_visSame`: from `HiddenPause.hidden_pause_eq` / `hiddenPause_visSame`; the visible scene is the original's
  at every instant, in every viewport, including the frames where the class switches.
- `drawOne_still_iff`: a copy is left still exactly when its window opacity is 0.
- `animatedCount_values`: 3 animated paths per draw frame become 1; idle frames run none in either.
- Golden `packages/contracts/golden/parts/hero.accent.drawone.jsonl` (16 rows) checked by `drawOne.test.ts`.

## Measurement (MEASURED, CI webkit-sim, iPhone 430x775 Simulator, 107-step scroll, 2 passes per arm)
Base run 39694385829, flag run 39699740380 (a first flag attempt, run 39694397870, died on a Simulator Runtime.evaluate timeout and is not a result).

| metric | base p1 / p2 | draw-one p1 / p2 |
|---|---|---|
| Layout events, whole scroll | 612 / 627 | 612 / 612 |
| Layout events, hero band (y up to 775) | 108 / 116 | 107 / 109 |
| Layout time, hero band (ms) | 60.4 / 126.2 | 63.8 / 60.3 |
| RecalculateStyles events, whole scroll | 654 / 681 | 650 / 641 |

Base pass 2 ran slow (scroll wall 14.4 s against 7.3 to 7.5 s elsewhere). Pass 1 against pass 1: 60.4 against 63.8 ms. No effect shows.
Breakpoint gate, both engines, `--fw hero.accent:draw-one`: run 39694389914 success. Lean CI: run 39694357292 success.
The lane has no per-SVG layout events and no RenderingFrame events, so the card's "SVG path layouts per draw frame" (3 to 1) is the
Lean count, not a CI reading, and frame interval p50/p90/p99 do not exist for this lane.

## Why no win (PROVED shape, INFERRED size)
WebKit runs one Layout pass per frame whenever any animated path is dirty; the visible copy still dirties it every draw frame, so the
pass count is unchanged and two of three small path boxes leave it. About 0.5 ms per Layout event here is below the pass-to-pass spread.

## Lesson
Cutting work on objects nobody sees pays only where the engine pays per object. Next: re-measure where frame time inside the draw windows is recorded.
