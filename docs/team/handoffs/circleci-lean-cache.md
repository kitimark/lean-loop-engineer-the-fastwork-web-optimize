# Handoff: circleci-lean-cache

Branch `worktree-wf_9aef738e-414-1`. Read first: `research/notes/2026/10-2x-circleci-lean-cache.md` (tables, verdict, limits).

## State
- The CircleCI land job restores/saves a Lake cache: `.circleci/config.yml` (land job steps `lake-key`, `restore_cache`, `lake-probe`, `lake-gate`,
  `save_cache`) and `.circleci/job.sh` (cases `lake-key`, `lake-probe`, `lake-gate`). Key rule like setup-lean; saved only when the key changes.
- Lean: `Fw.Ci.Provider.landJobs` + `savesCacheJob` theorems per land job, `Overflow.landJobs_eq_legs`, `ProviderGolden` row; golden
  `packages/contracts/golden/ci/provider.jsonl` regenerated. `scripts/circleci.mjs` reads `landJobs` from the golden (no new decision logic).
- Writes outside the task paths: those Lean files, the golden, `scripts/circleci.mjs`, `scripts/circleci.test.mjs`, docs `land.md`, `circleci.md`.
- TS stand-ins: none new. `job.sh` is shell glue (hashes, marker compare, `step halt`).

## Verified
- MEASURED on CI, 4 of 6 pipelines (arm.medium.gen2): cold dc8f3e2e (#310), warm 4c414d39 (#312), warm 8c1d9994 (#313), source change 2881e5a2 (#314).
  Cold `fwcore build` 353-374 s -> warm 0.1 s -> partial hit 15 s. Legs 420-576 s -> 48-215 s. GitHub twin run 39619679268.
- `node --test scripts/circleci.test.mjs`, `scripts/ci-paths.test.mjs`, apps/runner `pnpm test`, `sh lean/scripts/check.sh` green at the final commit.

## Open
- apps/runner `test/next.test.ts` "sleepLoop owned by the session" flaked once (#313): `obs.health ... startedAt: expected a non-negative integer`.
- Storage grows one ~292 MiB entry per distinct Lean source tree (307 milli GB-month at the 30-day bound); a save-count rule is a follow-up.
- Branch `ci/circleci-lean-cache-src` and the marker on `ci/land-circleci-lean-cache` are probes, not for main.

## Conventions
- CircleCI only through `scripts/circleci.mjs` (Keychain token); never print slug or token. Arm Linux only, no macOS.
- Each measurement used one pipeline per cold/warm/probe; wait with `pnpm -s fw ci wait --provider circleci --pipeline <id> --out <dir>`.
Scope: landed with --allow for docs/team/tools/{circleci,land}.md, lean/Fw/Ci/{Overflow,Provider}.lean and lean/scripts/ProviderGolden.lean: without Lean landJobs the storage ledger would not count a land save.
