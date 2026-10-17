# Handoff: mutants-ci

State: the M0 mutation pass runs on GitHub Actions (`.github/workflows/mutants.yml`), commit e34882c and later on
branch `worktree-agent-a966e67858251bd9e`, verified through branch `ci/mutants-ci` (run ids in the lead's report).

What exists:
- `mutants.yml`: push on `ci/**` and `main` (paths: the 9 M0 modules, `lean/FwTest/Mutants/**`,
  `lean/scripts/mutants.sh`, setup-lean, the workflow) plus `workflow_dispatch` with inputs `tag` (ci),
  `jobs` (workers per shard, 2), `shards` (8), `limit` (mutants per shard, 0 = all; a smoke run).
  Jobs: `plan` (checks the inputs, lists the shards) → `shard` matrix (ubuntu-24.04-arm, setup-lean, node 24,
  `mutants.sh -S i/n`) → `merge` (`mutants.sh -m`, step summary, artifact `mutants-<tag>-summary`).
- `mutants.sh -S i/n`: shard i of n = the mutants whose FNV-1a hash of `file<TAB>id` is i mod n
  (`gen.mjs shard`). Order: `-p`/`-i` filter (pool) → shard → `-n` cut. Writes `meta.tsv`
  (shard n pool todo limit done) and `summary.txt`; exits 1 if a verdict is missing.
- `mutants.sh -m [-r tag] <dir>...`: merges shard dirs; fails on a survivor, a missing or doubled shard, a shard
  with missing verdicts, or (without `-n`) shards that do not add up to the pool.
- Linux: `cp -a --reflink=auto` instead of `cp -c` (GNU `cp -c` means `--preserve=context`, so it picks by
  `uname`), no `sed -i`; checked with `shellcheck --shell=dash` and `actionlint`.

Conventions: the baseline is still built from scratch per shard with Lake's artifact cache off, so mutant
artifacts never reach the `.lake-cache` that setup-lean saves. Never run the full pass locally; read results with
`gh run view <id>` / `gh run download <id> -n mutants-ci-summary`.

MEASURED (633 mutants; local m0-mutants pass: 23 min wall at load ~500):
| run | shards x workers | wall | slowest shard | worker-s | note |
|---|---|---|---|---|---|
| 39039184087 | 8 x 2 | 22 min | 17 min | 10698 | |
| 39040896166 | 16 x 3 | 21 min | 10 min | 11845 | shards queued for runners (other agents' runs) |
| 39042494239 | 8 x 4 (default) | 13.3 min | 13 min | 14040 | no queueing |
Per shard: setup about 30 s, baseline 80-90 s. Raise `shards` when runners are idle; 16 x 3 would give about 9 min.

Open items:
- All 3 runs: 631 killed/stillborn/equivalent, 2 survived, both stale entries of `equivalent.tsv`: Fw/Wire.lean
  `samples` "error" literals moved from 480:36 / 482:53 to 500:36 / 502:53 (same reasons). Update those two ids
  (not in this task's write set); then the run should go green.
- Imbalance: Fw/Ops/Wire.lean mutants cost about 58 s each (most die at `lake test`), others 3-22 s.

Read first: the `mutants.sh` header, then `mutants.yml`.
