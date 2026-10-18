# task-state-truth (handoff)

State: branch `worktree-wf_b39c0afc-f56-1`, code at 7d9a613 (round 2: 318558d Lean, 0da41b5 TS, 7d9a613 backfill and docs).
`check.sh` reports all gates green. The vitest suites pass: console-api 245, runner 605, console-web 4, contracts 7.

Root cause (MEASURED): the strict zod `ObsRecord` rejected every SubagentStop that carried `background_tasks`
(emit.mjs 2a43e6e), so 6376 stops never became `agent.stop`.

## What changed in round 2
- **Admission in Lean** (`Fw.Ops.Obs` `admit`; wire `ops.obs raw`):
  - Known fields are typed and kept; unknown fields are accepted, counted and raised as a spool alert (`fieldAlert`).
  - Rejects carry a reason (`json`, `x:missing`, `x:invalid`).
  - Theorems: `accept_extra`, `accept_known`, `drop_counted`, `mem_unknown`, `fieldAlert_some_iff`.
- **Life in Lean** (`lifeOf`; wire `ops.obs life`):
  - Named SpawnGuard → spawn; SubagentStop → stop at the record time, or counted as unnamed.
  - A tool event is a heartbeat spawn keyed `seen:<name>|<epoch>|<ts/10min>`.
  - `background_tasks` is never read. Theorems: `stop_counted`, `stop_named`.
- **Timed life** (`Fw.Plan`):
  - `Cmd.spawn/stop a ts`; `ended` means a stop at or after the last spawn; `since` is on the board.
  - `plan.timeouts`: a quiet limit of 120 min. Theorems: `ended_eventually`, `stop_ends`, `mem_timeouts`.
  - For a live agent, open blockers beat marks. A park with `folded-no-change` satisfies dependents.
  - Every name of main is refused; the runner sends the full ref of `--into`.
- **Glue:**
  - `drain.ts` calls Lean for each chunk; there is no TS decision left.
  - `health.ts` `NameIndex` reads health.jsonl incrementally instead of scanning 64 MB per stop.
  - Out of scope: `lean/Fw/Console.lean`.
- **Real spool replay (MEASURED)**, read-only, scratch `drainsim.py`:
  - 46371 lines, 0 rejected; 6465 SubagentStop accepted (6108 carry background_tasks).
  - Only 314 are named, because the health index knows 206 ids; the other 6151 are unnamed and fall to the timeout.

## Lead steps
1. Restart console-api.
2. Let one drain run.
3. Apply `docs/team/backfill/task-state-2026-10-18.jsonl` with `fw send`, one line at a time, actor lead (drop `cite`).

## Open items
- After a restart the epochs map is empty, so a heartbeat key can repeat within one 10-minute bucket; the repeat is a duplicate, which is harmless.
- Unnamed stops end only by the timeout: ids missing from health.jsonl need a better name source.
- Agents older than 2 h with no fresh heartbeat time out on the first drain and revive on their next tool event.
- Handback and integrate still have no automatic emitter (hook, `fw land`). A failed Agent call still emits a phantom spawn.

Read first: `lean/Fw/Ops/Obs.lean` (admission and life sections), then `Fw/Plan/Core.lean` "Quiet timeout".
