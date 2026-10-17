import Lean.Data.Json
import Fw.Parts.Commission
import Fw.Parts.CommissionTyping
/-!
# Golden vectors for commission and commission.typing

`CommissionGolden.commissionLines` is the content of `packages/contracts/golden/parts/commission.jsonl`,
`CommissionGolden.typingLines` that of `commission.typing.jsonl` (same line format and encodings as `Fw/Parts/Golden.lean`:
`Rat` inputs as exact JSON decimals, `Rat` outputs as `{"num","den"}`). `Golden.lean` writes both files.
-/
namespace Fw.Parts.CommissionGolden
open Lean Fw.Parts.Commission Fw.Parts.CommissionTyping

/-- A rational input as an exact JSON decimal (denominators here divide $1000$).

$$q \mapsto q \cdot 10^3 \cdot 10^{-3}$$ -/
def rin (q : Rat) : Json := .num ⟨q.num * ((1000 / q.den : Nat) : Int), 3⟩

/-- The `Rat` output wire form. $$q \mapsto \{\mathrm{num}, \mathrm{den}\}$$ -/
def ratWire (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- One golden line. $$(\mathit{fn}, \mathit{in}, \mathit{out}) \mapsto \text{JSON line}$$ -/
def line (fn : String) (inp : List (String × Json)) (out : Json) : String :=
  (Json.mkObj [("fn", .str fn), ("in", Json.mkObj inp), ("out", out)]).compress

/-- Booleans. $$\mathbb B$$ -/
def bs : List Bool := [false, true]

/-- An optional rational (`none` is JSON null). $$\mathrm{Option}\ \mathbb Q \to \mathrm{JSON}$$ -/
def optIn (q : Option Rat) : Json := match q with | some x => rin x | none => .null

/-- An optional rational output. $$\mathrm{Option}\ \mathbb Q \to \mathrm{JSON}$$ -/
def optWire (q : Option Rat) : Json := match q with | some x => ratWire x | none => .null

/-- A frame as JSON. $$F \mapsto \{n, r, \mathit{entering}, \mathit{shrinking}, \mathit{runway}, \mathit{more}\}$$ -/
def frameJson (f : Frame) : Json :=
  Json.mkObj [("n", ratWire f.n), ("r", ratWire f.r), ("entering", .bool f.entering), ("shrinking", .bool f.shrinking),
    ("runway", optWire f.runway), ("more", .bool f.more)]

/-- The golden lines of the section logic. $$\text{lines}$$ Vectors the TS section logic must reproduce. -/
def commissionLines : List String :=
  (([-1, 0, 0.1, 0.25, 0.5, 0.9, 1, 2] : List Rat).map fun x => line "smooth" [("x", rin x)] (ratWire (smooth x))) ++
  (([(0, 1000), (60, 1000), (150, 1000), (240, 1000), (420, 1000), (421, 1000), (5000, 1000), (-300, 800), (200, 800)] :
      List (Rat × Rat)).flatMap fun (t, h) =>
    [line "enterRaw" [("top", rin t), ("h", rin h)] (ratWire (enterRaw t h)),
     line "exitRaw" [("bottom", rin t), ("h", rin h)] (ratWire (exitRaw t h))]) ++
  (bs.flatMap fun rm => ([0, 0.2, 0.49, 0.5, 0.75, 1] : List Rat).map fun x =>
    line "target" [("reduced", .bool rm), ("x", rin x)] (ratWire (target rm x))) ++
  (let pairs : List (Rat × Rat) := [(1, 0), (0, 0), (0.5, 0.5), (0.9, 0.2), (1, 1), (0.0005, 0.9995)]
   let geoms : List (Rat × Rat × Rat) :=
     [(5000, 6000, 1000), (250, 1400, 1000), (0, 1000, 1000), (-200, 700, 1000), (-900, 100, 1000), (60, 400, 800), (800, 1900, 800)]
   pairs.flatMap fun (n, r) => geoms.flatMap fun (t, b, h) => bs.flatMap fun rm => bs.map fun c =>
     line "frame" [("n", rin n), ("r", rin r), ("top", rin t), ("bottom", rin b), ("h", rin h), ("reduced", .bool rm),
       ("compact", .bool c)] (frameJson (frame ⟨n, r⟩ t b h rm c))) ++
  (([(1000, 1920), (1001, 1920), (1001, 500), (1001, 501), (1200, 1920), (1201, 1920), (320, 320)] : List (Rat × Rat)).flatMap
    fun (w, d) => bs.map fun t => line "compact" [("width", rin w), ("deviceWidth", rin d), ("touch", .bool t)] (.bool (compact w d t))) ++
  (bs.flatMap fun c => ([0, 1, 2, 3] : List Nat).map fun k =>
    line "titleWrapped" [("compact", .bool c), ("rects", .num ⟨Int.ofNat k, 0⟩)] (.bool (titleWrapped c k))) ++
  (bs.flatMap fun i => ([0, 0.2, 0.44, 0.45, 0.75, 1] : List Rat).map fun r =>
    line "ulFire" [("isIntersecting", .bool i), ("ratio", rin r)] (.bool (ulFire i r))) ++
  (bs.map fun rm => line "ulStart" [("reduced", .bool rm)] (.str (match ulStart rm with | .hidden => "hidden" | .enter => "enter" | .idle => "idle"))) ++
  (([(0, 800, 800), (1600, 2400, 800), (1601, 2400, 800), (-900, -800, 800), (-900, -801, 800), (3000, 4000, 800)] :
      List (Rat × Rat × Rat)).map fun (t, b, h) =>
    line "sceneActive" [("top", rin t), ("bottom", rin b), ("h", rin h)] (.bool (sceneActive t b h)))

/-- A view as JSON. $$V \mapsto \{\text{ten fields}\}$$ -/
def viewJson (v : View) : Json :=
  Json.mkObj [("resetting", .bool v.resetting), ("avatar", .bool v.avatar), ("bubble", .bool v.bubble),
    ("chars", .num ⟨Int.ofNat v.chars, 0⟩), ("caret", .bool v.caret), ("card", .bool v.card), ("out", .bool v.out),
    ("earned", ratWire v.earned), ("pct", ratWire v.pct), ("progress", ratWire v.progress)]

/-- A trigger state as the input of a golden line. $$S \mapsto \{\mathit{visible}, \mathit{token}, \mathit{since}, \mathit{frozen}, \mathit{static}\}$$ -/
def trigIn (s : Trig) : Json :=
  Json.mkObj [("visible", .bool s.visible), ("token", .num ⟨Int.ofNat s.token, 0⟩), ("since", optIn s.since),
    ("frozen", rin s.frozen), ("static", .bool s.static)]

/-- A trigger state as an output. $$S \mapsto \{\mathit{visible}, \mathit{token}, \mathit{since}, \mathit{frozen}, \mathit{static}\}$$ -/
def trigWire (s : Trig) : Json :=
  Json.mkObj [("visible", .bool s.visible), ("token", .num ⟨Int.ofNat s.token, 0⟩), ("since", optWire s.since),
    ("frozen", ratWire s.frozen), ("static", .bool s.static)]

/-- The golden lines of the typing timeline. $$\text{lines}$$ Vectors the TS typing logic must reproduce. -/
def typingLines : List String :=
  let taus : List Rat :=
    [0, 40, 79, 79.5, 80, 499, 499.9, 500, 513.5, 527, 527.9, 528, 556, 1000, 1535, 1535.9, 1536, 1563, 1563.5, 1564, 1743,
     1743.9, 1744, 2223, 2224, 2500, 2774, 3000, 3323, 3323.9, 3324, 3380, 3443, 3444, 3500, 3894, 4000, 4343, 4344, 5000,
     5943, 5943.9, 5944, 6500, 6843, 6843.9]
  (taus.map fun t => line "viewAt" [("tau", rin t)] (viewJson (viewAt t))) ++
  (taus.map fun t => line "chars" [("tau", rin t)] (.num ⟨Int.ofNat (chars t), 0⟩)) ++
  (([0, 0.5, 449.9, 450, 450.5, 899.9, 900, 1349.9, 1350, 12345] : List Rat).flatMap fun a =>
    [line "caretOpaque" [("age", rin a)] (.bool (caretOpaque a)),
     line "boilFrame" [("age", rin a)] (.num ⟨Int.ofNat (boilFrame a), 0⟩)]) ++
  (([0, 199.9, 199.97, 199.98, 300, 399.95, 399.96, 500, 599.99, 600, 600.01, 1000, 1199.98] : List Rat).map fun a =>
    line "boilFrame" [("age", rin a)] (.num ⟨Int.ofNat (boilFrame a), 0⟩)) ++
  (([0, 100, 300, 345.6, 346, 432, 1000] : List Rat).map fun w => line "visualScale" [("width", rin w)] (ratWire (visualScale w))) ++
  (let states : List Trig :=
    [trig0, ⟨true, 1, some 1000, 0, false⟩, ⟨false, 2, none, 777.5, false⟩, ⟨true, 3, some 500, 12, true⟩, ⟨false, 1, none, 0, true⟩]
   states.flatMap fun s => bs.flatMap fun i => bs.map fun rm =>
     line "observe" [("state", trigIn s), ("isIntersecting", .bool i), ("now", rin 1500), ("reduced", .bool rm)]
       (let r := observe s i 1500 rm
        Json.mkObj [("state", trigWire r.1), ("act", .str (match r.2 with | .keep => "keep" | .cancel => "cancel" | .restart => "restart"))])) ++
  (let states : List Trig :=
    [trig0, ⟨true, 1, some 1000, 0, false⟩, ⟨false, 2, none, 777.5, false⟩, ⟨true, 3, some 500, 12, true⟩, ⟨false, 1, none, 0, true⟩,
     ⟨true, 2, some 0, 0, false⟩, ⟨false, 4, none, 6900, false⟩]
   states.flatMap fun s => ([1000, 1500, 2000, 8000, 20000] : List Rat).map fun n =>
     line "picture" [("state", trigIn s), ("now", rin n)] (viewJson (picture s n)))

end Fw.Parts.CommissionGolden
