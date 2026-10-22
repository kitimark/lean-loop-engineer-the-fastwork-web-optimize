# jev-file-context-ablation handoff

- Branch `worktree-wf_308f05f9-86b-1`, worktree `.claude/worktrees/wf_308f05f9-86b-1`, last sha in `git log -1`. CI runs: none.
- State: done. Lean module, glue, all arms, paired comparison and note are committed. Adopt is false.

## Verified
- `Fw.Oracle.Expand`, `Fw.Oracle.ExpandPaired`, `Fw.Oracle.ExpandWire` build; golden
  `packages/contracts/golden/oracle/expand.jsonl` is checked by `lean/scripts/check.sh` and replayed by
  `node --test scripts/jev-expand.test.mjs`.
- `node scripts/jev-expand.mjs build`: 27 of 116 D1 rows expanded (`results/jev-file-context-ablation/inputs.json`).
- Jev sends: d1x 27, d1n 22 (49 of the cap 200 on 2026-10-22). Haiku and Sonnet: 27 of 27 each via
  `scripts/jev-arms-clean.mjs`.
- `node scripts/jev-expand.mjs paired`: every arm and mode has a negative net (-1 to -4), adopt false
  (`results/jev-file-context-ablation/paired.json`).

## Open
- Hand trace of the 14 untraced gains (would not change the verdict; `reject_netLow` fixes it).
- Outside the graph writes: `lean/Fw/Oracle/Questions.lean` (`files` field), `lean/Fw/Oracle/Replay.lean` (sets
  d1x, d1n), `lean/Fw/Wire.lean` (ops wiring).

## Read first
research/notes/2026/10-2x-jev-file-context-ablation.md, lean/Fw/Oracle/Expand.lean, scripts/jev-expand.mjs.
