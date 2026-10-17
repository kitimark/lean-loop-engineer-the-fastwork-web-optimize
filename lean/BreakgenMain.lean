import Fw.Site.BreakpointGen
import Fw.Gate.SweepsGen

/-- `lake exe breakgen [--inventory <breakpoints.json>] [--check <file>]`: print `breakpoints.gen.json` to
stdout, or with `--check` fail (exit 1) when the file differs byte for byte; `--inventory` also checks the
catalogue and the matrix against the inventory. All logic is in `Fw.Site.BreakpointGen.run`.
`lake exe breakgen --sweeps [--check <file>]` and `--sweeps-golden [--check <file>]` print or check
`sweeps.gen.json` and `golden/gate/sweeps.jsonl` instead (`Fw.Gate.SweepsGen.run`). -/
def main (args : List String) : IO UInt32 :=
  if args.contains "--sweeps" || args.contains "--sweeps-golden" then Fw.Gate.SweepsGen.run args
  else Fw.Site.BreakpointGen.run args
