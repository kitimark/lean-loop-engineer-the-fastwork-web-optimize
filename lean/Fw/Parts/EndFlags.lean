import Fw.Engine.Core

/-!
# End flags for the parts: moving per-part proofs from `frameWork` to `frameWorkE`

`Fw.Engine.frameWork` charges every touched stage one lifecycle pass; `Fw.Engine.frameWorkE` charges it only when the
stage's flag is still dirty at frame end (ledger n=1, `Fw.Engine.frameWork_overcount`). The per-part proofs were
written against `frameWork`. This module holds the transfer lemmas the parts use:

* **read-free frames** (`forcedStyle = forcedLayout = 0`): a touched stage that no read cleans ends dirty
  (`flagEnd_of_forced_zero`), so the faithful end flags are all `true` on touched stages and `frameWorkE` *is*
  `frameWork` (`frameWorkE_eq_of_dirty`). Every verdict of such a part carries over unchanged.
* **same script, different changes** (pause, skip writes, lifted engines): with equal forced passes, a `frameWork`
  order gives the `frameWorkE` order for every common end-flag assignment (`frameE_le_of_same_forced`).
* **different scripts** (nav probes, gates): a stage-wise bound on forced plus end passes (`frameE_le_of_total`,
  `frameE_lt_of_total`).
-/

namespace Fw.Parts.EndFlags

open Fw.Engine

/-- **A read-free stage ends dirty.** If an access sequence forces no pass and the stage is dirty at the start or the
sequence writes, the flag is dirty at the end.

Nothing that never forces a pass can have cleaned the flag. -/
theorem flagEnd_of_forced_zero : ∀ (d : Bool) (as : List FlagOp),
    flagForced d as = 0 → (d = true ∨ FlagOp.dirty ∈ as) → flagEnd d as = true
  | d, [], _, h => by simpa [flagEnd] using h
  | d, .check :: as, hf, h => by
    simp only [flagForced] at hf
    have hd : d = false := by cases d <;> simp_all
    subst hd
    have hm : FlagOp.dirty ∈ as := by simpa using h
    exact flagEnd_of_forced_zero false as (by omega) (Or.inr hm)
  | _, .dirty :: as, hf, _ => flagEnd_of_forced_zero true as hf (Or.inl rfl)
  | d, .neutral :: as, hf, h => flagEnd_of_forced_zero d as hf (by simpa using h)

/-- **All touched stages dirty: `frameWorkE` is `frameWork`.** If the end-flag assignment is true on every touched
stage, the corrected work equals the old work.

On a frame whose touched stages all end dirty, the old model has no over-count. -/
theorem frameWorkE_eq_of_dirty {P M : Type} (E : Engine P M) (f : FrameIn P) (e : Stage → Bool)
    (h : ∀ s, s ∈ touched E f → e s = true) : frameWorkE E f e = frameWork E f := by
  unfold frameWorkE frameWork
  congr 1
  funext s
  by_cases ht : s ∈ touched E f <;> simp [ht, h s]

/-- **Same forced passes: the order transfers.** If two frames have the same forced passes on every stage and the
variant does no more `frameWork` than the original, then it does no more `frameWorkE` work for every common end-flag
assignment.

When the script is the same, the end flags are the same and the old proof still holds. -/
theorem frameE_le_of_same_forced {P M : Type} (E : Engine P M) {v o : FrameIn P} (e : Stage → Bool)
    (hF : ∀ s, forcedPasses v s = forcedPasses o s) (hle : (frameWork E v).le (frameWork E o)) :
    (frameWorkE E v e).le (frameWorkE E o e) := by
  refine ⟨fun s => ⟨?_, (hle.1 s).2⟩, hle.2⟩
  have h := (hle.1 s).1
  simp only [frameWork, frameWorkE, hF s] at h ⊢
  by_cases hv : s ∈ touched E v <;> by_cases ho : s ∈ touched E o <;> cases e s <;> simp_all

/-- **Stage-wise end-flag bound.** The variant does no more `frameWorkE` work than the original if its touched stages
are touched by the original, its `frameWork` units and hits are no larger, its forced passes are no larger on every
stage, and on every stage it touches its forced plus end passes are no larger.

A variant that never ends a stage dirtier than the original without paying for it in forced passes is no costlier. -/
theorem frameE_le_of_total {P M : Type} (E : Engine P M) {v o : FrameIn P} (ev eo : Stage → Bool)
    (ht : ∀ s, s ∈ touched E v → s ∈ touched E o) (hu : ∀ s, stageUnits E v s ≤ stageUnits E o s)
    (hh : v.hits ≤ o.hits) (hf : ∀ s, forcedPasses v s ≤ forcedPasses o s)
    (htot : ∀ s, s ∈ touched E v → forcedPasses v s + (ev s).toNat ≤ forcedPasses o s + (eo s).toNat) :
    (frameWorkE E v ev).le (frameWorkE E o eo) := by
  refine ⟨fun s => ⟨?_, hu s⟩, hh⟩
  simp only [frameWorkE]
  have h1 := hf s
  by_cases hv : s ∈ touched E v
  · have h2 := htot s hv
    have ho := ht s hv
    simp only [hv, ho, true_and]
    revert h2; cases ev s <;> cases eo s <;> simp <;> omega
  · simp only [hv, false_and, ↓reduceIte]
    split <;> omega

/-- **Stage-wise strictness.** Under the hypotheses of `frameE_le_of_total`, a stage with strictly fewer forced passes
and, if the variant touches it, strictly fewer forced plus end passes makes the variant strictly cheaper.

A forced pass saved and not paid back at frame end is a strict win. -/
theorem frameE_lt_of_total {P M : Type} (E : Engine P M) {v o : FrameIn P} (ev eo : Stage → Bool)
    (ht : ∀ s, s ∈ touched E v → s ∈ touched E o) (hu : ∀ s, stageUnits E v s ≤ stageUnits E o s)
    (hh : v.hits ≤ o.hits) (hf : ∀ s, forcedPasses v s ≤ forcedPasses o s)
    (htot : ∀ s, s ∈ touched E v → forcedPasses v s + (ev s).toNat ≤ forcedPasses o s + (eo s).toNat)
    (s0 : Stage) (hf0 : forcedPasses v s0 < forcedPasses o s0)
    (htot0 : s0 ∈ touched E v → forcedPasses v s0 + (ev s0).toNat < forcedPasses o s0 + (eo s0).toNat) :
    (frameWorkE E v ev).lt (frameWorkE E o eo) := by
  refine ⟨frameE_le_of_total E ev eo ht hu hh hf htot, Or.inl ⟨s0, Or.inl ?_⟩⟩
  simp only [frameWorkE]
  by_cases hv : s0 ∈ touched E v
  · have h2 := htot0 hv
    have ho := ht s0 hv
    simp only [hv, ho, true_and]
    revert h2; cases ev s0 <;> cases eo s0 <;> simp <;> omega
  · simp only [hv, false_and, ↓reduceIte]
    split <;> omega

/-- Strictness from hits carries over to every end-flag assignment pair that satisfies the stage-wise bound.

A saved hit test is a strict win in either model. -/
theorem frameE_lt_of_hits {P M : Type} (E : Engine P M) {v o : FrameIn P} (ev eo : Stage → Bool)
    (ht : ∀ s, s ∈ touched E v → s ∈ touched E o) (hu : ∀ s, stageUnits E v s ≤ stageUnits E o s)
    (hh : v.hits < o.hits) (hf : ∀ s, forcedPasses v s ≤ forcedPasses o s)
    (htot : ∀ s, s ∈ touched E v → forcedPasses v s + (ev s).toNat ≤ forcedPasses o s + (eo s).toNat) :
    (frameWorkE E v ev).lt (frameWorkE E o eo) :=
  ⟨frameE_le_of_total E ev eo ht hu (Nat.le_of_lt hh) hf htot, Or.inr hh⟩

/-- `frameWork`'s order gives the touched-stage inclusion when forced passes are equal.

With the same script, a smaller old count means fewer touched stages. -/
theorem touched_of_le_same_forced {P M : Type} (E : Engine P M) {v o : FrameIn P}
    (hF : ∀ s, forcedPasses v s = forcedPasses o s) (hle : (frameWork E v).le (frameWork E o)) :
    ∀ s, s ∈ touched E v → s ∈ touched E o := by
  intro s hv
  have h := (hle.1 s).1
  simp only [frameWork, hF s, hv] at h
  by_cases ho : s ∈ touched E o
  · exact ho
  · simp [ho] at h; omega

/-! ## Transfer of whole verdicts -/

/-- **Read-free transfer of `≤`.** If both frames' end-flag assignments are true on every touched stage (what a frame
with no forced read gets, `flagEnd_of_forced_zero`), a `frameWork` bound is a `frameWorkE` bound.

With nothing cleaning a flag, both models count the same. -/
theorem frameE_le_of_dirty {P M : Type} (E : Engine P M) {v o : FrameIn P} (ev eo : Stage → Bool)
    (hv : ∀ s, s ∈ touched E v → ev s = true) (ho : ∀ s, s ∈ touched E o → eo s = true)
    (h : (frameWork E v).le (frameWork E o)) : (frameWorkE E v ev).le (frameWorkE E o eo) := by
  rw [frameWorkE_eq_of_dirty E v ev hv, frameWorkE_eq_of_dirty E o eo ho]; exact h

/-- **Read-free transfer of `≺`.**

A strict win with nothing cleaning a flag stays strict. -/
theorem frameE_lt_of_dirty {P M : Type} (E : Engine P M) {v o : FrameIn P} (ev eo : Stage → Bool)
    (hv : ∀ s, s ∈ touched E v → ev s = true) (ho : ∀ s, s ∈ touched E o → eo s = true)
    (h : (frameWork E v).lt (frameWork E o)) : (frameWorkE E v ev).lt (frameWorkE E o eo) := by
  rw [frameWorkE_eq_of_dirty E v ev hv, frameWorkE_eq_of_dirty E o eo ho]; exact h

/-- **Read-free transfer of `⋠`** (a trade or a loss stays one).

A read-free frame that costs more in one stage still does. -/
theorem frameE_not_le_of_dirty {P M : Type} (E : Engine P M) {v o : FrameIn P} (ev eo : Stage → Bool)
    (hv : ∀ s, s ∈ touched E v → ev s = true) (ho : ∀ s, s ∈ touched E o → eo s = true)
    (h : ¬ (frameWork E v).le (frameWork E o)) : ¬ (frameWorkE E v ev).le (frameWorkE E o eo) := by
  rw [frameWorkE_eq_of_dirty E v ev hv, frameWorkE_eq_of_dirty E o eo ho]; exact h

/-- **Same forced passes, end flags no dirtier: `≤` transfers.** If the frames force the same passes, the variant
does no more `frameWork` work, and on every stage the variant touches its end flag is dirty only if the original's
is, then the variant does no more `frameWorkE` work.

Removing writes under the same reads cannot leave a stage dirtier. -/
theorem frameE_le_mono {P M : Type} (E : Engine P M) {v o : FrameIn P} (ev eo : Stage → Bool)
    (hF : ∀ s, forcedPasses v s = forcedPasses o s) (hle : (frameWork E v).le (frameWork E o))
    (hm : ∀ s, s ∈ touched E v → ev s = true → eo s = true) :
    (frameWorkE E v ev).le (frameWorkE E o eo) := by
  refine frameE_le_of_total E ev eo (touched_of_le_same_forced E hF hle) (fun s => (hle.1 s).2) hle.2
    (fun s => Nat.le_of_eq (hF s)) (fun s hs => ?_)
  have := hm s hs
  rw [hF s]; revert this; cases ev s <;> cases eo s <;> simp

/-- **Same forced passes: a strict saving in units or hits transfers.** Under the hypotheses of `frameE_le_mono`, a
stage with fewer units, or fewer hits, keeps the variant strictly cheaper.

Units and hits do not depend on the end flags. -/
theorem frameE_lt_mono {P M : Type} (E : Engine P M) {v o : FrameIn P} (ev eo : Stage → Bool)
    (hF : ∀ s, forcedPasses v s = forcedPasses o s) (hle : (frameWork E v).le (frameWork E o))
    (hm : ∀ s, s ∈ touched E v → ev s = true → eo s = true)
    (hs : (∃ s, stageUnits E v s < stageUnits E o s) ∨ v.hits < o.hits) :
    (frameWorkE E v ev).lt (frameWorkE E o eo) := by
  refine ⟨frameE_le_mono E ev eo hF hle hm, ?_⟩
  rcases hs with ⟨s, h⟩ | h
  · exact Or.inl ⟨s, Or.inr h⟩
  · exact Or.inr h

#guard flagEnd false [.check, .dirty, .neutral] == true
#guard flagForced false [.check, .dirty, .neutral] == 0

end Fw.Parts.EndFlags
