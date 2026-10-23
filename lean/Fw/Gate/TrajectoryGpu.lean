import Lean.Data.Json
import Fw.Gate.PathPix
import Fw.Parts.MorphPanel
/-!
# GPU trajectory cells: clip rect, matched cell, panel lag, pain flip, carousel swaps
Spec of the reducers in `packages/gate-breakpoints/src/trajectory/cells-gpu.mjs`, checked against `golden/gate/trajectory-gpu.jsonl`.
-/
namespace Fw.Gate.TrajectoryGpu
open Lean
open Fw.Gate.PathPix (Grade)
open Fw.Parts.MorphPanel (panelOpacity panelBlurPx panelScale)

def PixTol : Rat := 1 / 2

def tolCss (dpr : Rat) : Rat := PixTol / dpr

theorem tolCss_device (dpr : Rat) (h : 0 < dpr) : tolCss dpr * dpr = PixTol := by
  unfold tolCss
  rw [Rat.div_mul_cancel (by grind)]

def Within (t x y : Rat) : Prop := x - t ≤ y ∧ y ≤ x + t

instance (t x y : Rat) : Decidable (Within t x y) := inferInstanceAs (Decidable (_ ∧ _))

def cellEq : List Rat → List Rat → List Rat → Bool
  | [], [], [] => true
  | t :: ts, x :: xs, y :: ys => decide (Within t x y) && cellEq ts xs ys
  | _, _, _ => false

def CellEq : List Rat → List Rat → List Rat → Prop
  | [], [], [] => True
  | t :: ts, x :: xs, y :: ys => Within t x y ∧ CellEq ts xs ys
  | _, _, _ => False

theorem cell_eq_iff (ts a b : List Rat) : cellEq ts a b = true ↔ CellEq ts a b := by
  induction ts generalizing a b with
  | nil => cases a <;> cases b <;> simp [cellEq, CellEq]
  | cons t ts ih => cases a <;> cases b <;> simp [cellEq, CellEq, ih]

theorem cellEq_refl (ts a : List Rat) (hl : a.length = ts.length) (hn : ∀ t ∈ ts, 0 ≤ t) : cellEq ts a a = true := by
  induction ts generalizing a with
  | nil => cases a <;> simp_all [cellEq]
  | cons t ts ih =>
    cases a with
    | nil => simp at hl
    | cons x xs =>
      have h0 : 0 ≤ t := hn t (by simp)
      simp only [cellEq, Bool.and_eq_true, decide_eq_true_eq]
      refine ⟨by unfold Within; grind, ih xs (by simpa using hl) (fun u hu => hn u (by simp [hu]))⟩

theorem cellEq_symm (ts a b : List Rat) : cellEq ts a b = true → cellEq ts b a = true := by
  induction ts generalizing a b with
  | nil => cases a <;> cases b <;> simp [cellEq]
  | cons t ts ih =>
    cases a <;> cases b <;> simp only [cellEq, Bool.and_eq_true, decide_eq_true_eq, Bool.false_eq_true, imp_self]
    rename_i x xs y ys
    intro h
    exact ⟨by unfold Within at h ⊢; grind, ih xs ys h.2⟩

inductive Len where
  | px (v : Rat)
  | pct (v : Rat)
  deriving DecidableEq, Repr

def Len.resolve : Len → Rat → Rat
  | .px v, _ => v
  | .pct v, side => v * side / 100

structure Box where
  x : Rat
  y : Rat
  w : Rat
  h : Rat
  deriving DecidableEq, Repr

structure Shape where
  rect : Box
  r : Rat
  deriving DecidableEq, Repr

structure Inset where
  top : Len
  right : Len
  bottom : Len
  left : Len
  radii : Option (Len × Len × Len × Len)
  deriving DecidableEq, Repr

def expand4 {α : Type} : List α → Option (α × α × α × α)
  | [a] => some (a, a, a, a)
  | [a, b] => some (a, b, a, b)
  | [a, b, c] => some (a, b, c, b)
  | [a, b, c, d] => some (a, b, c, d)
  | _ => none

theorem expand4_one {α : Type} (a : α) : expand4 [a] = some (a, a, a, a) := rfl
theorem expand4_two {α : Type} (a b : α) : expand4 [a, b] = some (a, b, a, b) := rfl
theorem expand4_three {α : Type} (a b c : α) : expand4 [a, b, c] = some (a, b, c, b) := rfl
theorem expand4_four {α : Type} (a b c d : α) : expand4 [a, b, c, d] = some (a, b, c, d) := rfl
theorem expand4_none {α : Type} (xs : List α) (h : xs.length = 0 ∨ 5 ≤ xs.length) : expand4 xs = none := by
  match xs, h with
  | [], _ => rfl
  | _ :: _ :: _ :: _ :: _ :: _, _ => rfl

def usedRadius (r w h : Rat) : Rat := min r (min (w / 2) (h / 2))

theorem usedRadius_of_fits (r w h : Rat) (h1 : r ≤ w / 2) (h2 : r ≤ h / 2) : usedRadius r w h = r := by
  unfold usedRadius; grind

theorem usedRadius_le (r w h : Rat) : usedRadius r w h ≤ w / 2 ∧ usedRadius r w h ≤ h / 2 := by
  unfold usedRadius; grind

def shapeOfBox (b : Box) (r : Rat) : Shape := ⟨b, usedRadius r b.w b.h⟩

def insetRect (box : Box) (i : Inset) : Box :=
  let l := i.left.resolve box.w
  let rt := i.right.resolve box.w
  let t := i.top.resolve box.h
  let bt := i.bottom.resolve box.h
  ⟨box.x + l, box.y + t, max 0 (box.w - l - rt), max 0 (box.h - t - bt)⟩

def radiusShape (rect : Box) : Option (Len × Len × Len × Len) → Option Shape
  | none => some ⟨rect, 0⟩
  | some (tl, tr, br, bl) =>
    let rx (c : Len) := c.resolve rect.w
    let ry (c : Len) := c.resolve rect.h
    if [tl, tr, br, bl].all (fun c => rx c == rx tl && ry c == rx tl) then some (shapeOfBox rect (rx tl)) else none

def clipRect_of_inset (box : Box) (i : Inset) : Option Shape := radiusShape (insetRect box i) i.radii

theorem max_zero_of_nonneg (v : Rat) (h : 0 ≤ v) : max 0 v = v := by
  rw [Rat.max_def]; grind

theorem insetRect_zero (box : Box) (radii : Option (Len × Len × Len × Len)) (hw : 0 ≤ box.w) (hh : 0 ≤ box.h) :
    insetRect box ⟨.px 0, .px 0, .px 0, .px 0, radii⟩ = box := by
  obtain ⟨x, y, w, h⟩ := box
  have e1 : w - 0 - 0 = w := by grind
  have e2 : h - 0 - 0 = h := by grind
  have e3 : x + 0 = x := by grind
  have e4 : y + 0 = y := by grind
  simp only [insetRect, Len.resolve, e1, e2, e3, e4, max_zero_of_nonneg w hw, max_zero_of_nonneg h hh]

theorem clip_no_inset (box : Box) (hw : 0 ≤ box.w) (hh : 0 ≤ box.h) :
    clipRect_of_inset box ⟨.px 0, .px 0, .px 0, .px 0, none⟩ = some ⟨box, 0⟩ := by
  unfold clipRect_of_inset
  rw [insetRect_zero box none hw hh]
  rfl

theorem clip_round_eq_border_box (box : Box) (r : Rat) (hw : 0 ≤ box.w) (hh : 0 ≤ box.h) :
    clipRect_of_inset box ⟨.px 0, .px 0, .px 0, .px 0, some (.px r, .px r, .px r, .px r)⟩ = some (shapeOfBox box r) := by
  unfold clipRect_of_inset
  rw [insetRect_zero box _ hw hh]
  simp [radiusShape, Len.resolve]

theorem clip_roundtrip (u p : Box) (hpw : 0 ≤ p.w) (hph : 0 ≤ p.h) :
    clipRect_of_inset u ⟨.px (p.y - u.y), .px (u.x + u.w - p.x - p.w), .px (u.y + u.h - p.y - p.h), .px (p.x - u.x), none⟩ =
      some ⟨p, 0⟩ := by
  obtain ⟨ux, uy, uw, uh⟩ := u
  obtain ⟨px, py, pw, ph⟩ := p
  have e1 : uw - (px - ux) - (ux + uw - px - pw) = pw := by grind
  have e2 : uh - (py - uy) - (uy + uh - py - ph) = ph := by grind
  have e3 : ux + (px - ux) = px := by grind
  have e4 : uy + (py - uy) = py := by grind
  simp only [clipRect_of_inset, insetRect, Len.resolve, radiusShape, e1, e2, e3, e4, max_zero_of_nonneg pw hpw,
    max_zero_of_nonneg ph hph]

theorem clip_nonuniform (rect : Box) (a b c d : Len)
    (hne : b.resolve rect.w ≠ a.resolve rect.w ∨ b.resolve rect.h ≠ a.resolve rect.w) :
    radiusShape rect (some (a, b, c, d)) = none := by
  simp only [radiusShape, List.all_cons, List.all_nil, Bool.and_true, Bool.and_eq_true, beq_iff_eq]
  rw [ite_eq_right_iff]
  intro h
  grind

def digitsVal (cs : List Char) : Option Nat :=
  if cs.isEmpty then none
  else cs.foldlM (fun acc c => if c.isDigit then some (acc * 10 + (c.toNat - 48)) else none) 0

def parseDec (s : String) : Option Rat :=
  let (neg, cs) := match s.toList with
    | '-' :: r => (true, r)
    | '+' :: r => (false, r)
    | l => (false, l)
  let ip := cs.takeWhile (· != '.')
  let sign (r : Rat) : Rat := if neg then -r else r
  match cs.drop ip.length with
  | [] => (digitsVal ip).map fun n => sign n
  | '.' :: fr => do
    let i ← if ip.isEmpty then some 0 else digitsVal ip
    let f ← digitsVal fr
    some (sign ((i : Rat) + (f : Rat) / ((10 ^ fr.length : Nat) : Rat)))
  | _ => none

def parseLen (s : String) : Option Len :=
  if s == "0" then some (.px 0)
  else if s.endsWith "px" then (parseDec (s.dropEnd 2).toString).map .px
  else if s.endsWith "%" then (parseDec (s.dropEnd 1).toString).map .pct
  else none

def parseLens (ts : List String) : Option (List Len) := ts.mapM parseLen

def parseInset (s : String) : Option Inset :=
  let t := s.trimAscii.toString
  if t.startsWith "inset(" && t.endsWith ")" then
    let body := ((t.drop 6).dropEnd 1).toString
    let toks := (body.splitOn " ").filter (· != "")
    let sides := toks.takeWhile (· != "round")
    let rest := toks.drop sides.length
    match parseLens sides >>= expand4 with
    | none => none
    | some (t, r, b, l) =>
      match rest with
      | [] => some ⟨t, r, b, l, none⟩
      | "round" :: rs => (parseLens rs >>= expand4).map fun q => ⟨t, r, b, l, some q⟩
      | _ => none
  else none

def readShape (box : Box) (radius : Rat) (clip : String) : Option Shape :=
  if clip == "none" then some (shapeOfBox box radius)
  else (parseInset clip).bind (clipRect_of_inset box)

theorem readShape_none (box : Box) (r : Rat) : readShape box r "none" = some (shapeOfBox box r) := by
  simp [readShape]

def shapeVec (s : Shape) : List Rat := [s.rect.x, s.rect.y, s.rect.w, s.rect.h, s.r]

#guard parseDec "12" == some 12
#guard parseDec "-0.5" == some (-1 / 2)
#guard parseDec ".5" == some (1 / 2)
#guard parseDec "1e-7" == none
#guard parseDec "5." == none
#guard parseLen "0" == some (.px 0)
#guard parseLen "12.5px" == some (.px (25 / 2))
#guard parseLen "50%" == some (.pct 50)
#guard parseLen "3em" == none
#guard parseInset "inset(0px 10px round 16px)" ==
  some ⟨.px 0, .px 10, .px 0, .px 10, some (.px 16, .px 16, .px 16, .px 16)⟩
#guard parseInset "inset(calc(1px))" == none
#guard parseInset "circle(5px)" == none
#guard readShape ⟨0, 0, 100, 40⟩ 20 "inset(0px 10px round 16px)" == some ⟨⟨10, 0, 80, 40⟩, 16⟩

def absR (x : Rat) : Rat := if x < 0 then -x else x

abbrev Series := List (Rat × List Rat)

def lerpVec (f : Rat) : List Rat → List Rat → Option (List Rat)
  | [], [] => some []
  | a :: as, b :: bs => (lerpVec f as bs).map fun r => (a + (b - a) * f) :: r
  | _, _ => none

theorem lerpVec_zero (a b : List Rat) (h : a.length = b.length) : lerpVec 0 a b = some a := by
  induction a generalizing b with
  | nil => cases b <;> simp_all [lerpVec]
  | cons x xs ih =>
    cases b with
    | nil => simp at h
    | cons y ys =>
      have := ih ys (by simpa using h)
      simp only [lerpVec, this, Option.map_some, Option.some.injEq, List.cons.injEq, and_true]
      grind

theorem lerpVec_one (a b : List Rat) (h : a.length = b.length) : lerpVec 1 a b = some b := by
  induction a generalizing b with
  | nil => cases b <;> simp_all [lerpVec]
  | cons x xs ih =>
    cases b with
    | nil => simp at h
    | cons y ys =>
      have := ih ys (by simpa using h)
      simp only [lerpVec, this, Option.map_some, Option.some.injEq, List.cons.injEq, and_true]
      grind

def sortedKeys : Series → Bool
  | a :: b :: r => decide (a.1 < b.1) && sortedKeys (b :: r)
  | _ => true

def edge : Rat := 1 / 100

def interior (s : Series) : Series := s.filter fun p => decide (edge < p.1) && decide (p.1 < 1 - edge)

theorem mem_interior (s : Series) (p : Rat × List Rat) (h : p ∈ interior s) :
    p ∈ s ∧ edge < p.1 ∧ p.1 < 1 - edge := by
  simp only [interior, List.mem_filter, Bool.and_eq_true, decide_eq_true_eq] at h
  exact ⟨h.1, h.2.1, h.2.2⟩

theorem interior_mem (s : Series) (p : Rat × List Rat) (h : p ∈ s) (h1 : edge < p.1) (h2 : p.1 < 1 - edge) :
    p ∈ interior s := by
  simp only [interior, List.mem_filter, Bool.and_eq_true, decide_eq_true_eq]
  exact ⟨h, h1, h2⟩

def insertKey (p : Rat × List Rat) : Series → Series
  | [] => [p]
  | q :: r => if p.1 < q.1 then p :: q :: r else if p.1 = q.1 then q :: r else q :: insertKey p r

def seriesOf (s : Series) : Series := s.foldl (fun acc p => insertKey p acc) []

theorem sortedKeys_iff (l : Series) : sortedKeys l = true ↔ l.Pairwise (fun a b => a.1 < b.1) := by
  induction l with
  | nil => simp [sortedKeys]
  | cons a t ih =>
    cases t with
    | nil => simp [sortedKeys]
    | cons b r =>
      simp only [sortedKeys, Bool.and_eq_true, decide_eq_true_eq, ih]
      constructor
      · rintro ⟨hab, hp⟩
        refine List.pairwise_cons.2 ⟨?_, hp⟩
        intro x hx
        rcases List.mem_cons.1 hx with rfl | hx
        · exact hab
        · exact (by have := (List.pairwise_cons.1 hp).1 x hx; grind)
      · intro h
        exact ⟨(List.pairwise_cons.1 h).1 b (by simp), (List.pairwise_cons.1 h).2⟩

theorem mem_insertKey (p x : Rat × List Rat) (l : Series) (h : x ∈ insertKey p l) : x = p ∨ x ∈ l := by
  induction l with
  | nil => simpa [insertKey] using h
  | cons q r ih =>
    unfold insertKey at h
    split at h
    · simpa using h
    · split at h
      · exact Or.inr h
      · rcases List.mem_cons.1 h with rfl | h
        · simp
        · rcases ih h with h | h
          · exact Or.inl h
          · exact Or.inr (List.mem_cons_of_mem _ h)

theorem mem_insertKey_of_mem (p x : Rat × List Rat) (l : Series) (h : x ∈ l) : x ∈ insertKey p l := by
  induction l with
  | nil => simp at h
  | cons q r ih =>
    unfold insertKey
    split
    · simp [h]
    · split
      · exact h
      · rcases List.mem_cons.1 h with rfl | h
        · simp
        · exact List.mem_cons_of_mem _ (ih h)

theorem insertKey_key (p : Rat × List Rat) (l : Series) : ∃ y ∈ insertKey p l, y.1 = p.1 := by
  induction l with
  | nil => exact ⟨p, by simp [insertKey], rfl⟩
  | cons q r ih =>
    unfold insertKey
    split
    · exact ⟨p, by simp, rfl⟩
    · rename_i h
      split
      · rename_i h2
        exact ⟨q, by simp, h2.symm⟩
      · obtain ⟨y, hy, hk⟩ := ih
        exact ⟨y, List.mem_cons_of_mem _ hy, hk⟩

theorem insertKey_pairwise (p : Rat × List Rat) (l : Series) (h : l.Pairwise (fun a b => a.1 < b.1)) :
    (insertKey p l).Pairwise (fun a b => a.1 < b.1) := by
  induction l with
  | nil => simp [insertKey]
  | cons q r ih =>
    obtain ⟨hq, hr⟩ := List.pairwise_cons.1 h
    unfold insertKey
    split
    · rename_i hlt
      refine List.pairwise_cons.2 ⟨?_, h⟩
      intro x hx
      rcases List.mem_cons.1 hx with rfl | hx
      · exact hlt
      · exact (by have := hq x hx; grind)
    · split
      · exact h
      · rename_i hn1 hn2
        refine List.pairwise_cons.2 ⟨?_, ih hr⟩
        intro x hx
        rcases mem_insertKey p x r hx with rfl | hx
        · grind
        · exact hq x hx

theorem foldInsert_props (s acc : Series) (h : acc.Pairwise (fun a b => a.1 < b.1)) :
    (s.foldl (fun a p => insertKey p a) acc).Pairwise (fun a b => a.1 < b.1) ∧
    (∀ x ∈ s.foldl (fun a p => insertKey p a) acc, x ∈ acc ∨ x ∈ s) ∧
    (∀ x ∈ acc, x ∈ s.foldl (fun a p => insertKey p a) acc) ∧
    (∀ p ∈ s, ∃ q ∈ s.foldl (fun a p => insertKey p a) acc, q.1 = p.1) := by
  induction s generalizing acc with
  | nil => simpa using h
  | cons p t ih =>
    obtain ⟨h1, h2, h3, h4⟩ := ih (insertKey p acc) (insertKey_pairwise p acc h)
    simp only [List.foldl_cons]
    refine ⟨h1, ?_, ?_, ?_⟩
    · intro x hx
      rcases h2 x hx with hx | hx
      · rcases mem_insertKey p x acc hx with rfl | hx
        · exact Or.inr (by simp)
        · exact Or.inl hx
      · exact Or.inr (List.mem_cons_of_mem _ hx)
    · intro x hx
      exact h3 x (mem_insertKey_of_mem p x acc hx)
    · intro x hx
      rcases List.mem_cons.1 hx with rfl | hx
      · obtain ⟨y, hy, hk⟩ := insertKey_key x acc
        exact ⟨y, h3 y hy, hk⟩
      · exact h4 x hx

theorem seriesOf_sorted (s : Series) : sortedKeys (seriesOf s) = true :=
  (sortedKeys_iff _).2 (foldInsert_props s [] (by simp)).1

theorem mem_seriesOf (s : Series) (p : Rat × List Rat) (h : p ∈ seriesOf s) : p ∈ s := by
  rcases (foldInsert_props s [] (by simp)).2.1 p h with h | h
  · simp at h
  · exact h

theorem seriesOf_keys (s : Series) (p : Rat × List Rat) (h : p ∈ s) : ∃ q ∈ seriesOf s, q.1 = p.1 :=
  (foldInsert_props s [] (by simp)).2.2.2 p h

def interpAt : Series → Rat → Option (List Rat)
  | (k0, v0) :: (k1, v1) :: rest, k =>
    if k < k0 then none
    else if k ≤ k1 then (if k0 < k1 then lerpVec ((k - k0) / (k1 - k0)) v0 v1 else none)
    else interpAt ((k1, v1) :: rest) k
  | [(k0, v0)], k => if k == k0 then some v0 else none
  | [], _ => none

theorem interp_below (k0 k : Rat) (v : List Rat) (t : Series) (h : k < k0) : interpAt ((k0, v) :: t) k = none := by
  cases t with
  | nil => simp [interpAt]; grind
  | cons p r => obtain ⟨k1, v1⟩ := p; simp [interpAt, h]

theorem interp_first_key (k0 k1 : Rat) (v0 v1 : List Rat) (t : Series) (hk : k0 < k1) (hl : v0.length = v1.length) :
    interpAt ((k0, v0) :: (k1, v1) :: t) k0 = some v0 := by
  have h1 : ¬ k1 < k0 := by grind
  have h2 : k0 ≤ k1 := by grind
  have h0 : (k0 - k0) / (k1 - k0) = 0 := by rw [Rat.sub_self, Rat.div_def, Rat.zero_mul]
  simp [interpAt, hk, h2, h0, lerpVec_zero v0 v1 hl]

def matchStep (tols : List Rat) (ref : Series) (shift : Rat) (acc : Nat × Bool) (p : Rat × List Rat) : Nat × Bool :=
  match interpAt ref (p.1 + shift) with
  | some r => (acc.1 + 1, acc.2 && cellEq tols r p.2)
  | none => acc

def matchAt (tols : List Rat) (ref cand : Series) (shift : Rat) : Nat × Bool :=
  cand.foldl (matchStep tols ref shift) (0, true)

theorem matchAt_ok_of_all (tols : List Rat) (ref cand : Series) (shift : Rat)
    (h : ∀ p ∈ cand, ∀ r, interpAt ref (p.1 + shift) = some r → cellEq tols r p.2 = true) :
    (matchAt tols ref cand shift).2 = true := by
  have key : ∀ (cs : Series) (acc : Nat × Bool), acc.2 = true →
      (∀ p ∈ cs, ∀ r, interpAt ref (p.1 + shift) = some r → cellEq tols r p.2 = true) →
      (cs.foldl (matchStep tols ref shift) acc).2 = true := by
    intro cs
    induction cs with
    | nil => intro acc ha _; exact ha
    | cons p rest ih =>
      intro acc ha hp
      apply ih
      · unfold matchStep
        split
        · rename_i r hr
          simp [ha, hp p (by simp) r hr]
        · exact ha
      · intro q hq; exact hp q (by simp [hq])
  exact key cand (0, true) rfl h

def matchedGrade (tols grid : List Rat) (frameKey : Rat) (minCovered : Nat) (ref cand : Series) : Option Grade :=
  if !sortedKeys ref || !sortedKeys cand || (matchAt tols ref cand 0).1 < minCovered then none
  else if (matchAt tols ref cand 0).2 then some .e
  else if grid.any (fun s => s != 0 && decide (absR s ≤ 1) &&
      decide (minCovered ≤ (matchAt tols ref cand (s * frameKey)).1) && (matchAt tols ref cand (s * frameKey)).2)
  then some .q else some .l

theorem matched_unsorted_ref (tols grid : List Rat) (fk : Rat) (n : Nat) (ref cand : Series)
    (h : sortedKeys ref = false) : matchedGrade tols grid fk n ref cand = none := by
  simp [matchedGrade, h]

theorem matched_under_covered (tols grid : List Rat) (fk : Rat) (n : Nat) (ref cand : Series)
    (h : (matchAt tols ref cand 0).1 < n) : matchedGrade tols grid fk n ref cand = none := by
  simp [matchedGrade, h]

theorem matched_e (tols grid : List Rat) (fk : Rat) (n : Nat) (ref cand : Series)
    (hr : sortedKeys ref = true) (hc : sortedKeys cand = true) (hn : n ≤ (matchAt tols ref cand 0).1)
    (hm : (matchAt tols ref cand 0).2 = true) : matchedGrade tols grid fk n ref cand = some .e := by
  have : ¬ (matchAt tols ref cand 0).1 < n := by grind
  simp [matchedGrade, hr, hc, this, hm]

theorem matched_l (tols grid : List Rat) (fk : Rat) (n : Nat) (ref cand : Series)
    (hr : sortedKeys ref = true) (hc : sortedKeys cand = true) (hn : n ≤ (matchAt tols ref cand 0).1)
    (hm : (matchAt tols ref cand 0).2 = false)
    (hg : grid.any (fun s => s != 0 && decide (absR s ≤ 1) &&
      decide (n ≤ (matchAt tols ref cand (s * fk)).1) && (matchAt tols ref cand (s * fk)).2) = false) :
    matchedGrade tols grid fk n ref cand = some .l := by
  have : ¬ (matchAt tols ref cand 0).1 < n := by grind
  simp [matchedGrade, hr, hc, this, hm, hg]

theorem matched_q (tols grid : List Rat) (fk : Rat) (n : Nat) (ref cand : Series)
    (hr : sortedKeys ref = true) (hc : sortedKeys cand = true) (hn : n ≤ (matchAt tols ref cand 0).1)
    (hm : (matchAt tols ref cand 0).2 = false)
    (hg : grid.any (fun s => s != 0 && decide (absR s ≤ 1) &&
      decide (n ≤ (matchAt tols ref cand (s * fk)).1) && (matchAt tols ref cand (s * fk)).2) = true) :
    matchedGrade tols grid fk n ref cand = some .q := by
  have : ¬ (matchAt tols ref cand 0).1 < n := by grind
  simp [matchedGrade, hr, hc, this, hm, hg]

def effectAt (m : Rat) : List Rat := [panelOpacity m, panelBlurPx m, panelScale m]

def readStep : Rat := 1 / 1000

def effectTols (dpr side : Rat) : List Rat := [1 / 100, tolCss dpr, tolCss dpr / side + readStep]

def residual (s : Series) : Series := s.map fun (k, v) => (k, List.zipWith (· - ·) v (effectAt k))

theorem residual_sorted (s : Series) : sortedKeys (residual s) = sortedKeys s := by
  have h : (residual s).Pairwise (fun a b => a.1 < b.1) ↔ s.Pairwise (fun a b => a.1 < b.1) := by
    simp only [residual, List.pairwise_map]
  exact Bool.eq_iff_iff.2 ((sortedKeys_iff _).trans (h.trans (sortedKeys_iff _).symm))

theorem residual_model (k : Rat) : List.zipWith (· - ·) (effectAt k) (effectAt k) = [0, 0, 0] := by
  simp [effectAt, Rat.sub_self]

def ZeroSeries (s : Series) : Prop := ∀ p ∈ s, p.2 = [0, 0, 0]

theorem residual_zero (s : Series) (h : ∀ p ∈ s, p.2 = effectAt p.1) : ZeroSeries (residual s) := by
  intro q hq
  simp only [residual, List.mem_map] at hq
  obtain ⟨p, hp, rfl⟩ := hq
  simp only [h p hp]
  exact residual_model p.1

theorem interpAt_zero (s : Series) (hs : ZeroSeries s) (k : Rat) (r : List Rat) (h : interpAt s k = some r) :
    r = [0, 0, 0] := by
  induction s with
  | nil => simp [interpAt] at h
  | cons p t ih =>
    obtain ⟨k0, v0⟩ := p
    have h0 : v0 = [0, 0, 0] := hs (k0, v0) (by simp)
    cases t with
    | nil =>
      simp only [interpAt] at h
      split at h
      · simp only [Option.some.injEq] at h; rw [← h, h0]
      · simp at h
    | cons q t' =>
      obtain ⟨k1, v1⟩ := q
      have h1 : v1 = [0, 0, 0] := hs (k1, v1) (by simp)
      have hrest : ZeroSeries ((k1, v1) :: t') := fun x hx => hs x (by simp_all)
      simp only [interpAt] at h
      split at h
      · simp at h
      · split at h
        · split at h
          · simp only [h0, h1, lerpVec, Option.map_some, Option.some.injEq] at h
            rw [← h]
            simp [Rat.sub_self, Rat.zero_mul, Rat.add_zero]
          · simp at h
        · exact ih hrest h

def effClock (p : Rat) : Rat := 2 / 25 + 18 / 25 * p

theorem effClock_opacity (m : Rat) (h0 : 2 / 25 ≤ m) (h1 : m ≤ 4 / 5) : effClock (panelOpacity m) = m := by
  have hp : Fw.Parts.MorphPanel.panelProgress m = (m - 2 / 25) / (18 / 25) := by
    unfold Fw.Parts.MorphPanel.panelProgress Fw.Parts.MorphPanel.clamp01
    have a : 0 ≤ (m - 2 / 25) / (18 / 25) := by grind
    have b : (m - 2 / 25) / (18 / 25) ≤ 1 := by grind
    rw [Rat.min_def, Rat.max_def]; grind
  unfold effClock panelOpacity
  rw [hp]
  grind

structure LagFrame where
  nav : Rat
  op : Rat
  deriving DecidableEq, Repr

def lagAt (prev cur : LagFrame) : Option Rat :=
  if 0 < cur.op && cur.op < 1 && prev.nav != cur.nav then some ((cur.nav - effClock cur.op) / (cur.nav - prev.nav))
  else none

theorem lagAt_sync (prev cur : LagFrame) (h0 : 0 < cur.op) (h1 : cur.op < 1) (hn : prev.nav ≠ cur.nav)
    (hs : cur.nav = effClock cur.op) : lagAt prev cur = some 0 := by
  have : (cur.nav - effClock cur.op) = 0 := by grind
  have hz : (0 : Rat) / (cur.nav - prev.nav) = 0 := by rw [Rat.div_def, Rat.zero_mul]
  simp [lagAt, h0, h1, hn, this, hz]

theorem lagAt_one_frame (prev cur : LagFrame) (h0 : 0 < cur.op) (h1 : cur.op < 1) (hn : prev.nav ≠ cur.nav)
    (hs : effClock cur.op = prev.nav) : lagAt prev cur = some 1 := by
  have hne : cur.nav - prev.nav ≠ 0 := by grind
  have hd : (cur.nav - prev.nav) / (cur.nav - prev.nav) = 1 := by rw [Rat.div_def]; exact Rat.mul_inv_cancel _ hne
  simp [lagAt, h0, h1, hn, hs, hd]

def lagFrames (fs : List LagFrame) : Option Rat :=
  let ls := ((fs.zip fs.tail).filterMap fun (p, c) => lagAt p c).map absR
  if ls.length < 3 then none else some (ls.foldl max 0)

def lagSlack : Rat := 1 / 10

def lagGrade (lag : Rat) : Grade := if lag ≤ 1 + lagSlack then .q else .l

theorem lagGrade_q (lag : Rat) (h : lag ≤ 1) : lagGrade lag = .q := by
  have : lag ≤ 1 + lagSlack := by unfold lagSlack; grind
  simp [lagGrade, this]

theorem lagGrade_l (lag : Rat) (h : 1 + lagSlack < lag) : lagGrade lag = .l := by
  have : ¬ lag ≤ 1 + lagSlack := by grind
  simp [lagGrade, this]

#guard lagGrade (21 / 20) == .q
#guard lagGrade (6 / 5) == .l

def laggedKey (l prev cur : Rat) : Rat := cur - l * (cur - prev)

theorem laggedKey_zero (prev cur : Rat) : laggedKey 0 prev cur = cur := by
  unfold laggedKey; grind

theorem laggedKey_one (prev cur : Rat) : laggedKey 1 prev cur = prev := by
  unfold laggedKey; grind

def laggedSeries (l : Rat) (fs : Series) : Series :=
  interior ((fs.zip fs.tail).map fun (p, c) => (laggedKey l p.1 c.1, c.2))

def modelGrade (tols : List Rat) (minCovered : Nat) (ref cand : Series) : Option Grade :=
  matchedGrade tols [] 1 minCovered (residual ref) (residual cand)

def shiftedGrade (tols : List Rat) (minCovered : Nat) (ref : Series) (l : Rat) (fs : Series) : Option Grade :=
  modelGrade tols minCovered ref (seriesOf (laggedSeries l fs))

def panelGrade (series : Option Grade) (lag : Option Rat) (shifted : Option Grade) : Option Grade :=
  match series with
  | none => none
  | some .e => some .e
  | some _ =>
    match lag with
    | none => none
    | some l => if l ≤ 1 + lagSlack && shifted == some .e then some .q else some .l

theorem panelGrade_e (lag : Option Rat) (sh : Option Grade) : panelGrade (some .e) lag sh = some .e := rfl

theorem panelGrade_no_lag (g : Grade) (h : g ≠ .e) (sh : Option Grade) : panelGrade (some g) none sh = none := by
  cases g <;> simp_all [panelGrade]

theorem panelGrade_no_match_l (g : Grade) (h : g ≠ .e) (l : Rat) (sh : Option Grade) (hs : sh ≠ some .e) :
    panelGrade (some g) (some l) sh = some .l := by
  cases g <;> simp_all [panelGrade]

theorem panelGrade_long_lag_l (g : Grade) (h : g ≠ .e) (l : Rat) (hl : 1 + lagSlack < l) (sh : Option Grade) :
    panelGrade (some g) (some l) sh = some .l := by
  have : ¬ l ≤ 1 + lagSlack := by grind
  cases g <;> simp_all [panelGrade]

theorem panelGrade_short_lag_q (g : Grade) (h : g ≠ .e) (l : Rat) (hl : l ≤ 1 + lagSlack) :
    panelGrade (some g) (some l) (some .e) = some .q := by
  cases g <;> simp_all [panelGrade]

theorem matched_e_ok (tols grid : List Rat) (fk : Rat) (n : Nat) (ref cand : Series)
    (h : matchedGrade tols grid fk n ref cand = some .e) : (matchAt tols ref cand 0).2 = true := by
  unfold matchedGrade at h
  split at h
  · simp at h
  · split at h
    · assumption
    · split at h <;> simp at h

theorem shiftedGrade_ne_e (tols : List Rat) (n : Nat) (ref : Series) (l : Rat) (fs : Series)
    (h : (matchAt tols (residual ref) (residual (seriesOf (laggedSeries l fs))) 0).2 = false) :
    shiftedGrade tols n ref l fs ≠ some .e := by
  intro he
  have := matched_e_ok _ _ _ _ _ _ he
  simp_all

theorem model_grade_e (tols : List Rat) (n : Nat) (ref cand : Series) (hl : tols.length = 3)
    (hnn : ∀ t ∈ tols, 0 ≤ t) (hr : sortedKeys ref = true) (hc : sortedKeys cand = true)
    (hrm : ∀ p ∈ ref, p.2 = effectAt p.1) (hcm : ∀ p ∈ cand, p.2 = effectAt p.1)
    (hn : n ≤ (matchAt tols (residual ref) (residual cand) 0).1) : modelGrade tols n ref cand = some .e := by
  unfold modelGrade
  have hz := residual_zero cand hcm
  have hzr := residual_zero ref hrm
  apply matched_e _ _ _ _ _ _ (by rw [residual_sorted]; exact hr) (by rw [residual_sorted]; exact hc) hn
  apply matchAt_ok_of_all
  intro p hp r hr'
  have h1 := hz p hp
  have h2 := interpAt_zero _ hzr _ r hr'
  rw [h1, h2]
  exact cellEq_refl tols _ (by simp [hl]) hnn

def panelCell (tols : List Rat) (minCovered : Nat) (ref : Series) (fs : Series) : Option Grade :=
  let series := modelGrade tols minCovered ref (seriesOf (interior fs))
  let lag := lagFrames (fs.map fun f => ⟨f.1, f.2.headD 0⟩)
  panelGrade series lag (lag.bind fun l => shiftedGrade tols minCovered ref l fs)

theorem panelCell_series_e (tols : List Rat) (n : Nat) (ref fs : Series)
    (h : modelGrade tols n ref (seriesOf (interior fs)) = some .e) : panelCell tols n ref fs = some .e := by
  simp [panelCell, h, panelGrade]

theorem panelCell_no_lag (tols : List Rat) (n : Nat) (ref fs : Series) (g : Grade) (hg : g ≠ .e)
    (h : modelGrade tols n ref (seriesOf (interior fs)) = some g)
    (hl : lagFrames (fs.map fun f => ⟨f.1, f.2.headD 0⟩) = none) : panelCell tols n ref fs = none := by
  simp only [panelCell, h, hl, Option.bind_none]
  exact panelGrade_no_lag g hg _

theorem panelCell_unmatched_l (tols : List Rat) (n : Nat) (ref fs : Series) (g : Grade) (hg : g ≠ .e) (l : Rat)
    (h : modelGrade tols n ref (seriesOf (interior fs)) = some g)
    (hl : lagFrames (fs.map fun f => ⟨f.1, f.2.headD 0⟩) = some l)
    (hm : (matchAt tols (residual ref) (residual (seriesOf (laggedSeries l fs))) 0).2 = false) :
    panelCell tols n ref fs = some .l := by
  simp only [panelCell, h, hl, Option.bind_some]
  exact panelGrade_no_match_l g hg l _ (shiftedGrade_ne_e tols n ref l fs hm)

theorem panelCell_long_lag_l (tols : List Rat) (n : Nat) (ref fs : Series) (g : Grade) (hg : g ≠ .e) (l : Rat)
    (h : modelGrade tols n ref (seriesOf (interior fs)) = some g)
    (hl : lagFrames (fs.map fun f => ⟨f.1, f.2.headD 0⟩) = some l) (hs : 1 + lagSlack < l) :
    panelCell tols n ref fs = some .l := by
  simp only [panelCell, h, hl, Option.bind_some]
  exact panelGrade_long_lag_l g hg l hs _

theorem panelCell_matched_q (tols : List Rat) (n : Nat) (ref fs : Series) (g : Grade) (hg : g ≠ .e) (l : Rat)
    (h : modelGrade tols n ref (seriesOf (interior fs)) = some g)
    (hl : lagFrames (fs.map fun f => ⟨f.1, f.2.headD 0⟩) = some l) (hs : l ≤ 1 + lagSlack)
    (hm : shiftedGrade tols n ref l fs = some .e) : panelCell tols n ref fs = some .q := by
  simp only [panelCell, h, hl, Option.bind_some, hm]
  exact panelGrade_short_lag_q g hg l hs

def darkness (layer : Option Rat) (cls : Bool) : Rat :=
  match layer with
  | some o => o
  | none => if cls then 1 else 0

theorem darkness_layer (o : Rat) (c : Bool) : darkness (some o) c = o := rfl

theorem darkness_class (c : Bool) : darkness none c = if c then 1 else 0 := rfl

def changes (l : List Rat) : Nat := ((l.zip l.tail).filter fun (a, b) => a != b).length

def painGrade (b c : List Rat) : Option Grade :=
  if b.length != c.length || b.isEmpty then none
  else
    let tol : Rat := 1 / 100
    let at_ (l : List Rat) (i : Nat) : Rat := l.getD i 0
    let eq (i : Nat) : Bool := decide (Within tol (at_ b i) (at_ c i))
    let bin (x : Rat) : Bool := x == 0 || x == 1
    let slip (i : Nat) : Bool :=
      bin (at_ b i) && bin (at_ c i) &&
      ((0 < i && decide (Within tol (at_ b (i - 1)) (at_ c i))) || decide (Within tol (at_ b (i + 1)) (at_ c i)))
    let idx := List.range b.length
    if idx.all eq then some .e
    else if changes b == changes c && idx.all fun i => eq i || slip i then some .q else some .l

theorem painGrade_refl (b : List Rat) (h : b ≠ []) : painGrade b b = some .e := by
  have hb : b.isEmpty = false := by cases b <;> simp_all
  have hall : (List.range b.length).all (fun i => decide (Within (1 / 100) (b.getD i 0) (b.getD i 0))) = true := by
    simp only [List.all_eq_true, List.mem_range, decide_eq_true_eq]
    intro i _
    unfold Within
    grind
  simp only [painGrade, bne_self_eq_false, hb, Bool.or_self, Bool.false_eq_true, ite_false, hall, ite_true]

theorem painGrade_length (b c : List Rat) (h : b.length ≠ c.length) : painGrade b c = none := by
  simp [painGrade, h]

#guard painGrade [0, 0, 1, 1] [0, 1, 1, 1] == some .q
#guard painGrade [0, 0, 1, 1] [0, 0, 0, 1] == some .q
#guard painGrade [0, 0, 1, 1] [0, 0, 1, 1] == some .e
#guard painGrade [0, 0, 1, 1] [0, 1, 0, 1] == some .l
#guard painGrade [0, 0, 1, 1] [1, 1, 1, 1] == some .l
#guard painGrade [0, 1 / 2, 1] [0, 3 / 4, 1] == some .l
#guard painGrade [0, 1] [0] == none

def worse (a b : Grade) : Grade := if a.rank.getD 0 < b.rank.getD 0 then b else a

def worst (gs : List (Option Grade)) : Option Grade :=
  match gs.mapM id with
  | some (g :: rest) => some (rest.foldl worse g)
  | _ => none

theorem mapM_id_none : ∀ (gs : List (Option Grade)), none ∈ gs → gs.mapM id = none
  | [], h => by simp at h
  | none :: _, _ => by simp [List.mapM_cons]
  | some _ :: rest, h => by
    have : none ∈ rest := by simpa using h
    simp [List.mapM_cons, mapM_id_none rest this]

theorem worst_nil : worst [] = none := rfl

theorem worst_none_mem (gs : List (Option Grade)) (h : none ∈ gs) : worst gs = none := by
  simp [worst, mapM_id_none gs h]

#guard worst [some .e, some .e] == some .e
#guard worst [some .e, some .q, some .e] == some .q
#guard worst [some .l, some .e, some .q] == some .l
#guard worst [some .e, none] == none
#guard worst [some .e, some .e1, some .e] == some .e1
#guard worst [some .e, some .e1, some .q] == some .q
#guard worst [some .e1, some .l, some .e] == some .l

abbrev Row := Option (List Int)

def restedBefore (rows : List Row) (i : Nat) : Bool :=
  0 < i && match rows[i - 1]?, rows[i]? with
    | some (some a), some (some b) => a == b
    | _, _ => false

theorem restedBefore_zero (rows : List Row) : restedBefore rows 0 = false := rfl

structure Scan where
  cur : Option (Nat × Nat)
  quiet : Nat
  spans : List (Nat × Nat)

def settle (rows : List Row) (still : Nat) (sp : Nat × Nat) (q : Nat) (spans : List (Nat × Nat)) : Scan :=
  if still ≤ q then ⟨none, 0, if restedBefore rows sp.1 then spans ++ [sp] else spans⟩ else ⟨some sp, q, spans⟩

def scanStep (rows : List Row) (still : Nat) (s : Scan) (i : Nat) : Scan :=
  match rows[i - 1]?, rows[i]? with
  | some (some a), some (some b) =>
    match (if a != b && s.cur.isNone then some (i - 1, i) else s.cur) with
    | none => s
    | some (f, t) => settle rows still (f, if a == b then t else i) (if a == b then s.quiet + 1 else 0) s.spans
  | _, _ => ⟨none, 0, s.spans⟩

def swapSpans (rows : List Row) (still : Nat) : List (Nat × Nat) :=
  ((List.range' 1 (rows.length - 1)).foldl (scanStep rows still) ⟨none, 0, []⟩).spans

theorem settle_rested (rows : List Row) (still : Nat) (sp : Nat × Nat) (q : Nat) (spans : List (Nat × Nat))
    (h : ∀ x ∈ spans, restedBefore rows x.1 = true) :
    ∀ x ∈ (settle rows still sp q spans).spans, restedBefore rows x.1 = true := by
  intro x hx
  unfold settle at hx
  split at hx
  · split at hx
    · simp only [List.mem_append, List.mem_singleton] at hx
      rcases hx with hx | rfl
      · exact h x hx
      · assumption
    · exact h x hx
  · exact h x hx

theorem scanStep_rested (rows : List Row) (still : Nat) (s : Scan) (i : Nat)
    (h : ∀ sp ∈ s.spans, restedBefore rows sp.1 = true) :
    ∀ sp ∈ (scanStep rows still s i).spans, restedBefore rows sp.1 = true := by
  unfold scanStep
  split
  · split
    · exact h
    · exact settle_rested _ _ _ _ _ h
  · exact h

theorem foldScan_rested (rows : List Row) (still : Nat) (is : List Nat) (s : Scan)
    (h : ∀ sp ∈ s.spans, restedBefore rows sp.1 = true) :
    ∀ sp ∈ (is.foldl (scanStep rows still) s).spans, restedBefore rows sp.1 = true := by
  induction is generalizing s with
  | nil => exact h
  | cons i rest ih => exact ih _ (scanStep_rested rows still s i h)

theorem swapSpans_rested (rows : List Row) (still : Nat) (sp : Nat × Nat) (h : sp ∈ swapSpans rows still) :
    restedBefore rows sp.1 = true :=
  foldScan_rested rows still _ ⟨none, 0, []⟩ (by simp) sp h

theorem swapSpans_from_pos (rows : List Row) (still : Nat) (sp : Nat × Nat) (h : sp ∈ swapSpans rows still) :
    0 < sp.1 := by
  have := swapSpans_rested rows still sp h
  simp only [restedBefore, Bool.and_eq_true, decide_eq_true_eq] at this
  exact this.1

def frameMs : Rat := 50 / 3

def spanSeries (rows : List Row) (sp : Nat × Nat) : Series :=
  let vs := ((rows.drop sp.1).take (sp.2 + 2 - sp.1)).map (·.getD [])
  let full := vs.foldl (fun m v => max m v.length) 0
  ((List.range vs.length).zip vs |>.filter fun (_, v) => v.length == full).map fun (j, v) =>
    ((j : Rat) * frameMs, v.map fun (x : Int) => (x : Rat) / 1000)

def dropHold : Series → Series
  | p :: q :: r => if p.2 = q.2 then dropHold (q :: r) else p :: q :: r
  | s => s

def rebase : Series → Series
  | [] => []
  | (k0, v0) :: r => (0, v0) :: r.map fun (k, v) => (k - k0, v)

def swapSeries (rows : List Row) (sp : Nat × Nat) : Series := rebase (dropHold (spanSeries rows sp))

def holdFrames (rows : List Row) (sp : Nat × Nat) : Nat := (spanSeries rows sp).length - (dropHold (spanSeries rows sp)).length

theorem dropHold_hold (p q : Rat × List Rat) (r : Series) (h : p.2 = q.2) : dropHold (p :: q :: r) = dropHold (q :: r) := by
  simp [dropHold, h]

theorem dropHold_move (p q : Rat × List Rat) (r : Series) (h : p.2 ≠ q.2) : dropHold (p :: q :: r) = p :: q :: r := by
  simp [dropHold, h]

theorem dropHold_first_moves (s : Series) (p q : Rat × List Rat) (r : Series) (h : dropHold s = p :: q :: r) :
    p.2 ≠ q.2 := by
  induction s with
  | nil => simp [dropHold] at h
  | cons a t ih =>
    cases t with
    | nil => simp [dropHold] at h
    | cons b t' =>
      by_cases hab : a.2 = b.2
      · rw [dropHold_hold a b t' hab] at h
        exact ih h
      · rw [dropHold_move a b t' hab] at h
        simp only [List.cons.injEq] at h
        obtain ⟨rfl, rfl, -⟩ := h
        exact hab

theorem onset_hold_invariant (p q : Rat × List Rat) (r : Series) (h : p.2 = q.2) :
    rebase (dropHold (p :: q :: r)) = rebase (dropHold (q :: r)) := by
  rw [dropHold_hold p q r h]

theorem rebase_first_key (s : Series) (p : Rat × List Rat) (r : Series) (h : rebase s = p :: r) : p.1 = 0 := by
  cases s with
  | nil => simp [rebase] at h
  | cons a t =>
    obtain ⟨k0, v0⟩ := a
    simp only [rebase, List.cons.injEq] at h
    rw [← h.1]

def swapsOf (rows : List Row) (still : Nat := 6) : List Series := (swapSpans rows still).map (swapSeries rows)

def stillFrames : Nat := 6

def settleCapMs : Rat := 2200

def tailCapMs : Rat := 1500

structure SettleSt where
  prev : List Int
  moved : Bool
  quiet : Nat
  deriving DecidableEq, Repr

def settleStep (s : SettleSt) (v : List Int) : SettleSt :=
  if s.prev == v then ⟨v, s.moved, if s.moved then s.quiet + 1 else s.quiet⟩ else ⟨v, true, 0⟩

def settleDone (still : Nat) (s : SettleSt) : Bool := s.moved && decide (still ≤ s.quiet)

def settleRun (still : Nat) (cap s0 : Rat) : SettleSt → Rat → List (Rat × List Int) → Nat → Nat × Bool
  | _, _, [], n => (n, false)
  | s, now, (t, v) :: fs, n =>
    if s0 + cap ≤ now then (n, false)
    else
      let s' := settleStep s v
      if settleDone still s' then (n + 1, true) else settleRun still cap s0 s' t fs (n + 1)

theorem settleStep_move (s : SettleSt) (v : List Int) (h : s.prev ≠ v) : settleStep s v = ⟨v, true, 0⟩ := by
  simp [settleStep, h]

theorem settleStep_rest (s : SettleSt) : settleStep s s.prev = ⟨s.prev, s.moved, if s.moved then s.quiet + 1 else s.quiet⟩ := by
  simp [settleStep]

theorem settle_unmoved_not_done (still : Nat) (v : List Int) (q : Nat) : settleDone still ⟨v, false, q⟩ = false := rfl

theorem settle_waits_for_move (still : Nat) (cap s0 : Rat) (v : List Int) (q : Nat) (now : Rat)
    (fs : List (Rat × List Int)) (n : Nat) (h : ∀ f ∈ fs, f.2 = v) :
    (settleRun still cap s0 ⟨v, false, q⟩ now fs n).2 = false := by
  induction fs generalizing now n with
  | nil => simp [settleRun]
  | cons f fs ih =>
    obtain ⟨t, w⟩ := f
    have hw : w = v := h (t, w) (by simp)
    subst hw
    have hs : settleStep ⟨w, false, q⟩ w = ⟨w, false, q⟩ := by simp [settleStep]
    simp only [settleRun, hs]
    split
    · rfl
    · rw [ite_eq_right_iff.2 (fun h => by simp [settleDone] at h)]
      exact ih t (n + 1) (fun x hx => h x (by simp [hx]))

theorem settle_quiet_after_still (still : Nat) (cap s0 t0 : Rat) (v : List Int) (ht : t0 < s0 + cap) :
    ∀ (m q : Nat) (now : Rat) (n : Nat), q + m = still → 0 < m → now < s0 + cap →
      settleRun still cap s0 ⟨v, true, q⟩ now (List.replicate m (t0, v)) n = (n + m, true) := by
  intro m
  induction m with
  | zero => intro q now n _ h; omega
  | succ m ih =>
    intro q now n hq _ hn
    have hnc : ¬ s0 + cap ≤ now := by grind
    have hs : settleStep ⟨v, true, q⟩ v = ⟨v, true, q + 1⟩ := by simp [settleStep]
    cases m with
    | zero =>
      have hd : settleDone still ⟨v, true, q + 1⟩ = true := by simp [settleDone]; omega
      simp [List.replicate_succ, settleRun, hnc, hs, hd]
    | succ m =>
      have hd : settleDone still ⟨v, true, q + 1⟩ = false := by simp [settleDone]; omega
      have := ih (q + 1) t0 (n + 1) (by omega) (by omega) ht
      simp only [List.replicate_succ, settleRun, hnc, hs, hd] at this ⊢
      simp only [this]
      simp
      omega

def tailNext (prev : Option (List Int)) (v : List Int) (tail : Nat) : Nat := if prev == some v then tail + 1 else 0

def tailStop (ms : Rat) (still : Nat) (t : Rat) (tail : Nat) : Bool :=
  decide (ms + tailCapMs ≤ t) || (decide (ms ≤ t) && decide (still ≤ tail))

theorem tailStop_cap (ms t : Rat) (still tail : Nat) (h : ms + tailCapMs ≤ t) : tailStop ms still t tail = true := by
  simp [tailStop, h]

theorem tailStop_quiet (ms t : Rat) (still tail : Nat) (h : ms ≤ t) (hq : still ≤ tail) : tailStop ms still t tail = true := by
  simp [tailStop, h, hq]

theorem tailStop_before_ms (ms t : Rat) (still tail : Nat) (h : t < ms) : tailStop ms still t tail = false := by
  have h1 : ¬ ms + tailCapMs ≤ t := by unfold tailCapMs; grind
  have h2 : ¬ ms ≤ t := by grind
  simp [tailStop, h1, h2]

theorem tailStop_waits (ms t : Rat) (still tail : Nat) (h : t < ms + tailCapMs) (hq : tail < still) :
    tailStop ms still t tail = false := by
  have h1 : ¬ ms + tailCapMs ≤ t := by grind
  have h2 : ¬ still ≤ tail := by grind
  simp [tailStop, h1, h2]

def tailRun (ms : Rat) (still : Nat) : Option (List Int) → Nat → List (Rat × List Int) → Nat → Nat × Bool
  | _, _, [], n => (n, false)
  | prev, tail, (t, v) :: fs, n =>
    let tail' := tailNext prev v tail
    if tailStop ms still t tail' then (n + 1, decide (t < ms + tailCapMs))
    else tailRun ms still (some v) tail' fs (n + 1)

theorem tail_quiet_after_still (ms t0 : Rat) (still : Nat) (v : List Int) (h0 : ms ≤ t0) (h1 : t0 < ms + tailCapMs) :
    ∀ (m tail n : Nat), tail + m = still → 0 < m →
      tailRun ms still (some v) tail (List.replicate m (t0, v)) n = (n + m, true) := by
  intro m
  induction m with
  | zero => intro tail n _ h; omega
  | succ m ih =>
    intro tail n hq _
    have hn : tailNext (some v) v tail = tail + 1 := by simp [tailNext]
    cases m with
    | zero =>
      have hst := tailStop_quiet ms t0 still (tail + 1) h0 (by omega)
      simp [List.replicate_succ, tailRun, hn, hst, h1]
    | succ m =>
      have hst := tailStop_waits ms t0 still (tail + 1) h1 (by omega)
      have := ih (tail + 1) (n + 1) (by omega) (by omega)
      simp only [List.replicate_succ, tailRun, hn, hst] at this ⊢
      simp only [this]
      simp
      omega

def carouselGrid : List Rat := [-1, -3 / 4, -1 / 2, -1 / 4, 1 / 4, 1 / 2, 3 / 4, 1]

def carouselMinCovered : Nat := 4

def swapGrade (dpr : Rat) (b c : Series) : Option Grade :=
  matchedGrade (List.replicate ((b.head?.map (·.2.length)).getD 0) (tolCss dpr)) carouselGrid frameMs carouselMinCovered b c

def holdTol : Nat := 1

def holdGrade (hb hc : Nat) : Grade := if hb ≤ hc + holdTol ∧ hc ≤ hb + holdTol then .e else .l

theorem holdGrade_e_le (hb hc : Nat) (h : hb ≤ hc + holdTol) (h' : hc ≤ hb + holdTol) : holdGrade hb hc = .e := by
  simp [holdGrade, h, h']

theorem holdGrade_l_base_long (hb hc : Nat) (h : hc + holdTol < hb) : holdGrade hb hc = .l := by
  have : ¬ hb ≤ hc + holdTol := by omega
  simp [holdGrade, this]

theorem holdGrade_l_cand_long (hb hc : Nat) (h : hb + holdTol < hc) : holdGrade hb hc = .l := by
  have : ¬ hc ≤ hb + holdTol := by omega
  simp [holdGrade, this]

theorem holdGrade_symm (hb hc : Nat) : holdGrade hb hc = holdGrade hc hb := by
  simp only [holdGrade, and_comm]

theorem holdGrade_refl (h : Nat) : holdGrade h h = .e := holdGrade_e_le h h (by omega) (by omega)

#guard holdGrade 2 1 == .e
#guard holdGrade 1 2 == .e
#guard holdGrade 3 3 == .e
#guard holdGrade 1 3 == .l
#guard holdGrade 3 1 == .l
#guard holdGrade 0 4 == .l

def repGrade (motion : Option Grade) (hb hc : Nat) : Option Grade := motion.map fun g => worse g (holdGrade hb hc)

theorem repGrade_hold_l (motion : Option Grade) (g : Grade) (hm : motion = some g) (hb hc : Nat) (h : holdGrade hb hc = .l) :
    repGrade motion hb hc = some .l := by
  subst hm
  cases g <;> simp [repGrade, h, worse, Grade.rank]

theorem repGrade_hold_e (g : Grade) (hb hc : Nat) (h : holdGrade hb hc = .e) :
    repGrade (some g) hb hc = some g := by
  cases g <;> simp [repGrade, h, worse, Grade.rank]

theorem repGrade_none (hb hc : Nat) : repGrade none hb hc = none := rfl

def holdsOf (rows : List Row) (still : Nat := 6) : List Nat := (swapSpans rows still).map (holdFrames rows)

def carouselReps (dpr : Rat) (bs cs : List Series) (hbs hcs : List Nat) : List (Option Grade) :=
  ((bs.zip cs).zip (hbs.zip hcs)).map fun ((b, c), (hb, hc)) => repGrade (swapGrade dpr b c) hb hc

def carouselGrade (nb nc : Nat) (reps : List (Option Grade)) : Option Grade := if nb = nc then worst reps else some .l

structure CarouselCell where
  swaps : Nat × Nat
  reps : List (Option Grade)
  grade : Option Grade

def carouselCell (dpr : Rat) (base cand : List Row) : CarouselCell :=
  let bs := swapsOf base
  let cs := swapsOf cand
  let reps := carouselReps dpr bs cs (holdsOf base) (holdsOf cand)
  ⟨(bs.length, cs.length), reps, carouselGrade bs.length cs.length reps⟩

theorem carouselGrade_mismatch (nb nc : Nat) (reps : List (Option Grade)) (h : nb ≠ nc) :
    carouselGrade nb nc reps = some .l := by
  simp [carouselGrade, h]

theorem carouselCell_mismatch (dpr : Rat) (base cand : List Row) (h : (swapsOf base).length ≠ (swapsOf cand).length) :
    (carouselCell dpr base cand).grade = some .l :=
  carouselGrade_mismatch _ _ _ h

theorem carouselCell_zero_swaps (dpr : Rat) (base cand : List Row) (hb : swapsOf base ≠ []) (hc : swapsOf cand = []) :
    (carouselCell dpr base cand).grade = some .l := by
  apply carouselCell_mismatch
  rw [hc]
  simpa using hb

theorem carouselCell_null_rep (dpr : Rat) (base cand : List Row)
    (hn : (swapsOf base).length = (swapsOf cand).length) (h : none ∈ (carouselCell dpr base cand).reps) :
    (carouselCell dpr base cand).grade = none := by
  simp only [carouselCell, carouselGrade, hn, ite_true]
  exact worst_none_mem _ h

def painDir (b c : List Rat) : Option Grade := if !b.isEmpty && changes b == 0 then none else painGrade b c

theorem painDir_no_flip (b c : List Rat) (hb : b ≠ []) (h : changes b = 0) : painDir b c = none := by
  have : b.isEmpty = false := by cases b <;> simp_all
  simp [painDir, this, h]

theorem painDir_flips (b c : List Rat) (h : changes b ≠ 0) : painDir b c = painGrade b c := by
  simp [painDir, h]

def painCell (up down : List Rat × List Rat) : List (Option Grade) := [painDir up.1 up.2, painDir down.1 down.2]

theorem painCell_no_flip_up (up down : List Rat × List Rat) (hb : up.1 ≠ []) (h : changes up.1 = 0) :
    worst (painCell up down) = none :=
  worst_none_mem _ (by simp [painCell, painDir_no_flip up.1 up.2 hb h])

theorem painCell_no_flip_down (up down : List Rat × List Rat) (hb : down.1 ≠ []) (h : changes down.1 = 0) :
    worst (painCell up down) = none :=
  worst_none_mem _ (by simp [painCell, painDir_no_flip down.1 down.2 hb h])

def ratStr (r : Rat) : String := s!"{r.num}/{r.den}"

def vecJson (v : List Rat) : Json := toJson (v.map ratStr)

def boxJson (b : Box) : Json := vecJson [b.x, b.y, b.w, b.h]

def lenStr : Len → String
  | .px v => "px:" ++ ratStr v
  | .pct v => "pct:" ++ ratStr v

def insetJson (i : Inset) : Json :=
  Json.mkObj [("sides", toJson ([i.top, i.right, i.bottom, i.left].map lenStr)),
    ("radii", match i.radii with
      | none => Json.null
      | some (a, b, c, d) => toJson ([a, b, c, d].map lenStr))]

def seriesJson (s : Series) : Json := toJson (s.map fun (k, v) => Json.mkObj [("k", toJson (ratStr k)), ("v", vecJson v)])

def ramp (n : Nat) (step : Rat) (f : Rat → List Rat) : Series := (List.range n).map fun (i : Nat) => ((i : Rat) * step, f ((i : Rat) * step))

def gradeName (g : Option Grade) : Json := toJson (g.map Grade.name)

def ringAt (x : Int) : Row := some [x, 0, 32000, 32000]

def hold (x : Int) (n : Nat) : List Row := List.replicate n (ringAt x)

def glide (x0 x1 : Int) (n : Nat) : List Row :=
  (List.range n).map fun (i : Nat) => ringAt (x0 + (x1 - x0) * ((i : Int) + 1) / ((n : Int) + 1))

def wideAt (x : Int) : Row := some [x, 0, 32000, 32000, x + 24000, 0, 32000, 32000]

def twoSwaps : List Row := hold 0 8 ++ glide 0 30000 5 ++ hold 30000 10 ++ glide 30000 60000 5 ++ hold 60000 10

def restedCases : List (String × List Row × Nat) :=
  [("the first row", twoSwaps, 0), ("two equal rows", twoSwaps, 1), ("a change", twoSwaps, 9),
   ("an unread row before", [none, ringAt 0], 1), ("past the end", hold 0 2, 2)]

def holdSwap (h : Nat) (step : Int := 5000) : List Row :=
  hold 0 8 ++ List.replicate h (wideAt 0) ++ ((List.range 6).map fun (i : Nat) => wideAt (-step * ((i : Int) + 1))) ++ hold (-30000) 10

def swapCases : List (String × List Row × Nat) :=
  [("opens at rest", twoSwaps, 6), ("opens mid-swap", twoSwaps.drop 10, 6),
   ("opens one row before a swap", twoSwaps.drop 7, 6), ("ends mid-swap", twoSwaps.take 26, 6),
   ("an unread row inside the swap", hold 0 8 ++ glide 0 30000 2 ++ [none] ++ glide 15000 30000 2 ++ hold 30000 10, 6),
   ("an entering avatar", hold 0 8 ++ ((List.range 4).map fun (i : Nat) => wideAt (-6000 * ((i : Int) + 1))) ++ hold (-30000) 10, 6),
   ("a shorter quiet", hold 0 4 ++ glide 0 30000 3 ++ hold 30000 3 ++ glide 30000 60000 3 ++ hold 60000 3, 2),
   ("an entering avatar held 1 row", holdSwap 1, 6), ("an entering avatar held 4 rows", holdSwap 4, 6)]

def missingSwap : List Row := hold 0 8 ++ glide 0 30000 5 ++ hold 30000 25

def jumpSwap : List Row := hold 0 8 ++ glide 0 30000 5 ++ hold 30000 10 ++ hold 60000 10

def movedEnd : List Row := hold 0 8 ++ glide 0 30000 5 ++ hold 30000 10 ++ glide 30000 61000 5 ++ hold 61000 10

def carouselCases : List (String × List Row × List Row) :=
  [("equal swaps in step", twoSwaps, twoSwaps), ("one swap missing", twoSwaps, missingSwap),
   ("zero swaps", twoSwaps, hold 0 38), ("a null rep among E reps", jumpSwap, jumpSwap),
   ("no swaps on either side", hold 0 20, hold 0 20), ("end position moved", twoSwaps, movedEnd),
   ("candidate opens mid-swap", twoSwaps, twoSwaps.drop 10),
   ("entering avatar held 1 row against 2", holdSwap 1, holdSwap 2),
   ("entering avatar held 2 rows against 4", holdSwap 2, holdSwap 4),
   ("entering avatar held 4 rows against 1, steps differ", holdSwap 4, holdSwap 1 5400)]

def carouselDpr : Rat := 2

#guard (carouselCases.map fun (_, b, c) => (carouselCell carouselDpr b c).grade) ==
  [some .e, some .l, some .l, none, none, some .l, some .l, some .e, some .l, some .l]

#guard (carouselCell carouselDpr jumpSwap jumpSwap).reps == [some .e, none]

#guard (swapCases.map fun (_, rs, st) => swapSpans rs st) ==
  [[(7, 13), (22, 28)], [(12, 18)], [(15, 21)], [(7, 13)], [], [(7, 12)], [(3, 7), (9, 13)], [(7, 15)], [(7, 18)]]

def painCellCases : List (String × (List Rat × List Rat) × (List Rat × List Rat)) :=
  [("both directions flip, equal", ([1, 1, 0, 0], [1, 1, 0, 0]), ([0, 0, 1, 1], [0, 0, 1, 1])),
   ("down flips one step late", ([1, 1, 0, 0], [1, 1, 0, 0]), ([0, 0, 1, 1], [0, 0, 0, 1])),
   ("up base never flips", ([1, 1, 1, 1], [1, 1, 1, 1]), ([0, 0, 1, 1], [0, 0, 1, 1])),
   ("up base empty", ([], []), ([0, 0, 1, 1], [0, 0, 1, 1])),
   ("up flicker", ([1, 1, 0, 0], [1, 0, 1, 0]), ([0, 0, 1, 1], [0, 0, 1, 1]))]

#guard (painCellCases.map fun (_, u, d) => worst (painCell u d)) == [some .e, some .q, none, none, some .l]

def worstCases : List (List (Option Grade)) :=
  [[], [some .e, some .e], [some .e, some .q, some .e], [some .l, some .e, some .q], [some .e, none], [none], [none, some .l],
   [some .e, some .e1, some .e], [some .q, some .e1], [some .e1, some .l, some .e], [some .e, some .e1, some .q], [some .invalid, some .e1],
   [some .e1, some .invalid]]

def rowsJson (rs : List Row) : Json := toJson rs

def gradesJson (gs : List (Option Grade)) : Json := toJson (gs.map gradeName)

def clipCases : List (String × Box × Rat × String) :=
  [("none keeps the border box", ⟨0, 0, 100, 40⟩, 20, "none"),
   ("radius shrinks to fit", ⟨0, 0, 100, 40⟩, 30, "none"),
   ("side insets with a round", ⟨0, 0, 100, 40⟩, 20, "inset(0px 10px round 16px)"),
   ("fractional box", ⟨25 / 2, 4, 640, 56⟩, 28, "inset(0px 100px 0px 100px round 28px)"),
   ("half-pixel insets", ⟨0, 0, 300, 56⟩, 28, "inset(0px 25.5px 0px 25.5px round 20px)"),
   ("percent radius differs per axis", ⟨0, 0, 100, 40⟩, 20, "inset(0% round 50%)"),
   ("percent insets", ⟨0, 0, 100, 40⟩, 20, "inset(50% 0px)"),
   ("insets longer than the box", ⟨0, 0, 100, 40⟩, 20, "inset(30px 0px 30px 0px)"),
   ("two radii differ", ⟨0, 0, 100, 40⟩, 20, "inset(0px round 10px 20px)"),
   ("calc is not read", ⟨0, 0, 100, 40⟩, 20, "inset(calc(1px))"),
   ("three sides", ⟨0, 0, 100, 40⟩, 0, "inset(1px 2px 3px)"),
   ("circle is not read", ⟨0, 0, 100, 40⟩, 20, "circle(5px)")]

def cellCases : List (List Rat × List Rat × List Rat) :=
  [([1 / 2, 1 / 2], [1, 2], [3 / 2, 5 / 2]), ([1 / 2, 1 / 2], [1, 2], [2, 2]), ([1 / 2], [1, 2], [1]),
   ([], [], []), ([1 / 100], [1], [101 / 100]), ([1 / 100], [1], [102 / 100]), ([0], [5], [5])]

def interpTable : Series := [(0, [0, 10]), (1, [10, 20]), (3, [10, 0])]

def matchedCases : List (String × List Rat × List Rat × Rat × Nat × Series × Series) :=
  let ref := ramp 11 1 fun k => [k, 2 * k]
  [("identical", [1 / 10, 1 / 10], [0], 1, 5, ref, ref),
   ("inside tolerance", [1 / 10, 1 / 10], [0], 1, 5, ref, ramp 11 1 fun k => [k + 1 / 20, 2 * k - 1 / 20]),
   ("half a frame late is Q on a grid", [1 / 10, 1 / 10], [-1 / 2, 1 / 2, 1], 1, 5, ref, ramp 11 1 fun k => [k + 1 / 2, 2 * k + 1]),
   ("a late shift on grid 0 is L", [1 / 10, 1 / 10], [0], 1, 5, ref, ramp 11 1 fun k => [k + 1 / 2, 2 * k + 1]),
   ("two frames late is L", [1 / 10, 1 / 10], [-2, 2, 1], 1, 5, ref, ramp 11 1 fun k => [k + 2, 2 * k + 4]),
   ("a frame of 25/3 keys", [1 / 10, 1 / 10], [1], 25 / 3, 3, ramp 40 (25 / 3) fun k => [k, 2 * k],
    ramp 20 (25 / 3) fun k => [k + 25 / 3, 2 * k + 50 / 3]),
   ("under covered", [1 / 10, 1 / 10], [0], 1, 5, ref, ramp 3 1 fun k => [k + 20, k]),
   ("unsorted reference", [1 / 10], [0], 1, 1, [(1, [0]), (1, [1])], [(1, [0])]),
   ("unsorted candidate", [1 / 10], [0], 1, 1, ref, [(2, [2, 4]), (1, [1, 2])]),
   ("different vector lengths", [1 / 10, 1 / 10], [0], 1, 3, ref, ramp 11 1 fun k => [k])]

def lagFramesOf (d : Rat) (navs : List Rat) : List LagFrame :=
  navs.map fun n => ⟨n, panelOpacity (n - d / 10)⟩

def navSteps : List Rat := (List.range 9).map fun (i : Nat) => (i : Rat) / 10 + 1 / 10

def lagCases : List (String × List LagFrame) :=
  [("in step", lagFramesOf 0 navSteps), ("one frame behind", lagFramesOf 1 navSteps),
   ("two frames behind", lagFramesOf 2 navSteps), ("half a frame behind", lagFramesOf (1 / 2) navSteps),
   ("too few frames", lagFramesOf 0 [1 / 10, 1 / 5]), ("nav stands still", lagFramesOf 0 [1 / 5, 1 / 5, 1 / 5, 1 / 5, 1 / 5]),
   ("opacity at an end", [⟨1, 1⟩, ⟨11 / 10, 1⟩, ⟨6 / 5, 1⟩, ⟨13 / 10, 1⟩])]

def painCases : List (String × List Rat × List Rat) :=
  [("equal", [0, 0, 1, 1], [0, 0, 1, 1]), ("flip one step early", [0, 0, 1, 1], [0, 1, 1, 1]),
   ("flip one step late", [0, 0, 1, 1], [0, 0, 0, 1]), ("flip two steps early", [0, 0, 0, 1, 1], [0, 1, 1, 1, 1]),
   ("flicker", [0, 0, 1, 1], [0, 1, 0, 1]), ("always dark", [0, 0, 1, 1], [1, 1, 1, 1]),
   ("ramp differs", [0, 1 / 2, 1], [0, 3 / 4, 1]), ("ramp inside tolerance", [0, 1 / 2, 1], [0, 501 / 1000, 1]),
   ("length differs", [0, 1], [0]), ("empty", [], []), ("reverse", [1, 1, 0, 0], [1, 0, 0, 0])]

def panelCases : List (String × Option Grade × Option Rat × Option Grade) :=
  [("equal", some .e, some 3, none), ("short lag", some .l, some 1, some .e),
   ("short lag, lagged clock differs", some .l, some 1, some .l), ("short lag, lagged clock not compared", some .l, some 1, none),
   ("long lag", some .l, some (3 / 2), some .e), ("no lag", some .l, none, some .e), ("no series", none, some 0, some .e),
   ("series q", some .q, some (1 / 2), some .e), ("series q, lagged clock differs", some .q, some (1 / 2), some .l)]

def panelRef : Series := ramp 201 (1 / 200) effectAt

def panelFrames (d : Rat) (f : List Rat → List Rat) : Series :=
  (List.range 21).map fun (i : Nat) => ((i : Rat) / 20, f (effectAt ((i : Rat) / 20 - d / 20)))

def panelCellCases : List (String × Series) :=
  [("in step", panelFrames 0 id), ("one frame behind", panelFrames 1 id),
   ("one frame behind, blur dropped", panelFrames 1 fun v => [v.getD 0 0, 0, v.getD 2 1]),
   ("one frame behind, scale dropped", panelFrames 1 fun v => [v.getD 0 0, v.getD 1 0, 1]),
   ("in step, blur dropped", panelFrames 0 fun v => [v.getD 0 0, 0, v.getD 2 1]),
   ("in step, scale dropped", panelFrames 0 fun v => [v.getD 0 0, v.getD 1 0, 1]),
   ("two frames behind", panelFrames 2 id), ("half a frame behind", panelFrames (1 / 2) id),
   ("closing in step", (panelFrames 0 id).reverse), ("closing one frame behind", (panelFrames (-1) id).reverse),
   ("closing one frame behind, blur dropped", (panelFrames (-1) fun v => [v.getD 0 0, 0, v.getD 2 1]).reverse),
   ("in step, stalled frame", (panelFrames 0 id).take 11 ++ [(1 / 2, effectAt (11 / 20))] ++ (panelFrames 0 id).drop 11)]

def panelCellTols : List Rat := effectTols 2 600

#guard (panelCellCases.map fun (_, fs) => panelCell panelCellTols 8 panelRef fs) ==
  [some .e, some .q, some .l, some .l, some .l, some .l, some .l, some .q, some .e, some .q, some .l, some .e]

def seriesCases : List (String × Series) :=
  [("rising unique keys", [(0, [1]), (1, [2]), (2, [3])]), ("falling keys", [(2, [3]), (1, [2]), (0, [1])]),
   ("two reps pooled, interleaved", [(0, [1]), (2, [3]), (4, [5]), (1, [2]), (3, [4])]),
   ("an equal key, the first stays", [(0, [1]), (1, [2]), (1, [9]), (2, [3])]),
   ("an equal key after a larger one", [(1, [2]), (0, [1]), (1, [9])]),
   ("falling with an equal key", [(2, [3]), (1, [2]), (1, [9]), (0, [1])]), ("empty", [])]

#guard (seriesCases.map fun (_, s) => seriesOf s) ==
  [[(0, [1]), (1, [2]), (2, [3])], [(0, [1]), (1, [2]), (2, [3])],
   [(0, [1]), (1, [2]), (2, [3]), (3, [4]), (4, [5])], [(0, [1]), (1, [2]), (2, [3])],
   [(0, [1]), (1, [2])], [(0, [1]), (1, [2]), (2, [3])], []]

def kinkRef : Series := [(1 / 10, effectAt (1 / 10)), (3 / 10, effectAt (3 / 10)), (1 / 2, effectAt (1 / 2)), (7 / 10, effectAt (7 / 10)),
  (9 / 10, effectAt (9 / 10))]

def kinkFrames (f : List Rat → List Rat) : Series :=
  (List.range 15).map fun (i : Nat) => (((i : Rat) + 3) / 20, f (effectAt (((i : Rat) + 3) / 20)))

def kinkCases : List (String × Series) :=
  [("sparse reference, candidate on the effect", kinkFrames id),
   ("sparse reference, blur dropped", kinkFrames fun v => [v.getD 0 0, 0, v.getD 2 1]),
   ("sparse reference, opacity off by 3/100", kinkFrames fun v => [v.getD 0 0 + 3 / 100, v.getD 1 0, v.getD 2 1])]

#guard (kinkCases.map fun (_, fs) => matchedGrade panelCellTols [] 1 8 kinkRef fs) == [some .l, some .l, some .l]

#guard (kinkCases.map fun (_, fs) => panelCell panelCellTols 8 kinkRef fs) == [some .e, some .l, some .l]

def timed (vs : List (List Int)) : List (Rat × List Int) :=
  ((List.range vs.length).zip vs).map fun (i, v) => (17 * ((i : Rat) + 1), v)

def moves : List (List Int) := [[1], [2], [3], [4]]

def settleCases : List (String × Nat × List Int × List (Rat × List Int)) :=
  [("a swap then rest", 6, [0], timed (List.replicate 3 [0] ++ moves ++ List.replicate 8 [4])),
   ("a still page never ends", 6, [0], timed (List.replicate 20 [0])),
   ("five rests are not enough", 6, [0], timed (moves ++ List.replicate 5 [4])),
   ("six rests are enough", 6, [0], timed (moves ++ List.replicate 6 [4])),
   ("a flicker restarts the count", 6, [0], timed (moves ++ List.replicate 4 [4] ++ [[5]] ++ List.replicate 6 [5])),
   ("the cap ends the wait", 6, [0], [(2000, [1]), (2100, [2]), (2200, [3]), (2300, [4])]),
   ("two rests suffice at still 2", 2, [0], timed (moves ++ List.replicate 2 [4]))]

def tailCases : List (String × Rat × Nat × List (Rat × List Int)) :=
  [("rest after ms", 100, 6, timed ((List.range 8).map (fun (i : Nat) => [(i : Int)]) ++ List.replicate 12 [8])),
   ("moving to the cap", 100, 6, timed ((List.range 120).map fun (i : Nat) => [(i : Int)])),
   ("rest before ms keeps recording", 100, 6, timed (List.replicate 12 [0])),
   ("still 1", 100, 1, timed (List.replicate 12 [0]))]

#guard (settleCases.map fun (_, st, p, fs) => settleRun st settleCapMs 0 ⟨p, false, 0⟩ 0 fs 0) ==
  [(13, true), (20, false), (9, false), (10, true), (15, true), (3, false), (6, true)]

#guard (tailCases.map fun (_, ms, st, fs) => tailRun ms st none 0 fs 0) ==
  [(15, true), (95, false), (7, true), (6, true)]

def framesJson (fs : List (Rat × List Int)) : Json :=
  toJson (fs.map fun (t, v) => Json.mkObj [("t", toJson (ratStr t)), ("v", toJson v)])

def goldenLines (_ : Unit := ()) : List String :=
  let o (kvs : List (String × Json)) : String := (Json.mkObj kvs).compress
  [1, 2, 3, 3 / 2].map (fun (d : Rat) => o [("kind", "tol"), ("dpr", toJson (ratStr d)), ("tol", toJson (ratStr (tolCss d)))]) ++
  ["12", "-0.5", ".5", "1e-7", "5.", "", "0.125", "+3", "-", "1.2.3"].map (fun s =>
    o [("kind", "dec"), ("s", toJson s), ("out", toJson ((parseDec s).map ratStr))]) ++
  ["0", "12.5px", "50%", "3em", "calc(1px)", "-4px", "", "px", "1.5%"].map (fun s =>
    o [("kind", "len"), ("s", toJson s), ("out", toJson ((parseLen s).map lenStr))]) ++
  ["inset(0px)", "inset(0px 10px round 16px)", "inset(1px 2px 3px)", "inset(1px 2px 3px 4px round 5px 6px 7px)",
   "inset(0% round 50%)", "inset(calc(1px))", "circle(5px)", "inset()", "inset(1px 2px 3px 4px 5px)", "inset(0px round )",
   "inset(0px round 1px 2px 3px 4px 5px)", "none", "inset(0px round 1px / 2px)"].map (fun s =>
    o [("kind", "inset"), ("s", toJson s), ("out", match parseInset s with | some i => insetJson i | none => Json.null)]) ++
  [["a"], ["a", "b"], ["a", "b", "c"], ["a", "b", "c", "d"], [], ["a", "b", "c", "d", "e"]].map (fun l =>
    o [("kind", "expand4"), ("in", toJson l), ("out", toJson ((expand4 l).map fun (a, b, c, d) => [a, b, c, d]))]) ++
  clipCases.map (fun (n, b, r, c) =>
    o [("kind", "clip"), ("name", toJson n), ("box", boxJson b), ("radius", toJson (ratStr r)), ("clip", toJson c),
      ("out", toJson ((readShape b r c).map fun s => (shapeVec s).map ratStr))]) ++
  cellCases.map (fun (t, a, b) =>
    o [("kind", "cell"), ("tols", vecJson t), ("a", vecJson a), ("b", vecJson b), ("eq", toJson (cellEq t a b))]) ++
  [-1, 0, 1 / 2, 1, 2, 3, 4].map (fun (k : Rat) =>
    o [("kind", "interp"), ("table", seriesJson interpTable), ("k", toJson (ratStr k)),
      ("out", toJson ((interpAt interpTable k).map fun v => v.map ratStr))]) ++
  matchedCases.map (fun (n, t, g, fk, mc, r, c) =>
    o [("kind", "matched"), ("name", toJson n), ("tols", vecJson t), ("grid", vecJson g), ("frameKey", toJson (ratStr fk)),
      ("minCovered", toJson mc), ("ref", seriesJson r), ("cand", seriesJson c),
      ("grade", gradeName (matchedGrade t g fk mc r c))]) ++
  [0, 1 / 200, 1 / 100, 1 / 50, 1 / 2, 49 / 50, 99 / 100, 199 / 200, 1].map (fun (k : Rat) =>
    o [("kind", "interior"), ("k", toJson (ratStr k)),
      ("kept", toJson (!(interior [(k, [])]).isEmpty))]) ++
  [0, 1 / 25, 2 / 25, 11 / 25, 4 / 5, 1].map (fun (m : Rat) =>
    o [("kind", "effect"), ("m", toJson (ratStr m)), ("out", vecJson (effectAt m)),
      ("tols", vecJson (effectTols 2 600)), ("clock", toJson (ratStr (effClock (panelOpacity m))))]) ++
  lagCases.map (fun (n, fs) =>
    o [("kind", "lag"), ("name", toJson n),
      ("frames", toJson (fs.map fun f => [ratStr f.nav, ratStr f.op])),
      ("lag", toJson ((lagFrames fs).map ratStr)), ("grade", gradeName ((lagFrames fs).map lagGrade))]) ++
  panelCases.map (fun (n, g, l, sh) =>
    o [("kind", "panel"), ("name", toJson n), ("series", gradeName g), ("lag", toJson (l.map ratStr)), ("shifted", gradeName sh),
      ("grade", gradeName (panelGrade g l sh))]) ++
  seriesCases.map (fun (n, s) =>
    o [("kind", "series"), ("name", toJson n), ("in", seriesJson s), ("out", seriesJson (seriesOf s))]) ++
  panelCellCases.map (fun (n, fs) =>
    o [("kind", "panelcell"), ("name", toJson n), ("tols", vecJson panelCellTols), ("minCovered", toJson 8),
      ("ref", seriesJson panelRef), ("frames", seriesJson fs),
      ("lag", toJson ((lagFrames (fs.map fun f => ⟨f.1, f.2.headD 0⟩)).map ratStr)),
      ("grade", gradeName (panelCell panelCellTols 8 panelRef fs))]) ++
  painCases.map (fun (n, b, c) =>
    o [("kind", "pain"), ("name", toJson n), ("base", vecJson b), ("cand", vecJson c), ("grade", gradeName (painGrade b c))]) ++
  [(some (1 / 2 : Rat), false), (some 0, true), (none, true), (none, false)].map (fun (l, c) =>
    o [("kind", "dark"), ("layer", toJson (l.map ratStr)), ("class", toJson c), ("out", toJson (ratStr (darkness l c)))]) ++
  worstCases.map (fun gs => o [("kind", "worst"), ("in", gradesJson gs), ("out", gradeName (worst gs))]) ++
  restedCases.map (fun (n, rs, i) =>
    o [("kind", "rested"), ("name", toJson n), ("rows", rowsJson rs), ("i", toJson i), ("out", toJson (restedBefore rs i))]) ++
  swapCases.map (fun (n, rs, st) =>
    o [("kind", "swaps"), ("name", toJson n), ("rows", rowsJson rs), ("still", toJson st),
      ("spans", toJson ((swapSpans rs st).map fun (f, t) => [f, t])),
      ("holds", toJson ((swapSpans rs st).map (holdFrames rs))),
      ("out", toJson ((swapSpans rs st).map fun sp => seriesJson (swapSeries rs sp)))]) ++
  carouselCases.map (fun (n, b, c) =>
    let cc := carouselCell carouselDpr b c
    o [("kind", "carousel"), ("name", toJson n), ("dpr", toJson (ratStr carouselDpr)), ("base", rowsJson b), ("cand", rowsJson c),
      ("swaps", toJson [cc.swaps.1, cc.swaps.2]), ("holds", toJson [holdsOf b, holdsOf c]), ("reps", gradesJson cc.reps), ("grade", gradeName cc.grade)]) ++
  painCellCases.map (fun (n, (ub, uc), (db, dc)) =>
    o [("kind", "paincell"), ("name", toJson n), ("up", toJson [vecJson ub, vecJson uc]), ("down", toJson [vecJson db, vecJson dc]),
      ("reps", gradesJson (painCell (ub, uc) (db, dc))), ("grade", gradeName (worst (painCell (ub, uc) (db, dc))))]) ++
  kinkCases.map (fun (n, fs) =>
    o [("kind", "kinkcell"), ("name", toJson n), ("tols", vecJson panelCellTols), ("minCovered", toJson 8),
      ("ref", seriesJson kinkRef), ("frames", seriesJson fs),
      ("plain", gradeName (matchedGrade panelCellTols [] 1 8 kinkRef fs)),
      ("grade", gradeName (panelCell panelCellTols 8 kinkRef fs))]) ++
  settleCases.map (fun (n, st, p, fs) =>
    let r := settleRun st settleCapMs 0 ⟨p, false, 0⟩ 0 fs 0
    o [("kind", "settle"), ("name", toJson n), ("still", toJson st), ("cap", toJson (ratStr settleCapMs)), ("prev", toJson p),
      ("frames", framesJson fs), ("consumed", toJson r.1), ("quiet", toJson r.2)]) ++
  tailCases.map (fun (n, ms, st, fs) =>
    let r := tailRun ms st none 0 fs 0
    o [("kind", "tail"), ("name", toJson n), ("ms", toJson (ratStr ms)), ("still", toJson st), ("cap", toJson (ratStr tailCapMs)),
      ("frames", framesJson fs), ("rows", toJson r.1), ("quiet", toJson r.2)])

def goldenText (_ : Unit := ()) : String := String.intercalate "" ((goldenLines ()).map (· ++ "\n"))

def main (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"trajectory-gpu golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"trajectory-gpu golden: {path} differs from the generated bytes"
    return 1
  | [] =>
    IO.print (goldenText ())
    return 0
  | _ =>
    IO.eprintln "usage: TrajectoryGpu [--check <file>]"
    return 2

end Fw.Gate.TrajectoryGpu
