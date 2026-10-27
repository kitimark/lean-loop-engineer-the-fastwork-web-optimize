import Fw.Parts.MorphGeom
/-! `morph.geom:on`: exact rectangles of the flip layers, the nav fill, panel and platform tracks, the logo bound. -/
namespace Fw.Parts.MorphGeom
open Fw.Parts.Nav Fw.Parts.MorphTween

theorem eval01 (f : Rat → Rat) (a b : Rat) (hf : ∀ x, f x = a + b * x) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    Track.eval (mk f [0, 1]) m = f m :=
  exact_of_aff f [1] 0 m ⟨by grind, ⟨a, b, fun x _ _ => hf x⟩, trivial⟩ h0 (by simpa [lastOf] using h1)

def ev (f : Rat → Rat) (m : Rat) : Rat := Track.eval (mk f [0, 1]) m

def Aff (f : Rat → Rat) : Prop := ∃ a b, ∀ x, f x = a + b * x

theorem ev_eq (f : Rat → Rat) (h : Aff f) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) : ev f m = f m := by
  obtain ⟨a, b, hf⟩ := h
  exact eval01 f a b hf m h0 h1

theorem aff_wd (v : Vp) : Aff (wd v) := ⟨pillW v, wp v - pillW v, fun x => wd_eq v x⟩
theorem aff_ht (v : Vp) : Aff (ht v) := ⟨pillH v, hp v - pillH v, fun x => ht_eq v x⟩
theorem aff_x0 (v : Vp) : Aff (x0 v) :=
  ⟨(wp v - pillW v) / 2, -(wp v - pillW v) / 2, fun x => by unfold x0; rw [wd_eq]; grind⟩
theorem aff_y0 (v : Vp) : Aff (y0 v) :=
  ⟨-(navTop v 1 - 16), navTop v 1 - 16, fun x => by rw [y0_eq]; grind⟩
theorem aff_const (c : Rat) : Aff (fun _ => c) := ⟨c, 0, fun _ => by grind⟩
theorem aff_add (f g : Rat → Rat) (hf : Aff f) (hg : Aff g) : Aff (fun x => f x + g x) := by
  obtain ⟨a, b, hf⟩ := hf; obtain ⟨c, d, hg⟩ := hg
  exact ⟨a + c, b + d, fun x => by simp only [hf, hg]; grind⟩
theorem aff_smul (k : Rat) (f : Rat → Rat) (hf : Aff f) : Aff (fun x => k * f x) := by
  obtain ⟨a, b, hf⟩ := hf
  exact ⟨k * a, k * b, fun x => by simp only [hf]; grind⟩
theorem aff_id : Aff (fun x => x) := ⟨0, 1, fun _ => by grind⟩

theorem wp_pos (v : Vp) (hv : Valid v) : 0 < wp v := by have := pill_le v hv; grind
theorem hp_pos (v : Vp) (hv : Valid v) : 0 < hp v := by have := pill_le v hv; grind
theorem wp_split (v : Vp) (m : Rat) : wp v = 2 * x0 v m + wd v m := by unfold x0; grind


def dP (v : Vp) (m : Rat) : Rat := y0 v m + ht v m / 2 - hp v / 2

def pS (m : Rat) : Rat := 24 / 25 + 1 / 25 * m

def nCols (v : Vp) : Rat := if phone v.w then 3 else 5

def colGap (v : Vp) : Rat := if phone v.w then 8 else 12

def cw (v : Vp) (m : Rat) : Rat := (53 / 50 * wd v m - (nCols v - 1) * colGap v) / nCols v

def sImg (v : Vp) (m : Rat) : Rat := cw v m / cw v 1

def colTx (v : Vp) (i : Nat) (m : Rat) : Rat := (i : Rat) * (cw v m - cw v 1)

theorem cw1_pos (v : Vp) (hv : Valid v) : 0 < cw v 1 := by
  obtain ⟨hv1, _⟩ := hv
  have s := sizes v
  unfold cw nCols colGap
  rw [wd_eq]
  by_cases h : phone v.w = true
  · have := s.1 h; simp only [h, ite_true]; grind
  · have h' : phone v.w = false := by simpa using h
    have := s.2 h'
    simp only [h', Bool.false_eq_true, ite_false]
    unfold phone at h'; simp at h'
    have : 600 < wp v := by grind
    grind

theorem aff_cw (v : Vp) : Aff (cw v) := by
  obtain ⟨a, b, h⟩ := aff_wd v
  exact ⟨(53 / 50 * a - (nCols v - 1) * colGap v) / nCols v, 53 / 50 * b / nCols v,
    fun x => by unfold cw; rw [h x]; grind⟩

theorem aff_sImg (v : Vp) : Aff (sImg v) := by
  obtain ⟨a, b, h⟩ := aff_cw v
  exact ⟨a / cw v 1, b / cw v 1, fun x => by unfold sImg; rw [h x]; grind⟩

theorem aff_colTx (v : Vp) (i : Nat) : Aff (colTx v i) := by
  obtain ⟨a, b, h⟩ := aff_cw v
  exact ⟨(i : Rat) * (a - cw v 1), (i : Rat) * b, fun x => by unfold colTx; rw [h x]; grind⟩


inductive Item where
  | bar
  | actions
  | column (i : Nat)
  | veil
  | centre
  | footer (fh : Rat)
  | footerGrad
  | footerEnd (pad : Rat)
  | backdropClip
  | panelCentre

def faithful (v : Vp) (m : Rat) : Item → List Rat
  | .bar => [y0 v m, y0 v m + pillH v]
  | .actions => [x0 v m + wd v m - 8, y0 v m + pillH v / 2]
  | .column i => [(i : Rat) * (cw v m + colGap v), (i : Rat) * (cw v m + colGap v) + cw v m]
  | .veil => [x0 v m, y0 v m, x0 v m + wd v m, y0 v m + ht v m]
  | .centre => [x0 v m + wd v m / 2, y0 v m + ht v m / 2]
  | .footer fh => [x0 v m, y0 v m + ht v m - fh, y0 v m + ht v m]
  | .footerGrad => [x0 v m, x0 v m + wd v m]
  | .footerEnd pad => [x0 v m + wd v m - pad]
  | .backdropClip => [x0 v m - 3 / 100 * wd v m, y0 v m, x0 v m + 103 / 100 * wd v m, y0 v m + ht v m]
  | .panelCentre => [x0 v m + wd v m / 2, y0 v m + ht v m / 2]

def composed (v : Vp) (m : Rat) : Item → List Rat
  | .bar => [0 + ev (y0 v) m, pillH v + ev (y0 v) m]
  | .actions => [wp v - 8 + ev (fun x => -x0 v x) m, pillH v / 2 + ev (y0 v) m]
  | .column i =>
    [(i : Rat) * (cw v 1 + colGap v) + ev (colTx v i) m,
      (i : Rat) * (cw v 1 + colGap v) + ev (colTx v i) m + ev (sImg v) m * cw v 1]
  | .veil =>
    [ev (x0 v) m, ev (y0 v) m, ev (x0 v) m + ev (fun x => wd v x / wp v) m * wp v,
      ev (y0 v) m + ev (fun x => ht v x / hp v) m * hp v]
  | .centre => [wp v / 2, hp v / 2 + ev (dP v) m]
  | .footer fh => [0 + ev (x0 v) m, hp v - fh + ev (fun x => y0 v x + ht v x - hp v) m,
      hp v + ev (fun x => y0 v x + ht v x - hp v) m]
  | .footerGrad => [ev (x0 v) m, ev (x0 v) m + ev (fun x => wd v x / wp v) m * wp v]
  | .footerEnd pad => [wp v - pad + ev (x0 v) m + ev (fun x => -2 * x0 v x) m]
  | .backdropClip =>
    [-3 / 100 * wp v + ev (fun x => 53 / 50 * x0 v x) m, ev (y0 v) m,
      103 / 100 * wp v + ev (fun x => 53 / 50 * x0 v x) m + ev (fun x => -(106 / 50) * x0 v x) m,
      hp v + ev (y0 v) m + ev (fun x => ht v x - hp v) m]
  | .panelCentre => [wp v / 2, hp v / 2 + ev (dP v) m]

theorem aff_div (f : Rat → Rat) (c : Rat) (hf : Aff f) : Aff (fun x => f x / c) := by
  obtain ⟨a, b, h⟩ := hf
  exact ⟨a / c, b / c, fun x => by simp only [h x]; grind⟩

theorem aff_neg (f : Rat → Rat) (hf : Aff f) : Aff (fun x => -f x) := by
  obtain ⟨a, b, h⟩ := hf
  exact ⟨-a, -b, fun x => by simp only [h x]; grind⟩

theorem aff_dP (v : Vp) : Aff (dP v) := by
  obtain ⟨a, b, h⟩ := aff_y0 v; obtain ⟨c, d, k⟩ := aff_ht v
  exact ⟨a + c / 2 - hp v / 2, b + d / 2, fun x => by unfold dP; rw [h x, k x]; grind⟩

theorem aff_foot (v : Vp) : Aff (fun x => y0 v x + ht v x - hp v) := by
  obtain ⟨a, b, h⟩ := aff_y0 v; obtain ⟨c, d, k⟩ := aff_ht v
  exact ⟨a + c - hp v, b + d, fun x => by simp only [h x, k x]; grind⟩

theorem aff_htd (v : Vp) : Aff (fun x => ht v x - hp v) := by
  obtain ⟨c, d, k⟩ := aff_ht v
  exact ⟨c - hp v, d, fun x => by simp only [k x]; grind⟩

theorem rect_eq (v : Vp) (hv : Valid v) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) (e : Item) :
    composed v m e = faithful v m e := by
  have hw := wp_pos v hv
  have hh := hp_pos v hv
  have hc := cw1_pos v hv
  have sp := wp_split v m
  have ex0 := ev_eq _ (aff_x0 v) m h0 h1
  have ey0 := ev_eq _ (aff_y0 v) m h0 h1
  have enx := ev_eq _ (aff_neg _ (aff_x0 v)) m h0 h1
  have ewd := ev_eq _ (aff_div _ (wp v) (aff_wd v)) m h0 h1
  have eht := ev_eq _ (aff_div _ (hp v) (aff_ht v)) m h0 h1
  have edp := ev_eq _ (aff_dP v) m h0 h1
  have eft := ev_eq _ (aff_foot v) m h0 h1
  have e2x := ev_eq _ (aff_smul (-2) _ (aff_x0 v)) m h0 h1
  have ebx := ev_eq _ (aff_smul (53 / 50) _ (aff_x0 v)) m h0 h1
  have ebk := ev_eq _ (aff_smul (-(106 / 50)) _ (aff_x0 v)) m h0 h1
  have ehd := ev_eq _ (aff_htd v) m h0 h1
  have es := ev_eq _ (aff_sImg v) m h0 h1
  cases e with
  | bar => simp only [composed, faithful, ey0]; grind
  | actions => simp only [composed, faithful, ey0, enx]; grind
  | column i =>
    have et := ev_eq _ (aff_colTx v i) m h0 h1
    simp only [composed, faithful, et, es]
    unfold colTx sImg
    have : cw v m / cw v 1 * cw v 1 = cw v m := Rat.div_mul_cancel (by grind)
    grind
  | veil =>
    simp only [composed, faithful, ex0, ey0, ewd, eht]
    have a : wd v m / wp v * wp v = wd v m := Rat.div_mul_cancel (by grind)
    have b : ht v m / hp v * hp v = ht v m := Rat.div_mul_cancel (by grind)
    grind
  | centre => simp only [composed, faithful, edp]; unfold dP; grind
  | footer fh => simp only [composed, faithful, ex0, eft]; grind
  | footerGrad =>
    simp only [composed, faithful, ex0, ewd]
    have a : wd v m / wp v * wp v = wd v m := Rat.div_mul_cancel (by grind)
    grind
  | footerEnd pad => simp only [composed, faithful, ex0, e2x]; grind
  | backdropClip => simp only [composed, faithful, ebx, ebk, ey0, ehd]; grind
  | panelCentre => simp only [composed, faithful, edp]; unfold dP; grind


def mixOver (c1 a1 c2 a2 p bg : Rat) : Rat :=
  (p * a1 * c1 + (1 - p) * a2 * c2) + (1 - (p * a1 + (1 - p) * a2)) * bg

def over (c a bg : Rat) : Rat := a * c + (1 - a) * bg

theorem fill_eq (cG aG cD bg m : Rat) :
    over cD m (over cG aG bg) = mixOver cG aG cD 1 (1 - m) bg := by
  unfold over mixOver; grind

theorem fill_ev (cG aG cD bg m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    over cD (ev (fun x => x) m) (over cG aG bg) = mixOver cG aG cD 1 (1 - m) bg ∧
      ev navBlur m = navBlur m := by
  rw [ev_eq _ aff_id m h0 h1, ev_eq _ ⟨20, -20, fun x => by unfold navBlur; grind⟩ m h0 h1]
  exact ⟨fill_eq cG aG cD bg m, rfl⟩

def panelO (m : Rat) : Rat := clamp01 ((m - 2 / 25) / (18 / 25))

def panelBlur (v : Vp) (m : Rat) : Rat := if v.w ≤ 720 then 0 else 12 * (1 - panelO m)

def panelKnots : List Rat := [0, 2 / 25, 4 / 5, 1]

def fadeKnots : List Rat := [0, 11 / 20, 1]

theorem pw_aff3 (f : Rat → Rat) (k1 k2 : Rat) (hk : 0 < k1 ∧ k1 < k2 ∧ k2 < 1)
    (h1 : ∃ a b, ∀ x, 0 ≤ x → x ≤ k1 → f x = a + b * x) (h2 : ∃ a b, ∀ x, k1 ≤ x → x ≤ k2 → f x = a + b * x)
    (h3 : ∃ a b, ∀ x, k2 ≤ x → x ≤ 1 → f x = a + b * x) (m : Rat) (hm0 : 0 ≤ m) (hm1 : m ≤ 1) :
    Track.eval (mk f [0, k1, k2, 1]) m = f m :=
  exact_of_aff f [k1, k2, 1] 0 m ⟨hk.1, h1, hk.2.1, h2, hk.2.2, h3, trivial⟩ hm0 (by simpa [lastOf] using hm1)

theorem pw_aff2 (f : Rat → Rat) (k1 : Rat) (hk : 0 < k1 ∧ k1 < 1)
    (h1 : ∃ a b, ∀ x, 0 ≤ x → x ≤ k1 → f x = a + b * x) (h2 : ∃ a b, ∀ x, k1 ≤ x → x ≤ 1 → f x = a + b * x)
    (m : Rat) (hm0 : 0 ≤ m) (hm1 : m ≤ 1) : Track.eval (mk f [0, k1, 1]) m = f m :=
  exact_of_aff f [k1, 1] 0 m ⟨hk.1, h1, hk.2, h2, trivial⟩ hm0 (by simpa [lastOf] using hm1)

theorem panel_eq (v : Vp) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    Track.eval (mk panelO panelKnots) m = panelO m ∧ Track.eval (mk (panelBlur v) panelKnots) m = panelBlur v m := by
  have k : (0 : Rat) < 2 / 25 ∧ (2 / 25 : Rat) < 4 / 5 ∧ (4 / 5 : Rat) < 1 := by grind
  have o1 : ∃ a b, ∀ x, (0 : Rat) ≤ x → x ≤ 2 / 25 → panelO x = a + b * x :=
    ⟨0, 0, fun x _ h => by unfold panelO clamp01; grind⟩
  have o2 : ∃ a b, ∀ x, (2 / 25 : Rat) ≤ x → x ≤ 4 / 5 → panelO x = a + b * x :=
    ⟨-1 / 9, 25 / 18, fun x _ _ => by unfold panelO clamp01; grind⟩
  have o3 : ∃ a b, ∀ x, (4 / 5 : Rat) ≤ x → x ≤ 1 → panelO x = a + b * x :=
    ⟨1, 0, fun x _ _ => by unfold panelO clamp01; grind⟩
  refine ⟨pw_aff3 panelO _ _ k o1 o2 o3 m h0 h1, ?_⟩
  unfold panelKnots
  by_cases hw : v.w ≤ 720
  · have : panelBlur v = fun _ => 0 := by funext x; simp [panelBlur, hw]
    rw [this]; exact pw_aff3 _ _ _ k ⟨0, 0, fun _ _ _ => by grind⟩ ⟨0, 0, fun _ _ _ => by grind⟩
      ⟨0, 0, fun _ _ _ => by grind⟩ m h0 h1
  · have : panelBlur v = fun x => 12 * (1 - panelO x) := by funext x; simp [panelBlur, hw]
    rw [this]
    obtain ⟨a1, b1, e1⟩ := o1; obtain ⟨a2, b2, e2⟩ := o2; obtain ⟨a3, b3, e3⟩ := o3
    exact pw_aff3 _ _ _ k ⟨12 - 12 * a1, -12 * b1, fun x p q => by rw [e1 x p q]; grind⟩
      ⟨12 - 12 * a2, -12 * b2, fun x p q => by rw [e2 x p q]; grind⟩
      ⟨12 - 12 * a3, -12 * b3, fun x p q => by rw [e3 x p q]; grind⟩ m h0 h1

def fadeBlur (m : Rat) : Rat := 12 * (1 - fade m)

theorem fade_eq (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    Track.eval (mk fade fadeKnots) m = fade m ∧ Track.eval (mk fadeBlur fadeKnots) m = fadeBlur m := by
  have k : (0 : Rat) < 11 / 20 ∧ (11 / 20 : Rat) < 1 := by grind
  have f1 : ∃ a b, ∀ x, (0 : Rat) ≤ x → x ≤ 11 / 20 → fade x = a + b * x :=
    ⟨1, -20 / 11, fun x _ _ => by unfold fade fadeEnd; grind⟩
  have f2 : ∃ a b, ∀ x, (11 / 20 : Rat) ≤ x → x ≤ 1 → fade x = a + b * x :=
    ⟨0, 0, fun x _ _ => by unfold fade fadeEnd; grind⟩
  refine ⟨pw_aff2 fade _ k f1 f2 m h0 h1, ?_⟩
  obtain ⟨a1, b1, e1⟩ := f1; obtain ⟨a2, b2, e2⟩ := f2
  exact pw_aff2 _ _ k ⟨12 - 12 * a1, -12 * b1, fun x p q => by unfold fadeBlur; rw [e1 x p q]; grind⟩
    ⟨12 - 12 * a2, -12 * b2, fun x p q => by unfold fadeBlur; rw [e2 x p q]; grind⟩ m h0 h1


def logoT (v : Vp) (inset lw m : Rat) : Rat :=
  x0 v m + logoLeft inset (wd v m) m - m * lw / 2 - (wp v / 2 - lw / 2)

theorem logo_exact (v : Vp) (inset lw m : Rat) :
    wp v / 2 - lw / 2 + logoT v inset lw m = x0 v m + logoLeft inset (wd v m) m - m * lw / 2 := by
  unfold logoT; grind

def dW (v : Vp) : Rat := wp v - pillW v

theorem logoT_quad (v : Vp) (inset lw m : Rat) :
    logoT v inset lw m = (lw - pillW v) / 2 + inset +
      (pillW v / 2 - (wp v - pillW v) / 2 - inset - lw / 2) * m + dW v / 2 * m * m := by
  unfold logoT logoLeft dW x0; rw [wd_eq]; grind

theorem chord_quad (c b a p q m : Rat) (hpq : p < q) :
    chord (fun x => c + b * x + a * x * x) p q m - (c + b * m + a * m * m) = a * (m - p) * (q - m) := by
  unfold chord
  have : q - p ≠ 0 := by grind
  grind

theorem quad_seg (c b a p h m : Rat) (ha : 0 ≤ a) (hh : 0 < h) (h1 : p ≤ m) (h2 : m ≤ p + h) :
    Within (chord (fun x => c + b * x + a * x * x) p (p + h) m - (c + b * m + a * m * m)) (a * h ^ 2 / 4) := by
  rw [chord_quad c b a p (p + h) m (by grind)]
  have e : a * h ^ 2 / 4 - a * (m - p) * (p + h - m) = a * ((m - p) - (p + h - m)) ^ 2 / 4 := by grind
  have s1 : 0 ≤ a * ((m - p) - (p + h - m)) ^ 2 / 4 := by
    have := sqNonneg ((m - p) - (p + h - m)); have := Rat.mul_nonneg ha this; grind
  have s2 : 0 ≤ a * ((m - p) * (p + h - m)) := Rat.mul_nonneg ha (Rat.mul_nonneg (by grind) (by grind))
  unfold Within; grind

theorem chordOk_grid_quad (c b a h : Rat) (ha : 0 ≤ a) (hh : 0 < h) :
    ∀ (k : Nat) (P : Rat), ChordOk (fun x => c + b * x + a * x * x) (a * h ^ 2 / 4) (gridFrom P h k) := by
  intro k
  induction k with
  | zero => intros; simp [gridFrom, ChordOk]
  | succ k ih =>
    intro P
    cases k with
    | zero => exact ⟨by grind, fun m h1 h2 => quad_seg c b a P h m ha hh h1 h2, by simp [ChordOk]⟩
    | succ k' => exact ⟨by grind, fun m h1 h2 => quad_seg c b a P h m ha hh h1 h2, ih (P + h)⟩

theorem knots_within (v : Vp) (hv : Valid v) (F : Rat → Rat) (B : Rat) (hB0 : 0 ≤ B)
    (c1 : phone v.w = true → ChordOk F B (gridFrom 0 (stepA v) (n1 v)))
    (c2 : phone v.w = true → ChordOk F B (gridFrom (mKnot v) (stepB v) nMain))
    (c3 : phone v.w = false → ChordOk F B (gridFrom 0 (1 / nMain) nMain)) :
    ∀ m, 0 ≤ m → m ≤ 1 → Within (Track.eval (mk F (knots v)) m - F m) B := by
  intro m hm0 hm1
  by_cases hph : phone v.w = true
  · have kp := mKnot_pos v hv
    have ⟨e1, hh1p⟩ := stepA_facts v hv
    have ⟨e2, hh2p⟩ := stepB_facts v hv
    have hp1 : 0 < n1 v := by unfold n1; grind
    have g1 : gridFrom 0 (stepA v) (n1 v) = gridInit 0 (stepA v) (n1 v) ++ [mKnot v] := by
      rw [gridFrom_eq]; rw [show (0 : Rat) + (n1 v : Rat) * stepA v = mKnot v by grind]
    have d1 := c1 hph
    rw [g1] at d1
    have g2 := gridFrom_cons (mKnot v) (stepB v) nMain
    have d2 := c2 hph
    rw [g2] at d2
    have call := chordOk_append F _ (gridInit 0 (stepA v) (n1 v)) (mKnot v) _ d1 d2
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
    have e : (nMain : Rat) * (1 / (nMain : Rat)) = 1 := by grind
    have hk : knots v = gridFrom 0 (1 / nMain) nMain := by
      unfold knots; simp only [hph', Bool.false_eq_true, ↓reduceIte]
    have g := gridFrom_cons 0 (1 / (nMain : Rat)) nMain
    refine eval_knots F _ hB0 (knots v) 0 _ (by rw [hk]; exact g) (by rw [hk]; exact c3 hph') m hm0 ?_
    rw [hk, lastL_gridFrom]
    grind

def hMax (v : Vp) : Rat := if phone v.w then max (stepA v) (stepB v) else 1 / nMain

def logoB (v : Vp) : Rat := dW v * hMax v ^ 2 / 8

theorem sq_mono (a b : Rat) (h0 : 0 ≤ a) (h : a ≤ b) : a ^ 2 ≤ b ^ 2 := by
  have := mulLe a b a b h0 h h0 h
  grind

theorem logo_err (v : Vp) (hv : Valid v) (inset lw m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    Within (Track.eval (mk (logoT v inset lw) (knots v)) m - logoT v inset lw m) (logoB v) := by
  have pl := pill_le v hv
  have ha : 0 ≤ dW v / 2 := by unfold dW; grind
  have hF : logoT v inset lw = fun x => (lw - pillW v) / 2 + inset +
      (pillW v / 2 - (wp v - pillW v) / 2 - inset - lw / 2) * x + dW v / 2 * x * x := by
    funext x; exact logoT_quad v inset lw x
  have hB : logoB v = dW v / 2 * hMax v ^ 2 / 4 := by unfold logoB; grind
  have hm0 : 0 ≤ hMax v := by
    unfold hMax; split
    · have := (stepA_facts v hv).2; grind
    · unfold nMain; grind
  have hB0 : 0 ≤ logoB v := by rw [hB]; have := Rat.mul_nonneg ha (sqNonneg (hMax v)); grind
  rw [hF]
  apply knots_within v hv _ _ hB0 _ _ _ m h0 h1
  · intro hph
    have ⟨_, hs⟩ := stepA_facts v hv
    refine chordOk_mono _ _ _ ?_ _ (chordOk_grid_quad _ _ _ (stepA v) ha hs (n1 v) 0)
    rw [hB]
    have : stepA v ^ 2 ≤ hMax v ^ 2 := sq_mono _ _ (by grind) (by unfold hMax; simp [hph]; grind)
    have := Rat.mul_le_mul_of_nonneg_left this ha
    grind
  · intro hph
    have ⟨_, hs⟩ := stepB_facts v hv
    refine chordOk_mono _ _ _ ?_ _ (chordOk_grid_quad _ _ _ (stepB v) ha hs nMain (mKnot v))
    rw [hB]
    have : stepB v ^ 2 ≤ hMax v ^ 2 := sq_mono _ _ (by grind) (by unfold hMax; simp [hph]; grind)
    have := Rat.mul_le_mul_of_nonneg_left this ha
    grind
  · intro hph
    have hs : (0 : Rat) < 1 / nMain := by unfold nMain; grind
    refine chordOk_mono _ _ _ ?_ _ (chordOk_grid_quad _ _ _ (1 / nMain) ha hs nMain 0)
    rw [hB]; unfold hMax; simp [hph]

theorem logo_ok_bands : bandVps.all (fun v => decide (logoB v ≤ 1 / 64)) = true := by decide +kernel

end Fw.Parts.MorphGeom
