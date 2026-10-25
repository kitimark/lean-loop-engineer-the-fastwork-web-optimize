# fw-run-vms: `fw run --runs N` now reaches the WebKit Simulator lane as `vms`

Answer: the webkit dispatch of `fw run` now sends `vms` = `--runs` (2 or 3), the run count is part of the store key
(key version 3), and `--runs` above 3 with webkit is a request problem. `sessions` stays at its workflow default of 1.

## Before (CONFIRMED)
- `Fw.Store.Layout.dispatchInputs .webkit` sent only target, preset and fw, so webkit-sim fell back to
  `VMS: inputs.vms || ... || '1'` (`.github/workflows/webkit-sim.yml:198`). Every `fw run` WebKit dispatch ran 1 VM
  (work-graph title: runs 40134016822, 40134234199, 40139526492, 40139511311).
- The store key (`keyPairs`, version 2) had no run count, so a 1-VM run and a later 3-VM request on the same sha shared
  one key, and the plan reported a cache hit. The task premise "the key still separates 1-VM and 3-VM runs" did not
  hold, so the key changed too (below).

## Change (CONFIRMED, Lean)
- `dispatchInputs .webkit` = `[vms, target, preset, fw]`, with `vms = toString q.runs` (`lean/Fw/Store/Layout.lean:491`).
  Theorem `dispatch_vms` (`:500`), beside `dispatch_target`.
- Every webkit input name is declared: `dispatch_keys_declared` (`:578`) still holds, and a `#guard` checks the list
  against `Lane.webkitSim.inputs` (`:919`). The `vms` input exists (`webkit-sim.yml:16-19`), so the workflow is unchanged.
- webkit-sim accepts only 1 to 3 VMs (`Fw.Measure.SimPlan.problems`, `countOf 1 3`). `reqProblems` refuses webkit with
  more than `webkitMaxVms` = 3 runs (`Layout.lean:585`, `:612`); `reqProblems_nil_webkit_runs` (`:739`) proves that an
  accepted webkit request runs 2 or 3 times, and `webkit_vms_accepted` (`lean/Fw/Wire/Store.lean:242`) proves that the
  `vms` value sent passes SimPlan's own `countOf 1 3` and reads back as the run count.
- Key version 3 adds `("runs", toString r.runs)` (`Layout.lean:346`). `keyPairs_inj` still holds (`Nat.repr_injective`).
  `keyPairs_runs_ne` (`:369`) and `plan_key_runs_ne` (`:731`): two requests with different run counts never share a key.
  `keyPairs_ne_v2` (`:375`): no version 3 key equals a version 2 key, so no stored 1-VM run is a hit for a request now.
- The run count comes into the manifest in three places: `Manifest.runs` (checked ≥ 1), `Req.runs`, and for `fw ci` the shard count
  (`lean/Fw/Store/Ci.lean:210`, one chromium-counts shard per run). `fw run` reads it from the planned key
  (`apps/runner/src/run.ts:103`), so a manifest is filed under the key it was planned with.

## Sessions do not follow (INFERRED from the workflow text)
`sessions` is the repeat count inside one VM ("Sessions per VM", `webkit-sim.yml:20-23`). Chromium's `runs` counts
independent shards (one matrix job per run), and the WebKit counterpart is the independent VM ("Independent macOS VMs",
`:17`), not the session. The workflow says a push "runs 1 until 2 sessions pass on CI" (`:21`), so 2 sessions are not
proven yet. `fw run` sends no `sessions`, so `SESSIONS: inputs.sessions || '1'` (`:199`) applies. The key's sha pins
the workflow file, and with it that default.

## Checks (MEASURED, this Mac, no CI dispatch)
- `pnpm -s fw run --target rewrite --engines webkit --runs 3 --ref main --dry` printed
  `webkit   webkit-sim.yml  key 0e28b65f63e2  cache miss  inputs fw= preset=original target=rewrite vms=3  image runner:xcode-27`.
  `--runs 2` printed `vms=2` and key `d6cb4d32e9d1`; `--runs 4` printed `problem: runs: webkit-sim takes at most 3 VMs`.
- Store goldens regenerated (`lake env lean --run scripts/StoreGolden.lean`, 58 cases). New cases: plan with 2 runs
  (vms 2, both keys differ from the 3-run case), plan with 4 runs (problem), manifest with 2 runs (different key).
  `apps/runner/test/run-golden.test.ts` replays every plan and manifest case against fwcore.
- The live check is the next lead WebKit dispatch: its plan job should list 3 VM jobs (`v1..v3` or `r1..r3`).
