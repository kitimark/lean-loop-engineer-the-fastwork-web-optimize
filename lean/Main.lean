import Fw.Serve
import Fw.Ops.FwCoreRoute
import FwTestMain
import SweepsgenMain
import Fw.Parts.Golden
/-!
# `fwcore`: JSON lines over stdin/stdout, and the former Lean executables as subcommands

Reads one request per line and writes exactly one reply line per input line, in order, flushing
after each (a blank line gets an error reply too). Stops at end of input. The session is stateful
(`console.apply` with one event, `console.replay`, `console.query`, `console.reset`; PLAN §3.2):
the loop is `Fw.Wire.Serve.loop` (one `modifyGet` per line), every decision is pure
(`Fw.Wire.Serve.serveLine`, `Fw.Wire.handleLine`); this file only picks the mode. Spawn it with `LEAN_ABORT_ON_PANIC=1`
(see `README.md`): without it a Lean panic returns a default value instead of exiting.
`fwcore fwtest|sweepsgen|partsgolden <args>` runs that former executable's entry point (`Fw.Ops.FwCoreRoute`).
-/

/-- Entry point: `fwcore` or `fwcore serve` serves JSON lines (stateful); `fwcore --ops` lists the ops;
`fwcore <sub> <args>` runs the former executable `<sub>` on `<args>` (`Fw.Ops.FwCoreRoute.route`). -/
def main (args : List String) : IO UInt32 := do
  match Fw.Ops.FwCoreRoute.route args with
  | (.fwtest, a) => FwTestMain.main a
  | (.sweepsgen, a) => SweepsgenMain.main a
  | (.partsgolden, a) => do Fw.Parts.Golden.main a; return 0
  | (.ops, _) => do
    IO.println (", ".intercalate (Fw.Wire.ops ++ Fw.Wire.Plan.ops))
    return 0
  | (.serve, _) => do
    Fw.Wire.Serve.main (← IO.getStdin) (← IO.getStdout)
    return 0
