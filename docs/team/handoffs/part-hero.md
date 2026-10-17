# Handoff: part-hero (hero.countdown, hero.exit)

State at 88a4302 (written by the lead from part-hero's report).

- Parts: `apps/site/src/parts/hero.countdown/` (variants faithful and strip, impl mui/plain) and
  `apps/site/src/parts/hero.exit/` (faithful, mui/plain). Each part has logic.ts (pure, exports `GOLDEN_ARGS`),
  driver.ts, index.tsx, hero.module.css, media.ts and tests.
- Wiring is done by part-engine: registry/index.ts, App.tsx and Census.tsx. Prerender builds every config.
- Engine API: `registerScroll(id, order, cb)`. cb may return a writer, which runs after its own cb in faithful
  mode and after all cbs in batched mode. Clock: `getClock().subscribe(tick, {own:true})` gives the subscriber its
  own rAF registration; `interval(ms, cb)` is a real setInterval.
- Breakpoints: countdown uses C1000-nodw and ≤400 (≤400 wins); exit uses ≤600/>600 plus reduced motion. Media text
  is restated in the CSS modules; media.test.ts compares it with `breakpoints.gen.json` once that has entries.
  The media-check gate stays red until lean-site's generator lands.
- Decisions: countdown target = the original's TARGET_MS (2026-11-02T12:00+07:00), so captures pin Date.now;
  aria-label is static.
- **Open:** the faithful countdown still folds the original's 1 s setInterval and per-digit rAF springs into one
  clock subscriber. Switch the faithful variant to `clock.interval(1000, …)` plus one `{own:true}` subscriber per
  digit spring, so rAF and timer counts equal the original's (PL5). Strip and plain can keep the shared loop.
- Goldens: lean-parts writes `packages/contracts/golden/parts/<id>.jsonl` with the fn names in logic.ts.
