# land-hardening handoff

State: committed on branch worktree-agent-af026a23eb35d35ef (see `git log -1`). `sh lean/scripts/check.sh` and `pnpm --filter ./apps/runner test` green (204 tests).

Read first: `lean/Fw/Console/Land.lean` (protocol model, lock, guard, pick, scope), `apps/runner/src/land.ts` (task path), `apps/runner/hooks/land-guard.mjs`.

What was done (incidents inc-commit-during-land, inc-land-scope-registrations, inc-agent-on-ci-branch, inc-fw-lean-import-conflict):
- Land lock `<git-common-dir>/fw-land.lock` (JSON pid/token/at/branch/pre/dir, created with `wx`). Released in `finally` and on SIGINT/SIGTERM. Checks now run async (spawn) so the signal handlers run during a check.
- pre-commit hook (`scripts/hooks/pre-commit` runs `land-guard.mjs`): refuses commits while a live land holds the lock, except the land's own (env FW_LAND_TOKEN). Fail closed when a lock exists and fwcore is missing. Stale lock (dead pid): commit and next land refused, lock NOT removed, message says what to do.
- Before committing, Lean `console.landCommit` checks lock + MERGE_HEAD + HEAD == pre; otherwise no commit, no reset, prints main/pre.
- landScope takes `task`+`stream`: kind from id (port-*, proof-*) / stream measure; per-kind registration sets; protected stays refused. Goldens regenerated (landScope, landLock, landGuard, landCommit, landPick).
- Branch choice: `console.landPick` (unique qualifying candidate among `ci/<task>` and worktree branches whose dir ends with the stem of `worktree-<stem>`; otherwise refuse).
- lean/Fw.lean: a CHECK, `lean/scripts/check-imports.mjs` (in check.sh): no repeated import, every import exists, every Fw module reachable (or root/driver allowlist DRIVER_RUN). `merge=union` KEPT in .gitattributes: a hand-kept list still conflicts textually without it and a check cannot prevent that; the check catches what union can break (duplicates, orphans).

Files edited outside the task writes (land needs `--allow`): lean/Fw/Ops/Golden.lean, apps/console-api/src/ops/routes.ts, scripts/hooks/pre-commit (lean/Fw/Wire/Console.lean is under the registrations glob).

Lean docstrings fixed after math review r13 (protectedGlobs list with `!`, testGlob/testGlob_eq_some with possibly-empty rest).

Open: pre-commit of other worktrees only checks their own checkout (`dir` in lock); `plan.ts` untouched (claim-order-lean).
