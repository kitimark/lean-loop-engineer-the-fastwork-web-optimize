# next-killorphan-reap

- Branch `worktree-wf_b3ab2d32-15e-1`, worktree `.claude/worktrees/wf_b3ab2d32-15e-1`; last sha: `git log -1` on the
  branch. CI runs: none (accepted limit).
- State: `NEXT <id> killOrphan pid= start=` is printed only for an entry of the Reap plan's `held` list
  (`Fw.Ops.Reap.held`, op `ops.reapHeld`) whose worktree id is the agent's worktree id. The old inference in
  `Fw.Obs.Next` (orphanB, killB, staleB, deadB, oldB, fileStaleMin) is removed.

## Verified
- `lean/Fw/Obs/Next.lean`: `kill_held` (every killOrphan names a held entry in the agent's worktree), `held_kill`
  (each such entry gets killOrphan with its pid and start), `kill_iff`, `no_kill_unheld`, `no_kill_empty`; `#guard`s on
  the ghb-runner, integrate-ports and port-nav examples.
- `lean/Fw/Wire/Obs.lean`: codecs `worktree.id`, `reapHeld [{pid, start, wt}]`, killOrphan `pid` + `start`; golden
  `packages/contracts/golden/obs/next.jsonl` regenerated (59 cases, held cases 2 to 2h and 6b, held literals).
- `apps/runner/src/next.ts`: `reapHeldFacts` (gather + `ops.reapHeld`, wt from the row with that pid and start;
  `[]` on failure or `FW_WATCH_REAP=0`); `collectRaw` adds the worktree id by identity (`wtIdOf`). Tests in
  `apps/runner/test/next.test.ts` (fake gather/call, no process is signalled).
- `sh lean/scripts/check.sh` green; `pnpm --filter @fw/runner test` and typecheck green; ci-paths test green.

## Open
- Outside the task's writes: `apps/runner/test/signals.test.ts` (expectation now `investigate heldByChild`).
- Docs still describing the old rule: `docs/team/tools/watch.md:40,43`, `docs/team/tools/watch-rules.md:48`,
  `docs/team/tools/reap.md:33`.
- Follow-ups: `next` no longer reads child facts `watchedAt`, `producerExited`, `watch`; a watch pass runs `gather`
  twice (`reapHeldAlerts` and `reapHeldFacts`), share one; the `ops.reapHeld` reply carries no `wt` (TS joins it).

## Read first
`lean/Fw/Obs/Next.lean` (`kills`, then `kill_held` at the start of the kill theorems), then `reapHeldFacts` in `apps/runner/src/next.ts`.
