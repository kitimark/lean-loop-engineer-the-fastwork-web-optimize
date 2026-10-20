# land-phase1-slow handoff

State: branch worktree-wf_02570387-b4e-2. Lean rule + TS + golden + test + docs/team/tools/land.md section committed.

What changed
- lean/Fw/Console/LandTier.lean: `buildFree`, `binaryChange`, `phase1Build`, `selectBin`; theorems `phase1Build_iff`, `phase1Build_of_input`,
  `skip_binMoved`, `skip_selection`, `built_selection`, `skip_binary_equal` (premise `BinaryOfInputs`), `skip_keeps_local_build`.
- packages/contracts/golden/console/land-phase1.jsonl (generated; `lake env lean --run scripts/LandTierGolden.lean`).
- apps/runner/src/land.ts: `BUILD_FREE`, `binaryChange`, `phase1Build`, `selectBin` (TS stand-ins checked against the golden); `twoPhaseChecks`
  uses them; `checksWithReads` takes a `select` argument. Remote lane, `selectTwoPhase`, `fw checks`, post-land build unchanged.
- apps/runner/test/land-phase1.test.ts: golden vectors + import closure of the lakefile roots has no build-free file + no include_str into one.

Phase-1 uses of the local fwcore build (land.ts, before): build span :636 (only for a change in FWCORE_BUILD_READS); digest d1 :638 -> selection
`checksWithReads` :640 (binMoved); `built: phase1Built` :658 -> `localPlan` (land-remote.ts:326) builds again only if false. The land's own fwcore
calls (render guard :498, scope/behind, checkmap, regen) use `fwcoreCall(mainDir)`, the main checkout's binary, never the merge tree's build.

MEASURED (before) / INFERRED (after)
- Recount of .fw-console/timings.jsonl (115 phase-1 rows; each row's main commit mapped to the land merge whose first parent it is): 110 rows touch lean/**
  or scripts/fwcore-build.sh, 1395 s in total; the build-free-only rows are one land (2 attempts, 0.5 s and 1.2 s).
- Build-free-only change: `sh scripts/fwcore-build.sh` 0.63 s MEASURED (direct script run, not an fw land span); span absent after is INFERRED (code identity plus
  golden build=false). Trailing comment in a leaf module: 2.2 s MEASURED (direct script run; Lake artifact cache); a real code change costs 14 to 110 s and still builds.
- `fw land --dry` does not reach phase 1 (land.ts:534-557) and no checks-only land mode exists, so no after span was measured.

Finding: the lead's idea (skip when every check is remote) does not hold: phase 1 yields the digest, and three local fwcore users (difftest,
measure-webkit, measure-wktr) are selected whenever the digest moves, so the build is needed anyway (and is not duplicated: built=true is passed on).
The closure of Fw covers 280 of 290 modules plus FwTest, so no Lean module change can skip. The remaining lever is moving those 3 users remote, or
caching by lean-input tree hash, which gains only the 0.6 s Lake already gives.

Open: none for the unit. lean/scripts/check.sh green at the last Lean change; runner `pnpm test` 1641 passed; ci-paths 49 pass.
Follow-ups: read the 'fwcore build (phase 1)' span of this land and of the next build-free-only land from .fw-console/timings.jsonl; model phase1Built in Lean (skip_keeps_local_build does not mention phase1Build today); accept 'meta'/'private' import prefixes in the land-phase1.test.ts closure regex.
Writes outside the graph list: none.
