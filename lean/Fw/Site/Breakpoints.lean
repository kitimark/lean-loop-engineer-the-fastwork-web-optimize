/-!
# Breakpoints of the original homepage, as decidable predicates

Source of truth: `research/kickoff/11-breakpoints/README.md` and `breakpoints.json` (inventory schema
`fw.breakpoints/1`). The inventory lists **30 distinct media conditions** after normalising to range syntax
(29 in CSS, 1 JS-only). This module

* models the media environment of one page load (`Env`): viewport width (a non-negative rational, so the four
  fractional gaps are representable), device width, primary hover / pointer capability, reduced motion, colour
  scheme, and the extra inputs the test matrix fixes (viewport height, device height, DPR);
* gives a tiny abstract syntax for media query lists (`MQ`: an OR of ANDs of features) with an evaluator and an
  exact CSS printer (range syntax, the inventory's normal form) plus a legacy printer (`max-width` / `min-width`);
* defines the 30 conditions under the inventory's ids (`catalogue`), each a decidable predicate `MQ.Holds`;
* proves that the value of any query changes only at the edges read off its syntax (`MQ.eval_congr`,
  `MQ.eval_ofNat_congr`): testing both sides `N | N+1` of each listed edge is enough.

Mathlib-free. Widths are exact rationals `num / den`; comparisons with an integer bound `N` are the
cross-multiplied Nat inequalities, so `omega` decides every arithmetic step.
-/

namespace Fw.Site.Breakpoints

/-! ## Environment -/

/-- A non-negative rational number of CSS pixels, `num / den` with `den > 0` (not normalised).

$$ x = \tfrac{p}{q} \in \mathbb{Q}_{\ge 0},\quad p \in \mathbb{N},\ q \in \mathbb{N}_{>0} $$

A length in CSS px that may be fractional, as a browser at DPR 1.25 or under zoom reports it. -/
structure Px where
  /-- numerator $p$ -/
  num : Nat
  /-- denominator $q$ -/
  den : Nat
  /-- $q > 0$ -/
  den_pos : 0 < den
deriving DecidableEq, Repr

namespace Px

/-- The whole-pixel length $n$, i.e. $n/1$.

$$ \mathrm{ofNat}(n) = \tfrac{n}{1} $$

A whole number of CSS px as an exact rational. -/
def ofNat (n : Nat) : Px := ⟨n, 1, Nat.one_pos⟩

/-- The half-pixel length $n + \tfrac12$, i.e. $(2n+1)/2$.

$$ \mathrm{half}(n) = \tfrac{2n+1}{2} = n + \tfrac12 $$

The probe width in the middle of the gap between $n$ and $n+1$. -/
def half (n : Nat) : Px := ⟨2 * n + 1, 2, by decide⟩

/-- Comparison with an integer bound: $x \le N$.

$$ x \le N \iff p \le N\,q $$

The length is at most `N` px. -/
def LeNat (x : Px) (N : Nat) : Prop := x.num ≤ N * x.den

/-- Comparison with an integer bound: $x \ge N$.

$$ x \ge N \iff N\,q \le p $$

The length is at least `N` px. -/
def GeNat (x : Px) (N : Nat) : Prop := N * x.den ≤ x.num

/-- Comparison with an integer bound: $x > N$.

$$ x > N \iff N\,q < p $$

The length is strictly more than `N` px. -/
def GtNat (x : Px) (N : Nat) : Prop := N * x.den < x.num

instance (x : Px) (N : Nat) : Decidable (x.LeNat N) := inferInstanceAs (Decidable (_ ≤ _))
instance (x : Px) (N : Nat) : Decidable (x.GeNat N) := inferInstanceAs (Decidable (_ ≤ _))
instance (x : Px) (N : Nat) : Decidable (x.GtNat N) := inferInstanceAs (Decidable (_ < _))

end Px

/-- The `hover` media feature of the primary input: `none` or `hover`.

$$ \eta \in \{\text{none}, \text{hover}\} $$ -/
inductive Hover | none | hover
deriving DecidableEq, Repr

/-- The `pointer` media feature of the primary input: `none`, `coarse` or `fine`.

$$ \pi \in \{\text{none}, \text{coarse}, \text{fine}\} $$ -/
inductive Pointer | none | coarse | fine
deriving DecidableEq, Repr

/-- The `prefers-reduced-motion` media feature: `no-preference` or `reduce`.

$$ \mu \in \{\text{no-preference}, \text{reduce}\} $$ -/
inductive Motion | noPreference | reduce
deriving DecidableEq, Repr

/-- The `prefers-color-scheme` media feature: `light` or `dark`.

$$ \sigma \in \{\text{light}, \text{dark}\} $$ -/
inductive Scheme | light | dark
deriving DecidableEq, Repr

/-- The media type of the load: `screen` or `print`.

$$ \tau \in \{\text{screen}, \text{print}\} $$ -/
inductive MediaType | screen | print
deriving DecidableEq, Repr

/-- The `forced-colors` media feature: `none` or `active`.

$$ \phi \in \{\text{none}, \text{active}\} $$ -/
inductive ForcedColors | none | active
deriving DecidableEq, Repr

/-- The media environment of one page load.

$$ e = (w, h, d_w, d_h, r, \eta, \pi, \mu, \sigma, \tau, \phi) \in \mathbb{Q}_{\ge0}^5 \times \mathrm{Hover} \times
   \mathrm{Pointer} \times \mathrm{Motion} \times \mathrm{Scheme} \times \mathrm{MediaType} \times \mathrm{ForcedColors} $$

Viewport width and height, device (screen) width and height, device pixel ratio, the four discrete media features
of the inventory, and the media type and forced-colors mode read only by the MUI-internal neutral queries. -/
structure Env where
  /-- viewport width $w$ in CSS px (the `width` media feature) -/
  width : Px
  /-- viewport height $h$ in CSS px (no media condition reads it; the test matrix fixes it) -/
  height : Px
  /-- screen width $d_w$ in CSS px (the `device-width` media feature) -/
  deviceWidth : Px
  /-- screen height $d_h$ in CSS px (read by no condition) -/
  deviceHeight : Px
  /-- device pixel ratio $r$ (read by no condition; the page has no DPR-dependent code) -/
  dpr : Px
  /-- `hover` of the primary input -/
  hover : Hover
  /-- `pointer` of the primary input -/
  pointer : Pointer
  /-- `prefers-reduced-motion` -/
  motion : Motion
  /-- `prefers-color-scheme` -/
  scheme : Scheme
  /-- media type $\tau$ (`screen` for every gate load) -/
  mediaType : MediaType := .screen
  /-- `forced-colors` $\phi$ (`none` for every gate load) -/
  forcedColors : ForcedColors := .none
deriving DecidableEq, Repr

/-! ## Media query syntax, semantics and printing -/

/-- One media feature test, in the inventory's normal form.

$$ f ::= w \le N \mid w > N \mid w \ge N{+}1 \mid d_w \le N \mid \eta = v \mid \pi = v \mid \mu = v \mid \sigma = v
   \mid \tau = v \mid \phi = v $$

The atoms the 30 conditions are built from; `widthGeSucc N` is printed `(width>=N+1px)` so that its edge is `N`. -/
inductive Feature
  /-- `(width<=Npx)` -/
  | widthLe (n : Nat)
  /-- `(width>Npx)` -/
  | widthGt (n : Nat)
  /-- `(width>=(N+1)px)`; stored by its edge `N` -/
  | widthGeSucc (n : Nat)
  /-- `(device-width<=Npx)` -/
  | deviceWidthLe (n : Nat)
  /-- `(hover: v)` -/
  | hover (v : Hover)
  /-- `(pointer: v)` -/
  | pointer (v : Pointer)
  /-- `(prefers-reduced-motion: v)` -/
  | motion (v : Motion)
  /-- `(prefers-color-scheme: v)` -/
  | scheme (v : Scheme)
  /-- the media type `print` / `screen` (bare keyword) -/
  | mediaType (v : MediaType)
  /-- `(forced-colors: v)` -/
  | forcedColors (v : ForcedColors)
deriving DecidableEq, Repr

/-- A media query list: a comma list (OR) of `and`-conjunctions of features.

$$ q = \bigvee_{i} \bigwedge_{j} f_{ij} $$

What one `@media` prelude or one `matchMedia` argument means. -/
structure MQ where
  /-- the comma-separated arms; each arm is a conjunction -/
  arms : List (List Feature)
deriving DecidableEq, Repr

namespace Feature

/-- Truth of one feature in an environment.

$$ \llbracket w \le N \rrbracket_e = [w \le N],\ \llbracket w > N \rrbracket_e = [w > N],\
   \llbracket w \ge N{+}1 \rrbracket_e = [w \ge N{+}1],\ \llbracket d_w \le N \rrbracket_e = [d_w \le N],\
   \llbracket \eta = v \rrbracket_e = [e.\eta = v], \dots $$

Evaluates a single media feature exactly as the CSS Media Queries 4 range and discrete forms define it. -/
def holds (e : Env) : Feature → Bool
  | widthLe n => decide (e.width.LeNat n)
  | widthGt n => decide (e.width.GtNat n)
  | widthGeSucc n => decide (e.width.GeNat (n + 1))
  | deviceWidthLe n => decide (e.deviceWidth.LeNat n)
  | hover v => decide (e.hover = v)
  | pointer v => decide (e.pointer = v)
  | motion v => decide (e.motion = v)
  | scheme v => decide (e.scheme = v)
  | mediaType v => decide (e.mediaType = v)
  | forcedColors v => decide (e.forcedColors = v)

/-- CSS keyword of a `hover` value.

$$ \mathrm{kw}(\text{none}) = \texttt{none},\ \mathrm{kw}(\text{hover}) = \texttt{hover} $$ -/
def hoverKw : Hover → String | .none => "none" | .hover => "hover"
/-- CSS keyword of a `pointer` value.

$$ \mathrm{kw}(v) \in \{\texttt{none}, \texttt{coarse}, \texttt{fine}\} $$ -/
def pointerKw : Pointer → String | .none => "none" | .coarse => "coarse" | .fine => "fine"
/-- CSS keyword of a `prefers-reduced-motion` value.

$$ \mathrm{kw}(v) \in \{\texttt{no-preference}, \texttt{reduce}\} $$ -/
def motionKw : Motion → String | .noPreference => "no-preference" | .reduce => "reduce"
/-- CSS keyword of a `prefers-color-scheme` value.

$$ \mathrm{kw}(v) \in \{\texttt{light}, \texttt{dark}\} $$ -/
def schemeKw : Scheme → String | .light => "light" | .dark => "dark"
/-- CSS keyword of a media type.

$$ \mathrm{kw}(v) \in \{\texttt{screen}, \texttt{print}\} $$ -/
def mediaTypeKw : MediaType → String | .screen => "screen" | .print => "print"
/-- CSS keyword of a `forced-colors` value.

$$ \mathrm{kw}(v) \in \{\texttt{none}, \texttt{active}\} $$ -/
def forcedColorsKw : ForcedColors → String | .none => "none" | .active => "active"

/-- The feature in the inventory's normal form (range syntax, no spaces around the comparison,
`name: value` for discrete features).

$$ \mathrm{css}(w \le N) = \texttt{(width<=}N\texttt{px)},\ \mathrm{css}(w > N) = \texttt{(width>}N\texttt{px)},\ \mathrm{css}(w \ge N{+}1) = \texttt{(width>=}N{+}1\texttt{px)},\ \dots $$ -/
def css : Feature → String
  | widthLe n => s!"(width<={n}px)"
  | widthGt n => s!"(width>{n}px)"
  | widthGeSucc n => s!"(width>={n + 1}px)"
  | deviceWidthLe n => s!"(device-width<={n}px)"
  | hover v => s!"(hover: {hoverKw v})"
  | pointer v => s!"(pointer: {pointerKw v})"
  | motion v => s!"(prefers-reduced-motion: {motionKw v})"
  | scheme v => s!"(prefers-color-scheme: {schemeKw v})"
  | mediaType v => mediaTypeKw v
  | forcedColors v => s!"(forced-colors: {forcedColorsKw v})"

/-- The feature in legacy `min-`/`max-` syntax, if one exists (`width > N` has no exact legacy form).

$$ \mathrm{legacy}(w \le N) = \texttt{(max-width: }N\texttt{px)},\ \mathrm{legacy}(w > N) = \bot,\ \mathrm{legacy}(w \ge N{+}1) = \texttt{(min-width: }N{+}1\texttt{px)} $$ -/
def legacyCss : Feature → Option String
  | widthLe n => some s!"(max-width: {n}px)"
  | widthGt _ => none
  | widthGeSucc n => some s!"(min-width: {n + 1}px)"
  | deviceWidthLe n => some s!"(max-device-width: {n}px)"
  | f => some f.css

/-- The integer edges of `width` this feature is sensitive to (edge `N` = the pair `N | N+1`).

$$ E_w(w \le N) = E_w(w > N) = E_w(w \ge N{+}1) = [N],\quad E_w(f) = [\,] \text{ otherwise} $$ -/
def widthCuts : Feature → List Nat
  | widthLe n => [n]
  | widthGt n => [n]
  | widthGeSucc n => [n]
  | _ => []

/-- The integer edges of `device-width` this feature is sensitive to.

$$ E_d(d_w \le N) = [N],\quad E_d(f) = [\,] \text{ otherwise} $$ -/
def dwCuts : Feature → List Nat
  | deviceWidthLe n => [n]
  | _ => []

/-- The inventory's feature name (`width`, `device-width`, `hover`, …).

$$ \mathrm{name}(w \lessgtr N) = \texttt{width},\ \mathrm{name}(d_w \le N) = \texttt{device-width},\ \dots $$ -/
def featureName : Feature → String
  | widthLe _ | widthGt _ | widthGeSucc _ => "width"
  | deviceWidthLe _ => "device-width"
  | hover _ => "hover"
  | pointer _ => "pointer"
  | motion _ => "prefers-reduced-motion"
  | scheme _ => "prefers-color-scheme"
  | mediaType _ => "media-type"
  | forcedColors _ => "forced-colors"

end Feature

/-- The axis an edge lives on, as the inventory tags it: `width`, `width(touch)` (a width bound inside the touch
arm of a combo) or `device-width`.

$$ a \in \{\text{width}, \text{width(touch)}, \text{device-width}\} $$ -/
inductive Axis | width | widthTouch | deviceWidth
deriving DecidableEq, Repr

/-- The inventory's feature tag of an axis.

$$ \mathrm{str}(\text{width}) = \texttt{width},\ \mathrm{str}(\text{width(touch)}) = \texttt{width(touch)},\ \mathrm{str}(\text{device-width}) = \texttt{device-width} $$ -/
def Axis.str : Axis → String
  | .width => "width" | .widthTouch => "width(touch)" | .deviceWidth => "device-width"

namespace MQ

/-- Truth of a media query list.

$$ \llbracket q \rrbracket_e = \bigvee_i \bigwedge_j \llbracket f_{ij} \rrbracket_e $$

A comma list matches when some arm has all its features true. -/
def eval (q : MQ) (e : Env) : Bool := q.arms.any (fun arm => arm.all (fun f => f.holds e))

/-- The condition as a decidable proposition.

$$ e \models q \iff \llbracket q \rrbracket_e = \mathrm{true} $$

The query matches in environment `e`. -/
def Holds (q : MQ) (e : Env) : Prop := q.eval e = true

instance (q : MQ) (e : Env) : Decidable (q.Holds e) := inferInstanceAs (Decidable (_ = _))

/-- Exact CSS text in the inventory's normal form: arms joined by `", "`, features by `" and "`.

$$ \mathrm{css}(q) = \mathrm{join}_{\texttt{, }}\big(\mathrm{join}_{\texttt{ and }}(\mathrm{css}(f_{ij}))_j\big)_i $$ -/
def css (q : MQ) : String := ", ".intercalate (q.arms.map fun arm => " and ".intercalate (arm.map Feature.css))

/-- Legacy `min-`/`max-` text, if every feature has a legacy form.

$$ \mathrm{legacy}(q) = \mathrm{join}_{\texttt{, }}\big(\mathrm{join}_{\texttt{ and }}(\mathrm{legacy}(f_{ij}))_j\big)_i \text{ if every } \mathrm{legacy}(f_{ij}) \ne \bot $$ -/
def legacyCss (q : MQ) : Option String := do
  let arms ← q.arms.mapM fun arm => do
    let fs ← arm.mapM Feature.legacyCss
    pure (" and ".intercalate fs)
  pure (", ".intercalate arms)

/-- All width edges read off the syntax (with repetitions).

$$ E_w(q) = \mathrm{concat}_{i,j}\, E_w(f_{ij}) $$ -/
def widthEdges (q : MQ) : List Nat := q.arms.flatMap (·.flatMap Feature.widthCuts)

/-- All device-width edges read off the syntax (with repetitions).

$$ E_d(q) = \mathrm{concat}_{i,j}\, E_d(f_{ij}) $$ -/
def dwEdges (q : MQ) : List Nat := q.arms.flatMap (·.flatMap Feature.dwCuts)

/-- Whether an arm is a touch arm (contains a `hover` or `pointer` test).

$$ \mathrm{touchArm}(A) \iff \exists f \in A.\ f \in \{\eta = v, \pi = v\} $$ -/
def armIsTouch (arm : List Feature) : Bool :=
  arm.any fun | .hover _ | .pointer _ => true | _ => false

/-- Insert at the end unless already present (order-preserving dedup).

$$ \mathrm{pushNew}(l, x) = \begin{cases} l & x \in l \\ l \mathbin{+\!\!+} [x] & \text{otherwise} \end{cases} $$ -/
def pushNew {α} [BEq α] (l : List α) (x : α) : List α := if l.contains x then l else l ++ [x]

/-- The inventory's tagged edges in order of first appearance: `(axis, N)` where the axis is `width`,
`device-width`, or `width(touch)` for a width bound inside a touch arm.

$$ E(q) = \mathrm{dedup}\,[(a(f), N) \mid f \in q,\ N \in E_w(f) \cup E_d(f)] $$ -/
def taggedEdges (q : MQ) : List (Axis × Nat) :=
  q.arms.foldl (init := []) fun acc arm =>
    arm.foldl (init := acc) fun acc f =>
      let tag := if armIsTouch arm then Axis.widthTouch else Axis.width
      match f with
      | .widthLe n | .widthGt n | .widthGeSucc n => pushNew acc (tag, n)
      | .deviceWidthLe n => pushNew acc (.deviceWidth, n)
      | _ => acc

/-- The inventory's feature list: feature names in order of first appearance.

$$ \mathrm{features}(q) = \mathrm{dedup}\,[\mathrm{name}(f) \mid f \in q] $$ -/
def features (q : MQ) : List String :=
  q.arms.foldl (init := []) fun acc arm => arm.foldl (init := acc) fun acc f => pushNew acc f.featureName

/-- Insertion into a sorted list without duplicates.

$$ \mathrm{insertSorted}(x, l) = \mathrm{sort}(\mathrm{dedup}(x :: l)) \text{ for sorted, duplicate-free } l $$ -/
def insertSorted (x : Nat) : List Nat → List Nat
  | [] => [x]
  | y :: ys => if x < y then x :: y :: ys else if x = y then y :: ys else y :: insertSorted x ys

/-- The inventory's `edges_px`: the sorted, deduplicated edge values.

$$ \mathrm{edgesPx}(q) = \mathrm{sort}(\mathrm{dedup}[N \mid (\_, N) \in E(q)]) $$ -/
def edgesPx (q : MQ) : List Nat := (q.taggedEdges.map (·.2)).foldl (fun acc n => insertSorted n acc) []

end MQ

/-! ## The 30 conditions -/

open Feature in
/-- The touch arm shared by every combo: `(hover: none) and (pointer: coarse) and (width<=1200px)`.

$$ \eta = \text{none} \land \pi = \text{coarse} \land w \le 1200 $$ -/
def touchArm : List Feature := [hover .none, pointer .coarse, widthLe 1200]

/-- Combo `N`: `(width<=Npx), (device-width<=500px), <touch arm>`; without the device-width arm if `dw = false`.

$$ C_N = (w \le N) \lor (d_w \le 500) \lor (\eta = \mathrm{none} \land \pi = \mathrm{coarse} \land w \le 1200) $$

The phone-or-small-device-or-touch-tablet query family; `combo N false` drops the middle arm. -/
def combo (n : Nat) (dw : Bool := true) : MQ :=
  ⟨[[.widthLe n]] ++ (if dw then [[.deviceWidthLe 500]] else []) ++ [touchArm]⟩

/-- `mq.rm-reduce`: `(prefers-reduced-motion: reduce)`.

$$ e \models \mathtt{rmReduce} \iff \mu = \text{reduce} $$ -/
def rmReduce : MQ := ⟨[[.motion .reduce]]⟩
/-- `mq.rm-nopref`: `(prefers-reduced-motion: no-preference)`.

$$ e \models \mathtt{rmNopref} \iff \mu = \text{no-preference} $$ -/
def rmNopref : MQ := ⟨[[.motion .noPreference]]⟩
/-- `mq.hover-hover`: `(hover: hover)`.

$$ e \models \mathtt{hoverHover} \iff \eta = \text{hover} $$ -/
def hoverHover : MQ := ⟨[[.hover .hover]]⟩
/-- `mq.hover-none`: `(hover: none)` (JS only).

$$ e \models \mathtt{hoverNone} \iff \eta = \text{none} $$ -/
def hoverNone : MQ := ⟨[[.hover .none]]⟩
/-- `mq.dark`: `(prefers-color-scheme: dark)`.

$$ e \models \mathtt{dark} \iff \sigma = \text{dark} $$ -/
def dark : MQ := ⟨[[.scheme .dark]]⟩
/-- `mq.w-le-400`: `(width<=400px)`.

$$ e \models \mathtt{wLe400} \iff w \le 400 $$ -/
def wLe400 : MQ := ⟨[[.widthLe 400]]⟩
/-- `mq.w-le-461`: `(width<=461px)`.

$$ e \models \mathtt{wLe461} \iff w \le 461 $$ -/
def wLe461 : MQ := ⟨[[.widthLe 461]]⟩
/-- `mq.w-le-480`: `(width<=480px)`.

$$ e \models \mathtt{wLe480} \iff w \le 480 $$ -/
def wLe480 : MQ := ⟨[[.widthLe 480]]⟩
/-- `mq.w-le-600`: `(width<=600px)`.

$$ e \models \mathtt{wLe600} \iff w \le 600 $$ -/
def wLe600 : MQ := ⟨[[.widthLe 600]]⟩
/-- `mq.w-gt-600`: `(width>600px)`.

$$ e \models \mathtt{wGt600} \iff w > 600 $$ -/
def wGt600 : MQ := ⟨[[.widthGt 600]]⟩
/-- `mq.w-601-1279`: `(width>=601px) and (width<=1279px)`.

$$ e \models \mathtt{w601to1279} \iff w \ge 601 \land w \le 1279 $$ -/
def w601to1279 : MQ := ⟨[[.widthGeSucc 600, .widthLe 1279]]⟩
/-- `mq.w-601-1511`: `(width>=601px) and (width<=1511px)`.

$$ e \models \mathtt{w601to1511} \iff w \ge 601 \land w \le 1511 $$ -/
def w601to1511 : MQ := ⟨[[.widthGeSucc 600, .widthLe 1511]]⟩
/-- `mq.w-le-640`: `(width<=640px)`.

$$ e \models \mathtt{wLe640} \iff w \le 640 $$ -/
def wLe640 : MQ := ⟨[[.widthLe 640]]⟩
/-- `mq.w-gt-640`: `(width>640px)`.

$$ e \models \mathtt{wGt640} \iff w > 640 $$ -/
def wGt640 : MQ := ⟨[[.widthGt 640]]⟩
/-- `mq.w-641-1000`: `(width>=641px) and (width<=1000px)`.

$$ e \models \mathtt{w641to1000} \iff w \ge 641 \land w \le 1000 $$ -/
def w641to1000 : MQ := ⟨[[.widthGeSucc 640, .widthLe 1000]]⟩
/-- `mq.w-le-720`: `(width<=720px)`.

$$ e \models \mathtt{wLe720} \iff w \le 720 $$ -/
def wLe720 : MQ := ⟨[[.widthLe 720]]⟩
/-- `mq.w-le-860`: `(width<=860px)` (pure width; never substitute `c860`).

$$ e \models \mathtt{wLe860} \iff w \le 860 $$ -/
def wLe860 : MQ := ⟨[[.widthLe 860]]⟩
/-- `mq.w-ge-861`: `(width>=861px)`.

$$ e \models \mathtt{wGe861} \iff w \ge 861 $$ -/
def wGe861 : MQ := ⟨[[.widthGeSucc 860]]⟩
/-- `mq.w-ge-861-nopref`: `(width>=861px) and (prefers-reduced-motion: no-preference)`.

$$ e \models \mathtt{wGe861Nopref} \iff w \ge 861 \land \mu = \text{no-preference} $$ -/
def wGe861Nopref : MQ := ⟨[[.widthGeSucc 860, .motion .noPreference]]⟩
/-- `mq.w-861-1000`: `(width>=861px) and (width<=1000px)`.

$$ e \models \mathtt{w861to1000} \iff w \ge 861 \land w \le 1000 $$ -/
def w861to1000 : MQ := ⟨[[.widthGeSucc 860, .widthLe 1000]]⟩
/-- `mq.w-le-960`: `(width<=960px)`.

$$ e \models \mathtt{wLe960} \iff w \le 960 $$ -/
def wLe960 : MQ := ⟨[[.widthLe 960]]⟩
/-- `mq.w-le-1000`: `(width<=1000px)`.

$$ e \models \mathtt{wLe1000} \iff w \le 1000 $$ -/
def wLe1000 : MQ := ⟨[[.widthLe 1000]]⟩
/-- `mq.w-ge-1001`: `(width>=1001px)`.

$$ e \models \mathtt{wGe1001} \iff w \ge 1001 $$ -/
def wGe1001 : MQ := ⟨[[.widthGeSucc 1000]]⟩
/-- `mq.w-ge-1001-nopref`: `(width>=1001px) and (prefers-reduced-motion: no-preference)`.

$$ e \models \mathtt{wGe1001Nopref} \iff w \ge 1001 \land \mu = \text{no-preference} $$ -/
def wGe1001Nopref : MQ := ⟨[[.widthGeSucc 1000, .motion .noPreference]]⟩
/-- `mq.w-le-1100`: `(width<=1100px)`.

$$ e \models \mathtt{wLe1100} \iff w \le 1100 $$ -/
def wLe1100 : MQ := ⟨[[.widthLe 1100]]⟩
/-- `mq.w-le-1200`: `(width<=1200px)` (plain width, no touch clause).

$$ e \models \mathtt{wLe1200} \iff w \le 1200 $$ -/
def wLe1200 : MQ := ⟨[[.widthLe 1200]]⟩
/-- `mq.c860`: combo 860 with the device-width arm.

$$ e \models \mathtt{c860} \iff w \le 860 \lor d_w \le 500 \lor (\eta = \text{none} \land \pi = \text{coarse} \land w \le 1200) $$ -/
def c860 : MQ := combo 860
/-- `mq.c1000`: combo 1000 with the device-width arm.

$$ e \models \mathtt{c1000} \iff w \le 1000 \lor d_w \le 500 \lor (\eta = \text{none} \land \pi = \text{coarse} \land w \le 1200) $$ -/
def c1000 : MQ := combo 1000
/-- `mq.c1030`: combo 1030 with the device-width arm.

$$ e \models \mathtt{c1030} \iff w \le 1030 \lor d_w \le 500 \lor (\eta = \text{none} \land \pi = \text{coarse} \land w \le 1200) $$ -/
def c1030 : MQ := combo 1030
/-- `mq.c1000-nodw`: combo 1000 **without** the device-width arm (countdown).

$$ e \models \mathtt{c1000Nodw} \iff w \le 1000 \lor (\eta = \text{none} \land \pi = \text{coarse} \land w \le 1200) $$ -/
def c1000Nodw : MQ := combo 1000 false

/-- Where the inventory says a condition is used: CSS `@media`, JS `matchMedia`, or both.

$$ \kappa \in \{\text{css}, \text{js}, \text{css+js}\} $$ -/
inductive Kind | css | js | cssJs
deriving DecidableEq, Repr

/-- The inventory's `kind` string.

$$ \mathrm{str}(\kappa) \in \{\texttt{css-media}, \texttt{js-matchMedia}, \texttt{css-media+js-matchMedia}\} $$ -/
def Kind.str : Kind → String
  | .css => "css-media" | .js => "js-matchMedia" | .cssJs => "css-media+js-matchMedia"

/-- One catalogue row: inventory id, TypeScript identifier, kind, and the query.

$$ c = (\mathrm{id}, \mathrm{ts}, \kappa, q) $$ -/
structure Entry where
  /-- inventory id, e.g. `mq.c860` -/
  id : String
  /-- TS-ready identifier, e.g. `c860` -/
  tsId : String
  /-- CSS / JS / both -/
  kind : Kind
  /-- the condition -/
  query : MQ
deriving Repr

/-- The 30 media conditions of the inventory, in the inventory's order.

$$ \mathrm{catalogue} = (c_0, \dots, c_{29}) $$ -/
def catalogue : List Entry := [
  ⟨"mq.rm-reduce", "rmReduce", .cssJs, rmReduce⟩,
  ⟨"mq.rm-nopref", "rmNopref", .css, rmNopref⟩,
  ⟨"mq.hover-hover", "hoverHover", .css, hoverHover⟩,
  ⟨"mq.hover-none", "hoverNone", .js, hoverNone⟩,
  ⟨"mq.dark", "dark", .css, dark⟩,
  ⟨"mq.w-le-400", "wLe400", .css, wLe400⟩,
  ⟨"mq.w-le-461", "wLe461", .css, wLe461⟩,
  ⟨"mq.w-le-480", "wLe480", .css, wLe480⟩,
  ⟨"mq.w-le-600", "wLe600", .cssJs, wLe600⟩,
  ⟨"mq.w-gt-600", "wGt600", .css, wGt600⟩,
  ⟨"mq.w-601-1279", "w601to1279", .css, w601to1279⟩,
  ⟨"mq.w-601-1511", "w601to1511", .css, w601to1511⟩,
  ⟨"mq.w-le-640", "wLe640", .css, wLe640⟩,
  ⟨"mq.w-gt-640", "wGt640", .css, wGt640⟩,
  ⟨"mq.w-641-1000", "w641to1000", .css, w641to1000⟩,
  ⟨"mq.w-le-720", "wLe720", .css, wLe720⟩,
  ⟨"mq.w-le-860", "wLe860", .cssJs, wLe860⟩,
  ⟨"mq.w-ge-861", "wGe861", .cssJs, wGe861⟩,
  ⟨"mq.w-ge-861-nopref", "wGe861Nopref", .css, wGe861Nopref⟩,
  ⟨"mq.w-861-1000", "w861to1000", .css, w861to1000⟩,
  ⟨"mq.w-le-960", "wLe960", .css, wLe960⟩,
  ⟨"mq.w-le-1000", "wLe1000", .css, wLe1000⟩,
  ⟨"mq.w-ge-1001", "wGe1001", .css, wGe1001⟩,
  ⟨"mq.w-ge-1001-nopref", "wGe1001Nopref", .css, wGe1001Nopref⟩,
  ⟨"mq.w-le-1100", "wLe1100", .css, wLe1100⟩,
  ⟨"mq.w-le-1200", "wLe1200", .css, wLe1200⟩,
  ⟨"mq.c860", "c860", .cssJs, c860⟩,
  ⟨"mq.c1000", "c1000", .cssJs, c1000⟩,
  ⟨"mq.c1030", "c1030", .css, c1030⟩,
  ⟨"mq.c1000-nodw", "c1000Nodw", .css, c1000Nodw⟩
]

/-! ## Edges: values change only where the syntax says -/

/-- Two widths lie on the same side of edge `N`, for both closed cuts the edge induces.

$$ \mathrm{SameSide}_N(a,b) \iff (a \le N \Leftrightarrow b \le N) \land (a \ge N{+}1 \Leftrightarrow b \ge N{+}1) $$

Neither the cut at `N` nor the cut at `N+1` separates `a` from `b` (for fractional widths these are two cuts). -/
def SameSide (N : Nat) (a b : Px) : Prop := (a.LeNat N ↔ b.LeNat N) ∧ (a.GeNat (N + 1) ↔ b.GeNat (N + 1))

/-- Two environments agree on every discrete media feature.

$$ e \sim e' \iff \eta = \eta' \land \pi = \pi' \land \mu = \mu' \land \sigma = \sigma' \land \tau = \tau' \land \phi = \phi' $$

Same hover, pointer, motion, colour-scheme, media-type and forced-colors settings; sizes, height and DPR may differ. -/
def Agree (e e' : Env) : Prop :=
  e.hover = e'.hover ∧ e.pointer = e'.pointer ∧ e.motion = e'.motion ∧ e.scheme = e'.scheme ∧
    e.mediaType = e'.mediaType ∧ e.forcedColors = e'.forcedColors

instance (e e' : Env) : Decidable (Agree e e') := inferInstanceAs (Decidable (_ ∧ _))

/-- A single feature keeps its value when no cut of it separates the two environments.

$$ e \sim e' \land (\forall N \in E_w(f).\ \mathrm{SameSide}_N(w,w')) \land
   (\forall N \in E_d(f).\ \mathrm{SameSide}_N(d_w,d_w')) \Rightarrow \llbracket f\rrbracket_e = \llbracket f\rrbracket_{e'} $$

A feature can only flip across one of its own edges. -/
theorem Feature.holds_congr {f : Feature} {e e' : Env} (hm : Agree e e')
    (hw : ∀ N ∈ f.widthCuts, SameSide N e.width e'.width)
    (hd : ∀ N ∈ f.dwCuts, SameSide N e.deviceWidth e'.deviceWidth) : f.holds e = f.holds e' := by
  obtain ⟨h1, h2, h3, h4, h5, h6⟩ := hm
  cases f with
  | widthLe n =>
    have := (hw n (by simp [Feature.widthCuts])).1
    simp only [Feature.holds]; exact decide_eq_decide.mpr this
  | widthGt n =>
    have := (hw n (by simp [Feature.widthCuts])).1
    simp only [Feature.holds, Px.GtNat]; simp only [Px.LeNat] at this
    exact decide_eq_decide.mpr (by omega)
  | widthGeSucc n =>
    have := (hw n (by simp [Feature.widthCuts])).2
    simp only [Feature.holds]; exact decide_eq_decide.mpr this
  | deviceWidthLe n =>
    have := (hd n (by simp [Feature.dwCuts])).1
    simp only [Feature.holds]; exact decide_eq_decide.mpr this
  | hover v => simp [Feature.holds, h1]
  | pointer v => simp [Feature.holds, h2]
  | motion v => simp [Feature.holds, h3]
  | scheme v => simp [Feature.holds, h4]
  | mediaType v => simp [Feature.holds, h5]
  | forcedColors v => simp [Feature.holds, h6]

private theorem all_congr' {α} {l : List α} {f g : α → Bool} (h : ∀ x ∈ l, f x = g x) : l.all f = l.all g := by
  induction l with
  | nil => rfl
  | cons a t ih => simp only [List.all_cons, h a (by simp), ih (fun x hx => h x (by simp [hx]))]

private theorem any_congr' {α} {l : List α} {f g : α → Bool} (h : ∀ x ∈ l, f x = g x) : l.any f = l.any g := by
  induction l with
  | nil => rfl
  | cons a t ih => simp only [List.any_cons, h a (by simp), ih (fun x hx => h x (by simp [hx]))]

/-- **Edge sufficiency (rational widths).** A query keeps its value between two environments that agree on the
discrete features and are on the same side of every width edge and every device-width edge of the query.

$$ e \sim e' \land (\forall N \in E_w(q).\ \mathrm{SameSide}_N(w,w')) \land
   (\forall N \in E_d(q).\ \mathrm{SameSide}_N(d_w,d_w')) \Rightarrow \llbracket q\rrbracket_e = \llbracket q\rrbracket_{e'} $$

The truth value of any condition changes only at the edges listed by its syntax. -/
theorem MQ.eval_congr {q : MQ} {e e' : Env} (hm : Agree e e')
    (hw : ∀ N ∈ q.widthEdges, SameSide N e.width e'.width)
    (hd : ∀ N ∈ q.dwEdges, SameSide N e.deviceWidth e'.deviceWidth) : q.eval e = q.eval e' := by
  unfold MQ.eval
  apply any_congr'
  intro arm harm
  apply all_congr'
  intro f hf
  apply Feature.holds_congr hm
  · intro N hN; exact hw N (by simp only [MQ.widthEdges, List.mem_flatMap]; exact ⟨arm, harm, f, hf, hN⟩)
  · intro N hN; exact hd N (by simp only [MQ.dwEdges, List.mem_flatMap]; exact ⟨arm, harm, f, hf, hN⟩)

/-- For whole-pixel widths, being on the same side of edge `N` is just comparing with `N`.

$$ \mathrm{SameSide}_N(a/1, b/1) \iff (a \le N \Leftrightarrow b \le N) \qquad (a, b \in \mathbb{N}) $$

At integer widths the two cuts of an edge coincide, so the pair `N | N+1` is the whole edge. -/
theorem sameSide_ofNat {N a b : Nat} : SameSide N (Px.ofNat a) (Px.ofNat b) ↔ (a ≤ N ↔ b ≤ N) := by
  simp only [SameSide, Px.LeNat, Px.GeNat, Px.ofNat]
  omega

/-- **Edge sufficiency (whole pixels).** At integer widths and device widths, a query has the same value at any
two sizes that compare the same way with every edge of the query; so between consecutive edges it is constant and
probing `N` and `N+1` at each edge `N` observes every change.

$$ e \sim e' \land (\forall N \in E_w(q).\ a \le N \Leftrightarrow b \le N) \land
   (\forall N \in E_d(q).\ c \le N \Leftrightarrow d \le N) \Rightarrow
   \llbracket q\rrbracket_{e[w:=a,\,d_w:=c]} = \llbracket q\rrbracket_{e'[w:=b,\,d_w:=d]} \qquad (a,b,c,d \in \mathbb{N}) $$

Whole-pixel widths in the same band between edges give the same answer. -/
theorem MQ.eval_ofNat_congr {q : MQ} {e e' : Env} {a b c d : Nat} (hm : Agree e e')
    (hw : ∀ N ∈ q.widthEdges, (a ≤ N ↔ b ≤ N)) (hd : ∀ N ∈ q.dwEdges, (c ≤ N ↔ d ≤ N)) :
    q.eval { e with width := Px.ofNat a, deviceWidth := Px.ofNat c } =
      q.eval { e' with width := Px.ofNat b, deviceWidth := Px.ofNat d } :=
  MQ.eval_congr hm (fun N hN => sameSide_ofNat.mpr (hw N hN)) (fun N hN => sameSide_ofNat.mpr (hd N hN))

/-- **Bands.** If no width edge `N` of `q` satisfies `a ≤ N < b`, then `q` has the same value at every
whole-pixel width from `a` to `b` (device width and discrete features fixed).

$$ (\forall N \in E_w(q).\ \neg(a \le N < b)) \land a \le x \le b \Rightarrow
   \llbracket q\rrbracket_{e[w:=a]} = \llbracket q\rrbracket_{e[w:=x]} \qquad (a,b,x \in \mathbb{N}) $$

Between two consecutive edges a condition is constant. -/
theorem MQ.eval_const_on_band {q : MQ} {e : Env} {a b x : Nat}
    (hband : ∀ N ∈ q.widthEdges, ¬ (a ≤ N ∧ N < b)) (hx : a ≤ x ∧ x ≤ b) :
    q.eval { e with width := Px.ofNat a } = q.eval { e with width := Px.ofNat x } := by
  refine MQ.eval_congr ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩ ?_ ?_
  · intro N hN
    have := hband N hN
    exact sameSide_ofNat.mpr (by omega)
  · intro N _
    exact ⟨Iff.rfl, Iff.rfl⟩

/-! ## Examples (`#guard`, run at build time) -/

/-- A desktop environment at whole-pixel width `w` and screen width `d` (examples only).

$$ \mathrm{ex}(w, d, \eta, \pi) = (w, 900, d, 900, 1, \eta, \pi, \text{no-preference}, \text{light}, \text{screen}, \text{none}) $$

A test fixture for the `#guard` examples. -/
def exEnv (w d : Nat) (h : Hover := .hover) (p : Pointer := .fine) : Env :=
  { width := .ofNat w, height := .ofNat 900, deviceWidth := .ofNat d, deviceHeight := .ofNat 900,
    dpr := .ofNat 1, hover := h, pointer := p, motion := .noPreference, scheme := .light }

#guard wLe600.eval (exEnv 600 600) && !wLe600.eval (exEnv 601 601)
#guard !wGt600.eval (exEnv 600 600) && wGt600.eval (exEnv 601 601)
#guard w601to1279.eval (exEnv 601 601) && w601to1279.eval (exEnv 1279 1279) && !w601to1279.eval (exEnv 1280 1280)
#guard !wGe861.eval { exEnv 861 861 with width := Px.half 860 } && !wLe860.eval { exEnv 861 861 with width := Px.half 860 }
#guard wGt600.eval { exEnv 600 600 with width := Px.half 600 }
#guard c860.eval (exEnv 1024 1024 .none .coarse) && wGe861.eval (exEnv 1024 1024 .none .coarse)
#guard !c860.eval (exEnv 1024 1024 .none .fine) && !c860.eval (exEnv 1024 1024 .hover .coarse)
#guard c1000.eval (exEnv 1031 500) && !c1000Nodw.eval (exEnv 1031 500)
#guard !c1030.eval (exEnv 1201 1201 .none .coarse) && c1030.eval (exEnv 1200 1200 .none .coarse)
#guard c860.css == "(width<=860px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)"
#guard c1000Nodw.css == "(width<=1000px), (hover: none) and (pointer: coarse) and (width<=1200px)"
#guard wGt600.legacyCss == none && wGe861.legacyCss == some "(min-width: 861px)"
#guard c860.edgesPx == [500, 860, 1200] && w601to1511.taggedEdges == [(.width, 600), (.width, 1511)]

end Fw.Site.Breakpoints
