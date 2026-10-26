---
id: 2026-10-2x-push-cycle-separate
kind: note
title: "Push cycles, cycle versus clock: on the Simulator the rise of slow frames is undecided for both arms (run 3 had no clock-matched cycle inside its 12-cycle pass; run 2 lost too many dwell passes); layers and backing memory are flat per cycle"
status: review
created: 2026-10-26
topics: [end-of-page, touch, simulator, webkit, push-cycle, census, ci]
---

# Push cycles: is the rise driven by the cycle count or by the clock

Task push-cycle-separate, follow-up of `10-2x-push-cycle-lag.md` (the slow share rises with the cycle index; the index is also the pass clock).

## Answer

- MEASURED (Simulator, GitHub macOS, real touches, three CI pushes): **rewrite undecided, user undecided.** No arm earns cycle-driven or clock-driven. A side under 3 passes is undecided, never a win (Lean `sepMinPasses`).
- Run 40315679172 (push 3, the one that counts; 6 VMs, all jobs green): rewrite 5 full passes and 6 dwell passes, user 4 full and 6 dwell. Both arms read `undecided:noRoom`. The dwell pass took 2.39 times (rewrite) and 2.37 times (user) the full pass period instead of the planned 2, so the clock-matched index of cycle 5 is `(5 * 2391 + 500) / 1000 = 12` and a 12-cycle pass has cycles 0 to 11: the matched window runs off the pass (Lean `sep_noRoom`). The rule refuses; the harness did not hold the planned stretch (rest cap and touch time).
- Run 40297879483 (push 2): rewrite 4 full, 3 dwell, `undecided:inseparable` (stretch 1.69: rate by cycle index 152166 and by clock 163666 per 1000 frames are too close, Lean `separable`); user 6 full, 2 dwell, `undecided:fewDwell`. Vm 3 job failed; lost passes: rewrite full vm 1 and 5, dwell vm 1, 3 and 4; user dwell vm 1, 2 and 5.
- Runs 2 and 3 pooled (not planned; same code design except the bundle removal, evidence only): rewrite 9 and 9 `undecided:inseparable`, user 10 and 8 `undecided:noRoom`.
- Run 40284577163 (push 1, per-cycle xcodebuild design, evidence only): sims 2 and 3 failed, 1 cancelled stale; not read.
- INFERRED, no verdict: in run 3 the dwell passes (one cycle per touch run, census and rest between) read fewer slow frames over cycles 3 to 5 (rewrite 84666, user 98200 per 1000 frames) than the full pass by index (184533, 129333) and by clock (154700, 111000). So the continuous touch run costs more than the same cycles spread over a longer time; that points away from a pure clock effect, but the rule needs a clock-matched window inside the pass and the harness did not give one. A fix for the rise is a later task.

## H4: layers and backing memory per cycle

MEASURED (run 40315679172, census after each cycle of the dwell passes, Lean `across`/`readCensus`): rewrite layers no, backing bytes no (6 of 6 passes flat), layers created mixed; user layers mixed (1 of 6 passes rises), backing bytes no, layers created mixed. Mean backing bytes before and after the full pass: 119.4 MB (rewrite), 106.4 MB (user); after the dwell passes 121.5 MB and 107.3 MB. So neither layer count nor backing memory grows with the cycle: H4 (memory grows per cycle) is refuted on this lane for both arms (the rise is not a leak of layers or backing store). Runs 2 and 3 pooled give the same reading (backing bytes flat in every pass).

## Method

Per arm (rewrite, user) per VM: one `full` pass (12 cycles, one continuous touch run) and one `dwell` pass (6 one-cycle touch runs; a census and a rest between runs that fills the period to 2 times the full pass period, `restMs`). Counted window per cycle = open stretch + 8 s. Metric: slow >50 ms frames per 1000 frames, cycles 3 to 5 by index against the clock-matched index, with the dwell passes by index. Rule: Lean `Fw.Measure.PushCycle.sepVerdict`, a theorem per branch (`sep_fewFull`, `sep_fewDwell`, `sep_noPeriod_*`, `sep_noRoom`, `sep_noObs`, `sep_inseparable`, `sep_pick`, `pure_cycle`, `pure_clock`), golden `packages/contracts/golden/measure/push-cycle.jsonl` replayed by the TS twin. The table was regenerated locally from the downloaded artifacts with `push-cycle-cli.mjs report` and matches the CI report job byte for byte in the verdict section (run 3).

## Limits and stand-ins

- CI only: Simulator on GitHub macOS, not the iPhone. Three pushes are used.
- TS stand-ins with no Lean golden (decision parts stay in TS): `periodMs`, `activeQuiet`/`activeCycles`, `sepArm` (arm grouping and exclusions), `censusSeries`. The verdict itself and the census reading (`across`) are Lean.
- Follow-up: hold the stretch near 2 (the full pass period is measured per VM, the dwell touch time adds to it) or run 16 cycles so the clock-matched window fits; then re-run.
- `ci-steps-lint` fails on `path-pix.yml: uncovered:sim-draw`; that file and `Steps.lean` are unchanged by this branch.
