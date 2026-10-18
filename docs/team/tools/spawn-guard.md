# Spawn guard (PreToolUse on `Agent`)

Hook: `apps/runner/hooks/spawn-guard.mjs`. Decision: Lean `Fw.Ops.SpawnGuard.decide` through `fwcore ops.spawn`
(the hook only builds the request and prints the answer). Every call is logged to the spool as a `SpawnGuard`
record (`verb` = `decision[:reason]`), in every mode except `off`.

## Mode switch
| Mode | Effect | How |
|---|---|---|
| `enforce` (default) | deny prints `permissionDecision: "deny"` with the reason; `needsApproval` (model `fable`) prints `"ask"`; the spawn does not start on deny | nothing to set |
| `shadow` | log only, no stdout (the old behaviour) | `FW_SPAWN_GUARD=shadow`, or `{"mode":"shadow"}` in `.fw-console/spawn-guard.json` |
| `off` | nothing at all | `FW_SPAWN_GUARD=off` or the file |

The env var wins over the file; an unknown value means `enforce`. fwcore missing, slow or erroring fails open
(the spawn goes ahead, the record says `unavailable`).

## Install (lead only)
Add to `.claude/settings.json` under `hooks.PreToolUse`: matcher `Agent`, command `node apps/runner/hooks/spawn-guard.mjs`.
It is already the shadow hook there today; with this change the same line enforces. To go back, set
`FW_SPAWN_GUARD=shadow` in the environment of the session.

## What is refused (reason, fix)
| Reason | Case | Fix |
|---|---|---|
| `kindMismatch` | a worktree role (lean-prover, part-builder, ...) named without `isolation: "worktree"` (it would run as a teammate in the main checkout, I-272), or a teammate role as an unnamed/nested subagent | add `isolation: "worktree"` |
| `unnamed` | an unnamed call for a role that edits or is not a read-only subagent | give it a name |
| `nameInUse`, `unknownRole`, `nestedEditor`, `rateLimited`, `cap*` | see Lean `Reason` | |

## Allowed (false-positive classes of the shadow log, Lean `fp_classes_allowed`)
- A: a named lead call with `isolation: "worktree"` for plan-editor, researcher or general-purpose (a worktree is never
  less safe than the kind the role names; `okKind`).
- B: an unnamed read-only helper (fork, workflow-subagent, checker, scout, ...), also nested under another agent.
- A task defined after the spawn: the guard reads no task, so nothing to refuse.

Shadow-log counts (spawns the guard saw, 2026-10-17 18:49 to 10-18 03:30): 14 refusals. Class A 9 (plan-editor 6,
researcher 2, general-purpose 1), class B 1 (an unnamed fork), true positives 4 (worktree role named without
isolation: part-builder, measure-engineer, and 2 early records without a role). One more record was `needsApproval`
(model fable). Workflow agents and agents spawned outside the `Agent` tool (SubagentStart only) never reach the guard.
