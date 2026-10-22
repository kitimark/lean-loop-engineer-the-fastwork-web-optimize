import Lean.Data.Json
import Fw.Gate.PathPix
import Fw.Parts.MorphPanel
/-!
# GPU trajectory cells: clip rect, matched cell, panel lag, pain flip
Spec of the reducers in `packages/gate-breakpoints/src/trajectory/cells-gpu.mjs`, checked against `golden/gate/trajectory-gpu.jsonl`.
-/
namespace Fw.Gate.TrajectoryGpu
open Lean
open Fw.Gate.PathPix (Grade)
open Fw.Parts.MorphPanel (panelOpacity panelBlurPx panelScale)

/-! ## Tolerance and the cell -/

/-- Half a device pixel: the most two geometry readings of one cell may differ. -/
def PixTol : Rat := 1 / 2

/-- `PixTol` in CSS px at a device pixel ratio. -/
def tolCss (dpr : Rat) : Rat := PixTol / dpr

/-- A device pixel ratio above zero turns the CSS tolerance back into `PixTol` device px. -/
theorem tolCss_device (dpr : Rat) (h : 0 < dpr) : tolCss dpr * dpr = PixTol := by
  unfold tolCss
  rw [Rat.div_mul_cancel (by grind)]

/-- `y` lies within `t` of `x`. -/
def Within (t x y : Rat) : Prop := x - t ≤ y ∧ y ≤ x + t

instance (t x y : Rat) : Decidable (Within t x y) := inferInstanceAs (Decidable (_ ∧ _))

/-- Two cell readings are equal when every component is within its own tolerance and the lengths agree. -/
def cellEq : List Rat → List Rat → List Rat → Bool
  | [], [], [] => true
  | t :: ts, x :: xs, y :: ys => decide (Within t x y) && cellEq ts xs ys
  | _, _, _ => false

/-- The statement `cellEq` decides, component by component. -/
def CellEq : List Rat → List Rat → List Rat → Prop
  | [], [], [] => True
  | t :: ts, x :: xs, y :: ys => Within t x y ∧ CellEq ts xs ys
  | _, _, _ => False

/-- A cell is equal exactly when the lengths agree and every component lies within its tolerance. -/
theorem cell_eq_iff (ts a b : List Rat) : cellEq ts a b = true ↔ CellEq ts a b := by
  induction ts generalizing a b with
  | nil => cases a <;> cases b <;> simp [cellEq, CellEq]
  | cons t ts ih => cases a <;> cases b <;> simp [cellEq, CellEq, ih]

/-- A cell equals itself under any non-negative tolerances of its own length. -/
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

/-- Cell equality is symmetric. -/
theorem cellEq_symm (ts a b : List Rat) : cellEq ts a b = true → cellEq ts b a = true := by
  induction ts generalizing a b with
  | nil => cases a <;> cases b <;> simp [cellEq]
  | cons t ts ih =>
    cases a <;> cases b <;> simp only [cellEq, Bool.and_eq_true, decide_eq_true_eq, Bool.false_eq_true, imp_self]
    rename_i x xs y ys
    intro h
    exact ⟨by unfold Within at h ⊢; grind, ih xs ys h.2⟩

/-! ## Clip-path inset to one rect and radius -/

/-- A length of an inset: CSS px or a percent of the reference box side. -/
inductive Len where
  | px (v : Rat)
  | pct (v : Rat)
  deriving DecidableEq, Repr

/-- The length in px on a reference side. -/
def Len.resolve : Len → Rat → Rat
  | .px v, _ => v
  | .pct v, side => v * side / 100

/-- A rectangle: left, top, width, height in CSS px. -/
structure Box where
  x : Rat
  y : Rat
  w : Rat
  h : Rat
  deriving DecidableEq, Repr

/-- One rect and one corner radius, the common form of a clip and of a border box. -/
structure Shape where
  rect : Box
  r : Rat
  deriving DecidableEq, Repr

/-- A computed `inset()`: four sides (top, right, bottom, left) and optional corner radii (top-left, top-right,
bottom-right, bottom-left). -/
structure Inset where
  top : Len
  right : Len
  bottom : Len
  left : Len
  radii : Option (Len × Len × Len × Len)
  deriving DecidableEq, Repr

/-- The CSS four-value expansion of one to four values. -/
def expand4 {α : Type} : List α → Option (α × α × α × α)
  | [a] => some (a, a, a, a)
  | [a, b] => some (a, b, a, b)
  | [a, b, c] => some (a, b, c, b)
  | [a, b, c, d] => some (a, b, c, d)
  | _ => none

/-- One value sets all four. -/
theorem expand4_one {α : Type} (a : α) : expand4 [a] = some (a, a, a, a) := rfl
/-- Two values set the opposite pairs. -/
theorem expand4_two {α : Type} (a b : α) : expand4 [a, b] = some (a, b, a, b) := rfl
/-- Three values set the left side to the right one. -/
theorem expand4_three {α : Type} (a b c : α) : expand4 [a, b, c] = some (a, b, c, b) := rfl
/-- Four values are taken as they are. -/
theorem expand4_four {α : Type} (a b c d : α) : expand4 [a, b, c, d] = some (a, b, c, d) := rfl
/-- No value, or more than four, is no expansion. -/
theorem expand4_none {α : Type} (xs : List α) (h : xs.length = 0 ∨ 5 ≤ xs.length) : expand4 xs = none := by
  match xs, h with
  | [], _ => rfl
  | _ :: _ :: _ :: _ :: _ :: _, _ => rfl

/-- The radius a box really gets: a corner radius shrinks until two neighbouring corners fit the shorter side. -/
def usedRadius (r w h : Rat) : Rat := min r (min (w / 2) (h / 2))

/-- A radius that fits is kept. -/
theorem usedRadius_of_fits (r w h : Rat) (h1 : r ≤ w / 2) (h2 : r ≤ h / 2) : usedRadius r w h = r := by
  unfold usedRadius; grind

/-- A radius never exceeds half of either side. -/
theorem usedRadius_le (r w h : Rat) : usedRadius r w h ≤ w / 2 ∧ usedRadius r w h ≤ h / 2 := by
  unfold usedRadius; grind

/-- The shape of a border box with a uniform `border-radius`. -/
def shapeOfBox (b : Box) (r : Rat) : Shape := ⟨b, usedRadius r b.w b.h⟩

/-- The rect an `inset()` leaves of a border box; a side longer than the box leaves an empty rect. -/
def insetRect (box : Box) (i : Inset) : Box :=
  let l := i.left.resolve box.w
  let rt := i.right.resolve box.w
  let t := i.top.resolve box.h
  let bt := i.bottom.resolve box.h
  ⟨box.x + l, box.y + t, max 0 (box.w - l - rt), max 0 (box.h - t - bt)⟩

/-- The shape of a rect under optional corner radii (top-left, top-right, bottom-right, bottom-left), or none when the
corners differ. Percent radii read their own axis, so a corner counts only when its two radii agree. -/
def radiusShape (rect : Box) : Option (Len × Len × Len × Len) → Option Shape
  | none => some ⟨rect, 0⟩
  | some (tl, tr, br, bl) =>
    let rx (c : Len) := c.resolve rect.w
    let ry (c : Len) := c.resolve rect.h
    if [tl, tr, br, bl].all (fun c => rx c == rx tl && ry c == rx tl) then some (shapeOfBox rect (rx tl)) else none

/-- The clip rect and radius of an `inset()` on a border box, or none when the four corners differ. -/
def clipRect_of_inset (box : Box) (i : Inset) : Option Shape := radiusShape (insetRect box i) i.radii

/-- Rat `max 0 v` is `v` for a non-negative `v`. -/
theorem max_zero_of_nonneg (v : Rat) (h : 0 ≤ v) : max 0 v = v := by
  rw [Rat.max_def]; grind

/-- A zero inset leaves the border box. -/
theorem insetRect_zero (box : Box) (radii : Option (Len × Len × Len × Len)) (hw : 0 ≤ box.w) (hh : 0 ≤ box.h) :
    insetRect box ⟨.px 0, .px 0, .px 0, .px 0, radii⟩ = box := by
  obtain ⟨x, y, w, h⟩ := box
  have e1 : w - 0 - 0 = w := by grind
  have e2 : h - 0 - 0 = h := by grind
  have e3 : x + 0 = x := by grind
  have e4 : y + 0 = y := by grind
  simp only [insetRect, Len.resolve, e1, e2, e3, e4, max_zero_of_nonneg w hw, max_zero_of_nonneg h hh]

/-- No inset and no radius is the border box with a square corner. -/
theorem clip_no_inset (box : Box) (hw : 0 ≤ box.w) (hh : 0 ≤ box.h) :
    clipRect_of_inset box ⟨.px 0, .px 0, .px 0, .px 0, none⟩ = some ⟨box, 0⟩ := by
  unfold clipRect_of_inset
  rw [insetRect_zero box none hw hh]
  rfl

/-- A zero inset with a radius is the border box with that radius, so the flag-off border box and the flag-on clip read
as one shape. -/
theorem clip_round_eq_border_box (box : Box) (r : Rat) (hw : 0 ≤ box.w) (hh : 0 ≤ box.h) :
    clipRect_of_inset box ⟨.px 0, .px 0, .px 0, .px 0, some (.px r, .px r, .px r, .px r)⟩ = some (shapeOfBox box r) := by
  unfold clipRect_of_inset
  rw [insetRect_zero box _ hw hh]
  simp [radiusShape, Len.resolve]

/-- Px insets cut from a union box `u` down to a rect `p` inside it give back `p`: the clip of the fixed-size nav is its
pill. -/
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

/-- A second corner whose radius differs from the first in either axis gives no single radius. -/
theorem clip_nonuniform (rect : Box) (a b c d : Len)
    (hne : b.resolve rect.w ≠ a.resolve rect.w ∨ b.resolve rect.h ≠ a.resolve rect.w) :
    radiusShape rect (some (a, b, c, d)) = none := by
  simp only [radiusShape, List.all_cons, List.all_nil, Bool.and_true, Bool.and_eq_true, beq_iff_eq]
  rw [ite_eq_right_iff]
  intro h
  grind

/-! ## Reading a computed clip-path -/

/-- The value of a digit string, or none when it is empty or holds another character. -/
def digitsVal (cs : List Char) : Option Nat :=
  if cs.isEmpty then none
  else cs.foldlM (fun acc c => if c.isDigit then some (acc * 10 + (c.toNat - 48)) else none) 0

/-- A signed decimal number as an exact rational; an exponent, a bare `5.` or an empty string is none. -/
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

/-- A length in px or percent; a bare `0` is 0 px; any other unit is none. -/
def parseLen (s : String) : Option Len :=
  if s == "0" then some (.px 0)
  else if s.endsWith "px" then (parseDec (s.dropEnd 2).toString).map .px
  else if s.endsWith "%" then (parseDec (s.dropEnd 1).toString).map .pct
  else none

/-- The lengths of a token list, or none when one fails. -/
def parseLens (ts : List String) : Option (List Len) := ts.mapM parseLen

/-- A computed `inset(<1-4 lengths> [round <1-4 lengths>])`, or none for anything else. -/
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

/-- The shape a nav reads as: its border box and radius when `clip-path` is `none`, else the clip of the border box. -/
def readShape (box : Box) (radius : Rat) (clip : String) : Option Shape :=
  if clip == "none" then some (shapeOfBox box radius)
  else (parseInset clip).bind (clipRect_of_inset box)

/-- With no clip the nav reads as its border box. -/
theorem readShape_none (box : Box) (r : Rat) : readShape box r "none" = some (shapeOfBox box r) := by
  simp [readShape]

/-- Five numbers a shape is compared by: x, y, width, height, radius. -/
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

/-! ## One series against another at a matched clock -/

/-- The absolute value of a rational. -/
def absR (x : Rat) : Rat := if x < 0 then -x else x

/-- A reading series: samples keyed by a clock, each a vector of cell components. -/
abbrev Series := List (Rat × List Rat)

/-- The point `f` of the way from `a` to `b`, component by component; none when the lengths differ. -/
def lerpVec (f : Rat) : List Rat → List Rat → Option (List Rat)
  | [], [] => some []
  | a :: as, b :: bs => (lerpVec f as bs).map fun r => (a + (b - a) * f) :: r
  | _, _ => none

/-- The start of a segment is returned at fraction 0. -/
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

/-- The end of a segment is returned at fraction 1. -/
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

/-- The keys of a series rise strictly. -/
def sortedKeys : Series → Bool
  | a :: b :: r => decide (a.1 < b.1) && sortedKeys (b :: r)
  | _ => true

/-- The ends of the morph value, where the page keeps settling while the value stays clamped (A/A on the 1280 close: the nav
width moves 3 px with the value at 0), so the rows there are not a function of the value. -/
def edge : Rat := 1 / 100

/-- The interior of a series: the samples whose key is strictly between `edge` and `1 - edge`. -/
def interior (s : Series) : Series := s.filter fun p => decide (edge < p.1) && decide (p.1 < 1 - edge)

/-- Every kept sample lies inside the interval and was in the series. -/
theorem mem_interior (s : Series) (p : Rat × List Rat) (h : p ∈ interior s) :
    p ∈ s ∧ edge < p.1 ∧ p.1 < 1 - edge := by
  simp only [interior, List.mem_filter, Bool.and_eq_true, decide_eq_true_eq] at h
  exact ⟨h.1, h.2.1, h.2.2⟩

/-- A sample inside the interval is kept. -/
theorem interior_mem (s : Series) (p : Rat × List Rat) (h : p ∈ s) (h1 : edge < p.1) (h2 : p.1 < 1 - edge) :
    p ∈ interior s := by
  simp only [interior, List.mem_filter, Bool.and_eq_true, decide_eq_true_eq]
  exact ⟨h, h1, h2⟩

/-- The series read between its samples by straight lines; none outside its first and last key. -/
def interpAt : Series → Rat → Option (List Rat)
  | (k0, v0) :: (k1, v1) :: rest, k =>
    if k < k0 then none
    else if k ≤ k1 then (if k0 < k1 then lerpVec ((k - k0) / (k1 - k0)) v0 v1 else none)
    else interpAt ((k1, v1) :: rest) k
  | [(k0, v0)], k => if k == k0 then some v0 else none
  | [], _ => none

/-- Before the first key there is no reading. -/
theorem interp_below (k0 k : Rat) (v : List Rat) (t : Series) (h : k < k0) : interpAt ((k0, v) :: t) k = none := by
  cases t with
  | nil => simp [interpAt]; grind
  | cons p r => obtain ⟨k1, v1⟩ := p; simp [interpAt, h]

/-- At the first key the first sample is returned. -/
theorem interp_first_key (k0 k1 : Rat) (v0 v1 : List Rat) (t : Series) (hk : k0 < k1) (hl : v0.length = v1.length) :
    interpAt ((k0, v0) :: (k1, v1) :: t) k0 = some v0 := by
  have h1 : ¬ k1 < k0 := by grind
  have h2 : k0 ≤ k1 := by grind
  have h0 : (k0 - k0) / (k1 - k0) = 0 := by rw [Rat.sub_self, Rat.div_def, Rat.zero_mul]
  simp [interpAt, hk, h2, h0, lerpVec_zero v0 v1 hl]

/-- Components that agree on a cell: how many of the candidate's samples fall inside the reference, and whether all of
those match the reference read at `k + shift`. -/
def matchAt (tols : List Rat) (ref cand : Series) (shift : Rat) : Nat × Bool :=
  cand.foldl (fun (n, ok) (k, v) =>
    match interpAt ref (k + shift) with
    | some r => (n + 1, ok && cellEq tols r v)
    | none => (n, ok)) (0, true)

/-- The grade of a candidate series against a reference on a matched clock.

E: every covered sample matches the reference at its own key. Q: not at its own key but at one shift of the grid with
at most one frame (a frame is `frameKey` keys). L: at no such shift. None: a series is unsorted, or fewer than
`minCovered` samples fall inside the reference, so nothing is compared. E here is equality within the tolerances at the
same clock, not byte equality. -/
def matchedGrade (tols grid : List Rat) (frameKey : Rat) (minCovered : Nat) (ref cand : Series) : Option Grade :=
  if !sortedKeys ref || !sortedKeys cand || (matchAt tols ref cand 0).1 < minCovered then none
  else if (matchAt tols ref cand 0).2 then some .e
  else if grid.any (fun s => s != 0 && decide (absR s ≤ 1) &&
      decide (minCovered ≤ (matchAt tols ref cand (s * frameKey)).1) && (matchAt tols ref cand (s * frameKey)).2)
  then some .q else some .l

/-- An unsorted reference compares nothing. -/
theorem matched_unsorted_ref (tols grid : List Rat) (fk : Rat) (n : Nat) (ref cand : Series)
    (h : sortedKeys ref = false) : matchedGrade tols grid fk n ref cand = none := by
  simp [matchedGrade, h]

/-- Too few covered samples compare nothing. -/
theorem matched_under_covered (tols grid : List Rat) (fk : Rat) (n : Nat) (ref cand : Series)
    (h : (matchAt tols ref cand 0).1 < n) : matchedGrade tols grid fk n ref cand = none := by
  simp [matchedGrade, h]

/-- Matching at the own key is E. -/
theorem matched_e (tols grid : List Rat) (fk : Rat) (n : Nat) (ref cand : Series)
    (hr : sortedKeys ref = true) (hc : sortedKeys cand = true) (hn : n ≤ (matchAt tols ref cand 0).1)
    (hm : (matchAt tols ref cand 0).2 = true) : matchedGrade tols grid fk n ref cand = some .e := by
  have : ¬ (matchAt tols ref cand 0).1 < n := by grind
  simp [matchedGrade, hr, hc, this, hm]

/-- No match at the own key and none within a frame is L. -/
theorem matched_l (tols grid : List Rat) (fk : Rat) (n : Nat) (ref cand : Series)
    (hr : sortedKeys ref = true) (hc : sortedKeys cand = true) (hn : n ≤ (matchAt tols ref cand 0).1)
    (hm : (matchAt tols ref cand 0).2 = false)
    (hg : grid.any (fun s => s != 0 && decide (absR s ≤ 1) &&
      decide (n ≤ (matchAt tols ref cand (s * fk)).1) && (matchAt tols ref cand (s * fk)).2) = false) :
    matchedGrade tols grid fk n ref cand = some .l := by
  have : ¬ (matchAt tols ref cand 0).1 < n := by grind
  simp [matchedGrade, hr, hc, this, hm, hg]

/-- A match at a shift of the grid within a frame, none at the own key, is Q. -/
theorem matched_q (tols grid : List Rat) (fk : Rat) (n : Nat) (ref cand : Series)
    (hr : sortedKeys ref = true) (hc : sortedKeys cand = true) (hn : n ≤ (matchAt tols ref cand 0).1)
    (hm : (matchAt tols ref cand 0).2 = false)
    (hg : grid.any (fun s => s != 0 && decide (absR s ≤ 1) &&
      decide (n ≤ (matchAt tols ref cand (s * fk)).1) && (matchAt tols ref cand (s * fk)).2) = true) :
    matchedGrade tols grid fk n ref cand = some .q := by
  have : ¬ (matchAt tols ref cand 0).1 < n := by grind
  simp [matchedGrade, hr, hc, this, hm, hg]

/-! ## The panel effect and its clock -/

/-- The three panel effect components at a morph value: opacity, blur in px, scale. -/
def effectAt (m : Rat) : List Rat := [panelOpacity m, panelBlurPx m, panelScale m]

/-- The step of a reading: the probe reports the scale in thousandths, and half a device px across a 390 px panel is 0.00064,
under that step (an A/A rep read 0.9900 against an interpolated 0.9890). -/
def readStep : Rat := 1 / 1000

/-- Tolerances of the three components: an alpha step of 1/100, half a device px of blur, and half a device px across
a panel `side` CSS px wide plus one reading step for the scale. -/
def effectTols (dpr side : Rat) : List Rat := [1 / 100, tolCss dpr, tolCss dpr / side + readStep]

/-- The morph value at which the faithful panel has opacity `p`. -/
def effClock (p : Rat) : Rat := 2 / 25 + 18 / 25 * p

/-- On the panel's own stretch of the morph the opacity reads back as the morph value. -/
theorem effClock_opacity (m : Rat) (h0 : 2 / 25 ≤ m) (h1 : m ≤ 4 / 5) : effClock (panelOpacity m) = m := by
  have hp : Fw.Parts.MorphPanel.panelProgress m = (m - 2 / 25) / (18 / 25) := by
    unfold Fw.Parts.MorphPanel.panelProgress Fw.Parts.MorphPanel.clamp01
    have a : 0 ≤ (m - 2 / 25) / (18 / 25) := by grind
    have b : (m - 2 / 25) / (18 / 25) ≤ 1 := by grind
    rw [Rat.min_def, Rat.max_def]; grind
  unfold effClock panelOpacity
  rw [hp]
  grind

/-- A frame of the panel lag series: the nav's morph value and the panel's opacity. -/
structure LagFrame where
  nav : Rat
  op : Rat
  deriving DecidableEq, Repr

/-- How many frames the panel's clock trails the nav's at the second frame: the gap between the nav's morph value and the
one the panel's opacity belongs to, over the nav's step. None when the opacity is at an end or the nav did not move. -/
def lagAt (prev cur : LagFrame) : Option Rat :=
  if 0 < cur.op && cur.op < 1 && prev.nav != cur.nav then some ((cur.nav - effClock cur.op) / (cur.nav - prev.nav))
  else none

/-- The panel clock in step with the nav is no lag. -/
theorem lagAt_sync (prev cur : LagFrame) (h0 : 0 < cur.op) (h1 : cur.op < 1) (hn : prev.nav ≠ cur.nav)
    (hs : cur.nav = effClock cur.op) : lagAt prev cur = some 0 := by
  have : (cur.nav - effClock cur.op) = 0 := by grind
  have hz : (0 : Rat) / (cur.nav - prev.nav) = 0 := by rw [Rat.div_def, Rat.zero_mul]
  simp [lagAt, h0, h1, hn, this, hz]

/-- A panel clock one nav step behind is one frame of lag. -/
theorem lagAt_one_frame (prev cur : LagFrame) (h0 : 0 < cur.op) (h1 : cur.op < 1) (hn : prev.nav ≠ cur.nav)
    (hs : effClock cur.op = prev.nav) : lagAt prev cur = some 1 := by
  have hne : cur.nav - prev.nav ≠ 0 := by grind
  have hd : (cur.nav - prev.nav) / (cur.nav - prev.nav) = 1 := by rw [Rat.div_def]; exact Rat.mul_inv_cancel _ hne
  simp [lagAt, h0, h1, hn, hs, hd]

/-- The largest lag in frames over the consecutive frames that have one; none under three of them. -/
def lagFrames (fs : List LagFrame) : Option Rat :=
  let ls := ((fs.zip fs.tail).filterMap fun (p, c) => lagAt p c).map absR
  if ls.length < 3 then none else some (ls.foldl max 0)

/-- A lag of one frame reads within a tenth of a frame of 1: the opacity and the morph value are read in thousandths. -/
def lagSlack : Rat := 1 / 10

/-- Q when the panel trails the nav by at most one frame (and the reading slack), else L. -/
def lagGrade (lag : Rat) : Grade := if lag ≤ 1 + lagSlack then .q else .l

/-- One frame or less is Q. -/
theorem lagGrade_q (lag : Rat) (h : lag ≤ 1) : lagGrade lag = .q := by
  have : lag ≤ 1 + lagSlack := by unfold lagSlack; grind
  simp [lagGrade, this]

/-- Past one frame and the reading slack is L. -/
theorem lagGrade_l (lag : Rat) (h : 1 + lagSlack < lag) : lagGrade lag = .l := by
  have : ¬ lag ≤ 1 + lagSlack := by grind
  simp [lagGrade, this]

#guard lagGrade (21 / 20) == .q
#guard lagGrade (6 / 5) == .l

/-- The key a frame's effect is read at when the panel trails the nav by `l` frames: the nav's morph value `l` of its own
steps back, `cur - l * (cur - prev)`. -/
def laggedKey (l prev cur : Rat) : Rat := cur - l * (cur - prev)

/-- A zero lag reads at the frame's own key. -/
theorem laggedKey_zero (prev cur : Rat) : laggedKey 0 prev cur = cur := by
  unfold laggedKey; grind

/-- One frame of lag reads at the previous frame's key. -/
theorem laggedKey_one (prev cur : Rat) : laggedKey 1 prev cur = prev := by
  unfold laggedKey; grind

/-- The effect series at the lagged clock: each frame after the first (a pair of morph value and all three effect readings)
re-keyed by `laggedKey`, and only its interior kept. -/
def laggedSeries (l : Rat) (fs : Series) : Series :=
  interior ((fs.zip fs.tail).map fun (p, c) => (laggedKey l p.1 c.1, c.2))

/-- The series grade at the lagged clock: E when opacity, blur and scale all match the reference there, L when not (no
shift grid, so no Q), none when the lagged series is unsorted or covers too little. -/
def shiftedGrade (tols : List Rat) (minCovered : Nat) (ref : Series) (l : Rat) (fs : Series) : Option Grade :=
  matchedGrade tols [] 1 minCovered ref (laggedSeries l fs)

/-- The panel cell from the series grade at the own clock, the lag in frames, and the series grade at the lagged clock.

E: the series matches at the own clock. Otherwise the lag must be readable and at most one frame (and the reading slack),
and all three components must match at the lagged clock: that is Q, anything else L. None: no series was compared, or no
lag can be read. -/
def panelGrade (series : Option Grade) (lag : Option Rat) (shifted : Option Grade) : Option Grade :=
  match series with
  | none => none
  | some .e => some .e
  | some _ =>
    match lag with
    | none => none
    | some l => if l ≤ 1 + lagSlack && shifted == some .e then some .q else some .l

/-- Equal series need no lag. -/
theorem panelGrade_e (lag : Option Rat) (sh : Option Grade) : panelGrade (some .e) lag sh = some .e := rfl

/-- A series that differs without a readable lag has no grade. -/
theorem panelGrade_no_lag (g : Grade) (h : g ≠ .e) (sh : Option Grade) : panelGrade (some g) none sh = none := by
  cases g <;> simp_all [panelGrade]

/-- A series that differs and matches at no shift within one frame grades L, whatever the lag. -/
theorem panelGrade_no_match_l (g : Grade) (h : g ≠ .e) (l : Rat) (sh : Option Grade) (hs : sh ≠ some .e) :
    panelGrade (some g) (some l) sh = some .l := by
  cases g <;> simp_all [panelGrade]

/-- A lag past one frame and the reading slack is L even when the lagged clock matches. -/
theorem panelGrade_long_lag_l (g : Grade) (h : g ≠ .e) (l : Rat) (hl : 1 + lagSlack < l) (sh : Option Grade) :
    panelGrade (some g) (some l) sh = some .l := by
  have : ¬ l ≤ 1 + lagSlack := by grind
  cases g <;> simp_all [panelGrade]

/-- A differing series that matches at the lagged clock within one frame is Q. -/
theorem panelGrade_short_lag_q (g : Grade) (h : g ≠ .e) (l : Rat) (hl : l ≤ 1 + lagSlack) :
    panelGrade (some g) (some l) (some .e) = some .q := by
  cases g <;> simp_all [panelGrade]

/-- Only a lagged series that matched every covered sample reference-side grades E. -/
theorem matched_e_ok (tols grid : List Rat) (fk : Rat) (n : Nat) (ref cand : Series)
    (h : matchedGrade tols grid fk n ref cand = some .e) : (matchAt tols ref cand 0).2 = true := by
  unfold matchedGrade at h
  split at h
  · simp at h
  · split at h
    · assumption
    · split at h <;> simp at h

/-- A lagged clock with a covered sample that differs is not E. -/
theorem shiftedGrade_ne_e (tols : List Rat) (n : Nat) (ref : Series) (l : Rat) (fs : Series)
    (h : (matchAt tols ref (laggedSeries l fs) 0).2 = false) : shiftedGrade tols n ref l fs ≠ some .e := by
  intro he
  have := matched_e_ok _ _ _ _ _ _ he
  simp_all

/-- The panel cell of a run from its frames (morph value and the effect readings in time order) against the reference. -/
def panelCell (tols : List Rat) (minCovered : Nat) (ref : Series) (fs : Series) : Option Grade :=
  let series := matchedGrade tols [] 1 minCovered ref (interior fs)
  let lag := lagFrames (fs.map fun f => ⟨f.1, f.2.headD 0⟩)
  panelGrade series lag (lag.bind fun l => shiftedGrade tols minCovered ref l fs)

/-! ## The pain section's dark layer across scroll offsets -/

/-- How dark the section is: the layer's opacity when the layer exists, else the class on (1) or off (0). -/
def darkness (layer : Option Rat) (cls : Bool) : Rat :=
  match layer with
  | some o => o
  | none => if cls then 1 else 0

/-- The opacity of a present layer is the darkness. -/
theorem darkness_layer (o : Rat) (c : Bool) : darkness (some o) c = o := rfl

/-- Without a layer the class decides. -/
theorem darkness_class (c : Bool) : darkness none c = if c then 1 else 0 := rfl

/-- How many times a series changes value between neighbours. -/
def changes (l : List Rat) : Nat := ((l.zip l.tail).filter fun (a, b) => a != b).length

/-- The grade of the candidate's darkness against the base across the same scroll offsets.

E: equal within 1/100 everywhere. Q: every mismatch is a flip (both values 0 or 1) that sits one offset away from the
base's flip, and both change the same number of times. L: any other mismatch. None: the series differ in length or are empty. -/
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

/-- A series equals itself. -/
theorem painGrade_refl (b : List Rat) (h : b ≠ []) : painGrade b b = some .e := by
  have hb : b.isEmpty = false := by cases b <;> simp_all
  have hall : (List.range b.length).all (fun i => decide (Within (1 / 100) (b.getD i 0) (b.getD i 0))) = true := by
    simp only [List.all_eq_true, List.mem_range, decide_eq_true_eq]
    intro i _
    unfold Within
    grind
  simp only [painGrade, bne_self_eq_false, hb, Bool.or_self, Bool.false_eq_true, ite_false, hall, ite_true]

/-- Lists of different lengths compare nothing. -/
theorem painGrade_length (b c : List Rat) (h : b.length ≠ c.length) : painGrade b c = none := by
  simp [painGrade, h]

#guard painGrade [0, 0, 1, 1] [0, 1, 1, 1] == some .q
#guard painGrade [0, 0, 1, 1] [0, 0, 0, 1] == some .q
#guard painGrade [0, 0, 1, 1] [0, 0, 1, 1] == some .e
#guard painGrade [0, 0, 1, 1] [0, 1, 0, 1] == some .l
#guard painGrade [0, 0, 1, 1] [1, 1, 1, 1] == some .l
#guard painGrade [0, 1 / 2, 1] [0, 3 / 4, 1] == some .l
#guard painGrade [0, 1] [0] == none

/-! ## Golden vectors -/

/-- A rational as `n/d`. -/
def ratStr (r : Rat) : String := s!"{r.num}/{r.den}"

/-- A list of rationals as strings. -/
def vecJson (v : List Rat) : Json := toJson (v.map ratStr)

/-- A box as four strings. -/
def boxJson (b : Box) : Json := vecJson [b.x, b.y, b.w, b.h]

/-- A length as `px:n/d` or `pct:n/d`. -/
def lenStr : Len → String
  | .px v => "px:" ++ ratStr v
  | .pct v => "pct:" ++ ratStr v

/-- An inset as its four sides and its optional radii. -/
def insetJson (i : Inset) : Json :=
  Json.mkObj [("sides", toJson ([i.top, i.right, i.bottom, i.left].map lenStr)),
    ("radii", match i.radii with
      | none => Json.null
      | some (a, b, c, d) => toJson ([a, b, c, d].map lenStr))]

/-- A series as pairs of key and vector. -/
def seriesJson (s : Series) : Json := toJson (s.map fun (k, v) => Json.mkObj [("k", toJson (ratStr k)), ("v", vecJson v)])

/-- A series from a step, a count and a function of the key. -/
def ramp (n : Nat) (step : Rat) (f : Rat → List Rat) : Series := (List.range n).map fun (i : Nat) => ((i : Rat) * step, f ((i : Rat) * step))

/-- Name of an optional grade. -/
def gradeName (g : Option Grade) : Json := toJson (g.map Grade.name)

/-- The boxes and clips read by the golden `clip` lines: a name, border box, border radius, computed clip-path. -/
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

/-- Cell comparison cases: tolerances, left, right. -/
def cellCases : List (List Rat × List Rat × List Rat) :=
  [([1 / 2, 1 / 2], [1, 2], [3 / 2, 5 / 2]), ([1 / 2, 1 / 2], [1, 2], [2, 2]), ([1 / 2], [1, 2], [1]),
   ([], [], []), ([1 / 100], [1], [101 / 100]), ([1 / 100], [1], [102 / 100]), ([0], [5], [5])]

/-- A table for the interpolation lines. -/
def interpTable : Series := [(0, [0, 10]), (1, [10, 20]), (3, [10, 0])]

/-- Matched-grade cases: name, tolerances, shift grid, frame key, minimum covered, reference, candidate. -/
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

/-- Frames of a panel whose clock trails the nav by `d` steps. -/
def lagFramesOf (d : Rat) (navs : List Rat) : List LagFrame :=
  navs.map fun n => ⟨n, panelOpacity (n - d / 10)⟩

/-- The nav's morph values: 0.1 steps through the panel's stretch. -/
def navSteps : List Rat := (List.range 9).map fun (i : Nat) => (i : Rat) / 10 + 1 / 10

/-- Lag cases: a name and the frames. -/
def lagCases : List (String × List LagFrame) :=
  [("in step", lagFramesOf 0 navSteps), ("one frame behind", lagFramesOf 1 navSteps),
   ("two frames behind", lagFramesOf 2 navSteps), ("half a frame behind", lagFramesOf (1 / 2) navSteps),
   ("too few frames", lagFramesOf 0 [1 / 10, 1 / 5]), ("nav stands still", lagFramesOf 0 [1 / 5, 1 / 5, 1 / 5, 1 / 5, 1 / 5]),
   ("opacity at an end", [⟨1, 1⟩, ⟨11 / 10, 1⟩, ⟨6 / 5, 1⟩, ⟨13 / 10, 1⟩])]

/-- Pain cases: base and candidate darkness. -/
def painCases : List (String × List Rat × List Rat) :=
  [("equal", [0, 0, 1, 1], [0, 0, 1, 1]), ("flip one step early", [0, 0, 1, 1], [0, 1, 1, 1]),
   ("flip one step late", [0, 0, 1, 1], [0, 0, 0, 1]), ("flip two steps early", [0, 0, 0, 1, 1], [0, 1, 1, 1, 1]),
   ("flicker", [0, 0, 1, 1], [0, 1, 0, 1]), ("always dark", [0, 0, 1, 1], [1, 1, 1, 1]),
   ("ramp differs", [0, 1 / 2, 1], [0, 3 / 4, 1]), ("ramp inside tolerance", [0, 1 / 2, 1], [0, 501 / 1000, 1]),
   ("length differs", [0, 1], [0]), ("empty", [], []), ("reverse", [1, 1, 0, 0], [1, 0, 0, 0])]

/-- Series, lag and lagged-series cases for the panel grade: name, series grade, lag, series grade at the lagged clock. -/
def panelCases : List (String × Option Grade × Option Rat × Option Grade) :=
  [("equal", some .e, some 3, none), ("short lag", some .l, some 1, some .e),
   ("short lag, lagged clock differs", some .l, some 1, some .l), ("short lag, lagged clock not compared", some .l, some 1, none),
   ("long lag", some .l, some (3 / 2), some .e), ("no lag", some .l, none, some .e), ("no series", none, some 0, some .e),
   ("series q", some .q, some (1 / 2), some .e), ("series q, lagged clock differs", some .q, some (1 / 2), some .l)]

/-- The reference of the panel cell cases: the faithful effect every two-hundredth of the morph, so the kinks at 2/25 and 4/5
lie on the grid and the straight lines between neighbours are exact. -/
def panelRef : Series := ramp 201 (1 / 200) effectAt

/-- Panel frames whose effect trails the nav by `d` twentieths of the morph, with a component overridden by `f`. -/
def panelFrames (d : Rat) (f : List Rat → List Rat) : Series :=
  (List.range 21).map fun (i : Nat) => ((i : Rat) / 20, f (effectAt ((i : Rat) / 20 - d / 20)))

/-- Panel cell cases: name and frames. The candidate drops the blur or the scale while its opacity, and so its lag, stay as the
faithful panel's. -/
def panelCellCases : List (String × Series) :=
  [("in step", panelFrames 0 id), ("one frame behind", panelFrames 1 id),
   ("one frame behind, blur dropped", panelFrames 1 fun v => [v.getD 0 0, 0, v.getD 2 1]),
   ("one frame behind, scale dropped", panelFrames 1 fun v => [v.getD 0 0, v.getD 1 0, 1]),
   ("in step, blur dropped", panelFrames 0 fun v => [v.getD 0 0, 0, v.getD 2 1]),
   ("in step, scale dropped", panelFrames 0 fun v => [v.getD 0 0, v.getD 1 0, 1]),
   ("two frames behind", panelFrames 2 id), ("half a frame behind", panelFrames (1 / 2) id)]

/-- The tolerances of the panel cell cases: a 2x screen and a panel 600 px wide. -/
def panelCellTols : List Rat := effectTols 2 600

#guard (panelCellCases.map fun (_, fs) => panelCell panelCellTols 8 panelRef fs) ==
  [some .e, some .q, some .l, some .l, some .l, some .l, some .l, some .q]

/-- The lines of `packages/contracts/golden/gate/trajectory-gpu.jsonl`. -/
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
  panelCellCases.map (fun (n, fs) =>
    o [("kind", "panelcell"), ("name", toJson n), ("tols", vecJson panelCellTols), ("minCovered", toJson 8),
      ("ref", seriesJson panelRef), ("frames", seriesJson fs),
      ("lag", toJson ((lagFrames (fs.map fun f => ⟨f.1, f.2.headD 0⟩)).map ratStr)),
      ("grade", gradeName (panelCell panelCellTols 8 panelRef fs))]) ++
  painCases.map (fun (n, b, c) =>
    o [("kind", "pain"), ("name", toJson n), ("base", vecJson b), ("cand", vecJson c), ("grade", gradeName (painGrade b c))]) ++
  [(some (1 / 2 : Rat), false), (some 0, true), (none, true), (none, false)].map (fun (l, c) =>
    o [("kind", "dark"), ("layer", toJson (l.map ratStr)), ("class", toJson c), ("out", toJson (ratStr (darkness l c)))])

/-- The exact bytes of `packages/contracts/golden/gate/trajectory-gpu.jsonl`: the lines, each newline-terminated. -/
def goldenText (_ : Unit := ()) : String := String.intercalate "" ((goldenLines ()).map (· ++ "\n"))

/-- Print the golden text, or with `--check <file>` exit 0 iff the file holds exactly these bytes. -/
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
