branch: worktree-wf_f26cc506-df2-1 (CI branch ci/offscreen-count-lane)
worktree: .claude/worktrees/wf_f26cc506-df2-1
last code commit: 02b61a255 (land.ts reads: packages/contracts/src/**); CI push 2 code was e3ea0ff79; main merged again at 410ef5ae9 (r432 writes)
CI runs: 40114634566 failure (push 1: ERR_MODULE_NOT_FOUND /contracts/src/flag-key.mjs, host.mjs did not mount contracts/src)
         40115582041 success (push 2, sha e3ea0ff79: original, rewrite, f1 sweep, f2 glint x r1..r3, classify, offscreen)

Result (MEASURED, run 40115582041): both flags noGain; all 12 counters equal in all 3 runs of every rewrite arm (window 234 frames).
Class counts and per-flag table: research/notes/2026/10-2x-offscreen-count-lane.md. WebKit: named follow-up (WKTR runs the original).

Verified locally after the second merge of main: check.sh green, measure-chromium 91, runner 3450, ci-paths 56, plan lint 0 errors.
Earlier: lean/scripts/check.sh green, @fw/measure-chromium 91 tests, @fw/runner 3437, @fw/contracts 11,
scripts/ci-paths.test.mjs 56, lane inputs check (no new dispatch input).

Open: isolation arm (?only=platform with a flag; workflow refuses arms with only), WebKit rewrite arm, other sections,
shardOfJob does not know labels f1..f4 (telemetry skips them). 2 of 3 pushes used.

Read first: docs/team/tools/offscreen-counts.md, lean/Fw/Measure/Offscreen.lean, packages/measure-chromium/src/offscreen.mjs,
.github/workflows/chromium-counts.yml (plan arms, offscreen job).

Conventions: arms come from the head commit line `[counts profile=offscreen-v1 runs=3 target=both arms=a:b|c:d]` on a ci/* push
(no dispatch input, because Fw.Store.Lane.inputs equals the workflow inputs). host.mjs mounts packages/contracts/src (outside the
task graph writes).
