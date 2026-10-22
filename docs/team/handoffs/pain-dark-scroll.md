# pain-dark-scroll (part-builder) handoff

- Branch `worktree-wf_5c56f74c-ecb-1`, worktree `.claude/worktrees/wf_5c56f74c-ecb-1`, CI branch `ci/pain-dark-scroll`. Last commit d7ad646a (flag, Lean, goldens).
- CI runs (all on d7ad646a, dispatched with `pnpm -s fw run ... --ref ci/pain-dark-scroll`):
  - breakpoint-gate both engines, `--fw pain:dark-scroll`: 39817106098 running.
  - webkit-sim rewrite, `--fw pain:dark-scroll`: 39817118604 queued.
- Not started: base (faithful) webkit-sim, chromium-counts base/cand, trajectory probe (needs gpu-trajectory-cells on main), local `fw land --dry`.

## Verified
- Lean `lean/Fw/Parts/PainDarkScroll.lean` builds (`lake build Fw.Parts.PainDarkScroll`): pixel_eq, opacity_eq, measure_eq, wide_eq, reveal_needed, cont_needed, no_lift, toggle_free, layer_backing_zero; golden `packages/contracts/golden/parts/pain-dark-scroll.jsonl` (240 rows, `#guard`).
- Site: vitest `src/parts/pain` + `people.card` green, typecheck green. Footprint and v2-proved decisions regenerated.

## Open
- Full `sh lean/scripts/check.sh`, site/package tests, ci-paths + land-inputs tests, merge main, dry land.
- Note `research/notes/2026/10-2x-pain-dark-scroll.md` with run ids.

## Conventions
- Flag `pain:dark-scroll`; people.card reads `data-fw-variant` of the Pain section (no People edit). Golden regen: scratch `def main := IO.print (Fw.Parts.PainDarkScroll.darkScrollJsonl ())` with `lake env lean --run`.
- Read first: Lean file header, `apps/site/src/parts/pain/darkScroll.ts`.
