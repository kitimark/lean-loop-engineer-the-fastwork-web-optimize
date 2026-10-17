# device-lane-web handoff
- Contract: `PlanTask.needs?: string[]`, `PlanTask.lane?: "agent"|"device"` (optional, packages/contracts/src/index.ts). fwcore computes them; console-api passes through (zod parse of LiveBoard; no api code change).
- Web: `apps/console-web/src/Plan.tsx` adds `DeviceLane` panel (ready first, then blocked/running with "waits on", done collapsed in details) and `DeviceBadge` on any task with lane "device". Absent lane renders nothing. No logic in TS.
- Test: `apps/console-web/test/device-lane.test.tsx` (vitest + renderToStaticMarkup; ready/blocked/done device + agent task; no-lane case). Added vitest devDependency and `test` script to console-web.
- Checked: console-web test, typecheck, build pass; console-api tsc passes.
- Open: console-api vitest could not run here (fwcore binary absent in worktree; main Lean build was running). Rerun after `lake build`. Once fwcore emits lane, check one real-board render.
