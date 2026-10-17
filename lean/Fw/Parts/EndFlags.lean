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

$$\forall d \in \mathbb{B},\ \forall as \in \mathrm{FlagOp}^{*}:\ \operatorname{fF}(d, as) = 0 \land (d \lor \mathrm{dirty} \in as) \Rightarrow \operatorname{fE}(d, as) = \top$$

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

$$\forall E,\ \forall f \in \mathrm{FrameIn}(P),\ \forall e : \mathrm{Stage} \to \mathbb{B}:\ (\forall s \in \operatorname{touched}_E(f):\ e(s) = \top) \Rightarrow \operatorname{frameWork}^{e}_E(f) = \operatorname{frameWork}_E(f)$$

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

$$\forall E,\ \forall v, o \in \mathrm{FrameIn}(P),\ \forall e : \mathrm{Stage} \to \mathbb{B}:\ (\forall s:\ \operatorname{forced}(v, s) = \operatorname{forced}(o, s)) \land \operatorname{frameWork}_E(v) \preceq \operatorname{frameWork}_E(o) \Rightarrow \operatorname{frameWork}^{e}_E(v) \preceq \operatorname{frameWork}^{e}_E(o)$$

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

$$\forall E,\ \forall v, o,\ \forall e_v, e_o:\ \big(\forall s:\ s \in \operatorname{touched}_E(v) \Rightarrow s \in \operatorname{touched}_E(o)\big) \land \big(\forall s:\ \operatorname{units}_E(v, s) \le \operatorname{units}_E(o, s)\big) \land v.\mathrm{hits} \le o.\mathrm{hits} \land \big(\forall s:\ \operatorname{forced}(v, s) \le \operatorname{forced}(o, s)\big) \land \big(\forall s \in \operatorname{touched}_E(v):\ \operatorname{forced}(v, s) + [e_v(s)] \le \operatorname{forced}(o, s) + [e_o(s)]\big) \Rightarrow \operatorname{frameWork}^{e_v}_E(v) \preceq \operatorname{frameWork}^{e_o}_E(o)$$

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

$$\forall E, v, o, e_v, e_o, s_0:\ \text{hyp.\ of } \texttt{frameE\_le\_of\_total} \land \operatorname{forced}(v, s_0) < \operatorname{forced}(o, s_0) \land \big(s_0 \in \operatorname{touched}_E(v) \Rightarrow \operatorname{forced}(v, s_0) + [e_v(s_0)] < \operatorname{forced}(o, s_0) + [e_o(s_0)]\big) \Rightarrow \operatorname{frameWork}^{e_v}_E(v) \prec \operatorname{frameWork}^{e_o}_E(o)$$

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

$$\forall E, v, o, e_v, e_o:\ \text{hyp.\ of } \texttt{frameE\_le\_of\_total} \land v.\mathrm{hits} < o.\mathrm{hits} \Rightarrow \operatorname{frameWork}^{e_v}_E(v) \prec \operatorname{frameWork}^{e_o}_E(o)$$

A saved hit test is a strict win in either model. -/
theorem frameE_lt_of_hits {P M : Type} (E : Engine P M) {v o : FrameIn P} (ev eo : Stage → Bool)
    (ht : ∀ s, s ∈ touched E v → s ∈ touched E o) (hu : ∀ s, stageUnits E v s ≤ stageUnits E o s)
    (hh : v.hits < o.hits) (hf : ∀ s, forcedPasses v s ≤ forcedPasses o s)
    (htot : ∀ s, s ∈ touched E v → forcedPasses v s + (ev s).toNat ≤ forcedPasses o s + (eo s).toNat) :
    (frameWorkE E v ev).lt (frameWorkE E o eo) :=
  ⟨frameE_le_of_total E ev eo ht hu (Nat.le_of_lt hh) hf htot, Or.inr hh⟩

/-- `frameWork`'s order gives the touched-stage inclusion when forced passes are equal.

$$\forall E,\ \forall v, o:\ (\forall s:\ \operatorname{forced}(v, s) = \operatorname{forced}(o, s)) \land \operatorname{frameWork}_E(v) \preceq \operatorname{frameWork}_E(o) \Rightarrow \forall s:\ s \in \operatorname{touched}_E(v) \Rightarrow s \in \operatorname{touched}_E(o)$$

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

#guard flagEnd false [.check, .dirty, .neutral] == true
#guard flagForced false [.check, .dirty, .neutral] == 0

end Fw.Parts.EndFlags
