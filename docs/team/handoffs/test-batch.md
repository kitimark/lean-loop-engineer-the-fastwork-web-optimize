# test-batch handoff

State: committed on branch worktree-wf_56836044-1da-1 (rows A1, A2, A4 of research/notes/2026/10-19-speed-review.md).

Changes
- apps/runner/test/wait-guard.test.ts: golden describe sends all ops.wait cases to ONE fwcore (ids 0..N-1, replies
  matched by id), then asserts per case in it.each (a mismatch names its case). One test still goes through ask()
  (the hook's per-call spawn path). The remaining ask() in `verb` now passes 30_000.
- packages/gate-breakpoints/test/verdict.test.mjs: literal non-error cases in one call(); error cases one per call.

Measured (one run each, wall seconds, load average at start)
| file | before | after |
| wait-guard.test.ts (vitest) | 144 s (load 13) | 57 s (load 5) |
| verdict.test.mjs (node --test) | 45 s (load 6-13, contended); 31 s at load 5 (reviewer) | 19-20 s (load 4) |
Load differs between runs, so part of the gain is less contention; the spawn count dropped by 128 (wait-guard: 130 -> 2) and 16 (verdict: 21 -> 5).

Open
- wait-guard.test.ts still spawns one fwcore per case in the "false positives" describe (allow / deny / review3
  it.each via verb(), ~83 spawns (review, review3, allow, deny)); that is now the dominant cost. Batching it needs a lazy precompute like the golden one.
- Both files pass (226 and 13 tests).
