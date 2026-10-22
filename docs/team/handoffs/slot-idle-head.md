# slot-idle-head handoff

State: branch `worktree-wf_72ad8749-94c-1`; commits 6b83db0e (Lean, goldens, TS), 45feba2c (slot.md, ledger),
e4348288 (note); round 2 merged main fde0b15b (graph r217 adds slot-core.ts to the writes) in 9dba97eb, which
changed only work-graph.json, so checks were not re-run. Plain dry land: `VERDICT dry slot-idle-head`.

Verified:
- `lean/scripts/check.sh` green (axiom check 0 failing; sup-adapt golden equals the Lean output), heavy commands ran
  with `FW_SLOT_HELD=1` by lead exception.
- apps/runner: typecheck, vitest 85 files / 2400 tests; `node --test scripts/ci-paths.test.mjs` 54/54.

What changed:
- `lean/Fw/Sup/Adapt.lean`: `swapActive` (swap-out MB/min ≥ `Params.swapOutMBPerMinMax` 64) replaces swap
  occupancy in `memLow`; `VmMark` carries `swapCount`/`swapRate`; `idleHead` and `verdictWith`; `stallSample` is the
  2026-10-22 reading (281 MB available). Theorems: `idle_head_admitted`, `idle_head_only_when_empty`,
  `idle_head_at_most_one`, `verdict_unchanged_with_holder`, `admit_calm`, `idleHead_antitone`.
- `AdaptGolden.lean` -> `packages/contracts/golden/sup/adapt.jsonl`; `apps/runner/src/slot-core.ts` mirrors it
  (in the graph writes since r217); `slot.ts` reads `Swapouts` and treats an old vm-mark.json as a first reading.
- `docs/team/tools/slot.md` (Memory low, Idle head); ledger row `inc-slot-stall`.

Open:
- The 64 MB/min swap-out bound is an initial Params value; replay it on sampler data.
- The live queue was not re-run under the fix.
- thrash, floorMB and the availMB definition are unchanged (accepted limits).

Read first: `lean/Fw/Sup/Adapt.lean` from `idleHead` (line 525), then `docs/team/tools/slot.md` "Idle head".
