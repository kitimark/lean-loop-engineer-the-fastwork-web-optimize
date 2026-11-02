branch: worktree-wf_9cf01a33-b63-1
worktree: .claude/worktrees/wf_9cf01a33-b63-1
last commit: `git log -1` on the branch
CI runs: none (local unit tests only)

Verified: Lean `Fw.Ops.LandLink` builds with theorems check_empty/absolute/escapes/inside, mem_refused; goldens regenerated
(`lake env lean --run scripts/OpsGolden.lean`); `apps/runner/test/land-link.test.ts` 13 tests pass (golden replay via fwcore,
temp git repo with one escaping and one inside link, land --dry refusal).

Files: lean/Fw/Ops/LandLink.lean, lean/Fw.lean (import), lean/Fw/Ops/Wire.lean (ops.landLink), lean/Fw/Ops/Golden.lean,
lean/FwTest/Mutants/OpsWire.lean (op list + mutant guards; graph r637), packages/contracts/golden/ops/land-link.jsonl,
apps/runner/src/land-link.ts, apps/runner/src/land.ts, apps/runner/test/land-link.test.ts, .claude/workflows/build-review.js,
research/notes/2026/11-02-scratch-link-check.md.

Conventions: Lean decides (fwcore op ops.landLink); TS only reads git. Refusal is kind `scope` with `REFUSED: land-link:`.
Open: the lead sets the regression field of inc-scratch-symlink-wait in docs/team/incidents/ledger.json (outside the task writes).
Open: two added links can escape together while each passes (`a/l1 -> ..`, `l2 -> a/l1/..`); untracked links are not checked.
The dry-land / check.sh results are in the report. Read it, then lean/Fw/Ops/LandLink.lean.
