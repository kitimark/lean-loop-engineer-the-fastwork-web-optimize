import Fw

partial def loop (stdin : IO.FS.Stream) (stdout : IO.FS.Stream) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return            -- EOF
  let t := line.trimAscii.toString
  unless t.isEmpty do
    stdout.putStrLn (Fw.Wire.handleLine t)
    stdout.flush
  loop stdin stdout

def main : IO Unit := do
  loop (← IO.getStdin) (← IO.getStdout)
