# Handoff: part-hero-3 (hero.exit breakpoint-gate fixes)

Branch worktree-agent-a15dc4fc7fb789a22. Only `apps/site/src/parts/hero.exit/hero.module.css` changed.

## Changes (restated values, no hand-written media: the existing three generated conditions only)
- `>600` block: `.copy { padding: 0 24px; position: relative; top: 0; left: 0 }`.
- Reduced-motion block moved ahead of the width blocks: `.copy, .cue { filter: none }`. The `>600` cue rule comes after
  and restores its own blur, so the cue's `none` shows at <=600 only (media.test.ts allows exactly 3 @media blocks,
  so no combined rm+width query).
- 320 floor: `.track { width: max(100%, 320px) }`. First try `min-width: 320px` failed the gate: the gate compares
  every property the rewrite declares, and the original's track has min-width 0 (the floor is on the page wrapper
  `.start-selling`). Computed `width` equals the original's (320 at a 319 viewport).

## Gate
No part filter in the CLI (`--probes` is by block). Full run, both engines, concurrency 3, about 11 min:
`FW_SNAPSHOT_SITE=<main>/snapshot/site node src/cli.mjs run --engine both --out out/h4 --concurrency 3`.
Result: hero.exit passes all 14 cells in both engines (before: FAIL in all 14), run 554 s. Informational, not in the verdict: title display/flex and font-family (unchanged).

## Notes
- `pnpm install --frozen-lockfile --offline` was needed in the fresh worktree (wt-prep did not install).
- Page-level floor still belongs to the page wrapper long term; this is a scoped stand-in.
