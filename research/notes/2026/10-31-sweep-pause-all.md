# sweep-pause-all: the sweep pause must reach all four loops

Task `sweep-pause-all` (plan r609). Follow-up of `10-31-sweep-pending-play.md`; census facts from sim-end-cut (CI iOS Simulator run
41173535319): `platform.sweep:offscreen-pause` left 2 of the 4 `sweepDoc` loops running at the end of the page in 3 of 3 jobs (v2p: 4).
That run predates the pending-play guard (6f3fae869), so the guard is not the cause of those 2.

## Cause candidates and what the code does (INFERRED from the code; the Simulator census below decides)

The old watcher read `el.getAnimations()` once at mount (the effect) and kept that list. It could miss a loop in three ways:
1. a loop that did not yet exist at mount or was recreated after it (the cue float watcher reads at report time for this reason);
2. a loop still pending at the report (after the guard it was skipped, before the guard it saved a null start time);
3. a hidden report with nothing pausable still set `paused`, so the next hidden report was `none` (reportAction) and nothing paused later.
All three are one defect: the pause decision used a list taken at another time than the report.

## Fix (class E, same look)

`watchSweepPause` reads `getAnimations()` at each hidden report, pauses what is running with a start time, waits on `ready` for a pending play
and pauses it then if the element is still reported, and pauses a loop created while reported on `animationstart`. The start time saved at
the pause is restored at the resume, so the phase is `orig` (`Fw.Parts.PlatformSweepPause.seek`, `shown_same`, `visible_phase`): no new
Lean case, the model's `paused` state covers a loop paused later. Unit tests: pending then ready, ready after visible again, created later, not touched while visible.
TS stand-in: none new; the pure model is still golden-checked (`platform-sweep-pause`).

## Census (own function, same harness)

`SWEEP_LOOPS_JS` in `packages/measure-webkit/src/sim-end-floor.mjs`: one row per sweepDoc animation
[target, playState, pending, startTime null, in viewport] at the end and back stages, a new arm `sweepPause` (`?fw=platform.sweep:offscreen-pause`,
the flag alone: the preset flag `platform:faded-pause` conflicts with it). Rows file lines `sweep loops <arm>`.

## platform:faded-pause vs platform.sweep:offscreen-pause (finding, no change)

`platform/part.json` conflicts them. faded-pause pauses every CSS animation in the section subtree while the section's fade is 0 and restores
their start times from one saved map (`createFadedPause`); the sweep watcher pauses and restores the same animations by its own saved map. Two
owners of `pause()`/`startTime` on one animation break the resume identity (each restores a start time the other one moved). The conditions
differ: faded = fade 0 (section invisible), offscreen = no overlap with the viewport; at the end of the page the section is offscreen but not
faded (sim-end-cut v2p still ran 4 sweeps). They could compose with one owner holding a reason set {faded, offscreen} per animation and resuming
only when it is empty (like `writer_or` for the scene attribute). That is a new Lean case (resume phase with two reasons) and a registry change;
follow-up, not done here.

## Limits

IntersectionObserver lag stays a named premise (the leaving frame ticks). No preset change. Simulator is not the phone; the full-stack rate is
measured by sim-end-cut-2.
