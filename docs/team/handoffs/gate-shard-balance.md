# gate-shard-balance handoff (round 4, fix round)

State: branch worktree-wf_609b7614-73c-1, CI branch ci/gate-shard-balance-r4, CI-measured code head ea00f2bc; later commits edit docs only.
`sh lean/scripts/check.sh` green; packages/gate-breakpoints `pnpm test`: 131 pass; snapshot-extract 10; `.github/scripts/gate-jobs.test.mjs` 10.
Read first: research/notes/2026/10-18-gate-shard-balance.md, section "Round 4".

## What round 4 did
- Per-reading gate rule (`Fw.Gate.Exit`: `rollup_pass_iff_all_readings`, `engine_pass_iff_all_cells`); registry has 5 entries (two new touch-1024
  entries, premise `Fw.Gate.touch1024_lean_na`); `cli.mjs` reads it from `exit.jsonl` (71 lines, `scripts/ExitGolden.lean --check` in check.sh);
  every excused reading is printed. WebKit phone-rotation stops 1 and 3 (not-comparable, env not achieved) stay unexcused on purpose.
- View stage over the union of both arms (`src/view.mjs`, barrier pair sample in `run.mjs`); `FW_GATE_VIEW=1` is off by default.
- `breakpoint-gate.yml` `times` default `measured` + node test that it equals the Lean plan default.
- Docstring formulas fixed (Freeze, Exit, Rule, Scope). `ShardObs.lean` and `shards.jsonl` regenerated from run 39125771186.

## Result (MEASURED, runs 39125771186/39125776112 on 454f6c0b; 39126934987/39126939905 on ea00f2bc)
504 cells identical to r3 run 39121185833 in all four. Chromium pass (3521 readings pass, 7 excused). WebKit fail (stageBg, 13 stops; plus 2 NC stops
that r3 absorbed: phone-rotation). 28.1/27.5 job-min (old plan), 28.6/28.5 (new plan, 7 jobs); gate wall 5.6 to 6.1 min.

## Open
- Land with `--allow` for the out-of-scope files. `mutants` fails on main too (SpawnGuard).
- ShardObs costs are flat (5024 ms per probe): frozen-clock settle waits are about 0. Needs a weighted source before the plan means anything.
- View path never ran on CI (mock session only); second-reading scroll position differs per arm.
- Push alone runs the gate only with `[ci:breakpoint-gate]` in the head commit message (else the guard skips); dispatch always runs.
- 33-part cells (desk-rm-861 hero.orbit, desk-rm-1279 commission) need integrate-ports-3; align-self canonicalisation stays with gate-align-equiv.
- Worktree needs `pnpm install --offline --frozen-lockfile` before `pnpm fw` works.
