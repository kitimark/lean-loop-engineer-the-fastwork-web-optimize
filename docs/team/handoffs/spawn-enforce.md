# spawn-enforce (handoff)

State: done on branch worktree-agent-a75b9f07c0e9c592d (see `git log -1`). Lean check.sh green, apps/runner tests 271 pass.
The live .claude/settings.json is untouched: the lead decides when to land (the hook already runs there; it now enforces by default).

What changed
- Lean `Fw.Ops.SpawnGuard`: `okKind` (a worktree run satisfies any role kind; only "worktree role not given a worktree" stays a
  mismatch), `prodRoles` (adds `fork`, `workflow-subagent`), classes `ClassA`/`ClassB`, theorems `fp_classes_allowed`,
  `deny_names_reason`, `isolation_not_mismatch` (replaces `teammate_with_isolation_denied`), `Reason.code`.
- Hook `apps/runner/hooks/spawn-guard.mjs` (+ `.d.mts`): mode `enforce` (default) | `shadow` | `off` via `FW_SPAWN_GUARD` or
  `.fw-console/spawn-guard.json`; deny/ask printed as PreToolUse permission decision; fails open. Doc: docs/team/tools/spawn-guard.md.
- Shadow log (14 refusals): class A 9 (plan-editor 6, researcher 2, general-purpose 1) now allowed; class B 1 (unnamed fork) now allowed;
  4 true positives (worktree role named without isolation) stay refused: incident `inc-worktree-role-as-teammate`.
- Files outside my write list: lean/Fw/Ops/Golden.lean (case title), packages/contracts/golden/ops/ops.spawn.jsonl (regenerated).

Open items
- `Reason.code` duplicates `Fw.Ops.Wire.reasonFields` strings (not touched); `ROLES` in the hook mirrors `prodRoles` by hand.
- Workflow agents never reach the guard (SubagentStart only); the `workflow-subagent` row is a precaution.
- The 2 early records had no role logged, so are counted as true positives by default.
