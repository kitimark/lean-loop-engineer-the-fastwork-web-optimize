import FwTest.Lease
import FwTest.Golden

/-- `lake test`: pseudo-random lease traces, golden JSON-lines round trips, the `Rat` wire form,
and a replay timing for the console reducer. Exit code 0 only if everything passes. -/
def main : IO UInt32 := do
  let leaseOk ← FwTest.Lease.leaseProps
  let a ← FwTest.Golden.consoleApply
  let w ← FwTest.Golden.wire
  let r ← FwTest.Golden.ratRoundTrip
  -- replay timing (informational): 2,000 events through the reducer
  let evs : List Fw.Console.Event := (List.range 1000).flatMap fun i =>
    [⟨s!"o{i}", i, .owner, .cardOpen s!"c{i}" "o" false⟩, ⟨s!"a{i}", i, .lead, .cardApprove s!"c{i}"⟩]
  let t0 ← IO.monoNanosNow
  let s := Fw.Console.project evs
  let n := (s.cards.filter (·.approved)).length
  let t1 ← IO.monoNanosNow
  IO.println s!"console replay: 2000 events, {n} approved cards, {(t1 - t0) / 1000000} ms"
  let ok := leaseOk && a == 0 && w == 0 && r == 0 && n == 1000
  IO.println (if ok then "fwtest: all passed" else "fwtest: FAILED")
  return if ok then 0 else 1
