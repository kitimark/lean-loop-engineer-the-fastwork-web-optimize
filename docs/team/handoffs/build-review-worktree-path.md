branch: worktree-wf_23b1b99a-2c5-1
worktree: .claude/worktrees/wf_23b1b99a-2c5-1
last commit: 2b0d85106 (item 2)
CI runs: none (no CI push; the task needs none)

# build-review-worktree-path (item 2 only)

Done (item 2)
- Lean `Fw.Plan.Polish`: `protectedDirs` (`.claude/`), `protectedFiles` (`CLAUDE.md`) = the `ask` Edit rules of
  `.claude/settings.json`; `protectedPath`, `polishable`; `skipped` includes `protectedPath`, so classify = skip.
  Theorems: `protected_skip`, `claude_dir_protected`, `claude_md_protected`, `protected_never_scoped`, `protected_not_kept`,
  `polishable_iff`. `.local/` (deny rule) was already a skip root.
- `plan.polishPlan` replies `protected`; `fw polish plan` prints `skip <path> (protected)` (apps/runner/src/polish.ts).
- Golden row (polish.jsonl, regenerated with FW_WRITE_POLISH_GOLDEN=1), vitest asserts, real-git test "plan skips a protected path".
- docs/team/tools/polish.md names the rule.

Followed up, not done: item (1), because .claude/ edits wait on the user. Lead applies with the user present:
- .claude/agents/comment-sicko.md, add to its steps before the first edit: "Before your first edit run
  `git -C <worktree> rev-parse --abbrev-ref HEAD`; it must print exactly the branch you were given. If the worktree path is
  not absolute (starts with ~ or a placeholder) or the branch differs, edit nothing and reply `refused: not on branch`."
- .claude/workflows/build-review.js (Polish, near the comment-sicko prompt): pass the branch `${b.branch}` with the worktree
  `${wt}` and the same sentence; add a test in scripts/build-review.test.mjs that the prompt contains `rev-parse --abbrev-ref HEAD`.
  (The `wt` regex at build-review.js:~120 already rejects a ~ path before comment-sicko starts.)

Read first: lean/Fw/Plan/Polish.lean (protectedPath), apps/runner/src/polish.ts plan branch.
