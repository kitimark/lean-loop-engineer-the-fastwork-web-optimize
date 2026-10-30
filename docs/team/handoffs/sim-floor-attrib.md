# Handoff sim-floor-attrib

- Branch: worktree-wf_1f5ece3e-bb2-1; worktree: .claude/worktrees/wf_1f5ece3e-bb2-1; CI branch: ci/sim-floor-attrib
- Last commit: see `git log -1` (updated at each checkpoint)
- CI runs: none yet (first push pending)
- Verified: Lean module `lean/Fw/Device/SimFloorAttrib.lean` builds, golden `packages/contracts/golden/device/sim-floor-attrib.jsonl`
  generated from it, TS stand-in `packages/measure-webkit/src/sim-floor-attrib.mjs` equals the golden (test/sim-floor-attrib.test.mjs),
  measure-webkit tests (1067), ci-paths test and runner land-inputs test pass locally.
- Open: CI run (webkit-sim, 3 jobs, one round each, arm order rotated by 2 per job), note, ledger row, check.sh, dry land, review gate.

## State
- Arms (sim-end-floor.mjs ARMS): base, v2p, minusT, minusU, blank (empty body page), minusBoth, v2pCancelScroll (cancels every
  scroll/view-timeline animation at the paused stage, pauses the rest).
- Commit tokens `[end-floor] [end-floor-vms:3]` run 3 jobs; each: `sim-end-floor-cli.mjs run --rounds 1 --rotate 2*(n-1)`.
- Report: `node packages/measure-webkit/src/sim-end-floor-cli.mjs attrib <vm1.json> <vm2.json> <vm3.json> --out results/sim-floor-attrib/r1`
  writes rows.txt, table.txt, attrib.txt (Lean-verified verdicts per edge).
- The preference value stays INFERRED (source default); `meta.prefOverrides` records `defaults read` matches only.

## Read first
- research/notes/2026/10-31-sim-end-floor.md (section 5 names this task), lean/Fw/Device/SimFloorAttrib.lean.
