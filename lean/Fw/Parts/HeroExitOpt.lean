import Fw.Parts.HeroExit
import Fw.Engine.Chromium
import Fw.Engine.WebKit
import Lean.Data.Json

/-!
# hero.exit, variant `hero-exit-threaded`: scroll-driven consumers (design note §4.2, row HE)

The original (`Fw.Parts.HeroExit`) runs one `requestAnimationFrame` callback per scrolled frame: it reads the track
rect, computes $e = \operatorname{exitOpacity}$ and writes the inherited custom property `--exit-opacity` on `.hero`;
every consumer (copy, scroll cue, cards) recomputes its `opacity`, `transform` and `filter: blur()` from it by
`calc()`. The variant drops the callback and gives each consumer its own CSS animation on a scroll timeline (a
`view-timeline` on `.hero-track`, range `contain`, linear easing, `fill: both`), with keyframes
$0\% = g(1)$ and $100\% = g(0)$ for the consumer's own value function $g$ of $e$:

* one animation of `opacity` + `transform` per consumer (copy; cue in the phone band; each card), and
* one separate animation of `filter: blur()` per blurred consumer (copy above 600 px; cue in both bands). Blur is
  split off because on Chromium a pixel-moving filter sets failure bit 12 and would drag the whole animation to the
  main thread (`merged_main`).

`pointer-events` is not a visual consumer: the variant flips it from an IntersectionObserver sentinel placed at the
threshold that `HeroExit.pointerOff_iff_threshold` proves (`sentinel_iff_pointerOff`); its delivery (one
observation step after the frame) is glue and is not proved here.

What is proved:
* **E-s** (`consumer_eq_s`): under the research-gap hypothesis RG11 (`RG11`: the engine's timeline progress at offset
  $y$ is the clamped linear progress of the CSS spec with start $T$ and length $\max(1, h - v)$), every consumer's
  animated value equals the original's `calc()` value at **every** scroll offset, in both width bands, for any
  settled entrance state. Core step: `progress_eq_js`, from `exitOpacity_linear`, `_before` and `_after`.
* **Work, Chromium** (`chromiumAt m`, threaded animation on): exact per-frame tables for a scrolled frame
  (`cr_orig_exact`, `cr_var_exact`). The script callback is gone; opacity and transform go to the compositor; blur
  stays on main (bit 12, `blur_main`). In real Chrome the main-thread work strictly drops (`cr_real_trade`); in the CI
  lane (every BeginFrame a main frame) the compositor animations' ride-along makes the props units one higher
  (`cr_lane_mixed`). Either way the compositor stage gains work: a **trade**, never "dominates".
* **Work, WebKit** (`webkitAt m`, threaded scroll-driven on): every animation, blur included, is accelerated
  (`wk_all_comp`; with the threaded path off, all run on main: `wk_legacy_main`); a scrolled frame keeps only the scroll commit on the web process (`wk_var_exact`), so the
  main-thread work strictly drops for **any** original change list (`wk_trade`), and the UI process gains the
  animations: again a trade.
* **Golden rows** (`goldenJsonl` → `packages/contracts/golden/engine/hero-exit.jsonl`) in the `engine-check` schema.

Not modelled (open): the frames where the opacity crosses 1 (WebKit `opacityCross1` lays out; only interior frames
$0 < e < 1$ are tabled), resident layers (the variant adds a composited layer per animated consumer, so the core
`claim` is a trade at best), units of the inherited restyle beyond one change per consumer (gap R2; this
undercounts the original only), and which scroll offset the compositor shows (path premise C3).

All values `Rat`; no `Float`.
-/
namespace Fw.Parts.HeroExitOpt

open Fw.Parts.HeroExit
open Fw.Engine

/-! ## Timeline progress (RG11) -/

/-- Clamp to the unit interval.

$$\operatorname{clamp01}(x) = \min(1, \max(0, x))$$

A value held between 0 and 1. -/
def clamp01 (x : Rat) : Rat := min 1 (max 0 x)

/-- Progress of a scroll timeline with start offset $S$ and length $L$ at scroll offset $y$, with `fill: both`
(CSS Scroll-driven Animations: progress = (offset − start) / (end − start), held at the end keyframes outside the
range).

$$\operatorname{progress}(S, L, y) = \min\!\Big(1, \max\!\Big(0, \frac{y - S}{L}\Big)\Big)$$

How far through its range a scroll-driven animation is at scroll offset $y$ (Lean division: $x / 0 = 0$). -/
def timelineProgress (S L y : Rat) : Rat := clamp01 ((y - S) / L)

/-- **Research gap RG11, carried as a hypothesis.** The engine's progress function `prog` (offset ↦ progress)
equals the spec formula with start $T$ (the offset where the track top meets the viewport top) and length
$\max(1, h - v)$ (the JS's `innerHeight`-based range). Whether `view-timeline` `contain` gives exactly these
numbers on each engine (scrollport vs `innerHeight`, dynamic toolbars) is RG11 itself.

$$\operatorname{RG11}(\mathit{prog}, T, h, v) \iff \forall y \in \mathbb{Q}:\ \mathit{prog}(y) = \operatorname{progress}\big(T, \max(1, h - v), y\big)$$

The engine's scroll-timeline progress is the spec's clamped linear progress over the original's exit range. -/
def RG11 (prog : Rat → Rat) (T h v : Rat) : Prop := ∀ y, prog y = timelineProgress T (exitRange h v) y

/-- Cancel a positive factor on the right.

$$\forall x, z, n \in \mathbb{Q}:\ n > 0 \land x = z \cdot n \Rightarrow \frac{x}{n} = z$$

Dividing a product by its positive factor gives the other factor back. -/
theorem div_eq_of_eq_mul (x z n : Rat) (hn : 0 < n) (h : x = z * n) : x / n = z := by
  have q := div_mul_pos x n hn
  have h0 : (x / n - z) * n = 0 := by grind
  rcases Rat.mul_eq_zero.mp h0 with h1 | h1
  · grind
  · grind

/-- **The spec progress over the original's range is one minus the JS exit opacity**, at every scroll offset: before
the range both give progress 0 (`exitOpacity_before`), after it both give 1 (`exitOpacity_after`), and inside it
the linear fade (`exitOpacity_linear`) is the timeline's linear progress.

$$\forall T, h, v, y \in \mathbb{Q}:\quad \operatorname{progress}\big(T, n, y\big) = 1 - \operatorname{exitOpacity}(T - y, h, v),\quad n = \max(1, h - v)$$

The scroll timeline and the original's JS compute the same fade at every scroll position. -/
theorem progress_eq_js (T h v y : Rat) :
    timelineProgress T (exitRange h v) y = 1 - exitOpacityAt T h v y := by
  have hn := exitRange_pos h v
  unfold timelineProgress clamp01 exitOpacityAt
  by_cases h1 : y ≤ T
  · have he := exitOpacity_before (T - y) h v (by grind)
    have hd := div_mono (y - T) 0 (exitRange h v) hn (by grind)
    have h0 : (0 : Rat) / exitRange h v = 0 := by grind
    rw [he]; grind
  · by_cases h2 : T + exitRange h v ≤ y
    · have he := exitOpacity_after (T - y) h v (by grind)
      have hd := div_mono (exitRange h v) (y - T) (exitRange h v) hn (by grind)
      have h1' : exitRange h v / exitRange h v = 1 := div_eq_of_eq_mul _ 1 _ hn (by grind)
      rw [he]; grind
    · have hl := exitOpacity_linear (T - y) h v (by grind) (by grind)
      have hm := exitOpacity_mem (T - y) h v
      have hq : (y - T) / exitRange h v = 1 - exitOpacity (T - y) h v :=
        div_eq_of_eq_mul _ _ _ hn (by grind)
      rw [hq]; grind

/-! ## Consumers and keyframes -/

/-- Linear interpolation between two keyframe values (the CSS rule for numbers, lengths and `blur()` radii with
linear easing).

$$\operatorname{lerp}(a, b, p) = a + (b - a)\,p$$

The value a two-keyframe linear animation shows at progress $p$. -/
def lerp (a b p : Rat) : Rat := a + (b - a) * p

/-- One animated consumer value of the hero exit, with the parameters that are constant while the user scrolls a
settled page: the copy's entrance amount $c$ (`--copy-in`), the band $\ell$ (`width<=600px`), and a card's entrance
state and offsets.

$$\mathrm{Consumer} = \{\mathrm{copyOpacity}(c), \mathrm{copyTranslateY}(c, \ell), \mathrm{copyBlur}(c, \ell), \mathrm{cueBlur}, \mathrm{cueTranslateY}(\ell), \mathrm{cardOpacity}, \mathrm{cardTranslate}(n, x_e, x_s) \mid c, n, x_e, x_s \in \mathbb{Q},\ \ell \in \mathbb{B}\}$$
-/
inductive Consumer where
  | copyOpacity (c : Rat)
  | copyTranslateY (c : Rat) (l : Bool)
  | copyBlur (c : Rat) (l : Bool)
  | cueBlur
  | cueTranslateY (l : Bool)
  | cardOpacity
  | cardTranslate (entered enter off : Rat)

/-- The original's value of a consumer as a function of the exit opacity $e$ (its `calc()`, restated in
`Fw.Parts.HeroExit`, with $s = 1 - e$).

$$\begin{aligned} g_{\mathrm{copyOpacity}(c)}(e) &= \operatorname{copyOpacity}(c, e) & g_{\mathrm{copyTranslateY}(c, \ell)}(e) &= \operatorname{copyTranslateYPx}(c, 1 - e, \ell) \\ g_{\mathrm{copyBlur}(c, \ell)}(e) &= \operatorname{copyBlurPx}(c, 1 - e, \ell) & g_{\mathrm{cueBlur}}(e) &= \operatorname{cueBlurPx}(1 - e) \\ g_{\mathrm{cueTranslateY}(\ell)}(e) &= \operatorname{cueTranslateYPx}(1 - e, \ell) & g_{\mathrm{cardOpacity}}(e) &= \operatorname{cardOpacity}(1 - e) \\ g_{\mathrm{cardTranslate}(n, x_e, x_s)}(e) &= \operatorname{cardTranslate}(n, x_e, 1 - e, x_s) \end{aligned}$$

What the original shows for each consumer at exit opacity $e$. -/
def Consumer.val : Consumer → Rat → Rat
  | .copyOpacity c, e => HeroExit.copyOpacity c e
  | .copyTranslateY c l, e => HeroExit.copyTranslateYPx c (exitScatter e) l
  | .copyBlur c l, e => HeroExit.copyBlurPx c (exitScatter e) l
  | .cueBlur, e => HeroExit.cueBlurPx (exitScatter e)
  | .cueTranslateY l, e => HeroExit.cueTranslateYPx (exitScatter e) l
  | .cardOpacity, e => HeroExit.cardOpacity (exitScatter e)
  | .cardTranslate n xe xs, e => HeroExit.cardTranslate n xe (exitScatter e) xs

/-- The variant's animation of a consumer: keyframe $0\%$ is the value at rest ($e = 1$), keyframe $100\%$ the value
fully exited ($e = 0$), linear easing.

$$\operatorname{anim}_k(p) = \operatorname{lerp}\big(g_k(1), g_k(0), p\big)$$

What the scroll-driven animation of consumer $k$ shows at progress $p$. -/
def Consumer.anim (k : Consumer) (p : Rat) : Rat := lerp (k.val 1) (k.val 0) p

/-- Every consumer is affine in the exit opacity.

$$\forall k \in \mathrm{Consumer},\ \forall e \in \mathbb{Q}:\quad g_k(e) = g_k(0) + \big(g_k(1) - g_k(0)\big)\, e$$

Each `calc()` the original evaluates is a straight line in $e$. -/
theorem val_affine (k : Consumer) (e : Rat) : k.val e = k.val 0 + (k.val 1 - k.val 0) * e := by
  cases k <;> simp only [Consumer.val, HeroExit.copyOpacity, HeroExit.copyTranslateYPx, HeroExit.copyBlurPx,
    HeroExit.cueBlurPx, HeroExit.cueTranslateYPx, HeroExit.cardOpacity, HeroExit.cardTranslate, exitScatter] <;>
    (try split) <;> grind

/-- The animation at progress $1 - e$ shows the original's value at exit opacity $e$.

$$\forall k \in \mathrm{Consumer},\ \forall e \in \mathbb{Q}:\quad \operatorname{anim}_k(1 - e) = g_k(e)$$

Two keyframes and a linear ramp reproduce any affine consumer exactly. -/
theorem anim_eq (k : Consumer) (e : Rat) : k.anim (1 - e) = k.val e := by
  have := val_affine k e
  unfold Consumer.anim lerp
  grind

/-- **E-s: every scroll-driven consumer equals the original at every scroll offset** (under RG11), in both width
bands and for any settled entrance state.

$$\forall k \in \mathrm{Consumer},\ \forall \mathit{prog} : \mathbb{Q} \to \mathbb{Q},\ \forall T, h, v \in \mathbb{Q}:\ \operatorname{RG11}(\mathit{prog}, T, h, v) \Rightarrow \forall y \in \mathbb{Q}:\ \operatorname{anim}_k\big(\mathit{prog}(y)\big) = g_k\big(\operatorname{exitOpacity}(T - y, h, v)\big)$$

The variant shows exactly the original's copy, cue and card values wherever the page is scrolled. -/
theorem consumer_eq_s (k : Consumer) (prog : Rat → Rat) (T h v : Rat) (hrg : RG11 prog T h v) (y : Rat) :
    k.anim (prog y) = k.val (exitOpacityAt T h v y) := by
  rw [hrg y, progress_eq_js]
  exact anim_eq k _

/-- Under reduced motion the variant attaches no animation (its rules sit in
`@media (prefers-reduced-motion: no-preference)`), so each consumer takes its rest value $g_k(1)$, which is what the
original's reduced-motion frame writes.

$$\forall k \in \mathrm{Consumer},\ \forall t, h, v \in \mathbb{Q}:\quad g_k\big(\operatorname{exitFrame}(\top, t, h, v).\mathrm{opacity}\big) = g_k(1) = \operatorname{anim}_k(0)$$

With reduced motion both variants show the hero at rest. -/
theorem reduced_eq (k : Consumer) (t h v : Rat) :
    k.val (exitFrame true t h v).opacity = k.val 1 ∧ k.val 1 = k.anim 0 := by
  refine ⟨rfl, ?_⟩
  unfold Consumer.anim lerp; grind

/-- The IntersectionObserver sentinel for `pointer-events`: it sits $\tfrac{19}{20}$ of the exit range below the
track top, and pointer events are off when it is strictly above the viewport top.

$$\operatorname{sentinelAbove}(T, h, v, y) \iff T + \tfrac{19}{20}\max(1, h - v) - y < 0$$

Whether the sentinel has scrolled past the top of the viewport. -/
def sentinelAbove (T h v y : Rat) : Bool := decide (T + 19 / 20 * exitRange h v - y < 0)

#guard sentinelAbove 0 1600 800 761 == true
#guard sentinelAbove 0 1600 800 760 == false

/-- The sentinel decides exactly the original's pointer cut-off (from `pointerOff_iff_threshold`).

$$\forall T, h, v, y \in \mathbb{Q}:\quad \operatorname{sentinelAbove}(T, h, v, y) \iff \operatorname{pointerOff}\big(\operatorname{exitOpacity}(T - y, h, v)\big)$$

The sentinel's position is the original's tap cut-off; only its delivery timing is left to the gate. -/
theorem sentinel_iff_pointerOff (T h v y : Rat) :
    sentinelAbove T h v y = true ↔ pointerOff (exitOpacityAt T h v y) = true := by
  rw [pointerOff_iff_threshold]
  unfold sentinelAbove
  simp only [decide_eq_true_eq]
  grind

/-! ## Main-thread order -/

/-- Work order on the main thread only: every stage except `comp` has no more passes and no more units, and no more
hit tests.

$$a \preceq_{\mathrm{main}} b \iff \big(\forall s \in \mathrm{Stage},\ s \ne \mathrm{comp}:\ a.\mathrm{passes}(s) \le b.\mathrm{passes}(s) \land a.\mathrm{units}(s) \le b.\mathrm{units}(s)\big) \land a.\mathrm{hits} \le b.\mathrm{hits}$$

One frame does no more main-thread work than another, ignoring the compositor. -/
def mainLe (a b : Work) : Prop :=
  (∀ s, s ≠ Stage.comp → a.passes s ≤ b.passes s ∧ a.units s ≤ b.units s) ∧ a.hits ≤ b.hits

/-- Strict main-thread order: $\preceq_{\mathrm{main}}$ plus one main-thread stage with strictly fewer passes or
units.

$$a \prec_{\mathrm{main}} b \iff a \preceq_{\mathrm{main}} b \land \exists s \in \mathrm{Stage},\ s \ne \mathrm{comp}:\ a.\mathrm{passes}(s) < b.\mathrm{passes}(s) \lor a.\mathrm{units}(s) < b.\mathrm{units}(s)$$

One frame does strictly less main-thread work than another. -/
def mainLt (a b : Work) : Prop :=
  mainLe a b ∧ ∃ s, s ≠ Stage.comp ∧ (a.passes s < b.passes s ∨ a.units s < b.units s)

/-- Main-thread order bounds the main-thread time under any unit costs (`toCost` reads only script, style, layout and
paint units).

$$\forall u \in \mathbb{N}^{3},\ \forall a, b \in \mathrm{Work}:\ a \preceq_{\mathrm{main}} b \Rightarrow \operatorname{mainUs}(u, \operatorname{toCost}(a)) \le \operatorname{mainUs}(u, \operatorname{toCost}(b))$$

Less main-thread work per stage never costs more main-thread time. -/
theorem mainLe_mainUs (u : Cost.UnitCost) {a b : Work} (h : mainLe a b) :
    Cost.mainUs u (toCost a) ≤ Cost.mainUs u (toCost b) :=
  Cost.mainUs_mono u ⟨(h.1 .script (by decide)).2, (h.1 .style (by decide)).2, (h.1 .layout (by decide)).2,
    (h.1 .paint (by decide)).2⟩

/-! ## Chromium -/

section Cr
open Fw.Engine.Chromium

/-- The custom property id of `--exit-opacity`.

$$\mathrm{exitVar} = 0$$
-/
def exitVar : Nat := 0

/-- The properties of the copy that read `--exit-opacity` (phone band: `filter: none`).

$$\operatorname{copyReaders}(\ell) = \begin{cases} [\mathrm{opacity}, \mathrm{transform}] & \ell \\ [\mathrm{opacity}, \mathrm{filter}(\mathrm{blur}), \mathrm{transform}] & \lnot\ell \end{cases}$$
-/
def copyReaders (l : Bool) : List CrKey :=
  if l then [.opacity, .transform] else [.opacity, .filter true, .transform]

/-- The properties of the scroll cue that read `--exit-opacity` (settled; its translate is constant above 600 px).

$$\operatorname{cueReaders}(\ell) = \begin{cases} [\mathrm{filter}(\mathrm{blur}), \mathrm{transform}] & \ell \\ [\mathrm{filter}(\mathrm{blur})] & \lnot\ell \end{cases}$$
-/
def cueReaders (l : Bool) : List CrKey := if l then [.filter true, .transform] else [.filter true]

/-- The root scroller's offset change in a scrolled frame ($r$: the scroll crosses a cull-rect repaint).

$$\operatorname{scrollC}(r) = (0, \mathrm{scroll}(r), \mathrm{own})$$
-/
def scrollC (r : Bool) : Change CrProp := ⟨0, .scroll r, .own⟩

/-- The original's style changes in one scrolled frame: `--exit-opacity` on `.hero` (element 1, read by nothing on
itself), then the inherited change on the copy (2), the cue (3) and the $N$ cards ($4 + i$), each at layer state
$\lambda$, then the scroll.

$$\operatorname{crOrigChanges}(\ell, N, \lambda, r) = [(1, \mathrm{custom}(0, [\,]), \lambda), (2, \mathrm{custom}(0, \operatorname{copyReaders}(\ell)), \lambda), (3, \mathrm{custom}(0, \operatorname{cueReaders}(\ell)), \lambda)] \mathbin{+\!\!+} [(4 + i, \mathrm{custom}(0, [\mathrm{opacity}, \mathrm{transform}]), \lambda) \mid i \in [0, N)] \mathbin{+\!\!+} [\operatorname{scrollC}(r)]$$
-/
def crOrigChanges (l : Bool) (N : Nat) (lo : LayerState) (r : Bool) : List (Change CrProp) :=
  [⟨1, .custom exitVar [], lo⟩, ⟨2, .custom exitVar (copyReaders l), lo⟩, ⟨3, .custom exitVar (cueReaders l), lo⟩] ++
    (List.range N).map (fun i => (⟨4 + i, .custom exitVar [.opacity, .transform], lo⟩ : Change CrProp)) ++
    [scrollC r]

/-- **The original's scrolled frame on Chromium**: one rAF callback that writes the custom property.

$$\operatorname{crOrig}(\ell, N, \lambda, r) = \operatorname{jsWrite}\big(1, \operatorname{crOrigChanges}(\ell, N, \lambda, r)\big)$$

What the original asks of Chromium in one scrolled frame. -/
def crOrig (l : Bool) (N : Nat) (lo : LayerState) (r : Bool) : FrameIn CrProp := jsWrite 1 (crOrigChanges l N lo r)

/-- A scroll-driven animation on a user-scrollable source, target on its own layer (`will-change`).

$$\operatorname{sAnim}(x, P) = (x, P, \mathrm{own}, \mathrm{true}, \mathrm{scroll}(\mathrm{true}))$$
-/
def sAnim (x : Nat) (ps : List CrProp) : CrAnim := ⟨x, ps, .own, true, .scroll true⟩

/-- **The variant's animations**: opacity + transform on the copy; transform on the cue (phone band only); a separate
blur on the copy (above 600 px only) and on the cue; opacity + transform on each card.

$$\operatorname{anims}(\ell, N) = [\operatorname{sAnim}(2, [\mathrm{opacity}, \mathrm{transform}])] \mathbin{+\!\!+} \begin{cases} [\operatorname{sAnim}(3, [\mathrm{transform}])] & \ell \\ [\operatorname{sAnim}(2, [\mathrm{filter}(\mathrm{blur})])] & \lnot\ell \end{cases} \mathbin{+\!\!+} [\operatorname{sAnim}(3, [\mathrm{filter}(\mathrm{blur})])] \mathbin{+\!\!+} [\operatorname{sAnim}(4 + i, [\mathrm{opacity}, \mathrm{transform}]) \mid i \in [0, N)]$$

The scroll-driven animations the variant declares. -/
def crAnims (l : Bool) (N : Nat) : List CrAnim :=
  [sAnim 2 [.css .opacity, .css .transform]] ++
    (if l then [sAnim 3 [.css .transform]] else [sAnim 2 [.css (.filter true)]]) ++
    [sAnim 3 [.css (.filter true)]] ++ (List.range N).map (fun i => sAnim (4 + i) [.css .opacity, .css .transform])

/-- **The variant's scrolled frame on Chromium** in mode $m$: the animation frame plus the scroll.

$$\operatorname{crVar}(m, \ell, N, r) = \operatorname{animFrame}(m, \operatorname{anims}(\ell, N)) \text{ with } \mathrm{changes} \mathbin{+\!\!+}= [\operatorname{scrollC}(r)]$$

What the variant asks of Chromium in one scrolled frame. -/
def crVar (m : CrMode) (l : Bool) (N : Nat) (r : Bool) : FrameIn CrProp :=
  let f := animFrame m (crAnims l N)
  { f with changes := f.changes ++ [scrollC r] }

/-- **Blur stays on main (bit 12).** A `filter: blur()` animation sets failure bit 12 and runs on the main thread in
every mode.

$$\forall m \in \mathrm{CrMode},\ \forall x \in \mathbb{N}:\ 12 \in \operatorname{bits}\big(m, \operatorname{sAnim}(x, [\mathrm{filter}(\mathrm{blur})])\big) \land \operatorname{crThread}\big(m, \operatorname{sAnim}(x, [\mathrm{filter}(\mathrm{blur})])\big) = \mathrm{main}$$

Chromium never composites a blur animation. -/
theorem blur_main (m : CrMode) (x : Nat) :
    12 ∈ failBits m (sAnim x [.css (.filter true)]) ∧ crThread m (sAnim x [.css (.filter true)]) = .main := by
  constructor
  · simp [failBits, sAnim, CrProp.movesPixels]
  · cases h : crThread m (sAnim x [.css (.filter true)])
    · rfl
    · have := ((crThread_comp_iff m _).mp h).2.2.2.1 (.css (.filter true)) (by simp [sAnim])
      simp [CrProp.movesPixels] at this

/-- **Opacity and transform go to the compositor.** With threaded animation on, the variant's opacity + transform and
transform-only scroll-driven animations run on the compositor.

$$\forall m \in \mathrm{CrMode},\ \forall x \in \mathbb{N}:\ m.\mathrm{threadedAnim} \Rightarrow \operatorname{crThread}\big(m, \operatorname{sAnim}(x, [\mathrm{opacity}, \mathrm{transform}])\big) = \mathrm{comp} \land \operatorname{crThread}\big(m, \operatorname{sAnim}(x, [\mathrm{transform}])\big) = \mathrm{comp}$$

The fade and the motion leave the main thread. -/
theorem opTr_comp (m : CrMode) (x : Nat) (hm : m.threadedAnim = true) :
    crThread m (sAnim x [.css .opacity, .css .transform]) = .comp ∧ crThread m (sAnim x [.css .transform]) = .comp := by
  constructor <;> simp [crThread, failBits, sAnim, hm, CrProp.movesPixels, CrProp.eligible]

/-- **Why the blur is split off.** One animation of opacity, blur and transform together would run on the main thread
(bit 12), taking the fade and the motion with it.

$$\forall m \in \mathrm{CrMode},\ \forall x \in \mathbb{N}:\ \operatorname{crThread}\big(m, \operatorname{sAnim}(x, [\mathrm{opacity}, \mathrm{filter}(\mathrm{blur}), \mathrm{transform}])\big) = \mathrm{main}$$

Merging the blur into the copy's animation would drag it all back to main. -/
theorem merged_main (m : CrMode) (x : Nat) :
    crThread m (sAnim x [.css .opacity, .css (.filter true), .css .transform]) = .main := by
  cases h : crThread m (sAnim x [.css .opacity, .css (.filter true), .css .transform])
  · rfl
  · have := ((crThread_comp_iff m _).mp h).2.2.2.1 (.css (.filter true)) (by simp [sAnim])
    simp [CrProp.movesPixels] at this

/-- The variant's frame, computed: the blur animations' changes on main (one per blurred consumer), the scroll, and
$N + 1 + [\ell]$ compositor animations.

$$\forall m, \ell, N, r:\ m.\mathrm{threadedAnim} \Rightarrow \operatorname{crVar}(m, \ell, N, r) = \Big(0, 0, 0, 0,\ \Big(\begin{cases} [\,] & \ell \\ [(2, \mathrm{filter}(\mathrm{blur}), \mathrm{own})] & \lnot\ell \end{cases}\Big) \mathbin{+\!\!+} [(3, \mathrm{filter}(\mathrm{blur}), \mathrm{own}), \operatorname{scrollC}(r)],\ N + \begin{cases} 2 & \ell \\ 1 & \lnot\ell \end{cases}\Big)$$

What the variant's frame consists of once the thread rule has run. -/
theorem crVar_eq (m : CrMode) (l : Bool) (N : Nat) (r : Bool) (hm : m.threadedAnim = true) :
    crVar m l N r = ⟨0, 0, 0, 0, (if l then [] else [⟨2, .css (.filter true), .own⟩]) ++
      [⟨3, .css (.filter true), .own⟩, scrollC r], N + (if l then 2 else 1)⟩ := by
  have hb := fun x => (blur_main m x).2
  have hc := fun x => (opTr_comp m x hm)
  have hcards : ∀ a ∈ (List.range N).map (fun i => sAnim (4 + i) [.css .opacity, .css .transform]),
      crThread m a = .comp := by
    intro a ha
    simp only [List.mem_map] at ha
    obtain ⟨i, _, rfl⟩ := ha
    exact (hc _).1
  have hf1 : ((List.range N).map (fun i => sAnim (4 + i) [.css .opacity, .css .transform])).filter
      (fun a => decide (crThread m a = .main)) = [] := by
    rw [List.filter_eq_nil_iff]; intro a ha; simp [hcards a ha]
  have hf2 : ((List.range N).map (fun i => sAnim (4 + i) [.css .opacity, .css .transform])).filter
      (fun a => decide (crThread m a = .comp)) =
      (List.range N).map (fun i => sAnim (4 + i) [.css .opacity, .css .transform]) := by
    rw [List.filter_eq_self]; intro a ha; simp [hcards a ha]
  cases l <;>
    simp [crVar, animFrame, crAnims, hf1, hf2, hb, (hc _).1, (hc _).2, CrAnim.changes] <;>
    rfl

/-- The original's passes per stage in a scrolled frame ($\lambda$: the consumers' layer state, $r$: a cull-rect
repaint).

$$\operatorname{oP}(\lambda, r)(s) = \begin{cases} 1 & s \in \{\mathrm{script}, \mathrm{style}, \mathrm{props}, \mathrm{commit}\} \\ [r] & s = \mathrm{paint} \\ [\lambda \ne \mathrm{own} \lor r] & s = \mathrm{raster} \\ 0 & s \in \{\mathrm{layout}, \mathrm{comp}\} \end{cases}$$
-/
def crOrigPasses (lo : LayerState) (r : Bool) : Stage → Nat
  | .script => 1 | .style => 1 | .layout => 0 | .props => 1
  | .paint => if r then 1 else 0
  | .raster => if lo ≠ .own ∨ r = true then 1 else 0
  | .commit => 1 | .comp => 0

/-- The original's units per stage in a scrolled frame with $N$ cards.

$$\operatorname{oU}(N, \lambda, r)(s) = \begin{cases} 1 & s = \mathrm{script} \\ N + 3 & s \in \{\mathrm{style}, \mathrm{props}, \mathrm{commit}\} \\ [r] & s = \mathrm{paint} \\ [\lambda \ne \mathrm{own}]\,(N + 2) + [r] & s = \mathrm{raster} \\ 0 & s \in \{\mathrm{layout}, \mathrm{comp}\} \end{cases}$$
-/
def crOrigUnits (N : Nat) (lo : LayerState) (r : Bool) : Stage → Nat
  | .script => 1 | .style => N + 3 | .layout => 0 | .props => N + 3
  | .paint => if r then 1 else 0
  | .raster => (if lo = .own then 0 else N + 2) + (if r then 1 else 0)
  | .commit => N + 3 | .comp => 0

/-- The stages a reader of `--exit-opacity` dirties at layer state $\lambda$: its own layer takes the property-tree
fast path, any other layer state re-rasters.

$$\operatorname{readerStages}(\lambda) = \begin{cases} [\mathrm{style}, \mathrm{props}, \mathrm{commit}] & \lambda = \mathrm{own} \\ [\mathrm{style}, \mathrm{props}, \mathrm{raster}, \mathrm{commit}] & \lambda \ne \mathrm{own} \end{cases}$$
-/
def readerStages (lo : LayerState) : List Stage :=
  if lo = .own then [.style, .props, .commit] else [.style, .props, .raster, .commit]

/-- Every consumer of the original dirties exactly the reader stages, in both bands.

$$\forall x \in \mathbb{N},\ \forall K, \lambda, \ell:\ K \in \{\operatorname{copyReaders}(\ell), \operatorname{cueReaders}(\ell), [\mathrm{opacity}, \mathrm{transform}]\} \Rightarrow \operatorname{stagesOf}_{\mathrm{cr}}\big(x, \mathrm{custom}(0, K), \lambda\big) = \operatorname{readerStages}(\lambda)$$

Copy, cue and cards all cost the same stages per frame. -/
theorem reader_stages (x : Nat) (ks : List CrKey) (lo : LayerState) (l : Bool)
    (hk : ks = copyReaders l ∨ ks = cueReaders l ∨ ks = [.opacity, .transform]) :
    crStagesOf ⟨x, .custom exitVar ks, lo⟩ = readerStages lo := by
  rcases hk with rfl | rfl | rfl <;> cases l <;> cases lo <;> rfl

/-- **Exact work of the original's scrolled frame on Chromium**, in every mode and both bands: one callback, one
style pass over the hero and its $N + 2$ readers, a property update and commit for the readers and the scroll, and a
raster of every reader unless it has its own layer.

$$\forall m, \ell, N, \lambda, r,\ \forall s \in \mathrm{Stage}:\ W.\mathrm{passes}(s) = \operatorname{oP}(\lambda, r)(s) \land W.\mathrm{units}(s) = \operatorname{oU}(N, \lambda, r)(s)\quad\text{where } W = \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}\big(\operatorname{crOrig}(\ell, N, \lambda, r)\big)$$

What one scrolled frame of the original costs Chromium, stage by stage. -/
theorem cr_orig_exact (m : CrMode) (l : Bool) (N : Nat) (lo : LayerState) (r : Bool) (s : Stage) :
    (frameWork (chromiumAt m) (crOrig l N lo r)).passes s = crOrigPasses lo r s ∧
      (frameWork (chromiumAt m) (crOrig l N lo r)).units s = crOrigUnits N lo r s := by
  have hc : ∀ i, crStagesOf ⟨4 + i, .custom exitVar [.opacity, .transform], lo⟩ = readerStages lo :=
    fun i => reader_stages _ _ lo l (by simp)
  have h2 := reader_stages 2 (copyReaders l) lo l (by simp)
  have h3 := reader_stages 3 (cueReaders l) lo l (by simp)
  have h1 : crStagesOf ⟨1, .custom exitVar [], lo⟩ = [.style] := by cases lo <;> rfl
  have hs : crStagesOf (scrollC r) = scrollStages r := rfl
  have hm : ∀ t, t ∈ ((List.range N).map fun i =>
      (⟨4 + i, .custom exitVar [.opacity, .transform], lo⟩ : Change CrProp)).flatMap crStagesOf →
      t ∈ readerStages lo := by
    intro t ht
    simp only [List.mem_flatMap, List.mem_map] at ht
    obtain ⟨_, ⟨i, _, rfl⟩, h⟩ := ht
    rwa [hc i] at h
  have hp : (frameWork (chromiumAt m) (crOrig l N lo r)).passes s =
      if s ∈ (crOrigChanges l N lo r).flatMap crStagesOf ++ [.script] then 1 else 0 := by
    simp [frameWork, touched, crOrig, jsWrite, FrameIn.updates, chromiumAt]
    cases s <;> simp [forcedPasses]
  have hu : (frameWork (chromiumAt m) (crOrig l N lo r)).units s =
      (crOrigChanges l N lo r).countP (fun c => decide (s ∈ crStagesOf c)) + (if s = .script then 1 else 0) := by
    simp [frameWork, stageUnits, crOrig, jsWrite, chromiumAt]
    by_cases h : s ∈ crCompStages m <;> simp [h] <;> first | rfl | congr
  have hmem : s ∈ (crOrigChanges l N lo r).flatMap crStagesOf ++ [.script] ↔
      (s = .style ∨ s ∈ readerStages lo ∨ s ∈ scrollStages r ∨ s = .script) := by
    have := hm s
    simp only [crOrigChanges, List.flatMap_append, List.flatMap_cons, List.flatMap_nil, List.mem_append,
      List.mem_cons, List.mem_nil_iff, h1, h2, h3, hs, or_false, List.append_nil]
    grind
  rw [hp, hu]
  simp only [hmem]
  simp only [crOrigChanges, List.countP_append, List.countP_cons, List.countP_nil, List.countP_map,
    Function.comp_def, h1, h2, h3, hc, hs]
  clear hp hu hmem hm hc h1 h2 h3 hs
  cases lo <;> cases r <;> cases s <;>
    simp [readerStages, scrollStages, crOrigPasses, crOrigUnits] <;> omega

/-- The variant's passes per stage in a scrolled frame.

$$\operatorname{vP}(r)(s) = \begin{cases} 1 & s \in \{\mathrm{style}, \mathrm{props}, \mathrm{commit}, \mathrm{comp}\} \\ [r] & s \in \{\mathrm{paint}, \mathrm{raster}\} \\ 0 & s \in \{\mathrm{script}, \mathrm{layout}\} \end{cases}$$
-/
def crVarPasses (r : Bool) : Stage → Nat
  | .script => 0 | .style => 1 | .layout => 0 | .props => 1
  | .paint => if r then 1 else 0
  | .raster => if r then 1 else 0
  | .commit => 1 | .comp => 1

/-- The variant's units per stage in a scrolled frame, with $b = 1 + [\lnot\ell]$ blur animations on main,
$c = N + 1 + [\ell]$ compositor animations, and the ride-along $\varepsilon = [m.\mathrm{everyBeginFrameIsMainFrame}]\,c$.

$$\operatorname{vU}(m, \ell, N, r)(s) = \begin{cases} b + \varepsilon & s = \mathrm{style} \\ b + 1 + \varepsilon & s = \mathrm{props} \\ [r] & s \in \{\mathrm{paint}, \mathrm{raster}\} \\ b + 1 & s = \mathrm{commit} \\ c & s = \mathrm{comp} \\ 0 & s \in \{\mathrm{script}, \mathrm{layout}\} \end{cases}$$
-/
def crVarUnits (m : CrMode) (l : Bool) (N : Nat) (r : Bool) : Stage → Nat :=
  let b := if l then 1 else 2
  let c := N + (if l then 2 else 1)
  let e := if m.everyBeginFrameIsMainFrame then c else 0
  fun
  | .script => 0 | .style => b + e | .layout => 0 | .props => b + 1 + e
  | .paint => if r then 1 else 0
  | .raster => if r then 1 else 0
  | .commit => b + 1 | .comp => c

/-- **Exact work of the variant's scrolled frame on Chromium** (threaded animation on): no script; the blur animations
alone restyle, update properties and commit on main; opacity and transform tick on the compositor; in a mode where
every BeginFrame is a main frame, each compositor animation adds a ride-along style and property unit.

$$\forall m, \ell, N, r:\ m.\mathrm{threadedAnim} \Rightarrow \forall s \in \mathrm{Stage}:\ W.\mathrm{passes}(s) = \operatorname{vP}(r)(s) \land W.\mathrm{units}(s) = \operatorname{vU}(m, \ell, N, r)(s)\quad\text{where } W = \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}\big(\operatorname{crVar}(m, \ell, N, r)\big)$$

What one scrolled frame of the variant costs Chromium, stage by stage. -/
theorem cr_var_exact (m : CrMode) (l : Bool) (N : Nat) (r : Bool) (hm : m.threadedAnim = true) (s : Stage) :
    (frameWork (chromiumAt m) (crVar m l N r)).passes s = crVarPasses r s ∧
      (frameWork (chromiumAt m) (crVar m l N r)).units s = crVarUnits m l N r s := by
  rw [crVar_eq m l N r hm]
  cases l <;> cases r <;> cases he : m.everyBeginFrameIsMainFrame <;> cases s <;>
    simp [frameWork, touched, stageUnits, forcedPasses, FrameIn.updates, chromiumAt, crStagesOf, crLevel, keyLevel,
      CrLevel.stages, CrProp.extra, scrollStages, scrollC, crCompStages, crVarPasses, crVarUnits, he] <;> omega

/-- **Real Chrome: a trade.** With the main thread asleep between compositor frames, the variant's scrolled frame does
strictly less main-thread work than the original's (no script; fewer style, property, raster and commit units), but it
adds a compositor pass the original does not have. So the variant does not dominate; it moves work to the compositor.

$$\forall \ell, N, \lambda, r:\ V \prec_{\mathrm{main}} O \ \land\ V.\mathrm{passes}(\mathrm{comp}) = 1 > 0 = O.\mathrm{passes}(\mathrm{comp})\quad\text{where } V = \operatorname{frameWork}_{\operatorname{chromiumAt}(\mathrm{realChrome})}\big(\operatorname{crVar}(\mathrm{realChrome}, \ell, N, r)\big),\ O = \operatorname{frameWork}_{\operatorname{chromiumAt}(\mathrm{realChrome})}\big(\operatorname{crOrig}(\ell, N, \lambda, r)\big)$$

In real Chrome the variant is cheaper on the main thread and pays for it on the compositor. -/
theorem cr_real_trade (l : Bool) (N : Nat) (lo : LayerState) (r : Bool) :
    mainLt (frameWork (chromiumAt realChrome) (crVar realChrome l N r))
      (frameWork (chromiumAt realChrome) (crOrig l N lo r)) ∧
    (frameWork (chromiumAt realChrome) (crVar realChrome l N r)).passes .comp = 1 ∧
    (frameWork (chromiumAt realChrome) (crOrig l N lo r)).passes .comp = 0 := by
  have hv := cr_var_exact realChrome l N r rfl
  have ho := cr_orig_exact realChrome l N lo r
  refine ⟨⟨⟨fun s hs => ?_, ?_⟩, .script, by decide, ?_⟩, (hv .comp).1, (ho .comp).1⟩
  · rw [(hv s).1, (hv s).2, (ho s).1, (ho s).2]
    cases l <;> cases lo <;> cases r <;> cases s <;>
      simp_all [crVarPasses, crVarUnits, crOrigPasses, crOrigUnits, realChrome] <;> omega
  · simp [frameWork, crVar, crOrig, animFrame, jsWrite]
  · left; rw [(hv .script).1, (ho .script).1]; simp [crVarPasses, crOrigPasses]

/-- **CI lane: mixed.** When every BeginFrame is a main frame, the variant's scrolled frame drops the script and does no
more passes on any main-thread stage and no more units on any main-thread stage except `props`, where the compositor
animations' ride-along makes it one unit more than the original; it keeps the original's style units, and it adds a
compositor pass. So in the lane the variant neither dominates nor is dominated on the main thread.

$$\forall \ell, N, \lambda, r:\ \big(\forall s \notin \{\mathrm{props}, \mathrm{comp}\}:\ V.\mathrm{passes}(s) \le O.\mathrm{passes}(s) \land V.\mathrm{units}(s) \le O.\mathrm{units}(s)\big) \land V.\mathrm{passes}(\mathrm{props}) = O.\mathrm{passes}(\mathrm{props}) \land V.\mathrm{units}(\mathrm{props}) = O.\mathrm{units}(\mathrm{props}) + 1 \land V.\mathrm{units}(\mathrm{style}) = O.\mathrm{units}(\mathrm{style}) \land V.\mathrm{passes}(\mathrm{script}) < O.\mathrm{passes}(\mathrm{script}) \land V.\mathrm{passes}(\mathrm{comp}) = 1 > 0 = O.\mathrm{passes}(\mathrm{comp})$$
$$\text{where } V = \operatorname{frameWork}_{\operatorname{chromiumAt}(\mathrm{lane})}\big(\operatorname{crVar}(\mathrm{lane}, \ell, N, r)\big),\ O = \operatorname{frameWork}_{\operatorname{chromiumAt}(\mathrm{lane})}\big(\operatorname{crOrig}(\ell, N, \lambda, r)\big)$$

In the CI lane the variant removes the script but costs one more property-update unit and adds compositor work. -/
theorem cr_lane_mixed (l : Bool) (N : Nat) (lo : LayerState) (r : Bool) :
    let V := frameWork (chromiumAt lane) (crVar lane l N r)
    let O := frameWork (chromiumAt lane) (crOrig l N lo r)
    (∀ s, s ≠ .props → s ≠ .comp → V.passes s ≤ O.passes s ∧ V.units s ≤ O.units s) ∧
      V.passes .props = O.passes .props ∧ V.units .props = O.units .props + 1 ∧
      V.units .style = O.units .style ∧ V.passes .script < O.passes .script ∧
      V.passes .comp = 1 ∧ O.passes .comp = 0 := by
  intro V O
  have hv := cr_var_exact lane l N r rfl
  have ho := cr_orig_exact lane l N lo r
  refine ⟨fun s _ _ => ?_, ?_, ?_, ?_, ?_, (hv .comp).1, (ho .comp).1⟩
  · show (frameWork _ _).passes s ≤ (frameWork _ _).passes s ∧ (frameWork _ _).units s ≤ (frameWork _ _).units s
    rw [(hv s).1, (hv s).2, (ho s).1, (ho s).2]
    cases l <;> cases lo <;> cases r <;> cases s <;>
      simp_all [crVarPasses, crVarUnits, crOrigPasses, crOrigUnits, lane] <;> omega
  · show (frameWork _ _).passes _ = (frameWork _ _).passes _
    rw [(hv _).1, (ho _).1]; rfl
  · show (frameWork _ _).units _ = (frameWork _ _).units _ + 1
    rw [(hv _).2, (ho _).2]; cases l <;> simp [crVarUnits, crOrigUnits, lane] <;> omega
  · show (frameWork _ _).units _ = (frameWork _ _).units _
    rw [(hv _).2, (ho _).2]; cases l <;> simp [crVarUnits, crOrigUnits, lane] <;> omega
  · show (frameWork _ _).passes _ < (frameWork _ _).passes _
    rw [(hv _).1, (ho _).1]; simp [crVarPasses, crOrigPasses]

end Cr

/-! ## Work on WebKit -/

section Wk
open Fw.Engine.WebKit

/-- A consumer's animation on WebKit: a scroll timeline with linear easing, otherwise clean (no blocker, not pending,
asynchronous scroller, two keyframes).

$$\operatorname{wkAnim}(P) = \operatorname{clean}(P, \mathrm{scroll}) \text{ with easing} := \mathrm{linear}$$
-/
def wkAnim (ps : List CssProp) : WkAnim := { WkAnim.clean ps .scroll with easing := .linear }

/-- **The variant's animations on WebKit**, the same list as on Chromium: opacity + transform on the copy; transform on
the cue (phone band only); a separate blur on the copy (above 600 px only) and on the cue; opacity + transform on
each of the $N$ cards.

$$\operatorname{wkAnims}(\ell, N) = [\operatorname{wkAnim}([\mathrm{opacity}, \mathrm{transform}])] \mathbin{+\!\!+} \begin{cases} [\operatorname{wkAnim}([\mathrm{transform}])] & \ell \\ [\operatorname{wkAnim}([\mathrm{filter}])] & \lnot\ell \end{cases} \mathbin{+\!\!+} [\operatorname{wkAnim}([\mathrm{filter}])] \mathbin{+\!\!+} [\operatorname{wkAnim}([\mathrm{opacity}, \mathrm{transform}]) \mid i \in [0, N)]$$
-/
def wkAnims (l : Bool) (N : Nat) : List WkAnim :=
  [wkAnim [.opacity, .transform]] ++ (if l then [wkAnim [.transform]] else [wkAnim [.filter]]) ++
    [wkAnim [.filter]] ++ (List.range N).map (fun _ => wkAnim [.opacity, .transform])

/-- The variant declares $N + 3$ animations in both bands.

$$\forall \ell \in \mathbb{B},\ \forall N \in \mathbb{N}:\ |\operatorname{wkAnims}(\ell, N)| = N + 3$$

Three hero animations plus one per card. -/
theorem wkAnims_length (l : Bool) (N : Nat) : (wkAnims l N).length = N + 3 := by
  cases l <;> simp [wkAnims] <;> omega

/-- Every animation of the variant animates one of three property lists.

$$\forall \ell, N,\ \forall a \in \operatorname{wkAnims}(\ell, N):\ a \in \{\operatorname{wkAnim}([\mathrm{opacity}, \mathrm{transform}]), \operatorname{wkAnim}([\mathrm{transform}]), \operatorname{wkAnim}([\mathrm{filter}])\}$$

The variant animates only opacity, transform and filter. -/
theorem wkAnims_mem (l : Bool) (N : Nat) (a : WkAnim) (ha : a ∈ wkAnims l N) :
    a = wkAnim [.opacity, .transform] ∨ a = wkAnim [.transform] ∨ a = wkAnim [.filter] := by
  cases l <;> simp [wkAnims] at ha <;> grind

/-- **Threaded scroll-driven on: one animation of the variant is accelerated**, blur included (WebKit accelerates
`filter`).

$$\forall m \in \mathrm{WkMode}:\ m.\mathrm{threadedScrollDriven} \Rightarrow \forall P \in \{[\mathrm{opacity}, \mathrm{transform}], [\mathrm{transform}], [\mathrm{filter}]\}:\ \operatorname{wkThread}\big(m, \operatorname{wkAnim}(P)\big) = \mathrm{comp}$$

Each property list the variant uses runs off the main thread when scroll-driven animations are threaded. -/
theorem wk_anim_comp (m : WkMode) (hm : m.threadedScrollDriven = true) (ps : List CssProp)
    (hps : ps = [.opacity, .transform] ∨ ps = [.transform] ∨ ps = [.filter]) : wkThread m (wkAnim ps) = .comp := by
  obtain ⟨tsd, ttb, p⟩ := m
  simp only at hm
  subst hm
  rcases hps with rfl | rfl | rfl <;> cases ttb <;> cases p <;> decide

/-- **WebKit: everything is accelerated.** With threaded scroll-driven animations on, every animation of the variant,
in both bands, runs on the compositor.

$$\forall m \in \mathrm{WkMode}:\ m.\mathrm{threadedScrollDriven} \Rightarrow \forall \ell \in \mathbb{B},\ \forall N \in \mathbb{N},\ \forall a \in \operatorname{wkAnims}(\ell, N):\ \operatorname{wkThread}(m, a) = \mathrm{comp}$$

On WebKit no animation of the variant stays on the main thread. -/
theorem wk_all_comp (m : WkMode) (hm : m.threadedScrollDriven = true) (l : Bool) (N : Nat) :
    ∀ a ∈ wkAnims l N, wkThread m a = .comp := by
  intro a ha
  rcases wkAnims_mem l N a ha with rfl | rfl | rfl <;> exact wk_anim_comp m hm _ (by simp)

/-- **The premise is needed:** with threaded scroll-driven animations off (the legacy path accepts only time
timelines), every animation of the variant runs on the main thread.

$$\forall m \in \mathrm{WkMode}:\ \lnot m.\mathrm{threadedScrollDriven} \Rightarrow \forall \ell \in \mathbb{B},\ \forall N \in \mathbb{N},\ \forall a \in \operatorname{wkAnims}(\ell, N):\ \operatorname{wkThread}(m, a) = \mathrm{main}$$

Without the threaded path the variant gains nothing on WebKit. -/
theorem wk_legacy_main (m : WkMode) (hm : m.threadedScrollDriven = false) (l : Bool) (N : Nat) :
    ∀ a ∈ wkAnims l N, wkThread m a = .main := by
  intro a ha
  obtain ⟨tsd, ttb, p⟩ := m
  simp only at hm
  subst hm
  rcases wkAnims_mem l N a ha with rfl | rfl | rfl <;> cases ttb <;> cases p <;> decide

/-- A frame of WebKit animations: if every animation is accelerated, a compositor frame with one tick each;
otherwise the main thread applies the changes $cs$ (no script).

$$\operatorname{wkAnimsFrame}(m, A, cs) = \begin{cases} \operatorname{compFrame}(|A|) & \forall a \in A:\ \operatorname{wkThread}(m, a) = \mathrm{comp} \\ (0, 0, 0, 0, cs, 0) & \text{otherwise} \end{cases}$$
-/
def wkAnimsFrame (m : WkMode) (as : List WkAnim) (cs : List (Change WkProp)) : FrameIn WkProp :=
  if as.all (fun a => decide (wkThread m a = .comp)) then compFrame as.length else ⟨0, 0, 0, 0, cs, 0⟩

/-- **The variant's scrolled frame on WebKit** in mode $m$ ($cs$: what the animations would write on the main thread).

$$\operatorname{wkVar}(m, \ell, N, cs) = \operatorname{scrollStep}\big(\operatorname{wkAnimsFrame}(m, \operatorname{wkAnims}(\ell, N), cs)\big)$$
-/
def wkVar (m : WkMode) (l : Bool) (N : Nat) (cs : List (Change WkProp)) : FrameIn WkProp :=
  scrollStep (wkAnimsFrame m (wkAnims l N) cs)

/-- With threaded scroll-driven animations on, the variant's scrolled frame is the scroll plus a compositor frame with
$N + 3$ animation ticks.

$$\forall m:\ m.\mathrm{threadedScrollDriven} \Rightarrow \forall \ell, N, cs:\ \operatorname{wkVar}(m, \ell, N, cs) = \operatorname{scrollStep}\big(\operatorname{compFrame}(N + 3)\big)$$

What the variant's frame consists of on WebKit. -/
theorem wkVar_eq (m : WkMode) (hm : m.threadedScrollDriven = true) (l : Bool) (N : Nat) (cs : List (Change WkProp)) :
    wkVar m l N cs = scrollStep (compFrame (N + 3)) := by
  have h : (wkAnims l N).all (fun a => decide (wkThread m a = .comp)) = true := by
    rw [List.all_eq_true]; intro a ha; simp [wk_all_comp m hm l N a ha]
  simp only [wkVar, wkAnimsFrame, h, ↓reduceIte, wkAnims_length]

/-- **Exact work of the variant's scrolled frame on WebKit** (threaded scroll-driven on): the web process does only the
scroll's commit pass (zero units); the compositor ticks the $N + 3$ animations.

$$\forall m:\ m.\mathrm{threadedScrollDriven} \Rightarrow \forall \ell, N, cs,\ \forall s \in \mathrm{Stage}:\ W.\mathrm{passes}(s) = [s \in \{\mathrm{commit}, \mathrm{comp}\}] \land W.\mathrm{units}(s) = \begin{cases} N + 3 & s = \mathrm{comp} \\ 0 & s \ne \mathrm{comp} \end{cases}\quad\text{where } W = \operatorname{frameWork}_{\operatorname{webkitAt}(m)}\big(\operatorname{wkVar}(m, \ell, N, cs)\big)$$

What one scrolled frame of the variant costs WebKit, stage by stage. -/
theorem wk_var_exact (m : WkMode) (hm : m.threadedScrollDriven = true) (l : Bool) (N : Nat)
    (cs : List (Change WkProp)) (s : Stage) :
    (frameWork (webkitAt m) (wkVar m l N cs)).passes s = (if s = .commit ∨ s = .comp then 1 else 0) ∧
      (frameWork (webkitAt m) (wkVar m l N cs)).units s = (if s = .comp then N + 3 else 0) := by
  rw [wkVar_eq m hm l N cs]
  have h0 := scrollPos_stages m 0 .none
  simp only [webkitAt] at h0
  cases s <;> simp [frameWork, touched, stageUnits, forcedPasses, FrameIn.updates, webkitAt, scrollStep,
    compFrame, h0]

/-- No WebKit style change dirties the compositor stage.

$$\forall d \in \mathrm{Diff}:\ \mathrm{comp} \notin \operatorname{diffStages}(d)$$

The web process never runs compositor work for a style change. -/
theorem comp_not_diff (d : Diff) : Stage.comp ∉ diffStages d := by
  cases d <;> simp [diffStages]

/-- **WebKit: a trade.** With threaded scroll-driven animations on, the variant's scrolled frame does strictly less
main-thread work than a scrolled frame of the original's callback, **whatever** changes $cs$ that callback writes
(the script pass is gone and every main-thread stage but the scroll's commit is empty), and its compositor ticks $N + 3$
animations where the original's compositor does nothing.

$$\forall m:\ m.\mathrm{threadedScrollDriven} \Rightarrow \forall \ell, N, cs:\ V \prec_{\mathrm{main}} O \land V.\mathrm{passes}(\mathrm{comp}) = 1 \land V.\mathrm{units}(\mathrm{comp}) = N + 3 \land O.\mathrm{passes}(\mathrm{comp}) = 0 \land O.\mathrm{units}(\mathrm{comp}) = 0$$
$$\text{where } V = \operatorname{frameWork}_{\operatorname{webkitAt}(m)}\big(\operatorname{wkVar}(m, \ell, N, cs)\big),\ O = \operatorname{frameWork}_{\operatorname{webkitAt}(m)}\big(\operatorname{scrollStep}(\operatorname{jsFrame}(cs))\big)$$

On WebKit the variant empties the main thread and pays on the compositor. -/
theorem wk_trade (m : WkMode) (hm : m.threadedScrollDriven = true) (l : Bool) (N : Nat) (cs : List (Change WkProp)) :
    let V := frameWork (webkitAt m) (wkVar m l N cs)
    let O := frameWork (webkitAt m) (scrollStep (jsFrame cs))
    mainLt V O ∧ V.passes .comp = 1 ∧ V.units .comp = N + 3 ∧ O.passes .comp = 0 ∧ O.units .comp = 0 := by
  intro V O
  have hv := wk_var_exact m hm l N cs
  have hoc : O.passes .commit = 1 := scroll_commit m (jsFrame cs)
  have hos : O.passes .script = 1 := by
    show (frameWork _ _).passes _ = _
    simp [frameWork, touched, forcedPasses, scrollStep, jsFrame]
  have hnc : ∀ c : Change WkProp, Stage.comp ∉ diffStages (wkDiff c) := fun c => comp_not_diff _
  have hop : O.passes .comp = 0 := by
    show (frameWork _ _).passes _ = _
    simp [frameWork, touched, forcedPasses, scrollStep, jsFrame, webkitAt, FrameIn.updates, hnc]
  have hou : O.units .comp = 0 := by
    show (frameWork _ _).units _ = _
    simp [frameWork, stageUnits, scrollStep, jsFrame, webkitAt, hnc]
  refine ⟨⟨⟨fun s hs => ?_, ?_⟩, .script, by decide, ?_⟩, (hv .comp).1, (hv .comp).2, hop, hou⟩
  · show (frameWork _ _).passes s ≤ O.passes s ∧ (frameWork _ _).units s ≤ O.units s
    rw [(hv s).1, (hv s).2]
    by_cases hc : s = .commit
    · subst hc; simp [hoc]
    · simp [hc, hs]
  · show (frameWork _ _).hits ≤ (frameWork _ _).hits
    simp [frameWork, wkVar_eq m hm l N cs, scrollStep, compFrame, jsFrame]
  · left
    show (frameWork _ _).passes _ < O.passes _
    rw [(hv _).1, hos]; decide

/-- **The original's scrolled frame on WebKit** at layer state $\lambda$: the callback writes the inherited property,
and each consumer's computed `opacity`, `transform` and `filter` change (copy: opacity, transform, and blur above
600 px; cue: blur, and transform in the phone band; each card: opacity, transform).

$$\operatorname{wkOrigChanges}(\ell, N, \lambda) = [(2, \mathrm{opacity}, \lambda), (2, \mathrm{transform}, \lambda)] \mathbin{+\!\!+} \begin{cases} [\,] & \ell \\ [(2, \mathrm{filter}, \lambda)] & \lnot\ell \end{cases} \mathbin{+\!\!+} [(3, \mathrm{filter}, \lambda)] \mathbin{+\!\!+} \begin{cases} [(3, \mathrm{transform}, \lambda)] & \ell \\ [\,] & \lnot\ell \end{cases} \mathbin{+\!\!+} \big[(4 + i, \mathrm{opacity}, \lambda), (4 + i, \mathrm{transform}, \lambda) \mid i \in [0, N)\big]$$
-/
def wkOrigChanges (l : Bool) (N : Nat) (lo : LayerState) : List (Change WkProp) :=
  [⟨2, .opacity, lo⟩, ⟨2, .transform, lo⟩] ++ (if l then [] else [⟨2, .filter, lo⟩]) ++ [⟨3, .filter, lo⟩] ++
    (if l then [⟨3, .transform, lo⟩] else []) ++
    (List.range N).flatMap (fun i => [⟨4 + i, .opacity, lo⟩, ⟨4 + i, .transform, lo⟩])

end Wk

/-! ## Golden rows (`engine-check` schema) -/

/-- One golden row: engine, scenario, variant, stage, prediction against the base `original`, count type.

$$\mathrm{GRow} = \mathrm{String}^{6} \ni (\mathrm{engine}, \mathrm{scenario}, \mathrm{variant}, \mathrm{stage}, \mathrm{prediction}, \mathrm{countType})$$
-/
structure GRow where
  engine     : String
  scenario   : String
  variant    : String
  stage      : String
  prediction : String
  countType  : String
deriving Repr, DecidableEq

/-- The JSON line of a row (keys sorted, `base` = `original`).

$$\operatorname{json}(r) = \{\mathrm{base}: \text{original},\ \mathrm{countType}: r.\mathrm{countType},\ \mathrm{engine}: r.\mathrm{engine},\ \mathrm{prediction}: r.\mathrm{prediction},\ \mathrm{scenario}: r.\mathrm{scenario},\ \mathrm{stage}: r.\mathrm{stage},\ \mathrm{variant}: r.\mathrm{variant}\}$$
-/
def GRow.json (r : GRow) : String :=
  (Lean.Json.mkObj [("base", .str "original"), ("countType", .str r.countType), ("engine", .str r.engine),
    ("prediction", .str r.prediction), ("scenario", .str r.scenario), ("stage", .str r.stage),
    ("variant", .str r.variant)]).compress

/-- **The prediction of one stage over a frame sequence** of (variant, original) work pairs: `<o` when the variant's
passes and units are at most the original's in every frame and its passes are strictly fewer in some frame; `≤o` when
only the first holds; `any` otherwise. Counts are whole-page, so the rule never predicts `=0` or `=o`.

$$\operatorname{framePred}(F, s) = \begin{cases} \text{<o} & (\forall (v, o) \in F:\ v.\mathrm{passes}(s) \le o.\mathrm{passes}(s) \land v.\mathrm{units}(s) \le o.\mathrm{units}(s)) \land \exists (v, o) \in F:\ v.\mathrm{passes}(s) < o.\mathrm{passes}(s) \\ \text{≤o} & (\forall (v, o) \in F:\ v.\mathrm{passes}(s) \le o.\mathrm{passes}(s) \land v.\mathrm{units}(s) \le o.\mathrm{units}(s)) \land \lnot\exists (v, o) \in F:\ v.\mathrm{passes}(s) < o.\mathrm{passes}(s) \\ \text{any} & \text{otherwise} \end{cases}$$
-/
def framePred (fr : List (Work × Work)) (s : Stage) : String :=
  if fr.all (fun p => decide (p.1.passes s ≤ p.2.passes s ∧ p.1.units s ≤ p.2.units s)) then
    if fr.any (fun p => decide (p.1.passes s < p.2.passes s)) then "<o" else "≤o"
  else "any"

/-- The empty work (a test value for `framePred`).

$$\mathrm{zeroWork} = (s \mapsto 0,\ s \mapsto 0,\ 0)$$
-/
def zeroWork : Work := ⟨fun _ => 0, fun _ => 0, 0⟩

/-- A work with one pass and one unit at `script` (a test value for `framePred`).

$$\mathrm{scriptWork} = (s \mapsto [s = \mathrm{script}],\ s \mapsto [s = \mathrm{script}],\ 0)$$
-/
def scriptWork : Work := ⟨fun s => if s = .script then 1 else 0, fun s => if s = .script then 1 else 0, 0⟩

#guard framePred [(zeroWork, scriptWork)] .script == "<o"
#guard framePred [(zeroWork, scriptWork), (zeroWork, zeroWork)] .script == "<o"
#guard framePred [(zeroWork, zeroWork)] .script == "≤o"
#guard framePred [] .script == "≤o"
#guard framePred [(scriptWork, zeroWork)] .script == "any"
#guard framePred [(zeroWork, scriptWork), (scriptWork, zeroWork)] .script == "any"

/-- The golden scenario: the Chromium lane profile `swipe-v1` (430 px, phone band).

$$\mathrm{gScenario} = \text{swipe-v1}$$
-/
def gScenario : String := "swipe-v1"

/-- The variant's name.

$$\mathrm{gVariant} = \text{hero-exit-threaded}$$
-/
def gVariant : String := "hero-exit-threaded"

/-- The golden band: the phone band, since `swipe-v1` is 430 px wide.

$$\mathrm{gBand} = \mathrm{true}$$
-/
def gBand : Bool := true

/-- Number of cards in the golden setting.

$$\mathrm{gN} = 4$$
-/
def gN : Nat := 4

/-- **Chromium lane frames**: a scrolled frame and an idle frame (original: nothing; variant: the compositor
animations alone, which in the lane ride along a main frame).

$$F_{\mathrm{cr}} = \big[(V_{\mathrm{scroll}}, O_{\mathrm{scroll}}),\ (V_{\mathrm{idle}}, O_{\mathrm{idle}})\big],\quad V_{\mathrm{scroll}} = \operatorname{frameWork}(\operatorname{crVar}(\mathrm{lane}, \mathrm{true}, 4, \mathrm{false})),\ O_{\mathrm{scroll}} = \operatorname{frameWork}(\operatorname{crOrig}(\mathrm{true}, 4, \mathrm{layer}, \mathrm{false}))$$
$$V_{\mathrm{idle}} = \operatorname{frameWork}\big((0, 0, 0, 0, [\,], \operatorname{crVar}(\mathrm{lane}, \mathrm{true}, 4, \mathrm{false}).\mathrm{compAnims})\big),\ O_{\mathrm{idle}} = \operatorname{frameWork}\big((0, 0, 0, 0, [\,], 0)\big)$$
-/
def crFrames : List (Work × Work) :=
  let E := Chromium.chromiumAt Chromium.lane
  let v := crVar Chromium.lane gBand gN false
  [(frameWork E v, frameWork E (crOrig gBand gN .layer false)),
    (frameWork E ⟨0, 0, 0, 0, [], v.compAnims⟩, frameWork E (⟨0, 0, 0, 0, [], 0⟩ : FrameIn Chromium.CrProp))]

/-- **WebKit frames** (Safari mode): a scrolled frame and an idle frame (original: nothing; variant: compositor
ticks only).

$$F_{\mathrm{wk}} = \big[(\operatorname{frameWork}(\operatorname{wkVar}(\mathrm{safari}, \mathrm{true}, 4, cs)), \operatorname{frameWork}(\operatorname{scrollStep}(\operatorname{jsFrame}(cs)))),\ (\operatorname{frameWork}(\operatorname{compFrame}(7)), \operatorname{frameWork}((0, 0, 0, 0, [\,], 0)))\big],\quad cs = \operatorname{wkOrigChanges}(\mathrm{true}, 4, \mathrm{layer})$$
-/
def wkFrames : List (Work × Work) :=
  let E := WebKit.webkitAt WebKit.WkMode.safari
  let cs := wkOrigChanges gBand gN .layer
  [(frameWork E (wkVar WebKit.WkMode.safari gBand gN cs), frameWork E (WebKit.scrollStep (WebKit.jsFrame cs))),
    (frameWork E (WebKit.compFrame (gN + 3)), frameWork E (⟨0, 0, 0, 0, [], 0⟩ : FrameIn WebKit.WkProp))]

/-- The Chromium count types per stage; `paint` keeps only `trace.Paint`, since the raster counts belong to
`raster`.

$$\operatorname{crCounts}(s) = \begin{cases} [\text{trace.Paint}] & s = \mathrm{paint} \\ \operatorname{stageCounts}(s) & s \ne \mathrm{paint} \end{cases}$$
-/
def crCounts (s : Stage) : List String :=
  if s = .paint then ["trace.Paint"] else Chromium.stageCounts s

/-- **Golden rows.** Chromium: every stage and count type; `props` (lifecycle frames) and `comp` (layer census) are
`any`. WebKit: the Simulator and WKTR count types.

$$\mathrm{rows} = [(\mathrm{chromium}, s, \kappa, p_{\mathrm{cr}}(s)) \mid s \in \mathrm{Stage}, \kappa \in \operatorname{crCounts}(s)] \mathbin{+\!\!+} [(\mathrm{webkit}, s, \kappa, \operatorname{framePred}(F_{\mathrm{wk}}, s)) \mid (s, \kappa) \in \operatorname{counts}(\mathrm{sim}) \mathbin{+\!\!+} \operatorname{counts}(\mathrm{wktr})]$$
$$p_{\mathrm{cr}}(s) = \begin{cases} \text{any} & s \in \{\mathrm{props}, \mathrm{comp}\} \\ \operatorname{framePred}(F_{\mathrm{cr}}, s) & \text{otherwise} \end{cases}$$
-/
def goldenRows : List GRow :=
  let stages : List Stage := [.script, .style, .layout, .props, .paint, .raster, .commit, .comp]
  let cr := stages.flatMap fun s =>
    let p := if s = .props ∨ s = .comp then "any" else framePred crFrames s
    (crCounts s).map fun k => ⟨"chromium", gScenario, gVariant, Chromium.stageName s, p, k⟩
  let wk := (WebKit.Lane.counts .sim ++ WebKit.Lane.counts .wktr).map fun (s, k) =>
    ⟨"webkit", gScenario, gVariant, WebKit.stageName s, framePred wkFrames s, k⟩
  cr ++ wk

/-- The rows as JSON lines (`packages/contracts/golden/engine/hero-exit.jsonl`).

$$\mathrm{goldenJsonl} = \operatorname{concat}[\operatorname{json}(r) \mathbin{+\!\!+} \text{"\textbackslash n"} \mid r \in \mathrm{rows}]$$
-/
def goldenJsonl : String := String.join (goldenRows.map fun r => r.json ++ "\n")

/-- The prediction of the first row with engine $e$ and count type $k$ (`?` if there is none).

$$\operatorname{gPred}(e, k) = \begin{cases} r.\mathrm{prediction} & r \text{ the first row of rows with } r.\mathrm{engine} = e \land r.\mathrm{countType} = k \\ \text{?} & \text{no such row} \end{cases}$$
-/
def gPred (e k : String) : String :=
  ((goldenRows.find? fun r => r.engine == e && r.countType == k).map (·.prediction)).getD "?"

#guard goldenRows.length == 20
-- Chromium lane: the script is gone, the raster of the shared-layer consumers is gone; style rides along when idle.
#guard gPred "chromium" "trace.FireAnimationFrame" == "<o" && gPred "chromium" "raster.invalidationRects" == "<o"
#guard gPred "chromium" "trace.UpdateLayoutTree" == "any" && gPred "chromium" "trace.Layout" == "≤o"
#guard gPred "chromium" "trace.cc.Commit" == "≤o" && gPred "chromium" "trace.Paint" == "≤o"
#guard gPred "chromium" "trace.PrePaint" == "any" && gPred "chromium" "census.layers" == "any"
-- WebKit: script, style, layout and paint are gone; the scroll's commit stays.
#guard gPred "webkit" "FireAnimationFrame" == "<o" && gPred "webkit" "RecalculateStyles" == "<o"
#guard gPred "webkit" "Layout" == "<o" && gPred "webkit" "Paint" == "<o" && gPred "webkit" "Composite" == "≤o"
#guard gPred "webkit" "styleRecalcs" == "<o" && gPred "webkit" "layoutUpdates" == "<o"
#guard gPred "webkit" "compositingUpdates" == "≤o" && gPred "webkit" "renderingUpdates" == "≤o"
#guard gPred "webkit" "x" == "?"

end Fw.Parts.HeroExitOpt
