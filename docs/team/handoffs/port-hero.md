# Handoff: port-hero (hero, hero.orbit, hero.deck, hero.accent, hero.cue; P1)

Branch worktree-agent-a61694f39f98455fd (CI ref `ci/port-hero`). Commits and gate run id are in the report.
Verdict: `faithful` for hero, hero.orbit, hero.deck, hero.cue; hero.accent `faithful-with-delta` (stroke artwork).

## Files
- Lean (new): `lean/Fw/Parts/HeroOrbit.lean` (splash clock phases, ring angle/radius/blur, delays 8+28k, 1164/1820 ms
  identities, edge push below 1280, scatter, ten pieces, Float `place`), `HeroAccent.lean` (cursor, 2200/1250/900 timer
  chain `chainAt`, period 3050, 7-step wrap, idle boil), `HeroDeck.lean` (deck slots, cue float and entrance facts),
  `HeroGolden.lean` (-> `packages/contracts/golden/parts/hero.orbit.jsonl` 527 lines, `hero.accent.jsonl` 58).
- TS: `apps/site/src/parts/{hero,hero.orbit,hero.deck,hero.accent,hero.cue}/`; `hero` composes `hero.exit` (now only the
  track + sticky stage, takes children) with the other four and the existing `hero.countdown` (moved inside the copy).
  Shared card markup/CSS: `hero.orbit/card.{tsx,module.css}` (deck imports it).
- Splash state: stage `data-splash=prep|run|done`, orbit `data-orbit data-expand data-done` (set by the driver; CSS keys on them).
- Drivers: orbit = `clock.subscribe(own)` + one 1820 ms `clock.interval` timer (faithful rAF/timer counts, 3 vars x 10 cards
  per frame); accent = one pending timer chain (`clock.interval` as a one-shot) + IntersectionObserver (100% margin).

## Shared edits (separate commit; lead merges)
- `App.tsx`: `<HeroCountdown/><HeroExit/>` replaced by `<Hero variants=.../>`. `registry/index.ts`: 5 parts added.
- `Golden.lean` (+2 lines, import), `Fw.lean` (4 imports), `Scope.lean`: hero.exit shrunk to owners [hero.exit]; PartUses
  hero, hero.cue, hero.orbit, hero.deck (owners deck+orbit: the card CSS is shared, incl. its rm rule), hero.accent;
  `scope.gen.json` regenerated; `anchors.json`: hero.exit reduced to track+stage, five parts added.
- hero.exit `part.json`: impls plain only, muiStates []; `media.ts` 2 ids; media.test 2 blocks.

## Gate
Local debug run (Chrome, scoped probes, no sweeps): all six parts pass. Result of record: the CI run in the report.
Skipped on purpose: orbit start vars `--orbit-enter-x/y`, `--orbit-start-rot` (set by the splash's last frame; formula in
Lean/golden), accent width/transition (depends on capture time), text-dependent boxes (placeholder text).

## Deltas / open
- hero.accent strokes are plain stand-in waves (not the original's hand-drawn paths); words/widths/insets/timing are restated.
- Pictures are a 1x1 GIF, text is placeholder. Pointer-enter raise (z-index) and the cue's smooth scroll are untested handlers.
- Not reproduced: `pageshow`-persisted restart is wired but untested in a browser; the dead `.hero-cta:before` gradient.
- Scope.lean docstring LaTeX list of pilot parts not updated. Read first: `HeroOrbit.lean` docstring, then `hero.orbit/driver.ts`.
