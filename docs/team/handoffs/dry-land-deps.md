# dry-land-deps handoff

- Branch: worktree-wf_0db9698f-0bf-1; worktree: .claude/worktrees/wf_0db9698f-0bf-1; work commit 0c51a0143 (+ this handoff).
- CI runs: none (Lean and golden only; no CI push needed).
- Verified: `sh lean/scripts/check.sh` green at 0c51a0143 (axiom check included); packages/contracts test 11/11;
  `node --test scripts/ci-paths.test.mjs` 56/56; apps/runner test/land-inputs.test.ts 73/73.
- Done: lean/Fw/Ops/LandDry.lean and LandDryGolden.lean taken from dfa8a1815 (`git checkout`); `import Fw.Ops.LandDryGolden`
  in lean/Fw.lean. Kind and buildsLake docstrings name both fwcoreBuild command lines (fwcore-build.sh and check.sh,
  check.sh:37). Waves docstring replaced with the reviewer's text. New deps golden row and `#guard`s for a plan holding
  check.sh and the build script as two fwcoreBuild checks. deps, lake_serial, core_after_builds, install_first,
  kindDep_rank unchanged.
- Goldens: packages/contracts/golden/ops/land-dry.jsonl (8 rows), land-dry-deps.jsonl (13 rows); regenerated with a
  scratch `lake -d lean env lean --run` script calling `Fw.Ops.LandDry.jsonl`/`depsJsonl`; the `#guard`s in
  LandDryGolden.lean fail when stale.
- Note: research/notes/2026/11-01-dry-land-deps.md (rule, theorems, threat model).
- Open (next task dry-land-wiring): TS `checkKind` must map `["sh","lean/scripts/check.sh"]` to fwcoreBuild; the TS
  test in dfa8a1815 apps/runner/test/land-parallel.test.ts checks every deps row, so it must accept the 13th row.
- Read first: LandDry.lean:96-180, then the note.
