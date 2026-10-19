# land-fwcore-key handoff

## State
Branch `worktree-wf_f4119fe3-e43-1`. Commits: 469dc603 (Lean and goldens), 81546e47 (TS), then a merge of main (a03e4aee, latex-lint-relax).

## Premise `land.binaryOfLean` (MEASURED)
A docstring-only edit to a Lean module, followed by `sh scripts/fwcore-build.sh`, leaves the stripped fwcore sha256 unchanged (f2a2d9bd08c1...). Reverting the edit leaves it unchanged as well. Lake regenerates the module's `.c` byte for byte, so the `.o` and the linked binary stay the same.

## What is verified
- `lean/Fw/Console/LandSpeed.lean` defines `fwcoreBin`, `fwcoreBuildReads`, `digestDiffers`, `binMoved`, `withBin` and `selectTwoPhase`.
  - One theorem per branch of `binMoved`: `binMoved_unbuilt`, `_main_unknown`, `_merge_unknown`, `_differ`, `_same`, and `binMoved_iff`.
  - `fwcore_digest_skip` and `fwcore_nobuild_skip` are instances of `skip_sound`. The second rests on `BinaryOfBuildReads`, which is premise row `land.binaryOfLean`.
  - There are 9 `landSpeed.select2` golden cases.
- `apps/runner/src/land.ts`:
  - `binMoved` and `selectTwoPhase` mirror Lean and are checked against the select2 goldens in `test/land-inputs.test.ts`.
  - Each fwcore user declares `FWCORE_BIN` in place of `lean/**`.
  - `fw land` (pre-lock) runs `twoPhaseChecks`. Phase 1 runs `scripts/fwcore-build.sh` in the merge-tree worktree, and only when the change touches `FWCORE_BUILD_READS`.
  - Phase 2 compares main0's digest with the merge build's digest. main0's digest is stored per commit under `<git-common-dir>/fw-land/fwcore-digest/`; when no stored value exists it is seeded from the main checkout's `fwcore.commit` record.
  - A failed build, a dirty `lean/` tree or a missing digest counts as unknown, and unknown selects every fwcore user.
- Explicit Lean source reads: console-api (PreviewFacts.lean), measure-chromium (Store/Layout.lean, Faithful/Measured.lean) and apps/site (Parts/HiddenPause.lean, Parts/HeroCountdownHidden.lean). The apps/site pair was a gap the new scan found.
- apps/runner and gate-breakpoints keep `lean/**`, because they walk Lean sources or spawn `lake`.
- The new test in `land-inputs.test.ts` requires quoted `lean/...lean` paths to be declared, and requires packages that spawn lake to declare `lean/**`. Its exception tables are `LEAN_NAMED_NOT_READ` and `LAKE_NOT_IN_TEST`.
- Test runs: apps/runner `pnpm test` passes (1055 tests), and `node --test scripts/ci-paths.test.mjs` passes (32 tests).

## Open items
- These were accepted as limits for this task: check.sh rows, the key cache, the CI land lane and the builder preamble.
- TS stand-in: the `twoPhaseChecks` glue and the `storedDigest` seeding are unproved I/O.
- Phase 1 runs in series before the other checks.
- Only the pre-lock path uses digests. The other paths call `checksFor`, which treats digests as unknown (conservative).
- The module doc's op list does not mention `select2`.

## Read first
`lean/Fw/Console/LandSpeed.lean` (the section after `scanDecls`), `apps/runner/src/land.ts` (`twoPhaseChecks`, `storedDigest`).
