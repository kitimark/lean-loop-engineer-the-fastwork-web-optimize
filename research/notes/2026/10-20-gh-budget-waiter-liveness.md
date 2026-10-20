# gh-budget: a watch is kept exactly while its waiter lives (2026-10-20)

Follow-up of `10-20-gh-budget-watch-expiry.md`. That task removed the age rule; a sentinel whose waiter died then stayed registered
and pinned the list window. Status of the claims below: CONFIRMED where a Lean theorem or a test is named, INFERRED otherwise.

## Rule

No time constant (no heartbeat, no age). Identity only.

- A waiter writes a marker `r<runId>.<pid>.<hex>` holding `{pid, start}`. `start` is `ps -o lstart= -p <pid>`, read once, an opaque
  token compared for equality (second resolution).
- The marker is alive iff `kill(pid, 0)` succeeds (EPERM counts) and the recorded token equals the token read now. A reused pid fails
  the token. A marker without a token (older code, unreadable text) is alive iff its pid exists. All in Lean: `Marker.alive`.
- `ci.budget.next` takes `markers` (facts the TS gathered); fwcore runs `sweep(aliveIds markers)` before `createdSince`. A watch with no
  live marker leaves `watched` and gets an incident `{runId, time, why: "orphan"}`. This holds for real runs and sentinels alike.

## Theorems (`Fw.Ci.Budget`, section (j))

| name | says |
|---|---|
| `sweep_keeps_alive` | a watch with a live marker stays |
| `sweep_drops_orphan` | a watch without one leaves `watched` and gains an `orphan` incident |
| `sweep_total` | every watch is still watched or has its incident (nothing vanishes) |
| `next_window_from_live` | the window start of `next` is computed from live watches only |
| `marker_dead`, `marker_reused`, `marker_same`, `marker_tokenless`, `marker_unreadable` | the verdict of one marker |

## Race

`addWaiter` writes the marker and sends `register` inside one state lock. The poller reads the waiters dir inside the lock of its
`next` decision. So a watch without its marker cannot be seen by a sweep. Test: "no register-before-marker gap" (marker on disk and
lock held when `register` is sent).

## Tests (simulated clock, temp dirs)

`packages/gh-budget/test/waiter-liveness.test.ts`: start token, facts for dead / reused / tokenless / non-marker files, a dead
sentinel dropped without widening the window, a live watch kept over ticks, reused pid dropped, tokenless kept or dropped by pid,
nobody alive (no tick, no gh call). Goldens: 7 new wire cases (47 total).

## Folded-in lows

`Limits.missMax` docstring indent, the `#guard registered at 90000` comment, the note `tickCost 20 (pageCap 10 x listCost 2)`, a wire
golden with a watch carrying `registeredAt` that the reply omits, the poller test now asserts a tick happened. Limit (i) of the
watch-expiry note and fw-ci.md is deleted.

## Stated limits

- The start token has second resolution: a pid reused by a process started in the same second as the dead waiter, with the same pid,
  passes. A pid wraps only after the pid space is used, so this needs the whole space in one second.
- `dropWaiter` keeps a pid-only refcount shortcut for the waiter's own cleanup (glue, no decision about the budget).
- The `onSig` signal wiring is covered through `dropWaiter` tests; a real SIGTERM test of the process is a gap.
- A dropped waiter still learns nothing until its own timeout (unchanged follow-up).
