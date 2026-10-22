import Lean.Data.Json
import Fw.Parts.PeopleCard
import Fw.Gate.PathPix
import Fw.Engine.WebKit

/-!
# pain:dark-scroll: the Pain dark flip as a scroll-driven `steps(1)` opacity (variant `dark-scroll`)

Original (`snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`, `Fw.Parts.PeopleCard.painDark`): at width at most
860 px the people card driver adds `is-pain-dark` to the Pain section once the People header's top is at or above
`0.5` px, which swaps the white section, stage and hold backgrounds for `#131922`.

Variant: the white backgrounds stay and two empty `#131922` layers lie over them behind the content (over the hold, and
over the stage's own background); each has its opacity animated from 0 to 1 on the root scroll timeline over a range
that starts `window` px before the flip offset `T = H - 1/2` (`H` the header's document top, written once per layout)
and is far longer than the page, fill both. The flip is a keyframe at `window / rangeLen` of the range whose interval
is eased by `steps(1, jump-start)`, so the animation is already running when the scroll crosses `T` (a range that
starts at `T` is idle before it, and WebKit then flips on the main thread). Above 860 px the layers do not exist and the
base CSS is dark in both arms.
-/
namespace Fw.Parts.PainDarkScroll
open Fw.Parts.PeopleCard

/-! ## Pixels -/

/-- An opaque sRGB colour, channels 0 to 255 as `Rat` so source-over arithmetic is exact. -/
structure Rgb where
  r : Rat
  g : Rat
  b : Rat
deriving Repr, DecidableEq

/-- The Pain section colour on the narrow layout before the flip (`#fff`). -/
def light : Rgb := ⟨255, 255, 255⟩

/-- The dark Pain colour (`#131922`). -/
def darkRgb : Rgb := ⟨19, 25, 34⟩

/-- Source-over of an opaque `top` at opacity `a` on an opaque `bottom`. -/
def over (bottom top : Rgb) (a : Rat) : Rgb :=
  ⟨bottom.r + (top.r - bottom.r) * a, bottom.g + (top.g - bottom.g) * a, bottom.b + (top.b - bottom.b) * a⟩

/-- Opacity 0 shows the bottom colour exactly. -/
theorem over_zero (b t : Rgb) : over b t 0 = b := by
  cases b; cases t; simp only [over, Rat.mul_zero, Rat.add_zero]

/-- Opacity 1 shows the top colour exactly (opaque top). -/
theorem over_one (b t : Rgb) : over b t 1 = t := by
  cases b; cases t; simp only [over, Rat.mul_one, Rgb.mk.injEq]; grind

/-! ## The original -/

/-- Where the People header's top sits in the viewport at scroll offset `y`: document top `h`, the card's residual
reveal translation `tr`. -/
def headerTop (h tr y : Rat) : Rat := h + tr - y

/-- Original pixel of the Pain section at viewport width `w`: dark iff the class is on. The class is
`painDark narrow headerTop`, so it is always on above 860 px. -/
def origPixel (w h tr y : Rat) : Rgb :=
  if painDark (decide (w ≤ 860)) (headerTop h tr y) = true then darkRgb else light

/-! ## The variant -/

/-- The scroll offset at which the layer turns on: the header's document top minus `darkTop`. -/
def flipAt (h : Rat) : Rat := h - darkTop

/-- Scroll px before the flip offset at which the animation's range starts, so the animation is already running (and, in
WebKit, accelerated) when the scroll crosses the flip. -/
def window : Rat := 256

/-- The animation's range length in scroll px (past the end of any page in the band). -/
def rangeLen : Rat := 32768

/-- Keyframe offset of the flip inside the range: `window / rangeLen`, the CSS `0.78125%`. -/
def offsetX : Rat := window / rangeLen

/-- The range start written for a header at document top `h`. -/
def rangeStart (h : Rat) : Rat := flipAt h - window

/-- The flip offset the range encodes: its start plus the keyframe offset of the range length. -/
theorem flip_of_range (h : Rat) : rangeStart h + offsetX * rangeLen = flipAt h := by
  unfold rangeStart offsetX window rangeLen; grind

/-- What the layout effect writes as range start from a measurement taken at scroll offset `y0`: the header's viewport
top, the scroll offset and the card's current translation (read from its transform). -/
def measuredStart (rectTop y0 ty : Rat) : Rat := rectTop + y0 - ty - darkTop - window

/-- **The written range start is the encoded one, at any scroll offset and in any reveal state.** -/
theorem measure_eq (h tr y0 : Rat) : measuredStart (headerTop h tr y0) y0 tr = rangeStart h := by
  unfold measuredStart headerTop rangeStart flipAt; grind

/-- CSS Easing `steps(1, jump-start)` (`TimingFunction::transformProgress`, `TimingFunction.cpp:100-139@862f17d`):
current step `floor p + 1`, minus one when the before flag is set and `p` is an integer, clamped to `[0, 1]`. -/
def stepsStart1 (before : Bool) (p : Rat) : Rat :=
  let c0 : Int := p.floor + 1
  let c1 : Int := if before && decide (p = (p.floor : Rat)) then c0 - 1 else c0
  let c2 : Int := if decide (p < 0) && decide (c1 < 0) then 0 else c1
  let c3 : Int := if decide (p ≤ 1) && decide (1 < c2) then 1 else c2
  (c3 : Rat)

/-- The scroll animation's progress at offset `y` over the range `[s, s + len]`: 0 before it (fill backwards), linear
inside it, 1 after it (fill forwards). -/
def progress (s len y : Rat) : Rat :=
  if y < s then 0 else if y < s + len then (y - s) / len else 1

/-- The layer's opacity. Keyframes: `0%` opacity 0, `x` opacity 0 with timing `steps(1, jump-start)`, `100%` opacity 1.
The interval of progress `p` starts at the last keyframe at or before `p`, so at `p = x` the second interval applies. -/
def layerOpacity (s len x y : Rat) : Rat :=
  let p := progress s len y
  if p < x then 0 else stepsStart1 false ((p - x) / (1 - x))

private theorem floor_zero : (0 : Rat).floor = 0 := by
  have := Rat.floor_intCast 0
  simpa using this

private theorem floor_one : (1 : Rat).floor = 1 := by
  have := Rat.floor_intCast 1
  simpa using this

private theorem floor_unit (p : Rat) (h0 : 0 ≤ p) (h1 : p < 1) : p.floor = 0 := by
  have a : (0 : Int) ≤ p.floor := Rat.le_floor_iff.2 (by simpa using h0)
  have b : p.floor < 1 := Rat.floor_lt_iff.2 (by simpa using h1)
  omega

/-- **Opacity is exactly 0 before the flip offset `s + x * len` and exactly 1 from it on** (steps only, no ramp), for any
range start `s`, positive length and keyframe offset strictly inside `(0, 1)`. -/
theorem opacity_eq (s len x y : Rat) (hl : 0 < len) (hx0 : 0 < x) (hx1 : x < 1) :
    layerOpacity s len x y = if s + x * len ≤ y then 1 else 0 := by
  have hxl : 0 < x * len := Rat.mul_pos hx0 hl
  have hxl1 : x * len < len := by
    have := Rat.mul_pos (show 0 < 1 - x by grind) hl
    grind
  unfold layerOpacity progress
  by_cases h1 : y < s
  · have h3 : ¬ s + x * len ≤ y := by grind
    simp [h1, h3, hx0]
  · by_cases h2 : y < s + len
    · by_cases h4 : (y - s) / len < x
      · have h5 : ¬ s + x * len ≤ y := by
          rw [Rat.div_lt_iff hl] at h4; grind
        simp [h1, h2, h4, h5]
      · have h6 : s + x * len ≤ y := by
          have : ¬ (y - s) / len < x := h4
          rw [Rat.div_lt_iff hl] at this; grind
        have hq0 : 0 ≤ ((y - s) / len - x) / (1 - x) := by
          refine Rat.not_lt.1 fun hn => ?_
          rw [Rat.div_lt_iff (by grind)] at hn
          have : x ≤ (y - s) / len := Rat.not_lt.1 h4
          grind
        have hq1 : ((y - s) / len - x) / (1 - x) < 1 := by
          rw [Rat.div_lt_iff (by grind)]
          have : (y - s) / len < 1 := by rw [Rat.div_lt_iff hl]; grind
          grind
        have hf := floor_unit _ hq0 hq1
        simp [h1, h2, h4, h6, stepsStart1, hf]
    · have h6 : s + x * len ≤ y := by grind
      have h7 : ¬ (1 : Rat) < x := by grind
      have h8 : (1 - x) / (1 - x) = 1 := by rw [Rat.div_def]; exact Rat.mul_inv_cancel _ (by grind)
      simp [h1, h2, h6, h7, h8, stepsStart1, floor_one]

/-- Variant pixel at width `w` and scroll offset `y`: the layers over the white section in the band, the base dark
above it (layers absent). -/
def varPixel (w h y : Rat) : Rgb :=
  if w ≤ 860 then over light darkRgb (layerOpacity (rangeStart h) rangeLen offsetX y) else darkRgb

/-- The layer's opacity from the written range is 0 before the flip offset and 1 from it on. -/
theorem layer_flip (h y : Rat) : layerOpacity (rangeStart h) rangeLen offsetX y = if flipAt h ≤ y then 1 else 0 := by
  have := opacity_eq (rangeStart h) rangeLen offsetX y (by unfold rangeLen; grind) (by unfold offsetX window rangeLen; grind)
    (by unfold offsetX window rangeLen; grind)
  rw [this, flip_of_range]

/-! ## Same look -/

/-- Premise Reveal: the card's reveal translation has finished (`transform: none`, scale 1 in the band) at this offset. -/
def Reveal (tr : Rat) : Prop := tr = 0

/-- Premise Cont: the original's last class write used this very scroll offset (no frame behind). -/
def Cont (lastY y : Rat) : Prop := lastY = y

/-- **Pixel equality** (for every width, document top and offset): under Reveal and Cont, the variant shows the same
pixel as the original. -/
theorem pixel_eq (w h tr lastY y : Rat) (hr : Reveal tr) (hc : Cont lastY y) :
    varPixel w h y = origPixel w h tr lastY := by
  unfold Reveal at hr; unfold Cont at hc
  subst hr; subst hc
  unfold varPixel origPixel
  by_cases hw : w ≤ 860
  · simp only [hw, ite_true, layer_flip, painDark, decide_true, Bool.not_true, Bool.false_or, headerTop, flipAt]
    by_cases ht : h + 0 - lastY ≤ darkTop
    · have : h - darkTop ≤ lastY := by grind
      simp [ht, this, over_one]
    · have : ¬ h - darkTop ≤ lastY := by grind
      simp [ht, this, over_zero]
  · simp [hw, painDark]

/-- Reveal is needed: a card still 48 px low (its `translateY(48px)`) flips the original later than the layer. -/
theorem reveal_needed : ∃ w h y : Rat, varPixel w h y ≠ origPixel w h 48 y := by
  refine ⟨390, 1000, 1000, ?_⟩
  decide +kernel

/-- Above 860 px both arms are dark at every offset and in every state. -/
theorem wide_eq (w h tr y : Rat) (hw : 860 < w) : varPixel w h y = origPixel w h tr y := by
  have : ¬ w ≤ 860 := by grind
  simp [varPixel, origPixel, this, painDark]

/-- **Where Reveal fails the looks differ only inside a window of at most 48 px of scroll.** The reveal translation
`tr` runs from 48 px (`translateY(48px)`, card.module.css) down to 0; with a current class, the two arms differ at `y`
only in the band and only while `flipAt h <= y < flipAt h + tr`, the original being the later one. -/
theorem drift_window (w h tr lastY y : Rat) (hc : Cont lastY y) (h0 : 0 ≤ tr) (h48 : tr ≤ 48)
    (hne : varPixel w h y ≠ origPixel w h tr lastY) :
    w ≤ 860 ∧ flipAt h ≤ y ∧ y < flipAt h + 48 := by
  unfold Cont at hc
  subst hc
  by_cases hw : w ≤ 860
  · refine ⟨hw, ?_⟩
    unfold varPixel origPixel at hne
    simp only [hw, ite_true, layer_flip, painDark, decide_true, Bool.not_true, Bool.false_or, headerTop,
      flipAt] at hne
    by_cases ha : h - darkTop ≤ lastY
    · by_cases hb : h + tr - lastY ≤ darkTop
      · simp [ha, hb, over_one] at hne
      · have : lastY < h - darkTop + 48 := by grind
        exact ⟨ha, by unfold flipAt; grind⟩
    · by_cases hb : h + tr - lastY ≤ darkTop
      · exfalso; grind
      · simp [ha, hb, over_zero] at hne
  · exfalso
    exact hne (wide_eq w h tr lastY (by grind))

/-- Cont is needed: an original one frame behind (class from `lastY < y`) differs from the layer. -/
theorem cont_needed : ∃ w h y lastY : Rat, varPixel w h y ≠ origPixel w h 0 lastY := by
  refine ⟨390, 1000, 1000, 900, ?_⟩
  decide +kernel

#guard varPixel 390 1000 999 == light && varPixel 390 1000 999.5 == darkRgb && varPixel 390 1000 5000 == darkRgb
#guard layerOpacity 0 100 (1 / 2) 49 == 0 && layerOpacity 0 100 (1 / 2) 50 == 1 && layerOpacity 0 100 (1 / 2) 100 == 1
  && layerOpacity 0 100 (1 / 2) (-1) == 0 && layerOpacity 0 100 (1 / 2) 101 == 1

/-! ## Work -/

/-- Main-thread work the toggle adds to its frame: elements restyled and painted area in kpx. -/
structure Work where
  styleUnits : Nat
  paintKpx : Nat
deriving Repr, DecidableEq

/-- Original: the class write restyles the `n` elements its three rules can reach and repaints the section's `a` kpx of
background. -/
def origToggle (n a : Nat) : Work := ⟨n, a⟩

/-- Variant: the opacity animation runs off the main thread (UI process, INFERRED), so the toggle adds nothing. -/
def varToggle : Work := ⟨0, 0⟩

/-- **The toggle frame is free of paints and style passes in the variant.** -/
theorem toggle_free : varToggle.styleUnits = 0 ∧ varToggle.paintKpx = 0 := ⟨rfl, rfl⟩

/-- The original's toggle frame pays style and paint whenever the class reaches an element and the area is non-empty. -/
theorem toggle_cost (n a : Nat) (hn : 0 < n) (ha : 0 < a) :
    varToggle.styleUnits < (origToggle n a).styleUnits ∧ varToggle.paintKpx < (origToggle n a).paintKpx :=
  ⟨hn, ha⟩

/-- WebKit restyles the animation's target in every updating scroll frame (`Fw.Engine.WebKit.scroll_comp_ride`), so
over `f` frames in the band the variant pays `f` style units on its layer and the original none outside the toggle: the
paint saving is paid for in style units, a trade for `f` above the original's `n`. -/
def varRide (f : Nat) : Nat := f

theorem ride_exceeds (f n : Nat) (h : n < f) : n < varRide f := h

/-! ## Layers and acceleration -/

open Fw.Engine.WebKit (CssProp) in
/-- The properties of the layer's one effect. -/
def darkProps : List CssProp := [.opacity]

/-- The layer's effect is completely accelerated (opacity is in WebKit's `always` list). -/
theorem dark_accelerated : Fw.Gate.PathPix.Accelerated darkProps :=
  (Fw.Gate.PathPix.accelerated_iff darkProps).1 rfl

/-- The throttle-lift condition (`AnimationTimelinesController.cpp:267-279@862f17d`): a progress-based timeline has an
effect that is not completely accelerated. -/
def liftsThrottle (effects : List (List Fw.Engine.WebKit.CssProp)) : Bool :=
  effects.any fun ps => !Fw.Gate.PathPix.accelerated ps

/-- **The variant does not lift the scroll throttle**: its only effect is completely accelerated. -/
theorem no_lift : liftsThrottle [darkProps] = false := by decide

/-- The layers the variant adds: one over the hold, one over the stage (at most 3). -/
def solidLayers : Nat := 2

/-- Layers the engine adds around them. Chromium counts 3 more layers in every frame (CI run 39822446444: 19 to 22,
`census.layers`); the third is INFERRED to be a host layer for the negative-z layer in the stage. -/
def hostLayers : Nat := 1

theorem solid_layers_le : solidLayers + hostLayers ≤ 3 := by decide

/-- Area in kpx of the stage's text block (430 x 775 css px at dpr 3), which WebKit promotes to a layer of its own
because it paints above and overlaps the animated layer (reason `overlap`; MEASURED, CI run 39828605244: 12.0 MB more
backing at the two scroll states that show the Pain stage, 0 elsewhere; the cause is INFERRED from the layer list). -/
def promotedKpx : Nat := 2999

/-- **The promoted block costs its whole area in resident backing; the solid layers cost none.** So the layer budget of
the variant is 0 MB for the layers it adds and `promotedKpx` for the layer it forces. -/
theorem promoted_cost :
    Fw.Engine.WebKit.residentKpx true false promotedKpx - Fw.Engine.WebKit.residentKpx false false promotedKpx = promotedKpx := by
  simp [Fw.Engine.WebKit.residentKpx, Fw.Engine.WebKit.usesBacking]

/-- **The solid layer has no backing store** (no content, no display delegation). -/
theorem layer_backing_zero (areaKpx : Nat) :
    Fw.Engine.WebKit.residentKpx false false areaKpx = 0 :=
  (Fw.Engine.WebKit.simple_layer true areaKpx).1

/-! ## Golden rows -/

open Lean in
private def jrat (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

open Lean in
private def jrgb (c : Rgb) : Json := Json.arr #[jrat c.r, jrat c.g, jrat c.b]

/-- Header document tops (px) of the rows. -/
def docTops : List Rat := [900, 1850, 2400.25, 3120.5]

/-- Widths of the rows: both sides of the 860 edge. -/
def widths : List Rat := [320, 390, 640, 860, 861, 1280]

/-- Offsets of the pixel rows relative to the flip offset. -/
def deltas : List Rat := [-1000, -1, -1 / 2, -1 / 100, 0, 1 / 100, 1 / 2, 1, 1000]

open Lean in
/-- Range-start rows: the value the layout effect writes from a measurement at scroll offset `y0` with card translation
`tr` (the reveal's 48 px or none). -/
def flipRows (_ : Unit := ()) : List String :=
  docTops.flatMap fun h => [0, 48].flatMap fun tr => [0, 313, 1337 / 3].map fun y0 =>
    (Json.mkObj [("kind", .str "flip"), ("h", jrat h), ("tr", jrat tr), ("y0", jrat y0),
      ("rectTop", jrat (headerTop h tr y0)), ("ty", jrat tr), ("start", jrat (measuredStart (headerTop h tr y0) y0 tr))]).compress

open Lean in
/-- Pixel rows: original (revealed, class current) and variant at offsets around the flip. -/
def pixelRows (_ : Unit := ()) : List String :=
  widths.flatMap fun w => docTops.flatMap fun h => deltas.map fun d =>
    let y := flipAt h + d
    (Json.mkObj [("kind", .str "pixel"), ("w", jrat w), ("h", jrat h), ("y", jrat y), ("start", jrat (rangeStart h)),
      ("opacity", jrat (layerOpacity (rangeStart h) rangeLen offsetX y)), ("orig", jrgb (origPixel w h 0 y)),
      ("var", jrgb (varPixel w h y))]).compress

/-- The contents of `packages/contracts/golden/parts/pain-dark-scroll.jsonl`. -/
def darkScrollJsonl (_ : Unit := ()) : String := String.join ((flipRows () ++ pixelRows ()).map (· ++ "\n"))

#guard ((flipRows ()).length, (pixelRows ()).length) == (24, 216)

#guard darkScrollJsonl () == include_str "../../../packages/contracts/golden/parts/pain-dark-scroll.jsonl"

end Fw.Parts.PainDarkScroll
