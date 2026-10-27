import Fw.Parts.MorphGeomRect
/-! `morph.geom:on` column pictures: `object-fit: cover` rectangle and crop of the base page and of the flip, equal at every `m`.
The flip moves one `img` by transform inside static and translated clippers; no layout and no clip-path animation. -/
namespace Fw.Parts.MorphGeom
open Fw.Parts.Nav

/-- A picture box: top `y` in the track, height `h`, intrinsic size `iw` by `ih`. -/
structure Pic where
  y : Rat
  h : Rat
  iw : Rat
  ih : Rat
  deriving Repr, DecidableEq

/-- Left, top, right and bottom edges. -/
structure Rc where
  l : Rat
  t : Rat
  r : Rat
  b : Rat
  deriving Repr, DecidableEq

def rmax (a b : Rat) : Rat := if a ≤ b then b else a

def rmin (a b : Rat) : Rat := if a ≤ b then a else b

/-- The `object-fit: cover` scale, the larger fit ratio (`layout_replaced.cc:447-478@f842f52`, `RenderReplaced.cpp:582-612@862f17d`). -/
def coverK (bw bh iw ih : Rat) : Rat := rmax (bw / iw) (bh / ih)

/-- The drawn rectangle in box coordinates at `object-position: 50% 50%` (same two files). -/
def drawn (bw bh iw ih : Rat) : Rc :=
  ⟨(bw - iw * coverK bw bh iw ih) / 2, (bh - ih * coverK bw bh iw ih) / 2,
    (bw + iw * coverK bw bh iw ih) / 2, (bh + ih * coverK bw bh iw ih) / 2⟩

/-- The crop window: the box itself. -/
def cropBox (bw bh : Rat) : Rc := ⟨0, 0, bw, bh⟩

/-- The base page at `m`: a `cw v m` by `p.h` box. -/
def basePic (v : Vp) (p : Pic) (m : Rat) : Rc := drawn (cw v m) p.h p.iw p.ih

def baseCrop (v : Vp) (p : Pic) (m : Rat) : Rc := cropBox (cw v m) p.h

/-- The flip's `img` rectangle at rest (`object-fit: fill`): what the base draws at `m = 1`. -/
def layRect (v : Vp) (p : Pic) : Rc := drawn (cw v 1) p.h p.iw p.ih

/-- Uniform scale of the picture: its drawn size over its size at `m = 1`. -/
def uImg (v : Vp) (p : Pic) (m : Rat) : Rat := coverK (cw v m) p.h p.iw p.ih / coverK (cw v 1) p.h p.iw p.ih

/-- Translate of the picture about its centre: it follows the centre of the narrowing box. -/
def imgTx (v : Vp) (m : Rat) : Rat := (sImg v m - 1) * cw v 1 / 2

/-- Translate of the right-edge clipper `Kc`; `Uc` moves by the negative. -/
def kcTx (v : Vp) (m : Rat) : Rat := (sImg v m - 1) * cw v 1

/-- The `m` where the two fit ratios cross: `cw v m = iw * h / ih`. -/
def qImg (v : Vp) (p : Pic) : Rat := (p.iw * p.h / p.ih - cw v 0) / (cw v 1 - cw v 0)

/-- Key offsets: a knot at the crossing `q` when it lies inside `(0, 1)`. -/
def kinkKnots (q : Rat) : List Rat := if 0 < q ∧ q < 1 then [0, q, 1] else [0, 1]

def evK (f : Rat → Rat) (ks : List Rat) (m : Rat) : Rat := Track.eval (mk f ks) m

/-- `r` scaled by `u` about its centre, then moved by `tx`. -/
def xform (r : Rc) (tx u : Rat) : Rc :=
  ⟨(r.l + r.r) / 2 + tx - u * ((r.r - r.l) / 2), (r.t + r.b) / 2 - u * ((r.b - r.t) / 2),
    (r.l + r.r) / 2 + tx + u * ((r.r - r.l) / 2), (r.t + r.b) / 2 + u * ((r.b - r.t) / 2)⟩

def composedPic (v : Vp) (p : Pic) (m : Rat) : Rc :=
  xform (layRect v p) (ev (imgTx v) m) (evK (uImg v p) (kinkKnots (qImg v p)) m)

/-- The flip's crop at `m`: the static box cut by the clipper `Kc`, moved by `kcTx`. -/
def composedCrop (v : Vp) (p : Pic) (m : Rat) : Rc :=
  ⟨rmax 0 (ev (kcTx v) m), 0, rmin (cw v 1) (ev (kcTx v) m + cw v 1), p.h⟩

theorem div_le_iff' (a b iw ih : Rat) (hw : 0 < iw) (hh : 0 < ih) : a / iw ≤ b / ih ↔ a * ih ≤ b * iw := by
  have h1 : a / iw * iw = a := Rat.div_mul_cancel (by grind)
  have h2 : b / ih * ih = b := Rat.div_mul_cancel (by grind)
  generalize a / iw = x at *
  generalize b / ih = y at *
  subst h1 h2
  have hp : 0 < iw * ih := Rat.mul_pos hw hh
  constructor
  · intro h
    have := Rat.mul_le_mul_of_nonneg_right h (Rat.le_of_lt hp)
    grind
  · intro h
    by_cases hx : x ≤ y
    · exact hx
    · have : y < x := by grind
      have := Rat.mul_lt_mul_of_pos_right this hp
      grind

theorem div_one_of' (x : Rat) (h : x ≠ 0) : x / x = 1 := by rw [Rat.div_def, Rat.mul_inv_cancel _ h]

theorem coverK_pos (bw bh iw ih : Rat) (hh : 0 < bh) (hi : 0 < ih) : 0 < coverK bw bh iw ih := by
  unfold coverK rmax
  have : 0 < bh / ih := by
    have h1 : bh / ih * ih = bh := Rat.div_mul_cancel (by grind)
    by_cases h : 0 < bh / ih
    · exact h
    · have : bh / ih ≤ 0 := by grind
      have := Rat.mul_le_mul_of_nonneg_right this (Rat.le_of_lt hi)
      grind
  split <;> grind

/-- The drawn rectangle covers the crop window. -/
theorem cover_covers (bw bh iw ih : Rat) (hw : 0 < iw) (hi : 0 < ih) :
    (drawn bw bh iw ih).l ≤ (cropBox bw bh).l ∧ (drawn bw bh iw ih).t ≤ (cropBox bw bh).t ∧
      (cropBox bw bh).r ≤ (drawn bw bh iw ih).r ∧ (cropBox bw bh).b ≤ (drawn bw bh iw ih).b := by
  have h1 : bw / iw * iw = bw := Rat.div_mul_cancel (by grind)
  have h2 : bh / ih * ih = bh := Rat.div_mul_cancel (by grind)
  have ha : bw / iw ≤ coverK bw bh iw ih := by unfold coverK rmax; split <;> grind
  have hb : bh / ih ≤ coverK bw bh iw ih := by unfold coverK rmax; split <;> grind
  have ha' := Rat.mul_le_mul_of_nonneg_right ha (Rat.le_of_lt hw)
  have hb' := Rat.mul_le_mul_of_nonneg_right hb (Rat.le_of_lt hi)
  unfold drawn cropBox
  simp only
  refine ⟨by grind, by grind, by grind, by grind⟩

/-- The old flip scaled the box in both axes: its height `sImg v m * h` is not the base's `h`. -/
theorem old_height_differs (v : Vp) (p : Pic) (m : Rat) (hh : p.h ≠ 0) (hs : sImg v m ≠ 1) : sImg v m * p.h ≠ p.h := by
  intro h
  apply hs
  have : (sImg v m - 1) * p.h = 0 := by grind
  rcases Rat.mul_eq_zero.mp this with h | h
  · grind
  · exact absurd h hh

theorem cw_lin (v : Vp) (x : Rat) : cw v x = cw v 0 + (cw v 1 - cw v 0) * x := by
  obtain ⟨a, b, h⟩ := aff_cw v
  have h0 := h 0
  have h1 := h 1
  have hx := h x
  grind

/-- The box widens with `m`. -/
theorem cw_incr (v : Vp) (hv : Valid v) : cw v 0 < cw v 1 := by
  have s := sizes v
  have hp := pill_le v hv
  obtain ⟨hv1, _⟩ := hv
  unfold cw nCols colGap
  rw [wd_eq, wd_eq]
  by_cases h : phone v.w = true
  · have := s.1 h; simp only [h, ite_true]; grind
  · have h' : phone v.w = false := by simpa using h
    have := s.2 h'
    simp only [h', Bool.false_eq_true, ite_false]
    unfold phone at h'; simp at h'
    grind

theorem cw_le (v : Vp) (hv : Valid v) (m : Rat) (h1 : m ≤ 1) : cw v m ≤ cw v 1 := by
  have := cw_incr v hv
  have := cw_lin v m
  have := Rat.mul_le_mul_of_nonneg_left h1 (show 0 ≤ cw v 1 - cw v 0 by grind)
  grind

theorem sImg_mul (v : Vp) (hv : Valid v) (m : Rat) : sImg v m * cw v 1 = cw v m := by
  unfold sImg; exact Rat.div_mul_cancel (by have := cw1_pos v hv; grind)

/-- Positive box height and intrinsic size. -/
def PicOk (p : Pic) : Prop := 0 < p.h ∧ 0 < p.iw ∧ 0 < p.ih

theorem k1_pos (v : Vp) (p : Pic) (hp : PicOk p) : 0 < coverK (cw v 1) p.h p.iw p.ih :=
  coverK_pos _ _ _ _ hp.1 hp.2.2

/-- Left of the crossing the height ratio wins. -/
theorem cover_lo (v : Vp) (hv : Valid v) (p : Pic) (hp : PicOk p) (x : Rat) (hx : x ≤ qImg v p) :
    coverK (cw v x) p.h p.iw p.ih = p.h / p.ih := by
  obtain ⟨hh, hw, hi⟩ := hp
  have hB := cw_incr v hv
  have hq : qImg v p * (cw v 1 - cw v 0) = p.iw * p.h / p.ih - cw v 0 := by
    unfold qImg; exact Rat.div_mul_cancel (by grind)
  have h1 := Rat.mul_le_mul_of_nonneg_right hx (show 0 ≤ cw v 1 - cw v 0 by grind)
  have h2 := cw_lin v x
  have h3 : p.iw * p.h / p.ih * p.ih = p.iw * p.h := Rat.div_mul_cancel (by grind)
  have h4 : cw v x ≤ p.iw * p.h / p.ih := by grind
  have h5 := Rat.mul_le_mul_of_nonneg_right h4 (Rat.le_of_lt hi)
  have : cw v x / p.iw ≤ p.h / p.ih := (div_le_iff' _ _ _ _ hw hi).mpr (by grind)
  unfold coverK rmax
  simp only [this, ite_true]

/-- Right of the crossing the width ratio wins. -/
theorem cover_hi (v : Vp) (hv : Valid v) (p : Pic) (hp : PicOk p) (x : Rat) (hx : qImg v p ≤ x) :
    coverK (cw v x) p.h p.iw p.ih = cw v x / p.iw := by
  obtain ⟨hh, hw, hi⟩ := hp
  have hB := cw_incr v hv
  have hq : qImg v p * (cw v 1 - cw v 0) = p.iw * p.h / p.ih - cw v 0 := by
    unfold qImg; exact Rat.div_mul_cancel (by grind)
  have h1 := Rat.mul_le_mul_of_nonneg_right hx (show 0 ≤ cw v 1 - cw v 0 by grind)
  have h2 := cw_lin v x
  have h3 : p.iw * p.h / p.ih * p.ih = p.iw * p.h := Rat.div_mul_cancel (by grind)
  have h4 : p.iw * p.h / p.ih ≤ cw v x := by grind
  have h5 := Rat.mul_le_mul_of_nonneg_right h4 (Rat.le_of_lt hi)
  have : p.h / p.ih ≤ cw v x / p.iw := (div_le_iff' _ _ _ _ hi hw).mpr (by grind)
  unfold coverK rmax
  by_cases hc : cw v x / p.iw ≤ p.h / p.ih
  · simp only [hc, ite_true]; grind
  · simp only [hc, ite_false]

theorem uImg_lo (v : Vp) (hv : Valid v) (p : Pic) (hp : PicOk p) (x : Rat) (hx : x ≤ qImg v p) :
    uImg v p x = p.h / p.ih / coverK (cw v 1) p.h p.iw p.ih := by
  unfold uImg; rw [cover_lo v hv p hp x hx]

theorem uImg_hi (v : Vp) (hv : Valid v) (p : Pic) (hp : PicOk p) (x : Rat) (hx : qImg v p ≤ x) :
    uImg v p x = cw v 0 / p.iw / coverK (cw v 1) p.h p.iw p.ih +
      (cw v 1 - cw v 0) / p.iw / coverK (cw v 1) p.h p.iw p.ih * x := by
  unfold uImg; rw [cover_hi v hv p hp x hx, cw_lin v x]
  simp only [Rat.div_def]
  grind

theorem affPieces_uImg (v : Vp) (hv : Valid v) (p : Pic) (hp : PicOk p) :
    AffPieces (uImg v p) (kinkKnots (qImg v p)) := by
  have lo : ∃ α β : Rat, ∀ x, x ≤ qImg v p → uImg v p x = α + β * x :=
    ⟨p.h / p.ih / coverK (cw v 1) p.h p.iw p.ih, 0, fun x hx => by rw [uImg_lo v hv p hp x hx]; grind⟩
  have hi : ∃ α β : Rat, ∀ x, qImg v p ≤ x → uImg v p x = α + β * x :=
    ⟨_, _, fun x hx => uImg_hi v hv p hp x hx⟩
  unfold kinkKnots
  by_cases h : 0 < qImg v p ∧ qImg v p < 1
  · simp only [h, and_self, ite_true]
    obtain ⟨a, b, hab⟩ := lo
    obtain ⟨c, d, hcd⟩ := hi
    exact ⟨h.1, ⟨a, b, fun x _ h2 => hab x h2⟩, h.2, ⟨c, d, fun x h1 _ => hcd x h1⟩, trivial⟩
  · simp only [h, ite_false]
    by_cases hq : qImg v p ≤ 0
    · obtain ⟨c, d, hcd⟩ := hi
      exact ⟨by grind, ⟨c, d, fun x h1 _ => hcd x (by grind)⟩, trivial⟩
    · obtain ⟨a, b, hab⟩ := lo
      exact ⟨by grind, ⟨a, b, fun x _ h2 => hab x (by grind)⟩, trivial⟩

theorem evK_uImg (v : Vp) (hv : Valid v) (p : Pic) (hp : PicOk p) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    evK (uImg v p) (kinkKnots (qImg v p)) m = uImg v p m := by
  have ha := affPieces_uImg v hv p hp
  unfold evK kinkKnots at *
  by_cases h : 0 < qImg v p ∧ qImg v p < 1
  · simp only [h, and_self, ite_true] at *
    exact exact_of_aff _ [qImg v p, 1] 0 m ha h0 (by simpa [lastOf] using h1)
  · simp only [h, ite_false] at *
    exact exact_of_aff _ [1] 0 m ha h0 (by simpa [lastOf] using h1)

theorem u_mul (v : Vp) (p : Pic) (hp : PicOk p) (m : Rat) :
    uImg v p m * coverK (cw v 1) p.h p.iw p.ih = coverK (cw v m) p.h p.iw p.ih := by
  unfold uImg
  exact Rat.div_mul_cancel (by have := k1_pos v p hp; grind)

theorem aff_imgTx (v : Vp) : Aff (imgTx v) := by
  obtain ⟨a, b, h⟩ := aff_sImg v
  exact ⟨(a - 1) * cw v 1 / 2, b * cw v 1 / 2, fun x => by unfold imgTx; rw [h x]; grind⟩

theorem aff_kcTx (v : Vp) : Aff (kcTx v) := by
  obtain ⟨a, b, h⟩ := aff_sImg v
  exact ⟨(a - 1) * cw v 1, b * cw v 1, fun x => by unfold kcTx; rw [h x]; grind⟩

/-- The flip draws the base's picture rectangle at every `m`. -/
theorem pic_rect_eq (v : Vp) (hv : Valid v) (p : Pic) (hp : PicOk p) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    composedPic v p m = basePic v p m := by
  have hu := evK_uImg v hv p hp m h0 h1
  have ht := ev_eq _ (aff_imgTx v) m h0 h1
  have hm := u_mul v p hp m
  have hs := sImg_mul v hv m
  unfold composedPic basePic xform layRect drawn
  rw [hu, ht]
  unfold imgTx
  simp only [Rc.mk.injEq]
  generalize coverK (cw v m) p.h p.iw p.ih = k at *
  generalize coverK (cw v 1) p.h p.iw p.ih = k1 at *
  generalize uImg v p m = u at *
  refine ⟨?_, ?_, ?_, ?_⟩ <;> grind

/-- The flip crops to the base's window at every `m`. -/
theorem pic_crop_eq (v : Vp) (hv : Valid v) (p : Pic) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    composedCrop v p m = baseCrop v p m := by
  have ht := ev_eq _ (aff_kcTx v) m h0 h1
  have hs := sImg_mul v hv m
  have hle := cw_le v hv m h1
  unfold composedCrop baseCrop cropBox
  rw [ht]
  unfold kcTx rmax rmin
  simp only [Rc.mk.injEq]
  refine ⟨?_, trivial, ?_, trivial⟩ <;> split <;> grind

/-- Rectangle and crop of the flip both equal the base's. -/
theorem pic_eq (v : Vp) (hv : Valid v) (p : Pic) (hp : PicOk p) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    composedPic v p m = basePic v p m ∧ composedCrop v p m = baseCrop v p m :=
  ⟨pic_rect_eq v hv p hp m h0 h1, pic_crop_eq v hv p m h0 h1⟩

/-- Amplitude of the track drift, the `up` and `down` keyframes of the columns. -/
def driftAmp : Rat := 56

/-- Vertical padding of `Kc` (and the margin that undoes it): more than the drift. -/
def clipPad : Rat := 64

theorem clipPad_covers_drift : driftAmp ≤ clipPad := by decide

/-- The flip's crop window lies inside its drawn rectangle: no gap shows. -/
theorem flip_covers (v : Vp) (hv : Valid v) (p : Pic) (hp : PicOk p) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    (composedPic v p m).l ≤ (composedCrop v p m).l ∧ (composedPic v p m).t ≤ (composedCrop v p m).t ∧
      (composedCrop v p m).r ≤ (composedPic v p m).r ∧ (composedCrop v p m).b ≤ (composedPic v p m).b := by
  rw [pic_rect_eq v hv p hp m h0 h1, pic_crop_eq v hv p m h0 h1]
  exact cover_covers _ _ _ _ hp.2.1 hp.2.2

/-- The picture box starts where the base's does. -/
theorem pic_box_x (v : Vp) (hv : Valid v) (p : Pic) (i : Nat) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    (i : Rat) * (cw v 1 + colGap v) + ev (colTx v i) m + (composedCrop v p m).l = (i : Rat) * (cw v m + colGap v) := by
  have et := ev_eq _ (aff_colTx v i) m h0 h1
  rw [pic_crop_eq v hv p m h0 h1]
  unfold colTx baseCrop cropBox at *
  simp only at *
  grind

/-- At `m = 1` every moving piece is neutral. -/
theorem pic_end (v : Vp) (hv : Valid v) (p : Pic) (hp : PicOk p) :
    imgTx v 1 = 0 ∧ kcTx v 1 = 0 ∧ uImg v p 1 = 1 := by
  have hs : sImg v 1 = 1 := by unfold sImg; exact div_one_of' _ (by have := cw1_pos v hv; grind)
  refine ⟨by unfold imgTx; grind, by unfold kcTx; grind, ?_⟩
  unfold uImg
  exact div_one_of' _ (by have := k1_pos v p hp; grind)

end Fw.Parts.MorphGeom
