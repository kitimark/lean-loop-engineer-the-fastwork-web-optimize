# dry-land-slow: why `fw land --dry` took 33 to 38 s, and the cut

Task dry-land-slow. Status words: MEASURED (from `.fw-console/timings.jsonl` or my own runs), CONFIRMED (source cited), INFERRED.

## Answer

- Nothing grew per step. Every sub-step ran as long as in the fast sample (reads test 9.7 to 10.1 s in all samples).
  The slow samples ran more checks: the lake build (lint cache miss), the workflow lint, and `runner:overflow-widths`
  (12 s). `fw land` ran its phases one after the other: reads test, then the lints, then the local tests. The dry
  land time was the sum of the three phases (MEASURED, spans below).
- Host load is a small second cause: `console-api:compose` 6.0 s (load 5.4) became 7.1 and 8.3 s (load 4.7 and 6.2).
  The slowest sample (38.1 s) is not the one with the highest load at its start.
- Fix: the three phases start together (Lean `Fw.Ops.LandDry`, theorems `par_eq_seq`, `seqRan_sub_parRan`,
  `waves_cover`), so the dry land costs the longest chain, not the sum. No check is dropped, the refusal named for the
  same results is the same.

## Spans of the dry land (offsets from the start of "land dry lake", seconds; MEASURED)

| step | fast c83df96 (20.8 s, load 5.4) | 001d247 (33.3 s, load 4.7) | 0058ef3 (38.1 s, load 6.2) |
|---|---|---|---|
| claims lint | 2.5 | 1.3 | 2.3 |
| reads test (land-inputs) | 9.9 (3.5..13.4) | 9.7 (2.3..12.0) | 10.1 (3.3..13.4) |
| lake build + axiom check | not run (cache hit) | 7.6 (12.2..19.8) | 8.9 (13.6..22.5) |
| workflow lint | not selected | 2.8 | 2.7 |
| ledger-merge + notes test | 2.1 | 3.5 | 3.0 |
| console-api:compose | 6.0 (14.7..20.7) | 7.1 (21.0..28.1) | 8.3 (24.6..32.9) |
| runner:overflow-widths | not selected | 12.0 (21.0..33.0) | 12.3 (24.6..36.9) |
| total | 20.8 | 33.3 | 38.1 |

Critical path: fast = claims + reads + compose; slow = claims + reads + lake + overflow-widths (1.3 + 9.7 + 7.6 + 12.0
= 30.6 s, plus 2.7 s of git and install before the first check). The checks of one phase ran in parallel, the phases did
not.

## What was added, when (CONFIRMED, git log)

- 2026-10-23 `986f847b9` workflow lint check; 2026-10-24 `94f974b89` any workflow change selects the overflow width test
  (Lean LandTier rule); `29c007fe8` the 6-job width test. Both were on main before the fast sample's window, so neither
  explains a change of speed by itself: the three slow samples are the first dry lands whose change set selected all of
  them together with a lake miss (lean/ and golden changed).
- Since 2026-10-25 no new land lint or local test was added (git log of `apps/runner/src/land*.ts`).

## The rule (Lean first)

`lean/Fw/Ops/LandDry.lean`, golden `packages/contracts/golden/ops/land-dry.jsonl` (8 rows), TS stand-in
`apps/runner/src/land-dry.ts` (marked for Lean replacement by a fwcore op), checked by `apps/runner/test/land-dry.test.ts`.

- `seqVerdict` is the old protocol (each phase only after the earlier ones passed). `parVerdict` runs all and names the
  first failing phase of `order`. `par_eq_seq`: same refusal for the same results. `par_none_iff`: ok only when all
  four pass. `par_reads_first`, `par_lints_second`, `par_ledger_third`, `par_loc_last`: one theorem per branch.
- `seqRan_sub_parRan`: every phase the old protocol ran, the new one runs (no check dropped).
- `waves`: one wave holds reads, lints and local. The lake build and the fwcore build step both go through the
  machine-wide Lake slot (CONFIRMED, scripts/lake-slot-lib.sh:2-3: a flock per slot), so they queue instead of racing;
  a local test that uses fwcore waits for the build step through `checkDeps` (land.ts). A first version kept a second
  wave for that case (`waves_build_serial`); its run took 22.5 s (below), so the rule was dropped for the slot.
- `recordLake`: the lake pass record is written only when reads and lints passed (`recordLake_needs_reads`,
  `recordLake_needs_lints`). The ledger-note check stays a short read after the wave (`waves_no_ledger`).

## Before and after (MEASURED, my own dry lands, lake cache off so the lake step runs; same change set, same machine)

The change set: lean/ and golden changes (lake lint), land-inputs read scan, `research/findings/ledger.json` (selects
compose and the ledger test). `runner:overflow-widths` and the workflow lint cannot be selected inside this task's
writes, so they are absent from both rows.

| run | code | total | load (start, end) | reads | lake | compose | ledger-merge |
|---|---|---|---|---|---|---|---|
| before | main land.ts (phases in series) | 20.8 s | 5.0, 5.1 | 9.8 | 3.2 (warm) | 6.1 | 2.1 |
| mid | phases in series after a build conflict rule | 22.5 s | 3.0, 3.3 | 11.7 | 8.3 | 7.4 | 2.1 |
| after | one wave | 14.2 s | 4.9, 5.5 | 11.2 | 9.2 | 7.7 | 2.3 |

With the slow samples' extra checks (INFERRED from the spans above, not re-run): the chains are reads 10, lake 9 then
fwcore-using tests (compose 7 to 8, overflow-widths 12) behind the build step, so the dry land is about 9 + 12 = 21 s
at the same load, below the 30 s budget, against 33 to 38 s.
Accepted limit: `runner:overflow-widths` waits for the build step, so its 12 s starts after the lake build when both
run; a smaller chain would need the width test not to use fwcore (a follow-up).

## Follow-ups (outside the unit)

- A load-aware baseline for `timing.slow` is not needed: reads (the step least sensitive to the plan) is flat across
  loads 4.7 to 6.2.
- `scripts/hooks/pre-commit` takes about 3 minutes on a commit that touches `research/findings/ledger.json` (the preset
  check elaborates Lean through `lake env lean --stdin`); not part of the dry land.
- The `fwcore-build.sh` step after a lake lint that already built the same tree is a no-op; skipping it needs a rule on
  what `lake build` covers (Lean first).
