Branch: worktree-wf_c479f33a-757-1
Worktree: .claude/worktrees/wf_c479f33a-757-1 (under the repo root)
Last commit: see `git log -1` (WIP e613e878f, then the land-scope test fix and this handoff). CI runs: none (no CI pushes in this task).

State: built and checked locally. check.sh green (slot), runner package test green after the land-scope.test.ts fix, ci-paths test 56/56, tsc clean.

What it does (read research/notes/2026/10-2x-ledger-note-check.md first):
- Lean `Fw.Ops.CheckMap`: new `Check.ledgerNotes`, trigger `ledgerInput` (findings ledger only); theorems `ledgerInput_planned`, `ledgerInput_planStaged`, `findingsLedger_planned`, `ledgerInput_not`; `plan_covers`/`plan_sound` extended. Golden: `packages/contracts/golden/ops/checkmap.jsonl` (3 new cases).
- Lean `Fw.Console.LandTier`: `ledgerNotesReads`, third `localTests` entry `runner:ledger-notes`; theorems `ledger_selects_notes`, `ledgerNotes_reads_ledger`, `ledgerNotes_local`, `ledgerNotes_no_core`. Golden: `golden/console/land-tier-local.jsonl`.
- TS: `apps/runner/src/land-notes.ts` (`noteShapeProblems`, TS stand-in), `land.ts` (`ledgerNoteKeyCheck` also judges shape; `LOCAL_TESTS` gets the ledger gate from the golden), `scripts/checkmap.mjs` mode `file ledger`.
- Tests: `apps/runner/test/land-notes.test.ts`, `scripts/test-checkmap.mjs` section 3b (fixtures), fixes in land-dry/land-inputs/land-scope tests (ledger gate is not an fwcore user).
- Records: `research/mistakes/ledger.json` m219, m220 (c-late-check); `docs/team/incidents/ledger.json` inc-ledger-note-late (fix.task ledger-note-check, commits empty until landed).

Open: (1) files outside the row's writes: lean/Fw/Console/LandTier.lean, lean/scripts/CheckMapGolden.lean, packages/contracts/golden/console/land-tier-local.jsonl, apps/runner/test/land-scope.test.ts is in scope. (2) `node scripts/test-checkmap.mjs` is wired to no job and fails on the preset import-closure case (27 modules vs 3 listed) before this task. (3) incident `fix.commits` to fill after the land.
Limits: `git commit --no-verify` bypasses the hook; the dry land still blocks; the remote suite stays the last line.
