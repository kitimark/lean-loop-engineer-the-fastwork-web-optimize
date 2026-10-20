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

MEASURED
- Historical `fwcore build (phase 1)` spans (.fw-console/timings.jsonl): 114 rows, 92 on lands whose diff touches lean/** or the script, 1069 s total
  (mean 11.6 s, range 0.6 to 110 s under load). Only 2 of 92 were build-free-only (1.7 s together): the rule saves about 0.9 s on such a land.
- Now, warm tree, build-free-only change: `sh scripts/fwcore-build.sh` 0.63 s before, span absent after. Trailing comment in a leaf module: 2.2 s
  (Lake artifact cache); a real code change in a module costs the 14 to 110 s above and still builds. Non-Lean lands: no phase-1 span before or after.
- `fw land --dry` does not run phase 1 (only cheap stages); no scratch land was done, spans come from history and the script run.

Finding: the lead's idea (skip when every check is remote) does not hold: phase 1 yields the digest, and three local fwcore users (difftest,
measure-webkit, measure-wktr) are selected whenever the digest moves, so the build is needed anyway (and is not duplicated: built=true is passed on).
The closure of Fw covers 280 of 290 modules plus FwTest, so no Lean module change can skip. The remaining lever is moving those 3 users remote, or
caching by lean-input tree hash, which gains only the 0.6 s Lake already gives.

Open: none for the unit. lean/scripts/check.sh green at the last Lean change; runner `pnpm test` 1641 passed; ci-paths 49 pass.
Writes outside the graph list: none.
