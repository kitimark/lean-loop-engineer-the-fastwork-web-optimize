---
id: 2026-10-2x-touch-lock-page-end
kind: note
title: "The page-end lock fight: a Lean model of scrollY reversals under the site's restore, and what the CI Simulator run showed"
status: review
created: 2026-10-24
topics: [webkit, simulator, touch, scroll, morph, lock, measure, lean]
---

# The page-end lock fight

Task `touch-lock-page-end`. WebKit cites `@862f17d`. The CI Simulator is not the phone.

## Answer

- **No reversal count was delivered (MEASURED).** Run `40060600880` (the 2nd and last allowed dispatch) kept 3 windows, one per
  arm, and all three were refused `noOpen`: the morph never opened, so the open phase was empty and Lean's `refusal` rejects it
  instead of counting zero fights. Run `40059669688` (1st dispatch) failed before any window: `nearEndJs` was never invoked
  (an extra `)` made the arrow function itself the expression), fixed in `3ec3348ab` and covered by a test that calls it.
- **Cause of the refusals (INFERRED from the run's rows, then CONFIRMED by one local debug run).** The 1800 pt/s flick in run
  `40060600880` travelled 250 px to the end and into rubber-band in a few touch samples (the event series jumps from y 5051
  to 5327 in one scroll event; `maxY` 5267 was measured after the toolbar came back). The site opens the morph only from a
  touchmove or wheel while the platform's bottom is within 8 px of the viewport bottom
  (`2.DyWL8TcE.js`, handler `k(delta) = C() || (delta > 0 && O())`), and none of the 14 to 17 touchmoves per window saw that.
  A local debug run (not a result, one window per arm, no numbers kept) with `{dragPt 500, velocity 500, holdMs 0}` opened the
  morph in all three arms and showed the site's restore scrolls, so the default pan is now `PAN = {500, 500, 0}`
  (`packages/measure-webkit/src/touchlock.mjs`, flags `--drag-pt --velocity --hold-ms`). This is not yet measured on CI.
- **Second blocker.** The walk's lane ended after the third window: the lock window's driver finished at 209 s (bound 125 s;
  the inspector probe logged `page missing` in the same window) and `laneAfter` closed the touch lane. That is the load
  stall already studied in `2026-10-2x-sim-touch-reliable`, not a model result.
- **Look class of the candidate (INFERRED, no run data).** Lean `look` says "same look" only if neither arm shows displaced
  open frames. The faithful site restores scrollY by design, so displaced frames are expected in `base`; the candidate (CSS
  `overflow:hidden; overscroll-behavior:none; touch-action:none` on `html` while the morph is open) removes the rubber band and
  the native pan, which changes what the finger does, so it goes to the look-change class for the user's review. The local
  debug run agreed in direction (`lock` showed fewer restores) and is the only evidence.

## Model

`lean/Fw/Measure/TouchLock.lean`, golden `packages/contracts/golden/measure/touch-lock.jsonl` (22 rows, generated with
`lake env lean --run scripts/TouchLockGolden.lean`, checked by `lean/scripts/check.sh`), JS twin `packages/measure-webkit/src/touchlock.mjs`
replaying the golden in `test/touchlock.test.mjs`.

- A sample is `(scrollY in tenths of a CSS px, morph open)`. The open phase is the first stretch of open samples. The lock is
  its first position `s` (the site stores `s = scrollY` when it opens).
- `reversals` counts direction changes of the de-duplicated open-phase positions; `fights` counts the reversals whose end
  position is `s` (the restore put it there); `displaced` counts open samples off `s`; `restores` counts scroll events off `s`.
- A run is `jitter` iff `frameFights > 0` (`jitter_iff`). A run with no open frames or fewer than 10 is refused, not counted
  (`refusal_noOpen`, `refusal_tooShort`, `refusal_none_iff`). `fights_le_reversals`, `fights_zero_of_steady`,
  `reversals_zero_of_steady`, `displaced_zero_iff`.
- Arms compare per run: `cmp` is `lower`/`higher` only when the two ranges are separated, else `overlap`
  (`cmp_lower`, `cmp_higher`, `cmp_overlap`, `cmp_empty_*`). `look` is `same` iff both arms have zero displaced frames
  (`look_same`, `look_change_faith`, `look_change_cand`).

## Engine facts (WebKit@862f17d, `.cache/upstream`)

- **Script scrollTo does not stop a user deceleration (CONFIRMED, source).**
  `RemoteScrollingCoordinatorProxy.cpp:172-192` passes `InterruptScrollAnimation::No` for a script position update;
  `ScrollingTreeScrollingNode.cpp:432-433` stops only `Programmatic` animations for non-implicit requests;
  `ScrollingTreeScrollingNodeDelegateIOS.mm:494-510` stops a user deceleration only for `AnimatedScrollType::User`.
- **What UIKit does with the final `setContentOffset:` is UNKNOWN** (`WKWebViewIOS.mm:1515-1550` calls it, UIKit is closed);
  only a run with open frames can tell.
- **A pan that began before the open stays unpreventable (CONFIRMED, source).** `WKContentViewInteraction.mm:4239-4245` sets
  `_touchEventsCanPreventNativeGestures = NO` at pan start; `:2257-2268` then sends unpreventable touch events; `:2270-2271`
  resets it when all fingers lift. The site's later `preventDefault` cannot stop that pan, so the restore fights it.
- **The first touchmove of a gesture waits for the main thread (CONFIRMED, source, Q2 not modelled).**
  `WebPageProxy.cpp:5199-5202, 5252-5253, 5288-5292`.

## Deviations and limits

- The start is 250 px above the end (`START_GAP_PX`), not more than 2 viewports: one XCUITest press moves at most 0.6 of the
  window height.
- The sampled `scrollY` is the content process's value, not the drawn offset; a screen-recording count of drawn reversals is a
  follow-up. Q2 (touch deferral) rows are kept raw in `q2` and have no Lean model.
- The candidate is an injected shim with one frame of latency (`LOCK_CSS`), not a site change.
- One job only: the across-job verdict belongs to `sim-touch-verdict-jobs`.
- Dispatches: 2 of 2 used (runs `40059669688`, `40060600880`).

## TS stand-ins (temporary)

`touchlock-run.mjs`, `touchlock-page.mjs`, `touchlock-cli.mjs` (I/O and page glue, no decision logic) and the `summarize` and
`markdown` formatting in `touchlock.mjs` (the decisions in them are the Lean-golden `reduce`, `refusal`, `cmp`, `look`).

## Next

One more dispatch with the new default pan (`[ci:smoothness] [webkit-cadence] [sim-only] [touch-lock]` in the head commit
message) would give the counts; results of run `40060600880` are in `results/touch-lock-page-end/run-40060600880/`.
