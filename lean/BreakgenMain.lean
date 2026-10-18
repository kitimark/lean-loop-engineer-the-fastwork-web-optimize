import Fw.Site.BreakpointGen
import Fw.Site.GenRoute

/-- `lake exe breakgen [--inventory <breakpoints.json>] [--check <file>]`: print `breakpoints.gen.json` to
stdout, or with `--check` fail (exit 1) when the file differs byte for byte; `--inventory` also checks the
catalogue and the matrix against the inventory. All logic is in `Fw.Site.BreakpointGen.run`.
The site build runs this binary, so it imports only the breakpoint generator (task `site-build-cache`): the gate
generators (`--sweeps`, `--sweeps-golden`, `--scope`) moved to `lake exe sweepsgen` (`SweepsgenMain.lean`), and a
gate flag here exits 2 with that pointer (`Fw.Site.GenRoute.breakgenRoute`; `split_agrees` proves the split keeps
every old route). -/
def main (args : List String) : IO UInt32 :=
  match Fw.Site.GenRoute.breakgenRoute args with
  | some g => Fw.Site.BreakpointGen.run (Fw.Site.GenRoute.argsFor g args)
  | none => do
    IO.eprintln "breakgen: --sweeps, --sweeps-golden and --scope moved to `lake exe sweepsgen` (same flags)"
    return 2
