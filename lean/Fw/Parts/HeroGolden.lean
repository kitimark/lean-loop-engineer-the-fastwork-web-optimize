import Lean.Data.Json
import Fw.Parts.HeroOrbit
import Fw.Parts.HeroAccent
/-!
# Golden vectors for hero.orbit and hero.accent

`HeroGolden.orbitLines` and `HeroGolden.accentLines` are the contents of
`packages/contracts/golden/parts/hero.orbit.jsonl` and `hero.accent.jsonl` (same line format and encodings as
`Fw/Parts/Golden.lean`: `Rat` inputs as exact JSON decimals, `Rat` outputs in the wire form `{"num","den"}`; `Nat` and
`Int` as JSON integers). `Fw/Parts/Golden.lean` writes both files.
-/
namespace Fw.Parts.HeroGolden
open Lean Fw.Parts

/-- A rational input as an exact JSON decimal (all denominators here divide $10^6$).

$$q \mapsto q \cdot 10^6 \cdot 10^{-6}$$ -/
def rin (q : Rat) : Json := .num ⟨q.num * ((1000000 / q.den : Nat) : Int), 6⟩

/-- The `Rat` output wire form. $$q \mapsto \{\mathrm{num}, \mathrm{den}\}$$ -/
def ratWire (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- One golden line. $$(\mathit{fn}, \mathit{in}, \mathit{out}) \mapsto \text{JSON line}$$ -/
def line (fn : String) (inp : List (String × Json)) (out : Json) : String :=
  (Json.mkObj [("fn", .str fn), ("in", Json.mkObj inp), ("out", out)]).compress

/-- A natural number as a JSON integer. $$n \mapsto n$$ -/
def jn (n : Nat) : Json := .num ⟨(n : Int), 0⟩

/-- An integer as a JSON integer. $$z \mapsto z$$ -/
def ji (z : Int) : Json := .num ⟨z, 0⟩

/-- Phase name. $$\mathrm{ph} \mapsto \text{string}$$ -/
def phaseName : HeroOrbit.Phase → String
  | .idle => "idle" | .rewind => "rewind" | .surge => "surge" | .after => "after"

/-- Elapsed times around every edge of the splash clock (ms). $$\text{samples}$$ -/
def times : List Rat :=
  [0, 100, 899, 900, 901, 1000, 1130, 11304 / 10, 1131, 1163, 1164, 1165, 1250, 1379, 1380, 1381, 1500, 1819, 1820, 3000]

/-- The orbit golden lines. $$\text{lines}$$ Vectors the TS orbit logic must reproduce. -/
def orbitLines : List String :=
  (times.map fun e =>
    let p := HeroOrbit.phase e
    line "phase" [("e", rin e)] (Json.mkObj [("phase", .str (phaseName p.phase)), ("t", ratWire p.t)])) ++
  (times.map fun e => line "angleDeg" [("e", rin e)] (ratWire (HeroOrbit.angleDeg e))) ++
  (times.map fun e => line "radius" [("e", rin e)] (ratWire (HeroOrbit.radius e))) ++
  (times.map fun e => line "blur" [("e", rin e)] (ratWire (HeroOrbit.blur e))) ++
  (([0, 1, 2, 3, 4] : List Nat).map fun k => line "enterDelay" [("k", jn k)] (ratWire (HeroOrbit.enterDelay k))) ++
  (([400, 600, 601, 800, 1000, 1279, 1280, 1281, 1511, 1512, 1920] : List Rat).map fun w =>
    line "push" [("w", rin w)] (ratWire (HeroOrbit.push w))) ++
  (HeroOrbit.pieces.map fun p =>
    line "scatter" [("left", rin p.left), ("top", rin p.top)]
      (Json.mkObj [("x", ratWire (HeroOrbit.scatterX p.left)), ("y", ratWire (HeroOrbit.scatterY p.left p.top))])) ++
  (HeroOrbit.pieces.map fun p =>
    line "ringScale" [("width", rin p.width)] (ratWire (HeroOrbit.chip / p.width))) ++
  (HeroOrbit.pieces.flatMap fun p => ([601, 900, 1279, 1280, 1511] : List Rat).map fun w =>
    line "leftEdge" [("isLeft", .bool (decide (p.left / 1512 * 100 < 50))), ("left", rin p.left),
      ("right", rin (1512 - p.left - p.width)), ("width", rin p.width), ("vw", rin w)]
      (ratWire (HeroOrbit.leftEdge (decide (p.left / 1512 * 100 < 50)) p.left (1512 - p.left - p.width) p.width w))) ++
  [line "ringIndex" [] (Json.arr (HeroOrbit.ringIndex.map fun i => jn i).toArray)] ++
  (let idx := HeroOrbit.ringIndex
   (HeroOrbit.pieces.zip idx).flatMap fun (p, i) =>
     ([1512, 1280, 1000, 700] : List Rat).flatMap fun n =>
       ([0, 500, 900, 1000, 11304 / 10, 1250, 1380, 1500, 1820] : List Rat).map fun e =>
         let a := decide (e ≥ HeroOrbit.expandAt)
         let nEff := if a then n else 1512
         let r := HeroOrbit.toF (HeroOrbit.angleDeg e) * HeroOrbit.piF / 180.0
         let rho := HeroOrbit.toF (HeroOrbit.radius e)
         let (x, y, rot) := HeroOrbit.place p.left p.top p.width p.height i (HeroOrbit.toF nEff) r rho a
         line "place"
           [("left", rin p.left), ("top", rin p.top), ("width", rin p.width), ("height", rin p.height),
            ("idx", jn i), ("n", rin nEff), ("e", rin e), ("expanded", .bool a)]
           (Json.mkObj [("x", ji x), ("y", ji y), ("rotTenths", ji rot)]))

/-- State name. $$\mathrm{st} \mapsto \text{string}$$ -/
def stName : HeroAccent.St → String
  | .idle => "idle" | .drawOut => "draw-out" | .drawIn => "draw-in"

/-- The accent golden lines. $$\text{lines}$$ Vectors the TS accent logic must reproduce. -/
def accentLines : List String :=
  (([-1, 0, 1, 4, 5, 6, 7] : List Int).map fun c =>
    line "next" [("c", ji c)] (ji (HeroAccent.next c))) ++
  ((List.range 16).map fun j =>
    line "cursorAfter" [("j", jn j)] (ji (HeroAccent.cursorAfter j))) ++
  (([-1, 0, 1, 2, 3, 4, 5] : List Int).map fun c =>
    line "widthOf" [("c", ji c)] (ji (HeroAccent.widthOf c))) ++
  (([0, 2199, 2200, 3099, 3100, 3999, 4000, 5249, 5250, 6149, 6150, 7049, 7050, 8299, 8300, 24000, 24549, 24550,
     45000] : List Nat).map fun e =>
    let (s, c) := HeroAccent.chainAt e
    line "chainAt" [("e", jn e)]
      (Json.mkObj [("state", .str (stName s)), ("cursor", ji c)])) ++
  (([0, 199, 200, 399, 400, 599, 600, 601, 1250] : List Nat).map fun e =>
    line "idleFrame" [("e", jn e)] (jn (HeroAccent.idleFrame e)))

end Fw.Parts.HeroGolden
