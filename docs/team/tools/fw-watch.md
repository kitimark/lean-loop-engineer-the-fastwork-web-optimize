# fw watch for the lead: stream and waits

The checks and alerts themselves: `watch.md`, `watch-rules.md`.

## Stream (Monitor)

Lead, with Monitor, re-armed every 30 min: `pnpm fw watch --interval 300 --stream`

| line | meaning |
|---|---|
| `OPEN <code> <subject> <detail>` | the alert is open now and was not open at the previous check |
| `CLOSE <code> <subject>` | the alert was open at the previous check and is gone now |
| `STREAM END <reason>` | the stream stopped: `signal SIGTERM`, `error <message>`, `exit <code>`; re-arm it |

- One line per change, written unbuffered. The stream never exits on an alert.
- `fwcore ops.watchDiff` (lean/Fw/Ops/WatchDiff.lean) decides the lines. Each alert (code and subject) gets one OPEN,
  and the next line for it is its CLOSE (`opened_once`). An alert open at a check is printed by that check
  (`every_open_reported`).
- Nothing is persisted: each stream starts empty and prints every open alert once (one batch per re-arm).
  Delete that file to have every open alert printed again.
- A check that fails ends the stream with `STREAM END error ...`. SIGKILL prints no last line.
- An alert that opens and closes between two checks is never printed.

## Single-event waits

Use a background Bash call (`run_in_background`), not Monitor: `pnpm fw watch --interval 300 --until-alert` (exits 3
on the first new alert), `pnpm fw ci wait ...`, `pnpm fw land --queue ...`.

## Declared long-runners

`pnpm fw watch --keep <pid> --note "<what>"` records `{pid, start, note}`, where `start` is the process's start time from
`ps lstart` (UTC, seconds). A check exempts the declaration only while a process with that pid and that exact start
runs (`keep_same_process`), so a reused pid is never exempt (`reused_pid_not_kept`). Machine load does not change this.
Entries in the older `startedAt` format are dropped; declare them again.
The lead's Monitor command (`node apps/runner/src/fw.ts watch --interval 300 --stream`, the node process of the
command above) is exempt without a declaration. The allowed command is a constant in Lean (`monitorShapes`) and cannot
be widened at run time.

## Console alert steps

The watch's own alerts above are a separate list from the console's alert steps. A console alert step (posted by the spool drain,
text in `docs/team/tools/console.md`) is for the owner only when Lean says so; lead-fixable ones carry audience `lead` and close
by themselves with a note "resolved automatically at ...". Do not hand-press Done on them.
