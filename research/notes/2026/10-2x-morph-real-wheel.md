# The end-of-page morph under a trusted wheel: does the synthetic WheelEvent change the lag counts?

Question: the WebKit lag probe pushes the morph with a synthetic `WheelEvent` on `document.body`. Does a trusted wheel (a
native wheel through the UI process) give different WebKit record counts per frame? Tags: MEASURED (a CI run id named
here), CONFIRMED (source cited), INFERRED (reasoned, not seen).

## Answer

| question | answer | tag |
|---|---|---|
| Does the page see a trusted wheel? | Yes: 72 of 72 trusted-drive events (2 pushes x 36 runs) had `isTrusted` true, 0 of 72 synthetic; all 144 were cancelable and the site called `preventDefault` on all 144 | MEASURED, run 39971123168 |
| Does the trusted push open the morph? | Yes: `--morph` reached 1 and returned to 0 in all 36 trusted runs, as in the synthetic runs | MEASURED, run 39971123168 |
| Do per-frame counts differ, trusted vs synthetic? | No separated difference in 41 of the 42 cells (2 arms x 3 phases x 7 counters); the one cell with a separation is in the idle phase (see below) | MEASURED, run 39971123168; pooled over 18 runs, superseded by the per-job verdicts of the follow-up below |
| Phase rule | Lean `Fw.Measure.WebKitLagPhase` with golden `webkit-lag.jsonl`; 72 of 72 runs accepted, 0 refused | MEASURED + Lean |
| Simulator leg | Run once (40018153769): touch pushes open the morph (job 1: 13 of 14; job 3: 3 of 3, then the lane was lost; job 2: no device), no counts (touch windows record no Timeline): INCONCLUSIVE for counts; see follow-up 2 | MEASURED |

The one separated cell (orig FireAnimationFrame, trusted higher) is in the idle phase, which ends at the first push. The trusted drive reaches its push 3 frames
later (13.89 vs 10.83 idle frames for `orig`), so the idle window is longer for it, and the cell is not a morph effect (INFERRED).
In the open and close phases, where the morph runs, no counter separates (every cell "overlap").

## Follow-up: a trusted wheel that scrolls into the push (run 39989441570)

The first run started at the page end, so no wheel scrolled anything. The third drive `scrollin` starts 300 px above the end,
sends trusted `page.mouse.wheel(0, 120)` until the page is within 8 px of the end (3 wheels, each moves the page 120 px, the last 60 px), waits for the
scroll to settle, then pushes down and up as the other drives do. Lean `acceptScrollIn` (`WebKitLagPhase.lean`, golden `scrollIn`) accepts a run only if the phase
rule holds, the page moved (`noScroll` otherwise) and `--morph` reached 0.9 (`noOpen` otherwise). Tags: MEASURED (run 39989441570, sha bba5ad159, tags `[ci:smoothness] [webkit-cadence] [morph-wheel]`),
CONFIRMED (source), INFERRED.

| question | answer | tag |
|---|---|---|
| Did the scroll move in every accepted run? | Yes: 36 of 36 scrollin runs accepted (and 0 of 108 runs of the run refused); `pushY - startY` = 300 in all 36; 3 scroll wheels per run, none prevented; the push wheels (12 of 30 events per cell) were prevented | MEASURED |
| Was the scroll wheel a trusted event? | 30 of 30 events per cell `isTrusted`, the 3 scroll wheels are not `defaultPrevented` (the site only prevents default at the page end or while the morph is open) | MEASURED, site code `nodes/2.DyWL8TcE.js` of the snapshot |
| Does the morph open after scrolling in? | `--morph` reached 1 in all 36 | MEASURED |
| Do open-phase counts differ, scroll-in vs synthetic? | orig only: RecalculateStyles lower in 3 of 3 jobs, Layout lower in 2 of 3 jobs (1 and 3); rewrite: none of 7 counters in any job | MEASURED |
| Do close-phase counts differ? | No separated cell in any job (7 counters x 2 arms x 3 jobs) | MEASURED |
| Idle phase | Not comparable: the scroll-in drive's idle phase holds the scrolling (26 to 32 frames per job on average (19 to 42 per run) against 10 to 13 per run for synthetic) and more RecalculateStyles and FireAnimationFrame per frame (orig: 3.7 vs 3.0 and 2.8 vs 2.0, higher in 3 of 3 jobs); the idle window of this drive is the scroll, not a rest | MEASURED + INFERRED |
| Trusted (at the end) vs synthetic | As in run 39971123168: no separated cell in open or close in any job (orig and rewrite); idle: orig FireAnimationFrame trusted higher in 3 of 3 jobs, rewrite once (job 3) | MEASURED |

Every verdict above is stated inside one job from that job's own runs (Lean `jobVerdicts`, `WebKitLag.lean`: job i depends
only on job i; `pooling_hides` shows two jobs that are each "lower" whose pool is "overlap"); no pooled 18-run verdict is
used.

| open phase, orig, scrollin vs synthetic (jobs 1 / 2 / 3) | verdicts |
|---|---|
| Layout | lower / overlap / lower |
| RecalculateStyles | lower / lower / lower |
| Paint, Composite, RenderingFrame, FireAnimationFrame, paintArea | overlap / overlap / overlap |
| rewrite, all 7 counters | overlap / overlap / overlap |

Mean open-phase Paint per frame (orig) is 19.5, 24.9, 21.1 for scrollin against 14.8, 18.5, 16.6 for synthetic (jobs 1 to 3), 27
to 35 percent higher on every job, but the per-run ranges overlap, so no verdict is stated. Mean frames of the open phase are 61 to 63 in all drives.

WebKit path exercised (CONFIRMED, `.cache/upstream/WebKit@862f17d`): a native wheel at a point inside a non-passive wheel
listener region takes the blocking path. `ScrollingTree::computeWheelProcessingSteps`
(`Source/WebCore/page/scrolling/ScrollingTree.cpp:101-136`): a point in a synchronous event-tracking region, or in a
NonPassiveWheel region (lines 119-131; that the build has `WHEEL_EVENT_REGIONS` is INFERRED), returns `SynchronousScrolling` plus
`BlockingDOMEventDispatch`; otherwise it returns `AsyncScrolling` (line 135, line 133 for a Wheel listener). The caller is at line 152. The site's wheel
handler is a non-passive capture listener on `window` installed while `#platform` is within 200 percent of the viewport (an
IntersectionObserver), and the drive starts 300 px above the end, inside that window, so the 3 scroll wheels and the 2 pushes all take the blocking
path (INFERRED from the region rule and the handler, not seen as a trace). The start of the scroll is the page's own scrolling; the
trusted wheel scrolls by `defaultWheelEventHandler` (`EventHandler.cpp:3814-3825`) when the page does not prevent it.
determineWheelEventProcessing (ScrollingTree.cpp:139-151) reaches computeWheelProcessingSteps for every wheel, whatever the scroll position, so the at-end pushes of run 39971123168 also ran it. What the scroll-in drive adds is a real page scroll of 300 px before the push, not the async-scrolling path: with the non-passive listener region both runs take SynchronousScrolling (INFERRED).

Limits: Playwright mac WebKit on a CI VM is not the phone; the Simulator leg ran later (follow-up 2);
one CI run, three jobs.

## Follow-up 2: the push during the scroll, and the Simulator leg (runs 40018133445, 40018153769)

Review finding: in run 39989441570 the scroll had settled before the push (last scroll at frame 23, push at frame 28), so no open phase had
a scroll in flight. The fourth drive `momentum` (`macmorph.mjs`) starts 300 px above the end, sends trusted scroll wheels with a 2-frame gap
until one is left, then sends the last scroll wheel, waits one frame and sends the push wheel. A scroll wheel at frame s counts as in flight for frames
s to s + 2 (Lean `flightHold`, `inFlight`, `flightFrames`, `WebKitLagPhase.lean`); a run is used only if the scroll-in rule holds, a push was seen,
at least 2 scroll wheels came before it and the push frame is in flight (`acceptMomentum`; refusals `noPush`, `fewWheels`, `settled`). Frame indices come from the page's
wheel events (`splitPush`: the scroll wheels are the events before the first one marked as the push). Tags: MEASURED (run 40018133445, sha 704cb3741, tags
`[ci:smoothness] [webkit-cadence] [morph-wheel]`, 3 jobs of 6 reps per cell), INFERRED, CONFIRMED.

| question | answer | tag |
|---|---|---|
| Did the push land with a scroll in flight? | Only by the 2-frame wheel label: the push came 2 frames after the last scroll wheel in 2 to 4 of 6 runs per cell (orig 4, 4, 3; rewrite 3, 3, 2), and 3 to 5 frames after it in the rest (refused settled); the page had stopped at maxY in all 36 runs, so no scroll was moving at the push. Mean frames from the last scroll wheel to the push: 2.3 to 2.8 (momentum) against 7.5 to 9.8 (scrollin), every job and arm | MEASURED |
| Is there scroll momentum to overlap? | No: the page was already at the end (`scrollY` = `maxY`) at the push event in 36 of 36 momentum runs and 36 of 36 scrollin runs, 1 to 5 frames after the last scroll wheel. The trusted wheel's scroll is applied at once, so the "scroll in flight" of a run is the wheel stream, not a continued scroll motion (INFERRED from `scrollY` at the push event; the Playwright wheel carries no momentum phase) | MEASURED + INFERRED |
| Open-phase frames with a scroll in flight | 0.33 to 0.67 of about 61 per run (at most 3 by the rule), so any difference in the open phase is not an effect of 60 frames of scrolling | MEASURED |
| Open phase, orig, momentum vs synthetic (jobs 1 / 2 / 3) | Layout overlap / overlap / lower; RecalculateStyles overlap / lower / lower; Paint overlap / overlap / higher; paintArea overlap / higher / higher; Composite, RenderingFrame, FireAnimationFrame overlap in all three | MEASURED |
| Open phase, rewrite, momentum vs synthetic | overlap in all 7 counters in all 3 jobs | MEASURED |
| Open phase, momentum, rewrite vs original (jobs 1 / 2 / 3) | Layout overlap / overlap / higher; Paint overlap / overlap / lower; FireAnimationFrame overlap / overlap / higher; paintArea overlap / overlap / higher; RecalculateStyles, Composite, RenderingFrame overlap | MEASURED |
| Close phase | drive vs synthetic: overlap in all 7 counters, both arms, all 3 jobs; rewrite vs original: Layout higher in job 3, rest overlap | MEASURED |
| Runs behind the verdicts | accepted runs per cell (jobs 1 / 2 / 3): orig 4 / 4 / 3, rewrite 3 / 3 / 2 of 6; verdicts need separated per-run ranges, so with 2 to 4 runs a "overlap" is weaker than in the other drives | MEASURED |

The Paint and paintArea "higher" cells for orig lie in the same direction as the scrollin drive's non-significant 27 to 35 percent (above) and appear in jobs 2 and 3 only; the Layout and RecalculateStyles
"lower" cells repeat the scrollin result for orig. None of the cells is stated for the rewrite arm.

**Labels (review item 2).** `macreport.mjs` named every job "job 1" because each matrix job reports its own file. A file now carries `jobIndex` (`mac-cli.mjs run --job-index N` or `FW_MATRIX_JOB`); the label rule is Lean `jobLabel`
(named index, else `this job` for one file, else the position); `report --files a,b,c --jobs 1,2,3` labels downloaded files. The workflow passes no index (`smoothness.yml` is outside this task), so the in-job table
says `this job`, and the table above was built offline with `--jobs 1,2,3`.

**Simulator leg (run 40018153769, sha eca3c0e60, tags `[ci:smoothness] [webkit-cadence] [earn-bound] [sim-only]`, the PushServer touch of `sim-touch-reliable`): INCONCLUSIVE for counts.** A touch window records no Timeline
(Lean `timelinePlan`), so this leg can show only whether the real touch opens the morph and how many frames the page saw, not record counts.

| job | result | tag |
|---|---|---|
| 1 | 14 touch end windows, 14 `ok`; `--morph` reached 1 in 13 of 14 (the 14th, `bound` rep 2, recorded 0 frames); frames per window 0 to 165, median 104; 4 to 50 touch moves | MEASURED |
| 2 | failed before any window: `simctl list devices` timed out (host load average 570) | MEASURED (artifact `smoothness-webkit-sim-2`, no `sim.json`) |
| 3 | 3 touch windows `ok`, `--morph` reached 1 in all 3, then `pageLost`; the touch lane went off for the rest of the job (host load average 1000) | MEASURED |

Hero windows and the touch swipe are not scroll-in-flight windows (the touch window starts at the page end), so the Simulator leg does not test the overlap question; it shows that the real-touch push opens the morph on CI. The windows are starved
(median 104 frames in the push window against about 480 for the same time at 60 Hz). Limits: CI macOS and CI Simulator are not the phone; Playwright WebKit has no momentum phase.

## Follow-up 3: no momentum phase on this lane, the site holds the page, and the pull drive (run 40032804511)

Review finding on follow-up 2: the push met a page already stopped at `maxY`, so "in flight" was only a label. Two questions: does a Playwright WebKit trusted wheel have a momentum phase at all, and can a scroll move during the open phase. Run 40032804511 (sha 8687ac51a, tags `[ci:smoothness] [webkit-cadence] [morph-wheel]`, mac only, 3 jobs of 6 reps per cell).

| question | answer | tag |
|---|---|---|
| Does a Playwright WebKit trusted wheel have a momentum phase? | No. Playwright 1.64.1 `RawMouseImpl.wheel` (`playwright-core/lib/coreBundle.js` lines 47746 to 47758; tag v1.64.1 = cfe490d94) sends `Page.updateScrollingState`, waits one rAF, then `Input.dispatchWheelEvent` with x, y, deltaX, deltaY and modifiers only, and throws on mobile. The WebKit patch (`browser_patches/webkit/patches/bootstrap.diff` @v1.64.1 lines 13937 to 13962, new file `Source/WebKit/UIProcess/WebPageInspectorInputAgent.cpp`) builds the `WebWheelEvent` with the six-argument constructor (`Source/WebKit/Shared/WebWheelEvent.h:63` @56453fdfe0b0, the base in `UPSTREAM_CONFIG.sh`), whose `m_phase` and `m_momentumPhase` start as `Phase::None` (`WebWheelEvent.h:102-103`; identical at the pinned 862f17d), then calls `handleNativeWheelEvent` (`WebPageProxy.cpp:4805`). The only synthetic momentum code runs on `momentumPhase() == Phase::Began` (`WebPageProxy.cpp:4988` and `:5012`), which never happens. So momentum is not reproducible on this lane; the phone's momentum stays the phone's | CONFIRMED |
| Can a scroll move during the open phase? | No, by the site's own code. While the morph is open every wheel is `preventDefault`ed (`snapshot/site/_app/immutable/nodes/2.DyWL8TcE.js`: handler `A`, `k(dy) = C() or (dy > 0 and O())`) and the scroll handler `L` puts `scrollY` back to the position taken at the push with `scrollTo({top: s, behavior: 'instant'})`. A push opens the morph only when `.start-selling-platform` is at least 0.45 of the viewport tall and ends within 8 px below it (`O()`), which is `scrollY` at or above `maxY - 7` (local debug check: `maxY` 5102, `O()` true from 5095, false at 5094). So `scrollY` cannot change monotonically in the open phase for any drive, and a push far from the end does not open the morph | CONFIRMED (source) + MEASURED (local debug, not a result) |
| What does the new drive `pull` do? | It scrolls to 4 px above the end (`maxY - 4`, inside the 7 px window), waits until the page stops, sends the trusted push (the morph opens, the wheel is prevented), then from the page calls `scrollBy({top: -2, behavior: 'instant'})` once per rAF frame until the trusted up push. The site puts the page back after every scroll event, so each open-phase frame carries a real scroll and a scroll event (scroll style, layout and event work) that a push into a stopped page does not. A plain `scrollBy(0, -2)` left `scrollY` unchanged in a local debug run (cause not isolated); `behavior: 'instant'` moved it every frame | INFERRED (stand-in for a moving scroll) |
| Rule (Lean `acceptPull`, `offFrames`, `pullFrames`) | A run is used only if the scroll-in rule holds, a push was seen, the push event reported `scrollY` below `maxY` (else `atEnd`), and every open-phase frame has a frame within 2 frames after it (`pullLook`) in which the position read right after the pull is not the lock position (else `stalled`). The reading is taken in the page between the pull and the site's restore, so it shows that the pull took effect, not that a frame was drawn at the pulled position | Lean + golden (16 pull lines) |
| Did the push land on a moving scroll? | The push arrived at `scrollY` 5098 against `maxY` 5102 in 36 of 36 pull runs (0 `atEnd`), and 36 of 36 runs were accepted (0 `stalled`, 0 refused in any drive). Every open-phase frame was off the lock (61.2 to 63.7 frames per run, equal to the open frames); scroll events in the open phase 60.2 to 62.7 per run | MEASURED |
| Open phase, pull vs synthetic (jobs 1 / 2 / 3, both arms) | Layout higher / higher / higher (3.5 to 4.0 per frame against 1.5 to 1.8); RecalculateStyles higher in all 3 (4.1 to 4.3 against 2.2 to 2.3); FireAnimationFrame higher in all 3 (3.1 to 3.3 against 1.3); paintArea higher in all 3; Paint, Composite, RenderingFrame overlap | MEASURED |
| Open phase, pull, rewrite vs original (jobs 1 / 2 / 3) | Layout, Paint, Composite, RenderingFrame, FireAnimationFrame, paintArea overlap in all 3; RecalculateStyles overlap / lower / overlap | MEASURED |
| Close phase, pull | pull vs synthetic overlap in all 7 counters for orig, and for rewrite except FireAnimationFrame higher in job 2; rewrite vs original: Paint lower in job 1, rest overlap | MEASURED |
| Idle phase | unchanged by the drive (the pull starts at the push); the idle window of `pull` is 17.5 to 31.2 frames, so idle cells of that drive are not compared with the other drives | MEASURED |

What this changes: the open phase now runs with scroll work in every frame (about twice the Layout, RecalculateStyles and FireAnimationFrame records of a push into a stopped page), and the rewrite's open-phase counts still overlap the original's, so the open-phase result of the earlier follow-ups is not an artefact of a stopped page (Layout, Paint, Composite, RenderingFrame, FireAnimationFrame, paintArea overlap in all 3 jobs, RecalculateStyles lower in one). It does not test the phone's momentum, which is not reproducible here, and it stays an INFERRED stand-in for a moving scroll. The Simulator leg stays INCONCLUSIVE (touch windows record no Timeline). CI macOS is not the phone.

## What was run (first run, 39971123168)

| item | value |
|---|---|
| CI run | 39971123168, workflow smoothness, branch ci/morph-real-wheel, sha 9cdcefc41, head commit tags `[ci:smoothness] [webkit-cadence] [morph-wheel]` |
| jobs | webkit-mac 1, 2, 3 (separate macos-26 runners, Apple M1 (Virtual), macOS 26.6.2, Playwright WebKit 27.2) |
| per job | 6 reps x 2 arms (orig snapshot, rewrite default build) x 2 drives (trusted, synthetic) = 24 runs, each in a fresh context |
| accepted | 24, 24, 24 of 24 (config hash of the rewrite arm ede2c7641aacf2d2 in all three) |
| page | 390 x 844, dpr 2, touch on, pinned clock, page at its end before the schedule |
| schedule | rAF loop marks every frame; push down after 10 frames, push up 60 frames later, 60 frames after that |
| trusted drive | `page.mouse.move` to the centre, then `page.mouse.wheel(0, 120)` and `(0, -120)` |
| synthetic drive | in-page `WheelEvent` on `document.body`, the probe's push |
| synthetic and trusted on the same SHA | yes: both drives of one arm run in the same job, order rotated per rep |

Not the phone: Playwright mac WebKit on a CI VM is neither the iPhone nor the Simulator (accepted limit).

## Per-frame counts (mean over 18 runs per cell, three jobs; MEASURED, run 39971123168)

| phase | arm | drive | frames | Layout | RecalcStyles | Paint | Composite | FireAnimFrame | paintArea |
|---|---|---|---|---|---|---|---|---|---|
| idle | orig | trusted | 13.89 | 3.16 | 3.02 | 6.23 | 1 | 2.07 | 26192 |
| idle | orig | synthetic | 10.83 | 3.26 | 3.03 | 6.62 | 1 | 2 | 28823 |
| idle | rewrite | trusted | 11.94 | 2.08 | 2.69 | 11.20 | 1 | 2.25 | 58982 |
| idle | rewrite | synthetic | 10.06 | 2.12 | 2.77 | 11.18 | 1 | 2.11 | 60972 |
| open | orig | trusted | 62 | 1.40 | 2.22 | 15.37 | 1 | 1.25 | 205821 |
| open | orig | synthetic | 61.17 | 1.50 | 2.29 | 16.83 | 1 | 1.31 | 236351 |
| open | rewrite | trusted | 62 | 1.36 | 2.02 | 17.14 | 1 | 1.27 | 298001 |
| open | rewrite | synthetic | 60.61 | 1.38 | 2.04 | 18.21 | 1 | 1.26 | 302837 |
| close | orig | trusted | 61.11 | 1.64 | 2.00 | 20.71 | 0.98 | 1.22 | 318622 |
| close | orig | synthetic | 61.22 | 1.66 | 2.01 | 21.95 | 0.98 | 1.22 | 322400 |
| close | rewrite | trusted | 61.39 | 1.63 | 2.02 | 18.06 | 0.98 | 1.18 | 276645 |
| close | rewrite | synthetic | 61.33 | 1.69 | 2.03 | 18.65 | 0.98 | 1.19 | 281598 |

RenderingFrame is 0 in every cell. Verdicts use the Lean-checked `verdict` of `lag/reduce.mjs` over the per-run values: a
difference is stated only when the ranges of all runs are separated.

| comparison | cells with a separated difference |
|---|---|
| synthetic vs trusted, open and close, both arms | none of 28 |
| synthetic vs trusted, idle | orig FireAnimationFrame (trusted higher); 1 of 14 |
| original vs rewrite, idle | Layout (rewrite lower), Paint (rewrite higher), both drives |
| original vs rewrite, open and close | none of 56 |

Run-to-run class of the phase totals (`classify`, tolerance of the totals): RenderingFrame is deterministic in every cell and
Composite is stable in 9 of 12 cells (FireAnimationFrame in 2 more, both orig synthetic); the other counters are quarantined because phase totals scale with the number of
frames in the phase, which varies by a few frames per run (the cause is INFERRED). The per-run tables are in the artifacts
`smoothness-webkit-mac-1..3` of run 39971123168 (`mac-morph.json`, `mac-morph.md`, `mac-morph-report.json`).

## Why a trusted wheel is a different path (CONFIRMED, WebKit 862f17d, read-only clone)

| step | trusted | synthetic |
|---|---|---|
| routing | `ScrollingTree::computeWheelProcessingSteps` (`Source/WebCore/page/scrolling/ScrollingTree.cpp:101-136`) chooses synchronous or asynchronous scrolling from the wheel-listener regions | none |
| dispatch | `EventHandler::handleWheelEvent` (`EventHandler.cpp:3536-3636`), `dispatchWheelEvent` at 3624, cancelable only when a blocking listener exists | `dispatchEvent` from script |
| default action | `defaultWheelEventHandler` (`EventHandler.cpp:3814-3825`): `isUserEvent` is true when a platform event exists | no platform event: `scrollViaNonPlatformEvent` (`EventHandler.cpp:3679`, `3731-3737`) |

`Node.cpp` is not in the sparse clone, so the claim that the script event skips latching and the delta filter is INFERRED.
Playwright 1.64.1 `Mouse.wheel` (`lib/coreBundle.js:47745-47757`) sends `Page.updateScrollingState`, waits one rAF, then
`Input.dispatchWheelEvent` on the page-proxy session (UI process); it throws on mobile WebKit, so the context is not mobile.
In the first run `scroll moved` was 0 in all runs; the wheel handler alone drove the morph.

## Method (what is Lean, what is glue)

| part | where | status |
|---|---|---|
| phase of a frame from the push times, refusal rule (idle >= 5, open >= 30, close >= 30 frames), theorems and golden | `lean/Fw/Measure/WebKitLagPhase.lean`, `packages/contracts/golden/measure/webkit-lag.jsonl` | Lean; twin `lag/phase.mjs` replays the golden in `test/lag-phase.test.mjs` |
| verdict, ratio, class | `lag/reduce.mjs`, `reduce.mjs` | existing Lean-checked twins |
| geometry index of a frame, scroll-in acceptance (`noScroll`, `noOpen`), minimum open morph 900 thousandths | `WebKitLagPhase.lean` (`geometryIndex`, `acceptScrollIn`), golden `geometryIndex`, `scrollIn`; twins in `lag/phase.mjs`, replayed in `test/lag-morph-followups.test.mjs` | Lean |
| one verdict per job, tally, no pooling | `WebKitLag.lean` (`jobVerdicts`, `tally`, `jobVerdicts_congr`, `pooled_lower`, `pooling_hides`), golden `jobVerdicts`; twin in `lag/reduce.mjs` | Lean |
| per-run means and table layout | `lag/macreport.mjs` | TS stand-in (arithmetic means, formatting) |
| `morphMilli` (largest `--morph` at the labelled frames, times 1000, rounded) | `lag/phase.mjs` | TS stand-in |
| Playwright session, rAF loop, wheel listener, scroll-in wheel loop | `lag/macmorph.mjs`, `lag/mac-cli.mjs` | glue |
| momentum drive, `inFlight`, `flightFrames`, `splitPush`, `acceptMomentum`, `jobLabel` | `WebKitLagPhase.lean`, golden `momentum*`, `flight`, `splitPush`, `jobLabel`; twins in `lag/macreport.mjs`, replayed in `test/lag-mac-morph.test.mjs` | Lean |
| pull drive: `offFrames`, `pullFrames`, `acceptPull` with refusals `atEnd`, `stalled` | `WebKitLagPhase.lean`, golden `pullConst`, `pull`; twins in `lag/macreport.mjs`, replayed in `test/lag-mac-morph.test.mjs` | Lean |
| pull page script (`scrollBy` per rAF, position reading), drive orchestration, report tables | `lag/macmorph.mjs`, `lag/macreport.mjs` | TS stand-in / glue |
| Simulator leg | PushServer touch, existing `webkit-sim` job | run 40018153769 |
