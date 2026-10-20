# fwcore replay speed and the restart loop (2026-10-20)

Symptom: `decision core failed: fwcore crashed (call 12846 timed out after 10000 ms); it restarts on the next call`.

## Cause (MEASURED, CONFIRMED in source)
- A fresh fwcore replays the log. The real log (14,460 events) took 12.8 s wall, 10.1 s CPU: about 0.7 ms per event.
- lean.ts started each call's 10 s timer when the call was written, also when it queued behind the replay (REPLAY_TIMEOUT_MS
  is 120 s). A call behind a 14 s replay timed out, `poison()` killed the child, the restart replayed again: a loop.
- The cost sat in `Fw.Plan.check`, `.define` branch: `acyclicB` (Kahn) ran over the whole task graph for every
  `task.define` (quadratic), plus `list ++ [x]` appends (O(n)) for spawns, stops, marks and labels in `Plan.exec`.
  A per-event-type split of the log located it; `sample` gave only stripped symbols.

## Fix
- `lean/Fw/Plan/Fast.lean`: `checkFast` tests only the new edges with a depth-first `reach`, because a new cycle must use a
  new edge (`acyclic_upsert_iff`, with `Plan.Inv` giving an acyclic graph). `reach_iff` proves the search exact;
  `checkFast_eq` proves `checkFast s c = check s c` on an acyclic state.
- `Srv.plan` keeps the four record lists newest-first; `unrev_execR` and `inv_unrev` prove the reading `unrev` equals the old
  state, so `replayFrom_spec` (replay is the fold of `apply`) holds unchanged.
- lean.ts: `call` awaits the replay promise before it writes and starts its timer (test: a fake core that replays in 2
  deadlines, a call made meanwhile succeeds, no restart, no timeout incident).
- `obs.backoff` takes `cores`: loaded means `max 1 cores <= load`. Theorems: `restart_when_not_loaded`,
  `wait_when_loaded`, `restart_after_total`, `no_restart_early`, `wait_then_restart`, `wait_pos`, `total_mono`,
  `total_mono_cores`, `incident_8_cores`. The fixed 50 never fired on 8 cores at load 10 to 15.

## Measurement (local debug run, not a result)
| log | old wall / CPU | new wall / CPU |
|---|---|---|
| real, 14,460 events | 12.8 s / 10.1 s | 0.14 s / 0.12 s |
| 4x (keys renamed) | not run | 0.60 s / 0.57 s |

Replay and query output of the old and new binaries is byte-identical on the real log and on the 4x log. Linear replay
is under 2 s at 4x, so no snapshot design is needed.

## Limits
Timing is a local debug measurement. The log format and the event set are unchanged. `backoffDecision` stays a TS stand-in
(the timeout path cannot ask the busy child), checked against the Lean golden.
