# Handoff: ci-main-triggers

## State
- Code commit 14a17b94 on branch `worktree-wf_3dd2b320-67f-1`. Not landed.
- A push to `main` now runs only `lean.yml` jobs `guard` and `lean`. The `lean` job writes the Lake cache.
- Every other workflow has `on.push.branches: ['ci/**']`. `workflow_dispatch` is unchanged everywhere.

## Verified
- Lean (`Fw.Ci.Trigger`):
  - `main_iff_seeder`: a workflow lists main exactly when it holds a seeder.
  - `mainRuns_iff`: on a main push, a job runs exactly when it is a seeder, or it is the `guard` job of a seeder workflow.
  - `branches_split` and `ci_triggers`: the ci/** trigger set equals the old table.
- Lean (`Fw.Ops.LakeCache`): `seeders_are_writers` says the seeders equal the jobs that save the Lake cache.
- Axioms are standard only.
- `sh lean/scripts/check.sh` is green. `ci-paths --check` is green. `node --test` on the ci-paths, .github/scripts and ci-* suites shows 63 pass.
- `apps/runner` `pnpm -s test`: 1044 pass.

## Design
- Cache scope: a run restores caches from its own branch and from the default branch (GitHub docs, dependency caching, "Restrictions for accessing a cache").
- Only the Lake cache is seeded from main.
- The gate-engine actions/cache entries (apt-debs, browsers, hs-zip) are not seeded from main. Each ci branch saves its own entry on its first miss.
- Gain from those caches is small: a hit saves 0-27 s (MEASURED, docs/team/handoffs/gate-speed-ci.md:20).
- `lean.yml` job `mathview-differential` carries the `notMainPush` conjunct in its `if:`. `scripts/ci-paths.mjs` (reconcile step 8) enforces and writes this conjunct for every non-seeder job of a workflow that lists main.

## Readers of main-run results (none broken, none changed)
- `fw ci` (apps/runner/src/ci.ts) defaults to `--branch main` with chromium-counts. It now finds a stale run, and later none. Pass `--branch ci/<x>` or a run id instead.
- timing-ci backfill and watch-collect list runs without a branch filter. They only lose the main samples.
- `run.ts` latestRun, the gh-budget poller and wait all filter on the ci ref, so they are unaffected.
- docs/team/tools/gate-speed.md:41 ("main runs warm their own") and docs/team/tools/fw-ci.md:3,74 are now stale.

## Open items
- Optionally make premise-tests `engine` a seeder, so main warms the gate-engine caches. That means adding it to `seeders`; the LakeCache theorem would then need a split.
- Change the `fw ci` default branch.
- Fix the stale doc lines listed above.
- The mode change on `apps/runner/src/fw.ts` (100644 to 100755) in the worktree is not mine. It is left uncommitted.

## Read first
- lean/Fw/Ci/Trigger.lean, section "Main pushes"
- scripts/ci-paths.mjs: `withNotMain` and reconcile step 8
