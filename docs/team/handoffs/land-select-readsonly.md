# land-select-readsonly (console-builder)

State: branch worktree-wf_95ca6613-c51-1, one commit (see report).

Finding: the static read-set scan (`test/land-inputs.test.ts`, premise `land.readsOnly`) only ran as part of the
`apps/runner` suite, so a land touching only `apps/site` never ran it (undeclared read slipped to main).

Done
- Lean `Fw.Console.LandSpeed`: `scanId`, `posGlobs`, `scanReads`, `withScan`; theorems `scanReads_no_excl`,
  `inScope_scanReads`, `scan_selected` (any changed path in a declared check's scope selects `reads-scan`),
  `scan_not_selected` (precision). All docstrings carry LaTeX. Sample table `scanDecls`, 2 `#guard`s + 1 more.
- Golden `packages/contracts/golden/console/land-speed.jsonl` regenerated with `writeGolden` (36 cases, 2 new select cases).
- `apps/runner/src/land.ts`: `withScan`, `READS_SCAN_ID`, `READS_SCAN_ARGV`; `candidateChecks` appends the scan (its reads =
  all inclusion globs of the other checks); dry land runs the scan when `reads-scan` is selected (was: apps/runner).
- Tests in `apps/runner/test/land-inputs.test.ts` (golden select cases cover the new rows; new test for the site-only change).
- `docs/team/tools/land.md` dry paragraph updated.

Verified: `lake env lean Fw/Console/LandSpeed.lean` clean; `lake build Fw.Console.LandSpeed`; runner tsc + land-inputs,
land-dry, land-parallel vitest; `node --test scripts/ci-paths.test.mjs`. See the report for the full runner suite.

Open
- When `apps/runner` is also selected the scan runs twice (once alone, once inside the suite); dedupe would deviate from the
  Lean table, so left. A real land of a Lean-only change now also runs the scan (cheap, vitest file).
- The scan is the one vitest file, so it needs `pnpm install` done first (checkDeps already orders install first).

Read first: `lean/Fw/Console/LandSpeed.lean` section "The read-set scan", then `candidateChecks` in `apps/runner/src/land.ts`.

Fix round 1 (after the adversarial refusal)
- `scanId` docstring has LaTeX; `scan_not_selected` restated (no table id equals scanId, no changed path in scan scope => scanId not in selectChecks (withScan ds) changed) and proved.
- land-inputs test golden-checks `withScan` and `READS_SCAN_ID` against every golden select row ending in reads-scan.
- dryReads doc (land.ts) and LandDry Stages doc now say "selected when the change selects the reads-scan check (LandSpeed.scan_selected)".
- `sh lean/scripts/check.sh`: exit 0 (all lean/ gates green). Runner suite: only wait-guard flaked under load, passes alone; ci-paths test 32/32.
- Commit: see the fix-round commit on this branch (git log -1).
- Follow-ups: exclude READS_SCAN_ARGV from usesCore; declare the scan's own git ls-files reads.
