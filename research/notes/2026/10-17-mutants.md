---
id: 2026-10-17-mutants
kind: note
title: "M0 mutation testing: every mechanical and design mutant of the M0 Lean modules killed or proved equivalent"
status: done
created: 2026-10-17
updated: 2026-10-17
authors: [agent:m0-mutants]
topics: [lean, testing, mutation, m0-gate]
links:
  refs: [docs/plan/PLAN.md]
  sources: []
  experiments: []
  v1: []
---

# M0 mutation testing (PLAN §10.2 M0 "every M0 mutant killed", V-r, §5.4)

Question: do the theorems, `#guard`s and golden tests of the M0 modules notice when the code is
changed in a small way? A mutant that changes the code and still passes every check marks a missing
theorem or golden case.

## Method

- Modules: `Fw/Console`, `Fw/Serve`, `Fw/Ops/{Meter,PathCheck,SpawnGuard,Usage,Wire}`,
  `Fw/Spec/DeviceQueue`, `Fw/Wire`.
- Harness: `lean/scripts/mutants.sh` (driver) and `lean/FwTest/Mutants/gen.mjs` (text rewriting only;
  no decision logic).
  - The baseline is a copy of `lean/` plus the contract goldens in `.cache/mutants/base`
    (gitignored), built with `enableArtifactCache = false` so mutant builds never touch the shared
    cache. The real source tree is never written.
  - Each mutant runs in its own APFS clone of that baseline (`cp -c`, about 1 s). The first failing
    step decides the verdict:
    1. `lake build <mutated module>`
    2. `lake build Fw FwTest.Mutants.Kill`
    3. `lake test`
    4. the `fwcore` wire golden diff
- Mechanical operators. They act only inside `def`/`abbrev`/`instance` bodies; fixture defs
  (`boardCases`, `boardGolden`, `sampleRequests`) are skipped; string mutants are capped at 2 per def.
  - comparisons: `<`↔`≤`, `>`↔`≥`, `==`↔`!=`, ` = ` to `≠`
  - logic: `&&`↔`||`, `∧`↔`∨`, drop `!`, `true`↔`false`
  - branches: negate an `if` condition (swaps its branches)
  - numbers: n±1 (off by one), `+`↔`-`, `min`↔`max`
  - lists and options: `any`↔`all`, drop a `.filter`, `head?`↔`getLast?`, `take`↔`drop`, drop
    `.reverse`, `isSome`↔`isNone`
  - strings: empty a string literal
- Design mutants: 12 hand-written `.patch` files under `FwTest/Mutants/<Module>/`, each putting back
  one v1 bug class:
  - I-059 done-without-start
  - I-145 answer keeps the wait open
  - I-011 no aging; I-011 head-of-line blocking
  - I-041 co-hold while running
  - duplicate event applied twice; refused key marked seen
  - self review; name reuse; alert repeats; usage double count
  - `..` in scope
- Verdicts:

  | verdict | the first failing step was |
  |---|---|
  | killed:proof | a theorem |
  | killed:guard | a `#guard` |
  | killed:build | another module's def |
  | killed:test | `lake test` |
  | killed:fwcore | the wire golden diff |
  | killed:timeout | a step ran past its time limit |
  | stillborn | the mutated def itself is ill-typed |
  | equivalent | none: the mutant survived, and `FwTest/Mutants/equivalent.tsv` gives a checked reason |
  | survived | none: the mutant survived, and no reason is listed |

## Results (MEASURED, 8-CPU laptop shared with other agents, 3 workers)

Round 1 (`r1`): 613 mechanical mutants against the existing theorems and goldens.

- 2369 s wall-clock; 6969 s summed over the workers.
- Outcome: 539 killed, 1 stillborn, 73 survived.

| module | all | killed | survived |
|---|---:|---:|---:|
| Fw/Console | 150 | 142 | 8 |
| Fw/Serve | 90 | 86 | 4 |
| Fw/Ops/Meter | 33 | 24 | 9 |
| Fw/Ops/PathCheck | 40 | 37 | 3 |
| Fw/Ops/SpawnGuard | 77 | 67 | 10 |
| Fw/Ops/Usage | 29 | 25 | 4 |
| Fw/Ops/Wire | 61 | 46 | 15 |
| Fw/Spec/DeviceQueue | 26 | 20 | 6 |
| Fw/Wire | 107 | 92 | 14 (1 stillborn) |

Design mutants (`d1`): 12 of 12 killed, 11 of them by an existing theorem (for example
`step_seen`, `refused_keeps`, `dispatch_busy`, `aged_beats_newer`, `faccept_st`, `inScope_iff`).

Round 2 (`r2`): the 73 survivors again, with the new killers.

- 207 s.
- Outcome: 66 killed, 2 equivalent, 5 to fix. Three of those five failed only because the run
  started before their guard was written.

Final run (`final`): all 625 mutants (613 mechanical + 12 design) against the final killers.

- 1392 s; exit status 0.
- Outcome: 0 survived.

| module | all | killed | proof | guard | test | fwcore | stillborn | equivalent | survived |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Fw/Console | 155 | 155 | 85 | 70 | 0 | 0 | 0 | 0 | 0 |
| Fw/Serve | 90 | 90 | 74 | 13 | 0 | 3 | 0 | 0 | 0 |
| Fw/Ops/Meter | 34 | 34 | 24 | 10 | 0 | 0 | 0 | 0 | 0 |
| Fw/Ops/PathCheck | 41 | 41 | 26 | 15 | 0 | 0 | 0 | 0 | 0 |
| Fw/Ops/SpawnGuard | 78 | 77 | 42 | 35 | 0 | 0 | 0 | 1 | 0 |
| Fw/Ops/Usage | 30 | 30 | 16 | 9 | 5 | 0 | 0 | 0 | 0 |
| Fw/Ops/Wire | 61 | 61 | 0 | 34 | 27 | 0 | 0 | 0 | 0 |
| Fw/Spec/DeviceQueue | 29 | 29 | 21 | 8 | 0 | 0 | 0 | 0 | 0 |
| Fw/Wire | 107 | 104 | 0 | 64 | 40 | 0 | 1 | 2 | 0 |
| **total** | **625** | **621** | 288 | 258 | 72 | 3 | 1 | 3 | **0** |

## What the survivors showed, and the fix

Each fix is in `lean/FwTest/Mutants/<Module>.lean`, imported by `FwTest/Mutants/Kill.lean`.

- **Console (8).** These survived because no test exercised those spots:
  - two refusal messages
  - the `"hook"` actor name
  - two `cardRefusal` branch conditions
  - the `&&` of the violation flag
  - the `stale` boundary

  Fix: about 90 `#guard`s that pin every refusal reason, every accept effect on the card, step and
  run rows, the stage and ready cases, and the stale edges.
- **Serve (4).** The `console.reset` op name and the `"outcome"`/`"reset"` reply keys were never
  checked: the board golden ignores the reset reply, and a reset of the initial state changes
  nothing. Fix: exact reply lines, plus "a reset forgets the card and its seen key".
- **Meter (9).** `Obs.le` is only ever a hypothesis, so a stricter `<` keeps every theorem true.
  Fix: `obs_le_refl` (reflexivity). The verdict ranks were only used through their order. Fix:
  `rank_values`.
- **PathCheck (3).** `parseScope` was only reached through `inScope`, and there a `!glob` that leaks
  into the includes matches nothing. Fix: guards on the exact parse.
- **SpawnGuard (10).** Several helpers had no direct tests: `countSub`/`countRole` without their
  filter, the `excused` conjunction and its `none` case, `isAsk` any→all, the last start position
  of `hasInfix`, and the example fixtures. Fix: guards for each.
- **Usage (4).** The rejected `lastWins` rule was only checked for order dependence. Fix: its exact
  result.
- **Ops/Wire (15).** Decoder defaults (missing counts are 0, a missing `edits` is false, the meter
  `window` and the TTL inputs), the `perRole` key, the `ctxBig`/`coldWake` names and the op list
  were not covered by any golden case. Fix: exact `handle` replies, plus "every listed op is
  dispatched".
- **DeviceQueue (6).** The aging constant `A`, the `dispatchHoL` window edges, and the `tick` stop
  at exactly `t0 + dur`. Fix: `A_eq` and boundary guards.
- **Wire (14).** Several enum codec names were never used by a golden (`hook`, `device`, `failed`,
  `footer`), and neither were the rational error message, the `conflicts` rule kind, the
  `breakpoints.gen` dispatch and the `samples` reply key. Fix: round-trip guards over every
  constructor, plus "every listed stateless op is dispatched".

## Equivalent mutants (3, each backed by a checked fact)

- `Fw/Wire.lean` `samples`, 480:36 and 482:53 (both error keys emptied). Both error branches are dead
  for the fixed `sampleRequests`: a `#guard` checks that every sample parses and is answered without
  an error.
- `Fw/Ops/SpawnGuard.lean` `hasInfix`, 183:28 (`range (|s|+1)` to `range (|s|+2)`). The extra start
  position reads the same empty window as position `|s|` (theorem `infix_past_end`).

## Notes

- Two survivors were test fixtures that the docstrings specify (`exRoles`, `exInput`, `exLines`).
  They are pinned to their documented values, not treated as equivalent.
- Open (lead): `FwTestMain.lean` and the lakefile do not build `FwTest.Mutants.Kill`, so the killers
  only run in `mutants.sh` or `lake build FwTest.Mutants.Kill`. One import line in `FwTestMain.lean`
  (outside this task's writes) would make them part of `lake test`.
- Rerun:
  - all mutants: `lean/scripts/mutants.sh -j 3 -r <tag>`
  - one run's survivors: `-i .cache/mutants/<tag>/survivors.tsv`
  - beside a running run: `-b` gives the run its own baseline
