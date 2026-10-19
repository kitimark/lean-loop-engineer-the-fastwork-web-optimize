# Handoff: ci-main-triggers

## State
- Final design round on branch `worktree-wf_3dd2b320-67f-1`, accepted; merge-conflict round merged main (after 7896402f). Not landed.
- Merge: main retired the `mathview-differential` job, so `lean.yml` keeps only guard + `lean`. The Lean guard that named it now checks `engine` in lean.yml; the ci-paths lint test of the notMainPush form uses `premise-tests.yml` `verdict`. `cacheWriters` gained `visual-diff.yml` `port-fonts` (from port-fonts-check); golden regenerated.
- Merge round 2: main brought land-lane (`land.yml` row, `ci/land-*`, kept with `[]` crons; `ci_triggers` lists it) and nav-scroll-hide-check (`visual-diff.yml` `navscroll` saves gate-apt, ms-playwright, hs-zip; added to `cacheWriters`, `seededCaches` unchanged). Goldens and `land.yml` guard comment regenerated.
- A `main` push runs only `lean.yml` (guard + `lean`, the Lake cache) and `premise-tests.yml` (guard + `engine`, both engines: the gate-engine caches apt-debs, browsers, hs-zip). All other workflows list `ci/**` only. Every `on:` holds only `push` and `workflow_dispatch` (Lean `onKeys`); difftest's nightly cron is gone.
- `fw ci` now needs a run id or `--branch`. Without either it exits 64 and prints the usage.

## Verified
- Lean `Fw.Ci.Trigger`:
  - `seeders_save_iff`: the seeders save exactly the caches main seeded before this task (`mainBefore`, `seededCaches`). This is not a fresh inventory of every cache ci/* restores.
  - `seeded_caches`, `unseeded_caches`: wktr-zip is excluded on purpose; main never seeded it.
  - `onKeys_push`, `onKeys_dispatch`, `onKeys_schedule`, `onKeys_iff`, `table_onKeys`: the `on:` allowlist.
  - `mainRuns_iff`, `main_iff_seeder`, `no_crons`, `ci_triggers` (ci/** unchanged).
  - `carries_bare`, `carries_wrap`, `carries_sound`, `withNotMain_none`, `withNotMain_some`: the `if:` form `${{ (e) && (notMainPush) }}`. Standard axioms only.
- `Fw.Ops.LakeCache.lake_writers`: the Lake rows of `cacheWriters` equal the generated Lake writers.
- `scripts/ci-paths.mjs --check`:
  - scans the cache writers (actions/cache steps, local actions with input-gated saves) and compares them to Lean `cacheWriters`;
  - lists every indent-2 key under `on:` (quoted or not, flow or block form) and rejects any key outside the golden row's `onKeys`; a non-key line there is a problem too;
  - checks the if-form structurally (Lean golden `ifForm`/`ifCheck` lines; tests include `a || b` and `(x) || true`).
- Merge round: ci-paths --check green; ci-paths tests 40 pass; runner tsc + ci, ci-triggers, land-inputs 78 pass; check.sh at the merge commit. Round 2: ci-paths --check green, ci-paths tests 40 pass, runner ci + ci-triggers 24 pass.

## Accepted limits / open
- Gain of the gate-engine seed: WebKit saves up to ~36 s per gate job on a ci branch's first run; Chromium saves ~0 s (MEASURED, gate-speed-ci.md:20).
- The main seed runs only when a main push touches premise-tests inputs (now incl. `cache-key.mjs`, `golden/ops/cache.jsonl`). A runner-image update (`$ImageOS-$ImageVersion` in the key) is not tracked: the first ci/* WebKit gate job after one may miss (up to ~36 s).
- wktr-zip is never seeded from main (it never was).
- The engine matrix of the seeder is not parsed; a cache is named by its `path:` basename.

## Read first
`lean/Fw/Ci/Trigger.lean` section "Main pushes"; `scripts/ci-paths.mjs` `cacheWriters`, `carriesNotMain`, `onKeys`, reconcile steps 8-10.
