# next-test-flake handoff

State: round 1 at the final commit of branch worktree-wf_c21c1303-2e0-1 (see git log). The sleepLoop e2e case in
apps/runner/test/next.test.ts no longer fails under load; next.ts psCommands now honors FW_EXEC_TIMEOUT_MS.

Cause: INFERRED, old-code failure not reproduced. Leading hypothesis: ps timeout under node starvation
(next.ts psCommands had a hard-coded 3000 ms), so exec returned null, psCommands returned [], children length 0.

Changes:
- apps/runner/src/next.ts psCommands: dropped the 3000 ms argument; exec default applies (FW_EXEC_TIMEOUT_MS, else 5000).
  land sets FW_EXEC_TIMEOUT_MS=30000 (land.ts:493).
- next.test.ts `observe`: polls ps every 50 ms until children is non-empty, deadline
  Date.now() + max(60_000, 2 x FW_EXEC_TIMEOUT_MS|5000) (above the ps timeout, below the 120 s testTimeout). Assertions unchanged.

Proof: command `npx vitest run test/next.test.ts` in apps/runner, 8 busy loops (`while :; do :; done`) started and
killed by this run, machine load already high. Default env 20/20; FW_EXEC_TIMEOUT_MS=1000 10/10;
FW_EXEC_TIMEOUT_MS=30000 10/10. `pnpm --filter ./apps/runner test` once: 34 files, 1043 tests passed (tsc included).
One file run takes ~80 s under this load; the time is not in this test.
Read first: next.test.ts lines ~130-150.
