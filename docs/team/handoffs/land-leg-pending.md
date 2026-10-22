# land-leg-pending

- Branch `worktree-wf_3956aa08-237-1`, worktree `.claude/worktrees/wf_3956aa08-237-1`; last code commit: see `git log -1` on the branch.
- CI runs: none (pure Lean + runner tests; no CI push needed).
- Verified: `lake build`, the golden regenerated (`lean/scripts/LandRemoteGolden.lean`), `pnpm --filter @fw/runner test` (91 files),
  runner typecheck, `node --test scripts/ci-paths.test.mjs`; check.sh and the dry land at the final commit (see the report).
- Open: none in the unit. Rerunning the refused gate-settle-scroll-timeline land is the lead's step.

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
