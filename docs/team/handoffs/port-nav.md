# Handoff: port-nav (nav and nav.langMenu, faithful)

Branch worktree-agent-a34edc97e50f57131 (CI ref `ci/port-nav`). Commits: a7ab67d (parts, Lean, goldens), 12bcaed, cac2dbb (fixes),
5bb3268 (shared, additive). Gate run ids are in the report to the lead.

## What is there
- Lean: `lean/Fw/Parts/Nav.lean` (decisions: progress/pastHero/stuck/view/earn/ready rules; geometry of the pill as functions of
  `--morph`: navWidth/Height/Top/Radius, earn collapse, gap; Bezier + the transition constants; theorems rest_box, end_box,
  navWidth_mono, earn_gone, heroPill_not_morphing ...), `NavLangMenu.lean` (Closed/Open/Closing machine, timer actions, keyframe
  poses, theorems closed_only_by_timer, closing_mounted ...), `NavGolden.lean` (`navLines`, `menuLines`). mathview: 0 failing.
- Goldens `packages/contracts/golden/parts/nav.jsonl` (527) and `nav.langMenu.jsonl` (15); `partsgolden` regenerates them byte-equal.
- TS `apps/site/src/parts/nav/` (logic.ts + golden test, driver.ts + driver.test.ts, index.tsx, nav.module.css, media.ts) and
  `nav.langMenu/` (logic, controller (140 ms timer on the engine clock), index.tsx, lang.module.css, media).
- Driver: classes `is-hero-pill is-hero-chrome-ready is-morphing is-expanded is-locale-open is-scroll-hidden` toggled on change only,
  from `registerScroll('nav', 99)` and a MutationObserver on `data-fw-morph` (morph.tween publishes it). `is-on-dark` stays nav.hitTest's.
  No React state in the nav; the menu keeps its phase in React state (click/key/timer, never per frame).
- Shared (additive): App.tsx (Nav replaces the placeholder AppBar; the Menu/Drawer/Dialog trigger buttons moved to a fixed tray
  `data-fw="overlay-triggers"` so the MUI census still clicks them), registry, Scope.lean (nav incl. mq.c860 from the inventory, nav.langMenu),
  scope.gen.json (nav 14 probes 4 sweeps; langMenu 4/3), anchors.json (nav: nav/bar/logo/actions/earn; nav.langMenu: wrap/switch),
  Golden.lean table + Fw.lean imports. Golden.lean's `main` docstring still says 7 files.

## Deltas (named)
- Logo glyph is a placeholder shape in the original's 122 x 31 box (artwork not restated).
- Morph panel inside the nav (title, columns, CTAs, footer) is morph.panel's; not built. `.hero-track` is `[data-fw="hero-exit"]`;
  the profile sticky item does not exist yet (people shell), so `is-scroll-hidden` never fires in the page (Lean/golden cover it).
- Language selection only calls `onSelect` (no locale routing). Chrome-ready timer uses `clock.interval(1140)` cancelled after one fire.
- nav.hitTest's anchors.json `excluded` entry about the nav box is now stale (the box is compared by `nav`); not edited (additive rule).

## Open
- Gate verdicts per CI run (see report); fix any style mismatch in `nav.module.css` or widen `skipProps` with a reason.
- Read first: `Nav.lean` module docstring, then `nav.module.css`, then the `nav` entry in anchors.json.
