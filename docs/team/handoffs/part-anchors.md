# Handoff: part-anchors (gate anchors for engine.scroll and nav.hitTest)

Branch `worktree-agent-afb5ec3a5523c8de5`. Gate run (both engines, 124 loads x 2 arms + 4 sweeps) gives **pass in all 14 cells
of both engines** for both parts (was NC). Raw run is in gitignored `packages/gate-breakpoints/out/run-a/`.

## What changed
- The gate's anchor spec lives in `packages/gate-breakpoints/src/anchors.json` (not `spec.mjs`, which only builds probes/sweeps).
  Its part list must equal each `part.json` `anchors` (checked by `test/spec.test.mjs`).
- `engine.scroll` (anchor `engine-scroll`): `EngineScroll` now sets `data-fw="engine-scroll"` on `<html>` in a mount effect
  (one write, removed on unmount; absent in prerendered HTML). Roles: `scroller` (orig `html`, rewrite `html[data-fw=...]`) and
  `content` (`body`), both compared on width `w` only (height is page content). A missing mark gives count 0 vs 1 and fails.
- `nav.hitTest` (anchor `nav`): no code change; reuses the existing `[data-fw="nav"]` (the part's default `navSelector`).
  Role `nav` (orig `header.start-selling-top-nav`) compares **count only** (no dims, no restated CSS). This is a weak pass.

## Open items
- nav box geometry is not compared: original is a floating pill (x16 y16, 52/64 high, max 984 wide), rewrite a full-width 48 px
  placeholder AppBar. Probe x (x + w/2) is equal in both (verified at 8 widths). Once the nav part exists, add dims x,y,w,h
  to the `nav` role, or add a centre dimension (`cx = x + w/2`) in `page.mjs`/`verdict.mjs` (not mine) to test the probe x.
- Dark sections and the `is-on-dark` class are not in the rewrite page; Lean golden vectors (logic.test.ts) cover the decision.
- `packages/gate-breakpoints/results/summary.*` and the gate handoff still show these two rows as NC; regenerate them from
  the next full run after hero.exit lands.

## Read first
`packages/gate-breakpoints/src/anchors.json` (entries `engine.scroll`, `nav.hitTest`), `apps/site/src/parts/engine.scroll/index.tsx`.
