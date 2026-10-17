import Fw.Wire
/-!
# `fwcore`: JSON lines over stdin/stdout

Reads one request per line and writes exactly one reply line per input line, in order, flushing
after each (a blank line gets an error reply too). Stops at end of input. All decisions are in
`Fw.Wire.handleLine` (pure); this file only moves bytes. Spawn it with `LEAN_ABORT_ON_PANIC=1`
(see `README.md`): without it a Lean panic returns a default value instead of exiting.
-/

/-- Serve until end of input. -/
partial def serve (stdin stdout : IO.FS.Stream) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return            -- end of input (a blank line is "\n", not "")
  stdout.putStrLn (Fw.Wire.handleLine line)
  stdout.flush
  serve stdin stdout

/-- Entry point: `fwcore` (no arguments) serves JSON lines; `fwcore --ops` lists the ops. -/
def main (args : List String) : IO UInt32 := do
  if args == ["--ops"] then
    IO.println (", ".intercalate Fw.Wire.ops)
    return 0
  serve (← IO.getStdin) (← IO.getStdout)
  return 0
