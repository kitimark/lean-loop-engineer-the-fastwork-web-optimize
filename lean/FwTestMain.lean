import FwTest.Lease
import FwTest.Golden
import FwTest.Serve
import Fw.Measure.Golden
import Fw.Ops.Golden
import Fw.Wire.SchedGolden
import Fw.Plan.Golden
import Fw.Wire.GateGolden
import Fw.Store.Golden
import Fw.Obs.Golden
import FwTest.CiBudget
import FwTest.Mutants.Kill  -- m0-mutants killers: #guards and theorems that kill the M0 mutants

/-- `lake test`: pseudo-random lease traces, golden JSON-lines round trips, the `Rat` wire form,
and a replay timing for the console reducer. Exit code 0 only if everything passes.
`lake test -- --write-plan-golden` regenerates `packages/contracts/golden/plan/` first. -/
def main (args : List String) : IO UInt32 := do
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
  let obg ← Fw.Wire.Obs.Golden.run (← FwTest.Golden.root) false  -- watch-lean
  let stg ← Fw.Wire.Store.Golden.run' (← FwTest.Golden.root) false  -- store-and-run: packages/contracts/golden/store/
  -- ghb-lean: packages/contracts/golden/ci-budget/ (`-- --write-ci-budget-golden` regenerates), then the fixture replay
  if args.contains "--write-ci-budget-golden" then discard <| Fw.Wire.Ci.Golden.run (← FwTest.Golden.root) true
  let cbg := (← Fw.Wire.Ci.Golden.run (← FwTest.Golden.root) false) + (← FwTest.CiBudget.replay (← FwTest.Golden.root))
  -- replay timing (informational): 2,000 events through the reducer
  let evs : List Fw.Console.Event := (List.range 1000).flatMap fun i =>
    [⟨s!"o{i}", i, .owner, .cardOpen s!"c{i}" "o" false⟩, ⟨s!"a{i}", i, .lead, .cardApprove s!"c{i}"⟩]
  let t0 ← IO.monoNanosNow
  let s := Fw.Console.project evs
  let n := (s.cards.filter (·.approved)).length
  let t1 ← IO.monoNanosNow
  IO.println s!"console replay: 2000 events, {n} approved cards, {(t1 - t0) / 1000000} ms"
  let ok := leaseOk && a == 0 && w == 0 && r == 0 && sb == 0 && mg == 0 && og == 0 && sg == 0 && pg == 0 && gg == 0 && obg == 0 && stg == 0 && cbg == 0 && n == 1000
  IO.println (if ok then "fwtest: all passed" else "fwtest: FAILED")
  return if ok then 0 else 1
