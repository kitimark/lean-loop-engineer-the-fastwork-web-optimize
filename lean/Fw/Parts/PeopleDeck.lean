import Fw.Engine.Chromium
import Fw.Engine.WebKit
import Fw.Engine.Visual
import Fw.Site.Breakpoints
import Fw.Parts.MorphMountOpt
import Fw.Parts.EndFlags
/-!
# people.deck, variant `cqi`: container-query units instead of `aspect-ratio` (PLAN rev 10)

**The part.** In the phone band (`mq.c860`, `2:3384`, the prettified v1 CSS
`site-pretty/_app/immutable/assets/2.gBuqKVzi.css`), the profile deck `.start-selling-profile-deck` is a horizontal
flex scroller with `box-sizing:border-box`, `width:calc(100% + 2b)`, `margin-inline:-b`, `padding-inline:b` and
bleed `b = 40px` (`36px` at `width<=640px`) (`2:3450-3467`, `2:3586-3592`). Each shell
`.start-selling-profile-shell` has `box-sizing:border-box`, `flex:0 0 100%`, `width:100%`, `height:auto` and
`aspect-ratio:353/764` (`2:3468-3496`). Outside the band the desktop rules (`2:3005-3031`, JS `--profile-scale`) apply
and the variant leaves them unchanged.

**The variant** (spec fixed here, Lean first): inside the same `c860` block the deck gets `container-type:inline-size`
and the shell gets `flex:0 0 100cqi`, `width:100cqi`, `height:calc(100cqi * 764 / 353)` and `aspect-ratio:auto`.

**Visual (E), all widths, by algebra.** The container's inline size is the deck's content box,
`(C + 2b) - 2b = C`, which is the shell's width in the original (`deck_content`). Hence `100cqi = C` and
`100cqi·764/353 = C·764/353`, the original's aspect-ratio height (`cqiShell_eq`), for every `C` and `b` in ℚ, and the
used shell size is equal in every environment (`usedShell_same`, `deck_vis`).

**Rounding premise (LayoutUnit).** Both engines store layout lengths as `LayoutUnit`, a fixed-point number with
6 fractional bits (1/64 px), and convert a floating value by truncation:
Chromium `B/platform/geometry/layout_unit.h:473` (`FixedPoint<6, int32_t>`), `:91`, `:127-130`@f842f52; WebKit
`WC/platform/LayoutUnit.h:63-64,83-86`@862f17d. Write `r` for the shell width in 1/64 px units. Chromium's original
height is `MulDiv` on raw integers (`B/core/layout/length_utils.cc:295-308`, `layout_unit.h:600-607`@f842f52), i.e.
exactly `⌊r·764/353⌋` (`crAspectRaw_eq`). WebKit's original divides in `double`
(`WC/rendering/RenderBoxInlines.h:309-314`@862f17d); both variants resolve `cqi` in `double`
(`B/core/css/css_length_resolver.cc:257-258`@f842f52, `WC/style/values/primitives/StyleLengthResolution.cpp:282-288`@862f17d).
`snap_faithful`: any computed value strictly within `1/353` raw unit of the exact one (and not below it when the exact value
is a whole raw unit) truncates to the same LayoutUnit; both bounds are strict. That is the open premise `Faithful`; it holds for exact
arithmetic (`snap_exact`) and for `double` (relative error ≈ 1e-16), and it can fail where a value passes through a
`float` (24-bit) `Length` (INFERRED, `B/platform/geometry/length.h:433`@f842f52) at heights ≥ 1024 px (an IEEE emulation found +1/64 px at integer widths 770, 1123 and
1187 px in Chromium's evaluation order). `snap_nudged` gives a variant formula that needs only an error bound:
`round(down, 100cqi * 764 / 353 + 1px / 45184, 1px / 64)`.

**Work.** The original runs an aspect-ratio relayout of the shells in some frames (the v1 toolbar step on a finger
in WebKit: largest layout 25.7 → 0.4 ms, MEASURED in v1, mechanism UNRESOLVED); the variant has no such pass. With the
lifted engine `lift ε` (the relayout dirties `layout` only), for every engine table and hence for ε ∈ {cr, wk}:
`deck_le` gives `W_ε(v,k) ⪯ W_ε(o,k)` in every frame, and `deck_lt` strict where the original relayouts and the
container width does not step. `lift_frameWork`: on plain changes the lifted engine is the engine itself.

**Premises (not axioms).** `Faithful` (above); the deck's scene is a function of the shells' used sizes (layout
inside the shell sees the same box); inline-size containment does not change the deck's width (its width
`calc(100% + 2b)` is definite, INFERRED) and style containment has no counters to scope (INFERRED); a container
width step makes the variant pay the same relayout (`widthStep`, INFERRED, `B/core/layout/block_node.cc:484-505`).
-/

namespace Fw.Parts.PeopleDeck

open Fw.Engine
open Fw.Site.Breakpoints

/-! ## Visual: exact algebra in ℚ -/

/-- The deck's content-box width: its border box `calc(100% + 2b)` minus its inline padding `2b`, for a containing
block of width `C` and bleed `b`.

$$\forall C, b \in \mathbb{Q}:\ \operatorname{deckContent}(C, b) = (C + 2b) - 2b$$

The width the shells and the container query see. -/
def deckContent (C b : Rat) : Rat := (C + 2 * b) - 2 * b

/-- The original phone shell's used border-box size: width `100%` (= `flex-basis 100%`) of the deck content box,
height from `aspect-ratio:353/764` applied to the border box.

$$\forall C, b \in \mathbb{Q}:\ \operatorname{origShell}(C, b) = \Big(\operatorname{deckContent}(C, b),\ \frac{\operatorname{deckContent}(C, b) \cdot 764}{353}\Big)$$

What the original lays out in exact arithmetic. -/
def origShell (C b : Rat) : Rat × Rat := (deckContent C b, deckContent C b * 764 / 353)

/-- One `cqi`: one hundredth of the deck's content-box inline size (the size container is the content box,
`B/core/layout/block_node.cc:484-505`@f842f52, `WC/style/values/primitives/StyleLengthResolution.cpp:282`@862f17d).

$$\forall C, b \in \mathbb{Q}:\ \operatorname{cqi}(C, b) = \frac{\operatorname{deckContent}(C, b)}{100}$$

The unit the variant's lengths use. -/
def cqi (C b : Rat) : Rat := deckContent C b / 100

/-- The variant phone shell's used size: `width:100cqi`, `height:calc(100cqi * 764 / 353)`.

$$\forall C, b \in \mathbb{Q}:\ \operatorname{cqiShell}(C, b) = \Big(100 \cdot \operatorname{cqi}(C, b),\ \frac{100 \cdot \operatorname{cqi}(C, b) \cdot 764}{353}\Big)$$

What the variant lays out in exact arithmetic. -/
def cqiShell (C b : Rat) : Rat × Rat := (100 * cqi C b, 100 * cqi C b * 764 / 353)

/-- The deck's content box is as wide as its containing block.

$$\forall C, b \in \mathbb{Q}:\ \operatorname{deckContent}(C, b) = C$$

The bleed adds and removes the same amount. -/
theorem deck_content (C b : Rat) : deckContent C b = C := by
  unfold deckContent; grind

/-- **Vis algebra.** The variant's shell size equals the original's, and both are `(C, C·764/353)`.

$$\forall C, b \in \mathbb{Q}:\ \operatorname{cqiShell}(C, b) = \operatorname{origShell}(C, b) \land \operatorname{origShell}(C, b) = \Big(C, \frac{C \cdot 764}{353}\Big)$$

`100cqi` is the shell width, so both lengths are equal for every width and bleed. -/
theorem cqiShell_eq (C b : Rat) : cqiShell C b = origShell C b ∧ origShell C b = (C, C * 764 / 353) := by
  have h : 100 * cqi C b = C := by unfold cqi; rw [deck_content]; grind
  refine ⟨?_, ?_⟩
  · unfold cqiShell origShell; rw [h, deck_content]
  · unfold origShell; rw [deck_content]

/-- The two arms of the A/B pair.

$$\mathrm{Arm} = \{\mathrm{orig}, \mathrm{cqi}\}$$

The original (`aspect-ratio`) and the variant (`cqi`). -/
inductive Arm where
  | orig
  | cqi
deriving Repr, DecidableEq

/-- The shell's used size in an environment: in the phone band `c860` the arm's phone rule, otherwise the shared
desktop size `desk` (the variant leaves the desktop rules unchanged).

$$\forall a \in \mathrm{Arm},\ \forall \mathit{desk} \in \mathbb{Q}^2,\ \forall e \in \mathrm{Env},\ \forall C, b \in \mathbb{Q}:\ \operatorname{usedShell}(a, \mathit{desk}, e, C, b) = \begin{cases} \operatorname{origShell}(C, b) & e \models \mathtt{c860},\ a = \mathrm{orig} \\ \operatorname{cqiShell}(C, b) & e \models \mathtt{c860},\ a = \mathrm{cqi} \\ \mathit{desk} & e \not\models \mathtt{c860} \end{cases}$$

Which rule sizes the shell. -/
def usedShell (a : Arm) (desk : Rat × Rat) (e : Env) (C b : Rat) : Rat × Rat :=
  if c860.eval e then (match a with | .orig => origShell C b | .cqi => cqiShell C b) else desk

#guard origShell 353 40 == (353, 764)
#guard cqiShell 353 36 == (353, 764)
#guard cqiShell 390 40 == origShell 390 40

/-- **Vis, every environment.** Both arms give the shell the same used size.

$$\forall \mathit{desk} \in \mathbb{Q}^2,\ \forall e \in \mathrm{Env},\ \forall C, b \in \mathbb{Q}:\ \operatorname{usedShell}(\mathrm{cqi}, \mathit{desk}, e, C, b) = \operatorname{usedShell}(\mathrm{orig}, \mathit{desk}, e, C, b)$$

Inside the band by `cqiShell_eq`, outside it because the desktop rule is shared. -/
theorem usedShell_same (desk : Rat × Rat) (e : Env) (C b : Rat) :
    usedShell .cqi desk e C b = usedShell .orig desk e C b := by
  unfold usedShell
  split
  · exact (cqiShell_eq C b).1
  · rfl

/-- **Vis (E).** For any scene builder that depends on the shells' used size (the premise: layout inside the shell
sees the same box), the original and the variant are `VisSame E` for every environment and instant.

$$\forall T,\ \forall \mathit{vp} : \mathrm{Env} \to \mathrm{Rect},\ \forall \mathit{desk} : \mathrm{Env} \to \mathbb{Q}^2,\ \forall C, b : \mathrm{Env} \to \mathbb{Q},\ \forall \mathit{scene} : \mathrm{Env} \to T \to \mathbb{Q}^2 \to \mathrm{Scene}:\ \operatorname{VisSame}_{\mathrm{E}}\Big(\mathit{vp},\ (e, t) \mapsto \mathit{scene}(e, t, \operatorname{usedShell}(\mathrm{orig}, \mathit{desk}(e), e, C(e), b(e))),\ (e, t) \mapsto \mathit{scene}(e, t, \operatorname{usedShell}(\mathrm{cqi}, \mathit{desk}(e), e, C(e), b(e)))\Big)$$

Same shell size gives the same picture. -/
theorem deck_vis {T : Type} (vp : Env → Rect) (desk : Env → Rat × Rat) (C b : Env → Rat)
    (scene : Env → T → Rat × Rat → Scene) :
    VisSame E vp (fun e t => scene e t (usedShell .orig (desk e) e (C e) (b e)))
      (fun e t => scene e t (usedShell .cqi (desk e) e (C e) (b e))) :=
  visSame_of_eq vp fun e t => by rw [usedShell_same]

/-! ## Rounding: LayoutUnit (1/64 px) snapping -/

/-- The exact aspect-ratio height in LayoutUnits for a shell width of `r` LayoutUnits, truncated (ℕ division).

$$\forall r \in \mathbb{N}:\ \operatorname{aspectRaw}(r) = \Big\lfloor \frac{764\, r}{353} \Big\rfloor$$

The height an exact engine stores. -/
def aspectRaw (r : Nat) : Nat := r * 764 / 353

/-- Chromium's original: `inline_size.MulDiv(764, 353)` on raw values, `(r · 764·64) / (353·64)` with integer
truncating division (`B/platform/geometry/layout_unit.h:600-607`@f842f52; the ratio 353/764 is exact in
LayoutUnits, `B/platform/geometry/physical_size.cc:37-44`).

$$\forall r \in \mathbb{N}:\ \operatorname{crAspectRaw}(r) = \Big\lfloor \frac{r \cdot (764 \cdot 64)}{353 \cdot 64} \Big\rfloor$$

What Chromium's border-box aspect-ratio branch stores. -/
def crAspectRaw (r : Nat) : Nat := r * (764 * 64) / (353 * 64)

/-- Chromium's original height is exact.

$$\forall r \in \mathbb{N}:\ \operatorname{crAspectRaw}(r) = \operatorname{aspectRaw}(r)$$

The common factor 64 cancels. -/
theorem crAspectRaw_eq (r : Nat) : crAspectRaw r = aspectRaw r := by
  unfold crAspectRaw aspectRaw
  rw [← Nat.mul_assoc, Nat.mul_div_mul_right _ _ (by decide)]

/-- LayoutUnit conversion of a length `x` px, modelled as `⌊64x⌋` raw units for every `x`. The engines truncate
toward zero, which equals the floor for `x ≥ 0`; `Faithful` implies `x ≥ 0` (`faithful_nonneg`).

$$\forall x \in \mathbb{Q}:\ \operatorname{snapRaw}(x) = \lfloor 64x \rfloor \in \mathbb{Z}$$

How a computed length becomes a layout length. -/
def snapRaw (x : Rat) : Int := (64 * x).floor

#guard aspectRaw 22592 == 48896
#guard crAspectRaw 22592 == 48896
#guard crAspectRaw 30528 == aspectRaw 30528
#guard snapRaw 764 == 48896
#guard snapRaw ((353 : Rat) * 764 / 353) == 48896
#guard snapRaw ((390 : Rat) * 764 / 353) == (aspectRaw (390 * 64) : Int)

/-- **The rounding premise.** A computed height `x` px is faithful to a shell width of `r` LayoutUnits when `64x`
lies strictly within `1/353` of the exact `764r/353`, and is not below it when `353 ∣ r` (the exact value is a whole
raw unit).

$$\forall r \in \mathbb{N},\ \forall x \in \mathbb{Q}:\ \operatorname{Faithful}(r, x) \iff \frac{764 r}{353} - \frac{1}{353} < 64x < \frac{764 r}{353} + \frac{1}{353} \land \Big(r \bmod 353 = 0 \Rightarrow \frac{764 r}{353} \le 64x\Big)$$

The engine's floating error stays below the gap to the next LayoutUnit boundary. -/
def Faithful (r : Nat) (x : Rat) : Prop :=
  (r : Rat) * 764 / 353 - 1 / 353 < 64 * x ∧ 64 * x < (r : Rat) * 764 / 353 + 1 / 353 ∧
    (r % 353 = 0 → (r : Rat) * 764 / 353 ≤ 64 * x)

/-- The floor of a rational is the integer it lies at or above and below the successor of.

$$\forall y \in \mathbb{Q},\ \forall q \in \mathbb{Z}:\ q \le y < q + 1 \Rightarrow \lfloor y \rfloor = q$$

Characterises the floor. -/
theorem floor_eq_of (y : Rat) (q : Int) (h1 : (q : Rat) ≤ y) (h2 : y < q + 1) : y.floor = q := by
  have := (Rat.le_floor_iff (x := q) (a := y)).2 h1
  have h3 : y.floor < q + 1 := by
    rw [Rat.floor_lt_iff]; push_cast; exact h2
  omega

/-- Division with remainder of `764r` by 353, in ℚ.

$$\forall r \in \mathbb{N}:\ \frac{764 r}{353} = \Big\lfloor \frac{764 r}{353} \Big\rfloor + \frac{764 r \bmod 353}{353}$$

The exact height is the stored part plus a fraction of a raw unit. -/
theorem split_div (r : Nat) :
    ((r : Rat) * 764 / 353) = ((r * 764 / 353 : Nat) : Rat) + ((r * 764 % 353 : Nat) : Rat) / 353 := by
  have h := Nat.div_add_mod (r * 764) 353
  have h' : ((r * 764 : Nat) : Rat) = ((353 * (r * 764 / 353) + r * 764 % 353 : Nat) : Rat) := by rw [h]
  push_cast at h'
  grind

/-- The fraction is zero exactly when 353 divides `r` (353 is prime and does not divide 764).

$$\forall r \in \mathbb{N}:\ 764 r \bmod 353 = 0 \iff r \bmod 353 = 0$$

Only widths that are multiples of 353 raw units give a whole-unit height. -/
theorem mod_zero_iff (r : Nat) : r * 764 % 353 = 0 ↔ r % 353 = 0 := by
  omega

/-- **Snap theorem.** A faithful computed height truncates to the exact LayoutUnit height.

$$\forall r \in \mathbb{N},\ \forall x \in \mathbb{Q}:\ \operatorname{Faithful}(r, x) \Rightarrow \lfloor 64x \rfloor = \Big\lfloor \frac{764 r}{353} \Big\rfloor$$

Within the premise, rounding cannot make the two arms differ. -/
theorem snap_faithful (r : Nat) (x : Rat) (h : Faithful r x) : snapRaw x = (aspectRaw r : Int) := by
  obtain ⟨hlo, hhi, hz⟩ := h
  unfold snapRaw aspectRaw
  have hs := split_div r
  have hmz := mod_zero_iff r
  have hm2 : r * 764 % 353 < 353 := Nat.mod_lt _ (by decide)
  generalize r * 764 / 353 = q at *
  generalize r * 764 % 353 = m at *
  have h2 : (m : Rat) ≤ 352 := by exact_mod_cast (by omega : m ≤ 352)
  apply floor_eq_of
  · rw [Rat.intCast_natCast]
    by_cases hm : m = 0
    · subst hm
      have := hz (hmz.1 rfl)
      simp at hs; grind
    · have h1 : (1 : Rat) ≤ m := by exact_mod_cast (by omega : 1 ≤ m)
      grind
  · rw [Rat.intCast_natCast]; grind

/-- A faithful height is non-negative, so LayoutUnit truncation is the floor.

$$\forall r \in \mathbb{N},\ \forall x \in \mathbb{Q}:\ \operatorname{Faithful}(r, x) \Rightarrow 0 \le x$$

The premise rules out the negative side where truncation and floor differ. -/
theorem faithful_nonneg (r : Nat) (x : Rat) (h : Faithful r x) : 0 ≤ x := by
  obtain ⟨hlo, _, hz⟩ := h
  have hs := split_div r
  by_cases hm : r * 764 % 353 = 0
  · have := hz ((mod_zero_iff r).1 hm)
    have : (0 : Rat) ≤ ((r * 764 / 353 : Nat) : Rat) := by exact_mod_cast Nat.zero_le _
    rw [hm] at hs; push_cast at hs; grind
  · have h1 : (1 : Rat) ≤ ((r * 764 % 353 : Nat) : Rat) := by
      have : 1 ≤ r * 764 % 353 := by omega
      exact_mod_cast this
    have : (0 : Rat) ≤ ((r * 764 / 353 : Nat) : Rat) := by exact_mod_cast Nat.zero_le _
    grind

/-- Exact arithmetic is faithful: the exact height `r·764/(353·64)` px satisfies the premise.

$$\forall r \in \mathbb{N}:\ \operatorname{Faithful}\Big(r, \frac{764 r}{353 \cdot 64}\Big)$$

With no floating error the premise holds for every width. -/
theorem faithful_exact (r : Nat) : Faithful r ((r : Rat) * 764 / 353 / 64) := by
  refine ⟨?_, ?_, fun _ => ?_⟩ <;> grind

/-- **Vis at LayoutUnit level, exact evaluation.** With exact arithmetic the variant's stored height equals
Chromium's original MulDiv height for every shell width.

$$\forall r \in \mathbb{N}:\ \Big\lfloor 64 \cdot \frac{764 r}{353 \cdot 64} \Big\rfloor = \operatorname{crAspectRaw}(r)$$

The algebra survives the 1/64 px grid when nothing is lost to floating point. -/
theorem snap_exact (r : Nat) : snapRaw ((r : Rat) * 764 / 353 / 64) = (crAspectRaw r : Int) := by
  rw [crAspectRaw_eq]; exact snap_faithful r _ (faithful_exact r)

/-- **Chromium, under the premise.** A faithful variant height stores the same LayoutUnit as the original's exact
MulDiv.

$$\forall r \in \mathbb{N},\ \forall x \in \mathbb{Q}:\ \operatorname{Faithful}(r, x) \Rightarrow \lfloor 64x \rfloor = \operatorname{crAspectRaw}(r)$$

Chromium's arms agree on the 1/64 px grid when the variant's `double`/`float` error is small. -/
theorem cr_snap_same (r : Nat) (x : Rat) (h : Faithful r x) : snapRaw x = (crAspectRaw r : Int) := by
  rw [crAspectRaw_eq]; exact snap_faithful r x h

/-- **WebKit, under the premise on both arms.** If the original's `double` quotient `xo` and the variant's
`cqi` height `xv` are both faithful, they store the same LayoutUnit.

$$\forall r \in \mathbb{N},\ \forall x_o, x_v \in \mathbb{Q}:\ \operatorname{Faithful}(r, x_o) \land \operatorname{Faithful}(r, x_v) \Rightarrow \lfloor 64 x_v \rfloor = \lfloor 64 x_o \rfloor$$

WebKit computes both arms in floating point, so both need the premise. -/
theorem wk_snap_same (r : Nat) (xo xv : Rat) (ho : Faithful r xo) (hv : Faithful r xv) :
    snapRaw xv = snapRaw xo := by
  rw [snap_faithful r xv hv, snap_faithful r xo ho]

/-- The nudged variant formula `round(down, y + 1px/45184, 1px/64)`, in raw units: `⌊64y + 1/706⌋`.

$$\forall y \in \mathbb{Q}:\ \operatorname{snapNudged}(y) = \Big\lfloor 64y + \frac{1}{706} \Big\rfloor$$

A half-gap nudge before rounding down to the 1/64 px grid. -/
def snapNudged (y : Rat) : Int := (64 * y + 1 / 706).floor

#guard snapNudged 764 == 48896
#guard snapNudged ((390 : Rat) * 764 / 353) == (aspectRaw (390 * 64) : Int)

/-- **Nudged snap.** With the nudge, an error bound alone suffices: a computed height within `1/706` raw unit of
the exact one (either side) rounds to the exact LayoutUnit.

$$\forall r \in \mathbb{N},\ \forall y \in \mathbb{Q}:\ \frac{764 r}{353} - \frac{1}{706} < 64y < \frac{764 r}{353} + \frac{1}{706} \Rightarrow \Big\lfloor 64y + \frac{1}{706} \Big\rfloor = \Big\lfloor \frac{764 r}{353} \Big\rfloor$$

The recommended variant formula is exact under a plain error bound, with no side condition at whole units. -/
theorem snap_nudged (r : Nat) (y : Rat) (hlo : (r : Rat) * 764 / 353 - 1 / 706 < 64 * y)
    (hhi : 64 * y < (r : Rat) * 764 / 353 + 1 / 706) : snapNudged y = (aspectRaw r : Int) := by
  unfold snapNudged aspectRaw
  have hs := split_div r
  have hm2 : r * 764 % 353 < 353 := Nat.mod_lt _ (by decide)
  generalize r * 764 / 353 = q at *
  generalize r * 764 % 353 = m at *
  have h2 : (m : Rat) ≤ 352 := by exact_mod_cast (by omega : m ≤ 352)
  have h0 : (0 : Rat) ≤ m := by exact_mod_cast Nat.zero_le m
  apply floor_eq_of
  · rw [Rat.intCast_natCast]; grind
  · rw [Rat.intCast_natCast]; grind

/-! ## Work: no aspect-ratio relayout pass -/

/-- A deck property: an engine property `base p`, or the shells' aspect-ratio relayout.

$$\mathrm{DeckProp}(P) = \{\mathrm{base}(p) \mid p \in P\} \cup \{\mathrm{ratioRelayout}\}$$

The engine's properties plus one. -/
inductive DeckProp (P : Type) where
  | base (p : P)
  | ratioRelayout
deriving Repr, DecidableEq

/-- An engine's change seen as a deck change.

$$\forall c \in \mathrm{Change}(P):\ \operatorname{liftC}(c) = (c.\mathrm{elem}, \mathrm{base}(c.\mathrm{prop}), c.\mathrm{layer})$$

Wraps the property, keeps element and layer. -/
def liftC {P : Type} (c : Change P) : Change (DeckProp P) := ⟨c.elem, .base c.prop, c.layer⟩

/-- **The lifted engine.** Plain changes keep the engine's stages; the aspect-ratio relayout dirties `layout` only
(same geometry, so no repaint: INFERRED).

$$\forall \varepsilon,\ \forall c \in \mathrm{Change}(\mathrm{DeckProp}\,P):\ \operatorname{stagesOf}_{\operatorname{lift}(\varepsilon)}(c) = \begin{cases} \operatorname{stagesOf}_{\varepsilon}(c.\mathrm{elem}, p, c.\mathrm{layer}) & c.\mathrm{prop} = \mathrm{base}(p) \\ [\mathrm{layout}] & c.\mathrm{prop} = \mathrm{ratioRelayout} \end{cases},\quad \text{mode, compStages, base as in } \varepsilon$$

The engine with one extra kind of change. -/
def lift {P M : Type} (ε : Engine P M) : Engine (DeckProp P) M where
  mode := ε.mode
  stagesOf c := match c.prop with
    | .base p => ε.stagesOf ⟨c.elem, p, c.layer⟩
    | .ratioRelayout => [.layout]
  compStages := ε.compStages
  base := ε.base

/-- A plain frame seen as a deck frame.

$$\forall f \in \mathrm{FrameIn}(P):\ \operatorname{liftF}(f) = f \text{ with changes } [\,\operatorname{liftC}(c)\,]_{c \in f.\mathrm{changes}}$$

Every change wrapped, the rest unchanged. -/
def liftF {P : Type} (f : FrameIn P) : FrameIn (DeckProp P) := { f with changes := f.changes.map liftC }

/-- The lifted engine is the engine on plain frames.

$$\forall \varepsilon,\ \forall f \in \mathrm{FrameIn}(P):\ \operatorname{frameWork}_{\operatorname{lift}(\varepsilon)}(\operatorname{liftF}(f)) = \operatorname{frameWork}_{\varepsilon}(f)$$

Lifting adds no work to frames without a relayout. -/
theorem lift_frameWork {P M : Type} (ε : Engine P M) (f : FrameIn P) :
    frameWork (lift ε) (liftF f) = frameWork ε f := by
  have hs : ∀ c : Change P, (lift ε).stagesOf (liftC c) = ε.stagesOf c := fun _ => rfl
  have ht : touched (lift ε) (liftF f) = touched ε f := by
    unfold touched liftF FrameIn.updates
    simp only [List.flatMap_map, hs, List.isEmpty_map]
    rfl
  have hu : ∀ s, stageUnits (lift ε) (liftF f) s = stageUnits ε f s := by
    intro s
    unfold stageUnits liftF
    simp only [List.countP_map, Function.comp_def, hs]
    rfl
  simp only [frameWork]
  rw [ht]
  congr 1
  · funext s; rw [hu]

/-- One relayout change per shell.

$$\forall S \in \mathbb{N}^{*}:\ \operatorname{relayouts}(S) = [\,(e, \mathrm{ratioRelayout}, \mathrm{none})\,]_{e \in S}$$

The original's extra pass, as changes. -/
def relayouts {P : Type} (shells : List Nat) : List (Change (DeckProp P)) :=
  shells.map fun e => ⟨e, .ratioRelayout, .none⟩

/-- A frame with extra changes appended.

$$\forall f \in \mathrm{FrameIn}(P),\ \forall X \in \mathrm{Change}(P)^{*}:\ \operatorname{withExtra}(f, X) = f \text{ with changes } f.\mathrm{changes} \mathbin{+\!\!+} X$$

The same frame plus more changes. -/
def withExtra {P : Type} (f : FrameIn P) (xs : List (Change P)) : FrameIn P := { f with changes := f.changes ++ xs }

/-- One deck frame: the work both arms share, whether the original runs its aspect-ratio relayout, and whether the
container's inline size steps (then the variant re-resolves `cqi` and relayouts too, INFERRED).

$$\mathrm{DeckFrame}(P) = \underbrace{\mathrm{FrameIn}(\mathrm{DeckProp}\,P)}_{\mathrm{base}} \times \underbrace{\mathbb{B}}_{\mathrm{relayout}} \times \underbrace{\mathbb{B}}_{\mathrm{widthStep}}$$
-/
structure DeckFrame (P : Type) where
  base : FrameIn (DeckProp P)
  relayout : Bool
  widthStep : Bool

/-- The original's frame: shared work plus the shells' relayout when it relayouts or the width steps.

$$\forall d \in \mathrm{DeckFrame}(P),\ \forall S \in \mathbb{N}^{*}:\ \operatorname{orig}(d, S) = d.\mathrm{base} \text{ with changes } d.\mathrm{base.changes} \mathbin{+\!\!+} \begin{cases} \operatorname{relayouts}(S) & d.\mathrm{relayout} \lor d.\mathrm{widthStep} \\ [\,] & \text{otherwise} \end{cases}$$

What the aspect-ratio arm runs (for `S = []` it is `d.base` with `[]` appended). -/
def DeckFrame.orig {P : Type} (d : DeckFrame P) (shells : List Nat) : FrameIn (DeckProp P) :=
  withExtra d.base (if d.relayout || d.widthStep then relayouts shells else [])

/-- The variant's frame: shared work plus the shells' relayout only when the width steps.

$$\forall d \in \mathrm{DeckFrame}(P),\ \forall S \in \mathbb{N}^{*}:\ \operatorname{cqiF}(d, S) = d.\mathrm{base} \text{ with changes } d.\mathrm{base.changes} \mathbin{+\!\!+} \begin{cases} \operatorname{relayouts}(S) & d.\mathrm{widthStep} \\ [\,] & \text{otherwise} \end{cases}$$

What the `cqi` arm runs. -/
def DeckFrame.cqiF {P : Type} (d : DeckFrame P) (shells : List Nat) : FrameIn (DeckProp P) :=
  withExtra d.base (if d.widthStep then relayouts shells else [])

/-- A change list covers itself.

$$\forall \varepsilon,\ \forall L \in \mathrm{Change}(P)^{*}:\ \operatorname{cover}_{\varepsilon}(L, L) = \mathrm{true}$$

Each change dirties the stages it dirties. -/
theorem coverB_self {P M : Type} (ε : Engine P M) : ∀ l : List (Change P), coverB ε l l = true
  | [] => rfl
  | c :: cs => by simp [coverB, coverB_self ε cs]

/-- Appending changes never lowers frame work.

$$\forall \varepsilon,\ \forall f \in \mathrm{FrameIn}(P),\ \forall X \in \mathrm{Change}(P)^{*}:\ \operatorname{frameWork}_{\varepsilon}(f) \preceq \operatorname{frameWork}_{\varepsilon}(f \text{ with changes } f.\mathrm{changes} \mathbin{+\!\!+} X)$$

More changes, at least as much work. -/
theorem frame_le_extra {P M : Type} (ε : Engine P M) (f : FrameIn P) (xs : List (Change P)) :
    (frameWork ε f).le (frameWork ε (withExtra f xs)) :=
  frame_le_of_cover ε f.changes xs (List.Perm.refl _) (coverB_self ε f.changes) (Nat.le_refl _) (Nat.le_refl _)
    (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _)

/-- Appending a non-empty list of layout-dirtying changes strictly raises frame work (the layout units).

$$\forall \varepsilon,\ \forall f \in \mathrm{FrameIn}(P),\ \forall X \in \mathrm{Change}(P)^{*}:\ X \ne [\,] \land (\forall c \in X:\ \mathrm{layout} \in \operatorname{stagesOf}_{\varepsilon}(c)) \Rightarrow \operatorname{frameWork}_{\varepsilon}(f) \prec \operatorname{frameWork}_{\varepsilon}(f \text{ with changes } f.\mathrm{changes} \mathbin{+\!\!+} X)$$

Each extra relayout is one more layout unit. -/
theorem frame_lt_extra {P M : Type} (ε : Engine P M) (f : FrameIn P) (xs : List (Change P)) (hne : xs ≠ [])
    (hl : ∀ c ∈ xs, Stage.layout ∈ ε.stagesOf c) :
    (frameWork ε f).lt (frameWork ε (withExtra f xs)) := by
  refine ⟨frame_le_extra ε f xs, Or.inl ⟨.layout, Or.inr ?_⟩⟩
  have hc : xs.countP (fun c => decide (Stage.layout ∈ ε.stagesOf c)) = xs.length :=
    List.countP_eq_length.2 (fun c hc => by simpa using hl c hc)
  have hpos : 0 < xs.length := List.length_pos_iff.2 hne
  simp only [frameWork, stageUnits, withExtra, List.countP_append, hc]
  omega

/-- **Work (⪯), every frame, every engine.** The variant's frame work is at most the original's.

$$\forall \varepsilon,\ \forall d \in \mathrm{DeckFrame}(P),\ \forall S \in \mathbb{N}^{*}:\ \operatorname{frameWork}_{\operatorname{lift}(\varepsilon)}(\operatorname{cqiF}(d, S)) \preceq \operatorname{frameWork}_{\operatorname{lift}(\varepsilon)}(\operatorname{orig}(d, S))$$

The variant never relayouts where the original does not. -/
theorem deck_le {P M : Type} (ε : Engine P M) (d : DeckFrame P) (shells : List Nat) :
    (frameWork (lift ε) (d.cqiF shells)).le (frameWork (lift ε) (d.orig shells)) := by
  unfold DeckFrame.cqiF DeckFrame.orig
  cases hw : d.widthStep
  · have h := frame_le_extra (lift ε) d.base (if d.relayout || false then relayouts shells else [])
    simpa [withExtra] using h
  · simp only [Bool.or_true, ite_true]
    exact Work.le_refl _

/-- **Work (≺), where the original relayouts.** With at least one shell, a relayout frame without a width step is
strictly cheaper in the variant.

$$\forall \varepsilon,\ \forall d \in \mathrm{DeckFrame}(P),\ \forall S \in \mathbb{N}^{*}:\ d.\mathrm{relayout} = \mathrm{true} \land d.\mathrm{widthStep} = \mathrm{false} \land S \ne [\,] \Rightarrow \operatorname{frameWork}_{\operatorname{lift}(\varepsilon)}(\operatorname{cqiF}(d, S)) \prec \operatorname{frameWork}_{\operatorname{lift}(\varepsilon)}(\operatorname{orig}(d, S))$$

The variant skips one layout unit per shell. -/
theorem deck_lt {P M : Type} (ε : Engine P M) (d : DeckFrame P) (shells : List Nat) (hr : d.relayout = true)
    (hw : d.widthStep = false) (hne : shells ≠ []) :
    (frameWork (lift ε) (d.cqiF shells)).lt (frameWork (lift ε) (d.orig shells)) := by
  unfold DeckFrame.cqiF DeckFrame.orig
  simp only [hr, hw, Bool.or_false, Bool.false_eq_true, ↓reduceIte]
  have hb : withExtra d.base ([] : List (Change (DeckProp P))) = d.base := by
    simp [withExtra]
  rw [hb]
  apply frame_lt_extra
  · simpa [relayouts] using hne
  · intro c hc
    simp only [relayouts, List.mem_map] at hc
    obtain ⟨e, _, rfl⟩ := hc
    simp [lift]

/-- The deck engine for Chromium.

$$\mathrm{crDeck} = \operatorname{lift}(\mathrm{chromium})$$

Chromium's table plus the relayout change. -/
def crDeck : Engine (DeckProp Chromium.CrProp) Chromium.CrMode := lift Chromium.chromium

/-- The deck engine for WebKit.

$$\mathrm{wkDeck} = \operatorname{lift}(\mathrm{webkit})$$

WebKit's table plus the relayout change. -/
def wkDeck : Engine (DeckProp WebKit.WkProp) WebKit.WkMode := lift WebKit.webkit

/-- **Chromium.** `W_cr(v,k) ⪯ W_cr(o,k)` in every frame, `≺` where the original relayouts without a width step.

$$\forall d \in \mathrm{DeckFrame}(\mathrm{CrProp}),\ \forall S \in \mathbb{N}^{*}:\ \operatorname{frameWork}_{\operatorname{lift}(\mathrm{chromium})}(\operatorname{cqiF}(d, S)) \preceq \operatorname{frameWork}_{\operatorname{lift}(\mathrm{chromium})}(\operatorname{orig}(d, S)) \land \big(d.\mathrm{relayout} = \mathrm{true} \land d.\mathrm{widthStep} = \mathrm{false} \land S \ne [\,] \Rightarrow \operatorname{frameWork}_{\operatorname{lift}(\mathrm{chromium})}(\operatorname{cqiF}(d, S)) \prec \operatorname{frameWork}_{\operatorname{lift}(\mathrm{chromium})}(\operatorname{orig}(d, S))\big)$$

On Chromium the variant never does more work, and does strictly less where the original relayouts. -/
theorem deck_cr (d : DeckFrame Chromium.CrProp) (shells : List Nat) :
    (frameWork crDeck (d.cqiF shells)).le (frameWork crDeck (d.orig shells)) ∧
      (d.relayout = true → d.widthStep = false → shells ≠ [] →
        (frameWork crDeck (d.cqiF shells)).lt (frameWork crDeck (d.orig shells))) :=
  ⟨deck_le _ d shells, fun hr hw hne => deck_lt _ d shells hr hw hne⟩

/-- **WebKit.** `W_wk(v,k) ⪯ W_wk(o,k)` in every frame, `≺` where the original relayouts without a width step.

$$\forall d \in \mathrm{DeckFrame}(\mathrm{WkProp}),\ \forall S \in \mathbb{N}^{*}:\ \operatorname{frameWork}_{\operatorname{lift}(\mathrm{webkit})}(\operatorname{cqiF}(d, S)) \preceq \operatorname{frameWork}_{\operatorname{lift}(\mathrm{webkit})}(\operatorname{orig}(d, S)) \land \big(d.\mathrm{relayout} = \mathrm{true} \land d.\mathrm{widthStep} = \mathrm{false} \land S \ne [\,] \Rightarrow \operatorname{frameWork}_{\operatorname{lift}(\mathrm{webkit})}(\operatorname{cqiF}(d, S)) \prec \operatorname{frameWork}_{\operatorname{lift}(\mathrm{webkit})}(\operatorname{orig}(d, S))\big)$$

On WebKit the variant never does more work, and does strictly less where the original relayouts. -/
theorem deck_wk (d : DeckFrame WebKit.WkProp) (shells : List Nat) :
    (frameWork wkDeck (d.cqiF shells)).le (frameWork wkDeck (d.orig shells)) ∧
      (d.relayout = true → d.widthStep = false → shells ≠ [] →
        (frameWork wkDeck (d.cqiF shells)).lt (frameWork wkDeck (d.orig shells))) :=
  ⟨deck_le _ d shells, fun hr hw hne => deck_lt _ d shells hr hw hne⟩

/-- Pointwise `⪯` on mapped lists gives `leAll`.

$$\forall g, h : \alpha \to \mathrm{Work},\ \forall L \in \alpha^{*}:\ (\forall x \in L:\ g(x) \preceq h(x)) \Rightarrow \operatorname{leAll}(\operatorname{map}(g, L), \operatorname{map}(h, L)) = \mathrm{true}$$

Frame-by-frame order lifts to runs. -/
theorem leAll_map {α : Type} (g h : α → Work) :
    ∀ (l : List α), (∀ x ∈ l, (g x).le (h x)) → leAll (l.map g) (l.map h) = true
  | [], _ => rfl
  | x :: xs, hx => by
    simp only [List.map_cons, leAll, Bool.and_eq_true]
    exact ⟨(Work.leb_iff _ _).2 (hx x (by simp)), leAll_map g h xs (fun y hy => hx y (by simp [hy]))⟩

/-- **Run dominance.** Over any run of deck frames with a relayout frame without a width step and at least one shell,
the screen says the variant dominates.

$$\forall \varepsilon,\ \forall D \in \mathrm{DeckFrame}(P)^{*},\ \forall S \in \mathbb{N}^{*}:\ S \ne [\,] \land (\exists d \in D:\ d.\mathrm{relayout} = \mathrm{true} \land d.\mathrm{widthStep} = \mathrm{false}) \Rightarrow \operatorname{screen}\big(\operatorname{toRun}([\operatorname{frameWork}_{\operatorname{lift}(\varepsilon)}(\operatorname{orig}(d, S))]_{d \in D}),\ \operatorname{toRun}([\operatorname{frameWork}_{\operatorname{lift}(\varepsilon)}(\operatorname{cqiF}(d, S))]_{d \in D})\big) = \mathrm{ok}(\mathrm{dominates})$$

A run with one relayout frame is dominated. -/
theorem deck_run_dominates {P M : Type} (ε : Engine P M) (ds : List (DeckFrame P)) (shells : List Nat)
    (hne : shells ≠ []) (hex : ∃ d ∈ ds, d.relayout = true ∧ d.widthStep = false) :
    Screen.screen (toRun (ds.map fun d => frameWork (lift ε) (d.orig shells)))
      (toRun (ds.map fun d => frameWork (lift ε) (d.cqiF shells))) = .ok .dominates := by
  apply run_dominates
  · exact leAll_map _ _ ds (fun d _ => deck_le ε d shells)
  · obtain ⟨d, hd, hr, hw⟩ := hex
    unfold someLt
    rw [List.any_eq_true]
    refine ⟨(frameWork (lift ε) (d.cqiF shells), frameWork (lift ε) (d.orig shells)), ?_, ?_⟩
    · rw [List.zip_map']
      exact List.mem_map.2 ⟨d, hd, rfl⟩
    · exact (Work.ltb_iff _ _).2 (deck_lt ε d shells hr hw hne)

/-- **Swipe lanes: equal.** In a run with no relayout and no width step (the CI swipe profiles have no toolbar
step), the arms' frames are equal.

$$\forall \varepsilon,\ \forall D \in \mathrm{DeckFrame}(P)^{*},\ \forall S \in \mathbb{N}^{*}:\ (\forall d \in D:\ d.\mathrm{relayout} = \mathrm{false} \land d.\mathrm{widthStep} = \mathrm{false}) \Rightarrow [\operatorname{frameWork}_{\operatorname{lift}(\varepsilon)}(\operatorname{cqiF}(d, S))]_{d \in D} = [\operatorname{frameWork}_{\operatorname{lift}(\varepsilon)}(\operatorname{orig}(d, S))]_{d \in D}$$

Hence every count is predicted `=o`. -/
theorem swipe_eq {P M : Type} (ε : Engine P M) (ds : List (DeckFrame P)) (shells : List Nat)
    (h : ∀ d ∈ ds, d.relayout = false ∧ d.widthStep = false) :
    (ds.map fun d => frameWork (lift ε) (d.cqiF shells)) = ds.map fun d => frameWork (lift ε) (d.orig shells) := by
  apply List.map_congr_left
  intro d hd
  obtain ⟨hr, hw⟩ := h d hd
  simp [DeckFrame.cqiF, DeckFrame.orig, hr, hw]

/-- Equal series predict `=0` or `=o` (`=0` is the stronger reading of the same equality).

$$\forall x \in \mathbb{B},\ \forall v \in \mathbb{N}^{*}:\ \operatorname{predict}(x, v, v) \in \{\texttt{=0}, \texttt{=o}\}$$

An equal pair is never `<o`, `≤o` or `any` (for `v = []` it is `=0`). -/
theorem predict_self (x : Bool) (v : List Nat) :
    MorphMountOpt.predict x v v = "=0" ∨ MorphMountOpt.predict x v v = "=o" := by
  unfold MorphMountOpt.predict
  split
  · exact Or.inl rfl
  · right; cases x <;> simp

/-! ## Golden rows -/

/-- One JSON row, keys sorted, prediction `=o` (by `swipe_eq` and `predict_self`).

$$\operatorname{row}(e, sc, t) = \{\mathrm{base} = \text{rewrite}, \mathrm{countType} = t.\mathrm{name}, \mathrm{engine} = e, \mathrm{prediction} = \texttt{=o}, \mathrm{scenario} = sc, \mathrm{stage} = \operatorname{stageName}(t.\mathrm{stage}), \mathrm{variant} = \text{rewrite+?fw=people.deck:cqi}\}$$

The variant flag is `?fw=people.deck:cqi`; the base is the faithful rewrite. -/
def row (engine scenario : String) (t : MorphMountOpt.CountType) : String :=
  "{\"base\":\"rewrite\",\"countType\":\"" ++ t.name ++ "\",\"engine\":\"" ++ engine ++
    "\",\"prediction\":\"=o\",\"scenario\":\"" ++ scenario ++ "\",\"stage\":\"" ++
    MorphMountOpt.stageName t.stage ++ "\",\"variant\":\"rewrite+?fw=people.deck:cqi\"}"

/-- All golden rows: Chromium on `swipe-v1` and `swipe-touch-v1`, WebKit on `swipe-v1`.

$$|\mathrm{goldenLines}| = 2 \cdot |\mathrm{crTypes}| + |\mathrm{wkTypes}| = 20$$

The file `packages/contracts/golden/engine/people-deck.jsonl`, line by line. -/
def goldenLines : List String :=
  (["swipe-v1", "swipe-touch-v1"].flatMap fun sc => MorphMountOpt.crTypes.map fun t => row "chromium" sc t) ++
    MorphMountOpt.wkTypes.map fun t => row "webkit" "swipe-v1" t

/-- The golden file text: one row per line, trailing newline.

$$\mathrm{goldenText} = \operatorname{concat}[\, \ell \mathbin{+\!\!+} \text{"\textbackslash n"} \,]_{\ell \in \mathrm{goldenLines}}$$

What the driver writes. -/
def goldenText : String := String.join (goldenLines.map (· ++ "\n"))

#guard goldenLines.length == 20
#guard goldenLines.head? == some
  "{\"base\":\"rewrite\",\"countType\":\"trace.FunctionCall\",\"engine\":\"chromium\",\"prediction\":\"=o\",\"scenario\":\"swipe-v1\",\"stage\":\"script\",\"variant\":\"rewrite+?fw=people.deck:cqi\"}"

/-! ## Examples: a relayout frame on both engines -/

/-- A relayout frame with no other work (example input).

$$\forall P:\ \operatorname{exFrame}(P) = \big((0, 0, 0, 0, [\,], 0),\ \mathrm{true},\ \mathrm{false}\big)$$

Empty shared work, relayout on, no width step. -/
def exFrame (P : Type) : DeckFrame P := ⟨⟨0, 0, 0, 0, [], 0⟩, true, false⟩

#guard (frameWork crDeck ((exFrame _).orig [1, 2])).units .layout == 2
#guard (frameWork crDeck ((exFrame _).cqiF [1, 2])).units .layout == 0
#guard (frameWork wkDeck ((exFrame _).orig [1, 2])).passes .commit == 1
#guard (frameWork wkDeck ((exFrame _).cqiF [1, 2])).passes .commit == 0
#guard (frameWork wkDeck ((exFrame _).cqiF [1, 2])).ltb (frameWork wkDeck ((exFrame _).orig [1, 2]))
#guard (frameWork crDeck ((exFrame _).cqiF [1, 2])).ltb (frameWork crDeck ((exFrame _).orig [1, 2]))

/-! ## Under the frame-end pass (`frameWorkE`, ledger n=1)

Both arms run the same shared frame and differ only in appended relayout changes, so they force the same passes.
Dropping a relayout cannot leave a stage dirtier at frame end (hypothesis `hm`), so both verdicts carry over
(`Fw.Parts.EndFlags.frameE_le_mono`, `Fw.Parts.EndFlags.frameE_lt_mono`); the strict layout-unit saving does not
depend on end flags. -/

section EndPass

open Fw.Parts.EndFlags

/-- **Work (⪯) under `frameWorkE`.** For end flags where the variant's stage is dirty only if the original's is, the
variant does no more work.

$$\forall \varepsilon, d, S,\ \forall e_v, e_o:\ \big(\forall s \in \operatorname{touched}_{\operatorname{lift}(\varepsilon)}(\operatorname{cqiF}(d, S)):\ e_v(s) = \top \Rightarrow e_o(s) = \top\big) \Rightarrow \operatorname{frameWork}^{e_v}_{\operatorname{lift}(\varepsilon)}(\operatorname{cqiF}(d, S)) \preceq \operatorname{frameWork}^{e_o}_{\operatorname{lift}(\varepsilon)}(\operatorname{orig}(d, S))$$

The frame-end pass does not undo the skipped relayout. -/
theorem deck_leE {P M : Type} (ε : Engine P M) (d : DeckFrame P) (shells : List Nat) (ev eo : Stage → Bool)
    (hm : ∀ s, s ∈ touched (lift ε) (d.cqiF shells) → ev s = true → eo s = true) :
    (frameWorkE (lift ε) (d.cqiF shells) ev).le (frameWorkE (lift ε) (d.orig shells) eo) :=
  frameE_le_mono _ ev eo (fun s => by cases s <;> rfl) (deck_le ε d shells) hm

/-- **Work (≺) under `frameWorkE`, where the original relayouts.**

$$\forall \varepsilon, d, S,\ \forall e_v, e_o:\ d.\mathrm{relayout} \land \lnot d.\mathrm{widthStep} \land S \ne [\,] \land \big(\forall s \in \operatorname{touched}_{\operatorname{lift}(\varepsilon)}(\operatorname{cqiF}(d, S)):\ e_v(s) = \top \Rightarrow e_o(s) = \top\big) \Rightarrow \operatorname{frameWork}^{e_v}_{\operatorname{lift}(\varepsilon)}(\operatorname{cqiF}(d, S)) \prec \operatorname{frameWork}^{e_o}_{\operatorname{lift}(\varepsilon)}(\operatorname{orig}(d, S))$$

One layout unit per shell is saved whatever the end flags say. -/
theorem deck_ltE {P M : Type} (ε : Engine P M) (d : DeckFrame P) (shells : List Nat) (hr : d.relayout = true)
    (hw : d.widthStep = false) (hne : shells ≠ []) (ev eo : Stage → Bool)
    (hm : ∀ s, s ∈ touched (lift ε) (d.cqiF shells) → ev s = true → eo s = true) :
    (frameWorkE (lift ε) (d.cqiF shells) ev).lt (frameWorkE (lift ε) (d.orig shells) eo) := by
  refine frameE_lt_mono _ ev eo (fun s => by cases s <;> rfl) (deck_le ε d shells) hm (Or.inl ⟨.layout, ?_⟩)
  have hc : (relayouts shells : List (Change (DeckProp P))).countP
      (fun c => decide (Stage.layout ∈ (lift ε).stagesOf c)) = shells.length := by
    rw [List.countP_eq_length.2 (fun c hc => ?_)]
    · simp [relayouts]
    · simp only [relayouts, List.mem_map] at hc
      obtain ⟨e, _, rfl⟩ := hc
      simp [lift]
  have hpos : 0 < shells.length := List.length_pos_iff.2 hne
  simp only [DeckFrame.cqiF, DeckFrame.orig, hr, hw, Bool.or_false, Bool.false_eq_true, ↓reduceIte, stageUnits,
    withExtra, List.countP_append, hc, List.countP_nil]
  omega

end EndPass

end Fw.Parts.PeopleDeck
