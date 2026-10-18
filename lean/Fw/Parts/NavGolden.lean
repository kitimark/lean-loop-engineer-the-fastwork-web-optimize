import Lean.Data.Json
import Fw.Parts.NavLangMenu
/-!
# Golden vectors for nav and nav.langMenu

`NavGolden.navLines` is `packages/contracts/golden/parts/nav.jsonl`, `NavGolden.menuLines` is
`packages/contracts/golden/parts/nav.langMenu.jsonl` (same line format and encodings as `Fw/Parts/Golden.lean`: `Rat`
inputs as exact JSON decimals, `Rat` outputs in the wire form `{"num","den"}`). No `main`: write them with a one-line
driver (`IO.FS.writeFile path (String.intercalate "\n" lines ++ "\n")`, run through `lake env lean --run`).
`Golden.lean` appends both tables in one line each.
-/
namespace Fw.Parts.NavGolden
open Lean Fw.Parts.Nav Fw.Parts.NavLangMenu

/-- A rational input as an exact JSON decimal (denominators here divide $10^4$). $$q \mapsto q \cdot 10^4 \cdot 10^{-4}$$ -/
def rin (q : Rat) : Json := .num ⟨q.num * ((10000 / q.den : Nat) : Int), 4⟩

/-- The `Rat` output wire form. $$q \mapsto \{\mathrm{num}, \mathrm{den}\}$$ -/
def ratWire (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- One golden line. $$(\mathit{fn}, \mathit{in}, \mathit{out}) \mapsto \text{JSON line}$$ -/
def line (fn : String) (inp : List (String × Json)) (out : Json) : String :=
  (Json.mkObj [("fn", .str fn), ("in", Json.mkObj inp), ("out", out)]).compress

/-- Booleans. $$\mathbb B$$ -/
def bs : List Bool := [false, true]

/-- The class set as JSON. $$c \mapsto \{\ldots\}$$ -/
def viewJ (v : View) : Json :=
  Json.mkObj [("heroPill", .bool v.heroPill), ("ready", .bool v.ready), ("morphing", .bool v.morphing),
    ("expanded", .bool v.expanded), ("onDark", .bool v.onDark), ("localeOpen", .bool v.localeOpen),
    ("scrollHidden", .bool v.scrollHidden)]

/-- Phase name. $$p \mapsto \text{string}$$ -/
def phaseName : Phase → String
  | .closed => "closed" | .open_ => "open" | .closing => "closing"

/-- Event name. $$e \mapsto \text{string}$$ -/
def evName : Ev → String
  | .toggle => "toggle" | .select => "select" | .outside => "outside" | .timer => "timer"

/-- Timer action name. $$\tau \mapsto \text{string}$$ -/
def timerName : Timer → String
  | .keep => "keep" | .clear => "clear" | .rearm => "rearm"

/-- Morph values around every cut. $$m$$ -/
def ms : List Rat := [0, 0.001, 0.0011, 0.2, 0.2001, 0.4, 0.4001, 0.55, 0.5501, 0.92, 0.9201, 1]

/-- nav lines. $$\text{lines}$$ Vectors the TS logic must reproduce. -/
def navLines : List String :=
  (([(0, 2000, 800), (-863, 2000, 800), (-864, 2000, 800), (-1000, 2000, 800), (10, 2000, 800), (0, 500, 800),
     (-100, 500, 800), (-5, 1000, 1000)] : List (Rat × Rat × Rat)).flatMap fun (t, h, v) =>
    bs.flatMap fun pr => bs.map fun rm =>
      line "pastHero" [("present", .bool pr), ("reduced", .bool rm), ("top", rin t), ("height", rin h), ("vh", rin v)]
        (.bool (pastHero pr rm t h v))) ++
  (([(0, 2000, 800), (-432, 2000, 800), (-863, 2000, 800), (-864, 2000, 800), (-2000, 2000, 800), (5, 500, 800)] :
      List (Rat × Rat × Rat)).map fun (t, h, v) =>
    line "progress" [("top", rin t), ("height", rin h), ("vh", rin v)] (ratWire (progress t h v))) ++
  (([(some 80, 81, 400, 900), (some 80, 82, 400, 900), (some 80, 80, 400, 401), (some 80, 80, 400, 400),
     (none, 0, 400, 900), (some 0, 1, 10, 20), (some 0, 3/2, 10, 20)] : List (Option Rat × Rat × Rat × Rat)).flatMap
    fun (top, it, ib, sb) => bs.flatMap fun a => bs.flatMap fun b => bs.map fun c =>
      line "stuck" [("present", .bool a), ("isSticky", .bool b), ("hasSection", .bool c),
        ("top", match top with | some r => rin r | none => .null), ("itemTop", rin it), ("itemBottom", rin ib),
        ("sectionBottom", rin sb)] (.bool (stuck ⟨a, b, c, top, it, ib, sb⟩))) ++
  (ms.flatMap fun m => bs.flatMap fun past => bs.flatMap fun ready => bs.flatMap fun loc => bs.flatMap fun hit =>
    bs.map fun stk =>
      line "view" [("past", .bool past), ("ready", .bool ready), ("localeOpen", .bool loc), ("hit", .bool hit),
        ("stuck", .bool stk), ("m", rin m)] (viewJ (view past ready loc hit stk m))) ++
  (ms.flatMap fun m => bs.map fun pill =>
    line "earn" [("heroPill", .bool pill), ("m", rin m)]
      (Json.mkObj [("tabOff", .bool (earn pill m).tabOff), ("ariaHidden", .bool (earn pill m).ariaHidden)])) ++
  (bs.flatMap fun a => bs.map fun b =>
    line "readyInit" [("reduced", .bool a), ("phone", .bool b)] (.bool (readyInit a b))) ++
  (bs.flatMap fun r => bs.flatMap fun a => bs.flatMap fun b => bs.map fun c =>
    line "readyChange" [("ready", .bool r), ("reduced", .bool a), ("phone", .bool b), ("splash", .bool c)]
      (.bool (readyChange r a b c))) ++
  (([0, 1139, 1140, 1141, 5000] : List Nat).map fun (t : Nat) =>
    line "readyAt" [("t", .num ⟨(t : Int), 0⟩)] (.bool (readyAt t)))

/-- nav.langMenu lines. $$\text{lines}$$ Vectors the TS logic must reproduce. -/
def menuLines : List String :=
  (([Phase.closed, .open_, .closing]).flatMap fun p => ([Ev.toggle, .select, .outside, .timer]).map fun e =>
    let o := step p e
    line "step" [("phase", .str (phaseName p)), ("ev", .str (evName e))]
      (Json.mkObj [("phase", .str (phaseName o.phase)), ("timer", .str (timerName o.timer))])) ++
  (([Phase.closed, .open_, .closing]).map fun p =>
    line "flags" [("phase", .str (phaseName p))]
      (Json.mkObj [("isOpen", .bool (isOpen p)), ("mounted", .bool (mounted p)), ("isClosing", .bool (isClosing p)),
        ("listening", .bool (listening p)), ("navLocaleOpen", .bool (navLocaleOpen p))]))

end Fw.Parts.NavGolden
