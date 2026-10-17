# Handoff: gate-speed-ci

State: branch `worktree-agent-a2051dc7680577d08`, last code commit 3c2deab (CI branch `ci/gate-speed-ci` has the same code). Tool doc: `docs/team/tools/gate-speed.md`.

## What it is
- Lean: `lean/Fw/Ops/Cache.lean` (`cache_sound`, `key_complete`; collision-freeness and "depends only on declared inputs" are explicit premises),
  `lean/Fw/Gate/Schedule.lean` (`graham`, `graham_runs`, lower bounds `sum_le_mul_makespan`, `le_makespan`, `wall_lower`, `wall_upper`, `choose_le_current`,
  `layout_merge_sound` over the real `mergeGateById_eq_unsharded`, `Fixed.two_fewer_jobs`, `work_saved`, `chain_cost`).
- Goldens (generated, `cd lean && lake env lean --run scripts/GateSpeedGolden.lean [--check]`): `packages/contracts/golden/gate/schedule.jsonl` (36 lines: times x free runners 4/8/12/20 x runs 1-3), `golden/ops/cache.jsonl`.
- CI: `.github/scripts/gate-jobs.mjs` (matrix from the golden; `.test.mjs` 7 tests), `cache-key.mjs`, `merge-gate.mjs`, `gate-engine` action (3 caches), `breakpoint-gate.yml`
  (plan inside `site`, 7 gate jobs, one `merge` job that builds fwcore once; inputs `free`, `runs`, `times`, `fw`, `parts`, `engines`; concurrency cancels only the same ref).

## Measured (runs on `ci/gate-speed-ci`; per-job seconds, jobs list `gh run view --json jobs`)
| Run | Layout | Jobs | Wall | Sum of job time | Longest gate job | No-queue critical path |
|---|---|---|---|---|---|---|
| R1 39074271060 | base: 8+8 shards + 2 sweeps jobs, plan, site, 2 merges | 22 | 2837 (queue) | 2333 | 326 | ~470 |
| R2 39077507337 | Lean split, old action | 11 | 636 (queue) | 1649 | 251 | ~395 |
| R3 39078357547 | + caches, cache miss | 11 | 413 | 1759 | 279 | ~400 |
| R4 39079281353 | + plan in site, one merge, caches hit | 9 | 530 (queue 75-160 s) | 1553 | 246 | ~356 |
- Critical path = site 41 + longest gate 246 + merge 69 (R4); wall of R1/R2/R4 is other agents' queueing, so compare per-job durations. Cache hit saves little: WebKit `gate-engine` step 29-38 s (miss 37-65), Chromium 20-27 (no change; the zip is small). apt still runs `update` and dpkg.
- Same results: `engines.*.failures` identical in R1, R3, R4 (Chromium none; WebKit 14 entries with the same part/class/role/key/status). Sample counts of the animated
  parts (`hero.countdown`, `hero.exit`) differ run to run, also between R3 and R4 with the same layout: that is WebKit noise, not the split.

## Open items
- FLAKE found in R2: WebKit phase 0 (`run.mjs` declared-property scan, `page.mjs:163-170`) listed the original nav `opacity` in 3 of 4 jobs; `merge-gate` rightly failed on "header differs". Per-job declared lists depend on page state at scan time. Not fixed here (run.mjs is gate-speed-impl's); more jobs raise the odds.
- Switch the live `times` default to `reduced` once gate-speed-impl wires the 35-stop desktop sweep (chosen plan then has 9-10 gate jobs).
- Lead: add `lake env lean --run scripts/GateSpeedGolden.lean --check` to `FwTestMain` or `lean/check.sh` (not in my write set).
- `.github/scripts/gate-shards.mjs` is now unused; delete it when convenient.
- Caches made on a `ci/*` branch are visible only to that branch; `main` warms its own. No `restore-keys` on purpose (`partial_key_unsound`).
- `free` default 8 is INFERRED from queueing. Merge keeps gate-exit-verdict semantics (exit code kept per engine, step summary written, job fails last, upload under `!cancelled()`).
