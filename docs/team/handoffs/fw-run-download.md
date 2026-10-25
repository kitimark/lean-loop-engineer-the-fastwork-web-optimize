branch: worktree-wf_7b33798c-11e-1
worktree: .claude/worktrees/wf_7b33798c-11e-1 (under the repo root)
last commit: see `git log -1` (final commit of the task)
CI runs: none (no push needed; the measurement is gh run download timings, not a CI lane)

State: fw run downloads per piece (fwcore op store.download), sized timeout, one retry. Verified: lake build of Fw.Store.Ci
(theorems piece_fits_hold, shard_downloaded, build_outputs_skipped, retryCost_le), store golden regenerated (download.jsonl),
runner tests run-download / run-golden / run / run-budget, one fw run filing webkit run 40153925235 (key 2ef4f3d8966c, 19 artifacts).
Read first: research/notes/2026/10-2x-fw-run-download.md, lean/Fw/Store/Ci.lean (section "The download of a run"),
apps/runner/src/run.ts (downloadPieces, GhTimedOut).

Open (none: no original-target 3-VM webkit run exists on any branch, checked 7 recent dispatches: all rewrite):
- ci.ts (fw ci) keeps one 40 s call, no retry (5.5 MB, 9.5 s measured): follow-up.
- The zod schemas DownloadRequest/DownloadReply live in apps/runner/src/run.ts, not packages/contracts: move later (follow-up).
- Byte bound (simKb 12500) is assumed, not checked against the artifact list (follow-up). Run 40156384878 was measured only for its kept pieces.
- Original webkit target: pieces webkit-sim-v<i> + webkit-classes (round 2); shown by golden + runner test, not a live download.
- `maxHoldMs` in Ci.lean is a copy of Timing.defaultCallTimeoutMs; run-download.test.ts checks equality.
- The 3-VM re-file wrote into the shared .fw-console/store (key 2ef4f3d8966c).
Convention: gh run download always with --pattern, so entries keep the <artifact>/ directory prefix.
