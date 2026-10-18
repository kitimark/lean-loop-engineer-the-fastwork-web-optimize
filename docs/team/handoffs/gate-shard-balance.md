# gate-shard-balance handoff (round 3, final design round)

State: branch worktree-wf_bde7589c-9ba-1, CI branch ci/gate-shard-balance-r3, code head 9d620c16 (docs commit on top).
`sh lean/scripts/check.sh` green; `node --test test/*.test.mjs` in packages/gate-breakpoints: 125 pass.
Read first: research/notes/2026/10-18-gate-shard-balance.md, section "Round 3".

## What round 3 did
- Same instant by identity: `Fw.Gate.Freeze` section Instants (`instant`, `stopBase`, `both_arms_same_instant`, `mount_same_instant`,
  `overshoot_flagged`), twins in `src/freeze.mjs`, restructure in `src/run.mjs` (`at(rank, label)`, union of step lists, `raw.late`).
- Per-cell verdict: `Fw.Gate.Exit` (`engine_pass_iff_all_cells`, `exit_zero_iff_all_cells`, exemption registry, `incomplete`);
  `cli.mjs` reads the registry from `exit.jsonl`; `exit.test.mjs` replays 33 engine cases.
- Math-review docstring fixes: Settle, Shard (`kCands`), ShardGolden (`engJobs`), Freeze, Exit (`plainNat?`, ASCII digits only).
- Restored `mountPanel` and stage-less `prepareInPage` in page.mjs (packages/snapshot-extract imports them).
- Align-self canonicalisation removed (followup: integrate-ports, see gate-align-equiv.md).

## Result (MEASURED, 4 full-gate runs on acc2a006/9d620c16, vs main 39102911533 and r2 39116538316)
Chromium pass (251 + 1 excused), 0 cells differ. WebKit: 215 pass + 36 excused + 1 fail (platform.stageBg x desktop-1512-320-1512,
also on main); 12 hero.countdown/hero.exit cells fail -> pass vs main (same as r2). 504 cells, no change r2 -> r3. 27.1 to 28.0
job-minutes, wall ~5.9 min (r2: 25.9, 5.0).

## Open
- Land with `--allow` for the out-of-scope files (list in the report). `mutants` fails on main too (SpawnGuard).
- Regenerate `ShardObs.lean` (scripts/shard-obs.mjs) from a round 3 run: costs moved from 65 to ~28 job-minutes.
- The 33-part cells (desk-rm-861 hero.orbit, desk-rm-1279 commission) need integrate-ports-3.
- Native-clock `waitReady` (snapshot-extract uses it) now repeats the finite-animation wait; check reference datasets if they drift.
- Worktree needs `pnpm install --offline --frozen-lockfile` before `pnpm fw` works.
