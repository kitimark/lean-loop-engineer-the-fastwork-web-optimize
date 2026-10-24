Branch: worktree-wf_fdcc899a-56b-1
Worktree: .claude/worktrees/wf_fdcc899a-56b-1 (repo-relative)
Last commit: see `git log -1` on the branch. CI runs: none (no CI push for this task).

State: Lean model lean/Fw/Ci/State.lean (burst=1000, mayHide, step, go, theorems incl. present_found, go_terminates,
absent_never_in_burst); golden packages/contracts/golden/ci/ci-state.jsonl from lean/scripts/CiStateGolden.lean;
check.sh job "ci-state golden check"; Trigger.lean lean.yml row + triggers.jsonl regenerated; ci.ts stateStep twin
(STATE_BURST); ci-state.test.ts replays the golden incl. run 40100783726 cases.
Verified: `pnpm -s fw ci state 40100783726 --branch ci/earn-webkit-smooth` prints `complete`; ci-paths --check ok.
Open: Fw.Ci.StateList + lean/scripts/StateListGolden.lean + golden/ci/state-list.jsonl are superseded (not replayed);
remove in a follow-up. burst=1000 is an assumption (observed max 345).
Read first: research/notes/2026/10-2x-ci-state-burst.md.
