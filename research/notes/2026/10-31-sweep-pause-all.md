# sweep-pause-all: two of the four loops are on screen at the end of the page

Task `sweep-pause-all` (plan r609). Follow-up of `10-31-sweep-pending-play.md`.

## Finding 1: the task's premise fell (MEASURED, CI iOS Simulator run 41182219539, jobs 1 to 3, one round each, `results/sweep-pause-all/`)

sim-end-cut (run 41173535319) read "platform sweep running 2" at the end of the page as two loops the pause missed. The new census
`sweepLoops()` (one row per sweepDoc animation: target, playState, pending, startTime null, target in the viewport) shows the two loops
that run in the sim-end-cut flag arms are the Secure and Organized words, which are inside the viewport at the end of the page (in view true);
the Document and Earn words are out of it. Running two there is correct: pausing a visible loop would change the look. The run that
produced sim-end-cut used the code before the pending-play guard, and it paused the two hidden loops. "Running 0 at the end" is therefore
the wrong target; the right one is "running out of the viewport 0".

## Finding 2: the pending-play guard (6f3fae869) regressed the end stage (MEASURED, same run)

With the guard, arm `sweepPause` (flag alone) at the end stage: 4 running of 4, two of them out of the viewport, startTime set, not pending.
After the scroll up and back (`back` stage): 2 running, the two hidden loops paused. So at the first hidden report the two out-of-view
loops had no start time yet, the guard skipped them, and no later report came because the page jumped straight to the end. The
sweep-pending-play note had assumed a play with a null start time is pending and soon starts; it never got a second report.
(An intermediate version in this branch waited on `ready`; the same 4 running at the end stage shows that waiting does not pause them in
WebKit. That is the run's code, cb16967d6.)

## Fix (class E, same look)

`watchSweepPause` reads `getAnimations()` at each hidden report and pauses every running animation, pending or not. For a loop with a start
time it restores that start time at the resume (Lean `seek` to `orig`, unchanged). For a loop with none it saves the current time and a
`performance.now()` stamp and resumes at the current time plus the time spent paused (`resumeTime`), which is within one frame of the unpaused
phase (the loop had just been created, current time 0). No `animationstart` listener: the `engine.events:quiet` premise allows none, so a loop
created while the element stays reported is not tracked. Unit tests in `platform.sweep/pause.test.ts` (no start time yet pauses and resumes at
time plus paused; created after mount; empty first report; cancelled while paused left alone). No new Lean case: `Running` premise text in
`PlatformSweepPause.lean`; `shown_same`, `visible_phase` unchanged.

## Census (own function, same harness)

`SWEEP_LOOPS_JS` in `packages/measure-webkit/src/sim-end-floor.mjs`, run for every arm at the end and back stages; the extra arm `sweepPause`
(`?fw=platform.sweep:offscreen-pause`, the flag alone; the preset flag `platform:faded-pause` conflicts with it) is in `EXTRA_ARMS`, not in the Lean
`ArmId` list. Rows file lines `sweep loops <arm>` give the count running out of the viewport.

## platform:faded-pause vs platform.sweep:offscreen-pause (finding, no change)

`platform/part.json` conflicts them. faded-pause pauses every CSS animation of the section subtree while the section's fade is 0 and restores
their start times from one saved map (`createFadedPause`); the sweep watcher pauses and restores the same animations by its own map. Two
owners of `pause()`/`startTime` on one animation break the resume identity (each restores a start time the other moved). The conditions
differ: faded = fade 0 (section invisible), offscreen = no overlap with the viewport. They could compose with one owner holding a reason set
{faded, offscreen} per animation, resuming at the empty set (like `writer_or` for the scene attribute). That is a new Lean case (resume phase
with two reasons) and a registry change; follow-up.

## Follow-ups

`hero.accent/pause.ts` has the same skip of a play with no start time (the guard of sweep-pending-play was copied from it); the same end-of-page
census would show it. Not touched here. sim-end-cut-2 measures the full-stack rate; IntersectionObserver lag stays a named premise.
