# Handoff: webkit-sim-failfast, round 2 (branch worktree-wf_d864cd42-ccc-2, CI branches ci/webkit-sim-failfast[-n1|-n2])

Task: a dead Simulator inspector or dead Safari ends the webkit-sim job with exit 4 within the Lean-proved bound.
Read first: lean/Fw/Measure/SimBound.lean, packages/measure-webkit/src/guard.mjs, research/notes/2026/10-20-macos-pool-v2.md.

State
- Lean `SimBound`: detect 85 s (tick 30 s, probe 25 s, 2 failed probes) + one relaunch 320 s + stall 360 s = `deadEndMs` 765 s;
  `dead_run_ends`, `relaunch_at_most_once`, `giveUp_last`, `dead_forever_gives_up`; `job_min` = setup 6 + sessions + tail 10 (51 for one
  determinism session). Wire ops `measure.inspector`, `measure.simBounds`; goldens in packages/contracts/golden/measure/.
- TS stand-ins (checked against the goldens): `src/inspector.mjs`. Glue: `src/guard.mjs` (probe socket/proxy/page, relaunch once, no
  second tab), `src/fault.mjs` (FW_WK_FAULT), `src/session.mjs` (guard wiring, end-of-run probe), `src/sim.mjs` helpers.
- Workflow input `fault` (off by default) sets FW_WK_FAULT; a ci/* push carries no inputs, so the commit tokens fault:kill-safari and
  fault:kill-proxy do the same (guard job also needs the lane token).

CI (webkit-sim, original, 1 session)
- Fault kill-safari run 39444758495: first kill 15:18:26Z, "relaunching" 15:19:41Z, "giving up" 15:20:45Z, exit 4 (139 s, bound 765 s).
- Fault kill-proxy run 39447914983: first kill 15:32:43Z, "relaunching" 15:33:14Z, "giving up" 15:34:33Z, exit 4 (111 s).
- Normal runs 39447981526 and 39449995130: green, no probe false positive. 23-min failure (39426562165) did not recur.
- Parity vs baseline 39102911639 (58 deterministic rows, per-row value vectors): 56/58 and 57/58 equal. The lane never gates on
  differing rows (reduce.mjs `classify`: quarantined is "Reported, never gated on"); older main greens show 58/58, 57/58, 58/58.

Open
- Log line "forced exit ... 20 s later the process is alive; open: PipeWrap 2" predates this change (4 older green logs have it);
  inside the 40 s exit budget, cause unexplained.
- `terminate Safari` took 16 s of its 20 s bound in one fault run: a loaded runner could give up falsely; widen after more data.
- Sync spawnSync calls can overrun a tick; cause of inspector deaths undiagnosed; census y=4500 layerCount varies between runs.
- Used 4 of 6 webkit-sim runs.

Convention: regenerate goldens with `lake env lean --run scripts/MeasureGolden.lean` in lean/; run `sh lean/scripts/check.sh`.
