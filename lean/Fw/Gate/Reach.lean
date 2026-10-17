import Fw.Gate.Rule
import Fw.Site.BreakpointMatrix
/-!
# Which gate cells an engine port can reach (Q33)

A cell is `unreachable` on a port only by a fact proved or modelled from engine source here, never by
a runtime guess. Three facts, one `Reason` each:

* **primary hover/pointer pair** (`primaryPair`): WebKit derives `hover` and `pointer` from one value.
  Apple ports (iOS, iPadOS, visionOS: constant (none, coarse); macOS and Catalyst: constant (hover, fine);
  `Source/WebKit/WebProcess/WebPage/ios/WebPageIOS.mm:4201-4255`, `mac/WebPageMac.mm:762-780` @862f17d,
  CONFIRMED) give `{(hover, fine), (none, coarse)}`; GLib (GTK/WPE, Playwright WebKit on Linux CI) reads
  one primary pointing device (`glib/WebPageGLib.cpp:229-258` @862f17d, CONFIRMED) and adds (none, none)
  when there is none. Chromium reaches all six pairs (the gate's CDP emulation sets them independently).
* **whole media width** (`wholeWidth`): WebKit's media width is the `int` layout width, so it never lies
  strictly inside a gap `(N, N+1)` (`Px.whole_not_in_gap`, from `no_gap_ofNat`).
* **whole device pixels** (`widthDpr`): Chromium's media width is `P / dpr` with `P` whole physical px,
  so `width x dpr` must be whole (`Px.mulWhole_of_device_px`).

Research: `research/notes/2026/10-17-gate-gaps-hover-pointer.md`, `10-17-gate-gaps-fractional.md`.

Proved: the cross probes lie outside both WebKit pair sets and are exactly the matrix probes that do
(`matrix_outside_pairs_iff`), the fractional probes are unreachable on WebKit (`matrix_fractional_webkit`),
a WebKit port reaches every other probe (`matrix_webkit_unreachable_iff`), and Chromium reaches all 124
(`matrix_chromium_reachable`).
-/
namespace Fw.Gate

open Fw.Site.Breakpoints

/-- An engine port the gate runs on.

$$\mathcal P = \{\mathrm{chromium}, \mathrm{webkitApple}, \mathrm{webkitGLib}\}$$

Chromium, Apple WebKit (Safari, WKWebView, the iOS Simulator), or WebKit GTK/WPE (Playwright WebKit on
Linux). -/
inductive Port where
  | chromium
  | webkitApple
  | webkitGLib
  deriving DecidableEq, Repr, Inhabited

/-- The primary (hover, pointer) pairs a port can report.

$$\begin{aligned} \operatorname{pairs}(\mathrm{chromium}) &= \{\mathrm{none}, \mathrm{hover}\} \times \{\mathrm{none}, \mathrm{coarse}, \mathrm{fine}\} \\ \operatorname{pairs}(\mathrm{webkitApple}) &= [(\mathrm{hover}, \mathrm{fine}), (\mathrm{none}, \mathrm{coarse})] \\ \operatorname{pairs}(\mathrm{webkitGLib}) &= [(\mathrm{hover}, \mathrm{fine}), (\mathrm{none}, \mathrm{coarse}), (\mathrm{none}, \mathrm{none})] \end{aligned}$$

WebKit drives both features from one value; Chromium's emulation sets them apart. -/
def Port.pairs : Port → List (Hover × Pointer)
  | .chromium =>
    [(.none, .none), (.none, .coarse), (.none, .fine), (.hover, .none), (.hover, .coarse), (.hover, .fine)]
  | .webkitApple => [(.hover, .fine), (.none, .coarse)]
  | .webkitGLib => [(.hover, .fine), (.none, .coarse), (.none, .none)]

/-- Whether the port's media width is always a whole number of CSS px.

$$\operatorname{wholeWidth}(\mathrm{chromium}) = \bot,\quad \operatorname{wholeWidth}(\mathrm{webkitApple}) = \operatorname{wholeWidth}(\mathrm{webkitGLib}) = \top$$

WebKit compares queries against its integer layout width. -/
def Port.wholeWidth : Port → Bool
  | .chromium => false
  | .webkitApple | .webkitGLib => true

/-- Whether the port's media width times DPR is always a whole number (of physical px).

$$\operatorname{wholeDevPx}(\mathrm{chromium}) = \top,\quad \operatorname{wholeDevPx}(\mathrm{webkitApple}) = \operatorname{wholeDevPx}(\mathrm{webkitGLib}) = \bot$$

Chromium's media width is a whole number of physical px divided by the DPR (no claim for WebKit). -/
def Port.wholeDevPx : Port → Bool
  | .chromium => true
  | .webkitApple | .webkitGLib => false

/-- **The reach rule** (first match): the reason a requested environment is unreachable on a port,
or none. Inputs: whether its (hover, pointer) pair is a primary pair of the port ($a$), whether its
width is whole ($b$), whether width times DPR is whole ($c$).

$$\forall \pi \in \mathcal P,\ \forall a, b, c \in \mathbb B,\quad \operatorname{reason}_\pi(a, b, c) = \begin{cases} \mathrm{primaryPair} & \neg a \\ \mathrm{wholeWidth} & a \wedge \operatorname{wholeWidth}(\pi) \wedge \neg b \\ \mathrm{widthDpr} & a \wedge \neg(\operatorname{wholeWidth}(\pi) \wedge \neg b) \wedge \operatorname{wholeDevPx}(\pi) \wedge \neg c \\ \bot & \text{otherwise} \end{cases}$$

A cell is unreachable only for one of the three proved facts. -/
def Port.reason (pt : Port) (pairIn wWhole wdWhole : Bool) : Option Reason :=
  if !pairIn then some .primaryPair
  else if pt.wholeWidth && !wWhole then some .wholeWidth
  else if pt.wholeDevPx && !wdWhole then some .widthDpr
  else none

/-- The reach rule applied to a Lean environment.

$$\forall \pi \in \mathcal P,\ \forall e,\quad \operatorname{reach}_\pi(e) = \operatorname{reason}_\pi\bigl((\eta(e), \kappa(e)) \in \operatorname{pairs}(\pi),\ \mathrm{Whole}(w(e)),\ \mathrm{MulWhole}(w(e), r(e))\bigr)$$

Whether the port can produce this probe, and if not, why. -/
def envReason (pt : Port) (e : Env) : Option Reason :=
  pt.reason (pt.pairs.contains (e.hover, e.pointer)) (decide e.width.Whole)
    (decide (e.width.MulWhole e.dpr))

/-- A port reaches an environment exactly when all three tests pass.

$$\forall \pi, a, b, c,\quad \operatorname{reason}_\pi(a, b, c) = \bot \iff a \wedge (\operatorname{wholeWidth}(\pi) \Rightarrow b) \wedge (\operatorname{wholeDevPx}(\pi) \Rightarrow c)$$

No reason means the pair is primary and the port's width facts hold. -/
theorem Port.reason_eq_none_iff (π : Port) (a b c : Bool) :
    π.reason a b c = none ↔ a = true ∧ (π.wholeWidth = true → b = true) ∧
      (π.wholeDevPx = true → c = true) := by
  cases π <;> cases a <;> cases b <;> cases c <;> decide

/-- The GLib pairs are the Apple pairs plus (none, none).

$$\operatorname{pairs}(\mathrm{webkitGLib}) = \operatorname{pairs}(\mathrm{webkitApple}) \mathbin{+\!\!+} [(\mathrm{none}, \mathrm{none})]$$

Linux WebKit without a pointing device adds the pair (none, none). -/
theorem glib_pairs : Port.webkitGLib.pairs = Port.webkitApple.pairs ++ [(.none, .none)] := rfl

/-- The four cross probes, in matrix order: (none, fine) and (hover, coarse) at 1024x768 and
1200x900.

$$[\,(w(p), h(p), \eta(p), \kappa(p)) \mid p \in M_{\text{cross}}\,] = [(1024, 768, \mathrm{none}, \mathrm{fine}), (1024, 768, \mathrm{hover}, \mathrm{coarse}), (1200, 900, \mathrm{none}, \mathrm{fine}), (1200, 900, \mathrm{hover}, \mathrm{coarse})]$$

The cross block is exactly these four loads. -/
theorem matrix_cross_probes :
    (matrix.filter (·.block == .hoverPointerCross)).map (fun p => (p.env.width, p.env.height, p.env.hover, p.env.pointer)) =
      [(.ofNat 1024, .ofNat 768, .none, .fine), (.ofNat 1024, .ofNat 768, .hover, .coarse),
       (.ofNat 1200, .ofNat 900, .none, .fine), (.ofNat 1200, .ofNat 900, .hover, .coarse)] := by
  decide +kernel

/-- **The cross pairs exist on no WebKit.** Neither (none, fine) nor (hover, coarse) is a primary pair
of Apple or GLib WebKit.

$$\forall \pi \in \{\mathrm{webkitApple}, \mathrm{webkitGLib}\},\quad (\mathrm{none}, \mathrm{fine}) \notin \operatorname{pairs}(\pi) \wedge (\mathrm{hover}, \mathrm{coarse}) \notin \operatorname{pairs}(\pi)$$

Half a touch device is no WebKit's primary input. -/
theorem cross_pairs_not_webkit :
    ∀ π ∈ [Port.webkitApple, .webkitGLib], (Hover.none, Pointer.fine) ∉ π.pairs ∧ (Hover.hover, Pointer.coarse) ∉ π.pairs := by
  decide

/-- On both WebKit ports, a matrix probe's pair is outside the port's pairs exactly in the cross block.

$$\forall \pi \in \{\mathrm{webkitApple}, \mathrm{webkitGLib}\},\ \forall p \in M,\quad (\eta(p), \kappa(p)) \notin \operatorname{pairs}(\pi) \iff b(p) = \text{hover-pointer-cross}$$

The four cross loads, and only they, ask WebKit for an impossible input pair. -/
theorem matrix_outside_pairs_iff :
    ∀ pt ∈ [Port.webkitApple, .webkitGLib], ∀ p ∈ matrix,
      ((p.env.hover, p.env.pointer) ∉ pt.pairs ↔ p.block = .hoverPointerCross) := by
  decide +kernel

/-- **Whole widths have no gap.** For a whole-valued width, `(width<=Npx)` and `(width>=N+1px)` are
complementary, in any representation (`no_gap_ofNat` after cancelling the denominator).

$$\forall w \in \mathrm{Px},\ \forall N \in \mathbb N,\quad \mathrm{Whole}(w) \implies (w \le N \iff \neg(w \ge N + 1))$$

A port with whole media widths never shows a width that neither side of an edge claims. -/
theorem Px.whole_no_gap (w : Px) (hw : w.Whole) (N : Nat) : w.LeNat N ↔ ¬ w.GeNat (N + 1) := by
  have hd : w.den ∣ w.num := Nat.dvd_of_mod_eq_zero hw
  have e : w.num = w.num / w.den * w.den := (Nat.div_mul_cancel hd).symm
  have key := no_gap_ofNat N (w.num / w.den)
  simp only [Px.LeNat, Px.GeNat, Px.ofNat, Nat.mul_one] at key ⊢
  rw [e, Nat.mul_le_mul_right_iff w.den_pos, Nat.mul_le_mul_right_iff w.den_pos]
  exact key

/-- A whole width is never strictly inside a gap $(N, N+1)$.

$$\forall w \in \mathrm{Px},\ \forall N \in \mathbb N,\quad \mathrm{Whole}(w) \implies \neg(N < w < N + 1)$$

So the fractional-gap cells cannot be produced by a port whose media width is whole. -/
theorem Px.whole_not_in_gap (w : Px) (hw : w.Whole) (N : Nat) : ¬ (w.GtNat N ∧ ¬ w.GeNat (N + 1)) := by
  rintro ⟨hg, hn⟩
  have := (Px.whole_no_gap w hw N).mpr hn
  simp only [Px.LeNat, Px.GtNat] at this hg
  omega

/-- **The fractional probes are unreachable on WebKit**, for the whole-width reason, and each lies in a
gap that no whole width reaches.

$$\forall \pi \in \{\mathrm{webkitApple}, \mathrm{webkitGLib}\},\ \forall p \in M_{\text{frac}},\quad \operatorname{reach}_\pi(p) = \mathrm{wholeWidth} \wedge \exists N \in \{600, 640, 860, 1000\},\ N < w(p) < N + 1$$

WebKit cannot show a media width of $N + \tfrac12$. -/
theorem matrix_fractional_webkit :
    ∀ pt ∈ [Port.webkitApple, .webkitGLib], ∀ p ∈ matrix, p.block = .fractionalGaps →
      envReason pt p.env = some .wholeWidth ∧ ∃ N ∈ [600, 640, 860, 1000],
        p.env.width.GtNat N ∧ ¬ p.env.width.GeNat (N + 1) := by
  decide +kernel

/-- **The cross probes are unreachable on WebKit**, for the primary-pair reason.

$$\forall \pi \in \{\mathrm{webkitApple}, \mathrm{webkitGLib}\},\ \forall p \in M_{\text{cross}},\quad \operatorname{reach}_\pi(p) = \mathrm{primaryPair}$$

WebKit cannot report hover without a fine pointer, or a fine pointer without hover. -/
theorem matrix_cross_webkit :
    ∀ pt ∈ [Port.webkitApple, .webkitGLib], ∀ p ∈ matrix, p.block = .hoverPointerCross →
      envReason pt p.env = some .primaryPair := by
  decide +kernel

/-- On WebKit exactly the cross and fractional probes are unreachable.

$$\forall \pi \in \{\mathrm{webkitApple}, \mathrm{webkitGLib}\},\ \forall p \in M,\quad \operatorname{reach}_\pi(p) \ne \bot \iff b(p) \in \{\text{hover-pointer-cross}, \text{fractional-gaps}\}$$

The other 116 WebKit cells stay ordinary pass/fail/NC cells. -/
theorem matrix_webkit_unreachable_iff :
    ∀ pt ∈ [Port.webkitApple, .webkitGLib], ∀ p ∈ matrix,
      ((envReason pt p.env).isSome ↔ p.block = .hoverPointerCross ∨ p.block = .fractionalGaps) := by
  decide +kernel

/-- Chromium reaches every probe (it needs the DPR-2 fractional probes).

$$\forall p \in M,\quad \operatorname{reach}_{\mathrm{chromium}}(p) = \bot$$

No Chromium cell is unreachable. -/
theorem matrix_chromium_reachable : ∀ p ∈ matrix, envReason .chromium p.env = none := by
  decide +kernel

#guard Port.webkitApple.reason true true true == none
#guard Port.webkitApple.reason false false false == some .primaryPair
#guard Port.webkitGLib.reason true false true == some .wholeWidth
#guard Port.webkitApple.reason true true false == none
#guard Port.chromium.reason true false true == none
#guard Port.chromium.reason true true false == some .widthDpr
#guard Port.chromium.reason false true true == some .primaryPair
#guard envReason .webkitGLib { deskEnv (.ofNat 800) (.ofNat 600) (.ofNat 1) .noPreference with
  hover := .none, pointer := .none } == none
#guard envReason .webkitApple { deskEnv (.ofNat 800) (.ofNat 600) (.ofNat 1) .noPreference with
  hover := .none, pointer := .none } == some .primaryPair
#guard envReason .chromium (deskEnv (.half 600) (.ofNat 900) ⟨5, 4, by decide⟩ .noPreference) == some .widthDpr
#guard envReason .chromium (deskEnv (.half 600) (.ofNat 900) (.ofNat 2) .noPreference) == none
#guard envReason .webkitApple (deskEnv (.half 600) (.ofNat 900) (.ofNat 2) .noPreference) == some .wholeWidth
#guard (matrix.filter fun p => (envReason .webkitApple p.env).isSome).length == 8

end Fw.Gate
