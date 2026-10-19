import Fw.Guidance.Basic
/-!
# Guidance rules on style and layout reads: layout thrashing, JS size measurement, `:has()` scope

Rules `perf.inp.layout-thrashing`, `css.no-js-size-measurement` and `css.has-scope`. The first two use the dirty-flag
machine of `Fw.Engine.Core`, which both engine models share; the third uses each engine's style stage.
-/
namespace Fw.Guidance.Style

open Fw.Engine

/-- `n` write-then-read pairs.

The thrashing pattern: each read follows a write. -/
def interleaved : Nat → List FlagOp
  | 0 => []
  | n + 1 => .dirty :: .check :: interleaved n

/-- `r` reads, then `w` writes.

The guide's pattern: all reads before all writes. -/
def batched (r w : Nat) : List FlagOp := List.replicate r .check ++ List.replicate w .dirty

#guard flagTotal false (interleaved 3) == 3 && flagTotal false (batched 3 3) == 1 && flagTotal true (batched 3 3) == 2

/-- From a clean flag, `n` write-then-read pairs cost `n` passes.

Every read forces a pass. -/
theorem interleaved_clean : ∀ n, flagTotal false (interleaved n) = n
  | 0 => rfl
  | n + 1 => by
    have ih := interleaved_clean n
    simp only [flagTotal, interleaved, flagForced, flagEnd] at *
    simp only [Bool.toNat_true]; omega

/-- **Thrashing costs one pass per pair.** From either start flag, `n + 1` write-then-read pairs cost `n + 1` passes.

The start flag is overwritten by the first write. -/
theorem interleaved_total (d : Bool) (n : Nat) : flagTotal d (interleaved (n + 1)) = n + 1 := by
  have ih := interleaved_clean n
  simp only [flagTotal, interleaved, flagForced, flagEnd] at *
  simp only [Bool.toNat_true]; omega

/-- Reads only: one forced pass if the flag starts dirty and there is a read, then clean.

A run of reads pays the start flag once. -/
theorem checks_flag (d : Bool) : ∀ r : Nat,
    flagForced d (List.replicate r .check) = (d && decide (0 < r)).toNat ∧
      flagEnd d (List.replicate r .check) = (d && decide (r = 0))
  | 0 => by simp [flagForced, flagEnd]
  | r + 1 => by
    have ih := checks_flag false r
    simp only [List.replicate_succ, flagForced, flagEnd] at *
    simp [ih.1, ih.2]

/-- Writes only: no forced pass, and the flag ends dirty iff there is a write or it started dirty.

A run of writes forces nothing. -/
theorem dirties_flag : ∀ (d : Bool) (w : Nat),
    flagForced d (List.replicate w .dirty) = 0 ∧ flagEnd d (List.replicate w .dirty) = (d || decide (0 < w))
  | d, 0 => by simp [flagForced, flagEnd]
  | _, w + 1 => by
    have ih := dirties_flag true w
    simp only [List.replicate_succ, flagForced, flagEnd] at *
    simp [ih.1, ih.2]

/-- **The batched pattern's passes.** Reads then writes cost one pass for a dirty start flag that a read pays (or that
no write follows), plus one for the writes.

Batching leaves at most the start flag's pass and the end-of-frame pass. -/
theorem batched_total (d : Bool) (r w : Nat) :
    flagTotal d (batched r w) = (d && (decide (0 < r) || decide (w = 0))).toNat + (decide (0 < w)).toNat := by
  rw [batched, flagTotal_append]
  obtain ⟨h1, h2⟩ := checks_flag d r
  obtain ⟨h3, h4⟩ := dirties_flag (flagEnd d (List.replicate r .check)) w
  rw [h1]
  unfold flagTotal
  rw [h3, h4, h2]
  cases d <;> cases r <;> cases w <;> simp

/-- **Batching leaves at most one pass from a clean frame.**

The guide's claim, under the premise that the frame starts clean. -/
theorem batched_clean_le_one (r w : Nat) : flagTotal false (batched r w) ≤ 1 := by
  rw [batched_total]; cases h : decide (0 < w) <;> simp

/-- **Counterexample: from a dirty frame batching costs two passes.** With at least one read and one write, a frame
that is already dirty pays a forced pass at the first read and a lifecycle pass for the writes.

"At most one pass" needs the reads to come before any earlier write in the frame. -/
theorem batched_dirty_two (r w : Nat) (hr : 0 < r) (hw : 0 < w) : flagTotal true (batched r w) = 2 := by
  rw [batched_total]; simp [hr, hw]

/-- From a dirty start flag, any sequence costs at least one pass.

A dirty flag is paid by a read or at the end of the frame. -/
theorem flagTotal_true_pos : ∀ q : List FlagOp, 1 ≤ flagTotal true q
  | [] => by decide
  | .check :: _ => by simp only [flagTotal, flagForced, flagEnd, Bool.toNat_true]; omega
  | .dirty :: q => by have := flagTotal_true_pos q; simpa only [flagTotal, flagForced, flagEnd] using this
  | .neutral :: q => by have := flagTotal_true_pos q; simpa only [flagTotal, flagForced, flagEnd] using this

/-- A sequence costs at least as many passes from any start flag after a prefix as the suffix alone from that flag.

A prefix never removes passes. -/
theorem flagTotal_prefix (d : Bool) (p x : List FlagOp) :
    flagTotal (flagEnd d p) x ≤ flagTotal d (p ++ x) := by
  rw [flagTotal_append]; omega

/-- **A write, a later read, and a later write cost at least two passes.** For any start flag and any operations
before, between and after them.

Measuring between two size writes forces a layout pass on top of the frame's own. -/
theorem measure_ge_two (d : Bool) (p q r t : List FlagOp) :
    2 ≤ flagTotal d (p ++ .dirty :: (q ++ .check :: (r ++ .dirty :: t))) := by
  refine Nat.le_trans ?_ (flagTotal_prefix d p _)
  have h1 : ∀ e, flagTotal e (FlagOp.dirty :: (q ++ .check :: (r ++ .dirty :: t))) =
      flagTotal true (q ++ .check :: (r ++ .dirty :: t)) := fun _ => rfl
  rw [h1, flagTotal_append]
  have hq := flagTotal_true_pos q
  have h2 : flagTotal (flagEnd true q) (FlagOp.check :: (r ++ .dirty :: t)) =
      (flagEnd true q).toNat + flagTotal false (r ++ .dirty :: t) := by
    simp only [flagTotal, flagForced, flagEnd]; omega
  have h3 : 1 ≤ flagTotal false (r ++ .dirty :: t) := by
    refine Nat.le_trans ?_ (flagTotal_prefix false r _)
    exact flagTotal_true_pos t
  have hq' : 1 ≤ flagForced true q + (flagEnd true q).toNat := hq
  omega

/-- **A native size transition writes only.** Any number of writes costs at most one pass, from any start flag.

With no read the frame pays only its end-of-frame pass. -/
theorem native_le_one (d : Bool) (w : Nat) : flagTotal d (List.replicate w .dirty) ≤ 1 := by
  obtain ⟨h1, h2⟩ := dirties_flag d w
  simp only [flagTotal, h1, h2]
  cases (d || decide (0 < w)) <;> simp

/-- **Narrower `:has()` invalidation is less work (any engine).** A frame is strictly less work than the same frame plus
extra invalidated elements, when one of them dirties the style stage.

Fewer restyled elements, fewer style units. -/
theorem scope_lt {P M : Type} (E : Engine P M) (f : FrameIn P) (R : List (Change P)) (c : Change P) (hc : c ∈ R)
    (hs : Stage.style ∈ E.stagesOf c) : (frameWork E f).lt (frameWork E (join f (changesOnly R))) :=
  frame_lt_join_change E f (changesOnly R) c hc .style hs

/-- **`:has()` scope (Chromium).** Restyling extra elements, each a style-only change, is strictly more work.

An element's `:has()` invalidation is modelled as a custom-property change with no readers, which is style only. -/
theorem cr_has_scope (m : Chromium.CrMode) (f : FrameIn Chromium.CrProp) (R : List Nat) (l : LayerState)
    (hR : R ≠ []) :
    (frameWork (Chromium.chromiumAt m) f).lt
      (frameWork (Chromium.chromiumAt m) (join f (changesOnly (R.map fun e => ⟨e, .custom 0 [], l⟩)))) := by
  obtain ⟨e, es, rfl⟩ := List.exists_cons_of_ne_nil hR
  refine scope_lt _ f _ ⟨e, .custom 0 [], l⟩ (by simp) ?_
  show Stage.style ∈ Chromium.crStagesOf ⟨0, .custom 0 [], l⟩
  cases l <;> decide

/-- **`:has()` scope (WebKit).** Restyling extra elements is strictly more work.

An element's `:has()` invalidation is modelled as one `restyle` change. -/
theorem wk_has_scope (m : WebKit.WkMode) (f : FrameIn WebKit.WkPropX) (R : List Nat) (ℓ : LayerState)
    (hR : R ≠ []) :
    (frameWork (WebKit.webkitX m) f).lt
      (frameWork (WebKit.webkitX m) (join f (changesOnly (R.map fun e => ⟨e, .restyle, ℓ⟩)))) := by
  obtain ⟨e, es, rfl⟩ := List.exists_cons_of_ne_nil hR
  exact scope_lt _ f _ ⟨e, .restyle, ℓ⟩ (by simp) (by simp [WebKit.webkitX, WebKit.wkStagesOfX])

end Fw.Guidance.Style
