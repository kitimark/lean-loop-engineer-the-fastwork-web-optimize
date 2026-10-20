# console-idle-cpu handoff

State: branch worktree-wf_6c3ae4fd-86e-1 (commit named in the report). Audit items 4 and 5 of research/notes/2026/10-20-resource-audit.md.

Done
- Lean `lean/Fw/Console/ReconcileSched.lean`: `run`, `started_mono_run`, `inv_run`, `nextTick`, `nextTick_gt`, `nextTick_le`,
  `tick_pass_after_event`, `dropped_event_drained` (a dropped event is answered by a pass that starts after it, within one tick
  period plus two passes). Two golden cases added (`reconcile-sched.jsonl`).
- Lean `lean/Fw/Console/JournalFold.lean`: `fold_append`, `view_incremental` (incremental equals full, torn tail included),
  `commitEnd_*`, `plan` with a theorem per branch (hit, tail, shrink, rewrite, changed guard), `skip_*`, `skip_no_new_keys`.
  Golden `packages/contracts/golden/console/journal-cache.jsonl` (`scripts/JournalCacheGolden.lean`, check.sh job).
- TS (stand-ins checked on those goldens, `test/journal-cache.test.ts`): `spool/journal-cache.ts` (JournalCache, plan, commitEnd,
  skipRun, nextTick), `spool/workflow.ts` (`WfMemo`, `scanWorkflows(dir, ids, memo)`, `workflowWatchTargets`), `trigger.ts`
  (poke -> settle -> Sched request, safety tick), `watch.ts` (fs.watch glue), `spool/drain-watch.ts` (drain wiring, safety 10 s),
  `reconcile/reconciler.ts` `startWatching` (refs/heads recursive, packed-refs, store.subscribe, safety 30 s). `main.ts` uses both.

Measured (local debug, dev Mac, same 90 s window after 30 s warmup, copied console dir, `ps` cputime of console-api + fwcore)
- idle CPU: 10.5 % of a core (9.45 s) before, 0.93 % (0.84 s) after.
- latency spool append -> events.jsonl growth, 8 probes: before 458-1681 ms (median ~1.1 s), after 136-198 ms.
- one workflow scan pass (real 1 session dir, 565 task ids, 7.5 MB journals): 102.7 ms CPU before, 4.6 ms with the memo.
Scripts are in the session scratchpad only (measure.mjs, bench2.mjs), not committed.

Verified: console-api `pnpm test` (tsc + vitest), apps/runner `pnpm test`, `sh lean/scripts/check.sh` green, ci-paths test.

Limits and open
- Same-size/mtime rewrite of a journal is not seen (hit); a larger rewrite is caught by the guard bytes (head + end of the committed
  prefix), not by a full hash. Journals are append-only in practice (INFERRED).
- A settled run is looked at again when the task id list changes (all runs once), by design.
- Audit items 15, 16 (SSE heartbeat, preview timer) untouched. The 30 s preview tick still runs.
- Spool sweep still stats every spool file per wake (7.7k files); only the wake count dropped.

Read first: `apps/console-api/src/spool/drain-watch.ts`, `trigger.ts`, `lean/Fw/Console/JournalFold.lean`.
