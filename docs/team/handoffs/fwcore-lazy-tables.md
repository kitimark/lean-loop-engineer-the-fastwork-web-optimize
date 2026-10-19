# fwcore-lazy-tables

## State
- Branch `worktree-wf_c15f8d05-f78-1`. `64b04ef1` adds the CI timing step only (baseline); `42205e01` adds the lazy
  tables and the lint; the commit after it adds this handoff and the note. CI branch `ci/fwcore-lazy-tables`.
- Each start-time constant over 10,000 small allocations is now `def x (_ : Unit := ()) : T`: 85 definitions in 42
  files, plus `Fw.Ops.LeanFirst.instEnumFacts`, which reads `grid ()` inside `enum`. No docstring was touched.

## Verified
- `sh lean/scripts/check.sh` is green at `42205e01`, including the two new jobs `init cost lint` and
  `init cost lint cases`. `node --test scripts/ci-paths.test.mjs` and `apps/runner` `test/land-inputs.test.ts` pass.
- Outputs are byte-identical: every `--check`, plus a before/after dump of partsgolden, ContractsGolden, ShardGolden,
  the wire replay, `--ops` and sweepsgen. Only the `fwtest` timing lines differ.
- CI CPU per spawned call: 812.4 ms before (run 39323151165) and 40.4 ms after (run 39324877968), on the same image.
  Numbers and cause are in `research/notes/2026/10-20-fwcore-startup.md`.

## Conventions
- To make a table lazy, add the parameter `(_ : Unit := ())` and leave call sites as they are. An instance cannot take
  that parameter, so read the table inside the instance's function field instead.
- When the lint fails, it names the constant and its count. Converting a table moves its cost to the first start-time
  constant that forces it, so rerun the lint until it is green.
- `lake env lean scripts/InitCostLint.lean` from `lean/` needs a built `Main` and `.lake/build/ir`.

## Open
- The runner suite's total fwcore CPU was not measured. A persistent `fwcore serve` is task fwcore-serve-runner.
- Lowering `Fw.Lint.InitCost.bound` below 10,000 would list the next tables (the largest left is 9,970).
- The CI timing step in `.github/workflows/lean.yml` may be removed or kept as a span once the lead decides.

## Read first
`lean/Fw/Lint/InitCost.lean`, `lean/Fw/Lint/InitCostScan.lean`, `lean/scripts/check.sh` (init cost jobs), the note.
