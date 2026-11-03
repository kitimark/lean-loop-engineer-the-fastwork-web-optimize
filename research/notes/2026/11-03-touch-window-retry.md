---
id: 2026-11-03-touch-window-retry
kind: note
title: "Redo of a refused touch-lock window: priced and proved, run once, 5 of 13 redos recovered and 2 stalled the Simulator; no gain in jobs with every arm at minKept shown"
status: review
created: 2026-11-03
topics: [webkit, simulator, touch, measure, ci]
---

# Touch window retry

Task `touch-window-retry`, branch `worktree-wf_850db9c2-5f8-1`, CI branch `ci/touch-window-retry`. One `smoothness` dispatch (1 of 2 allowed): run 41534838350, 12 simulator
jobs, concurrency 5, free runners. The Simulator is not the phone. One run is one sample; the comparison with touch-window-loss stays open.

## Rule (CONFIRMED, Lean)

`lean/Fw/Measure/WindowRetry.lean`. A redo is one more try of a window the lane just recorded as `noOpen` or `tooShort` (status ok, refused by `touchlock.refusal`).
`verdict` decides in this order: kept, notRedoable (stall, `lockMoved`, any non-ok status), already (one redo per window), noDriver, noTime, redo. Each branch has its own theorem.

- The time gate is `redoFits dl now reserve left := now + blockMs (left + 1) + reserve <= dl`: the redo costs one window and the planned windows left still fit before `deadlineAt job`
  (2 400 000 ms) with the 30 s window reserve. `redo_inside_deadline` and `redo_start_bound` prove the planned walk stays inside the deadline after an admitted redo; `late_noRedo` proves none is admitted past it.
- `outcomeOf`: recovered, noOpen, tooShort, lockMoved, failed. `never_pass_from_failed` and `pass_only_recovered`: only a recovered redo counts as kept; a redo that fails keeps the first row and its
  refusal name (`finalClass`). A declined redo is recorded as noTime or noDriver.
- Pricing, `redos_at_start` 17, `redos_late` 6, `redos_none_at_cut` 0: redos the slack pays for at job start, late in the walk, and at the cut.
- TS: `packages/measure-webkit/src/window-retry.mjs` replays the Lean golden `packages/contracts/golden/measure/window-retry.jsonl` (25 lines, `window-retry.test.mjs`, 10 tests).
  `touchlock-run.mjs` pushes the first row at once and replaces it only when a redo recovers, so a walk abandoned at the deadline keeps the first row.
  Stand-ins (no decision logic): `dl: deadlineMs ?? Infinity` when no deadline is set, the `withRedo` glue, `window-retry-cli.mjs`.

## Price before the run (MEASURED, from runs 41436626306 and 41503168296 artifacts)

A window costs `bodyMs` 38 s (tail 383 s every 17th window in the budget); one redo costs one window. Redo needs the Simulator alive: a stalled window (pageLost, swipeLate, beginLate) is never redone.
In the old data 323 of 2016 planned windows were noOpen or tooShort; they only count if the job lives to use the slack, and 501 windows were lost after a stall.

## Result of run 41534838350 (MEASURED; classified by `window-loss-cli.mjs`, redo outcomes by `window-retry-cli.mjs`)

| | touch-window-loss (7 runs) | this run |
|---|---|---|
| planned windows | 2016 | 288 |
| kept (ok) | 558 (27.7%) | 87 (30.2%) |
| jobs with every arm at minKept | 2 of 84 | 2 of 12 (3 of 12 status-ok) |
| walkDeadline | not a class there | 18 |
| planShort | not counted there | 8 |
| noOpen / tooShort left | 248 / 75 | 16 / 5 |
| restartFailed / jobCut / inspectorDead | stall chain | 90 / 38 / 20 |

Redo outcomes by name: recovered 5, noOpen 5, tooShort 1, lockMoved 0, failed 2, noTime 13, noDriver 0. 13 redos ran (5 recovered, 8 did not); 13 were declined for time.
Redo time 2590 s in 8 jobs. Two redos (jobs 1 and 8) ended in `failed` and each cost 917 s and 1026 s of redo time: the redo hit a Simulator stall, restart needed about 308 s median.
Job 1 ended with the inspector dead; job 8 still finished its 24 windows.

Run state as `fw ci state` gives it: `failed` (the lane is partial by design: 3 of 12 jobs complete, 7, 8 and 10; 9 jobs `incomplete`).

## Reading

- MEASURED: 5 windows were recovered by redo, 8 redo tries gave back the same refusal or a stall. Recovered per redo run 5 of 13 = 0.38.
- INFERRED (small sample): a redo pays only if recovered/ran exceeds the extra stall cost. Break-even p* is about 0.585 from the old data (stalls per ran window times windows lost after a stall, 501 over 36 stalled jobs);
  0.38 observed is below it. The data neither proves nor refutes it: 13 trials.
- INFERRED (mechanism): redos mostly sit in cold rep 0, where noOpen is most common; the redo meets the same cold page and refuses again. A redo also adds push lines to `sim.log`,
  so the window-loss `firstStall` index (counted from push lines) drifts by the redo count in this run.
- MEASURED: `blockMs (left + 1)` declined 13 redos early; the gate is conservative because it prices the tail window as if it came next.
- The kept share moved from 27.7% to 30.2%; jobs with every arm at minKept were 2 of 84 and are 2 of 12 (12 jobs only, a sample). The dominant loss is the stall chain (restartFailed 90), outside this task.

## Limits and follow-ups

- Stall chain (restart failures) is a closed Simulator limit, out of scope. A second dispatch was not spent: it would stay a sample of 12 jobs.
- Follow-up: a warm-up window before rep 0 instead of a redo; isolate the noOpen cause; make `firstStall` count rows, not push lines; `rowClass` applies the refusal only when status is ok.
