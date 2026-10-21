# node-worker-budget (lean-prover, round 2)

State: branch worktree-wf_f48889d4-126-1, main merged; see `git log main..HEAD`. check.sh exit 0 (node-budget golden check green).

What it does:
- `lean/Fw/Sched/NodeBudget.lean`: `workers r = max 1 (fit r)`, `fit r = min (cores - reserveCores) (min (cores / pool) (freeMiB / (pool * workerMiB)))`.
- Room `today`: cores 8; reserveCores 1 (old default of vitest and node --test, `availableParallelism - 1`, CONFIRMED Node docs);
  freeMiB 2048 = `Fw.Sched.Heavy.Params.reserveMB` (cited rule, INFERRED: that reserve is chosen, not measured; follow-up sup-baseline);
  workerMiB 136 (MEASURED in the graph task: (1486 - 808) / 5 MiB, rounded up); pool 4: 2 workers. byPool 1..8: 7,4,2,2,1,1,1,1.
- Memory binds at no pool of today's room (`#guard`): cores and the reserve set the values, not the 2048 MiB.
- Theorems: earlier ones kept (`workers_pos`, `workers_floor`, `workers_fit`, `workers_pool_gt_cores`, `pool_within_room`, `monotone`,
  `antitone_demand`, `today_workers` = 2, `today_pool_sum` = 8; monotone/antitone now also hold reserveCores fixed); new
  `workers_le_reserve`, `workers_le_old_default` (reserve 1, cores >= 2: workers <= cores - 1), `today_le_old_default` (every pool), `today_alone` = 7.
- `lean/scripts/NodeBudgetGolden.lean [--check]` writes `packages/contracts/golden/sched/node-budget.gen.json` and `node-budget.jsonl` (720 rows).

Readers per check fw land runs:
- vitest (apps/runner, apps/console-api, apps/site, apps/console-web, packages/contracts): `VITEST_MAX_WORKERS` from `testWorkersEnv(cwd, pool)`
  in `runCheck` (land.ts); runner, console-api and site configs also set `maxWorkers` from the gen file outside fw land.
- node --test (apps/site, packages/{difftest,e2e-preview,engine-check,gate-breakpoints,gh-budget,measure-chromium,measure-webkit,
  measure-wktr,premise-tests,snapshot-extract,visual-diff}): `--test-concurrency=${VITEST_MAX_WORKERS:-<gen workers>}` in the test script.
- Every package check declares the gen file as a read (land.ts candidateChecks). `apps/runner/test/node-budget.test.ts` checks every
  node --test script fw land runs carries the flag with a path to the gen file.
- Root `package.json` `test` is back to main: its single-file node --test gains nothing from the flag, and fw land never runs it.

Debug run, not a result (gate-breakpoints, 25 files, load 17-18, ps sample every 0.1 s): pnpm test with VITEST_MAX_WORKERS=2: at most
2 node --test children, 21.5 s; plain `node --test` without the flag: 7 children, 12.9 s.

Open: live room from the daemon ledger (sup-tests); memory footprint of tests beside a heavy job (sup-baseline). Suites may run slower.
