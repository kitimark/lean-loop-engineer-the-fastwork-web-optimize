# land-queue-why handoff
State: branch worktree-wf_c3476a53-402-2 (see its last commit). Runner tests (tsc + vitest, 1246), ci-paths test and `sh lean/scripts/check.sh` were green at the final commit.
Done
- Lean `Fw.Console.LandQueue`: `reasonOf`, `refusedLine`, `fwcoreStale`, `fwcoreStaleReason` with theorems per branch; golden `packages/contracts/golden/console/land-queue.jsonl` regenerated (34 cases, ops `landQueue.reason`, `landQueue.fwcoreStale`).
- TS: `land-verdict.ts` mirrors them (stand-ins checked by the golden); `land-queue.ts` `runQueue` keeps the message, prints `REFUSED:`, records `reason` in the `res` line and the land log (`landLogOf`); `fw.ts` passes `{kind, reason}` from a land's last `REFUSED:` line; `land.ts` `fwcorePreflight` runs before the pick step of a real land.
- Tests: `apps/runner/test/land-queue.test.ts` (throwing attempt), `land-digest.test.ts` (preflight).
Open items
- The preflight kind is `stale` (exit 16), shared with the dry "branch lacks main" refusal; a separate Kind would touch every Kind golden.
- No graph edit was made (lead only). The scrub for session scratchpad paths (incident part 1) is another task.
Read first: docs/team/tools/land.md (last section), lean/Fw/Console/LandQueue.lean.
