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
- **Done (faithful scheduling):** faithful countdown now uses `startFaithful` (driver.ts): `clock.interval(1000, refresh)`
  plus one `{own:true}` subscriber per digit chain, started when that digit's target changes (previous chain
  cancelled) and ended when its spring settles; mount starts one chain per digit (unless reduced motion). Original:
  snapshot nodes/2.DyWL8TcE.js:3828-3840 (per-digit rAF chain) and :3932-3936 (immediate call, `setInterval(e, 1e3)`).
  Strip keeps the shared loop (`driver.tick`). `scheduling.test.ts` counts rAF registrations and timers per frame
  against a direct model of the original on the same ClockEnv (equal), plus strip = 1 shared rAF, cleanup = 0/0.
- Not reproduced: the original's `visibilitychange` listener that also refreshes the reading (no clock API for it).
- Gates at this commit: test and typecheck pass; census aot 0/0/0, runtime CAUGHT; media-check FAIL as expected
  (breakpoints.gen.json is `{}` until lean-site's generator lands).
- Goldens: lean-parts writes `packages/contracts/golden/parts/<id>.jsonl` with the fn names in logic.ts.
