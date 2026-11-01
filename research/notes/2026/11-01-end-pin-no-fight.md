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

- **No design holds the page during a live pan with the same look, but a deferred pin avoids the fight (PROVED in Lean, MEASURED once on the CI Simulator, class L).**
  A script write cannot cancel the user's pan in WebKit's code (below), so the only fight-free pin writes after the gesture and its momentum; the end pin does that, and Lean proves 0 fights for it (`pin_fights_zero`).
  This is not a negative finding: the task's premise ("a design may exist") holds. Its price is a look change, class L, for the user's review.
- **Lane result (MEASURED, CI Simulator, 3 dispatches, 6 jobs started, 4 gave results).** Dispatch 1 run `41267567864` (`0ce0723a6`): all 6 pin windows of job 1 were refused `config` (the window reset the URL to `/` and dropped `?fw=`; fixed by `armPath`, 5faf65ca7), job 2 had a pageLost at its first windows.
  Dispatch 2 run `41270567124` (`5faf65ca7`): job 1 lost its artifact (the job ran past 45 min, no log), job 2 gave the first pin windows. Dispatch 3 run `41275699141` (`d63c5f9e9`): job 1 stalled at its first window (`swipeLate`, then the upload step timed out after 2 min, no artifact), job 2 gave 1 more accepted pin window.
  Pooled over the 4 result files (`results/end-pin-no-fight/pooled/touch-lock.md`, the lane's own `summarize`; one entry per accepted window; the lock is the site's stored value, so a window with no open call has none):

| arm | windows | refused | accepted | fights per run | reversals per run | open scrollTo calls per run | runs with no open call |
|---|---|---|---|---|---|---|---|
| orig | 12 | noOpen 1 | 11 | `2 0 1 1 1 1 1 1 2 4 1` | `3 0 2 1 2 2 1 3 3 7 2` | `23 1 26 32 1 15 12 13 24 53 20` | 0 |
| base | 13 | tooShort 1, noOpen 1 | 11 | `1 1 1 1 1 1 2 2 1 5 2` | `1 1 1 1 1 1 3 3 2 10 4` | `16 5 2 25 3 15 9 3 2 94 38` | 0 |
| lock | 13 (1 pageLost) | tooShort 2, noOpen 1 | 9 | `1 1 3 1 3 2 2 1 2` | `1 1 6 1 6 3 3 1 4` | `11 2 8 2 60 15 4 2 101` | 0 |
| pin | 14 (6 config, 2 pageLost) | tooShort 1, noOpen 1 | 4 | `0 0 0 0` | `0 1 1 1` | `0 0 0 0` | 4 |

  By `cmp`: pin vs base fights `lower`, restores `lower`, event fights `lower`; pin vs orig fights `overlap`; lock vs base `overlap`; base vs orig `overlap`. The 6 config windows are a harness bug fixed before the later dispatches, not pin evidence; the 4 accepted pin windows come from two separate CI jobs (run `41270567124` job 2: 3, run `41275699141` job 2: 1).
- **The pin's 0 is by definition here, not a held page (MEASURED).** In all 4 accepted pin windows the pin made 0 `scrollTo` calls (so `lockOf` is none, fights and displaced are 0 by `openCalls_zero_iff` and `displaced_zero_of_unrestored`). The page left the end by 89 to 132 px (peak over `maxY10`, 890 1320 1250 1020 tenths) and came back by itself: the final position equals `maxY10` in 4 of 4 windows (52270 52270 51910 51910), with no pin write.
  Base ends 0 to 31.0 px above `maxY10` in its accepted windows (final minus `maxY10`, tenths, windows whose `maxY10` is 51910 or 52270: 80 20 310 260 310 60 10 -20 0 0); the original ends 0 to 31.0 px above it too (100 0 0 310 0 0 260 10 260 10 0). So the page rests exactly on the end with the pin and up to 31 px past it with the faithful pin. INFERRED mechanism: the faithful pin's target is a stored value above the reachable end; the end pin's rule `reverses` declines that write (the spring back is moving down, the write would go up), so the native rubber band decides the rest.
- **What this does not show.** The pin was never seen to write on the Simulator (0 calls in 4 of 4 windows), so the write branch is covered by Lean and the TS golden tests only; 4 accepted windows is below the usual 3 jobs of evidence for a count claim; phone feel (scroll fight, the 120 ms return) is not measured.
- **Look class L (the user's review).** At rest the pin ends on the end of the page where the faithful pin ends up to 31 px past it; during the morph nothing else changes. The class is L by the Lean witness (`decline_rests_off_target`: the page may rest off target after a pan), and the measured rest differs from the faithful (base) rest in 8 of 10 comparable windows. No preset change; the ledger row is `look-change`, `userDecision` pending.
- **Next.** A phone visit with the finger trace (not requested here) would tell whether the pin's rest differs by eye, and a trace of the pin's decline (`due` returns none) would turn the INFERRED mechanism into MEASURED.

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
