# Handoff: integrate-ports

Branch `worktree-agent-afe5e7954b26806f5` (CI ref `ci/integrate-ports`), from main 6626359. Merged, one merge commit each, in order:
port-morph-panel, port-nav, port-commission, port-overlays, port-hero, port-people, port-pain, then main 6e968ba (port-platform). gen-shells.mjs PORTED is derived: a section whose part.json has a faithful variant.
Head sha and run ids: in the lead report (the last pushed head is on `ci/integrate-ports`).

## Conventions
- Union of every shared file. App.tsx: Nav, MorphPanel outside `<main>`; main = Hero, morph.countdown stand-in, People, Pain, Commission, Platform, MorphColumns.
- Scope.lean docstring math lists every part with the same tuples as the Lean entries; Golden.lean writes 22 files.
- `scope.gen.json` regenerated (`lake build`, `node packages/gate-breakpoints/scripts/scopegen.mjs`), never hand-merged. mathview: 0 errors (`lake exe mathview`).

## Gate harness: ONE preparation mechanism (anchors.json `prepare.<arm>`, `page.mjs prepareInPage({stage, steps, capMs})`)
- step `kind: "mount"` (scrollNear, waitFor, why): morph.countdown, morph.columns, morph.panel. `kind: "overlay"` (trigger, ready, close, gone, why): overlays.*.
- `run.mjs evalCollect`: parts WITHOUT a prepare step are collected first (fresh load); then overlay parts one at a time (open, collect, close); then the
  mount steps run once and the mount parts are collected. (Mounting scrolls the original there and back and its scroll-driven values lag: this failed
  hero/nav cells in run 39062347763 when everything was prepared up front.)
- `waitReady` awaits every finite animation/transition (repeated until a quiet pass); result has `animations: {waitedMs, awaited, passes, left}`; no tolerance.
- Phase 0 property lists = union of 9 scans over one 3050 ms period (`declared.mjs`): fixed merge-gate "header differs" (hero.accent, WebKit).
- Tests: `test/prepare.test.mjs`, `settle.test.mjs`, `declared.test.mjs`; `scope.test.mjs` accepts height-axis knees (people.deck).

## CI
- Run 39062347763 (bb78c5f): all jobs success, but the merged summary has failures (chromium 39, WebKit 127). Job conclusions do NOT mean pass:
  read `gate-merged-*/summary.json` `engines.*.failures` (download with `gh run download <id> -p 'gate-merged-*'`).
- Wait with `pnpm fw ci wait --branch ci/integrate-ports --workflow breakpoint-gate`.

## Left (real part work, from run 39062347763; compare each cell with the port's own run)
- nav: border colour rgb(23,23,23) vs black and missing font-family on switch/earn (all cells; already failing in the port's run); WebKit nav and people.card at touch-rm-861 / dw-arm cells.
- commission: underline opacity/transform; section height 829 vs 777 and `--commission-shrink`; commission.typing visual scale at <=720 and avatarLarge at 319/320.
- will-change under touch+rm 861 (orig `auto`) on hero.countdown face, hero.orbit card, hero.deck card, hero copy; hero.orbit z-index 3 vs 2.
- overlays.signup widths 359.36 vs 360 (touch 960-1031); pain.notes note x (145 probes); people.deck shell/panel widths; people.card radius and --future-shrink in WebKit desk-861+.
