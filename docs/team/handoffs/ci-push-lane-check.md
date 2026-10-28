branch: worktree-wf_30808c70-1bc-1
worktree: .claude/worktrees/wf_30808c70-1bc-1 (under the main checkout)
last commit: 9ca7c1a62 (feature); later commits add the incident fix, this handoff and the main merge
CI runs: none (the task needs no CI push; the hook refuses locally)

State: done pending the final check.sh, runner tests and dry land (see the report).

What it is: the ci/* pre-push hook refuses a push that runs no measuring lane. Decision in Lean
`Fw.Ci.Intent` (section "The push lane check", lean/Fw/Ci/Intent.lean): `reason`, `refuseNoLane`, `pushRefused`; theorems
`refuse_iff`, `refuse_same_tree`, `refuse_missing`, `refuse_no_measuring`, `accept_iff`, `main_never_refused`,
`token_lane_runs`, `started_requested`, `missing_token_refused`, `same_tree_no_measuring`. Golden
packages/contracts/golden/ci/pushlane.jsonl (written by `lake test -- --write-ci-trigger-golden`, same call as intent.jsonl).

TS: apps/runner/src/ci-push.ts (`laneRefusal`, `laneReason`, `lanesTrailer`) is a TS STAND-IN for the Lean verdict, checked
against the golden by apps/runner/test/ci-push-lane-check.test.ts; lane starts come from `decide` in
.github/scripts/changed-inputs.mjs (golden-checked against intent.jsonl).

Conventions: required lanes come from a `[lanes: a, b]` trailer in any commit of origin/main..tip (one source; see
research/notes/2026/10-2x-ci-push-lane-check.md for why). A branch that requires lanes is judged on them alone, so
`[lanes: lean]` lets a Lean-only task push. The existing render-guard test now ends its clean ci push with a
`[lanes: lean]` commit.

Open: lead may add the `[lanes: ...]` trailer to spawn prompts. scripts/hooks/pre-push comment still names only the render
guard (outside the task's writes). `git push --no-verify` bypasses the hook (accepted).
Read first: the note above, then the Lean section.
