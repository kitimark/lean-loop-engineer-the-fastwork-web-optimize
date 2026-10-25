# hero.countdown `one-chain`: the frame-499 forced recalc, its fix, and the WebKit counts

Task one-chain-webkit, CI branch ci/one-chain-webkit. Follows `10-20-countdown-one-chain.md`.

## Answer

- **Cause of the +1 recalc and +10 elements in swipe-touch-v1 frame 499: the digits' position in the frame.** Mechanism
  CONFIRMED (source plus exact counts); that the reader is the scroll engine's tick is INFERRED. The first build ran
  the digits at their shared subscriber, before the scroll tick. The tick's first read, `window.scrollY`, flushes dirty
  style, so the 10 face writes got their own update, and the tick's later 320-element restyle visited them again:
  2 updates and 330 elements against 1 and 320 in `faithful`.
- **Lean why, both frame kinds** (`Fw.Parts.HeroCountdownOneChain`, `frameCost` with `f` faces, `o` other elements,
  `m` subtree). Frame 499 (`kind499`, the original's digits after the shared loop): faithful (1, m)
  (`frame499_faithful`), digits at their subscriber (2, f + m) (`frame499_atSubscriber`), digits last (1, m)
  (`frame499_last`). Early frames 13-34 (`kindEarly`, other style dirty before the callbacks, one shared reader, the
  original's digits before the shared loop, INFERRED from the counts): faithful (1, f + o) (`early_faithful`), digits
  at their subscriber (1, f + o) (`early_atSubscriber`), digits last (2, f + o) (`early_last`): +1 update, equal
  elements, which is the Chromium delta of the last build. **`no_fixed_order`: each fixed position adds an update on
  one kind** (`extra_updates`). The two kinds differ in the original's rAF registration order (a shared loop that
  stopped re-registers behind the own chains, `engine/clock.ts` `createRafClock`), a per-frame fact no fixed
  position reproduces.
- **Decision (closed design, round 2).** Digits last is reverted to the subscribe position. Measured on Chromium,
  swipe-touch-v1: subscribe position +1 UpdateLayoutTree in 1 of 531 frames (frame 499; old runs, all 3 runs), digits
  last +1 in 157 of 771 frames. The subscribe position is the smaller extra, FireAnimationFrame -252 in the old runs
  (1860 vs 2112). Golden row `orders` (regenerated from Lean) is replayed through the real shared loop by
  `oneChain.test.ts` for the three orders and both kinds; `last` is the model's order, not shipped code.
- **Verdicts.** Chromium: trade (fewer rAF callbacks, one extra update in the frames where a scroll tick follows the
  digits). WebKit: see Round 2 runs below.

## Round-1 runs with digits last (MEASURED, sha 9623493da, ci/one-chain-webkit; the variant they ran is reverted)

- Chromium counts, swipe-touch-v1, 3 runs per arm: base run 40139538524, flag run 40139529440. The profile file
  changed since the old runs (sha 3e038fd6 against 616ca6ab; 771 frames against 531), so "frame 499" is a different
  frame now and the causal check "frame 499 back at 1 update and 320 elements" cannot be read. At index 499 base and
  flag are equal (4 updates, 67 elements). The cause stays CONFIRMED by source and Lean, not causally by this run.
- What the runs show instead: flag minus base is +1 UpdateLayoutTree and +1 ScheduleStyleRecalculation in 157, 157 and
  159 frames (r1, r2, r3), starting at frame 13 (frames 13-34 are all +1 with equal element counts), elements -46 over
  the run, FireAnimationFrame -314 (2572 to 2258), RequestAnimationFrame -315. Before the fix, on the same first
  frames (old flag run 39313842964 against old base 39313910496) frames 13-34 were equal to base. So running the
  digits last adds an update that the original does not have in those frames, while it removes the one in frame 499.
  The one-dirty-bit model fits frame 499 only; the original's order is not "last" in every frame (INFERRED: in frames
  13-34 the original's face writes ride the scroll tick's flush, that is they run before the tick).
- WebKit Simulator counts (webkit-sim.yml, rewrite, 430): flag run 40139526492 gave 1 usable VM (n=1; passes style
  665 and 680, layout 605 and 639). Base run 40139511311: its only VM (r1) timed out in the Simulator (no Safari
  tab for minutes, warm-up retried) and produced no artifact json (n=0); its job log shows one pass of style 699,
  layout 663 from a degraded session. That is not a comparison. Re-dispatch the base:
  `pnpm -s fw run --target rewrite --engines webkit --runs 3 --ref ci/one-chain-webkit`.
- Breakpoint gate, both engines, flag on: run 40139523821 success (chromium j0-j2, playwright-webkit j0-j3, merge).
- Round 2 took the second branch: back to the subscribe position (net recalc +1, not +157).

## Source (CONFIRMED)

- Scroll steps run before the animation-frame callbacks: Chromium `page_animator.cc:266-271` (scroll) and `:335-340`
  (rAF callbacks) @f842f52; WebKit `Page.cpp:2294-2295` (Scroll) and `:2329` (AnimationFrameCallbacks) @862f17d.
- `scrollY` flushes style: Chromium `local_dom_window.cc:1853-1877` (`UpdateStyleAndLayout`) @f842f52; WebKit
  `LocalDOMWindow.cpp:1476-1480` (`updateLayoutIgnorePendingStylesheets`, only for a nonzero scroll) @862f17d. The
  WebKit lane may therefore show the same extra flush in a swipe frame.
- Why the swipe frames before 499 show no delta: their first layout read already finds dirty style from earlier work,
  so the faces ride that flush (INFERRED from the equal counts in frames 497-498).

## Limits

- The counts lane has no stacks, so the scroll tick and the early-frame reader are named from the code and the counts,
  not from a trace (INFERRED). Frame 499 is not comparable across profile versions (531 vs 771 frames); the claim rests
  on source and Lean (`frame499_faithful`, `frame499_atSubscriber`).
- The model places the digits before or after every shared subscriber; both kinds have one, so any fixed rule collapses
  to these two. A per-frame order chosen at runtime is out of scope.
- The early-frame kind (other dirt before the callbacks, digits before the shared loop in the original) is fitted to
  the counts (+1 update, equal elements), not observed.

## Dispatches (the lead runs them)

- WebKit counts, base then flag (3 runs each):
  `pnpm -s fw run --target rewrite --engines webkit --runs 3 --ref ci/one-chain-webkit` and the same with
  `--fw hero.countdown:one-chain`.
- Chromium counts, swipe-touch-v1, base then flag:
  `pnpm -s fw run --target rewrite --engines chromium --profile swipe-touch-v1 --runs 3 --ref ci/one-chain-webkit
  [--fw hero.countdown:one-chain]`.
- Breakpoint gate, both engines, flag on:
  `pnpm -s fw run --gate --engines both --fw hero.countdown:one-chain --ref ci/one-chain-webkit`.
