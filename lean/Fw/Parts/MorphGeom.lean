import Fw.Parts.Nav
/-! Compositor-only morph geometry (variant `morph.geom:on`): clip doors, counter layers, piecewise-linear tracks. -/
namespace Fw.Parts.MorphGeom
open Fw.Parts.Nav Fw.Parts.MorphTween

/-- Knots `(m, value)` of a piecewise-linear track, sorted by `m`. -/
abbrev Track := List (Rat × Rat)

def Track.eval : Track → Rat → Rat
  | [], _ => 0
  | [(_, a)], _ => a
  | (p, a) :: (q, b) :: rest, m =>
    if m ≤ q then a + (b - a) * (m - p) / (q - p) else Track.eval ((q, b) :: rest) m

def mk (f : Rat → Rat) (ps : List Rat) : Track := ps.map fun p => (p, f p)

def chord (f : Rat → Rat) (p q m : Rat) : Rat := f p + (f q - f p) * (m - p) / (q - p)

def Within (e B : Rat) : Prop := -B ≤ e ∧ e ≤ B

def lastOf : Rat → List Rat → Rat
  | p, [] => p
  | _, q :: rest => lastOf q rest

def ChordOk (f : Rat → Rat) (B : Rat) : List Rat → Prop
  | p :: q :: rest => p < q ∧ (∀ m, p ≤ m → m ≤ q → Within (chord f p q m - f m) B) ∧ ChordOk f B (q :: rest)
  | _ => True

theorem eval_mk_cons (f : Rat → Rat) (p q : Rat) (rest : List Rat) (m : Rat) :
    Track.eval (mk f (p :: q :: rest)) m = if m ≤ q then chord f p q m else Track.eval (mk f (q :: rest)) m := by
  simp [mk, Track.eval, chord]

theorem eval_mk_within (f : Rat → Rat) (B : Rat) (hB : 0 ≤ B) :
    ∀ (ps : List Rat) (p m : Rat), ChordOk f B (p :: ps) → p ≤ m → m ≤ lastOf p ps →
      Within (Track.eval (mk f (p :: ps)) m - f m) B := by
  intro ps
  induction ps with
  | nil =>
    intro p m _ h1 h2
    have : m = p := by simp only [lastOf] at h2; grind
    subst this
    simp [mk, Track.eval, Within]
    grind
  | cons q rest ih =>
    intro p m hok h1 h2
    obtain ⟨hpq, hseg, hrest⟩ := hok
    rw [eval_mk_cons]
    by_cases hmq : m ≤ q
    · simp only [hmq, ite_true]
      exact hseg m h1 hmq
    · simp only [hmq, ite_false]
      exact ih q m hrest (by grind) (by simpa [lastOf] using h2)

theorem chord_aff (f : Rat → Rat) (α β p q m : Rat) (hpq : p < q)
    (h : ∀ x, p ≤ x → x ≤ q → f x = α + β * x) (h1 : p ≤ m) (h2 : m ≤ q) : chord f p q m = f m := by
  unfold chord
  have hp := h p (by grind) (by grind)
  have hq := h q (by grind) (by grind)
  have hm := h m h1 h2
  have : q - p ≠ 0 := by grind
  rw [hp, hq, hm]
  grind

def AffPieces (f : Rat → Rat) : List Rat → Prop
  | p :: q :: rest => p < q ∧ (∃ α β, ∀ x, p ≤ x → x ≤ q → f x = α + β * x) ∧ AffPieces f (q :: rest)
  | _ => True

theorem chordOk_of_aff (f : Rat → Rat) : ∀ ps : List Rat, AffPieces f ps → ChordOk f 0 ps := by
  intro ps
  induction ps with
  | nil => intros; trivial
  | cons p tl ih =>
    cases tl with
    | nil => intros; trivial
    | cons q rest =>
      intro ⟨hpq, ⟨α, β, h⟩, hr⟩
      refine ⟨hpq, ?_, ih hr⟩
      intro m h1 h2
      rw [chord_aff f α β p q m hpq h h1 h2]
      unfold Within; grind

theorem exact_of_aff (f : Rat → Rat) (ps : List Rat) (p m : Rat) (h : AffPieces f (p :: ps))
    (h1 : p ≤ m) (h2 : m ≤ lastOf p ps) : Track.eval (mk f (p :: ps)) m = f m := by
  have := eval_mk_within f 0 (by grind) ps p m (chordOk_of_aff f _ h) h1 h2
  simp [Within] at this
  grind


/-! ## Rational tracks and the chord identity -/

/-- `κ + (α + β m) / (ρ0 + ρ1 m)`: the shape of every clip and counter track. -/
def ratFn (κ α β ρ0 ρ1 m : Rat) : Rat := κ + (α + β * m) / (ρ0 + ρ1 * m)

/-- `(a + b m) / (1 - c m)`. -/
def mobius (a b c x : Rat) : Rat := (a + b * x) / (1 - c * x)

theorem chord_sub_eq (a b c p q m : Rat) (hc : c ≠ 0) (hp : 1 - c * p ≠ 0) (hq : 1 - c * q ≠ 0)
    (hm : 1 - c * m ≠ 0) (hpq : q - p ≠ 0) :
    chord (mobius a b c) p q m - mobius a b c m
      = (m - p) * (q - m) * (a + b / c) * c ^ 2 / ((1 - c * p) * (1 - c * q) * (1 - c * m)) := by
  unfold chord mobius
  have h3 : (1 - c * p) * (1 - c * q) * (1 - c * m) ≠ 0 := by intro h; grind
  grind

theorem chord_rat_eq (κ α β ρ0 ρ1 p q m : Rat) (hp : ρ0 + ρ1 * p ≠ 0) (hq : ρ0 + ρ1 * q ≠ 0)
    (hm : ρ0 + ρ1 * m ≠ 0) (hpq : q - p ≠ 0) :
    chord (ratFn κ α β ρ0 ρ1) p q m - ratFn κ α β ρ0 ρ1 m
      = (m - p) * (q - m) * ((α * ρ1 - β * ρ0) * ρ1) / ((ρ0 + ρ1 * p) * (ρ0 + ρ1 * q) * (ρ0 + ρ1 * m)) := by
  unfold chord ratFn
  have h3 : (ρ0 + ρ1 * p) * (ρ0 + ρ1 * q) * (ρ0 + ρ1 * m) ≠ 0 := by intro h; grind
  grind

theorem sqNonneg (x : Rat) : 0 ≤ x * x := by
  by_cases h : 0 ≤ x
  · exact Rat.mul_nonneg h h
  · have := Rat.mul_nonneg (show 0 ≤ -x by grind) (show 0 ≤ -x by grind)
    grind

theorem mulLe (a b c d : Rat) (h1 : 0 ≤ a) (h2 : a ≤ b) (h3 : 0 ≤ c) (h4 : c ≤ d) : a * c ≤ b * d := by
  have h5 : a * c ≤ b * c := Rat.mul_le_mul_of_nonneg_right h2 h3
  have h6 : b * c ≤ b * d := Rat.mul_le_mul_of_nonneg_left h4 (by grind)
  grind

theorem within_div (N D c r3 : Rat) (hr : 0 < r3) (hD : r3 ≤ D) (hc : -c ≤ N ∧ N ≤ c) :
    Within (N / D) (c / r3) := by
  have hD0 : 0 < D := by grind
  have hc0 : 0 ≤ c := by grind
  have he : N / D * D = N := by
    have : D ≠ 0 := by grind
    grind
  have hB : c / r3 * r3 = c := by
    have : r3 ≠ 0 := by grind
    grind
  have hB0 : 0 ≤ c / r3 := by
    refine Classical.byContradiction fun h => ?_
    have h' : c / r3 < 0 := by grind
    have := Rat.mul_lt_mul_of_pos_right h' hr
    grind
  have hBD : c / r3 * r3 ≤ c / r3 * D := Rat.mul_le_mul_of_nonneg_left hD hB0
  unfold Within
  constructor
  · refine Classical.byContradiction fun h => ?_
    have h' : N / D < -(c / r3) := by grind
    have := Rat.mul_lt_mul_of_pos_right h' hD0
    grind
  · refine Classical.byContradiction fun h => ?_
    have h' : c / r3 < N / D := by grind
    have := Rat.mul_lt_mul_of_pos_right h' hD0
    grind

/-- Chord error of a rational track on one segment, with `K = (α ρ1 - β ρ0) ρ1`, `r ≥ rmin > 0` and `|K| ≤ Kb`. -/
theorem chord_rat_within (κ α β ρ0 ρ1 p q m rmin Kb : Rat) (hrmin : 0 < rmin)
    (hp : rmin ≤ ρ0 + ρ1 * p) (hq : rmin ≤ ρ0 + ρ1 * q) (hm : rmin ≤ ρ0 + ρ1 * m)
    (hKb : Within ((α * ρ1 - β * ρ0) * ρ1) Kb) (hpq : p < q) (h1 : p ≤ m) (h2 : m ≤ q) :
    Within (chord (ratFn κ α β ρ0 ρ1) p q m - ratFn κ α β ρ0 ρ1 m) ((q - p) ^ 2 / 4 * Kb / rmin ^ 3) := by
  rw [chord_rat_eq κ α β ρ0 ρ1 p q m (by grind) (by grind) (by grind) (by grind)]
  have hr3 : 0 < rmin ^ 3 := by
    have := Rat.mul_pos (Rat.mul_pos hrmin hrmin) hrmin
    grind
  have hD : rmin ^ 3 ≤ (ρ0 + ρ1 * p) * (ρ0 + ρ1 * q) * (ρ0 + ρ1 * m) := by
    have := mulLe _ _ _ _ (Rat.le_of_lt (Rat.mul_pos hrmin hrmin)) (mulLe _ _ _ _ (Rat.le_of_lt hrmin) hp (Rat.le_of_lt hrmin) hq) (Rat.le_of_lt hrmin) hm
    grind
  have hu0 : 0 ≤ (m - p) * (q - m) := Rat.mul_nonneg (by grind) (by grind)
  have hu1 : (m - p) * (q - m) ≤ (q - p) ^ 2 / 4 := by
    have : 0 ≤ ((q - p) - 2 * (m - p)) * ((q - p) - 2 * (m - p)) := by
      have := sqNonneg ((q - p) - 2 * (m - p))
      grind
    grind
  have hKb0 : 0 ≤ Kb := by unfold Within at hKb; grind
  have hc : -((q - p) ^ 2 / 4 * Kb) ≤ (m - p) * (q - m) * ((α * ρ1 - β * ρ0) * ρ1) ∧
      (m - p) * (q - m) * ((α * ρ1 - β * ρ0) * ρ1) ≤ (q - p) ^ 2 / 4 * Kb := by
    unfold Within at hKb
    have a1 := Rat.mul_le_mul_of_nonneg_left hKb.2 hu0
    have a2 := Rat.mul_le_mul_of_nonneg_left hKb.1 hu0
    have a3 := Rat.mul_le_mul_of_nonneg_right hu1 hKb0
    constructor <;> grind
  exact within_div _ _ _ _ hr3 hD hc

/-! ## The final box, the pill inside it and the clip doors -/

/-- Viewports the geometry is stated for. -/
def Valid (v : Vp) : Prop := 320 ≤ v.w ∧ 300 ≤ v.h

/-- Final (m = 1) nav width. -/
def wp (v : Vp) : Rat := panelW v

/-- Final (m = 1) nav height. -/
def hp (v : Vp) : Rat := panelH v

/-- Pill width at `m`. -/
def wd (v : Vp) (m : Rat) : Rat := navWidth v false m

/-- Pill height at `m`. -/
def ht (v : Vp) (m : Rat) : Rat := navHeight v m

/-- Pill left edge in the final box. -/
def x0 (v : Vp) (m : Rat) : Rat := (wp v - wd v m) / 2

/-- Pill top edge in the final box. -/
def y0 (v : Vp) (m : Rat) : Rat := navTop v m - navTop v 1

/-- Used corner radius: the 52 px phone pill clamps 32 to 26. -/
def rad (v : Vp) (m : Rat) : Rat := min (navRadius m) (min (ht v m / 2) (wd v m / 2))

/-- Scale of the first clipper, whose corner has radius 20. -/
def kk (v : Vp) (m : Rat) : Rat := rad v m / 20

/-- The phone radius knot `12 / (vh - 52)`. -/
def mKnot (v : Vp) : Rat := 12 / (v.h - 52)

theorem wd_eq (v : Vp) (m : Rat) : wd v m = pillW v + (wp v - pillW v) * m := by
  unfold wd wp navWidth expand; grind

theorem ht_eq (v : Vp) (m : Rat) : ht v m = pillH v + (hp v - pillH v) * m := by
  unfold ht hp navHeight; grind

theorem y0_eq (v : Vp) (m : Rat) : y0 v m = (navTop v 1 - 16) * (m - 1) := by
  unfold y0 navTop; grind

/-- Sizes of the pill and the final box that every proof below needs. -/
theorem sizes (v : Vp) :
    (phone v.w = true → pillW v = v.w - 32 ∧ pillH v = 52 ∧ wp v = v.w - 24 ∧ hp v = v.h - 24 ∧ navTop v 1 = 12) ∧
    (phone v.w = false → pillW v = min 984 (v.w - 48) ∧ pillH v = 64 ∧ wp v = min 1398 (v.w - 40) ∧
      hp v = min 820 (v.h - 40) ∧ navTop v 1 = 20) := by
  unfold pillW pillH wp hp panelW panelH navTop phone
  constructor <;> intro h <;> simp at h <;> simp [h] <;> grind

theorem pill_le (v : Vp) (hv : Valid v) : 288 ≤ pillW v ∧ pillW v ≤ wp v ∧ 52 ≤ pillH v ∧ pillH v ≤ hp v := by
  obtain ⟨hv1, hv2⟩ := hv
  have := sizes v
  by_cases h : phone v.w = true
  · have := this.1 h
    unfold phone at h; simp at h
    grind
  · have h' : phone v.w = false := by simpa using h
    have := this.2 h'
    unfold phone at h'; simp at h'
    grind

theorem rad_facts (v : Vp) (hv : Valid v) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    20 ≤ rad v m ∧ rad v m ≤ 32 ∧ rad v m ≤ ht v m / 2 ∧ rad v m ≤ wd v m / 2 ∧
      pillW v ≤ wd v m ∧ wd v m ≤ wp v ∧ pillH v ≤ ht v m ∧ ht v m ≤ hp v := by
  have hp' := pill_le v hv
  rw [wd_eq, ht_eq] at *
  unfold rad navRadius
  rw [wd_eq, ht_eq]
  have a1 : 0 ≤ (wp v - pillW v) * m := Rat.mul_nonneg (by grind) h0
  have a2 : 0 ≤ (hp v - pillH v) * m := Rat.mul_nonneg (by grind) h0
  have a3 : (wp v - pillW v) * m ≤ (wp v - pillW v) * 1 := Rat.mul_le_mul_of_nonneg_left h1 (by grind)
  have a4 : (hp v - pillH v) * m ≤ (hp v - pillH v) * 1 := Rat.mul_le_mul_of_nonneg_left h1 (by grind)
  grind

/-! ## Knot grids -/

/-- `P, P+h, ..., P+k h`. -/
def gridFrom (P h : Rat) : Nat → List Rat
  | 0 => [P]
  | k + 1 => P :: gridFrom (P + h) h k

/-- `P, P+h, ..., P+(k-1) h`. -/
def gridInit (P h : Rat) : Nat → List Rat
  | 0 => []
  | k + 1 => P :: gridInit (P + h) h k

theorem gridFrom_eq (h : Rat) : ∀ (k : Nat) (P : Rat), gridFrom P h k = gridInit P h k ++ [P + (k : Rat) * h] := by
  intro k
  induction k with
  | zero => intro P; simp [gridFrom, gridInit]; grind
  | succ k ih =>
    intro P
    simp only [gridFrom, gridInit, ih, List.cons_append]
    have : P + h + (k : Rat) * h = P + ((k + 1 : Nat) : Rat) * h := by
      push_cast; grind
    rw [this]

theorem lastOf_gridFrom (h : Rat) : ∀ (k : Nat) (P : Rat), lastOf P (List.tail (gridFrom P h k)) = P + (k : Rat) * h := by
  intro k
  induction k with
  | zero => intro P; simp [gridFrom, lastOf]; grind
  | succ k ih =>
    intro P
    cases k with
    | zero => simp [gridFrom, lastOf]
    | succ k' =>
      have := ih (P + h)
      simp only [gridFrom] at this ⊢
      simp only [List.tail_cons] at this ⊢
      simp only [lastOf] at this ⊢
      push_cast at this ⊢
      grind

theorem chordOk_append (f : Rat → Rat) (B : Rat) :
    ∀ (xs : List Rat) (p : Rat) (ys : List Rat), ChordOk f B (xs ++ [p]) → ChordOk f B (p :: ys) →
      ChordOk f B (xs ++ p :: ys) := by
  intro xs
  induction xs with
  | nil => intro p ys _ h; simpa using h
  | cons a xs' ih =>
    intro p ys h1 h2
    cases xs' with
    | nil =>
      obtain ⟨hap, hseg, _⟩ := h1
      exact ⟨hap, hseg, h2⟩
    | cons b xs'' =>
      obtain ⟨hab, hseg, hrest⟩ := h1
      exact ⟨hab, hseg, ih p ys hrest h2⟩

theorem chordOk_mono (f : Rat → Rat) (B1 B2 : Rat) (hB : B1 ≤ B2) :
    ∀ ps : List Rat, ChordOk f B1 ps → ChordOk f B2 ps := by
  intro ps
  induction ps with
  | nil => intros; trivial
  | cons p tl ih =>
    cases tl with
    | nil => intros; trivial
    | cons q rest =>
      intro ⟨hpq, hseg, hr⟩
      refine ⟨hpq, ?_, ih hr⟩
      intro m h1 h2
      have := hseg m h1 h2
      unfold Within at *
      grind

theorem chordOk_grid_rat (F : Rat → Rat) (κ α β ρ0 ρ1 L U rmin Kb h : Rat)
    (hF : ∀ x, L ≤ x → x ≤ U → F x = ratFn κ α β ρ0 ρ1 x) (hr : 0 < rmin)
    (hrmin : ∀ x, L ≤ x → x ≤ U → rmin ≤ ρ0 + ρ1 * x)
    (hK : Within ((α * ρ1 - β * ρ0) * ρ1) Kb) (hh : 0 < h) :
    ∀ (k : Nat) (P : Rat), L ≤ P → P + (k : Rat) * h ≤ U →
      ChordOk F (h ^ 2 / 4 * Kb / rmin ^ 3) (gridFrom P h k) := by
  have seg : ∀ P, L ≤ P → P + h ≤ U → ∀ m, P ≤ m → m ≤ P + h →
      Within (chord F P (P + h) m - F m) (h ^ 2 / 4 * Kb / rmin ^ 3) := by
    intro P hP hPh m h1 h2
    have e1 := hF P hP (by grind)
    have e2 := hF (P + h) (by grind) hPh
    have e3 := hF m (by grind) (by grind)
    have : chord F P (P + h) m - F m = chord (ratFn κ α β ρ0 ρ1) P (P + h) m - ratFn κ α β ρ0 ρ1 m := by
      unfold chord; rw [e1, e2, e3]
    rw [this]
    have := chord_rat_within κ α β ρ0 ρ1 P (P + h) m rmin Kb hr (hrmin P hP (by grind))
      (hrmin (P + h) (by grind) hPh) (hrmin m (by grind) (by grind)) hK (by grind) h1 h2
    have hh' : P + h - P = h := by grind
    rw [hh'] at this
    exact this
  intro k
  induction k with
  | zero => intros; simp [gridFrom, ChordOk]
  | succ k ih =>
    intro P hP hU
    have hU' : P + h ≤ U := by
      have : (0 : Rat) ≤ (k : Rat) * h := Rat.mul_nonneg (by exact_mod_cast Nat.zero_le k) (by grind)
      push_cast at hU; grind
    have ih' := ih (P + h) (by grind) (by push_cast at hU; grind)
    cases k with
    | zero => exact ⟨by grind, seg P hP hU', by simp [ChordOk]⟩
    | succ k' => exact ⟨by grind, seg P hP hU', ih'⟩

/-! ## Clip doors -/

/-- A rounded rectangle by its edges and corner radius. -/
structure RR where
  l : Rat
  t : Rat
  rt : Rat
  b : Rat
  r : Rat

def cTL (x y r p q : Rat) : Prop := p < x + r ∧ q < y + r ∧ r * r < (p - (x + r)) ^ 2 + (q - (y + r)) ^ 2
def cTR (x y r p q : Rat) : Prop := x - r < p ∧ q < y + r ∧ r * r < (p - (x - r)) ^ 2 + (q - (y + r)) ^ 2
def cBL (x y r p q : Rat) : Prop := p < x + r ∧ y - r < q ∧ r * r < (p - (x + r)) ^ 2 + (q - (y - r)) ^ 2
def cBR (x y r p q : Rat) : Prop := x - r < p ∧ y - r < q ∧ r * r < (p - (x - r)) ^ 2 + (q - (y - r)) ^ 2

/-- Membership in a rounded rectangle: inside the box and outside the four corner cut-outs. -/
def inRR (k : RR) (p q : Rat) : Prop :=
  k.l ≤ p ∧ p ≤ k.rt ∧ k.t ≤ q ∧ q ≤ k.b ∧
  ¬ cTL k.l k.t k.r p q ∧ ¬ cTR k.rt k.t k.r p q ∧ ¬ cBL k.l k.b k.r p q ∧ ¬ cBR k.rt k.b k.r p q

theorem vTL (x y r p q : Rat) (h : x + r ≤ p ∨ y + r ≤ q) : ¬ cTL x y r p q := by unfold cTL; grind
theorem vTR (x y r p q : Rat) (h : p ≤ x - r ∨ y + r ≤ q) : ¬ cTR x y r p q := by unfold cTR; grind
theorem vBL (x y r p q : Rat) (h : x + r ≤ p ∨ q ≤ y - r) : ¬ cBL x y r p q := by unfold cBL; grind
theorem vBR (x y r p q : Rat) (h : p ≤ x - r ∨ q ≤ y - r) : ¬ cBR x y r p q := by unfold cBR; grind

/-- The four clippers, each cutting one corner of the pill: top-left, top-right, bottom-left, bottom-right. -/
def door (x0 y0 W H r E F : Rat) (i : Nat) : RR :=
  match i with
  | 0 => ⟨x0, y0, x0 + E, y0 + F, r⟩
  | 1 => ⟨x0 + W - E, y0, x0 + W, y0 + F, r⟩
  | 2 => ⟨x0, y0 + H - F, x0 + E, y0 + H, r⟩
  | _ => ⟨x0 + W - E, y0 + H - F, x0 + W, y0 + H, r⟩

theorem clip_eq (x0 y0 W H r E F p q : Rat) (hr : 0 ≤ r) (hW : W + r ≤ E) (hH : H + r ≤ F) :
    (inRR (door x0 y0 W H r E F 0) p q ∧ inRR (door x0 y0 W H r E F 1) p q ∧
      inRR (door x0 y0 W H r E F 2) p q ∧ inRR (door x0 y0 W H r E F 3) p q) ↔
      inRR ⟨x0, y0, x0 + W, y0 + H, r⟩ p q := by
  simp only [door, inRR]
  constructor
  · intro h
    obtain ⟨⟨a1, a2, a3, a4, a5, a6, a7, a8⟩, ⟨b1, b2, b3, b4, b5, b6, b7, b8⟩,
      ⟨c1, c2, c3, c4, c5, c6, c7, c8⟩, ⟨d1, d2, d3, d4, d5, d6, d7, d8⟩⟩ := h
    refine ⟨?_, ?_, ?_, ?_, a5, b6, c7, d8⟩ <;> grind
  · rintro ⟨h1, h2, h3, h4, h5, h6, h7, h8⟩
    refine ⟨⟨?_, ?_, ?_, ?_, h5, vTR _ _ _ _ _ ?_, vBL _ _ _ _ _ ?_, vBR _ _ _ _ _ ?_⟩,
      ⟨?_, ?_, ?_, ?_, vTL _ _ _ _ _ ?_, h6, vBL _ _ _ _ _ ?_, vBR _ _ _ _ _ ?_⟩,
      ⟨?_, ?_, ?_, ?_, vTL _ _ _ _ _ ?_, vTR _ _ _ _ _ ?_, h7, vBR _ _ _ _ _ ?_⟩,
      ⟨?_, ?_, ?_, ?_, vTL _ _ _ _ _ ?_, vTR _ _ _ _ _ ?_, vBL _ _ _ _ _ ?_, h8⟩⟩ <;> grind

/-- The pill as a rounded rectangle in the final box. -/
def boxAt (v : Vp) (m : Rat) : RR := ⟨x0 v m, y0 v m, x0 v m + wd v m, y0 v m + ht v m, rad v m⟩

/-- Door width in the final box (2 Wp scaled by the first clipper). -/
def ex (v : Vp) (m : Rat) : Rat := 2 * wp v * kk v m

/-- Door height in the final box. -/
def ey (v : Vp) (m : Rat) : Rat := 2 * hp v * kk v m

theorem cover (v : Vp) (hv : Valid v) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    wd v m + rad v m ≤ ex v m ∧ ht v m + rad v m ≤ ey v m := by
  have f := rad_facts v hv m h0 h1
  have p := pill_le v hv
  unfold ex ey kk
  have a1 : 0 ≤ (rad v m - 20) * wp v := Rat.mul_nonneg (by grind) (by grind)
  have a2 : 0 ≤ (rad v m - 20) * hp v := Rat.mul_nonneg (by grind) (by grind)
  constructor <;> grind

theorem clip_pill (v : Vp) (hv : Valid v) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) (p q : Rat) :
    (inRR (door (x0 v m) (y0 v m) (wd v m) (ht v m) (rad v m) (ex v m) (ey v m) 0) p q ∧
      inRR (door (x0 v m) (y0 v m) (wd v m) (ht v m) (rad v m) (ex v m) (ey v m) 1) p q ∧
      inRR (door (x0 v m) (y0 v m) (wd v m) (ht v m) (rad v m) (ex v m) (ey v m) 2) p q ∧
      inRR (door (x0 v m) (y0 v m) (wd v m) (ht v m) (rad v m) (ex v m) (ey v m) 3) p q) ↔
      inRR (boxAt v m) p q :=
  clip_eq _ _ _ _ _ _ _ p q (by have := (rad_facts v hv m h0 h1).1; grind) (cover v hv m h0 h1).1 (cover v hv m h0 h1).2

/-- Translation of the top-right and bottom-right doors in the first clipper's frame (x). -/
def tauX (v : Vp) (m : Rat) : Rat := 20 * wd v m / rad v m - 2 * wp v

/-- Translation of the bottom-left door in the first clipper's frame (y). -/
def tauY (v : Vp) (m : Rat) : Rat := 20 * ht v m / rad v m - 2 * hp v

theorem rad_ne (v : Vp) (hv : Valid v) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) : rad v m ≠ 0 := by
  have := (rad_facts v hv m h0 h1).1
  grind

/-- Door origins from the translate chain equal the origins of `door`. -/
theorem chain_eq (v : Vp) (hv : Valid v) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    x0 v m + kk v m * tauX v m = x0 v m + wd v m - ex v m ∧
    (x0 v m + kk v m * tauX v m) + kk v m * (-tauX v m) = x0 v m ∧
    y0 v m + kk v m * tauY v m = y0 v m + ht v m - ey v m := by
  have := rad_ne v hv m h0 h1
  unfold ex ey kk tauX tauY
  refine ⟨?_, ?_, ?_⟩ <;> grind

/-- The counter layer's scale. -/
def sU (v : Vp) (m : Rat) : Rat := 20 / rad v m

/-- The counter layer's translation (x). -/
def tUx (v : Vp) (m : Rat) : Rat := 2 * wp v - 20 * (x0 v m + wd v m) / rad v m

/-- The counter layer's translation (y). -/
def tUy (v : Vp) (m : Rat) : Rat := 2 * hp v - 20 * (y0 v m + ht v m) / rad v m

theorem sU_exact (v : Vp) (hv : Valid v) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) : kk v m * sU v m = 1 := by
  have := rad_ne v hv m h0 h1
  unfold kk sU; grind

theorem tUx_exact (v : Vp) (hv : Valid v) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    x0 v m + kk v m * (tUx v m + tauX v m) = 0 := by
  have := rad_ne v hv m h0 h1
  unfold kk tUx tauX; grind

theorem tUy_exact (v : Vp) (hv : Valid v) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    y0 v m + kk v m * (tUy v m + tauY v m) = 0 := by
  have := rad_ne v hv m h0 h1
  unfold kk tUy tauY; grind

/-! ## Error algebra -/

theorem within_mul (a b A B : Rat) (ha : Within a A) (hb : Within b B) :
    Within (a * b) (A * B) := by
  unfold Within at *
  have p1 : 0 ≤ (A - a) * (B - b) := Rat.mul_nonneg (by grind) (by grind)
  have p2 : 0 ≤ (A + a) * (B + b) := Rat.mul_nonneg (by grind) (by grind)
  have p3 : 0 ≤ (A - a) * (B + b) := Rat.mul_nonneg (by grind) (by grind)
  have p4 : 0 ≤ (A + a) * (B - b) := Rat.mul_nonneg (by grind) (by grind)
  constructor <;> grind

theorem within_mono (e B1 B2 : Rat) (h : Within e B1) (hB : B1 ≤ B2) : Within e B2 := by
  unfold Within at *; grind

/-- One axis of the counter layer: the content offset error is `k es u + k et + k eT`. -/
theorem net_axis (o k s t T u es et eT Bs Bt BT R kmax : Rat) (hks : k * s = 1) (hot : o + k * (t + T) = 0)
    (hk0 : 0 ≤ k) (hk : k ≤ kmax)
    (hes : Within es Bs) (het : Within et Bt) (heT : Within eT BT) (hu : Within u R) :
    Within (o + k * ((s + es) * u + (t + et) + (T + eT)) - u) (kmax * (Bs * R) + kmax * (Bt + BT)) := by
  have e : o + k * ((s + es) * u + (t + et) + (T + eT)) - u = k * (es * u) + k * (et + eT) := by
    have : k * s * u = u := by rw [hks]; grind
    grind
  rw [e]
  have h1 := within_mul es u Bs R hes hu
  have h2 : Within (et + eT) (Bt + BT) := by unfold Within at *; grind
  have hk' : Within k kmax := by unfold Within; grind
  have h3 := within_mul k (es * u) kmax (Bs * R) hk' h1
  have h4 := within_mul k (et + eT) kmax (Bt + BT) hk' h2
  unfold Within at *; grind

/-! ## Rational tracks on the radius segments -/

/-- Chord error bound of `ratFn κ α β ρ0 ρ1` on a segment with knot step `h` and `r ≥ rmin`. -/
def segB (h ρ0 ρ1 rmin α β : Rat) : Rat :=
  h ^ 2 / 4 * max ((α * ρ1 - β * ρ0) * ρ1) (-((α * ρ1 - β * ρ0) * ρ1)) / rmin ^ 3

theorem within_abs (K : Rat) : Within K (max K (-K)) := by unfold Within; grind

/-- Main knot count, and the factor by which the short phone segment below the radius knot is refined. -/
def nMain : Nat := 320
def nFirst : Nat := 16

/-- Knot count of the phone segment `[0, mKnot]`. -/
def n1 (v : Vp) : Nat := (mKnot v * nMain * nFirst).floor.toNat + 1

/-- Knot step of the phone segment below the radius knot. -/
def stepA (v : Vp) : Rat := mKnot v / (n1 v : Rat)

/-- Knot step of the phone segment above the radius knot. -/
def stepB (v : Vp) : Rat := (1 - mKnot v) / (nMain : Rat)

/-- Knots of every rational track: one uniform grid on desktop, two grids meeting at the radius knot on phone. -/
def knots (v : Vp) : List Rat :=
  if phone v.w then gridInit 0 (stepA v) (n1 v) ++ gridFrom (mKnot v) (stepB v) nMain
  else gridFrom 0 (1 / nMain) nMain

/-- Error bound of a rational track `κ + (α + β m) / r(m)` over the knot table. -/
def bndRat (v : Vp) (α β : Rat) : Rat :=
  if phone v.w then
    max (segB (stepA v) (pillH v / 2) ((hp v - pillH v) / 2) 26 α β) (segB (stepB v) 32 (-12) 20 α β)
  else segB (1 / nMain) 32 (-12) 20 α β

theorem gridFrom_cons (P h : Rat) (k : Nat) : gridFrom P h k = P :: List.tail (gridFrom P h k) := by
  cases k <;> simp [gridFrom]

theorem gridInit_cons (P h : Rat) (k : Nat) : gridInit P h (k + 1) = P :: gridInit (P + h) h k := by
  simp [gridInit]

def lastL : List Rat → Rat
  | [] => 0
  | [x] => x
  | _ :: y :: r => lastL (y :: r)

theorem lastOf_eq (ps : List Rat) : ∀ p, lastOf p ps = lastL (p :: ps) := by
  induction ps with
  | nil => intro p; simp [lastOf, lastL]
  | cons q rest ih => intro p; simp only [lastOf, ih]; cases rest <;> simp [lastL]

theorem lastL_append (y : Rat) (ys : List Rat) : ∀ xs : List Rat, lastL (xs ++ y :: ys) = lastL (y :: ys) := by
  intro xs
  induction xs with
  | nil => simp
  | cons a xs ih =>
    cases xs with
    | nil => simp [lastL]
    | cons b xs' => simp only [List.cons_append] at ih ⊢; simp [lastL, ih]

theorem lastL_gridFrom (P h : Rat) (k : Nat) : lastL (gridFrom P h k) = P + (k : Rat) * h := by
  have := lastOf_gridFrom h k P
  rw [lastOf_eq, ← gridFrom_cons] at this
  exact this

theorem div_nonneg' (a b : Rat) (ha : 0 ≤ a) (hb : 0 < b) : 0 ≤ a / b := by
  refine Classical.byContradiction fun h => ?_
  have h' : a / b < 0 := by grind
  have := Rat.mul_lt_mul_of_pos_right h' hb
  have h2 : a / b * b = a := by
    have : b ≠ 0 := by grind
    grind
  grind

theorem segB_nonneg (h ρ0 ρ1 rmin α β : Rat) (hr : 0 < rmin) : 0 ≤ segB h ρ0 ρ1 rmin α β := by
  unfold segB
  have h1 : 0 ≤ h ^ 2 / 4 := by
    have := sqNonneg h
    grind
  have h2 : 0 ≤ max ((α * ρ1 - β * ρ0) * ρ1) (-((α * ρ1 - β * ρ0) * ρ1)) := by grind
  have h3 : 0 < rmin ^ 3 := by
    have := Rat.mul_pos (Rat.mul_pos hr hr) hr
    grind
  exact div_nonneg' _ _ (Rat.mul_nonneg h1 h2) h3

/-! ## The radius on the two phone segments -/

theorem mKnot_mul (v : Vp) (hv : Valid v) : mKnot v * (v.h - 52) = 12 := by
  have : v.h - 52 ≠ 0 := by unfold Valid at hv; grind
  unfold mKnot; grind

theorem mKnot_pos (v : Vp) (hv : Valid v) : 0 < mKnot v ∧ mKnot v < 1 := by
  have h := mKnot_mul v hv
  unfold Valid at hv
  have hpos : 0 < v.h - 52 := by grind
  constructor
  · refine Classical.byContradiction fun hc => ?_
    have := Rat.mul_nonneg (show 0 ≤ -mKnot v by grind) (show 0 ≤ v.h - 52 by grind)
    grind
  · refine Classical.byContradiction fun hc => ?_
    have := Rat.mul_le_mul_of_nonneg_right (show 1 ≤ mKnot v by grind) (show 0 ≤ v.h - 52 by grind)
    grind

theorem rad_desktop (v : Vp) (hv : Valid v) (hph : phone v.w = false) (x : Rat) (h0 : 0 ≤ x) (h1 : x ≤ 1) :
    rad v x = 32 + (-12) * x := by
  have f := rad_facts v hv x h0 h1
  have s := (sizes v).2 hph
  unfold rad navRadius
  rw [ht_eq, wd_eq]
  have := pill_le v hv
  have a1 : 0 ≤ (hp v - pillH v) * x := Rat.mul_nonneg (by grind) h0
  have a2 : 0 ≤ (wp v - pillW v) * x := Rat.mul_nonneg (by grind) h0
  grind

theorem rad_phone1 (v : Vp) (hv : Valid v) (hph : phone v.w = true) (x : Rat) (h0 : 0 ≤ x) (h1 : x ≤ mKnot v) :
    rad v x = pillH v / 2 + (hp v - pillH v) / 2 * x := by
  have k := mKnot_pos v hv
  have km := mKnot_mul v hv
  have s := (sizes v).1 hph
  have f := rad_facts v hv x h0 (by grind)
  have a1 : x * (v.h - 52) ≤ mKnot v * (v.h - 52) := Rat.mul_le_mul_of_nonneg_right h1 (by unfold Valid at hv; grind)
  have a2 : 0 ≤ (wp v - pillW v) * x := Rat.mul_nonneg (by have := pill_le v hv; grind) h0
  have b : (hp v - pillH v) * x = x * (v.h - 52) - 24 * x := by rw [s.2.1, s.2.2.2.1]; grind
  have pl := pill_le v hv
  have c1 : (pillH v + (hp v - pillH v) * x) / 2 ≤ 32 - 12 * x := by grind
  have c2 : (pillH v + (hp v - pillH v) * x) / 2 ≤ (pillW v + (wp v - pillW v) * x) / 2 := by grind
  unfold rad navRadius
  rw [ht_eq, wd_eq]
  grind

theorem rad_phone2 (v : Vp) (hv : Valid v) (hph : phone v.w = true) (x : Rat) (h0 : mKnot v ≤ x) :
    rad v x = 32 + (-12) * x := by
  have k := mKnot_pos v hv
  have km := mKnot_mul v hv
  have s := (sizes v).1 hph
  have a1 : mKnot v * (v.h - 52) ≤ x * (v.h - 52) := Rat.mul_le_mul_of_nonneg_right h0 (by unfold Valid at hv; grind)
  have a2 : 0 ≤ (wp v - pillW v) * x := Rat.mul_nonneg (by have := pill_le v hv; grind) (by grind)
  have b : (hp v - pillH v) * x = x * (v.h - 52) - 24 * x := by rw [s.2.1, s.2.2.2.1]; grind
  have pl := pill_le v hv
  have c1 : 32 - 12 * x ≤ (pillH v + (hp v - pillH v) * x) / 2 := by grind
  have c2 : 32 - 12 * x ≤ (pillW v + (wp v - pillW v) * x) / 2 := by grind
  unfold rad navRadius
  rw [ht_eq, wd_eq]
  grind


theorem stepA_facts (v : Vp) (hv : Valid v) : (n1 v : Rat) * stepA v = mKnot v ∧ 0 < stepA v := by
  have kp := mKnot_pos v hv
  have hp1 : 0 < n1 v := by unfold n1; grind
  have hn1 : (0 : Rat) < (n1 v : Rat) := by exact_mod_cast hp1
  have e : (n1 v : Rat) * stepA v = mKnot v := by unfold stepA; grind
  refine ⟨e, ?_⟩
  refine Classical.byContradiction fun hc => ?_
  have : stepA v = 0 := by
    have := div_nonneg' (mKnot v) (n1 v : Rat) (by grind) hn1
    unfold stepA at *; grind
  rw [this] at e; grind

theorem stepB_facts (v : Vp) (hv : Valid v) : (nMain : Rat) * stepB v = 1 - mKnot v ∧ 0 < stepB v := by
  have kp := mKnot_pos v hv
  have hn2 : (0 : Rat) < (nMain : Rat) := by unfold nMain; grind
  have e : (nMain : Rat) * stepB v = 1 - mKnot v := by unfold stepB; grind
  refine ⟨e, ?_⟩
  refine Classical.byContradiction fun hc => ?_
  have : stepB v = 0 := by
    have := div_nonneg' (1 - mKnot v) (nMain : Rat) (by grind) hn2
    unfold stepB at *; grind
  rw [this] at e; grind

theorem le_max_l (a b : Rat) : a ≤ max a b := by grind

theorem le_max_r (a b : Rat) : b ≤ max a b := by grind

theorem eval_knots (F : Rat → Rat) (B : Rat) (hB : 0 ≤ B) (ks : List Rat) (p : Rat) (ps : List Rat)
    (hks : ks = p :: ps) (hok : ChordOk F B ks) (m : Rat) (h1 : p ≤ m) (h2 : m ≤ lastL ks) :
    Within (Track.eval (mk F ks) m - F m) B := by
  subst hks
  exact eval_mk_within F B hB ps p m hok h1 (by rw [lastOf_eq]; exact h2)

/-- A rational track `κ + (α + β m) / r(m)` evaluated on the knot table stays within `bndRat` of the exact value. -/
theorem ratTrack_within (v : Vp) (hv : Valid v) (F : Rat → Rat) (κ α β : Rat)
    (hF : ∀ x, 0 ≤ x → x ≤ 1 → F x = κ + (α + β * x) / rad v x) :
    ∀ m, 0 ≤ m → m ≤ 1 → Within (Track.eval (mk F (knots v)) m - F m) (bndRat v α β) := by
  intro m hm0 hm1
  by_cases hph : phone v.w = true
  · have kp := mKnot_pos v hv
    have s := (sizes v).1 hph
    have pl := pill_le v hv
    have ⟨e1, hh1p⟩ := stepA_facts v hv
    have ⟨e2, hh2p⟩ := stepB_facts v hv
    have hp1 : 0 < n1 v := by unfold n1; grind
    have seg1 : ChordOk F (segB (stepA v) (pillH v / 2) ((hp v - pillH v) / 2) 26 α β)
        (gridFrom 0 (stepA v) (n1 v)) := by
      refine chordOk_grid_rat F κ α β (pillH v / 2) ((hp v - pillH v) / 2) 0 (mKnot v) 26 _ (stepA v) ?_
        (by grind) ?_ (within_abs _) hh1p (n1 v) 0 (by grind) (by grind)
      · intro x hx0 hx1
        rw [hF x hx0 (by grind), rad_phone1 v hv hph x hx0 hx1]
        unfold ratFn; rfl
      · intro x hx0 hx1
        have : 0 ≤ (hp v - pillH v) * x := Rat.mul_nonneg (by grind) hx0
        grind
    have seg2 : ChordOk F (segB (stepB v) 32 (-12) 20 α β) (gridFrom (mKnot v) (stepB v) nMain) := by
      refine chordOk_grid_rat F κ α β 32 (-12) (mKnot v) 1 20 _ (stepB v) ?_ (by grind) ?_ (within_abs _)
        hh2p nMain (mKnot v) (by grind) (by grind)
      · intro x hx0 hx1
        rw [hF x (by grind) hx1, rad_phone2 v hv hph x hx0]
        unfold ratFn; rfl
      · intro x hx0 hx1; grind
    have hB0 : 0 ≤ bndRat v α β := by
      unfold bndRat; simp only [hph, ↓reduceIte]
      exact Rat.le_trans (segB_nonneg _ _ _ _ _ _ (by grind)) (le_max_l _ _)
    have c1 := chordOk_mono F _ (bndRat v α β)
      (by unfold bndRat; simp only [hph, ↓reduceIte]; exact le_max_l _ _) _ seg1
    have c2 := chordOk_mono F _ (bndRat v α β)
      (by unfold bndRat; simp only [hph, ↓reduceIte]; exact le_max_r _ _) _ seg2
    have g1 : gridFrom 0 (stepA v) (n1 v) = gridInit 0 (stepA v) (n1 v) ++ [mKnot v] := by
      rw [gridFrom_eq]; rw [show (0 : Rat) + (n1 v : Rat) * stepA v = mKnot v by grind]
    rw [g1] at c1
    have g2 := gridFrom_cons (mKnot v) (stepB v) nMain
    rw [g2] at c2
    have call := chordOk_append F _ (gridInit 0 (stepA v) (n1 v)) (mKnot v) _ c1 c2
    rw [← g2] at call
    have hk : knots v = gridInit 0 (stepA v) (n1 v) ++ gridFrom (mKnot v) (stepB v) nMain := by
      unfold knots; simp only [hph, ↓reduceIte]
    obtain ⟨k', hk'⟩ : ∃ k', n1 v = k' + 1 := ⟨n1 v - 1, by grind⟩
    have hcons : knots v = 0 :: (gridInit (0 + stepA v) (stepA v) k' ++ gridFrom (mKnot v) (stepB v) nMain) := by
      rw [hk, hk', gridInit_cons]; rfl
    refine eval_knots F _ hB0 (knots v) 0 _ hcons (by rw [hk]; exact call) m hm0 ?_
    rw [hk, g2, lastL_append, ← g2, lastL_gridFrom]
    grind
  · have hph' : phone v.w = false := by simpa using hph
    have hn : (0 : Rat) < (nMain : Rat) := by unfold nMain; grind
    have hh : 0 < 1 / (nMain : Rat) := by
      have := div_nonneg' 1 (nMain : Rat) (by grind) hn
      refine Classical.byContradiction fun hc => ?_
      have : 1 / (nMain : Rat) = 0 := by grind
      have e : (nMain : Rat) * (1 / (nMain : Rat)) = 1 := by grind
      rw [this] at e; grind
    have e : (nMain : Rat) * (1 / (nMain : Rat)) = 1 := by grind
    have sg : ChordOk F (segB (1 / nMain) 32 (-12) 20 α β) (gridFrom 0 (1 / nMain) nMain) := by
      refine chordOk_grid_rat F κ α β 32 (-12) 0 1 20 _ (1 / nMain) ?_ (by grind) ?_ (within_abs _) hh nMain 0
        (by grind) (by grind)
      · intro x hx0 hx1
        rw [hF x hx0 hx1, rad_desktop v hv hph' x hx0 hx1]
        unfold ratFn; rfl
      · intro x hx0 hx1; grind
    have hB0 : 0 ≤ bndRat v α β := by
      unfold bndRat; simp only [hph', Bool.false_eq_true, ↓reduceIte]
      exact segB_nonneg _ _ _ _ _ _ (by grind)
    have hk : knots v = gridFrom 0 (1 / nMain) nMain := by
      unfold knots; simp only [hph', Bool.false_eq_true, ↓reduceIte]
    have hb : bndRat v α β = segB (1 / nMain) 32 (-12) 20 α β := by
      unfold bndRat; simp only [hph', Bool.false_eq_true, ↓reduceIte]
    rw [hb] at hB0 ⊢
    have g := gridFrom_cons 0 (1 / (nMain : Rat)) nMain
    refine eval_knots F _ hB0 (knots v) 0 _ (by rw [hk]; exact g) (by rw [hk]; exact sg) m hm0 ?_
    rw [hk, lastL_gridFrom]
    grind

/-! ## The five rational tracks and the net error of the counter layer -/

theorem sU_within (v : Vp) (hv : Valid v) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    Within (Track.eval (mk (sU v) (knots v)) m - sU v m) (bndRat v 20 0) :=
  ratTrack_within v hv (sU v) 0 20 0 (fun x _ _ => by unfold sU; grind) m h0 h1

theorem tauX_within (v : Vp) (hv : Valid v) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    Within (Track.eval (mk (tauX v) (knots v)) m - tauX v m) (bndRat v (20 * pillW v) (20 * (wp v - pillW v))) :=
  ratTrack_within v hv (tauX v) (-2 * wp v) (20 * pillW v) (20 * (wp v - pillW v))
    (fun x _ _ => by unfold tauX; rw [wd_eq]; grind) m h0 h1

theorem tauY_within (v : Vp) (hv : Valid v) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    Within (Track.eval (mk (tauY v) (knots v)) m - tauY v m) (bndRat v (20 * pillH v) (20 * (hp v - pillH v))) :=
  ratTrack_within v hv (tauY v) (-2 * hp v) (20 * pillH v) (20 * (hp v - pillH v))
    (fun x _ _ => by unfold tauY; rw [ht_eq]; grind) m h0 h1

theorem tUx_within (v : Vp) (hv : Valid v) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    Within (Track.eval (mk (tUx v) (knots v)) m - tUx v m)
      (bndRat v (-10 * (wp v + pillW v)) (-10 * (wp v - pillW v))) :=
  ratTrack_within v hv (tUx v) (2 * wp v) (-10 * (wp v + pillW v)) (-10 * (wp v - pillW v))
    (fun x _ _ => by unfold tUx x0; rw [wd_eq]; grind) m h0 h1

theorem tUy_within (v : Vp) (hv : Valid v) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    Within (Track.eval (mk (tUy v) (knots v)) m - tUy v m)
      (bndRat v (-20 * (16 - navTop v 1 + pillH v)) (-20 * (navTop v 1 - 16 + (hp v - pillH v)))) :=
  ratTrack_within v hv (tUy v) (2 * hp v) (-20 * (16 - navTop v 1 + pillH v))
    (-20 * (navTop v 1 - 16 + (hp v - pillH v)))
    (fun x _ _ => by unfold tUy; rw [y0_eq, ht_eq]; grind) m h0 h1

theorem eval_mk_neg (f : Rat → Rat) : ∀ (ks : List Rat) (m : Rat),
    Track.eval (mk (fun x => -f x) ks) m = -Track.eval (mk f ks) m := by
  intro ks
  induction ks with
  | nil => intro m; simp [mk, Track.eval]
  | cons p tl ih =>
    cases tl with
    | nil => intro m; simp [mk, Track.eval]
    | cons q rest =>
      intro m
      rw [eval_mk_cons, eval_mk_cons]
      by_cases h : m ≤ q
      · simp only [h, ↓reduceIte, chord]
        have : q - p = q - p := rfl
        grind
      · simp only [h, ↓reduceIte]
        exact ih m

/-- The worst content offset of the counter layer, x axis, in css px. -/
def netBoundX (v : Vp) : Rat :=
  8 / 5 * (bndRat v 20 0 * (wp v + hp v)) +
    8 / 5 * (bndRat v (-10 * (wp v + pillW v)) (-10 * (wp v - pillW v)) +
      bndRat v (20 * pillW v) (20 * (wp v - pillW v)))

/-- The worst content offset of the counter layer, y axis, in css px. -/
def netBoundY (v : Vp) : Rat :=
  8 / 5 * (bndRat v 20 0 * (wp v + hp v)) +
    8 / 5 * (bndRat v (-20 * (16 - navTop v 1 + pillH v)) (-20 * (navTop v 1 - 16 + (hp v - pillH v))) +
      bndRat v (20 * pillH v) (20 * (hp v - pillH v)))

/-- The knot table of `v` keeps the content within 1/64 css px. -/
def netOk (v : Vp) : Bool := decide (netBoundX v ≤ 1 / 64 ∧ netBoundY v ≤ 1 / 64)

/-- Content position of a point `u` of the counter layer along x, through the generated tracks. -/
def navX (v : Vp) (m u : Rat) : Rat :=
  x0 v m + kk v m * (Track.eval (mk (sU v) (knots v)) m * u + Track.eval (mk (tUx v) (knots v)) m +
    (Track.eval (mk (tauX v) (knots v)) m + Track.eval (mk (fun x => -tauX v x) (knots v)) m +
      Track.eval (mk (tauX v) (knots v)) m))

theorem net_err_x (v : Vp) (hv : Valid v) (hok : netOk v = true) (m u : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1)
    (hu : Within u (wp v + hp v)) : Within (navX v m u - u) (1 / 64) := by
  unfold netOk at hok
  have hok' := of_decide_eq_true hok
  have f := rad_facts v hv m h0 h1
  have hk0 : 0 ≤ kk v m := by unfold kk; grind
  have hk : kk v m ≤ 8 / 5 := by unfold kk; grind
  have hneg := eval_mk_neg (tauX v) (knots v) m
  have e := net_axis (x0 v m) (kk v m) (sU v m) (tUx v m) (tauX v m) u
    (Track.eval (mk (sU v) (knots v)) m - sU v m) (Track.eval (mk (tUx v) (knots v)) m - tUx v m)
    (Track.eval (mk (tauX v) (knots v)) m - tauX v m) _ _ _ (wp v + hp v) (8 / 5)
    (sU_exact v hv m h0 h1) (tUx_exact v hv m h0 h1) hk0 hk
    (sU_within v hv m h0 h1) (tUx_within v hv m h0 h1) (tauX_within v hv m h0 h1) hu
  have eq : navX v m u = x0 v m + kk v m * ((sU v m + (Track.eval (mk (sU v) (knots v)) m - sU v m)) * u +
      (tUx v m + (Track.eval (mk (tUx v) (knots v)) m - tUx v m)) +
      (tauX v m + (Track.eval (mk (tauX v) (knots v)) m - tauX v m))) := by
    unfold navX; rw [hneg]; grind
  rw [eq]
  exact within_mono _ _ _ e (by unfold netBoundX at hok'; grind)

/-- Content position of a point `u` of the counter layer along y, through the generated tracks. -/
def navY (v : Vp) (m u : Rat) : Rat :=
  y0 v m + kk v m * (Track.eval (mk (sU v) (knots v)) m * u + Track.eval (mk (tUy v) (knots v)) m +
    (0 + Track.eval (mk (tauY v) (knots v)) m + 0))

theorem net_err_y (v : Vp) (hv : Valid v) (hok : netOk v = true) (m u : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1)
    (hu : Within u (wp v + hp v)) : Within (navY v m u - u) (1 / 64) := by
  unfold netOk at hok
  have hok' := of_decide_eq_true hok
  have f := rad_facts v hv m h0 h1
  have hk0 : 0 ≤ kk v m := by unfold kk; grind
  have hk : kk v m ≤ 8 / 5 := by unfold kk; grind
  have e := net_axis (y0 v m) (kk v m) (sU v m) (tUy v m) (tauY v m) u
    (Track.eval (mk (sU v) (knots v)) m - sU v m) (Track.eval (mk (tUy v) (knots v)) m - tUy v m)
    (Track.eval (mk (tauY v) (knots v)) m - tauY v m) _ _ _ (wp v + hp v) (8 / 5)
    (sU_exact v hv m h0 h1) (tUy_exact v hv m h0 h1) hk0 hk
    (sU_within v hv m h0 h1) (tUy_within v hv m h0 h1) (tauY_within v hv m h0 h1) hu
  have eq : navY v m u = y0 v m + kk v m * ((sU v m + (Track.eval (mk (sU v) (knots v)) m - sU v m)) * u +
      (tUy v m + (Track.eval (mk (tUy v) (knots v)) m - tUy v m)) +
      (tauY v m + (Track.eval (mk (tauY v) (knots v)) m - tauY v m))) := by
    unfold navY; grind
  rw [eq]
  exact within_mono _ _ _ e (by unfold netBoundY at hok'; grind)

/-- Viewports whose knot table is proved: phones, tablets and desktops of the breakpoint gate. -/
def bandVps : List Vp :=
  [⟨320, 568⟩, ⟨360, 640⟩, ⟨390, 844⟩, ⟨430, 932⟩, ⟨640, 360⟩, ⟨640, 1000⟩, ⟨641, 700⟩, ⟨768, 1024⟩, ⟨1024, 768⟩,
    ⟨1280, 800⟩, ⟨1440, 900⟩, ⟨1920, 1080⟩]

theorem net_ok_bands : bandVps.all netOk = true := by decide +kernel

end Fw.Parts.MorphGeom
