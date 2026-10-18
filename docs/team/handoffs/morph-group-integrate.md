# morph-group-integrate (G2) handoff

State: branch worktree-wf_e6ffd6eb-9d3-3, CI branch ci/morph-group-integrate. Typecheck, vitest (17 morph/nav files, 1017 tests) and `pnpm build` (gates, shells check) pass locally; no gate or counts result is claimed from local runs.

Done
- Nav hosts the panel: `Nav` takes `children` (the panel), `onJoin`, `panelWriterRef`; its existing `data-fw-morph` MutationObserver calls `panelWriterRef.current.apply(morph)` (change-gated, no React state). `--morph` reaches the panel by inheritance from the nav (tween publishes it on the nav).
- App: panel mounted lazily by morph.mount (observing `[data-fw="platform"]` now, not the hidden sentinel), inside the nav; debug tray, MUI Menu and the fixed stub div removed.
- morph.panel: stand-in `.host` removed (panel fills the nav), bell/calendar glyphs, `onAction`, initial morph read from the nav, `<=640` backdrop gap moved here.
- morph.columns: 21 snapshot images (`/selling/{media,roles,profile,work}/...`), rendered as the backdrop's flex items (stage is `display: contents`), pause rule keyed on the panel's `data-start-selling-scene`; hidden-pause follows that attribute with a MutationObserver and observes the backdrop.
- Nav logo: `nav/logo.paths.ts` (9 paths from the snapshot's compiled page, generated once; no build-time snapshot read, so no land.ts declaration) and `nav/logo.tsx`.
- CTAs: nav Join and panel action call `openSignup`; hero button and people message button (signup) and commission "why" (drawer) via one delegated click listener in App.tsx, since hero/commission files are other lanes.

Open / follow-ups (outside my writes)
- packages/gate-breakpoints/src/anchors.json morph.columns roles assume `[data-fw="morph-columns"] > div` is the backdrop; now the backdrop is the panel's `[data-fw-role="backdrop"]` and the stage's children are the columns. Rows need re-anchoring.
- apps/site/scripts/census.mjs clicks `#open-menu/#open-drawer/#open-dialog` (removed); needs real triggers.
- Mount and tween both attach wheel/touch listeners (mount's `isActive` left default false, no `onPush`); a taken push is handled twice harmlessly. Unifying is a decision for the Lean side.
- Goldens for MorphPanel/MorphTween untouched.

Read first: apps/site/src/App.tsx, apps/site/src/parts/nav/index.tsx, morph.columns/index.tsx.

CI (branch ci/morph-group-integrate, commit 79ad2063): chromium-counts swipe-v1 rewrite run 39146819430 pass. breakpoint-gate chromium run 39146816361 fail only in rows that need re-anchoring: morph.columns (all cells: anchors assume the columns own the backdrop) and overlays.drawer / overlays.signup (anchors.json triggers #open-drawer / #open-dialog no longer exist; real triggers are [data-selenium="start-selling.commission.button.why"] and [data-fw="hero"] button). morph.panel, morph.tween, morph.mount, morph.countdown, nav, nav.langMenu, nav.hitTest all pass in every cell. commission(+typing) fails are the excused commission_resize_scope readings.
