# console-reconcile-speed handoff

State: branch worktree-wf_7ba814d3-2b5-1 (commit named in the report). Lean first, then TS.

Done
- Lean `lean/Fw/Console/ReconcileSched.lean`: 3-state scheduler (started, finished, pending). Theorems: `pending_le_one_req`,
  `pending_le_one_fin`, `one_running`, `req_idle_starts`, `req_busy_waits`, `req_coalesces`, `answered_after_idle`,
  `answered_after_busy`, `wait_le_two`, `wait_le_one_idle`. Golden: `packages/contracts/golden/console/reconcile-sched.jsonl`
  (write/check: `lake env lean --run scripts/ReconcileSchedGolden.lean [--check]`, check.sh stage added).
- TS stand-in `apps/console-api/src/reconcile/coalesce.ts` (checked against the golden in `test/reconcile-coalesce.test.ts`);
  `Reconciler.reconcile()` uses it: a request gets the promise of pass `ticket`.
- `Store.board()` shares one console.query per seq (1 s window): one board per pass, one for all SSE clients.
- `onMainSet` (git.ts, one `git rev-list main`) replaces per-sha `git merge-base` in runner `plan.ts gitOnMain` and in the reconciler.
- fw land: the post-merge plan sync is dropped (fw.ts no longer passes `after`; `syncViaCommands` removed). Reason: the reconciler
  syncs main's head work graph when main moves, same keys (actor is not in the key: contracts plan-sync.ts:46,58), before task.done.
  So the retry-once for the POST loop has nothing left to protect. `LandOptions.after` stays in land.ts for tests.
- land.ts `httpFor`: 90 s deadline per request (`HTTP_DEADLINE_MS`), below undici's 300 s; the step's existing retry takes it.

Open
- Profiling console.query in Lean (M) and the 120 s replay deadline: follow-ups.
- MEASURED on this Mac (scratch console, copy of the event log, load 276 before / 229 after; one run each, so a ratio, not a rate):
  idle reconcile pass median 14.7 s -> 1.0 s; POST /api/reconcile under 12 requests 150 ms apart: median 130.7 s (max 150.9 s)
  -> 1.5 s (max 4.7 s); syncCommands (407 cmds, ancestry test) 27.2 s -> 0.2 s; post-merge reconcile 168.9 s + old plan sync
  698.4 s -> reconcile 3.4 s and no plan sync step. Bench: scratchpad crs/bench.mjs (not committed).

Read first: the Lean module docstrings, then reconciler.ts `reconcile`/`launch`.
