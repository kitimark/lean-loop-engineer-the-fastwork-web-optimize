---
id: 2026-10-29-gen-merge-retry-bound
kind: note
title: "Gen.merge keeps every stored trajectory row; a newer run supersedes an older one only on a reader change or within a retry bound of 2; hero.exit:threaded stays met"
status: draft
created: 2026-10-29
topics: [trajectory-probe, gate, preset, lean, hero.exit]
---

# Gen.merge retry bound

Task `gen-merge-retry-bound`. Unit of decision: the supersession rule of stored trajectory rows in Lean
(`lean/Fw/Preset/V2Proved.lean`, section "Superseded rows"), the merge and run-id parser in `lean/Fw/Preset/Gen.lean`,
their theorems, and the preset goldens regenerated with `Gen.record`. No CI runs.

## Answer

- `hero.exit:threaded` keeps its gate met. The macOS WebKit morph no-verdict of run 40671695274 and the pass of run
  40674554372 share one reader version (`03b75d1b69fa`); the no-verdict is the first of two runs at that version, so
  the pass supersedes it as the one allowed retry. The webkit/morph cell reads pass, and all four cells read pass.
  With a bound of 1 the no-verdict would stay live and the cell would read pending.
- The rows the previous merge deleted are back in the stored file, marked superseded: 5 rows of run 40156078840
  (old reader `6ee3baa8`, 3 of them fails) are superseded by reader change; the 40668662980 linux-webkit hero pass and
  the 40671695274 rows are kept live or superseded per the rule.
- No other flag changes a cell or a verdict (each flag's cells and verdict compared before and after; only the
  evidence text and the new `superseded` field differ).

## The rule

CONFIRMED (Lean, `lean/Fw/Preset/V2Proved.lean`):

- A row's key is (flags, engine, walk). Its reader is the git object id of the `git ls-tree` listing of the 13 files the
  trajectory probe runs at the row's commit (`Gen.readerFiles`, the relative-import closure of
  `packages/gate-breakpoints/src/trajectory/cli.mjs`; `packages/gate-breakpoints/test/reader-files.test.mjs` checks the
  list).
- `supersede st s` is `.reader n` when a later row of the key has another reader (the first such run); else `.retry n`
  when `s` has no verdict and `streak st s < retryBound`, where the streak counts the key's runs since the last reader
  change up to `s`; else none. A pass or a fail is never superseded at its own reader.
- The cell reads the conjunction (`keyOutcome`) of the live rows of each key: fail if any fails, else no verdict if any
  has none, else pass.
- `retryBound = 2`: the first run plus one retry. A retry replaces a no-verdict only, so per reader version at most one
  no-verdict is dropped; a second no-verdict at the same version stays live and keeps the cell pending.

| Theorem | Statement |
|---|---|
| `fail_not_hidden` | a fail with no later row at another reader makes its cell fail, whatever later runs pass |
| `retry_spent` | a no-verdict after a no-verdict at the same reader stays live and its key is not pass |
| `supersede_reader`, `reader_needs_change` | supersession by reader needs a later row with another reader |
| `supersede_retry`, `retry_needs_noVerdict`, `live_of_bound` | supersession by retry needs a no-verdict within the bound |
| `merge_keeps` | a stored row leaves the file only when a new row re-records its run, engine and walk |
| `merge_idem` | recording the same rows twice equals recording them once |
| `parseRunId_ok`, `parseRunId_error` | a run id is all decimal digits, anything else is an error |

## Changes

- `Stored` gains `reader` (Fw.Gate.Trajectory) and its `run` is a `Nat`. Old rows were not left at version 0: every
  row's commit exists in git, so `Gen.record` filled each reader from its commit. `Gen.run` refuses a stored file with
  an empty reader.
- The stored file carries `reader`, `outcome` and `superseded` (`{"by", "why"}` or null) per row, written by
  `Gen.run` and checked by `--check`. Rows are sorted by run number, then engine and walk.
- Stored file: 73 rows, 30 superseded (28 by reader change, 2 by retry: the hero.exit:threaded mac morph above and the
  hero.exit:scoped linux-webkit morph no-verdict of 39448209903, superseded by 39452631146).

## Lesson

A store of measurement runs that lets the newest run win also lets a re-run hide a failure. Keep every row, decide per
row whether it counts (identity of the reader code, not run order), and read a cell as the conjunction of the rows that
count.
