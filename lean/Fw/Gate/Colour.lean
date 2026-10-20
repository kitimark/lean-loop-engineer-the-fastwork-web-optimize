import Lean.Data.Json
import Fw.Gate.Trajectory
import Fw.Gate.Settle
/-!
# Trajectory kit: one colour space

The trajectory kit (`packages/gate-breakpoints/src/trajectory/kit.mjs`, `colour`) records every colour reading as
`[r, g, b, a]`: sRGB channels on the 0..255 scale and alpha on the same scale, each times 1000 and rounded. The judge
(`Fw.Gate.Trajectory.judgeColour`) compares those numbers channel by channel and expects one space for both arms.

The engines do not serialise a computed colour in one space. A colour at rest is `rgb(r, g, b)` or `rgba(r, g, b, a)`
(legacy syntax); a colour in the middle of a transition between two colours that interpolate in another space is
`oklab(L a b / alpha)`, `oklch(...)`, `lab(...)`, `lch(...)` or `color(srgb r g b / alpha)`.

* WebKit 862f17d: `Source/WebCore/platform/graphics/ColorSerialization.cpp` `serializationForCSS` (lines 157-162 pick the
  type; 222-243 `color(...)` and named-function forms; 381-384 extended sRGB; 444-447 `lch`; 461-464 `lab`; 512-515 `oklch`;
  529-532 `oklab`; 580-586 and 620-634 `rgb`/`rgba`, alpha as 8 bit with 1 to 3 digits; 398-407 `hsl` goes through sRGB).
  Numbers are CSS numbers (`FormattedCSSNumber`, 6 significant digits). Conversion matrices
  `Source/WebCore/platform/graphics/ColorConversion.cpp` (OKLab 274-308, Lab 205-235, polar 40-73, HSL 118-198) and the
  Bradford D50 to D65 matrix `ColorConversion.h` 250-255.
* Chromium f842f52: `third_party/blink/renderer/platform/graphics/color.cc` `SerializeAsCSSColor` 1131-1137: legacy colour
  spaces `SerializeLegacyColorAsCSSColor` 1045-1101 (`rgb(`/`rgba(`, integer channels, alpha rounded to 8 bit and then to 2
  or 3 decimals); others `SerializeInternal` 1103-1129 (`oklab(` and `lab(` lightness first, else `color(srgb ...`, numbers
  to 6 significant digits, ` / alpha` only when alpha is not 1). Conversions `ui/gfx/color_conversions.cc` 73-90 (Lab),
  227-249 (Oklab), 265-272 (polar), 282-287 (XYZ D50 to sRGB), 296-309 (HSL).
* CSS Color 4, the sample code of "Converting Colors" (`https://www.w3.org/TR/css-color-4/#color-conversion-code`): both
  engines implement these formulas, so the kit does too.

This file specifies the conversion to that one space in `Float` (it generates the golden file the kit is checked against,
`packages/contracts/golden/gate/trajectory-colour.jsonl`) and proves what the judge needs: the conversion error stays
inside the judge's colour tolerance.

```
cd lean && lake env lean --run scripts/ColourGolden.lean           # write the file
cd lean && lake env lean --run scripts/ColourGolden.lean --check ../packages/contracts/golden/gate/trajectory-colour.jsonl
```
-/
namespace Fw.Gate.Colour
open Lean Fw.Gate.Trajectory

/-! ## The error budget the judge depends on -/

/-- The error of one channel reading against the true colour, in thousandths of a channel level (500 = half a level).

Where it comes from: a legacy `rgb` channel is rounded to an integer by the engine, at most half a level (500). The other
sources are far smaller: an engine prints a component with 6 significant digits (WebKit `FormattedCSSNumber`, Chromium
`AppendNumber(.., 6)`), and the matrices differ between the engines' recalculated ones and Ottosson's own. The golden test
(`kit-colour.test.mjs`) measures both together on a grid of the sRGB cube: 8 (of 500) at most. -/
def chanErr : Int := 500

/-- The error of the alpha reading against the true alpha, in thousandths of a level on the 0..255 scale.

An engine rounds alpha to 8 bit (at most 0.5 level, 500). It then prints two decimals when a two-decimal number reads back
as the same 8 bit value, which can sit another 0.5 level away from it (500); otherwise three decimals (at most 128 more).
Worst case 1000. The golden test measures 765 on the sweep of 1001 alphas, so 1000 is a bound, not a fit. -/
def alphaErr : Int := 1000

/-- The error bound of component `j` of a reading `[r, g, b, a]`. -/
def errAt (j : Nat) : Int := if j < 3 then chanErr else alphaErr

/-- A reading `x` is within `e` of the truth `t`. -/
def Within (e t x : Int) : Prop := t - e ≤ x ∧ x ≤ t + e

/-- Every error bound is at most the alpha bound. -/
theorem errAt_le (j : Nat) : errAt j ≤ alphaErr := by
  unfold errAt chanErr alphaErr
  split <;> omega

/-- Two readings of one colour, each inside the error budget, differ by less than the judge's colour tolerance: the
budget leaves room (`2 * 628 = 1256` of 2000). -/
theorem budget_inside_tol (j : Nat) : 2 * errAt j ≤ tol .colour := by
  have h := errAt_le j
  have ht : tol .colour = 2000 := by decide
  unfold alphaErr at h
  omega

/-- **The judge passes two readings of one colour.** The original is read in one space (say `oklab`) and the rewrite in
another (`rgb`); both are converted to sRGB x 1000. When each converted component is within its error bound of the true
colour, `judgeVal` passes them. So a colour unit that fails on a converted reading is a difference of more than the budget
from the original's colour, not the colour space. -/
theorem judge_colour_same_truth (xs ys ts : List Int)
    (hx : xs.length = ts.length) (hy : ys.length = ts.length)
    (hxe : ∀ j, j < ts.length → Within (errAt j) (ts.getD j 0) (xs.getD j 0))
    (hye : ∀ j, j < ts.length → Within (errAt j) (ts.getD j 0) (ys.getD j 0)) :
    judgeVal .colour [.num xs] (.num ys) = .pass := by
  have hband : inBand (tol .colour) [xs] ys = true := by
    unfold inBand
    simp only [List.all_eq_true, List.mem_range, List.map_cons, List.map_nil, List.min?_cons, List.max?_cons,
      List.min?_nil, List.max?_nil]
    intro j hj
    have hj' : j < ts.length := hy ▸ hj
    have h1 := hxe j hj'
    have h2 := hye j hj'
    have h3 := budget_inside_tol j
    unfold Within at h1 h2
    simp only [List.getD_eq_getElem?_getD] at h1 h2
    simp
    omega
  unfold judgeVal
  simp [numsOf, hx, hy, hband]

/-! ## The conversion, in `Float` -/

/-- A colour written in a CSS function, by the function. -/
inductive Fn
  /-- `rgb(r g b)`, channels 0 to 255. -/
  | rgb
  /-- `hsl(h s% l%)`, hue in degrees, saturation and lightness in percent. -/
  | hsl
  /-- `color(srgb r g b)`, channels 0 to 1. -/
  | srgb
  /-- `color(srgb-linear r g b)`, channels 0 to 1. -/
  | srgbLinear
  /-- `lab(L a b)`, D50. -/
  | lab
  /-- `lch(L C h)`, D50. -/
  | lch
  /-- `oklab(L a b)`. -/
  | oklab
  /-- `oklch(L C h)`. -/
  | oklch
  deriving DecidableEq, Repr

/-- A 3 by 3 matrix times a vector. -/
def mul3 (m : Array Float) (v : Float × Float × Float) : Float × Float × Float :=
  let (x, y, z) := v
  (m[0]! * x + m[1]! * y + m[2]! * z, m[3]! * x + m[4]! * y + m[5]! * z, m[6]! * x + m[7]! * y + m[8]! * z)

/-- The sRGB transfer function, sign-preserving (CSS Color 4 `gam_sRGB`, an extended range colour keeps its sign). -/
def encode (c : Float) : Float :=
  let a := c.abs
  let e := if a > 0.0031308 then 1.055 * Float.pow a (1.0 / 2.4) - 0.055 else 12.92 * a
  if c < 0.0 then -e else e

/-- Linear sRGB to encoded sRGB. -/
def encode3 (v : Float × Float × Float) : Float × Float × Float := (encode v.1, encode v.2.1, encode v.2.2)

/-- XYZ D65 to linear sRGB (CSS Color 4 `XYZ_to_lin_sRGB`). -/
def xyzD65ToLinSrgb : Array Float :=
  #[3.2409699419045226, -1.537383177570094, -0.4986107602930034,
    -0.9692436362808796, 1.8759675015077202, 0.04155505740717559,
    0.05563007969699366, -0.20397695888897652, 1.0569715142428786]

/-- XYZ D50 to XYZ D65, Bradford (WebKit `ColorConversion.h` 250-255, CSS Color 4 `D50_to_D65`). -/
def xyzD50ToD65 : Array Float :=
  #[0.955473421488075, -0.02309845494876471, 0.06325924320057072,
    -0.0283697093338637, 1.0099953980813041, 0.021041441191917323,
    0.012314014864481998, -0.020507649298898964, 1.330365926242124]

/-- Linear LMS to XYZ D65 (WebKit `ColorConversion.cpp` 282-286, the matrices recalculated for one reference white). -/
def lmsToXyzD65 : Array Float :=
  #[1.2268798758459243, -0.5578149944602171, 0.2813910456659647,
    -0.0405757452148008, 1.1122868032803170, -0.0717110580655164,
    -0.0763729366746601, -0.4214933324022432, 1.5869240198367816]

/-- Oklab to non-linear LMS (WebKit `ColorConversion.cpp` 288-292). -/
def oklabToLms : Array Float :=
  #[1.0, 0.3963377773761749, 0.2158037573099136,
    1.0, -0.1055613458156586, -0.0638541728258133,
    1.0, -0.0894841775298119, -1.2914855480194092]

/-- Oklab to encoded sRGB, not clamped. -/
def oklabToSrgb (l a b : Float) : Float × Float × Float :=
  let (x, y, z) := mul3 oklabToLms (l, a, b)
  encode3 (mul3 xyzD65ToLinSrgb (mul3 lmsToXyzD65 (x * x * x, y * y * y, z * z * z)))

/-- Lab (D50) to encoded sRGB, not clamped (WebKit `ColorConversion.cpp` 205-235, CSS Color 4 `Lab_to_XYZ`). -/
def labToSrgb (l a b : Float) : Float × Float × Float :=
  let e := 216.0 / 24389.0
  let k := 24389.0 / 27.0
  let f1 := (l + 16.0) / 116.0
  let f0 := f1 + a / 500.0
  let f2 := f1 - b / 200.0
  let xz := fun (t : Float) => if t * t * t > e then t * t * t else (116.0 * t - 16.0) / k
  let y := if l > k * e then f1 * f1 * f1 else l / k
  let x := 0.3457 / 0.3585 * xz f0
  let z := (1.0 - 0.3457 - 0.3585) / 0.3585 * xz f2
  encode3 (mul3 xyzD65ToLinSrgb (mul3 xyzD50ToD65 (x, y, z)))

/-- The rectangular form of a polar pair: chroma and hue in degrees. -/
def polar (c h : Float) : Float × Float :=
  let r := h * 3.141592653589793 / 180.0
  (c * Float.cos r, c * Float.sin r)

/-- HSL to encoded sRGB (CSS Color 4 `hslToRgb`), saturation and lightness as fractions. -/
def hslToSrgb (h s l : Float) : Float × Float × Float :=
  let a := s * (if l < 1.0 - l then l else 1.0 - l)
  let f := fun (n : Float) =>
    let hh := h / 30.0 + n
    let k := hh - 12.0 * Float.floor (hh / 12.0)
    let m := if k - 3.0 < 9.0 - k then k - 3.0 else 9.0 - k
    let m := if m < 1.0 then m else 1.0
    l - a * (if m > -1.0 then m else -1.0)
  (f 0.0, f 8.0, f 4.0)

/-- The three channels of a colour written in `fn`, as encoded sRGB on the 0 to 1 scale. -/
def toSrgb (fn : Fn) (c : List Float) : Float × Float × Float :=
  let c0 := c.getD 0 0.0
  let c1 := c.getD 1 0.0
  let c2 := c.getD 2 0.0
  match fn with
  | .rgb => (c0 / 255.0, c1 / 255.0, c2 / 255.0)
  | .hsl => hslToSrgb c0 (c1 / 100.0) (c2 / 100.0)
  | .srgb => (c0, c1, c2)
  | .srgbLinear => encode3 (c0, c1, c2)
  | .lab => labToSrgb c0 c1 c2
  | .lch => let (a, b) := polar c1 c2; labToSrgb c0 a b
  | .oklab => oklabToSrgb c0 c1 c2
  | .oklch => let (a, b) := polar c1 c2; oklabToSrgb c0 a b

/-- A value times 255000, rounded half up: a channel or an alpha on the kit's scale. -/
def q255 (x : Float) : Int := (Float.floor (x * 255000.0 + 0.5)).toInt64.toInt

/-- The kit's reading of a colour: `[r, g, b, alpha]` times 1000 on the 0 to 255 scale. -/
def reading (fn : Fn) (c : List Float) (alpha : Float) : List Int :=
  let (r, g, b) := toSrgb fn c
  [q255 r, q255 g, q255 b, q255 alpha]

/-! ## Golden vectors -/

/-- A vector: the name, the function, the components as written, the alpha (`none`: not written) and the syntax (legacy
commas or the modern slash). -/
structure Vec where
  name : String
  fn : Fn
  c : List Float
  alpha : Option Float
  legacy : Bool

/-- The function name as the engines print it. -/
def Vec.head (v : Vec) : String :=
  match v.fn with
  | .rgb => if v.legacy && v.alpha.isSome then "rgba" else "rgb"
  | .hsl => if v.legacy && v.alpha.isSome then "hsla" else "hsl"
  | .srgb => "color(srgb"
  | .srgbLinear => "color(srgb-linear"
  | .lab => "lab"
  | .lch => "lch"
  | .oklab => "oklab"
  | .oklch => "oklch"

/-- The colour as a string, the way a computed style carries it. -/
def Vec.text (v : Vec) : String :=
  let isColor := v.fn == .srgb || v.fn == .srgbLinear
  let sep := if v.legacy then ", " else " "
  let pct := fun (i : Nat) (x : Float) => if v.fn == .hsl && i > 0 then toString x ++ "%" else toString x
  let comps := String.intercalate sep ((v.c.zipIdx.map fun (x, i) => pct i x))
  let tail := match v.alpha with
    | none => ""
    | some a => (if v.legacy then ", " else " / ") ++ toString a
  if isColor then v.head ++ " " ++ comps ++ tail ++ ")" else v.head ++ "(" ++ comps ++ tail ++ ")"

/-- The vectors: the colours the probe met, one of each function and syntax, and edges. -/
def vecs : List Vec := [
  ⟨"white at rest", .rgb, [255.0, 255.0, 255.0], none, true⟩,
  ⟨"rgba with alpha", .rgb, [10.0, 20.0, 30.0], some 0.5, true⟩,
  ⟨"rgb modern syntax", .rgb, [43.0, 49.0, 59.0], some 0.102, false⟩,
  ⟨"hsl", .hsl, [210.0, 50.0, 40.0], none, false⟩,
  ⟨"hsla legacy", .hsl, [120.0, 100.0, 25.0], some 0.75, true⟩,
  ⟨"hsl grey", .hsl, [0.0, 0.0, 50.0], none, false⟩,
  ⟨"srgb function", .srgb, [1.0, 0.5, 0.0], some 0.25, false⟩,
  ⟨"srgb function opaque", .srgb, [0.2, 0.4, 0.6], none, false⟩,
  ⟨"srgb-linear", .srgbLinear, [0.5, 0.25, 0.01], none, false⟩,
  ⟨"oklab white", .oklab, [1.0, 0.0, 0.0], none, false⟩,
  ⟨"oklab black", .oklab, [0.0, 0.0, 0.0], none, false⟩,
  ⟨"oklab late in a close (the observed 989)", .oklab, [0.989, 0.0, 0.0], some 0.10344, false⟩,
  ⟨"oklab red", .oklab, [0.627955, 0.224863, 0.125846], none, false⟩,
  ⟨"oklab dark panel", .oklab, [0.3, -0.01, -0.03], some 0.9, false⟩,
  ⟨"oklab out of gamut", .oklab, [0.9, 0.25, -0.25], none, false⟩,
  ⟨"oklch", .oklch, [0.7, 0.15, 200.0], none, false⟩,
  ⟨"oklch hue wrap", .oklch, [0.5, 0.2, 350.0], some 0.4, false⟩,
  ⟨"lab", .lab, [50.0, 40.0, 30.0], none, false⟩,
  ⟨"lab red", .lab, [54.2905, 80.8049, 69.8910], none, false⟩,
  ⟨"lab dark", .lab, [5.0, 1.0, -2.0], some 0.3, false⟩,
  ⟨"lch", .lch, [70.0, 40.0, 120.0], none, false⟩,
  ⟨"lch alpha", .lch, [30.0, 60.0, 300.0], some 0.6, false⟩
]

/-- One golden line: the string, its reading, and the vector's name. -/
def goldenOf (v : Vec) : String :=
  (Json.mkObj [("kind", "colour"), ("name", v.name), ("in", v.text),
    ("out", toJson (reading v.fn v.c (v.alpha.getD 1.0)))]).compress

/-- The error budget and the slack between the kit and the Lean `Float` reference. -/
def boundsLine : String :=
  (Json.mkObj [("kind", "bounds"), ("chanErr", toJson chanErr), ("alphaErr", toJson alphaErr), ("slack", toJson (1 : Int)),
    ("tolColour", toJson (tol .colour))]).compress

/-- Strings the kit leaves as they are: not a colour it converts. -/
def passthrough : List String := ["", "transparent", "color(display-p3 0.5 0.5 0.5)", "currentcolor"]

/-- The golden lines. -/
def goldenLines : List String :=
  [boundsLine] ++ vecs.map goldenOf ++ passthrough.map fun (s : String) =>
    (Json.mkObj [("kind", "string"), ("in", Json.str s)]).compress

/-- The golden file text. -/
def goldenText (_ : Unit := ()) : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

/-- Print the golden, or with `--check <file>` compare its bytes; exit 1 when they differ. -/
def run (args : List String) : IO UInt32 := do
  match Fw.Gate.Settle.argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"trajectory-colour golden: {path} is up to date ({goldenLines.length} lines)"
      return 0
    IO.eprintln s!"trajectory-colour golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print goldenText
    return 0

end Fw.Gate.Colour
