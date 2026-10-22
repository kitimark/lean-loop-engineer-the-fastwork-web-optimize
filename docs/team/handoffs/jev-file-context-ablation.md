# jev-file-context-ablation handoff

- Branch `worktree-wf_308f05f9-86b-1`, worktree `.claude/worktrees/wf_308f05f9-86b-1`, last sha in `git log -1`. CI runs: none.
- State: Lean part done; Jev sends and the Haiku/Sonnet arms not yet run.

## Verified
- `Fw.Oracle.Expand`: path scan (Lean port of the PATH_RE of `scripts/jev-leak.mjs`), allowlist `safe` (code under
  apps/ packages/ scripts/ lean/Fw/, never lean/Fw/Oracle/), vocabulary drop, whole-file fit under `stateCap`;
  theorems `expand_files`, `expand_same`, `expand_refused` (not one file fits), `expand_uncut` (`capState` keeps all),
  `expand_local`, `expand_noop_state`.
- `Fw.Oracle.ExpandPaired`: `signP` (exact two-sided sign test), `adopt` with `adopt_iff` and the four `reject_*`.
- `Fw.Oracle.ExpandWire`: ops `oracle.expandPaths`, `oracle.expand`, `oracle.paired`, `oracle.adopt`; golden
  `packages/contracts/golden/oracle/expand.jsonl` (`lean/scripts/ExpandGolden.lean`, check.sh job), replayed by
  `node --test scripts/jev-expand.test.mjs` (25 pass).
- Replay sets `d1x` (`d1-expand.jsonl`) and `d1n` (`d1-naive.jsonl`); the `files` field is declared on incident-class.
- `node scripts/jev-expand.mjs build`: 27 of 116 D1 rows expanded, 9 refused (one file over the cap), 1 vocab drop
  on an expanded row; record in `results/jev-file-context-ablation/inputs.json`.

## Open
- `pnpm fw oracle send --set d1x`, then `--set d1n` (count today's log entries first, cap 200).
- Haiku/Sonnet: `pnpm fw oracle arm-input --set d1x --out <scratch>`, `node scripts/jev-expand.mjs prompts`, then
  `scripts/jev-arms-clean.mjs run --set d1x --out results/jev-file-context-ablation`.
- `node scripts/jev-expand.mjs paired`, hand trace into `traced.json`, the note
  `research/notes/2026/10-2x-jev-file-context-ablation.md`, and the "designed, not run" lines of the design note.

## Read first
research/notes/2026/10-2x-jev-file-context.md (design and rule), lean/Fw/Oracle/Expand.lean, scripts/jev-expand.mjs.
