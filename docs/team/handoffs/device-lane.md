# device-lane handoff

State: committed on the worktree branch (`git log --grep "device-lane"`); lean `check-fast.sh` green (lint 0 failing),
contracts 7/7, runner 135/135, console-api 201/201, console-web tsc clean.

## Done
- Lean: `Task.needs` / `Def.needs` (wire `needs`, string array, missing = `[]`, at most 8). `Fw.Plan.lane t = device`
  iff `"device" ∈ needs` (`lane_device_iff`, `lane_agent_iff`); `readyIn ts l`; `ready_split`: READY = READY_agent ⊎
  READY_device (Perm + disjoint). `groups` / `parallelSafe` now cover only agent-ready tasks (`groups_perm`).
- Wire: every plan task carries `needs: string[]` and `lane: "agent" | "device"` (`Fw/Wire/Plan.lean`).
- Goldens: `packages/contracts/golden/plan/{serve,work-graph}.jsonl` regenerated (new case "lanes: …").
- `packages/contracts/src/index.ts`: `task.define.needs` optional, `PlanTask.needs`, `PlanTask.lane` (`TaskLane`);
  JSON schemas regenerated (`pnpm --filter @fw/contracts gen`).
- Runner: `fw plan sync` sends `needs` only when non-empty (old task keys unchanged); `fw plan show` prints a
  `DEVICE (needs you + the iPhone):` block after READY (ready rows, then blocked with blockers); BLOCKED lists agent
  lane only.
- work-graph.json: `needs: ["device"]` on q1-phone, gap-device, phone-session-1, calibration; new swipe-baseline,
  gap-light (M3, lead, deps []).

## Open
- console-web `Plan.tsx` (console-builder): parallelSafe no longer holds device tasks; show the device lane from
  `tasks[].lane`.
- work-graph `about` text does not yet mention `needs` (left alone to ease the plan-editor merge).

## Read first
`lean/Fw/Plan/Core.lean` (section "Lanes"), `apps/runner/src/plan.ts` (`renderPlan`).
