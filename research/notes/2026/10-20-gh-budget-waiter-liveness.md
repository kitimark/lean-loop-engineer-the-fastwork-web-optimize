# gh-budget: a watch is kept exactly while its waiter lives (2026-10-20)

Follow-up of `10-20-gh-budget-watch-expiry.md`. That task removed the age rule; a sentinel whose waiter died then stayed registered
and pinned the list window. Status of the claims below: CONFIRMED where a Lean theorem or a test is named, INFERRED otherwise.

## Rule

No time constant (no heartbeat, no age). Identity only.

- A waiter writes a marker `r<runId>.<pid>.<hex>` holding `{pid, start}`. `start` is `ps -o lstart= -p <pid>`, read once, an opaque
  token compared for equality (second resolution). The call pins `TZ=UTC` and `LC_ALL=C` (as `PS_START` in
  `apps/runner/src/watch-collect.ts` does), so the token does not depend on the TZ of the process that reads it. Test: recorded by a
  child under `Asia/Bangkok`, read under `UTC`, the watch is kept (it fails without the pin).
- Lean, exactly (`Marker.alive`): `kill(pid, 0)` succeeds (EPERM counts) AND, by the recorded and the current token: both present
  and equal is alive; both present and different (reused pid) is dead; recorded present and current absent (`ps` cannot see the
  pid) is dead (`marker_unreadable`); recorded absent (older code, unreadable text) is alive iff its pid exists (`marker_tokenless`).
- `ci.budget.next` takes `markers` (facts the TS gathered); fwcore runs `sweep(aliveIds markers)` before `createdSince`. A watch with no
  live marker leaves `watched` and gets an incident `{runId, time, why: "orphan"}`. This holds for real runs and sentinels alike.

## Theorems (`Fw.Ci.Budget`, section (j))

| name | says |
|---|---|
| `sweep_keeps_alive` | a watch with a live marker stays |
| `sweep_drops_orphan` | a watch without one leaves `watched` and gains an `orphan` incident |
| `sweep_total` | every watch is still watched or has its incident (nothing vanishes) |
| `next_window_from_live` | the window start of `next` is computed from live watches only |
| `marker_dead`, `marker_reused`, `marker_same`, `marker_tokenless`, `marker_unreadable` (recorded token, `ps` cannot see the pid: dead) | the verdict of one marker |

## Race

`addWaiter` writes the marker and sends `register` inside one state lock. The poller reads the waiters dir inside the lock of its
`next` decision. So a watch without its marker cannot be seen by a sweep. Tests: "no register-before-marker gap" (marker on disk and
lock held when `register` is sent) and "lock order, poller side" (an `env.core` wrapper asserts the state lock is held on every
`ci.budget.next`, so reading markers outside the lock fails).

## Tests (simulated clock, temp dirs)

`packages/gh-budget/test/waiter-liveness.test.ts`: start token, facts for dead / reused / tokenless / non-marker files, a dead
sentinel dropped without widening the window, a live watch kept over ticks, reused pid dropped, tokenless kept or dropped by pid,
nobody alive (no tick, no gh call). Goldens: 8 new wire cases (48 total).

## Folded-in lows

`Limits.missMax` docstring indent, the `#guard registered at 90000` comment, the note `tickCost 20 (pageCap 10 x listCost 2)`, a wire
golden with a watch carrying `registeredAt` that the reply omits, the poller test now asserts a tick happened. Limit (i) of the
watch-expiry note and fw-ci.md is deleted.

## Stated limits

- Source of `lstart`: macOS ps(1) "The exact time the command started, using the %c format described in strftime(3)"; procps ps(1)
  "time the command started". INFERRED: on Linux procps derives it from the boot time plus clock ticks, so a wall-clock step can
  shift it by about 1 s and a live waiter would then be swept (`/proc/<pid>/stat` field 22 would avoid that; not done, this repo
  runs the waiters on macOS).
- The start token has second resolution: a pid reused by a process started in the same second as the dead waiter, with the same pid,
  passes. A pid wraps only after the pid space is used, so this needs the whole space in one second.
- Follow-ups: `dropWaiter` keeps a pid-only refcount shortcut for the waiter's own cleanup (a reused-pid stale marker can stop a clean
  `unregister`, and the next sweep then logs an `orphan`); `readMarkers` never reaps markers fwcore judged dead, so dead tokenless
  markers stay on disk.
- The `onSig` signal wiring is covered through `dropWaiter` tests; a real SIGTERM test of the process is a gap.
- A dropped waiter still learns nothing until its own timeout (unchanged follow-up).
