# pa-land handoff (updated by pa-sync-main)

State: `fw land` usable for every landing. Commits: branch worktree-agent-a6a2cc54dc4208211 (pa-sync-main + four land fixes).

## Lead usage (main checkout, console-api up)
    pnpm fw land worktree-agent-<id> --task <task-id> [--allow 'docs/x/**']   # merge --no-ff, Task: trailer, checks, cleanup, plan sync
A task with empty `writes` is refused with the changed files; card/<CARD> branches also do readiness + land_request.

## Post-commit behaviour (new)
- Cause of the "fetch failed" exit 1: any throw after the merge commit (reconcile/verify fetch, or the internal sync) escaped to fw.ts, skipping cleanup and sync. Suspect also `localhost` -> ::1 against a 127.0.0.1 listener: `httpFor` now dials 127.0.0.1.
- Each step (reconcile, verify, cleanup, plan sync) is tried twice; one that still fails is listed under "WARNING ... run these in the main checkout" with its command. Exit 0 once main moved (`ok` = main changed). Non-zero only when main is unchanged.
- Internal plan sync goes through `/api/commands` (no capability): the single-use cap of the `pnpm fw land` call is spent by a card's land_request, and the hook mints caps only for `pnpm fw ...`. Hook untouched.
- Checks write to `.fw-console/land-logs/<task>-<sha7>.log` (gitignored); one line per check; a failure prints FAILED, the log path and the last 30 lines.
- Evidence: `writeEvidence` puts the branch head's 7-char sha into docs/team/work-graph.json inside the merge commit (only if the task has none). Back-filled ghb-glue 901481f, pa-land 50434d4, pa-evidence-lint 2d743c5.
- `fw plan sync` (and the internal sync) refuse unless run in the main checkout with HEAD = main (`syncRefusal` in plan.ts).

## Lean (lean/Fw/Console/Land.lean)
Scope = writes + `testGlobs` (apps|packages/<n>/src/** write admits <n>/test/**) + handoffs + generated + registrations (now also lean/Fw/Wire/**.lean, lean/Fw/*/Wire.lean) + allow + protected.
Theorems: testGlob_eq_some, landScope_mem_tests, landScope_protected_suffix, plus matchesPath_dir_prefix, outside_every_glob_refused, excluded_refused, noWrites_refused, landVerdict_ok_iff. Golden console.landScope.jsonl regenerated.

## Notes
- Files outside the write list touched: apps/runner/src/fw.ts (wiring), docs/team/work-graph.json (back-fill), packages/contracts/golden/console/console.landScope.jsonl (generated). pa-sync-main `writes` lists only plan.ts: land it with --allow for those.
- `lean/Fw/Wire/**.lean` matches one directory level (a segment glob), not deeper.
- Tests: apps/runner/test/land-post.test.ts (dropped console, evidence, log, sync location).
