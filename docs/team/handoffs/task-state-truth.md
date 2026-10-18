# task-state-truth (handoff)

State: branch `worktree-wf_aadbf6f9-218-1`, round 6 (fix round on the round-5 closed design), on round 5 head c0bb618e
and main db41542a. check.sh green; vitest console-api 323, runner 1018, console-web 11.
Root cause (MEASURED, round 1): strict zod `ObsRecord` refused every SubagentStop carrying `background_tasks`.

## Design (round 5, kept)
- Quiet: a live key not sighted within q (`quietMs` = 120 min) shows quiet with `since` = its last sighting, derived
  at query time (`view q now`). No timeout stop exists. Identity keys only: agent id, `wf:<run>`, SpawnGuard obs key;
  names and claims bind keys, never sight or stop (`names_never_sight`, `claim_never_sights`).
- Workflow agents bind the run-name task and their label task; a journal `failed` line stops the id like `result`.

## Round 6
- `tstate` checks the mark before quiet (running still wins over a mark): `mark_ends_quiet`,
  `timeout_ends_only_by_mark`; `timeout_never_ends` and `settle_eq` now need "no mark recorded"; golden
  serve.jsonl case "a mark ends a quiet task" and #guard cases in Core.lean.
- workflow.ts `scanWorkflows` stamps `at`: agent spawn = `agent-<id>.meta.json` mtime (else journal birth, else
  mtime), agent stop = max(journal mtime, run file mtime), run spawn/stop = script/run file mtime. Journal lines carry
  no time. Test: workflow-claim "journal first read after the SubagentStop".
- Prose fixed: Cmd docstring, binding section header, `event_revives` gloss.
- Replay note re-run at main db41542a and this head: `research/notes/2026/10-18-task-state-truth.md`.

## Lead steps
1. Land; restart console-api; let one drain run.
2. Apply `docs/team/backfill/task-state-2026-10-18.jsonl` via `fw send`, one line at a time, actor lead, drop `cite`.

## Stated limits
Forged events; 10-min display lag after restart; a teammate between turns shows quiet; quiet lasts until a stop of
the key or a lead/user mark; a SpawnGuard key has no stop producer, so its task stays quiet until a mark; drain: the
workflow sweep catches its own throws and the spool sweep still runs; a throw inside the spool sweep (store.board,
readdir, a store.submit rejection) skips the remaining spool files until the next drain and is counted
(`svc.sweepError`); sweep-error counts reset on restart; a workflow agent with no `agent-<id>.meta.json`, on a file
system with no birth time, gets its spawn at the journal mtime, which can postdate its SubagentStop (then quiet).
No checker subagent was available (no spawn tool): docstrings self-checked against the 6-point list.

Read first: `lean/Fw/Plan/Core.lean` (search `mark_ends_quiet`), `apps/console-api/src/spool/workflow.ts`.
