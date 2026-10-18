# task-state-truth (handoff)

State: branch `worktree-wf_d935f448-1a8-3`; see `git log -1` there. Lean builds, `lake test` passes, and the
contracts, console-api, runner and console-web vitest suites pass.

Cause (MEASURED): `ObsRecord` is `.strict()` and lacked the `background_tasks` field that `emit.mjs` adds to
Stop and SubagentStop records. The drain therefore counted every stop as invalid and dropped it without a log
line, so no `agent.stop` reached the plan and claimed tasks stayed `running` forever.

## What changed
- **Lean `Fw.Plan` (Core and Graph):**
  - four new commands: `task.handback`, `task.integrate`, `task.park` and `task.unpark`. They write to `State.marks`, and the last mark per task wins.
  - `outcomeOf` derives a board row's mark. When every candidate agent has ended and no mark exists, the row gets `parked noHandback`.
  - `tstate` has three new states: handedBack, integrated and parked. A row is `running` only when it has a live agent and no blockers.
- **Theorems:**
  - `bound_running_live` and `view_running_no_blockers`: a running row has a live agent and no blockers.
  - `view_done_landed`: a done row has landed evidence.
  - `ended_state` and `ended_outcome`: a row whose agents all ended is done, handedBack, integrated or parked.
  - `integrate_main_refused`, `view_det` and `markOf_step_self/other`.
  - The compat and perm theorems were updated for marks.
- **Authority:** `Fw.Console.mayList` allows handback for hook/script/lead, integrate for git/script/lead, and park/unpark for lead/user/script.
- **Wire:** `Fw.Wire.Plan` gains the new commands and a `TaskView.outcome` JSON field. The goldens in `golden/plan/serve.jsonl` have 4 new cases.
- **Glue:**
  - `obs.ts` accepts `background_tasks`.
  - `drain.ts` logs rejected records to `spool-rejects.jsonl` and sends no stop when `background_tasks > 0`.
  - `health.agentNameOf` scans back up to 64 MB of health lines.
  - New command `fw task handback|integrate|park|unpark`.
  - `plan.ts` and `Plan.tsx` show an ENDED section with labels.
- **Backfill (not applied):** `docs/team/backfill/task-state-2026-10-18.jsonl` has 40 events. Each carries a `cite`
  field, which zod strips. Apply them with `fw send` one line at a time, actor lead.

## Open items
- **Stand-ins in TS:** the stop-skip rule `(background_tasks ?? 0) === 0` and the reject-reason format are written in TS and not proved in Lean.
- **No automatic emitter:**
  - Handback: the hook does not emit it yet. The idea is to detect the handoff commit in `watch-collect.ts:307`.
  - Integrate: `fw land` does not emit it either. Both are manual `fw task` calls today.
- **Same agent id:** a teammate's SubagentStop at each turn end is keyed `stop:<agent_id>`, so only the first one counts as an end.
- **Phantom spawn:** a failed Agent call still emits `agent.spawn` (not fixed here).

Read first: `lean/Fw/Plan/Core.lean`, the section "Task outcomes"; then `tstate` and `outcomeOf`.
