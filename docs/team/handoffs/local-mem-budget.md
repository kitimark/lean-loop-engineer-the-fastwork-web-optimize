# Handoff: local-mem-budget (console-builder)

State: branch `worktree-wf_a08b7aa9-761-1`, commit named in the report. Read first: `lean/Fw/Obs/Timing.lean` (`contendedLoad`, the
"contended samples" proofs), `lean/Fw/Obs/Health.lean` (`sContended`), `lean/Fw/Sched/Heavy.lean`, `scripts/heavy-lock.mjs`.

Done (pinned unit):
- timing.slow under contention: `noisy` renamed `contended`; limit `contendedLoad = 8` (measured on this Mac, 8 CPUs: the same
  step runs 1.3-2x longer above load 8, e.g. props lint 16.8 s below load 4, 22.7 s at 12-16). A contended sample is never slow and
  never enters the baseline (`contended_not_slow`, `windowOf_append_contended`); a regression at normal load still fires
  (`slow_through_contention`). `Next.slowSteps_uncontended`.
- `sys.contended` (Health.lean, rank 17; `sysContended_iff`): one machine alert with load, `lake` builders, heavy-lock holders.
  Wire `builders`, `heavyJobs`; collector `countBuilders` / `countHeavy` in `apps/runner/src/watch-collect.ts`; Health.tsx Load row.
- Heavy lock: Lean `Fw.Sched.Heavy` (`verdict`, cap, memory, swap, FIFO rank, stale holder prune by pid+start); golden
  `packages/contracts/golden/sched/heavy.jsonl`; `scripts/heavy-lock.mjs` (TS STAND-IN of `verdict`/`prune`, replayed by
  `scripts/heavy-lock.test.mjs`); `lean/scripts/check.sh` re-execs under it (`FW_HEAVY_LOCK=off` skips).
- PropsLint: compiled exe `propslint` (lakefile); peak 2.36 GB (`lean --run` re-maps the `Lean` oleans the script imports) to 0.20 GB.
- One fwcore builder: `check-fast.sh` now builds through `scripts/fwcore-build.sh` like check.sh.
Measured (one local debug run of check.sh, load 10-15, not a result): warm check.sh 25-36 s wall, 29 processes, summed RSS peak 7.0 GB (upper bound; workers share oleans), so jobMB 5000, capMax 2 (2 jobs x 4-wide groups = 8 CPUs = contendedLoad). 1/2/4-concurrent timing was not run: other agents held load at 6-37 on this Mac, so it would measure them.
Accepted limits: cap measured on this Mac only (local debug runs, not results); MCP servers not stopped; a load above 8 for a
whole run hides a regression from the local alert (CI timings cover it); `fwcore-build.sh` writes no `fwcore.commit` record on a
dirty tree / mid-merge, so svc.unknown after a check.sh on a dirty checkout is by design.

Open (follow-ups, not in the unit): sys.swapHigh; proc.leftover; proc.heavy; why proc.long missed lake-serve trees under the
lean-lsp MCP server; memory/swap/builder trend per tick in the obs log and console; `fwcore-build.sh` and `check-fast.sh` outside
the heavy lock; `Fw/Wire/Obs.lean` `systemOf_systemJson` needs 16M heartbeats (was 4M) and 4 min to elaborate: split that proof.

Conventions: Lean writes the goldens (`lake env lean --run scripts/HeavyGolden.lean`, `TimingGolden.lean`, `ObsGolden.lean`,
`OpsGolden.lean`; each with `--check`). Writes outside the graph list: lean/Fw/Ci/Trigger.lean, lean/Fw/Console/LandSpeed.lean and apps/runner/src/land.ts (new read scripts/heavy-lock.mjs), apps/console-api/src/health.ts (load1), golden/ci/triggers.jsonl and golden/console/land-speed.jsonl (regenerated), lean/Fw/Obs/Timing.lean, Next.lean, Fw/Ci/Telemetry.lean,
Fw/Wire/Obs.lean, Fw/Sched/Heavy.lean, lean/lakefile.toml, lean/scripts/check-fast.sh, HeavyGolden.lean, scripts/heavy-lock.test.mjs,
apps/console-web/src/Health.tsx, docs/team/tools/{lean-first,timings,watch-rules}.md.
