import Lean.Data.Json
import Fw.Parts.CommissionOpt
import Fw.Parts.CommissionGolden
/-!
# Golden vectors for commission:band-gate

`CommissionOptGolden.files` is the content of `packages/contracts/golden/parts/commission-gate.jsonl` (same line format and
encodings as `Fw/Parts/CommissionGolden.lean`). `logic.ts` (`planWrite`, `cardLook`) and `driver.test.ts` (the traces) are
checked against it.
-/
namespace Fw.Parts.CommissionOptGolden
open Lean Fw.Parts.Commission Fw.Parts.CommissionOpt Fw.Parts.CommissionGolden Fw.Site.Breakpoints

/-- A natural number as a JSON integer. -/
def jn (n : Int) : Json := .num ⟨n, 0⟩

/-- Event as JSON (inputs). -/
def evJson (e : Ev) : Json :=
  Json.mkObj [("gate", .bool e.gate), ("rm", .bool e.rm), ("top", rin e.top), ("bottom", rin e.bottom), ("vh", rin e.vh)]

/-- A pair as JSON. -/
def pairWire (p : Rat × Rat) : Json := Json.mkObj [("enter", ratWire p.1), ("shrink", ratWire p.2)]

/-- Traces: a platform scroll-in inside the band, then a band exit and a band entry. Each line gives, after every event,
the inline pair and the write count of both arms. -/
def traces : List (List Ev) :=
  let e (g : Bool) (t b : Rat) : Ev := ⟨g, false, t, b, 1000⟩
  [[e true 5000 6000, e true 250 1400, e true 0 850, e true 0 600, e true 0 400, e true 0 350, e true 0 340],
   [e true 0 850, e true 0 600, e false 0 600, e false 0 500, e false 0 500],
   [e false 0 850, e false 0 600, e true 0 500, e true 0 400, e false 0 400, e true 0 400],
   [({ e true 0 600 with rm := true }), ({ e false 0 600 with rm := true }), ({ e false 0 900 with rm := true })]]

/-- The state after each of the events of a trace, for both arms. -/
def traceLine (tr : List Ev) : String :=
  let ev : Nat → Ev := fun k => tr.getD k ⟨true, false, 0, 0, 1000⟩
  line "trace" [("events", Json.arr (tr.map evJson).toArray)]
    (Json.mkObj
      [("variantInl", Json.arr ((List.range tr.length).map fun k => pairWire (stV ev (k + 1)).inl).toArray),
       ("variantWrites", Json.arr ((List.range tr.length).map fun k => jn (stV ev (k + 1)).writes).toArray),
       ("origInl", Json.arr ((List.range tr.length).map fun k => pairWire (stO ev (k + 1)).inl).toArray),
       ("origWrites", Json.arr ((List.range tr.length).map fun k => jn (stO ev (k + 1)).writes).toArray)])

/-- Lines of `commission-gate.jsonl`: the write decision, the card's look per environment (the boolean `c1000` is Lean's
evaluation of the generated condition at that environment) and inline pair, and the traces. -/
def gateLines : List String :=
  (([false, true] : List Bool).map fun g => line "planWrite" [("gated", .bool g)] (.bool (writeNow g))) ++
  (([(430, 430, true, false), (500, 500, false, false), (800, 800, false, false), (1000, 1000, false, false),
     (1001, 1001, false, false), (1001, 500, false, false), (1001, 501, false, false), (1200, 1200, true, true),
     (1201, 1201, true, true), (1280, 1280, false, false), (1280, 400, false, false)] :
      List (Nat × Nat × Bool × Bool)).flatMap fun (w, d, noHover, coarse) =>
    let env := exEnv w d (if noHover then .none else .hover) (if coarse then .coarse else .fine)
    (([(1, 1), (0, 0), (1, 0), (0, 1), (1/2, 1/4)] : List (Rat × Rat))).map fun p =>
      line "cardLook" [("width", jn w), ("deviceWidth", jn d), ("c1000", .bool (c1000.eval env)),
        ("enter", rin p.1), ("shrink", rin p.2)]
        (Json.mkObj [("scale", ratWire (look env p).1), ("radius", ratWire (look env p).2)])) ++
  traces.map traceLine

/-- The golden files of commission:band-gate: name and lines. -/
def files (_ : Unit := ()) : List (String × List String) := [("commission-gate.jsonl", gateLines)]

end Fw.Parts.CommissionOptGolden
