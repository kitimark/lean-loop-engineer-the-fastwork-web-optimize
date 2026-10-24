import Lean.Data.Json
import Fw.Parts.NavEarnWebkit
/-! Proof note: research/notes/2026/10-2x-earn-logical-proof.md. Both engines interpolate `from + (to - from) * y(x⁻¹((t - delay) / dur))`:
WebKit@862f17d `Source/WebCore/platform/animation/TimingFunction.cpp:100-110`, Chromium@f842f52 `ui/gfx/geometry/cubic_bezier.cc:181-240`. -/
namespace Fw.Parts.NavEarnCurve

open Fw.Engine.TransitionStart Fw.Parts.NavEarnWebkit

def gridBits : Nat := 16

def M : Nat := 2 ^ gridBits

def D : Nat := 100 * M * M * M

theorem M_pos : 0 < M := Nat.two_pow_pos _

theorem D_pos : 0 < D := by
  have := M_pos
  unfold D
  exact Nat.mul_pos (Nat.mul_pos (Nat.mul_pos (by decide) this) this) this

structure Bez where
  x1 : Nat
  y1 : Nat
  x2 : Nat
  y2 : Nat
  deriving DecidableEq, Repr

def earnBez : Bez := ⟨33, 0, 20, 100⟩

def Bez.xBar (b : Bez) (k : Nat) : Nat :=
  3 * b.x1 * (M - k) * (M - k) * k + 3 * b.x2 * (M - k) * k * k + 100 * k * k * k

def Bez.yBar (b : Bez) (k : Nat) : Nat :=
  3 * b.y1 * (M - k) * (M - k) * k + 3 * b.y2 * (M - k) * k * k + 100 * k * k * k

def bisect (p : Nat → Bool) : Nat → Nat → Nat
  | 0, lo => lo
  | n + 1, lo => if p (lo + 2 ^ n) then bisect p n (lo + 2 ^ n) else bisect p n lo

def Bez.solve (b : Bez) (a c : Nat) : Nat :=
  if c ≤ a then M else bisect (fun k => b.xBar k * c ≤ a * D) gridBits 0

def Bez.ease (b : Bez) (a c : Nat) : Nat := b.yBar (b.solve a c)

structure Run where
  fromPx : Nat
  toPx : Nat
  durUs : Nat
  delayUs : Nat
  bez : Bez
  deriving DecidableEq, Repr

def Run.num (r : Run) (t : Nat) : Int :=
  r.fromPx * D + ((r.toPx : Int) - r.fromPx) * r.bez.ease (t - r.delayUs) r.durUs

def padRun (e : Eng) (d : Dir) (l : List Item) (p : CssProp) (fromPx toPx : Nat) : Option Run :=
  if starts e d (entries l) flipChanged p then
    (timing e d l p).map fun (du, de) => ⟨fromPx, toPx, du * 1000, de * 1000, earnBez⟩
  else none

def padAt (e : Eng) (d : Dir) (l : List Item) (p : CssProp) (fromPx toPx t : Nat) : Int :=
  match padRun e d l p fromPx toPx with
  | some r => r.num t
  | none => toPx * D

theorem bisect_spec (p : Nat → Bool) : ∀ n lo, p lo = true → p (lo + 2 ^ n) = false →
    p (bisect p n lo) = true ∧ p (bisect p n lo + 1) = false ∧ lo ≤ bisect p n lo ∧ bisect p n lo < lo + 2 ^ n
  | 0, lo, h1, h2 => by simp [bisect] at *; exact ⟨h1, h2⟩
  | n + 1, lo, h1, h2 => by
    have hp : 2 ^ (n + 1) = 2 ^ n + 2 ^ n := by rw [Nat.pow_succ]; omega
    have h0 := Nat.two_pow_pos n
    unfold bisect
    split
    · next h =>
      obtain ⟨a, b, c, d⟩ := bisect_spec p n (lo + 2 ^ n) h (by rw [Nat.add_assoc, ← hp]; exact h2)
      exact ⟨a, b, by omega, by omega⟩
    · next h =>
      obtain ⟨a, b, c, d⟩ := bisect_spec p n lo h1 (by simpa using h)
      exact ⟨a, b, c, by omega⟩

theorem xBar_zero (b : Bez) : b.xBar 0 = 0 := by simp [Bez.xBar]

theorem xBar_M (b : Bez) : b.xBar M = D := by simp [Bez.xBar, D]

theorem yBar_M (b : Bez) : b.yBar M = D := by simp [Bez.yBar, D]

theorem solve_spec (b : Bez) (a c : Nat) :
    b.solve a c ≤ M ∧ b.xBar (b.solve a c) * c ≤ a * D ∧ (b.solve a c = M ∨ a * D < b.xBar (b.solve a c + 1) * c) := by
  unfold Bez.solve
  split
  · next h =>
    refine ⟨Nat.le_refl _, ?_, Or.inl rfl⟩
    rw [xBar_M, Nat.mul_comm]
    exact Nat.mul_le_mul_right _ h
  · next h =>
    have hM : ¬ (b.xBar (0 + 2 ^ gridBits) * c ≤ a * D) := by
      rw [Nat.zero_add, show 2 ^ gridBits = M from rfl, xBar_M, Nat.mul_comm]
      intro h'
      exact h (Nat.le_of_mul_le_mul_right h' D_pos)
    obtain ⟨h1, h2, _, h4⟩ := bisect_spec (fun k => decide (b.xBar k * c ≤ a * D)) gridBits 0
      (by simp [xBar_zero]) (by simpa using hM)
    simp only [decide_eq_true_eq, decide_eq_false_iff_not, Nat.not_le] at h1 h2
    exact ⟨by simp [M] at h4 ⊢; omega, h1, Or.inr h2⟩

private theorem sq_nn (x : Int) : 0 ≤ x * x := by
  rcases Int.le_total 0 x with h | h
  · exact Int.mul_nonneg h h
  · have := Int.mul_nonneg (Int.neg_nonneg_of_nonpos h) (Int.neg_nonneg_of_nonpos h)
    rwa [Int.neg_mul_neg] at this

private def xP (m k : Int) : Int := 99 * m * m * k - 138 * m * k * k + 139 * k * k * k

private def yP (m k : Int) : Int := 300 * m * k * k - 200 * k * k * k

private theorem xBar_int (k : Nat) (h : k ≤ M) : (earnBez.xBar k : Int) = xP M k := by
  have e : ((M - k : Nat) : Int) = (M : Int) - k := by omega
  simp only [Bez.xBar, earnBez, xP, Int.natCast_add, Int.natCast_mul, e]
  grind

private theorem yBar_int (k : Nat) (h : k ≤ M) : (earnBez.yBar k : Int) = yP M k := by
  have e : ((M - k : Nat) : Int) = (M : Int) - k := by omega
  simp only [Bez.yBar, earnBez, yP, Int.natCast_add, Int.natCast_mul, e]
  grind

private theorem xP_mono (j k m : Int) (h1 : j ≤ k) : xP m j ≤ xP m k := by
  have hs := sq_nn (417 * (j + k) - 276 * m)
  have hv := sq_nn (j - k)
  have hm := sq_nn m
  have hq : 0 ≤ 99 * m * m - 138 * m * (j + k) + 139 * (j * j + j * k + k * k) := by grind
  have := Int.mul_nonneg (by omega : 0 ≤ k - j) hq
  unfold xP
  grind

private theorem yP_mono (j k m : Int) (h0 : 0 ≤ j) (h1 : j ≤ k) (h2 : k ≤ m) : yP m j ≤ yP m k := by
  have a := Int.mul_nonneg h0 (by omega : 0 ≤ m - j)
  have b := Int.mul_nonneg (by omega : 0 ≤ k) (by omega : 0 ≤ m - k)
  have c := Int.mul_nonneg h0 (by omega : 0 ≤ m - k)
  have e := Int.mul_nonneg (by omega : 0 ≤ k) (by omega : 0 ≤ k - j)
  have q : 0 ≤ 300 * m * (j + k) - 200 * (j * j + j * k + k * k) := by grind
  have := Int.mul_nonneg (by omega : 0 ≤ k - j) q
  unfold yP
  grind

private theorem chord (j k m : Int) (h1 : j ≤ k) : 100 * (yP m k - yP m j) ≤ 261 * (xP m k - xP m j) := by
  have hs := sq_nn (337674 * (j + k) - 264072 * m)
  have hv := sq_nn (j - k)
  have hm := sq_nn m
  have hq : 0 ≤ 25839 * m * m - 66018 * m * (j + k) + 56279 * (j * j + j * k + k * k) := by grind
  have := Int.mul_nonneg (by omega : 0 ≤ k - j) hq
  unfold xP yP
  grind

private theorem xP_step (k m : Int) (h0 : 0 ≤ k) (h1 : k + 1 ≤ m) : xP m (k + 1) - xP m k ≤ 300 * (m * m) := by
  have p1 := Int.mul_nonneg (by omega : 0 ≤ m - (k + 1)) (by omega : 0 ≤ m - 1)
  have p2 := Int.mul_nonneg (by omega : 0 ≤ m - (k + 1)) (by omega : 0 ≤ k + 1)
  have p3 := Int.mul_nonneg (by omega : 0 ≤ k + 1) h0
  have hm := sq_nn m
  unfold xP
  grind

private theorem yP_step (k m : Int) : yP m (k + 1) - yP m k ≤ 150 * (m * m) := by
  have hs := sq_nn (m - 1 - 2 * k)
  unfold yP
  grind

theorem xBar_mono (j k : Nat) (h1 : j ≤ k) (h2 : k ≤ M) : earnBez.xBar j ≤ earnBez.xBar k := by
  have := xP_mono j k M (by omega)
  rw [← xBar_int j (by omega), ← xBar_int k h2] at this
  omega

theorem yBar_mono (j k : Nat) (h1 : j ≤ k) (h2 : k ≤ M) : earnBez.yBar j ≤ earnBez.yBar k := by
  have := yP_mono j k M (by omega) (by omega) (by omega)
  rw [← yBar_int j (by omega), ← yBar_int k h2] at this
  omega

theorem chord_bound (j k : Nat) (h1 : j ≤ k) (h2 : k ≤ M) :
    100 * earnBez.yBar k + 261 * earnBez.xBar j ≤ 100 * earnBez.yBar j + 261 * earnBez.xBar k := by
  have := chord j k M (by omega)
  rw [← xBar_int j (by omega), ← xBar_int k h2, ← yBar_int j (by omega), ← yBar_int k h2] at this
  omega

theorem xBar_step (k : Nat) (h : k + 1 ≤ M) : earnBez.xBar (k + 1) ≤ earnBez.xBar k + 300 * M * M := by
  have := xP_step k M (by omega) (by omega)
  rw [show ((k : Int) + 1) = ((k + 1 : Nat) : Int) by omega, ← xBar_int (k + 1) h, ← xBar_int k (by omega)] at this
  rw [Nat.mul_assoc]
  have h' : ((earnBez.xBar (k + 1) : Nat) : Int) ≤ ((earnBez.xBar k + 300 * (M * M) : Nat) : Int) := by
    rw [Int.natCast_add, Int.natCast_mul, Int.natCast_mul]; omega
  exact Int.ofNat_le.mp h'

theorem yBar_step (k : Nat) (h : k + 1 ≤ M) : earnBez.yBar (k + 1) ≤ earnBez.yBar k + 150 * M * M := by
  have := yP_step k M
  rw [show ((k : Int) + 1) = ((k + 1 : Nat) : Int) by omega, ← yBar_int (k + 1) h, ← yBar_int k (by omega)] at this
  rw [Nat.mul_assoc]
  have h' : ((earnBez.yBar (k + 1) : Nat) : Int) ≤ ((earnBez.yBar k + 150 * (M * M) : Nat) : Int) := by
    rw [Int.natCast_add, Int.natCast_mul, Int.natCast_mul]; omega
  exact Int.ofNat_le.mp h'

theorem solve_mono (a a' c : Nat) (h : a ≤ a') : earnBez.solve a c ≤ earnBez.solve a' c := by
  obtain ⟨k1, x1, _⟩ := solve_spec earnBez a c
  obtain ⟨k2, _, h2⟩ := solve_spec earnBez a' c
  rcases h2 with h2 | h2
  · omega
  · apply Nat.not_lt.mp
    intro hlt
    have hx := xBar_mono (earnBez.solve a' c + 1) (earnBez.solve a c) hlt k1
    have : earnBez.xBar (earnBez.solve a' c + 1) * c ≤ a' * D :=
      Nat.le_trans (Nat.mul_le_mul_right c hx) (Nat.le_trans x1 (Nat.mul_le_mul_right D h))
    omega

theorem ease_mono (a a' c : Nat) (h : a ≤ a') : earnBez.ease a c ≤ earnBez.ease a' c :=
  yBar_mono _ _ (solve_mono a a' c h) (solve_spec earnBez a' c).1

theorem ease_le_D (a c : Nat) : earnBez.ease a c ≤ D := by
  rw [← yBar_M earnBez]
  exact yBar_mono _ _ (solve_spec earnBez a c).1 (Nat.le_refl _)

theorem ease_full (b : Bez) (a c : Nat) (h : c ≤ a) : b.ease a c = D := by
  simp [Bez.ease, Bez.solve, h, yBar_M]

theorem ease_zero (c : Nat) (hc : 0 < c) : earnBez.ease 0 c = 0 := by
  obtain ⟨_, h, _⟩ := solve_spec earnBez 0 c
  have hk : earnBez.solve 0 c = 0 := by
    apply Nat.eq_zero_of_not_pos
    intro hp
    have := xBar_mono 1 (earnBez.solve 0 c) hp (solve_spec earnBez 0 c).1
    have h1 : 100 ≤ earnBez.xBar 1 := by unfold Bez.xBar; exact Nat.le_add_left _ _
    have : 0 < earnBez.xBar (earnBez.solve 0 c) * c := Nat.mul_pos (by omega) hc
    omega
  simp [Bez.ease, hk, Bez.yBar]

theorem ease_lipschitz (a a' c : Nat) (h : a ≤ a') :
    100 * earnBez.ease a' c * c ≤ 100 * earnBez.ease a c * c + 261 * ((a' - a) * D + 300 * M * M * c) := by
  obtain ⟨k1, x1, r1⟩ := solve_spec earnBez a c
  obtain ⟨k2, x2, _⟩ := solve_spec earnBez a' c
  have hm := solve_mono a a' c h
  have ch := chord_bound _ _ hm k2
  unfold Bez.ease
  generalize earnBez.solve a c = k at *
  generalize earnBez.solve a' c = k' at *
  by_cases hk : k = M
  · subst hk
    have : k' = M := by omega
    subst this
    omega
  · have r1 := r1.resolve_left hk
    have st := xBar_step k (by omega)
    have e1 := Nat.mul_le_mul_right c ch
    have e2 := Nat.mul_le_mul_right c st
    have e3 : (a' - a) * D = a' * D - a * D := Nat.sub_mul a' a D
    have e4 : a * D ≤ a' * D := Nat.mul_le_mul_right D h
    simp only [Nat.add_mul] at e1 e2
    have e5 : 100 * earnBez.yBar k' * c = 100 * (earnBez.yBar k' * c) := Nat.mul_assoc _ _ _
    have e6 : 100 * earnBez.yBar k * c = 100 * (earnBez.yBar k * c) := Nat.mul_assoc _ _ _
    have e7 : 261 * earnBez.xBar k' * c = 261 * (earnBez.xBar k' * c) := Nat.mul_assoc _ _ _
    have e8 : 261 * earnBez.xBar k * c = 261 * (earnBez.xBar k * c) := Nat.mul_assoc _ _ _
    have e9 : 300 * M * M * c = 300 * M * M * c := rfl
    omega

theorem num_settle (r : Run) (t : Nat) (h : r.delayUs + r.durUs ≤ t) : r.num t = r.toPx * D := by
  simp only [Run.num, ease_full r.bez _ _ (by omega : r.durUs ≤ t - r.delayUs)]
  push_cast
  grind

theorem num_hold (r : Run) (t : Nat) (hb : r.bez = earnBez) (hc : 0 < r.durUs) (h : t ≤ r.delayUs) :
    r.num t = r.fromPx * D := by
  simp [Run.num, hb, show t - r.delayUs = 0 by omega, ease_zero _ hc]

theorem num_mono (r : Run) (t t' : Nat) (hb : r.bez = earnBez) (h : t ≤ t') :
    (r.fromPx ≤ r.toPx → r.num t ≤ r.num t') ∧ (r.toPx ≤ r.fromPx → r.num t' ≤ r.num t) := by
  have he := ease_mono (t - r.delayUs) (t' - r.delayUs) r.durUs (by omega)
  simp only [Run.num, hb]
  generalize earnBez.ease (t - r.delayUs) r.durUs = x at *
  generalize earnBez.ease (t' - r.delayUs) r.durUs = y at *
  constructor
  · intro hl
    have := Int.mul_le_mul_of_nonneg_left (by omega : (x : Int) ≤ y) (by omega : (0 : Int) ≤ (r.toPx : Int) - r.fromPx)
    omega
  · intro hl
    have := Int.mul_le_mul_of_nonneg_left (by omega : (x : Int) ≤ y) (by omega : (0 : Int) ≤ (r.fromPx : Int) - r.toPx)
    grind

theorem num_between (r : Run) (t : Nat) (hb : r.bez = earnBez) (hc : 0 < r.durUs) :
    (r.fromPx ≤ r.toPx → r.fromPx * D ≤ r.num t ∧ r.num t ≤ r.toPx * D) ∧
    (r.toPx ≤ r.fromPx → r.toPx * D ≤ r.num t ∧ r.num t ≤ r.fromPx * D) := by
  have lo := num_mono r 0 t hb (Nat.zero_le _)
  rw [num_hold r 0 hb hc (Nat.zero_le _)] at lo
  by_cases ht : t ≤ r.delayUs + r.durUs
  · have hi := num_mono r t (r.delayUs + r.durUs) hb ht
    rw [num_settle r _ (Nat.le_refl _)] at hi
    exact ⟨fun h => ⟨lo.1 h, hi.1 h⟩, fun h => ⟨hi.2 h, lo.2 h⟩⟩
  · have e := num_settle r t (by omega)
    exact ⟨fun h => ⟨lo.1 h, by omega⟩, fun h => ⟨by omega, lo.2 h⟩⟩

def padProps : List CssProp := [.paddingLeft, .paddingRight]

theorem run_identity (d : Dir) (p : CssProp) (fromPx toPx : Nat) :
    padRun .webkit d variantHero p fromPx toPx = padRun .chromium d faithfulHero p fromPx toPx ∧
    padRun .webkit d variantBase p fromPx toPx = padRun .chromium d faithfulBase p fromPx toPx := by
  have ht := variant_webkit_timing_eq_chromium_faithful d p
  have s1 : starts .webkit d (entries variantHero) flipChanged p = starts .chromium d (entries faithfulHero) flipChanged p := by
    cases d <;> cases p <;> decide
  have s2 : starts .webkit d (entries variantBase) flipChanged p = starts .chromium d (entries faithfulBase) flipChanged p := by
    cases d <;> cases p <;> decide
  simp only [padRun, s1, s2, ht.1, ht.2, and_self]

theorem curve_identity (d : Dir) (p : CssProp) (fromPx toPx t : Nat) :
    padAt .webkit d variantHero p fromPx toPx t = padAt .chromium d faithfulHero p fromPx toPx t ∧
    padAt .webkit d variantBase p fromPx toPx t = padAt .chromium d faithfulBase p fromPx toPx t := by
  have h := run_identity d p fromPx toPx
  simp only [padAt, h.1, h.2, and_self]

theorem chromium_unchanged (d : Dir) (p : CssProp) (fromPx toPx t : Nat) :
    padAt .chromium d variantHero p fromPx toPx t = padAt .chromium d faithfulHero p fromPx toPx t ∧
    padAt .chromium d variantBase p fromPx toPx t = padAt .chromium d faithfulBase p fromPx toPx t := by
  have ht := variant_chromium_timing d p
  have s1 : starts .chromium d (entries variantHero) flipChanged p = starts .chromium d (entries faithfulHero) flipChanged p := by
    cases d <;> cases p <;> decide
  have s2 : starts .chromium d (entries variantBase) flipChanged p = starts .chromium d (entries faithfulBase) flipChanged p := by
    cases d <;> cases p <;> decide
  simp only [padAt, padRun, s1, s2, ht.1, ht.2, and_self]

def earnRun (fromPx toPx : Nat) : Run := ⟨fromPx, toPx, 680000, 0, earnBez⟩

theorem variant_runs (d : Dir) (p : CssProp) (hp : p ∈ padProps) (fromPx toPx : Nat) :
    padRun .webkit d variantHero p fromPx toPx = some (earnRun fromPx toPx) ∧
    padRun .webkit d variantBase p fromPx toPx = some (earnRun fromPx toPx) := by
  simp only [padProps, List.mem_cons, List.mem_nil_iff, or_false] at hp
  rcases hp with rfl | rfl <;> cases d <;> exact ⟨rfl, rfl⟩

theorem faithful_webkit_snaps (d : Dir) (p : CssProp) (hp : p ∈ padProps) (fromPx toPx t : Nat) :
    padAt .webkit d faithfulHero p fromPx toPx t = toPx * D ∧ padAt .webkit d faithfulBase p fromPx toPx t = toPx * D := by
  simp only [padProps, List.mem_cons, List.mem_nil_iff, or_false] at hp
  rcases hp with rfl | rfl <;> cases d <;> exact ⟨rfl, rfl⟩

theorem settle_680 (d : Dir) (p : CssProp) (hp : p ∈ padProps) (fromPx toPx t : Nat) (h : 680000 ≤ t) :
    padAt .webkit d variantHero p fromPx toPx t = toPx * D ∧ padAt .webkit d variantBase p fromPx toPx t = toPx * D := by
  have hr := variant_runs d p hp fromPx toPx
  simp only [padAt, hr.1, hr.2]
  exact ⟨num_settle _ _ (by simp [earnRun]; omega), num_settle _ _ (by simp [earnRun]; omega)⟩

theorem variant_monotone (d : Dir) (p : CssProp) (hp : p ∈ padProps) (fromPx toPx t t' : Nat) (h : t ≤ t') :
    (fromPx ≤ toPx → padAt .webkit d variantHero p fromPx toPx t ≤ padAt .webkit d variantHero p fromPx toPx t') ∧
    (toPx ≤ fromPx → padAt .webkit d variantHero p fromPx toPx t' ≤ padAt .webkit d variantHero p fromPx toPx t) ∧
    (fromPx ≤ toPx → padAt .webkit d variantBase p fromPx toPx t ≤ padAt .webkit d variantBase p fromPx toPx t') ∧
    (toPx ≤ fromPx → padAt .webkit d variantBase p fromPx toPx t' ≤ padAt .webkit d variantBase p fromPx toPx t) := by
  have hr := variant_runs d p hp fromPx toPx
  have m := num_mono (earnRun fromPx toPx) t t' rfl h
  simp only [padAt, hr.1, hr.2]
  exact ⟨m.1, m.2, m.1, m.2⟩

theorem variant_between (d : Dir) (p : CssProp) (hp : p ∈ padProps) (fromPx toPx t : Nat) :
    (fromPx ≤ toPx → fromPx * D ≤ padAt .webkit d variantHero p fromPx toPx t ∧
      padAt .webkit d variantHero p fromPx toPx t ≤ toPx * D) ∧
    (toPx ≤ fromPx → toPx * D ≤ padAt .webkit d variantHero p fromPx toPx t ∧
      padAt .webkit d variantHero p fromPx toPx t ≤ fromPx * D) := by
  have hr := variant_runs d p hp fromPx toPx
  simp only [padAt, hr.1]
  exact num_between (earnRun fromPx toPx) t rfl (by simp [earnRun])

def ceilDiv (a b : Nat) : Nat := (a + b - 1) / b

theorem le_ceilDiv (a b : Nat) (hb : 0 < b) : a ≤ b * ceilDiv a b := by
  unfold ceilDiv
  have := Nat.div_add_mod (a + b - 1) b
  have := Nat.mod_lt (a + b - 1) hb
  omega

def slackMicro (deltaPx w durUs : Nat) : Nat :=
  ceilDiv (deltaPx * 261 * w * 1000000) (100 * durUs) + ceilDiv (deltaPx * 783 * 1000000) (100 * M)

private theorem ring1 (c x δ : Nat) : 100 * c * (δ * x * 1000000) = δ * 1000000 * (100 * c * x) := by grind

private theorem ring2 (δ m w c : Nat) : δ * 1000000 * (261 * (100 * m * m * m) * w + 78300 * (m * m) * c) =
    δ * 261 * w * 1000000 * (100 * m * m * m) + δ * 783 * 1000000 * (100 * m * m * c) := by grind

private theorem ring3 (c c1 c2 m : Nat) : 100 * c * ((c1 + c2) * (100 * m * m * m)) =
    100 * c * c1 * (100 * m * m * m) + 100 * m * c2 * (100 * m * m * c) := by grind

private theorem ring4 (e x c g m : Nat) : 100 * (e + x) * c = 100 * e * c + 100 * c * x ∧
    261 * (g * (100 * m * m * m) + 300 * m * m * c) = 261 * (100 * m * m * m) * g + 78300 * (m * m) * c := by
  constructor <;> grind

private theorem slack_core (c x δ w c1 c2 m g e : Nat)
    (hl : 100 * (e + x) * c ≤ 100 * e * c + 261 * (g * (100 * m * m * m) + 300 * m * m * c)) (hg : g ≤ w)
    (hc1 : δ * 261 * w * 1000000 ≤ 100 * c * c1) (hc2 : δ * 783 * 1000000 ≤ 100 * m * c2) (hc : 0 < c) :
    δ * x * 1000000 ≤ (c1 + c2) * (100 * m * m * m) := by
  have hL : 100 * c * x ≤ 261 * (100 * m * m * m) * w + 78300 * (m * m) * c := by
    have := Nat.mul_le_mul_left (261 * (100 * m * m * m)) hg
    rw [(ring4 e x c g m).1, (ring4 e x c g m).2] at hl
    omega
  have hm := Nat.mul_le_mul_left (δ * 1000000) hL
  have h1 := Nat.mul_le_mul_right (100 * m * m * m) hc1
  have h2 := Nat.mul_le_mul_right (100 * m * m * c) hc2
  refine Nat.le_of_mul_le_mul_left (c := 100 * c) ?_ (by omega)
  rw [ring1 c x δ, ring3 c c1 c2 m]
  rw [ring2 δ m w c] at hm
  exact Nat.le_trans hm (Nat.add_le_add h1 h2)

theorem num_slack (r : Run) (hb : r.bez = earnBez) (hc : 0 < r.durUs) (t t' w : Nat) (h : t ≤ t') (hw : t' ≤ t + w) :
    (r.num t' - r.num t).natAbs * 1000000 ≤ slackMicro ((r.toPx : Int) - r.fromPx).natAbs w r.durUs * D := by
  have hl := ease_lipschitz (t - r.delayUs) (t' - r.delayUs) r.durUs (by omega)
  have he := ease_mono (t - r.delayUs) (t' - r.delayUs) r.durUs (by omega)
  have ha : (t' - r.delayUs) - (t - r.delayUs) ≤ w := by omega
  have hdiff : r.num t' - r.num t =
      ((r.toPx : Int) - r.fromPx) * ((earnBez.ease (t' - r.delayUs) r.durUs : Int) - earnBez.ease (t - r.delayUs) r.durUs) := by
    simp only [Run.num, hb]
    grind
  rw [hdiff, Int.natAbs_mul]
  generalize earnBez.ease (t - r.delayUs) r.durUs = e at *
  generalize earnBez.ease (t' - r.delayUs) r.durUs = e' at *
  generalize ((r.toPx : Int) - r.fromPx).natAbs = δ
  obtain ⟨x, rfl⟩ : ∃ x, e' = e + x := ⟨e' - e, by omega⟩
  have hx : (((e + x : Nat) : Int) - e).natAbs = x := by omega
  rw [hx]
  generalize r.durUs = c at *
  generalize (t' - r.delayUs) - (t - r.delayUs) = g at *
  have hD : D = 100 * M * M * M := rfl
  rw [hD] at hl
  unfold slackMicro
  rw [hD]
  exact slack_core c x δ w _ _ M g e hl ha (le_ceilDiv _ _ (by omega)) (le_ceilDiv _ _ (by have := M_pos; omega)) hc

def tolMicro (deltaPx jUs eUs durUs : Nat) : Nat :=
  slackMicro deltaPx (jUs + eUs) durUs + ceilDiv (deltaPx * 150 * 1000000) (100 * M) + 50

-- WebKit solves x to 1/(1000·dur s), i.e. 1 ms: `Source/WebCore/platform/animation/TimingFunction.cpp:100-110`@862f17d;
-- Chromium to 1e-7: `ui/gfx/geometry/cubic_bezier.cc:22`@f842f52.
def solverUs : Eng → Nat
  | .webkit => 1000
  | .chromium => 1

def toMicroPx (n : Int) : Nat := (n.toNat * 1000000 + D / 2) / D

#guard earnBez.solve 0 680000 = 0
#guard earnBez.solve 680000 680000 = M
#guard earnBez.ease 0 680000 = 0
#guard earnBez.ease 680000 680000 = D
#guard earnBez.ease 340000 680000 > D / 2
#guard toMicroPx ((earnRun 24 0).num 340000) < 12000000
#guard padRun .webkit .ltr faithfulHero .paddingLeft 24 0 = none
#guard padRun .webkit .ltr variantHero .paddingLeft 24 0 = some (earnRun 24 0)
#guard padAt .webkit .ltr variantBase .paddingRight 0 16 700000 = 16 * D
#guard padAt .chromium .ltr faithfulHero .paddingLeft 24 0 0 = 24 * D
#guard ceilDiv 7 2 = 4 ∧ ceilDiv 8 2 = 4
#guard slackMicro 24 0 680000 = 2868
#guard solverUs .webkit = 1000

def widths : List (Nat × Nat) := [(390, 16), (1280, 24)]

def seqList (entry : Bool) (variant : Bool) : List Item :=
  match entry, variant with
  | true, true => variantHero
  | true, false => faithfulHero
  | false, true => variantBase
  | false, false => faithfulBase

def seqEnds (entry : Bool) (pad : Nat) : Nat × Nat := if entry then (pad, 0) else (0, pad)

def seqName (entry : Bool) : String := if entry then "entry" else "exit"

def frameUs (n : Nat) : Nat := n * 50000 / 3

def sampleTimes : List Nat := (List.range 43).map frameUs ++ [680000]

open Lean in
private def line (fn : String) (inp : List (String × Json)) (out : Json) : String :=
  (Json.mkObj [("fn", Json.str fn), ("in", Json.mkObj inp), ("out", out)]).compress

open Lean in
private def runJson : Option Run → Json
  | none => Json.null
  | some r => Json.mkObj [("fromPx", Json.num (r.fromPx : Nat)), ("toPx", Json.num (r.toPx : Nat)),
      ("durUs", Json.num (r.durUs : Nat)), ("delayUs", Json.num (r.delayUs : Nat)), ("curve", curveJson)]

def tolCases : List (Nat × Nat × Nat) :=
  [16, 24].flatMap fun dl => [0, 500, 1000, 2500, 16667].flatMap fun j => [1, 1000].map fun e => (dl, j, e)

open Lean in
def lines (_ : Unit) : List String :=
  [line "grid" [] (Json.mkObj [("gridBits", Json.num gridBits), ("M", Json.num M), ("D", Json.str (toString D)),
      ("slopeNum", Json.num (261 : Nat)), ("slopeDen", Json.num (100 : Nat)), ("xStep", Json.num (300 : Nat)),
      ("yStep", Json.num (150 : Nat)), ("readMicro", Json.num (50 : Nat)),
      ("solverUs", Json.mkObj [("chromium", Json.num (solverUs .chromium)), ("webkit", Json.num (solverUs .webkit))])])]
  ++ (widths.flatMap fun (w, pad) => [true, false].flatMap fun entry => [Eng.chromium, .webkit].flatMap fun e =>
    [false, true].flatMap fun variant => [CssProp.paddingLeft, .paddingRight].map fun p =>
      line "run" [("width", Json.num w), ("seq", Json.str (seqName entry)), ("engine", Json.str e.name),
          ("arm", Json.str (if variant then "variant" else "faithful")), ("prop", Json.str p.css)]
        (runJson (padRun e .ltr (seqList entry variant) p (seqEnds entry pad).1 (seqEnds entry pad).2)))
  ++ (widths.flatMap fun (w, pad) => [true, false].flatMap fun entry => sampleTimes.map fun t =>
    let v := padAt .webkit .ltr (seqList entry true) .paddingLeft (seqEnds entry pad).1 (seqEnds entry pad).2 t
    line "sample" [("width", Json.num w), ("seq", Json.str (seqName entry)), ("tUs", Json.num t)]
      (Json.mkObj [("num", Json.str (toString v)), ("microPx", Json.num (toMicroPx v))]))
  ++ (tolCases.map fun (dl, j, e) =>
    line "tol" [("deltaPx", Json.num dl), ("jUs", Json.num j), ("eUs", Json.num e), ("durUs", Json.num (680000 : Nat))]
      (Json.mkObj [("slackMicro", Json.num (slackMicro dl (j + e) 680000)), ("tolMicro", Json.num (tolMicro dl j e 680000))]))

def goldenText (_ : Unit) : String := String.join ((lines ()).map (· ++ "\n"))

def gen (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText () then
      IO.eprintln s!"nav.earn.curve golden: {path} is up to date ({(lines ()).length} lines)"
      return 0
    IO.eprintln s!"nav.earn.curve golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Parts.NavEarnCurve
