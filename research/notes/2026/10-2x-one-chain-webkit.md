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
  last +1 in 157 of 771 frames. The revert is the lead's closed-design choice. On the same 771-frame profile the subscribe position adds +1 in
  233-238 frames (round 2) and digits last in 157-159 (round 1), so on Chromium the subscribe position is the larger
  extra. Golden row `orders` (regenerated from Lean) is replayed through the real shared loop by
  `oneChain.test.ts` for the three orders and both kinds; `last` is the model's order, not shipped code.
- **Verdicts.** Chromium: trade (MEASURED; FireAnimationFrame -314, UpdateLayoutTree +283 in 233-238 of 771 frames, elements
  equal). WebKit: no-win (MEASURED; see Round 2 runs below). Task closed as a finding.

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
- Superseded: the claim that the swipe frames before 499 show no delta held for the old 531-frame profile only; on the
  771-frame profile frames 14-33 show +1 (see Round-2 runs).

## Limits

- The counts lane has no stacks, so the scroll tick and the early-frame reader are named from the code and the counts,
  not from a trace (INFERRED). Frame 499 is not comparable across profile versions (531 vs 771 frames); the claim rests
  on source and Lean (`frame499_faithful`, `frame499_atSubscriber`).
- The model places the digits before or after every shared subscriber; both kinds have one, so any fixed rule collapses
  to these two. A per-frame order chosen at runtime is out of scope.
- The early-frame kind (other dirt before the callbacks, digits before the shared loop in the original) is fitted to
  the counts (+1 update, equal elements), not observed.

## Round-2 runs at the subscribe position (MEASURED, head f74e3313a, ci/one-chain-webkit)

Summaries: `results/one-chain-webkit/summary.json`.

| lane | base run | flag run | n per arm |
|---|---|---|---|
| Chromium counts, swipe-touch-v1 | 40153927556 | 40153920231 | 3 and 3 |
| WebKit Simulator, rewrite, 430 | 40153925235 | 40153917806 | 3 VMs (6 passes) and 2 VMs (4 passes) |
| breakpoint gate, both engines, flag on | 40153922711 | | |

- **Chromium** (771 frames, totals per run, 3 runs each, spread at most 5): UpdateLayoutTree 2393/2392/2388 base against
  2671/2676/2676 flag (+283 on average, +11.8 %); ScheduleStyleRecalculation 2409/2408/2404 against 2687/2692/2692
  (+284); elements 60225/60158/60157 against 60139/60162/60163 (equal within 0.1 %); FireAnimationFrame 2572 against
  2259/2258/2258 (-314, -12.2 %). The extra update is +1 in 233, 238 and 238 frames (30 %), in the same frame ranges
  in all three runs (14-33, 62-79, 122-147, 182-207, ... 483-500), 5 of them in the settle phase. Frame 499 is
  inside the last range: 5 updates against 4, elements 67 against 67.
- **The round-2 prediction failed.** Lean `early_atSubscriber` says the subscribe position adds no update in the early
  frames (1, f + o), and the old 531-frame runs showed +1 in 1 frame. On the current profile (771 frames) and the
  merged base it adds +1 in 30 % of frames. The early-frame kind was fitted (INFERRED) and is falsified for this base:
  the model explains frame 499 only. Frame 499 and the old runs are not comparable across profile versions.
- **WebKit** (RecalculateStyles / Layout per pass; flag applied: configHash 1e8f122ab2eb19fc, `?fw=hero.countdown:one-chain`):
  RecalculateStyles base mean 672.3 (654-692, n = 6 passes of 3 VMs) against flag 671.8 (652-693, n = 4 passes of 2 VMs);
  Layout 627.2 (603-664) against 644.3 (618-680), +17, inside the 61-wide base spread; ScheduleStyleRecalculation
  634.0 against 636.3; FireAnimationFrame 672.7 against 676.3. Per 500 px zone the RecalculateStyles means differ by at
  most 3 (zone 4: 62.7 against 59.8), inside each zone's base spread (zone 4: 58-64). One flag VM (r1) failed: the
  inspector died and `simctl launch Safari` failed with CoreSimulator code 405; n = 2 VMs for the flag.
- **Breakpoint gate, flag on** (run 40153922711): Chromium 14 of 14 widths pass for every row incl. hero.countdown;
  playwright-webkit 12 pass and 2 unreachable (primary-pair, whole-width), the same two for every row, none failing.

## Verdicts (MEASURED)

- **Chromium: trade (MEASURED).** FireAnimationFrame -12 %, UpdateLayoutTree +12 % at equal elements: fewer rAF
  callbacks, more but smaller style updates. The unit that mattered (a win in recalc) is not met; counts are engine
  work, not felt smoothness.
- **WebKit: no-win.** Style recalcs and rAF callbacks equal within noise; no measured effect, no regression.
- Follow-ups (outside the unit): (1) a Lean model of the shared loop's per-frame registration order (the early-frame
  kind is a fit, early_atSubscriber is falsified on the 771-frame profile; frame499_atSubscriber holds for the
  531-frame profile only; no_fixed_order is a model result); (2) the TS stand-in `frameCost` in `oneChain.test.ts`
  stays until that model exists.
