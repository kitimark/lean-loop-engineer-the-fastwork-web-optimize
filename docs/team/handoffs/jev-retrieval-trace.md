# jev-retrieval-trace handoff

- Branch `worktree-wf_c7cc80f6-a2a-1`, worktree `.claude/worktrees/wf_c7cc80f6-a2a-1`, last sha in `git log -1`. CI runs: none.
- State: Lean part done and checked; harness and trees done; arms not run yet.

## Verified
- `Fw.Oracle.Retrieve` (scope, tree, hook, trace, evidence, J-pick, J-hybrid, send plan, adopt) and
  `Fw.Oracle.RetrieveWire` build; `lean/scripts/check.sh` green through the slot.
- Golden `packages/contracts/golden/oracle/retrieve.jsonl` (`lean/scripts/RetrieveGolden.lean`, check job in
  `lean/scripts/check.sh`), replayed by `node --test scripts/jev-trace.test.mjs` (48 pass).
- `node scripts/jev-trace.mjs trees --work <scratch>/work`: 38 rows, 29 pins, 315-1076 files per row
  (`results/jev-retrieval-trace/trees.json`). Trees live in the scratchpad, not in git.

## Open
- Probe, T-haiku, T-sonnet, J-hybrid, J-pick, paired tables, note, replay-note Limits line.

## Conventions
- Prompts: `pnpm -s fw oracle arm-input --set d1 --out <scratch>/d1.prompts.jsonl`.
- Writes outside the graph: `lean/Fw/Oracle/Questions.lean` (filePick), `lean/Fw/Oracle/Replay.lean` (d1h, d1p, d1k),
  `lean/Fw/Wire.lean`, `lean/scripts/check.sh`, `lean/scripts/RetrieveGolden.lean`.

## Read first
research/notes/2026/10-2x-jev-retrieval.md (plan section), lean/Fw/Oracle/Retrieve.lean, scripts/jev-trace.mjs.
