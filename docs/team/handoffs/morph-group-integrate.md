# morph-group-integrate (G2) handoff

State: branch worktree-wf_e6ffd6eb-9d3-3, CI branch ci/morph-group-integrate. Typecheck, vitest (17 morph/nav files, 1017 tests) and `pnpm build` (gates, shells check) pass locally; no gate or counts result is claimed from local runs.

Done
- Nav hosts the panel: `Nav` takes `children` (the panel), `onJoin`, `panelWriterRef`; its existing `data-fw-morph` MutationObserver calls `panelWriterRef.current.apply(morph)` (change-gated, no React state). `--morph` reaches the panel by inheritance from the nav (tween publishes it on the nav).
- App: panel mounted lazily by morph.mount (observing `[data-fw="platform"]` now, not the hidden sentinel), inside the nav; debug tray, MUI Menu and the fixed stub div removed.
- morph.panel: stand-in `.host` removed (panel fills the nav), bell/calendar glyphs, `onAction`, initial morph read from the nav, `<=640` backdrop gap moved here.
- morph.columns: 21 snapshot images (`/selling/{media,roles,profile,work}/...`), rendered as the backdrop's flex items (stage is `display: contents`), pause rule keyed on the panel's `data-start-selling-scene`; hidden-pause follows that attribute with a MutationObserver and observes the backdrop.
- Nav logo: round 2 removed the copied wordmark; nav keeps main's placeholder glyph until svg-extract.
- CTAs: nav Join and panel action call `openSignup`; hero button and people message button (signup) and commission "why" (drawer) via one delegated click listener in App.tsx, since hero/commission files are other lanes.

Round 2 (faithful arm judged)
- anchors.json rows morph.columns (backdrop = panel's backdrop, col/track shifted one level, waitFor morph-columns), overlays.drawer (trigger = commission why button), overlays.signup (trigger = hero button) re-anchored on this branch. census.mjs triggers fixed (tab clicks dropped, no tabs exist). BLANK_GIF removed from morph.columns.
- Local: apps/site test (70 files, 5026 tests) and tsc pass.

Open / limits
- waapi arm: `--morph` registered inherits:false, so the panel under the v2-proved preset does not see it: finding, owner morph-tween-inherit (Lean first). Not changed here.
- Double wheel/touch listeners (mount and tween): row morph-double-listener. Glyph stand-ins: bell/calendar duplicated in hero and morph.panel; logo placeholder; hero button lacks data-selenium (OPEN_SIGNUP uses '[data-fw="hero"] button').
- Goldens for MorphPanel/MorphTween untouched.

Read first: apps/site/src/App.tsx, apps/site/src/parts/nav/index.tsx, morph.columns/index.tsx.

CI (9d7ff406): breakpoint-gate chromium 39149624174 success; chromium-counts swipe-v1 rewrite 39149627595 success.
