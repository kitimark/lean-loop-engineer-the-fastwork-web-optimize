# drain-wake-flake handoff (round 2)

State: the tip commit of branch worktree-wf_2bbfa127-06f-1. Task: journal-cache 'a journal append and a new session dir wake the
drain' missed on the Linux land lane.

Mechanism (MEASURED on CI, CONFIRMED in source):
- Node v24.21.0 on Linux: `fs.watch(missingPath, {recursive:true})` does not throw; it returns a watcher that never fires.
  `lib/internal/fs/recursive_watch.js:236-241 @v24.21.0` swallows the ENOENT unless `throwIfNoEntry` is false (default true, :71-76).
  v24.14.0 (:225) and v24.22.0 (:332-337) throw. The land legs run floating Node 24: 24.21.0 and 24.22.0 in one run (setup logs of
  runs 39432902864, 39438056251, 39440821027), so the miss depends on the runner pool.
- `Watches.sync` counted that watcher as open and never retried: the `subagents/workflows` watch of a not-yet-created tree was dead.
  Fix: `Watches.sync()` skips a missing path (`existsSync`) and returns the number of watches it opened (> 0 requests a sweep).
- Unfixed full-suite loop, run 39440821027 (v24.21.0, 4 cpus): old test and the new event-path test missed in loop 1 and 2 (10 of 10
  repeats), trail: pokes 1, passes 2 (the mkdir pass only), loop lag max 13 ms, passes 42-47 ms: a lost event, not a long pass or
  starvation. Raw probe on the same node: `threw null, eventsAfterCreate 0`.
- Fixed, run 39442175823: 30 full-suite loops (2 at a time), 0 wake misses (old test at 05d720ae restored in a probe copy, instrumented).
  Probe files were removed after; the wake tests keep the trail (pokes, passes with length, loop lag, node version, failed wait).

Lean (`Fw.Console.ReconcileSched`): timed model `T`, `answered`, `answer_idle`, `answer_busy`, `answer_start_le`, `poke_wake_le`,
`poke_done_le`, `tick_wake_le`: the pass numbered `ticket` is the last one started and begins in [r, r + pass] when only the running
pass is assumed to end by `since + pass` (uses `req_idle_starts`, `fin_starts_pending` facts). Golden `wake-bound.jsonl` and
`wake-params.jsonl` (`pass_max_ms` 2000 and the margin 500 are ASSUMPTIONS; event deadline 2550, rescue deadline 3500 DERIVED).

Tests (`journal-cache.test.ts`): event path (60 s tick, repeats 10), the same with the watcher disabled must fail (asserted), tick
rescue (all events dropped, repeats 10), `Watches` missing-path test. Each asserts pokes rose before the answering pass (event path)
and that the drained store holds the journal line's agent; a pass over PASS_MAX_MS or a loop stall over the margin fails with the trail.

Writes outside the task's graph writes: `apps/console-api/src/watch.ts` (the fix). Open: pin `node-version` in
`.github/actions/setup-pnpm/action.yml` (lead; outside writes) so 24.21.0 cannot return; the TS `wakeStartBound` is a stand-in.
