import Fw.Measure.SimHost
import Fw.Measure.SimRetryData
/-! The scroll, pass and tab needs of the Simulator lane, chosen over the gate decisions of the 98 green sample jobs. -/
namespace Fw.Measure.SimRetryChoice
open Fw.Measure.SimHost Fw.Measure.SimRetryData

structure Needs where
  scroll : Nat
  pass : Nat
  tab : Nat
deriving DecidableEq, Repr

def Needs.le (c d : Needs) : Prop := c.scroll ≤ d.scroll ∧ c.pass ≤ d.pass ∧ c.tab ≤ d.tab

def Needs.of (c : Needs) : Kind → Nat
  | .scroll => c.scroll
  | .pass => c.pass
  | .tab => c.tab

def tabWaitS : Nat := tabNeedS (navWaitMs * ciScale)

def Premise (c : Needs) : Prop := Seen.tryS ≤ c.scroll ∧ Seen.headS + c.scroll ≤ c.pass ∧ tabWaitS ≤ c.tab

instance (c : Needs) : Decidable (Premise c) := by unfold Premise; infer_instance

def admits (c : Needs) (b maxTries : Nat) (d : Decision) : Bool :=
  match d.kind with
  | .tab => retryFits d.atS c.tab (some b)
  | k => afterFailure d.tries maxTries d.atS (c.of k) (some b)

def boundOf (j : Job) : Nat := gateBoundS (j.sessions * SimBound.perSessionMin)

def refused (c : Needs) (j : Job) : Bool := j.decisions.any fun d => !admits c (boundOf j) j.maxTries d

def refusedCount (c : Needs) (js : List Job) : Nat := js.countP (refused c)

def best : Needs := ⟨Seen.tryS, Seen.headS + Seen.tryS, tabWaitS⟩

def shipped : Needs := ⟨Seen.scrollRetryS, Seen.passRetryS, tabWaitS⟩

/-- The deployed needs: `best` unless it refuses more of `js` than `fallback` does. -/
def pick (best fallback : Needs) (js : List Job) : Needs :=
  if refusedCount best js ≤ refusedCount fallback js then best else fallback

def deployed : Needs := ⟨scrollNeedS, passNeedS, tabWaitS⟩

def grid : List Needs :=
  [⟨589, 436, 0⟩, ⟨589, 436, 480⟩, ⟨589, 1563, 0⟩, ⟨589, 1563, 480⟩,
   ⟨876, 436, 0⟩, ⟨876, 436, 480⟩, ⟨876, 1563, 0⟩, ⟨876, 1563, 480⟩]

theorem retryFits_mono {e n n' b : Nat} (h : n ≤ n') (hf : retryFits e n' (some b) = true) : retryFits e n (some b) = true :=
  le_retryFits (by have := retryFits_le hf; omega)

theorem admits_mono {c d : Needs} (h : c.le d) (b mt : Nat) (x : Decision) (ha : admits d b mt x = true) :
    admits c b mt x = true := by
  obtain ⟨hs, hp, ht⟩ := h
  unfold admits at ha ⊢
  cases hk : x.kind <;> simp only [hk, Needs.of] at ha ⊢
  · simp only [afterFailure, Bool.and_eq_true] at ha ⊢; exact ⟨ha.1, retryFits_mono hs ha.2⟩
  · simp only [afterFailure, Bool.and_eq_true] at ha ⊢; exact ⟨ha.1, retryFits_mono hp ha.2⟩
  · exact retryFits_mono ht ha

theorem refused_mono {c d : Needs} (h : c.le d) (j : Job) (hr : refused c j = true) : refused d j = true := by
  simp only [refused, List.any_eq_true, Bool.not_eq_true'] at hr ⊢
  obtain ⟨x, hx, hn⟩ := hr
  refine ⟨x, hx, ?_⟩
  cases hd : admits d (boundOf j) j.maxTries x
  · rfl
  · have := admits_mono h _ _ x hd; simp_all

theorem refusedCount_mono {c d : Needs} (h : c.le d) (js : List Job) : refusedCount c js ≤ refusedCount d js :=
  List.countP_mono_left fun j _ hr => refused_mono h j hr

theorem best_premise : Premise best := by decide

theorem premise_best_le {c : Needs} (h : Premise c) : best.le c := by
  obtain ⟨hs, hp, ht⟩ := h
  exact ⟨hs, by show Seen.headS + Seen.tryS ≤ c.pass; omega, ht⟩

theorem best_fewest {c : Needs} (h : Premise c) (js : List Job) : refusedCount best js ≤ refusedCount c js :=
  refusedCount_mono (premise_best_le h) js

theorem grid_fewest : ∀ c ∈ grid, Premise c → refusedCount best jobs ≤ refusedCount c jobs :=
  fun _ _ h => best_fewest h jobs

theorem pick_best {b f : Needs} {js : List Job} (h : refusedCount b js ≤ refusedCount f js) : pick b f js = b := by
  simp [pick, h]

theorem pick_fallback {b f : Needs} {js : List Job} (h : refusedCount f js < refusedCount b js) : pick b f js = f := by
  simp [pick, Nat.not_le.mpr h]

theorem best_refused : refusedCount best jobs = 14 := by decide

theorem shipped_refused : refusedCount shipped jobs = 10 := by decide

theorem shipped_untabbed_refused : refusedCount { shipped with tab := 0 } jobs = 1 := by decide

theorem deployed_is_pick : pick best shipped jobs = deployed := by
  rw [pick_fallback (by rw [best_refused, shipped_refused]; decide)]; rfl

theorem deployed_premise_unmet : ¬ Premise deployed := by decide

theorem best_stop_le (n m b : Nat) (ps : List PassTry)
    (hin : ∀ p ∈ ps, ∀ t ∈ p.scroll, t.reconS + t.runS ≤ Seen.tryS)
    (hhead : ∀ p ∈ ps, p.reconS + p.tabS + p.baseS ≤ Seen.headS) :
    ∀ k e, (runPass n m best.scroll best.pass best.tab b k e ps).stop ≤ max (e + best.pass) b ∧
      ((runPass n m best.scroll best.pass best.tab b k e ps).retried = true →
        (runPass n m best.scroll best.pass best.tab b k e ps).stop ≤ b) :=
  runPass_stop_le n m best.scroll best.pass best.tab b ps hin
    (fun p hp => by have := hhead p hp; show _ + Seen.tryS ≤ Seen.headS + Seen.tryS; omega)

#guard grid.map (fun c => (refusedCount c jobs, decide (Premise c))) ==
  [(1, false), (10, false), (8, false), (13, false), (3, false), (11, false), (9, false), (14, true)]
#guard pick best shipped jobs == deployed
#guard pick ⟨0, 0, 0⟩ shipped jobs == ⟨0, 0, 0⟩
#guard pick best best [] == best

end Fw.Measure.SimRetryChoice
