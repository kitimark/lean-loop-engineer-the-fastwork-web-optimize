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

end Fw.Engine
