# land-scope-golden-regs

- Branch `worktree-wf_86e5c32d-062-1`, worktree `.claude/worktrees/wf_86e5c32d-062-1`. No CI runs.
- State: Lean + TS done, main merged, `check.sh` green, `@fw/runner` and contracts tests green, `ci-paths.test.mjs` green.

## What landed
- `Land.goldenRegs` (Land.lean, golden registration set section): a write under `packages/contracts/golden/` admits
  `lean/scripts/*Golden.lean` and `lean/scripts/check.sh`. Theorems `goldenRegs_nil`, `goldenRegs_of_golden`,
  `goldenRegs_eq_nil_iff`, `goldenRegs_incl` (never an exclusion), `goldenRegs_mem_landScope`, `landScope_no_golden`
  (no golden write: the old scope). The protected suffix and `protected_refused` were re-proved with the new set.
- `generated` now holds `apps/runner/src/land-reads.gen.ts`, so a regenerated read list never needs a write.
- One source for the check.sh reads: `LandSpeed.checkShReads` feeds `readsTs`, which writes `apps/runner/src/land-reads.gen.ts`;
  `land.ts` re-exports `CHECK_SH_READS` from it. `LandSpeed.checkGolden` (run by the existing check.sh job
  "land-speed golden check") now checks land-speed.jsonl, land-reads.gen.ts and land-scope-regs.jsonl.
- Regenerate all three: `cd lean && lake env lean --run scripts/LandReadsGen.lean --write` (`--check` to verify).
- Regression goldens: `Land.regCases` (#guard on every verdict) -> `golden/console/land-scope-regs.jsonl`, replayed
  through fwcore in `apps/runner/test/land-scope.test.ts`.

## Limits (accepted)
- `Trigger.lean` rows stay hand-kept: the lean.yml row is a different set (named golden files instead of
  `golden/**`, plus CI-only scripts and tests), so it cannot share `checkShReads`.
- A new check.sh read of a non-golden file still needs `LandSpeed.lean` (and the Trigger row) in the task writes
  (golden case "site-layer-opts: a new check.sh read ...").
- `lean/scripts/*Golden.lean` admits any generator script, not only the new one.
- The goldens cover the registration files that the golden set and the generated read list now admit, not every file
  graph r257/r258 widened: `apps/runner/src/land.ts` PACKAGE_EXTRA_READS (site-layer-opts) and `apps/runner/src/fw-main.ts`
  (slot-span-key) still need task writes.
