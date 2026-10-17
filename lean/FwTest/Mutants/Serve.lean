import Fw.Serve

/-! # Mutant killers for `Fw.Serve` (task m0-mutants)

Golden reply lines of the stateful serve loop (`Fw.Wire.Serve.serveLine`): the exact `console.reset`,
`console.apply` and `console.replay` replies (field names and values), and that a reset really empties
the state. They kill the surviving mutants of `cmdOf` (the `"console.reset"` op name) and `respFields`
(the `"outcome"` / `"reset"` keys and the `true` flag). -/

namespace FwTest.Mutants.Serve
open Lean Fw.Console Fw.Serve

/-- One stateful request line, `{"op":…,"id":…}` plus extra fields. -/
def line (op : String) (id : Nat) (extra : List (String × Json)) : String :=
  (Json.mkObj ([("op", Json.str op), ("id", toJson id)] ++ extra)).compress

/-- The `console.apply` line of the card-open event `a1` at time 1. -/
def openLine : String :=
  line "console.apply" 2 [("event", Fw.Wire.Serve.eventJson ⟨"a1", 1, .owner, .cardOpen "A" "o" false⟩)]

/-- The reply to `line` after the lines `pre` (each run against the state the previous one left). -/
def replyAfter (pre : List String) (l : String) : String :=
  (Fw.Wire.Serve.serveLine (pre.foldl (fun v p => (Fw.Wire.Serve.serveLine v p).1) init) l).2

#guard replyAfter [] (line "console.reset" 1 []) == "{\"id\":1,\"reset\":true}"
#guard replyAfter [] openLine ==
  "{\"changed\":{\"cards\":[{\"approved\":false,\"builders\":[],\"deviceAt\":null,\"head\":null,\"id\":\"A\"," ++
  "\"landReq\":null,\"landed\":false,\"lastAt\":1,\"needsDevice\":false,\"owner\":\"o\",\"reviewAt\":null," ++
  "\"reviewedBy\":null,\"screenAt\":null,\"violation\":false}],\"runs\":[],\"steps\":[]},\"id\":2," ++
  "\"outcome\":{\"accepted\":true,\"duplicate\":false}}"
#guard replyAfter [] (line "console.replay" 3 [("events", Json.arr #[Fw.Wire.Serve.eventJson
    ⟨"a1", 1, .owner, .cardOpen "A" "o" false⟩])]) == "{\"id\":3,\"replayed\":{\"accepted\":1,\"duplicate\":0,\"refused\":0}}"
-- a reset forgets the card and the seen key: the same event is accepted again, not a duplicate
#guard replyAfter [openLine, line "console.reset" 1 []] openLine == replyAfter [] openLine
#guard replyAfter [openLine, line "console.reset" 1 []] (line "console.query" 4 [("now", toJson 5), ("seq", toJson 0)])
  == replyAfter [] (line "console.query" 4 [("now", toJson 5), ("seq", toJson 0)])
#guard replyAfter [openLine] (line "console.query" 4 [("now", toJson 5), ("seq", toJson 0)])
  != replyAfter [] (line "console.query" 4 [("now", toJson 5), ("seq", toJson 0)])

end FwTest.Mutants.Serve
