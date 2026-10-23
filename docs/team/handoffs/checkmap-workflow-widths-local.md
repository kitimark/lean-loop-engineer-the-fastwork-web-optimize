branch: worktree-wf_4e3726a1-e6b-1
worktree: .claude/worktrees/wf_4e3726a1-e6b-1
last commit: see `git log -1`; CI runs: none (accepted limit: no CI run)

# checkmap-workflow-widths-local

State: done. Any change under `.github/workflows/` selects the local check `runner:overflow-widths`
(`pnpm --filter ./apps/runner exec vitest run test/land-overflow-widths.test.ts`) in `fw land --dry`; the dry land refuses a stale
width row (path-pix 4 -> 6 case).

Where it lives (the task text said CheckMap.lean; that file is the pre-commit map and has no land tiers, so the rule is in the land tier module):
- `lean/Fw/Console/LandTier.lean`: `overflowWidthsId`, `overflowWidthsReads`, `localTests` row, theorem `workflow_selects_overflowWidths`
  (every path `.github/workflows/<r>` with `".." not in r`), `overflowWidths_local`, `overflowWidths_core_user`, `#guard`s, 5 golden rows.
- `packages/contracts/golden/console/land-tier-local.jsonl` (regenerated: `cd lean && lake build Fw.Console.LandTier && lake env lean --run scripts/LandTierGolden.lean --write`; build first, `lean --run` reads the compiled olean).
- TS stand-in (checked against that golden by `land-tier.test.ts`): `LOCAL_TESTS`, `OVERFLOW_WIDTHS_READS`, `FWCORE_USERS` in `apps/runner/src/land.ts`.
- Tests: `land-tier.test.ts` (every workflow file selects it), `land-dry.test.ts` (path-pix case refused with the test's failure text, `VERDICT lint`), `land-scope.test.ts` (Lean change selects both local tests).
- Incident `inc-workflow-widths-remote` in `docs/team/incidents/ledger.json` (`fw incidents lint`: 0 errors). Doc: `docs/team/tools/land.md` local tests section.

Verified: lean/scripts/check.sh green; apps/runner full test passed except the land-scope case fixed afterwards (re-run of land-scope + overflow test green);
ci-paths test 56 pass. MEASURED: the overflow test is about 10 s wall (vitest 10.3 s), added to a dry land that touches a workflow or
Lean overflow table; a Lean change also selects it (fwcore binary read) and was already building fwcore.

Open / follow-up: the stand-in failure text in the dry-land test is not the real test run (the real test is run by the land); a
dynamic-matrix bound elsewhere (new planner script outside `.github/scripts/**`, `packages/gate-breakpoints/src/trajectory/**`) must be added to `overflowWidthsReads` (Lean) and `OVERFLOW_WIDTHS_READS` (TS).
Writes: LandTier.lean, land-tier-local.jsonl, land.ts, land-dry/land-tier/land-scope tests, ledger.json, land.md.
Read first: `lean/Fw/Console/LandTier.lean` section "Local tests".
