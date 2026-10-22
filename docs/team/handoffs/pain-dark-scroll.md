# pain-dark-scroll (part-builder) handoff

- Branch `worktree-wf_5c56f74c-ecb-1`, worktree `.claude/worktrees/wf_5c56f74c-ecb-1`, CI branch `ci/pain-dark-scroll`. Measured sha 83260609 (pushed); later commits add `promoted_cost`, the note, the report and a merge of main (no flag code changed).
- Final-design runs (dispatched with `pnpm -s fw run ... --ref ci/pain-dark-scroll`): breakpoint-gate both engines 39828600078 PASS; webkit-sim 39828605244 PASS; chromium-counts 39828614430 PASS (stored). Base: counts 39818749535, webkit-sim 39818734599. Second webkit base 39831383981 was still running at the last write (not used).
- Earlier designs (all in the note): gate 39817106098 cancelled (child div), gate 39818716087 FAIL (transparent sticky and hold), gate 39822433333 PASS and webkit-sim 39822439200 (range 1 px: layers never in the WebKit census), counts 39822446444 / 39818742200.
- Verdict: hold. Pixel equality proved, gate passes; Chromium toggle frame paints one viewport less, WebKit pass paints 28 to 34 percent less; WebKit +12 MB backing (overlap promotion), Chromium +3 layers, +14 style recalcs. Trajectory pain cell pending (gpu-trajectory-cells not on main). Toggle-frame duration not measured.

## Verified
- Lean `lean/Fw/Parts/PainDarkScroll.lean` builds: pixel_eq, opacity_eq, layer_flip, measure_eq, wide_eq, drift_window, reveal_needed, cont_needed, no_lift, toggle_free, layer_backing_zero, promoted_cost; golden `packages/contracts/golden/parts/pain-dark-scroll.jsonl` (240 rows, `#guard`).
- Site: vitest `src/parts/pain` green, typecheck green. Footprint, rows, diff, v2-proved decisions and Bridge tables regenerated (people.card to pain edge, 314 chain pairs; `Bridge.lean` is outside the graph writes).

## Open
- See the report's `open`; the note is `research/notes/2026/10-2x-pain-dark-scroll.md`, numbers in `results/pain-dark-scroll/report.json`.

## Conventions
- Flag `pain:dark-scroll`; people.card reads `data-fw-variant` of the Pain section (no People edit). Golden regen: copy the Lean file without its `include_str` line, add `def main := IO.print (Fw.Parts.PainDarkScroll.darkScrollJsonl ())`, `lake env lean --run`.
- After a footprint change: `part-footprint.mjs --write`, `ContractsGolden --rows/--diff`, rebuild the Bridge tables (`codeAdj`, the self-independent list, chain pairs).
- The gate compares computed styles of sticky and hold, so the variant adds pseudo-elements only and restyles nothing.
- Read first: the note, then the Lean file header and `apps/site/src/parts/pain/pain.module.css` tail.
