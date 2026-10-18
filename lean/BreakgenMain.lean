import Fw.Site.BreakpointGen
import Fw.Gate.SweepsGen
import Fw.Gate.ScopeGen

/-- `lake exe breakgen [--inventory <breakpoints.json>] [--check <file>]`: print `breakpoints.gen.json` to
stdout, or with `--check` fail (exit 1) when the file differs byte for byte; `--inventory` also checks the
catalogue and the matrix against the inventory. All logic is in `Fw.Site.BreakpointGen.run`.
`lake exe breakgen --sweeps [--check <file>]` and `--sweeps-golden [--check <file>]` print or check
`sweeps.gen.json` and `golden/gate/sweeps.jsonl` instead (`Fw.Gate.SweepsGen.run`).
`lake exe breakgen --scope [--check <file>]` prints or checks the gate's `scope.gen.json` (`Fw.Gate.ScopeGen.run`): the
compiled binary replaces the interpreted `lean --run` driver of `packages/gate-breakpoints/scripts/scopegen.mjs`
(100 s under load). -/
def main (args : List String) : IO UInt32 :=
  if args.contains "--scope" then Fw.Gate.ScopeGen.run (args.filter (· != "--scope"))
  else if args.contains "--sweeps" || args.contains "--sweeps-golden" then Fw.Gate.SweepsGen.run args
  else Fw.Site.BreakpointGen.run args
