# fw watch: data sources

What `fw watch` and `fw next` collect (apps/runner/src/watch-collect.ts, next.ts). Observation only: every decision is
Lean's (`watch-rules.md`). Usage: `watch.md`.

## Sources

Read-only; names, counts and times only, never payload text.
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
  `git worktree list`, `.fw-console/api.json`, `gh run list` (through the request budget, `ghCharged`: a wait or stop
  from the budget keeps the previous value, marked stale; `updatedAt` of a completed run is its end).
- processes: `ps -A -o pid=,ppid=,etime=,comm=` (process trees: the shell children of this process's nearest `claude`
  ancestor, named by their first non-shell program, executable basename only; a tree keeps its first name and owner);
  `lsof -a -d 1 -Fpn -p <tree roots>` (3 s; exit 1 for a root that ended meanwhile still counts; the root shell's stdout
  `.../tasks/<id>.output` names the Bash task; the transcript whose `toolUseResult.backgroundTaskId` is that id names
  the owner agent; a foreground call moves to the background after 10 min, so every tree old enough to alert has one);
  `.fw-console/keep.json` (an entry counts while `ps` shows its pid with a start within 2 s of the recorded one).
- GET `/api/plan` (3 s).

A gh, docker, ps or plan failure or timeout carries the previous check's value forward (if <= 1 h old) and lists it in
`system.stale` (`ci`, `docker`, `procs`, `plan`); a program that is not installed, or console-api not running, gives an
empty value, not stale. `prevAt` is the previous check's time (the last line of `health.jsonl`).

## Scope

Agents with no Stop and no event for 24 h are treated as ended; ended agents drop out 1 h later. Params are the Lean
defaults (`DEFAULT_PARAMS` in `apps/runner/src/watch-collect.ts`). fwcore is found via `FW_CORE_BIN`, this checkout, the
main checkout, then sibling worktrees, the first that knows `obs.health`. Env: `FW_CONSOLE_DIR`, `FW_PROJECTS_DIR` (tests).

## Facts per agent for NEXT

Health state (the same check); handback = time of the last `SubagentHandback` tool call in the transcript; branch of the
worktree `agent-<id>`: `rev-list --count main..<branch>`, `merge-base --is-ancestor <branch> main`, queued = the branch
name appears in `docs/team/handoffs/integrate-ports.md`; worktree lock pid from `git worktree list --porcelain` and
`kill -0`; children = the session's Bash trees owned by the agent (same owner lookup as `proc.long`): kind from the root
command line (`waitrun.sh <run> [min]` / `ci wait <run>` = ciWait, `until ...; do ... sleep` = sleepLoop,
lake/vitest/tsc/pnpm test = build, else other), ppid chain, age, the file named in the `until ... <file>` clause with its
mtime and `producerExited` (last line `[exited with code N]`); CI run = the latest `ci/<task>` run of the existing
budgeted `gh run list` call (no extra gh calls); board row = `GET /api/plan` task named like the agent. Command lines are
read to classify and never stored or printed. Limits: a loop outside the session's tree is never seen (only owned trees
are listed); an agent without a worktree has no branch fact.
