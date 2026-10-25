# ledger-class-lint handoff

- Branch `worktree-wf_f85a205d-8b4-1`, worktree `.claude/worktrees/wf_f85a205d-8b4-1`; the last commit is `git log -1` on
  the branch. No CI runs: the task needs none, since the check runs in `lean/scripts/check.sh`.
- Verified: the `Fw.Preset.Gen.run ["--check"]` preset check passes after the backfill and failed on all 18 classed
  flags before it. The apps/runner `test/ledger-merge.test.ts` passes (41 tests; the ledger round-trips byte for
  byte). `check.sh` and the dry land: in the report.

## State
- `lean/Fw/Preset/V2Proved.lean`: `Row.visClass : Option VisClass := none`.
- `lean/Fw/Preset/Gen.lean`: `parseRow` reads `visClass`. New: `flagRows`, `ClassIssue`, `classIssue`,
  `classDisagreements`, `ClassAgrees`, the theorems `classDisagreements_eq_nil_iff`, `classIssue_eq_none_iff`,
  `classIssue_of_{noRow,rowCount,differs,unclassed}` and `mem_classDisagreements`, and `#guard` cases after the
  `lookJson` guard. `run` throws "the ledger visClass disagrees with part.json".
- `research/findings/ledger.json`: `visClass` sits right after `flag` on 17 rows. New row n 80 `pain.dark-static`
  (L). `about` documents the field.
- `research/notes/2026/10-2x-ledger-class-lint.md`: the check and the four decisions (n 39, 49, 50, 52 all L,
  matching part.json; no part.json change).

## Open
- The lead confirms the four L decisions (table in the note).
- Follow-up, not built: rows that carry a `visClass` but whose flag has no part.json class are not checked.

## Conventions
- Write the ledger with `JSON.stringify(doc, null, 1) + "\n"`, which gives 3-space row keys. A new classed flag
  needs its ledger row and `visClass` in the same branch, or check.sh fails.
- Backfill script used: scratchpad `lcl/backfill.mjs`, which is not committed. It copies part.json `visClass` onto
  rows by `flag`.

Read first: the note, then `Gen.lean` from `flagRows` on.
