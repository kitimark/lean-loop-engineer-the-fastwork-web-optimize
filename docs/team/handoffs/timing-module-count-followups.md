branch: worktree-wf_96b56729-703-1
worktree: .claude/worktrees/wf_96b56729-703-1
last commit: 74332a514 (code, after the merge of main)
CI runs: none (accepted limit: no CI run for this task)
verified: lean/scripts/check.sh green; `@fw/runner` test 102 files / 3208 tests; `@fw/contracts` test; scripts/ci-paths.test.mjs; plan lint 0 errors
open: land needs `--allow apps/runner/src/next.ts --allow apps/runner/src/watch-collect.ts --allow apps/runner/src/watch.ts` (scope refuses them; with them `VERDICT dry` passes)

What changed
- lean/Fw/Obs/Timing.lean: `Code.unkeyed` and `judgeQ` (mixed, then unkeyed, then `judgeW`). `unkeyedLate hist s`: a sample with no
  checks/mods work class after an earlier full keyed sample of the same step gets no verdict (theorems `unkeyed_late_no_slow`,
  `unkeyedLate_iff`, `judgeQ_no_keyed_history`, `slow_not_unkeyed_late`). Remote waits: `Sample.ownMs`, `Sample.norm`,
  `verdictsOf` (entry point). `fw land` `remote queue` is judged as 0 ms (`remoteQueue_never_slow`); `fw ci wait` by its own time
  (`ciWait_norm_dur`, `ciWait_never_slow`); a ci wait without own time gets no verdict. `SampleVerdict.detail` names the sample,
  baseline, and the window. Golden rows from the 2026-10-23 numbers (numbers only) in `golden/obs/timing.jsonl`.
- Item 4 finding: no cross-module-count or cross-host comparison. The alert subject is the key of the LATEST sample of that key;
  the unkeyed 51 s span (ffb7792) stayed the latest of the unkeyed key (newer spans are keyed) and was slow against the
  unkeyed window (p50 26.8 s). Keyed built-0 spans are ok against the built-0 window (`judgeQ_other_mods`). Rule (a) closes it.
- Item 5 accepted limit: the `fw ci wait` span has no workflow or queue time; it has `phases.updMs`, so the rule judges by own
  time, which is span end minus updMs (only `how = done`), not keyed by workflow. `fw ci state` was not needed.
- Wire: `obs.slow` takes `detail: true` and then also returns `details` (one line per subject); default reply unchanged.
- TS glue: `ownOf` (timing.ts), `ownMs` in `parseSamples`, `slowWith` + `slowAlerts(slow, details)` (alert detail), `stagedSpan`
  sets `lake` only when `realRun` exits 0 (run may return null). Tests: timing-own.test.ts, timing-slow.test.ts, land-dry.test.ts.

Conventions: regenerate with `cd lean && lake env lean --run scripts/TimingGolden.lean` (and `--check`); never hand-edit goldens.
Read first: the `Remote waits` and `unkeyed samples and remote waits` sections of lean/Fw/Obs/Timing.lean.
