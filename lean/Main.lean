import Fw.Serve
/-!
# `fwcore`: JSON lines over stdin/stdout

Reads one request per line and writes exactly one reply line per input line, in order, flushing
after each (a blank line gets an error reply too). Stops at end of input. The session is stateful
(`console.apply` with one event, `console.replay`, `console.query`, `console.reset`; PLAN §3.2):
the loop is `Fw.Wire.Serve.loop` (one `modifyGet` per line), every decision is pure
(`Fw.Wire.Serve.serveLine`, `Fw.Wire.handleLine`); this file only picks the mode. Spawn it with `LEAN_ABORT_ON_PANIC=1`
(see `README.md`): without it a Lean panic returns a default value instead of exiting.
-/

/-- Entry point: `fwcore` or `fwcore serve` serves JSON lines (stateful); `fwcore --ops` lists the ops. -/
def main (args : List String) : IO UInt32 := do
  if args == ["--ops"] then
    IO.println (", ".intercalate Fw.Wire.ops)
    return 0
  Fw.Wire.Serve.main (← IO.getStdin) (← IO.getStdout)
  return 0
