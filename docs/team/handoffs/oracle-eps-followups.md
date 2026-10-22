# oracle-eps-followups handoff

- Branch `worktree-wf_dac48000-f0e-1`, worktree `.claude/worktrees/wf_dac48000-f0e-1`; work commit b744d823, main
  merged after it (see `git log -1`). CI runs: none (local re-validation only, no sends, no model calls).

## Verified (MEASURED)
- fwcore: the main checkout binary, record tree = tree of `e96b2ea5` (oracle-eps land); `lean/Fw/Oracle`,
  `oracle*.ts`, `jev-expand.mjs` unchanged on main since then.
- `node scripts/jev-expand.mjs paired`: only strict rows move (jev -4 → -3, haiku -2 → -1, sonnet -2, jev-naive
  -1 → -2); renorm unchanged; adopt false, 18 reasons (12 untraced). Note table and verdict text updated.
- `fw oracle score` for d1x (jev, haiku, sonnet) and d1n (jev): `d1x.json`, `d1n.json` byte-identical (lenient pick).
- `scripts/jev-arms-clean.mjs table`: reads `results/jev/eps-rescore.json` (default `<out>/../jev/`, or `--eps`),
  takes the invalid column from its old-rule counts after checking fwcore still gives its sumOk counts (else throws
  "stale"), and appends the oracle-eps block. In-place regenerate leaves `table.md` and `table.json` byte-identical.
- Tests: `node --test scripts/jev-arms-clean.test.mjs` 14/14 (one regenerates on a temp copy, ~35 s, skips without
  fwcore); ci-paths + jev-expand 79/79; runner land-inputs 56/56.

## Open / conventions
- TS/JS stand-ins: `results/jev/rescore-eps.ts` (needs an old fwcore binary) and the block renderer `epsBlock`
  duplicated in it; a follow-up could make rescore-eps.ts import `epsBlock` (outside this task's writes).
- Hand trace of the 12 untraced gains stays a follow-up.

## Read first
research/notes/2026/10-2x-jev-file-context-ablation.md ("Re-score under sumOk"), scripts/jev-arms-clean.mjs `table`.
