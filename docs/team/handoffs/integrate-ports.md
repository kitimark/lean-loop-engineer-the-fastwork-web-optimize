# Handoff: integrate-ports

Branch `worktree-agent-afe5e7954b26806f5` (CI ref `ci/integrate-ports`). Built from main 6626359; merged in order: port-morph-panel,
port-nav, port-commission, port-overlays. One merge commit each. CI run ids are in the report to the lead.

## Conventions
- Union of every shared file (registry parts, App.tsx, Census.tsx, Fw.lean, Golden.lean, Scope.lean PartUse, anchors.json).
  App.tsx: Nav, MorphPanel outside `<main>`, then hero, exit, countdown stand-in, people, pain, commission, platform, columns;
  placeholder trigger tray (`overlay-triggers`) now calls `openDrawer` / `openSignup`.
- `Scope.lean` docstring math lists every part (mount, tween, panel, nav, nav.langMenu, commission, commission.typing, overlays.*)
  with the same tuples as the Lean entries. `Golden.lean` writes 15 files (docstring says 15).
- `scope.gen.json` is regenerated (`lake build`, then `node packages/gate-breakpoints/scripts/scopegen.mjs`), never hand-merged.

## Gate harness: ONE preparation mechanism
- anchors.json per-part `prepare.<arm>` = list of steps with a `kind`:
  - `mount` (`scrollNear`, `waitFor`, `why`): run once after `waitReady`, page back at the top (morph.countdown, morph.columns, morph.panel);
  - `overlay` (`trigger`, `ready`, `close`, `gone`, `why`): the part is collected alone between stage open and stage close (overlays.*).
- `page.mjs prepareInPage({stage: ready|open|close, steps, capMs})` is the only page function; `run.mjs` calls it from `evalReady`/`evalCollect`.
  Removed: `ORIG_PREPARE`, `mountPanel`, `primeOrig`, `PREPARE`, `openOverlay`, `closeOverlay`. Tests: `test/prepare.test.mjs`.
- Behaviour change to watch: morph.columns used to be collected after the early parts (late pass); it now mounts the panel before every part
  is collected (like morph.countdown). If a CI cell for another part changes because the panel is mounted, add a `phase` option here.

## Open
- Not kept: nothing dropped. `scripts/mathview-cached.sh` does not exist in this tree; used `lake exe mathview` (0 errors, all `sorryFree`).
- Read first: `page.mjs prepareInPage`, then the `prepare` keys in anchors.json.
- CI: the first push of ci/integrate-ports raised a ref-lock error and started no run; a second push triggered it.
