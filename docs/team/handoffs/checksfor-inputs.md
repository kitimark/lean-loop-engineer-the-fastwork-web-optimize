# checksfor-inputs handoff

**State.** `apps/runner/src/land.ts` now declares an input set per check; `apps/runner/test/land-inputs.test.ts` tests it. Runner tests are green except 2 in `incidents.test.ts` that failed here only because the worktree used the main checkout's `fwcore` (not caused by this task; rerun with a fresh `lean/.lake`). No caching or skipping: lands run the same checks as before.

**API (land.ts).** `Check = {id, argv, reads}`; `candidateChecks(root)` (install, check.sh, each package with a `test` script, in run order); `checksWithReads(root, changed)`; `checksFor` = their argv; `selectChecks` and `inScope` are a TS stand-in for Lean `Fw.Ops.PathCheck.inScope` / `LandSpeed.selectChecks` (marked for Lean replacement); `inputKey(root, reads)` = sha256 over the tracked files the globs select (unused by lands).

**Declared inputs.** install: `pnpm-lock.yaml`, `**/package.json`. check.sh: `lean/**`, `packages/contracts/golden/**`, `apps/site/src/{breakpoints,sweeps}.gen.json`, `scripts/span.sh` (equal to Lean `checkShReads`; the test compares it with the golden). Package test `p`: `p/**`, its `workspace:` deps, and `PACKAGE_EXTRA_READS[p]` (files its tests read, found by the scan).

**Behaviour change (small).** Selection now follows the declared globs: a change to a golden, a generated site file, or a file another package's tests read (for example `apps/console-api/**` selects the runner tests) now selects those checks. Before, only `lean/` selected check.sh and only the package's own directory selected its tests.

**Findings (undeclared reads).**
- 8 packages run the `fwcore` binary, built from `lean/**` (`FWCORE_USERS`). Declaring it makes every Lean change select all 8 suites, so `LEAN_BINARY_READS` is `false`. Lead decides; the premise stays open until then (`land.readsOnly` is false for them).
- `lean/Fw/Plan/Golden.lean:343` reads `docs/team/work-graph.json`, but only in `--write-plan-golden` mode, which check.sh never passes (allowlisted with the reason in the test).
- The scan is static. Not seen: paths built at run time, `git` calls (span.sh records HEAD into timings only, which never decides a verdict), network, environment variables.

**Open items.** Move `inScope`/`selectChecks` to an `fwcore` op (Lean has the spec). Land-prelock and check-dag use `candidateChecks`. Read first: the header of `land-inputs.test.ts`.
