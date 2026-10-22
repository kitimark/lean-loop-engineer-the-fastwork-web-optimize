# jev-retrieval-followups handoff

- Branch `worktree-wf_a0391afd-f5f-1`, worktree `.claude/worktrees/wf_a0391afd-f5f-1`, last sha in `git log -1`.
- CI runs: none (Lean check and tests run locally through the slot).
- State: done. Adopt false for all six arms.

## Verified
- Lean `Fw.Oracle.Retrieve`: `Multi`, `share`, `uniformFirst`, theorems `multi?_two`, `share_few`, `share_multi`;
  `answerGate` with `answerGate_allow`, `answerGate_readFirst`, `answerGate_free`. Wire ops `oracle.retrievePickPos`,
  `oracle.retrieveAnswer`; `oracle.retrieveEvidence` takes `root`. Golden 43 cases.
- `node scripts/jev-trace.mjs position` writes `results/jev-retrieval-trace/position.json` (10 multi rows: f1 4, f2 5, f3 1).
- Forced-read runs: `run --forced yes --model haiku|sonnet`, 38/38 each, 1 Read per row, traces ok. `paired` adds `vsT`.
- Hand trace of the 5 T-haiku-read renorm gains: none traced (`results/jev-retrieval-trace/traced.json`).
- Note updated, incl. the d1k/d1p run split from send-log timestamps (one run each, deviation stated).

## Open
- Shuffled-slot J-pick rerun stays optional.

## Conventions
- Prompts and trees in a scratch work dir: `pnpm -s fw oracle arm-input --set d1 --out <w>/d1.prompts.jsonl`, then
  `jev-trace.mjs trees --work <w>`. `reevidence --work <w> --arm <arm>` recomputes evidence of stored rows.

## Read first
research/notes/2026/10-2x-jev-retrieval-trace.md, lean/Fw/Oracle/Retrieve.lean, scripts/jev-trace.mjs.
