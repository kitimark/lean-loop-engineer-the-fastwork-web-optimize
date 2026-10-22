# land-tier-compose-test handoff

State: branch worktree-wf_1619d88e-e92-1. The local land tier selects a test file from its declared read set; compose.test is the first.

- Lean: `lean/Fw/Console/LandTier.lean` section "Local tests" (`composeReads`, `localTests`, `selectLocal`, `selects_reader`,
  `selects_only_reader`, `compose_reader_selected`, `compose_local`, `compose_core_user`, `#guard` cases). `console-api:compose` is also in `fwcoreUsers`.
  Concrete-path theorems by `decide` do not reduce (glob matching on strings), so concrete paths are `#guard`s plus the golden.
- Golden: `packages/contracts/golden/console/land-tier-local.jsonl` (generated: `cd lean && lake env lean --run scripts/LandTierGolden.lean`).
- TS: `apps/runner/src/land.ts` `LOCAL_TESTS`, `COMPOSE_READS`, `candidateChecks`, dry-land step after the fast lints (TS stand-in:
  failure is kind `lint`; real land says `checks`). Test `apps/runner/test/land-tier.test.ts`; land-inputs and land-scope tests updated.
- Docs: `docs/team/tools/land.md` last section; incident `inc-local-tier-misses-compose` (class c-late-check, three run ids).
- Open: generated read sets; more local tests (add a row to `localTests` + `LOCAL_TESTS`, regenerate golden); Lean `lintPlan` could list the step.
- Read first: LandTier.lean "Local tests", land.ts `LOCAL_TESTS`.
