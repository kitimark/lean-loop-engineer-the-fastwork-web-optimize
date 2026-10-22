import Lean.Data.Json
import Fw.Parts.PlatformSection
import Fw.Parts.PlatformSweep
import Fw.Parts.PlatformGlint
import Fw.Parts.PlatformMarquee
import Fw.Parts.PlatformEntries
import Fw.Parts.PlatformScene
import Fw.Parts.HiddenPausePlatform
import Fw.Parts.PlatformShrinkOpt
import Fw.Parts.PlatformFade

namespace Fw.Parts.PlatformGolden
open Lean

/-- A rational input as an exact JSON decimal when its denominator divides `10^6`, else the wire object. -/
def rin (q : Rat) : Json :=
  if (1000000 % q.den) == 0 then .num ⟨q.num * ((1000000 / q.den : Nat) : Int), 6⟩
  else Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- The `Rat` output wire form: numerator and denominator of the reduced fraction as decimal strings. -/
def ratWire (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- One golden line: the compact JSON text (Lean's `compress`, keys sorted) of the object with keys `fn`, `in`, `out`. -/
def line (fn : String) (inp : List (String × Json)) (out : Json) : String :=
  (Json.mkObj [("fn", .str fn), ("in", Json.mkObj inp), ("out", out)]).compress

/-- Integers as JSON. -/
def jn (n : Int) : Json := .num ⟨n, 0⟩

/-- Times in ms used by the cyclic parts: around the start, the quarter points and a few cycles. -/
def times (period : Rat) : List Rat :=
  [0, 1, period / 8, period / 5, period / 4, period / 2, period * 3 / 4, period - 1, period, period + 1, period * 5 / 2, period * 7 + 123]

/-- A colour as JSON. -/
def rgbWire (c : Rat × Rat × Rat) : Json := Json.arr #[ratWire c.1, ratWire c.2.1, ratWire c.2.2]

/-! ### platform -/

open Fw.Parts.PlatformSection in
/-- Lines of `platform.jsonl`: per viewport height and bottom the four position lines, then scale, then the stage
size per width, then one `const` line. Comprehensions run their generators left to right, outer to inner. -/
def platformLines (_ : Unit := ()) : List String :=
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
/-- Lines of `platform.sweep.jsonl`: position and phase over the sample times, colours on a grid of image
coordinates, the active flag, one `const` line. Comprehensions run their generators left to right, outer to inner. -/
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
/-- Lines of `platform.marquee.jsonl`: both offsets over the sample times and three track widths, the running flag,
one `const` line. Comprehensions run their generators left to right, outer to inner. -/
def marqueeLines : List String :=
  (times period).flatMap (fun t =>
    ([1000, 2192, 4048] : List Rat).flatMap fun w =>
      [line "offsetLeft" [("w", rin w), ("t", rin t)] (ratWire (offsetLeft w t)),
       line "offsetRight" [("w", rin w), ("t", rin t)] (ratWire (offsetRight w t))]) ++
  ([false, true].map fun r => line "running" [("reduce", .bool r)] (.bool (running r))) ++
  [line "const" [] (Json.mkObj [("periodMs", ratWire period)])]

/-! ### platform.glint -/

open Fw.Parts.PlatformGlint in
/-- A side as a name. -/
def sideName : Side → String
  | .left => "left" | .right => "right"

open Fw.Parts.PlatformGlint in
/-- A glint state as JSON (an output: times in the wire form). -/
def stJson (s : St) : Json :=
  Json.mkObj [("h", .bool s.h), ("g", .bool s.g), ("v", .bool s.v),
    ("timer", match s.timer with | some d => ratWire d | none => .null),
    ("t0", match s.t0 with | some d => ratWire d | none => .null)]

open Fw.Parts.PlatformGlint in
/-- A glint state as an input (times as exact decimals). -/
def stIn (s : St) : Json :=
  Json.mkObj [("h", .bool s.h), ("g", .bool s.g), ("v", .bool s.v),
    ("timer", match s.timer with | some d => rin d | none => .null),
    ("t0", match s.t0 with | some d => rin d | none => .null)]

open Fw.Parts.PlatformGlint in
/-- An event as JSON input. -/
def evIn : Ev → Json
  | .ratio r => Json.mkObj [("kind", .str "ratio"), ("ratio", rin r)]
  | .reduced b => Json.mkObj [("kind", .str "reduced"), ("value", .bool b)]
  | .fire => Json.mkObj [("kind", .str "fire")]

open Fw.Parts.PlatformGlint in
/-- Lines of `platform.glint.jsonl`: dash samples, the step function over states, times and events, the view, one
`const` line. Comprehensions run their generators left to right, outer to inner. -/
def glintLines (_ : Unit := ()) : List String :=
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
/-- A view as JSON: the three numbers as JSON integers, the three flags as booleans. -/
def viewJson (v : View) : Json :=
  Json.mkObj [("len", jn v.len), ("topic", jn v.topic), ("shown", jn v.shown), ("leaving", .bool v.leaving),
    ("results", .bool v.results), ("caret", .bool v.caret)]

open Fw.Parts.PlatformEntries in
/-- The entries of the live stages with their table name, in a fixed order (18 pairs). -/
def entryTable : List (String × Entry) :=
  [("credCard0", credCard 0), ("credCard3", credCard 3), ("profilePhone", profilePhone), ("rings", rings),
   ("faceLeft", faceLeft), ("faceRight", faceRight), ("dash", dash), ("shield", shield), ("logo", logo),
   ("flag1", flag 1), ("flag3", flag 3), ("flag6", flag 6), ("invoiceCard", invoiceCard), ("orderRow0", orderRow 0),
   ("orderRow3", orderRow 3), ("askIn0", askIn 0), ("askIn2", askIn 2), ("askOut1", askOut 1)]

open Fw.Parts.PlatformEntries in
/-- Lines of `platform.entries.jsonl`: the spring ease, every table entry's progress, the count-up, the search view,
one `const` line. Comprehensions run their generators left to right, outer to inner; `ease` is on the
spring curve. -/
def entriesLines (_ : Unit := ()) : List String :=
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

open Fw.Parts.PlatformScene in
/-- Lines of `platform.scene.jsonl`: the scene value at ten rects around the two edges `b = -h` and `t = 2h`, then one
`const` line with the attribute name, its two values, the observer margin and the rule's property.

Each rect is (top, bottom, viewport height); the lines follow `R`'s order. -/
def sceneLines : List String :=
  (([(0, 800, 900), (-5000, -901, 900), (-5000, -900, 900), (1800, 2600, 900), (1801, 2600, 900), (-1000, -500, 900),
     (3000, 3800, 900), (-300, 100, 400), (801, 1200, 400), (800, 1200, 400)] : List (Rat × Rat × Rat)).map fun (t, b, h) =>
    line "scene" [("top", rin t), ("bottom", rin b), ("vh", rin h)] (.str (sceneOf t b h))) ++
  [line "const" [] (Json.mkObj
    [("attr", .str "data-fw-scene"), ("active", .str (attr true)), ("paused", .str (attr false)),
     ("rootMargin", .str "100% 0px"), ("playState", .str "paused")])]

open Fw.Parts.HiddenPausePlatform in
/-- Lines of `engine.scene.jsonl`: for each trace, from the synced start `s_0 = (0, 0, ⊥, 0)` and `ℓ_0 = 0`, the
variant's shown local time and the original's at every frame, and the variant's local time at the end.

`Δ` is an exact JSON decimal, times are in the `Rat` wire form, `a` and `h` are JSON booleans. -/
def syncLines : List String :=
  let s0 : St := ⟨0, 0, false, 0⟩
  ([[(16, true, false), (16, true, true), (16, true, true), (16, true, false)],
    [(16, true, true), (16, false, true), (16, true, true), (16, true, false)],
    [(10, true, false), (20, true, true), (30, false, true), (40, false, true), (50, true, true), (60, true, false),
     (70, true, true), (80, true, false)],
    [],
    [(33 / 2, true, true), (100, false, true), (33 / 2, true, false)],
    [(16, false, true), (16, false, true), (16, true, false)]] : List (List Step)).map fun tr =>
    line "sync" [("frames", Json.arr (tr.map fun f => Json.arr #[rin f.1, .bool f.2.1, .bool f.2.2]).toArray)]
      (Json.mkObj
        [("shown", Json.arr ((List.range tr.length).map fun k => ratWire (shownAt s0 tr k)).toArray),
         ("orig", Json.arr ((List.range tr.length).map fun k => ratWire (origAt 0 tr k)).toArray),
         ("local", ratWire (run s0 tr).loc)])

open Fw.Parts.PlatformShrinkOpt Fw.Site.Breakpoints in
/-- Lines of `platform-shrink.jsonl` (variant `mq`): the write decision over the gate, the computed value and the last
written value; the card's look per environment (the booleans `c860`, `le720` are Lean's evaluation of the generated
conditions at that environment) and inline value.

`planShrink` and `cardLook` in `logic.ts` are checked against these lines (`shrink.test.ts`). -/
def shrinkMqLines : List String :=
  let vals : List Rat := [0, 1 / 4, 1 / 2, 1]
  (([false, true] : List Bool).flatMap fun g => vals.flatMap fun sv => vals.map fun last =>
    line "planShrink" [("gated", .bool g), ("s", rin sv), ("last", rin last)]
      (Json.mkObj [("write", .bool (writeNow g sv last)), ("last", ratWire (lastAfter g sv last))])) ++
  (([(430, 430, true, false), (500, 500, false, false), (700, 700, false, false), (800, 800, false, false),
     (860, 860, false, false), (861, 861, false, false), (1000, 1000, true, true), (1200, 1200, true, true),
     (1201, 1201, true, true), (1280, 1280, false, false), (1280, 400, false, false)] :
      List (Nat × Nat × Bool × Bool)).flatMap fun (w, d, noHover, coarse) =>
    let env := exEnv w d (if noHover then .none else .hover) (if coarse then .coarse else .fine)
    vals.map fun v =>
      line "cardLook" [("width", jn w), ("deviceWidth", jn d), ("c860", .bool (c860.eval env)),
        ("le720", .bool (wLe720.eval env)), ("v", rin v)]
        (Json.mkObj [("scale", ratWire (look env v).1), ("radius", ratWire (look env v).2)]))

open Fw.Parts.PlatformFade in
def fadeLines (_ : Unit := ()) : List String :=
  let ends : List Rat := [0, 1 / 5, 1 / 4, 1 / 2, 11 / 20, 3 / 5, 3 / 4, 1]
  [line "const" [] (Json.mkObj [("blurMax", ratWire blurMax), ("duration", ratWire Fw.Parts.MorphTween.duration),
      ("fadeEnd", ratWire Fw.Parts.MorphTween.fadeEnd),
      ("easing", Json.arr #[ratWire easing.1, ratWire easing.2.1, ratWire easing.2.2.1, ratWire easing.2.2.2])])] ++
  (ends.flatMap fun f => ends.map fun t =>
    line "keyframes" [("from", rin f), ("to", rin t)]
      (Json.arr ((keyframes f t).map fun k =>
        Json.mkObj [("off", ratWire k.off), ("fade", ratWire k.val), ("blur", ratWire (blurOf k.val))]).toArray))

/-- The golden files of the platform parts: name and lines, in this order. -/
def files (_ : Unit := ()) : List (String × List String) :=
  [("platform.jsonl", platformLines), ("platform.sweep.jsonl", sweepLines), ("platform.glint.jsonl", glintLines),
   ("platform.marquee.jsonl", marqueeLines), ("platform.entries.jsonl", entriesLines),
   ("platform.scene.jsonl", sceneLines), ("engine.scene.jsonl", syncLines), ("platform-shrink.jsonl", shrinkMqLines),
   ("platform-fade.jsonl", fadeLines ())]

end Fw.Parts.PlatformGolden
