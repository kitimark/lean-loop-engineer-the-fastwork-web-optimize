import Lean.Data.Json
import Fw.Parts.PeopleCard
import Fw.Gate.PathPix
import Fw.Engine.WebKit

/-!
# pain:dark-scroll: the Pain dark flip as a scroll-driven `steps(1)` opacity (variant `dark-scroll`)

Original (`snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`, `Fw.Parts.PeopleCard.painDark`): at width at most
860 px the people card driver adds `is-pain-dark` to the Pain section once the People header's top is at or above
`0.5` px, which swaps the white section, stage and hold backgrounds for `#131922`.

Variant: the three backgrounds stay transparent in the band and an empty `#131922` layer behind the content has its
opacity animated from 0 to 1 on the root scroll timeline with `steps(1, jump-start)`, range start `T = H - 1/2` (`H` the
header's document top, written once per layout), range length `len > 0`, fill both. Above 860 px the layer is hidden and
the base CSS is dark in both arms.
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

/-- What the layout effect writes as range start from a measurement taken at scroll offset `y0`: the header's viewport
top, the scroll offset and the card's current translation (read from its transform). -/
def measuredFlip (rectTop y0 ty : Rat) : Rat := rectTop + y0 - ty - darkTop

/-- **The written range start is the flip offset, at any scroll offset and in any reveal state.** -/
theorem measure_eq (h tr y0 : Rat) : measuredFlip (headerTop h tr y0) y0 tr = flipAt h := by
  unfold measuredFlip headerTop flipAt; grind

/-- CSS Easing `steps(1, jump-start)` (`TimingFunction::transformProgress`, `TimingFunction.cpp:100-139@862f17d`):
current step `floor p + 1`, minus one when the before flag is set and `p` is an integer, clamped to `[0, 1]`. -/
def stepsStart1 (before : Bool) (p : Rat) : Rat :=
  let c0 : Int := p.floor + 1
  let c1 : Int := if before && decide (p = (p.floor : Rat)) then c0 - 1 else c0
  let c2 : Int := if decide (p < 0) && decide (c1 < 0) then 0 else c1
  let c3 : Int := if decide (p ≤ 1) && decide (1 < c2) then 1 else c2
  (c3 : Rat)

/-- The scroll animation's progress and before flag at offset `y`: before the range (fill backwards) 0 and flag set,
inside it `(y - T) / len`, after it (fill forwards) 1. -/
def phase (t len y : Rat) : Rat × Bool :=
  if y < t then (0, true) else if y < t + len then ((y - t) / len, false) else (1, false)

/-- The layer's opacity: keyframes 0 to 1 eased by `steps(1, jump-start)`. -/
def layerOpacity (t len y : Rat) : Rat := stepsStart1 (phase t len y).2 (phase t len y).1

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

/-- **Opacity is exactly 0 before the flip offset and exactly 1 from it on** (steps only, no ramp). -/
theorem opacity_eq (t len y : Rat) (hl : 0 < len) : layerOpacity t len y = if t ≤ y then 1 else 0 := by
  unfold layerOpacity phase
  by_cases h1 : y < t
  · have : ¬ t ≤ y := by grind
    simp [h1, this, stepsStart1, floor_zero]
  · by_cases h2 : y < t + len
    · have hp0 : 0 ≤ (y - t) / len := by
        refine Rat.not_lt.1 fun hn => ?_
        rw [Rat.div_lt_iff hl] at hn
        grind
      have hp1 : (y - t) / len < 1 := by
        rw [Rat.div_lt_iff hl]; grind
      have hf := floor_unit _ hp0 hp1
      have : t ≤ y := by grind
      simp [h1, h2, this, stepsStart1, hf]
    · have : t ≤ y := by grind
      simp [h1, h2, this, stepsStart1, floor_one]

/-- Variant pixel at width `w` and scroll offset `y`: the layer over the white section in the band, the base dark
above it (layer hidden). -/
def varPixel (w h len y : Rat) : Rgb :=
  if w ≤ 860 then over light darkRgb (layerOpacity (flipAt h) len y) else darkRgb

/-! ## Same look -/

/-- Premise Reveal: the card's reveal translation has finished (`transform: none`, scale 1 in the band) at this offset. -/
def Reveal (tr : Rat) : Prop := tr = 0

/-- Premise Cont: the original's last class write used this very scroll offset (no frame behind). -/
def Cont (lastY y : Rat) : Prop := lastY = y

/-- **Pixel equality** (for every width, offset and layer range length): under Reveal and Cont, the variant shows the
same pixel as the original. -/
theorem pixel_eq (w h tr lastY y len : Rat) (hl : 0 < len) (hr : Reveal tr) (hc : Cont lastY y) :
    varPixel w h len y = origPixel w h tr lastY := by
  unfold Reveal at hr; unfold Cont at hc
  subst hr; subst hc
  unfold varPixel origPixel
  by_cases hw : w ≤ 860
  · simp only [hw, ite_true, opacity_eq _ _ _ hl, painDark, decide_true, Bool.not_true, Bool.false_or, headerTop, flipAt]
    by_cases ht : h + 0 - lastY ≤ darkTop
    · have : h - darkTop ≤ lastY := by grind
      simp [ht, this, over_one]
    · have : ¬ h - darkTop ≤ lastY := by grind
      simp [ht, this, over_zero]
  · simp [hw, painDark]

/-- Reveal is needed: a card still 48 px low (its `translateY(48px)`) flips the original later than the layer. -/
theorem reveal_needed : ∃ w h y len : Rat, 0 < len ∧ varPixel w h len y ≠ origPixel w h 48 y := by
  refine ⟨390, 1000, 1000, 1, by grind, ?_⟩
  decide +kernel

/-- Above 860 px both arms are dark at every offset and in every state. -/
theorem wide_eq (w h tr y len : Rat) (hw : 860 < w) : varPixel w h len y = origPixel w h tr y := by
  have : ¬ w ≤ 860 := by grind
  simp [varPixel, origPixel, this, painDark]

/-- **Where Reveal fails the looks differ only inside a window of at most 48 px of scroll.** The reveal translation
`tr` runs from 48 px (`translateY(48px)`, card.module.css) down to 0; with a current class and a layer of positive
range length, the two arms differ at `y` only in the band and only while `flipAt h <= y < flipAt h + tr`, the original
being the later one. -/
theorem drift_window (w h tr lastY y len : Rat) (hl : 0 < len) (hc : Cont lastY y) (h0 : 0 ≤ tr) (h48 : tr ≤ 48)
    (hne : varPixel w h len y ≠ origPixel w h tr lastY) :
    w ≤ 860 ∧ flipAt h ≤ y ∧ y < flipAt h + 48 := by
  unfold Cont at hc
  subst hc
  by_cases hw : w ≤ 860
  · refine ⟨hw, ?_⟩
    unfold varPixel origPixel at hne
    simp only [hw, ite_true, opacity_eq _ _ _ hl, painDark, decide_true, Bool.not_true, Bool.false_or, headerTop,
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
    exact hne (wide_eq w h tr lastY len (by grind))

/-- Cont is needed: an original one frame behind (class from `lastY < y`) differs from the layer. -/
theorem cont_needed : ∃ w h y lastY len : Rat, 0 < len ∧ varPixel w h len y ≠ origPixel w h 0 lastY := by
  refine ⟨390, 1000, 1000, 900, 1, by grind, ?_⟩
  decide +kernel

#guard varPixel 390 1000 1 999 == light && varPixel 390 1000 1 999.5 == darkRgb && varPixel 390 1000 1 5000 == darkRgb
#guard layerOpacity 100 1 99 == 0 && layerOpacity 100 1 100 == 1 && layerOpacity 100 1 100.5 == 1 && layerOpacity 100 1 101 == 1

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

/-- The layer count the variant adds, at most 3 (one per site section kept; this build uses one). -/
def solidLayers : Nat := 1

theorem solid_layers_le : solidLayers ≤ 3 := by decide

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
      ("rectTop", jrat (headerTop h tr y0)), ("ty", jrat tr), ("flip", jrat (measuredFlip (headerTop h tr y0) y0 tr))]).compress

open Lean in
/-- Pixel rows: original (revealed, class current) and variant at offsets around the flip. -/
def pixelRows (_ : Unit := ()) : List String :=
  widths.flatMap fun w => docTops.flatMap fun h => deltas.map fun d =>
    let y := flipAt h + d
    (Json.mkObj [("kind", .str "pixel"), ("w", jrat w), ("h", jrat h), ("y", jrat y), ("len", jrat 1),
      ("opacity", jrat (layerOpacity (flipAt h) 1 y)), ("orig", jrgb (origPixel w h 0 y)),
      ("var", jrgb (varPixel w h 1 y))]).compress

/-- The contents of `packages/contracts/golden/parts/pain-dark-scroll.jsonl`. -/
def darkScrollJsonl (_ : Unit := ()) : String := String.join ((flipRows () ++ pixelRows ()).map (· ++ "\n"))

#guard ((flipRows ()).length, (pixelRows ()).length) == (24, 216)

#guard darkScrollJsonl () == include_str "../../../packages/contracts/golden/parts/pain-dark-scroll.jsonl"

end Fw.Parts.PainDarkScroll
