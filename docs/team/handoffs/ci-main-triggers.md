# Handoff: ci-main-triggers

## State
- Round 1 on branch `worktree-wf_3dd2b320-67f-1`. Not landed. The round-1 commit is the one after 84d84418.
- A `main` push runs only `lean.yml` (guard + `lean`, the Lake cache) and `premise-tests.yml` (guard + `engine`, both engines: the gate-engine caches apt-debs, browsers, hs-zip). All other workflows list `ci/**` only. No workflow has `schedule:`; difftest's nightly cron is gone. `workflow_dispatch` is unchanged.
- `fw ci` now needs a run id or `--branch`. Without either it exits 64 and prints the usage.

## Verified
- Lean `Fw.Ci.Trigger`:
  - `seeders_save_iff`: the seeders save exactly `seededCaches`, the caches that a job of a workflow on main before the task (`mainBefore`) saved.
  - `seeded_caches`, `unseeded_caches`: wktr-zip is the only unseeded cache. Main never seeded it.
  - `mainRuns_iff`, `main_iff_seeder`, `no_crons`, `ci_triggers` (ci/** unchanged).
  - `carries_bare`, `carries_wrap`, `carries_sound`, `withNotMain_none`, `withNotMain_some`: the `if:` form `${{ (e) && (notMainPush) }}`.
- `Fw.Ops.LakeCache.lake_writers`: the Lake rows of `cacheWriters` equal the generated Lake writers.
- Axioms: propext, Classical.choice, Quot.sound only.
- `scripts/ci-paths.mjs --check`:
  - scans the cache writers (actions/cache steps, local actions with input-gated saves) and compares them to Lean `cacheWriters`;
  - rejects any `on.schedule` that differs from the row's crons (all empty);
  - checks the if-form structurally (Lean golden `ifForm`/`ifCheck` lines; tests include `a || b` and `(x) || true`).
- Results: `sh lean/scripts/check.sh` green (24 s); `node --test scripts/ci-paths.test.mjs` 38 pass; .github/scripts + ci-* 67 pass; apps/runner `pnpm -s test` 1044 pass.

## Accepted limits / open
- Gain of the gate-engine seed: WebKit saves up to ~36 s per gate job on a ci branch's first run; Chromium saves ~0 s (MEASURED, gate-speed-ci.md:20).
- The main seed runs only when a main push touches premise-tests inputs. Not in that row: `cache-key.mjs`, `golden/ops/cache.jsonl`, runner image updates.
- The engine matrix of the seeder is not parsed; a cache is named by its `path:` basename.
- `apps/runner/src/fw.ts` mode change (100644 to 100755) is not mine and is left uncommitted.

## Read first
`lean/Fw/Ci/Trigger.lean` section "Main pushes"; `scripts/ci-paths.mjs` `cacheWriters`, `carriesNotMain`, reconcile steps 8-9.
