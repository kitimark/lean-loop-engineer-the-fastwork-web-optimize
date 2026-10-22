# polish-skip-generated handoff

Branch: worktree-wf_df1d82e3-2d8-1. Worktree: .claude/worktrees/wf_df1d82e3-2d8-1. No CI run (local task, no push).

Cause (CONFIRMED): `fw polish` read the generator-owned set (`genOutputs`) from the main checkout. The path-pix branch
added the `path-pix.yml` row to the golden table, so main's table did not list it, the file was class code, and
comment-sicko deleted the generated guard comment.

Fix: `genOwned` in apps/runner/src/polish.ts unions the main checkout's set with the branch worktree's set; the Lean
rule (`gen_never_edited`, `skip_never_edited`, `classify`) is unchanged and takes the union as its `gen` data. Tests in
apps/runner/test/polish.test.ts: a branch-only workflow row is restored on commit and planned as none; genOwned union and fallback.

Open: the other two lost docstrings (MorphListen.lean, guard.mjs) are comment judgement, out of this task.
Not done: no post-edit `ci-paths --check` revert pass (the identity rule makes it unneeded for table-listed files).
