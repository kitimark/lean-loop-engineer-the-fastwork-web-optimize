# ts-lean-diff handoff
State: packages/difftest (fast-check + one fwcore child per file), .github/workflows/difftest.yml, docs/team/tools/difftest.md.
Covered ops and the Lean-first inventory: see the tool doc. 13 tests incl. a negative control, all green locally.
Conventions: ESM .mjs, node:test, fwcore from FW_CORE_BIN; pnpm-lock.yaml gained the new importer (needed for frozen install).
Open items (follow-up tasks): Lean wire op `parts.eval`; wire ops for `Fw.Plan.Workflow` and `syncFrom`; flags.resolve
differential (needs a TS resolve hook + registry mapper); trace splits generator; Lean specs for parseMemLevel, ci-wait verdict,
classifyTree, judgeDevice X/S/pass, wktr reduce, shells model.
Read first: docs/team/tools/difftest.md, packages/difftest/src/diff.mjs.
