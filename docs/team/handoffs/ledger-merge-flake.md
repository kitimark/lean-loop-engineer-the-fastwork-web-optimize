Branch worktree-wf_c2cf5595-49f-1; worktree .claude/worktrees/wf_c2cf5595-49f-1; no CI runs pushed.
State: note research/notes/2026/10-2x-ledger-merge-flake.md; no code change (no deterministic repro within budget).
Verified: failing line is setup's `git checkout -qb a` (128, branch exists); a re-init of a surviving .git yields exactly it.
Open: why .git survives rmSync on the CI runner (inferred: detached git gc/maintenance); candidate fix in the note.
Read first: the note.
