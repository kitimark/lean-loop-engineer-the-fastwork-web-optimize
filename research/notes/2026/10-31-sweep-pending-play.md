# sweep-pending-play: the sweep's offscreen pause leaves a pending play running

Task `sweep-pending-play` (plan r608), follow-up of `10-31-hero-offscreen-pause.md`.

## Finding (CONFIRMED in code, not measured)

`watchSweepPause` (`apps/site/src/parts/platform.sweep/pause.ts`) saved `a.startTime` and called `a.pause()` for every animation it
snapshotted. An animation whose play is still pending (`playState` running, `startTime` null) saved null; resume only called `play()`,
so the loop continued from its hold time and lagged the unpaused phase by the off-screen time. The Lean model resumes at `orig`
(`Fw.Parts.PlatformSweepPause.seek`), so the code broke the identity it claims.

## Fix

Pause only an animation that is running with a start time; resume only one still paused (one the page cancelled while paused is left alone).
Same guard as `hero.accent/pause.ts`. Unit tests in `platform.sweep/pause.test.ts`: a pending-play animation stays running with no
pause/play calls; a running one pauses and resumes with the saved start time.

Reuse was tried and refused. `part-footprint.mjs` reads `pause()`/`play()`/`startTime` at the call site as a style write, so one
shared watcher moves the write rows from one part set to the other (the hero rows vanished in the trial). Each part keeps its call site;
the pure model (`init`, `seek`, `tick`, `reportAction`) is shared as before.

## Lean

Premise `Running` is now named in the module docstring of `lean/Fw/Parts/PlatformSweepPause.lean`: `seek` pauses only a running
animation with a start time; `shown_same` and `Ok` concern the animations the watcher pauses. A TS guard, not proved about the engine.
`Lag` (the observer reports after the frame the element leaves) stays a named premise. No theorem changed.

## Goldens, class, limits

Footprint regenerated with `part-footprint.mjs --write`, `--check` green (sweep rows only, line 45 to 50). Same look (class E), no preset
change, no device or Simulator claim. gate: run id added by the lead.
