# Handoff: ci-main-triggers

## State
- Final design round on branch `worktree-wf_3dd2b320-67f-1` (after 28bb1007). Not landed.
- A `main` push runs only `lean.yml` (guard + `lean`, the Lake cache) and `premise-tests.yml` (guard + `engine`, both engines: the gate-engine caches apt-debs, browsers, hs-zip). All other workflows list `ci/**` only. Every `on:` holds only `push` and `workflow_dispatch` (Lean `onKeys`); difftest's nightly cron is gone.
- `fw ci` now needs a run id or `--branch`. Without either it exits 64 and prints the usage.

## Verified
- Lean `Fw.Ci.Trigger`:
  - `seeders_save_iff`: the seeders save exactly the caches main seeded before this task (`mainBefore`, `seededCaches`). This is not a fresh inventory of every cache ci/* restores.
  - `seeded_caches`, `unseeded_caches`: wktr-zip is excluded on purpose; main never seeded it.
  - `onKeys_push`, `onKeys_dispatch`, `onKeys_schedule`, `onKeys_iff`, `table_onKeys`: the `on:` allowlist.
  - `mainRuns_iff`, `main_iff_seeder`, `no_crons`, `ci_triggers` (ci/** unchanged).
  - `carries_bare`, `carries_wrap`, `carries_sound`, `withNotMain_none`, `withNotMain_some`: the `if:` form `${{ (e) && (notMainPush) }}`.
- `Fw.Ops.LakeCache.lake_writers`: the Lake rows of `cacheWriters` equal the generated Lake writers.
- Axioms: propext, Classical.choice, Quot.sound only.
- `scripts/ci-paths.mjs --check`:
  - scans the cache writers (actions/cache steps, local actions with input-gated saves) and compares them to Lean `cacheWriters`;
  - lists every indent-2 key under `on:` (quoted or not, flow or block form) and rejects any key outside the golden row's `onKeys`; a non-key line there is a problem too;
  - checks the if-form structurally (Lean golden `ifForm`/`ifCheck` lines; tests include `a || b` and `(x) || true`).
- Results: see the final report (check.sh, ci-paths 40 tests, runner suite).

## Accepted limits / open
- Gain of the gate-engine seed: WebKit saves up to ~36 s per gate job on a ci branch's first run; Chromium saves ~0 s (MEASURED, gate-speed-ci.md:20).
- The main seed runs only when a main push touches premise-tests inputs (now incl. `cache-key.mjs`, `golden/ops/cache.jsonl`). A runner-image update (`$ImageOS-$ImageVersion` in the key) is not tracked: the first ci/* WebKit gate job after one may miss (up to ~36 s).
- wktr-zip is never seeded from main (it never was).
- The engine matrix of the seeder is not parsed; a cache is named by its `path:` basename.
- `apps/runner/src/fw.ts`: the index and main already hold 100644; the stray +x bit in the worktree was cleared, so no commit was needed.

## Read first
`lean/Fw/Ci/Trigger.lean` section "Main pushes"; `scripts/ci-paths.mjs` `cacheWriters`, `carriesNotMain`, `onKeys`, reconcile steps 8-10.
