# Handoff: port-morph-countdown

Branch worktree-agent-abe3a54c4338613fb, CI ref `ci/port-morph-countdown`. Verdict and run id are in the report to the lead.

## What it is
The original's second countdown sits in the morph panel centre column: `.waitlist-closing-countdown` (flex, centred, 100% wide,
margin-top 32px; css 11296-11301) around the same clock component with `inverse` (N2:12879, 13160). So the part is a wrapper
plus the hero.countdown component; logic, driver, scheduling and clock CSS are NOT duplicated.
- `apps/site/src/parts/morph.countdown/`: index.tsx (MorphCountdown), morph.module.css (wrapper only, no @media), media.ts
  (same 3 ids as hero.countdown), part.json (faithful; strip `requires` hero.countdown:strip), tests.
- Lean-first: no new decision logic, so nothing new to prove; the clock is covered by hero.countdown's goldens. The gate scope
  is Lean: `Fw.Gate.pilotParts` has a `morph.countdown` entry (same key as hero.countdown); the kernel `decide` theorems still hold.

## Shared edits (each its own commit; lead merges, expect conflicts with the other morph ports in the same spots)
- `hero.countdown/index.tsx`: optional `fwId` prop (root `data-fw`, default `hero-countdown`).
- `registry/index.ts` + `App.tsx`: part registered and rendered after HeroExit (placeholder host; morph.panel will own it later).
- `entry-server.tsx` `enumerateSearches`: a single-variant swap is requested with its `requires` (prerender failed otherwise).
- Gate: `anchors.json` (morph.countdown roles + `prepare`), `page.mjs prepareInPage`, `run.mjs evalReady`, `Scope.lean`, `scope.gen.json`
  (regenerate with `node packages/gate-breakpoints/scripts/scopegen.mjs`).

## Gate design note (read this)
The original mounts the morph panel only when `.start-selling-platform` is within 200% of the viewport (N2:13081-13085) and keeps
it. At scroll 0 the clock does not exist. anchors.json `prepare.orig` makes the gate scroll near it, wait, and return to the top
(generic: other morph parts can reuse the field). The panel is `scale(0.96)` at rest, so no role compares rects; only computed style.
Delta vs the original: rewrite host is a placeholder block (no panel), so position/size of the row are not compared.

## Open
- Not reproduced (same as hero.countdown): the original's visibilitychange refresh.
- morph.panel should mount `<MorphCountdown>` and own its lazy-mount rule; then drop the App.tsx placeholder.
