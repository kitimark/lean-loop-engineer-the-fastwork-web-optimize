Branch: worktree-wf_879f7b4e-2cf-1. Worktree: .claude/worktrees/wf_879f7b4e-2cf-1. Last commit: see git log. No CI runs (none needed; no push).
Task: runBase/runFlag/runBase6/runFlag6 in lean/Fw/Measure/WkCost.lean were hand-copied; now a committed reduced golden checks them.
Delivered:
- `morph-verdict --json` now also emits `base`/`flag` PassSums (packages/measure-webkit/src/lag/morphcost.mjs `passJson`); `--sums <file> --run baseId,flagId` writes one `morphRunSums` line (numbers only).
- packages/contracts/golden/measure/wkcost-sums.jsonl: 2 lines, runs 39903977820,39903974246 (2 passes/arm) and 39915136431,39915146774 (6 passes/arm). Not Lean-generated: it is the reduction of the r*-lag.json artifacts.
- Lean: `recordedRuns`, `recordedRuns_overlap`, `sumsMismatches`, `runSums` in WkCost.lean; script lean/scripts/WkCostSums.lean; job "wkcost sums check" in lean/scripts/check.sh. A changed digit, a missing run or an unknown run line exits 1.
Verified: all 12 passes re-derived from the artifacts equal the Lean literals (the check exits 0); tampering one number exits 1; verdict stays overlap 8/8 (node test + Lean theorem).
Regenerate: gh run download 39915136431 / 39915146774 (r*-lag.json under webkit-sim-r1..r3), then `node packages/measure-webkit/src/lag/cli.mjs morph-verdict --original <base r1,r2,r3> --rewrite <flag r1,r2,r3> --sums f --run 39915136431,39915146774`; older pair has only webkit-sim-r1 (2 passes per file).
Outside the task writes: lean/scripts/check.sh (one job line), lean/Fw/Ci/Trigger.lean (lean.yml row reads wkcost-sums.jsonl) and its regenerated packages/contracts/golden/ci/triggers.jsonl.
