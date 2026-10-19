# deck-panels-lean handoff

State: branch worktree-wf_f0e4209d-fe6-3, one commit. apps/site vitest 80 files / 5282 tests pass, typecheck clean, local aot
build passes (debug only, not a result), `lake build` passes. No CI run made, no browser run.

Done
- Lean: lean/Fw/Parts/PeopleDeckPanels.lean (tab dispatch with fallback to about, review filter ids and listing, faces and "+n",
  verdict (monotone), filled stars (prefix), toggle involution, about section list, ASCII monogram). Golden:
  packages/contracts/golden/parts/people.deck.panels.jsonl (from PeopleGolden.files, `lake exe fwcore partsgolden`).
- TS: people.deck/panels.logic.ts (conformance in panels.logic.test.ts), feedPanels.tsx (ServicesPanel, ReviewsPanel, AboutPanel),
  panels.module.css (all breakpoints of the original: 1200, 1030/500/touch-1200 combo, 480), panel.tsx wires the tabs and the
  Services "View all" button. Content: people/panels.data.ts (reviews and about of the six professions, restated text),
  pictures through people/assets.ts (logos, review photos, reviewer avatars from the snapshot, bundled by glob).
- footprint.gen.json and FootprintData.lean regenerated (`node apps/site/scripts/part-footprint.mjs --write`).

Stand-ins (temporary)
- Star is a clip-path polygon; the four review-dimension icons are drawn SVG shapes (not the original's vector paths).
- English only (the original also has th/id/vi/ar strings; the site is English everywhere else).
- graphic-designer/logo-fastwork.png is named by the original but absent from the snapshot: it renders a broken image there
  in the original; here it renders the monogram (assets.test.ts pins this single miss).
- Monogram spec covers ASCII letters/digits only (all names in the data are ASCII).

Open
- No breakpoint-gate/zones run: the three panels are new DOM under people.deck, ci/<name> push needed to prove boxes.
- The feed body clips (overflow hidden + mask, as in the original); long Reviews/About content relies on the shell height.
- apps/runner/src/fw.ts shows a mode-only change from pnpm install; not committed.
Read first: lean/Fw/Parts/PeopleDeckPanels.lean, apps/site/src/parts/people.deck/feedPanels.tsx.
