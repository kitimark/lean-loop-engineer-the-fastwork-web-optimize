# wk-loop-freeze: the webkit-sim losses after wk-sim-hang are runner-VM freezes, not a blocked node loop

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

A node loop blocked in-process would stop only our process; the sampler, a separate process, has gaps of 549 s and 153 s (17:21:43 to 17:33:25, one sample at 17:30:52) covering the 705 s in which node did not tick; both processes stalled, so the cause is outside our process. Cause: the VM held every process. In-process block: refuted. Runner log timestamps are receive times, so lines arrive in bursts after the freeze.

The 731 s of silence is 675 s of freeze plus 56 s of real silence. Lean theorem `run40364461242`: raw silence 731000 ms is stalled, silence with the freeze credited is 56000 ms and not stalled.

## Loss 2: run 40349930733, job r2 (glint base; exits 1, 130, 4)

| Attempt | What the log shows | Status |
|---|---|---|
| 1 | page target lost, reboot (bootstatus 60 s), then terminate Safari done in 10 s of 20 s on the fresh boot; exit 1 later | MEASURED |
| 2 | stalled 747 s, exit 130, no `blocked` warning, no tick data kept | MEASURED; cause not found, follow-up |
| 3 | ticks 62 s (18:50:15) and 89 s (18:54:08) late with no host call; sampler gaps 91 s, 95 s, 74 s with swap-outs +94836 and +47268; 18:54:25 tick 46 s late (lsof running); socket gone, device not booted; reboot: shutdown 1 s, boot 6 s, bootstatus 86 s; then terminate Safari took longer than 20 s, exit 4 | MEASURED |

Why `terminate Safari` overran: the reboot builds a fresh device, so Safari is not running and the step has nothing to do. `simctl terminate` on a freshly booted, still loaded device waited past its bound. It took 10 s of 20 s in attempt 1 (MEASURED). That the call waits on the booting launchd of a loaded device is INFERRED. Removing the step removes its 20 s and its overrun (`plan_fresh`: 300000 ms against 320000 ms). The next simctl call (launch Safari, bound 90 s) runs on the same loaded device, and no run shows it passes there (INFERRED).

The 18:54:25 probe came after a frozen tick (89 s at 18:54:08, no host call), so `failsIn` drops the streak to 1, but the socket was gone and the device not booted, so the inspector is dead either way (Lean `frozen_not_dead` needs socket = true). For loss 2 the streak rule does nothing; the fresh relaunch is the rule that applies.

## Lean rule (`lean/Fw/Measure/SimHost.lean`, `Freeze`)

- `lagMs = since - tick`; `blocked` = lag at least one tick; `frozen` = blocked and no host call running.
- `clockStart` = `min (lastOut + lag) now` when frozen, else `lastOut`; `silence = now - clockStart`. Theorems: `silence_le_raw`, `silence_host_call`, `silence_on_time`, `silence_frozen`, `frozen_as_on_time`, `frozen_not_stalled`, `carried`.
- `failsIn frozen fails` is 0 when frozen: `failsIn_frozen`, `failsIn_still`, `frozen_not_dead`, `stale_streak_dead`.
- `relaunchPlan fresh` omits `terminate Safari` when fresh: `plan_full`, `plan_fresh`, `fresh_no_terminate`.
- Golden ops `silence` (10 cases), `streak` (8), `plan` (2) in `packages/contracts/golden/measure/sim-host.jsonl`, replayed in `packages/measure-webkit/test/sim-host.test.mjs`. Glue tests: `watchdog.test.mjs` (a freeze is not silence; a late tick with a host call counts in full), `guard.test.mjs` (stale streak dropped; reboot relaunch is fresh).

TS stand-ins: none for the decisions (sim-host.mjs reads the golden for the plan and computes the rest as the Lean defs). Glue: the freeze counter and the cpu note in `watchdog.mjs`.

## Re-measure on CI (2 of 2 dispatches, `ci/wk-loop-freeze` at b3f0299cb, webkit-sim, target rewrite, 3 VMs each)

| Run | Arm | Jobs lost / total |
|---|---|---|
| 40390428285 | base | 2 / 3 (r2 exit 4, r1 job timeout) |
| 40390434234 | flag `platform.glint:hold-freeze` | 0 / 3 |
| both | | 2 / 6 (wk-sim-hang: 0 / 7) |

The rate did not fall, and the two base losses are not the two classes fixed above. MEASURED; the mechanisms are INFERRED.

| Job | What the log and telemetry show | Class |
|---|---|---|
| base r2 (121811602882, exit 4 after 31 min) | no `blocked` or `stalled` line; warm-up `Runtime.evaluate` timed out after 120 s, no page target after 484 s, relaunch failed at `terminate Safari` (20 s), then `simctl shutdown` ETIMEDOUT; sampler gaps at most 34 s, swap-outs 26180 | Simulator wedged under load, not a VM freeze |
| base r1 (121811602912, cancelled after 58 min, log not kept; the job limit is INFERRED to be the cause) | last sampler row 22:26:27, then nothing for 34 min: sampler and tick uploads stopped together, so the whole VM or runner went away; free memory 70% at the last row | VM lost, nothing in-process can end it |

What worked: the stall limit and the guard ended base r2 in 31 min with exit 4 and named causes instead of the 50 min step limit. The `terminate Safari` overrun now shows up in the first (non-fresh) relaunch too: the freeze fix does not cover a wedged device. No kept re-measure job logged a late tick: the freeze rule and the stale-streak rule never fired on CI (the 74 s sampler gap of flag r1 at 21:22:11 was before the measure process started). The re-measure does not test the fix; it shows only that the 4 kept jobs still pass with it. MEASURED.

Host load1 was 800 to 920 at the last row of every job, successes included (cpu 100%), so it does not separate lost from kept jobs.

## Follow-ups

- The Simulator wedge of base r2: `simctl` calls and the inspector time out with no VM freeze (sampler steady). Needs the daemon and process state when the first `Runtime.evaluate` timeout happens.
- Base r1: a VM that vanishes for 34 min is outside a node watchdog; the job limit (58 min) is the only end.

- Which process takes the memory (per-process RSS when free memory is below 15%) and the Simulator daemon load.
- Attempt 2 of loss 2 (silent stall without a blocked warning).
- Repair on the first failed probe after a freeze, and socket-gone handling after a freeze.
- Cpu ratio instead of "no host call running" as the freeze signal, once the logged cpu figure shows its spread.

Evidence scripts: `results/wk-loop-freeze/scripts/`; sampler gaps: `results/wk-loop-freeze/data/sampler-gaps.txt`.
