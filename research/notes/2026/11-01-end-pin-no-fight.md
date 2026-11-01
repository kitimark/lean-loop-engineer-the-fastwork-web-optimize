---
id: 2026-11-01-end-pin-no-fight
kind: note
title: "A page-end pin that does not fight a live pan: WebKit source, a Lean zero-fight proof, look class L, and the CI Simulator windows"
status: review
created: 2026-11-01
topics: [webkit, ios, scroll, morph, pin, touch, lean, measure]
---

# A page-end pin that does not fight a live pan

Task `end-pin-no-fight`. WebKit cites `@862f17d`. The CI Simulator is not the phone; phone feel is not measured here.

## Answer

RESULTS_PLACEHOLDER

## What a script scrollTo does on iOS (CONFIRMED, WebKit 862f17d)

- A page script `scrollTo` reaches the UI process as a `PositionUpdate` request, and the request is sent with `InterruptScrollAnimation::No`
  (`Source/WebKit/UIProcess/RemoteLayerTree/RemoteScrollingCoordinatorProxy.cpp:186`); only `CancelAnimatedScroll` sends `Yes` (`:190`).
- `PageClientImpl::requestScroll` hands the flag on (`Source/WebKit/UIProcess/ios/PageClientImplIOS.mm:136-138`).
- `_scrollToContentScrollPosition:` bounds the target to the valid range (`Source/WebKit/UIProcess/API/ios/WKWebViewIOS.mm:1533`), stops the scroll view
  only when `interruptAnimation` is set (`:1535-1536`), and otherwise calls plain `[_scrollView setContentOffset:]` when the target differs (`:1541-1544`).
- So the script write does not cancel a user pan or its deceleration in WebKit's code. What UIKit does with `setContentOffset:` while the user's finger
  drives the scroll view is UNKNOWN (not in WebKit source); the earlier lane windows (`10-2x-touch-lock-page-end.md`) show the page ends up displaced and
  fighting, which is consistent with the write moving the page for a frame and the pan taking it back.
- No `scrollend` fires for a native iOS root pan or its momentum (INFERRED from the same files: the UI-process scroll view is UIKit's, and the web process is told by scroll position updates only). The only end signals a page has are touch events and a quiet time without scroll events.

## The design and the Lean proof (`lean/Fw/Parts/EndPin.lean`)

- **Policy.** The pin writes the target `s` only when `mayWrite`: no finger down, `quietMs = 120` ms without a scroll or touch event, the page is off the target, and the write does not reverse the last distinct motion (`reverses a b s` is `(b-a)*(s-b) < 0`).
  The page's own positions are the user's pan and its momentum; the pin never writes on a scroll frame, only from a timer once the quiet time is over.
- **Theorems (PROVED).** One per branch: `no_write_touching`, `no_write_live`, `no_write_settled`, `no_write_reversal`, `write_of_clear`, `write_is_target`.
  The invariant `play_no_turn` (with `tailTurns`) gives the main result `pin_fights_zero`: under the TouchLock model (`Fw.Measure.TouchLock.fights`) the pin has 0 fights for any event list whose user positions avoid the target.
  `due_write` and `observe_write` tie the timer driver (`due`, `observe`) to the same write rule.
- **Limits of the proof.** A user position that turns exactly on `s` (a spring-back that lands on the target and then leaves) still counts as a fight in the metric, so the theorem assumes `∀ y ∈ movesOf es, y ≠ s`. That a deceleration emits a scroll event at least every 120 ms is INFERRED from frame cadence.
- **Look class L (PROVED against the faithful pin).** The faithful pin fights twice on a spring out and back (`faith_fights_witness`, 2 fights), the end pin has 0 (`decline_fights_zero`) but rests off the target after a pan whose write would reverse the motion (`decline_rests_off_target`); the faithful pin ends on the target (`faith_ends_on_target`). The page may rest off target, or return after the quiet time instead of at once, so the look changes and the variant goes to the user's look review. No preset change.
- **A window with no open scrollTo call has no stored lock, so its fights and displaced are 0 by definition** (`openCalls_zero_iff`, `displaced_zero_of_unrestored`). The lane therefore reports `openCalls` per run and how many runs never wrote.

## Code

- `apps/site/src/parts/morph.tween/end-pin.logic.ts` (TS twin, each function names its Lean twin), `driver.ts` (`restPin`, timer from `due`), `index.tsx` (`fingerWatch`), variant `end-pin` in `part.json` (`visClass: L`).
- Golden rows `pin*` in `packages/contracts/golden/measure/touch-lock.jsonl`, checked by `apps/site/src/parts/morph.tween/end-pin.golden.test.ts` (rows and driver glue with a fake clock) and by `packages/measure-webkit/test/touchlock.test.mjs` (fights and reversals over the Lean frames).
- Lane: arm `pin` (`?fw=morph.tween:end-pin`) added to `packages/measure-webkit/src/touchlock*.mjs`; windows per rep run in the Lean `repOrder` (base, lock, pin, orig on even reps; pin, lock, base, orig on odd reps).
