import Lean.Data.Json
import Fw.Parts.CommissionOpt
import Fw.Parts.CommissionGolden
import Fw.Parts.CommissionOptWindow
/-!
Golden vectors for commission:band-gate (`commission-gate.jsonl`).
-/
namespace Fw.Parts.CommissionOptGolden
open Lean Fw.Parts.Commission Fw.Parts.CommissionOpt Fw.Parts.CommissionGolden Fw.Site.Breakpoints
open Fw.Parts.CommissionOptLayout Fw.Parts.CommissionOptWindow

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

def rowWidth (r : Row) : Rat := (r.width : Rat) + (if r.widthHalf then 1 / 2 else 0)

def touchOf (r : Row) : Bool := r.hover == .none && r.pointer == .coarse

def rowBottom (r : Row) : Rat := r.sectionTop + r.sectionH

def layoutLine (r : Row) : String :=
  let b := rowBands r
  line "layoutRow"
    [("id", .str r.id), ("width", ratWire (rowWidth r)), ("deviceWidth", jn r.deviceWidth), ("touch", .bool (touchOf r)),
     ("cardTop", ratWire r.cardTop), ("bottom", ratWire (rowBottom r)), ("vh", jn r.height)]
    (Json.mkObj
      [("compact", .bool (c1000.eval r.env)), ("enterFrom", ratWire b.1), ("enterTo", ratWire b.2.1),
       ("exitFrom", ratWire b.2.2.1), ("exitTo", ratWire b.2.2.2)])

def bandSamples (b : Rat × Rat × Rat × Rat) : List Rat :=
  [b.1 - 1, b.1, b.1 + 1, (b.1 + b.2.1) / 2, b.2.1 - 1, b.2.1, b.2.1 + 1, b.2.2.1 - 1, b.2.2.1, b.2.2.1 + 1,
   (b.2.2.1 + b.2.2.2) / 2, b.2.2.2 - 1, b.2.2.2, b.2.2.2 + 1]

def sampleRows : List String := ["height-probes-430x775", "dark-430x932", "desk-1280", "touch-1200"]

def inBandLines : List String :=
  (rows.filter fun r => sampleRows.contains r.id).flatMap fun r =>
    (bandSamples (rowBands r)).map fun y =>
      line "inBand"
        [("cardTop", ratWire r.cardTop), ("bottom", ratWire (rowBottom r)), ("vh", jn r.height), ("y", ratWire y)]
        (.bool (decide (inBand r.cardTop (rowBottom r) r.height y)))

def scrollRows : List String := ["height-probes-430x775", "dark-430x932"]

def scrollYs (r : Row) : List Rat :=
  let lo : Nat := ((enterFrom r.cardTop r.height - 400) / 50).floor.toNat * 50
  let hi : Nat := (rowBottom r + r.height - 100).floor.toNat
  (List.range ((hi - lo) / 50 + 1)).flatMap fun i => let y : Rat := (lo + 50 * i : Nat); [y, y]

def scrollLine (r : Row) : String :=
  let ys := scrollYs r
  let ev : Nat → Ev := scrollEv r.cardTop (rowBottom r) r.height fun k => ys.getD k 0
  let ks := List.range ys.length
  let skipped (k : Nat) : Bool := !writeNow (ev k).gate ((ev k).frame (stO ev k)).more
  line "scrollTrace"
    [("cardTop", ratWire r.cardTop), ("bottom", ratWire (rowBottom r)), ("vh", jn r.height),
     ("ys", Json.arr (ys.map ratWire).toArray)]
    (Json.mkObj
      [("variantWrites", Json.arr (ks.map fun k => jn (stV ev (k + 1)).writes).toArray),
       ("origWrites", Json.arr (ks.map fun k => jn (stO ev (k + 1)).writes).toArray),
       ("skipped", Json.arr (ks.map fun k => Json.bool (skipped k)).toArray),
       ("band", Json.arr (ks.map fun k => Json.bool (decide (inBand r.cardTop (rowBottom r) r.height (ys.getD k 0)))).toArray)])

def settleLine : String := line "settleEvents" [] (jn 29)

def windowLines (_ : Unit := ()) : List String :=
  [settleLine] ++ rows.map layoutLine ++ inBandLines ++ (rows.filter fun r => scrollRows.contains r.id).map scrollLine

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
  merged.map mergedLine ++ windowLines ()

def files (_ : Unit := ()) : List (String × List String) := [("commission-gate.jsonl", gateLines ())]

end Fw.Parts.CommissionOptGolden
