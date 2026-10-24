import Lean.Data.Json
import Fw.Parts.CommissionOpt
import Fw.Parts.CommissionGolden
/-!
Golden vectors for commission:band-gate (`commission-gate.jsonl`).
-/
namespace Fw.Parts.CommissionOptGolden
open Lean Fw.Parts.Commission Fw.Parts.CommissionOpt Fw.Parts.CommissionGolden Fw.Site.Breakpoints

def jn (n : Int) : Json := .num ⟨n, 0⟩

def evJson (e : Ev) : Json :=
  Json.mkObj [("gate", .bool e.gate), ("rm", .bool e.rm), ("top", rin e.top), ("bottom", rin e.bottom), ("vh", rin e.vh)]

def pairWire (p : Rat × Rat) : Json := Json.mkObj [("enter", ratWire p.1), ("shrink", ratWire p.2)]

def traces : List (List Ev) :=
  let e (g : Bool) (t b : Rat) : Ev := ⟨g, false, t, b, 1000⟩
  [[e true 5000 6000, e true 250 1400, e true 0 850, e true 0 600, e true 0 400, e true 0 350, e true 0 340],
   [e true 0 850, e true 0 600, e false 0 600, e false 0 500, e false 0 500],
   [e false 0 850, e false 0 600, e true 0 500, e true 0 400, e false 0 400, e true 0 400],
   [({ e true 0 600 with rm := true }), ({ e false 0 600 with rm := true }), ({ e false 0 900 with rm := true })]]

def traceLine (tr : List Ev) : String :=
  let ev : Nat → Ev := fun k => tr.getD k ⟨true, false, 0, 0, 1000⟩
  line "trace" [("events", Json.arr (tr.map evJson).toArray)]
    (Json.mkObj
      [("variantInl", Json.arr ((List.range tr.length).map fun k => pairWire (stV ev (k + 1)).inl).toArray),
       ("variantWrites", Json.arr ((List.range tr.length).map fun k => jn (stV ev (k + 1)).writes).toArray),
       ("origInl", Json.arr ((List.range tr.length).map fun k => pairWire (stO ev (k + 1)).inl).toArray),
       ("origWrites", Json.arr ((List.range tr.length).map fun k => jn (stO ev (k + 1)).writes).toArray)])

def lookWire (l : Rat × Rat) : Json := Json.mkObj [("scale", ratWire l.1), ("radius", ratWire l.2)]

def tickJson (t : Tick × Bool) : Json :=
  Json.mkObj [("media", match t.1.media with | some g => .bool g | none => .null),
    ("body", match t.1.body with | some e => evJson e | none => .null), ("c1000", .bool t.2)]

def merged : List (List (Tick × Bool)) :=
  let b (g : Bool) (bot : Rat) : Option Ev := some ⟨g, false, 0, bot, 1000⟩
  [[(⟨none, b true 850⟩, true), (⟨none, b true 600⟩, true), (⟨some false, none⟩, false)],
   [(⟨none, b true 850⟩, true), (⟨none, b true 600⟩, true), (⟨some false, b false 600⟩, false),
    (⟨none, b false 500⟩, false)],
   [(⟨none, b true 850⟩, true), (⟨none, b true 600⟩, true), (⟨none, b false 600⟩, false),
    (⟨some false, none⟩, false), (⟨none, none⟩, false)],
   [(⟨none, b false 850⟩, false), (⟨some true, none⟩, true), (⟨none, b true 600⟩, true),
    (⟨none, b true 500⟩, true), (⟨none, none⟩, true)],
   [(⟨none, b true 850⟩, true), (⟨none, b true 600⟩, true), (⟨none, none⟩, false)]]

def mergedLine (tr : List (Tick × Bool)) : String :=
  let ts : Nat → Tick := fun k => (tr.getD k (⟨none, none⟩, false)).1
  let env (k : Nat) : Env := if (tr.getD k (⟨none, none⟩, false)).2 then exEnv 430 430 else exEnv 1280 1280
  let ks := List.range tr.length
  line "mergedTrace" [("ticks", Json.arr (tr.map tickJson).toArray)]
    (Json.mkObj
      [("variantInl", Json.arr (ks.map fun k => pairWire (mV ts (k + 1)).inl).toArray),
       ("variantWrites", Json.arr (ks.map fun k => jn (mV ts (k + 1)).writes).toArray),
       ("origInl", Json.arr (ks.map fun k => pairWire (mO ts (k + 1)).inl).toArray),
       ("origWrites", Json.arr (ks.map fun k => jn (mO ts (k + 1)).writes).toArray),
       ("variantLook", Json.arr (ks.map fun k => lookWire (look (env k) (mV ts (k + 1)).inl)).toArray),
       ("origLook", Json.arr (ks.map fun k => lookWire (look (env k) (mO ts (k + 1)).inl)).toArray)])

def gateLines (_ : Unit := ()) : List String :=
  (([false, true] : List Bool).flatMap fun g => ([false, true] : List Bool).map fun m =>
    line "planWrite" [("gated", .bool g), ("moving", .bool m)] (.bool (writeNow g m))) ++
  (([false, true] : List Bool).map fun g => line "planCatchup" [("gated", .bool g)] (.bool (catchupNow g))) ++
  (([(1, 0), (0, 0), (1/2, 1/4), (1/4, 1/2), (0, 1)] : List (Rat × Rat)).map fun p =>
    line "catchupPair" [("n", rin p.1), ("r", rin p.2)]
      (pairWire (stepC false ⟨⟨p.1, p.2⟩, (0, 0), 0, (false, false)⟩).inl)) ++
  (([(430, 430, true, false), (500, 500, false, false), (800, 800, false, false), (1000, 1000, false, false),
     (1001, 1001, false, false), (1001, 500, false, false), (1001, 501, false, false), (1200, 1200, true, true),
     (1201, 1201, true, true), (1280, 1280, false, false), (1280, 400, false, false)] :
      List (Nat × Nat × Bool × Bool)).flatMap fun (w, d, noHover, coarse) =>
    let env := exEnv w d (if noHover then .none else .hover) (if coarse then .coarse else .fine)
    (([(1, 1), (0, 0), (1, 0), (0, 1), (1/2, 1/4)] : List (Rat × Rat))).map fun p =>
      line "cardLook" [("width", jn w), ("deviceWidth", jn d), ("c1000", .bool (c1000.eval env)),
        ("enter", rin p.1), ("shrink", rin p.2)]
        (Json.mkObj [("scale", ratWire (look env p).1), ("radius", ratWire (look env p).2)])) ++
  traces.map traceLine ++
  merged.map mergedLine

def files (_ : Unit := ()) : List (String × List String) := [("commission-gate.jsonl", gateLines ())]

end Fw.Parts.CommissionOptGolden
