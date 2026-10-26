/-!
# One CSS animation in time: phase, fill, the shown value and which engine keeps its animation layer
-/
namespace Fw.Engine.VisualTimed

/-- `animation-fill-mode`. -/
inductive Fill | none | forwards | backwards | both
deriving DecidableEq, Repr

/-- Web Animations phase of an effect with a resolved local time. -/
inductive Phase | before | active | after
deriving DecidableEq, Repr

-- Chromium timing_calculations.cc:103-130@f842f52, WebKit AnimationEffectTiming.cpp:182-201@862f17d (document timeline,
-- forwards direction, no end delay: the boundaries are not aligned).
/-- Phase at local time `t` of an animation with delay `d` and duration `D`. -/
def phaseAt (d D t : Rat) : Phase := if t < d then .before else if t < d + D then .active else .after

/-- The fill covers the before phase. -/
def fillsBack : Fill → Bool | .backwards | .both => true | _ => false

/-- The fill covers the after phase. -/
def fillsFwd : Fill → Bool | .forwards | .both => true | _ => false

-- Chromium timing_calculations.cc:141-161 and timing.cc:259@f842f52; WebKit AnimationEffectTiming.cpp:219-241@862f17d.
/-- The active time is defined, so the effect writes its keyframe value. -/
def inEffect (f : Fill) : Phase → Bool
  | .before => fillsBack f
  | .active => true
  | .after => fillsFwd f

-- Chromium timing.cc:267-270@f842f52 (playback rate 1, no scroll timeline).
/-- Current: in play or yet to play. -/
def current : Phase → Bool | .after => false | _ => true

-- Chromium css_animations.cc:2267-2280 sets HasCurrent{Transform,Opacity,Filter}Animation (:2225-2238), which
-- compositing_reason_finder.cc:570-597@f842f52 turns into kActive{Transform,Opacity,Filter}Animation.
/-- Chromium gives the element an animation compositing reason. -/
def chromiumHeld (f : Fill) (p : Phase) : Bool := current p || inEffect f p

-- WebKit KeyframeEffect.cpp:1703-1715 (affecting only in the active phase), :2085-2089 (stopped out of it),
-- RenderLayerCompositor.cpp:3841-3866@862f17d; threaded animations off.
/-- WebKit gives the element an animation compositing reason. -/
def webkitHeld (_ : Fill) (p : Phase) : Bool := p == .active

/-- One property of one animated element: timing, fill, keyframe value at local time, static style value. -/
structure Track (α : Type) where
  d : Rat
  D : Rat
  fill : Fill
  anim : Rat → α
  base : α

/-- The value the element shows at local time `t`. -/
def shown {α : Type} (k : Track α) (t : Rat) : α := if inEffect k.fill (phaseAt k.d k.D t) then k.anim t else k.base

/-- The end value: the keyframe value once the active interval is over. -/
def endVal {α : Type} (k : Track α) : α := k.anim (k.d + k.D)

/-- The keyframe value holds still after the active interval. -/
def Settles {α : Type} (k : Track α) : Prop := ∀ t, k.d + k.D ≤ t → k.anim t = endVal k

/-- The variant: fill `backwards`, the end value written as static style. -/
def release {α : Type} (k : Track α) : Track α := { k with fill := .backwards, base := endVal k }

theorem phase_after (d D t : Rat) (h : d + D ≤ t) (hD : 0 ≤ D) : phaseAt d D t = .after := by
  unfold phaseAt
  have : ¬ t < d := by grind
  have : ¬ t < d + D := by grind
  simp [*]

theorem phase_not_after (d D t : Rat) (h : t < d + D) : phaseAt d D t ≠ .after := by
  unfold phaseAt; split <;> simp_all

theorem held_after_both : chromiumHeld .both .after = true := rfl

theorem held_after_forwards : chromiumHeld .forwards .after = true := rfl

theorem released_after_backwards : chromiumHeld .backwards .after = false := rfl

theorem released_after_none : chromiumHeld .none .after = false := rfl

theorem webkit_released_after (f : Fill) : webkitHeld f .after = false := rfl

theorem webkit_same_fill (f g : Fill) (p : Phase) : webkitHeld f p = webkitHeld g p := rfl

theorem held_before (f : Fill) : chromiumHeld f .before = true := rfl

theorem held_active (f : Fill) : chromiumHeld f .active = true := rfl

/-- Chromium holds the layer of a `both` animation from its start on, at every later time. -/
theorem both_held (d D t : Rat) : chromiumHeld .both (phaseAt d D t) = true := by
  unfold phaseAt; split
  · rfl
  · split <;> rfl

/-- The variant's layer goes away at the end of the active interval and never comes back. -/
theorem release_no_held_after {α : Type} (k : Track α) (t : Rat) (h : k.d + k.D ≤ t) (hD : 0 ≤ k.D) :
    chromiumHeld (release k).fill (phaseAt k.d k.D t) = false := by
  rw [phase_after _ _ _ h hD]; rfl

/-- Before the end, the variant holds exactly when the original does. -/
theorem release_held_before_end {α : Type} (k : Track α) (t : Rat) (h : t < k.d + k.D) :
    chromiumHeld (release k).fill (phaseAt k.d k.D t) = chromiumHeld k.fill (phaseAt k.d k.D t) := by
  have := phase_not_after k.d k.D t h
  cases hp : phaseAt k.d k.D t <;> simp_all [chromiumHeld, current]

/-- Same look: a `both` animation and its release show the same value at every time. -/
theorem release_shown {α : Type} (k : Track α) (hf : k.fill = .both) (hs : Settles k) (hD : 0 ≤ k.D) (t : Rat) :
    shown (release k) t = shown k t := by
  unfold shown release
  by_cases h : t < k.d + k.D
  · have := phase_not_after k.d k.D t h
    cases hp : phaseAt k.d k.D t <;> simp_all [inEffect, fillsBack]
  · have h' : k.d + k.D ≤ t := by grind
    rw [phase_after _ _ _ h' hD]
    simp [inEffect, fillsFwd, hf, hs t h']

/-- Frames (local times) at which Chromium holds the animation layer. -/
def heldFrames {α : Type} (k : Track α) (ts : List Rat) : Nat :=
  (ts.filter fun t => chromiumHeld k.fill (phaseAt k.d k.D t)).length

/-- The original holds the layer on every frame. -/
theorem both_heldFrames {α : Type} (k : Track α) (hf : k.fill = .both) (ts : List Rat) :
    heldFrames k ts = ts.length := by
  unfold heldFrames; rw [hf]
  have : ∀ t ∈ ts, chromiumHeld .both (phaseAt k.d k.D t) = true := fun t _ => both_held _ _ _
  rw [List.filter_eq_self.mpr this]

/-- The variant holds it only on the frames before the end. -/
theorem release_heldFrames {α : Type} (k : Track α) (hD : 0 ≤ k.D) (ts : List Rat) :
    heldFrames (release k) ts = (ts.filter fun t => decide (t < k.d + k.D)).length := by
  unfold heldFrames
  congr 1
  apply List.filter_congr
  intro t _
  by_cases h : t < k.d + k.D
  · have := phase_not_after k.d k.D t h
    simp only [release, h, decide_true]
    cases hp : phaseAt k.d k.D t <;> simp_all [chromiumHeld, current]
  · have h' : k.d + k.D ≤ t := by grind
    simp only [release, h, decide_false]
    rw [phase_after _ _ _ h' hD]; rfl

/-- Every frame after the end is one held layer-frame less. -/
theorem release_saves {α : Type} (k : Track α) (hf : k.fill = .both) (hD : 0 ≤ k.D) (ts : List Rat) :
    heldFrames (release k) ts + (ts.filter fun t => decide (k.d + k.D ≤ t)).length = heldFrames k ts := by
  rw [release_heldFrames k hD, both_heldFrames k hf]
  induction ts with
  | nil => rfl
  | cons t ts ih =>
    by_cases h : t < k.d + k.D
    · have : ¬ k.d + k.D ≤ t := by grind
      simp [h, this]; grind
    · have : k.d + k.D ≤ t := by grind
      simp [h, this]; grind

#guard phaseAt 100 400 0 == .before && phaseAt 100 400 100 == .active && phaseAt 100 400 500 == .after
#guard chromiumHeld .both .after && !chromiumHeld .backwards .after && !webkitHeld .both .after
#guard heldFrames ({ d := 0, D := 400, fill := .both, anim := id, base := 0 } : Track Rat) [0, 200, 400, 600] == 4
#guard heldFrames (release ({ d := 0, D := 400, fill := .both, anim := id, base := 0 } : Track Rat)) [0, 200, 400, 600] == 2

end Fw.Engine.VisualTimed
