branch: worktree-wf_bba3b92b-fa2-1 (CI branch ci/sim-layer-sweep, last pushed 9110f3bbd)
worktree: .claude/worktrees/wf_bba3b92b-fa2-1 (under the repository root)
state: all 3 CI runs done and committed; note and ledger entry written; lean check.sh green; measure-webkit tests 1098 pass.

Question: does platform.sweep:layer-sweep (class L) remove the last per-frame style recalc at the end of the page on the CI iOS Simulator?
Arms: both (sim-end-cut) and bothL (both with offscreen-pause replaced by layer-sweep); 3 jobs x 1 round per run.

MEASURED (webkit-sim 41212638765, 41215962130, 41219277317; 9 jobs): end bothL 99..110 vs both 199..204 per 100; back bothL 100..102 vs both 200;
paused 100 in both arms; every flag took; Lean verdict cut:platform.sweep held in all runs; tiers bothL one, both two (9 of 9 jobs).
Inspector (run 3): 4 layers with the animation reason (necessary, not sufficient); accelerated state is INFERRED.
Premise refuted: 360-frame windows span 7..30 s (paused up to 30.0 s), not 6-8 s (Lean windowMsMax 24000).

Read first: research/notes/2026/10-31-sim-layer-sweep.md, results/sim-layer-sweep/r3/layer.txt.
Lean: lean/Fw/Device/SimLayerSweep.lean (tick demand, KeyframeEffect.cpp:2724-2745 @862f17d).
TS stand-in checked against packages/contracts/golden/device/sim-layer-sweep.jsonl: packages/measure-webkit/src/sim-layer-sweep.mjs
(layerReadOf and the report lines have no golden: TS stand-in). Probe: packages/measure-webkit/src/sim-layer-probe.mjs (I/O only).

Open follow-ups: the 36 px page growth between the end and back stages (5231 vs 5267) is not investigated; 13 of 18 end windows
sit at 5231. layer-sweep needs the user's visual review; the Simulator is not the phone. No flag or preset change made.
Report line: gate: none (measurement task; layer-sweep gate run 40335795674 is older).
