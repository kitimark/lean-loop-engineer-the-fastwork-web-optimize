# pool-caps handoff

State: branch worktree-wf_d864cd42-ccc-1. Lean `sh lean/scripts/check.sh` green; `node --test scripts/ci-paths.test.mjs` 45/45.

What is done:
- `lean/Fw/Ci/Pool/Caps.lean`: `capMin p90dm = (13 * p90dm + 99) / 100`, where p90 is in tenths of a minute. Theorems:
  `cap_ge_scaled` (13p <= 100 cap), `cap_least`, `cap_ge_p90`, `cap_mono`, `rows_cap_ge_p90`,
  `rows_files_nodup`, `rows_lanes_nodup`, `excluded_disjoint`, `thin_only_gate_gaps`, `caps_eq`. Has `#guard`s, incl. capMin 289 = 38.
- Rows (p90 = linear p90 of successes from note 10-20-macos-pool-v2.md, rounded UP to 0.1 min, so cap >= the measured p90):
  wktr/wktr 119 -> 16, wktr-fixtures/fixtures 161 -> 21, sim-speed/probe 124 -> 17, engine-premises/webkit 56 -> 8,
  gate-gaps/collect-macos 198 -> 26 (n = 3, `thin`). `excluded`: webkit-sim.yml (owned by task webkit-sim-failfast).
- `lean/Fw/Ci/Pool.lean` is the umbrella and imports only Caps. Later pool tasks add one import line each; there are no stubs.
- Golden: `packages/contracts/golden/ci/pool-caps.jsonl`, written by `lake env lean --run scripts/PoolCapsGolden.lean`
  (`--check` is one line in check.sh).
- `scripts/ci-paths.mjs` `capProblems` / `loadCaps` (part of `run`, so `--check` covers it and land runs it).
  - Every macOS job (macos-* / xcode-*, including dispatch-only jobs) outside `excluded` must have a cap row, and its
    job-level timeout-minutes must equal the cap. A cap row must name an existing macOS job.
  - A runs-on expression is refused.
  - `--write` sets or inserts the timeouts.

Open / follow-ups:
- gate-gaps `collect-macos` still has a step-level `timeout-minutes: 34` inside the 26-minute job, so that step timeout
  can no longer fire. Lower it or drop it in a measured follow-up.
- The lean.yml trigger row (Fw.Ci.Trigger) does not list golden/ci/pool-caps.jsonl. The same is true of the other
  golden/ci files. check.sh covers it through checkShReads (`packages/contracts/golden/**`).
- Caps per (lane, sessions) once F27 lanes are pooled; re-measure p90 (3 days of data; gate-gaps n = 3, re-derive at n >= 10).
- apps/runner `plan.test.ts` "real work-graph.json converts" fails. The cause is that work-graph task trajectory-probe has 33
  writes (the limit is 32); this fails on main too and is not caused by this task.

Read first: lean/Fw/Ci/Pool/Caps.lean, then `capProblems` in scripts/ci-paths.mjs.
