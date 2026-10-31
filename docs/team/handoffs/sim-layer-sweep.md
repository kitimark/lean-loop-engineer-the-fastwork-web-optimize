branch: worktree-wf_bba3b92b-fa2-1 (CI branch ci/sim-layer-sweep)
worktree: .claude/worktrees/wf_bba3b92b-fa2-1 (under the repository root)
last commit: 9110f3bbd (CI push 3, tags [ci:webkit-sim] [end-floor] [end-floor-vms:3] [end-layer])
CI runs: webkit-sim 41212638765 complete success (3 jobs, results/sim-layer-sweep/r1); webkit-sim 41215962130 complete success (results/sim-layer-sweep/r2: rates reproduce, probe still errored: Missing renderer of node); webkit-sim 41219277317 on 9110f3bbd queued (probe skips nodes without a renderer)

Question: does platform.sweep:layer-sweep (class L) remove the last per-frame style recalc at the end of the page on the CI iOS Simulator?
Arms: both (sim-end-cut) and bothL (both with platform.sweep:offscreen-pause replaced by layer-sweep); 3 jobs x 1 round per run.

Run 1 (MEASURED): end bothL 100/103/106 vs both 201/203/204 (cut:platform.sweep, held); back bothL 101/101/101 vs both 200/200/200;
every flag took; 4 layer loops (transform only, 2 in view); 6 of 6 end windows pinned (y = maxY); paused 100 both arms.
Inspector probe failed in run 1 ("DOM.enable was not found": the probe sent DOM.enable); fixed in 13f66adf0, run 2 reads the animation reason.

Lean: lean/Fw/Device/SimLayerSweep.lean (tick demand, KeyframeEffect.cpp:2724-2745 @862f17d). TS stand-in checked against
packages/contracts/golden/device/sim-layer-sweep.jsonl: packages/measure-webkit/src/sim-layer-sweep.mjs (layerReadOf and report lines have no golden).

Open: fetch run 3 into results/sim-layer-sweep/r3, `node packages/measure-webkit/src/sim-end-floor-cli.mjs layer <jobs> --out <dir>`,
note research/notes/2026/10-31-sim-layer-sweep.md, pre-report checks (check.sh, tests, dry land, review ready).
No flag or preset change; layer-sweep stays class L. Simulator is not the phone.
