# node-worker-budget (lean-prover)

State: branch worktree-wf_f48889d4-126-1; see `git log main..HEAD`. check.sh green; runner land-inputs, node-budget,
console-api, site and ci-paths tests green.

What it does:
- `lean/Fw/Sched/NodeBudget.lean`: `workers r = max 1 (min (cores / pool) (freeMiB / (pool * workerMiB)))`; `today` room
  8 cores, 1024 MiB test budget (chosen, not measured), 115 MiB per worker (upper end of the MEASURED 95-115 MiB p50), pool 4: 2.
- Theorems: `workers_pos`, `workers_floor`, `workers_fit`, `workers_pool_gt_cores`, `pool_within_room` (replicate sums over the
  pool within cores and free memory, given pool <= cores and pool * workerMiB <= freeMiB), `monotone` (cores, memory),
  `antitone_demand` (pool, workerMiB), `today_workers`, `today_pool_sum` (= 8).
- `lean/scripts/NodeBudgetGolden.lean [--check]` writes `packages/contracts/golden/sched/node-budget.gen.json` (room, workers,
  byPool 1..8) and `node-budget.jsonl` (360 rows); check.sh job "node-budget golden check".
- Readers: the three vitest configs (`maxWorkers`), root package.json `test` (`--test-concurrency=${VITEST_MAX_WORKERS:-gen}`),
  `fw land` (`testWorkersEnv(cwd, pool)` sets `VITEST_MAX_WORKERS` per check from byPool; test `apps/runner/test/node-budget.test.ts`).

Deviations from the graph writes:
- The gen file lives in `packages/contracts/golden/sched/` (precedent lake-slot.gen.sh), not `packages/contracts/src/`: check.sh
  reads it and `golden/**` is already in `checkShReads`; `src/` would need a LandSpeed.lean + proof + golden change.
- Extra write `apps/runner/test/node-budget.test.ts` (replays the golden through `testWorkersEnv`).

Open:
- Package-level `node --test` scripts (12 packages/*/package.json and apps/site) do not read the budget yet: node rejects
  `--test-concurrency` in NODE_OPTIONS (MEASURED, node 24.22.0), so each script needs the argv; outside this task's writes.
- vitest 5.0.5 has no `minWorkers` option (grep of dist finds none); only `maxWorkers` is set.
- Live room from the daemon ledger: follow-up sup-tests.
- reap-stop / reap-safety tests fail in this sandbox (`gather` returns null: lsof/ps of other processes); untouched by this task.

Debug run, not a result (console-api vitest, once each, load 15-21, /usr/bin/time -l + 0.5 s ps tree-RSS sampler):
cap 2: 65.9 s wall, 75.0 CPU-s, peak tree RSS 733 MiB; 7 workers: 26.9 s, 74.6 CPU-s, 1524 MiB. time -l maxrss 205 MiB both.
