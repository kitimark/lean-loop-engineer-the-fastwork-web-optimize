import Fw.Console.LandSpeed

def main (args : List String) : IO UInt32 := do
  match args with
  | ["--write"] => Fw.Console.LandSpeed.writeAll; return 0
  | ["--check"] => return if (← Fw.Console.LandSpeed.checkGolden) then 0 else 1
  | _ => IO.eprintln "usage: LandReadsGen (--write | --check)"; return 2
