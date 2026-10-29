# end-wktr-flip handoff

- Branch worktree-wf_1e156d0c-e49-1 (CI branch ci/end-wktr-flip), worktree .claude/worktrees/wf_1e156d0c-e49-1 under the repo root, last commit 49a5c04f3. Pushes used 1 of 3.
- CI runs: wktr run id pending (push 1; difftest 40869911093 and path-pix 40869911175 skipped, expected).
- Verified: Lean EndWktr.lean compiles, check.sh green, measure-wktr tests 137 pass, ci-paths 56 pass, runner land-inputs 73 pass.
- Open: CI data (3 jobs), results/end-wktr-flip/, note research/notes/2026/10-2x-end-wktr-flip.md, ledger notes, revert of the temporary wktr.yml edit, dry land, review ready.
- Temporary wktr.yml edit (commit 49a5c04f3): build --config x4, accel --modes end-*-thr-off, wktr job timeout 16 -> 50. Revert before the dry land.
- Read first: lean/Fw/Device/EndWktr.lean (verdict rules, decided before the data), packages/measure-wktr/src/end-wktr.mjs (TS stand-in, replays packages/contracts/golden/device/end-wktr.jsonl).
- Arms (accel-cli.mjs END_ARMS): nat = natural page, pall = all paused floor in-process, pallf/obsf = frame records for the mechanism split.
- Decide results: node packages/measure-wktr/src/end-wktr-cli.mjs <job dirs> --out verdict.txt.
- Conventions: heavy commands through fw slot; no local runs reported; apps/runner/src/land.ts and lean/Fw/Ci/Trigger.lean edited for the new golden (outside the task writes, list in open).
