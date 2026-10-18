---
title: gate-no-skip, every reading compared or excused by an enumerated exemption, against a Lean universe
date: 2026-10-18
status: MEASURED
---

# gate-no-skip

Question: can the breakpoint gate exit 0 while a reading was skipped, dropped or excused by a wildcard? Task text:
docs/team/work-graph.json `gate-no-skip`.

## Answer first
- **Before (CONFIRMED, Exit.lean at 10e05a80):** two holes. (1) Exemptions had `row`/`ids` as `Option`, with `none` meaning
  any. The two WebKit entries excused every row and every id of their column. (2) The verdict judged only the readings
  the summary supplied. A dropped shard job, probe or stop shrank the table, and nothing compared it with what should be
  there. The narrowed flag came from the engine JSON (`e.parts`), not the command line.
- **After (Lean `Fw.Gate.Exit`, commit 612e9678):**
  - Exemptions list their rows and ids. The WebKit ones list the 18 table rows and the 4 block ids, generated from
    `gateRows` and `blockIds`. `exemptions_enumerated` proves an excuse comes from an entry that lists the row and the
    id, and `excused_in_universe` proves every excused reading is a key of the universe.
  - The universe `gateUniverse` is generated from `truthRows`, `pilotParts`, the 10 matrix blocks and the 4 sweeps:
    18 rows by 196 reading ids per row, 3528 keys. It is printed into `exit.jsonl` as one `universe` line, which
    `cli.mjs` reads.
  - A run that is not narrowed is `refused` unless its keys are a permutation of the universe (`universe_identity`,
    `universe_identity_run`).
  - `narrowed` is the `--parts` flag (`runExit`), and a narrowed run never exits 0 (`narrowed_never_zero`). An engine
    file narrowed by its run but summarized without the flag lacks universe keys, so it is refused.
  - The exit iff is per engine, per key, per cell and per wait (`exit_zero_iff_all_cells`).
- **Chromium fractional entry:** it is now limited to the 4 fractional probe ids and the `matchMedia =Lean` row. Its
  premise `fractional_chromium_lean_na` holds the reach fact (Chromium `envReason` none, width not whole) and the
  `truthItems_lean_na` fact.
- **CI (MEASURED):** see the table below. The acceptance figure is the `gate readings` line, not the job conclusion,
  because WebKit stays red until gate-webkit-red.

## CI runs (ci/gate-no-skip, head 612e9678)
| run | event | engine | total | pass | excused | bad | universe | table sha256 (first 12) | summary exit (runExit of the printed verdict, INFERRED) |
|---|---|---|---|---|---|---|---|---|---|
| 39130848323 | push | chromium | 3528 | 3521 | 7 | 0 | identical | ef0128c824f0 | summary 0 (pass) |
| 39130848323 | push | playwright-webkit | 3528 | 3366 | 147 | 15 | identical | 26cbd4f42f36 | summary 1 (fail) |
| 39130859625 | dispatch | chromium | 3528 | 3521 | 7 | 0 | identical | ef0128c824f0 | summary 0 (pass) |
| 39130859625 | dispatch | playwright-webkit | 3528 | 3366 | 147 | 15 | identical | 26cbd4f42f36 | summary 1 (fail) |

The two runs produce byte-identical per-reading tables (`readings-<engine>.json`; the merge step prints their sha256).
WebKit has 15 bad readings, so it stays red, as gate-webkit-red expects:
- 13 `platform.stageBg` desktop-sweep fails;
- 2 not-comparable `matchMedia =Lean` phone-rotation stops, #1 and #3, which no exemption covers.

Mutant (ci/gate-no-skip-mutant, 3602cf62): summary.mjs sets the first reading of the table (`matchMedia orig=rewrite`,
`desk`, `desk-319`) to not-comparable. Run 39130919551 (MEASURED):
- Chromium: verdict `incomplete`; readings total 3528, pass 3520, excused 7, bad 1
  (`not ok: matchMedia orig=rewrite|desk: desk-319 not-comparable`). Its summary therefore exits 1, where the unmutated
  run exits 0.
- WebKit: bad 16.
- Job exit code: 1.

## Threat model and accepted limits
- Must catch: a reading neither pass nor listed by an exemption; an excuse beyond its listed rows or ids; a supplied
  set that differs from the universe (missing, extra, doubled, misplaced); a narrowed run reported as exit 0.
- Need not catch, accepted: the view stage stays off by default; the frozen clock gives end states only; WebKit stays
  red until gate-webkit-red; the merge job's conclusion is not the acceptance figure.
- `cli.mjs` is still the TS stand-in, checked against the 87 Lean golden lines (57 engine cases with an explicit
  universe, 15 run cases with the narrowed flag).

## Follow-ups
- The touch-1024 stops (`touch-1024-1201#0,2,4`) still use an exemption (`touch1024_lean_na`). Lean expected vectors
  from breakgen would remove it, but that needs BreakpointGen.lean, breakpoints.gen.json and spec.mjs, which are
  outside this task's write scope.
- The breakpoint-gate workflow does not pass `--parts` to `summary`. A dispatched narrowed run is therefore refused by
  the universe check instead of being reported as narrowed. Both outcomes exit 1. Passing the flag needs a change to
  `.github/workflows/breakpoint-gate.yml`, which is outside this task's write scope.
