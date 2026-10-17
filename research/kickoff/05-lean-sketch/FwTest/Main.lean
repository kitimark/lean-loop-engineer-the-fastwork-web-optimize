import FwTest.Lease

def main : IO UInt32 := do
  let ok ← leaseProps
  -- wire round-trip: what the TS shell sends
  let out := Fw.Wire.handleLine "{\"op\":\"verdict\",\"dir\":\"lower\",\"ctl\":[5,6,7],\"var\":[1,2,3]}"
  IO.println out
  return if ok && out == "{\"verdict\":\"better\"}" then 0 else 1
