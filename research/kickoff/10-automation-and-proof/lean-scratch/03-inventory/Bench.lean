import Auto
open Lean Auto.Console

/-- Stateful console brain: the state lives in the process; every line is one event; the reply
is the acceptance bit and the derived projection when asked. State = fold of the lines read. -/
partial def loop (r : IO.Ref State) (stdin stdout : IO.FS.Stream) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return
  let t := line.trimAscii.toString
  let out : String ←
    if t == "?" then pure s!"\{\"needsYou\":{needsYou (← r.get)}}"
    else match Json.parse t >>= fromJson? (α := Event) with
      | .ok e => do
        -- modifyGet keeps the state uniquely referenced, so HashMap.insert updates in place
        let ok ← r.modifyGet fun s => let (s', ok) := apply s e; (ok, s')
        pure s!"\{\"eid\":{e.eid},\"ok\":{ok}}"
      | .error err => pure (Json.mkObj [("error", Json.str err)]).compress
  stdout.putStrLn out
  stdout.flush
  loop r stdin stdout

def main : IO Unit := do
  let r ← IO.mkRef ({} : State)
  loop r (← IO.getStdin) (← IO.getStdout)
