import Lean.Data.Json
import Fw.Parts.PlatformScene
import Fw.Parts.HiddenPause
import Fw.Parts.HeroCountdownOpt
/-!
# hero scene pause (`hero:scene-pause`): the original's paused-scene rule on the hero track
-/
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

/-- The hero's `will-change` boxes that keep no other reason: 80 countdown faces (8 digits), 4 deck cards (≤ 600 px),
the copy after the splash. -/
def heroWcOnly : List WcBox := List.replicate 85 ⟨false⟩

theorem hero_paused_drop (h : Host) (ho : owns h true = true) :
    layers h false heroWcOnly = 85 ∧ layers h true heroWcOnly = 0 := by
  have := layers_paused h ho heroWcOnly
  refine ⟨by simpa [heroWcOnly] using this.1, by rw [this.2]; decide⟩

theorem wk_normal_owns : owns (.webkit .normal) true = true := by decide

#guard layers (.webkit .normal) true heroWcOnly == 0
#guard layers (.webkit .normal) false heroWcOnly == 85
#guard layers (.webkit .conservative) false heroWcOnly == 0
#guard layers .chromium true [⟨true⟩, ⟨false⟩] == 1
#guard layer .chromium false ⟨false⟩ && !layer .chromium true ⟨false⟩ && layer .chromium true ⟨true⟩

/-! ## 6. Golden `packages/contracts/golden/parts/hero-scene-pause.jsonl` -/

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
     ("rootMargin", .str "100% 0px"), ("playState", .str "paused"), ("willChange", .str "auto")])]

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
