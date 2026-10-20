import Lean.Data.Json
import Fw.Parts.MorphMount
/-!
# Golden vectors for morph.mount

`MorphMountGolden.lines` is the content of `packages/contracts/golden/parts/morph.mount.jsonl` (same line format and
encodings as `Fw/Parts/Golden.lean`: `Rat` inputs as exact JSON decimals, `Rat` outputs in the wire form
`{"num","den"}`). It has no `main`: `scripts`-free; run it with a one-line driver, e.g.
`lake env lean --run` on a file that does `IO.FS.writeFile path (String.intercalate "\n" lines ++ "\n")`.
`Golden.lean` can append `MorphMountGolden.lines` to its own table in one line (left to the lead: shared file).
-/
namespace Fw.Parts.MorphMountGolden
open Lean Fw.Parts.MorphMount

/-- A rational input as a JSON decimal with mantissa `n · ⌊ 1000/d ⌋` (natural-number division) and exponent `3`; exact only when `d | 1000`. -/
def rin (q : Rat) : Json := .num ⟨q.num * ((1000 / q.den : Nat) : Int), 3⟩

/-- The `Rat` output wire form. -/
def ratWire (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- One golden line. -/
def line (fn : String) (inp : List (String × Json)) (out : Json) : String :=
  (Json.mkObj [("fn", .str fn), ("in", Json.mkObj inp), ("out", out)]).compress

/-- Action name. -/
def actionName : Action → String
  | .attach => "attach" | .detach => "detach" | .none => "none"

/-- Fourteen (height, bottom, viewport height) samples around the 0.45 and +8 edges. -/
def rects : List (Rat × Rat × Rat) :=
  [(450, 800, 1000), (449, 800, 1000), (449.5, 800, 1000), (900, 1008, 1000), (900, 1008.5, 1000), (900, 1009, 1000),
   (0, 0, 0), (0, -5, 0), (360, 844, 800), (359, 844, 800), (360, 808, 800), (360, 809, 800), (1, 1, 2), (0.5, 0, 1)]

/-- Booleans. -/
def bs : List Bool := [false, true]

/-- The 74 golden lines the TS logic must reproduce, concatenated in this order: `armed` over `rects` (14), `active` (8 pairs), `takes` over `𝔹 × {-5,-0.5,0,0.5,120} × 𝔹` (20), `touchDelta` (4), `viewportHeight` (4), `wanted` over `𝔹^2` (4), `action` over `𝔹^2` (4), `mountNext` over `𝔹^3` (8), `repin` over `𝔹 × 4` pairs (8). -/
def lines : List String :=
  (rects.map fun (h, b, v) =>
    line "armed" [("height", rin h), ("bottom", rin b), ("vh", rin v)] (.bool (armed ⟨h, b⟩ v))) ++
  ([(0, 0), (1, 0), (0, 1), (0.001, 0), (0, 0.001), (0.002, 0), (0, 0.002), (0.5, 0.5)].map fun (w, m) =>
    line "active" [("target", rin w), ("value", rin m)] (.bool (active w m))) ++
  (bs.flatMap fun a => [(-5 : Rat), -0.5, 0, 0.5, 120].flatMap fun d => bs.map fun g =>
    line "takes" [("active", .bool a), ("delta", rin d), ("geom", .bool g)] (.bool (takes a d g))) ++
  ([(300, 200), (200, 300), (250, 250), (0, 0.5)].map fun (p, c) =>
    line "touchDelta" [("prev", rin p), ("cur", rin c)] (ratWire (touchDelta p c))) ++
  ([(some 700, 800), (none, 800), (some 0, 800), (some 640.5, 667)].map fun (v, i) =>
    line "viewportHeight" [("visual", match v with | some x => rin x | none => .null), ("inner", rin i)]
      (ratWire (viewportHeight v i))) ++
  (bs.flatMap fun n => bs.map fun a => line "wanted" [("near", .bool n), ("active", .bool a)] (.bool (wanted n a))) ++
  (bs.flatMap fun d => bs.map fun w =>
    line "action" [("attached", .bool d), ("wanted", .bool w)] (.str (actionName (action d w)))) ++
  (bs.flatMap fun m => bs.flatMap fun i => bs.map fun p =>
    line "mountNext" [("mounted", .bool m), ("intersecting", .bool i), ("pushed", .bool p)]
      (.bool (mountNext m i p))) ++
  (bs.flatMap fun a => [(0, 0), (0, 100), (100, 0), (250.5, 250.5)].map fun (y, p) =>
    line "repin" [("active", .bool a), ("y", rin y), ("pin", rin p)] (.bool (repin a y p)))

#guard lines.length == 14 + 8 + 20 + 4 + 4 + 4 + 4 + 8 + 8

end Fw.Parts.MorphMountGolden
