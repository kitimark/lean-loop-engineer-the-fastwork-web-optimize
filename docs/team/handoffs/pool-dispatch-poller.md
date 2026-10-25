# Handoff: pool-dispatch-poller (console-builder)

Branch `worktree-wf_2de28e7d-882-1`, worktree `.claude/worktrees/wf_2de28e7d-882-1`, ci branch `ci/pool-dispatch-poller`.
Code commit e1b97e186, then main merged and handoff afd8e01e9, then polish 40fdf22fc and this rewrite.

## State (round 3, final design round)
- Dry land: `VERDICT dry pool-dispatch-poller`.
- CI: lean 40219737473 success at e1b97e186.
- GitHub twin: dispatch 40211928946; cell r1 success (the reference); cell r2 cancelled (not needed).
- Codemagic (prose): build 6ade2733 hit the 40 min cap (41 min; the determinism step hung, no artifacts); retry build
  6ade316d finished in 21 min. 62 min this round; the month is at 166 of the 400 line.
- Paired run outcome (a), MEASURED, n=1 per side: keys equal (macOS 26A434, Xcode 27A9275, runtime 24A434), Lean
  `ci.cellMerged` merges; site digests equal (GitHub run 40211928946 site-dist and Codemagic site-digest.txt, 243 files);
  20 of 104 rows differ in class (GitHub 39 quarantined / 52 deterministic / 13 stable, Codemagic 27 / 59 / 18; hardware
  3 cpus vs 8 cpus / 12 GiB). Row list in docs/team/tools/ci-pool.md.

## Done
- Lean `PlatformKey`, `cellMerged` and theorems (lean/Fw/Ci/PoolTier.lean), wire op `ci.cellMerged` (PoolTierWire.lean),
  golden cases (lean/scripts/PoolGolden.lean, packages/contracts/golden/ci/pool-tier.jsonl).
- codemagic.yaml pins xcode 27.1; ci-pool-tier.ts parses keys, asks Lean once per cell, emits `ci.cell.platform`, files
  refused cells under `webkit-classes/refused/`, refuses a build with no sha.
- TS stand-ins: `mergeClasses`, the siteDigest walk, `parsePlatformKey`, `parseHw`.

## Follow-ups (re-plan, not this branch)
- Hardware in the key, k pinned pairs (the 20 class differences with equal keys).
- `fw ci state` for cm: ids; re-route of jobs already queued on GitHub; spool ci-route.jsonl into console events.

## Read first
docs/team/tools/ci-pool.md, then `realRoute` / `place` in apps/runner/src/ci-pool-tier.ts.
