---
id: 2026-11-01-end-pin-followups
kind: note
title: "End pin follow-ups: one writesLive over a pin policy, the trace only with the page hook, the lockedCmp selection"
status: review
created: 2026-11-01
topics: [webkit, ios, scroll, morph, pin, lean, measure]
---

# End pin follow-ups

Task `end-pin-followups`, the review follow-up of `end-pin-trace` (`research/notes/2026/11-01-end-pin-trace.md`). There was no CI run. Lean, site and measure-webkit unit tests only. The look class stays L and the user's review is still pending.

## Answer

- **One function gives both counts (PROVED in Lean, `lean/Fw/Parts/EndPin.lean`).** A `Policy` (`Pin → Int → Bool`) is the write decision at one reading, with that reading's own target (`Ev.idle ms s`). `stepBy may` gives a pin its step. The end pin's `step` is `stepBy mayWrite` by definition. The faithful pin is `faithMay q s = (q.b ≠ s)`, which writes the target at every reading that is off it. `writesLive may` counts the writes made in a `live` state and is the same function for both pins.
  - `writesLive_zero_of`: a policy that writes only outside a live state makes 0 such writes on every event list. `writesLive_zero` instantiates it at `mayWrite` through `mayWrite_not_live`.
  - The faithful pin goes through the same `writesLive`. `faith_writesLive_witness` gives 2 on `liveEvents`, the list where `end_writesLive_witness` gives 0. `faith_writesLive` gives the count for a frame-by-frame reading list (`faithEvents`: each move is followed by a reading at 0 ms): one per move off the target. `faith_writesLive_pos` gives at least one write for any move off the target.
  - `faith_play` proves `playBy faithMay` over `faithEvents` equals `faithOut`, so `faith_fights_witness` is a statement about this same step function. `playBy_mayWrite` proves `playBy mayWrite = play`.
  - The separate counter `faithWritesLive` (fixed `s`, counting moves) is gone, together with `pass` and `faithWritesLive_eq`.
- **Goldens.** Regenerated from Lean: `packages/contracts/golden/measure/touch-lock.jsonl` (128 lines).
  - Each `pinPlay` row carries `writesLive` (at `mayWrite`, 0 in 12 of 12 rows), `faithWritesLive` (the same function at `faithMay`, greater than 0 in 5 of 12) and `faithPositions`.
  - The `pinFaith` rows carry their `faithEvents`.
  - A new play row, "readings while a pan is live", is `liveEvents`.
  - The TS twin is `writesLive(may, p, es)` in `end-pin.live.ts`, with `play(p, es, may)` and `idle(..., may)` in `end-pin.logic.ts`. `end-pin.golden.test.ts` checks every row, and the driver replays all 12 play rows.
- **The shipped END_PIN computes no trace.** `withPinTrace` (`end-pin.trace.ts`) defines `env.trace` as a getter that returns `window.__fwPinTrace`, or `undefined` when the page has no hook. The driver reads `env.trace` at every reading. With no hook, it never calls `outcome` or `dueWhy`.
  - The touch-lock harness installs the hook after the page loads (`touchlock-run.mjs`, `installJs` after `loadFresh`). The getter picks the hook up at the next reading.
  - `end-pin.trace.test.ts` spies on `outcome` and `dueWhy`. With no hook, neither is called and the pin still writes 0. With a hook installed after mount, both are called and the trace sees the write.
- **Provenance.** The end-pin entry in `apps/site/src/parts/morph.tween/part.json` lists `writesLive_zero` (through `writesLive_zero_of`), the faithful witnesses on the same function, and the target-per-event theorems (`writes_target`, `write_is_target`, `due_write`, `observe_write`, and `pin_fights_zero` and `play_no_turn` for any targets, `quiet_no_write` with its premise).
  - The limit says no write is made while a touch is down or within 120 ms of the last page move or touch the pin read.
  - That this covers momentum is INFERRED. A deceleration that emits no scroll event for 120 ms reads as quiet, and the Simulator showed scroll events 286 ms apart in one deceleration.
- **lockedCmp states its selection.** `summarize` adds `verdicts.ranked`: for each arm, the runs with a stored lock out of the accepted runs. `markdown` prints the line "lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out", followed by the counts per arm. A test checks the counts, the line, and that `lockedCmp` gives the same result on the locked subset alone.

## Limits

- Momentum coverage stays INFERRED. `writesLive_zero` is about the pin's own readings, not about UIKit's deceleration.
- `rankedText` and `withPinTrace` are display and I/O glue. They hold no decision. The per-arm counts reuse `lockedOf`, which is checked against the Lean `lockedCmp` golden.
