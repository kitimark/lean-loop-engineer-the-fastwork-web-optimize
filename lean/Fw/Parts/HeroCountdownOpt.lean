import Fw.Engine
import Fw.Parts.HeroCountdown
import Fw.Parts.EndFlags

/-! hero.countdown and morph.countdown `strip`: same picture, fewer layers. -/
namespace Fw.Parts.HeroCountdownOpt

open Fw.Engine
open Fw.Parts.HeroCountdown

structure DigitGeo where
  slot  : Nat
  x     : Rat
  y     : Rat
  w     : Rat
  c     : Rat
  order : Nat
deriving Repr, DecidableEq

def glyph (g : DigitGeo) (k : Int) (o : Rat) : BoxVis where
  box := ⟨0, 0, g.w, g.c⟩
  ink := ⟨0, 0, g.w, g.c⟩
  paint := [("text", toString k)]
  xf := ⟨1, 0, 0, 1, g.x, g.y + o * g.c⟩
  alpha := 1
  clip := some (.rect ⟨0, -(o * g.c), g.w, g.c⟩)
  filter := []
  order := g.order

def glyphId (g : DigitGeo) (k : Int) : BoxId := s!"cd{g.slot}.g{k}"

def facesDigit (g : DigitGeo) (a : Rat) : Scene :=
  (List.range 10).map fun (k : Nat) => (glyphId g k, glyph g k (faceDelta k a))

def stripEntries (k : Int) : List Int := if k = 0 then [1, 11] else if k = 9 then [0, 10] else [k + 1]

#guard (List.range 10).all fun (k : Nat) =>
  stripEntries k == ((List.range 12).map Int.ofNat).filter (fun j => stripEntryDigit j == k)

theorem mem_stripEntries (k j : Int) (hk0 : 0 ≤ k) (hk1 : k < 10) :
    j ∈ stripEntries k ↔ 0 ≤ j ∧ j < 12 ∧ stripEntryDigit j = k := by
  unfold stripEntries stripEntryDigit
  by_cases h0 : k = 0 <;> by_cases h9 : k = 9 <;> simp [h0, h9] <;> omega

def stripDigit (g : DigitGeo) (a : Rat) : Scene :=
  (List.range 10).flatMap fun (k : Nat) =>
    (stripEntries k).map fun (j : Int) => (glyphId g k, glyph g k ((j : Rat) + stripOffsetCells a))

def facesClock (ds : List (DigitGeo × Rat)) : Scene := ds.flatMap fun d => facesDigit d.1 d.2

def stripClock (ds : List (DigitGeo × Rat)) : Scene := ds.flatMap fun d => stripDigit d.1 d.2

theorem glyph_kept_window (vp : Rect) (g : DigitGeo) (k : Int) (o : Rat)
    (h : (glyph g k o).drop vp = false) : -1 < o ∧ o < 1 := by
  simp only [BoxVis.drop, glyph, Rect.meets, Bool.or_eq_false_iff, Bool.not_eq_false',
    Bool.and_eq_true, decide_eq_true_eq] at h
  obtain ⟨⟨⟨_, _⟩, ⟨⟨⟨⟨⟨⟨⟨_, _⟩, _⟩, _⟩, hc⟩, _⟩, h1⟩, h2⟩⟩, _⟩ := h
  constructor
  · apply Classical.byContradiction
    intro hn
    have hn' : 0 ≤ -(1 + o) := by grind
    have := Rat.mul_nonneg hn' (Rat.le_of_lt hc)
    grind
  · apply Classical.byContradiction
    intro hn
    have hn' : 0 ≤ o - 1 := by grind
    have := Rat.mul_nonneg hn' (Rat.le_of_lt hc)
    grind

theorem filter_map_unique {α β : Type} (P : β → Bool) (f : α → β) (b : β) :
    ∀ (L : List α), (∀ x ∈ L, P (f x) = true → f x = b) → (P b = true → ∃ x ∈ L, f x = b) →
      L.Pairwise (fun x y => P (f x) = true → P (f y) = false) →
      (L.map f).filter P = [b].filter P
  | [], _, h2, _ => by
    cases hb : P b
    · simp [hb]
    · obtain ⟨x, hx, _⟩ := h2 hb; cases hx
  | x :: xs, h1, h2, h3 => by
    rw [List.pairwise_cons] at h3
    cases hx : P (f x)
    · have ih := filter_map_unique P f b xs (fun y hy => h1 y (List.mem_cons_of_mem _ hy))
        (fun hb => by
          obtain ⟨y, hy, hyb⟩ := h2 hb
          rcases List.mem_cons.mp hy with rfl | hy'
          · rw [hyb, hb] at hx; cases hx
          · exact ⟨y, hy', hyb⟩)
        h3.2
      simp [List.filter_cons, hx, ih]
    · have hxb := h1 x (List.mem_cons_self) hx
      have hnil : (xs.map f).filter P = [] := by
        rw [List.filter_eq_nil_iff]
        intro y hy
        obtain ⟨z, hz, rfl⟩ := List.mem_map.mp hy
        simp [h3.1 z hz hx]
      rw [← hxb]
      simp [hx, hnil]

theorem strip_glyph_same (vp : Rect) (g : DigitGeo) (a : Rat) (k : Int) (hk0 : 0 ≤ k) (hk1 : k < 10) :
    ((stripEntries k).map fun (j : Int) => (glyphId g k, glyph g k ((j : Rat) + stripOffsetCells a))).filter
        (fun e => !(e.2.drop vp)) =
      [(glyphId g k, glyph g k (faceDelta k a))].filter (fun e => !(e.2.drop vp)) := by
  apply filter_map_unique
  · intro j hj hkeep
    have hw := glyph_kept_window vp g k _ (by simpa using hkeep)
    have hm := (mem_stripEntries k j hk0 hk1).mp hj
    have := (strip_shows_same a k hk0 hk1 _ hw.1 hw.2).mp ⟨j, hm.1, hm.2.1, hm.2.2, rfl⟩
    rw [this]
  · intro hkeep
    have hw := glyph_kept_window vp g k _ (by simpa using hkeep)
    obtain ⟨j, hj0, hj1, hjd, hjo⟩ := (strip_shows_same a k hk0 hk1 _ hw.1 hw.2).mpr rfl
    exact ⟨j, (mem_stripEntries k j hk0 hk1).mpr ⟨hj0, hj1, hjd⟩, by rw [hjo]⟩
  · unfold stripEntries
    by_cases h0 : k = 0
    · rw [ite_eq_left_of_eq_true _ _ (eq_true h0)]
      refine List.Pairwise.cons ?_ (List.Pairwise.cons (by simp) List.Pairwise.nil)
      intro j hj hkeep
      rw [List.mem_singleton] at hj
      subst hj
      apply Bool.eq_false_iff.mpr
      intro h11
      have w1 := glyph_kept_window vp g k _ (by simpa using hkeep)
      have w11 := glyph_kept_window vp g k _ (by simpa using h11)
      grind
    · by_cases h9 : k = 9
      · rw [ite_eq_right_of_eq_false _ _ (eq_false h0), ite_eq_left_of_eq_true _ _ (eq_true h9)]
        refine List.Pairwise.cons ?_ (List.Pairwise.cons (by simp) List.Pairwise.nil)
        intro j hj hkeep
        rw [List.mem_singleton] at hj
        subst hj
        apply Bool.eq_false_iff.mpr
        intro h10
        have w0 := glyph_kept_window vp g k _ (by simpa using hkeep)
        have w10 := glyph_kept_window vp g k _ (by simpa using h10)
        grind
      · rw [ite_eq_right_of_eq_false _ _ (eq_false h0), ite_eq_right_of_eq_false _ _ (eq_false h9)]
        exact List.pairwise_singleton _ _

theorem flatMap_congr' {α β : Type} {l : List α} {f g : α → List β} (h : ∀ x ∈ l, f x = g x) :
    l.flatMap f = l.flatMap g := by
  induction l with
  | nil => rfl
  | cons x xs ih =>
    rw [List.flatMap_cons, List.flatMap_cons, h x List.mem_cons_self,
      ih (fun y hy => h y (List.mem_cons_of_mem _ hy))]

theorem strip_digit_same (vp : Rect) (g : DigitGeo) (a : Rat) :
    visible vp (stripDigit g a) = visible vp (facesDigit g a) := by
  have hf : facesDigit g a =
      (List.range 10).flatMap fun (k : Nat) => [(glyphId g k, glyph g k (faceDelta k a))] := by
    unfold facesDigit
    generalize List.range 10 = l
    induction l with
    | nil => rfl
    | cons x xs ih => simp [ih]
  rw [hf]
  unfold stripDigit visible
  rw [List.filter_flatMap, List.filter_flatMap]
  apply flatMap_congr'
  intro k hk
  have hk' := List.mem_range.mp hk
  exact strip_glyph_same vp g a k (by omega) (by omega)

theorem strip_visSame {Env T : Type} (vp : Env → Rect) (pre post : Env → T → Scene)
    (ds : Env → T → List (DigitGeo × Rat)) :
    VisSame E vp (fun env t => pre env t ++ facesClock (ds env t) ++ post env t)
      (fun env t => pre env t ++ stripClock (ds env t) ++ post env t) := by
  intro env t
  unfold E visible facesClock stripClock
  simp only [List.filter_append, List.filter_flatMap]
  congr 2
  apply flatMap_congr'
  intro d _
  exact (strip_digit_same (vp env) d.1 d.2).symm

inductive Align where
  | center
  | start
deriving Repr, DecidableEq

def lineTop : Align → Rat → Rat → Rat
  | .center, h, l => (h - l) / 2
  | .start, _, _ => 0

#guard lineTop .center (312 / 10) (312 / 10) == 0
#guard lineTop .center 31 (312 / 10) == -(1 / 10)
#guard lineTop .center 36 (364 / 10) == -(1 / 5)
#guard lineTop .center 52 52 == 0
#guard lineTop .start 31 (312 / 10) == 0

theorem face_top (l : Rat) : lineTop .center l l = 0 := by
  simp only [lineTop]; grind

theorem entry_center_iff (h l : Rat) : lineTop .center h l = lineTop .center l l ↔ h = l := by
  simp only [lineTop]; grind

theorem entry_start (h l : Rat) : lineTop .start h l = lineTop .center l l := by
  simp only [lineTop]; grind

def stackPx (c : Rat) (as : List Rat) : Int := as.foldl (fun v a => roundQ (a * v)) (roundQ c)

#guard stackPx (3 / 10 * 255) [1 / 2] == 39
#guard stackPx (3 / 10 * 255) [1, 1 / 2] == 39
#guard stackPx (3 / 10 * 255) [1 / 2, 1] == 39
#guard stackPx 255 [] == 255

theorem stackPx_one (c : Rat) (l r : List Rat) : stackPx c (l ++ 1 :: r) = stackPx c (l ++ r) := by
  simp only [stackPx, List.foldl_append, List.foldl_cons, Rat.one_mul, roundQ_int]

theorem stackPx_filter (c : Rat) (as : List Rat) : stackPx c as = stackPx c (as.filter (· ≠ 1)) := by
  unfold stackPx
  generalize roundQ c = v
  induction as generalizing v with
  | nil => rfl
  | cons a as ih =>
    by_cases h : a = 1
    · subst h; simp only [List.foldl_cons, Rat.one_mul, roundQ_int, List.filter_cons]; simpa using ih v
    · simp [h, ih]

/-- Premise not stated by the theorem: the glyph is in a composited layer in both arms or in neither (same scene-pause rule), and the panel opacity is applied once to the group in both arms (render surface / CA group opacity), backdrop blend not modelled: INFERRED. -/
theorem strip_px_eq (c α : Rat) (strip faces outer : List Rat) (hs : ∀ a ∈ strip, a = 1)
    (hf : ∀ a ∈ faces, a = 1) : stackPx c (strip ++ α :: outer) = stackPx c (faces ++ α :: outer) := by
  have e : ∀ l : List Rat, (∀ a ∈ l, a = 1) → l.filter (· ≠ 1) = [] := fun l h =>
    List.filter_eq_nil_iff.mpr (by simpa using h)
  rw [stackPx_filter, stackPx_filter c (faces ++ _), List.filter_append, List.filter_append, e _ hs, e _ hf]

#guard stackPx (3 / 10 * 255) ([1, 1] ++ [1 / 2]) == stackPx (3 / 10 * 255) ([1] ++ [1 / 2])
#guard stackPx (3 / 10 * 255) [1 / 2] != stackPx (1 / 2 * (3 / 10) * 255) []

section Work
variable {P M : Type}

def faceWrites (p : P) (ℓ : LayerState) (ds : List Nat) : List (Change P) :=
  ds.flatMap fun d => (List.range 10).map fun k => ⟨10 * d + k, p, ℓ⟩

def stripWrites (p : P) (ℓ : LayerState) (ds : List Nat) : List (Change P) :=
  ds.map fun d => ⟨10 * d, p, ℓ⟩

def withWrites (f : FrameIn P) (ws : List (Change P)) : FrameIn P := { f with changes := f.changes ++ ws }

theorem faceWrites_stages (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (ds : List Nat) (s : Stage) :
    s ∈ (faceWrites p ℓ ds).flatMap E.stagesOf ↔ ds ≠ [] ∧ s ∈ S := by
  unfold faceWrites
  simp only [List.mem_flatMap, List.mem_map, List.mem_range]
  constructor
  · rintro ⟨c, ⟨d, hd, k, _, rfl⟩, hs⟩
    rw [hS] at hs
    exact ⟨List.ne_nil_of_mem hd, hs⟩
  · rintro ⟨hne, hs⟩
    obtain ⟨d, hd⟩ := List.exists_mem_of_ne_nil ds hne
    exact ⟨_, ⟨d, hd, 0, by omega, rfl⟩, by rw [hS]; exact hs⟩

theorem stripWrites_stages (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (ds : List Nat) (s : Stage) :
    s ∈ (stripWrites p ℓ ds).flatMap E.stagesOf ↔ ds ≠ [] ∧ s ∈ S := by
  unfold stripWrites
  simp only [List.mem_flatMap, List.mem_map]
  constructor
  · rintro ⟨c, ⟨d, hd, rfl⟩, hs⟩
    rw [hS] at hs
    exact ⟨List.ne_nil_of_mem hd, hs⟩
  · rintro ⟨hne, hs⟩
    obtain ⟨d, hd⟩ := List.exists_mem_of_ne_nil ds hne
    exact ⟨_, ⟨d, hd, rfl⟩, by rw [hS]; exact hs⟩

theorem faceWrites_isEmpty (p : P) (ℓ : LayerState) (ds : List Nat) :
    (faceWrites p ℓ ds).isEmpty = ds.isEmpty := by
  cases ds <;> simp [faceWrites, List.range_succ]

theorem stripWrites_isEmpty (p : P) (ℓ : LayerState) (ds : List Nat) :
    (stripWrites p ℓ ds).isEmpty = ds.isEmpty := by
  cases ds <;> simp [stripWrites]

theorem faceWrites_count (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (ds : List Nat) (s : Stage) :
    (faceWrites p ℓ ds).countP (fun c => decide (s ∈ E.stagesOf c)) =
      10 * ds.length * (if s ∈ S then 1 else 0) := by
  induction ds with
  | nil => simp [faceWrites]
  | cons d ds ih =>
    unfold faceWrites at ih ⊢
    rw [List.flatMap_cons, List.countP_append, ih]
    simp only [List.countP_map, Function.comp_def, hS, List.length_cons]
    by_cases h : s ∈ S <;> simp [h] <;> grind

theorem stripWrites_count (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (ds : List Nat) (s : Stage) :
    (stripWrites p ℓ ds).countP (fun c => decide (s ∈ E.stagesOf c)) = ds.length * (if s ∈ S then 1 else 0) := by
  unfold stripWrites
  simp only [List.countP_map, Function.comp_def, hS]
  by_cases h : s ∈ S <;> simp [h]

theorem touched_congr (E : Engine P M) (f : FrameIn P) (w1 w2 : List (Change P))
    (hs : ∀ s, s ∈ w1.flatMap E.stagesOf ↔ s ∈ w2.flatMap E.stagesOf) (he : w1.isEmpty = w2.isEmpty)
    (s : Stage) : s ∈ touched E (withWrites f w1) ↔ s ∈ touched E (withWrites f w2) := by
  have hu : (withWrites f w1).updates = (withWrites f w2).updates := by
    have he' : (f.changes ++ w1).isEmpty = (f.changes ++ w2).isEmpty := by
      cases f.changes <;> simp [he]
    simp only [FrameIn.updates, withWrites]; rw [he']; rfl
  unfold touched
  rw [hu]
  simp only [withWrites, List.flatMap_append, List.mem_append, hs s]; exact Iff.rfl

theorem strip_passes_eq (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (f : FrameIn P) (ds : List Nat) (s : Stage) :
    (frameWork E (withWrites f (stripWrites p ℓ ds))).passes s =
      (frameWork E (withWrites f (faceWrites p ℓ ds))).passes s := by
  have h := touched_congr E f (stripWrites p ℓ ds) (faceWrites p ℓ ds)
    (fun s => by rw [stripWrites_stages E p ℓ S hS, faceWrites_stages E p ℓ S hS])
    (by rw [stripWrites_isEmpty, faceWrites_isEmpty]) s
  simp only [frameWork, forcedPasses, withWrites] at h ⊢
  by_cases ht : s ∈ touched E { f with changes := f.changes ++ faceWrites p ℓ ds } <;>
    simp_all

theorem strip_units (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (f : FrameIn P) (ds : List Nat) (s : Stage) :
    (frameWork E (withWrites f (faceWrites p ℓ ds))).units s =
      (frameWork E (withWrites f (stripWrites p ℓ ds))).units s + 9 * ds.length * (if s ∈ S then 1 else 0) := by
  simp only [frameWork, stageUnits, withWrites, List.countP_append,
    faceWrites_count E p ℓ S hS, stripWrites_count E p ℓ S hS]
  by_cases h : s ∈ S <;> simp [h] <;> omega

theorem strip_frame_le (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (f : FrameIn P) (ds : List Nat) :
    (frameWork E (withWrites f (stripWrites p ℓ ds))).le (frameWork E (withWrites f (faceWrites p ℓ ds))) := by
  refine ⟨fun s => ⟨?_, ?_⟩, Nat.le_refl _⟩
  · rw [strip_passes_eq E p ℓ S hS]; exact Nat.le_refl _
  · rw [strip_units E p ℓ S hS]; exact Nat.le_add_right _ _

theorem strip_frame_lt (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (hS0 : S ≠ []) (f : FrameIn P) (ds : List Nat) (hd : ds ≠ []) :
    (frameWork E (withWrites f (stripWrites p ℓ ds))).lt (frameWork E (withWrites f (faceWrites p ℓ ds))) := by
  refine ⟨strip_frame_le E p ℓ S hS f ds, Or.inl ?_⟩
  obtain ⟨s, hs⟩ := List.exists_mem_of_ne_nil S hS0
  refine ⟨s, Or.inr ?_⟩
  rw [strip_units E p ℓ S hS]
  have : 0 < ds.length := List.length_pos_iff.mpr hd
  simp [hs]; omega

def facesRun (E : Engine P M) (p : P) (ℓ : LayerState) (fs : List (FrameIn P × List Nat)) : List Work :=
  fs.map fun x => frameWork E (withWrites x.1 (faceWrites p ℓ x.2))

def stripRun (E : Engine P M) (p : P) (ℓ : LayerState) (fs : List (FrameIn P × List Nat)) : List Work :=
  fs.map fun x => frameWork E (withWrites x.1 (stripWrites p ℓ x.2))

def rolls (fs : List (FrameIn P × List Nat)) : Bool := fs.any fun x => !x.2.isEmpty

theorem strip_leAll (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) :
    ∀ fs : List (FrameIn P × List Nat), leAll (stripRun E p ℓ fs) (facesRun E p ℓ fs) = true
  | [] => rfl
  | x :: xs => by
    simp only [stripRun, facesRun, List.map_cons, leAll, Bool.and_eq_true]
    exact ⟨(Work.leb_iff _ _).mpr (strip_frame_le E p ℓ S hS x.1 x.2), strip_leAll E p ℓ S hS xs⟩

theorem strip_someLt (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (hS0 : S ≠ []) :
    ∀ fs : List (FrameIn P × List Nat), rolls fs = true → someLt (stripRun E p ℓ fs) (facesRun E p ℓ fs) = true
  | [], h => by cases h
  | x :: xs, h => by
    simp only [rolls, List.any_cons, Bool.or_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff] at h
    simp only [someLt, stripRun, facesRun, List.map_cons, List.zip_cons_cons, List.any_cons, Bool.or_eq_true]
    rcases h with h | h
    · left
      exact (Work.ltb_iff _ _).mpr (strip_frame_lt E p ℓ S hS hS0 x.1 x.2 h)
    · right
      exact strip_someLt E p ℓ S hS hS0 xs h

theorem strip_run_eq_of_still (E : Engine P M) (p : P) (ℓ : LayerState) :
    ∀ fs : List (FrameIn P × List Nat), rolls fs = false → stripRun E p ℓ fs = facesRun E p ℓ fs
  | [], _ => rfl
  | x :: xs, h => by
    simp only [rolls, List.any_cons, Bool.or_eq_false_iff, Bool.not_eq_false', List.isEmpty_iff] at h
    simp only [stripRun, facesRun, List.map_cons] at *
    rw [h.1]
    congr 1
    exact strip_run_eq_of_still E p ℓ xs h.2

theorem strip_claim (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (hS0 : S ≠ []) (fs : List (FrameIn P × List Nat)) (rv ro : Resident) :
    claim (Screen.screen (toRun (facesRun E p ℓ fs)) (toRun (stripRun E p ℓ fs))) rv ro =
      if rolls fs then (if rv.le ro then .dominates else .trade) else .noClaim := by
  cases hr : rolls fs
  · rw [strip_run_eq_of_still E p ℓ fs hr]
    simp [Screen.screen, Screen.shapeEq, claim]
  · simp only [ite_true]
    exact run_claim rv ro (strip_leAll E p ℓ S hS fs) (strip_someLt E p ℓ S hS hS0 fs hr)

end Work

open Fw.Engine.Chromium in
theorem cr_strip (m : CrMode) (ℓ : LayerState) (fs : List (FrameIn CrProp × List Nat)) (rv ro : Resident) :
    claim (Screen.screen (toRun (facesRun (chromiumAt m) (.css .transform) ℓ fs))
        (toRun (stripRun (chromiumAt m) (.css .transform) ℓ fs))) rv ro =
      (if rolls fs then (if rv.le ro then .dominates else .trade) else .noClaim) ∧
    ∀ (f : FrameIn CrProp) (ds : List Nat) (s : Stage),
      (frameWork (chromiumAt m) (withWrites f (stripWrites (.css .transform) ℓ ds))).passes s =
        (frameWork (chromiumAt m) (withWrites f (faceWrites (.css .transform) ℓ ds))).passes s := by
  have hS : ∀ e, (chromiumAt m).stagesOf ⟨e, .css .transform, ℓ⟩ =
      (chromiumAt m).stagesOf ⟨0, .css .transform, ℓ⟩ := fun _ => rfl
  have hS0 : (chromiumAt m).stagesOf ⟨0, .css .transform, ℓ⟩ ≠ [] := by
    cases ℓ <;> simp [chromiumAt, crStagesOf, crLevel, keyLevel, CrLevel.stages, CrProp.extra]
  exact ⟨strip_claim _ _ _ _ hS hS0 fs rv ro, strip_passes_eq _ _ _ _ hS⟩

open Fw.Engine.WebKit in
theorem wk_strip (m : WkMode) (ℓ : LayerState) (fs : List (FrameIn WkProp × List Nat)) (rv ro : Resident) :
    claim (Screen.screen (toRun (facesRun (webkitAt m) .transform ℓ fs))
        (toRun (stripRun (webkitAt m) .transform ℓ fs))) rv ro =
      (if rolls fs then (if rv.le ro then .dominates else .trade) else .noClaim) ∧
    ∀ (f : FrameIn WkProp) (ds : List Nat) (s : Stage),
      (frameWork (webkitAt m) (withWrites f (stripWrites .transform ℓ ds))).passes s =
        (frameWork (webkitAt m) (withWrites f (faceWrites .transform ℓ ds))).passes s := by
  have hS : ∀ e, (webkitAt m).stagesOf ⟨e, .transform, ℓ⟩ = (webkitAt m).stagesOf ⟨0, .transform, ℓ⟩ :=
    fun _ => rfl
  have hS0 : (webkitAt m).stagesOf ⟨0, .transform, ℓ⟩ ≠ [] := by
    simp only [webkitAt]
    cases ℓ <;> decide
  exact ⟨strip_claim _ _ _ _ hS hS0 fs rv ro, strip_passes_eq _ _ _ _ hS⟩

inductive Host where
  | chromium
  | webkit (pol : WebKit.Policy)
deriving Repr, DecidableEq

-- Chromium compositing_reason_finder.cc:116-119@f842f52 (will-change: transform is a direct reason), :535-546 (a transform needs a 3D operation)
def owns : Host → Bool → Bool
  | .chromium, wc => wc
  | .webkit pol, wc => (wc && WebKit.composites pol .willChange) || WebKit.composites pol .transform2D

theorem wk_owns (pol : WebKit.Policy) (wc : Bool) :
    owns (.webkit pol) wc = (wc && decide (pol = .normal)) := by
  cases pol <;> cases wc <;> simp [owns, WebKit.composites]

def facesResident (h : Host) (wc : Bool) (n a : Nat) : Resident :=
  if owns h wc then ⟨10 * n, 10 * n * a⟩ else ⟨0, 0⟩

def stripResident (h : Host) (wc : Bool) (n a : Nat) : Resident :=
  if owns h wc then ⟨n, 12 * n * a⟩ else ⟨0, 0⟩

def clockDigits (secs : Nat) : Nat :=
  ((unitsFromSeconds secs).zipIdx.map fun x => (digitPlaces (x.1 : Rat) (decide (0 < x.2))).length).sum

#guard clockDigits (remainingSeconds 1792281600000 targetMs) == 8
#guard clockDigits (remainingSeconds 1793318400000 targetMs) == 7
#guard clockDigits (10 * 86400) == 8 && clockDigits (99 * 86400 + 86399) == 8 && clockDigits (100 * 86400) == 9
#guard clockDigits 0 == 7

theorem strip_layers_lt (h : Host) (wc : Bool) (n a : Nat) (ho : owns h wc = true) (hn : 0 < n) :
    (stripResident h wc n a).layers = n ∧ n < 10 * n ∧ (facesResident h wc n a).layers = 10 * n := by
  simp [stripResident, facesResident, ho]; omega

theorem hero_layers (h : Host) (wc : Bool) (a : Nat) (ho : owns h wc = true) :
    (facesResident h wc 8 a).layers = 80 ∧ (stripResident h wc 8 a).layers = 8 ∧
      (stripResident h wc 8 a).layers ≤ 16 := by
  simp [stripResident, facesResident, ho]

theorem strip_backing_gt (h : Host) (wc : Bool) (n a : Nat) (ho : owns h wc = true) (hn : 0 < n) (ha : 0 < a) :
    (facesResident h wc n a).backingKpx = 10 * n * a ∧ 10 * n * a < 12 * n * a ∧
      (stripResident h wc n a).backingKpx = 12 * n * a := by
  simp only [stripResident, facesResident, ho, ite_true, true_and, and_true]
  have : 0 < n * a := Nat.mul_pos hn ha
  rw [Nat.mul_assoc, Nat.mul_assoc]; omega

theorem strip_label_fullLayer (h : Host) (wc : Bool) (n a : Nat) (ho : owns h wc = true) (hn : 0 < n)
    (ha : 0 < a) :
    ¬ (stripResident h wc n a).le (facesResident h wc n a) ∧
      claim (.ok .dominates) (stripResident h wc n a) (facesResident h wc n a) = .trade := by
  have hb := strip_backing_gt h wc n a ho hn ha
  have hnle : ¬ (stripResident h wc n a).le (facesResident h wc n a) := by
    intro hle; have := hle.2; omega
  exact ⟨hnle, by simp [claim, hnle]⟩

theorem uncomposited_same (h : Host) (wc : Bool) (n a : Nat) (ho : owns h wc = false) :
    stripResident h wc n a = ⟨0, 0⟩ ∧ facesResident h wc n a = ⟨0, 0⟩ ∧
      claim (.ok .dominates) (stripResident h wc n a) (facesResident h wc n a) = .dominates := by
  simp [stripResident, facesResident, ho, claim, Resident.le]

theorem wk_conservative_same (wc : Bool) (n a : Nat) :
    stripResident (.webkit .conservative) wc n a = ⟨0, 0⟩ ∧
      facesResident (.webkit .conservative) wc n a = ⟨0, 0⟩ :=
  let h := uncomposited_same (.webkit .conservative) wc n a (by rw [wk_owns]; simp)
  ⟨h.1, h.2.1⟩

theorem paused_same (h : Host) (n a : Nat) :
    stripResident h false n a = ⟨0, 0⟩ ∧ facesResident h false n a = ⟨0, 0⟩ := by
  have ho : owns h false = false := by
    cases h with
    | chromium => rfl
    | webkit pol => rw [wk_owns]; simp
  exact ⟨(uncomposited_same h false n a ho).1, (uncomposited_same h false n a ho).2.1⟩

theorem wk_normal_layers (a : Nat) :
    (facesResident (.webkit .normal) true 8 a).layers = 80 ∧
      (stripResident (.webkit .normal) true 8 a).layers = 8 := by
  have := hero_layers (.webkit .normal) true a (by rw [wk_owns]; rfl)
  exact ⟨this.1, this.2.1⟩

def layersPred (v o : Nat) : String := if v < o then "<o" else if v = o then "=o" else "any"

#guard layersPred 8 80 == "<o" && layersPred 0 0 == "=o" && layersPred 12 10 == "any"

def variantName : String := "rewrite+?fw=hero.countdown:strip,morph.countdown:strip"

def goldenRow (scenario : String) : String :=
  "{\"base\":\"rewrite\",\"countType\":\"census.layers\",\"engine\":\"chromium\",\"prediction\":\"" ++
    layersPred (stripResident .chromium true 8 1).layers (facesResident .chromium true 8 1).layers ++
    "\",\"scenario\":\"" ++ scenario ++ "\",\"stage\":\"comp\",\"variant\":\"" ++ variantName ++ "\"}"

/-- The golden file `packages/contracts/golden/engine/countdown-strip.jsonl`: one row per Chromium profile. -/
def goldenJsonl : String := goldenRow "swipe-v1" ++ "\n" ++ goldenRow "swipe-touch-v1" ++ "\n"

#guard (goldenJsonl.splitOn "\n").length == 3
#guard (goldenRow "swipe-v1").startsWith "{\"base\":\"rewrite\",\"countType\":\"census.layers\""
#guard ((goldenRow "swipe-v1").splitOn "\"prediction\":\"<o\"").length == 2

section EndPass

open Fw.Parts.EndFlags

theorem strip_frame_leE {P M : Type} (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (f : FrameIn P) (ds : List Nat) (e : Stage → Bool) :
    (frameWorkE E (withWrites f (stripWrites p ℓ ds)) e).le (frameWorkE E (withWrites f (faceWrites p ℓ ds)) e) :=
  frameE_le_of_same_forced E e (fun s => by cases s <;> rfl) (strip_frame_le E p ℓ S hS f ds)

theorem strip_frame_ltE {P M : Type} (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (hS0 : S ≠ []) (f : FrameIn P) (ds : List Nat) (hd : ds ≠ [])
    (e : Stage → Bool) :
    (frameWorkE E (withWrites f (stripWrites p ℓ ds)) e).lt (frameWorkE E (withWrites f (faceWrites p ℓ ds)) e) := by
  refine frameE_lt_mono E e e (fun s => by cases s <;> rfl) (strip_frame_le E p ℓ S hS f ds)
    (fun _ _ h => h) (Or.inl ?_)
  obtain ⟨s, hs⟩ := List.exists_mem_of_ne_nil S hS0
  refine ⟨s, ?_⟩
  have h := strip_units E p ℓ S hS f ds s
  have : 0 < ds.length := List.length_pos_iff.mpr hd
  simp only [frameWork, hs, ite_true] at h
  show stageUnits E _ s < stageUnits E _ s
  omega

end EndPass

section Schedule

def addScript {P : Type} (f : FrameIn P) (k : Nat) : FrameIn P := { f with script := f.script + k }

theorem sub_still_not_le {P M : Type} (E : Engine P M) (p : P) (ℓ : LayerState) (f : FrameIn P) (k : Nat)
    (hk : 0 < k) (ev eo : Stage → Bool) :
    ¬ (frameWorkE E (withWrites (addScript f k) (stripWrites p ℓ [])) ev).le
        (frameWorkE E (withWrites f (faceWrites p ℓ [])) eo) := by
  intro h
  have hu := (h.1 .script).2
  simp only [frameWorkE, stageUnits, withWrites, addScript, stripWrites, faceWrites, List.map_nil,
    List.flatMap_nil, List.append_nil, ↓reduceIte] at hu
  omega

theorem strip_still_eq {P M : Type} (E : Engine P M) (p : P) (ℓ : LayerState) (f : FrameIn P) (e : Stage → Bool) :
    frameWorkE E (withWrites (addScript f 0) (stripWrites p ℓ [])) e =
      frameWorkE E (withWrites f (faceWrites p ℓ [])) e := by
  simp [addScript, stripWrites, faceWrites]

theorem same_run_noClaim (ws : List Work) (rv ro : Resident) :
    claim (Screen.screen (toRun ws) (toRun ws)) rv ro = .noClaim :=
  resident_only_noClaim ws ws rv ro rfl

end Schedule

end Fw.Parts.HeroCountdownOpt
