# reap-watch-one-rule handoff
Branch worktree-wf_e07fe309-bfe-1, worktree .claude/worktrees/wf_e07fe309-bfe-1, main work in 95e9777ec (+ handoff commits). No CI runs (accepted limit).
Rule (lean/Fw/Ops/Reap.lean, section "Branches E and F"): pickE = until-loop shell in this repo, tool call ended (LoopFact.callLive false),
>= orphanMinSec old, no live writer (writerLive: a Waiter of the same worktree id writing the awaited path, its pid+start in the table).
pickF = Simulator device (kind simDevice) started before the last sim slot release, simHolders 0, simGraceSec passed.
reapOne/planOne = reapAll/planAll + E/F; `held` = the orphanLoop selections; theorem held_in_plan (alert identity is a TERM target).
Ops: ops.lspReap/ops.reapPlan now use reapOne; new ops.reapHeld. Row is unchanged (Fw.Wire.Sup round-trips it); loop facts ride in `loops`.
Goldens: packages/contracts/golden/ops/reap-one.jsonl (19 rows: case 1 pid 2846 selected, case 2 pid 40204 with live waiter kept,
case 3 Simulator selected, reused pid, other agent, other path, callLive, young, sim holder/after release/grace/no release).
Glue (apps/runner/src/reap.ts): classify untilLoop/simDevice, awaitedPath, isCiWait + lsof fd 1,2 for waiter stdout, simctl `fw-` names,
slot state.json for simIdleSince/simHolders. apps/runner/src/watch-reap.ts: agent.held alert from ops.reapHeld, wired in watch.ts pass().
Tests: apps/runner/test/reap-one.test.ts (golden replay, glue parsers, alert == stop on a fixture).
TS stand-ins: none for decisions. Unproved glue: callLive := ppid > 1; waiter file := stdout path from lsof; sim name filter via simctl.
Open: (a) Next.lean/next.ts still raise their own killOrphan agent.held (outside writes); retire once this alert is trusted.
(b) the tick (reapTick) now auto-stops E/F selections, as for A-D. (c) sim stop is TERM/KILL of launchd_sim, not `simctl shutdown`.
(d) rule exercised on fixtures only. (e) docs/team/tools/reap.md has no E/F section yet (outside this task's writes; lead adds it). Read first: Reap.lean E/F section.
