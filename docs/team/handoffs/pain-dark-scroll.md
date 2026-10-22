# pain-dark-scroll (part-builder) handoff

- Branch `worktree-wf_5c56f74c-ecb-1`, worktree `.claude/worktrees/wf_5c56f74c-ecb-1`, CI branch `ci/pain-dark-scroll`. Last commit 77b7744e (pushed).
- First design (a child div) failed by design: the gate selector `[data-fw="pain"] > div:first-child` is the sticky. The layer is now the section's `::before`. Runs 39817106098 (gate) and 39817118604 (webkit-sim) on the old sha were cancelled by me.
- Runs on 77b7744e (dispatched with `pnpm -s fw run ... --ref ci/pain-dark-scroll`), state running unless noted:
  - breakpoint-gate both engines `--fw pain:dark-scroll`: 39818716087.
  - webkit-sim rewrite `--fw pain:dark-scroll`: 39818721897; webkit-sim rewrite base (faithful): 39818734599 (queued).
  - chromium-counts swipe-v1 x3 cand and base: dispatched, run ids not yet read.
- Not started: trajectory pain cell (gpu-trajectory-cells not on main: pending), `fw land --dry`.

## Verified
- Lean `lean/Fw/Parts/PainDarkScroll.lean` builds (`lake build Fw.Parts.PainDarkScroll`): pixel_eq, opacity_eq, measure_eq, wide_eq, reveal_needed, cont_needed, no_lift, toggle_free, layer_backing_zero; golden `packages/contracts/golden/parts/pain-dark-scroll.jsonl` (240 rows, `#guard`).
- Site: vitest `src/parts/pain` + `people.card` green, typecheck green. Footprint and v2-proved decisions regenerated.

## Open
- Full `sh lean/scripts/check.sh`, site/package tests, ci-paths + land-inputs tests, merge main, dry land.
- Note `research/notes/2026/10-2x-pain-dark-scroll.md` with run ids.

## Conventions
- Flag `pain:dark-scroll`; people.card reads `data-fw-variant` of the Pain section (no People edit). Golden regen: scratch `def main := IO.print (Fw.Parts.PainDarkScroll.darkScrollJsonl ())` with `lake env lean --run`.
- Read first: Lean file header, `apps/site/src/parts/pain/darkScroll.ts`.
