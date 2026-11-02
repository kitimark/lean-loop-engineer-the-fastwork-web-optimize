branch: worktree-wf_871d2df0-421-1 (CI branch ci/end-pin-position)
worktree: .claude/worktrees/wf_871d2df0-421-1
last commit: see `git log -1` on the branch (CI trigger commit 04e6cdb3d; the results commit follows it)
CI run 41380162402 (smoothness, touch-lock lane, 12 jobs, 3 waves): failed (jobs 5 and 7 touch-driver-not-ready), dispatch 1 of 2 used, results downloaded
earlier run 41369102226 (end-pin-rank): failed, read offline with the new rule
verified: Lean TouchLock builds, golden touch-lock.jsonl (193 lines) --check up to date, measure-webkit tests 1125/1125, ci-paths 56/56, runner land-inputs 73/73, ledger tests pass
open: lead review; the push server not ready after 480 s (5 of 12 jobs) needs its own task; sensitivity to tolerance 10 px / margin 3 not run

## State
- Lean (lean/Fw/Measure/TouchLock.lean): restOf (notReached / atEnd / over / short), settle10, restCmp, jobVerdict with the liveWrites guard (live > 0 never ranks pin better), acrossRest via Smooth acrossDecisive; goldens for runs 41369102226 and 41380162402.
- TS twin packages/measure-webkit/src/touchlock-rest.mjs, wired into touchlock.mjs; test/touchlock-rest.test.mjs replays the goldens. touchlock-run.mjs passes readyMs: READY_ALLOW_MS on both startServer paths.
- Result: across jobs by rest position in run 41380162402 is same (8 decisive of 12, 5 pin-better, 3 same, 6 needed); run 41369102226 offline is second (6 decisive, 4 needed). Live writes 0 everywhere. No walk variant needed.

## Read first
research/notes/2026/11-02-end-pin-position.md, then results/end-pin-position/run-41380162402/across.md.

## Conventions
CI waits: pnpm -s fw ci wait --branch ci/end-pin-position --workflow smoothness (540 s per call). One more dispatch is allowed (2 max), not used.
Writes outside the graph writes: results/end-pin-position/, research/findings/ledger.json (row morph.tween:end-pin), packages/contracts/golden/measure/touch-lock.jsonl (generated).
