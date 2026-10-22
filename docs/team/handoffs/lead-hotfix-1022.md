# lead-hotfix-1022

- State: two one-line fixes by the lead, landed from branch worktree-lead-hotfix-1022.
- scripts/slot-self.mjs: routed `slot run` no longer wraps an outer span (slot-span-key moved the run and wait spans into
  slot.ts, writesOwnSpans); the removed slotStepEnd import made every routed check.sh throw on exit after green gates.
- .claude/workflows/build-review.js resume path: the dry-rerun runner takes the branch from `git rev-parse --abbrev-ref HEAD`
  in the worktree instead of typing report.branch (an empty branch gave a usage line instead of a VERDICT).
- Verified: scripts/slot-self.test.mjs; a routed `node scripts/slot-self.mjs check -- true` exits 0 with no TypeError.
- Read first: apps/runner/src/fw.ts (the same writesOwnSpans guard), apps/runner/src/slot-span.ts.
