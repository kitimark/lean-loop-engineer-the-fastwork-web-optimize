# fwcore-lazy-tables

## State
- Branch `worktree-wf_c15f8d05-f78-1`. `64b04ef1` adds the CI timing step (baseline), `42205e01` the lazy tables and
  the lint, `d938746f` the note. CI branch `ci/fwcore-lazy-tables`.
- Round 2 merged main up to `488b0e41` (latex-strip-c conflicts in 17 files: main's docstrings, the branch's
  signatures) and made main's new `Fw.Wire.Ci.Telemetry.cases` and `goldenText` lazy. Limits added: the scan fails
  closed on a project module with no C file (`noc`, `findings_noC`, `findings_nil_iff`); `start-timing.sh` fails
  unless every reply is the expected one (lean.yml no longer pipes it through `tee`); limit bullets in the note.
- Each start-time constant over 10,000 small allocations is `def x (_ : Unit := ()) : T`, plus
  `Fw.Ops.LeanFirst.instEnumFacts`, which reads `grid ()` inside `enum`.

## Verified
- `sh lean/scripts/check.sh` is green after the round 2 merge, with every `--check` and both init cost jobs.
  `node --test scripts/ci-paths.test.mjs` and `apps/runner` `test/land-inputs.test.ts` pass.
- Round 1 also compared before/after dumps (partsgolden, ContractsGolden, ShardGolden, wire replay, `--ops`,
  sweepsgen): identical. CI CPU per call 812.4 ms -> 40.4 ms (runs 39323151165, 39324877968); see the note.

## Conventions
- To make a table lazy, add `(_ : Unit := ())` and leave call sites alone; an instance reads it inside a field.
- Converting a table moves its cost to the first start-time constant that forces it: rerun the lint until green.
- `lake env lean scripts/InitCostLint.lean` from `lean/` needs a built `Main` and `.lake/build/ir`.

## Open
- Runner suite fwcore CPU unmeasured (task fwcore-serve-runner). Next tables appear if `bound` drops (max 9,970).
- The lint covers 269 of the 2,643 modules `Main` reaches. Toolchain initializers, all of `Lean` included (imported
  by `Fw.Spec.MathFacts`, `Fw.Spec.Reach`, `MathView`), are unmeasured: follow-up, drop `import Lean` from fwcore.
- IO initializers (`initialize`, `@[init]`) are not `_init_` lines; the lint does not see them (none exist today).

Read first: `lean/Fw/Lint/InitCost.lean`, `lean/Fw/Lint/InitCostScan.lean`, `lean/scripts/check.sh` (init cost jobs), the note.
