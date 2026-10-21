# reap-auto-stop handoff
Branch worktree-wf_19c39b39-743-1. Read first: docs/team/tools/reap.md, lean/Fw/Ops/Reap.lean, apps/runner/src/reap.ts.

State
- Lean: branches A/B/C selection, stop plan, kill plan, verify, script, theorems, golden reap.jsonl (27) and lspreap.jsonl.
- TS: reap.ts executor (stopSelected, reapTick, reapCli), fw reap --list|--stop, fw land hook, fw watch tick.
- Teardown: build-review preamble line; land.ts runCheck children get their own group and die on SIGINT/SIGTERM/exit.

Verified
- apps/runner vitest all green, incl. 7 real process-tree tests (TERM, KILL, pid-reuse, live never touched) and stubbed glue.
- lean/scripts/check.sh at the final commit.

Local lane (evidence, not a measurement): `fw reap --list` on this Mac printed "nothing leftover". `fw reap --stop` was
denied by the permission classifier, so no stop ran locally.

Incident: an early non-hermetic test run TERMed two unrelated real processes (pids 4444, 4480) chosen by Lean relative
to a temp repo; fixed by hermetic gather and signal guard in the tests.

Open
- Console display of reap.stopped needs a contract command plus console-api/web edits (not done).
- checks.ts spawnRunner (land checks) still spawns without its own group; outside allowed writes.
- fw ci wait uses short gh calls only; nothing to stop. Linux path (/proc cwd) untested locally; CI is Linux.
- Groups with unselected members are signalled per pid. MCP servers not stopped.
