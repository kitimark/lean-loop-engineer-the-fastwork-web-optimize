branch: worktree-wf_850db9c2-5f8-1 (CI branch ci/touch-window-retry); worktree .claude/worktrees/wf_850db9c2-5f8-1
read first: research/notes/2026/11-03-touch-window-retry.md, then lean/Fw/Measure/WindowRetry.lean
state: rule, goldens, TS and lane wiring committed; CI dispatch 1 of 2 finished, state failed (smoothness run 41534838350, commit 4fdde6020); second dispatch not spent
verified: check.sh green, window-retry.test.mjs 10/10, measure-webkit tests, lint-wallclock, ci-paths test
result (MEASURED, 12 jobs): kept 87 of 288 (30.2% vs 27.7%), jobs at minKept 2 of 12 (3 status-ok), redos ran 13: recovered 5, noOpen 5, tooShort 1, failed 2, 13 noTime; walkDeadline 18, planShort 8, restartFailed 90
finding: redo recovered 0.38 of tries, below the INFERRED break-even 0.585; two redos hit a Simulator stall (failed redos 830 s and 986 s; job redo totals 917 s and 1026 s); no gain shown
open: comparison with touch-window-loss stays a one-sample question; warm-up window before rep 0; window-loss firstStall counts push lines, a redo adds some; noOpen cause not isolated
conventions: pricing scratch under scratchpad/touch-window-retry/ (not committed); redo outcomes by `node packages/measure-webkit/src/window-retry-cli.mjs --root <run artifacts>`; classify with window-loss-cli.mjs
stand-ins (TS, no decision logic): dl = deadlineMs ?? Infinity, withRedo glue, window-retry-cli.mjs
