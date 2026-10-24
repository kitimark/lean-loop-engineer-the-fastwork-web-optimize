# fw-run-vms handoff

- Branch: worktree-wf_8bb1a100-839-1; worktree: .claude/worktrees/wf_8bb1a100-839-1
- Last commit: see `git log -1` on the branch (the work commit, then the main merge)
- CI runs: none (no CI dispatch or push, as the task says)

## State
- Lean: `dispatchInputs .webkit` sends `("vms", toString q.runs)`; `dispatch_vms`; `webkit_vms_accepted` (Wire/Store);
  webkit with runs > 3 is a request problem (`webkitMaxVms`, `reqProblems_nil_webkit_runs`).
- Store key version 3 carries `runs` (`keyPairs_runs_ne`, `plan_key_runs_ne`, `keyPairs_ne_v2`). Manifest and Req gained
  `runs`; `fw ci` sets it to the shard count (Ci.lean `ciReq`); `fw run` reads it from the planned key (`keyRuns`).
- Goldens regenerated from Lean; `run-golden.test.ts` replays plan and manifest cases against fwcore.
- Dry `fw run --target rewrite --engines webkit --runs 3 --ref main --dry` prints `vms=3` (note has the line).

## Writes outside the task graph
lean/Fw/Store/Ci.lean, apps/runner/src/ci.ts, packages/contracts/src/artifacts.ts (the run count in the key needs them).

## Open
- Live check: the next lead WebKit dispatch should show 3 VM jobs.
- Stored runs under version 2 keys are no longer hits (intended); re-ingest with `fw ci` if one is needed.

Read first: research/notes/2026/10-2x-fw-run-vms.md.
