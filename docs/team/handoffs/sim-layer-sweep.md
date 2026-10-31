branch: worktree-wf_bba3b92b-fa2-1 (CI branch ci/sim-layer-sweep)
worktree: .claude/worktrees/wf_bba3b92b-fa2-1 (under the repository root)
last commit: 9672980ce (CI push, tags [ci:webkit-sim] [end-floor] [end-floor-vms:3] [end-layer])
CI runs: webkit-sim 41212638765 in_progress (the other workflows on the branch are skipped by design)

Question: does platform.sweep:layer-sweep (class L) remove the last per-frame style recalc at the end of the page on the CI iOS Simulator?
Arms: both (sim-end-cut) and bothL (both with platform.sweep:offscreen-pause replaced by layer-sweep); 3 jobs x 1 round.

Verified (local, no timing): Lean SimLayerSweep + golden green in lean/scripts/check.sh; measure-webkit tests 1098 pass.
Lean: lean/Fw/Device/SimLayerSweep.lean (tick demand from WebKit KeyframeEffect.cpp:2724-2745 @862f17d; predTierL; gateL).
TS stand-in checked against the golden packages/contracts/golden/device/sim-layer-sweep.jsonl: packages/measure-webkit/src/sim-layer-sweep.mjs
(layerReadOf and the report lines are TS stand-ins without a golden). Page side: sim-end-floor.mjs (layer census, maxY pin), probe sim-layer-probe.mjs.
Harness fixes from sim-end-cut-2: "job N" labels (roundName), end windows pinned to maxY (pinEnd).

Open: fetch the artifacts of the run, `node packages/measure-webkit/src/sim-end-floor-cli.mjs layer <3 files> --out results/sim-layer-sweep`,
check pinned windows 6 of 6 and every flag took, write research/notes/2026/10-31-sim-layer-sweep.md, pre-report checks, dry land, review ready.
No flag or preset change; layer-sweep stays class L. Simulator is not the phone.
Read first: this file, the Lean module doc, the note once written.
