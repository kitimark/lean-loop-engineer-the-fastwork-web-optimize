branch: worktree-wf_4092969b-128-1
worktree: .claude/worktrees/wf_4092969b-128-1 (under the main checkout)
last commit: see `git log -1` on the branch (updated at the final commit)
CI runs: none (no CI push needed for this task)
state: built, tests green (see verified); dry land result in the report

Task raw-local-main (graph r541), incident inc-raw-in-worktree: raw phone lanes under <worktree>/.local were deleted when disk-gc removed landed worktrees.

What changed
- lean/Fw/Ops/DiskGc.lean: Cand.localEntries / localBytes; `localClear`, `ruleLandedBase`, `ruleLanded`, `heldLocal`; theorems local_data_kept, local_nonempty_kept, local_unread_kept, held_local_kept, held_local_would_select; the reply carries `heldLocal` [{path, localBytes, reason}].
- lean/scripts/DiskGcGolden.lean (outside the graph writes list; it generates the golden) + packages/contracts/golden/ops/diskgc.jsonl: 3 new rows (71 cases).
- apps/runner/src/disk-gc.ts: `localState`, gather passes the facts, summary lines `disk-gc: kept <path>: local-nonempty (...)`; test in apps/runner/test/disk-gc.test.ts.
- packages/measure-webkit/src/device-raw-dir.mjs: `rawResolve` (relative `.local/...` -> main checkout via git-common-dir parent); device-cli, device-push-cli, device-replay-cli import it as `resolve`. Test: test/device-raw-dir.test.mjs.
- docs/team/incidents/ledger.json row inc-raw-in-worktree (fix.task raw-local-main, class c-env-assume); research/findings/ledger.json note (entry of morph.columns:probe-off, task raw-local-main, field lesson); research/notes/2026/10-2x-raw-local-main.md.

Verified: lake build Fw.Ops.DiskGc (guards + theorems), golden --check, vitest disk-gc.test.ts (86), node --test device-raw-dir.test.mjs (3), `pnpm fw incidents lint` (0 errors). Package-level runs and check.sh via fw slot: see the report.

Open / follow-ups
- TS stand-ins: `localState` (I/O) and `rawResolve` (path glue). An absolute raw dir under a worktree is not redirected.
- docs/team/tools/disk-gc.md does not yet describe the `.local` rule (not in this task's writes).
- Existing raw data in other worktrees' .local now keeps those worktrees; the lead can move it to the main .local by hand.
Read first: research/notes/2026/10-2x-raw-local-main.md.
