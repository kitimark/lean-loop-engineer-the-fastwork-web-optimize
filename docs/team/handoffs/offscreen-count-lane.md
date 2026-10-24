branch: worktree-wf_f26cc506-df2-1 (CI branch ci/offscreen-count-lane)
worktree: .claude/worktrees/wf_f26cc506-df2-1
last code commit: e3ea0ff79 (CI push 2; later commits are note, handoff and merges of main)
CI runs: 40114634566 failure (push 1: ERR_MODULE_NOT_FOUND /contracts/src/flag-key.mjs, host.mjs did not mount contracts/src)
         40115582041 success (push 2, sha e3ea0ff79: original, rewrite, f1 sweep, f2 glint x r1..r3, classify, offscreen)

Result (MEASURED, run 40115582041): both flags noGain; all 12 counters equal in all 3 runs of every rewrite arm (window 234 frames).
Class counts and per-flag table: research/notes/2026/10-2x-offscreen-count-lane.md. WebKit: named follow-up (WKTR runs the original).

Verified locally: lean/scripts/check.sh green, @fw/measure-chromium 91 tests, @fw/runner 3437, @fw/contracts 11,
scripts/ci-paths.test.mjs 56, lane inputs check (no new dispatch input).

Open: isolation arm (?only=platform with a flag; workflow refuses arms with only), WebKit rewrite arm, other sections,
shardOfJob does not know labels f1..f4 (telemetry skips them). 2 of 3 pushes used.

Read first: docs/team/tools/offscreen-counts.md, lean/Fw/Measure/Offscreen.lean, packages/measure-chromium/src/offscreen.mjs,
.github/workflows/chromium-counts.yml (plan arms, offscreen job).

Conventions: arms come from the head commit line `[counts profile=offscreen-v1 runs=3 target=both arms=a:b|c:d]` on a ci/* push
(no dispatch input, because Fw.Store.Lane.inputs equals the workflow inputs). host.mjs mounts packages/contracts/src (outside the
task graph writes).
