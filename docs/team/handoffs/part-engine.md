# Handoff: part-engine (engine.scroll, nav.hitTest, shared engine)

State written by part-engine after the Lean parts specs (lean/Fw/Parts/*.lean).

## engine.scroll
- Code: `apps/site/src/engine/scroll.ts` (engine), `apps/site/src/parts/engine.scroll/` (logic, tests, EngineScroll part).
- Variants: `faithful` (callback runs reads and writes interleaved, as the original), `batched` (all reads, then all writers).
- Frame structure of the original (Lean `pilotFrame`): steady frame = `[hero exit body (own rAF, queued first)] ++ [engine iE:
  nav callback read, write, read, write, read]`. The faithful variant now reproduces it: hero.exit requests its own rAF from the
  engine callback (`mountExit`, parts/hero.exit/driver.ts); nav.hitTest runs ee() reads, F(), and the hero-track rect inside its
  callback. `src/engine/pilot-frame.test.ts` logs the accesses with fakes and checks equality with `PILOT_FRAME`, forced style
  passes 4 (dirty start) / 3 (clean), engine `batched` + `elements-skip` nav at most 1.
- Cost model in logic.ts (`forced`, `forcedCounts`, `forcedCountsBatched`, `planLayouts`, `engineRuns`, `NAV_ACCESSES`,
  `HERO_EXIT_ACCESSES`, `PILOT_FRAME`), all golden-checked against `engine.scroll.jsonl` and `.spec.jsonl`.
- Caveat: engine `batched` only batches what callbacks return as writers. The faithful nav probe writes `pointer-events` inside
  its callback, so `batched` + nav `faithful` still pays the write/read pairs; pair `batched` with `elements-skip` (or `hit-skip`
  while morph > 0.2) to reach <= 1. This is tested.

## nav.hitTest
- Variants: `faithful` (real `elementFromPoint` with the nav root forced to `pointer-events: none`, so nav boxes that set
  `pointer-events` themselves stay hit-testable: actions, expanded morph panel, active morph pill, earn button; this is the
  original), `hit-skip` (v1 `hit-skip`: skip the test while morph > 0.2, keep the stale answer; class = `isOnDark(hit, morph)`),
  `elements-skip` (v1 `nav-hit-test`: `elementsFromPoint` plus the allow-list `ALLOW_SELECTOR`, no style write).
- `firstOutside` (skip the whole nav subtree) is NOT faithful (Lean `firstOutside_ne_faithful`); it is kept only as a pinned
  function and no variant uses it. `faithfulHit`/`allowHit` match Lean `faithfulHit`/`allowHit`, `isOnDark` the class rule.
- Morph source: `data-fw-morph` on the nav element (absent = 0); the nav part has to set it.
- Results of the ee() profile-sticky reads and of the hero-track progress are read for cost parity and returned by `navFrame`, not
  applied (they feed `is-scroll-hidden` and `is-hero-pill`, nav-part behaviour). The track selector is `[data-fw="hero-exit"]`.

## Tests and gates
- Shared golden harness: `src/engine/golden.testutil.ts` (see part-hero.md). `engine.clock.test.ts` still has a `skipIf` because
  there is no `engine.clock.jsonl` golden yet.
- Gates: `pnpm test` 688 pass, `pnpm typecheck` clean, `pnpm census --engine aot` 0/0/0 PASS, media-check FAIL until the Lean
  breakpoint generator is wired into `breakpoints.gen.json`.
