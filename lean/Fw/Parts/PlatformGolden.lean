import Lean.Data.Json
import Fw.Parts.PlatformSection
import Fw.Parts.PlatformSweep
import Fw.Parts.PlatformGlint
import Fw.Parts.PlatformMarquee
import Fw.Parts.PlatformEntries
/-!
# Golden vectors for the platform parts

`PlatformGolden.files` is the list of `(file name, lines)` that `Golden.lean` writes into
`packages/contracts/golden/parts/`: `platform.jsonl`, `platform.sweep.jsonl`, `platform.glint.jsonl`,
`platform.marquee.jsonl`, `platform.entries.jsonl`. Same line format and encodings as `Fw/Parts/Golden.lean`
(`Rat` inputs as exact JSON decimals, `Rat` outputs in the wire form `{"num","den"}`).
The `const` lines carry the constants the CSS Modules restate; a TS test checks the CSS text against them.
-/
namespace Fw.Parts.PlatformGolden
open Lean

/-- A rational input as an exact JSON decimal (denominators here divide $10^6$).

$$q \mapsto q \cdot 10^6 \cdot 10^{-6}$$ -/
def rin (q : Rat) : Json :=
  if (1000000 % q.den) == 0 then .num ⟨q.num * ((1000000 / q.den : Nat) : Int), 6⟩
  else Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- The `Rat` output wire form. $$q \mapsto \{\mathrm{num}, \mathrm{den}\}$$ -/
def ratWire (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- One golden line. $$(\mathit{fn}, \mathit{in}, \mathit{out}) \mapsto \text{JSON line}$$ -/
def line (fn : String) (inp : List (String × Json)) (out : Json) : String :=
  (Json.mkObj [("fn", .str fn), ("in", Json.mkObj inp), ("out", out)]).compress

/-- Integers as JSON. $$n \mapsto n$$ -/
def jn (n : Int) : Json := .num ⟨n, 0⟩

/-- Times in ms used by the cyclic parts: around the start, the quarter points and a few cycles.

$$T(p) = [0, 1, \tfrac p8, \tfrac p5, \tfrac p4, \tfrac p2, \tfrac{3p}{4}, p - 1, p, p + 1, \tfrac{5p}{2}, 7p + 123]$$ -/
def times (period : Rat) : List Rat :=
  [0, 1, period / 8, period / 5, period / 4, period / 2, period * 3 / 4, period - 1, period, period + 1, period * 5 / 2, period * 7 + 123]

/-- A colour as JSON.

$$(r, g, b) \mapsto [\mathrm{wire}(r), \mathrm{wire}(g), \mathrm{wire}(b)]$$ -/
def rgbWire (c : Rat × Rat × Rat) : Json := Json.arr #[ratWire c.1, ratWire c.2.1, ratWire c.2.2]

/-! ### platform -/

open Fw.Parts.PlatformSection in
/-- Lines of `platform.jsonl`. $$\text{lines}$$ -/
def platformLines : List String :=
  let vhs : List Rat := [600, 800, 900]
  let bottoms : List Rat := [-100, 0, 280, 300, 350, 400, 500, 600, 680, 700, 765, 770, 800, 900, 1200]
  (vhs.flatMap fun vh => bottoms.flatMap fun b =>
    [line "raw" [("bottom", rin b), ("vh", rin vh)] (ratWire (raw b vh)),
     line "shrinking" [("bottom", rin b), ("vh", rin vh)] (.bool (shrinking b vh))] ++
    [false, true].map fun rm =>
      line "shrink" [("reduced", .bool rm), ("bottom", rin b), ("vh", rin vh)] (ratWire (shrink rm b vh))) ++
  (([0, 1 / 4, 1 / 2, 3 / 4, 1] : List Rat).map fun s =>
    line "scale" [("s", rin s)] (ratWire (scale s))) ++
  (([0, 320, 361, 640, 1000, 1280] : List Rat).flatMap fun w =>
    [line "stageHeight" [("w", rin w)] (ratWire (stageHeight w)),
     line "artboardScale" [("w", rin w)] (ratWire (artboardScale w))]) ++
  [line "const" [] (Json.mkObj
    [("bgBlur", ratWire bgBlur), ("bgOpacity", ratWire (bgOpacity false)), ("bgOpacityQuote", ratWire (bgOpacity true)),
     ("grainOpacity", ratWire (grainOpacity false)), ("grainOpacitySecure", ratWire (grainOpacity true)),
     ("grainTile", ratWire grainTile)])]

/-! ### platform.sweep -/

open Fw.Parts.PlatformSweep in
/-- Lines of `platform.sweep.jsonl`. $$\text{lines}$$ -/
def sweepLines : List String :=
  (times period).flatMap (fun t =>
    [line "pos" [("t", rin t)] (ratWire (pos t)),
     line "phase" [("t", rin t)] (ratWire (phase t))]) ++
  (([0, 1 / 6, 1 / 3, 1 / 2, 2 / 3, 5 / 6, 1] : List Rat).flatMap fun v =>
    ([0, 1 / 4, 1 / 2, 3 / 4, 1] : List Rat).map fun p =>
      line "color" [("u", rin (imageU v p))] (rgbWire (color (imageU v p)))) ++
  ([false, true].map fun r => line "active" [("reduce", .bool r)] (.bool (active r))) ++
  [line "const" [] (Json.mkObj
    [("periodMs", ratWire period),
     ("stops", Json.arr (stops.map ratWire).toArray)])]

/-! ### platform.marquee -/

open Fw.Parts.PlatformMarquee in
/-- Lines of `platform.marquee.jsonl`. $$\text{lines}$$ -/
def marqueeLines : List String :=
  (times period).flatMap (fun t =>
    ([1000, 2192, 4048] : List Rat).flatMap fun w =>
      [line "offsetLeft" [("w", rin w), ("t", rin t)] (ratWire (offsetLeft w t)),
       line "offsetRight" [("w", rin w), ("t", rin t)] (ratWire (offsetRight w t))]) ++
  ([false, true].map fun r => line "running" [("reduce", .bool r)] (.bool (running r))) ++
  [line "const" [] (Json.mkObj [("periodMs", ratWire period)])]

/-! ### platform.glint -/

open Fw.Parts.PlatformGlint in
/-- A side as a name.

$$\mathit{side} \mapsto \text{"left"} \mid \text{"right"}$$ -/
def sideName : Side → String
  | .left => "left" | .right => "right"

open Fw.Parts.PlatformGlint in
/-- A glint state as JSON.

$$s \mapsto \{h, g, v, \tau, t_0\}$$ -/
def stJson (s : St) : Json :=
  Json.mkObj [("h", .bool s.h), ("g", .bool s.g), ("v", .bool s.v),
    ("timer", match s.timer with | some d => ratWire d | none => .null),
    ("t0", match s.t0 with | some d => ratWire d | none => .null)]

open Fw.Parts.PlatformGlint in
/-- A glint state as an input.

$$s \mapsto \{h, g, v, \tau, t_0\}$$ -/
def stIn (s : St) : Json :=
  Json.mkObj [("h", .bool s.h), ("g", .bool s.g), ("v", .bool s.v),
    ("timer", match s.timer with | some d => rin d | none => .null),
    ("t0", match s.t0 with | some d => rin d | none => .null)]

open Fw.Parts.PlatformGlint in
/-- An event as JSON input.

$$e \mapsto \{\mathrm{kind}, \ldots\}$$ -/
def evIn : Ev → Json
  | .ratio r => Json.mkObj [("kind", .str "ratio"), ("ratio", rin r)]
  | .reduced b => Json.mkObj [("kind", .str "reduced"), ("value", .bool b)]
  | .fire => Json.mkObj [("kind", .str "fire")]

open Fw.Parts.PlatformGlint in
/-- Lines of `platform.glint.jsonl`. $$\text{lines}$$ -/
def glintLines : List String :=
  ([Side.left, Side.right].flatMap fun s =>
    ([0, 1, 250, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500, 4999, 5000, 5001, 7500, 12345] : List Rat).map fun e =>
      let z := sample s e
      line "sample" [("side", .str (sideName s)), ("elapsed", rin e)] (Json.arr #[ratWire z.1, ratWire z.2])) ++
  (let states : List St :=
    [init false, init true, step (init false) 0 (.ratio 0.4), step (step (init false) 0 (.ratio 0.4)) 1000 .fire,
     step (step (init false) 0 (.ratio 0.4)) 500 .fire, step (step (init false) 0 (.ratio 0.4)) 100 (.reduced true)]
   let evs : List Ev := [.ratio 0, .ratio 0.34, .ratio 0.35, .ratio 0.6, .reduced false, .reduced true, .fire]
   states.flatMap fun s => ([0, 600, 1000, 2500] : List Rat).flatMap fun n => evs.map fun e =>
     line "step" [("state", stIn s), ("now", rin n), ("event", evIn e)] (stJson (step s n e))) ++
  (let states : List St := [init false, step (step (init false) 0 (.ratio 0.4)) 1000 .fire]
   states.flatMap fun s => [Side.left, Side.right].flatMap fun sd => ([1000, 1500, 3000, 6500] : List Rat).map fun n =>
     line "view" [("state", stIn s), ("side", .str (sideName sd)), ("now", rin n)] (Json.arr #[ratWire (view s sd n).1, ratWire (view s sd n).2])) ++
  [line "const" [] (Json.mkObj [("durMs", ratWire dur), ("startDelayMs", ratWire startDelay), ("minRatio", ratWire minRatio)])]

/-! ### platform.entries -/

open Fw.Parts.PlatformEntries in
/-- A view as JSON.

$$v \mapsto \{\ell, i, s, a, r, c\}$$ -/
def viewJson (v : View) : Json :=
  Json.mkObj [("len", jn v.len), ("topic", jn v.topic), ("shown", jn v.shown), ("leaving", .bool v.leaving),
    ("results", .bool v.results), ("caret", .bool v.caret)]

open Fw.Parts.PlatformEntries in
/-- The entries of the live stages with their table name, in a fixed order.

$$\mathrm{table} = [(\mathrm{name}, e)]$$ -/
def entryTable : List (String × Entry) :=
  [("credCard0", credCard 0), ("credCard3", credCard 3), ("profilePhone", profilePhone), ("rings", rings),
   ("faceLeft", faceLeft), ("faceRight", faceRight), ("dash", dash), ("shield", shield), ("logo", logo),
   ("flag1", flag 1), ("flag3", flag 3), ("flag6", flag 6), ("invoiceCard", invoiceCard), ("orderRow0", orderRow 0),
   ("orderRow3", orderRow 3), ("askIn0", askIn 0), ("askIn2", askIn 2), ("askOut1", askOut 1)]

open Fw.Parts.PlatformEntries in
/-- Lines of `platform.entries.jsonl`. $$\text{lines}$$ -/
def entriesLines : List String :=
  (([-1, 0, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 1, 1.5] : List Rat).map fun x =>
    line "ease" [("x", rin x)] (ratWire (ease spring x))) ++
  (entryTable.flatMap fun (n, e) =>
    ([0, 30, 60, 100, 180, 300, 420, 560, 700, 1000, 1400] : List Rat).map fun t =>
      line "progress" [("entry", .str n), ("t", rin t)] (ratWire (progress e t))) ++
  ([(40, 240), (5, 240), (500, 43), (0, 5), (1000, 48), (1500, 240), (9999, 5), (180, 5)] : List (Rat × Nat)).map (fun (t, n) =>
    line "countAt" [("n", jn n), ("t", rin t)] (jn (countAt n t))) ++
  (let lens : List Nat := [23, 25, 22, 20]
   ([0, 699, 700, 731, 732, 1435, 1436, 1715, 1716, 2000, 4715, 4716, 4765, 5415, 5416, 6000, 9000, 12000, 20000, 33333, 50000, 80000, 123456]
      : List Rat).map fun t =>
    line "askView" [("lens", Json.arr (lens.map (fun (n : Nat) => jn (n : Int))).toArray), ("t", rin t)] (viewJson (askView lens t))) ++
  [line "const" [] (Json.mkObj
    [("spring", Json.arr #[ratWire spring.x1, ratWire spring.y1, ratWire spring.x2, ratWire spring.y2]),
     ("countDelayMs", ratWire countDelay), ("countDurMs", ratWire countDur), ("askLeadMs", ratWire askLead),
     ("typeStepMs", ratWire typeStep), ("eraseStepMs", ratWire eraseStep), ("holdMs", ratWire holdMs),
     ("firstRevealMs", ratWire firstReveal), ("swapMs", ratWire swapMs),
     ("entries", Json.arr (entryTable.map fun (n, e) =>
        Json.mkObj [("name", .str n), ("keyframes", .str e.name), ("durMs", ratWire e.dur), ("delayMs", ratWire e.delay),
          ("props", Json.arr (e.trs.map fun tr => Json.mkObj [("key", .str tr.key), ("from", ratWire tr.a), ("to", ratWire tr.b)]).toArray)]).toArray)])]

/-- The five golden files of the platform parts: name and lines. $$\mathit{files} = [(\mathrm{name}, \mathrm{lines})]$$ -/
def files : List (String × List String) :=
  [("platform.jsonl", platformLines), ("platform.sweep.jsonl", sweepLines), ("platform.glint.jsonl", glintLines),
   ("platform.marquee.jsonl", marqueeLines), ("platform.entries.jsonl", entriesLines)]

end Fw.Parts.PlatformGolden
