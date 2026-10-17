import Fw.Site.BreakpointGen

/-- `lake exe breakgen [--inventory <breakpoints.json>] [--check <file>]`: print `breakpoints.gen.json` to
stdout, or with `--check` fail (exit 1) when the file differs byte for byte; `--inventory` also checks the
catalogue and the matrix against the inventory. All logic is in `Fw.Site.BreakpointGen.run`. -/
def main (args : List String) : IO UInt32 := Fw.Site.BreakpointGen.run args
