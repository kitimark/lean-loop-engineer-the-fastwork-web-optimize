# wk-loop-freeze: the webkit-sim losses after wk-sim-hang are runner-VM freezes, not a blocked node loop

Answer first.

- Both losses are whole-VM freezes (memory exhaustion, swap thrash), not a node loop blocked in our process. MEASURED.
- The 20 s `terminate Safari` overrun in the reboot is a step that has nothing to terminate on a fresh boot, run on a VM that is still loaded. MEASURED overrun, INFERRED mechanism.
- Fix: the silence clock skips a freeze, failed probes from before a freeze are dropped, and the reboot relaunch has no `terminate Safari`. All three are Lean rules (`Fw.Measure.SimHost`, section `Freeze`) with a golden replayed by the TS tests.
- Detection and recovery only: the memory hog and the Simulator daemon load stay follow-ups.

## Loss 1: run 40364461242, job 1 (tick 675 s late, stalled 731 s, exit 3)

| Evidence | Value | Status |
|---|---|---|
| Job log, 17:34:37 | `the 30 s tick came 675 s late; host calls running: []`, then `stalled: no output for 731 s (limit 720 s)` | MEASURED |
| Sampler (own process, `scripts/ci-telemetry/sampler.mjs`) | one gap of 549 s at 17:21:43, another of 153 s at 17:30:52 | MEASURED |
| Swap-outs around the gaps | +109712 pages across the 153 s gap; 591699 pages at the end of the 549 s gap; free memory 10% then 7% | MEASURED |

A node loop blocked in-process would stop only our process; the sampler is a separate process and stopped for the same span. Cause: the VM held every process. In-process block: refuted. Runner log timestamps are receive times, so lines arrive in bursts after the freeze.

The 731 s of silence is 675 s of freeze plus 56 s of real silence. Lean theorem `run40364461242`: raw silence 731000 ms is stalled, silence with the freeze credited is 56000 ms and not stalled.

## Loss 2: run 40349930733, job r2 (glint base; exits 1, 130, 4)

| Attempt | What the log shows | Status |
|---|---|---|
| 1 | ticks 62 s and 89 s late with no host call; sampler gaps 91 s, 95 s, 74 s; swap-outs +94836 and +47268 in the gaps | MEASURED |
| 2 | stalled 747 s, exit 130, no `blocked` warning, no tick data kept | MEASURED; cause not found, follow-up |
| 3 | 18:54:25 tick 46 s late; `2 failed in a row`; `the device is not booted`; reboot: shutdown 1 s, boot 6 s, bootstatus 86 s; then `terminate Safari took longer than 20 s`, exit 4 | MEASURED |

Why `terminate Safari` overran: the reboot builds a fresh device, so Safari is not running and the step has nothing to do. `simctl terminate` on a freshly booted, still loaded device waited past its bound. It took 10 s of 20 s in attempt 1 (MEASURED). That the call waits on the booting launchd of a loaded device is INFERRED. Removing the step removes the failure and 20 s of the recover budget (`plan_fresh`: 300000 ms against 320000 ms).

The guard also counted "2 failed in a row" across a freeze: the first failed probe was from before it. With the rule, a tick the host held starts the streak again. This tick had a host call (`lsof`) just started, so the rule does not count it as held (accepted limit: no host call running is the unit, cpu ratio is logged only).

## Lean rule (`lean/Fw/Measure/SimHost.lean`, `Freeze`)

- `lagMs = since - tick`; `blocked` = lag at least one tick; `frozen` = blocked and no host call running.
- `clockStart` = `min (lastOut + lag) now` when frozen, else `lastOut`; `silence = now - clockStart`. Theorems: `silence_le_raw`, `silence_host_call`, `silence_on_time`, `silence_frozen`, `frozen_as_on_time`, `frozen_not_stalled`, `carried`.
- `failsIn frozen fails` is 0 when frozen: `failsIn_frozen`, `failsIn_still`, `frozen_not_dead`, `stale_streak_dead`.
- `relaunchPlan fresh` omits `terminate Safari` when fresh: `plan_full`, `plan_fresh`, `fresh_no_terminate`.
- Golden ops `silence` (10 cases), `streak` (8), `plan` (2) in `packages/contracts/golden/measure/sim-host.jsonl`, replayed in `packages/measure-webkit/test/sim-host.test.mjs`. Glue tests: `watchdog.test.mjs` (a freeze is not silence; a late tick with a host call counts in full), `guard.test.mjs` (stale streak dropped; reboot relaunch is fresh).

TS stand-ins: none for the decisions (sim-host.mjs reads the golden for the plan and computes the rest as the Lean defs). Glue: the freeze counter and the cpu note in `watchdog.mjs`.

## Follow-ups

- Which process takes the memory (per-process RSS when free memory is below 15%) and the Simulator daemon load.
- Attempt 2 of loss 2 (silent stall without a blocked warning).
- Repair on the first failed probe after a freeze, and socket-gone handling after a freeze.
- Cpu ratio instead of "no host call running" as the freeze signal, once the logged cpu figure shows its spread.

Evidence scripts: `results/wk-loop-freeze/scripts/`; sampler gaps: `results/wk-loop-freeze/data/sampler-gaps.txt`.
