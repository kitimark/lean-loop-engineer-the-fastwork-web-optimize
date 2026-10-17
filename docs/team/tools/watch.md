# fw watch: team health check

`pnpm fw watch` collects a snapshot of the team and the machine, asks `fwcore` (`obs.health`, lean/Fw/Wire/Obs.lean)
for each agent's state (active, idle, parked, stalled, done) and the alerts, prints a table (<= 40 lines) and appends
`{at, input, output}` as one line to `.fw-console/health.jsonl` (in the main checkout). TS holds no health decision;
the rules and their proofs are in lean/Fw/Obs/Health.lean.

| usage | meaning |
|---|---|
| `pnpm fw watch` | one check, table, exit 0 |
| `--json` | print `{input, output}` instead of the table |
| `--interval <s>` | repeat every s seconds (stay in the foreground) |
| `--keep <pid> [--note <text>]` | declare an intended long-runner: writes `{pid, startedAt, note}` to `.fw-console/keep.json`; a missing pid is an error |
| `--unkeep <pid>` | remove that declaration (entries whose process has ended or whose pid now names a newer process drop out on every write and every check) |
| `--until-alert` | repeat (default 300 s) until an alert appears that the previous check did not have; print it, exit 3. The baseline is the last line of `health.jsonl`, so a relaunch after exit 3 does not re-report the alert it exited on, and alerts already open do not end the wait (no log yet: the first check is the baseline) |

Lead, in the background (you are re-invoked when it exits 3): `pnpm fw watch --interval 300 --until-alert`
(run it with `run_in_background`; do not poll it). An `--interval` run declares its own pid in `keep.json` while it runs.
A long-running helper of the lead (a monitor script, a server): `pnpm fw watch --keep <pid> --note "<what>"`.

Reading the table: one row per live agent (name or task, kind `tm`/`sub`/`wf`, type, model, state, minutes since the
last event, tool calls, failed calls, context tokens, in-flight tool and its age), worst states first; then one system
line (counts including `gone`, load, memory pressure, free disk, sim lock, docker, worktrees, CI runs and failures; `stale` after
docker or ci = that collector failed and the value is the previous check's); then the alerts (subject shown as the
agent's name; `*` = tied to a critical-path task, listed first).

States (Lean `state`, first match): **done** = stopped, or a workflow agent whose workflow run finished, or a
transcript-only workflow agent silent >= `wfQuietMin` (30) min; **gone** = not stopped but silent > `goneAfterMin`
(120) min: it has ended without a Stop, so it is not live (not in `team.overCap`, not a holder for the sim lock or
docker checks, not a child that turns a long `Agent` call into a wait); **parked** = a teammate with no tool in flight whose
last tool was `SendMessage` or whose last `TeammateIdle` is newer than its last tool (it waits for a message on
purpose; no stall alert); **stalled** = silent >= `stallMin` with no tool in flight or a hung one; **idle**; **active**.
A tool in flight >= `toolHangMin` is `agent.toolHang`, except an `Agent` or `SendMessage` call while a child agent
(`parent` = this agent) is live: that is a wait. `team.overCap` counts live non-lead agents and names them by kind.
Slow work (this replaces the lead's ad-hoc monitor; every threshold is strict `>` except the load):
`agent.gone` once, at the first check that sees the agent gone (the previous check, `prevAt`, did not; the first check
raises it for every gone agent); `agent.toolSlow` = a tool in flight > `toolSlowMin` (15) min, with the same wait
exception as `toolHang`; `ci.slow` = a run queued, waiting or in progress > `ciSlowMin` (20) min; `ci.finished` = a run
the previous check saw running > `ciSlowMin` has completed since then: its conclusion and duration, once;
`proc.long` = a process tree this Claude session started through its Bash tool, alive > `procMaxMin` (20) min, unless
it is declared or its owner is live. Declared = its root program is on the checked-in allowlist `keepProgs`
(`caffeinate`), or the tree holds this `fw watch` process, console-api (`services`) or a pid in `keep.json` (`keep`).
Owner = the agent whose Bash call started the tree; a tree of a live agent (not stopped, not gone) is that agent's own
business (its `until ...; do sleep 60; done` loop), so it alerts only as an orphan after the agent ended or went gone,
with detail `alive N min, agent <id> ended`. Trees with no owner (the lead's own) alert as before; `sys.loadHigh` = the floor of the 1-min load average
>= `loadMax` (150).
Critical path: the snapshot's `critical` is GET `/api/plan` `.criticalPath` (task ids). An agent is tied to task c when
its id, name or task is c or c-<digits>; a CI run when its branch is `ci/c` or `ci/c-<digits>`. Their alerts carry
`critical: true` and fwcore sorts them before all others (then by code, subject, detail).
`team.permissionWait`: a Notification in the lead's spool is newer than the lead's last tool event. Hook Notifications
carry no agent id, so this is team-level; limits: any lead tool event clears it, and Notifications also fire for idle
input prompts, not only permission prompts.

Sources (read-only; names, counts and times only, never payload text):
- `.fw-console/spool/<agent_id>.jsonl`: tool counts, errors, trailing error streak, Stop, last tool and its time,
  last `TeammateIdle`. A Start or tool event after the last Stop = resumed; a teammate's Stop followed by
  `TeammateIdle` = turn end, not exit (INFERRED from 4 teammate spools).
- `.fw-console/spool/main.jsonl` (events with no agent id): the lead's last tool event and last Notification.
- `~/.claude/projects/<project>/<session>/subagents/[workflows/wf_*/]agent-<id>.jsonl` + `.meta.json`: name,
  description, model, context size (last assistant usage: input + cache read + cache write), token sums, in-flight
  tool (last tool_use without a tool_result), last tool (fallback when there is no spool). Kind: meta `taskKind`
  containing `teammate` = teammate; under `workflows/` or with `workflowPhase` = workflow; else subagent. Parent: the
  agent whose transcript holds the `Agent`/`Task` call whose id is the child's meta `toolUseId` (none = the lead).
  Workflow done: `<session>/workflows/<wf>.json` has a `status` other than running/pending. The newest file with the
  agent id wins. A transcript-only agent that ended with text or a finished `StructuredOutput` call counts as stopped.
- system: `sysctl kern.memorystatus_vm_pressure_level`, statfs, `.local/locks/sim`, `docker ps` (3 s),
  `git worktree list`, `.fw-console/api.json`, `gh run list` (through the request budget, `ghCharged`: a wait or stop from the budget keeps the previous value, marked stale; `updatedAt` of a completed run is its end),
  `ps -A -o pid=,ppid=,etime=,comm=` (process trees: the shell children of this process's nearest `claude` ancestor,
  named by their first non-shell program, executable basename only; a tree keeps its first name and owner),
`lsof -a -d 1 -Fpn -p <tree roots>` (3 s; exit 1 for a root that ended meanwhile still counts; the root shell's stdout `.../tasks/<id>.output` names the Bash task; the
transcript whose `toolUseResult.backgroundTaskId` is that id names the owner agent; a foreground call moves to the
background after 10 min, so every tree old enough to alert has one), `.fw-console/keep.json` (an entry counts while
`ps` shows its pid with a start within 2 s of the recorded one), GET `/api/plan`
  (3 s). A gh, docker, ps or plan failure or timeout carries the previous check's value forward (if <= 1 h old) and
  lists it in `system.stale` (`ci`, `docker`, `procs`, `plan`); a program that is not installed, or console-api not
  running, gives an empty value, not stale. `prevAt` is the previous check's time (the last line of `health.jsonl`).

Scope (collection, not health): agents with no Stop and no event for 24 h are treated as ended; ended agents drop out
1 h later. Params are the Lean defaults (`DEFAULT_PARAMS` in `apps/runner/src/watch-collect.ts`).
fwcore is found via `FW_CORE_BIN`, this checkout, the main checkout, then sibling worktrees, the first that knows
`obs.health`. Env: `FW_CONSOLE_DIR`, `FW_PROJECTS_DIR` (tests).
