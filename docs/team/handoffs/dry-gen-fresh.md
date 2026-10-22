# dry-gen-fresh

- Branch `worktree-wf_fcfd62cf-5a2-1`, worktree `.claude/worktrees/wf_fcfd62cf-5a2-1`, work commit eed91fab plus a docstring fix and
  this note (see `git log`). No CI run (no measurement in this task).
- Verified locally: `lean/scripts/check.sh` green (goldens, wire replies, axioms), runner 2444, console-api 769, console-web 110
  tests pass, typecheck of the three packages clean, `scripts/ci-paths.test.mjs` 54 pass.

## What changed
- `lean/Fw/Console/LandDry.lean`: lint `footprint` (`part-footprint.mjs --check`), `footprintInput`, `lintPlan` with
  `hasFootprint`; theorems `footprint_mem_plan`, `gen_selected`, `lintPlan_old`, `lintPlan_noScript`, `gen_stale_refuses`,
  `dry_pass_land_pass_planned`, `dry_refusal_is_land_refusal_planned`. Golden `packages/contracts/golden/console/land-dry.jsonl`
  (198 cases) from `scripts/LandDryGolden.lean`.
- TS mirror: `apps/runner/src/land-verdict.ts` (`footprintInput`, `lintPlan`), `apps/runner/src/land.ts` (passes the script's
  existence); fixture test in `apps/runner/test/land-dry.test.ts` (part edit with a stale footprint gives `VERDICT lint`).
- `lean/Fw/Console/ReviewInfo.lean`: excerpts are `anchor` + `span`; `locate` (theorems `locate_at`, `locate_missing`,
  `locate_twice`, `locate_outside`, `locate_shift`). Wire op `console.reviewExcerpt` in `lean/Fw/Wire/ReviewInfo.lean` and
  `lean/Fw/Wire/Console.lean` (outside the graph writes; dry land needs `--allow` for both).
- `apps/console-api/src/review/info.ts` reads the file and asks Lean for the range; tests in `apps/console-api/test/review-info.test.ts`.
- Fixture `apps/console-web/test/fixtures/review-info.earn.json` is the fwcore reply to `console.reviewInfo` for
  `nav:earn-no-transition`, printed with `json.dumps(indent=1, sort_keys=True, ensure_ascii=False)`.

## Open
- `apps/console-web/src/ReviewInfo.tsx` still types `first`/`last` on every excerpt and prints `file:undefined` for a refused one.
- `earnMechanism` prose still cites absolute line numbers.
- ContractsGolden `--check` outputs (footprint-diff, FootprintRows) are not a dry lint yet.
- The footprint lint needs `pnpm install` in the dry worktree (vite); an install failure shows as a lint refusal.

Read first: `docs/team/tools/land.md` section "The dry land's fast lints", then `LandDry.lean` `lintPlan`.
