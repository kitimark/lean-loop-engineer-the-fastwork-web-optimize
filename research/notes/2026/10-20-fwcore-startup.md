---
id: 2026-10-20-fwcore-startup
kind: note
title: "fwcore start cost: eager top-level tables made each spawned call cost 0.81 s CPU; lazy tables bring it to 40 ms CPU on CI"
status: review
created: 2026-10-20
topics: [lean, fwcore, runner, performance, lint]
---

# fwcore start cost

## Answer
- Every spawned `fwcore` call ran the module initializers of its whole import closure before `main`. They evaluated
  794 top-level constants, golden tables among them, for 14,440,789 small allocations. Four tables held 8,787,831 of
  them (61 %). CONFIRMED by source (below) and MEASURED by the init-cost lint.
- Fix: each table over 10,000 allocations is now a function `def x (_ : Unit := ()) : T` (85 definitions in 42
  files, plus one instance). Call sites keep the
  spelling `x`, because the elaborator fills in the default argument. The body becomes a lazy closed term, evaluated
  on first use and then cached. After the change, start evaluates 708 constants for 491,561 allocations (3.4 % of
  before). MEASURED.
- On CI (lean lane, ubuntu-24.04-arm, 4 CPUs), each spawned call with one cheap wire request costs:

  | | CPU ms per call | wall ms per call | run |
  |---|---|---|---|
  | before (64b04ef1) | 812.4 | 812.7 | 39323151165 |
  | after (42205e01) | 40.4 | 40.4 | 39324877968 |

  MEASURED: 50 calls each by `lean/scripts/start-timing.sh`, artifact `fwcore-linux-arm64` file `fwcore-start.json`,
  same runner image (20261012.149.1). Each call now costs 1/20 of the CPU it did, and saves 0.77 s.
- Every generator and golden output is byte-identical. Every `--check` in `lean/scripts/check.sh` is green, and a
  before/after dump of `partsgolden`, ContractsGolden, ShardGolden, the wire replay, `--ops` and `sweepsgen` is
  identical. The only lines that differ are the timing lines `fwcore fwtest` prints. MEASURED.

## Cause, from the compiler source
- `emitDeclInit` (src/Lean/Compiler/LCNF/EmitC.lean:986-1005 @ eb6cafb, v4.35.0) emits `x = _init_x();` into the
  module's `initialize_` function. It does this for every zero-parameter declaration that has no `[init]` function
  and is neither a closed term (`isClosedTermName`) nor a simple ground declaration. So a top-level
  `def lines : List String := ...` runs at program start. CONFIRMED.
- Extracted closed terms are read through `lean_obj_once` (EmitC.lean:93 and 620-631), which evaluates on first use.
  A declaration with one parameter is not zero-parameter, so its body is only evaluated through such a cell or a
  call. CONFIRMED.
- In the generated C on main, `lean/.lake/build/ir/Fw/Parts/PainNotesGolden.c:12688` reads
  `lp_fwcore_Fw_Parts_PainNotesGolden_lines = _init_lp_fwcore_Fw_Parts_PainNotesGolden_lines();`. After the change,
  that line is gone; the only `_init_` lines left in the file are boxed scalar constants. CONFIRMED.

## The four named tables, allocations at start before the change (MEASURED, init-cost lint over main's build)

| constant | allocations |
|---|---|
| `Fw.Wire.Shard.Golden.cases` | 4,692,616 |
| `Fw.Parts.PainNotesGolden.lines` | 2,831,412 |
| `Fw.Parts.Contract.rowsText` | 655,575 |
| `Fw.Parts.Contract.diffText` | 608,228 |

Making these four lazy left 5,703,647 allocations. The other 65 constants over the bound include
`Fw.Site.Reference.referenceChromium` (992,492), `referenceWebkit` (928,151), `Fw.Ci.Trigger.goldenText` (391,456),
`Fw.Site.BreakpointGen.genText` (373,327) and `Fw.Parts.Contract.footprintText` (257,082). The lint attributes the cost
of a lazy table to the first start-time constant that forces it. Three rounds were needed: after each round, the
consumers of the newly lazy tables showed up. One of them was the instance `Fw.Ops.LeanFirst.instEnumFacts`, whose
seed list is now read inside `enum`.

## The lint (`Fw.Lint.InitCost`, `Fw.Lint.InitCostScan`)
- Identity: the constants that start evaluates are the `X = _init_X();` lines of `.lake/build/ir/**/*.c` for the
  modules `Main` reaches. Each stem maps to a constant by `Lean.getSymbolStem` over the module's IR declarations. A
  stem with no constant is a finding unless it is a boxed scalar (`___boxed__const__`).
- Cost: in an elaborated file (`lake env lean scripts/InitCostLint.lean`), each constant is evaluated in start order.
  Its cost is the difference in `IO.getNumHeartbeats`, which counts small allocations per thread. The count is
  deterministic, unlike time. The probe returns the value, so the compiler cannot move the evaluation past the second
  heartbeat read.
- Verdict: `findings` is empty exactly when each unmapped stem is a boxed scalar and each cost is at most `bound`
  (10,000) (`findings_nil_iff`; branch theorems `rowFinding_within`, `rowFinding_over`, `stemFinding_boxed`,
  `stemFinding_unmapped`).
- Test: `scripts/init-cost-cases/Adv.lean` is compiled to C in a temp directory. The findings must equal
  `Adv.expected.txt`: an eager 20,000-row table, and an eager constant that forces a lazy 30,000-row table. A small
  constant, a constant that reuses the eager table, and two lazy functions must pass.
- Cost of the gate: 33 s wall for the lint and 15 s for the cases, at load 166 on this Mac, inside the parallel group.

## Local debug run (not a result)
At load 130-166 on this Mac, 5 calls each: 941 ms CPU per call with the old binary, 44 ms with the new one.

## Limits and follow-ups
- The runner suite's total fwcore CPU was not measured. An estimate is the number of spawns times the per-call
  saving. A persistent `fwcore serve` for the runner is task fwcore-serve-runner.
- Constants just under the bound remain eager, for example `Fw.Wire.Plan.Golden.wfText` (9,970). Lowering `bound`
  is a one-line change; the lint then lists what to convert.
- Probes measure constants in `Type` only. A start-time constant in a higher universe stops the lint with an error;
  none exists today.
