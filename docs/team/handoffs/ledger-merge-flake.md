Branch worktree-wf_c2cf5595-49f-1; worktree .claude/worktrees/wf_c2cf5595-49f-1; last code commit see git log; no CI runs pushed (none needed).
State: round 2 done. Fix in apps/runner/test/ledger-merge.test.ts: mkdtemp per setup, afterEach rm, gc.auto=0 maintenance.auto=false; regression test stubs the reset and shows old setup fails with "a branch named 'a' already exists", new passes.
Verified: runner package test green (3698), ledger-merge file 3 consecutive runs 42/42, tsc clean.
Open: why .git survived on the runner stays INFERRED (note). Limits: no retries/timeouts, no CI stress lane.
Read first: research/notes/2026/10-2x-ledger-merge-flake.md
