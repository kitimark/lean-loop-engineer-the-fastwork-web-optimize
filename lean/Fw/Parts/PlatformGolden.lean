import Lean.Data.Json
import Fw.Parts.PlatformSection
import Fw.Parts.PlatformSweep
import Fw.Parts.PlatformGlint
import Fw.Parts.PlatformMarquee
import Fw.Parts.PlatformEntries
import Fw.Parts.PlatformScene
import Fw.Parts.HiddenPausePlatform
/-!
# Golden vectors for the platform parts

`PlatformGolden.files` is the list of `(file name, lines)` that `Golden.lean` writes into
`packages/contracts/golden/parts/`: `platform.jsonl`, `platform.sweep.jsonl`, `platform.glint.jsonl`,
`platform.marquee.jsonl`, `platform.entries.jsonl`, `platform.scene.jsonl`, and `engine.scene.jsonl` (the hidden-pause
variant's clock on the platform section). Same line format and encodings as `Fw/Parts/Golden.lean`
(`Rat` inputs as exact JSON decimals, `Rat` outputs in the wire form `{"num","den"}`).
The `const` lines carry the constants the CSS Modules restate; a TS test checks the CSS text against them.
-/
namespace Fw.Parts.PlatformGolden
open Lean

/-- A rational input as an exact JSON decimal when its denominator divides $10^6$, else the wire object.

$$\forall q = \tfrac nd \in \mathbb{Q} \text{ (lowest terms, } d \ge 1):\quad \operatorname{rin}(q) = \begin{cases} \text{the JSON number with mantissa } n \cdot (10^6 / d) \text{ and exponent } 6 \text{, i.e. } n \cdot \tfrac{10^6}{d} \cdot 10^{-6} & d \mid 10^6 \\ \{\texttt{num}{:}\ \operatorname{str}(n),\ \texttt{den}{:}\ \operatorname{str}(d)\} & d \nmid 10^6 \end{cases}$$ -/
def rin (q : Rat) : Json :=
  if (1000000 % q.den) == 0 then .num ⟨q.num * ((1000000 / q.den : Nat) : Int), 6⟩
  else Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- The `Rat` output wire form: numerator and denominator of the reduced fraction as decimal strings.

$$\forall q = \tfrac nd \in \mathbb{Q} \text{ (lowest terms, } d \ge 1):\quad \operatorname{ratWire}(q) = \{\texttt{num}{:}\ \operatorname{str}(n),\ \texttt{den}{:}\ \operatorname{str}(d)\}$$ -/
def ratWire (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- One golden line: the compact JSON text (Lean's `compress`, keys sorted) of the object with keys `fn`, `in`, `out`.

$$\forall \mathit{fn}, \mathit{in}, \mathit{out}:\quad \operatorname{line}(\mathit{fn}, \mathit{in}, \mathit{out}) = \operatorname{compress}(\{\texttt{fn}{:}\ \mathit{fn},\ \texttt{in}{:}\ \operatorname{obj}(\mathit{in}),\ \texttt{out}{:}\ \mathit{out}\})$$ -/
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
/-- Lines of `platform.jsonl`: per viewport height and bottom the four position lines, then scale, then the stage
size per width, then one `const` line. Comprehensions run their generators left to right, outer to inner.

$$\begin{aligned} \mathrm{platformLines} = {} &[\, x \mid \mathit{vh} \in [600, 800, 900],\ b \in B,\ x \in [\operatorname{line}(\texttt{raw}, \{\texttt{bottom}{:}\ \operatorname{rin}(b), \texttt{vh}{:}\ \operatorname{rin}(\mathit{vh})\}, \operatorname{ratWire}(\operatorname{raw}(b, \mathit{vh}))), \\ &\qquad \operatorname{line}(\texttt{shrinking}, \{\texttt{bottom}{:}\ \operatorname{rin}(b), \texttt{vh}{:}\ \operatorname{rin}(\mathit{vh})\}, \operatorname{shrinking}(b, \mathit{vh})), \\ &\qquad \operatorname{line}(\texttt{shrink}, \{\texttt{reduced}{:}\ \bot, \texttt{bottom}{:}\ \operatorname{rin}(b), \texttt{vh}{:}\ \operatorname{rin}(\mathit{vh})\}, \operatorname{ratWire}(\operatorname{shrink}(\bot, b, \mathit{vh}))), \\ &\qquad \operatorname{line}(\texttt{shrink}, \{\texttt{reduced}{:}\ \top, \texttt{bottom}{:}\ \operatorname{rin}(b), \texttt{vh}{:}\ \operatorname{rin}(\mathit{vh})\}, \operatorname{ratWire}(\operatorname{shrink}(\top, b, \mathit{vh})))]\,] \\ \mathbin{+\!\!+} {} &[\, \operatorname{line}(\texttt{scale}, \{\texttt{s}{:}\ \operatorname{rin}(s)\}, \operatorname{ratWire}(\operatorname{scale}(s))) \mid s \in [0, \tfrac14, \tfrac12, \tfrac34, 1] \,] \\ \mathbin{+\!\!+} {} &[\, x \mid w \in [0, 320, 361, 640, 1000, 1280],\ x \in [\operatorname{line}(\texttt{stageHeight}, \{\texttt{w}{:}\ \operatorname{rin}(w)\}, \operatorname{ratWire}(\operatorname{stageHeight}(w))), \\ &\qquad \operatorname{line}(\texttt{artboardScale}, \{\texttt{w}{:}\ \operatorname{rin}(w)\}, \operatorname{ratWire}(\operatorname{artboardScale}(w)))]\,] \\ \mathbin{+\!\!+} {} &[\operatorname{line}(\texttt{const}, \{\}, \{\texttt{bgBlur}{:}\ \operatorname{ratWire}(\mathrm{bgBlur}),\ \texttt{bgOpacity}{:}\ \operatorname{ratWire}(\operatorname{bgOpacity}(\bot)),\ \texttt{bgOpacityQuote}{:}\ \operatorname{ratWire}(\operatorname{bgOpacity}(\top)), \\ &\qquad \texttt{grainOpacity}{:}\ \operatorname{ratWire}(\operatorname{grainOpacity}(\bot)),\ \texttt{grainOpacitySecure}{:}\ \operatorname{ratWire}(\operatorname{grainOpacity}(\top)),\ \texttt{grainTile}{:}\ \operatorname{ratWire}(\mathrm{grainTile})\})], \\ \text{with } B = {} &[-100, 0, 280, 300, 350, 400, 500, 600, 680, 700, 765, 770, 800, 900, 1200] \end{aligned}$$ -/
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
coordinates, the active flag, one `const` line. Comprehensions run their generators left to right, outer to inner.

$$\begin{aligned} \mathrm{sweepLines} = {} &[\, x \mid t \in T(\mathrm{period}),\ x \in [\operatorname{line}(\texttt{pos}, \{\texttt{t}{:}\ \operatorname{rin}(t)\}, \operatorname{ratWire}(\operatorname{pos}(t))),\ \operatorname{line}(\texttt{phase}, \{\texttt{t}{:}\ \operatorname{rin}(t)\}, \operatorname{ratWire}(\operatorname{phase}(t)))]\,] \\ \mathbin{+\!\!+} {} &[\, \operatorname{line}(\texttt{color}, \{\texttt{u}{:}\ \operatorname{rin}(\operatorname{imageU}(v, p))\}, \operatorname{rgbWire}(\operatorname{color}(\operatorname{imageU}(v, p)))) \mid v \in [0, \tfrac16, \tfrac13, \tfrac12, \tfrac23, \tfrac56, 1],\ p \in [0, \tfrac14, \tfrac12, \tfrac34, 1] \,] \\ \mathbin{+\!\!+} {} &[\, \operatorname{line}(\texttt{active}, \{\texttt{reduce}{:}\ r\}, \operatorname{active}(r)) \mid r \in [\bot, \top] \,] \\ \mathbin{+\!\!+} {} &[\operatorname{line}(\texttt{const}, \{\}, \{\texttt{periodMs}{:}\ \operatorname{ratWire}(\mathrm{period}),\ \texttt{stops}{:}\ [\, \operatorname{ratWire}(z) \mid z \in \mathrm{stops} \,]\})],\quad \mathrm{period} = 4000 \end{aligned}$$ -/
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
one `const` line. Comprehensions run their generators left to right, outer to inner.

$$\begin{aligned} \mathrm{marqueeLines} = {} &[\, x \mid t \in T(\mathrm{period}),\ w \in [1000, 2192, 4048],\ x \in [\operatorname{line}(\texttt{offsetLeft}, \{\texttt{w}{:}\ \operatorname{rin}(w), \texttt{t}{:}\ \operatorname{rin}(t)\}, \operatorname{ratWire}(\operatorname{offsetLeft}(w, t))), \\ &\qquad \operatorname{line}(\texttt{offsetRight}, \{\texttt{w}{:}\ \operatorname{rin}(w), \texttt{t}{:}\ \operatorname{rin}(t)\}, \operatorname{ratWire}(\operatorname{offsetRight}(w, t)))]\,] \\ \mathbin{+\!\!+} {} &[\, \operatorname{line}(\texttt{running}, \{\texttt{reduce}{:}\ r\}, \operatorname{running}(r)) \mid r \in [\bot, \top] \,] \mathbin{+\!\!+} [\operatorname{line}(\texttt{const}, \{\}, \{\texttt{periodMs}{:}\ \operatorname{ratWire}(\mathrm{period})\})],\quad \mathrm{period} = 90000 \end{aligned}$$ -/
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
/-- A glint state as JSON (an output: times in the wire form).

$$\forall s = (h, g, v, \tau, t_0):\quad \operatorname{stJson}(s) = \{\texttt{h}{:}\ h,\ \texttt{g}{:}\ g,\ \texttt{v}{:}\ v,\ \texttt{timer}{:}\ (\tau = \operatorname{some}(d)\ ?\ \operatorname{ratWire}(d) : \texttt{null}),\ \texttt{t0}{:}\ (t_0 = \operatorname{some}(d')\ ?\ \operatorname{ratWire}(d') : \texttt{null})\}$$ -/
def stJson (s : St) : Json :=
  Json.mkObj [("h", .bool s.h), ("g", .bool s.g), ("v", .bool s.v),
    ("timer", match s.timer with | some d => ratWire d | none => .null),
    ("t0", match s.t0 with | some d => ratWire d | none => .null)]

open Fw.Parts.PlatformGlint in
/-- A glint state as an input (times as exact decimals).

$$\forall s = (h, g, v, \tau, t_0):\quad \operatorname{stIn}(s) = \{\texttt{h}{:}\ h,\ \texttt{g}{:}\ g,\ \texttt{v}{:}\ v,\ \texttt{timer}{:}\ (\tau = \operatorname{some}(d)\ ?\ \operatorname{rin}(d) : \texttt{null}),\ \texttt{t0}{:}\ (t_0 = \operatorname{some}(d')\ ?\ \operatorname{rin}(d') : \texttt{null})\}$$ -/
def stIn (s : St) : Json :=
  Json.mkObj [("h", .bool s.h), ("g", .bool s.g), ("v", .bool s.v),
    ("timer", match s.timer with | some d => rin d | none => .null),
    ("t0", match s.t0 with | some d => rin d | none => .null)]

open Fw.Parts.PlatformGlint in
/-- An event as JSON input.

$$\forall r \in \mathbb{Q},\ \forall b \in \mathbb{B}:\quad \operatorname{evIn}(\operatorname{ratio}(r)) = \{\texttt{kind}{:}\ \texttt{ratio},\ \texttt{ratio}{:}\ \operatorname{rin}(r)\},\quad \operatorname{evIn}(\operatorname{reduced}(b)) = \{\texttt{kind}{:}\ \texttt{reduced},\ \texttt{value}{:}\ b\},\quad \operatorname{evIn}(\mathrm{fire}) = \{\texttt{kind}{:}\ \texttt{fire}\}$$ -/
def evIn : Ev → Json
  | .ratio r => Json.mkObj [("kind", .str "ratio"), ("ratio", rin r)]
  | .reduced b => Json.mkObj [("kind", .str "reduced"), ("value", .bool b)]
  | .fire => Json.mkObj [("kind", .str "fire")]

open Fw.Parts.PlatformGlint in
/-- Lines of `platform.glint.jsonl`: dash samples, the step function over states, times and events, the view, one
`const` line. Comprehensions run their generators left to right, outer to inner.

$$\begin{aligned} \mathrm{glintLines} = {} &[\, \operatorname{line}(\texttt{sample}, \{\texttt{side}{:}\ \operatorname{sideName}(s), \texttt{elapsed}{:}\ \operatorname{rin}(e)\}, [\operatorname{ratWire}(\operatorname{sample}(s, e)_1), \operatorname{ratWire}(\operatorname{sample}(s, e)_2)]) \mid s \in [\mathrm{left}, \mathrm{right}],\ e \in E \,] \\ \mathbin{+\!\!+} {} &[\, \operatorname{line}(\texttt{step}, \{\texttt{state}{:}\ \operatorname{stIn}(s), \texttt{now}{:}\ \operatorname{rin}(n), \texttt{event}{:}\ \operatorname{evIn}(e)\}, \operatorname{stJson}(\operatorname{step}(s, n, e))) \mid s \in S,\ n \in [0, 600, 1000, 2500],\ e \in \mathit{Ev} \,] \\ \mathbin{+\!\!+} {} &[\, \operatorname{line}(\texttt{view}, \{\texttt{state}{:}\ \operatorname{stIn}(s), \texttt{side}{:}\ \operatorname{sideName}(d), \texttt{now}{:}\ \operatorname{rin}(n)\}, [\operatorname{ratWire}(\operatorname{view}(s, d, n)_1), \operatorname{ratWire}(\operatorname{view}(s, d, n)_2)]) \\ &\qquad \mid s \in [\operatorname{init}(\bot), \operatorname{step}(s_1, 1000, \mathrm{fire})],\ d \in [\mathrm{left}, \mathrm{right}],\ n \in [1000, 1500, 3000, 6500] \,] \\ \mathbin{+\!\!+} {} &[\operatorname{line}(\texttt{const}, \{\}, \{\texttt{durMs}{:}\ \operatorname{ratWire}(\mathrm{dur}),\ \texttt{startDelayMs}{:}\ \operatorname{ratWire}(\mathrm{startDelay}),\ \texttt{minRatio}{:}\ \operatorname{ratWire}(\mathrm{minRatio})\})], \\ \text{with } E = {} &[0, 1, 250, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500, 4999, 5000, 5001, 7500, 12345], \\ s_1 = {} &\operatorname{step}(\operatorname{init}(\bot), 0, \operatorname{ratio}(0.4)), \\ S = {} &[\operatorname{init}(\bot), \operatorname{init}(\top), s_1, \operatorname{step}(s_1, 1000, \mathrm{fire}), \operatorname{step}(s_1, 500, \mathrm{fire}), \operatorname{step}(s_1, 100, \operatorname{reduced}(\top))], \\ \mathit{Ev} = {} &[\operatorname{ratio}(0), \operatorname{ratio}(0.34), \operatorname{ratio}(0.35), \operatorname{ratio}(0.6), \operatorname{reduced}(\bot), \operatorname{reduced}(\top), \mathrm{fire}] \end{aligned}$$ -/
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
/-- A view as JSON: the three numbers as JSON integers, the three flags as booleans.

$$\forall v = (\ell, i, s, a, r, c):\quad \operatorname{viewJson}(v) = \{\texttt{len}{:}\ \ell,\ \texttt{topic}{:}\ i,\ \texttt{shown}{:}\ s,\ \texttt{leaving}{:}\ a,\ \texttt{results}{:}\ r,\ \texttt{caret}{:}\ c\}$$ -/
def viewJson (v : View) : Json :=
  Json.mkObj [("len", jn v.len), ("topic", jn v.topic), ("shown", jn v.shown), ("leaving", .bool v.leaving),
    ("results", .bool v.results), ("caret", .bool v.caret)]

open Fw.Parts.PlatformEntries in
/-- The entries of the live stages with their table name, in a fixed order (18 pairs).

$$\begin{aligned} \mathrm{table} = [\ &(\texttt{credCard0}, \operatorname{credCard}(0)),\ (\texttt{credCard3}, \operatorname{credCard}(3)),\ (\texttt{profilePhone}, \mathrm{profilePhone}),\ (\texttt{rings}, \mathrm{rings}), \\ &(\texttt{faceLeft}, \mathrm{faceLeft}),\ (\texttt{faceRight}, \mathrm{faceRight}),\ (\texttt{dash}, \mathrm{dash}),\ (\texttt{shield}, \mathrm{shield}),\ (\texttt{logo}, \mathrm{logo}), \\ &(\texttt{flag1}, \operatorname{flag}(1)),\ (\texttt{flag3}, \operatorname{flag}(3)),\ (\texttt{flag6}, \operatorname{flag}(6)),\ (\texttt{invoiceCard}, \mathrm{invoiceCard}),\ (\texttt{orderRow0}, \operatorname{orderRow}(0)), \\ &(\texttt{orderRow3}, \operatorname{orderRow}(3)),\ (\texttt{askIn0}, \operatorname{askIn}(0)),\ (\texttt{askIn2}, \operatorname{askIn}(2)),\ (\texttt{askOut1}, \operatorname{askOut}(1))\ ] \end{aligned}$$ -/
def entryTable : List (String × Entry) :=
  [("credCard0", credCard 0), ("credCard3", credCard 3), ("profilePhone", profilePhone), ("rings", rings),
   ("faceLeft", faceLeft), ("faceRight", faceRight), ("dash", dash), ("shield", shield), ("logo", logo),
   ("flag1", flag 1), ("flag3", flag 3), ("flag6", flag 6), ("invoiceCard", invoiceCard), ("orderRow0", orderRow 0),
   ("orderRow3", orderRow 3), ("askIn0", askIn 0), ("askIn2", askIn 2), ("askOut1", askOut 1)]

open Fw.Parts.PlatformEntries in
/-- Lines of `platform.entries.jsonl`: the spring ease, every table entry's progress, the count-up, the search view,
one `const` line. Comprehensions run their generators left to right, outer to inner; $\mathrm{ease}$ is on the
spring curve.

$$\begin{aligned} \mathrm{entriesLines} = {} &[\, \operatorname{line}(\texttt{ease}, \{\texttt{x}{:}\ \operatorname{rin}(x)\}, \operatorname{ratWire}(\operatorname{ease}_{\mathrm{spring}}(x))) \mid x \in [-1, 0, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 1, 1.5] \,] \\ \mathbin{+\!\!+} {} &[\, \operatorname{line}(\texttt{progress}, \{\texttt{entry}{:}\ k, \texttt{t}{:}\ \operatorname{rin}(t)\}, \operatorname{ratWire}(\operatorname{progress}(e, t))) \mid (k, e) \in \mathrm{table},\ t \in [0, 30, 60, 100, 180, 300, 420, 560, 700, 1000, 1400] \,] \\ \mathbin{+\!\!+} {} &[\, \operatorname{line}(\texttt{countAt}, \{\texttt{n}{:}\ m, \texttt{t}{:}\ \operatorname{rin}(t)\}, \operatorname{countAt}(m, t)) \mid (t, m) \in [(40, 240), (5, 240), (500, 43), (0, 5), (1000, 48), (1500, 240), (9999, 5), (180, 5)] \,] \\ \mathbin{+\!\!+} {} &[\, \operatorname{line}(\texttt{askView}, \{\texttt{lens}{:}\ [23, 25, 22, 20], \texttt{t}{:}\ \operatorname{rin}(t)\}, \operatorname{viewJson}(\operatorname{askView}([23, 25, 22, 20], t))) \mid t \in A \,] \\ \mathbin{+\!\!+} {} &[\operatorname{line}(\texttt{const}, \{\}, \{\texttt{spring}{:}\ [\operatorname{ratWire}(\tfrac{4}{25}), \operatorname{ratWire}(1), \operatorname{ratWire}(\tfrac{3}{10}), \operatorname{ratWire}(1)],\ \texttt{countDelayMs}{:}\ \operatorname{ratWire}(180),\ \texttt{countDurMs}{:}\ \operatorname{ratWire}(1080), \\ &\qquad \texttt{askLeadMs}{:}\ \operatorname{ratWire}(700),\ \texttt{typeStepMs}{:}\ \operatorname{ratWire}(32),\ \texttt{eraseStepMs}{:}\ \operatorname{ratWire}(18),\ \texttt{holdMs}{:}\ \operatorname{ratWire}(3000), \\ &\qquad \texttt{firstRevealMs}{:}\ \operatorname{ratWire}(280),\ \texttt{swapMs}{:}\ \operatorname{ratWire}(700),\ \texttt{entries}{:}\ [\, \{\texttt{name}{:}\ k, \texttt{keyframes}{:}\ \mathit{name}_e, \texttt{durMs}{:}\ \operatorname{ratWire}(D_e), \texttt{delayMs}{:}\ \operatorname{ratWire}(d_e), \\ &\qquad\quad \texttt{props}{:}\ [\, \{\texttt{key}{:}\ q, \texttt{from}{:}\ \operatorname{ratWire}(a), \texttt{to}{:}\ \operatorname{ratWire}(b)\} \mid (q, a, b) \in \mathit{props}_e \,]\} \mid (k, e) \in \mathrm{table} \,]\})], \\ \text{with } A = {} &[0, 699, 700, 731, 732, 1435, 1436, 1715, 1716, 2000, 4715, 4716, 4765, 5415, 5416, 6000, 9000, 12000, 20000, 33333, 50000, 80000, 123456], \\ &e = (\mathit{name}_e, D_e, d_e, \mathit{props}_e) \text{ and the integers } m, \operatorname{countAt}(m, t) \text{ and the lens as JSON integers} \end{aligned}$$ -/
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
/-- Lines of `platform.scene.jsonl`: the scene value at ten rects around the two edges $b = -h$ and $t = 2h$, then one
`const` line with the attribute name, its two values, the observer margin and the rule's property.

$$\begin{aligned} \mathrm{sceneLines} = {} &[\operatorname{line}(\texttt{scene}, \{\texttt{top}{:}\ t, \texttt{bottom}{:}\ b, \texttt{vh}{:}\ h\}, \operatorname{sceneOf}(t, b, h)) \mid (t, b, h) \in R] \\ \mathbin{+\!\!+} {} &[\operatorname{line}(\texttt{const}, \{\}, \{\texttt{attr}{:}\ \texttt{data-fw-scene},\ \texttt{active}{:}\ \operatorname{attr}(\top),\ \texttt{paused}{:}\ \operatorname{attr}(\bot),\ \texttt{rootMargin}{:}\ \texttt{100\% 0px},\ \texttt{playState}{:}\ \texttt{paused}\})], \\ R = {} &[(0, 800, 900), (-5000, -901, 900), (-5000, -900, 900), (1800, 2600, 900), (1801, 2600, 900), \\ &\ (-1000, -500, 900), (3000, 3800, 900), (-300, 100, 400), (801, 1200, 400), (800, 1200, 400)] \end{aligned}$$

Each rect is (top, bottom, viewport height); the lines follow $R$'s order. -/
def sceneLines : List String :=
  (([(0, 800, 900), (-5000, -901, 900), (-5000, -900, 900), (1800, 2600, 900), (1801, 2600, 900), (-1000, -500, 900),
     (3000, 3800, 900), (-300, 100, 400), (801, 1200, 400), (800, 1200, 400)] : List (Rat × Rat × Rat)).map fun (t, b, h) =>
    line "scene" [("top", rin t), ("bottom", rin b), ("vh", rin h)] (.str (sceneOf t b h))) ++
  [line "const" [] (Json.mkObj
    [("attr", .str "data-fw-scene"), ("active", .str (attr true)), ("paused", .str (attr false)),
     ("rootMargin", .str "100% 0px"), ("playState", .str "paused")])]

open Fw.Parts.HiddenPausePlatform in
/-- Lines of `engine.scene.jsonl`: for each trace, from the synced start $s_0 = (0, 0, \bot, 0)$ and $\ell_0 = 0$, the
variant's shown local time and the original's at every frame, and the variant's local time at the end.

$$\begin{aligned} \mathrm{syncLines} = {} &[\operatorname{line}(\texttt{sync}, \{\texttt{frames}{:}\ [[\Delta, a, h] \mid (\Delta, a, h) \in F]\}, \{\texttt{shown}{:}\ [\operatorname{shownAt}(s_0, F, k) \mid k \in [0, |F|)],\ \texttt{orig}{:}\ [\operatorname{origAt}(0, F, k) \mid k \in [0, |F|)],\ \texttt{local}{:}\ \operatorname{run}(s_0, F).\ell\}) \mid F \in S], \\ S = {} &[\ [(16, \top, \bot), (16, \top, \top), (16, \top, \top), (16, \top, \bot)],\ [(16, \top, \top), (16, \bot, \top), (16, \top, \top), (16, \top, \bot)], \\ &\ \ [(10, \top, \bot), (20, \top, \top), (30, \bot, \top), (40, \bot, \top), (50, \top, \top), (60, \top, \bot), (70, \top, \top), (80, \top, \bot)], \\ &\ \ [\,],\ [(16.5, \top, \top), (100, \bot, \top), (16.5, \top, \bot)],\ [(16, \bot, \top), (16, \bot, \top), (16, \top, \bot)]\ ] \end{aligned}$$

$\Delta$ is an exact JSON decimal, times are in the `Rat` wire form, $a$ and $h$ are JSON booleans. -/
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

/-- The seven golden files of the platform parts and the engine.scene variant on the platform: name and lines, in this
order.

$$\begin{aligned} \mathrm{files} = [\ &(\texttt{platform.jsonl}, \mathrm{platformLines}),\ (\texttt{platform.sweep.jsonl}, \mathrm{sweepLines}),\ (\texttt{platform.glint.jsonl}, \mathrm{glintLines}),\ (\texttt{platform.marquee.jsonl}, \mathrm{marqueeLines}), \\ &(\texttt{platform.entries.jsonl}, \mathrm{entriesLines}),\ (\texttt{platform.scene.jsonl}, \mathrm{sceneLines}),\ (\texttt{engine.scene.jsonl}, \mathrm{syncLines})\ ] \end{aligned}$$

Seven files, each written whole. -/
def files (_ : Unit := ()) : List (String × List String) :=
  [("platform.jsonl", platformLines), ("platform.sweep.jsonl", sweepLines), ("platform.glint.jsonl", glintLines),
   ("platform.marquee.jsonl", marqueeLines), ("platform.entries.jsonl", entriesLines),
   ("platform.scene.jsonl", sceneLines), ("engine.scene.jsonl", syncLines)]

end Fw.Parts.PlatformGolden
