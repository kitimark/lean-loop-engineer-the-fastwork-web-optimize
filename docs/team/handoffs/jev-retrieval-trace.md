# jev-retrieval-trace handoff

- Branch `worktree-wf_c7cc80f6-a2a-1`, worktree `.claude/worktrees/wf_c7cc80f6-a2a-1`, last sha in `git log -1`. CI runs: none.
- State: done. Lean, harness, all four arms, paired tables (main scoring after oracle-eps), note. Adopt false for all.

## Verified
- `Fw.Oracle.Retrieve` + `Fw.Oracle.RetrieveWire` (12 ops), golden `packages/contracts/golden/oracle/retrieve.jsonl`
  (36 cases, `lean/scripts/RetrieveGolden.lean --check` in `lean/scripts/check.sh`); `node --test scripts/jev-trace.test.mjs`.
- Probe: thinking text not exposed. T-haiku and T-sonnet: 38/38 each, 0 reads, traces all ok.
- J-hybrid = C (0 ranges, 38 replays). J-pick: 36 + 31 Jev sends; the day ends at 116 of 200.
- `results/jev-retrieval-trace/paired.json` and the note `research/notes/2026/10-2x-jev-retrieval-trace.md`.

## Open
- Forced-read variant (a prompt that requires a read) not run; "would reading help" is still open.
- J-pick step 1 never chose `none`; 26 of 36 rows had a single candidate, and over the 10 multi-candidate rows it chose
  f1 4, f2 5, f3 1 (no position bias seen). A shuffled-slot rerun is optional.

## Conventions
- Prompts: `pnpm -s fw oracle arm-input --set d1 --out <scratch>/d1.prompts.jsonl`; trees and raw streams stay in the
  scratch work dir. Jev datasets `d1-hybrid`, `d1-pick1`, `d1-pick` go to the shared `.cache/jev/`.
- Order: `trees`, `probe`, `run --model haiku|sonnet`, `hybrid`, `pick1`, send `d1k`, `pick2`, send `d1h`/`d1p`, `paired`.
- Writes beyond the first graph entry (added in graph r253): `lean/Fw/Oracle/Questions.lean` (filePick), `lean/Fw/Oracle/Replay.lean` (d1h, d1p, d1k),
  `lean/Fw/Wire.lean`, `lean/scripts/check.sh`, `lean/scripts/RetrieveGolden.lean`.

## Read first
research/notes/2026/10-2x-jev-retrieval-trace.md, lean/Fw/Oracle/Retrieve.lean, scripts/jev-trace.mjs.
