# Handoff: faithful-empty-guard

- Branch: worktree-wf_430146b4-b48-1; worktree .claude/worktrees/wf_430146b4-b48-1
- Last work commit: 1a3c538f7 (guard, proofs, goldens, TS caller); this handoff and the note follow it.
- CI runs: none (no CI measurement in scope).

## State
- Lean: `Fw.Faithful.evidence`, `Judged`, `zoneJudged`, `judged`, `unguarded` in `lean/Fw/Faithful/Zone.lean`;
  `verdictReply`, `unguardedReply`, `zoneFields` in `lean/Fw/Faithful/Wire.lean`; `opVerdict` returns `verdictReply`.
- Proved: (a) `evidence_of_judged_pass`, `evidence_of_reply_pass`; (b) `judged_eq_unguarded`,
  `verdictReply_eq_unguarded`; branch theorems per `judged` outcome.
- Goldens: `faithful.verdict.jsonl` gained rows 16-21; rows 1-15 byte-identical.
- TS: `faithful.mjs` `stateOf`, `undecidedZones`, `namedLines`; `UNDECIDED: <p>: <reason>` exits 1; `leanSource`
  refuses undecided verdicts. `test/faithful.test.mjs` covers the undecided rows.

## Verified
- `node --test test/faithful.test.mjs`: 12/12 pass (committed verdict files and Measured.lean unchanged).
- `sh lean/scripts/check.sh` (fw slot): all gates green, axiom check 0 failing.
- Package tests `@fw/measure-chromium` (104 pass), `@fw/contracts` (11 pass); `scripts/ci-paths.test.mjs` (56 pass);
  `apps/runner` `land-inputs.test.ts` (73 pass).
- main merged (no new commits); `fw plan lint`: 0 errors, no writesClosure line for this task.
- Dry land: `VERDICT dry faithful-empty-guard`.

## Open
- NavFixedCounts partial-arm question (audit open 3) not in scope.

## Read first
`research/notes/2026/10-2x-faithful-empty-guard.md`.
