# obs-next-glue handoff

**State.** Branch worktree-agent-a580a837f761be7fa. `apps/runner/src/next.ts` (observation + classification + printing),
`nextFor`/`nextMain` in `watch.ts`, `fw next` in `fw.ts`, `parseCi` now keeps the gh `databaseId` (`id`) for the ci fact,
`lean/FwTestMain.lean` runs `NextGolden.run ... false` (new `nxg` in the all-passed test). Tests: `apps/runner/test/next.test.ts`.
`pnpm --filter ./apps/runner test` and `sh lean/scripts/check.sh` green.

**Read first.** Header of `next.ts`, then `docs/team/tools/watch.md` (last section).

**Conventions.** No decision in TS: facts in, fwcore `obs.next` out. `agent.held` / `agent.unlanded` are appended to
`Health.alerts` in `watchMain` (so they are logged and trigger `--until-alert`). `none` actions are not printed.

**Open items.**
- Integrator list file `docs/team/handoffs/integrate-ports.md` does not exist yet in the tree; queued = false until it does.
- Agent-to-worktree match is by dir `agent-<id>` or branch named after the agent; named worktrees with other names have no branch fact.
- Only process trees owned via the lsof task-id lookup are children; loops outside the session tree are never seen (Lean's foreignLoop case is test-only).
- Golden case 6b (producerExited without a watched file) is not replayable through the collector (marker is read from the file).
- Live `fw next` is noisy: ghost transcripts of long-gone agents yield respawnFromHandoff (Lean rule: gone, no handback).
