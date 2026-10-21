# Handoff: jev-replay (lean-prover)

## State
- Branch `worktree-wf_30bab1a1-3ee-1`; Jev arm run and scored on 2026-10-21 UTC (the answer log's day).
- Lean: `Fw/Oracle/Questions.lean` (incident-class, finding-severity), `Send.lean` (`RunBudget`, `preRun`),
  `Replay.lean` (sets D1/D2, `scrubWf`, `minHoldout`, stratified sample, score math), `ReplayWire.lean` (ops
  `oracle.replay`, `oracle.preRun`, `oracle.score`), `Calibrate.lean` (`heldOut` = `Labels.heldOut`).
- CLI: `fw oracle send|score|arm-input` (apps/runner/src/oracle.ts, oracle-score.ts); client `replayRun` gate.
- Results: `results/jev/d1.json`, `d2.json` (arm `jev`); note `research/notes/2026/10-2x-jev-replay.md`.

## Verified
- `sh lean/scripts/check.sh` green; axioms standard; runner vitest + tsc, packages/oracle tests, ci-paths tests.
- Live: D1 116/116, D2 83/90 (daily cap 200 reached). Accuracy D1 52.6 %, D2 48.2 %; nothing certified.

## Open
- 7 D2 rows (follow-up) after the UTC day rolls over: `pnpm fw oracle send --set d2`, then
  `pnpm fw oracle score --set d2`, then update the D2 tables of the note.
- Haiku/Sonnet arms: the lead runs them (`fw oracle arm-input`, prompt and format in the note), then
  `fw oracle score --arm haiku|sonnet --answers <file>`.
- Finding: `Core.eps` = 1/1000 rejects 9/116 Jev replies (14 probabilities rounded to 0.01 sum to 0.99). Make eps
  depend on the option count or renormalize (Fw.Oracle.Core, outside this task).

## Conventions
- Live sends only as bare `pnpm fw oracle send ...`; datasets stay in `.cache/jev` (gitignored); prompts files stay
  out of git.
- Read first: the note, then `lean/Fw/Oracle/ReplayWire.lean` (op table in its module doc).
