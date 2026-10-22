import Lean.Data.Json
import Fw.Parts.PeopleCard
import Fw.Gate.PathPix
import Fw.Engine.WebKit

/-!
# pain:dark-scroll: the Pain dark flip as a scroll-driven `steps(1)` opacity
-/
namespace Fw.Parts.PainDarkScroll
open Fw.Parts.PeopleCard

structure Rgb where
  r : Rat
  g : Rat
  b : Rat
deriving Repr, DecidableEq

def light : Rgb := ⟨255, 255, 255⟩

def darkRgb : Rgb := ⟨19, 25, 34⟩

def over (bottom top : Rgb) (a : Rat) : Rgb :=
  ⟨bottom.r + (top.r - bottom.r) * a, bottom.g + (top.g - bottom.g) * a, bottom.b + (top.b - bottom.b) * a⟩

theorem over_zero (b t : Rgb) : over b t 0 = b := by
  cases b; cases t; simp only [over, Rat.mul_zero, Rat.add_zero]

theorem over_one (b t : Rgb) : over b t 1 = t := by
  cases b; cases t; simp only [over, Rat.mul_one, Rgb.mk.injEq]; grind

def headerTop (h tr y : Rat) : Rat := h + tr - y

def origPixel (w h tr y : Rat) : Rgb :=
  if painDark (decide (w ≤ 860)) (headerTop h tr y) = true then darkRgb else light

def flipAt (h : Rat) : Rat := h - darkTop

def window : Rat := 256

def rangeLen : Rat := 32768

def offsetX : Rat := window / rangeLen

def rangeStart (h : Rat) : Rat := flipAt h - window

theorem flip_of_range (h : Rat) : rangeStart h + offsetX * rangeLen = flipAt h := by
  unfold rangeStart offsetX window rangeLen; grind

def measuredStart (rectTop y0 ty : Rat) : Rat := rectTop + y0 - ty - darkTop - window

theorem measure_eq (h tr y0 : Rat) : measuredStart (headerTop h tr y0) y0 tr = rangeStart h := by
  unfold measuredStart headerTop rangeStart flipAt; grind

-- TimingFunction.cpp:100-139@862f17d
def stepsStart1 (before : Bool) (p : Rat) : Rat :=
  let c0 : Int := p.floor + 1
  let c1 : Int := if before && decide (p = (p.floor : Rat)) then c0 - 1 else c0
  let c2 : Int := if decide (p < 0) && decide (c1 < 0) then 0 else c1
  let c3 : Int := if decide (p ≤ 1) && decide (1 < c2) then 1 else c2
  (c3 : Rat)

def progress (s len y : Rat) : Rat :=
  if y < s then 0 else if y < s + len then (y - s) / len else 1

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

def varPixel (w h y : Rat) : Rgb :=
  if w ≤ 860 then over light darkRgb (layerOpacity (rangeStart h) rangeLen offsetX y) else darkRgb

theorem layer_flip (h y : Rat) : layerOpacity (rangeStart h) rangeLen offsetX y = if flipAt h ≤ y then 1 else 0 := by
  have := opacity_eq (rangeStart h) rangeLen offsetX y (by unfold rangeLen; grind) (by unfold offsetX window rangeLen; grind)
    (by unfold offsetX window rangeLen; grind)
  rw [this, flip_of_range]

def Reveal (tr : Rat) : Prop := tr = 0

def Cont (lastY y : Rat) : Prop := lastY = y

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

theorem reveal_needed : ∃ w h y : Rat, varPixel w h y ≠ origPixel w h 48 y := by
  refine ⟨390, 1000, 1000, ?_⟩
  decide +kernel

theorem wide_eq (w h tr y : Rat) (hw : 860 < w) : varPixel w h y = origPixel w h tr y := by
  have : ¬ w ≤ 860 := by grind
  simp [varPixel, origPixel, this, painDark]

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

theorem cont_needed : ∃ w h y lastY : Rat, varPixel w h y ≠ origPixel w h 0 lastY := by
  refine ⟨390, 1000, 1000, 900, ?_⟩
  decide +kernel

#guard varPixel 390 1000 999 == light && varPixel 390 1000 999.5 == darkRgb && varPixel 390 1000 5000 == darkRgb
#guard layerOpacity 0 100 (1 / 2) 49 == 0 && layerOpacity 0 100 (1 / 2) 50 == 1 && layerOpacity 0 100 (1 / 2) 100 == 1
  && layerOpacity 0 100 (1 / 2) (-1) == 0 && layerOpacity 0 100 (1 / 2) 101 == 1

/-- Toggle-frame work: main-thread style units and invalidated paint area. -/
structure Work where
  styleUnits : Nat
  paintKpx : Nat
deriving Repr, DecidableEq

def origToggle (n a : Nat) : Work := ⟨n, a⟩

/-- MODEL ASSUMPTION `ToggleUi` (INFERRED): the flip runs in the UI process, so the toggle frame adds no style or paint.
Chromium refutes it for style (`chromium_style_gt`). -/
def varToggle : Work := ⟨0, 0⟩

theorem toggle_free : varToggle.styleUnits = 0 ∧ varToggle.paintKpx = 0 := ⟨rfl, rfl⟩

theorem toggle_cost (n a : Nat) (hn : 0 < n) (ha : 0 < a) :
    varToggle.styleUnits < (origToggle n a).styleUnits ∧ varToggle.paintKpx < (origToggle n a).paintKpx :=
  ⟨hn, ha⟩

/-- Chromium toggle frame (scroll 970, swipe-v1, 430x932 dpr 3), px: base run 39818749535, flag run 39828614430. -/
def chromiumBasePx : Nat := 3413963

def chromiumVarPx : Nat := 3013203

def chromiumBase : Work := ⟨4, chromiumBasePx / 1000⟩

def chromiumVar : Work := ⟨5, chromiumVarPx / 1000⟩

theorem chromium_paint_drop : chromiumBasePx - chromiumVarPx = 430 * 932 := by decide

theorem chromium_paint_lt : chromiumVar.paintKpx < chromiumBase.paintKpx := by decide

theorem chromium_style_gt : chromiumBase.styleUnits < chromiumVar.styleUnits := by decide

theorem chromium_not_toggle_free : chromiumVar.styleUnits ≠ varToggle.styleUnits := by decide

/-- MODEL ASSUMPTION `RideEveryFrame`: each updating scroll frame adds one style unit
(`Fw.Engine.WebKit.scroll_comp_ride`, proved for the WebKit model). -/
def varRide (f : Nat) : Nat := f

theorem ride_exceeds (f n : Nat) (h : n < f) : n < varRide f := h

open Fw.Engine.WebKit (CssProp) in
def darkProps : List CssProp := [.opacity]

theorem dark_accelerated : Fw.Gate.PathPix.Accelerated darkProps :=
  (Fw.Gate.PathPix.accelerated_iff darkProps).1 rfl

-- AnimationTimelinesController.cpp:267-279@862f17d
def liftsThrottle (effects : List (List Fw.Engine.WebKit.CssProp)) : Bool :=
  effects.any fun ps => !Fw.Gate.PathPix.accelerated ps

theorem no_lift : liftsThrottle [darkProps] = false := by decide

def solidLayers : Nat := 2

def hostLayers : Nat := 1

theorem solid_layers_le : solidLayers + hostLayers ≤ 3 := by decide

def promotedKpx : Nat := 2999

theorem promoted_cost :
    Fw.Engine.WebKit.residentKpx true false promotedKpx - Fw.Engine.WebKit.residentKpx false false promotedKpx = promotedKpx := by
  simp [Fw.Engine.WebKit.residentKpx, Fw.Engine.WebKit.usesBacking]

theorem layer_backing_zero (areaKpx : Nat) :
    Fw.Engine.WebKit.residentKpx false false areaKpx = 0 :=
  (Fw.Engine.WebKit.simple_layer true areaKpx).1

structure Span where
  top : Int
  bot : Int

def Span.meets (a b : Span) : Prop := a.top < b.bot ∧ b.top < a.bot

instance (a b : Span) : Decidable (a.meets b) := inferInstanceAs (Decidable (_ ∧ _))

structure Content where
  span : Span
  kpx : Nat

-- RenderLayerCompositor.cpp:1332-1335@862f17d: a later layer composites iff it meets an earlier composited layer.
def promoted (animated : List Span) (c : Content) : Bool := animated.any fun a => decide (a.meets c.span)

def backingKpx (animated : List Span) (content : List Content) (stageKpx : Nat) : Nat :=
  ((content.filter (promoted animated)).map (·.kpx)).sum + (if content.any (!promoted animated ·) then stageKpx else 0)

def baseBackingKpx (content : List Content) (stageKpx : Nat) : Nat := if content.isEmpty then 0 else stageKpx

theorem static_eq_base (content : List Content) (stageKpx : Nat) :
    backingKpx [] content stageKpx = baseBackingKpx content stageKpx := by
  have hp : ∀ c : Content, promoted [] c = false := by intro c; simp [promoted]
  have hf : content.filter (promoted []) = [] := List.filter_eq_nil_iff.2 (by intro c _; simp [hp])
  unfold backingKpx baseBackingKpx
  rw [hf]
  cases content with
  | nil => simp
  | cons c cs => simp [hp]

def stageSpan : Span := ⟨0, 775⟩

def stageContent : List Content := [⟨stageSpan, 2999⟩, ⟨stageSpan, 2999⟩]

theorem hold_backing : backingKpx [stageSpan] stageContent 2999 = baseBackingKpx stageContent 2999 + promotedKpx := by
  decide +kernel

theorem animated_meets_costs (a : Span) (c : Content) (hm : a.meets c.span) (s : Nat) :
    backingKpx [a] [c] s = c.kpx := by
  simp [backingKpx, promoted, hm]

def staticPixel : Rgb := darkRgb

def Hidden (h p vh : Rat) : Prop := h + 48 - darkTop + vh ≤ p

def Seen (p vh y : Rat) : Prop := p < y + vh

theorem static_pixel_eq (w h tr lastY y p vh : Rat) (hh : Hidden h p vh) (h48 : tr ≤ 48)
    (hc : Cont lastY y) (hs : Seen p vh y) : staticPixel = origPixel w h tr lastY := by
  unfold Hidden at hh; unfold Cont at hc; unfold Seen at hs
  subst hc
  unfold staticPixel origPixel
  by_cases hw : w ≤ 860
  · have : h + tr - lastY ≤ darkTop := by grind
    simp [hw, painDark, headerTop, this]
  · simp [hw, painDark]

theorem hidden_needed : ∃ w h tr y p vh : Rat, Seen p vh y ∧ staticPixel ≠ origPixel w h tr y := by
  refine ⟨390, 1000, 0, 0, 500, 775, ?_, ?_⟩
  · unfold Seen; decide +kernel
  · decide +kernel

def ownsFlip (variant : String) (supports : Bool) : Bool :=
  (variant == "dark-scroll" && supports) || variant == "dark-static"

theorem owns_static (s : Bool) : ownsFlip "dark-static" s = true := by simp [ownsFlip]

theorem owns_scroll (s : Bool) : ownsFlip "dark-scroll" s = s := by cases s <;> simp [ownsFlip]

theorem owns_faithful (s : Bool) : ownsFlip "faithful" s = false := by cases s <;> simp [ownsFlip]

open Lean in
private def jrat (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

open Lean in
private def jrgb (c : Rgb) : Json := Json.arr #[jrat c.r, jrat c.g, jrat c.b]

def docTops : List Rat := [900, 1850, 2400.25, 3120.5]

def widths : List Rat := [320, 390, 640, 860, 861, 1280]

def deltas : List Rat := [-1000, -1, -1 / 2, -1 / 100, 0, 1 / 100, 1 / 2, 1, 1000]

open Lean in
def flipRows (_ : Unit := ()) : List String :=
  docTops.flatMap fun h => [0, 48].flatMap fun tr => [0, 313, 1337 / 3].map fun y0 =>
    (Json.mkObj [("kind", .str "flip"), ("h", jrat h), ("tr", jrat tr), ("y0", jrat y0),
      ("rectTop", jrat (headerTop h tr y0)), ("ty", jrat tr), ("start", jrat (measuredStart (headerTop h tr y0) y0 tr))]).compress

open Lean in
def pixelRows (_ : Unit := ()) : List String :=
  widths.flatMap fun w => docTops.flatMap fun h => deltas.map fun d =>
    let y := flipAt h + d
    (Json.mkObj [("kind", .str "pixel"), ("w", jrat w), ("h", jrat h), ("y", jrat y), ("start", jrat (rangeStart h)),
      ("opacity", jrat (layerOpacity (rangeStart h) rangeLen offsetX y)), ("orig", jrgb (origPixel w h 0 y)),
      ("var", jrgb (varPixel w h y))]).compress

open Lean in
def ownsRows (_ : Unit := ()) : List String :=
  ["faithful", "dark-scroll", "dark-static", ""].flatMap fun v => [false, true].map fun s =>
    (Json.mkObj [("kind", .str "owns"), ("variant", .str v), ("supports", .bool s), ("owns", .bool (ownsFlip v s))]).compress

def darkScrollJsonl (_ : Unit := ()) : String := String.join ((flipRows () ++ pixelRows () ++ ownsRows ()).map (· ++ "\n"))

#guard ((flipRows ()).length, (pixelRows ()).length, (ownsRows ()).length) == (24, 216, 8)

#guard darkScrollJsonl () == include_str "../../../packages/contracts/golden/parts/pain-dark-scroll.jsonl"

end Fw.Parts.PainDarkScroll
