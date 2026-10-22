# site-layer-opts (part-builder)

Branch `worktree-wf_2347cc65-024-1`, worktree `.claude/worktrees/wf_2347cc65-024-1`, CI branch `ci/site-layer-opts`.
Last commit: 2b62ef0f.
CI runs: breakpoint-gate dispatch 39758534358 (both engines, default config, no fwl) running; lean push run 39758424234 success.
Dry land: VERDICT scope site-layer-opts (8 files outside the task writes, listed in the report open).

Done:
- `lean/Fw/Site/LayerOpts.lean`: per-layer, per-option CSS (`will-change` rule on `[data-fw-layer]`, unlayered; snap adds
  no rule, no snap table exists yet), theorems per branch (`rules_composite`, `rules_snap_only`, `css_snap_only`,
  `layerProps_none/some`, `table_length`), `#guard`s over the table. Generator `lean/scripts/LayerOptsGolden.lean`
  (`--write|--check <ts> <golden>`), job in `lean/scripts/check.sh`.
- Generated: `apps/site/src/registry/layer-opts.gen.ts`, `packages/contracts/golden/console/layer-opts.jsonl`.
- `resolve.ts` reads `fwl` (mirrors `BuildsOpen.layerErrors`, same reason texts) and returns `layerOpts`; `layer-opts.ts`
  looks entries up in the table and appends one `<style id="fw-layer-opts">`; `entry-client.tsx` calls it before render.
- Tests `apps/site/src/registry/layer-opts.test.ts`: replays layer-opts.jsonl and layers-search.jsonl against TS.
- Declared reads: Trigger.lean lean.yml row (+ triggers.jsonl), LandSpeed.checkShReads (+ land-speed.jsonl, land.ts).

Verified locally: check.sh green, site tests, ci-paths test, runner land-inputs test.
Open: gate run result (id above); snap tables (task snap-hero-proposal); per-layer `props` are not in part.json, so
the default `opacity, filter, transform` is used for every layer (`defaultProps`).
Read first: `lean/Fw/Site/LayerOpts.lean`, `apps/site/src/registry/layer-opts.ts`.
