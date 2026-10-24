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

- **Round 2, run `40065281372` (3rd and last dispatch, MEASURED): one arm counted, the lane ended in the 2nd window.** The slow pan
  `{500 pt, 500 pt/s, hold 0}` opened the morph on the first try. Windows in the run's order:

| window | arm | outcome | open frames | reversals | fights | displaced | restores |
|---|---|---|---|---|---|---|---|
| 1 | base (faithful rewrite) | open, accepted (72 moves, 167 frames) | 73 | 8 | 0 | 72 | 72 |
| 2 | lock (candidate) | refused: push failed, `pageLost` (page silent 89 s, 0 moves) | none | none | none | none | none |
| 3 | orig | never started (touch lane ended) | none | none | none | none | none |

  Table in `results/touch-lock-page-end/run-40065281372/touch-lock.md`. Reading the base window: the first open sample is the
  rubber-band overscroll (scrollY 5346.0), after which scrollY alternates 5236.0 and 5227.0 (the end) four times. So 8 direction
  reversals while the morph was open, but Lean counts a fight only when a reversal ends at the lock position (`s` = 5346.0, the
  overscroll value), so `frameFights` is 0 and the run is not jitter by the Lean verdict. The oscillation itself is about 0.9 CSS
  px, taken from the content process (`scrollY`), not the drawn offset. One window per arm is not a verdict: `lockVsBase` is `overlap`
  by `cmp` (an empty candidate list).
- **Why the lane ended (MEASURED, then CONFIRMED in the log).** The order fix worked: base ran before lock and orig, so the
  faithful window survived the stall. The lock window's page went silent (`pageLost`, done at 89 s), the walk restarted the push
  server once (`afterWindow`), and the restart failed: `xcodebuild: error: Existing file at -resultBundlePath .../serve.xcresult`
  (driver exit 64), because the restarted server reused the first server's result bundle name. Fix after the run, not measured:
  `startServer` takes a `tag`, the restart passes `serve-r<n>` (`touch-push.mjs`, `touchlock-run.mjs`). The page stall (second page load after a push) is the same as in run `40060600880` and is not cured.
- **Candidate look class (INFERRED, no candidate window delivered): look change**, as decided for the review: the CSS lock removes
  the rubber band and the native pan. The only displaced-frame evidence is in `base` (72 displaced open frames), so Lean `look`
  is `change` for any pair that includes it. Goes to the user's visual review.
- **Earlier rounds.**
  Run history: no reversal count in round 1 (MEASURED). Run `40060600880` (the 2nd dispatch) kept 3 windows, one per
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
  (`packages/measure-webkit/src/touchlock.mjs`, flags `--drag-pt --velocity --hold-ms`). Run `40065281372` then opened the morph on CI with this pan (base arm).
- **Second blocker.** Run 40060600880 (round 1): its lane ended after the third window: the lock window's driver finished at 209 s (bound 125 s;
  the inspector probe logged `page missing` in the same window) and `laneAfter` closed the touch lane. That is the load
  stall already studied in `2026-10-2x-sim-touch-reliable`, not a model result.

## Model

`lean/Fw/Measure/TouchLock.lean`, golden `packages/contracts/golden/measure/touch-lock.jsonl` (31 rows, generated with
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

- Round 2 (stall-proof order): `repOrder` runs `base`, `lock`, then `orig` on even reps and `lock`, `base`, `orig` on odd reps, so
  the original always runs last in a rep and a stall can only cut the windows after it (`repOrder_orig_last`, `repOrder_once`). `afterWindow` restarts a stalled push server up to
  `maxRestarts = 2` times before the lane ends (`afterWindow_keep`, `afterWindow_restart`, `afterWindow_stop`). Golden ops
  `order` and `lane`, replayed in the twin test.

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
- Dispatches: 3 of 3 used (runs `40059669688`, `40060600880`, `40065281372`); no more are allowed for this task.

## TS stand-ins (temporary)

`touchlock-run.mjs`, `touchlock-page.mjs`, `touchlock-cli.mjs` (I/O and page glue, no decision logic) and the `summarize` and
`markdown` formatting in `touchlock.mjs` (the decisions in them are the Lean-golden `reduce`, `refusal`, `cmp`, `look`).

## Next

A later task (not this one) can re-run the lane with the `serve-r<n>` restart fix and the page-stall guard to get the lock and
orig windows; its across-job verdict belongs to `sim-touch-verdict-jobs`.
