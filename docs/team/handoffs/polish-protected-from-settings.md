branch: worktree-wf_590afc95-b3e-1
worktree: .claude/worktrees/wf_590afc95-b3e-1
last commit: see git log (handoff commit on top of "polish: protected_skip proof through polishable")
CI runs: none (accepted limit: no CI run)

# polish-protected-from-settings

Done
- (1) Lean `Fw.Plan.Polish.skipped` now calls `!polishable p` (was `protectedPath p`); `protected_skip` proof goes through `polishable`.
- (1) Test "settings.json Edit rules are covered by the Lean skip rule" (apps/runner/test/polish.test.ts): parses every
  `Edit(...)` ask and deny rule in `.claude/settings.json` (read only), maps `/<dir>/**` to `<dir>/x/y.md` and `/<file>` to `<file>` (a second sample `<dir>/z.md` per dir rule, so a narrower protectedDirs entry fails), asks fwcore
  `plan.polishPlan`: every such path is class skip; an ask rule's path is also named in `protected`. A new Edit rule that
  protectedDirs/protectedFiles/skipRoots do not cover fails the test, as does any shape other than `/path` or `/path/**`.
- (2) CONFIRMED (docs https://code.claude.com/docs/en/permissions, "Read and Edit" table: `/path` = "Path relative to the
  settings source", `Edit(/src/**/*.ts)` -> `<primary working directory>/src/**/*.ts` in project settings; and the local
  settings paragraph: "in a worktree session, a shared rule such as `Edit(/src/**)` matches that worktree's own `src/`
  directory"). So `Edit(/.claude/**)` anchors at the session's primary working directory: in a worktree session it matches
  that worktree's own `.claude/**` (so `.claude/agents/x.md` edits in a worktree prompt), and it does NOT match the main
  checkout's `.claude/worktrees/<wt>/lean/...`. The earlier INFERRED "not matched" holds for non-`.claude/` files only.
  Not checked: a session whose primary working directory is the main checkout editing `.claude/worktrees/<wt>/x` by absolute
  path (the docs do not say; INFERRED: matches, since the path is under `<main>/.claude/`).
- Subagent worktrees (isolation:worktree builders): INFERRED same anchor (the session's primary working directory is the worktree), not checked.

Open: none. Read first: Polish.lean protectedPath, the new describe block in polish.test.ts.
