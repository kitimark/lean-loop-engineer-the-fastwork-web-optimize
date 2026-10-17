# pa-land handoff

State: `fw land` is usable for every landing (plain agent branches included). Commit: see `git log -1 pa-land` on branch worktree-agent-a16e352bda27255a5.

## Lead usage (run from the main checkout, console-api up)
    pnpm fw land worktree-agent-<id> --task <task-id>            # merge --no-ff, Task: trailer, checks, cleanup, plan sync
    pnpm fw land worktree-agent-<id> --task <id> --allow 'docs/x/**'   # explicit extra scope, recorded as `Land-Allow:` in the merge message
A task whose `writes` are empty in docs/team/work-graph.json is refused with the changed files: add writes, or pass --allow.
card/<CARD> branches still work (readiness + land_request); without --task they fast-forward and need --allow (no writes exist).

## What it does
- Scope: Lean `Fw.Console.Land.landVerdict` via op `console.landScope` (route /api/ops/land-scope). Scope = task writes + docs/team/handoffs/<task>.md and <owner>.md + generated (`**/*.gen.json`, packages/contracts/golden/**, lean/golden/**, lean/math.lock.json) + registrations (lean/Fw.lean, lean/Fw/Wire.lean, lean/FwTestMain.lean, apps/runner/src/fw.ts) + --allow, minus protected (.fw-console/, .git/, .claude/settings*, lean/.lake/), which win over everything.
- Writes are read from main's docs/team/work-graph.json (the board does not carry them).
- `git merge --no-ff --no-commit`, then marker grep (`^<<<<<<<|^>>>>>>>`), checks (derived: lean/ -> lean/scripts/check.sh; apps|packages/<n> -> pnpm --filter ./<n> test), then commit. Any failure -> `git merge --abort`, main unchanged. Never rebases, pushes, forces.
- Evidence: the `Task:` trailer only (reconciler derives task.done; land no longer sends task.done). Then plan sync (fw.ts `after`).
- CI: one `gh run list --branch ci/<task>`, advisory. Cleanup: `branch -d` only; worktree removed only if clean, unlocked, not cwd; a locked one (live agent pid) is reported and kept with its branch.

## Theorems (lean/Fw/Console/Land.lean)
matchesPath_dir_prefix (d/** implies head = d), outside_every_glob_refused, excluded_refused, noWrites_refused, landVerdict_ok_iff; #guard cases incl. protected paths.

## Open / notes
- Files outside the write list that I touched (needed): apps/console-api/src/ops/routes.ts (new route), lean/Fw/Wire/Console.lean (op), lean/Fw/Ops/Golden.lean (golden cases), packages/contracts/golden/console/console.landScope.jsonl (generated).
- apps/runner/test/e2e-land.sh still lands card/A without --allow and will now be refused: add `--allow '**'` to its land calls (not my file).
- The hooks timing test may flake under load. Read first: apps/runner/src/land.ts, apps/runner/test/land-scope.test.ts.
