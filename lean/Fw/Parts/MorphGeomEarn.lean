import Fw.Parts.MorphGeomRect
import Fw.Parts.NavEarnOpt
import Fw.Parts.NavEarnWebkit
/-! `morph.geom:on`: the earn button and the language switch on 60 Hz time tracks, per engine. -/
namespace Fw.Parts.MorphGeom
open Fw.Parts.Nav Fw.Parts.MorphTween Fw.Engine.TransitionStart Fw.Parts.NavEarnWebkit
open Fw.Parts.NavEarnOpt (shown maxWTr padTr opacityTr faithfulOn frameTime frameMs frames morphAt)

theorem eval_grid (f : Rat → Rat) (h : Rat) (hh : 0 < h) :
    ∀ (n : Nat) (P : Rat) (k : Nat), k ≤ n →
      Track.eval (mk f (gridFrom P h n)) (P + (k : Rat) * h) = f (P + (k : Rat) * h) := by
  intro n
  induction n with
  | zero => intro P k hk; have : k = 0 := by omega
            subst this; simp [gridFrom, mk, Track.eval, Rat.add_zero]
  | succ n ih =>
    intro P k hk
    have hc := gridFrom_cons (P + h) h n
    have e : gridFrom P h (n + 1) = P :: (P + h) :: List.tail (gridFrom (P + h) h n) := by
      simp only [gridFrom]; rw [← hc]
    rw [e, eval_mk_cons]
    cases k with
    | zero =>
      have : P + ((0 : Nat) : Rat) * h ≤ P + h := by simp; grind
      simp only [this, ite_true, chord]; simp; grind
    | succ k =>
      by_cases hm : P + ((k + 1 : Nat) : Rat) * h ≤ P + h
      · have hk0 : k = 0 := by
          refine Classical.byContradiction fun hne => ?_
          have : (1 : Rat) ≤ (k : Rat) := by exact_mod_cast Nat.one_le_iff_ne_zero.mpr hne
          push_cast at hm
          have := Rat.mul_le_mul_of_nonneg_right this (Rat.le_of_lt hh)
          grind
        subst hk0
        simp only [hm, ite_true, chord]
        have : P + ((0 + 1 : Nat) : Rat) * h = P + h := by simp
        rw [this]
        have : h ≠ 0 := by grind
        have : P + h - P ≠ 0 := by grind
        grind
      · simp only [hm, ite_false]
        rw [← hc]
        have := ih (P + h) k (by omega)
        have e2 : P + h + (k : Rat) * h = P + ((k + 1 : Nat) : Rat) * h := by push_cast; grind
        rw [e2] at this
        exact this

/-- Frame index of a time on the 60 Hz grid. -/
def idx (t : Rat) : Nat := (t / frameMs).floor.toNat

theorem idx_frame (k : Nat) : idx (frameTime k) = k := by
  unfold idx frameTime frameMs
  have : (k : Rat) * (50 / 3) / (50 / 3) = (k : Rat) := by grind
  rw [this, ← Rat.intCast_natCast, Rat.floor_intCast]
  simp

/-- Time track of a per-frame sequence `g`, knots every frame of the 60 Hz grid. -/
def timeTrack (g : Nat → Rat) : Track := mk (fun t => g (idx t)) (gridFrom 0 frameMs frames)

theorem timeTrack_eq (g : Nat → Rat) (k : Nat) (hk : k ≤ frames) :
    Track.eval (timeTrack g) (frameTime k) = g k := by
  unfold timeTrack
  have hh : (0 : Rat) < frameMs := by unfold frameMs; grind
  have e : frameTime k = 0 + (k : Rat) * frameMs := by unfold frameTime; grind
  rw [e, eval_grid _ frameMs hh frames 0 k hk, ← e, idx_frame]

/-! ## The original, frame by frame -/

/-- Whether the engine starts the earn button's padding transition (`NavEarnWebkit.hero_exit_webkit`). -/
def padRuns (e : Eng) : Bool := (startedSet e .ltr faithfulBase flipChanged).contains .paddingLeft

theorem padRuns_webkit : padRuns .webkit = false := by decide
theorem padRuns_chromium : padRuns .chromium = true := by decide

/-- Shown `max-width` at frame `k` of a push from `a` to `b`. -/
def maxWF (v : Vp) (a b : Rat) (k : Nat) : Rat :=
  shown maxWTr frameTime (fun j => earnMaxW v false (morphAt a b j)) faithfulOn k

/-- Shown `padding-inline` at frame `k`: transitioned where the engine starts it, else the computed value. -/
def padF (e : Eng) (v : Vp) (a b : Rat) (k : Nat) : Rat :=
  if padRuns e then shown padTr frameTime (fun j => earnPad v false (morphAt a b j)) faithfulOn k
  else earnPad v false (morphAt a b k)

/-- Shown opacity at frame `k`. -/
def opF (a b : Rat) (k : Nat) : Rat :=
  shown opacityTr frameTime (fun j => earnOpacity false (morphAt a b j)) faithfulOn k

/-- Border-box width of the earn button with a label `lw` wide: padding is never squeezed. -/
def boxW (maxW pad lw : Rat) : Rat := max (2 * pad) (min maxW (lw + 2 * pad))

def earnWF (e : Eng) (v : Vp) (lw a b : Rat) (k : Nat) : Rat := boxW (maxWF v a b k) (padF e v a b k) lw

/-! ## The flip layers -/

/-- Knots of the tracks that follow `earnOut` (`darkCut` = 0.2). -/
def earnKnots : List Rat := [0, 1 / 5, 1]

/-- Earn clip door: x translate `w0 - w(t)` over a button laid out `w0` wide. -/
def kLTrack (e : Eng) (v : Vp) (lw w0 a b : Rat) : Track := timeTrack fun k => w0 - earnWF e v lw a b k

def opTrack (a b : Rat) : Track := timeTrack (opF a b)

/-- Label padding term: a time track where the engine runs the padding transition, an m-track where it does not. -/
def padG (e : Eng) (v : Vp) (a b : Rat) (k : Nat) : Rat :=
  if padRuns e then Track.eval (timeTrack (padF e v a b)) (frameTime k)
  else Track.eval (mk (earnPad v false) earnKnots) (morphAt a b k)

/-- Earn box edges `[R - w0 + kL, R]`: the clip door over the laid-out button `[R - w0, R]`. -/
def clipEdges (R w0 kL : Rat) : Rat × Rat := (max (R - w0) (R - w0 + kL), min R (R + kL))

theorem earn_edges (R w0 w : Rat) (h0 : 0 ≤ w) (h1 : w ≤ w0) : clipEdges R w0 (w0 - w) = (R - w, R) := by
  unfold clipEdges; simp only [Prod.mk.injEq]; constructor <;> grind

theorem morphAt_mem (a b : Rat) (ha : 0 ≤ a ∧ a ≤ 1) (hb : 0 ≤ b ∧ b ≤ 1) (k : Nat) :
    0 ≤ morphAt a b k ∧ morphAt a b k ≤ 1 := by
  have := MorphTween.tween_between a b (frameTime k)
  unfold morphAt; grind

theorem earnPad_pw (v : Vp) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    Track.eval (mk (earnPad v false) earnKnots) m = earnPad v false m := by
  obtain ⟨c, hc⟩ : ∃ c : Rat, ∀ x, earnPad v false x = (1 - clamp01 (x / darkCut)) * c :=
    ⟨if phone v.w then 16 else 24, fun x => by unfold earnPad earnLayout earnOut expand; simp⟩
  exact pw_aff2 _ _ (by grind) ⟨c, -5 * c, fun x _ _ => by
    rw [hc]; unfold clamp01 darkCut; by_cases hx : x = 1 / 5
    · subst hx; grind
    · grind⟩
    ⟨0, 0, fun x _ _ => by rw [hc]; unfold clamp01 darkCut; grind⟩ m h0 h1

theorem earnOut_pw (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    Track.eval (mk earnOut earnKnots) m = earnOut m :=
  pw_aff2 _ _ (by grind) ⟨0, 5, fun x _ _ => by unfold earnOut clamp01 darkCut; grind⟩
    ⟨1, 0, fun x _ _ => by unfold earnOut clamp01 darkCut; grind⟩ m h0 h1

theorem earnBlur_pw (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    Track.eval (mk earnBlur earnKnots) m = earnBlur m :=
  pw_aff2 _ _ (by grind) ⟨0, 50, fun x _ _ => by unfold earnBlur earnOut clamp01 darkCut; grind⟩
    ⟨10, 0, fun x _ _ => by unfold earnBlur earnOut clamp01 darkCut; grind⟩ m h0 h1

theorem earnShift_pw (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    Track.eval (mk earnShift earnKnots) m = earnShift m :=
  pw_aff2 _ _ (by grind) ⟨0, -40, fun x _ _ => by unfold earnShift earnOut clamp01 darkCut; grind⟩
    ⟨-8, 0, fun x _ _ => by unfold earnShift earnOut clamp01 darkCut; grind⟩ m h0 h1

theorem actionsGap_pw (v : Vp) (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) :
    Track.eval (mk (actionsGap v false) earnKnots) m = actionsGap v false m := by
  obtain ⟨c, hc⟩ : ∃ c : Rat, ∀ x, actionsGap v false x = (1 - clamp01 (x / darkCut)) * c :=
    ⟨if phone v.w then 4 else 8, fun x => by unfold actionsGap earnOut expand; simp⟩
  exact pw_aff2 _ _ (by grind) ⟨c, -5 * c, fun x _ _ => by
    rw [hc]; unfold clamp01 darkCut; by_cases hx : x = 1 / 5
    · subst hx; grind
    · grind⟩
    ⟨0, 0, fun x _ _ => by rw [hc]; unfold clamp01 darkCut; grind⟩ m h0 h1

/-- Language switch right edge in the original: left of the earn box and the gap. -/
def langRightF (e : Eng) (v : Vp) (R lw a b : Rat) (k : Nat) : Rat :=
  R - earnWF e v lw a b k - actionsGap v false (morphAt a b k)

/-- Language switch right edge under the flip: laid out next to a `w0` button with gap `gL`, moved by the
`transform` (earn width) and `translate` (gap) tracks. -/
def langRightG (e : Eng) (v : Vp) (R lw w0 gL a b : Rat) (k : Nat) : Rat :=
  R - w0 - gL + Track.eval (kLTrack e v lw w0 a b) (frameTime k) +
    (gL - Track.eval (mk (actionsGap v false) earnKnots) (morphAt a b k))

/-- On the 60 Hz grid the earn and language tracks equal the engine's run of the original: box edges, label
padding, opacity, blur, shift and the language switch edge. -/
theorem earn_eq (e : Eng) (v : Vp) (R lw w0 gL a b : Rat) (ha : 0 ≤ a ∧ a ≤ 1) (hb : 0 ≤ b ∧ b ≤ 1)
    (k : Nat) (hk : k ≤ frames) (hw0 : 0 ≤ earnWF e v lw a b k) (hw1 : earnWF e v lw a b k ≤ w0) :
    clipEdges R w0 (Track.eval (kLTrack e v lw w0 a b) (frameTime k)) = (R - earnWF e v lw a b k, R) ∧
      padG e v a b k = padF e v a b k ∧
      Track.eval (opTrack a b) (frameTime k) = opF a b k ∧
      Track.eval (mk earnBlur earnKnots) (morphAt a b k) = earnBlur (morphAt a b k) ∧
      Track.eval (mk earnShift earnKnots) (morphAt a b k) = earnShift (morphAt a b k) ∧
      langRightG e v R lw w0 gL a b k = langRightF e v R lw a b k := by
  have hm := morphAt_mem a b ha hb k
  have ek : Track.eval (kLTrack e v lw w0 a b) (frameTime k) = w0 - earnWF e v lw a b k := by
    unfold kLTrack; exact timeTrack_eq _ k hk
  refine ⟨by rw [ek]; exact earn_edges R w0 _ hw0 hw1, ?_, timeTrack_eq _ k hk, earnBlur_pw _ hm.1 hm.2,
    earnShift_pw _ hm.1 hm.2, ?_⟩
  · unfold padG
    split
    · exact timeTrack_eq _ k hk
    · rename_i h
      rw [earnPad_pw v _ hm.1 hm.2]
      unfold padF; simp [h]
  · unfold langRightG langRightF
    rw [ek, actionsGap_pw v _ hm.1 hm.2]
    grind

theorem earn_eq_webkit (v : Vp) (a b : Rat) (k : Nat) : padF .webkit v a b k = earnPad v false (morphAt a b k) := by
  unfold padF; simp [padRuns_webkit]

theorem earn_eq_chromium (v : Vp) (a b : Rat) (k : Nat) :
    padF .chromium v a b k = shown padTr frameTime (fun j => earnPad v false (morphAt a b j)) faithfulOn k := by
  unfold padF; simp [padRuns_chromium]

end Fw.Parts.MorphGeom
