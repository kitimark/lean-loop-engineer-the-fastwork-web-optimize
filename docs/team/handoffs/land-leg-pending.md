# land-leg-pending

- Branch `worktree-wf_3956aa08-237-1`, worktree `.claude/worktrees/wf_3956aa08-237-1`; code at merge `ec7256f8` (main 596de3e6 merged).
- CI runs: none (pure Lean + runner tests; no CI push needed).
- Verified at ec7256f8: `sh lean/scripts/check.sh` green (5m45s, slot), contracts test 11/11, runner test 91 files / 2572 tests
  (4m41s, slot), both typechecks, `node --test scripts/ci-paths.test.mjs` 54/54; dry land: see the report.
- Behaviour change: a `skipped` leg now counts as ok.
- Open: `apps/runner/test/land-legs.test.ts` edited outside the writes (job status added to its views). Rerunning the refused
  gate-settle-scroll-timeline land is the lead's step.

## What changed
- Lean `Fw.Console.LandRemote`: `Job` (status, conclusion), `legState` (pending when status is not `completed`, ok on success or
  skipped, else fail), `rereadBound = 3`, `rereads`, `laneState` takes `Option (List Job)` and `reads`. Theorems: one per leg branch,
  `laneState_pending_reread`, `laneState_pending_exhausted`, `laneState_fail_legs_completed` (no fail from an unfinished leg),
  `laneState_success_pending_not_fail`, `verdict_pending_leg_no_refuse`, `verdict_no_fail_no_refuse`.
- Wire `console.landLaneState` takes `jobs: [{status, conclusion}] | null` and `reads`, answers `{state, reread}`; new op
  `console.landLegStates` (failed legs of a refusal detail).
- Golden `land-remote.jsonl`: run 39792901389 as the land read it (four legs in_progress, conclusion "") and once finalised.
- `apps/runner/src/land-remote.ts`: `GhJob.status`, `legRecords` replaces `legResults` (null when a job has no status: the poller's
  cached facts), `laneRead`, `Handle.reads` counts re-reads; a pending leg returns `running`, so `awaitRemote` sleeps a slice (cadence kept)
  and reads again; after the bound the run is `unavailable` (degraded wait, then local), never `fail`.
- Tests: `apps/runner/test/land-remote-pending.test.ts`; job status added to the views of land-remote*.test.ts and land-legs.test.ts.

## Conventions
- A job without a status says nothing (null records), as before a job without a conclusion did.
- `legsPass` / `LandLegs.legsVeto` are untouched (not on the land path).
