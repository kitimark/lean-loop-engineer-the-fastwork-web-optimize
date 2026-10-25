# One ledger note per (entry, task) now refuses in fw land --dry, not only on the land lane

Answer: `fw land --dry` checks the merge tree's `research/findings/ledger.json` notes and refuses a repeated
(entry, task) key as `VERDICT lint` with a `REFUSED: ledger-note-key: ...` line naming each repeated key, its note
count and fields. The rule is Lean `onePerKey` (lean/Fw/Ops/LedgerMerge.lean); a pass gives the distinct-keys premise
of `distinct_notes_merge`, so passing add-only branches of different tasks merge with no clash (`onePerKey_tasks_merge`).
Before this task the dry land passed both refused branches. Incident `inc-ledger-note-key-dup`.

## The two refusals

| branch | notes under one key | fields | land run | failed tests in `ledger-merge.test.ts` | fix |
|---|---|---|---|---|---|
| combo-scroll-fight | 3 | mechanism, visual, next | 40137318231 | keys distinct (57 vs 59), hero.exit append (1 conflict) | 9f59cf85a |
| commission-band-mech | 2 | mechanism, missingWhy | 40144233684 | keys distinct (58 vs 59), hero.exit append (1 conflict) | fe854965f |

MEASURED: both runs' `--log-failed` output (suites-a leg) show these two assertions, at `ledger-merge.test.ts:68` and `:78`.

## Why a repeated key breaks the merge

CONFIRMED (scripts/merge-ledger.mjs `idKeyed`, line 47, and its use at line 121): a notes array with a repeated key is
not id-keyed, so the driver merges `notes` as one whole member and any concurrent note change by another branch is a
conflict. That is the second failing test: one appended note on each side gave 1 conflict instead of 0. In Lean,
`merge` assumes distinct keys; the `#guard` beside `onePerKey_tasks_merge` shows a branch with two notes under one key
merging to the first note twice and losing the second.

INFERRED: builders read the note shape (one `field` per note) as one note per field; the remote test was the only
place the rule lived, and it runs only after the full CI land.

## What runs where

- Lean: `onePerKey`, `dupKeys`; theorems `onePerKey_iff` (pass branch), `onePerKey_false`, `mem_dupKeys` (refusal
  branch: a key is named iff it repeats), `dupKeys_nodup`, `onePerKey_merge`, `onePerKey_tasks_merge`.
- Golden `packages/contracts/golden/ops/ledger-note-key.jsonl`: the two refused trees (the last notes of each branch
  tip before its fix, strings from history), the fixed tree, two passing shapes, two repeated keys. Written by
  `Fw.Wire.LedgerMerge.Golden.run`, checked by `lake test`.
- TS: `noteKeyDups`, `onePerKey`, `noteKeyRefusal` (`apps/runner/src/land-verdict.ts`) replay the golden in
  `apps/runner/test/ledger-merge.test.ts`; `ledgerNoteKeyCheck` (`land.ts`) is read and parse glue.
- MEASURED cost on this Mac: 1.21 ms per read, parse and check of the 418148-byte ledger (mean of 20; a debug
  measurement, not a result).

## Limits

The real land does not run the stage; the remote `ledger-merge.test.ts` stays as the second line. The build-review
preamble does not name the rule yet (an edit under `.claude/`, the lead's).
