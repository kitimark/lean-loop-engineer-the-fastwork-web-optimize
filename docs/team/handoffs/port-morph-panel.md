# Handoff: port-morph-panel (morph.panel faithful)

Branch worktree-agent-aa399880b0e73e3d8. Commits listed in the report. Gate run id in the report.

## What is there
- `apps/site/src/parts/morph.panel/`: `index.tsx` (MorphPanel: fixed stand-in host + panel: backdrop slot, veil, centre with title,
  countdown slot, CTA stack (button + RSVP link), footer), `morph.module.css` (values restated from the original CSS, the
  component rules and the page's inline `<style>` in index.html; media blocks 1000, 720, rm, 640, 600), `logic.ts`
  (flags + calc readings, `GOLDEN_ARGS`), `driver.ts` (`createPanelWriter`: attribute writes only on change, no React state),
  `media.ts`, tests, `part.json`.
- Lean: `lean/Fw/Parts/MorphPanel.lean` (readings, 4 flags, 8 theorems); golden `packages/contracts/golden/parts/morph.panel.jsonl`.
- Gate: `anchors.json` entry `morph.panel` (16 roles, style only, no boxes: the host differs), `Scope.lean` PartUse (21 probes
  + 4 sweeps), regenerated `scope.gen.json`, and a `prime` step (see below).

## Shared edits (separate commit; the lead merges, expect conflicts with the other 4 morph ports)
`lean/Fw.lean` + `lean/Fw/Parts/Golden.lean` (import, `morphPanelLines`, file list), `registry/index.ts`, `App.tsx`, `Census.tsx`,
`lean/Fw/Gate/Scope.lean` (+1 PartUse), `anchors.json`, `scope.gen.json` (regenerate after merging all: `node scripts/scopegen.mjs`),
`packages/gate-breakpoints/src/page.mjs` + `run.mjs` (`primeOrig`, used when a covered part has `prime.orig`).

## Facts
- The original mounts the panel only after the platform section intersects (200% margin) and keeps it; at load there is none.
  Hence `prime.orig` in anchors: scroll the original to `.start-selling-platform`, wait for the panel, scroll back. Other morph ports
  (mount, tween, countdown, columns) can reuse it: put `prime` on their anchors entry.
- The page's inline style (index.html) restyles the CTA stack (grid, 12/8 gaps), CTA gap 8, the RSVP link, `.cta-icon`, with
  `(max-width:600px)`: restated, uses `mq.w-le-600`.
- Not restated: font-family (no token), `--panel-w/h` (host, `mq.c860`), images/columns (morph.columns), countdown (morph.countdown).
- The host is a stand-in for the nav; `--morph` is written on it by morph.tween (not yet). `writerRef.current.apply(m)` sets the flags.

## Open
- Deltas and the gate verdict: see the report. Read first: `morph.module.css`, then the `morph.panel` entry in `anchors.json`.
