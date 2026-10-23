import Lean.Data.Json
import Fw.Measure.WebKitLag
import Fw.Measure.SimBound
import Fw.Parts.PeopleCarouselCrop
/-!
# Swap-window sampling of people.carousel on the WebKit lane (`packages/measure-webkit/src/lag/swap.mjs`)
-/
namespace Fw.Measure.SwapWindow
open Lean Fw.Measure.WebKitLag

def restUs : Int := (Fw.Parts.PeopleCarousel.restMs : Int) * 1000

def swapUs : Int := (Fw.Parts.PeopleCarousel.swapMs : Int) * 1000

def periodUs : Int := (Fw.Parts.PeopleCarousel.periodMs : Int) * 1000

theorem period_split : periodUs = restUs + swapUs := by decide

theorem period_eq : periodUs = 1020000 := by decide

theorem rest_eq : restUs = 800000 := by decide

theorem swap_eq : swapUs = 220000 := by decide

def periods : Nat := 8

def tolUs : Int := 33333

def deadlineUs (n : Nat) : Int := (n : Int) * periodUs + swapUs + periodUs

def windowFrames60 : Nat := Fw.Parts.PeopleCarouselCrop.swapFrames 60

theorem windowFrames60_eq : windowFrames60 = 13 := Fw.Parts.PeopleCarouselCrop.swapFrames_60

structure Win where
  start : Int
  stop : Int
  deriving Repr, DecidableEq

def nomStart (s0 : Int) (k : Nat) : Int := s0 + (k : Int) * periodUs

def nominal (s0 : Int) (n : Nat) : List Win :=
  (List.range n).map fun k => ⟨nomStart s0 k, nomStart s0 k + swapUs⟩

def Wf (ws : List Win) : Prop := (∀ w ∈ ws, w.start < w.stop) ∧ ws.Pairwise fun a b => a.stop ≤ b.start

theorem nominal_wf (s0 : Int) (n : Nat) : Wf (nominal s0 n) := by
  refine ⟨?_, ?_⟩
  · intro w hw
    simp only [nominal, List.mem_map, List.mem_range] at hw
    obtain ⟨k, -, rfl⟩ := hw
    simp only [swap_eq]; omega
  · simp only [nominal]
    rw [List.pairwise_map]
    refine List.pairwise_lt_range.imp ?_
    intro a b hab
    have : (a : Int) + 1 ≤ b := by exact_mod_cast hab
    simp only [nomStart, swap_eq, period_eq]
    omega

theorem nominal_length (s0 : Int) (n : Nat) : (nominal s0 n).length = n := by simp [nominal]

theorem nominal_next (s0 : Int) (k : Nat) : nomStart s0 (k + 1) = nomStart s0 k + swapUs + restUs := by
  simp only [nomStart, swap_eq, rest_eq, period_eq]; push_cast; omega

theorem nominal_last_before_deadline (s0 : Int) (n : Nat) (h1 : s0 ≤ periodUs) (hn : 0 < n) :
    nomStart s0 (n - 1) + swapUs ≤ deadlineUs n := by
  obtain ⟨m, rfl⟩ : ∃ m, n = m + 1 := ⟨n - 1, by omega⟩
  simp only [nomStart, deadlineUs, Nat.add_sub_cancel, swap_eq, period_eq] at *
  push_cast; omega

inductive Phase where
  | swap (k : Nat)
  | rest (k : Nat)
  | outside
  deriving Repr, DecidableEq

def phaseFrom : Nat → List Win → Int → Phase
  | _, [], _ => .outside
  | k, [w], t => if w.start ≤ t ∧ t < w.stop then .swap k else .outside
  | k, w :: v :: vs, t =>
    if t < w.start then .outside
    else if t < w.stop then .swap k
    else if t < v.start then .rest k
    else phaseFrom (k + 1) (v :: vs) t

def phaseOf (ws : List Win) (t : Int) : Phase := phaseFrom 0 ws t

def InSwap (ws : List Win) (i : Nat) (t : Int) : Prop :=
  ∃ w, ws[i]? = some w ∧ w.start ≤ t ∧ t < w.stop

def InRest (ws : List Win) (i : Nat) (t : Int) : Prop :=
  ∃ w v, ws[i]? = some w ∧ ws[i + 1]? = some v ∧ w.stop ≤ t ∧ t < v.start

private theorem wf_cons {w : Win} {ws : List Win} (h : Wf (w :: ws)) : Wf ws ∧ ∀ v ∈ ws, w.stop ≤ v.start := by
  obtain ⟨h1, h2⟩ := h
  rw [List.pairwise_cons] at h2
  exact ⟨⟨fun x hx => h1 x (List.mem_cons_of_mem _ hx), h2.2⟩, h2.1⟩

private theorem wf_head {w : Win} {ws : List Win} (h : Wf (w :: ws)) : w.start < w.stop := h.1 w (List.mem_cons_self ..)

private theorem wf_first {w : Win} {ws : List Win} (h : Wf (w :: ws)) : ∀ x ∈ w :: ws, w.start ≤ x.start := by
  intro x hx
  rcases List.mem_cons.1 hx with rfl | hx
  · exact Int.le_refl _
  · have := (wf_cons h).2 x hx
    have := wf_head h
    omega

private theorem getElem?_mem {ws : List Win} {i : Nat} {x : Win} (h : ws[i]? = some x) : x ∈ ws :=
  List.mem_of_getElem? h

private theorem swap_cons_zero {w : Win} {ws : List Win} {t : Int} :
    InSwap (w :: ws) 0 t ↔ w.start ≤ t ∧ t < w.stop := by simp [InSwap]

private theorem swap_cons_succ {w : Win} {ws : List Win} {i : Nat} {t : Int} :
    InSwap (w :: ws) (i + 1) t ↔ InSwap ws i t := by simp [InSwap]

private theorem rest_cons_succ {w : Win} {ws : List Win} {i : Nat} {t : Int} :
    InRest (w :: ws) (i + 1) t ↔ InRest ws i t := by simp [InRest]

private theorem swap_ge {ws : List Win} {a : Int} (h : ∀ x ∈ ws, a ≤ x.start) {i : Nat} {t : Int} :
    InSwap ws i t → a ≤ t := by
  rintro ⟨x, hx, h1, -⟩
  have := h x (getElem?_mem hx)
  omega

private theorem rest_ge {ws : List Win} (hp : ∀ x ∈ ws, x.start < x.stop) {a : Int} (h : ∀ x ∈ ws, a ≤ x.start) {i : Nat} {t : Int} :
    InRest ws i t → a ≤ t := by
  rintro ⟨x, y, hx, hy, h1, h2⟩
  have := h x (getElem?_mem hx)
  have := hp x (getElem?_mem hx)
  omega

theorem phaseFrom_swap : ∀ (ws : List Win) (k0 : Nat) (t : Int), Wf ws →
    ∀ j, phaseFrom k0 ws t = .swap j ↔ ∃ i, j = k0 + i ∧ InSwap ws i t
  | [], k0, t, _, j => by simp [phaseFrom, InSwap]
  | [w], k0, t, _, j => by
    unfold phaseFrom
    by_cases h : w.start ≤ t ∧ t < w.stop
    · simp only [h, and_self, ite_true, Phase.swap.injEq]
      constructor
      · rintro rfl; exact ⟨0, rfl, swap_cons_zero.2 h⟩
      · rintro ⟨i, rfl, hi⟩
        cases i with
        | zero => rfl
        | succ i => simp [InSwap] at hi
    · simp only [h, ite_false, reduceCtorEq, false_iff, not_exists, not_and]
      rintro i rfl hi
      cases i with
      | zero => exact h (swap_cons_zero.1 hi)
      | succ i => simp [InSwap] at hi
  | w :: v :: vs, k0, t, hwf, j => by
    obtain ⟨hwf', hle⟩ := wf_cons hwf
    have hws := wf_head hwf
    have hge : ∀ x ∈ v :: vs, w.stop ≤ x.start := fun x hx => hle x hx
    have ih := phaseFrom_swap (v :: vs) (k0 + 1) t hwf'
    unfold phaseFrom
    by_cases h1 : t < w.start
    · simp only [h1, ite_true, reduceCtorEq, false_iff, not_exists, not_and]
      rintro i rfl hi
      cases i with
      | zero => have := swap_cons_zero.1 hi; omega
      | succ i => have := swap_ge hge (swap_cons_succ.1 hi); omega
    · by_cases h2 : t < w.stop
      · simp only [h1, h2, ite_true, ite_false, Phase.swap.injEq]
        constructor
        · rintro rfl; exact ⟨0, rfl, swap_cons_zero.2 ⟨by omega, h2⟩⟩
        · rintro ⟨i, rfl, hi⟩
          cases i with
          | zero => rfl
          | succ i => have := swap_ge hge (swap_cons_succ.1 hi); omega
      · by_cases h3 : t < v.start
        · simp only [h1, h2, h3, ite_true, ite_false, reduceCtorEq, false_iff, not_exists, not_and]
          have hv := wf_first hwf'
          rintro i rfl hi
          cases i with
          | zero => have := swap_cons_zero.1 hi; omega
          | succ i => have := swap_ge hv (swap_cons_succ.1 hi); omega
        · simp only [h1, h2, h3, ite_false]
          rw [ih j]
          constructor
          · rintro ⟨i, rfl, hi⟩; exact ⟨i + 1, by omega, swap_cons_succ.2 hi⟩
          · rintro ⟨i, rfl, hi⟩
            cases i with
            | zero => have := swap_cons_zero.1 hi; omega
            | succ i => exact ⟨i, by omega, swap_cons_succ.1 hi⟩

theorem phaseFrom_rest : ∀ (ws : List Win) (k0 : Nat) (t : Int), Wf ws →
    ∀ j, phaseFrom k0 ws t = .rest j ↔ ∃ i, j = k0 + i ∧ InRest ws i t
  | [], k0, t, _, j => by simp [phaseFrom, InRest]
  | [w], k0, t, _, j => by
    unfold phaseFrom
    by_cases h : w.start ≤ t ∧ t < w.stop
    · simp only [h, and_self, ite_true, reduceCtorEq, false_iff, not_exists, not_and]
      rintro i rfl ⟨x, y, hx, hy, -, -⟩
      cases i with
      | zero => simp at hy
      | succ i => simp at hx
    · simp only [h, ite_false, reduceCtorEq, false_iff, not_exists, not_and]
      rintro i rfl ⟨x, y, hx, hy, -, -⟩
      cases i with
      | zero => simp at hy
      | succ i => simp at hx
  | w :: v :: vs, k0, t, hwf, j => by
    obtain ⟨hwf', hle⟩ := wf_cons hwf
    have hws := wf_head hwf
    have hge : ∀ x ∈ v :: vs, w.stop ≤ x.start := fun x hx => hle x hx
    have ih := phaseFrom_rest (v :: vs) (k0 + 1) t hwf'
    unfold phaseFrom
    by_cases h1 : t < w.start
    · simp only [h1, ite_true, reduceCtorEq, false_iff, not_exists, not_and]
      rintro i rfl hi
      cases i with
      | zero => obtain ⟨x, y, hx, hy, h4, h5⟩ := hi; simp at hx; subst hx; omega
      | succ i => have := rest_ge hwf'.1 hge (rest_cons_succ.1 hi); omega
    · by_cases h2 : t < w.stop
      · simp only [h1, h2, ite_true, ite_false, reduceCtorEq, false_iff, not_exists, not_and]
        rintro i rfl hi
        cases i with
        | zero => obtain ⟨x, y, hx, hy, h4, h5⟩ := hi; simp at hx; subst hx; omega
        | succ i => have := rest_ge hwf'.1 hge (rest_cons_succ.1 hi); omega
      · by_cases h3 : t < v.start
        · simp only [h1, h2, h3, ite_true, ite_false, Phase.rest.injEq]
          have hv := wf_first hwf'
          constructor
          · rintro rfl; exact ⟨0, rfl, w, v, rfl, rfl, by omega, h3⟩
          · rintro ⟨i, rfl, hi⟩
            cases i with
            | zero => rfl
            | succ i => have := rest_ge hwf'.1 hv (rest_cons_succ.1 hi); omega
        · simp only [h1, h2, h3, ite_false]
          rw [ih j]
          constructor
          · rintro ⟨i, rfl, hi⟩; exact ⟨i + 1, by omega, rest_cons_succ.2 hi⟩
          · rintro ⟨i, rfl, hi⟩
            cases i with
            | zero => obtain ⟨x, y, hx, hy, h4, h5⟩ := hi; simp at hx hy; subst hx; subst hy; omega
            | succ i => exact ⟨i, by omega, rest_cons_succ.1 hi⟩

structure Rec where
  ty : String
  t : Int
  deriving Repr, DecidableEq

def countIn (ws : List Win) (p : Phase) (ty : String) (rs : List Rec) : Nat :=
  (rs.filter fun r => r.ty == ty && decide (phaseOf ws r.t = p)).length

theorem countIn_append (ws : List Win) (p : Phase) (ty : String) (a b : List Rec) :
    countIn ws p ty (a ++ b) = countIn ws p ty a + countIn ws p ty b := by
  simp [countIn, List.filter_append]

theorem countIn_other_type (ws : List Win) (p : Phase) (ty : String) (rs : List Rec) (h : ∀ r ∈ rs, r.ty ≠ ty) :
    countIn ws p ty rs = 0 := by
  simp only [countIn, List.length_eq_zero_iff, List.filter_eq_nil_iff, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq,
    not_and]
  exact fun r hr hty => absurd hty (h r hr)

theorem countIn_swap_sound (ws : List Win) (hw : Wf ws) (k : Nat) (ty : String) (rs : List Rec)
    (h : 0 < countIn ws (.swap k) ty rs) : ∃ r ∈ rs, r.ty = ty ∧ InSwap ws k r.t := by
  obtain ⟨r, hr⟩ := List.exists_mem_of_length_pos h
  simp only [List.mem_filter, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at hr
  obtain ⟨hmem, hty, hph⟩ := hr
  obtain ⟨i, hi, hs⟩ := (phaseFrom_swap ws 0 r.t hw k).1 hph
  exact ⟨r, hmem, hty, by simpa [show k = i by omega] using hs⟩

theorem countIn_swap_complete (ws : List Win) (hw : Wf ws) (k : Nat) (ty : String) (rs : List Rec)
    (r : Rec) (hr : r ∈ rs) (hty : r.ty = ty) (hs : InSwap ws k r.t) : 0 < countIn ws (.swap k) ty rs := by
  have hph : phaseOf ws r.t = .swap k := (phaseFrom_swap ws 0 r.t hw k).2 ⟨k, by omega, hs⟩
  apply List.length_pos_of_mem (a := r)
  simp [hr, hty, hph]

theorem countIn_rest_not_swap (ws : List Win) (hw : Wf ws) (k j : Nat) (r : Rec) (hs : InRest ws k r.t) :
    phaseOf ws r.t ≠ .swap j := by
  intro h
  have : phaseOf ws r.t = .rest k := (phaseFrom_rest ws 0 r.t hw k).2 ⟨k, by omega, hs⟩
  rw [h] at this
  cases this

def validAt (ws : List Win) (k : Nat) : Bool :=
  match ws[k]? with
  | none => false
  | some w =>
    decide ((w.stop - w.start - swapUs).natAbs ≤ tolUs.toNat) &&
      match ws[k + 1]? with
      | none => true
      | some v => decide ((v.start - w.start - periodUs).natAbs ≤ tolUs.toNat)

theorem validAt_none (ws : List Win) (k : Nat) (h : ws[k]? = none) : validAt ws k = false := by
  simp [validAt, h]

theorem validAt_length (ws : List Win) (k : Nat) (h : validAt ws k = true) :
    ∃ w, ws[k]? = some w ∧ (w.stop - w.start - swapUs).natAbs ≤ tolUs.toNat := by
  unfold validAt at h
  split at h
  · cases h
  · rename_i w hw
    simp only [Bool.and_eq_true, decide_eq_true_eq] at h
    exact ⟨w, hw, h.1⟩

theorem validAt_spacing (ws : List Win) (k : Nat) (w v : Win) (hw : ws[k]? = some w) (hv : ws[k + 1]? = some v)
    (h : validAt ws k = true) : (v.start - w.start - periodUs).natAbs ≤ tolUs.toNat := by
  unfold validAt at h
  simp only [hw, hv, Bool.and_eq_true, decide_eq_true_eq] at h
  exact h.2

theorem validAt_false_long (ws : List Win) (k : Nat) (w : Win) (hw : ws[k]? = some w)
    (h : tolUs.toNat < (w.stop - w.start - swapUs).natAbs) : validAt ws k = false := by
  unfold validAt
  simp only [hw]
  have : ¬ ((w.stop - w.start - swapUs).natAbs ≤ tolUs.toNat) := by omega
  simp [this]

theorem validAt_false_spacing (ws : List Win) (k : Nat) (w v : Win) (hw : ws[k]? = some w) (hv : ws[k + 1]? = some v)
    (h : tolUs.toNat < (v.start - w.start - periodUs).natAbs) : validAt ws k = false := by
  unfold validAt
  simp only [hw, hv]
  have : ¬ ((v.start - w.start - periodUs).natAbs ≤ tolUs.toNat) := by omega
  simp [this]

theorem nominal_valid (s0 : Int) (n k : Nat) (hk : k < n) : validAt (nominal s0 n) k = true := by
  have e1 : (nominal s0 n)[k]? = some ⟨nomStart s0 k, nomStart s0 k + swapUs⟩ := by
    simp [nominal, hk]
  unfold validAt
  rw [e1]
  simp only [Bool.and_eq_true, decide_eq_true_eq]
  refine ⟨by simp only [swap_eq, tolUs]; omega, ?_⟩
  by_cases h : k + 1 < n
  · have e2 : (nominal s0 n)[k + 1]? = some ⟨nomStart s0 (k + 1), nomStart s0 (k + 1) + swapUs⟩ := by
      simp [nominal, h]
    rw [e2]
    simp only [nomStart, period_eq, tolUs]
    push_cast
    simp only [decide_eq_true_eq]
    omega
  · have e2 : (nominal s0 n)[k + 1]? = none := by
      rw [List.getElem?_eq_none_iff, nominal_length]; omega
    rw [e2]

def predictedLayout (layoutPasses : Nat) : Nat := Fw.Parts.PeopleCarouselCrop.layoutFrames 60 layoutPasses

theorem predicted_crop : predictedLayout 0 = 0 := (Fw.Parts.PeopleCarouselCrop.layoutFrames_swap 60).1

theorem predicted_faithful : predictedLayout 1 = 13 := (Fw.Parts.PeopleCarouselCrop.layoutFrames_swap 60).2

theorem predicted_crop_lt : predictedLayout 0 < predictedLayout 1 := by
  rw [predicted_crop, predicted_faithful]; decide

inductive Reason where
  | drift
  | noSamples
  | fewSamples
  | floorBroken
  | overlap
  deriving Repr, DecidableEq

inductive Cell where
  | win
  | loss
  | unresolved (r : Reason)
  deriving Repr, DecidableEq

def Cell.name : Cell → String
  | .win => "win"
  | .loss => "loss"
  | .unresolved .drift => "unresolved:drift"
  | .unresolved .noSamples => "unresolved:noSamples"
  | .unresolved .fewSamples => "unresolved:fewSamples"
  | .unresolved .floorBroken => "unresolved:floorBroken"
  | .unresolved .overlap => "unresolved:overlap"

def asRat (xs : List Int) : List Rat := xs.map fun x => Int.cast x

def minFaithful : Nat := 3

def cell (a1 a2 c : List Int) (dropped : Nat) : Cell :=
  if a1.isEmpty || a2.isEmpty || c.isEmpty then (if 0 < dropped then .unresolved .drift else .unresolved .noSamples)
  else if a1.length < minFaithful || a2.length < minFaithful then .unresolved .fewSamples
  else if verdict (asRat a1) (asRat a2) != .overlap then .unresolved .floorBroken
  else match verdict (asRat (a1 ++ a2)) (asRat c) with
    | .lower => .win
    | .higher => .loss
    | _ => .unresolved .overlap

theorem cell_drift (a1 a2 c : List Int) (d : Nat) (h : a1 = [] ∨ a2 = [] ∨ c = []) (hd : 0 < d) :
    cell a1 a2 c d = .unresolved .drift := by
  rcases h with rfl | rfl | rfl <;> simp [cell, hd]

theorem cell_noSamples (a1 a2 c : List Int) (h : a1 = [] ∨ a2 = [] ∨ c = []) :
    cell a1 a2 c 0 = .unresolved .noSamples := by
  rcases h with rfl | rfl | rfl <;> simp [cell]

theorem cell_fewSamples_a1 (a1 a2 c : List Int) (d : Nat) (h1 : a1 ≠ []) (h2 : a2 ≠ []) (h3 : c ≠ [])
    (hn : a1.length < minFaithful) : cell a1 a2 c d = .unresolved .fewSamples := by
  simp [cell, h1, h2, h3, hn]

theorem cell_fewSamples_a2 (a1 a2 c : List Int) (d : Nat) (h1 : a1 ≠ []) (h2 : a2 ≠ []) (h3 : c ≠ [])
    (hn : a2.length < minFaithful) : cell a1 a2 c d = .unresolved .fewSamples := by
  simp [cell, h1, h2, h3, hn]

theorem cell_two_samples_undecided (a1 a2 c : List Int) (d : Nat) (h1 : a1.length = 2) (h2 : a2 ≠ []) (h3 : c ≠ []) :
    cell a1 a2 c d ≠ .win ∧ cell a1 a2 c d ≠ .loss := by
  have h1' : a1 ≠ [] := by intro h; simp [h] at h1
  have := cell_fewSamples_a1 a1 a2 c d h1' h2 h3 (by simp [minFaithful, h1])
  simp [this]

theorem cell_floorBroken (a1 a2 c : List Int) (d : Nat) (h1 : a1 ≠ []) (h2 : a2 ≠ []) (h3 : c ≠ [])
    (hn1 : minFaithful ≤ a1.length) (hn2 : minFaithful ≤ a2.length)
    (hf : verdict (asRat a1) (asRat a2) ≠ .overlap) : cell a1 a2 c d = .unresolved .floorBroken := by
  simp [cell, h1, h2, h3, hf, Nat.not_lt.mpr hn1, Nat.not_lt.mpr hn2]

theorem cell_win (a1 a2 c : List Int) (d : Nat) (h1 : a1 ≠ []) (h2 : a2 ≠ []) (h3 : c ≠ [])
    (hn1 : minFaithful ≤ a1.length) (hn2 : minFaithful ≤ a2.length)
    (hf : verdict (asRat a1) (asRat a2) = .overlap) (hs : sepBelow (asRat c) (asRat (a1 ++ a2)) = true) :
    cell a1 a2 c d = .win := by
  have hne : asRat (a1 ++ a2) ≠ [] := by simp [asRat, h1]
  have hc : asRat c ≠ [] := by simp [asRat, h3]
  simp [cell, h1, h2, h3, hf, verdict_lower hne hc hs, Nat.not_lt.mpr hn1, Nat.not_lt.mpr hn2]

theorem cell_loss (a1 a2 c : List Int) (d : Nat) (h1 : a1 ≠ []) (h2 : a2 ≠ []) (h3 : c ≠ [])
    (hn1 : minFaithful ≤ a1.length) (hn2 : minFaithful ≤ a2.length)
    (hf : verdict (asRat a1) (asRat a2) = .overlap) (hs : sepBelow (asRat (a1 ++ a2)) (asRat c) = true) :
    cell a1 a2 c d = .loss := by
  have hne : asRat (a1 ++ a2) ≠ [] := by simp [asRat, h1]
  have hc : asRat c ≠ [] := by simp [asRat, h3]
  simp [cell, h1, h2, h3, hf, verdict_higher hne hc hs, Nat.not_lt.mpr hn1, Nat.not_lt.mpr hn2]

theorem cell_overlap (a1 a2 c : List Int) (d : Nat) (h1 : a1 ≠ []) (h2 : a2 ≠ []) (h3 : c ≠ [])
    (hn1 : minFaithful ≤ a1.length) (hn2 : minFaithful ≤ a2.length)
    (hf : verdict (asRat a1) (asRat a2) = .overlap) (hs : sepBelow (asRat c) (asRat (a1 ++ a2)) = false)
    (ht : sepBelow (asRat (a1 ++ a2)) (asRat c) = false) : cell a1 a2 c d = .unresolved .overlap := by
  simp [cell, h1, h2, h3, hf, verdict_overlap hs ht, Nat.not_lt.mpr hn1, Nat.not_lt.mpr hn2]

def restFrames60 : Nat := Int.toNat (restUs * 60 / 1000000)

theorem restFrames60_eq : restFrames60 = 48 := by decide

def busyMin : Nat := restFrames60 / 2

theorem busyMin_eq : busyMin = 24 := by decide

inductive Bg where
  | idle
  | busy
  | mixed
  | unknown
  deriving Repr, DecidableEq

def Bg.name : Bg → String
  | .idle => "idle"
  | .busy => "busy"
  | .mixed => "mixed"
  | .unknown => "unknown"

def bgOf (ns : List Nat) : Bg :=
  if ns.isEmpty then .unknown
  else if ns.all (fun n => busyMin ≤ n) then .busy
  else if ns.all (fun n => n < busyMin) then .idle
  else .mixed

theorem bgOf_unknown : bgOf [] = .unknown := by simp [bgOf]

theorem bgOf_busy (ns : List Nat) (hne : ns ≠ []) (h : ∀ n ∈ ns, busyMin ≤ n) : bgOf ns = .busy := by
  have h1 : ns.isEmpty = false := by simpa [List.isEmpty_iff] using hne
  have h2 : ns.all (fun n => busyMin ≤ n) = true := by simpa [List.all_eq_true] using h
  simp [bgOf, h1, h2]

theorem bgOf_idle (ns : List Nat) (hne : ns ≠ []) (h : ∀ n ∈ ns, n < busyMin) : bgOf ns = .idle := by
  have h1 : ns.isEmpty = false := by simpa [List.isEmpty_iff] using hne
  have h2 : ns.all (fun n => busyMin ≤ n) = false := by
    obtain ⟨a, ha⟩ := List.exists_mem_of_ne_nil ns hne
    have hlt := h a ha
    cases hall : ns.all (fun n => busyMin ≤ n)
    · rfl
    · have := (List.all_eq_true.mp hall) a ha
      simp at this; omega
  have h3 : ns.all (fun n => n < busyMin) = true := by simpa [List.all_eq_true] using h
  simp [bgOf, h1, h2, h3]

theorem bgOf_mixed (ns : List Nat) (a b : Nat) (ha : a ∈ ns) (hb : b ∈ ns) (hao : busyMin ≤ a) (hbo : b < busyMin) :
    bgOf ns = .mixed := by
  have h1 : ns.isEmpty = false := by
    cases ns with
    | nil => simp at ha
    | cons x xs => rfl
  have h2 : ns.all (fun n => busyMin ≤ n) = false := by
    cases hall : ns.all (fun n => busyMin ≤ n)
    · rfl
    · have := (List.all_eq_true.mp hall) b hb
      simp at this; omega
  have h3 : ns.all (fun n => n < busyMin) = false := by
    cases hall : ns.all (fun n => n < busyMin)
    · rfl
    · have := (List.all_eq_true.mp hall) a ha
      simp at this; omega
  simp [bgOf, h1, h2, h3]

theorem bgOf_floor : bgOf [5, 5] = .idle := by decide

theorem bgOf_full : bgOf [restFrames60, restFrames60] = .busy := by decide

def swapNeighbours (k n : Nat) : List Nat := (if 0 < k then [k - 1] else []) ++ (if k + 1 < n then [k] else [])

theorem swapNeighbours_first (n : Nat) (h : 1 < n) : swapNeighbours 0 n = [0] := by
  simp [swapNeighbours]; omega

theorem swapNeighbours_last (n : Nat) (h : 1 < n) : swapNeighbours (n - 1) n = [n - 2] := by
  have h1 : 0 < n - 1 := by omega
  have h2 : ¬ (n - 1 + 1 < n) := by omega
  have h3 : n - 1 - 1 = n - 2 := by omega
  simp [swapNeighbours, h1, h2, h3]

theorem swapNeighbours_mid (k n : Nat) (h0 : 0 < k) (h1 : k + 1 < n) : swapNeighbours k n = [k - 1, k] := by
  simp [swapNeighbours, h0, h1]
def bucketUs : Int := 100000

def swapBuckets : Nat := ((swapUs + bucketUs - 1) / bucketUs).toNat + 1

theorem swapBuckets_eq : swapBuckets = 4 := by decide

theorem window_touches (s len : Int) (h0 : 0 < len) (h1 : len ≤ swapUs) :
    (s + len - 1) / bucketUs - s / bucketUs + 1 ≤ (swapBuckets : Int) := by
  have h2 := swap_eq
  have h3 : swapBuckets = 4 := swapBuckets_eq
  unfold bucketUs
  omega

def busyBucket : Nat := 4

def longRunMin : Nat := swapBuckets + 1

theorem longRunMin_eq : longRunMin = 5 := by decide

def runsGo (m : Nat) : Nat → List Nat → Nat
  | cur, [] => if m ≤ cur then 1 else 0
  | cur, n :: ns => if busyBucket ≤ n then runsGo m (cur + 1) ns else (if m ≤ cur then 1 else 0) + runsGo m 0 ns

def longRuns (xs : List Nat) : Nat := runsGo longRunMin 0 xs

theorem runsGo_quiet (m : Nat) (hm : 0 < m) : ∀ (xs : List Nat) (cur : Nat), (∀ n ∈ xs, n < busyBucket) →
    runsGo m cur xs = if m ≤ cur then 1 else 0
  | [], cur, _ => by simp [runsGo]
  | n :: ns, cur, h => by
    have hn : ¬ busyBucket ≤ n := by have := h n (by simp); omega
    have ih := runsGo_quiet m hm ns 0 (fun k hk => h k (by simp [hk]))
    have h0 : ¬ m ≤ 0 := by omega
    simp [runsGo, hn, ih, h0]

theorem longRuns_quiet (xs : List Nat) (h : ∀ n ∈ xs, n < busyBucket) : longRuns xs = 0 := by
  have := runsGo_quiet longRunMin (by decide) xs 0 h
  have h0 : longRunMin ≠ 0 := by decide
  simpa [longRuns, h0] using this

theorem runsGo_busy (m b : Nat) (hb : busyBucket ≤ b) : ∀ (n cur : Nat),
    runsGo m cur (List.replicate n b) = if m ≤ cur + n then 1 else 0
  | 0, cur => by simp [runsGo]
  | n + 1, cur => by
    have ih := runsGo_busy m b hb n (cur + 1)
    have e : cur + 1 + n = cur + (n + 1) := by omega
    simp [List.replicate_succ, runsGo, hb, ih, e]

theorem longRuns_long_run (b n : Nat) (hb : busyBucket ≤ b) (hn : longRunMin ≤ n) :
    longRuns (List.replicate n b) = 1 := by
  simp [longRuns, runsGo_busy longRunMin b hb n 0, hn]

theorem longRuns_short_run (b n : Nat) (hb : busyBucket ≤ b) (hn : n < longRunMin) :
    longRuns (List.replicate n b) = 0 := by
  have : ¬ longRunMin ≤ n := by omega
  simp [longRuns, runsGo_busy longRunMin b hb n 0, this]

def median2 (xs : List Int) : Int :=
  let s := xs.mergeSort
  s.getD ((s.length - 1) / 2) 0 + s.getD (s.length / 2) 0

theorem median2_bounds (xs : List Int) (hne : xs ≠ []) (lo hi : Int) (hl : ∀ x ∈ xs, lo ≤ x) (hh : ∀ x ∈ xs, x ≤ hi) :
    2 * lo ≤ median2 xs ∧ median2 xs ≤ 2 * hi := by
  have hp : xs.mergeSort.Perm xs := List.mergeSort_perm xs _
  have hlen : xs.mergeSort.length = xs.length := hp.length_eq
  have hpos : 0 < xs.length := List.length_pos_iff.mpr hne
  have hmem : ∀ i, i < xs.length → xs.mergeSort.getD i 0 ∈ xs := by
    intro i hi
    have hi' : i < xs.mergeSort.length := by omega
    rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hi']
    exact hp.subset (List.getElem_mem hi')
  have h1 := hmem ((xs.length - 1) / 2) (by omega)
  have h2 := hmem (xs.length / 2) (by omega)
  have := hl _ h1; have := hl _ h2; have := hh _ h1; have := hh _ h2
  simp only [median2, hlen]
  omega

inductive FrozenCell where
  | noSamples
  | busyRemains
  | noIdleLevel
  | notAtIdle
  | atIdle
  deriving DecidableEq, Repr

def FrozenCell.name : FrozenCell → String
  | .noSamples => "noSamples"
  | .busyRemains => "busyRemains"
  | .noIdleLevel => "noIdleLevel"
  | .notAtIdle => "notAtIdle"
  | .atIdle => "atIdle"

def usableOf (frozen : List (Int × Bg)) : List (Int × Bg) := frozen.filter fun s => s.2 != Bg.unknown

def frozenCell (frozen : List (Int × Bg)) (idle : List Int) : FrozenCell :=
  let usable := usableOf frozen
  if usable.isEmpty then .noSamples
  else if usable.any (fun s => s.2 != Bg.idle) then .busyRemains
  else match idle.max? with
    | none => .noIdleLevel
    | some m => if 2 * m < median2 (usable.map (·.1)) then .notAtIdle else .atIdle

theorem frozenCell_noSamples (frozen : List (Int × Bg)) (idle : List Int) (h : ∀ s ∈ frozen, s.2 = Bg.unknown) :
    frozenCell frozen idle = .noSamples := by
  have : usableOf frozen = [] := by
    simp only [usableOf, List.filter_eq_nil_iff]
    intro s hs; simp [h s hs]
  simp [frozenCell, this]

theorem usableOf_ne (frozen : List (Int × Bg)) (s : Int × Bg) (hs : s ∈ frozen) (hu : s.2 ≠ Bg.unknown) :
    (usableOf frozen).isEmpty = false := by
  have hm : s ∈ usableOf frozen := by simp [usableOf, hs, hu]
  cases h : usableOf frozen with
  | nil => rw [h] at hm; simp at hm
  | cons a l => rfl

theorem usableOf_idle (frozen : List (Int × Bg)) (hq : ∀ t ∈ frozen, t.2 ≠ Bg.unknown → t.2 = Bg.idle) :
    (usableOf frozen).any (fun s => s.2 != Bg.idle) = false := by
  simp only [List.any_eq_false, usableOf, List.mem_filter]
  intro t ⟨ht, hu'⟩
  simp at hu'
  simp [hq t ht hu']

theorem frozenCell_busyRemains (frozen : List (Int × Bg)) (idle : List Int) (s : Int × Bg) (hs : s ∈ frozen)
    (hu : s.2 ≠ Bg.unknown) (hi : s.2 ≠ Bg.idle) : frozenCell frozen idle = .busyRemains := by
  have hm : s ∈ usableOf frozen := by simp [usableOf, hs, hu]
  have hany : (usableOf frozen).any (fun s => s.2 != Bg.idle) = true :=
    List.any_eq_true.mpr ⟨s, hm, by simp [hi]⟩
  simp [frozenCell, usableOf_ne frozen s hs hu, hany]

theorem frozenCell_noIdleLevel (frozen : List (Int × Bg)) (s : Int × Bg) (hs : s ∈ frozen)
    (hu : s.2 ≠ Bg.unknown) (hq : ∀ t ∈ frozen, t.2 ≠ Bg.unknown → t.2 = Bg.idle) :
    frozenCell frozen [] = .noIdleLevel := by
  simp [frozenCell, usableOf_ne frozen s hs hu, usableOf_idle frozen hq]

theorem frozenCell_notAtIdle (frozen : List (Int × Bg)) (idle : List Int) (s : Int × Bg) (hs : s ∈ frozen)
    (hu : s.2 ≠ Bg.unknown) (hq : ∀ t ∈ frozen, t.2 ≠ Bg.unknown → t.2 = Bg.idle) (m : Int) (hm : idle.max? = some m)
    (hlt : 2 * m < median2 ((usableOf frozen).map (·.1))) : frozenCell frozen idle = .notAtIdle := by
  simp [frozenCell, usableOf_ne frozen s hs hu, usableOf_idle frozen hq, hm, hlt]

theorem frozenCell_atIdle (frozen : List (Int × Bg)) (idle : List Int) (s : Int × Bg) (hs : s ∈ frozen)
    (hu : s.2 ≠ Bg.unknown) (hq : ∀ t ∈ frozen, t.2 ≠ Bg.unknown → t.2 = Bg.idle) (m : Int) (hm : idle.max? = some m)
    (hle : median2 ((usableOf frozen).map (·.1)) ≤ 2 * m) : frozenCell frozen idle = .atIdle := by
  have hnl : ¬ 2 * m < median2 ((usableOf frozen).map (·.1)) := by omega
  simp [frozenCell, usableOf_ne frozen s hs hu, usableOf_idle frozen hq, hm, hnl]

def sharePct (u f : Int) : Option Int := if 0 < u then some ((u - f) * 100 / u) else none

theorem sharePct_none (u f : Int) (h : u ≤ 0) : sharePct u f = none := by
  simp [sharePct]; omega

theorem sharePct_same (u : Int) (h : 0 < u) : sharePct u u = some 0 := by
  simp [sharePct, h]

theorem sharePct_all (u : Int) (h : 0 < u) : sharePct u 0 = some 100 := by
  have e : u * 100 / u = 100 := Int.mul_ediv_cancel_left 100 (by omega)
  simp [sharePct, h, e]

theorem sharePct_le (u f : Int) (h : 0 < u) (hf : 0 ≤ f) : ∃ p, sharePct u f = some p ∧ p ≤ 100 := by
  refine ⟨(u - f) * 100 / u, by simp [sharePct, h], ?_⟩
  apply Int.le_of_lt_add_one
  apply (Int.ediv_lt_iff_lt_mul h).mpr
  omega


def zoneVerdict (off on : List Int) : Verdict := verdict (asRat off) (asRat on)

theorem zoneVerdict_nil_off (on : List Int) : zoneVerdict [] on = .overlap := by
  simp [zoneVerdict, asRat, verdict]

theorem zoneVerdict_nil_on (off : List Int) : zoneVerdict off [] = .overlap := by
  simp [zoneVerdict, asRat, verdict]

inductive BusyFrozen where
  | noBusy
  | noFrozen
  | removed
  | raised
  | overlap
  deriving DecidableEq, Repr

def BusyFrozen.name : BusyFrozen → String
  | .noBusy => "noBusy"
  | .noFrozen => "noFrozen"
  | .removed => "removed"
  | .raised => "raised"
  | .overlap => "overlap"

def busyFrozen (busy frozen : List Int) : BusyFrozen :=
  if busy.isEmpty then .noBusy
  else if frozen.isEmpty then .noFrozen
  else match zoneVerdict busy frozen with
    | .lower => .removed
    | .higher => .raised
    | _ => .overlap

theorem busyFrozen_noBusy (frozen : List Int) : busyFrozen [] frozen = .noBusy := by
  simp [busyFrozen]

theorem busyFrozen_noFrozen (busy : List Int) (h : busy ≠ []) : busyFrozen busy [] = .noFrozen := by
  simp [busyFrozen, h]

theorem busyFrozen_removed (busy frozen : List Int) (hb : busy ≠ []) (hf : frozen ≠ [])
    (hs : sepBelow (asRat frozen) (asRat busy) = true) : busyFrozen busy frozen = .removed := by
  have hne : asRat busy ≠ [] := by simp [asRat, hb]
  have hc : asRat frozen ≠ [] := by simp [asRat, hf]
  simp [busyFrozen, hb, hf, zoneVerdict, verdict_lower hne hc hs]

theorem busyFrozen_raised (busy frozen : List Int) (hb : busy ≠ []) (hf : frozen ≠ [])
    (hs : sepBelow (asRat busy) (asRat frozen) = true) : busyFrozen busy frozen = .raised := by
  have hne : asRat busy ≠ [] := by simp [asRat, hb]
  have hc : asRat frozen ≠ [] := by simp [asRat, hf]
  simp [busyFrozen, hb, hf, zoneVerdict, verdict_higher hne hc hs]

theorem busyFrozen_overlap (busy frozen : List Int) (hb : busy ≠ []) (hf : frozen ≠ [])
    (h1 : sepBelow (asRat frozen) (asRat busy) = false) (h2 : sepBelow (asRat busy) (asRat frozen) = false) :
    busyFrozen busy frozen = .overlap := by
  simp [busyFrozen, hb, hf, zoneVerdict, verdict_overlap h1 h2]

def busyWindows (ns : List Nat) : Nat := (ns.filter fun n => busyMin ≤ n).length

theorem busyWindows_le (ns : List Nat) : busyWindows ns ≤ ns.length := List.length_filter_le _ _

theorem busyWindows_quiet (ns : List Nat) (h : ∀ n ∈ ns, n < busyMin) : busyWindows ns = 0 := by
  simp only [busyWindows, List.length_eq_zero_iff, List.filter_eq_nil_iff, decide_eq_true_eq]
  intro n hn; have := h n hn; omega

theorem busyWindows_all (ns : List Nat) (h : ∀ n ∈ ns, busyMin ≤ n) : busyWindows ns = ns.length := by
  have : ns.filter (fun n => decide (busyMin ≤ n)) = ns := List.filter_eq_self.mpr (by simpa using h)
  simp [busyWindows, this]

def perCaptureTenths (rows captures : Nat) : Nat :=
  if captures = 0 then 0 else (rows * 20 + captures) / (2 * captures)

theorem perCaptureTenths_none (rows : Nat) : perCaptureTenths rows 0 = 0 := by simp [perCaptureTenths]

theorem perCaptureTenths_exact (k c : Nat) (hc : 0 < c) : perCaptureTenths (k * c) c = 10 * k := by
  have e : k * c * 20 + c = c * (20 * k + 1) := by
    have : k * c * 20 = c * (20 * k) := by rw [Nat.mul_comm k c, Nat.mul_assoc, Nat.mul_comm k 20]
    rw [this, Nat.mul_add, Nat.mul_one]
  have e2 : 2 * c = c * 2 := Nat.mul_comm 2 c
  simp only [perCaptureTenths, Nat.pos_iff_ne_zero.mp hc, ite_false, e, e2]
  rw [Nat.mul_div_mul_left _ _ hc]
  omega

def perFrameMilli (rows frames : Nat) : Option Nat :=
  if frames = 0 then none else some ((rows * 2000 + frames) / (2 * frames))

theorem perFrameMilli_none (rows : Nat) : perFrameMilli rows 0 = none := by simp [perFrameMilli]

theorem perFrameMilli_exact (k f : Nat) (hf : 0 < f) : perFrameMilli (k * f) f = some (1000 * k) := by
  have e : k * f * 2000 + f = f * (2000 * k + 1) := by
    have : k * f * 2000 = f * (2000 * k) := by rw [Nat.mul_comm k f, Nat.mul_assoc, Nat.mul_comm k 2000]
    rw [this, Nat.mul_add, Nat.mul_one]
  have e2 : 2 * f = f * 2 := Nat.mul_comm 2 f
  simp only [perFrameMilli, Nat.pos_iff_ne_zero.mp hf, ite_false, e, e2]
  rw [Nat.mul_div_mul_left _ _ hf]
  congr 1
  omega

theorem perFrameMilli_zero (f : Nat) (hf : 0 < f) : perFrameMilli 0 f = some 0 := by
  simpa using perFrameMilli_exact 0 f hf

def laneBudgetMin : Nat := Fw.Measure.SimBound.perSessionMin - 11

theorem laneBudget_below_step : laneBudgetMin < Fw.Measure.SimBound.perSessionMin := by decide

def unitFits (elapsedMs estimateMs : Nat) : Bool := decide (elapsedMs + estimateMs ≤ laneBudgetMin * 60000)

theorem unitFits_fresh (est : Nat) (h : est ≤ laneBudgetMin * 60000) : unitFits 0 est = true := by
  simp [unitFits, h]

theorem unitFits_late (elapsed est : Nat) (h : laneBudgetMin * 60000 < elapsed) : unitFits elapsed est = false := by
  simp only [unitFits, decide_eq_false_iff_not]; omega

theorem unitFits_mono (e1 e2 est : Nat) (h : e1 ≤ e2) (hf : unitFits e2 est = true) : unitFits e1 est = true := by
  simp only [unitFits, decide_eq_true_eq] at hf ⊢; omega

def armOrder (shift : Nat) : List String :=
  match shift % 3 with
  | 1 => ["nolayout", "full", "faithful"]
  | 2 => ["full", "faithful", "nolayout"]
  | _ => ["faithful", "nolayout", "full"]

def laneUnits (shift : Nat) : List String :=
  (armOrder shift).map (fun a => "swap:" ++ a ++ "-a") ++ (armOrder shift).map (fun a => "zone:" ++ a ++ "-a") ++
  ["swap:faithful-frozen-a", "zone:faithful-frozen-a", "swap:faithful-b", "zone:faithful-b"] ++
  ((armOrder shift).filter (· != "faithful")).map (fun a => "zone:" ++ a ++ "-b") ++ ["zone:faithful-frozen-b"]

theorem laneUnits_length (shift : Nat) : (laneUnits shift).length = 13 := by
  have h : shift % 3 = 0 ∨ shift % 3 = 1 ∨ shift % 3 = 2 := by omega
  rcases h with h | h | h <;> simp [laneUnits, armOrder, h]

theorem laneUnits_nodup (shift : Nat) : (laneUnits shift).Nodup := by
  have h : shift % 3 = 0 ∨ shift % 3 = 1 ∨ shift % 3 = 2 := by omega
  rcases h with h | h | h <;> simp [laneUnits, armOrder, h] <;> decide

theorem laneUnits_first (shift : Nat) : ∃ u ∈ (laneUnits shift).head?, u.startsWith "swap:" = true := by
  have h : shift % 3 = 0 ∨ shift % 3 = 1 ∨ shift % 3 = 2 := by omega
  rcases h with h | h | h <;> simp [laneUnits, armOrder, h]

private def phaseJ (p : Phase) : Json := toJson (match p with | .swap k => s!"swap:{k}" | .rest k => s!"rest:{k}" | .outside => "outside")

private def winJ (w : Win) : Json := Json.arr #[toJson w.start, toJson w.stop]

private def recJ (r : Rec) : Json := Json.arr #[toJson r.ty, toJson r.t]

private def nomCases : List (Int × Nat) := [(0, 1), (0, 8), (1500000, 8), (123456, 3)]

private def wsNominal : List Win := nominal 1000000 3

private def wsDrift : List Win := [⟨0, 220000⟩, ⟨1020000, 1240000⟩, ⟨2100000, 2400000⟩, ⟨3100000, 3320000⟩, ⟨4200000, 4420000⟩]

private def wsOne : List Win := [⟨500, 700⟩]

private def phaseTimes (ws : List Win) : List Int :=
  (ws.flatMap fun w => [w.start - 1, w.start, w.start + 1, w.stop - 1, w.stop, w.stop + 1]) ++ [-5, 0, 10000000]

private def recCases : List (List Win × List Rec) :=
  [(nominal 0 3, [⟨"Layout", 0⟩, ⟨"Layout", 100000⟩, ⟨"Paint", 100000⟩, ⟨"Layout", 219999⟩, ⟨"Layout", 220000⟩, ⟨"Composite", 500000⟩,
    ⟨"Layout", 1020000⟩, ⟨"Layout", 1240000⟩, ⟨"Layout", 2040000⟩, ⟨"Layout", 2259999⟩, ⟨"Layout", 2260000⟩, ⟨"Paint", -1⟩]),
   (wsDrift, [⟨"Paint", 1⟩, ⟨"Paint", 1100000⟩, ⟨"Paint", 2150000⟩, ⟨"Composite", 2150000⟩, ⟨"Paint", 3100000⟩]),
   (wsOne, [⟨"Layout", 499⟩, ⟨"Layout", 500⟩, ⟨"Layout", 699⟩, ⟨"Layout", 700⟩]),
   ([], [⟨"Layout", 1⟩])]

private def cellCases : List (List Int × List Int × List Int × Nat) :=
  [([13, 13, 14], [13, 12, 13], [0, 0], 0), ([13, 13, 14], [13, 12, 13], [0, 12], 0), ([13, 13, 14], [13, 12, 13], [20, 21], 0),
   ([13, 13, 14], [30, 30, 31], [0, 0], 0),
   ([13, 13], [13, 12, 13], [0, 0], 0), ([13, 13, 14], [13, 12], [0, 0], 0), ([13, 13], [13, 12], [20, 21], 0), ([13], [13], [0], 0),
   ([], [13], [0], 0), ([], [13], [0], 2), ([13], [], [0], 0), ([13], [13], [], 1),
   ([2, 3, 3], [2, 3, 2], [2, 3], 0), ([5, 5, 5], [5, 5, 5], [5], 0), ([5, 5, 5], [5, 5, 5], [4], 0), ([5, 5, 5], [5, 5, 5], [6], 0),
   ([5, 5, 6], [5, 6, 6], [1, 2], 0)]

private def bgCases : List (List Nat) :=
  [[], [5], [47], [5, 5], [47, 49], [5, 47], [23, 23], [24, 24], [24, 23], [28, 49], [42, 5], [50, 50]]

private def nbCases : List (Nat × Nat) := [(0, 8), (1, 8), (6, 8), (7, 8), (0, 1), (0, 2), (1, 2)]

private def goldenLinesA : List String :=
  [(Json.mkObj [("kind", "swapConst"), ("restUs", restUs), ("swapUs", swapUs), ("periodUs", periodUs), ("periods", periods),
    ("tolUs", tolUs), ("deadlineUs", deadlineUs periods), ("frames60", windowFrames60),
    ("minFaithful", minFaithful), ("busyMin", busyMin)]).compress] ++
  (nomCases.map fun (s0, n) =>
    (Json.mkObj [("kind", "swapNominal"), ("s0", s0), ("n", n), ("wins", Json.arr ((nominal s0 n).map winJ).toArray),
      ("valid", Json.arr ((List.range n).map fun k => toJson (validAt (nominal s0 n) k)).toArray)]).compress) ++
  (([wsNominal, wsDrift, wsOne, []]).map fun ws =>
    (Json.mkObj [("kind", "swapPhase"), ("wins", Json.arr (ws.map winJ).toArray), ("ts", toJson (phaseTimes ws)),
      ("phases", Json.arr ((phaseTimes ws).map fun t => phaseJ (phaseOf ws t)).toArray),
      ("valid", Json.arr ((List.range (ws.length + 1)).map fun k => toJson (validAt ws k)).toArray)]).compress)

private def goldenLinesB : List String :=
  (recCases.map fun (ws, rs) =>
    (Json.mkObj [("kind", "swapCount"), ("wins", Json.arr (ws.map winJ).toArray), ("recs", Json.arr (rs.map recJ).toArray),
      ("cells", Json.arr (((List.range ws.length).flatMap fun k =>
        [Phase.swap k, Phase.rest k].flatMap fun p => ["Layout", "Paint", "Composite"].map fun ty =>
          Json.arr #[phaseJ p, toJson ty, toJson (countIn ws p ty rs)]) ++
        ["Layout", "Paint", "Composite"].map fun ty => Json.arr #[phaseJ .outside, toJson ty, toJson (countIn ws .outside ty rs)]).toArray)]).compress) ++
  (cellCases.map fun (a1, a2, c, d) =>
    (Json.mkObj [("kind", "swapCell"), ("a1", toJson a1), ("a2", toJson a2), ("crop", toJson c), ("dropped", d),
      ("cell", (cell a1 a2 c d).name)]).compress) ++
  (bgCases.map fun ns =>
    (Json.mkObj [("kind", "swapBg"), ("rows", toJson ns), ("bg", (bgOf ns).name)]).compress) ++
  (nbCases.map fun (k, n) =>
    (Json.mkObj [("kind", "swapNeighbours"), ("k", k), ("n", n), ("rests", toJson (swapNeighbours k n))]).compress) ++
  [(Json.mkObj [("kind", "swapPredict"), ("faithful", predictedLayout 1), ("crop", predictedLayout 0)]).compress]

private def runCases : List (List Nat) :=
  [[], [0, 0, 1, 0], List.replicate 18 6 ++ List.replicate 12 0 ++ List.replicate 19 9 ++ List.replicate 12 1,
   [0, 6, 7, 6, 1, 0, 0, 5, 6, 7, 0, 0, 0, 6, 7, 5, 0, 0],
   List.replicate 4 5 ++ [0] ++ List.replicate 5 5, List.replicate 5 4, List.replicate 4 4 ++ [3] ++ List.replicate 4 4,
   [3, 3, 3, 3, 3, 3, 3], List.replicate 6 40, [0, 0, 8, 8, 8, 8, 8, 8]]

private def medianCases : List (List Int) :=
  [[], [4], [4, 6], [6, 4, 5], [3, 3, 4, 15], [16, 2, 9, 9, 1], [5, 5, 5, 5], [14, 3, 14, 12, 3, 14, 11, 3]]

private def bgJ (b : Bg) : Json := toJson b.name

private def frozenCases : List (List (Int × Bg) × List Int) :=
  [([], [4, 5]), ([(6, .unknown)], [4, 5]), ([(3, .idle), (4, .idle), (5, .idle)], [3, 4, 6]),
   ([(3, .idle), (4, .idle), (5, .idle)], []), ([(12, .idle), (13, .idle), (14, .idle)], [3, 4, 6]),
   ([(3, .idle), (4, .busy), (5, .idle)], [3, 4, 6]), ([(3, .idle), (4, .mixed)], [3, 4, 6]),
   ([(3, .idle), (9, .unknown), (6, .idle)], [3, 4, 6]), ([(7, .idle), (7, .idle)], [3, 4, 6]),
   ([(14, .idle), (15, .idle), (16, .idle)], [13, 16]), ([(15, .busy)], [])]

private def goldenLinesC : List String :=
  [(Json.mkObj [("kind", "swapFreezeConst"), ("bucketUs", bucketUs), ("busyBucket", busyBucket), ("swapBuckets", swapBuckets),
    ("longRunMin", longRunMin)]).compress] ++
  (runCases.map fun xs => (Json.mkObj [("kind", "swapRuns"), ("buckets", toJson xs), ("longRuns", longRuns xs)]).compress) ++
  (medianCases.map fun xs => (Json.mkObj [("kind", "swapMedian2"), ("xs", toJson xs), ("median2", median2 xs)]).compress) ++
  (frozenCases.map fun (fr, idle) =>
    (Json.mkObj [("kind", "swapFrozen"), ("frozen", Json.arr (fr.map fun s => Json.arr #[toJson s.1, bgJ s.2]).toArray),
      ("idle", toJson idle), ("cell", (frozenCell fr idle).name)]).compress) ++
  (([(20, 6), (20, 20), (20, 0), (0, 5), (-4, 5), (30, 31), (15, 4)] : List (Int × Int)).map fun (u, f) =>
    (Json.mkObj [("kind", "swapShare"), ("u2", u), ("f2", f), ("pct", match sharePct u f with | some p => toJson p | none => Json.null)]).compress) ++
  (([([15, 16, 14], [4, 5, 6]), ([4, 5, 6], [15, 16, 14]), ([4, 9], [5, 6]), ([], [4]), ([4], [])] : List (List Int × List Int)).map fun (off, on) =>
    (Json.mkObj [("kind", "swapZone"), ("off", toJson off), ("on", toJson on), ("verdict", (zoneVerdict off on).name)]).compress)

private def pooledCases : List (List Nat × Nat) :=
  [([], 0), ([], 2), ([24, 23, 47], 3), ([1, 2, 3, 4], 2), (List.replicate 56 2, 8), ([50, 49, 5, 2, 24, 24, 0], 1),
   (List.replicate 28 48, 4)]

private def frameCases : List (Nat × Nat) := [(0, 0), (5, 0), (0, 40), (40, 40), (47, 40), (1, 3), (2, 3), (123, 40), (900, 40)]

private def fitsCases : List (Nat × Nat) :=
  [(0, 0), (0, 120000), (laneBudgetMin * 60000 - 1, 1), (laneBudgetMin * 60000, 1), (laneBudgetMin * 60000, 0), (1200000, 300000), (1500000, 300000)]

private def goldenLinesD : List String :=
  [(Json.mkObj [("kind", "swapLaneConst"), ("budgetMin", laneBudgetMin), ("stepMin", Fw.Measure.SimBound.perSessionMin)]).compress] ++
  (([([], [3]), ([15, 16, 14], []), ([15, 16, 14], [3, 4, 5]), ([3, 4, 5], [15, 16]), ([4, 9], [5, 6]), ([14, 14], [14]),
      ([5], [5])] : List (List Int × List Int)).map fun (busy, frozen) =>
    (Json.mkObj [("kind", "swapBusyFrozen"), ("busy", toJson busy), ("frozen", toJson frozen), ("cell", (busyFrozen busy frozen).name)]).compress) ++
  (pooledCases.map fun (ns, caps) =>
    (Json.mkObj [("kind", "swapPooled"), ("rows", toJson ns), ("captures", caps), ("busyWindows", busyWindows ns),
      ("tenthsPerCapture", perCaptureTenths (ns.foldl (· + ·) 0) caps), ("median2", median2 (ns.map Int.ofNat))]).compress) ++
  (frameCases.map fun (rows, frames) =>
    (Json.mkObj [("kind", "swapPerFrame"), ("rows", rows), ("frames", frames),
      ("milli", match perFrameMilli rows frames with | some m => toJson m | none => Json.null)]).compress) ++
  (fitsCases.map fun (e, est) =>
    (Json.mkObj [("kind", "swapUnitFits"), ("elapsedMs", e), ("estimateMs", est), ("fits", unitFits e est)]).compress) ++
  (([0, 1, 2, 3, 4] : List Nat).map fun (sh : Nat) =>
    (Json.mkObj [("kind", "swapLaneUnits"), ("shift", toJson sh), ("units", toJson (laneUnits sh))]).compress)

def swapGoldenLines : List String := goldenLinesA ++ goldenLinesB ++ goldenLinesC ++ goldenLinesD

end Fw.Measure.SwapWindow
