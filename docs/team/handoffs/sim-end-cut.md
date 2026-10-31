# Handoff sim-end-cut (checkpoint 1, after the first CI push)

- Branch: worktree-wf_e8817152-d6f-1; worktree: .claude/worktrees/wf_e8817152-d6f-1; CI branch: ci/sim-end-cut
- Last commit pushed: 2afff9f6b (tokens `[ci:webkit-sim] [end-floor] [end-floor-vms:3] [end-cut]`)
- CI runs: webkit-sim 41173075281 (commit 35807f6bc) FAILED at the site build: `platform:faded-pause` conflicts with `platform.sweep:offscreen-pause` (apps/site/src/registry/resolve.ts:141, platform/part.json:46). Fix: pauses and both swap faded-pause for the three pauses (Lean pause_arms_swap_faded, golden regenerated).
  webkit-sim 41173535319 (commit 2afff9f6b) in_progress (3 jobs, 1 round each, rotate 1 per job).
- Verified so far: Lean module `lean/Fw/Device/SimEndCut.lean` builds, golden `packages/contracts/golden/device/sim-end-cut.jsonl`
  generated from it, TS stand-in `packages/measure-webkit/src/sim-end-cut.mjs` equals the golden (test/sim-end-cut.test.mjs); prediction
  (both one; v2p, parks, pauses two) recorded in Lean before the run. Full check.sh, measure-webkit test script, ci-paths and runner tests not yet run.
- Open: results (results/sim-end-cut/r1), note research/notes/2026/10-31-sim-end-cut.md, ledger row, merge main, plan lint, dry land, review ready.
- Risks: the hero park may not engage under the instant jump to the page end (the census `parked`, view and scroll counts name it);
  pause flags may not engage if the platform section is visible at the end.

## State
- Arms (sim-end-floor.mjs CUT_ARMS): v2p, parks, pauses, both; stages end and back live, paused for v2p and both as a reference.
- Report: `node packages/measure-webkit/src/sim-end-floor-cli.mjs cut job1.json job2.json job3.json --out results/sim-end-cut/r1`
  writes rows.txt, table.txt, cut.txt (Lean-checked verdict per edge, prediction held or missed, census effect per flag).

## Read first
- lean/Fw/Device/SimEndCut.lean, packages/measure-webkit/src/sim-end-cut.mjs, research/notes/2026/10-31-sim-floor-attrib.md.
