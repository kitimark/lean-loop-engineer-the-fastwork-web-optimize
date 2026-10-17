# fw watch: team health check

`pnpm fw watch` collects a snapshot of the team and the machine, asks `fwcore` (`obs.health`, lean/Fw/Wire/Obs.lean)
for each agent's state (active, idle, waiting, stalled, done) and the alerts, prints a table (<= 40 lines) and appends
`{at, input, output}` as one line to `.fw-console/health.jsonl` (in the main checkout). TS holds no health decision.

| usage | meaning |
|---|---|
| `pnpm fw watch` | one check, table, exit 0 |
| `--json` | print `{input, output}` instead of the table |
| `--interval <s>` | repeat every s seconds (stay in the foreground) |
| `--until-alert` | repeat (default 300 s) until an alert appears that the previous check did not have; print it, exit 3. The first check is the baseline, so alerts already open do not end the wait |

Lead, in the background (you are re-invoked when it exits 3): `pnpm fw watch --interval 300 --until-alert`
(run it with `run_in_background`; do not poll it).

Reading the table: one row per live agent (name or task, type, model, state, minutes since the last event, tool
calls, failed calls, context tokens, in-flight tool and its age), worst states first; then one system line (counts,
load, memory pressure, free disk, sim lock, docker, worktrees, CI runs and failures); then the alerts (subject shown as
the agent's name). Teammates waiting for a message show as stalled (no event for `stallMin`); that is the real signal.

Sources (read-only; names, counts and times only, never payload text):
- `.fw-console/spool/<agent_id>.jsonl`: tool counts, errors, trailing error streak, Stop, permission notification
  (a Notification newer than the last tool event = waiting).
- `~/.claude/projects/<project>/<session>/subagents/[workflows/wf_*/]agent-<id>.jsonl` + `.meta.json`: name,
  description, model, context size (last assistant usage: input + cache read + cache write), token sums, in-flight
  tool (last tool_use without a tool_result). The newest file with the agent id wins. A transcript-only agent that
  ended with text or a finished `StructuredOutput` call counts as done.
- system: `sysctl kern.memorystatus_vm_pressure_level`, statfs, `.local/locks/sim`, `docker ps` (3 s),
  `git worktree list`, `.fw-console/api.json`, `gh run list` (10 s; skipped on failure).

Scope (collection, not health): agents with no Stop and no event for 24 h are treated as ended; ended agents drop out
1 h later. Params are the Lean defaults (`DEFAULT_PARAMS` in `apps/runner/src/watch-collect.ts`).
fwcore is found via `FW_CORE_BIN`, this checkout, the main checkout, then sibling worktrees, the first that knows
`obs.health`. Env: `FW_CONSOLE_DIR`, `FW_PROJECTS_DIR` (tests).
