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

end Fw.Parts.MorphGeom
