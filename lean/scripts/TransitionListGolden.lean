import Fw.Gate.TransitionList

def main (args : List String) : IO UInt32 := do
  let bad ← Fw.Gate.TransitionList.run "." (!args.contains "--check")
  return if bad == 0 then 0 else 1
