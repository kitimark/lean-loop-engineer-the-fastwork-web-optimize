branch: worktree-wf_30808c70-1bc-1
worktree: .claude/worktrees/wf_30808c70-1bc-1 (under the main checkout)
last commit: 9e72476a3 (round 2 code; this handoff is committed after it)
CI runs: none (the task needs no CI push; the hook refuses locally)
Verified at 9e72476a3: lean/scripts/check.sh green (through fw slot); apps/runner tests 117 files, 3679 tests pass;
node --test scripts/ci-paths.test.mjs 56 pass; plan lint 0 errors. Dry land: see the report line (`VERDICT dry ci-push-lane-check`).

What it is: the ci/* pre-push hook refuses a push whose tree equals main, whose tip selects no measuring lane (no
[lanes: ...] trailer exempts it), or that misses a lane a trailer requires. Decision in Lean `Fw.Ci.Intent` (section "The
push lane check", lean/Fw/Ci/Intent.lean): `reasonOf`, `reason`, `refuseNoLane`, `pushRefused`; theorems `reasonOf_ne_ok`,
`refuse_iff`, `refuse_same_tree`, `refuse_missing`, `refuse_no_measuring`, `accept_iff`, `main_never_refused`,
`token_lane_runs`, `started_requested`, `missing_token_refused`, `same_tree_no_measuring`. Golden
packages/contracts/golden/ci/pushlane.jsonl (written by `lake test -- --write-ci-trigger-golden`).

TS: apps/runner/src/ci-push.ts (`laneRefusal`, `laneReason`, `lanesTrailer`) is a TS STAND-IN for the Lean verdict, checked
against the golden by apps/runner/test/ci-push-lane-check.test.ts, twice: with the golden's cones and with the hook's own
globs (`g.preciseInputs`).

Conventions: required lanes come from a `[lanes: a, b]` trailer in any commit of origin/main..tip. A trailer may add
required lanes (case c) but never satisfies case (b): a Lean-only change needs no ci push. The render-guard test's clean
push carries `[ci:wktr]` and a packages/measure-wktr file.

Open: fails open on an internal error (prints a note; accepted). `git push --no-verify` bypasses the hook (accepted). The lead
may add the `[lanes: ...]` trailer to spawn prompts.
Read first: research/notes/2026/10-2x-ci-push-lane-check.md, then the Lean section.
