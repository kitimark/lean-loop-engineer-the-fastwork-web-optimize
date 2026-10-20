# Gate speed (CI structure)

Task `gate-speed-ci`. Source of the problem: `research/notes/2026/10-18-sweeps-speed.md` (sections A and C): the Free plan runs 20
jobs for the whole account, one gate run started 22, and about 830 s of the 1284 s wall in run 39067656223 was queueing.

## What changed

| Piece | File | Lean |
|---|---|---|
| Job split: how many jobs per engine, which probes and which whole sweeps each | `.github/scripts/gate-jobs.mjs`, matrix from `packages/contracts/golden/gate/schedule.jsonl` | `Fw.Gate.Schedule.choose`, `choose_le_current`, `graham_runs`, `layout_merge_sound` |
| Merge of jobs that hold probes and sweeps together | `.github/scripts/merge-gate.mjs` | `Fw.Gate.mergeGateById_eq_unsharded` (sweeps-lean), used by `layout_merge_sound` |
| Cache of the engine install | `.github/actions/gate-engine/action.yml`, keys by `.github/scripts/cache-key.mjs` | `Fw.Ops.Cache.cache_sound`, `key_complete` |
| Plan folded into the site job, one merge job (fwcore built once) | `.github/workflows/breakpoint-gate.yml` | `Fw.Gate.Schedule.Fixed.two_fewer_jobs`, `work_saved`, `chain_cost` |
| Concurrency group | `.github/workflows/breakpoint-gate.yml` | none (glue) |

Goldens (generated, never by hand): `cd lean && lake env lean --run scripts/GateSpeedGolden.lean [--check]` writes
`packages/contracts/golden/gate/schedule.jsonl` and `packages/contracts/golden/ops/cache.jsonl` from `lean/Fw/Wire/GateSpeedGolden.lean`.
Tests: `node --test .github/scripts/gate-jobs.test.mjs` (golden invariants, matrix coverage, cache-key agreement, merge failures).

## The split

- Free runners: the pool is 20 for the whole account, so a run sees `m` free runners, not 20. `choose P m r` is called for `m` in 4, 8, 12, 20
  (input `free`, default 8). Wall time `W = pre + makespan(m, r copies of the gate jobs) + post` is bounded below by `max(chain, work/m)`
  (`wall_lower`, with `sum_le_mul_makespan` and `le_makespan`) and above by the chain plus Graham's term (`wall_upper`). Fewer free runners choose fewer jobs.
- The model: a plan gives each engine `k` probe jobs (probes dealt by matrix index mod `k`) and a sweep mode (`sep`: one extra job with all four
  sweeps, as before; `deskSep`: the desktop sweep alone, the three short sweeps on probe jobs; `inline`: no extra job). `choose P m r` takes the
  plan with the smallest Graham bound `r*sum(d) + (m-1)*max(d)` (that is `m` times the bound on the makespan of `r` concurrent runs on `m = 20` slots)
  among 2304 plans; ties keep the current plan, so it is never worse (`choose_le_current`, for any times).
- Times are parameters (`noteBase`, `noteCached`, `noteReduced` in `Schedule.lean`, from the note); the live matrix uses `cached` (input `times`).
  When `gate-speed-impl` wires the 35-stop desktop sweep into `run.mjs`, switch the default to `reduced`: the chosen plan then has 9 to 10 jobs.
- Never splits a sweep: each stop's verdict depends on the whole collapsed history (`split_sweep_changes_verdict`).
- Dispatch inputs: `runs` (1 to 3, default 2), `free` (4, 8, 12, 20; default 8), `times` (default cached), `fw`, `parts`, `engines` as before; `shards` is gone (Lean decides).

## Caches

- Three caches in the `gate-engine` action: apt `.deb` files (copied to and from `/var/cache/apt/archives`), the Playwright browser directory (WebKit),
  the Chrome Headless Shell zip (Chromium; the sha256 check still runs). Key = prefix + SHA-256 of the declared inputs (Playwright version, Ubuntu release, architecture, engine; or HS version, HS sha256, architecture). `cache-key.mjs` refuses a missing or an undeclared input.
- No `restore-keys`: a partial key is not covered by `key_complete` (`partial_key_unsound`).
- Premises Lean cannot prove (written in `Cache.lean`): SHA-256 has no collision among the vectors used; the install reads only the declared inputs.
- The Ubuntu release (`$ImageOS`) is a declared input: playwright-core downloads a different WebKit build per release into a directory named by revision only. The runner image version (`$ImageVersion`) is not: the fleet runs two image versions at once, and a key naming it made `main`'s seed miss for every land on the other one (the apt files are checked by apt against its index, so a file of another image version is ignored).
- A cache made on a `ci/*` branch is visible only to that branch; every branch also reads `main`'s. A `main` push runs
  `premise-tests.yml` job `engine` (both engines) to seed these caches (Lean `Fw.Ci.Trigger.seeders_save_iff`).

## Measurements

See the table in `docs/team/handoffs/gate-speed-ci.md`.

Land lane: a shared fwcore prep job is serial and never beats parallel leg builds (477 s vs 553 s; `Fw.Ops.WallTime.wallPrep_ge`); `research/notes/2026/10-20-land-fwcore-once.md`.
