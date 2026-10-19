import Lean.Data.Json
import Fw.Parts.Bezier
import Fw.Parts.OverlayDrawer
import Fw.Parts.OverlaySignup
/-!
# Golden vectors for overlays.drawer and overlays.signup

`drawerLines` and `signupLines` are the contents of `packages/contracts/golden/parts/overlays.drawer.jsonl` and
`overlays.signup.jsonl` (same line format as `Fw/Parts/Golden.lean`: `Rat` inputs as exact JSON decimals, `Rat` outputs in
the wire form `{"num","den"}`). `Golden.lean` writes them (one import and two table entries).
-/
namespace Fw.Parts.OverlayGolden
open Lean

/-- A rational input as an exact JSON decimal (every input here has a denominator dividing $10^6$).

$$q \mapsto q \cdot 10^6 \cdot 10^{-6}$$ -/
def rin (q : Rat) : Json := .num ⟨q.num * ((1000000 / q.den : Nat) : Int), 6⟩

/-- The `Rat` output wire form. $$q \mapsto \{\mathrm{num}, \mathrm{den}\}$$ -/
def ratWire (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- One golden line. $$(\mathit{fn}, \mathit{in}, \mathit{out}) \mapsto \text{JSON line}$$ -/
def line (fn : String) (inp : List (String × Json)) (out : Json) : String :=
  (Json.mkObj [("fn", .str fn), ("in", Json.mkObj inp), ("out", out)]).compress

/-- An integer as JSON. $$z \mapsto z$$ -/
def jint (z : Int) : Json := .num ⟨z, 0⟩

/-- A pair of integers as JSON. $$(a, b) \mapsto [a, b]$$ -/
def pairJ (p : Int × Int) : Json := Json.arr #[jint p.1, jint p.2]

/-- A pair of rationals as JSON. $$(a, b) \mapsto [a, b]$$ -/
def ratPairJ (p : Rat × Rat) : Json := Json.arr #[ratWire p.1, ratWire p.2]

/-! ## Drawer -/

section Drawer
open Fw.Parts.OverlayDrawer Fw.Parts.Bezier

/-- Layout wire name. $$\ell \mapsto \text{"side"} \mid \text{"mid"} \mid \text{"sheet"}$$ -/
def layoutName : Layout → String
  | .side => "side" | .mid => "mid" | .sheet => "sheet"

/-- A state as JSON (output). $$S \mapsto \{\mathit{mounted}, \mathit{shown}, \mathit{rafPending}, \mathit{timerAt}\}$$ -/
def stJson (s : St) : Json :=
  Json.mkObj [("mounted", .bool s.mounted), ("shown", .bool s.shown), ("rafPending", .bool s.rafPending),
    ("timerAt", match s.timerAt with | some d => ratWire d | none => .null)]

/-- A state as JSON (input). $$S \mapsto \{\mathit{mounted}, \mathit{shown}, \mathit{rafPending}, \mathit{timerAt}\}$$ -/
def stIn (s : St) : Json :=
  Json.mkObj [("mounted", .bool s.mounted), ("shown", .bool s.shown), ("rafPending", .bool s.rafPending),
    ("timerAt", match s.timerAt with | some d => rin d | none => .null)]

/-- Reachable and edge states of the drawer machine. $$\text{states}$$ -/
def states : List St :=
  let opened := setOpen rest true 0 false
  let shown := raf opened
  let closing := setOpen shown false 1000 false
  [rest, opened, shown, closing, setOpen opened false 5 false, raf (setOpen opened false 5 false),
   tick (raf (setOpen opened false 5 false)) 485, setOpen shown false 1000 true]

/-- Lines for `overlays.drawer`. $$\text{lines}$$ The conformance vectors for the TS drawer. -/
def drawerLines : List String :=
  let ts : List Rat := [-50, 0, 25, 50, 100, 133.333, 200, 300, 399, 400, 401, 1000]
  let widths : List Rat := [320, 480, 640, 640.5, 641, 860, 860.5, 861, 1440]
  (([("easeInOut", easeInOut), ("easeStandard", easeStandard)] : List (String × Bez)).flatMap fun (n, c) =>
    ([-1, 0, 0.05, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9, 0.95, 1, 1.5] : List Rat).map fun t =>
      line "ease" [("curve", .str n), ("t", rin t)] (ratWire (ease c t))) ++
  (widths.map fun w => line "layoutOf" [("w", rin w)] (.str (layoutName (layoutOf w)))) ++
  ([Layout.side, .mid, .sheet].flatMap fun l => ([(600, 500), (390.5, 700.25)] : List (Rat × Rat)).map fun (pw, ph) =>
    line "hidden" [("layout", .str (layoutName l)), ("pw", rin pw), ("ph", rin ph)] (ratPairJ (hidden l pw ph))) ++
  ([false, true].flatMap fun r => ts.map fun e =>
    line "progress" [("elapsed", rin e), ("reduced", .bool r)] (ratWire (progress e r))) ++
  ([Layout.side, .mid, .sheet].flatMap fun l => [true, false].flatMap fun sh => [false, true].flatMap fun r =>
    ([0, 100, 200, 400, 500] : List Rat).map fun e =>
      line "panelPos" [("layout", .str (layoutName l)), ("pw", rin 600), ("ph", rin 500), ("shown", .bool sh),
        ("elapsed", rin e), ("reduced", .bool r)] (ratPairJ (panelPos l 600 500 sh e r))) ++
  ([true, false].flatMap fun sh => [false, true].flatMap fun r => ts.map fun e =>
    line "backdropAlpha" [("shown", .bool sh), ("elapsed", rin e), ("reduced", .bool r)] (ratWire (backdropAlpha sh e r))) ++
  (states.flatMap fun s => [true, false].flatMap fun b => [false, true].map fun r =>
    line "setOpen" [("state", stIn s), ("open", .bool b), ("now", rin 2000), ("reduced", .bool r)]
      (stJson (setOpen s b 2000 r))) ++
  (states.map fun s => line "raf" [("state", stIn s)] (stJson (raf s))) ++
  (states.flatMap fun s => ([0, 479.5, 580, 1000, 1480, 5000] : List Rat).map fun n =>
    line "tick" [("state", stIn s), ("now", rin n)] (stJson (tick s n))) ++
  (states.flatMap fun s => ["Escape", "Enter", "esc"].map fun k =>
    line "escapeCloses" [("state", stIn s), ("key", .str k)] (.bool (escapeCloses s k)))

end Drawer

/-! ## Signup -/

section Signup
open Fw.Parts.OverlaySignup

/-- Source wire name. $$\mathit{src} \mapsto \text{"escape"} \mid \text{"backdrop"} \mid \text{"cancel"}$$ -/
def sourceName : Source → String
  | .escape => "escape" | .backdrop => "backdrop" | .cancel => "cancel"

/-- Purpose wire name. $$p \mapsto \text{"info"} \mid \text{"form"} \mid \text{"required"}$$ -/
def purposeName : Purpose → String
  | .info => "info" | .form => "form" | .required => "required"

/-- Sync wire name. $$s \mapsto \text{"showModal"} \mid \text{"close"} \mid \text{"none"}$$ -/
def syncName : Sync → String
  | .showModal => "showModal" | .close => "close" | .none => "none"

/-- Form flags as JSON. $$F \mapsto \{\mathit{submitting}, \mathit{done}, \mathit{error}\}$$ -/
def formJ (f : Form) : Json :=
  Json.mkObj [("submitting", .bool f.submitting), ("done", .bool f.done), ("error", .bool f.error)]

/-- Lines for `overlays.signup`. $$\text{lines}$$ The conformance vectors for the TS dialog logic. -/
def signupLines : List String :=
  let offs : List (Rat × Rat) :=
    [(0, 0), (0, 1), (1, 0), (-1, 0), (0, -1), (3, 4), (-3, 4), (100, -100), (123.5, 67.25), (-640, -20), (0.5, 0.5),
     (1, 10), (10, 1), (-0.5, 300), (700, 0.25), (7, 7), (1, 1), (5, 12)]
  (offs.map fun (x, y) => line "dir" [("x", rin x), ("y", rin y)] (pairJ (dir x y))) ++
  (offs.map fun (x, y) => line "openDir" [("x", rin x), ("y", rin y)] (pairJ (openDir (some (x, y))))) ++
  [line "openDirNone" [] (pairJ (openDir none))] ++
  (([-10, 0, 100, 133.333, 200, 399.5, 400, 450, 1000] : List Rat).flatMap fun e => [false, true].flatMap fun r =>
    ([(0, 16), (11, -11), (-16, 0)] : List (Int × Int)).map fun (dx, dy) =>
      let f := frame dx dy e r
      line "frame" [("dx", jint dx), ("dy", jint dy), ("elapsed", rin e), ("reduced", .bool r)]
        (Json.mkObj [("opacity", ratWire f.opacity), ("tx", ratWire f.tx), ("ty", ratWire f.ty), ("scale", ratWire f.scale)])) ++
  ([Source.escape, .backdrop, .cancel].flatMap fun src => [Purpose.info, .form, .required].flatMap fun p =>
    [false, true].flatMap fun self => [false, true].flatMap fun c => [false, true].map fun l =>
      let r := react src p self c l
      line "react" [("source", .str (sourceName src)), ("purpose", .str (purposeName p)), ("self", .bool self),
        ("composing", .bool c), ("layered", .bool l)] (Json.mkObj [("prevent", .bool r.prevent), ("close", .bool r.close)])) ++
  ([false, true].map fun b => line "closeAllowed" [("submitting", .bool b)] (.bool (closeAllowed b))) ++
  ([false, true].flatMap fun a => [false, true].map fun b =>
    line "sync" [("isOpen", .bool a), ("domOpen", .bool b)] (.str (syncName (sync a b)))) ++
  (([("Ann", "a\x40example.com"), ("", "a\x40example.com"), ("  ", "a\x40example.com"), ("Ann", "a@b"), ("Ann", "a\x40.co"), ("Ann", "a\x40b."),
     ("Ann", "a b\x40example.com"), ("Ann", "a\x40\x40example.com"), (" Ann ", " a\x40b.c.d "), ("Ann", "\x40example.com"), ("Ann", "a\x40b.c"),
     ("Ann", "a\x40b..c"), ("Ann", ""), ("Ann", "a\x40b.c\x40d"), ("Ann", "a \x40example.com"), ("　", "a\x40example.com"),
     ("Ann", "ปก\x40example.com"), ("Ann", "a\x40example.com "),
     ("😀", "a\x40example.com"), ("👩‍💻", "a\x40example.com"), ("1", "a\x40example.com"), ("\n", "a\x40example.com")] : List (String × String)).map fun (n, e) =>
    line "valid" [("name", .str n), ("email", .str e)] (.bool (valid n.toList e.toList))) ++
  (let forms : List Form := [Form.init, ⟨true, false, false⟩, ⟨false, true, false⟩, ⟨false, false, true⟩]
   forms.flatMap fun f => [false, true].flatMap fun v => [false, true].map fun h =>
     let r := submit f v h
     line "submit" [("form", formJ f), ("valid", .bool v), ("hasHandler", .bool h)]
       (Json.mkObj [("form", formJ r.1), ("send", .bool r.2)])) ++
  (let forms : List Form := [Form.init, ⟨true, false, false⟩, ⟨true, false, true⟩]
   forms.flatMap fun f => [false, true].map fun ok =>
     line "settle" [("form", formJ f), ("ok", .bool ok)] (formJ (settle f ok)))

end Signup

end Fw.Parts.OverlayGolden
