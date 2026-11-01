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

- **The pin ran in every pin window (MEASURED, 10 pin windows in 2 dispatches, CI Simulator).** Every window has `ran = yes`, so the earlier "0 writes" reading (no trace) is now a decision, not silence. 2 dispatches, 4 jobs started, 4 result files, 3 with windows; the numbers are the lane's own trace table (`touch-lock.md`) over the entries between the first touchstart and the stop of the window. "Pin calls seen" counts every call since the page loaded, so it can be one above the in-window entries (calls before the first touchstart).

| run | job | window | state | pin calls seen | inactive | touches | due | moved | writes | declined: touching / live / onTarget / reversal |
|---|---|---|---|---|---|---|---|---|---|---|
| 41285184069 | 2 | 3 | refused `noOpen` | 24 | 19 | 4 | 0 | 0 | 0 | 0 / 0 / 0 / 0 |
| 41285184069 | 2 | 5 | open, no lock | 10 | 2 | 4 | 0 | 2 | 0 | 1 / 0 / 0 / 0 |
| 41289882234 | 1 | 3 | open, no lock | 24 | 4 | 4 | 1 | 5 | 0 | 4 / 0 / 0 / 5 |
| 41289882234 | 1 | 5 | open, no lock | 27 | 6 | 4 | 2 | 5 | 0 | 3 / 1 / 0 / 5 |
| 41289882234 | 1 | 11 | open, no lock | 18 | 2 | 4 | 0 | 3 | 0 | 4 / 0 / 0 / 4 |
| 41289882234 | 1 | 13 | open, no lock | 17 | 2 | 4 | 1 | 3 | 0 | 1 / 1 / 0 / 4 |
| 41289882234 | 1 | 19 | open, no lock | 22 | 6 | 4 | 0 | 3 | 0 | 4 / 0 / 0 / 4 |
| 41289882234 | 1 | 21 | open, lock 51890 | 33 | 5 | 4 | 5 | 6 | 1 | 4 / 3 / 3 / 1 |
| 41289882234 | 2 | 3 | open, no lock | 26 | 4 | 4 | 2 | 5 | 0 | 4 / 1 / 2 / 3 |
| 41289882234 | 2 | 5 | refused `tooShort` | 16 | 0 | 2 | 0 | 0 | 0 | 1 / 0 / 0 / 1 |

  Run `41285184069` job 1 gave 0 windows (the Simulator never opened a tab: `simctl openurl` timed out, "push server: no ready file after 285 s"; a harness fault, not this code). Run `41289882234` is the second and last dispatch; its job 1 walked all 24 windows (861 s), its job 2 stopped after 8 (`the touch lane ended`).
- **One write was made in 10 windows, and it was not live (MEASURED).** Window 21 of run `41289882234` job 1: the finger lifted, the page then moved at 10429, 10717, 10838, 10959, 11080 and 11124 ms (page clock); `due` was scheduled after each reading; the write `5191 -> 5189` happened at 11245 ms, 121 ms after the last move or touch, finger up. That is the Lean `write_of_clear` case, and the write time equals the scrollTo call time in the row (`calls: [[51890,1,11245]]`, the site's stored value, units of 0.1 px). The other 9 windows made no write: 7 ended on a `reversal` decline with the page 1 to 90 px short of its target (a write would turn the page around; job 1 windows 3, 5, 11, 13, 19: 7, 31, 27, 90, 31 px; job 2 windows 3 and 5: 1 and 3 px), the class-L look change measured for the first time as a decision; 1 was never active (dispatch 1 window 3, 19 of 24 calls `inactive`); 1 ended at a touch end with no later entry (dispatch 1 window 5, the gap dispatch 2 closed).
- **The decline at a touch end is traced since dispatch 2 (MEASURED).** Dispatch 1 had no entry when a finger lifted off a page the pin would not write to (the due check returned nothing and the lane saw no reading). Dispatch 2 adds `dueWhy` (Lean: `dueWhy_ne_live`, `due_none_of_dueWhy`, `dueWhy_none_of_due`): all 8 windows of dispatch 2 end with a decline right after the last touch end: `reversal` in 7, `onTarget` in 1 (the window with the write).
- **Fights (MEASURED, not decided).** Run `41289882234` job 1, fights per run: orig `7 2 3 3 4 6`, base `1 3 1 3 3`, lock `4 1 5 1 1 1`, pin `0 0 0 0 0 0`. Five of the 6 pin runs stored no lock, so their 0 is by definition and `cmp` reads `n/a`; the sixth stored lock 51890 with fights 0, and one locked run is below the sample floor, so `pin vs base` reads `undecided`, not `lower`. The honest sentence: the pin made 0 fights, and the trace shows why (it never wrote in a live state); the metric cannot yet rank it against base because the pin arm rarely writes.

## What the Lean numbers say about the trace

- `writesLive_zero` (every list), `end_writesLive_witness` (a list with 2 moves and a write: 0 live writes), and the 11 golden play rows (`writesLive = 0` in all) against `faithWritesLive > 0` in at least one. The trace's single write is the case the proof describes: clear, quiet, finger up.
- `outcome_declined_silent`: a decline makes no write, so the windows that ended on a decline made no write, and the trace names which condition held.
- `traceCounts` replays the lane counts (5 golden cases, `pinTrace`).

## Limits

- The CI Simulator is not the phone. There is no across-job verdict. A long touch-lock job can lose its artifact, and a Simulator that does not start ends a job with 0 windows.
- The trace shows the pin ran and what it decided. The readings in the windows are 38 to 507 ms apart (`dt` of the 32 `moved` entries), so a gap above 120 ms between scroll events exists on the Simulator; it is a wake from the timer, not a proof of the phone's cadence (INFERRED). Whether a real deceleration emits a scroll event at least every 120 ms stays open.
- One of 10 windows has a pin write. A write is rare in this walk (the pin usually declines `reversal`), so the lane cannot yet rank the pin against base by fights; more locked pin runs would need a walk that ends the pan on the target side.
- Class L: the page may rest off the target after a pan. The user's look review is pending.
