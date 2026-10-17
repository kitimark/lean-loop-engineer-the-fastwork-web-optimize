# Handoff: port-morph-columns (morph.columns, faithful)

Branch worktree-agent-a45d937c5dc59b0f6 (CI ref `ci/port-morph-columns`). Commits are in the report.

## What is there
- `apps/site/src/parts/morph.columns/`: `index.tsx` (five static columns, 21 `<img>` with inline heights, placeholder 1x1 GIF),
  `data.ts` (offsets and heights restated from the original list, JS 12887-12935), `morph.module.css` (CSS 10559-10607,
  10812-10825, 10983-10988, in `@layer parts`), `media.ts` + `media.test.ts` (ids `mq.rm-reduce`, `mq.w-le-640`, byte-equal
  to `breakpoints.gen.json`), `data.test.ts`, `part.json` (impl plain only). No JS, no state: the 16 s marquee is the original's CSS keyframes.
- Layout switch (columns 4 and 5 hidden, gap 12 -> 8 at <=640) is CSS only, from the generated media text; no TS decision logic.
- Stand-ins for the panel at morph = 0 on `.stage`: `transform: scale(0.96)` and `data-scene="paused"` (will-change auto, animation paused,
  the scene scheduler rule css 11754). morph.panel should own both and drive `scene`; `MorphColumns` takes a `scene` prop.
- Gate: Lean `PartUse` for `morph.columns` in `lean/Fw/Gate/Scope.lean` (key = rm-reduce, <=640) -> 4 probes + 3 sweeps in
  `scope.gen.json`; `anchors.json` roles backdrop/col/track/img; `run.mjs` `ORIG_PREPARE` + `page.mjs mountPanel`: the original mounts the panel
  only after #platform nears the viewport, so a second collect pass runs after a scroll there and back (other parts are read first, untouched).

## Shared files touched (lead merges; separate commits)
- Additive wiring: `apps/site/src/registry/index.ts`, `App.tsx`, `Census.tsx` (commit 7ee9e92).
- Gate/Lean: `Scope.lean` (one list entry + docstring), `scope.gen.json`, `anchors.json` (new part entry), `run.mjs`, `page.mjs`.
  The other morph ports will touch the same lines (pilotParts list, anchors.parts, ORIG_PREPARE): expect trivial conflicts; regenerate scope.gen.json with `node packages/gate-breakpoints/scripts/scopegen.mjs` after merging.

## Notes and open items
- The gate skips every `animation*` property for all parts (global skipPrefixes), so the marquee timing is not compared by the gate.
- Local debug run (Chrome, 3 probes) passed morph.columns; the result of record is the CI run named in the report.
- Package tests 41/41 (need `FW_CORE_BIN` to main's fwcore in a worktree without a built lean).
- Read first: `morph.module.css`, then the `morph.columns` entry in anchors.json.
