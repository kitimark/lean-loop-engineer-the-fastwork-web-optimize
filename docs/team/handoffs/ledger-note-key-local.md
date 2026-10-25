# ledger-note-key-local handoff

- Branch `worktree-wf_d25c26b4-c01-1`, worktree `.claude/worktrees/wf_d25c26b4-c01-1`; work commits 17910dbcc, 40b3549d0
  (this file is in the commit after them). No CI runs (no dispatch in the unit).
- Verified: `sh lean/scripts/check.sh` green (axiom check 0 failing); `pnpm --filter ./apps/runner test` 3480 passed
  (tsc included); `node --test scripts/ci-paths.test.mjs` exit 0; `fw incidents lint` 0 errors; plan lint 0 errors.
- Lean `lean/Fw/Ops/LedgerMerge.lean`: `twice`, `firsts`, `dupKeys`, `onePerKey`; theorems `twice_iff`,
  `mem_dupKeys`, `dupKeys_nodup`, `onePerKey_iff` (pass), `onePerKey_false` (refusal), `onePerKey_merge`,
  `onePerKey_tasks_merge` (both from `distinct_notes_merge`). Golden cases `noteKeyCases`, written by the same
  `Golden.run` as ledger-merge (no new check.sh job, no FwTestMain edit).
- Golden `packages/contracts/golden/ops/ledger-note-key.jsonl`, regenerate `cd lean && lake test --
  --write-ledger-merge-golden`; replayed in `apps/runner/test/ledger-merge.test.ts`.
- Dry stage: `ledgerNoteKeyCheck` in `apps/runner/src/land.ts`, after the fast lints, before the local tests; refusal
  `VERDICT lint` with `REFUSED: ledger-note-key: ...` and a row per repeated key. Test in `apps/runner/test/land-dry.test.ts`.
- Incident row `inc-ledger-note-key-dup` (no n), note `research/notes/2026/10-2x-ledger-note-key-local.md`, docs
  `docs/team/tools/land.md` (last section).
- Open: build-review preamble (under `.claude/`) could name the rule "one ledger note per (entry, task)" (lead's edit).
  The real land does not run the stage (remote `ledger-merge.test.ts` is the second line).
- Read first: the last section of `docs/team/tools/land.md`, then the `onePerKey` section of LedgerMerge.lean.
