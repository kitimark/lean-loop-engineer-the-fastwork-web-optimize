import Fw.Gate.Items
import Lean.Data.Json

/-!
# When two `align-self` values place a grid item the same way

The breakpoint gate compares every computed-style property either arm declares. A port may need a different
`align-self` value than the original only to work around an engine quirk (platform.stageBg: `align-self: start` on a
grid item with an aspect ratio, WebKit RenderGrid.cpp@862f17d). This module states when two values, each read with
its own arm's context, give the same used alignment under the spec, so the gate may judge the pair equal. Geometry
(the box items) is still compared (`geometry_still_compared`), so a wrong judgement here can never hide a moved box.

Spec (csswg-drafts@7b4c69e):
* css-align-3 §6.2 `align-self`: `auto` computes to the parent's computed `align-items`; behaves as `normal` for an
  absolutely positioned box. Auto margins take precedence over `align-self`.
* css-align-3 §6.2.5 Grid Items: the alignment container is the grid area, in the grid's block axis. `normal` sizes
  as `stretch` (typical non-replaced) or `start`, then the box is start-aligned.
* css-align-3 §6.1 `stretch`: applies when the computed block size is `auto` and neither margin in the axis is
  `auto`; the used size brings the outer size as close to the alignment container's size as possible while honouring
  min/max; otherwise it falls back to `flex-start`, which outside a flex formatting context is `start` (§4.1).
* css-grid-1 §6.2 Grid Item Sizing: `normal` with no preferred aspect ratio (and, if replaced, no natural size) sizes
  as `stretch`; otherwise by the block-level rules for the axis. `stretch` is the stretch-fit size; every other value
  uses fit-content.
* MEASURED (premise `grid.normal-aspect-ratio-no-stretch`, CI run 39080496538): for a non-replaced item with a
  preferred aspect ratio, `normal` gives the ratio height in WebKit but stretches to the row in Chromium, so the rule
  gives that case mode `other` (judged by neither engine's reading).
* css-sizing-3 §2.1: for block containers the min-content and max-content block sizes are the content block size, so
  fit-content in the block axis is the block-level auto height.

What breaks the rule (the item is then not eligible, or its mode is `other`): auto block margins, a declared non-auto
height, `baseline` or any value other than normal / stretch / start / flex-start, a writing mode other than
`horizontal-tb` on the item or its container, absolute positioning, a container that is not a grid, `normal` on a
box that is not a non-replaced HTML block container, `normal` on a box with a preferred aspect ratio (engines differ),
and an `auto` that resolves to a parent `align-items` outside those values.
-/

namespace Fw.Gate.AlignEquiv

open Fw.Gate Lean

/-! ## Facts and modes -/

/-- The used behaviour class of an `align-self` value on a grid item, in the block axis.

$$\mathrm{Mode} = \{\mathrm{content},\ \mathrm{fill},\ \mathrm{other}\}$$

`content`: start-aligned at its content (fit-content) size; `fill`: start-aligned and stretched to the grid area;
`other`: anything this rule does not judge. -/
inductive Mode
  | content | fill | other
  deriving DecidableEq, Repr, Inhabited

/-- Mode names as written in the golden vectors.

$$\operatorname{name}(\mathrm{content}) = \texttt{"content"},\ \operatorname{name}(\mathrm{fill}) = \texttt{"fill"},\ \operatorname{name}(\mathrm{other}) = \texttt{"other"}$$

The wire spelling of a mode. -/
def Mode.name : Mode → String
  | .content => "content"
  | .fill => "fill"
  | .other => "other"

/-- The facts one arm collects for one grid item: computed values (strings as `getComputedStyle` returns them), two
declared-style facts read from the matched rules and the inline style (`autoMargin`: `margin-top`,
`margin-bottom`, `margin-block-start` or `margin-block-end` declared `auto`; `heightAuto`: no `height` or
`block-size` declared other than `auto`), and three viewport-relative tops from `getBoundingClientRect`
(`rectTop`, `rectHeight` of the item, `parentRectTop` of its container). `parent*` and `alignItems`,
`alignContent`, `rows`, `rowGap` are the container's.

$$s \in \mathrm{String}^{24} \times \mathbb B^{3} \times \mathbb Q^{3}$$

One arm's view of one item. -/
structure Side where
  alignSelf : String
  alignItems : String
  display : String
  position : String
  localName : String
  html : Bool
  aspectRatio : String
  writingMode : String
  parentDisplay : String
  parentWritingMode : String
  autoMargin : Bool
  heightAuto : Bool
  alignContent : String
  rowStart : String
  rowEnd : String
  rows : String
  rowGap : String
  boxSizing : String
  height : String
  paddingTop : String
  paddingBottom : String
  borderTop : String
  borderBottom : String
  marginTop : String
  marginBottom : String
  parentBorderTop : String
  parentPaddingTop : String
  rectTop : Rat
  rectHeight : Rat
  parentRectTop : Rat
  deriving Repr, Inhabited

/-- The value `align-self` resolves to: the container's `align-items` for `auto` (css-align-3 §6.2).

$$\operatorname{resolve}(s) = \begin{cases} s.\mathrm{alignItems} & s.\mathrm{alignSelf} = \texttt{auto} \\ s.\mathrm{alignSelf} & \text{otherwise} \end{cases}$$

`auto` defers to the parent. -/
def resolve (s : Side) : String :=
  if s.alignSelf == "auto" then s.alignItems else s.alignSelf

/-- A positive number with nothing after it, in the number grammar of `Fw.Gate.numAt`.

$$\operatorname{pos}(v) \iff \exists d,\ \operatorname{numAt}(\operatorname{chars}(v)) = \mathrm{some}(d, [\,]) \wedge \operatorname{val}(d) > 0$$

A ratio term that is a positive number. -/
def posNum (v : String) : Bool :=
  match numAt v.toList with
  | some (d, []) => decide (0 < d.val)
  | _ => false

/-- Whether the computed `aspect-ratio` gives a preferred aspect ratio: `auto` none; `a / b` or `auto a / b` with
$a, b > 0$ one (the box is non-replaced where it matters, so `auto a / b` uses the ratio); anything else unknown.

$$\operatorname{ratio}(v) = \begin{cases} \mathrm{some}(\mathrm{false}) & v = \texttt{auto} \\ \mathrm{some}(\mathrm{true}) & \operatorname{split}_{\texttt{" / "}}(v') = [a, b] \text{ (exactly one separator)},\ \operatorname{pos}(a),\ \operatorname{pos}(b) \\ \bot & \text{otherwise} \end{cases},\quad v' = \begin{cases} v \text{ without its first 5 chars} & v \text{ starts with } \texttt{"auto "} \\ v & \text{otherwise} \end{cases}$$

(a degenerate ratio such as `0 / 1` is unknown). Tri-state, so an unreadable value never picks a mode. -/
def ratioOf (v : String) : Option Bool :=
  if v == "auto" then some false
  else
    let body := if v.startsWith "auto " then String.ofList (v.toList.drop 5) else v
    match body.splitOn " / " with
    | [a, b] => if posNum a && posNum b then some true else none
    | _ => none

/-- Local names of replaced (or form-control) HTML elements.

$$\mathrm{Replaced} = [\texttt{img}, \texttt{video}, \texttt{audio}, \texttt{canvas}, \texttt{iframe}, \texttt{embed}, \texttt{object}, \texttt{input}, \texttt{textarea}, \texttt{select}, \texttt{button}, \texttt{meter}, \texttt{progress}, \texttt{frame}]$$

Elements whose `normal` sizing may follow a natural size. -/
def replacedTags : List String :=
  ["img", "video", "audio", "canvas", "iframe", "embed", "object", "input", "textarea", "select", "button", "meter",
   "progress", "frame"]

/-- A non-replaced HTML block container (blockified grid items compute `display: block`).

$$\operatorname{blockC}(s) \iff s.\mathrm{html} \wedge s.\mathrm{display} \in \{\texttt{block}, \texttt{flow-root}\} \wedge s.\mathrm{localName} \notin \mathrm{Replaced}$$

Boxes whose fit-content block size is their block-level auto height (css-sizing-3 §2.1). -/
def blockContainer (s : Side) : Bool :=
  s.html && (s.display == "block" || s.display == "flow-root") && !replacedTags.contains s.localName

/-- The mode of the resolved value (css-align-3 §6.1, §4.1, §6.2.5; css-grid-1 §6.2).

$$\operatorname{mode}(s) = \begin{cases} \mathrm{fill} & v = \texttt{stretch} \\ \mathrm{content} & v \in \{\texttt{start}, \texttt{flex-start}\} \\ \mathrm{fill} & v = \texttt{normal} \wedge \operatorname{blockC}(s) \wedge \operatorname{ratio}(s.\mathrm{aspectRatio}) = \mathrm{some}(\mathrm{false}) \\ \mathrm{other} & \text{otherwise} \end{cases},\quad v = \operatorname{resolve}(s)$$

How the value sizes and places the item, or `other` (also for `normal` with a preferred aspect ratio, where the
engines differ). -/
def modeOf (s : Side) : Mode :=
  match resolve s with
  | "stretch" => .fill
  | "start" => .content
  | "flex-start" => .content
  | "normal" =>
    if blockContainer s then
      match ratioOf s.aspectRatio with
      | some true => .other
      | some false => .fill
      | none => .other
    else .other
  | _ => .other

/-- `normal` on a box with a preferred aspect ratio is never judged: Chromium stretches it, WebKit does not
(MEASURED, premise `grid.normal-aspect-ratio-no-stretch`).

$$\forall s,\quad \operatorname{resolve}(s) = \texttt{normal} \wedge \operatorname{ratio}(s.\mathrm{aspectRatio}) = \mathrm{some}(\mathrm{true}) \implies \operatorname{mode}(s) = \mathrm{other}$$

An engine-dependent size gives no mode. -/
theorem modeOf_normal_ratio (s : Side) (hn : resolve s = "normal") (hr : ratioOf s.aspectRatio = some true) :
    modeOf s = .other := by
  unfold modeOf
  rw [hn]
  split <;> simp_all

/-- The item is an in-flow grid item in a horizontal writing mode, with no auto block margin and no declared
non-auto height.

$$\operatorname{elig}(s) \iff s.\mathrm{parentDisplay} \in \{\texttt{grid}, \texttt{inline-grid}\} \wedge s.\mathrm{position} \notin \{\texttt{absolute}, \texttt{fixed}\} \wedge s.\mathrm{display} \notin \{\texttt{none}, \texttt{contents}\} \wedge s.\mathrm{writingMode} = s.\mathrm{parentWritingMode} = \texttt{horizontal-tb} \wedge \neg s.\mathrm{autoMargin} \wedge s.\mathrm{heightAuto}$$

The cases where the modes mean what `place` says. -/
def eligible (s : Side) : Bool :=
  (s.parentDisplay == "grid" || s.parentDisplay == "inline-grid") &&
  s.position != "absolute" && s.position != "fixed" &&
  s.display != "none" && s.display != "contents" &&
  s.writingMode == "horizontal-tb" && s.parentWritingMode == "horizontal-tb" &&
  !s.autoMargin && s.heightAuto

/-! ## Measured geometry -/

/-- A CSS pixel length `<number>px`.

$$\operatorname{px}(v) = \begin{cases} \operatorname{val}(d) & \operatorname{numAt}(\operatorname{chars}(v)) = \mathrm{some}(d, [\texttt{p}, \texttt{x}]) \\ \bot & \text{otherwise} \end{cases}$$

Reads a resolved length. -/
def px (v : String) : Option Rat :=
  match numAt v.toList with
  | some (d, ['p', 'x']) => some d.val
  | _ => none

/-- Replace bracketed line names by spaces (depth counted; `]` at depth 0 stays at depth 0).

$$\operatorname{strip}(c_1 \dots c_n, d) = c'_1 \dots,\quad c'_k = \begin{cases} \text{space} & c_k \in \{\texttt{[}, \texttt{]}\} \\ c_k & c_k \notin \{\texttt{[}, \texttt{]}\},\ d_k = 0 \\ \text{dropped} & \text{otherwise} \end{cases},\quad d_{k+1} = \begin{cases} d_k + 1 & c_k = \texttt{[} \\ d_k \mathbin{\dot-} 1 & c_k = \texttt{]} \\ d_k & \text{otherwise} \end{cases},\ d_1 = d$$

Line names carry no size. -/
def stripNames : List Char → Nat → List Char
  | [], _ => []
  | '[' :: r, d => ' ' :: stripNames r (d + 1)
  | ']' :: r, d => ' ' :: stripNames r (d - 1)
  | c :: r, d => if d == 0 then c :: stripNames r d else stripNames r d

/-- The row track sizes from the container's resolved `grid-template-rows` (every track listed in px).

$$\operatorname{tracks}(v) = \begin{cases} [\operatorname{px}(w_1), \dots, \operatorname{px}(w_n)] & n \ge 1 \wedge \forall k,\ \operatorname{px}(w_k) \ne \bot \\ \bot & \text{otherwise} \end{cases}$$

where $w_1, \dots, w_n$ are the non-empty space-separated words of $\operatorname{strip}(v, 0)$. The used row sizes. -/
def parseTracks (v : String) : Option (List Rat) :=
  let ws := ((String.ofList (stripNames v.toList 0)).splitOn " ").filter (· != "")
  if ws.isEmpty then none else ws.mapM px

/-- The row gap: `normal` is 0 in a grid (css-align-3 §8.1), otherwise a px length.

$$\operatorname{gap}(s) = \begin{cases} 0 & s.\mathrm{rowGap} = \texttt{normal} \\ \operatorname{px}(s.\mathrm{rowGap}) & \text{otherwise} \end{cases}$$

Space between rows. -/
def gapOf (s : Side) : Option Rat :=
  if s.rowGap == "normal" then some 0 else px s.rowGap

/-- The item's border-box height from computed values (`height` is the border-box height under `border-box`).

$$\operatorname{bh}(s) = \begin{cases} \operatorname{px}(s.\mathrm{height}) & s.\mathrm{boxSizing} = \texttt{border-box} \\ \operatorname{px}(s.\mathrm{height}) + \operatorname{px}(s.\mathrm{paddingTop}) + \operatorname{px}(s.\mathrm{paddingBottom}) + \operatorname{px}(s.\mathrm{borderTop}) + \operatorname{px}(s.\mathrm{borderBottom}) & \text{otherwise} \end{cases}$$

$\operatorname{bh}(s) = \bot$ iff $\operatorname{px}(s.\mathrm{height}) = \bot$ (under `border-box`; the other four are not read), or any of the five $\operatorname{px}$ terms is $\bot$ (otherwise). Layout height, free of transforms. -/
def borderH (s : Side) : Option Rat := do
  let h ← px s.height
  if s.boxSizing == "border-box" then some h
  else
    let pt ← px s.paddingTop
    let pb ← px s.paddingBottom
    let bt ← px s.borderTop
    let bb ← px s.borderBottom
    some (h + pt + pb + bt + bb)

/-- The item's outer (margin-box) block size.

$$\operatorname{outer}(s) = \operatorname{bh}(s) + \operatorname{px}(s.\mathrm{marginTop}) + \operatorname{px}(s.\mathrm{marginBottom})\quad (\bot \text{ if } \operatorname{bh}(s) = \bot \text{ or either } \operatorname{px} \text{ is } \bot)$$

What the alignment container holds. -/
def outerOf (s : Side) : Option Rat := do
  let b ← borderH s
  let mt ← px s.marginTop
  let mb ← px s.marginBottom
  some (b + mt + mb)

/-- Where the item's margin box starts below the container's content-box top.

$$\operatorname{off}(s) = s.\mathrm{rectTop} - s.\mathrm{parentRectTop} - \operatorname{px}(s.\mathrm{parentBorderTop}) - \operatorname{px}(s.\mathrm{parentPaddingTop}) - \operatorname{px}(s.\mathrm{marginTop})\quad (\bot \text{ if any } \operatorname{px} \text{ is } \bot)$$

The measured block offset. -/
def offsetOf (s : Side) : Option Rat := do
  let bt ← px s.parentBorderTop
  let pt ← px s.parentPaddingTop
  let mt ← px s.marginTop
  some (s.rectTop - s.parentRectTop - bt - pt - mt)

/-- Track start offsets: prefix sums of tracks and gaps.

$$\operatorname{starts}([t_0, \dots, t_{n-1}], g) = [S_0, \dots, S_{n-1}],\quad S_k = \sum_{m < k} (t_m + g)$$

Where each row begins. -/
def starts : List Rat → Rat → List Rat
  | [], _ => []
  | t :: ts, g => 0 :: (starts ts g).map (· + (t + g))

/-- The tolerance of the fill test, $\tfrac1{16}$ CSS px (the gate's box tolerance is $\tfrac12$).

$$\tau_f = \tfrac{1}{16}$$

Sub-pixel slack for layout rounding. -/
def tolFill : Rat := 1 / 16

/-- The indices whose start is within $\tau_f$ of an offset.

$$\operatorname{at}(S, x) = [\,k : 0 \le k < |S|,\ |S_k - x| \le \tau_f\,] \text{ (the list of such } k \text{ in increasing order; no } k \ge |S| \text{)}$$

Rows the measured offset could belong to. -/
def matchesAt (ss : List Rat) (x : Rat) : List Nat :=
  (List.range ss.length).filter fun k =>
    match ss[k]? with
    | some v => near tolFill v x
    | none => false

/-- An integer (optional `-`, at least one digit).

$$\operatorname{int}(v) \iff v \in \texttt{-}^{?}[\texttt{0}\text{-}\texttt{9}]^{+}$$

A grid line number. -/
def isIntStr (v : String) : Bool :=
  match v.toList with
  | '-' :: r => !r.isEmpty && r.all Char.isDigit
  | r => !r.isEmpty && r.all Char.isDigit

/-- The item spans exactly one row.

$$\operatorname{span1}(s) \iff s.\mathrm{rowEnd} \in \{\texttt{auto}, \texttt{span 1}\} \wedge (s.\mathrm{rowStart} = \texttt{auto} \vee \operatorname{int}(s.\mathrm{rowStart}))$$

Its grid area is one track. -/
def spanOne (s : Side) : Bool :=
  (s.rowEnd == "auto" || s.rowEnd == "span 1") && (s.rowStart == "auto" || isIntStr s.rowStart)

/-- The content-sized item already fills its row: the container packs rows at its start, the item spans one row,
is unscaled, exactly one row starts at its offset, and that row's size is its outer size (each within $\tau_f$).

$$\operatorname{fills}(s) \iff s.\mathrm{alignContent} \in \{\texttt{normal}, \texttt{stretch}, \texttt{start}, \texttt{flex-start}\} \wedge \operatorname{span1}(s) \wedge T = \operatorname{tracks}(s.\mathrm{rows}) \ne \bot \wedge g = \operatorname{gap}(s) \ne \bot \wedge b = \operatorname{bh}(s) \ne \bot \wedge o = \operatorname{outer}(s) \ne \bot \wedge x = \operatorname{off}(s) \ne \bot$$
$$\wedge\ b > 0 \wedge |s.\mathrm{rectHeight} - b| \le \tau_f \wedge \operatorname{at}(\operatorname{starts}(T, g), x) = [i] \text{ (exactly one index)} \wedge i < |T| \wedge |T_i - o| \le \tau_f$$

So stretching it would change nothing. -/
def contentFill (s : Side) : Bool :=
  ["normal", "stretch", "start", "flex-start"].contains s.alignContent && spanOne s &&
  match parseTracks s.rows, gapOf s, borderH s, outerOf s, offsetOf s with
  | some ts, some g, some b, some out, some off =>
    decide (0 < b) && near tolFill s.rectHeight b &&
    match matchesAt (starts ts g) off with
    | [i] =>
      match ts[i]? with
      | some a => near tolFill a out
      | none => false
    | _ => false
  | _, _, _, _, _ => false

/-! ## The rule -/

/-- Spec equivalence of two arms' values: both eligible, and the same mode, or `fill` against a `content` arm that
already fills its row.

$$\operatorname{eqv}(o, r) \iff \operatorname{elig}(o) \wedge \operatorname{elig}(r) \wedge \begin{cases} \mathrm{true} & \operatorname{mode}(o) = \operatorname{mode}(r) \in \{\mathrm{content}, \mathrm{fill}\} \\ \operatorname{fills}(r) & \operatorname{mode}(o) = \mathrm{fill},\ \operatorname{mode}(r) = \mathrm{content} \\ \operatorname{fills}(o) & \operatorname{mode}(o) = \mathrm{content},\ \operatorname{mode}(r) = \mathrm{fill} \\ \mathrm{false} & \text{otherwise (a mode is other)} \end{cases}$$

The two values place the item alike. -/
def equivSpec (o r : Side) : Bool :=
  eligible o && eligible r &&
  match modeOf o, modeOf r with
  | .content, .content => true
  | .fill, .fill => true
  | .fill, .content => contentFill r
  | .content, .fill => contentFill o
  | _, _ => false

/-- The gate's judgement for a declared `align-self` pair: the same computed value, or spec-equivalent.

$$\operatorname{alignEquiv}(o, r) \iff o.\mathrm{alignSelf} = r.\mathrm{alignSelf} \ \vee\ \operatorname{eqv}(o, r)$$

Equal values stay equal; different values are equal only by the spec rule. -/
def alignEquiv (o r : Side) : Bool :=
  o.alignSelf == r.alignSelf || equivSpec o r

/-- The rule judges every value equal to itself.

$$\forall s,\quad \operatorname{alignEquiv}(s, s)$$

Reflexive. -/
theorem alignEquiv_refl (s : Side) : alignEquiv s s = true := by
  simp [alignEquiv]

/-- The spec equivalence does not depend on which arm is the original.

$$\forall o, r,\quad \operatorname{eqv}(o, r) = \operatorname{eqv}(r, o)$$

Symmetric. -/
theorem equivSpec_symm (o r : Side) : equivSpec o r = equivSpec r o := by
  unfold equivSpec
  cases modeOf o <;> cases modeOf r <;> cases eligible o <;> cases eligible r <;> rfl

/-- The gate's judgement does not depend on which arm is the original.

$$\forall o, r,\quad \operatorname{alignEquiv}(o, r) = \operatorname{alignEquiv}(r, o)$$

Symmetric. -/
theorem alignEquiv_symm (o r : Side) : alignEquiv o r = alignEquiv r o := by
  unfold alignEquiv
  rw [equivSpec_symm, beq_swap]

/-! ## Soundness against the spec's placement -/

/-- The spec facts of one item in its row: the area's start and size, the content (fit-content = block-level auto)
outer size, and the outer sizes min/max allow, $[\mathit{lo}, \mathit{hi}]$ ($\mathit{hi} = \bot$: no maximum).

$$L = (\mathit{start}, A, C, \mathit{lo}, \mathit{hi}) \in \mathbb Q^{4} \times \mathbb Q_\bot$$

What the spec computes before alignment. -/
structure Layout where
  start : Rat
  area : Rat
  content : Rat
  lo : Rat
  hi : Option Rat

/-- Clamp a size to $[\mathit{lo}, \mathit{hi}]$, min winning over max (CSS 2 §10.7).

$$\operatorname{clamp}(\mathit{lo}, \mathit{hi}, x) = \max(\mathit{lo}, \min(\mathit{hi}, x))\quad (\min(\bot, x) = x)$$

The stretch-fit size honouring min/max. -/
def clampTo (lo : Rat) (hi : Option Rat) (x : Rat) : Rat :=
  max lo (match hi with | some h => min h x | none => x)

/-- The margin box the spec gives each mode: offset from the area start and outer size (css-align-3 §6.1, §6.2.5;
css-grid-1 §6.2).

$$\operatorname{place}(L, m) = \begin{cases} (0, L.C) & m = \mathrm{content} \\ (0, \operatorname{clamp}(L.\mathit{lo}, L.\mathit{hi}, L.A)) & m = \mathrm{fill} \\ \bot & m = \mathrm{other} \end{cases}$$

Start-aligned, at content size or stretched. -/
def place (L : Layout) : Mode → Option (Rat × Rat)
  | .content => some (0, L.content)
  | .fill => some (0, clampTo L.lo L.hi L.area)
  | .other => none

/-- Distance on $\mathbb Q$.

$$\operatorname{dist}(a, b) = |a - b|$$

How far apart two sizes are. -/
def dist (a b : Rat) : Rat := if a ≤ b then b - a else a - b

/-- The measurement premise for one arm: its layout's content size is allowed by min/max, its tracks and gap are the
parsed ones, its area is one of those rows, and the measured offset and outer size are its placed box.

$$\operatorname{agrees}(s, L) \iff L.\mathit{lo} \le L.C \wedge (\forall h,\ L.\mathit{hi} = h \implies L.C \le h) \wedge \exists T, g, j,\ \big(\operatorname{tracks}(s.\mathrm{rows}) = \mathrm{some}(T) \wedge \operatorname{gap}(s) = \mathrm{some}(g) \wedge j < |T| \wedge T_j = L.A \wedge \operatorname{starts}(T, g)_j = L.\mathit{start}$$
$$\wedge\ \forall p,\ \operatorname{place}(L, \operatorname{mode}(s)) = \mathrm{some}(p) \implies \operatorname{off}(s) = \mathrm{some}(L.\mathit{start} + p_1) \wedge \operatorname{outer}(s) = \mathrm{some}(p_2)\big)$$

When $\operatorname{mode}(s) = \mathrm{other}$, $\operatorname{place} = \bot$ and the last clause holds vacuously.

Rects and resolved values report the layout (registered premise `grid.stretch-fill-equals-start`). -/
def Agrees (s : Side) (L : Layout) : Prop :=
  L.lo ≤ L.content ∧ (∀ h, L.hi = some h → L.content ≤ h) ∧
  ∃ (ts : List Rat) (g : Rat) (j : Nat),
    parseTracks s.rows = some ts ∧ gapOf s = some g ∧ ts[j]? = some L.area ∧ (starts ts g)[j]? = some L.start ∧
    ∀ p, place L (modeOf s) = some p → offsetOf s = some (L.start + p.1) ∧ outerOf s = some p.2

/-- A size within $t$ of an allowed content size clamps to within $t$ of it.

$$\forall \mathit{lo}, \mathit{hi}, a, c, t,\quad \mathit{lo} \le c \wedge (\forall h,\ \mathit{hi} = h \implies c \le h) \wedge |a - c| \le t \implies \operatorname{dist}(\operatorname{clamp}(\mathit{lo}, \mathit{hi}, a), c) \le t$$

Clamping never moves a size away from an allowed one. -/
theorem clamp_dist (lo : Rat) (hi : Option Rat) (a c t : Rat) (hlo : lo ≤ c) (hhi : ∀ h, hi = some h → c ≤ h)
    (hn : near t a c = true) : dist (clampTo lo hi a) c ≤ t := by
  simp only [near, Bool.and_eq_true, decide_eq_true_eq] at hn
  obtain ⟨h1, h2⟩ := hn
  cases hi with
  | none => simp only [clampTo, dist]; grind
  | some h =>
    have := hhi h rfl
    simp only [clampTo, dist]; grind

/-- If row $j$ starts exactly at the offset and the offset matches only row $i$, then $i = j$.

$$\forall S, x, i, j,\quad j < |S| \wedge S_j = x \wedge \operatorname{at}(S, x) = [i] \implies i = j$$

The measured offset identifies the row. -/
theorem matchesAt_unique (ss : List Rat) (x : Rat) (i j : Nat) (hj : ss[j]? = some x)
    (hm : matchesAt ss x = [i]) : i = j := by
  have hlt : j < ss.length := by
    rcases Nat.lt_or_ge j ss.length with h | h
    · exact h
    · simp [List.getElem?_eq_none h] at hj
  have hmem : j ∈ matchesAt ss x := by
    simp only [matchesAt, List.mem_filter, List.mem_range, hj]
    refine ⟨hlt, ?_⟩
    simp only [near, Bool.and_self, tolFill]; grind
  rw [hm] at hmem
  simp at hmem
  exact hmem.symm

/-- Soundness: when the rule judges two values equivalent, on one of the two arms (the measured content arm, or
either when the modes agree) placing the item with the original's mode or with the rewrite's mode gives the same
offset exactly ($p_1 = q_1$) and outer sizes within $\tau_f$ ($\operatorname{dist}(p_2, q_2) \le \tau_f$), for every layout that agrees with that arm's facts; neither mode is `other`.

$$\forall o, r,\quad \operatorname{eqv}(o, r) \implies \exists X \in \{o, r\},\ \forall L,\ \operatorname{agrees}(X, L) \implies \exists p, q,\ \operatorname{place}(L, \operatorname{mode}(o)) = \mathrm{some}(p) \wedge \operatorname{place}(L, \operatorname{mode}(r)) = \mathrm{some}(q) \wedge p_1 = q_1 \wedge \operatorname{dist}(p_2, q_2) \le \tau_f$$

The two values give the same used alignment. -/
theorem equivSpec_sound (o r : Side) (h : equivSpec o r = true) :
    ∃ X, (X = o ∨ X = r) ∧ ∀ L, Agrees X L →
      ∃ p q, place L (modeOf o) = some p ∧ place L (modeOf r) = some q ∧ p.1 = q.1 ∧ dist p.2 q.2 ≤ tolFill := by
  -- the content arm `X` fills its row, so its fill placement is its content placement
  have key : ∀ X, modeOf X = .content → contentFill X = true → ∀ L, Agrees X L →
      dist (clampTo L.lo L.hi L.area) L.content ≤ tolFill := by
    intro X hX hf L ⟨hlo, hhi, ts, g, j, hts, hg, harea, hstart, hp⟩
    obtain ⟨hoff, hout⟩ := hp (0, L.content) (by simp [hX, place])
    simp only [Rat.add_zero] at hoff
    simp only [contentFill, Bool.and_eq_true, hts, hg, hoff, hout] at hf
    obtain ⟨_, hrest⟩ := hf
    revert hrest
    cases borderH X with
    | none => simp
    | some b =>
      simp only [Bool.and_eq_true]
      intro ⟨_, hm⟩
      revert hm
      split
      · rename_i i hi
        have := matchesAt_unique _ _ _ _ hstart hi
        subst this
        rw [harea]
        exact clamp_dist _ _ _ _ _ hlo hhi
      · simp
  have d0 : ∀ a : Rat, dist a a ≤ tolFill := by intro a; simp [dist, tolFill]; grind
  have dsymm : ∀ a b : Rat, dist a b = dist b a := by intro a b; simp only [dist]; grind
  unfold equivSpec at h
  simp only [Bool.and_eq_true] at h
  obtain ⟨_, hm⟩ := h
  cases ho : modeOf o <;> cases hr : modeOf r <;> rw [ho, hr] at hm <;>
    (try simp only [Bool.false_eq_true] at hm)
  · exact ⟨r, Or.inr rfl, fun L _ => ⟨_, _, rfl, rfl, rfl, d0 _⟩⟩
  · refine ⟨o, Or.inl rfl, fun L hL => ⟨_, _, rfl, rfl, rfl, ?_⟩⟩
    rw [dsymm]; exact key o ho hm L hL
  · refine ⟨r, Or.inr rfl, fun L hL => ⟨_, _, rfl, rfl, rfl, ?_⟩⟩
    exact key r hr hm L hL
  · exact ⟨r, Or.inr rfl, fun L _ => ⟨_, _, rfl, rfl, rfl, d0 _⟩⟩

/-- The fill tolerance stays well inside the gate's box tolerance.

$$2\tau_f \le \tfrac12 = \tau_{\mathrm{box}}$$

Accepting a pair never needs more slack than a box comparison allows. -/
theorem tol_below_box : 2 * tolFill ≤ tolBox := by
  simp only [tolFill, tolBox]; grind

/-! ## What the gate does with a judgement -/

/-- Canonicalise the rewrite element of a pair: when the pair is judged equivalent, its `align-self` value is set to
the original's; otherwise it is unchanged.

$$\operatorname{canon}(e, x, y) = \begin{cases} \operatorname{setStyle}_{\texttt{align-self},\, x[\texttt{align-self}]}(y) & e \\ y & \neg e \end{cases}$$

The only edit the rule makes. -/
def canonItem (e : Bool) (io ir : Item) : Item :=
  if e then setStyle "align-self" (io.style.lookup "align-self") ir else ir

/-- Canonicalising keeps the box.

$$\forall e, x, y,\quad \operatorname{canon}(e, x, y).\mathrm{rect} = y.\mathrm{rect}$$

No geometry is touched. -/
theorem canonItem_rect (e : Bool) (io ir : Item) : (canonItem e io ir).rect = ir.rect := by
  unfold canonItem; split <;> rfl

/-- Canonicalising keeps every other property.

$$\forall e, x, y, q,\quad q \ne \texttt{align-self} \implies \operatorname{canon}(e, x, y)[q] = y[q]$$

Only `align-self` can change. -/
theorem canonItem_lookup_ne (e : Bool) (io ir : Item) (q : String) (hq : q ≠ "align-self") :
    (canonItem e io ir).style.lookup q = ir.style.lookup q := by
  unfold canonItem; split
  · exact (setStyle_agree _ _ ir).2 q hq
  · rfl

/-- An equivalent pair's `align-self` items become equal.

$$\forall x, y, v,\quad x[\texttt{align-self}] = v \ne \bot \implies \operatorname{styleStatus}(x[\texttt{align-self}], \operatorname{canon}(\mathrm{true}, x, y)[\texttt{align-self}]) = \mathrm{equal}$$

The judged property passes. -/
theorem canonItem_align_equal (io ir : Item) (v : String) (hv : io.style.lookup "align-self" = some v) :
    styleStatus (io.style.lookup "align-self") ((canonItem true io ir).style.lookup "align-self") = .equal := by
  simp [canonItem, setStyle, hv, styleStatus, styleValueEq_refl]

/-- Hide the status of the non-box items with key $p$.

$$\operatorname{hide}_p(it) = \begin{cases} it \text{ with status } \mathrm{na},\ \delta = \mathrm{false} & it.\mathit{cls} \ne \mathrm{box} \wedge it.k = p \\ it & \text{otherwise} \end{cases}$$

Everything the rule leaves as it was. -/
def hideKey (p : String) (it : PItem) : PItem :=
  if it.cls ≠ .box ∧ it.key = p then { it with status := .na, differs := false } else it

/-- Geometry is still compared: canonicalising changes no box item and no item of another property; only the
`align-self` style and information items may change.

$$\forall \mathit{rs}, C, I, q_o, q_r, i, e, x, y,\quad [\operatorname{hide}_{\texttt{align-self}}(it) \mid it \in \operatorname{itemAt}_{\mathit{rs}, C, I, q_o, q_r}(i, x, \operatorname{canon}(e, x, y))] = [\operatorname{hide}_{\texttt{align-self}}(it) \mid it \in \operatorname{itemAt}_{\mathit{rs}, C, I, q_o, q_r}(i, x, y)]$$

A wrong judgement can never hide a moved or resized box. -/
theorem geometry_still_compared (rs : RoleSpec) (cmp info : List String) (refO refR : Option Rect) (i : Nat)
    (e : Bool) (io ir : Item) :
    (itemAt rs cmp info refO refR i io (canonItem e io ir)).map (hideKey "align-self") =
      (itemAt rs cmp info refO refR i io ir).map (hideKey "align-self") := by
  simp only [itemAt, List.map_append, List.map_map]
  congr 1
  congr 1
  · apply List.map_congr_left
    intro d _
    simp [boxDim, canonItem_rect]
  · apply List.map_congr_left
    intro q _
    by_cases hq : q = "align-self"
    · subst hq; simp [hideKey]
    · simp [hideKey, canonItem_lookup_ne e io ir q hq]
  · apply List.map_congr_left
    intro q _
    by_cases hq : q = "align-self"
    · subst hq; simp [hideKey]
    · simp [hideKey, canonItem_lookup_ne e io ir q hq]

/-! ## Examples and golden vectors -/

/-- The platform stage at width ≤ 640 on the rewrite arm: `align-self: start`, container `align-items: stretch`,
an aspect-ratio box of 300 px in a 300 px first row.

$$s_0 = (\mathrm{alignSelf} = \texttt{start},\ \mathrm{alignItems} = \texttt{stretch},\ \mathrm{display} = \texttt{block},\ \mathrm{aspectRatio} = \texttt{640 / 512},\ \mathrm{parentDisplay} = \texttt{grid},\ \mathrm{rows} = \texttt{300px 52.1875px},\ \mathrm{height} = \texttt{300px},\ \mathrm{rectTop} = \mathrm{parentRectTop} = 100,\ \mathrm{rectHeight} = 300,\ \dots)$$

Every field is listed in the definition below; all paddings, borders and margins are `0px`.

The base case the golden vectors vary. -/
def base : Side where
  alignSelf := "start"
  alignItems := "stretch"
  display := "block"
  position := "relative"
  localName := "div"
  html := true
  aspectRatio := "640 / 512"
  writingMode := "horizontal-tb"
  parentDisplay := "grid"
  parentWritingMode := "horizontal-tb"
  autoMargin := false
  heightAuto := true
  alignContent := "normal"
  rowStart := "auto"
  rowEnd := "auto"
  rows := "300px 52.1875px"
  rowGap := "normal"
  boxSizing := "border-box"
  height := "300px"
  paddingTop := "0px"
  paddingBottom := "0px"
  borderTop := "0px"
  borderBottom := "0px"
  marginTop := "0px"
  marginBottom := "0px"
  parentBorderTop := "0px"
  parentPaddingTop := "0px"
  rectTop := 100
  rectHeight := 300
  parentRectTop := 100

/-- The original arm of the stage: `align-self: auto` under `align-items: stretch`. -/
def baseO : Side := { base with alignSelf := "auto" }

/-- The golden cases: name, original facts, rewrite facts.

$$\mathrm{cases} = [(n_k, o_k, r_k)]_k$$

Every branch of the rule, and each thing that breaks it. -/
def cases : List (String × Side × Side) := [
  ("stage-stretch-vs-start-fills", baseO, base),
  ("stage-start-does-not-fill", baseO, { base with rows := "320px 52.1875px" }),
  ("auto-normal-ratio-vs-start", { baseO with alignItems := "normal" }, { base with rows := "320px 52.1875px" }),
  ("auto-normal-ratio-auto-prefix", { baseO with alignItems := "normal", aspectRatio := "auto 640 / 512" },
    { base with rows := "320px" }),
  ("normal-no-ratio-vs-start-fills", { baseO with alignItems := "normal", aspectRatio := "auto" }, base),
  ("normal-no-ratio-vs-start-short", { baseO with alignItems := "normal", aspectRatio := "auto" },
    { base with rows := "320px" }),
  ("normal-degenerate-ratio", { baseO with alignItems := "normal", aspectRatio := "0 / 1" }, base),
  ("normal-replaced-img", { baseO with alignItems := "normal", localName := "img" }, base),
  ("normal-flex-display", { baseO with alignItems := "normal", display := "flex" }, base),
  ("normal-svg-namespace", { baseO with alignItems := "normal", html := false }, base),
  ("flex-start-vs-start", { baseO with alignSelf := "flex-start" }, { base with rows := "320px" }),
  ("stretch-vs-normal-no-ratio", { baseO with alignSelf := "stretch" },
    { base with alignSelf := "normal", aspectRatio := "auto", rows := "320px" }),
  ("start-fills-vs-stretch", base, { baseO with alignSelf := "stretch" }),
  ("auto-margin", baseO, { base with autoMargin := true }),
  ("height-declared", baseO, { base with heightAuto := false }),
  ("baseline", { baseO with alignItems := "baseline" }, base),
  ("baseline-both-same", { baseO with alignSelf := "baseline" }, { base with alignSelf := "baseline", rows := "1px" }),
  ("center-vs-start", { baseO with alignItems := "center" }, base),
  ("vertical-writing-mode", baseO, { base with writingMode := "vertical-rl" }),
  ("parent-vertical-writing-mode", { baseO with parentWritingMode := "vertical-lr" }, base),
  ("parent-flex", baseO, { base with parentDisplay := "flex" }),
  ("parent-inline-grid", baseO, { base with parentDisplay := "inline-grid" }),
  ("absolute", baseO, { base with position := "absolute" }),
  ("second-row", baseO,
    { base with height := "52.1875px", rectHeight := 52.1875, rectTop := 400 }),
  ("ambiguous-zero-row", baseO, { base with rows := "0px 300px" }),
  ("span-two", baseO, { base with rowStart := "span 2" }),
  ("named-line-start", baseO, { base with rowStart := "head" }),
  ("line-number-start", baseO, { base with rowStart := "1", rowEnd := "span 1" }),
  ("align-content-center", baseO, { base with alignContent := "center" }),
  ("scaled", baseO, { base with rectHeight := 275 }),
  ("rows-none", baseO, { base with rows := "none" }),
  ("rows-line-names", baseO, { base with rows := "[top] 300px [mid a] 52.1875px [end]" }),
  ("row-gap", baseO, { base with rows := "100px 300px", rowGap := "10px", rectTop := 210 }),
  ("content-box-padding", baseO,
    { base with boxSizing := "content-box", height := "280px", paddingTop := "10px", paddingBottom := "10px" }),
  ("margins", baseO,
    { base with rows := "316px", marginTop := "8px", marginBottom := "8px", rectTop := 108 }),
  ("container-border-padding", baseO,
    { base with parentBorderTop := "2px", parentPaddingTop := "6px", rectTop := 108 }),
  ("off-by-a-sixteenth", baseO, { base with rows := "300.0625px" }),
  ("off-by-an-eighth", baseO, { base with rows := "300.125px" })
]

/-- An exact decimal JSON number (the golden values are multiples of $10^{-6}$).

$$\operatorname{dec}(x) = \tfrac{x_{\mathrm{num}} \cdot \lfloor 10^6 / x_{\mathrm{den}} \rfloor}{10^6}$$

Exact only when $x_{\mathrm{den}} \mid 10^6$ (true for every golden value); otherwise the printed value is wrong, not rounded.

Golden numbers print as JavaScript reads them. -/
def ratJson (x : Rat) : Json :=
  Json.num ⟨x.num * ((1000000 / x.den : Nat) : Int), 6⟩

/-- The facts as the collector writes them (keys as in `align-equiv.mjs`). -/
def sideJson (s : Side) : Json :=
  Json.mkObj [
    ("alignSelf", s.alignSelf), ("alignItems", s.alignItems), ("display", s.display), ("position", s.position),
    ("localName", s.localName), ("html", s.html), ("aspectRatio", s.aspectRatio), ("writingMode", s.writingMode),
    ("parentDisplay", s.parentDisplay), ("parentWritingMode", s.parentWritingMode), ("autoMargin", s.autoMargin),
    ("heightAuto", s.heightAuto), ("alignContent", s.alignContent), ("rowStart", s.rowStart),
    ("rowEnd", s.rowEnd), ("rows", s.rows), ("rowGap", s.rowGap), ("boxSizing", s.boxSizing),
    ("height", s.height), ("paddingTop", s.paddingTop), ("paddingBottom", s.paddingBottom),
    ("borderTop", s.borderTop), ("borderBottom", s.borderBottom), ("marginTop", s.marginTop),
    ("marginBottom", s.marginBottom), ("parentBorderTop", s.parentBorderTop),
    ("parentPaddingTop", s.parentPaddingTop), ("rectTop", ratJson s.rectTop),
    ("rectHeight", ratJson s.rectHeight), ("parentRectTop", ratJson s.parentRectTop)]

/-- One golden line: the request (both arms' facts) and every intermediate answer. -/
def caseRow (n : String) (o r : Side) : Json :=
  Json.mkObj [
    ("name", n),
    ("request", Json.mkObj [("orig", sideJson o), ("rewrite", sideJson r)]),
    ("response", Json.mkObj [
      ("equiv", alignEquiv o r), ("spec", equivSpec o r),
      ("modeOrig", (modeOf o).name), ("modeRewrite", (modeOf r).name),
      ("eligibleOrig", eligible o), ("eligibleRewrite", eligible r),
      ("fillsOrig", contentFill o), ("fillsRewrite", contentFill r)])]

/-- The golden text, one JSON line per case. -/
def goldenText : String :=
  String.join (cases.map fun (n, o, r) => (caseRow n o r).compress ++ "\n")

/-- The golden file, relative to `lean/`. -/
def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "gate" / "align-equiv.jsonl"

/-- Writes the golden file, or compares it with the generated text and returns $\mathrm{fail} \in \{0, 1\}$ (1 when
the file differs).

$$\operatorname{run}(\mathit{root}, w) = \begin{cases} 0 \text{ after writing} & w \\ [\,\text{file} \ne \mathrm{goldenText}\,] & \neg w \end{cases}$$

Keeps the JavaScript mirror's vectors in step with the rule. -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / goldenPath
  if write then
    IO.FS.writeFile p goldenText
    IO.println s!"align-equiv golden: {cases.length} cases, written"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != goldenText then
    IO.println s!"align-equiv golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/AlignEquivGolden.lean)"
    return 1
  IO.println s!"align-equiv golden: {cases.length} cases, up to date"
  return 0

private def eqvOf (n : String) : Option Bool :=
  (cases.find? (·.1 == n)).map fun (_, o, r) => alignEquiv o r

#guard eqvOf "stage-stretch-vs-start-fills" == some true
#guard eqvOf "stage-start-does-not-fill" == some false
#guard eqvOf "auto-normal-ratio-vs-start" == some false
#guard eqvOf "auto-normal-ratio-auto-prefix" == some false
#guard eqvOf "normal-no-ratio-vs-start-fills" == some true
#guard eqvOf "normal-no-ratio-vs-start-short" == some false
#guard eqvOf "normal-degenerate-ratio" == some false
#guard eqvOf "normal-replaced-img" == some false
#guard eqvOf "normal-flex-display" == some false
#guard eqvOf "normal-svg-namespace" == some false
#guard eqvOf "flex-start-vs-start" == some true
#guard eqvOf "stretch-vs-normal-no-ratio" == some true
#guard eqvOf "start-fills-vs-stretch" == some true
#guard eqvOf "auto-margin" == some false
#guard eqvOf "height-declared" == some false
#guard eqvOf "baseline" == some false
#guard eqvOf "baseline-both-same" == some true
#guard eqvOf "center-vs-start" == some false
#guard eqvOf "vertical-writing-mode" == some false
#guard eqvOf "parent-vertical-writing-mode" == some false
#guard eqvOf "parent-flex" == some false
#guard eqvOf "parent-inline-grid" == some true
#guard eqvOf "absolute" == some false
#guard eqvOf "second-row" == some true
#guard eqvOf "ambiguous-zero-row" == some false
#guard eqvOf "span-two" == some false
#guard eqvOf "named-line-start" == some false
#guard eqvOf "line-number-start" == some true
#guard eqvOf "align-content-center" == some false
#guard eqvOf "scaled" == some false
#guard eqvOf "rows-none" == some false
#guard eqvOf "rows-line-names" == some true
#guard eqvOf "row-gap" == some true
#guard eqvOf "content-box-padding" == some true
#guard eqvOf "margins" == some true
#guard eqvOf "container-border-padding" == some true
#guard eqvOf "off-by-a-sixteenth" == some true
#guard eqvOf "off-by-an-eighth" == some false
#guard (cases.map (·.1)).Nodup
#guard parseTracks "[a b] 1px [c] 2.5px" == some [1, 5/2]
#guard ratioOf "640 / 512" == some true
#guard ratioOf "auto" == some false
#guard ratioOf "1.25" == none
#guard cases.all fun (_, o, r) => alignEquiv o r == alignEquiv r o

end Fw.Gate.AlignEquiv
