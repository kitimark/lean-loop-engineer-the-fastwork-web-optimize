---
id: 2026-11-01-end-pin-trace
kind: note
title: "The end pin's writesLive metric, the target per event, and a pin decision trace in the touch-lock lane"
status: review
created: 2026-11-01
topics: [webkit, ios, scroll, morph, pin, touch, lean, measure]
---

# The end pin: writesLive, target per event, and a decision trace

Task `end-pin-trace`, the follow-up of `end-pin-no-fight` (`research/notes/2026/11-01-end-pin-no-fight.md`). WebKit cites stay as in that note (`@862f17d`). The CI Simulator is not the phone; phone feel is not measured here. Look class stays L, the user's review is pending.

## Answer

- **The end pin makes no write while a touch or momentum is live, for every event list (PROVED in Lean).** `Fw.Parts.EndPin.writesLive_zero : writesLive p es = 0` counts a write made in a `live` state (`live q = q.touching || q.since < quietMs`). The faithful pin (write the target at once after each page move) has `writesLive > 0`: `faith_writesLive_witness` is 2 for `[down, move 90, up, move 60]`, and `faith_writesLive_pos` gives at least one for any move off the target. `pin_fights_zero` is kept. A metric that counts fights only (as `fights` does) cannot tell the two apart when the user never lands on the target; `writesLive` can, with no stored lock.
- **The target gap is closed by stating the policy with a target per event (PROVED in Lean, checked against 11 golden play rows).** `Ev.idle ms s` carries the target of its own reading. The driver recomputes `rpTarget` at every `restPin`, so a write goes to the target of its own reading; `pin_fights_zero` and `play_no_turn` hold for any targets because a write is never a turn. The one weaker lemma, `quiet_no_write`, needs every target equal to the page position and says so. Three new play rows change the target between events; the driver test replays them (`end-pin.golden.test.ts`).
- **A pin decision trace is in the lane (MEASURED, CI Simulator, run ids below).** Per pin window the page records every `restPin` outcome: `inactive`, `touch` (down or up), `moved`, `touching`, `live`, `onTarget`, `reversal`, `write` (with its y), and `due` (with the wait). Lean names the reasons (`why`, `outcome`, `dueWhy`, each with an iff theorem) and counts them (`traceCounts`); the lane's table is the Lean count over the same names.
- **`cmp` prints `n/a` for fights when an arm has no stored lock (PROVED, `lockedCmp`).** A run with no open scrollTo call has no stored lock, so its fights are 0 by definition; comparing that 0 with a base arm's count read `lower`. `lockedCmp` compares only runs that stored a lock and reads `n/a` when an arm has runs but none stored a lock. The pin arm's verdict in dispatch 1 is `n/a`, not `lower`.

## What the trace showed

(see the section "CI results" below)

## Limits

- The CI Simulator is not the phone. There is no across-job verdict. A long touch-lock job can lose its artifact, and a Simulator that does not start ends a job with 0 windows.
- The trace shows the pin ran and what it decided. It does not show that a deceleration emits a scroll event at least every 120 ms (INFERRED from the frame cadence, still open).
- Class L: the page may rest off the target after a pan. The user's look review is pending.
