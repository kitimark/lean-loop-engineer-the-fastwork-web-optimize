# The end-of-page morph under a trusted wheel: does the synthetic WheelEvent change the lag counts?

Question: the WebKit lag probe pushes the morph with a synthetic `WheelEvent` on `document.body`. Does a trusted wheel (a
native wheel through the UI process) give different WebKit record counts per frame? Tags: MEASURED (a CI run id named
here), CONFIRMED (source cited), INFERRED (reasoned, not seen).

## Answer

| question | answer | tag |
|---|---|---|
| Does the page see a trusted wheel? | Yes: 72 of 72 trusted-drive events (2 pushes x 36 runs) had `isTrusted` true, 0 of 72 synthetic; all 144 were cancelable and the site called `preventDefault` on all 144 | MEASURED, run 39971123168 |
| Does the trusted push open the morph? | Yes: `--morph` reached 1 and returned to 0 in all 36 trusted runs, as in the synthetic runs | MEASURED, run 39971123168 |
| Do per-frame counts differ, trusted vs synthetic? | No separated difference in 41 of the 42 cells (2 arms x 3 phases x 7 counters); the one cell with a separation is in the idle phase (see below) | MEASURED, run 39971123168 |
| Phase rule | Lean `Fw.Measure.WebKitLagPhase` with golden `webkit-lag.jsonl`; 72 of 72 runs accepted, 0 refused | MEASURED + Lean |
| Simulator leg | Not done: sim-touch-reliable (worktree-wf_b60a7b2e) is not on main | follow-up |

The one separated cell (orig FireAnimationFrame, trusted higher) is in the idle phase, which ends at the first push. The trusted drive reaches its push 3 frames
later (13.89 vs 10.83 idle frames for `orig`), so the idle window is longer for it, and the cell is not a morph effect (INFERRED).
In the open and close phases, where the morph runs, no counter separates (every cell "overlap").

## What was run

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
In this run the page was already at its end, so neither drive scrolled (`scroll moved` 0 in all runs); the morph is
driven by the wheel handler only.

## Method (what is Lean, what is glue)

| part | where | status |
|---|---|---|
| phase of a frame from the push times, refusal rule (idle >= 5, open >= 30, close >= 30 frames), theorems and golden | `lean/Fw/Measure/WebKitLagPhase.lean`, `packages/contracts/golden/measure/webkit-lag.jsonl` | Lean; twin `lag/phase.mjs` replays the golden in `test/lag-phase.test.mjs` |
| verdict, ratio, class | `lag/reduce.mjs`, `reduce.mjs` | existing Lean-checked twins |
| per-run means and table layout | `lag/macreport.mjs` | TS stand-in (arithmetic means, formatting) |
| Playwright session, rAF loop, wheel listener | `lag/macmorph.mjs`, `lag/mac-cli.mjs` | glue |
| Simulator leg | PushServer touch | follow-up, not on main |
