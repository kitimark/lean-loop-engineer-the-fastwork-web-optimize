# sweep-pause-all: the platform scene rule restarts the hidden loops

Task `sweep-pause-all` (plan r609). Follow-up of `10-31-sweep-pending-play.md`.

## Finding 1: two of the four loops are on screen at the end of the page (MEASURED)

sim-end-cut (run 41173535319) read "platform sweep running 2" at the end as two loops the pause missed. The new census `sweepLoops()` (one row per
sweepDoc animation: target, playState, pending, startTime null, target in the viewport) shows that the Secure and Organized words are inside the
viewport at the end of the page (CI iOS Simulator run 41182219539, 3 jobs, and run 41186783133). Running two there is correct; "running 0 at the
end" is the wrong target, the right one is "running out of the viewport 0".

## Finding 2: cause of the hidden loops that still run (MEASURED: CI runs above for the numbers, local Playwright WebKit repro for the mechanism)

With the flag alone the end stage reads 4 running, 2 of them out of the viewport (all three jobs, with the pending-play guard and with a version
that paused every running loop); after the scroll up and back the 2 are paused. A local debug repro (Playwright WebKit, 430 px, patched
`pause`/`play` and IntersectionObserver logging) shows why: at load `getComputedStyle().animationPlayState` is already `paused` for all
four loops. The platform section's own scene rule (`data-fw-scene`, `platform/scene.ts`, `platform.module.css`; the original's `manageAnimations`
with rootMargin 100%) pauses every animation of the section in CSS while it is more than a viewport away. The watcher saw the loops as not running
(CSS paused), paused none (correct), and marked the element reported. When the scene turns `active` (the section is within one viewport) the CSS
starts all four again, including Document and Earn whose words are still out of the viewport. No IntersectionObserver report follows (they stay
hidden), so nothing paused them. The hidden loops stayed running until a later visible then hidden report. Neither the old mount-time list nor
the pending-play guard was the cause.

## Fix (class E, same look)

`watchSweepPause(els, IO, now, host)` holds the reported elements again when the scene attribute of `host` (the section) changes
(MutationObserver on `data-fw-scene`, a microtask in the report/frame step, no per-frame work): the CSS start leaves a pending play, which is
paused before the frame is drawn. It reads `getAnimations()` at each hold and pauses every running animation. A loop with a start time restores
it at the resume (Lean `seek` to `orig`, unchanged). A loop with none (the scene start) saves its current time (the CSS hold time) and resumes
at that time plus the time the scene was active while held (`resumeTime`), which is the phase the flag-off page shows: there the CSS rule freezes
the loop while the scene is paused. A loop with a start time moves its start later by the time the scene was paused while held (`startShift`). Local repro with the fix: end stage Document and Earn paused, Secure and Organized running. Unit tests in
`platform.sweep/pause.test.ts` (scene attribute change holds a reported element; leaves an on-screen one; no start time pauses and resumes at
time plus paused; created after mount; empty first report; cancelled while paused left alone). No `animationstart` listener (the
`engine.events:quiet` premise allows none). Lean: see "Lean for the fix" below; `shown_same`, `visible_phase` unchanged.
After the first `pause()` the CSS play state is overridden on that animation (WebKit CSSAnimation.cpp:278-287@862f17d), so the scene rule no longer
pauses a loop we hold or resumed. Round 1 missed what follows: hidden at the end of the page, scroll to the top (scene paused), scroll back showed
cur + whole wall-clock time instead of cur + the time the scene was active (off by the scene-paused span mod PERIOD_MS). The MutationObserver callback
now reads the scene attribute and closes a span for every held entry (`setScene`).

## Census of the fix (MEASURED)

CI iOS Simulator run 41196494063 at ce9eb255b (round 2 code, scene-frozen spans), arm set `sweep`, 3 of 3 jobs (`results/sweep-pause-all/r3/sweep-loops.txt`);
run 41189420040 at c74f1111e (round 1 code) gave the same counts (`r2/sweep-loops.txt`).

| arm | stage | running (all 4) | hidden running |
|---|---|---|---|
| base | end, back | 4 | 2 of 2 |
| sweepPause | end, back | 2 (the in-view Secure, Organized) | 0 of 2 |

The target is "hidden loops running 0 at the end": met in 3 of 3 jobs. The census counts play states, not phases; the phase identity is the Lean fold plus the
golden and unit tests. The Simulator is not the phone; the full-stack rate is sim-end-cut-2's.

## Lean for the fix (class E, same look)

`Fw.Parts.PlatformSweepPause`, section "Held loops". Premise `Override` (CSSAnimation.cpp:278-287@862f17d, CONFIRMED for WebKit; Chromium INFERRED the
same): after a script pause the scene rule no longer freezes the loop. The hold is a list of spans (duration, scene active). `Unpaused cur spans` is
defined on its own as `cur + activeSum spans`, what the flag-off page shows. The TS state `Held` (`cur`, `fz`, `since`, `frozen`) steps by `advance`
(one closed span), `close` and `setScene` (the observer callback). Proofs, all by induction on the spans or events:

| statement | theorem |
|---|---|
| the fold of `advance` gives cur = `Unpaused`, fz = frozen sum, since = total | `fold_core` |
| the page without tracking differs by exactly the frozen sum; a positive frozen span makes it differ | `untracked_off`, `untracked_differs` |
| the TS event handler closed at the resume equals the span fold | `events_core` |
| no start time: `resumeTime` = `Unpaused` over the spans, so any looking function agrees | `resume_same`, `look_same_pending`, `resume_pending_phase` |
| start time: `now - (start + startShift)` = `Unpaused` (premise `Clock`: a running loop shows clock minus start, so `cur = since - start`) | `start_same` |

Re-hold: `holdNew held running` has three branches (`hold_already_held`, `hold_running_new`, `hold_not_running`); the table `hold` never moves an earlier
entry (`rehold_keeps`, `rehold_idem`). Golden `platform-sweep-pause.jsonl` (17 lines): `resume` rows (resume time, start shift, independent `Unpaused`),
including scene paused then active while held; `pause.test.ts` replays them and has the two path cases (no start time, start time).

## Why the pending-play guard is reversed

`sweep-pending-play` paused only a loop with a start time, so a pending play was left running. Here a pending play is the scene rule's own start of a
hidden loop, which that guard left running; pausing it and resuming at `cur + paused` shows the unpaused phase (`resume_pending_span`).

## Census (own function, same harness)

`SWEEP_LOOPS_JS` in `packages/measure-webkit/src/sim-end-floor.mjs` for every arm at the end and back stages, and the arm set `sweep`
(`base`, `sweepPause` = `?fw=platform.sweep:offscreen-pause` alone; `platform:faded-pause` conflicts with it), picked by the tag `[end-sweep]` in
webkit-sim.yml. Rows file lines `sweep loops <arm>` give the count running out of the viewport. `results/sweep-pause-all/r1/sweep-loops.txt`
holds the rows of run 41182219539 before the fix.

## platform:faded-pause vs platform.sweep:offscreen-pause (finding, no change)

`platform/part.json` conflicts them. faded-pause pauses every CSS animation of the section subtree while the section's fade is 0 and restores
their start times from one saved map (`createFadedPause`); the sweep watcher pauses and restores the same animations by its own map. Two
owners of `pause()`/`startTime` on one animation break the resume identity (each restores a start time the other moved). The conditions
differ: faded = fade 0 (section invisible), offscreen = no overlap with the viewport. They could compose with one owner holding a reason set
{faded, offscreen} per animation, resuming at the empty set (like `writer_or` for the scene attribute). That is a new Lean case (resume phase
with two reasons) and a registry change; follow-up. The scene rule is a third pauser of the same animations (CSS), which the composition proof must include.

## Follow-ups

`hero.accent/pause.ts` and the cue float watcher may have the same shape (a CSS or scene rule starting a loop behind the watcher); the end-of-page
census would show it (cut.txt: "accent idle running 3" in some rounds). Not touched here. sim-end-cut-2 measures the full-stack rate;
IntersectionObserver lag stays a named premise.
