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
- Head 411847d on `ci/integrate-ports`. Run 39067170911 breakpoint-gate: jobs success, but the merged summary FAILS (chromium 64 items, WebKit 88). lean, gate-gaps,
  mutants, chromium-counts, wktr success on the same sha. Earlier run 39062347763 (bb78c5f, before the collect-order change): chromium 39, WebKit 127.
- Job conclusions do NOT mean pass: read `gate-merged-*/summary.json` `engines.*.failures` (`gh run download <id> -p 'gate-merged-*'`). Wait: `pnpm fw ci wait`.

## Left (real part work; fresh agent). Cells in run 39067170911, most also failed in the port's own run
- nav (all 196/188 cells): border colour rgb(23,23,23) vs black on nav and nav.hitTest; font-family missing on nav earn and nav.langMenu switch.
- commission: section/track/card/sticky height 829.77 vs 777.44; runway height 0 vs 54; title display block/flex; underline opacity/transform; inner/rows inline margins;
  commission.typing avatarLarge, message/referral transitions, visual scale at <=720, beat x/y.
- pain.notes note x (90 probes); hero.orbit card z-index 1 vs 2; platform.stageBg stage/bg/grain heights (WebKit); overlays.signup widths 359.2 vs 360 (WebKit touch);
  WebKit tails: people.card radius/--future-shrink, people.deck shell, people.o height, nav bar width in phone rotation.
