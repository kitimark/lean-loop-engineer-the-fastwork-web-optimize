# Handoff sim-floor-attrib

- Branch: worktree-wf_1f5ece3e-bb2-1; worktree: .claude/worktrees/wf_1f5ece3e-bb2-1; CI branch: ci/sim-floor-attrib
- Last commit: see `git log -1`
- CI runs (commit 1815c42): webkit-sim 41145066709 success (3 jobs, 1 round each); lean 41145066687 success.
- Results: `results/sim-floor-attrib/r1/` (job1..3.json, job1..3-log.txt, rows.txt, table.txt, attrib.txt). Note: research/notes/2026/10-31-sim-floor-attrib.md.
  Ledger row added (notes list, task sim-floor-attrib).
- Verified: Lean module `lean/Fw/Device/SimFloorAttrib.lean` builds, golden `packages/contracts/golden/device/sim-floor-attrib.jsonl`
  generated from it, TS stand-in `packages/measure-webkit/src/sim-floor-attrib.mjs` equals the golden (test/sim-floor-attrib.test.mjs),
  measure-webkit tests, ci-paths test and runner land-inputs test pass locally.
- Findings: recording floor 0 (blank); second scheduled recalc in paused arms = scroll/view-timeline animations (cancel 200->100,
  minusBoth 100); end/back stages stay 200 in every non-blank arm; first recalc of paused base unattributed (OPEN, INFERRED).
- Open: the run-time preference read, the candidate spec (list the accent idle animations or predict against minusBoth), the unscheduled first recalc of the paused base, per-round build in mergeRaws.

## State
- Arms (sim-end-floor.mjs ARMS): base, v2p, minusT, minusU, blank (empty body page), minusBoth, v2pCancelScroll (cancels every
  scroll/view-timeline animation at the paused stage, pauses the rest).
- Commit tokens `[end-floor] [end-floor-vms:3]` run 3 jobs; each: `sim-end-floor-cli.mjs run --rounds 1 --rotate 2*(n-1)`.
- Report: `node packages/measure-webkit/src/sim-end-floor-cli.mjs attrib <vm1.json> <vm2.json> <vm3.json> --out results/sim-floor-attrib/r1`
  writes rows.txt, table.txt, attrib.txt (Lean-verified verdicts per edge).
- The preference value stays INFERRED (source default); `meta.prefOverrides` records `defaults read` matches only.
- Candidate (spec only): both parks plus pause of off-screen document animations; follow-up, not built.

## Read first
- research/notes/2026/10-31-sim-floor-attrib.md, lean/Fw/Device/SimFloorAttrib.lean.
