# land-inputs-growth handoff

Branch worktree-wf_d436ffb0-499-1, worktree .claude/worktrees/wf_d436ffb0-499-1.
Last commit: see `git log -1` (merge of main f632aa354 plus this handoff). CI runs: none pushed (local-machine task, no CI lane).

## State
- Cause (MEASURED): the fixture test of `apps/runner/test/land-inputs.test.ts` calls `inputKey` 1867 times; each call
  spawned `git ls-files` (8 ms) and ran the original `inScope` (globs split again per path, 335 ns per file-glob pair).
  Step 37.1 / 34.7 s -> 7.4 / 7.2 s; fixture test 26.3 / 24.3 s -> 1.56 / 1.58 s; real-key test 3.9 -> 1.1 s.
- Fix: `apps/runner/src/land-inputs.ts` (`scopeOf`, `compileScope`, `trackedFiles`); `land.ts` imports them (inScope, inputKey).
- Lean: `lean/Fw/Obs/LandInputsCost.lean` (cost model, theorems, six measured rows within 35 percent), golden
  `packages/contracts/golden/obs/land-inputs-cost.jsonl` (rendered by a scratch `main` over `rowJson`), replayed in the test.
- Note: `research/notes/2026/10-2x-land-inputs-growth.md`. Scratch data: scratchpad/lig/.
- Verified: runner package test 105 files / 3370 tests green; ci-paths test 56 green; plan lint has no writesClosure line for this task.

## Open
- Round 2 done: oracle title says every fifth path; bench outputs and INFERRED fixedUs in note + Lean docstring; `rows_predMs`; `lean/scripts/LandInputsCostGolden.lean` + check.sh row. check.sh green, runner test 106 files/3402 green, plain dry land VERDICT dry.
- Findings 6-8 stay follow-ups.
- Superset test (2.7 s) reads package.json per path; follow-up.
- Effect on alerts: read on later dry lands (land-inputs vitest p50 after landing).

## Read first
The note, then `land-inputs.ts`, then the oracle tests at the end of `land-inputs.test.ts`.
