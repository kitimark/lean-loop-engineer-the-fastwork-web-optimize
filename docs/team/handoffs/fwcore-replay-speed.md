# fwcore-replay-speed handoff

State: branch worktree-wf_0aea5e2f-020-1 (commit in the report). All four parts done.
- Part 1: `lean/Fw/Plan/Fast.lean` (incremental cycle check, proofs) and `lean/Fw/Serve.lean` (`checkFast`, `execR`,
  newest-first records read through `unrev`). Real log replay 12.8 s -> 0.14 s; 4x 0.6 s. Old/new output byte-identical.
- Part 2: `apps/console-api/src/core/lean.ts` `call` awaits the replay first; test in `test/crash.test.ts`.
- Part 3: `Fw.Obs.Backoff` takes `cores` (loaded = `max 1 cores <= load`); wire op, golden generator and
  `packages/contracts/golden/obs/backoff.jsonl` regenerated (never hand-edited). TS stand-in
  `backoffDecision(cores, load, ...)`, checked against the golden.
- Notes: research/notes/2026/10-20-fwcore-replay-speed.md; docs/team/tools/console.md.

Verified: lean build, ObsGolden --check, console-api `pnpm test` (455 pass), lean/scripts/check.sh at the final commit.
Lead, after landing: rebuild fwcore (`sh scripts/fwcore-build.sh`), restart the console, and DROP the FW_CORE_CALL_MS=60000
mitigation (the default 10 s holds: parts 1 and 2).
Open: the TS `backoffDecision` stays a stand-in until a second fwcore can answer on the timeout path.
Writes outside the task graph: lean/Fw/Wire/Obs.lean, lean/Fw/Obs/Golden.lean, packages/contracts/golden/obs/backoff.jsonl,
apps/console-api/test/backoff.test.ts (all part 3).
