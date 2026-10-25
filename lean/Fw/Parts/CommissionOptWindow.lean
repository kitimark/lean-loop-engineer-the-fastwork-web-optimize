import Fw.Parts.CommissionOpt
import Fw.Parts.CommissionOptLayout
/-!
commission:band-gate, where the skip happens: the follower moves only inside two scroll bands and 28 events after.
Proof note: `research/notes/2026/10-2x-commission-band-mech.md`.
-/
namespace Fw.Parts.CommissionOptWindow

open Fw.Site.Breakpoints Fw.Parts.Commission Fw.Parts.CommissionOpt

def enterFrom (cardTop vh : Rat) : Rat := cardTop - enterHi * vh

def enterTo (cardTop vh : Rat) : Rat := cardTop - enterLo * vh

def exitFrom (bottom vh : Rat) : Rat := bottom - exitHi * vh

def exitTo (bottom vh : Rat) : Rat := bottom - exitLo * vh

def inEnter (cardTop vh y : Rat) : Prop := enterFrom cardTop vh < y ∧ y < enterTo cardTop vh

def inExit (bottom vh y : Rat) : Prop := exitFrom bottom vh < y ∧ y < exitTo bottom vh

def inBand (cardTop bottom vh y : Rat) : Prop := inEnter cardTop vh y ∨ inExit bottom vh y

instance (cardTop bottom vh y : Rat) : Decidable (inBand cardTop bottom vh y) := by
  unfold inBand inEnter inExit; infer_instance

def evAt (cardTop bottom vh y : Rat) : Ev := ⟨true, false, cardTop - y, bottom - y, vh⟩

def tgtE (cardTop vh y : Rat) : Rat := target false (enterRaw (cardTop - y) vh)

def tgtX (bottom vh y : Rat) : Rat := target false (exitRaw (bottom - y) vh)

theorem enterRaw_above (cardTop vh y : Rat) (h : y ≤ enterFrom cardTop vh) : enterRaw (cardTop - y) vh = 1 := by
  unfold enterRaw
  unfold enterFrom enterHi at h
  unfold enterHi enterLo
  split <;> first | rfl | (exfalso; grind)

theorem enterRaw_below (cardTop vh y : Rat) (hv : 0 < vh) (h : enterTo cardTop vh ≤ y) : enterRaw (cardTop - y) vh = 0 := by
  unfold enterRaw
  unfold enterTo enterLo at h
  unfold enterHi enterLo
  split
  · exfalso; grind
  · split
    · rfl
    · exfalso; grind

theorem exitRaw_above (bottom vh y : Rat) (h : y ≤ exitFrom bottom vh) : exitRaw (bottom - y) vh = 0 := by
  unfold exitRaw
  unfold exitFrom exitHi at h
  unfold exitHi exitLo
  split <;> first | rfl | (exfalso; grind)

theorem exitRaw_below (bottom vh y : Rat) (hv : 0 < vh) (h : exitTo bottom vh ≤ y) : exitRaw (bottom - y) vh = 1 := by
  unfold exitRaw
  unfold exitTo exitLo at h
  unfold exitHi exitLo
  split
  · exfalso; grind
  · split
    · rfl
    · exfalso; grind

theorem smooth_one : smooth 1 = 1 := by decide +kernel

theorem smooth_zero : smooth 0 = 0 := by decide +kernel

theorem absR_nonneg (x : Rat) : 0 ≤ absR x := by unfold absR; grind

theorem n_contracts (s : Pair) (top bottom h : Rat) (c : Bool) :
    absR (target false (enterRaw top h) - (frame s top bottom h false c).n)
      ≤ (78 / 100) * absR (target false (enterRaw top h) - s.n) := by
  unfold frame gainOf
  have e : gain = 22 / 100 := rfl
  simp only [Bool.false_eq_true, ite_false, e]
  generalize target false (enterRaw top h) = m
  generalize s.n = n
  have h0 := absR_nonneg (m - n)
  have h1 := abs_zero_lt
  unfold absR eps at *
  split
  · split
    · grind
    · grind
  · split <;> grind

theorem r_contracts (s : Pair) (top bottom h : Rat) (c : Bool) :
    absR (target false (exitRaw bottom h) - (frame s top bottom h false c).r)
      ≤ (78 / 100) * absR (target false (exitRaw bottom h) - s.r) := by
  unfold frame gainOf
  have e : gain = 22 / 100 := rfl
  simp only [Bool.false_eq_true, ite_false, e]
  generalize target false (exitRaw bottom h) = q
  generalize s.r = r
  have h0 := absR_nonneg (q - r)
  unfold absR eps at *
  split <;> grind

def tE (e : Ev) : Rat := target e.rm (enterRaw e.top e.vh)

def tX (e : Ev) : Rat := target e.rm (exitRaw e.bottom e.vh)

theorem frame_mem (s : Pair) (top bottom h : Rat) (c : Bool)
    (hn : 0 ≤ s.n ∧ s.n ≤ 1) (hr : 0 ≤ s.r ∧ s.r ≤ 1) :
    (0 ≤ (frame s top bottom h false c).n ∧ (frame s top bottom h false c).n ≤ 1) ∧
    (0 ≤ (frame s top bottom h false c).r ∧ (frame s top bottom h false c).r ≤ 1) := by
  have hm := target_mem false (enterRaw top h)
  have hq := target_mem false (exitRaw bottom h)
  unfold frame gainOf
  have e : gain = 22 / 100 := rfl
  simp only [Bool.false_eq_true, ite_false, e]
  generalize target false (enterRaw top h) = m at *
  generalize target false (exitRaw bottom h) = q at *
  constructor
  · split <;> split <;> grind
  · split <;> grind

theorem fol_mem (ev : Nat → Ev) (hrm : ∀ j, (ev j).rm = false) (k : Nat) :
    (0 ≤ (stO ev k).fol.n ∧ (stO ev k).fol.n ≤ 1) ∧ (0 ≤ (stO ev k).fol.r ∧ (stO ev k).fol.r ≤ 1) := by
  induction k with
  | zero =>
    simp only [stO, St.init, pair0]
    grind
  | succ k ih =>
    have := frame_mem (stO ev k).fol (ev k).top (ev k).bottom (ev k).vh (ev k).gate ih.1 ih.2
    simp only [stO, stepO, Ev.frame, hrm k]
    exact this

def dN (ev : Nat → Ev) (k : Nat) : Rat := absR (tE (ev k) - (stO ev (k + 1)).fol.n)

theorem more_false_iff (e : Ev) (st : St) :
    (e.frame st).more = false ↔
      absR (tE e - (e.frame st).n) < eps ∧ absR (tX e - (e.frame st).r) < eps := by
  have h : (e.frame st).more = decide (eps ≤ absR (tE e - (e.frame st).n) ∨ eps ≤ absR (tX e - (e.frame st).r)) := rfl
  rw [h]
  simp only [decide_eq_false_iff_not, not_or, Rat.not_le]

theorem step_contracts (ev : Nat → Ev) (hrm : ∀ j, (ev j).rm = false) (j : Nat) :
    absR (tE (ev j) - (stO ev (j + 1)).fol.n) ≤ (78 / 100) * absR (tE (ev j) - (stO ev j).fol.n) ∧
    absR (tX (ev j) - (stO ev (j + 1)).fol.r) ≤ (78 / 100) * absR (tX (ev j) - (stO ev j).fol.r) := by
  have h1 := n_contracts (stO ev j).fol (ev j).top (ev j).bottom (ev j).vh (ev j).gate
  have h2 := r_contracts (stO ev j).fol (ev j).top (ev j).bottom (ev j).vh (ev j).gate
  have e := hrm j
  simp only [tE, tX, e, stO, stepO, Ev.frame]
  exact ⟨h1, h2⟩

theorem quiet_run (ev : Nat → Ev) (hrm : ∀ j, (ev j).rm = false) (k : Nat) (m q : Rat)
    (hc : ∀ i, i < 29 → tE (ev (k + i)) = m ∧ tX (ev (k + i)) = q) :
    ((ev (k + 28)).frame (stO ev (k + 28))).more = false := by
  have key : ∀ i, i < 29 →
      absR (m - (stO ev (k + (i + 1))).fol.n) ≤ (78 / 100) ^ (i + 1) * absR (m - (stO ev k).fol.n) ∧
      absR (q - (stO ev (k + (i + 1))).fol.r) ≤ (78 / 100) ^ (i + 1) * absR (q - (stO ev k).fol.r) := by
    intro i
    induction i with
    | zero =>
      intro hi
      have h := step_contracts ev hrm k
      have h3 := hc 0 hi
      simp only [Nat.add_zero] at h3 ⊢
      rw [h3.1, h3.2] at h
      rw [Rat.pow_succ, Rat.pow_zero]
      grind
    | succ i ih =>
      intro hi
      have ih' := ih (by omega)
      have h := step_contracts ev hrm (k + (i + 1))
      have h3 := hc (i + 1) hi
      rw [h3.1, h3.2] at h
      have p : (78 / 100 : Rat) ^ (i + 1 + 1) = (78 / 100) * (78 / 100) ^ (i + 1) := by
        rw [Rat.pow_succ (78 / 100 : Rat) (i + 1)]; grind
      have hk : k + (i + 1 + 1) = k + (i + 1) + 1 := by omega
      rw [p, hk]
      constructor
      · have := ih'.1
        have := h.1
        grind
      · have := ih'.2
        have := h.2
        grind
  have hmem := fol_mem ev hrm k
  have hk := key 28 (by omega)
  have hm := target_mem false (enterRaw (ev (k + 28)).top (ev (k + 28)).vh)
  have hq := target_mem false (exitRaw (ev (k + 28)).bottom (ev (k + 28)).vh)
  have h28 := hc 28 (by omega)
  have hrm28 := hrm (k + 28)
  simp only [tE, tX, hrm28] at h28
  rw [h28.1] at hm
  rw [h28.2] at hq
  have hp : (78 / 100 : Rat) ^ (28 + 1) < eps := by decide +kernel
  have d0 : absR (m - (stO ev k).fol.n) ≤ 1 := by unfold absR; grind
  have d1 : absR (q - (stO ev k).fol.r) ≤ 1 := by unfold absR; grind
  have hpos : 0 ≤ (78 / 100 : Rat) ^ (28 + 1) := by decide +kernel
  rw [more_false_iff]
  have e1 : ((ev (k + 28)).frame (stO ev (k + 28))).n = (stO ev (k + (28 + 1))).fol.n := by
    simp only [stO, stepO]
  have e2 : ((ev (k + 28)).frame (stO ev (k + 28))).r = (stO ev (k + (28 + 1))).fol.r := by
    simp only [stO, stepO]
  rw [e1, e2]
  simp only [tE, tX, hrm28]
  rw [h28.1, h28.2]
  constructor
  · have := hk.1
    grind
  · have := hk.2
    grind

theorem tgtE_above (cardTop vh y : Rat) (h : y ≤ enterFrom cardTop vh) : tgtE cardTop vh y = 1 := by
  unfold tgtE
  rw [enterRaw_above cardTop vh y h]
  exact smooth_one

theorem tgtE_below (cardTop vh y : Rat) (hv : 0 < vh) (h : enterTo cardTop vh ≤ y) : tgtE cardTop vh y = 0 := by
  unfold tgtE
  rw [enterRaw_below cardTop vh y hv h]
  exact smooth_zero

theorem tgtX_above (bottom vh y : Rat) (h : y ≤ exitFrom bottom vh) : tgtX bottom vh y = 0 := by
  unfold tgtX
  rw [exitRaw_above bottom vh y h]
  exact smooth_zero

theorem tgtX_below (bottom vh y : Rat) (hv : 0 < vh) (h : exitTo bottom vh ≤ y) : tgtX bottom vh y = 1 := by
  unfold tgtX
  rw [exitRaw_below bottom vh y hv h]
  exact smooth_one

theorem tgtE_step (cardTop vh y1 y2 : Rat) (hv : 0 < vh) (h12 : y1 ≤ y2) (hs : y2 - y1 < 36 / 100 * vh)
    (a : ¬ inEnter cardTop vh y1) (b : ¬ inEnter cardTop vh y2) : tgtE cardTop vh y1 = tgtE cardTop vh y2 := by
  unfold inEnter enterFrom enterTo enterHi enterLo at *
  by_cases c : y1 ≤ cardTop - 42 / 100 * vh
  · have c2 : y2 ≤ cardTop - 42 / 100 * vh := by grind
    rw [tgtE_above cardTop vh y1 (by unfold enterFrom enterHi; exact c), tgtE_above cardTop vh y2 (by unfold enterFrom enterHi; exact c2)]
  · have c1 : cardTop - 6 / 100 * vh ≤ y1 := by grind
    rw [tgtE_below cardTop vh y1 hv (by unfold enterTo enterLo; exact c1), tgtE_below cardTop vh y2 hv (by unfold enterTo enterLo; grind)]

theorem tgtX_step (bottom vh y1 y2 : Rat) (hv : 0 < vh) (h12 : y1 ≤ y2) (hs : y2 - y1 < 36 / 100 * vh)
    (a : ¬ inExit bottom vh y1) (b : ¬ inExit bottom vh y2) : tgtX bottom vh y1 = tgtX bottom vh y2 := by
  unfold inExit exitFrom exitTo exitHi exitLo at *
  by_cases c : y1 ≤ bottom - 85 / 100 * vh
  · have c2 : y2 ≤ bottom - 85 / 100 * vh := by grind
    rw [tgtX_above bottom vh y1 (by unfold exitFrom exitHi; exact c), tgtX_above bottom vh y2 (by unfold exitFrom exitHi; exact c2)]
  · have c1 : bottom - 35 / 100 * vh ≤ y1 := by grind
    rw [tgtX_below bottom vh y1 hv (by unfold exitTo exitLo; exact c1), tgtX_below bottom vh y2 hv (by unfold exitTo exitLo; grind)]

def scrollEv (cardTop bottom vh : Rat) (ys : Nat → Rat) : Nat → Ev := fun k => evAt cardTop bottom vh (ys k)

theorem targets_chain (cardTop bottom vh : Rat) (ys : Nat → Rat) (hv : 0 < vh)
    (hmono : ∀ j, ys j ≤ ys (j + 1)) (hstep : ∀ j, ys (j + 1) - ys j < 36 / 100 * vh) (a n : Nat)
    (hout : ∀ i, i ≤ n → ¬ inBand cardTop bottom vh (ys (a + i))) :
    ∀ i, i ≤ n → tgtE cardTop vh (ys (a + i)) = tgtE cardTop vh (ys a) ∧
      tgtX bottom vh (ys (a + i)) = tgtX bottom vh (ys a) := by
  intro i
  induction i with
  | zero => intro _; exact ⟨rfl, rfl⟩
  | succ i ih =>
    intro hi
    have ih' := ih (by omega)
    have o1 := hout i (by omega)
    have o2 := hout (i + 1) hi
    have e1 : ¬ inEnter cardTop vh (ys (a + i)) := fun h => o1 (Or.inl h)
    have e2 : ¬ inEnter cardTop vh (ys (a + (i + 1))) := fun h => o2 (Or.inl h)
    have x1 : ¬ inExit bottom vh (ys (a + i)) := fun h => o1 (Or.inr h)
    have x2 : ¬ inExit bottom vh (ys (a + (i + 1))) := fun h => o2 (Or.inr h)
    have m1 := hmono (a + i)
    have s1 := hstep (a + i)
    have hk : a + (i + 1) = a + i + 1 := by omega
    rw [hk] at e2 x2 ⊢
    have t1 := tgtE_step cardTop vh _ _ hv m1 s1 e1 e2
    have t2 := tgtX_step bottom vh _ _ hv m1 s1 x1 x2
    exact ⟨t1.symm.trans ih'.1, t2.symm.trans ih'.2⟩

theorem rest_before (cardTop bottom vh : Rat) (ys : Nat → Rat) (hv : 0 < vh)
    (hmono : ∀ j, ys j ≤ ys (j + 1)) (hstep : ∀ j, ys (j + 1) - ys j < 36 / 100 * vh)
    (h0 : ys 0 ≤ enterFrom cardTop vh ∧ ys 0 ≤ exitFrom bottom vh) (n : Nat)
    (hout : ∀ i, i ≤ n → ¬ inBand cardTop bottom vh (ys i)) :
    ∀ i, i ≤ n → (stO (scrollEv cardTop bottom vh ys) i).fol = pair0 := by
  have ch := targets_chain cardTop bottom vh ys hv hmono hstep 0 n (by simpa using hout)
  have t1 : tgtE cardTop vh (ys 0) = 1 := tgtE_above cardTop vh _ h0.1
  have t2 : tgtX bottom vh (ys 0) = 0 := tgtX_above bottom vh _ h0.2
  intro i
  induction i with
  | zero => intro _; rfl
  | succ i ih =>
    intro hi
    have ih' := ih (by omega)
    have c := ch i (by omega)
    simp only [Nat.zero_add] at c
    have hn : pair0.n = target false (enterRaw (cardTop - ys i) vh) := by
      show (1 : Rat) = tgtE cardTop vh (ys i)
      rw [c.1, t1]
    have hr : pair0.r = target false (exitRaw (bottom - ys i) vh) := by
      show (0 : Rat) = tgtX bottom vh (ys i)
      rw [c.2, t2]
    have hs := frame_settled (cardTop - ys i) (bottom - ys i) vh false true pair0 hn hr
    simp only [stO, stepO, Ev.frame, scrollEv, evAt, ih']
    rw [Pair.mk.injEq]
    exact ⟨hs.1, hs.2.1⟩

theorem skip_in_band (cardTop bottom vh : Rat) (ys : Nat → Rat) (hv : 0 < vh)
    (hmono : ∀ j, ys j ≤ ys (j + 1)) (hstep : ∀ j, ys (j + 1) - ys j < 36 / 100 * vh)
    (h0 : ys 0 ≤ enterFrom cardTop vh ∧ ys 0 ≤ exitFrom bottom vh) (k : Nat)
    (hs : (writeNow ((scrollEv cardTop bottom vh ys) k).gate
      (((scrollEv cardTop bottom vh ys) k).frame (stO (scrollEv cardTop bottom vh ys) k)).more) = false) :
    ∃ j, j ≤ k ∧ k ≤ j + 28 ∧ inBand cardTop bottom vh (ys j) := by
  refine Classical.byContradiction fun hno => ?_
  have hno' : ∀ j, j ≤ k → k ≤ j + 28 → ¬ inBand cardTop bottom vh (ys j) := by
    intro j h1 h2 h3
    exact hno ⟨j, h1, h2, h3⟩
  have hmore : (((scrollEv cardTop bottom vh ys) k).frame (stO (scrollEv cardTop bottom vh ys) k)).more = true := by
    cases hm : (((scrollEv cardTop bottom vh ys) k).frame (stO (scrollEv cardTop bottom vh ys) k)).more
    · have hg : (scrollEv cardTop bottom vh ys k).gate = true := rfl
      simp [writeNow, hg, hm] at hs
    · rfl
  have hrm : ∀ j, (scrollEv cardTop bottom vh ys j).rm = false := fun _ => rfl
  by_cases hk : 28 ≤ k
  · obtain ⟨a, ha⟩ : ∃ a, k = a + 28 := ⟨k - 28, by omega⟩
    have ch := targets_chain cardTop bottom vh ys hv hmono hstep a 28
      (fun i hi => hno' (a + i) (by omega) (by omega))
    have q := quiet_run (scrollEv cardTop bottom vh ys) hrm a (tgtE cardTop vh (ys a)) (tgtX bottom vh (ys a))
      (fun i hi => ch i (by omega))
    rw [← ha] at q
    rw [q] at hmore
    exact Bool.noConfusion hmore
  · have ch := rest_before cardTop bottom vh ys hv hmono hstep h0 k (fun i hi => hno' i hi (by omega)) k (Nat.le_refl k)
    have c := targets_chain cardTop bottom vh ys hv hmono hstep 0 k (fun i hi => by simpa using hno' i hi (by omega)) k (Nat.le_refl k)
    simp only [Nat.zero_add] at c
    have t1 : tgtE cardTop vh (ys 0) = 1 := tgtE_above cardTop vh _ h0.1
    have t2 : tgtX bottom vh (ys 0) = 0 := tgtX_above bottom vh _ h0.2
    have hn : pair0.n = target false (enterRaw (cardTop - ys k) vh) := by
      show (1 : Rat) = tgtE cardTop vh (ys k)
      rw [c.1, t1]
    have hr : pair0.r = target false (exitRaw (bottom - ys k) vh) := by
      show (0 : Rat) = tgtX bottom vh (ys k)
      rw [c.2, t2]
    have hs2 := frame_settled (cardTop - ys k) (bottom - ys k) vh false true pair0 hn hr
    simp only [Ev.frame, scrollEv, evAt, ch] at hmore
    rw [hs2.2.2] at hmore
    exact Bool.noConfusion hmore

theorem no_skip_reduced (e : Ev) (st : St) (h : e.rm = true) : writeNow e.gate (e.frame st).more = true := by
  have := (frame_reduced st.fol e.top e.bottom e.vh e.gate).2.2
  simp only [Ev.frame, h] at *
  simp [writeNow, this]

theorem no_skip_ungated (e : Ev) (st : St) (h : e.gate = false) : writeNow e.gate (e.frame st).more = true := by
  simp [writeNow, h]


open Fw.Parts.CommissionOptLayout in
def rowBands (r : Row) : Rat × Rat × Rat × Rat :=
  (enterFrom r.cardTop r.height, enterTo r.cardTop r.height,
   exitFrom (r.sectionTop + r.sectionH) r.height, exitTo (r.sectionTop + r.sectionH) r.height)

open Fw.Parts.CommissionOptLayout in
#guard (rows.find? (·.id == "height-probes-430x775")).map rowBands ==
  some (163479 / 64, 181335 / 64, 54785 / 16, 60985 / 16)

open Fw.Parts.CommissionOptLayout in
#guard rows.length == 124 && (rows.filter fun r => c1000.eval r.env).length == 83

end Fw.Parts.CommissionOptWindow
