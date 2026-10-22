import Lean.Data.Json
import Fw.Parts.MorphPanelThreaded
import Fw.Parts.PlatformFadeRun
import Fw.Parts.Bezier

namespace Fw.Parts.MorphPanelThreaded
open Fw.Parts.MorphTween Fw.Parts.MorphTweenOpt Fw.Parts.MorphPanel Fw.Parts.PlatformFade

structure Tri where
  op : Rat
  blur : Rat
  sc : Rat
deriving Repr, DecidableEq

def triOf (m : Rat) : Tri := ⟨panelOpacity m, panelBlurPx m, panelScale m⟩

def valP (P : WaapiPremises) (e : Eff) (T : Rat) : Tri :=
  let q := P.timing (progress e.st T)
  ⟨interpKf P.interp (track panelOpacity e.f e.t) q, interpKf P.interp (track panelBlurPx e.f e.t) q,
    interpKf P.interp (track panelScale e.f e.t) q⟩

theorem frame_eq (P : WaapiPremises) (f t n R : Rat) :
    valP P ⟨f, t, P.startRead n⟩ (P.tl R) = triOf (tween f t (R - n)).value := by
  unfold valP triOf
  simp only [interpKf_lin, timing_progress, tween_value_eq]
  have := ease_mem ((R - n) / duration)
  have h := interp_eq f t _ this.1 this.2
  rw [h.1, h.2.1, h.2.2]

structure PSt where
  eff : Option Eff
  base : Rat
  shown : Tri
deriving Repr, DecidableEq

def initP : PSt := ⟨none, 0, triOf 0⟩

def stepP (P : WaapiPremises) (s : St) (x : PSt) : Ev → PSt
  | .push g rm n =>
    if s.target = g ∧ s.t = g then x
    else if rm then ⟨none, g, triOf g⟩
    else { x with eff := some ⟨s.value, g, P.startRead n⟩ }
  | .tick R =>
    match x.eff with
    | some e => if finished e (P.tl R) then ⟨none, e.t, valP P e (P.tl R)⟩ else { x with shown := valP P e (P.tl R) }
    | none => { x with shown := triOf x.base }

def runP (P : WaapiPremises) (s : St) (x : PSt) : List Ev → St × PSt
  | [] => (s, x)
  | e :: es => runP P (stepO s e) (stepP P s x e) es

def InvP (P : WaapiPremises) (s : St) (x : PSt) : Prop :=
  x.shown = triOf s.value ∧
    (s.pending = true → x.eff = some ⟨s.f, s.t, P.startRead s.start⟩) ∧
    (s.pending = false → x.eff = none ∧ x.base = s.value)

theorem invP_init (P : WaapiPremises) : InvP P rest initP := by
  unfold InvP rest initP; simp

theorem invP_push (P : WaapiPremises) (s : St) (x : PSt) (g : Rat) (rm : Bool) (n : Rat) (h : InvP P s x) :
    InvP P (stepO s (.push g rm n)) (stepP P s x (.push g rm n)) := by
  obtain ⟨hs, hp, hn⟩ := h
  simp only [stepO, stepP, push]
  by_cases hg : s.target = g ∧ s.t = g
  · simp only [hg, and_self, ite_true]; exact ⟨hs, hp, hn⟩
  · simp only [hg, ite_false]
    cases rm
    · simp only [Bool.false_eq_true, ite_false]
      exact ⟨hs, fun _ => rfl, fun h => by simp at h⟩
    · simp only [ite_true]
      exact ⟨rfl, fun h => by simp at h, fun _ => ⟨rfl, rfl⟩⟩

theorem invP_tick (P : WaapiPremises) (s : St) (x : PSt) (R : Rat) (h : InvP P s x) :
    InvP P (stepO s (.tick R)) (stepP P s x (.tick R)) := by
  obtain ⟨hs, hp, hn⟩ := h
  cases hpd : s.pending
  · obtain ⟨he, hb⟩ := hn hpd
    simp only [stepO, stepP, hpd, Bool.false_eq_true, ite_false, he]
    exact ⟨by rw [hb], fun h => by simp [hpd] at h, fun _ => ⟨rfl, hb⟩⟩
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
    simp only [stepO, stepP, hpd, ite_true, he, frame]
    rw [hfin]
    cases hd : (tween s.f s.t (R - s.start)).done
    · simp only [Bool.false_eq_true, ite_false, Bool.not_false]
      exact ⟨hv, fun _ => rfl, fun h => by simp at h⟩
    · simp only [ite_true, Bool.not_true]
      have hend := tween_end s.f s.t (R - s.start) ((tween_done_iff _ _ _).1 hd)
      refine ⟨hv, fun h => by simp at h, fun _ => ⟨rfl, ?_⟩⟩
      rw [hend]

theorem invP_run (P : WaapiPremises) :
    ∀ (es : List Ev) (s : St) (x : PSt), InvP P s x → InvP P (runP P s x es).1 (runP P s x es).2
  | [], _, _, h => h
  | .push g rm n :: es, s, x, h => invP_run P es _ _ (invP_push P s x g rm n h)
  | .tick R :: es, s, x, h => invP_run P es _ _ (invP_tick P s x R h)

theorem runP_fst (P : WaapiPremises) : ∀ (es : List Ev) (s : St) (x : PSt), (runP P s x es).1 = runO s es
  | [], _, _ => rfl
  | e :: es, s, x => by simp only [runP, runO, List.foldl_cons]; exact runP_fst P es _ _

theorem threaded_eq (P : WaapiPremises) (es : List Ev) :
    (runP P rest initP es).2.shown = triOf (runO rest es).value := by
  rw [← runP_fst P es rest initP]
  exact (invP_run P es rest initP (invP_init P)).1

theorem retarget_from_shown (P : WaapiPremises) (s : St) (x : PSt) (g n : Rat) (h : InvP P s x)
    (hm : ¬ (s.target = g ∧ s.t = g)) :
    (stepP P s x (.push g false n)).eff.map
        (fun e => ((track panelOpacity e.f e.t).head?, (track panelBlurPx e.f e.t).head?, (track panelScale e.f e.t).head?)) =
      some (some ⟨0, x.shown.op⟩, some ⟨0, x.shown.blur⟩, some ⟨0, x.shown.sc⟩) := by
  have hs := h.1
  simp only [stepP, hm, ite_false, Bool.false_eq_true, Option.map_some, track, offs, List.map_cons, List.head?_cons,
    mAt_zero, hs, triOf]

theorem reduced_never_installs (P : WaapiPremises) (s : St) (x : PSt) (g n : Rat) (hm : ¬ (s.target = g ∧ s.t = g)) :
    (stepP P s x (.push g true n)).eff = none := by
  simp [stepP, hm]

theorem reduced_run_none (P : WaapiPremises) :
    ∀ (es : List Ev) (s : St) (x : PSt), x.eff = none → (∀ e ∈ es, ∀ g n, e ≠ .push g false n) →
      (runP P s x es).2.eff = none
  | [], _, _, h, _ => h
  | .push g rm n :: es, s, x, h, hr => by
    have : rm = true := by
      cases rm
      · exact absurd rfl (hr _ (List.mem_cons_self ..) g n)
      · rfl
    subst this
    refine reduced_run_none P es _ _ ?_ (fun e he => hr e (List.mem_cons_of_mem _ he))
    by_cases hg : s.target = g ∧ s.t = g
    · simp [stepP, hg, h]
    · simp [stepP, hg]
  | .tick R :: es, s, x, h, hr => by
    refine reduced_run_none P es _ _ ?_ (fun e he => hr e (List.mem_cons_of_mem _ he))
    simp only [stepP, h]

def caOf (f t : Rat) : CaAnim :=
  ⟨1, true, duration, (offs f t).length, false, p1y, p2y, (offs f t).length == 2⟩

theorem offs_length (f t : Rat) : 2 ≤ (offs f t).length := by
  unfold offs; simp

theorem ca_accepts (f t : Rat) : caAccepts (caOf f t) = true := by
  have := offs_length f t
  simp only [caAccepts, caOf, duration, p1y, p2y]
  simp [this]
  exact Or.inl ⟨rfl, rfl⟩

#guard caAccepts (caOf 0 1) && caAccepts (caOf 1 0) && caAccepts (caOf (1 / 2) 0) && caAccepts (caOf 0 (1 / 25))

def effects : List (List Anim3) := [[.opacity, .transform], [.filter]]

theorem effects_cover (a : Anim3) : (effects.flatten.count a = 1) := by
  cases a <;> decide

theorem filter_alone : ∀ e ∈ effects, Anim3.filter ∈ e → e = [.filter] := by decide

def panelBez : Fw.Parts.Bezier.Bez := ⟨1 / 3, 1, 2 / 3, 1⟩

theorem panelBez_eq : (panelBez.x1, panelBez.y1, panelBez.x2, panelBez.y2) = easing := rfl

theorem bx_panel (s : Rat) : Fw.Parts.Bezier.bx panelBez s = s := by
  unfold Fw.Parts.Bezier.bx Fw.Parts.Bezier.coord panelBez
  grind

theorem by_panel (s : Rat) (h0 : 0 ≤ s) (h1 : s ≤ 1) : Fw.Parts.Bezier.by' panelBez s = Fw.Parts.MorphTween.ease s := by
  unfold Fw.Parts.Bezier.by' Fw.Parts.Bezier.coord panelBez Fw.Parts.MorphTween.ease Fw.Parts.MorphTween.clamp01
  grind

theorem ease_err (t : Rat) (ht0 : 0 < t) (ht1 : t < 1) :
    (Fw.Parts.Bezier.ease panelBez t - Fw.Parts.MorphTween.ease t) * 2 ^ 41 ≤ 3 ∧
      (Fw.Parts.MorphTween.ease t - Fw.Parts.Bezier.ease panelBez t) * 2 ^ 41 ≤ 3 := by
  have h := Fw.Parts.Bezier.ease_err panelBez t ht0 ht1 (by unfold panelBez; grind) (by unfold panelBez; grind) (by unfold panelBez; grind)
    (by unfold panelBez; grind) (by unfold panelBez; grind) (by unfold panelBez; grind) (by unfold panelBez; grind)
    (by unfold panelBez; grind) t (by grind) (by grind) (bx_panel t)
  rw [by_panel t (by grind) (by grind)] at h
  have e : Fw.Parts.Bezier.steps + 1 = 41 := rfl
  rw [e] at h
  exact h

end Fw.Parts.MorphPanelThreaded
