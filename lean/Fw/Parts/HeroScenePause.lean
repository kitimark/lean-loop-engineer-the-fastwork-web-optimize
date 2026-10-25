import Lean.Data.Json
import Fw.Parts.PlatformScene
import Fw.Parts.HiddenPause
import Fw.Parts.HeroCountdownOpt
import Fw.Parts.HeroDeck
import Fw.Parts.HeroExit
import Fw.Site.BreakpointMatrix
import Fw.Gate.Trajectory
namespace Fw.Parts.HeroScenePause
open Lean
open Fw.Engine
open Fw.Parts.PlatformScene (near attr sceneOf Frame advance local' frames origFrames faithful_eq_original sample)
open Fw.Parts.HiddenPause (Tmpl inst Hidden HiddenOrStill hidden_pause_eq)
open Fw.Parts.HeroCountdownOpt (Host owns wk_owns)

/-! ## 1. The rule -/

/-- The hero track's scene value: the original's `lE` and `cE` on its `hero-track` section, registered at
`snapshot/site/_app/immutable/nodes/2.DyWL8TcE.js` byte 152358 (`dE(c, {deferRendering: !0, element: b})`, default
`rootMargin` `100% 0px`, `manageAnimations` on). -/
def heroScene (top bottom vh : Rat) : String := attr (near top bottom vh)

theorem heroScene_eq_original : heroScene = sceneOf := rfl

theorem near_false_iff (top bottom vh : Rat) : near top bottom vh = false ↔ (bottom < -vh ∨ 2 * vh < top) := by
  simp only [near, Bool.and_eq_false_iff, decide_eq_false_iff_not]
  constructor
  · rintro (h | h)
    · exact Or.inl (Rat.not_le.mp h)
    · exact Or.inr (Rat.not_le.mp h)
  · rintro (h | h)
    · exact Or.inl (Rat.not_le.mpr h)
    · exact Or.inr (Rat.not_le.mpr h)

theorem paused_of_above (top bottom vh : Rat) (h : bottom < -vh) : heroScene top bottom vh = "paused" := by
  simp [heroScene, (near_false_iff top bottom vh).mpr (Or.inl h), attr]

theorem paused_of_below (top bottom vh : Rat) (h : 2 * vh < top) : heroScene top bottom vh = "paused" := by
  simp [heroScene, (near_false_iff top bottom vh).mpr (Or.inr h), attr]

theorem active_of_near (top bottom vh : Rat) (h1 : -vh ≤ bottom) (h2 : top ≤ 2 * vh) :
    heroScene top bottom vh = "active" := by
  simp [heroScene, near, attr, h1, h2]

theorem paused_iff (top bottom vh : Rat) :
    heroScene top bottom vh = "paused" ↔ near top bottom vh = false := by
  cases h : near top bottom vh <;> simp [heroScene, h, attr]

/-! The 430 × 775 census: a track `2 vh` tall at document top, scrolled to `y`. -/
#guard heroScene 0 1550 775 == "active"
#guard heroScene (-2325) (-775) 775 == "active"
#guard heroScene (-2326) (-776) 775 == "paused"
#guard heroScene (-3000) (-1450) 775 == "paused"
#guard heroScene (-4500) (-2950) 775 == "paused"
#guard heroScene (-5267) (-3717) 775 == "paused"
#guard heroScene 1550 3100 775 == "active"
#guard heroScene 1551 3101 775 == "paused"

/-! ## 2. Stale frames: the attribute lags the scroll -/

/-- The viewport of a `vw × vh` window. -/
def viewport (vw vh : Rat) : Rect := ⟨0, 0, vw, vh⟩

/-- `s` lies vertically within `[lo, hi]`. -/
def withinV (s : Rect) (lo hi : Rat) : Prop := lo ≤ s.y ∧ s.y + s.h ≤ hi

/-- The attribute was computed at a track rect `[top, bottom]`; the painted frame has scrolled it by `d`, `|d| ≤ k`, and
a box overflows the track by at most `m`. With `k + m ≤ vh` the box does not meet the viewport. -/
theorem stale_off (vw vh top bottom d k m : Rat) (s : Rect) (hp : near top bottom vh = false)
    (hd : -k ≤ d ∧ d ≤ k) (hk : k + m ≤ vh) (hs : withinV s (top + d - m) (bottom + d + m)) :
    (viewport vw vh).meets s = false := by
  rcases (near_false_iff top bottom vh).mp hp with h | h <;>
  · obtain ⟨h1, h2⟩ := hs
    cases hm : (viewport vw vh).meets s
    · rfl
    · simp only [Rect.meets, viewport, Bool.and_eq_true, decide_eq_true_eq] at hm
      grind

theorem stale_hidden {A : Type} (vw vh top bottom d k m : Rat) (f : A → BoxVis)
    (hp : near top bottom vh = false) (hd : -k ≤ d ∧ d ≤ k) (hk : k + m ≤ vh)
    (hs : ∀ a, withinV ((f a).xf.bbox (f a).ink) (top + d - m) (bottom + d + m)) :
    Hidden (viewport vw vh) f := by
  intro a
  simp [BoxVis.drop, stale_off vw vh top bottom d k m _ hp hd hk (hs a)]

/-- One stale paused frame against the faithful arm: every box is still or stays in the band, so the visible scene is
the same at any two animation values. -/
theorem paused_frame_same {A : Type} (vw vh top bottom d k m : Rat) (tm : Tmpl A)
    (hp : near top bottom vh = false) (hd : -k ≤ d ∧ d ≤ k) (hk : k + m ≤ vh)
    (hs : ∀ e ∈ tm, (∀ a a', e.2 a = e.2 a') ∨
      ∀ a, withinV ((e.2 a).xf.bbox (e.2 a).ink) (top + d - m) (bottom + d + m)) (a a' : A) :
    visible (viewport vw vh) (inst tm a) = visible (viewport vw vh) (inst tm a') := by
  refine hidden_pause_eq _ tm (fun e he => ?_) a a'
  rcases hs e he with h | h
  · exact Or.inl h
  · exact Or.inr (stale_hidden vw vh top bottom d k m e.2 hp hd hk h)

/-! ## 3. Clocks -/

/-- Against the original, at every width and every scroll trace (frame length, track active), class E: both pause on
the same rule, so every animation has the same local time. -/
theorem visSame_original {Env : Type} (vp : Env → Rect) (tm : Env → Tmpl Rat) (ℓ0 : Rat) :
    VisSame E vp (fun env (tr : List (Rat × Bool)) => inst (tm env) (local' ℓ0 (origFrames tr)))
      (fun env tr => inst (tm env) (local' ℓ0 (frames tr))) :=
  visSame_of_eq vp fun _ tr => by rw [(faithful_eq_original tr ℓ0).2]

/-- Total length of the paused frames of a trace. -/
def pausedTotal (tr : List (Rat × Bool)) : Rat := (tr.map fun x => if x.2 then 0 else x.1).foldr (· + ·) 0

/-- The faithful arm never pauses. -/
def faithfulFrames (tr : List (Rat × Bool)) : List Frame := tr.map fun x => (x.1, false)

theorem local_shift (ℓ c : Rat) (fs : List Frame) : local' (ℓ + c) fs = local' ℓ fs + c := by
  induction fs generalizing ℓ with
  | nil => rfl
  | cons f fs ih =>
    simp only [local', List.foldl_cons] at ih ⊢
    unfold advance
    split
    · exact ih ℓ
    · rw [show ℓ + c + f.1 = ℓ + f.1 + c by grind]; exact ih _

/-- The faithful arm runs ahead of the variant by exactly the paused time. -/
theorem phase_gap (tr : List (Rat × Bool)) (ℓ0 : Rat) :
    local' ℓ0 (faithfulFrames tr) = local' ℓ0 (frames tr) + pausedTotal tr := by
  induction tr generalizing ℓ0 with
  | nil => simp [local', faithfulFrames, frames, pausedTotal]; exact (Rat.add_zero _).symm
  | cons x tr ih =>
    obtain ⟨len, act⟩ := x
    have e1 : local' ℓ0 (faithfulFrames ((len, act) :: tr)) = local' (ℓ0 + len) (faithfulFrames tr) := rfl
    have e2 : local' ℓ0 (frames ((len, act) :: tr)) = local' (if act then ℓ0 + len else ℓ0) (frames tr) := by
      cases act <;> rfl
    have e3 : pausedTotal ((len, act) :: tr) = (if act then 0 else len) + pausedTotal tr := rfl
    rw [e1, e2, e3, ih]
    cases act
    · simp only [Bool.false_eq_true, ite_false]; rw [local_shift]; grind
    · simp only [ite_true]; grind

theorem faithful_eq_of_active (tr : List (Rat × Bool)) (ℓ0 : Rat) (h : ∀ x ∈ tr, x.2 = true) :
    local' ℓ0 (faithfulFrames tr) = local' ℓ0 (frames tr) := by
  have h0 : pausedTotal tr = 0 := by
    unfold pausedTotal
    induction tr with
    | nil => rfl
    | cons x tr ih =>
      simp only [List.map_cons, List.foldr_cons, h x (by simp), ite_true]
      rw [ih (fun y hy => h y (by simp [hy]))]
      exact Rat.add_zero _
  rw [phase_gap, h0]; exact Rat.add_zero _

/-- The cue's 2.2 s float after one paused second: the variant shows another phase than the faithful arm (and the
original's phase). -/
theorem cue_phase_differs :
    sample (.loop 2200) (local' 0 (frames [(1000, false), (500, true)])) ≠
      sample (.loop 2200) (local' 0 (faithfulFrames [(1000, false), (500, true)])) := by
  decide +kernel

/-! ## 4. Stacking and containing block -/

/-- A box's stacking context or containing-block flag from its transform and a `will-change` naming a transform
property: WebKit `Source/WebCore/rendering/RenderLayer.cpp:627@862f17d`,
`Source/WebCore/rendering/RenderElementStyleInlines.h:86,93@862f17d`; Chromium
`third_party/blink/renderer/core/style/computed_style.cc:2986@f842f52`,
`third_party/blink/renderer/core/style/computed_style.h:2185-2201,2262-2273@f842f52`. -/
def establishes (hasTransform wc : Bool) : Bool := hasTransform || wc

theorem establishes_wc_irrelevant (wc : Bool) : establishes true wc = establishes true false := by
  cases wc <;> rfl

#guard establishes true false && establishes false true && !establishes false false

/-- Whether a box paints as one unit: a stacking context, or a positioned box none of whose descendants is positioned
or stacks (CSS 2.1 Appendix E, step 8). -/
def atomic (positioned establishes hasPosDesc : Bool) : Bool := establishes || (positioned && !hasPosDesc)

theorem atomic_leaf (wc : Bool) : atomic true wc false = atomic true false false := by cases wc <;> rfl

/-- A family of the hero's `will-change` boxes at `≤ 600` px: how many, whether its CSS always gives it a transform,
whether it is a positioned leaf. -/
structure WcFamily where
  name : String
  count : Nat
  transform : Bool
  leaf : Bool
deriving Repr, DecidableEq

/-- The copy (`translate`, hero.module.css:208), the deck cards (`rotate`, deck.module.css:25) and the countdown faces
(absolute, text only, no transform before the driver's first write). -/
def heroWcFamilies : List WcFamily := [⟨"copy", 1, true, false⟩, ⟨"deck card", 4, true, false⟩, ⟨"face", 80, false, true⟩]

theorem hero_wc_paint_same : ∀ fam ∈ heroWcFamilies, ∀ wc : Bool,
    (fam.transform = true ∧ establishes true wc = establishes true false) ∨
      (fam.leaf = true ∧ atomic true wc false = atomic true false false) := by
  decide +kernel

#guard (heroWcFamilies.map (·.count)).sum == 85

/-! ## 5. Layers -/

/-- A hero box with `will-change` in the faithful arm; `other` holds when a reason other than `will-change` composites
it while paused (a paused animation still in effect, `RenderLayerCompositor.cpp:3842-3867@862f17d`). -/
structure WcBox where
  other : Bool
deriving Repr, DecidableEq

/-- Whether the box owns a layer: `will-change` is cleared while paused. -/
def layer (h : Host) (paused : Bool) (b : WcBox) : Bool := owns h (!paused) || b.other

/-- Layers of the boxes. -/
def layers (h : Host) (paused : Bool) (bs : List WcBox) : Nat := (bs.filter (layer h paused)).length

theorem layer_le (h : Host) (p : Bool) (b : WcBox) (hl : layer h p b = true) : layer h false b = true := by
  cases h with
  | chromium => cases p <;> simp_all [layer, owns]
  | webkit pol => cases p <;> simp_all [layer, wk_owns]

theorem layers_le (h : Host) (p : Bool) (bs : List WcBox) : layers h p bs ≤ layers h false bs := by
  induction bs with
  | nil => simp [layers]
  | cons b bs ih =>
    simp only [layers, List.filter_cons] at ih ⊢
    have := layer_le h p b
    cases h1 : layer h p b <;> cases h2 : layer h false b <;> simp_all <;> omega

theorem layers_paused (h : Host) (ho : owns h true = true) (bs : List WcBox) :
    layers h false bs = bs.length ∧ layers h true bs = (bs.filter (·.other)).length := by
  have hf : owns h false = false := by cases h with
    | chromium => rfl
    | webkit pol => rw [wk_owns]; rfl
  have e : layer h true = fun b => b.other := funext fun b => by simp [layer, hf]
  constructor
  · simp [layers, layer, ho]
  · simp only [layers, e]

theorem layers_unowned (h : Host) (ho : owns h true = false) (p : Bool) (bs : List WcBox) :
    layers h p bs = layers h false bs := by
  have hf : owns h false = false := by cases h with
    | chromium => rfl
    | webkit pol => rw [wk_owns]; rfl
  have e : ∀ q, layer h q = fun b => b.other := fun q => funext fun b => by cases q <;> simp [layer, ho, hf]
  simp only [layers, e]

/-- A modelled count, `heroWcFamilies` at `≤ 600` px, matched to the MEASURED will-change reason count 91 → 6 (webkit-sim
39548856639, y 3000 and 4500); the cue keeps its layers, as a paused animation still has the animation reason
(`RenderLayerCompositor.cpp:3842-3867@862f17d`). -/
def heroWcOnly : List WcBox := List.replicate (heroWcFamilies.map (·.count)).sum ⟨false⟩

theorem hero_paused_drop (h : Host) (ho : owns h true = true) :
    layers h false heroWcOnly = 85 ∧ layers h true heroWcOnly = 0 := by
  have := layers_paused h ho heroWcOnly
  have hl : heroWcOnly.length = 85 := by decide +kernel
  exact ⟨this.1.trans hl, by rw [this.2]; decide +kernel⟩

theorem wk_normal_owns : owns (.webkit .normal) true = true := by decide

#guard layers (.webkit .normal) true heroWcOnly == 0
#guard layers (.webkit .normal) false heroWcOnly == 85
#guard layers (.webkit .conservative) false heroWcOnly == 0
#guard layers .chromium true [⟨true⟩, ⟨false⟩] == 1
#guard layer .chromium false ⟨false⟩ && !layer .chromium true ⟨false⟩ && layer .chromium true ⟨true⟩

/-! ## 6. Every paused hero box is off-screen -/

open Fw.Site.Breakpoints (Probe matrix Motion)
open Fw.Parts.HeroOrbit (Piece pieces canvasH restRadius peakBlur scatterY radius phase phase_t_mem ease3 ease3_mem ease5)
open Fw.Parts.HeroDeck (Slot slots)

/-- An upper bound of the ink outset of `filter: blur(σ)`, `σ ≥ 0`: `3/2` of a box kernel of
`max 2 ⌊σ · 3√(2π)/4 + 1/2⌋` px (WebKit `Source/WebCore/platform/graphics/filters/FEGaussianBlur.cpp:97-108,132-137@862f17d`,
Chromium `third_party/blink/renderer/platform/graphics/filters/fe_gaussian_blur.cc:38-54,61-70@f842f52`). -/
def blurOutset (σ : Rat) : Rat := 3 * σ + 3

theorem radius_le (e : Rat) : radius e ≤ restRadius := by
  have h := phase_t_mem e
  unfold radius
  cases hq : phase e with
  | mk p t =>
    rw [hq] at h
    simp only at h
    have hu0 : 0 ≤ 1 - t := by grind
    have hu1 : 1 - t ≤ 1 := by grind
    have a2 : 0 ≤ (1 - t) * (1 - t) := Rat.mul_nonneg hu0 hu0
    have a3 : 0 ≤ (1 - t) * (1 - t) * (1 - t) := Rat.mul_nonneg a2 hu0
    have a4 : 0 ≤ (1 - t) * (1 - t) * (1 - t) * (1 - t) := Rat.mul_nonneg a3 hu0
    have b4 : (1 - t) * (1 - t) * (1 - t) * (1 - t) ≤ 1 := by
      have b2 : (1 - t) * (1 - t) ≤ 1 := by have := Rat.mul_le_mul_of_nonneg_left hu1 hu0; grind
      have b3 : (1 - t) * (1 - t) * (1 - t) ≤ 1 := by have := Rat.mul_le_mul_of_nonneg_left hu1 a2; grind
      have := Rat.mul_le_mul_of_nonneg_left hu1 a3; grind
    have b5 : (1 - t) * (1 - t) * (1 - t) * (1 - t) * (1 - t) ≤ 1 := by
      have := Rat.mul_le_mul_of_nonneg_left hu1 a4; grind
    have e0 : 0 ≤ ease5 t := by unfold ease5; grind
    have e1 : ease3 t ≤ 1 := (ease3_mem t h.1 h.2).2
    cases p <;> simp only [restRadius, Fw.Parts.HeroOrbit.pulledRadius] <;> grind

/-- The vertical reach of one hero box family in stage coordinates (the sticky stage's top is 0): at exit scatter
`s ∈ [0, 1]` its transformed ink lies in `[lo + s * loS, hi + s * hiS]`. -/
structure Reach where
  lo : Rat
  loS : Rat
  hi : Rat
  hiS : Rat
deriving Repr, DecidableEq

/-- The copy column's ink outset: a countdown face moves at most 5 cells of `40px × 1.3`; the copy's and the cue's blur
and translate stay within it (`copy_outset_dominates`). -/
def copyOutset : Rat := 5 * (40 * 13 / 10)

theorem copy_outset_dominates : blurOutset 34 + 12 ≤ copyOutset ∧ blurOutset 34 + 10 + 8 ≤ copyOutset := by
  decide +kernel

/-- The copy column and the cue, laid out inside the stage of height `H`. -/
def copyReach (H : Rat) : Reach := ⟨-copyOutset, 0, H + copyOutset, 0⟩

/-- An orbit card: centre between its ring slot and its resting centre on a `canvasH` canvas centred on the stage, ink
within half its width plus height of the centre, plus the motion blur, the shadow and `s · scatterY` vh. -/
def orbitReach (H vh : Rat) (p : Piece) : Reach :=
  let c0 := H / 2 - canvasH / 2
  let rest := p.top + p.height / 2
  let ext := (p.width + p.height) / 2
  let sy := scatterY p.left p.top * vh / 100
  ⟨c0 + min rest (canvasH / 2 - restRadius) - ext - blurOutset peakBlur - 2, min 0 sy,
   c0 + max rest (canvasH / 2 + restRadius) + ext + blurOutset peakBlur + 6, max 0 sy⟩

/-- A deck card: top at `topPct` of the stage, ink within half its width plus height of its centre, plus the shadow and
`s · sy` vh. -/
def deckReach (H vh : Rat) (sl : Slot) : Reach :=
  let c := sl.topPct / 100 * H + sl.height / 2
  let ext := (sl.width + sl.height) / 2
  ⟨c - ext - 2, min 0 (sl.sy * vh / 100), c + ext + 6, max 0 (sl.sy * vh / 100)⟩

/-- The hero's box families: the copy column, then the deck cards at `≤ 600` px or the orbit cards above. -/
def reaches (le600 : Bool) (H vh : Rat) : List Reach :=
  copyReach H :: if le600 then slots.map (deckReach H vh) else pieces.map (orbitReach H vh)

/-- How far a family reaches beyond the stage `[0, H]` at any scatter in `[0, 1]`. -/
def Reach.over (H : Rat) (r : Reach) : Rat := max 0 (max (-(r.lo + r.loS)) (r.hi + r.hiS - H))

/-- The hero's overflow `m`: the largest reach of a family beyond the stage. -/
def overflow (le600 : Bool) (H vh : Rat) : Rat := (reaches le600 H vh).foldr (fun r m => max (r.over H) m) 0

/-- A probe's viewport height. -/
def vhOf (p : Probe) : Rat := (p.env.height.num : Rat) / p.env.height.den

/-- A probe is in the `≤ 600` px band. -/
def le600Of (p : Probe) : Bool := decide ((p.env.width.num : Rat) / p.env.width.den ≤ 600)

/-- The sticky stage height at a probe (`svh = vh`). -/
def stageOf (p : Probe) : Rat := Fw.Parts.HeroExit.heroHeightPx (vhOf p) (le600Of p)

/-- The hero's overflow at a probe. -/
def overflowOf (p : Probe) : Rat := overflow (le600Of p) (stageOf p) (vhOf p)

/-- The largest scroll between two observer callbacks that keeps a stale paused frame off-screen: `vh - m`. -/
def kMax (p : Probe) : Rat := vhOf p - overflowOf p

/-- The same bound for the copy column alone, the only family that animates after the splash: `vh - copyOutset`. -/
def kCopy (p : Probe) : Rat := vhOf p - (copyReach (stageOf p)).over (stageOf p)

#guard overflow true 775 775 = 13111723 / 40000
#guard overflow false 680 430 = 2064 / 5
#guard overflow false 900 900 = 2266 / 5
#guard (matrix.filter (·.tag == "no-preference")).map kMax = [86 / 5]
#guard (matrix.filter (·.tag == "no-preference")).map kCopy = [170]

theorem stage_fits : ∀ p ∈ matrix, stageOf p ≤ 2 * vhOf p := by decide +kernel

theorem kMax_pos : ∀ p ∈ matrix, 0 < kMax p := by decide +kernel

theorem kCopy_ge : ∀ p ∈ matrix, 170 ≤ kCopy p := by decide +kernel

theorem reaches_signs (l : Bool) (H vh : Rat) : ∀ r ∈ reaches l H vh, r.loS ≤ 0 ∧ 0 ≤ r.hiS := by
  intro r hr
  simp only [reaches, List.mem_cons] at hr
  rcases hr with rfl | hr
  · exact ⟨Std.le_refl _, Std.le_refl _⟩
  · cases l <;> simp only [Bool.false_eq_true, ite_false, ite_true, List.mem_map] at hr <;>
      obtain ⟨x, -, rfl⟩ := hr <;> constructor <;> simp only [orbitReach, deckReach] <;> grind

theorem over_le (H : Rat) (rs : List Reach) : ∀ r ∈ rs, r.over H ≤ rs.foldr (fun r m => max (r.over H) m) 0 := by
  induction rs with
  | nil => simp
  | cons x xs ih =>
    intro r hr
    simp only [List.mem_cons, List.foldr_cons] at hr ⊢
    rcases hr with rfl | hr
    · grind
    · have := ih r hr; grind

theorem reach_within (H s : Rat) (r : Reach) (hs : 0 ≤ s ∧ s ≤ 1) (hr : r.loS ≤ 0 ∧ 0 ≤ r.hiS) :
    -(r.over H) ≤ r.lo + s * r.loS ∧ r.hi + s * r.hiS ≤ H + r.over H := by
  have h1 := Rat.mul_nonneg (show 0 ≤ 1 - s by grind) (show 0 ≤ -r.loS by grind)
  have h2 := Rat.mul_nonneg (show 0 ≤ 1 - s by grind) hr.2
  unfold Reach.over
  constructor <;> grind

/-- A box the hero CSS places on a stage whose top is at `y0`: its transformed ink lies in some family's reach. -/
def Placed (rs : List Reach) (y0 : Rat) (b : BoxVis) : Prop :=
  ∃ r ∈ rs, ∃ s : Rat, (0 ≤ s ∧ s ≤ 1) ∧ withinV (b.xf.bbox b.ink) (y0 + (r.lo + s * r.loS)) (y0 + (r.hi + s * r.hiS))

/-- At every probe of the breakpoint matrix, a paused hero box whose frame scrolled at most `kMax` since the observer's
callback does not meet the viewport. -/
theorem hero_paused_hidden {A : Type} (p : Probe) (vw top bottom y0 d : Rat) (f : A → BoxVis)
    (hn : near top bottom (vhOf p) = false) (hst : top + d ≤ y0 ∧ y0 + stageOf p ≤ bottom + d)
    (hd : -kMax p ≤ d ∧ d ≤ kMax p) (hb : ∀ a, Placed (reaches (le600Of p) (stageOf p) (vhOf p)) y0 (f a)) :
    Hidden (viewport vw (vhOf p)) f := by
  refine stale_hidden vw (vhOf p) top bottom d (kMax p) (overflowOf p) f hn hd
    (by unfold kMax; grind) (fun a => ?_)
  obtain ⟨r, hr, s, hs, h1, h2⟩ := hb a
  have hw := reach_within (stageOf p) s r hs (reaches_signs _ _ _ r hr)
  have ho := over_le (stageOf p) _ r hr
  unfold overflowOf overflow
  exact ⟨by grind, by grind⟩

/-- Without a stale frame every paused hero box is off-screen at every probe. -/
theorem hero_paused_hidden_fresh {A : Type} (p : Probe) (hp : p ∈ matrix) (vw top bottom y0 : Rat) (f : A → BoxVis)
    (hn : near top bottom (vhOf p) = false) (hst : top ≤ y0 ∧ y0 + stageOf p ≤ bottom)
    (hb : ∀ a, Placed (reaches (le600Of p) (stageOf p) (vhOf p)) y0 (f a)) :
    Hidden (viewport vw (vhOf p)) f := by
  have hk := kMax_pos p hp
  exact hero_paused_hidden p vw top bottom y0 0 f hn (by grind) (by grind) hb

inductive Fam where
  | copy
  | card
  deriving DecidableEq, Repr

structure Anim where
  file : String
  name : String
  fam : Fam
  uses : List (String × Option String)
  deriving DecidableEq, Repr

def Anim.afterSplash (a : Anim) : Bool := a.uses.any (·.2.isNone)

def threadedFile : String := "hero.exit/threaded.module.css"

def heroAnims (_ : Unit := ()) : List Anim :=
  let copyDone := some "[data-splash='done'] .copy"
  let cueDone := some "[data-splash='done'] .cue"
  let cardDone := some "[data-orbit][data-done] .card"
  let hero := "[data-exit-live] [data-splash='done'] [data-fw='hero']"
  let cue := "[data-exit-live] [data-splash='done'] [data-fw='hero-cue']"
  let orbit := "[data-fw='hero-exit'][data-exit-live] [data-splash='done'] [data-orbit-id]"
  let deck := "[data-exit-live] [data-splash='done'] [data-fw='hero-deck'] > article"
  let nl (d : String) := s!".accent:is([data-fw-draw='nolayout'], [data-fw-draw='nolayout-full']).{d} .frame0"
  [⟨"hero/hero.module.css", "copyFromRing", .copy, [(".copy", copyDone)]⟩,
   ⟨"hero.accent/accent.module.css", "strokeIn", .copy, [(".drawingIn .path", none)]⟩,
   ⟨"hero.accent/accent.module.css", "strokeOut", .copy, [(".drawingOut .path", none)]⟩,
   ⟨"hero.accent/accent.module.css", "clipIn", .copy, [(nl "drawingIn", none)]⟩,
   ⟨"hero.accent/accent.module.css", "clipOut", .copy, [(nl "drawingOut", none)]⟩,
   ⟨"hero.accent/accent.module.css", "idle0", .copy, [(".idle .frame0", none)]⟩,
   ⟨"hero.accent/accent.module.css", "idle1", .copy, [(".idle .frame1", none)]⟩,
   ⟨"hero.accent/accent.module.css", "idle2", .copy, [(".idle .frame2", none)]⟩,
   ⟨"hero.cue/cue.module.css", "copyIn", .copy, [(".cue", none)]⟩,
   ⟨"hero.cue/cue.module.css", "copyFromRing", .copy, [(".cue", cueDone)]⟩,
   ⟨"hero.cue/cue.module.css", "scrollFloat", .copy, [(".float", none)]⟩,
   ⟨threadedFile, "exitFade", .copy, [(hero, none), (cue, none)]⟩,
   ⟨threadedFile, "exitCardFade", .card, [(orbit, none), (deck, none)]⟩,
   ⟨threadedFile, "exitCopyUp", .copy, [(hero, none)]⟩,
   ⟨threadedFile, "exitCopyUpNarrow", .copy, [(hero, none)]⟩,
   ⟨threadedFile, "exitCueUpNarrow", .copy, [(cue, none)]⟩,
   ⟨threadedFile, "exitBlur", .copy, [(hero, none), (cue, none)]⟩,
   ⟨threadedFile, "exitCardMove", .card, [(orbit, none), (deck, none)]⟩,
   ⟨"hero.orbit/card.module.css", "cardFromRing", .card, [(".card", cardDone)]⟩,
   ⟨"hero.orbit/card.module.css", "ringAppear", .card, [(".card", cardDone)]⟩]

def baseAnims (_ : Unit := ()) : List Anim := (heroAnims ()).filter (·.file != threadedFile)

#guard (baseAnims ()).length == 13
#guard ((baseAnims ()).filter (·.afterSplash)).map (·.name) ==
  ["strokeIn", "strokeOut", "clipIn", "clipOut", "idle0", "idle1", "idle2", "copyIn", "scrollFloat"]

theorem after_splash_copy : ∀ a ∈ baseAnims, a.afterSplash = true → a.fam = .copy := by decide +kernel

theorem card_stops : ∀ a ∈ baseAnims, a.fam = .card → a.afterSplash = false := by decide +kernel

theorem threaded_card_after_splash : ∃ a ∈ heroAnims, a.file = threadedFile ∧ a.afterSplash = true ∧ a.fam = .card := by
  decide +kernel

theorem copy_over (H : Rat) : (copyReach H).over H = copyOutset := by
  simp only [Reach.over, copyReach, copyOutset]
  grind

theorem kCopy_eq (p : Probe) : kCopy p = vhOf p - copyOutset := by rw [kCopy, copy_over]

theorem kMax_le_kCopy : ∀ p ∈ matrix, kMax p ≤ kCopy p := by decide +kernel

theorem hero_paused_hidden_copy {A : Type} (p : Probe) (vw top bottom y0 d : Rat) (f : A → BoxVis)
    (hn : near top bottom (vhOf p) = false) (hst : top + d ≤ y0 ∧ y0 + stageOf p ≤ bottom + d)
    (hd : -kCopy p ≤ d ∧ d ≤ kCopy p) (hb : ∀ a, Placed [copyReach (stageOf p)] y0 (f a)) :
    Hidden (viewport vw (vhOf p)) f := by
  refine stale_hidden vw (vhOf p) top bottom d (kCopy p) ((copyReach (stageOf p)).over (stageOf p)) f hn hd
    (by unfold kCopy; grind) (fun a => ?_)
  obtain ⟨r, hr, s, hs, h1, h2⟩ := hb a
  rw [List.mem_singleton] at hr
  subst hr
  have hw := reach_within (stageOf p) s (copyReach (stageOf p)) hs ⟨Std.le_refl _, Std.le_refl _⟩
  exact ⟨by grind, by grind⟩

theorem hero_paused_same_after_splash {A : Type} (p : Probe) (vw top bottom y0 d : Rat) (tm : Tmpl A)
    (moves : Anim → (A → BoxVis) → Prop)
    (hn : near top bottom (vhOf p) = false) (hst : top + d ≤ y0 ∧ y0 + stageOf p ≤ bottom + d)
    (hd : -kCopy p ≤ d ∧ d ≤ kCopy p)
    (hs : ∀ e ∈ tm, Fw.Parts.HiddenPause.Still e.2 ∨ ∃ an ∈ baseAnims, an.afterSplash = true ∧ moves an e.2)
    (hplace : ∀ an ∈ baseAnims, ∀ f, moves an f → an.fam = .copy → ∀ a, Placed [copyReach (stageOf p)] y0 (f a))
    (a a' : A) :
    visible (viewport vw (vhOf p)) (inst tm a) = visible (viewport vw (vhOf p)) (inst tm a') := by
  refine hidden_pause_eq _ tm (fun e he => ?_) a a'
  rcases hs e he with h | ⟨an, han, haf, hm⟩
  · exact Or.inl h
  · exact Or.inr (hero_paused_hidden_copy p vw top bottom y0 d e.2 hn hst hd
      (hplace an han e.2 hm (after_splash_copy an han haf)))

def copySpeed (p : Probe) (hz : Rat) : Rat := kCopy p * hz

#guard (matrix.filter (·.tag == "no-preference")).map (copySpeed · 60) = [10200]
#guard (matrix.filter (·.tag == "no-preference")).map (copySpeed · 120) = [20400]

namespace Open
open Fw.Gate.Trajectory

structure OpenRun where
  run : String
  original : Nat
  faithful : Nat
  candidate : Nat
  deriving DecidableEq, Repr

def recorded : List OpenRun :=
  [⟨"39548822269", 0, 2, 0⟩, ⟨"39553952680", 0, 1, 0⟩, ⟨"39556935431", 0, 0, 0⟩]

def laneNow (r : OpenRun) : Lane :=
  openLane (passesWith 5 r.original) (passesWith 5 r.candidate) (passesWith 5 r.faithful)

#guard recorded.map laneNow == [.clean, .clean, .clean]
#guard firstCover 5 0 5 == .late

theorem recorded_open_late : ∀ r ∈ recorded,
    openAt (passesWith 5 r.original) (passesWith 5 r.candidate) = .skip .firstLate := by decide +kernel

theorem recorded_clean : ∀ r ∈ recorded, laneNow r = .clean := by decide +kernel

theorem red_needs_original : ∀ k, k < 6 → (firstCover 5 k 5 = .missing ↔ 4 ≤ k) := by decide +kernel

def leaveOneOut (k : Nat) : List Verdict :=
  coverVerdict (firstCover 5 k 5) :: (List.range 5).map fun i => coverVerdict (firstCover 4 (if i < k then k - 1 else k) 5)

#guard leaveOneOut 1 == [.skip .firstLate, .skip .firstLate, .skip .firstOpen, .skip .firstOpen, .skip .firstOpen,
  .skip .firstOpen]

theorem run_640_family : (leaveOneOut 1).count (.skip .firstLate) = 2 ∧
    (leaveOneOut 1).count (.skip .firstOpen) = 4 ∧ ∀ v ∈ leaveOneOut 1, isFail v = false := by decide +kernel

end Open

def jn (n : Int) : Json := .num ⟨n, 0⟩

def line (fn : String) (inp : List (String × Json)) (out : Json) : String :=
  (Json.mkObj [("fn", .str fn), ("in", Json.mkObj inp), ("out", out)]).compress

def cases (vh : Int) : List (Int × Int) :=
  [(0, 2 * vh), (-vh - 2 * vh, -vh), (-vh - 2 * vh - 1, -vh - 1), (2 * vh, 4 * vh), (2 * vh + 1, 4 * vh + 1),
   (-3000, 2 * vh - 3000), (-4500, 2 * vh - 4500), (-5267, 2 * vh - 5267)]

def lines (_ : Unit := ()) : List String :=
  (([667, 775, 844, 900] : List Int).flatMap fun vh => (cases vh).map fun (t, b) =>
    line "scene" [("top", jn t), ("bottom", jn b), ("vh", jn vh)] (.str (heroScene t b vh))) ++
  [line "const" [] (Json.mkObj
    [("attr", .str "data-fw-hero-scene"), ("active", .str (attr true)), ("paused", .str (attr false)),
     ("rootMargin", .str "100% 0px"), ("playState", .str "paused"), ("willChange", .str "auto")])] ++
  (heroAnims ()).map fun an => line "anim" [("file", .str an.file), ("name", .str an.name)] (Json.mkObj
    [("fam", .str (match an.fam with | .copy => "copy" | .card => "card")),
     ("uses", .arr (an.uses.map fun (s, o) => Json.mkObj [("sel", .str s), ("off", (o.map Json.str).getD .null)]).toArray),
     ("afterSplash", .bool an.afterSplash)])

def goldenText (_ : Unit := ()) : String := String.join ((lines ()).map (· ++ "\n"))

/-- Print the golden text, or with `--check <file>` compare it; exit 1 on a difference. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText () then
      IO.eprintln s!"hero-scene-pause golden: {path} is up to date ({(lines ()).length} lines)"
      return 0
    IO.eprintln s!"hero-scene-pause golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Parts.HeroScenePause
