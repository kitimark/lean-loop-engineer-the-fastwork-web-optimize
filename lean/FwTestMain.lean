import FwTest.Lease
import FwTest.Golden
import FwTest.Serve
import Fw.Measure.Golden
import Fw.Ops.Golden
import Fw.Wire.SchedGolden
import Fw.Plan.Golden
import Fw.Wire.GateGolden
import Fw.Gate.AlignEquiv
import Fw.Store.Golden
import Fw.Obs.Golden
import Fw.Ops.LedgerMerge
import Fw.Console.LedgerUnique
import FwTest.CiBudget
import Fw.Ci.Trigger
import Fw.Ci.Intent
import Fw.Ci.Dispatch
import FwTest.Mutants.Kill  -- m0-mutants killers: #guards and theorems that kill the M0 mutants

/-- `lake test`: pseudo-random lease traces, golden JSON-lines round trips, the `Rat` wire form,
and a replay timing for the console reducer. Exit code 0 only if everything passes.
`lake test -- --write-plan-golden` regenerates `packages/contracts/golden/plan/` first. -/
def FwTestMain.main (args : List String) : IO UInt32 := do
  let leaseOk ← FwTest.Lease.leaseProps
  let a ← FwTest.Golden.consoleApply
  let w ← FwTest.Golden.wire
  let r ← FwTest.Golden.ratRoundTrip
  let sb := (← FwTest.Serve.boardGolden) + (← FwTest.Serve.serveEquiv)
  FwTest.Serve.timing
  -- measure.* goldens: regenerated from Lean and compared with packages/contracts/golden/measure/ byte for byte
  let mg ← Fw.Wire.Measure.Golden.run (← FwTest.Golden.root) false
  -- ops.* goldens (lean-ops): packages/contracts/golden/ops/
  let og ← Fw.Wire.Ops.Golden.run (← FwTest.Golden.root) false
  -- ops.admit / metrics.* goldens (lean-wire-sched): packages/contracts/golden/ops/{admit,metrics}.jsonl
  let sg ← Fw.Wire.Sched.Golden.run (← FwTest.Golden.root) false
  -- plan goldens (lean-plan): packages/contracts/golden/plan/ (task.*, milestone.define, board plan)
  if args.contains "--write-plan-golden" then
    discard <| Fw.Wire.Plan.Golden.run (← FwTest.Golden.root) true
  let pg ← Fw.Wire.Plan.Golden.run (← FwTest.Golden.root) false
  -- gate.* goldens (verdict-to-lean): packages/contracts/golden/gate/, checked against the saved summaries
  let gg ← Fw.Wire.Gate.Golden.run (← FwTest.Golden.root) false
  let aeg ← Fw.Gate.AlignEquiv.run (← FwTest.Golden.root) false  -- gate-align-equiv: packages/contracts/golden/gate/align-equiv.jsonl
  let obg ← Fw.Wire.Obs.Golden.run (← FwTest.Golden.root) false  -- watch-lean
  let nxg ← Fw.Wire.Obs.NextGolden.run (← FwTest.Golden.root) false  -- obs-next-glue: packages/contracts/golden/obs/next.jsonl
  let sgn ← Fw.Wire.Obs.SignalsGolden.run (← FwTest.Golden.root) false  -- obs-signals: packages/contracts/golden/obs/signals.jsonl
  let stg ← Fw.Wire.Store.Golden.run' (← FwTest.Golden.root) false  -- store-and-run: packages/contracts/golden/store/
  -- ghb-lean: packages/contracts/golden/ci-budget/ (`-- --write-ci-budget-golden` regenerates), then the fixture replay
  if args.contains "--write-ci-budget-golden" then discard <| Fw.Wire.Ci.Golden.run (← FwTest.Golden.root) true
  let cbg := (← Fw.Wire.Ci.Golden.run (← FwTest.Golden.root) false) + (← FwTest.CiBudget.replay (← FwTest.Golden.root))
  -- ci-trigger-lean: packages/contracts/golden/ci/triggers.jsonl (`-- --write-ci-trigger-golden` regenerates)
  if args.contains "--write-ci-trigger-golden" then discard <| Fw.Ci.Trigger.runGolden (← FwTest.Golden.root) true
  -- ci-own-trigger: packages/contracts/golden/ci/intent.jsonl (the same flag regenerates it)
  if args.contains "--write-ci-trigger-golden" then discard <| Fw.Ci.Intent.runGolden (← FwTest.Golden.root) true
  -- fw-run-dispatch-pick: packages/contracts/golden/ci/dispatch.jsonl (the same flag regenerates it)
  if args.contains "--write-ci-trigger-golden" then discard <| Fw.Ci.Dispatch.runGolden (← FwTest.Golden.root) true
  let ctg := (← Fw.Ci.Trigger.runGolden (← FwTest.Golden.root) false) + (← Fw.Ci.Intent.runGolden (← FwTest.Golden.root) false) + (← Fw.Ci.Dispatch.runGolden (← FwTest.Golden.root) false)
  -- ledger-merge-driver: packages/contracts/golden/ops/ledger-merge.jsonl (`-- --write-ledger-merge-golden` regenerates)
  if args.contains "--write-ledger-merge-golden" then discard <| Fw.Wire.LedgerMerge.Golden.run (← FwTest.Golden.root) true
  let lmg ← Fw.Wire.LedgerMerge.Golden.run (← FwTest.Golden.root) false
  if args.contains "--write-ledger-unique-golden" then discard <| Fw.Wire.LedgerUnique.Golden.run (← FwTest.Golden.root) true
  let lug ← Fw.Wire.LedgerUnique.Golden.run (← FwTest.Golden.root) false
  -- replay timing (informational): 2,000 events through the reducer
  let evs : List Fw.Console.Event := (List.range 1000).flatMap fun i =>
    [⟨s!"o{i}", i, .owner, .cardOpen s!"c{i}" "o" false⟩, ⟨s!"a{i}", i, .lead, .cardApprove s!"c{i}"⟩]
  let t0 ← IO.monoNanosNow
  let s := Fw.Console.project evs
  let n := (s.cards.filter (·.approved)).length
  let t1 ← IO.monoNanosNow
  IO.println s!"console replay: 2000 events, {n} approved cards, {(t1 - t0) / 1000000} ms"
  let ok := leaseOk && a == 0 && w == 0 && r == 0 && sb == 0 && mg == 0 && og == 0 && sg == 0 && pg == 0 && gg == 0 && aeg == 0 && obg == 0 && nxg == 0 && sgn == 0 && stg == 0 && cbg == 0 && ctg == 0 && lmg == 0 && lug == 0 && n == 1000
  IO.println (if ok then "fwtest: all passed" else "fwtest: FAILED")
  return if ok then 0 else 1
