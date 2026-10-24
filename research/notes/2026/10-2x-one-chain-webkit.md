# hero.countdown `one-chain`: the frame-499 forced recalc, its fix, and the WebKit counts

Task one-chain-webkit, CI branch ci/one-chain-webkit. Follows `10-20-countdown-one-chain.md`.

## Answer

- **Cause of the +1 recalc and +10 elements in swipe-touch-v1 frame 499: the digits' position in the frame.** The
  mechanism is CONFIRMED (source plus exact counts); that the reader is the scroll engine's tick is INFERRED.
  The first build ran the digits at their shared subscriber, which sits before the scroll tick (a scroll event adds
  the tick to the shared set after it). The tick's first read, `window.scrollY`, flushes dirty style, so the 10 face
  writes got their own style update. The tick then dirties a subtree of 320 elements, faces included, and the frame's
  own update visits the faces again. Result: 2 updates and 10 + 320 = 330 elements, against 1 update and 320 in
  `faithful`.
- **Lean why.** `frameCost` (Fw.Parts.HeroCountdownOneChain) gives `(1, m)` for the faithful order
  (`frame499_faithful`) and `(2, f + m)` for the digits at their subscriber (`frame499_atSubscriber`). With f = 10 and
  m = 320 these are 1/320 and 2/330, the exact counts of runs 39313910496 (base) and 39313842964 (one-chain) in frame
  499, all 3 shards (MEASURED). In the same frame ScheduleStyleRecalculation is 2 against 1, and Layout, LayoutCount
  and FireAnimationFrame (4 and 4) are equal.
- **Fix, theorems kept.** `oneChainClock` now runs its chains after every other shared subscriber of the frame: on its
  first visit in a frame it removes and re-adds itself (a `Set` walk visits the re-added entry again, which
  `createRafClock` relies on) and runs the chains on the second visit. That is the faithful order
  (`orderLast_eq_faithful`, `frame499_last`). Steps, writes and rAF callback counts are untouched, so every earlier
  theorem stands. The golden got the row `order499` (regenerated from Lean), and `oneChain.test.ts` replays it through
  the real shared loop for the three orders.
- **Verdicts.** Chromium: win on script work (MEASURED before: FireAnimationFrame -243 and -252); the frame-499 fix is
  not yet measured. WebKit: not yet measured. The lead sets win, trade or no-win per engine after the dispatches below.

## Source (CONFIRMED)

- Scroll steps run before the animation-frame callbacks: Chromium `page_animator.cc:266-271` (scroll) and `:335-340`
  (rAF callbacks) @f842f52; WebKit `Page.cpp:2294-2295` (Scroll) and `:2329` (AnimationFrameCallbacks) @862f17d.
- `scrollY` flushes style: Chromium `local_dom_window.cc:1853-1877` (`UpdateStyleAndLayout`) @f842f52; WebKit
  `LocalDOMWindow.cpp:1476-1480` (`updateLayoutIgnorePendingStylesheets`, only for a nonzero scroll) @862f17d. The
  WebKit lane may therefore show the same extra flush in a swipe frame.
- Why the swipe frames before 499 show no delta: their first layout read already finds dirty style from earlier work,
  so the faces ride that flush (INFERRED from the equal counts in frames 497-498).

## Limits

- The counts lane has no stacks, so the scroll tick is named from the code and the counts, not from a trace. The
  post-fix Chromium run decides it: frame 499 back at 1 update and 320 elements confirms the cause causally.
- Moving the digits last matches the faithful position against shared subscribers. Against other own chains the order
  is by registration, as before.
- The model has one dirty bit per kind. It matches frame 499 exactly; it is not a model of every frame.

## Dispatches (the lead runs them)

- WebKit counts, base then flag (3 runs each):
  `pnpm -s fw run --target rewrite --engines webkit --runs 3 --ref ci/one-chain-webkit` and the same with
  `--fw hero.countdown:one-chain`.
- Chromium counts, swipe-touch-v1, base then flag:
  `pnpm -s fw run --target rewrite --engines chromium --profile swipe-touch-v1 --runs 3 --ref ci/one-chain-webkit
  [--fw hero.countdown:one-chain]`.
- Breakpoint gate, both engines, flag on:
  `pnpm -s fw run --gate --engines both --fw hero.countdown:one-chain --ref ci/one-chain-webkit`.
