branch: worktree-wf_f26cc506-df2-1 (CI branch ci/offscreen-count-lane)
worktree: .claude/worktrees/wf_f26cc506-df2-1
last code commit: 8e240c3f9 (push 1 head is the handoff commit on top of it)
CI runs: none finished yet (push 1 pending; run id is added after the first poll)

Verified locally (Lean and unit tests only, no measurement): lean/scripts/check.sh green, @fw/measure-chromium 90 tests,
@fw/runner 3437 tests, @fw/contracts 11, scripts/ci-paths.test.mjs 56, lane inputs check (no new dispatch input).

Open: the three-arm CI run (original, rewrite, f1 sweep, f2 glint; 3 runs each), class counts from the classify job per label,
the research note research/notes/2026/10-2x-offscreen-count-lane.md, merge of main, dry land, review ready.

Read first: docs/team/tools/offscreen-counts.md (lane), lean/Fw/Measure/Offscreen.lean (rule, reduction, verdict),
packages/measure-chromium/src/offscreen.mjs (TS twin and glue), .github/workflows/chromium-counts.yml (plan arms, offscreen job).

Conventions: the arms come from the head commit line `[counts profile=offscreen-v1 runs=3 target=both arms=a:b|c:d]` on a push
(no dispatch input, because Fw.Store.Lane.inputs equals the workflow inputs). At most 3 pushes for this task; 1 used by the first run.
Trace event names are unverified on Chromium 156: if `seen` totals in offscreen.json are 0 for a name, re-reduce offline from the
`offscreen-trace-*` artifacts and fix extraTraceCounts.
