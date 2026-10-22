import Fw.Parts.PlatformFade
import Fw.Parts.MorphTweenOpt
import Fw.Gate.PathPix

/-! platform, variant `fade-threaded`, over time: one effect per push equals the original's per-frame `--morph-fade`
on every frame under the WAAPI premises, and Core Animation runs it (task platform-fade-threaded). -/

namespace Fw.Parts.PlatformFade
open Fw.Parts.MorphTween Fw.Parts.MorphTweenOpt

theorem easing_eq : easing = (p1x, p1y, p2x, p2y) := rfl

theorem kink_eq (f t : Rat) : kink f t = kfOffset fadeEnd f t := rfl

/-! ## One effect per push -/

/-- One time-based effect on the section: the push's from and to morph values and its start on the timeline. -/
structure Eff where
  f : Rat
  t : Rat
  st : Rat
deriving Repr, DecidableEq

/-- The fade an effect shows at timeline time `T` (`fill: both`, effect easing `P.timing`, interpolation `P.interp`). -/
def valE (P : WaapiPremises) (e : Eff) (T : Rat) : Rat :=
  interpKf P.interp (keyframes e.f e.t) (P.timing (progress e.st T))

theorem interpKf_lin (P : WaapiPremises) (ks : List Kf) (p : Rat) : interpKf P.interp ks p = interpKf lerp ks p := by
  induction ks with
  | nil => rfl
  | cons a rest ih =>
    cases rest with
    | nil => rfl
    | cons b rest' =>
      simp only [interpKf]
      split
      · rw [P.interp_lin]; rfl
      · exact ih

/-- **One frame.** The effect of a push from `f` to `t` at `n` shows, on the frame at `R`, the original's fade of
the tween value on that frame. -/
theorem frame_eq (P : WaapiPremises) (f t n R : Rat) :
    valE P ⟨f, t, P.startRead n⟩ (P.tl R) = fade (tween f t (R - n)).value := by
  unfold valE
  rw [interpKf_lin, timing_progress, tween_value_eq]
  have := ease_mem ((R - n) / duration)
  exact interp_eq f t _ this.1 this.2

/-- The section's fade state in the variant: the running effect, the inline `--morph-fade`, the fade last shown. -/
structure FSt where
  eff : Option Eff
  base : Rat
  shown : Rat
deriving Repr, DecidableEq

/-- At rest: no effect, `--morph-fade: 1`. -/
def initF : FSt := ⟨none, 1, 1⟩

/-- The variant's fade at timeline time `T`. -/
def valF (P : WaapiPremises) (x : FSt) (T : Rat) : Rat :=
  match x.eff with
  | none => x.base
  | some e => valE P e T

/-- Whether the effect has finished by timeline time `T`. -/
def finished (e : Eff) (T : Rat) : Bool := decide (e.st + duration ≤ T)

#guard !finished ⟨0, 1, 100⟩ 779 && finished ⟨0, 1, 100⟩ 780 && finished ⟨1, 0, 0⟩ 2000

/-- The variant's step, given the tween state `s` before the event: a push that moves the tween replaces the effect
by one from the current value (reduced motion writes the fade instead); a frame shows the effect and, once it has
finished, writes its end fade inline and drops it. -/
def stepF (P : WaapiPremises) (s : St) (x : FSt) : Ev → FSt
  | .push g rm n =>
    if s.target = g ∧ s.t = g then x
    else if rm then ⟨none, fade g, fade g⟩
    else { x with eff := some ⟨s.value, g, P.startRead n⟩ }
  | .tick R =>
    match x.eff with
    | some e => if finished e (P.tl R) then ⟨none, fade e.t, valE P e (P.tl R)⟩ else { x with shown := valE P e (P.tl R) }
    | none => { x with shown := x.base }

/-- Both states after a list of events: the tween (unchanged from the original) and the section's fade. -/
def runB (P : WaapiPremises) (s : St) (x : FSt) : List Ev → St × FSt
  | [] => (s, x)
  | e :: es => runB P (stepO s e) (stepF P s x e) es

/-- The simulation invariant: the variant shows the original's fade; a running tween is the running effect. -/
def InvF (P : WaapiPremises) (s : St) (x : FSt) : Prop :=
  x.shown = fade s.value ∧
    (s.pending = true → x.eff = some ⟨s.f, s.t, P.startRead s.start⟩) ∧
    (s.pending = false → x.eff = none ∧ x.base = fade s.value)

theorem invF_init (P : WaapiPremises) : InvF P rest initF := by
  unfold InvF rest initF; simp [fade_ends.1]

theorem invF_push (P : WaapiPremises) (s : St) (x : FSt) (g : Rat) (rm : Bool) (n : Rat) (h : InvF P s x) :
    InvF P (stepO s (.push g rm n)) (stepF P s x (.push g rm n)) := by
  obtain ⟨hs, hp, hn⟩ := h
  simp only [stepO, stepF, push]
  by_cases hg : s.target = g ∧ s.t = g
  · simp only [hg, and_self, ite_true]; exact ⟨hs, hp, hn⟩
  · simp only [hg, ite_false]
    cases rm
    · simp only [Bool.false_eq_true, ite_false]
      exact ⟨hs, fun _ => rfl, fun h => by simp at h⟩
    · simp only [ite_true]
      exact ⟨rfl, fun h => by simp at h, fun _ => ⟨rfl, rfl⟩⟩

theorem invF_tick (P : WaapiPremises) (s : St) (x : FSt) (R : Rat) (h : InvF P s x) :
    InvF P (stepO s (.tick R)) (stepF P s x (.tick R)) := by
  obtain ⟨hs, hp, hn⟩ := h
  cases hpd : s.pending
  · obtain ⟨he, hb⟩ := hn hpd
    simp only [stepO, stepF, hpd, Bool.false_eq_true, ite_false, he]
    exact ⟨hb, fun h => by simp [hpd] at h, fun _ => ⟨rfl, hb⟩⟩
  · have he := hp hpd
    have hv := frame_eq P s.f s.t s.start R
    have hfin : finished ⟨s.f, s.t, P.startRead s.start⟩ (P.tl R) = (tween s.f s.t (R - s.start)).done := by
      unfold finished
      rw [P.tl_eq, P.start_eq]
      cases hd : (tween s.f s.t (R - s.start)).done
      · have : ¬ (680 ≤ R - s.start) := fun h => by rw [(tween_done_iff s.f s.t (R - s.start)).2 h] at hd; cases hd
        unfold duration; simp; grind
      · have := (tween_done_iff s.f s.t (R - s.start)).1 hd
        unfold duration; simp; grind
    simp only [stepO, stepF, hpd, ite_true, he, frame]
    rw [hfin]
    cases hd : (tween s.f s.t (R - s.start)).done
    · simp only [Bool.false_eq_true, ite_false, Bool.not_false]
      exact ⟨hv, fun _ => rfl, fun h => by simp at h⟩
    · simp only [ite_true, Bool.not_true]
      have hend := tween_end s.f s.t (R - s.start) ((tween_done_iff _ _ _).1 hd)
      refine ⟨hv, fun h => by simp at h, fun _ => ⟨rfl, ?_⟩⟩
      rw [hend]

theorem invF_run (P : WaapiPremises) :
    ∀ (es : List Ev) (s : St) (x : FSt), InvF P s x → InvF P (runB P s x es).1 (runB P s x es).2
  | [], _, _, h => h
  | .push g rm n :: es, s, x, h => invF_run P es _ _ (invF_push P s x g rm n h)
  | .tick R :: es, s, x, h => invF_run P es _ _ (invF_tick P s x R h)

theorem runB_fst (P : WaapiPremises) : ∀ (es : List Ev) (s : St) (x : FSt), (runB P s x es).1 = runO s es
  | [], _, _ => rfl
  | e :: es, s, x => by simp only [runB, runO, List.foldl_cons]; exact runB_fst P es _ _

/-- **Same fade on every frame.** Over every push sequence (retargets and reduced-motion jumps included), after any
events the section's fade in the variant equals the original's `--morph-fade`, exactly in `ℚ`, under `P`. -/
theorem threaded_eq (P : WaapiPremises) (es : List Ev) :
    (runB P rest initF es).2.shown = fade (runO rest es).value := by
  rw [← runB_fst P es rest initF]
  exact (invF_run P es rest initF (invF_init P)).1

/-- **Same blur on every frame.** The variant's `filter` keyframes, interpolated as the opacity ones, show the original's
`blur((1 - --morph-fade) * 12px)` on the frame at `R` of a push from `f` to `t` at `n`. -/
theorem frame_blur_eq (P : WaapiPremises) (f t n R : Rat) :
    interpKf P.interp (blurKfs (keyframes f t)) (P.timing (progress (P.startRead n) (P.tl R))) =
      blurOf (fade (tween f t (R - n)).value) := by
  rw [interpKf_lin, interp_blur _ (by unfold keyframes; split <;> simp), ← interpKf_lin P]
  exact congrArg blurOf (frame_eq P f t n R)

/-- A retarget starts its effect at the fade the section shows. -/
theorem retarget_from_shown (P : WaapiPremises) (s : St) (x : FSt) (g n : Rat) (h : InvF P s x)
    (hm : ¬ (s.target = g ∧ s.t = g)) :
    (stepF P s x (.push g false n)).eff.map (fun e => (keyframes e.f e.t).head?) = some (some ⟨0, x.shown⟩) := by
  simp only [stepF, hm, ite_false, Bool.false_eq_true, Option.map_some, keyframes_head, h.1]

#guard (runB (premisesWk 0) rest initF [.push 1 false 100, .tick 440]).2.shown == fade (7 / 8)
#guard (runB (premisesWk 0) rest initF [.push 1 false 100, .tick 200, .push 0 false 210, .tick 400]).2.shown ==
  fade (runO rest [.push 1 false 100, .tick 200, .push 0 false 210, .tick 400]).value
#guard (runB (premisesWk 0) rest initF [.push 1 false 100, .tick 800]).2.eff == none

/-! ## On the compositor -/

open Fw.Engine.WebKit (CssProp) in
/-- The effect's keyframed properties. -/
def props : List CssProp := [.opacity, .filter]

theorem props_accelerated : Fw.Gate.PathPix.Accelerated props :=
  (Fw.Gate.PathPix.accelerated_iff props).1 rfl

/-- What `GraphicsLayerCA::addAnimation` reads of one animation (GraphicsLayerCA.cpp:1169-1196@862f17d). -/
structure CaAnim where
  rate : Rat
  forward : Bool
  dur : Rat
  kfs : Nat
  steps : Bool
  y1 : Rat
  y2 : Rat
  singleLinear : Bool
deriving Repr, DecidableEq

/-- Whether `GraphicsLayerCA::addAnimation` hands the animation to Core Animation: rate 1, forwards, non-zero
duration, at least two keyframes, no steps, and a cubic easing with both y controls in `[0, 1]` unless the keyframes
are one linear interval. -/
def caAccepts (a : CaAnim) : Bool :=
  a.rate == 1 && a.forward && a.dur != 0 && decide (2 ≤ a.kfs) && !a.steps &&
    ((decide (0 ≤ a.y1) && decide (a.y1 ≤ 1) && decide (0 ≤ a.y2) && decide (a.y2 ≤ 1)) || a.singleLinear)

/-- The effect of a push from `f` to `t` as `addAnimation` reads it. -/
def caOf (f t : Rat) : CaAnim :=
  ⟨1, true, duration, (keyframes f t).length, false, p1y, p2y, (keyframes f t).length == 2⟩

#guard caAccepts (caOf 0 1) && caAccepts (caOf 1 0) && caAccepts (caOf (1 / 4) 0)
#guard !caAccepts { caOf 0 1 with y1 := 3 / 2 } && caAccepts { caOf 1 (11 / 20) with y1 := 3 / 2 }
#guard !caAccepts { caOf 0 1 with kfs := 1 }

/-- **Core Animation runs every push's effect.** -/
theorem ca_accepts (f t : Rat) : caAccepts (caOf f t) = true := by
  have := keyframes_length f t
  simp only [caAccepts, caOf, duration, p1y, p2y]
  simp [this]
  exact Or.inl ⟨rfl, rfl⟩

/-- The section in arm B (the variant) as one PathPix claim: opacity and blur, text inside, no scale, no snap. -/
def claim : Fw.Gate.PathPix.Claim :=
  { props, scales := false, text := true, snap := false, compA := false, compB := true, bound := none }

/-- **The WebKit pixel ceiling.** A WebKit cell of this claim is graded neither E nor E1: CA's blur is not the
software blur, so the look is at most Q there. -/
theorem webkit_not_exact (c : Fw.Gate.PathPix.Cell) (h : c.claim = claim) (he : c.engine = .webkit) :
    Fw.Gate.PathPix.grade c ≠ .e ∧ Fw.Gate.PathPix.grade c ≠ .e1 :=
  Fw.Gate.PathPix.ca_blur_not_e c (by rw [h, he]; rfl)

/-! ## Why style and layout counts stay -/

/-- An element the tween writes inline on a frame. -/
inductive Tgt where
  | nav
  | platform
  deriving DecidableEq, Repr

/-- The original's inline writes on a frame from morph `a` to `b`: the nav's `--morph`, the section's `--morph-fade`. -/
def writesO (a b : Rat) : List (Tgt × String) :=
  (if a = b then [] else [(.nav, "--morph")]) ++ (if fade a = fade b then [] else [(.platform, "--morph-fade")])

/-- The variant's inline writes on that frame: only the nav's `--morph`. -/
def writesT (a b : Rat) : List (Tgt × String) := if a = b then [] else [(.nav, "--morph")]

/-- A frame with an inline write schedules a style recalculation. -/
def recalc (w : List (Tgt × String)) : Bool := !w.isEmpty

#guard writesO 0 (1 / 2) = [(.nav, "--morph"), (.platform, "--morph-fade")]
#guard writesO (3 / 5) (4 / 5) = [(.nav, "--morph")]
#guard writesT 0 (1 / 2) = [(.nav, "--morph")]
#guard writesT (1 / 2) (1 / 2) = []
#guard recalc (writesT 0 (1 / 2)) && !recalc (writesO 1 1)

/-- **No recalculation saved.** A frame recalculates style in the variant exactly when it does in the original: a
fade change needs a morph change, which writes the nav. -/
theorem recalc_same (a b : Rat) : recalc (writesT a b) = recalc (writesO a b) := by
  unfold recalc writesT writesO
  by_cases h : a = b
  · subst h; simp
  · simp [h]

/-- The variant drops exactly the section's write. -/
theorem writesT_sub (a b : Rat) : writesT a b = (writesO a b).filter (·.1 = .nav) := by
  unfold writesT writesO
  by_cases h : a = b <;> by_cases hf : fade a = fade b <;> simp [h, hf]

end Fw.Parts.PlatformFade
