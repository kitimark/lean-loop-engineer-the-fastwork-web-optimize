# fw watch: team health check

`pnpm fw watch` collects a snapshot of the team and the machine, asks `fwcore` (`obs.health`, lean/Fw/Wire/Obs.lean)
for each agent's state (active, idle, parked, stalled, gone, done) and the alerts, prints a table (<= 40 lines) and
appends `{at, input, output}` as one line to `.fw-console/health.jsonl` (in the main checkout). TS holds no health
decision; the rules and their proofs are in lean/Fw/Obs/Health.lean. Rules in words: `watch-rules.md`; what is collected
and from where: `watch-sources.md`.

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

## Reading the table

One row per live agent (name or task, kind `tm`/`sub`/`wf`, type, model, state, minutes since the last event, tool calls,
failed calls, context tokens, in-flight tool and its age), worst states first; then one system line (counts including
`gone`, load, memory pressure, free disk, sim lock, docker, worktrees, CI runs and failures; `stale` after docker or ci =
that collector failed and the value is the previous check's); then the alerts (subject shown as the agent's name; `*` =
tied to a critical-path task, listed first).

Alerts: `agent.toolHang`, `agent.toolSlow`, `agent.gone`, `agent.held`, `agent.unlanded`, `team.overCap`,
`team.permissionWait`, `ci.slow`, `ci.finished`, `proc.long`, `sys.loadHigh`, `timing.slow` (`watch-rules.md`).

## NEXT lines and `pnpm fw next`

Agents that look busy while nothing will happen (handed back but never landed, held by their own dead wait loop, waiting
on CI, near the context limit) get a next action from `fwcore` (`obs.next`, lean/Fw/Obs/Next.lean; golden
packages/contracts/golden/obs/next.jsonl). `fw watch` prints one line per non-`none` action after the table:

    NEXT <agent> <action> <k=v args>      e.g.  NEXT port-nav routeIntegrator branch=wt-port-nav
                                                NEXT ghb-runner killOrphan pid=555 start=1759998680

`pnpm fw next` prints the same list once, exits 0, and is read-only (no log line, no kill, no land): the lead acts.
Actions: `killOrphan pid start`, `land branch task`, `routeIntegrator branch`, `waitCi run`, `waitDeps dep`, `cleanupWorktree`,
`respawnFromHandoff`, `nudgeHandoff`, `claimTask task agent`, `investigate reason`. Nothing to do prints nothing
(`fw next` prints `NEXT: none`). Without a built `fwcore` that knows `obs.next`, `fw watch` prints no NEXT lines and
`fw next` says so. When `land` and `respawnFromHandoff` are proposed: `watch-rules.md`.

## Console push (user events as they happen)

`fw watch --stream` also tails `.fw-console/events.jsonl` (watch on the directory plus a 1 s safety poll, a read from the last offset; a partial line waits for its newline; a rotated or shrunk file is read again from 0). Each new event is classified by fwcore `obs.push` (`lean/Fw/Obs/Push.lean`, golden `packages/contracts/golden/obs/push.jsonl`): lead-facing means actor `user` and type `review.feedback`, `step.answer`, `step.done` or `step.cancel`. Hook and script events and the user's `step.start` / `review.previewed` print nothing. One line per event: `USER <type> <flag or step> <text, 160 characters>`, within about 2 s of the append (measured p50 82 ms, p95 170 ms over 20 appends, `apps/runner/test/watch-push-latency.test.ts`). The OPEN/CLOSE tick lines are unchanged, so one Monitor on the stream replaces the `tail -F | grep user` workaround. Starts at the end of the log (events before the stream started are not replayed). Accepted limits: local Mac, the log stays single-writer, no phone notification.
