# Handoff: port-overlays (overlays.drawer, overlays.signup, faithful)

Branch worktree-agent-ad17b89f45046fe5e (also pushed as `ci/port-overlays`). Commits: 565b3b5 + d8b9015 + 5fd4490 (parts, Lean), 4e93967
(shared, additive). Gate run ids are in the report. Verdict: both `faithful`, no timing delta.

## What is there
- Lean (`lean/Fw/Parts/`): `Bezier.lean` (CSS cubic-bezier by 40-step bisection; ease range/endpoint theorems), `OverlayDrawer.lean`
  (mount/show/unmount machine with the 480 ms timer, layouts at 640/860, slide and backdrop curves, theorems incl. the original's quirk:
  a close before the frame leaves `shown` set after the unmount), `OverlaySignup.lean` (exact `Mn` direction rounding, enter frame,
  close reactions, form validity, submit/settle), `OverlayGolden.lean` (lines). Goldens: `packages/contracts/golden/parts/overlays.{drawer,signup}.jsonl`.
- Parts (`apps/site/src/parts/`): `overlays.drawer/` (plain, CSS Module, store.ts open flag, timer/frame via the engine clock) and
  `overlays.signup/` (native `<dialog>` + showModal, CSS keyframe enter animation). `logic.ts` is checked against the goldens.
- Triggers: `openDrawer()` / `openSignup()` (exported from each part). App.tsx still has the placeholder nav buttons `#open-drawer`,
  `#open-dialog` calling them; the gate's rewrite arm clicks those ids (run.mjs PREPARE). When the nav is ported keep them or edit PREPARE.
- Gate: `PartUse` entries (Scope.lean), `scope.gen.json` regenerated, `anchors.json` roles. `run.mjs` PREPARE is now per arm
  (`open` before, `close` after the collect of a late part; morph.columns moved into it); `page.mjs` `openOverlay` / `closeOverlay`.

## Deltas / boundaries
- Brand glyph and the drawer's icons/divider images are placeholders (assets not restated); copy is the original English only.
- Text-driven boxes (dialog/panel heights, titles, items) compare styles only: the rewrite has no Google Sans file. Dialog margin-top/bottom skipped (height-derived).
- Reduced motion, 480 ms unmount, Escape/backdrop/cancel logic and the submit flow follow the Lean; no backend (`onSignup` absent -> "temporarily unavailable" as the original without handler).
- Original opened with body focus in the gate -> dialog direction (0, 16); the rounding for other triggers is proved/golden only.

## Open
- Not in Census (no Emotion; plain parts). Scope.lean LaTeX list in the docstring not updated. `lake exe partsgolden` regenerates goldens.
- Shared-file merges: Fw.lean, Golden.lean (table entries), Scope.lean, anchors.json, registry, App.tsx are additive; regenerate scope.gen.json after merging.
- Read first: `OverlayDrawer.lean` module docstring, then `drawer.module.css`, then the anchors entry.
