import Fw.Engine.Core
import Fw.Gate.Compare
/-!
# The visual observable (design note 2026-10-18 §2.1-2.2, PLAN §4.7)

A *scene* is the list of boxes a page shows at one instant, each with geometry, ink rect, paint-relevant computed
values, accumulated transform, effective opacity, clip, filter and paint order. `visible vp` drops boxes that paint
nothing inside the viewport. Pixels are never defined: every visual theorem is quantified over an arbitrary
`R : Scene → α`, so equal visible scenes are identical inputs to rasterization.

Two relations compare scenes:
* **E** is equality;
* **Q** is the breakpoint gate's own closeness: `Gate.near Gate.tolBox` (½ CSS px, PL1) on box, ink and translation
  numbers, `Gate.styleValueEq` and `Gate.near Gate.tolStyle` ($10^{-3}$, PL2) on paint values, opacity, the linear
  part of the transform and filter arguments. No other tolerance is introduced.

`VisSame` is the theorem shape for one part: for every environment and every instant, the original's and the
variant's visible scenes are related. `PathPremises` carries C1-C3 (H1-H3 in PLAN) as hypotheses, never axioms: with
them, E-equal scenes give equal shown pixels (`shown_eq`).
-/
namespace Fw.Engine

open Fw.Gate (near tolBox tolStyle styleValueEq)

/-! ## Scenes -/

/-- An axis-aligned rectangle in CSS px: origin and size.

$$\mathrm{Rect} = \mathbb{Q}^{4},\qquad r = (x, y, w, h)$$
-/
structure Rect where
  x : Rat
  y : Rat
  w : Rat
  h : Rat
deriving Repr, DecidableEq

/-- A 2D affine transform, mapping $(x, y)$ to $(a x + c y + e,\ b x + d y + f)$.

$$\mathrm{Affine} = \mathbb{Q}^{6},\qquad m = (a, b, c, d, e, f)$$
-/
structure Affine where
  a : Rat
  b : Rat
  c : Rat
  d : Rat
  e : Rat
  f : Rat
deriving Repr, DecidableEq

/-- A clip shape: a rectangle in the box's local coordinates, or another shape named by its computed value.

$$\mathrm{Shape} = \mathrm{rect}(\mathrm{Rect}) \mid \mathrm{other}(\mathrm{String})$$
-/
inductive Shape where
  | rect (r : Rect)
  | other (key : String)
deriving Repr, DecidableEq

/-- One filter function: its name and numeric arguments (as in the computed `filter` value).

$$\mathrm{FilterOp} = \mathrm{String} \times \mathbb{Q}^{*}$$
-/
structure FilterOp where
  name : String
  args : List Rat
deriving Repr, DecidableEq

/-- A box identifier (a stable selector or part-local name).

$$\mathrm{BoxId} = \mathrm{String}$$
-/
abbrev BoxId := String

/-- What one box contributes to the picture. `box` is the border box (what PL1 measures); `ink` is the box's own ink
overflow rect (border box plus shadows, outline, filter outsets and its own overflowing text), both in local
coordinates; `paint` lists the paint-relevant computed values that differ from their initial values (what PL2
measures); `xf` maps local coordinates to viewport coordinates; `alpha` is the effective opacity; `clip` is in local
coordinates; `order` is the paint order.

$$\mathrm{BoxVis} = \underbrace{\mathrm{Rect}}_{\mathrm{box}} \times \underbrace{\mathrm{Rect}}_{\mathrm{ink}} \times \underbrace{(\mathrm{String} \times \mathrm{String})^{*}}_{\mathrm{paint}} \times \underbrace{\mathrm{Affine}}_{\mathrm{xf}} \times \underbrace{\mathbb{Q}}_{\mathrm{alpha}} \times \underbrace{\mathrm{Shape}_{\bot}}_{\mathrm{clip}} \times \underbrace{\mathrm{FilterOp}^{*}}_{\mathrm{filter}} \times \underbrace{\mathbb{N}}_{\mathrm{order}}$$
-/
structure BoxVis where
  box    : Rect
  ink    : Rect
  paint  : List (String × String)
  xf     : Affine
  alpha  : Rat
  clip   : Option Shape
  filter : List FilterOp
  order  : Nat
deriving Repr, DecidableEq

/-- A scene: the boxes shown at one instant, in a fixed order.

$$\mathrm{Scene} = (\mathrm{BoxId} \times \mathrm{BoxVis})^{*}$$
-/
abbrev Scene := List (BoxId × BoxVis)

/-- Two rectangles overlap with positive area.

$$\operatorname{meets}(r, s) \iff 0 < r.w \land 0 < s.w \land r.x < s.x + s.w \land s.x < r.x + r.w \land 0 < r.h \land 0 < s.h \land r.y < s.y + s.h \land s.y < r.y + r.h$$
-/
def Rect.meets (r s : Rect) : Bool :=
  decide (0 < r.w) && decide (0 < s.w) && decide (r.x < s.x + s.w) && decide (s.x < r.x + r.w) &&
    decide (0 < r.h) && decide (0 < s.h) && decide (r.y < s.y + s.h) && decide (s.y < r.y + r.h)

/-- The image of a point under an affine transform.

$$m(p) = (a\, p_1 + c\, p_2 + e,\ b\, p_1 + d\, p_2 + f)$$
-/
def Affine.apply (m : Affine) (p : Rat × Rat) : Rat × Rat :=
  (m.a * p.1 + m.c * p.2 + m.e, m.b * p.1 + m.d * p.2 + m.f)

/-- The bounding box of a rectangle's image: the smallest axis-aligned rectangle holding its four transformed corners
(an affine map sends the rectangle to the convex hull of those corners).

$$\operatorname{bbox}(m, r) = \big(x_0,\ y_0,\ x_1 - x_0,\ y_1 - y_0\big),\qquad x_0 = \min_{p \in C} m(p)_1,\ x_1 = \max_{p \in C} m(p)_1,\ y_0 = \min_{p \in C} m(p)_2,\ y_1 = \max_{p \in C} m(p)_2,\qquad C = \{(r.x, r.y), (r.x + r.w, r.y), (r.x, r.y + r.h), (r.x + r.w, r.y + r.h)\}$$
-/
def Affine.bbox (m : Affine) (r : Rect) : Rect :=
  let p1 := m.apply (r.x, r.y)
  let p2 := m.apply (r.x + r.w, r.y)
  let p3 := m.apply (r.x, r.y + r.h)
  let p4 := m.apply (r.x + r.w, r.y + r.h)
  let x0 := min (min p1.1 p2.1) (min p3.1 p4.1)
  let x1 := max (max p1.1 p2.1) (max p3.1 p4.1)
  let y0 := min (min p1.2 p2.2) (min p3.2 p4.2)
  let y1 := max (max p1.2 p2.2) (max p3.2 p4.2)
  ⟨x0, y0, x1 - x0, y1 - y0⟩

/-- A box paints nothing in the viewport when its effective opacity is at most 0, its computed `visibility` is
`hidden`, its rectangular clip does not meet its ink, or its transformed ink does not meet the viewport. Every rule
only drops boxes that paint nothing, so `visible` keeps every box that paints (occlusion is not modelled: an
occluded box is kept). `lookup` takes the first entry with that key; a missing key never drops. A clip that is absent
or not a rectangle never drops.

$$\operatorname{drop}_{vp}(b) \iff b.\mathrm{alpha} \le 0 \ \lor\ \operatorname{lookup}(\texttt{"visibility"}, b.\mathrm{paint}) = \mathrm{some}(\texttt{"hidden"}) \ \lor\ \big(\exists r:\ b.\mathrm{clip} = \mathrm{some}(\mathrm{rect}(r)) \land \neg\operatorname{meets}(r, b.\mathrm{ink})\big) \ \lor\ \neg\operatorname{meets}(vp, \operatorname{bbox}(b.\mathrm{xf}, b.\mathrm{ink}))$$
-/
def BoxVis.drop (vp : Rect) (b : BoxVis) : Bool :=
  decide (b.alpha ≤ 0) || b.paint.lookup "visibility" == some "hidden" ||
    (match b.clip with
      | some (.rect r) => !(r.meets b.ink)
      | _ => false) ||
    !(vp.meets (b.xf.bbox b.ink))

/-- The visible part of a scene: the boxes that are not dropped, in scene order.

$$\operatorname{visible}_{vp}(S) = [\,(i, b) \in S \mid \neg\operatorname{drop}_{vp}(b)\,]$$
-/
def visible (vp : Rect) (s : Scene) : Scene := s.filter fun e => !(e.2.drop vp)

/-- The identity transform. -/
private def idXf : Affine := ⟨1, 0, 0, 1, 0, 0⟩

private def demoBox (alpha : Rat) (paint : List (String × String)) (ink : Rect) : BoxVis :=
  ⟨⟨0, 0, 10, 10⟩, ink, paint, idXf, alpha, none, [], 0⟩

#guard (visible ⟨0, 0, 100, 100⟩ [("a", demoBox 1 [] ⟨0, 0, 10, 10⟩)]).length == 1
#guard (visible ⟨0, 0, 100, 100⟩ [("a", demoBox 0 [] ⟨0, 0, 10, 10⟩)]).length == 0
#guard (visible ⟨0, 0, 100, 100⟩ [("a", demoBox 1 [("visibility", "hidden")] ⟨0, 0, 10, 10⟩)]).length == 0
#guard (visible ⟨0, 0, 100, 100⟩ [("a", demoBox 1 [] ⟨200, 0, 10, 10⟩)]).length == 0
#guard (visible ⟨0, 0, 100, 100⟩ [("a", demoBox 1 [] ⟨100, 0, 10, 10⟩)]).length == 0
#guard (visible ⟨0, 0, 100, 100⟩ [("a", demoBox 1 [] ⟨99, 0, 10, 10⟩)]).length == 1
#guard (visible ⟨0, 0, 100, 100⟩ [("a", { demoBox 1 [] ⟨0, 0, 10, 10⟩ with clip := some (.rect ⟨20, 0, 5, 5⟩) })]).length == 0
#guard (visible ⟨0, 0, 100, 100⟩ [("a", { demoBox 1 [] ⟨200, 0, 10, 10⟩ with xf := ⟨1, 0, 0, 1, -150, 0⟩ })]).length == 1

/-! ## The relations E and Q -/

/-- Class E: the two scenes are equal.

$$\mathrm{E}(S, U) \iff S = U$$
-/
def E (s u : Scene) : Prop := s = u

/-- Two rectangles agree within tolerance `t` in every coordinate.

$$\operatorname{nearRect}_t(r, s) \iff \operatorname{near}_t(r.x, s.x) \land \operatorname{near}_t(r.y, s.y) \land \operatorname{near}_t(r.w, s.w) \land \operatorname{near}_t(r.h, s.h)$$
-/
def nearRect (t : Rat) (r s : Rect) : Bool := near t r.x s.x && near t r.y s.y && near t r.w s.w && near t r.h s.h

/-- Two transforms agree: the linear part within the style tolerance, the translation within the box tolerance.

$$\operatorname{xfQ}(m, n) \iff \bigwedge_{z \in \{a, b, c, d\}} \operatorname{near}_{t_{\mathrm{style}}}(m.z, n.z) \land \bigwedge_{z \in \{e, f\}} \operatorname{near}_{t_{\mathrm{box}}}(m.z, n.z)$$
-/
def xfQ (m n : Affine) : Bool :=
  near tolStyle m.a n.a && near tolStyle m.b n.b && near tolStyle m.c n.c && near tolStyle m.d n.d &&
    near tolBox m.e n.e && near tolBox m.f n.f

/-- Two paint lists agree: same length, the same property names in the same order, and each value pair equal under
the gate's computed-style comparison (PL2).

$$\operatorname{paintQ}(p, q) \iff |p| = |q| \land \forall i < |p|:\ p_i.1 = q_i.1 \land \operatorname{styleValueEq}(\mathrm{some}(p_i.2), \mathrm{some}(q_i.2)) = \mathrm{true}$$
-/
def paintQ : List (String × String) → List (String × String) → Bool
  | [], [] => true
  | x :: xs, y :: ys => x.1 == y.1 && styleValueEq (some x.2) (some y.2) && paintQ xs ys
  | _, _ => false

/-- Two number lists agree within tolerance `t`: same length, each pair `near`.

$$\operatorname{numsQ}_t(x, y) \iff |x| = |y| \land \forall i < |x|:\ \operatorname{near}_t(x_i, y_i)$$
-/
def numsQ (t : Rat) : List Rat → List Rat → Bool
  | [], [] => true
  | x :: xs, y :: ys => near t x y && numsQ t xs ys
  | _, _ => false

/-- Two filter lists agree: same length, the same function names in order, arguments within the style tolerance.

$$\operatorname{filterQ}(F, G) \iff |F| = |G| \land \forall i < |F|:\ F_i.\mathrm{name} = G_i.\mathrm{name} \land \operatorname{numsQ}_{t_{\mathrm{style}}}(F_i.\mathrm{args}, G_i.\mathrm{args})$$
-/
def filterQ : List FilterOp → List FilterOp → Bool
  | [], [] => true
  | x :: xs, y :: ys => x.name == y.name && numsQ tolStyle x.args y.args && filterQ xs ys
  | _, _ => false

/-- Two clips agree: both absent, both rectangles within the box tolerance, or both the same other shape.

$$\operatorname{clipQ}(k, l) \iff (k = l = \bot) \lor (k = \mathrm{rect}(r) \land l = \mathrm{rect}(r') \land \operatorname{nearRect}_{t_{\mathrm{box}}}(r, r')) \lor (k = \mathrm{other}(n) \land l = \mathrm{other}(n') \land n = n')$$
-/
def clipQ : Option Shape → Option Shape → Bool
  | none, none => true
  | some (.rect r), some (.rect r') => nearRect tolBox r r'
  | some (.other n), some (.other n') => n == n'
  | _, _ => false

/-- Two boxes agree under Q: box and ink within ½ px, transform per `xfQ`, paint per `paintQ`, opacity within
$10^{-3}$, clip per `clipQ`, filter per `filterQ`, and the same paint order.

$$\operatorname{boxQ}(b, c) \iff \operatorname{nearRect}_{t_{\mathrm{box}}}(b.\mathrm{box}, c.\mathrm{box}) \land \operatorname{nearRect}_{t_{\mathrm{box}}}(b.\mathrm{ink}, c.\mathrm{ink}) \land \operatorname{xfQ}(b.\mathrm{xf}, c.\mathrm{xf}) \land \operatorname{paintQ}(b.\mathrm{paint}, c.\mathrm{paint}) \land \operatorname{near}_{t_{\mathrm{style}}}(b.\mathrm{alpha}, c.\mathrm{alpha}) \land \operatorname{clipQ}(b.\mathrm{clip}, c.\mathrm{clip}) \land \operatorname{filterQ}(b.\mathrm{filter}, c.\mathrm{filter}) \land b.\mathrm{order} = c.\mathrm{order}$$
-/
def boxQ (b c : BoxVis) : Bool :=
  nearRect tolBox b.box c.box && nearRect tolBox b.ink c.ink && xfQ b.xf c.xf && paintQ b.paint c.paint &&
    near tolStyle b.alpha c.alpha && clipQ b.clip c.clip && filterQ b.filter c.filter && b.order == c.order

/-- Two scenes agree under Q as a Boolean: same length, the same box ids in order, each box pair `boxQ`.

$$\operatorname{sceneQ}(S, U) \iff |S| = |U| \land \forall i < |S|:\ S_i.1 = U_i.1 \land \operatorname{boxQ}(S_i.2, U_i.2)$$
-/
def sceneQ : Scene → Scene → Bool
  | [], [] => true
  | x :: xs, y :: ys => x.1 == y.1 && boxQ x.2 y.2 && sceneQ xs ys
  | _, _ => false

/-- Class Q: the two scenes agree within the breakpoint gate's tolerances.

$$\mathrm{Q}(S, U) \iff \operatorname{sceneQ}(S, U) = \mathrm{true}$$
-/
def Q (s u : Scene) : Prop := sceneQ s u = true

#guard sceneQ [("a", demoBox 1 [("color", "rgb(0, 0, 0)")] ⟨0, 0, 10, 10⟩)]
  [("a", demoBox (9995 / 10000) [("color", "rgb(0, 0, 0.0004)")] ⟨0, 0, 10.5, 10⟩)]
#guard !sceneQ [("a", demoBox 1 [] ⟨0, 0, 10, 10⟩)] [("a", demoBox 1 [] ⟨0, 0, 10.6, 10⟩)]
#guard !sceneQ [("a", demoBox 1 [] ⟨0, 0, 10, 10⟩)] [("a", demoBox (998 / 1000) [] ⟨0, 0, 10, 10⟩)]
#guard !sceneQ [("a", demoBox 1 [] ⟨0, 0, 10, 10⟩)] [("b", demoBox 1 [] ⟨0, 0, 10, 10⟩)]
#guard !sceneQ [("a", demoBox 1 [] ⟨0, 0, 10, 10⟩)] []

/-! ## Q is reflexive and symmetric; E implies Q -/

/-- A number is near itself under a non-negative tolerance.

$$\forall t, x \in \mathbb{Q}:\ 0 \le t \Rightarrow \operatorname{near}_t(x, x)$$
-/
theorem near_self {t : Rat} (ht : 0 ≤ t) (x : Rat) : near t x x = true := by
  simp [near, Rat.sub_self, ht]

/-- The box tolerance is non-negative.

$$0 \le t_{\mathrm{box}} = \tfrac12$$
-/
theorem tolBox_nonneg : (0 : Rat) ≤ tolBox := by unfold tolBox; decide +kernel

/-- The style tolerance is non-negative.

$$0 \le t_{\mathrm{style}} = 10^{-3}$$
-/
theorem tolStyle_nonneg : (0 : Rat) ≤ tolStyle := by unfold tolStyle; decide +kernel

/-- `nearRect` is reflexive for a non-negative tolerance and symmetric for every tolerance.

$$\forall t \in \mathbb{Q},\ \forall r, s \in \mathrm{Rect}:\ (0 \le t \Rightarrow \operatorname{nearRect}_t(r, r)) \land \operatorname{nearRect}_t(r, s) = \operatorname{nearRect}_t(s, r)$$
-/
theorem nearRect_refl_comm (t : Rat) (r s : Rect) :
    (0 ≤ t → nearRect t r r = true) ∧ nearRect t r s = nearRect t s r := by
  refine ⟨fun ht => by simp [nearRect, near_self ht], ?_⟩
  simp only [nearRect, Gate.near_comm t r.x, Gate.near_comm t r.y, Gate.near_comm t r.w, Gate.near_comm t r.h]

/-- `numsQ` is reflexive for a non-negative tolerance and symmetric for every tolerance.

$$\forall t \in \mathbb{Q},\ \forall x, y \in \mathbb{Q}^{*}:\ (0 \le t \Rightarrow \operatorname{numsQ}_t(x, x)) \land \operatorname{numsQ}_t(x, y) = \operatorname{numsQ}_t(y, x)$$
-/
theorem numsQ_refl_comm (t : Rat) : ∀ (x y : List Rat), (0 ≤ t → numsQ t x x = true) ∧ numsQ t x y = numsQ t y x
  | [], [] => ⟨fun _ => rfl, rfl⟩
  | [], _ :: _ => ⟨fun _ => rfl, rfl⟩
  | a :: as, [] => ⟨fun ht => by simp [numsQ, near_self ht, (numsQ_refl_comm t as []).1 ht], rfl⟩
  | a :: as, b :: bs => by
    refine ⟨fun ht => by simp [numsQ, near_self ht, (numsQ_refl_comm t as bs).1 ht], ?_⟩
    simp only [numsQ, Gate.near_comm t a b, (numsQ_refl_comm t as bs).2]

/-- `paintQ` is reflexive and symmetric.

$$\forall p, q \in (\mathrm{String} \times \mathrm{String})^{*}:\ \operatorname{paintQ}(p, p) \land \operatorname{paintQ}(p, q) = \operatorname{paintQ}(q, p)$$
-/
theorem paintQ_refl_comm : ∀ (p q : List (String × String)), paintQ p p = true ∧ paintQ p q = paintQ q p
  | [], [] => ⟨rfl, rfl⟩
  | [], _ :: _ => ⟨rfl, rfl⟩
  | x :: xs, [] => ⟨by simp [paintQ, Gate.styleValueEq_refl, (paintQ_refl_comm xs []).1], rfl⟩
  | x :: xs, y :: ys => by
    refine ⟨by simp [paintQ, Gate.styleValueEq_refl, (paintQ_refl_comm xs ys).1], ?_⟩
    simp only [paintQ, Gate.beq_swap x.1 y.1, Gate.styleValueEq_comm (some x.2), (paintQ_refl_comm xs ys).2]

/-- `filterQ` is reflexive and symmetric.

$$\forall F, G \in \mathrm{FilterOp}^{*}:\ \operatorname{filterQ}(F, F) \land \operatorname{filterQ}(F, G) = \operatorname{filterQ}(G, F)$$
-/
theorem filterQ_refl_comm : ∀ (F G : List FilterOp), filterQ F F = true ∧ filterQ F G = filterQ G F
  | [], [] => ⟨rfl, rfl⟩
  | [], _ :: _ => ⟨rfl, rfl⟩
  | x :: xs, [] =>
    ⟨by simp [filterQ, (numsQ_refl_comm tolStyle x.args x.args).1 tolStyle_nonneg, (filterQ_refl_comm xs []).1],
      rfl⟩
  | x :: xs, y :: ys => by
    refine ⟨by simp [filterQ, (numsQ_refl_comm tolStyle x.args x.args).1 tolStyle_nonneg,
      (filterQ_refl_comm xs ys).1], ?_⟩
    simp only [filterQ, Gate.beq_swap x.name y.name, (numsQ_refl_comm tolStyle x.args y.args).2,
      (filterQ_refl_comm xs ys).2]

/-- `clipQ` is reflexive and symmetric.

$$\forall k, l \in \mathrm{Shape}_{\bot}:\ \operatorname{clipQ}(k, k) \land \operatorname{clipQ}(k, l) = \operatorname{clipQ}(l, k)$$
-/
theorem clipQ_refl_comm (k l : Option Shape) : clipQ k k = true ∧ clipQ k l = clipQ l k := by
  constructor
  · rcases k with _ | (r | n)
    · rfl
    · simp [clipQ, (nearRect_refl_comm tolBox r r).1 tolBox_nonneg]
    · simp [clipQ]
  · rcases k with _ | (r | n) <;> rcases l with _ | (r' | n') <;> simp only [clipQ]
    · exact (nearRect_refl_comm tolBox r r').2
    · exact Gate.beq_swap n n'

/-- `xfQ` is reflexive and symmetric.

$$\forall m, n \in \mathrm{Affine}:\ \operatorname{xfQ}(m, m) \land \operatorname{xfQ}(m, n) = \operatorname{xfQ}(n, m)$$
-/
theorem xfQ_refl_comm (m n : Affine) : xfQ m m = true ∧ xfQ m n = xfQ n m := by
  refine ⟨by simp [xfQ, near_self tolStyle_nonneg, near_self tolBox_nonneg], ?_⟩
  simp only [xfQ, Gate.near_comm _ m.a, Gate.near_comm _ m.b, Gate.near_comm _ m.c, Gate.near_comm _ m.d,
    Gate.near_comm _ m.e, Gate.near_comm _ m.f]

/-- `boxQ` is reflexive and symmetric.

$$\forall b, c \in \mathrm{BoxVis}:\ \operatorname{boxQ}(b, b) \land \operatorname{boxQ}(b, c) = \operatorname{boxQ}(c, b)$$
-/
theorem boxQ_refl_comm (b c : BoxVis) : boxQ b b = true ∧ boxQ b c = boxQ c b := by
  refine ⟨?_, ?_⟩
  · simp [boxQ, (nearRect_refl_comm tolBox b.box b.box).1 tolBox_nonneg, (nearRect_refl_comm tolBox b.ink b.ink).1 tolBox_nonneg, (xfQ_refl_comm _ b.xf).1,
      (paintQ_refl_comm _ b.paint).1, near_self tolStyle_nonneg, (clipQ_refl_comm _ b.clip).1,
      (filterQ_refl_comm _ b.filter).1]
  · simp only [boxQ, (nearRect_refl_comm tolBox b.box c.box).2, (nearRect_refl_comm tolBox b.ink c.ink).2,
      (xfQ_refl_comm b.xf c.xf).2, (paintQ_refl_comm b.paint c.paint).2, Gate.near_comm tolStyle b.alpha,
      (clipQ_refl_comm b.clip c.clip).2, (filterQ_refl_comm b.filter c.filter).2, Gate.beq_swap b.order c.order]

/-- **Q is reflexive.**

$$\forall S \in \mathrm{Scene}:\ \mathrm{Q}(S, S)$$
-/
theorem Q_refl : ∀ (s : Scene), Q s s
  | [] => rfl
  | x :: xs => by
    have ih := Q_refl xs
    simp only [Q, sceneQ] at ih ⊢
    simp [ih, (boxQ_refl_comm x.2 x.2).1]

/-- `sceneQ` is symmetric as a Boolean.

$$\forall S, U \in \mathrm{Scene}:\ \operatorname{sceneQ}(S, U) = \operatorname{sceneQ}(U, S)$$
-/
theorem sceneQ_comm : ∀ (s u : Scene), sceneQ s u = sceneQ u s
  | [], [] => rfl
  | [], _ :: _ => rfl
  | _ :: _, [] => rfl
  | x :: xs, y :: ys => by
    simp only [sceneQ, Gate.beq_swap x.1 y.1, (boxQ_refl_comm x.2 y.2).2, sceneQ_comm xs ys]

/-- **Q is symmetric.**

$$\forall S, U \in \mathrm{Scene}:\ \mathrm{Q}(S, U) \Rightarrow \mathrm{Q}(U, S)$$
-/
theorem Q_symm {s u : Scene} (h : Q s u) : Q u s := by
  unfold Q at *; rw [sceneQ_comm]; exact h

/-- **E implies Q.**

$$\forall S, U \in \mathrm{Scene}:\ \mathrm{E}(S, U) \Rightarrow \mathrm{Q}(S, U)$$
-/
theorem E_imp_Q {s u : Scene} (h : E s u) : Q s u := by
  unfold E at h; subst h; exact Q_refl s

/-- **Equal scenes give equal pictures.** For every rasterization `R`, E-related scenes have the same image.

$$\forall \alpha,\ \forall R : \mathrm{Scene} \to \alpha,\ \forall S, U \in \mathrm{Scene}:\ \mathrm{E}(S, U) \Rightarrow R(S) = R(U)$$
-/
theorem E_render {α : Type} (R : Scene → α) {s u : Scene} (h : E s u) : R s = R u := by
  unfold E at h; rw [h]

/-! ## The theorem shape and the path premises -/

/-- **The visual theorem shape** for one part: under relation `rel`, for every environment (width band, touch and
hover, DPR) and every instant `t` (time since the push, or scroll offset), the original's visible scene and the
variant's visible scene are related.

$$\operatorname{VisSame}_{\mathit{rel}}(\mathit{vp}, o, v) \iff \forall \mathit{env} \in \mathrm{Env},\ \forall t \in T:\ \mathit{rel}\big(\operatorname{visible}_{\mathit{vp}(\mathit{env})}(o(\mathit{env}, t)),\ \operatorname{visible}_{\mathit{vp}(\mathit{env})}(v(\mathit{env}, t))\big)$$
-/
def VisSame {Env T : Type} (rel : Scene → Scene → Prop) (vp : Env → Rect) (o v : Env → T → Scene) : Prop :=
  ∀ env t, rel (visible (vp env) (o env t)) (visible (vp env) (v env t))

/-- Equal scene functions are `VisSame` under E.

$$\forall \mathit{vp},\ \forall o, v:\ (\forall \mathit{env}, t:\ o(\mathit{env}, t) = v(\mathit{env}, t)) \Rightarrow \operatorname{VisSame}_{\mathrm{E}}(\mathit{vp}, o, v)$$
-/
theorem visSame_of_eq {Env T : Type} (vp : Env → Rect) {o v : Env → T → Scene}
    (h : ∀ env t, o env t = v env t) : VisSame E vp o v := by
  intro env t; unfold E; rw [h env t]

/-- `VisSame` under E gives `VisSame` under Q.

$$\forall \mathit{vp},\ \forall o, v:\ \operatorname{VisSame}_{\mathrm{E}}(\mathit{vp}, o, v) \Rightarrow \operatorname{VisSame}_{\mathrm{Q}}(\mathit{vp}, o, v)$$
-/
theorem visSame_E_Q {Env T : Type} {vp : Env → Rect} {o v : Env → T → Scene} (h : VisSame E vp o v) :
    VisSame Q vp o v :=
  fun env t => E_imp_Q (h env t)

/-- `VisSame` under Q is symmetric in the two arms.

$$\forall \mathit{vp},\ \forall o, v:\ \operatorname{VisSame}_{\mathrm{Q}}(\mathit{vp}, o, v) \Rightarrow \operatorname{VisSame}_{\mathrm{Q}}(\mathit{vp}, v, o)$$
-/
theorem visSame_Q_symm {Env T : Type} {vp : Env → Rect} {o v : Env → T → Scene} (h : VisSame Q vp o v) :
    VisSame Q vp v o :=
  fun env t => Q_symm (h env t)

/-- `VisSame` under E gives equal pictures, for every rasterization, environment and instant.

$$\forall \alpha,\ \forall R : \mathrm{Scene} \to \alpha,\ \forall \mathit{vp}, o, v:\ \operatorname{VisSame}_{\mathrm{E}}(\mathit{vp}, o, v) \Rightarrow \forall \mathit{env}, t:\ R\big(\operatorname{visible}_{\mathit{vp}(\mathit{env})}(o(\mathit{env}, t))\big) = R\big(\operatorname{visible}_{\mathit{vp}(\mathit{env})}(v(\mathit{env}, t))\big)$$
-/
theorem visSame_render {α Env T : Type} (R : Scene → α) {vp : Env → Rect} {o v : Env → T → Scene}
    (h : VisSame E vp o v) :
    ∀ env t, R (visible (vp env) (o env t)) = R (visible (vp env) (v env t)) :=
  fun env t => E_render R (h env t)

/-- **The path premises C1-C3** (H1-H3 in PLAN) for one part, as hypotheses, never axioms. The engine rasterizes a
visible scene under a path assignment (main thread or compositor per box) with `raster`; per the raster model
(`raster_path`) the path matters only for boxes with LCD-antialiased text or a compositor scale animation.
* **C1** (`c1`): no box whose path differs between the arms has LCD text.
* **C2** (`c2`): no box whose path differs between the arms has a compositor scale animation.
* **C3** (`c3o`, `c3v`): what each arm shows at frame time `t` is the raster of its own value function at `t`
  (the compositor samples the same function at its own frame time).

$$\mathrm{PathPremises}_{\mathrm{Img}}(\mathit{vp}, o, v) = \Big(\mathit{raster} : (\mathrm{BoxId} \to \mathrm{Thread}) \to \mathrm{Scene} \to \mathrm{Img},\ \mathit{lcd}, \mathit{cs} : \mathrm{BoxId} \to \mathbb{B},\ \pi_o, \pi_v : \mathrm{Env} \to T \to \mathrm{BoxId} \to \mathrm{Thread},\ \mathit{shown}_o, \mathit{shown}_v : \mathrm{Env} \to T \to \mathrm{Img}\Big) \text{ such that } \begin{cases} \forall p, q : \mathrm{BoxId} \to \mathrm{Thread},\ \forall S \in \mathrm{Scene}:\ \big(\forall i:\ p(i) \ne q(i) \Rightarrow \neg\mathit{lcd}(i) \land \neg\mathit{cs}(i)\big) \Rightarrow \mathit{raster}(p, S) = \mathit{raster}(q, S) & \text{(raster\_path)} \\ \forall \mathit{env}, t, i:\ \pi_o(\mathit{env}, t)(i) \ne \pi_v(\mathit{env}, t)(i) \Rightarrow \neg\mathit{lcd}(i) & \text{(C1)} \\ \forall \mathit{env}, t, i:\ \pi_o(\mathit{env}, t)(i) \ne \pi_v(\mathit{env}, t)(i) \Rightarrow \neg\mathit{cs}(i) & \text{(C2)} \\ \forall \mathit{env}, t:\ \mathit{shown}_o(\mathit{env}, t) = \mathit{raster}\big(\pi_o(\mathit{env}, t), \operatorname{visible}_{\mathit{vp}(\mathit{env})}(o(\mathit{env}, t))\big) & \text{(C3)} \\ \forall \mathit{env}, t:\ \mathit{shown}_v(\mathit{env}, t) = \mathit{raster}\big(\pi_v(\mathit{env}, t), \operatorname{visible}_{\mathit{vp}(\mathit{env})}(v(\mathit{env}, t))\big) & \text{(C3)} \end{cases}$$
-/
structure PathPremises {Env T : Type} (Img : Type) (vp : Env → Rect) (o v : Env → T → Scene) where
  raster    : (BoxId → Thread) → Scene → Img
  lcdText   : BoxId → Bool
  compScale : BoxId → Bool
  pathO     : Env → T → BoxId → Thread
  pathV     : Env → T → BoxId → Thread
  shownO    : Env → T → Img
  shownV    : Env → T → Img
  raster_path : ∀ (p q : BoxId → Thread) (s : Scene),
    (∀ i, p i ≠ q i → lcdText i = false ∧ compScale i = false) → raster p s = raster q s
  c1  : ∀ env t i, pathO env t i ≠ pathV env t i → lcdText i = false
  c2  : ∀ env t i, pathO env t i ≠ pathV env t i → compScale i = false
  c3o : ∀ env t, shownO env t = raster (pathO env t) (visible (vp env) (o env t))
  c3v : ∀ env t, shownV env t = raster (pathV env t) (visible (vp env) (v env t))

/-- **Same scene, same pixels.** Under the path premises C1-C3, `VisSame` under E gives the same shown pixels for
every environment and every instant.

$$\forall \mathit{vp}, o, v,\ \forall P \in \mathrm{PathPremises}(\mathit{vp}, o, v):\ \operatorname{VisSame}_{\mathrm{E}}(\mathit{vp}, o, v) \Rightarrow \forall \mathit{env}, t:\ P.\mathit{shown}_o(\mathit{env}, t) = P.\mathit{shown}_v(\mathit{env}, t)$$
-/
theorem shown_eq {Img Env T : Type} {vp : Env → Rect} {o v : Env → T → Scene}
    (P : PathPremises Img vp o v) (h : VisSame E vp o v) : ∀ env t, P.shownO env t = P.shownV env t := by
  intro env t
  rw [P.c3o, P.c3v, h env t]
  exact P.raster_path _ _ _ fun i hi => ⟨P.c1 env t i hi, P.c2 env t i hi⟩

/-! ## Why the path premises need C4 and C5 (ledger n=6, 13, 18, 24)

`raster_path` says the path (main thread or compositor) matters only for LCD text and compositor scale. Two toy
one-pixel rasters show two more cases where it matters: a fractional translate (layout snaps to device pixels, the
compositor resamples) and a fractional group opacity over a separately rastered layer (two 8-bit roundings against
one). `PathPremises5` adds both as exceptions (C4, C5) and keeps `shown_eq`. -/

/-- Round half up to an integer.

$$\operatorname{rnd}(x) = \lfloor x + \tfrac12 \rfloor$$

The 8-bit quantiser used by the toy rasters. -/
def roundQ (x : Rat) : Int := (x + 1 / 2).floor

#guard roundQ (3 / 10 * 255) == 77
#guard roundQ (1 / 2 * 77) == 39
#guard roundQ (1 / 2 * (3 / 10) * 255) == 38
#guard roundQ (255 / 2) == 128

/-- The raster premise of `PathPremises` for a given raster function and exception sets.

$$\operatorname{RasterPathOK}(\mathit{raster}, \mathit{lcd}, \mathit{cs}) \iff \forall p, q : \mathrm{BoxId} \to \mathrm{Thread},\ \forall S \in \mathrm{Scene}:\ \big(\forall i:\ p(i) \ne q(i) \Rightarrow \mathit{lcd}(i) = \bot \land \mathit{cs}(i) = \bot\big) \Rightarrow \mathit{raster}(p, S) = \mathit{raster}(q, S)$$

Whether a raster function satisfies C1-C2's raster model. -/
def RasterPathOK {Img : Type} (raster : (BoxId → Thread) → Scene → Img) (lcd cs : BoxId → Bool) : Prop :=
  ∀ (p q : BoxId → Thread) (s : Scene), (∀ i, p i ≠ q i → lcd i = false ∧ cs i = false) → raster p s = raster q s

/-- A one-pixel toy raster of a translated box (C5): the first box covers pixel 0 when unshifted. On the main thread
layout snaps its offset `e` to the nearest device pixel; on the compositor it is rastered at 0 and resampled by `e`.

$$\operatorname{snapToy}(p, S) = \begin{cases} 255\cdot[\operatorname{rnd}(b.\mathrm{xf}.e) = 0] & S = (i, b) :: S' \land p(i) = \mathrm{main} \\ \operatorname{rnd}(255\,(1 - b.\mathrm{xf}.e)) & S = (i, b) :: S' \land p(i) = \mathrm{comp} \\ 0 & S = [\,] \end{cases}$$

A model of pixel snapping against bilinear resampling for offsets in [0, 1]. -/
def snapToy (p : BoxId → Thread) : Scene → Int
  | [] => 0
  | (i, b) :: _ => match p i with
    | .main => if roundQ b.xf.e = 0 then 255 else 0
    | .comp => roundQ (255 * (1 - b.xf.e))

/-- A one-pixel toy raster of a group (C4): the first box is a group with opacity `α`, the second its child with
opacity `β` over white 255. Flattened on the main thread the pixel is one rounding of `αβ·255`; with the child on its
own layer the child is rounded first and the group opacity applied after.

$$\operatorname{alphaToy}(p, S) = \begin{cases} \operatorname{rnd}(\alpha\beta\cdot 255) & S = (g, b_g) :: (i, b_i) :: S' \land p(i) = \mathrm{main} \\ \operatorname{rnd}(\alpha\,\operatorname{rnd}(\beta\cdot 255)) & S = (g, b_g) :: (i, b_i) :: S' \land p(i) = \mathrm{comp} \\ 0 & \text{otherwise} \end{cases},\quad \alpha = b_g.\mathrm{alpha},\ \beta = b_i.\mathrm{alpha}$$

A model of one 8-bit rounding against two. -/
def alphaToy (p : BoxId → Thread) : Scene → Int
  | (_, bg) :: (i, bi) :: _ => match p i with
    | .main => roundQ (bg.alpha * bi.alpha * 255)
    | .comp => roundQ (bg.alpha * roundQ (bi.alpha * 255))
  | _ => 0

/-- A box with only an alpha and a horizontal offset set.

$$\operatorname{toyBox}(\alpha, e) = (\mathrm{box} = \mathrm{ink} = (0,0,1,1),\ \mathrm{paint} = [\,],\ \mathrm{xf} = (1,0,0,1,e,0),\ \mathrm{alpha} = \alpha,\ \mathrm{clip} = \bot,\ \mathrm{filter} = [\,],\ \mathrm{order} = 0)$$

The toy scenes' only box shape. -/
def toyBox (a e : Rat) : BoxVis := ⟨⟨0, 0, 1, 1⟩, ⟨0, 0, 1, 1⟩, [], ⟨1, 0, 0, 1, e, 0⟩, a, none, [], 0⟩

/-- **C5 is needed (n=6, 18).** In the snapping toy, a half-pixel translate makes the path visible although the box has
no LCD text and no compositor scale: the main thread shows 0, the compositor 128.

$$\lnot \operatorname{RasterPathOK}(\operatorname{snapToy}, i \mapsto \bot, i \mapsto \bot),\ \text{witnessed by } S = [(\mathtt{b}, \operatorname{toyBox}(1, \tfrac12))]:\ \operatorname{snapToy}(\mathrm{main}, S) = 0 \ne 128 = \operatorname{snapToy}(\mathrm{comp}, S)$$

Layout snaps, the compositor resamples, so a fractional translate is path-sensitive. -/
theorem raster_path_fails_fracXf :
    snapToy (fun _ => .main) [("b", toyBox 1 (1 / 2))] = 0 ∧
      snapToy (fun _ => .comp) [("b", toyBox 1 (1 / 2))] = 128 ∧
      ¬ RasterPathOK snapToy (fun _ => false) (fun _ => false) := by
  have h1 : snapToy (fun _ => .main) [("b", toyBox 1 (1 / 2))] = 0 := by decide +kernel
  have h2 : snapToy (fun _ => .comp) [("b", toyBox 1 (1 / 2))] = 128 := by decide +kernel
  refine ⟨h1, h2, fun h => ?_⟩
  have := h (fun _ => .main) (fun _ => .comp) [("b", toyBox 1 (1 / 2))] (fun _ _ => ⟨rfl, rfl⟩)
  rw [h1, h2] at this
  exact absurd this (by decide)

/-- In the snapping toy an integral translate is path-free.

$$\operatorname{snapToy}(\mathrm{main}, [(\mathtt{b}, \operatorname{toyBox}(1, 0))]) = \operatorname{snapToy}(\mathrm{comp}, [(\mathtt{b}, \operatorname{toyBox}(1, 0))]) = 255$$

C5 excludes only fractional offsets. -/
theorem snapToy_integral :
    snapToy (fun _ => .main) [("b", toyBox 1 0)] = 255 ∧ snapToy (fun _ => .comp) [("b", toyBox 1 0)] = 255 := by
  decide +kernel

/-- **Double rounding (n=13, 24).** Rounding the child before the group opacity differs from rounding once.

$$\operatorname{rnd}\big(\tfrac12\,\operatorname{rnd}(\tfrac{3}{10}\cdot 255)\big) = 39 \ne 38 = \operatorname{rnd}\big(\tfrac12\cdot\tfrac{3}{10}\cdot 255\big)$$

Layer partition is visible under fractional group opacity. -/
theorem double_round_ne : roundQ (1 / 2 * roundQ (3 / 10 * 255)) = 39 ∧ roundQ (1 / 2 * (3 / 10) * 255) = 38 := by
  decide +kernel

/-- **C4 is needed (n=13, 24).** In the group toy, moving the child to its own layer changes the pixel under group
opacity ½ and child opacity 3/10, although no box has LCD text or compositor scale.

$$\lnot \operatorname{RasterPathOK}(\operatorname{alphaToy}, i \mapsto \bot, i \mapsto \bot),\ \text{witnessed by } S = [(\mathtt{g}, \operatorname{toyBox}(\tfrac12, 0)), (\mathtt{c}, \operatorname{toyBox}(\tfrac{3}{10}, 0))]:\ 38 \ne 39$$

Promoting a box can change its pixels: same scene is not same image. -/
theorem raster_path_fails_fracAlpha :
    alphaToy (fun _ => .main) [("g", toyBox (1 / 2) 0), ("c", toyBox (3 / 10) 0)] = 38 ∧
      alphaToy (fun _ => .comp) [("g", toyBox (1 / 2) 0), ("c", toyBox (3 / 10) 0)] = 39 ∧
      ¬ RasterPathOK alphaToy (fun _ => false) (fun _ => false) := by
  have h1 : alphaToy (fun _ => .main) [("g", toyBox (1 / 2) 0), ("c", toyBox (3 / 10) 0)] = 38 := by
    decide +kernel
  have h2 : alphaToy (fun _ => .comp) [("g", toyBox (1 / 2) 0), ("c", toyBox (3 / 10) 0)] = 39 := by
    decide +kernel
  refine ⟨h1, h2, fun h => ?_⟩
  have := h (fun _ => .main) (fun _ => .comp) [("g", toyBox (1 / 2) 0), ("c", toyBox (3 / 10) 0)]
    (fun _ _ => ⟨rfl, rfl⟩)
  rw [h1, h2] at this
  exact absurd this (by decide)

/-- Rounding an integer gives it back.

$$\forall z \in \mathbb{Z}:\ \operatorname{rnd}(z) = z$$

Quantised values are fixed points. -/
theorem roundQ_int (z : Int) : roundQ (z : Rat) = z := by
  unfold roundQ
  apply Int.le_antisymm
  · have : ((z : Rat) + 1 / 2).floor < z + 1 := Rat.floor_lt_iff.mpr (by rw [Rat.intCast_add]; grind)
    omega
  · exact Rat.le_floor_iff.mpr (by grind)

/-- **Group opacity 0 or 1 is path-free.** In the group toy, the two roundings agree when the group opacity is 0 or
1, for every child opacity: the exception C4 needs only fractional group opacity.

$$\forall a \in \{0, 1\},\ \forall b \in \mathbb{Q}:\ \operatorname{rnd}(a\,\operatorname{rnd}(b\cdot 255)) = \operatorname{rnd}(a b\cdot 255)$$

Whole opacities commute with rounding. -/
theorem double_round_whole (a b : Rat) (ha : a = 0 ∨ a = 1) :
    roundQ (a * roundQ (b * 255)) = roundQ (a * b * 255) := by
  rcases ha with rfl | rfl
  · simp
  · simp only [Rat.one_mul]; exact roundQ_int _

/-- **The path premises with C4 and C5.** As `PathPremises`, with two more raster exceptions: a box with a
non-device-pixel translate (`fracXf`, C5) and a box under a fractional group opacity (`fracAlpha`, C4) may change
pixels with its path, so no box whose path differs may have either.

$$\mathrm{PathPremises5} = \mathrm{PathPremises} \text{ with } \mathit{fracXf}, \mathit{fracAlpha} : \mathrm{BoxId} \to \mathbb{B} \text{ and } \begin{cases} \forall p, q, S:\ \big(\forall i:\ p(i) \ne q(i) \Rightarrow \neg\mathit{lcd}(i) \land \neg\mathit{cs}(i) \land \neg\mathit{fracXf}(i) \land \neg\mathit{fracAlpha}(i)\big) \Rightarrow \mathit{raster}(p, S) = \mathit{raster}(q, S) \\ \forall \mathit{env}, t, i:\ \pi_o(\mathit{env}, t)(i) \ne \pi_v(\mathit{env}, t)(i) \Rightarrow \neg\mathit{lcd}(i) \land \neg\mathit{cs}(i) \land \neg\mathit{fracXf}(i) \land \neg\mathit{fracAlpha}(i) & \text{(C1, C2, C5, C4)} \\ \text{C3 as in PathPremises} \end{cases}$$

The raster model the toy counterexamples force. -/
structure PathPremises5 {Env T : Type} (Img : Type) (vp : Env → Rect) (o v : Env → T → Scene) where
  raster    : (BoxId → Thread) → Scene → Img
  lcdText   : BoxId → Bool
  compScale : BoxId → Bool
  fracXf    : BoxId → Bool
  fracAlpha : BoxId → Bool
  pathO     : Env → T → BoxId → Thread
  pathV     : Env → T → BoxId → Thread
  shownO    : Env → T → Img
  shownV    : Env → T → Img
  raster_path : ∀ (p q : BoxId → Thread) (s : Scene),
    (∀ i, p i ≠ q i → lcdText i = false ∧ compScale i = false ∧ fracXf i = false ∧ fracAlpha i = false) →
      raster p s = raster q s
  c1245 : ∀ env t i, pathO env t i ≠ pathV env t i →
    lcdText i = false ∧ compScale i = false ∧ fracXf i = false ∧ fracAlpha i = false
  c3o : ∀ env t, shownO env t = raster (pathO env t) (visible (vp env) (o env t))
  c3v : ∀ env t, shownV env t = raster (pathV env t) (visible (vp env) (v env t))

/-- **Same scene, same pixels, under C1-C5.**

$$\forall \mathit{vp}, o, v,\ \forall P \in \mathrm{PathPremises5}(\mathit{vp}, o, v):\ \operatorname{VisSame}_{\mathrm{E}}(\mathit{vp}, o, v) \Rightarrow \forall \mathit{env}, t:\ P.\mathit{shown}_o(\mathit{env}, t) = P.\mathit{shown}_v(\mathit{env}, t)$$

E-equal scenes give equal pixels when no path-differing box is LCD, scaled, fractionally shifted or under a fractional
group opacity. -/
theorem shown_eq5 {Img Env T : Type} {vp : Env → Rect} {o v : Env → T → Scene}
    (P : PathPremises5 Img vp o v) (h : VisSame E vp o v) : ∀ env t, P.shownO env t = P.shownV env t := by
  intro env t
  rw [P.c3o, P.c3v, h env t]
  exact P.raster_path _ _ _ fun i hi => P.c1245 env t i hi

/-! ## Quantisation facts (ledger n=17, 19, 21, 25) -/

/-- **A 0.24 px blur tail is not Q-equal to no filter (n=17).** The lists differ in length, and even a zero-radius blur
is out of the style tolerance.

$$\operatorname{filterQ}([\mathrm{blur}(0.24)], [\,]) = \bot \land \operatorname{numsQ}_{t_{\mathrm{style}}}([0.24], [0]) = \bot$$

A visible blur tail is a look change under the gate. -/
theorem tail_not_Q :
    filterQ [⟨"blur", [24 / 100]⟩] [] = false ∧ numsQ tolStyle [24 / 100] [0] = false := by
  unfold tolStyle; decide +kernel

/-- **0.999 opacity is invisible under round-half-up (n=19).** For 8-bit source and destination channels, blending
at 999/1000 and rounding half up gives the source back; quantising the alpha first gives 255, i.e. opaque; only a
floor quantiser breaks it.

$$\forall s, d \in \mathbb{N}:\ s \le 255 \land d \le 255 \Rightarrow \Big\lfloor \tfrac{999 s + d + 500}{1000} \Big\rfloor = s,\qquad \Big\lfloor \tfrac{999\cdot 255 + 500}{1000} \Big\rfloor = 255,\qquad \Big\lfloor \tfrac{999\cdot 255}{1000} \Big\rfloor = 254$$

The 0.999 trick is E exactly when the engine rounds to nearest. -/
theorem alpha999_round :
    (∀ s d : Nat, s ≤ 255 → d ≤ 255 → (999 * s + d + 500) / 1000 = s) ∧
      (999 * 255 + 500) / 1000 = 255 ∧ (999 * 255) / 1000 = 254 := by
  refine ⟨fun s d hs hd => by omega, by decide, by decide⟩

/-- **Source-over is a lerp (n=21).** Painting colour `a` at opacity `t` over `b` is the linear interpolation.

$$\forall a, b, t \in \mathbb{Q}:\ t\,a + (1 - t)\,b = b + t\,(a - b)$$

A cross-fade by opacity and a colour tween are the same exact value. -/
theorem over_eq_lerp (a b t : Rat) : t * a + (1 - t) * b = b + t * (a - b) := by grind

/-- Rounding moves values at most one apart by at most one.

$$\forall x, y \in \mathbb{Q}:\ |x - y| \le 1 \Rightarrow |\operatorname{rnd}(x) - \operatorname{rnd}(y)| \le 1$$

Close values round to adjacent levels. -/
theorem roundQ_close (x y : Rat) (h1 : x - y ≤ 1) (h2 : y - x ≤ 1) :
    roundQ x - roundQ y ≤ 1 ∧ roundQ y - roundQ x ≤ 1 := by
  unfold roundQ
  have ax := Rat.floor_le (x + 1 / 2)
  have bx := Rat.lt_floor_add_one (x + 1 / 2)
  have ay := Rat.floor_le (y + 1 / 2)
  have b_y := Rat.lt_floor_add_one (y + 1 / 2)
  push_cast at bx b_y
  have k1 : (((x + 1 / 2).floor - (y + 1 / 2).floor : Int) : Rat) < 2 := by push_cast; grind
  have k2 : (((y + 1 / 2).floor - (x + 1 / 2).floor : Int) : Rat) < 2 := by push_cast; grind
  have e1 : (x + 1 / 2).floor - (y + 1 / 2).floor < 2 := by exact_mod_cast k1
  have e2 : (y + 1 / 2).floor - (x + 1 / 2).floor < 2 := by exact_mod_cast k2
  omega

/-- **An 8-bit opacity cross-fade is within one level of the exact tween (n=21).** If the opacity is quantised to
within half a level and both colours are in [0, 1], the cross-fade at the quantised opacity rounds to within one
8-bit level of the exact lerp.

$$\forall a, b, t, t' \in \mathbb{Q}:\ 0 \le a, b \le 1 \land |t' - t| \le \tfrac{1}{510} \Rightarrow \big|\operatorname{rnd}\big(255\,(t' a + (1 - t') b)\big) - \operatorname{rnd}\big(255\,(b + t\,(a - b))\big)\big| \le 1$$

An opacity cross-fade is Q-close to a colour tween at 8 bits. -/
theorem crossfade_close (a b t t' : Rat) (ha0 : 0 ≤ a) (ha1 : a ≤ 1) (hb0 : 0 ≤ b) (hb1 : b ≤ 1)
    (ht1 : t' - t ≤ 1 / 510) (ht2 : t - t' ≤ 1 / 510) :
    roundQ (255 * (t' * a + (1 - t') * b)) - roundQ (255 * (b + t * (a - b))) ≤ 1 ∧
      roundQ (255 * (b + t * (a - b))) - roundQ (255 * (t' * a + (1 - t') * b)) ≤ 1 := by
  have key : 255 * (t' * a + (1 - t') * b) - 255 * (b + t * (a - b)) = 255 * ((t' - t) * (a - b)) := by grind
  have hab1 : a - b ≤ 1 := by grind
  have hab2 : b - a ≤ 1 := by grind
  have hab3 : -(a - b) ≤ 1 := by grind
  have p1 : (t' - t) * (a - b) ≤ 1 / 510 := by
    rcases (Rat.le_total : (0 : Rat) ≤ t' - t ∨ t' - t ≤ 0) with g | g
    · have := Rat.mul_le_mul_of_nonneg_left hab1 g; grind
    · have := Rat.mul_le_mul_of_nonneg_left hab3 (show (0 : Rat) ≤ -(t' - t) by grind); grind
  have p2 : -(1 / 510) ≤ (t' - t) * (a - b) := by
    rcases (Rat.le_total : (0 : Rat) ≤ t' - t ∨ t' - t ≤ 0) with g | g
    · have := Rat.mul_le_mul_of_nonneg_left hab3 g; grind
    · have := Rat.mul_le_mul_of_nonneg_left hab1 (show (0 : Rat) ≤ -(t' - t) by grind); grind
  exact roundQ_close _ _ (by grind) (by grind)

/-- **An almost-opaque cover is opaque exactly up to 1/510 (n=25).** With opacity quantised by round-half-up to 8
bits, `1 - ε` becomes 255 exactly when `ε ≤ 1/510` (for `0 ≤ ε`); the ledger's strict `<` holds only under
round-half-even.

$$\forall \varepsilon \in \mathbb{Q}:\ 0 \le \varepsilon \Rightarrow \big(\operatorname{rnd}(255\,(1 - \varepsilon)) = 255 \iff \varepsilon \le \tfrac{1}{510}\big)$$

A cover hides what is under it only if its quantised alpha is 255. -/
theorem alpha_one_iff (ε : Rat) (h0 : 0 ≤ ε) : roundQ (255 * (1 - ε)) = 255 ↔ ε ≤ 1 / 510 := by
  unfold roundQ
  constructor
  · intro h
    have := Rat.floor_le (255 * (1 - ε) + 1 / 2)
    rw [h] at this
    push_cast at this
    grind
  · intro h
    have a : (255 : Int) ≤ (255 * (1 - ε) + 1 / 2).floor := Rat.le_floor_iff.mpr (by push_cast; grind)
    have d : (255 * (1 - ε) + 1 / 2).floor < 256 := by
      have := @Rat.floor_lt_iff (255 * (1 - ε) + 1 / 2) 256
      exact this.mpr (by rw [show ((256 : Int) : Rat) = 256 from rfl]; grind)
    omega

/-- Source-over of one 8-bit layer on one 8-bit pixel, rounded half up.

$$\forall d, c, a \in \mathbb{N}:\ \operatorname{over}_8(d, (c, a)) = \Big\lfloor \tfrac{2\,(a c + (255 \mathbin{\dot-} a)\, d) + 255}{510} \Big\rfloor$$

One paint step of the one-pixel fold. -/
def over8 (dst : Nat) (l : Nat × Nat) : Nat := (2 * (l.2 * l.1 + (255 - l.2) * dst) + 255) / 510

/-- Paint a list of (colour, alpha) layers in order onto a start pixel.

$$\operatorname{paint}(d, L) = \operatorname{foldl}(\operatorname{over}_8, d, L)$$

The one-pixel compositing fold. -/
def paint8 (d : Nat) (ls : List (Nat × Nat)) : Nat := ls.foldl over8 d

#guard over8 0 (200, 255) == 200
#guard over8 100 (200, 0) == 100
#guard paint8 7 [(10, 128), (90, 255), (30, 0)] == 90

/-- **Occlusion (n=25).** A layer painted under a later layer whose quantised alpha is 255 is invisible: dropping it
does not change the pixel.

$$\forall d \in \mathbb{N},\ \forall P, M, S \in (\mathbb{N}\times\mathbb{N})^{*},\ \forall b \in \mathbb{N}\times\mathbb{N},\ \forall c \in \mathbb{N}:\ \operatorname{paint}(d, P \mathbin{+\!\!+} b :: M \mathbin{+\!\!+} (c, 255) :: S) = \operatorname{paint}(d, P \mathbin{+\!\!+} M \mathbin{+\!\!+} (c, 255) :: S)$$

An exactly opaque cover makes the pause of what it covers E. -/
theorem occlusion (d : Nat) (pre mid post : List (Nat × Nat)) (b : Nat × Nat) (c : Nat) :
    paint8 d (pre ++ b :: mid ++ (c, 255) :: post) = paint8 d (pre ++ mid ++ (c, 255) :: post) := by
  have hcov : ∀ x, over8 x (c, 255) = c := by intro x; simp only [over8]; omega
  simp only [paint8, List.foldl_append, List.foldl_cons, hcov]

/-! ## Rounded-rectangle rigidity (ledger n=10) -/

/-- An axis-aligned rounded rectangle: width, height and the corner radii along x and y.

$$\mathrm{RRect} = \mathbb{Q}^{4},\qquad R = (w, h, r_x, r_y)$$

The geometry of a `border-radius` box. -/
structure RRect where
  w  : Rat
  h  : Rat
  rx : Rat
  ry : Rat
deriving Repr, DecidableEq

/-- Scale a rounded rectangle along the axes.

$$\operatorname{scale}_{s_x, s_y}(w, h, r_x, r_y) = (s_x w, s_y h, s_x r_x, s_y r_y)$$

What an axis-aligned transform does to the box. -/
def RRect.scale (sx sy : Rat) (R : RRect) : RRect := ⟨sx * R.w, sy * R.h, sx * R.rx, sy * R.ry⟩

/-- **Circular corners force a uniform scale.** If a box with circular corners of radius `r > 0` scales to a box with
circular corners, the scale is uniform and every dimension scales by the same factor.

$$\forall w, h, r, s_x, s_y, w', h', r' \in \mathbb{Q}:\ 0 < r \land \operatorname{scale}_{s_x, s_y}(w, h, r, r) = (w', h', r', r') \Rightarrow s_x = s_y \land w' = s_x w \land h' = s_x h \land r' = s_x r$$

A transform of a fixed rounded box keeps its aspect ratio. -/
theorem rrect_rigid (w h r sx sy w' h' r' : Rat) (hr : 0 < r)
    (heq : RRect.scale sx sy ⟨w, h, r, r⟩ = ⟨w', h', r', r'⟩) :
    sx = sy ∧ w' = sx * w ∧ h' = sx * h ∧ r' = sx * r := by
  simp only [RRect.scale, RRect.mk.injEq] at heq
  obtain ⟨e1, e2, e3, e4⟩ := heq
  have hs : sx * r = sy * r := by rw [e3, e4]
  have hsxy : sx = sy := by
    have : (sx - sy) * r = 0 := by grind
    rcases Rat.mul_eq_zero.mp this with h | h
    · grind
    · grind
  subst hsxy
  exact ⟨rfl, e1.symm, e2.symm, e3.symm⟩

/-- **No fixed box tweens a varying aspect ratio (n=10, axis-aligned transforms).** If two frames show circular-corner
boxes with different aspect ratios, no single fixed circular-corner box maps to both by axis-aligned scales.

$$\forall w, h, r, s_x, s_y, t_x, t_y, w_1, h_1, r_1, w_2, h_2, r_2 \in \mathbb{Q}:\ 0 < r \land\operatorname{scale}_{s_x, s_y}(w, h, r, r) = (w_1, h_1, r_1, r_1) \land \operatorname{scale}_{t_x, t_y}(w, h, r, r) = (w_2, h_2, r_2, r_2) \Rightarrow w_1 h_2 = w_2 h_1$$

A morph whose aspect ratio changes is not a transform of one box, so it is not E. -/
theorem rrect_no_fixed_box (w h r sx sy tx ty w1 h1 r1 w2 h2 r2 : Rat) (hr : 0 < r)
    (e1 : RRect.scale sx sy ⟨w, h, r, r⟩ = ⟨w1, h1, r1, r1⟩)
    (e2 : RRect.scale tx ty ⟨w, h, r, r⟩ = ⟨w2, h2, r2, r2⟩) : w1 * h2 = w2 * h1 := by
  obtain ⟨_, a1, b1, _⟩ := rrect_rigid w h r sx sy w1 h1 r1 hr e1
  obtain ⟨_, a2, b2, _⟩ := rrect_rigid w h r tx ty w2 h2 r2 hr e2
  subst a1 b1 a2 b2
  grind

/-! ## Composing parts: the page scene is the stacked part scenes -/

/-- One part's arm on the page: its band height (the PL1 box the part occupies) and its scene as a function of the
page offset `y` of its band's top edge.

$$\mathrm{PartArm} = \underbrace{\mathbb{Q}}_{\mathrm{height}} \times \underbrace{(\mathbb{Q} \to \mathrm{Scene})}_{\mathrm{scene}}$$
-/
structure PartArm where
  height : Rat
  scene  : Rat → Scene

/-- The page scene of parts stacked from offset `y`: each part's scene at its own offset, the next part starting at
the previous offset plus the previous height.

$$\operatorname{stackScene}(y, [\,]) = [\,],\qquad \operatorname{stackScene}(y, p :: ps) = p.\mathrm{scene}(y) \mathbin{+\!\!+} \operatorname{stackScene}(y + p.\mathrm{height}, ps)$$
-/
def stackScene : Rat → List PartArm → Scene
  | _, [] => []
  | y, p :: ps => p.scene y ++ stackScene (y + p.height) ps

/-- `visible` splits over concatenated scenes.

$$\forall \mathit{vp} \in \mathrm{Rect},\ \forall S, U \in \mathrm{Scene}:\ \operatorname{visible}_{\mathit{vp}}(S \mathbin{+\!\!+} U) = \operatorname{visible}_{\mathit{vp}}(S) \mathbin{+\!\!+} \operatorname{visible}_{\mathit{vp}}(U)$$
-/
theorem visible_scene_append (vp : Rect) (s u : Scene) : visible vp (s ++ u) = visible vp s ++ visible vp u :=
  List.filter_append ..

/-- Q on two scenes and Q on two more scenes give Q on the concatenations.

$$\forall S_1, U_1, S_2, U_2 \in \mathrm{Scene}:\ \mathrm{Q}(S_1, U_1) \land \mathrm{Q}(S_2, U_2) \Rightarrow \mathrm{Q}(S_1 \mathbin{+\!\!+} S_2,\ U_1 \mathbin{+\!\!+} U_2)$$
-/
theorem Q_append : ∀ {s₁ u₁ s₂ u₂ : Scene}, Q s₁ u₁ → Q s₂ u₂ → Q (s₁ ++ s₂) (u₁ ++ u₂)
  | [], [], _, _, _, h₂ => h₂
  | [], _ :: _, _, _, h, _ => by simp [Q, sceneQ] at h
  | _ :: _, [], _, _, h, _ => by simp [Q, sceneQ] at h
  | _ :: _, _ :: _, _, _, h, h₂ => by
    simp only [Q, sceneQ, List.cons_append, Bool.and_eq_true] at h h₂ ⊢
    exact ⟨h.1, Q_append h.2 h₂⟩

/-- **Visible page from visible parts (E).** If the two page arms have the same number of parts and, part by part,
equal band heights and equal visible scenes at every offset, the visible page scenes are equal, from every start
offset.

$$\forall \mathit{vp} \in \mathrm{Rect},\ \forall O, V \in \mathrm{PartArm}^{*},\ \forall y \in \mathbb{Q}:\ |O| = |V| \land \Big(\forall (o, v) \in \operatorname{zip}(O, V):\ o.\mathrm{height} = v.\mathrm{height} \land \forall y' \in \mathbb{Q}:\ \operatorname{visible}_{\mathit{vp}}(o.\mathrm{scene}(y')) = \operatorname{visible}_{\mathit{vp}}(v.\mathrm{scene}(y'))\Big) \Rightarrow \operatorname{visible}_{\mathit{vp}}(\operatorname{stackScene}(y, O)) = \operatorname{visible}_{\mathit{vp}}(\operatorname{stackScene}(y, V))$$

Equal boxes keep every later part at the same offset, so per-part E rows compose to the page. -/
theorem visible_append_of_boxes_eq (vp : Rect) :
    ∀ {os vs : List PartArm} (y : Rat), os.length = vs.length →
      (∀ p ∈ os.zip vs, p.1.height = p.2.height ∧
        ∀ y', visible vp (p.1.scene y') = visible vp (p.2.scene y')) →
      visible vp (stackScene y os) = visible vp (stackScene y vs)
  | [], [], _, _, _ => rfl
  | [], _ :: _, _, hl, _ => by simp at hl
  | _ :: _, [], _, hl, _ => by simp at hl
  | o :: os, v :: vs, y, hl, h => by
    have ⟨hh, hs⟩ : o.height = v.height ∧ ∀ y', visible vp (o.scene y') = visible vp (v.scene y') :=
      h (o, v) (by simp)
    have hr := visible_append_of_boxes_eq vp (os := os) (vs := vs) (y + o.height) (by simpa using hl)
      (fun p hp => h p (by simp [hp]))
    rw [stackScene, stackScene, visible_scene_append, visible_scene_append, hs y, hr, hh]

/-- **Visible page from visible parts (Q).** The same with the gate's relation Q in place of equality; band heights
must still be equal exactly.

$$\forall \mathit{vp} \in \mathrm{Rect},\ \forall O, V \in \mathrm{PartArm}^{*},\ \forall y \in \mathbb{Q}:\ |O| = |V| \land \Big(\forall (o, v) \in \operatorname{zip}(O, V):\ o.\mathrm{height} = v.\mathrm{height} \land \forall y' \in \mathbb{Q}:\ \mathrm{Q}\big(\operatorname{visible}_{\mathit{vp}}(o.\mathrm{scene}(y')),\ \operatorname{visible}_{\mathit{vp}}(v.\mathrm{scene}(y'))\big)\Big) \Rightarrow \mathrm{Q}\big(\operatorname{visible}_{\mathit{vp}}(\operatorname{stackScene}(y, O)),\ \operatorname{visible}_{\mathit{vp}}(\operatorname{stackScene}(y, V))\big)$$

Per-part Q rows compose to the page when no part's height moves. -/
theorem visible_append_of_boxes_Q (vp : Rect) :
    ∀ {os vs : List PartArm} (y : Rat), os.length = vs.length →
      (∀ p ∈ os.zip vs, p.1.height = p.2.height ∧
        ∀ y', Q (visible vp (p.1.scene y')) (visible vp (p.2.scene y'))) →
      Q (visible vp (stackScene y os)) (visible vp (stackScene y vs))
  | [], [], _, _, _ => Q_refl []
  | [], _ :: _, _, hl, _ => by simp at hl
  | _ :: _, [], _, hl, _ => by simp at hl
  | o :: os, v :: vs, y, hl, h => by
    have ⟨hh, hs⟩ : o.height = v.height ∧ ∀ y', Q (visible vp (o.scene y')) (visible vp (v.scene y')) :=
      h (o, v) (by simp)
    have hr := visible_append_of_boxes_Q vp (os := os) (vs := vs) (y + o.height) (by simpa using hl)
      (fun p hp => h p (by simp [hp]))
    simp only [stackScene, visible_scene_append]
    rw [← hh] at *
    exact Q_append (hs y) hr

end Fw.Engine
