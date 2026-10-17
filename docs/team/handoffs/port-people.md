# Handoff: port-people (people.card, people.o, people.deck, people.carousel)

Branch worktree-agent-a0f32f59682e1d759 (CI ref ci/port-people). Verdicts: people.card, people.o, people.carousel `faithful`;
people.deck `faithful-with-delta` (mechanics faithful, panel content delta). Gate: run 39059296556 (ci/port-people, `breakpoint-gate`, scoped to the 4 parts by default? no: full push run). Chromium: all four people parts pass every cell. WebKit: o, carousel, deck pass; card fails 2/10 touch-rm probes on `filter` (the original is mid-transition blur(0.0027px), the rewrite already `none`: a transition timing race, not structure). Card section/card HEIGHT is not compared (host font line wraps, 24 px per line); widths are.

## Files
- Lean: `lean/Fw/Parts/People{Card,O,Deck,Carousel}.lean` (math docstrings, proofs: smoothstep/ae range+monotone, coverage, lerp
  between/contracts/fixed, reveal monotone, o timeline monotone + 120 ms gap + card inside viewport, carousel closed form +
  swap lands on next rest window + row widths 104/128, deck total 3.15 vh for six, pe hysteresis band 0.85, goto first/last).
  `PeopleGolden.lean` -> `packages/contracts/golden/parts/people.{card,o,deck,carousel}.jsonl` (`lake exe partsgolden`).
- TS: `apps/site/src/parts/people.{card,o,deck,carousel}/{logic,driver,media,index.tsx,*.module.css,part.json}` + golden tests;
  `parts/people/{index.tsx (composition), data.ts (content), shared.ts (after(), watchActive, ORDER), drivers.test.ts}`.
- Shared (commit 1359672 and e6b3796): App.tsx (`<People variants>`), registry (4 parts, `people` removed), Scope.lean PartUses,
  scope.gen.json, anchors.json (4 parts), Fw.lean, Golden.lean, `shells/model.ts` (people out of SECTION_IDS; boxes.gen.json regenerated).

## Conventions
- Per-frame values go to the DOM (`--future-shrink`, `--profile-scale`, active shell transform); React state only at thresholds
  (profession, rail flag, o flags, carousel index). Timers via `after()` = clock.interval cancelled on first fire.
- Scroll engine orders: o 20, deck 30, card 40. Pain colour: card sets `data-fw-pain-dark` and class `is-pain-dark` on `[data-fw=pain], .pain`
  (the pain port must read the attribute).
- Pill (button, text, avatars) is rendered by people.carousel (inventory owner of the pill CSS).

## Deltas (named)
- Photos not shipped: avatars, covers, post and service thumbs, o.svg glyph are neutral fills / a ring. Font is the host stack.
- Deck panel: top block (crumb, identity, stats, cover) and the Portfolio tab (masonry, vinyl, services rail) restated; Services, Reviews and About
  feed panels are empty; article/video posts are plain fills. Not ported: scene pausing and content-visibility deferral of `dE`.
- `pnpm check:shell-boxes` has a syntax error in scripts/shell-measure.mjs:112 (not mine). Scene pausing is a `data-fw-scene` attribute plus CSS on the card and deck sections.

## Open
- Item-level mathview warnings (binder not quantified) in the new Lean files; 0 failing.
- Read first: PeopleDeck.lean docstring, then people.deck/driver.ts.
