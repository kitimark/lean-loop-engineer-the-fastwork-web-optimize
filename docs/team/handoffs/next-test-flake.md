# next-test-flake handoff

State: test-only fix in apps/runner/test/next.test.ts (`observe` helper of the real-child-process describe). next.ts unchanged.

Cause (INFERRED from code): the test spawned `sh -c` and read `ps` once at once. Under load the forked shell is not yet
in `ps` (or ps timed out and psCommands returned []), so buildFacts found no child (expected length 1, got 0).
next.ts only reports what ps shows; it has no race of its own.

Fix: `observe` re-reads ps and rebuilds facts every 50 ms until facts[0].children is non-empty, bounded by
2 x FW_EXEC_TIMEOUT_MS (default 5000). Assertions unchanged (kind sleepLoop, chain[0] = session, producerExited, killOrphan).

Verified: see the report for the 20-run pass count under 4 busy-loop processes (machine load already >200 from other agents).
Note: a single run of this file took ~150 s under that load; the time is not in this test.
Read first: apps/runner/test/next.test.ts lines ~118-140.
