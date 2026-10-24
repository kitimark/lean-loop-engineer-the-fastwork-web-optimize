# fw watch: state and alert rules

The rules `fwcore` applies (`obs.health`, `obs.next`, `obs.slow`; lean/Fw/Obs/Health.lean, Next.lean). Usage: `watch.md`;
what is collected: `watch-sources.md`.

## States

Lean `state`, first match:
- **done**: stopped, or a workflow agent whose workflow run finished, or a transcript-only workflow agent silent >=
  `wfQuietMin` (30) min.
- **gone**: not stopped but silent > `goneAfterMin` (120) min. It ended without a Stop, so it is not live (not in
  `team.overCap`, not a holder for the sim lock or docker checks, not a child that turns a long `Agent` call into a wait).
- **parked**: a teammate with no tool in flight whose last tool was `SendMessage` or whose last `TeammateIdle` is newer
  than its last tool (no stall alert).
- **stalled**: silent >= `stallMin` with no tool in flight or a hung one.
- **idle**, then **active**.

## Alerts

Every threshold is strict `>` except the load.
- `agent.toolHang`: a tool in flight >= `toolHangMin`, except an `Agent` or `SendMessage` call while a child agent
  (`parent` = this agent) is live: that is a wait.
- `team.overCap` counts live non-lead agents and names them by kind.
- `agent.gone` once, at the first check that sees the agent gone (the previous check, `prevAt`, did not; the first check
  raises it for every gone agent).
- `agent.toolSlow`: a tool in flight > `toolSlowMin` (15) min, with the same wait exception as `toolHang`.
- `ci.slow`: a run queued, waiting or in progress > `ciSlowMin` (20) min. `ci.finished`: a run the previous check saw
  running > `ciSlowMin` has completed since then: its conclusion and duration, once.
- `review.feedback`: one per flag with an open comment on its review card (the user's `review.feedback` events not yet answered by
  a `review.feedback.reply`), detail `N open; newest: <first 120 characters>`. Closes when the lead replies (`docs/team/tools/review-feedback.md`).
- `proc.long`: a process tree this Claude session started through its Bash tool, alive > `procMaxMin` (20) min, unless it
  is declared or its owner is live. Declared = its root program is on the checked-in allowlist `keepProgs`
  (`caffeinate`), or the tree holds this `fw watch` process, console-api (`services`) or a pid in `keep.json` (`keep`).
  Owner = the agent whose Bash call started the tree; a tree of a live agent (not stopped, not gone) is that agent's own
  business (its `until ...; do sleep 60; done` loop), so it alerts only as an orphan after the agent ended or went gone,
  with detail `alive N min, agent <id> ended`. Trees with no owner (the lead's own) alert unless declared.
- `sys.contended`: the floor of the 1-min load average is above `Fw.Obs.Timing.contendedLoad` (8, one load unit per CPU of the 8-CPU Mac); one
  alert for the whole machine, with the load, the `lake` builders and the heavy-lock holders in the detail
  (`sysContended_iff`). Hysteresis: once open it closes only when the floor falls to `calmLoad` (4) or below
  (`sysContended_opens`, `_closes`, `_between`); the previous state rides in `system.load.prevContended`. Replay (INFERRED) of the
  local timings: 5, 32, 25, 25, 12 opens per day (10-17..10-21) before, 1, 11, 6, 14, 2 after. Accepted limit: 60-96%
  of local lean/check samples per day are still contended; CI timings are the backstop. Timed steps measured while the load is above 8 are contended samples: they never raise `timing.slow`
  (Lean `contended_not_slow`).
- `sys.loadHigh`: the floor of the 1-min load average >= `loadMax` (150).
- `team.permissionWait`: a Notification in the lead's spool is newer than the lead's last tool event. Hook Notifications
  carry no agent id, so this is team-level; limits: any lead tool event clears it, and Notifications also fire for idle
  input prompts, not only permission prompts.
- `agent.held`: the Reap plan holds the loop (pid+start); `NEXT killOrphan` names the same entry.
- `agent.unlanded`: `land` or `routeIntegrator` proposed (handed back, branch ahead of `main`, not landed). False once
  main's history has a commit with the task's `Task:` trailer (`onMain`), even if the branch is gone, and while the live
  land lock names the branch (`landLock`). Proofs: `no_unlanded_once_on_main`, `alert_suppressed_iff_locked`.
- `timing.slow <tool>/<step>` (with `NEXT investigate step=<tool>/<step>`): `fw watch` and `fw next` send the spans of
  `.fw-console/timings.jsonl` to fwcore `obs.slow` (`Fw.Obs.Next.slowSteps` over `Fw.Obs.Timing` verdicts: the latest
  sample of a step is slow). No threshold in TS. A sample taken at load above 8 is contended and is never the slow one (`slowSteps_uncontended`);
  a regression that shows at normal load still raises it (`slow_through_contention`). Limit: a load that stays above 8 for a whole run hides a regression from the local alert; CI timings are the check for that.

Critical path: the snapshot's `critical` is GET `/api/plan` `.criticalPath` (task ids). An agent is tied to task c when
its id, name or task is c or c-<digits>; a CI run when its branch is `ci/c` or `ci/c-<digits>`. Their alerts carry
`critical: true` and fwcore sorts them before all others (then by code, subject, detail).

## NEXT proposals

`land` is proposed only for a branch that merges into `main` cleanly (`git merge-tree --write-tree main <branch>` exits 0)
and has no unlanded dependency (it contains no other unlanded agent branch, and the dependencies of its task on the
board are done). Otherwise: `waitDeps dep=<first dependency>` or `investigate reason=conflict`. `respawnFromHandoff` is
proposed only for a stalled or gone agent whose task is on the board and not done and whose
`docs/team/handoffs/<name>.md` exists (an agent without an open task gets nothing). Retention: an ended agent stays in the
snapshot after the 1 h window while its worktree directory exists (`hasWorktree`); Lean's `keepB`
(`keep_of_open_action`) says which ended agents have an open action, and the TS pre-filter only skips agents without a
worktree. Limitation (INFERRED): an unlanded branch whose worktree directory is gone is not seen.
