# watch-proc-allow handoff

State: branch of task watch-proc-allow (commit with trailer `Task: watch-proc-allow`), on top of 9000c1b.

What changed
- Lean `obs.health` (lean/Fw/Obs/Health.lean): `Proc.agent` (owner agent id), `System.keep` (pids the lead declared).
  `procLongB` = not `declaredB` (program in `keepProgs` = [caffeinate], or tree holds a `services`/`keep` pid) and
  not `ownerLiveB` (owner agent present and `live`) and age > `procMaxMin`. An orphan's detail names its agent.
  Proofs: `procLong_iff`, `ownerLive_quiet`, `declared_quiet`, `procLong_sound`, `orphan_raised`; `health_mono` kept.
- Wire (lean/Fw/Wire/Obs.lean): `procs[].agent?`, `system.keep?`, round trips proved. Golden: 73 cases.
- Runner: `fw watch --keep <pid> [--note t] | --unkeep <pid>` writes `.fw-console/keep.json` ({pid, startedAt,
  note}; an entry counts while ps shows the pid with a start within 2 s). `--interval` runs declare themselves.
  Owner: `lsof -a -d 1 -Fpn -p <roots>` gives `tasks/<id>.output`; transcripts' `toolUseResult.backgroundTaskId`
  maps id -> agent. lsof exits 1 when one pid ended: the Runner's `anyExit` keeps its stdout (that bug hid all owners).

Conventions: Lean first, TS holds no rule; ShadowLint (no binder named like a function in the same formula).

Gate: check.sh green; runner tests 112/112; `pnpm fw watch` from the worktree: 7 alerts before -> 1 after
(sys.diskLow only); caffeinate quiet by allowlist, agents' gh/sleep loops attributed to live agents, the lead's
Python monitor declared via `--keep` (main checkout keep.json).

Open items
- The lead's own Bash trees (no agent) still alert after 20 min; Monitor-tool streams have a socket stdout, no task
  id, so they need `--keep` (no heuristic by design).
- A subagent's foreground Bash call < 10 min has no task id yet; it is too young to alert anyway.

Read first: docs/team/tools/watch.md (proc.long paragraph, Sources), Health.lean section "Long-running processes".
