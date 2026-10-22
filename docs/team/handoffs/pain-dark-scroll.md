# pain-dark-scroll (part-builder) handoff

- Branch `worktree-wf_5c56f74c-ecb-1`, worktree `.claude/worktrees/wf_5c56f74c-ecb-1`, CI branch `ci/pain-dark-scroll`. Measured sha f05d0fcc (pushed); later commits are notes and handoff only.
- Design history (each failed on CI for a reason, see the note): design 1 a child div (gate selector `[data-fw="pain"] > div:first-child` is the sticky); design 2 one `::before` with transparent sticky and hold (gate compares their computed `background-color`: gate run 39818716087 FAILED, pain cells at every width). Design 3 (now): two `::before` layers over the unchanged white hold and stage.
- Runs on f05d0fcc (dispatched with `pnpm -s fw run ... --ref ci/pain-dark-scroll`), all running at last write:
  - breakpoint-gate both engines `--fw pain:dark-scroll`: 39822433333.
  - webkit-sim rewrite `--fw pain:dark-scroll` and chromium-counts swipe-v1 x3 `--fw pain:dark-scroll`: dispatched, ids not read yet.
- Valid baselines (faithful code is identical on 77b7744e and f05d0fcc): chromium-counts base 39818749535 (stored); webkit-sim base 39818734599 (was running).
- Design 2 chromium counts (run 39818742200, stored): read for the toggle-frame delta, but the layer census is design 2.
- Not started: trajectory pain cell (gpu-trajectory-cells not on main: pending), `fw land --dry`, full check.sh at the final commit.

## Verified
- Lean `lean/Fw/Parts/PainDarkScroll.lean` builds: pixel_eq, opacity_eq, measure_eq, wide_eq, drift_window, reveal_needed, cont_needed, no_lift, toggle_free, layer_backing_zero; golden `packages/contracts/golden/parts/pain-dark-scroll.jsonl` (240 rows, `#guard`).
- Site: vitest `src/parts/pain` green, typecheck green, footprint, rows, diff and Bridge tables regenerated (people.card to pain edge, 314 chain pairs; Bridge.lean is outside the graph writes).

## Open
- Gate and webkit-sim verdicts; note `research/notes/2026/10-2x-pain-dark-scroll.md`; `results/pain-dark-scroll/report.json`.
- Merge main, ci-paths + land-inputs tests, package test, check.sh, dry land.

## Conventions
- Flag `pain:dark-scroll`; people.card reads `data-fw-variant` of the Pain section (no People edit). Golden regen: scratch `def main := IO.print (Fw.Parts.PainDarkScroll.darkScrollJsonl ())` with `lake env lean --run`.
- After a footprint change: `part-footprint.mjs --write`, `ContractsGolden --rows/--diff`, rebuild Bridge (`codeAdj`, self-independent list, chain pairs).
- Read first: Lean file header, `apps/site/src/parts/pain/darkScroll.ts`, `pain.module.css` tail.
