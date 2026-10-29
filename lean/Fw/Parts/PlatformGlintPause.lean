import Fw.Parts.PlatformGlint
/-!
# platform.glint:offscreen-pause

Models WebKit `862f17dcae0a` SMILTimeContainer.cpp:42-208 and SVGSVGElement.cpp:551-593; times in ms.
-/
namespace Fw.Parts.PlatformGlintPause
open Fw.Parts.PlatformGlint (St sample)

structure Cont where
  accum : Rat
  last : Rat
  paused : Bool
deriving Repr, DecidableEq

def Cont.start (b : Rat) : Cont := ⟨0, b, false⟩

def Cont.elapsed (c : Cont) (t : Rat) : Rat := if c.paused then c.accum else t + c.accum - c.last

def Cont.pause (c : Cont) (t : Rat) : Cont :=
  if c.paused then c else { accum := c.accum + (t - c.last), last := c.last, paused := true }

def Cont.resume (c : Cont) (t : Rat) : Cont :=
  if c.paused then { accum := c.accum, last := t, paused := false } else c

def Cont.seek (c : Cont) (t x : Rat) : Cont :=
  { accum := if c.paused then x else 0, last := t - x, paused := c.paused }

def ticks (c : Cont) (armed : Bool) : Nat := if c.paused then 0 else if armed then 1 else 0

theorem elapsed_start (b s : Rat) : (Cont.start b).elapsed s = s - b := by
  simp [Cont.start, Cont.elapsed]; grind

theorem pause_frozen (c : Cont) (t s : Rat) (h : c.paused = false) :
    (c.pause t).elapsed s = c.elapsed t := by
  simp [Cont.pause, Cont.elapsed, h]; grind

theorem pause_paused (c : Cont) (t : Rat) : (c.pause t).paused = true := by
  unfold Cont.pause; split <;> simp_all

theorem ticks_paused (c : Cont) (hp : c.paused = true) (armed : Bool) : ticks c armed = 0 := by
  simp [ticks, hp]

theorem seek_running (c : Cont) (t x s : Rat) (h : c.paused = false) : (c.seek t x).elapsed s = s - t + x := by
  simp [Cont.seek, Cont.elapsed, h]; grind

theorem resume_running (c : Cont) (t : Rat) : (c.resume t).paused = false := by
  unfold Cont.resume; split <;> simp_all

structure P where
  c : Cont
  off : Rat
deriving Repr, DecidableEq

inductive Obs
  | hide (t : Rat)
  | reveal (t : Rat)
deriving Repr, DecidableEq

def P.step (p : P) : Obs → P
  | .hide t => if p.c.paused then p else ⟨p.c.pause t, p.c.elapsed t - t⟩
  | .reveal t => if p.c.paused then ⟨(p.c.resume t).seek t (t + p.off), p.off⟩ else p

def P.target (p : P) (t : Rat) : Option Rat := if p.c.paused then some (t + p.off) else none

def Same (b : Rat) (p : P) : Prop :=
  p.off = -b ∧ (p.c.paused = false → ∀ s, p.c.elapsed s = s - b)

theorem same_start (b : Rat) : Same b ⟨Cont.start b, -b⟩ := ⟨rfl, fun _ s => elapsed_start b s⟩

theorem same_step (b : Rat) (p : P) (o : Obs) (h : Same b p) : Same b (p.step o) := by
  obtain ⟨ho, hr⟩ := h
  cases o with
  | hide t =>
    by_cases hp : p.c.paused = true
    · have e : p.step (.hide t) = p := by simp [P.step, hp]
      rw [e]; exact ⟨ho, hr⟩
    · have hp' : p.c.paused = false := by simpa using hp
      have e : p.step (.hide t) = ⟨p.c.pause t, p.c.elapsed t - t⟩ := by simp [P.step, hp]
      rw [e]
      refine ⟨?_, fun h => by simp [pause_paused] at h⟩
      show p.c.elapsed t - t = -b
      rw [hr hp']; grind
  | reveal t =>
    by_cases hp : p.c.paused = true
    · have e : p.step (.reveal t) = ⟨(p.c.resume t).seek t (t + p.off), p.off⟩ := by simp [P.step, hp]
      rw [e]
      refine ⟨ho, fun _ s => ?_⟩
      show ((p.c.resume t).seek t (t + p.off)).elapsed s = s - b
      rw [seek_running _ _ _ _ (resume_running _ _), ho]; grind
    · have e : p.step (.reveal t) = p := by simp [P.step, hp]
      rw [e]; exact ⟨ho, hr⟩

theorem same_run (b : Rat) (p : P) (h : Same b p) (os : List Obs) : Same b (os.foldl P.step p) := by
  induction os generalizing p with
  | nil => exact h
  | cons o os ih => exact ih _ (same_step b p o h)

def Obs.time : Obs → Rat
  | .hide t => t
  | .reveal t => t

def seeks (p : P) : List Obs → List (Rat × Rat)
  | [] => []
  | o :: os =>
    (match o with
      | .reveal t => if p.c.paused then [(p.c.elapsed t, t + p.off)] else []
      | .hide _ => []) ++ seeks (p.step o) os

def Fwd (b now : Rat) (p : P) : Prop := Same b p ∧ (p.c.paused = true → p.c.accum ≤ now - b)

theorem fwd_start (b now : Rat) : Fwd b now ⟨Cont.start b, -b⟩ := ⟨same_start b, by simp [Cont.start]⟩

theorem fwd_step (b now : Rat) (p : P) (o : Obs) (h : Fwd b now p) (ht : now ≤ o.time) : Fwd b o.time (p.step o) := by
  obtain ⟨hs, hf⟩ := h
  refine ⟨same_step b p o hs, ?_⟩
  cases o with
  | hide t =>
    simp only [Obs.time] at ht ⊢
    by_cases hp : p.c.paused = true
    · have e : p.step (.hide t) = p := by simp [P.step, hp]
      rw [e]; intro _; have := hf hp; grind
    · have hp' : p.c.paused = false := by simpa using hp
      have e : p.step (.hide t) = ⟨p.c.pause t, p.c.elapsed t - t⟩ := by simp [P.step, hp]
      rw [e]; intro _
      have he := hs.2 hp' t
      simp only [Cont.elapsed, hp', Bool.false_eq_true, ↓reduceIte] at he
      simp only [Cont.pause, hp', Bool.false_eq_true, ↓reduceIte]
      grind
  | reveal t =>
    by_cases hp : p.c.paused = true
    · have e : p.step (.reveal t) = ⟨(p.c.resume t).seek t (t + p.off), p.off⟩ := by simp [P.step, hp]
      rw [e]; simp [Cont.seek, resume_running]
    · have e : p.step (.reveal t) = p := by simp [P.step, hp]
      rw [e]; intro h'; exact absurd h' hp

theorem seek_head_forward (b now t : Rat) (p : P) (h : Fwd b now p) (ht : now ≤ t) (hp : p.c.paused = true) :
    p.c.elapsed t ≤ t + p.off := by
  have := h.2 hp
  simp only [Cont.elapsed, hp, ↓reduceIte, h.1.1]
  grind

theorem resume_seek_forward (b now : Rat) (p : P) (h : Fwd b now p) (os : List Obs)
    (hge : ∀ o ∈ os, now ≤ o.time) (hm : os.Pairwise fun a c => a.time ≤ c.time) :
    ∀ q ∈ seeks p os, q.1 ≤ q.2 := by
  induction os generalizing p now with
  | nil => simp [seeks]
  | cons o os ih =>
    have ho := hge o (by simp)
    have hm' := List.pairwise_cons.1 hm
    intro q hq
    simp only [seeks, List.mem_append] at hq
    rcases hq with hq | hq
    · cases o with
      | hide t => simp at hq
      | reveal t =>
        by_cases hp : p.c.paused = true
        · simp only [hp, ↓reduceIte, List.mem_singleton] at hq
          subst hq
          exact seek_head_forward b now t p h ho hp
        · simp [hp] at hq
    · exact ih o.time (p.step o) (fwd_step b now p o h ho) hm'.1 hm'.2 q hq

theorem resume_seek_forward_start (b : Rat) (os : List Obs) (hm : os.Pairwise fun a c => a.time ≤ c.time) :
    ∀ q ∈ seeks ⟨Cont.start b, -b⟩ os, q.1 ≤ q.2 := by
  cases os with
  | nil => simp [seeks]
  | cons o os =>
    refine resume_seek_forward b o.time _ (fwd_start b o.time) _ ?_ hm
    intro x hx
    rcases List.mem_cons.1 hx with rfl | hx
    · exact Rat.le_refl
    · exact (List.pairwise_cons.1 hm).1 x hx

#guard seeks ⟨Cont.start 0, 0⟩ [.hide 1000, .reveal 4000, .hide 6000, .reveal 6000] == [(1000, 4000), (6000, 6000)]

inductive Io
  | ratio (r : Rat)
  | reduced (b : Bool)
  | fire
deriving Repr

structure W where
  g : St
  p : P
  away : Bool
deriving Repr

def W.init (b : Rat) (reduced : Bool) : W :=
  ⟨Fw.Parts.PlatformGlint.init reduced, ⟨Cont.start b, -b⟩, false⟩

def W.step (w : W) (t : Rat) : Io → W
  | .ratio r =>
    { g := Fw.Parts.PlatformGlint.step w.g t (.ratio r)
      p := w.p.step (if r = 0 then .hide t else .reveal t)
      away := decide (r = 0) }
  | .reduced b => { w with g := Fw.Parts.PlatformGlint.step w.g t (.reduced b) }
  | .fire => { w with g := Fw.Parts.PlatformGlint.step w.g t .fire }

structure J (b : Rat) (w : W) : Prop where
  same : Same b w.p
  glint : Fw.Parts.PlatformGlint.Inv w.g
  seen : w.g.h = true → w.p.c.paused = false
  away : w.away = true → w.p.c.paused = true ∧ w.g.h = false

theorem J_init (b : Rat) (r : Bool) : J b (W.init b r) :=
  ⟨same_start b, Fw.Parts.PlatformGlint.inv_init r, by simp [W.init, Fw.Parts.PlatformGlint.init],
    by simp [W.init]⟩

theorem minRatio_zero : decide (Fw.Parts.PlatformGlint.minRatio ≤ 0) = false := by
  unfold Fw.Parts.PlatformGlint.minRatio
  simp only [decide_eq_false_iff_not, Rat.not_le]
  grind

theorem h_ratio (g : St) (t r : Rat) :
    (Fw.Parts.PlatformGlint.step g t (.ratio r)).h = decide (Fw.Parts.PlatformGlint.minRatio ≤ r) := by
  unfold Fw.Parts.PlatformGlint.step Fw.Parts.PlatformGlint.reset
  simp only []
  by_cases hb : (decide (Fw.Parts.PlatformGlint.minRatio ≤ r) == g.h) = true
  · simp only [hb, ite_true]; simp_all
  · simp [hb]

theorem h_reduced (g : St) (t : Rat) (b : Bool) : (Fw.Parts.PlatformGlint.step g t (.reduced b)).h = g.h := by
  simp [Fw.Parts.PlatformGlint.step, Fw.Parts.PlatformGlint.reset]

theorem h_fire (g : St) (t : Rat) : (Fw.Parts.PlatformGlint.step g t .fire).h = g.h := by
  unfold Fw.Parts.PlatformGlint.step
  cases g.timer with
  | none => rfl
  | some d => simp only []; split <;> rfl

theorem J_step (b : Rat) (w : W) (t : Rat) (e : Io) (hj : J b w) : J b (w.step t e) := by
  obtain ⟨hs, hg, hseen, haway⟩ := hj
  cases e with
  | ratio r =>
    have hh := h_ratio w.g t r
    have hP : Same b (w.p.step (if r = 0 then .hide t else .reveal t)) := same_step b _ _ hs
    refine ⟨hP, Fw.Parts.PlatformGlint.inv_step _ _ _ hg, ?_, ?_⟩
    · intro hh'
      simp only [W.step] at hh' ⊢
      by_cases h0 : r = 0
      · subst h0
        rw [minRatio_zero] at hh
        simp [hh] at hh'
      · have : (if r = 0 then Obs.hide t else Obs.reveal t) = Obs.reveal t := by simp [h0]
        rw [this]
        by_cases hp : w.p.c.paused = true
        · have e : w.p.step (.reveal t) = ⟨(w.p.c.resume t).seek t (t + w.p.off), w.p.off⟩ := by simp [P.step, hp]
          rw [e]; simp [resume_running, Cont.seek]
        · have e : w.p.step (.reveal t) = w.p := by simp [P.step, hp]
          rw [e]; simpa using hp
    · intro ha
      simp only [W.step, decide_eq_true_eq] at ha ⊢
      subst ha
      refine ⟨?_, ?_⟩
      · simp only [ite_true]
        by_cases hp : w.p.c.paused = true
        · have e : w.p.step (.hide t) = w.p := by simp [P.step, hp]
          rw [e]; exact hp
        · have e : w.p.step (.hide t) = ⟨w.p.c.pause t, w.p.c.elapsed t - t⟩ := by simp [P.step, hp]
          rw [e]; exact pause_paused _ _
      · rw [minRatio_zero] at hh
        exact hh
  | reduced bb =>
    refine ⟨hs, Fw.Parts.PlatformGlint.inv_step _ _ _ hg, ?_, ?_⟩
    · intro hh'; simp only [W.step, h_reduced] at hh'; exact hseen hh'
    · intro ha; simp only [W.step, h_reduced]; exact haway ha
  | fire =>
    refine ⟨hs, Fw.Parts.PlatformGlint.inv_step _ _ _ hg, ?_, ?_⟩
    · intro hh'; simp only [W.step, h_fire] at hh'; exact hseen hh'
    · intro ha; simp only [W.step, h_fire]; exact haway ha

theorem J_run (b : Rat) (w : W) (hj : J b w) (es : List (Rat × Io)) :
    J b (es.foldl (fun w x => w.step x.1 x.2) w) := by
  induction es generalizing w with
  | nil => exact hj
  | cons x es ih => exact ih _ (J_step b w x.1 x.2 hj)

theorem visible_same_phase (b : Rat) (w : W) (hj : J b w) (hv : w.g.v = true) (s : Rat) :
    w.p.c.paused = false ∧ w.p.c.elapsed s = s - b := by
  have hh : w.g.h = true := (hj.glint.1 hv).1
  have hp := hj.seen hh
  exact ⟨hp, hj.same.2 hp s⟩

theorem local_time_same (b : Rat) (w1 w2 : W) (h1 : J b w1) (h2 : J b w2) (v1 : w1.g.v = true) (v2 : w2.g.v = true)
    (t0 s : Rat) (side : Fw.Parts.PlatformGlint.Side) :
    sample side (w2.p.c.elapsed s - w1.p.c.elapsed t0) = sample side (s - t0) := by
  rw [(visible_same_phase b w1 h1 v1 t0).2, (visible_same_phase b w2 h2 v2 s).2]
  congr 1; grind

theorem faithful_local_time (b s t0 : Rat) (side : Fw.Parts.PlatformGlint.Side) :
    sample side ((Cont.start b).elapsed s - (Cont.start b).elapsed t0) = sample side (s - t0) := by
  rw [elapsed_start, elapsed_start]; congr 1; grind

theorem variant_no_ticks_away (b : Rat) (w : W) (hj : J b w) (ha : w.away = true) (armed : Bool) :
    ticks w.p.c armed = 0 :=
  ticks_paused _ (hj.away ha).1 armed

theorem faithful_no_ticks_away (b : Rat) (w : W) (hj : J b w) (ha : w.away = true) (c : Cont) :
    ticks c w.g.v = 0 := by
  have hh := (hj.away ha).2
  have hv : w.g.v = false := by
    cases hv : w.g.v
    · rfl
    · have := (hj.glint.1 hv).1; simp_all
  simp [ticks, hv]

theorem away_ticks_equal (b : Rat) (w : W) (hj : J b w) (ha : w.away = true) :
    ticks (Cont.start b) w.g.v = ticks w.p.c w.g.v :=
  (faithful_no_ticks_away b w hj ha _).trans (variant_no_ticks_away b w hj ha _).symm

theorem window_gain (b : Rat) (w : W) (hj : J b w) (ha : w.away = true) :
    ticks w.p.c true = 0 ∧ ticks (Cont.start b) true = 1 :=
  ⟨variant_no_ticks_away b w hj ha true, by simp [ticks, Cont.start]⟩

def eg : P := ((⟨Cont.start 0, 0⟩ : P).step (.hide 1000)).step (.reveal 4000)

#guard eg.c.elapsed 4000 == 4000
#guard eg.c.elapsed 4500 == 4500
#guard (((⟨Cont.start 0, 0⟩ : P).step (.hide 1000)).c.elapsed 3000) == 1000
#guard ((Cont.start 0).pause 1000 |>.resume 4000).elapsed 4000 == 1000

end Fw.Parts.PlatformGlintPause
