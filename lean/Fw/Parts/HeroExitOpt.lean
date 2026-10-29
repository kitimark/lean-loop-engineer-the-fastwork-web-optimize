import Fw.Parts.HeroExit
import Fw.Engine.Chromium
import Fw.Engine.WebKit
import Lean.Data.Json
import Fw.Parts.EndFlags
import Fw.Engine.Restyle
import Fw.Engine.Visual

/-!
# hero.exit, variant `hero-exit-threaded`: scroll-driven consumers (design note §4.2, row HE)

The original (`Fw.Parts.HeroExit`) runs one `requestAnimationFrame` callback per scrolled frame: it reads the track
rect, computes `e = exitOpacity` and writes the inherited custom property `--exit-opacity` on `.hero`;
every consumer (copy, scroll cue, cards) recomputes its `opacity`, `transform` and `filter: blur()` from it by
`calc()`. The variant drops the callback and gives each consumer its own CSS animation on a scroll timeline (a
`view-timeline` on `.hero-track`).

`pointer-events` is not a visual consumer: the variant flips it from an IntersectionObserver sentinel placed at the
threshold that `HeroExit.pointerOff_iff_threshold` proves (`sentinel_iff_pointerOff`); its delivery (one
observation step after the frame) is glue and is not proved here.

What is proved:
* **E-s** (`consumer_eq_s`): under the research-gap hypothesis RG11 (`RG11`: the engine's timeline progress at offset
  `y` is the clamped linear progress of the CSS spec with start `T` and length `max(1, h - v)`), every consumer's
  animated value equals the original's `calc()` value at **every** scroll offset, in both width bands, for any
  settled entrance state. Core step: `progress_eq_js`, from `exitOpacity_linear`, `_before` and `_after`.
* **Work, Chromium** (`chromiumAt m`, threaded animation on): exact per-frame tables for a scrolled frame
  (`cr_orig_exact`, `cr_var_exact`). The script callback is gone; opacity and transform go to the compositor; blur
  stays on main (bit 12, `blur_main`). In real Chrome the main-thread work strictly drops (`cr_real_trade`); in the CI
  lane (every BeginFrame a main frame) the ride-along of the `animCount ℓ N = 2N + 5` animations (one per CSS name,
  `animCount_eq`) makes the props units `N + 3` and the style units `N + 2` higher (`cr_lane_mixed`), on fewer elements
  (`cr_lane_style_elems`). Either way the compositor stage gains work: a **trade**, never "dominates".
* **Work, WebKit** (`webkitX m`, threaded scroll-driven on): every animation, blur included, is accelerated
  (`wk_all_comp`; with the threaded path off, all run on main: `wk_legacy_main`). Under the measured premise
  `WktrStyleRate.Holds` (WKTR fixtures, task wktr-p1p4: a scroll-timeline animation restyles its target once per
  rendering update, accelerated or not) a scrolled frame keeps the scroll commit **and one style pass** with
  `animCount ℓ N` restyle units on the web process (`wk_var_exact`). The variant's ride-along targets are the elements
  of the model's original change list `wkOrigChanges` (copy, cue, the `N` cards, `wk_style_elems`). Since the style
  units are equal (`2N + 5` each) against `wkOrigChanges`, which omits the WebKit inherited fan-out, the main-thread
  work drops by the script pass (`wk_trade`), but not for any change list (`wk_trade_not_general`). The real original
  also resolves the inherited `--exit-opacity` fan-out of the hero subtree on WebKit, which `wkOrigChanges` omits, so
  per element WebKit style work still drops. The UI process gains the animations: again a trade.
* **Golden rows** (`goldenJsonl` → `packages/contracts/golden/engine/hero-exit.jsonl`) in the `engine-check` schema.
* **Changed since CI run 39088367495 (engine-model-fix).** On Chromium a `filter: blur()` value change on an own layer
  rasters (MEASURED), so both arms keep one raster pass (`crOrigPasses`, `crVarPasses`) and the golden raster row is
  `≤o`, not `<o`; the variant still rasters fewer units. On WebKit the compositing table (`wkCompUpdate`) gives the
  original's shared-layer changes a compositing update.
-/
namespace Fw.Parts.HeroExitOpt

open Fw.Parts.HeroExit
open Fw.Engine

/-! ## Timeline progress (RG11) -/

/-- Clamp to the unit interval.

A value held between 0 and 1. -/
def clamp01 (x : Rat) : Rat := min 1 (max 0 x)

/-- Progress of a scroll timeline with start offset `S` and length `L` at scroll offset `y`, with `fill: both`
(CSS Scroll-driven Animations: progress = (offset − start) / (end − start), held at the end keyframes outside the
range).

How far through its range a scroll-driven animation is at scroll offset `y` (Lean division: `x / 0 = 0`). -/
def timelineProgress (S L y : Rat) : Rat := clamp01 ((y - S) / L)

/-- **Research gap RG11, carried as a hypothesis.** The engine's progress function `prog` (offset ↦ progress)
equals the spec formula with start `T` (the offset where the track top meets the viewport top) and length
`max(1, h - v)` (the JS's `innerHeight`-based range). Whether `view-timeline` `contain` gives exactly these
numbers on each engine (scrollport vs `innerHeight`, dynamic toolbars) is RG11 itself.

The engine's scroll-timeline progress is the spec's clamped linear progress over the original's exit range. -/
def RG11 (prog : Rat → Rat) (T h v : Rat) : Prop := ∀ y, prog y = timelineProgress T (exitRange h v) y

/-- Cancel a positive factor on the right.

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

The value a two-keyframe linear animation shows at progress `p`. -/
def lerp (a b p : Rat) : Rat := a + (b - a) * p

/-- One animated consumer value of the hero exit, with the parameters that are constant while the user scrolls a
settled page: the copy's entrance amount `c` (`--copy-in`), the band `ℓ` (`width<=600px`), and a card's entrance
state `n` (field `entered`), entrance offset `x_e` (field `enter`) and scatter offset `x_s` (field `off`).
-/
inductive Consumer where
  | copyOpacity (c : Rat)
  | copyTranslateY (c : Rat) (l : Bool)
  | copyBlur (c : Rat) (l : Bool)
  | cueOpacity
  | cueBlur
  | cueTranslateY (l : Bool)
  | cardOpacity
  | cardTranslate (entered enter off : Rat)

/-- The original's value of a consumer as a function of the exit opacity `e` (its `calc()`, restated in
`Fw.Parts.HeroExit`, with `s = 1 - e`).

What the original shows for each consumer at exit opacity `e`. -/
def Consumer.val : Consumer → Rat → Rat
  | .copyOpacity c, e => HeroExit.copyOpacity c e
  | .copyTranslateY c l, e => HeroExit.copyTranslateYPx c (exitScatter e) l
  | .copyBlur c l, e => HeroExit.copyBlurPx c (exitScatter e) l
  | .cueOpacity, e => HeroExit.cueOpacity e
  | .cueBlur, e => HeroExit.cueBlurPx (exitScatter e)
  | .cueTranslateY l, e => HeroExit.cueTranslateYPx (exitScatter e) l
  | .cardOpacity, e => HeroExit.cardOpacity (exitScatter e)
  | .cardTranslate n xe xs, e => HeroExit.cardTranslate n xe (exitScatter e) xs

/-- The variant's animation of a consumer: keyframe `0%` is the value at rest (`e = 1`), keyframe `100%` the value
fully exited (`e = 0`), linear easing.

What the scroll-driven animation of consumer `k` shows at progress `p`. -/
def Consumer.anim (k : Consumer) (p : Rat) : Rat := lerp (k.val 1) (k.val 0) p

/-- Every consumer is affine in the exit opacity.

Each `calc()` the original evaluates is a straight line in `e`. -/
theorem val_affine (k : Consumer) (e : Rat) : k.val e = k.val 0 + (k.val 1 - k.val 0) * e := by
  cases k <;> simp only [Consumer.val, HeroExit.copyOpacity, HeroExit.copyTranslateYPx, HeroExit.copyBlurPx,
    HeroExit.cueOpacity, HeroExit.cueBlurPx, HeroExit.cueTranslateYPx, HeroExit.cardOpacity, HeroExit.cardTranslate,
    exitScatter] <;>
    (try split) <;> grind

/-- The animation at progress `1 - e` shows the original's value at exit opacity `e`.

Two keyframes and a linear ramp reproduce any affine consumer exactly. -/
theorem anim_eq (k : Consumer) (e : Rat) : k.anim (1 - e) = k.val e := by
  have := val_affine k e
  unfold Consumer.anim lerp
  grind

/-- **E-s: every scroll-driven consumer equals the original at every scroll offset** (under RG11), in both width
bands and for any settled entrance state.

The variant shows exactly the original's copy, cue and card values wherever the page is scrolled. -/
theorem consumer_eq_s (k : Consumer) (prog : Rat → Rat) (T h v : Rat) (hrg : RG11 prog T h v) (y : Rat) :
    k.anim (prog y) = k.val (exitOpacityAt T h v y) := by
  rw [hrg y, progress_eq_js]
  exact anim_eq k _

/-- Under reduced motion the variant attaches no animation (its rules sit in
`@media (prefers-reduced-motion: no-preference)`), so each consumer takes its rest value `g_k(1)`, which is what the
original's reduced-motion frame writes.

With reduced motion both variants show the hero at rest. -/
theorem reduced_eq (k : Consumer) (t h v : Rat) :
    k.val (exitFrame true t h v).opacity = k.val 1 ∧ k.val 1 = k.anim 0 := by
  refine ⟨rfl, ?_⟩
  unfold Consumer.anim lerp; grind

/-- The IntersectionObserver sentinel for `pointer-events`: it sits `19/20` of the exit range below the
track top, and pointer events are off when it is strictly above the viewport top.

Whether the sentinel has scrolled past the top of the viewport. -/
def sentinelAbove (T h v y : Rat) : Bool := decide (T + 19 / 20 * exitRange h v - y < 0)

#guard sentinelAbove 0 1600 800 761 == true
#guard sentinelAbove 0 1600 800 760 == false

/-- The sentinel decides exactly the original's pointer cut-off (from `pointerOff_iff_threshold`).

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

One frame does no more main-thread work than another, ignoring the compositor. -/
def mainLe (a b : Work) : Prop :=
  (∀ s, s ≠ Stage.comp → a.passes s ≤ b.passes s ∧ a.units s ≤ b.units s) ∧ a.hits ≤ b.hits

/-- Strict main-thread order: `≼_main` plus one main-thread stage with strictly fewer passes or
units.

One frame does strictly less main-thread work than another. -/
def mainLt (a b : Work) : Prop :=
  mainLe a b ∧ ∃ s, s ≠ Stage.comp ∧ (a.passes s < b.passes s ∨ a.units s < b.units s)

/-- Main-thread order bounds the main-thread time under any unit costs (`toCost` reads only script, style, layout and
paint units).

Less main-thread work per stage never costs more main-thread time. -/
theorem mainLe_mainUs (u : Cost.UnitCost) {a b : Work} (h : mainLe a b) :
    Cost.mainUs u (toCost a) ≤ Cost.mainUs u (toCost b) :=
  Cost.mainUs_mono u ⟨(h.1 .script (by decide)).2, (h.1 .style (by decide)).2, (h.1 .layout (by decide)).2,
    (h.1 .paint (by decide)).2⟩

inductive ExitNode where
  | orbit
  | deck
  | copy
  | cue
deriving Repr, DecidableEq

def exitNodes : List ExitNode := [.orbit, .deck, .copy, .cue]

def ExitNode.label : ExitNode → String
  | .orbit => "orbit"
  | .deck => "deck"
  | .copy => "copy"
  | .cue => "cue"

def exitNames (n : ExitNode) (le600 : Bool) : List String :=
  match n with
  | .orbit => ["exitCardFade", "exitCardMove"]
  | .deck => ["exitCardFade", "exitCardMove"]
  | .copy => if le600 then ["exitFade", "exitCopyUpNarrow"] else ["exitFade", "exitCopyUp", "exitBlur"]
  | .cue => if le600 then ["exitFade", "exitCueUpNarrow", "exitBlur"] else ["exitFade", "exitBlur"]

inductive AnimProp where
  | opacity
  | transform
  | translate
  | blur
deriving Repr, DecidableEq

def nameProp : String → Option AnimProp
  | "exitFade" | "exitCardFade" => some .opacity
  | "exitCopyUp" | "exitCopyUpNarrow" | "exitCueUpNarrow" => some .transform
  | "exitCardMove" => some .translate
  | "exitBlur" => some .blur
  | _ => none

#guard exitNodes.all fun n => [true, false].all fun l => (exitNames n l).all fun s => (nameProp s).isSome
#guard [true, false].all fun l => exitNames .deck l == exitNames .orbit l
#guard nameProp "exitCardMove" == some .translate && nameProp "copyIn" == none

def nodeAnims (e : Nat) (n : ExitNode) (l : Bool) : List (Nat × AnimProp) :=
  (exitNames n l).filterMap fun s => (nameProp s).map ((e, ·))

def exitAnims (l : Bool) (N : Nat) : List (Nat × AnimProp) :=
  nodeAnims 2 .copy l ++ nodeAnims 3 .cue l ++ (List.range N).flatMap fun i => nodeAnims (4 + i) .orbit l

def animCount (l : Bool) (N : Nat) : Nat := (exitAnims l N).length

def cardAnims (N : Nat) : List (Nat × AnimProp) :=
  (List.range N).flatMap fun i => [(4 + i, .opacity), (4 + i, .translate)]

def headAnims (l : Bool) : List (Nat × AnimProp) :=
  if l then [(2, .opacity), (2, .transform), (3, .opacity), (3, .transform), (3, .blur)]
  else [(2, .opacity), (2, .transform), (2, .blur), (3, .opacity), (3, .blur)]

theorem exitAnims_eq (l : Bool) (N : Nat) : exitAnims l N = headAnims l ++ cardAnims N := by
  cases l <;> rfl

theorem cardAnims_length (N : Nat) : (cardAnims N).length = 2 * N := by
  induction N with
  | zero => rfl
  | succ n ih => simp only [cardAnims, List.range_succ, List.flatMap_append] at *; simp [ih]; omega

theorem animCount_eq (l : Bool) (N : Nat) : animCount l N = 2 * N + 5 := by
  rw [animCount, exitAnims_eq, List.length_append, cardAnims_length]; cases l <;> simp [headAnims] <;> omega

#guard animCount true 4 == 13 && animCount false 10 == 25

theorem mem_cardAnims_fst (N e : Nat) : e ∈ (cardAnims N).map Prod.fst ↔ 4 ≤ e ∧ e < 4 + N := by
  simp only [cardAnims, List.map_flatMap, List.map_cons, List.map_nil, List.mem_flatMap, List.mem_range,
    List.mem_cons, List.not_mem_nil, or_false, or_self]
  constructor
  · rintro ⟨a, ha, rfl⟩; omega
  · intro h; exact ⟨e - 4, by omega, by omega⟩

section Cr
open Fw.Engine.Chromium

/-- The custom property id of `--exit-opacity`. -/
def exitVar : Nat := 0

/-- The properties of the copy that read `--exit-opacity` (phone band: `filter: none`). -/
def copyReaders (l : Bool) : List CrKey :=
  if l then [.opacity, .transform] else [.opacity, .filter true, .transform]

/-- The properties of the scroll cue that read `--exit-opacity` (settled; its translate is constant above 600 px). -/
def cueReaders (l : Bool) : List CrKey :=
  if l then [.opacity, .filter true, .transform] else [.opacity, .filter true]

/-- The root scroller's offset change in a scrolled frame (`r`: the scroll crosses a cull-rect repaint). -/
def scrollC (r : Bool) : Change CrProp := ⟨0, .scroll r, .own⟩

/-- The original's style changes in one scrolled frame: `--exit-opacity` on `.hero` (element 1, read by nothing on
itself), then the inherited change on the copy (2), the cue (3) and the `N` cards (`4 + i`), each at layer state
`λ`, then the scroll.
-/
def crOrigChanges (l : Bool) (N : Nat) (lo : LayerState) (r : Bool) : List (Change CrProp) :=
  [⟨1, .custom exitVar [], lo⟩, ⟨2, .custom exitVar (copyReaders l), lo⟩, ⟨3, .custom exitVar (cueReaders l), lo⟩] ++
    (List.range N).map (fun i => (⟨4 + i, .custom exitVar [.opacity, .transform], lo⟩ : Change CrProp)) ++
    [scrollC r]

/-- **The original's scrolled frame on Chromium**: one rAF callback that writes the custom property.

What the original asks of Chromium in one scrolled frame. -/
def crOrig (l : Bool) (N : Nat) (lo : LayerState) (r : Bool) : FrameIn CrProp := jsWrite 1 (crOrigChanges l N lo r)

def sAnim (x : Nat) (ps : List CrProp) : CrAnim := ⟨x, ps, .own, true, .scroll true⟩

def crProp : AnimProp → CrProp
  | .opacity => .css .opacity
  | .transform => .css .transform
  | .translate => .css .translate
  | .blur => .css (.filter true)

def crAnims (l : Bool) (N : Nat) : List CrAnim := (exitAnims l N).map fun p => sAnim p.1 [crProp p.2]

/-- **The variant's scrolled frame on Chromium** in mode `m`: the animation frame plus the scroll.

What the variant asks of Chromium in one scrolled frame. -/
def crVar (m : CrMode) (l : Bool) (N : Nat) (r : Bool) : FrameIn CrProp :=
  let f := animFrame m (crAnims l N)
  { f with changes := f.changes ++ [scrollC r] }

/-- **Blur stays on main (bit 12).** A `filter: blur()` animation sets failure bit 12 and runs on the main thread in
every mode.

Chromium never composites a blur animation. -/
theorem blur_main (m : CrMode) (x : Nat) :
    12 ∈ failBits m (sAnim x [.css (.filter true)]) ∧ crThread m (sAnim x [.css (.filter true)]) = .main := by
  constructor
  · simp [failBits, sAnim, CrProp.movesPixels]
  · cases h : crThread m (sAnim x [.css (.filter true)])
    · rfl
    · have := ((crThread_comp_iff m _).mp h).2.2.2.1 (.css (.filter true)) (by simp [sAnim])
      simp [CrProp.movesPixels] at this

theorem anim_comp (m : CrMode) (x : Nat) (p : AnimProp) (hp : p ≠ .blur) (hm : m.threadedAnim = true) :
    crThread m (sAnim x [crProp p]) = .comp := by
  cases p <;> simp_all [crThread, failBits, sAnim, crProp, CrProp.movesPixels, CrProp.eligible]

/-- **Why the blur is split off.** One animation of opacity, blur and transform together would run on the main thread
(bit 12), taking the fade and the motion with it.

Merging the blur into the copy's animation would drag it all back to main. -/
theorem merged_main (m : CrMode) (x : Nat) :
    crThread m (sAnim x [.css .opacity, .css (.filter true), .css .transform]) = .main := by
  cases h : crThread m (sAnim x [.css .opacity, .css (.filter true), .css .transform])
  · rfl
  · have := ((crThread_comp_iff m _).mp h).2.2.2.1 (.css (.filter true)) (by simp [sAnim])
    simp [CrProp.movesPixels] at this

theorem crVar_eq (m : CrMode) (l : Bool) (N : Nat) (r : Bool) (hm : m.threadedAnim = true) :
    crVar m l N r = ⟨0, 0, 0, 0, (if l then [] else [⟨2, .css (.filter true), .own⟩]) ++
      [⟨3, .css (.filter true), .own⟩, scrollC r], 2 * N + (if l then 4 else 3)⟩ := by
  have hb : ∀ x, crThread m (sAnim x [crProp .blur]) = .main := fun x => (blur_main m x).2
  have hc : ∀ x p, p ≠ AnimProp.blur → crThread m (sAnim x [crProp p]) = .comp :=
    fun x p hp => anim_comp m x p hp hm
  have hcards : ∀ a ∈ (cardAnims N).map (fun p => sAnim p.1 [crProp p.2]), crThread m a = .comp := by
    intro a ha
    simp only [List.mem_map, cardAnims, List.mem_flatMap, List.mem_range, List.mem_cons, List.not_mem_nil,
      or_false] at ha
    obtain ⟨p, ⟨i, _, hp⟩, rfl⟩ := ha
    rcases hp with rfl | rfl <;> exact hc _ _ (by simp)
  have hf1 : ((cardAnims N).map (fun p => sAnim p.1 [crProp p.2])).filter
      (fun a => decide (crThread m a = .main)) = [] := by
    rw [List.filter_eq_nil_iff]; intro a ha; simp [hcards a ha]
  have hf2 : ((cardAnims N).map (fun p => sAnim p.1 [crProp p.2])).filter
      (fun a => decide (crThread m a = .comp)) = (cardAnims N).map (fun p => sAnim p.1 [crProp p.2]) := by
    rw [List.filter_eq_self]; intro a ha; simp [hcards a ha]
  have h1 := hc 2 .opacity (by decide)
  have h2 := hc 2 .transform (by decide)
  have h3 := hc 3 .opacity (by decide)
  have h4 := hc 3 .transform (by decide)
  simp only [crVar, crAnims, exitAnims_eq, List.map_append]
  have hb2 := hb 2
  have hb3 := hb 3
  cases l <;> simp only [animFrame, headAnims, ↓reduceIte, Bool.false_eq_true, List.map_cons, List.cons_append,
      List.nil_append, List.filter_cons, List.filter_append, hf1, hf2, hb2, hb3, h1, h2, h3, h4] <;>
    simp [cardAnims_length, CrAnim.changes, sAnim, crProp] <;> omega

/-- The number of blurred consumers in a scrolled frame: the cue always, the copy above 600 px (`¬ℓ`).

How many consumers carry a `filter: blur()`. -/
def blurs (l : Bool) : Nat := if l then 1 else 2

/-- The original's passes per stage in a scrolled frame (`r`: a cull-rect repaint). The raster pass always runs,
because the cue's blur re-rasters on every layer state.

Changed since CI run 39088367495: the raster pass was `[λ ≠ own ∨ r]`; a blur value change on
an own layer was modelled as a property-tree update and is MEASURED as a raster.

The original's stage passes in one scrolled frame. -/
def crOrigPasses (r : Bool) : Stage → Nat
  | .script => 1 | .style => 1 | .layout => 0 | .props => 1
  | .paint => if r then 1 else 0
  | .raster => 1
  | .commit => 1 | .comp => 0

/-- The original's units per stage in a scrolled frame with `N` cards. On an own layer only the blurred consumers
re-raster.

Changed since CI run 39088367495: the raster units were `[λ ≠ own] (N + 2) + [r]` (no blurred
consumer re-rastered on an own layer).

The original's stage units in one scrolled frame. -/
def crOrigUnits (l : Bool) (N : Nat) (lo : LayerState) (r : Bool) : Stage → Nat
  | .script => 1 | .style => N + 3 | .layout => 0 | .props => N + 3
  | .paint => if r then 1 else 0
  | .raster => (if lo = .own then blurs l else N + 2) + (if r then 1 else 0)
  | .commit => N + 3 | .comp => 0

/-- The stages a reader of `--exit-opacity` dirties at layer state `λ`, `b`: the reader includes a blur. An
unblurred reader on its own layer takes the property-tree fast path; any other reader re-rasters.

Changed since CI run 39088367495: the blur flag `b` is new; a blurred reader on its own layer took the fast path.

What one consumer's inherited change costs. -/
def readerStages (lo : LayerState) (b : Bool) : List Stage :=
  if lo = .own ∧ b = false then [.style, .props, .commit] else [.style, .props, .raster, .commit]

/-- Every consumer of the original dirties exactly the reader stages of its layer state and blur flag, in both
bands.

Changed since CI run 39088367495: the stages now depend on whether `K` contains a blur.

Copy, cue and cards cost the reader stages; only a blur keeps the raster on an own layer. -/
theorem reader_stages (x : Nat) (ks : List CrKey) (lo : LayerState) (l : Bool)
    (hk : ks = copyReaders l ∨ ks = cueReaders l ∨ ks = [.opacity, .transform]) :
    crStagesOf ⟨x, .custom exitVar ks, lo⟩ = readerStages lo (decide (CrKey.filter true ∈ ks)) := by
  rcases hk with rfl | rfl | rfl <;> cases l <;> cases lo <;> rfl

/-- **Exact work of the original's scrolled frame on Chromium**, in every mode and both bands: one callback, one
style pass over the hero and its `N + 2` readers, a property update and commit for the readers and the scroll, and a
raster of every reader unless it has its own layer and no blur.

Changed since CI run 39088367495: the tables `oP` and `oU` changed (raster, see `crOrigPasses`, `crOrigUnits`).

What one scrolled frame of the original costs Chromium, stage by stage. -/
theorem cr_orig_exact (m : CrMode) (l : Bool) (N : Nat) (lo : LayerState) (r : Bool) (s : Stage) :
    (frameWork (chromiumAt m) (crOrig l N lo r)).passes s = crOrigPasses r s ∧
      (frameWork (chromiumAt m) (crOrig l N lo r)).units s = crOrigUnits l N lo r s := by
  have hc : ∀ i, crStagesOf ⟨4 + i, .custom exitVar [.opacity, .transform], lo⟩ = readerStages lo false :=
    fun i => reader_stages _ _ lo l (by simp)
  have h2 : crStagesOf ⟨2, .custom exitVar (copyReaders l), lo⟩ = readerStages lo (!l) := by
    rw [reader_stages 2 (copyReaders l) lo l (by simp)]; cases l <;> rfl
  have h3 : crStagesOf ⟨3, .custom exitVar (cueReaders l), lo⟩ = readerStages lo true := by
    rw [reader_stages 3 (cueReaders l) lo l (by simp)]; cases l <;> rfl
  have h1 : crStagesOf ⟨1, .custom exitVar [], lo⟩ = [.style] := by cases lo <;> rfl
  have hs : crStagesOf (scrollC r) = scrollStages r := rfl
  have hm : ∀ t, t ∈ ((List.range N).map fun i =>
      (⟨4 + i, .custom exitVar [.opacity, .transform], lo⟩ : Change CrProp)).flatMap crStagesOf →
      t ∈ readerStages lo false := by
    intro t ht
    simp only [List.mem_flatMap, List.mem_map] at ht
    obtain ⟨_, ⟨i, _, rfl⟩, h⟩ := ht
    rwa [hc i] at h
  have hp : (frameWork (chromiumAt m) (crOrig l N lo r)).passes s =
      if s ∈ (crOrigChanges l N lo r).flatMap crStagesOf ++ [.props, .script] then 1 else 0 := by
    simp [frameWork, touched, crOrig, jsWrite, FrameIn.updates, chromiumAt]
    cases s <;> simp [forcedPasses]
  have hu : (frameWork (chromiumAt m) (crOrig l N lo r)).units s =
      (crOrigChanges l N lo r).countP (fun c => decide (s ∈ crStagesOf c)) + (if s = .script then 1 else 0) := by
    simp [frameWork, stageUnits, crOrig, jsWrite, chromiumAt]
    by_cases h : s ∈ crCompStages m <;> simp [h] <;> first | rfl | congr
  have hmem : s ∈ (crOrigChanges l N lo r).flatMap crStagesOf ++ [.props, .script] ↔
      (s = .style ∨ s ∈ readerStages lo (!l) ∨ s ∈ readerStages lo true ∨ s ∈ scrollStages r ∨ s = .props ∨
        s = .script) := by
    have := hm s
    simp only [crOrigChanges, List.flatMap_append, List.flatMap_cons, List.flatMap_nil, List.mem_append,
      List.mem_cons, List.mem_nil_iff, h1, h2, h3, hs, or_false, List.append_nil]
    have hrs : s ∈ readerStages lo false → s ∈ readerStages lo true := by
      cases lo <;> cases s <;> decide
    grind
  rw [hp, hu]
  simp only [hmem]
  simp only [crOrigChanges, List.countP_append, List.countP_cons, List.countP_nil, List.countP_map,
    Function.comp_def, h1, h2, h3, hc, hs]
  clear hp hu hmem hm hc h1 h2 h3 hs
  cases l <;> cases lo <;> cases r <;> cases s <;>
    simp [readerStages, scrollStages, crOrigPasses, crOrigUnits, blurs] <;> omega

/-- The variant's passes per stage in a scrolled frame. The main-thread blur animations re-raster their own layers.

Changed since CI run 39088367495: the raster pass was `[r]` (a blur on an own layer was a property-tree update).

The variant's stage passes in one scrolled frame. -/
def crVarPasses (r : Bool) : Stage → Nat
  | .script => 0 | .style => 1 | .layout => 0 | .props => 1
  | .paint => if r then 1 else 0
  | .raster => 1
  | .commit => 1 | .comp => 1

/-- The variant's units per stage in a scrolled frame, with `b = 1 + [¬ℓ]` blur animations on main,
`c = 2N + 4 − [¬ℓ]` compositor animations (one per CSS animation name), and the
ride-along `ε = [m.everyBeginFrameIsMainFrame] c`.

Changed since CI run 39088367495: the raster units were `[r]`; each blur animation now adds one.

The variant's stage units in one scrolled frame. -/
def crVarUnits (m : CrMode) (l : Bool) (N : Nat) (r : Bool) : Stage → Nat :=
  let b := if l then 1 else 2
  let c := 2 * N + (if l then 4 else 3)
  let e := if m.everyBeginFrameIsMainFrame then c else 0
  fun
  | .script => 0 | .style => b + e | .layout => 0 | .props => b + 1 + e
  | .paint => if r then 1 else 0
  | .raster => b + (if r then 1 else 0)
  | .commit => b + 1 | .comp => c

theorem cr_var_exact (m : CrMode) (l : Bool) (N : Nat) (r : Bool) (hm : m.threadedAnim = true) (s : Stage) :
    (frameWork (chromiumAt m) (crVar m l N r)).passes s = crVarPasses r s ∧
      (frameWork (chromiumAt m) (crVar m l N r)).units s = crVarUnits m l N r s := by
  rw [crVar_eq m l N r hm]
  cases l <;> cases r <;> cases he : m.everyBeginFrameIsMainFrame <;> cases s <;>
    simp [frameWork, touched, stageUnits, forcedPasses, FrameIn.updates, chromiumAt, crStagesOf, crLevel, keyLevel,
      CrLevel.stages, CrProp.extra, scrollStages, scrollC, crCompStages, crVarPasses, crVarUnits, he] <;> omega

/-- **Real Chrome: a trade.** With the main thread asleep between compositor frames, the variant's scrolled frame does
strictly less main-thread work than the original's (no script, and no more passes or units on any main-thread stage),
but it adds a compositor pass the original does not have. So the variant does not dominate; it moves work to the compositor.

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
      simp_all [crVarPasses, crVarUnits, crOrigPasses, crOrigUnits, blurs, realChrome] <;> omega
  · simp [frameWork, crVar, crOrig, animFrame, jsWrite]
  · left; rw [(hv .script).1, (ho .script).1]; simp [crVarPasses, crOrigPasses]

theorem cr_lane_mixed (l : Bool) (N : Nat) (lo : LayerState) (r : Bool) :
    let V := frameWork (chromiumAt lane) (crVar lane l N r)
    let O := frameWork (chromiumAt lane) (crOrig l N lo r)
    (∀ s, s ≠ .style → s ≠ .props → s ≠ .comp → V.passes s ≤ O.passes s ∧ V.units s ≤ O.units s) ∧
      V.passes .style = O.passes .style ∧ V.passes .props = O.passes .props ∧
      V.units .props = O.units .props + (N + 3) ∧
      V.units .style = O.units .style + (N + 2) ∧ V.passes .script < O.passes .script ∧
      V.passes .comp = 1 ∧ O.passes .comp = 0 := by
  intro V O
  have hv := cr_var_exact lane l N r rfl
  have ho := cr_orig_exact lane l N lo r
  refine ⟨fun s _ _ _ => ?_, ?_, ?_, ?_, ?_, ?_, (hv .comp).1, (ho .comp).1⟩
  · show (frameWork _ _).passes s ≤ (frameWork _ _).passes s ∧ (frameWork _ _).units s ≤ (frameWork _ _).units s
    rw [(hv s).1, (hv s).2, (ho s).1, (ho s).2]
    cases l <;> cases lo <;> cases r <;> cases s <;>
      simp_all [crVarPasses, crVarUnits, crOrigPasses, crOrigUnits, blurs, lane] <;> omega
  · show (frameWork _ _).passes _ = (frameWork _ _).passes _
    rw [(hv _).1, (ho _).1]; rfl
  · show (frameWork _ _).passes _ = (frameWork _ _).passes _
    rw [(hv _).1, (ho _).1]; rfl
  · show (frameWork _ _).units _ = (frameWork _ _).units _ + _
    rw [(hv _).2, (ho _).2]; cases l <;> simp [crVarUnits, crOrigUnits, lane] <;> omega
  · show (frameWork _ _).units _ = (frameWork _ _).units _ + _
    rw [(hv _).2, (ho _).2]; cases l <;> simp [crVarUnits, crOrigUnits, lane] <;> omega
  · show (frameWork _ _).passes _ < (frameWork _ _).passes _
    rw [(hv _).1, (ho _).1]; simp [crVarPasses, crOrigPasses]

theorem cr_lane_style_elems (l : Bool) (N : Nat) (lo : LayerState) (r : Bool) :
    (∀ e ∈ (crAnims l N).map CrAnim.elem, e ∈ (crOrigChanges l N lo r).map Change.elem) ∧
      1 ∈ (crOrigChanges l N lo r).map Change.elem ∧ 1 ∉ (crAnims l N).map CrAnim.elem := by
  have hm : (crAnims l N).map CrAnim.elem = (exitAnims l N).map Prod.fst := by
    simp [crAnims, sAnim, Function.comp_def]
  have hc : ∀ e, e ∈ ((List.range N).map
      (fun i => (⟨4 + i, .custom exitVar [.opacity, .transform], lo⟩ : Change CrProp))).map Change.elem ↔
      4 ≤ e ∧ e < 4 + N := by
    intro e
    simp only [List.map_map, Function.comp_def, List.mem_map, List.mem_range]
    constructor
    · rintro ⟨a, ha, rfl⟩; omega
    · intro h; exact ⟨e - 4, by omega, by omega⟩
  rw [hm]
  simp only [exitAnims_eq, crOrigChanges, List.map_append, List.mem_append, mem_cardAnims_fst, hc]
  cases l <;> simp [headAnims, scrollC] <;> omega

end Cr

/-! ## Work on WebKit -/

section Wk
open Fw.Engine.WebKit

/-- A consumer's animation on WebKit: a scroll timeline with linear easing, otherwise clean (no blocker, not pending,
asynchronous scroller, two keyframes).
-/
def wkAnim (ps : List CssProp) : WkAnim := { WkAnim.clean ps .scroll with easing := .linear }

def wkProp : AnimProp → CssProp
  | .opacity => .opacity | .transform => .transform | .translate => .translate | .blur => .filter

def wkAnims (l : Bool) (N : Nat) : List WkAnim := (exitAnims l N).map fun p => wkAnim [wkProp p.2]

theorem wkAnims_length (l : Bool) (N : Nat) : (wkAnims l N).length = animCount l N := by
  simp [wkAnims, animCount]

theorem wkAnims_mem (l : Bool) (N : Nat) (a : WkAnim) (ha : a ∈ wkAnims l N) : ∃ p, a = wkAnim [wkProp p] := by
  simp only [wkAnims, List.mem_map] at ha
  obtain ⟨q, _, rfl⟩ := ha
  exact ⟨q.2, rfl⟩

theorem wk_anim_comp (m : WkMode) (hm : m.threadedScrollDriven = true) (p : AnimProp) :
    wkThread m (wkAnim [wkProp p]) = .comp := by
  obtain ⟨tsd, ttb, path⟩ := m
  simp only at hm
  subst hm
  cases p <;> cases ttb <;> cases path <;> decide

theorem wk_all_comp (m : WkMode) (hm : m.threadedScrollDriven = true) (l : Bool) (N : Nat) :
    ∀ a ∈ wkAnims l N, wkThread m a = .comp := by
  intro a ha
  obtain ⟨p, rfl⟩ := wkAnims_mem l N a ha
  exact wk_anim_comp m hm p

/-- **The premise is needed:** with threaded scroll-driven animations off (the legacy path accepts only time
timelines), every animation of the variant runs on the main thread.

Without the threaded path the variant gains nothing on WebKit. -/
theorem wk_legacy_main (m : WkMode) (hm : m.threadedScrollDriven = false) (l : Bool) (N : Nat) :
    ∀ a ∈ wkAnims l N, wkThread m a = .main := by
  intro a ha
  obtain ⟨tsd, ttb, path⟩ := m
  simp only at hm
  subst hm
  obtain ⟨p, rfl⟩ := wkAnims_mem l N a ha
  cases p <;> cases ttb <;> cases path <;> decide

/-! ### The variant's frames on the extended engine (`webkitX`, after the WKTR fixtures)

The first version modelled the variant's scrolled frame as `scrollStep (compFrame (N + 3))`: compositor ticks only, no
web-process style. The WKTR fixtures (task wktr-p1p4, premise `WktrStyleRate.Holds`) measured one style recalc per
rendering update for an accelerated animation on a scroll timeline, so the frame is rebuilt here with
`Fw.Engine.WebKit.withAnim`: each accelerated scroll-driven animation adds one compositor animation and, in a frame
with a rendering update, one `restyle` of its target. -/

def wkTargets (l : Bool) (N : Nat) : List Nat := (exitAnims l N).map Prod.fst

theorem wkTargets_length (l : Bool) (N : Nat) : (wkTargets l N).length = animCount l N := by
  simp [wkTargets, animCount]

def cssWk : CssProp → Option WkProp
  | .opacity => some .opacity
  | .transform => some .transform
  | .translate => some .transform
  | .filter => some .filter
  | _ => none

/-- What animation `a` on element `e` writes when it runs on the main thread: one change per animated property, with
the element on its own layer.
-/
def wkMain (e : Nat) (a : WkAnim) : List (Change WkPropX) :=
  a.props.filterMap fun p => (cssWk p).map fun q => ⟨e, .base q, .own⟩

/-- Add one animation `(e, a)` to a frame (`withAnim` with no scheduled document timeline). -/
def wkStep (m : WkMode) (f : FrameIn WkPropX) (p : Nat × WkAnim) : FrameIn WkPropX :=
  withAnim m p.2 p.1 .own (wkMain p.1 p.2) f false

/-- The frame `f` with all animations of the variant added, in order. -/
def wkWith (m : WkMode) (l : Bool) (N : Nat) (f : FrameIn WkPropX) : FrameIn WkPropX :=
  ((wkTargets l N).zip (wkAnims l N)).foldl (wkStep m) f

def wkVar (m : WkMode) (l : Bool) (N : Nat) : FrameIn WkPropX :=
  wkWith m l N (scrollStepX emptyX)

/-- **The variant's idle frame on WebKit**: no scroll, no change, only the animations (no rendering update). -/
def wkIdle (m : WkMode) (l : Bool) (N : Nat) : FrameIn WkPropX :=
  wkWith m l N emptyX

/-- Adding accelerated scroll-driven animations to a frame: each adds one compositor animation, and one `restyle` of
its target exactly when the frame has a rendering update.

The ride-along of `withAnim`, summed over a list of animations. -/
theorem foldl_wkStep (m : WkMode) (ps : List (Nat × WkAnim))
    (hps : ∀ p ∈ ps, wkThread m p.2 = .comp ∧ p.2.timeline = .scroll) (f : FrameIn WkPropX) :
    ps.foldl (wkStep m) f =
      ⟨f.script, f.forcedStyle, f.forcedLayout, f.hits,
        f.changes ++ (if f.updates then ps.map (fun p => ⟨p.1, .restyle, .own⟩) else []),
        f.compAnims + ps.length⟩ := by
  induction ps generalizing f with
  | nil => cases f; simp
  | cons p ps ih =>
    obtain ⟨hc, ht⟩ := hps p (List.mem_cons_self ..)
    rw [List.foldl_cons, ih (fun q hq => hps q (List.mem_cons_of_mem _ hq))]
    cases f with
    | mk sc fs fl hi ch ca =>
      cases hu : (FrameIn.updates ⟨sc, fs, fl, hi, ch, ca⟩ : Bool) <;>
        simp_all [wkStep, withAnim, wkTicks, FrameIn.updates] <;> omega

/-- Every animation of the variant, paired with its target, is accelerated and scroll-driven when threaded
scroll-driven animations are on.

The hypothesis of `foldl_wkStep` holds for the variant. -/
theorem wkPairs_comp (m : WkMode) (hm : m.threadedScrollDriven = true) (l : Bool) (N : Nat) :
    ∀ p ∈ (wkTargets l N).zip (wkAnims l N), wkThread m p.2 = .comp ∧ p.2.timeline = .scroll := by
  intro p hp
  have ha : p.2 ∈ wkAnims l N := (List.of_mem_zip hp).2
  refine ⟨wk_all_comp m hm l N p.2 ha, ?_⟩
  obtain ⟨q, h⟩ := wkAnims_mem l N p.2 ha
  rw [h]; rfl

theorem wkVar_eq (m : WkMode) (hm : m.threadedScrollDriven = true) (l : Bool) (N : Nat) :
    wkVar m l N = ⟨0, 0, 0, 0, ⟨0, .base .scrollPos, .none⟩ :: (wkTargets l N).map (fun e => ⟨e, .restyle, .own⟩),
      animCount l N⟩ := by
  have hz : ((wkTargets l N).zip (wkAnims l N)).map (fun p => (⟨p.1, .restyle, .own⟩ : Change WkPropX)) =
      (wkTargets l N).map (fun e => ⟨e, .restyle, .own⟩) := by
    have hf := List.map_fst_zip (l₁ := wkTargets l N) (l₂ := wkAnims l N)
      (by simp [wkTargets_length, wkAnims_length])
    calc ((wkTargets l N).zip (wkAnims l N)).map (fun p => (⟨p.1, .restyle, .own⟩ : Change WkPropX))
        = (((wkTargets l N).zip (wkAnims l N)).map Prod.fst).map
            (fun e => (⟨e, .restyle, .own⟩ : Change WkPropX)) := by rw [List.map_map]; rfl
      _ = _ := by rw [hf]
  rw [wkVar, wkWith, foldl_wkStep m _ (wkPairs_comp m hm l N)]
  simp [scrollStepX, emptyX, FrameIn.updates, hz, List.length_zip, wkTargets_length, wkAnims_length]

theorem wkIdle_eq (m : WkMode) (hm : m.threadedScrollDriven = true) (l : Bool) (N : Nat) :
    wkIdle m l N = liftWkFrame (compFrame (animCount l N)) := by
  rw [wkIdle, wkWith, foldl_wkStep m _ (wkPairs_comp m hm l N)]
  simp [emptyX, FrameIn.updates, liftWkFrame, compFrame, List.length_zip, wkTargets_length, wkAnims_length]

theorem wk_var_exact (μ : WktrStyleRate) (hμ : μ.Holds) (m : WkMode) (hm : m.threadedScrollDriven = true) (l : Bool)
    (N : Nat) (s : Stage) :
    (frameWork (webkitX m) (wkVar m l N)).passes s =
        (if s = .commit ∨ s = .comp then 1 else if s = .style then μ.timeline else 0) ∧
      (frameWork (webkitX m) (wkVar m l N)).units s = (if s = .style ∨ s = .comp then animCount l N else 0) := by
  obtain ⟨_, h1, _⟩ := hμ
  rw [h1, wkVar_eq m hm l N]
  have h0 : wkStages ⟨0, .scrollPos, .none⟩ = [] := scrollPos_stages m 0 .none
  have hfm : ((⟨0, .base .scrollPos, .none⟩ : Change WkPropX) ::
      (wkTargets l N).map (fun e => ⟨e, .restyle, .own⟩)).flatMap wkStagesOfX =
      (wkTargets l N).flatMap (fun _ => [Stage.style]) := by
    simp [wkStagesOfX, h0, List.flatMap_map]
  have hne : Stage.style ∈ (wkTargets l N).flatMap (fun _ => [Stage.style]) := by
    simp [List.mem_flatMap]; exact ⟨2, by cases l <;> simp [wkTargets, exitAnims_eq, headAnims]⟩
  have hsub : ∀ t, t ∈ (wkTargets l N).flatMap (fun _ => [Stage.style]) → t = .style := by
    intro t ht; simp [List.mem_flatMap] at ht; exact ht.2
  cases s <;> simp only [frameWork, touched, stageUnits, forcedPasses, FrameIn.updates, webkitX, hfm] <;>
    simp [h0, wkStagesOfX, hne, Function.comp_def, wkTargets_length] <;>
    (try intro h; exact absurd (hsub _ h) (by decide)) <;> cases l <;> simp [animCount, exitAnims_eq, headAnims]

/-- No WebKit style change dirties the compositor stage.

The web process never runs compositor work for a style change. -/
theorem comp_not_diff (d : Diff) : Stage.comp ∉ diffStages d := by
  cases d <;> simp [diffStages]

def wkOrigChanges (l : Bool) (N : Nat) (lo : LayerState) : List (Change WkProp) :=
  [⟨2, .opacity, lo⟩, ⟨2, .transform, lo⟩] ++ (if l then [] else [⟨2, .filter, lo⟩]) ++
    [⟨3, .opacity, lo⟩, ⟨3, .filter, lo⟩] ++ (if l then [⟨3, .transform, lo⟩] else []) ++
    (List.range N).flatMap (fun i => [⟨4 + i, .opacity, lo⟩, ⟨4 + i, .transform, lo⟩])

theorem wkOrigChanges_length (l : Bool) (N : Nat) (lo : LayerState) : (wkOrigChanges l N lo).length = 2 * N + 5 := by
  have h : ((List.range N).flatMap
      (fun i => ([⟨4 + i, .opacity, lo⟩, ⟨4 + i, .transform, lo⟩] : List (Change WkProp)))).length = 2 * N := by
    induction N with
    | zero => rfl
    | succ n ih => rw [List.range_succ, List.flatMap_append, List.length_append, ih]; simp; omega
  cases l <;> simp [wkOrigChanges, h] <;> omega

/-- Every change of the original dirties `style` on WebKit, at any layer state.

Each consumer's opacity, transform or filter change is restyled when the targets have a layer. Changed since CI run
39088367495: a filter change now lays out on every layer state (it was `equal` on a box without a layer), so the
hypothesis is no longer needed; it is kept so the callers stay as they were. -/
theorem wkOrig_style (m : WkMode) (l : Bool) (N : Nat) (lo : LayerState) (hlo : lo ≠ .none) :
    ∀ c ∈ wkOrigChanges l N lo, Stage.style ∈ (webkitAt m).stagesOf c := by
  have hp : ∀ c : Change WkProp, c.layer ≠ .none → (c.prop = .opacity ∨ c.prop = .transform ∨ c.prop = .filter) →
      Stage.style ∈ (webkitAt m).stagesOf c := by
    intro ⟨e, p, l'⟩ hl hp
    simp only [webkitAt]; rw [mem_wkStages_of_ne _ (by decide)]
    show Stage.style ∈ diffStages (wkDiff ⟨0, p, l'⟩)
    simp only at hp hl
    rcases hp with rfl | rfl | rfl <;> cases l' <;> first | decide | exact absurd rfl hl
  intro c hc
  refine hp c ?_ ?_ <;> cases l <;> simp [wkOrigChanges] at hc <;> grind

theorem wk_trade (μ : WktrStyleRate) (hμ : μ.Holds) (m : WkMode) (hm : m.threadedScrollDriven = true) (l : Bool)
    (N : Nat) (lo : LayerState) (hlo : lo ≠ .none) :
    let V := frameWork (webkitX m) (wkVar m l N)
    let O := frameWork (webkitAt m) (scrollStep (jsFrame (wkOrigChanges l N lo)))
    mainLt V O ∧ V.units .style = O.units .style ∧ V.passes .comp = 1 ∧ V.units .comp = animCount l N ∧
      O.passes .comp = 0 ∧ O.units .comp = 0 := by
  intro V O
  have hv := wk_var_exact μ hμ m hm l N
  have h1 : μ.timeline = 1 := hμ.2.1
  have hoc : O.passes .commit = 1 := scroll_commit m _
  have hos : O.passes .script = 1 := by
    show (frameWork _ _).passes _ = _
    simp [frameWork, touched, forcedPasses, scrollStep, jsFrame]
  have hsty := wkOrig_style m l N lo hlo
  have hne : wkOrigChanges l N lo ≠ [] := by
    intro h; have := wkOrigChanges_length l N lo; rw [h] at this; simp at this
  have hosp : O.passes .style = 1 := by
    show (frameWork _ _).passes _ = _
    obtain ⟨c, hc⟩ := List.exists_mem_of_ne_nil _ hne
    have : Stage.style ∈ touched (webkitAt m) (scrollStep (jsFrame (wkOrigChanges l N lo))) := by
      simp only [touched, scrollStep, jsFrame, List.mem_append, List.flatMap_cons, List.mem_flatMap]
      exact Or.inl (Or.inl (Or.inl (Or.inr ⟨c, hc, hsty c hc⟩)))
    show (if Stage.style ∈ touched (webkitAt m) (scrollStep (jsFrame (wkOrigChanges l N lo))) then 1 else 0) +
      forcedPasses (scrollStep (jsFrame (wkOrigChanges l N lo))) .style = 1
    simp only [this, ↓reduceIte]; rfl
  have hosu : O.units .style = 2 * N + 5 := by
    show stageUnits _ _ _ = _
    have hsp : (webkitAt m).stagesOf ⟨0, .scrollPos, .none⟩ = [] := scrollPos_stages m 0 .none
    simp only [stageUnits, scrollStep, jsFrame, List.countP_cons, hsp, List.not_mem_nil, decide_false,
      Bool.false_eq_true, ↓reduceIte, Nat.add_zero]
    rw [List.countP_eq_length.mpr (fun c hc => by simpa using hsty c hc), wkOrigChanges_length]
    simp [webkitAt]
  have hnc : ∀ c : Change WkProp, Stage.comp ∉ wkStages c := fun c => by
    rw [mem_wkStages_of_ne c (by decide)]; exact comp_not_diff _
  have hop : O.passes .comp = 0 := by
    show (frameWork _ _).passes _ = _
    simp [frameWork, touched, forcedPasses, scrollStep, jsFrame, webkitAt, FrameIn.updates, hnc]
  have hou : O.units .comp = 0 := by
    show (frameWork _ _).units _ = _
    simp [frameWork, stageUnits, scrollStep, jsFrame, webkitAt, hnc]
  refine ⟨⟨⟨fun s hs => ?_, ?_⟩, .script, by decide, ?_⟩, ?_, (hv .comp).1, (hv .comp).2, hop, hou⟩
  · show (frameWork _ _).passes s ≤ O.passes s ∧ (frameWork _ _).units s ≤ O.units s
    rw [(hv s).1, (hv s).2, h1]
    by_cases hc : s = .commit
    · subst hc; simp [hoc]
    · by_cases hy : s = .style
      · subst hy; simp [hosp, hosu, animCount_eq]
      · simp [hc, hs, hy]
  · show (frameWork _ _).hits ≤ (frameWork _ _).hits
    simp [frameWork, wkVar_eq m hm l N, scrollStep, jsFrame]
  · left
    show (frameWork _ _).passes _ < O.passes _
    rw [(hv _).1, hos]; simp
  · show (frameWork _ _).units _ = O.units _
    rw [(hv _).2, hosu]; simp [animCount_eq]

theorem wk_style_elems (l : Bool) (N : Nat) (lo : LayerState) (e : Nat) :
    e ∈ wkTargets l N ↔ e ∈ (wkOrigChanges l N lo).map Change.elem := by
  have hc : e ∈ ((List.range N).flatMap
      (fun i => ([⟨4 + i, .opacity, lo⟩, ⟨4 + i, .transform, lo⟩] : List (Change WkProp)))).map Change.elem ↔
      4 ≤ e ∧ e < 4 + N := by
    simp only [List.map_flatMap, List.map_cons, List.map_nil, List.mem_flatMap, List.mem_range, List.mem_cons,
      List.not_mem_nil, or_false, or_self]
    constructor
    · rintro ⟨a, ha, rfl⟩; omega
    · intro h; exact ⟨e - 4, by omega, by omega⟩
  simp only [wkTargets, exitAnims_eq, wkOrigChanges, List.map_append, List.mem_append, mem_cardAnims_fst, hc]
  cases l <;> simp [headAnims] <;> omega

/-- **The earlier trade "for any change list" is false.** Under the measured premise, against a scrolled frame whose
callback writes nothing, the variant does **more** main-thread work: its ride-along style pass (`1 > 0`).

The variant's style floor makes the trade depend on what the original writes (a negative result of the fixtures). -/
theorem wk_trade_not_general (μ : WktrStyleRate) (hμ : μ.Holds) (m : WkMode) (hm : m.threadedScrollDriven = true)
    (l : Bool) (N : Nat) :
    ¬ mainLe (frameWork (webkitX m) (wkVar m l N)) (frameWork (webkitAt m) (scrollStep (jsFrame []))) := by
  intro ⟨h, _⟩
  have hv := (wk_var_exact μ hμ m hm l N .style).1
  have h1 : μ.timeline = 1 := hμ.2.1
  have hle := (h .style (by decide)).1
  rw [hv, h1] at hle
  have hsp : (webkitAt m).stagesOf ⟨0, .scrollPos, .none⟩ = [] := scrollPos_stages m 0 .none
  have h0 : (frameWork (webkitAt m) (scrollStep (jsFrame []))).passes .style = 0 := by
    have hsp' : wkStages ⟨0, .scrollPos, .none⟩ = [] := hsp
    simp [frameWork, touched, forcedPasses, scrollStep, jsFrame, hsp', webkitAt, FrameIn.updates]
  rw [h0] at hle
  simp at hle

end Wk

/-! ## Golden rows (`engine-check` schema) -/

/-- One golden row: engine, scenario, variant, stage, prediction against the base `original`, count type. -/
structure GRow where
  engine     : String
  scenario   : String
  variant    : String
  stage      : String
  prediction : String
  countType  : String
deriving Repr, DecidableEq

/-- The JSON line of a row (keys sorted, `base` = `original`). -/
def GRow.json (r : GRow) : String :=
  (Lean.Json.mkObj [("base", .str "original"), ("countType", .str r.countType), ("engine", .str r.engine),
    ("prediction", .str r.prediction), ("scenario", .str r.scenario), ("stage", .str r.stage),
    ("variant", .str r.variant)]).compress

/-- **The prediction of one stage over a frame sequence** of (variant, original) work pairs: `<o` when the variant's
passes and units are at most the original's in every frame and its passes are strictly fewer in some frame; `≤o` when
only the first holds; `any` otherwise. Counts are whole-page, so the rule never predicts `=0` or `=o`. An empty `F` gives `≤o`.
-/
def framePred (fr : List (Work × Work)) (s : Stage) : String :=
  if fr.all (fun p => decide (p.1.passes s ≤ p.2.passes s ∧ p.1.units s ≤ p.2.units s)) then
    if fr.any (fun p => decide (p.1.passes s < p.2.passes s)) then "<o" else "≤o"
  else "any"

/-- The empty work (a test value for `framePred`). -/
def zeroWork : Work := ⟨fun _ => 0, fun _ => 0, 0⟩

/-- A work with one pass and one unit at `script` (a test value for `framePred`). -/
def scriptWork : Work := ⟨fun s => if s = .script then 1 else 0, fun s => if s = .script then 1 else 0, 0⟩

#guard framePred [(zeroWork, scriptWork)] .script == "<o"
#guard framePred [(zeroWork, scriptWork), (zeroWork, zeroWork)] .script == "<o"
#guard framePred [(zeroWork, zeroWork)] .script == "≤o"
#guard framePred [] .script == "≤o"
#guard framePred [(scriptWork, zeroWork)] .script == "any"
#guard framePred [(zeroWork, scriptWork), (scriptWork, zeroWork)] .script == "any"

/-- The golden scenario: the Chromium lane profile `swipe-v1` (430 px, phone band). -/
def gScenario : String := "swipe-v1"

/-- The variant's name. -/
def gVariant : String := "hero-exit-threaded"

/-- The golden band: the phone band, since `swipe-v1` is 430 px wide. -/
def gBand : Bool := true

/-- Number of cards in the golden setting. -/
def gN : Nat := 4

/-- **Chromium lane frames**: a scrolled frame and an idle frame (original: nothing; variant: the compositor
animations alone, which in the lane ride along a main frame).
-/
def crFrames : List (Work × Work) :=
  let E := Chromium.chromiumAt Chromium.lane
  let v := crVar Chromium.lane gBand gN false
  [(frameWork E v, frameWork E (crOrig gBand gN .layer false)),
    (frameWork E ⟨0, 0, 0, 0, [], v.compAnims⟩, frameWork E (⟨0, 0, 0, 0, [], 0⟩ : FrameIn Chromium.CrProp))]

/-- **WebKit frames** (Safari mode): a scrolled frame and an idle frame (original: nothing; variant: its animations
with no rendering update). The variant's frames use the extended engine `webkitX`, so the scrolled frame carries the
measured ride-along restyle (`wk_var_exact`); the original's use `webkitAt` (equal on lifted frames, `webkitX_lift`).
-/
def wkFrames : List (Work × Work) :=
  let E := WebKit.webkitAt WebKit.WkMode.safari
  let EX := WebKit.webkitX WebKit.WkMode.safari
  let cs := wkOrigChanges gBand gN .layer
  [(frameWork EX (wkVar WebKit.WkMode.safari gBand gN), frameWork E (WebKit.scrollStep (WebKit.jsFrame cs))),
    (frameWork EX (wkIdle WebKit.WkMode.safari gBand gN), frameWork E (⟨0, 0, 0, 0, [], 0⟩ : FrameIn WebKit.WkProp))]

/-- The Chromium count types per stage; `paint` keeps only `trace.Paint`, since the raster counts belong to
`raster`.
-/
def crCounts (s : Stage) : List String :=
  if s = .paint then ["trace.Paint"] else Chromium.stageCounts s

/-- **Golden rows.** Chromium: every stage and count type; `props` (lifecycle frames) and `comp` (layer census) are
`any`. WebKit: the Simulator and WKTR count types.

Each row is (engine, scenario, variant, stage name, prediction, count type).
-/
def goldenRows : List GRow :=
  let stages : List Stage := [.script, .style, .layout, .props, .paint, .raster, .commit, .comp]
  let cr := stages.flatMap fun s =>
    let p := if s = .props ∨ s = .comp then "any" else framePred crFrames s
    (crCounts s).map fun k => ⟨"chromium", gScenario, gVariant, Chromium.stageName s, p, k⟩
  let wk := (WebKit.Lane.counts .sim ++ WebKit.Lane.counts .wktr).map fun (s, k) =>
    ⟨"webkit", gScenario, gVariant, WebKit.stageName s, framePred wkFrames s, k⟩
  cr ++ wk

/-- The rows as JSON lines (`packages/contracts/golden/engine/hero-exit.jsonl`). -/
def goldenJsonl : String := String.join (goldenRows.map fun r => r.json ++ "\n")

/-- The prediction of the first row with engine `e` and count type `k` (`?` if there is none). -/
def gPred (e k : String) : String :=
  ((goldenRows.find? fun r => r.engine == e && r.countType == k).map (·.prediction)).getD "?"

#guard goldenRows.length == 20
-- Chromium lane: the script is gone. The raster pass stays (since CI run 39088367495 a blur value change rasters even
-- on an own layer, MEASURED), with fewer units (the blurred consumers only), so raster is `≤o`, no longer `<o`.
#guard gPred "chromium" "trace.FireAnimationFrame" == "<o" && gPred "chromium" "raster.invalidationRects" == "≤o"
#guard gPred "chromium" "trace.UpdateLayoutTree" == "any" && gPred "chromium" "trace.Layout" == "≤o"
#guard gPred "chromium" "trace.cc.Commit" == "≤o" && gPred "chromium" "trace.Paint" == "≤o"
#guard gPred "chromium" "trace.PrePaint" == "any" && gPred "chromium" "census.layers" == "any"
#guard gPred "webkit" "FireAnimationFrame" == "<o" && gPred "webkit" "RecalculateStyles" == "≤o"
#guard gPred "webkit" "Layout" == "<o" && gPred "webkit" "Paint" == "<o" && gPred "webkit" "Composite" == "≤o"
#guard gPred "webkit" "styleRecalcs" == "≤o" && gPred "webkit" "layoutUpdates" == "<o"
-- Since CI run 39088367495 the original's opacity and transform changes on a shared layer pay a compositing update
-- (the compositing table, `wkCompUpdate`) and the variant's do not, so compositing updates are `<o` (were `≤o`).
#guard gPred "webkit" "compositingUpdates" == "<o" && gPred "webkit" "renderingUpdates" == "≤o"
#guard gPred "webkit" "x" == "?"

/-! ## Under the frame-end pass (`frameWorkE`, ledger n=1)

Neither arm reads layout or style: the original's scroll callback only writes. So every stage either frame touches
ends dirty, `frameWorkE` equals `frameWork` (`Fw.Parts.EndFlags.frameWorkE_eq_of_dirty`), and both trades carry over
unchanged. -/

section EndPass

open Fw.Parts.EndFlags Fw.Engine.Chromium Fw.Engine.WebKit

/-- **Real Chrome under `frameWorkE`: still a trade.**

The frame-end pass changes nothing on frames without reads. -/
theorem cr_real_tradeE (l : Bool) (N : Nat) (lo : LayerState) (r : Bool) (ev eo : Stage → Bool)
    (hv : ∀ s, s ∈ touched (chromiumAt realChrome) (crVar realChrome l N r) → ev s = true)
    (ho : ∀ s, s ∈ touched (chromiumAt realChrome) (crOrig l N lo r) → eo s = true) :
    mainLt (frameWorkE (chromiumAt realChrome) (crVar realChrome l N r) ev)
      (frameWorkE (chromiumAt realChrome) (crOrig l N lo r) eo) ∧
    (frameWorkE (chromiumAt realChrome) (crVar realChrome l N r) ev).passes .comp = 1 ∧
    (frameWorkE (chromiumAt realChrome) (crOrig l N lo r) eo).passes .comp = 0 := by
  rw [frameWorkE_eq_of_dirty _ _ ev hv, frameWorkE_eq_of_dirty _ _ eo ho]
  exact cr_real_trade l N lo r

/-- **WebKit under `frameWorkE`: still a trade** for the original's own change list, under the measured premise.

Safari's trade does not depend on the frame-end pass either. -/
theorem wk_tradeE (μ : WktrStyleRate) (hμ : μ.Holds) (m : WkMode) (hm : m.threadedScrollDriven = true) (l : Bool)
    (N : Nat) (lo : LayerState) (hlo : lo ≠ .none) (ev eo : Stage → Bool)
    (hv : ∀ s, s ∈ touched (webkitX m) (wkVar m l N) → ev s = true)
    (ho : ∀ s, s ∈ touched (webkitAt m) (scrollStep (jsFrame (wkOrigChanges l N lo))) → eo s = true) :
    mainLt (frameWorkE (webkitX m) (wkVar m l N) ev)
      (frameWorkE (webkitAt m) (scrollStep (jsFrame (wkOrigChanges l N lo))) eo) ∧
    (frameWorkE (webkitX m) (wkVar m l N) ev).units .style =
      (frameWorkE (webkitAt m) (scrollStep (jsFrame (wkOrigChanges l N lo))) eo).units .style ∧
    (frameWorkE (webkitX m) (wkVar m l N) ev).passes .comp = 1 ∧
    (frameWorkE (webkitX m) (wkVar m l N) ev).units .comp = animCount l N ∧
    (frameWorkE (webkitAt m) (scrollStep (jsFrame (wkOrigChanges l N lo))) eo).passes .comp = 0 ∧
    (frameWorkE (webkitAt m) (scrollStep (jsFrame (wkOrigChanges l N lo))) eo).units .comp = 0 := by
  rw [frameWorkE_eq_of_dirty _ _ ev hv, frameWorkE_eq_of_dirty _ _ eo ho]
  exact wk_trade μ hμ m hm l N lo hlo

end EndPass

/-! ## Variant `scoped`: `--exit-opacity` and `--exit-scatter` registered non-inherited, passed down an `inherit` chain -/

section Scoped

open Fw.Engine.Restyle Fw.Engine.Restyle.Node

/-- The written element, as `part/class`. -/
def stageName : String := "hero.exit/hero"

/-- Elements whose winning declarations read `--exit-opacity` or `--exit-scatter`, as `part/class`. -/
def readers : List String := ["hero.orbit/card", "hero/copy", "hero.cue/cue"]

/-- Classes with a `[data-exit-scope]` rule declaring `inherit` for both properties, as `part/class`. -/
def inheritRules : List String :=
  ["hero.orbit/orbit", "hero.orbit/stage", "hero.orbit/stage3d", "hero.orbit/card", "hero.deck/deck", "hero/copy",
   "hero.cue/cue"]

private def leaf (n : String) (f : Flags := {}) : Node := mk n f []
private def v : Flags := { vars := true }
private def s : Flags := { slow := true }
private def chainReader : Flags := { vars := true, slow := true, inh := true, reads := true }

def card : Node :=
  mk "hero.orbit/card" chainReader
    [mk "hero.orbit/hit" {} [mk "hero.orbit/profile" {}
      [mk "hero.orbit/cover" v [mk "picture" {} [leaf "img"]],
       mk "hero.orbit/body" v
        [mk "hero.orbit/avatarRow" {} [mk "hero.orbit/avatar" v [mk "picture" {} [leaf "img"], leaf "hero.orbit/online" v]],
         mk "hero.orbit/info" v [leaf "hero.orbit/name" v, leaf "hero.orbit/role" v]]]]]

def accent : Node :=
  mk "hero.accent/accent" {} [leaf "hero.accent/sizer", mk "hero.accent/frame" {} [mk "hero.accent/paint" {}
    (List.replicate 3 (mk "hero.accent/svg" s [leaf "hero.accent/path" s]))]]

def countdownUnit : Node :=
  mk "hero.countdown/unit" v [mk "hero.countdown/value" v [leaf "hero.countdown/placeholder"], leaf "hero.countdown/label" v]

def copy : Node :=
  mk "hero/copy" chainReader
    [mk "hero/copyMain" {} [mk "hero/title" {} [leaf "hero/line", mk "hero/words" {} [leaf "span", accent, leaf "span"]],
       leaf "p"],
     mk "hero.countdown/countdown" v (List.replicate 4 countdownUnit),
     mk "hero/ctaStack" {}
      [mk "hero/cta" { vars := true, slow := true } [mk "button" {} [mk "hero/icon" s (List.replicate 2 (leaf "path" s))]],
       mk "hero/rsvp" s [mk "hero/icon" s (List.replicate 10 (leaf "path" s))], leaf "hero/note"]]

def cue : Node :=
  mk "hero.cue/cue" chainReader [mk "hero.cue/float" s [leaf "hero.cue/label", mk "svg" s (List.replicate 2 (leaf "path" s))]]

/-- The SSR hero stage with the cascade flags of `scoped.test.ts`; `narrow` is `width <= 600px`, where the orbit has
no box, and otherwise the deck has none. -/
def heroTree (narrow : Bool) : Node :=
  mk stageName v
    [mk "hero.orbit/orbit" { vars := true, hidden := narrow, inh := true }
      [mk "hero.orbit/stage" { inh := true } [mk "hero.orbit/stage3d" { inh := true } (List.replicate 10 card)]],
     mk "hero.deck/deck" { hidden := !narrow, inh := true } (List.replicate 4 card),
     copy, cue]

def heroPaths (narrow : Bool) : List (String × Bool × List Bool) := paths [] (heroTree narrow)

theorem readers_exact (narrow : Bool) : ∀ o ∈ heroPaths narrow, o.2.1 = readers.contains o.1 := by
  cases narrow <;> decide +kernel

theorem readers_in_tree (narrow : Bool) : ∀ r ∈ readers, (heroPaths narrow).any (·.1 == r) = true := by
  cases narrow <;> decide +kernel

theorem chain_covers (narrow : Bool) : ∀ o ∈ heroPaths narrow, o.2.1 = true → o.2.2.all id = true := by
  cases narrow <;> decide +kernel

theorem consumer_eq_scoped (narrow : Bool) (val : Option String) : ∀ o ∈ heroPaths narrow, o.2.1 = true →
    valueAt .registered val o.2.2 = valueAt .inherited val o.2.2 :=
  fun o ho hr => consumer_eq val o.2.2 (chain_covers narrow o ho hr)

/-- The stage's `--exit-opacity`: the driver's inline write, else the CSS default. -/
def stageOpacity (written : Option String) : String := written.getD "1"

/-- The stage's `--exit-scatter`; reduced motion overrides it with `0`. -/
def stageScatter (reduced : Bool) (opacity : String) : String :=
  if reduced then "0" else "calc(1 - " ++ opacity ++ ")"

#guard stageOpacity none == "1" && stageOpacity (some "0.25") == "0.25"
#guard stageScatter true "0.25" == "0" && stageScatter false "0.25" == "calc(1 - 0.25)"

theorem defaults (reg : Reg) (narrow : Bool) : ∀ o ∈ heroPaths narrow, o.2.1 = true →
    valueAt reg (some (stageOpacity none)) o.2.2 = some "1" := by
  intro o ho hr
  cases reg <;> simp [valueAt, stageOpacity, chain_covers narrow o ho hr]

theorem reduced_scatter (reg : Reg) (narrow : Bool) (opacity : String) : ∀ o ∈ heroPaths narrow, o.2.1 = true →
    valueAt reg (some (stageScatter true opacity)) o.2.2 = some "0" := by
  intro o ho hr
  cases reg <;> simp [valueAt, stageScatter, chain_covers narrow o ho hr]

theorem scatter_eq (narrow reduced : Bool) (opacity : String) : ∀ o ∈ heroPaths narrow, o.2.1 = true →
    valueAt .registered (some (stageScatter reduced opacity)) o.2.2 =
      valueAt .inherited (some (stageScatter reduced opacity)) o.2.2 :=
  fun o ho hr => consumer_eq _ o.2.2 (chain_covers narrow o ho hr)

theorem cr_units : crFull (heroTree true) = 99 ∧ crScoped (heroTree true) = 9 ∧
    crFull (heroTree false) = 172 ∧ crScoped (heroTree false) = 17 := by decide +kernel

theorem wk_units : wkFull (heroTree true) = 123 ∧ wkScoped (heroTree true) = 9 ∧
    wkFull (heroTree false) = 215 ∧ wkScoped (heroTree false) = 17 := by decide +kernel

theorem scoped_lt_faithful (narrow : Bool) : crScoped (heroTree narrow) < crFull (heroTree narrow) ∧
    wkScoped (heroTree narrow) < wkFull (heroTree narrow) := by
  cases narrow <;> decide +kernel

theorem narrow_delta : crFull (heroTree true) - crScoped (heroTree true) = 90 := by decide +kernel

/-- How a reader gets the exit values: `inherited` (faithful, unregistered), `chain` (registered, the `inherit` rules
only) or `inline` (the chain plus the driver's CSSOM write on the reader). -/
inductive Delivery where
  | inherited
  | chain
  | inline
deriving Repr, DecidableEq

def Delivery.reg : Delivery → Reg
  | .inherited => .inherited
  | _ => .registered

/-- The driver's per-frame writes on each reader for the stage write `opacity`; the scatter is the stage's
`stageScatter`. -/
def readerWrites (reduced : Bool) (opacity : String) : List (String × String) :=
  [("--exit-opacity", opacity), ("--exit-scatter", stageScatter reduced opacity)]

#guard readerWrites false "0.5" == [("--exit-opacity", "0.5"), ("--exit-scatter", "calc(1 - 0.5)")]
#guard readerWrites true "1" == [("--exit-opacity", "1"), ("--exit-scatter", "0")]

/-- A reader's own `(--exit-opacity, --exit-scatter)` after the stage write `w`, before any engine cache. -/
def ownVal (d : Delivery) (reduced : Bool) (path : List Bool) (w : String) : Option String × Option String :=
  match d with
  | .inline => ((readerWrites reduced w).lookup "--exit-opacity", (readerWrites reduced w).lookup "--exit-scatter")
  | d => (valueAt d.reg (some (stageOpacity (some w))) path,
      valueAt d.reg (some (stageScatter reduced (stageOpacity (some w)))) path)

/-- A WebKit matched-declarations cache entry for a reader: the parent's inherited custom properties it was built
under (`none` when the exit values are not among them) and the value its other properties were computed from. -/
structure WkEntry (α : Type) where
  key : Option α
  built : α
deriving DecidableEq

/-- One WebKit resolution of a reader whose own value is `v`: `(own value, value its var() properties show)` and the
cache after. Lookup key: matched declarations and the parent's inherited custom properties
(Source/WebCore/style/MatchedDeclarationsCache.cpp:123-163@862f17d). A hit copies the non-inherited properties and
re-applies only `inherit` declarations (Source/WebCore/style/StyleResolver.cpp:693-728@862f17d,
Source/WebCore/style/PropertyCascade.cpp:332-333@862f17d), so the own value is fresh and the var() properties are the
cached ones. A CSSOM inline style is mutable, so the reader's declarations are not cacheable and the hash is 0
(Source/WebCore/dom/StyledElement.cpp:93-105@862f17d, Source/WebCore/style/ElementRuleCollector.cpp:968-971,994-996@862f17d,
MatchedDeclarationsCache.cpp:125-126@862f17d). The `.inline` branch takes these lines as given, not derived: `wkRun_inline`
and `inline_visSame` hold under it. -/
def wkResolve {α : Type} [DecidableEq α] (d : Delivery) (cache : List (WkEntry α)) (v : α) :
    (α × α) × List (WkEntry α) :=
  if d = .inline then ((v, v), cache)
  else
    let key : Option α := if d = .inherited then some v else none
    match cache.find? (fun e => decide (e.key = key)) with
    | some e => ((v, e.built), cache)
    | none => ((v, v), cache ++ [⟨key, v⟩])

def wkRun {α : Type} [DecidableEq α] (d : Delivery) : List (WkEntry α) → List α → List (α × α)
  | _, [] => []
  | c, v :: vs => (wkResolve d c v).1 :: wkRun d (wkResolve d c v).2 vs

theorem wkRun_inline {α : Type} [DecidableEq α] (c : List (WkEntry α)) (vs : List α) :
    wkRun .inline c vs = vs.map fun v => (v, v) := by
  induction vs generalizing c with
  | nil => rfl
  | cons v vs ih => simp [wkRun, wkResolve, ih]

theorem wkRun_inherited {α : Type} [DecidableEq α] (c : List (WkEntry α)) (hc : ∀ e ∈ c, e.key = some e.built)
    (vs : List α) : wkRun .inherited c vs = vs.map fun v => (v, v) := by
  induction vs generalizing c with
  | nil => rfl
  | cons v vs ih =>
    simp only [wkRun, wkResolve, reduceCtorEq, ite_false, ite_true, List.map_cons]
    split
    · next e he =>
      have hk := List.find?_some he
      have hm := List.mem_of_find?_eq_some he
      have hb : e.built = v := by have := hc e hm; simp_all
      simp [hb, ih c hc]
    · next =>
      have hc' : ∀ e ∈ c ++ [⟨some v, v⟩], e.key = some e.built := by
        intro e he
        rcases List.mem_append.1 he with h | h
        · exact hc e h
        · simp at h; subst h; rfl
      simp [ih _ hc']

/-- The chain on WebKit: after the first frame every frame hits the entry built at frame 0, so the var() properties
stay at the first value while the own value follows the stage. -/
theorem wkRun_chain_frozen {α : Type} [DecidableEq α] (v : α) (vs : List α) :
    wkRun .chain [] (v :: vs) = (v, v) :: vs.map fun u => (u, v) := by
  have h : ∀ us : List α, wkRun .chain [⟨none, v⟩] us = us.map fun u => (u, v) := by
    intro us
    induction us with
    | nil => rfl
    | cons u us ih => simp [wkRun, wkResolve, ih]
  simp [wkRun, wkResolve, h]

/-- The values a reader's var() properties are computed from at each driver write of `ws`: WebKit through its
matched-declarations cache, Chromium as resolved. -/
def shown (webkit : Bool) (d : Delivery) (reduced : Bool) (path : List Bool) (ws : List String) :
    List (Option String × Option String) :=
  if webkit then (wkRun d [] (ws.map (ownVal d reduced path))).map (·.2) else ws.map (ownVal d reduced path)

theorem ownVal_inline_eq (reduced : Bool) (path : List Bool) (w : String) :
    ownVal .inline reduced path w = ownVal .inherited reduced path w := by
  simp [ownVal, readerWrites, Delivery.reg, valueAt, stageOpacity, List.lookup]

theorem shown_inline_eq (webkit reduced : Bool) (path : List Bool) (ws : List String) :
    shown webkit .inline reduced path ws = shown webkit .inherited reduced path ws := by
  have e : ws.map (ownVal .inline reduced path) = ws.map (ownVal .inherited reduced path) :=
    List.map_congr_left fun w _ => ownVal_inline_eq reduced path w
  cases webkit
  · simp [shown, e]
  · simp only [shown, ite_true, e, wkRun_inline, wkRun_inherited [] (by simp), List.map_map]

/-- Path of the hero copy below the stage. -/
def copyPath : List Bool := [true]

#guard (heroPaths true).any (fun o => o.1 == "hero/copy" && o.2.2 == copyPath)

/-- Bug A: on WebKit the chain shows the copy the first write while the faithful copy follows the stage. -/
theorem chain_stale_webkit :
    shown true .chain false copyPath ["1", "0.5"] = [(some "1", some "calc(1 - 1)"), (some "1", some "calc(1 - 1)")] ∧
    shown true .inherited false copyPath ["1", "0.5"] =
      [(some "1", some "calc(1 - 1)"), (some "0.5", some "calc(1 - 0.5)")] := by
  decide +kernel

theorem chain_eq_chromium (reduced : Bool) (path : List Bool) (h : path.all id = true) (ws : List String) :
    shown false .chain reduced path ws = shown false .inherited reduced path ws := by
  simp [shown, ownVal, Delivery.reg, valueAt, h]

/-- The readers' shown values at frame `t` of the writes `ws`, for an environment `(webkit, narrow, reduced, ws)`. -/
def readerInputs (d : Delivery) (env : Bool × Bool × Bool × List String) (t : Nat) :
    List (String × Option String × Option String) :=
  ((heroPaths env.2.1).filter (·.2.1)).map fun o =>
    (o.1, (shown env.1 d env.2.2.1 o.2.2 env.2.2.2).getD t (none, none))

/-- Every scene drawn from the readers' shown values is the same for `inline` and faithful, on both engines, at
every frame of every write sequence, given the `.inline` branch of `wkResolve`. -/
theorem inline_visSame (draw : List (String × Option String × Option String) → Fw.Engine.Scene)
    (vp : Bool × Bool × Bool × List String → Fw.Engine.Rect) :
    Fw.Engine.VisSame Fw.Engine.E vp (fun env t => draw (readerInputs .inherited env t))
      (fun env t => draw (readerInputs .inline env t)) :=
  Fw.Engine.visSame_of_eq vp fun env t => by simp only [readerInputs, shown_inline_eq]

mutual
/-- Readers an inline write marks dirty that the Chromium scoped walk does not resolve (`reached`: the walk resolves
this node); a write below a node with no box marks nothing
(third_party/blink/renderer/core/dom/node.cc:1474-1479,1659-1660@f842f52). -/
def crFresh (reached : Bool) : Node → Nat
  | mk _ f ks => (if f.reads && !reached then 1 else 0) +
      (if f.hidden then 0 else crFreshL (reached && f.inh && explicitKid ks) ks)
def crFreshL (pass : Bool) : List Node → Nat
  | [] => 0
  | k :: ks => crFresh pass k + crFreshL pass ks
end

mutual
/-- The same for the WebKit scoped walk; a write below a node with no box is not resolved
(Source/WebCore/style/StyleTreeResolver.cpp:1386-1387@862f17d). -/
def wkFresh (reached : Bool) : Node → Nat
  | mk _ f ks => (if f.reads && !reached then 1 else 0) +
      (if f.hidden then 0 else wkFreshL (reached && f.inh) ks)
def wkFreshL (pass : Bool) : List Node → Nat
  | [] => 0
  | k :: ks => wkFresh (pass && (k.flags.inh || k.flags.explicit)) k + wkFreshL pass ks
end

/-- Resolutions per frame for `inline`: the scoped walk from the stage plus the fresh readers. -/
def crInline : Node → Nat
  | n@(mk _ f ks) => crScoped n + (if f.hidden then 0 else crFreshL (explicitKid ks) ks)
def wkInline : Node → Nat
  | n@(mk _ f ks) => wkScoped n + (if f.hidden then 0 else wkFreshL true ks)

/-- Elements the `inline` driver writes per frame: the stage and every reader. -/
def inlineTouched (narrow : Bool) : Nat := 1 + ((heroPaths narrow).filter (·.2.1)).length

theorem inline_touched (narrow : Bool) : inlineTouched narrow = 17 := by cases narrow <;> decide +kernel

theorem inline_units (narrow : Bool) : crInline (heroTree narrow) = crScoped (heroTree narrow) ∧
    wkInline (heroTree narrow) = wkScoped (heroTree narrow) := by
  cases narrow <;> decide +kernel

theorem inline_lt_faithful (narrow : Bool) : crInline (heroTree narrow) < crFull (heroTree narrow) ∧
    wkInline (heroTree narrow) < wkFull (heroTree narrow) := by
  rw [(inline_units narrow).1, (inline_units narrow).2]
  exact scoped_lt_faithful narrow

theorem inline_narrow_delta : crFull (heroTree true) - crInline (heroTree true) = 90 := by
  rw [(inline_units true).1]; exact narrow_delta

/-- Elements and properties the scoped driver writes per zone frame. -/
def frameWrites : List (String × String) :=
  (stageName, "--exit-opacity") :: readers.flatMap fun r => [(r, "--exit-opacity"), (r, "--exit-scatter")]

/-- Golden `readerWrites` inputs: `(reduced, opacity)`. -/
def readerWriteCases : List (Bool × String) :=
  [(false, "1"), (false, "0.5"), (false, "0"), (false, "0.0429"), (true, "1")]

def zoneFirst : Nat := 10
def zoneLast : Nat := 103
/-- Golden `zone`: the swipe-v1 frame window 10-103, from the first scroll frame to the last frame below scrollY 950,
93 of them exit-write frames (11-103). It does not fit swipe-touch-v1, whose writes run to frame 111. The zone totals
are model products, never compared with a measured sum. -/
def zoneFrames : Nat := zoneLast + 1 - zoneFirst

#guard zoneFrames == 94

/-- Contents of `packages/contracts/golden/parts/hero.exit.scoped.json`. -/
def scopedJson (_ : Unit := ()) : Lean.Json :=
  let prop (n : String) : Lean.Json :=
    Lean.Json.mkObj [("name", Lean.toJson n), ("syntax", Lean.toJson "*"), ("inherits", Lean.toJson false)]
  let units (narrow : Bool) : Lean.Json :=
    Lean.Json.mkObj [("chromiumFaithful", Lean.toJson (crFull (heroTree narrow))),
      ("webkitFaithful", Lean.toJson (wkFull (heroTree narrow))), ("chromiumScoped", Lean.toJson (crScoped (heroTree narrow))),
      ("webkitScoped", Lean.toJson (wkScoped (heroTree narrow)))]
  let inl (narrow : Bool) : Lean.Json :=
    Lean.Json.mkObj [("touched", Lean.toJson (inlineTouched narrow)),
      ("chromium", Lean.toJson (crInline (heroTree narrow))), ("webkit", Lean.toJson (wkInline (heroTree narrow)))]
  Lean.Json.mkObj [
    ("variant", Lean.toJson "scoped"),
    ("scopeAttr", Lean.toJson "data-exit-scope"),
    ("register", Lean.Json.arr #[prop "--exit-opacity", prop "--exit-scatter"]),
    ("readers", Lean.toJson readers),
    ("inheritRules", Lean.toJson inheritRules),
    ("stageDefaults", Lean.Json.mkObj [("opacity", Lean.toJson (stageOpacity none)),
      ("scatter", Lean.toJson (stageScatter false "var(--exit-opacity)")),
      ("reducedScatter", Lean.toJson (stageScatter true "var(--exit-opacity)"))]),
    ("trees", Lean.Json.mkObj [("narrow", (heroTree true).json), ("wide", (heroTree false).json)]),
    ("units", Lean.Json.mkObj [("narrow", units true), ("wide", units false)]),
    ("inline", Lean.Json.mkObj [("narrow", inl true), ("wide", inl false)]),
    ("readerWrites", Lean.Json.arr (readerWriteCases.map fun (r, o) =>
      Lean.Json.mkObj [("reduced", Lean.toJson r), ("opacity", Lean.toJson o),
        ("writes", Lean.Json.arr ((readerWrites r o).map fun (p, x) => Lean.Json.arr #[Lean.toJson p, Lean.toJson x]).toArray)]).toArray),
    ("frameWrites", Lean.Json.arr (frameWrites.map fun (e, p) =>
      Lean.Json.mkObj [("element", Lean.toJson e), ("property", Lean.toJson p)]).toArray),
    ("zone", Lean.Json.mkObj [("first", Lean.toJson zoneFirst), ("last", Lean.toJson zoneLast),
      ("frames", Lean.toJson zoneFrames), ("narrowChromiumFaithful", Lean.toJson (zoneFrames * crFull (heroTree true))),
      ("narrowChromiumScoped", Lean.toJson (zoneFrames * crScoped (heroTree true)))])]

def scopedText (_ : Unit := ()) : String := (scopedJson ()).pretty ++ "\n"

/-- Print the golden, or with `--check <file>` compare it; exit 1 on a difference. -/
def runScoped (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == scopedText () then
      IO.eprintln s!"exit scoped golden: {path} is up to date"
      return 0
    IO.eprintln s!"exit scoped golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (scopedText ())
    return 0

end Scoped

/-! ## Variant `threaded`: the port's CSS endpoints, the hand-over rule and the sentinel, as golden rows -/

section Threaded

/-- The hero stage's `data-splash` value (set by `hero.orbit`). -/
inductive Splash where
  | prep
  | run
  | done
deriving Repr, DecidableEq, Inhabited

/-- Whether the hero stage runs on its CSS animations (true) or on the original's callback (false); `fin` is that the
entrance animations have finished (the phone cue's `copyIn` can still run at `data-splash = done`). -/
def live (s : Splash) (fin supported reduced : Bool) : Bool := decide (s = .done) && fin && supported && !reduced

/-- Live exactly when all four conditions hold. -/
theorem live_iff (s : Splash) (fin supported reduced : Bool) :
    live s fin supported reduced = true ↔ s = .done ∧ fin = true ∧ supported = true ∧ reduced = false := by
  unfold live
  cases fin <;> cases supported <;> cases reduced <;> simp

/-- While the splash plays the callback keeps the page. -/
theorem live_splash (s : Splash) (hs : s ≠ .done) (fin supported reduced : Bool) :
    live s fin supported reduced = false := by
  unfold live
  simp [hs]

/-- While an entrance animation still runs (splash `done`) the callback keeps the page. -/
theorem live_unfinished (supported reduced : Bool) : live .done false supported reduced = false := by
  unfold live
  simp

/-- Without `animation-timeline` the callback keeps the page. -/
theorem live_unsupported (s : Splash) (fin reduced : Bool) : live s fin false reduced = false := by
  unfold live
  simp

/-- Under reduced motion the callback keeps the page. -/
theorem live_reduced (s : Splash) (fin supported : Bool) : live s fin supported true = false := by
  unfold live
  simp

/-- The one live case: settled, finished, supported, not reduced. -/
theorem live_done : live .done true true false = true := by
  unfold live
  simp

/-- The next `live`: a live stage stays live (`prev`) until a mutation batch saw the splash leave `done` (`left`). -/
def liveNext (prev left : Bool) (s : Splash) (fin sup red : Bool) : Bool := live s (fin || (prev && !left)) sup red

/-- A batch that saw the splash leave `done` drops the latch. -/
theorem liveNext_left (prev : Bool) (s : Splash) (fin sup red : Bool) :
    liveNext prev true s fin sup red = live s fin sup red := by
  unfold liveNext
  simp

/-- With no such batch, a live stage stays live while its own animations read as unfinished. -/
theorem liveNext_latch (sup : Bool) : liveNext true false .done false sup false = sup := by
  unfold liveNext live
  simp

/-- A finished entrance needs no latch. -/
theorem liveNext_fin (prev left : Bool) (s : Splash) (sup red : Bool) :
    liveNext prev left s true sup red = live s true sup red := by
  unfold liveNext
  simp

/-- A stage that was not live and saw no leave follows `live`. -/
theorem liveNext_fresh (left : Bool) (s : Splash) (fin sup red : Bool) :
    liveNext false left s fin sup red = live s fin sup red := by
  unfold liveNext
  simp

def origNames (n : ExitNode) (le600 : Bool) (s : Splash) (ended : Bool) : List String :=
  match n with
  | .orbit => if s = .run then ["ringAppear", "cardFromRing"] else []
  | .deck => []
  | .copy => if !le600 && s = .run then ["copyFromRing"] else []
  | .cue =>
    if le600 then (if s = .prep || ended then [] else ["copyIn"])
    else if s = .run then ["copyFromRing"] else []

structure StylePass where
  s : Splash
  ended : Bool
  mo : Option Bool
deriving Repr, Inhabited

/-- The entrance counts as finished when the cue runs nothing (the TS reads the cue's animations). -/
def finOf (le600 : Bool) (p : StylePass) : Bool := (origNames .cue le600 p.s p.ended).isEmpty

/-- The state of `data-exit-live` at each style pass, from `a` before the first. -/
def attrRun (le600 sup red : Bool) : Bool → List StylePass → List Bool
  | _, [] => []
  | a, p :: ps =>
    let a' := match p.mo with
      | none => a
      | some left => liveNext a left p.s (finOf le600 p) sup red
    a' :: attrRun le600 sup red a' ps

/-- The original's animation names of a node at a pass. -/
def origAt (n : ExitNode) (le600 : Bool) (p : StylePass) : List String := origNames n le600 p.s p.ended

/-- The variant's: the exit list when the attribute is set at `done`, else the original's. -/
def varAt (n : ExitNode) (le600 : Bool) (p : StylePass) (a : Bool) : List String :=
  if a && decide (p.s = .done) then exitNames n le600 else origNames n le600 p.s p.ended

/-- The names present at a pass and absent at the one before. -/
def restarts (ls : List (List String)) : List (List String) :=
  List.zipWith (fun prev cur => cur.filter (fun x => !prev.contains x)) ([] :: ls) ls

/-- A path: band, `data-exit-live` before the first pass, the passes. -/
structure EntrancePath where
  name : String
  le600 : Bool
  a0 : Bool
  passes : List StylePass

/-- Initial load, wide: prep, run, done, entrance end. -/
def pathLoadWide : EntrancePath :=
  ⟨"load", false, false, [⟨.prep, false, some false⟩, ⟨.run, false, some false⟩, ⟨.done, false, some false⟩, ⟨.done, true, some false⟩]⟩

/-- Initial load, phone: prep, done (`copyIn` runs), entrance end. -/
def pathLoadNarrow : EntrancePath :=
  ⟨"load", true, false, [⟨.prep, false, some false⟩, ⟨.done, false, some false⟩, ⟨.done, true, some false⟩]⟩

/-- Restore, wide: done, prep (forced layout, no callback yet), run (one batch that left `done`), done. -/
def pathRestoreWide : EntrancePath :=
  ⟨"restore", false, true, [⟨.done, true, none⟩, ⟨.prep, false, none⟩, ⟨.run, false, some true⟩, ⟨.done, false, some false⟩]⟩

/-- Restore, phone: done, prep (forced layout), done (one batch that left `done`, `copyIn` plays again), entrance end. -/
def pathRestoreNarrow : EntrancePath :=
  ⟨"restore", true, true, [⟨.done, true, none⟩, ⟨.prep, false, none⟩, ⟨.done, false, some true⟩, ⟨.done, true, some false⟩]⟩

/-- The four paths. -/
def entrancePaths : List EntrancePath := [pathLoadWide, pathLoadNarrow, pathRestoreWide, pathRestoreNarrow]

/-- The variant's name list of a node at every pass of a path. -/
def varLists (e : EntrancePath) (sup red : Bool) (n : ExitNode) : List (List String) :=
  List.zipWith (fun p a => varAt n e.le600 p a) e.passes (attrRun e.le600 sup red e.a0 e.passes)

/-- The original's. -/
def origLists (e : EntrancePath) (n : ExitNode) : List (List String) := e.passes.map (origAt n e.le600)

/-- Drop the exit names. -/
def dropExit (n : ExitNode) (le600 : Bool) (l : List String) : List String :=
  l.filter (fun x => !(exitNames n le600).contains x)

/-- The variant minus the exit names equals the original at every pass, and so do the restart sets. -/
def entranceSame (e : EntrancePath) (sup red : Bool) (n : ExitNode) : Bool :=
  (varLists e sup red n).map (dropExit n e.le600) == origLists e n &&
  (restarts (varLists e sup red n)).map (dropExit n e.le600) == restarts (origLists e n)

/-- On every path, band, node and support setting the variant minus the exit names equals the original, restarts included. -/
theorem entrance_same :
    entrancePaths.all (fun e => [true, false].all fun sup => [true, false].all fun red =>
      exitNodes.all (entranceSame e sup red)) = true := by
  decide +kernel

/-- The live rule applies at the last pass of the phone restore (the entrance ended), and replaces the cue's list. -/
theorem restore_narrow_cue_live :
    (varLists pathRestoreNarrow true false .cue).getLast? = some (exitNames .cue true) := by
  decide +kernel

/-- Right after the phone restore the cue is not live, so its `copyIn` plays again. -/
theorem restore_narrow_cue_replays :
    (varLists pathRestoreNarrow true false .cue)[2]? = some ["copyIn"] := by
  decide +kernel

/-- The settled consumers the CSS animates in band `l`, named as in the golden. -/
def settled (l : Bool) : List (String × Consumer) :=
  [("copyOpacity", .copyOpacity 1), ("copyTranslateY", .copyTranslateY 1 l), ("copyBlur", .copyBlur 1 l),
   ("cueBlur", .cueBlur), ("cueTranslateY", .cueTranslateY l), ("cardOpacity", .cardOpacity),
   ("cardTranslate", .cardTranslate 1 0 1)]

/-- The keyframe endpoints (rest, exited) of every settled consumer in the wide band, as `threaded.module.css` restates them. -/
theorem keyframe_table_wide :
    (settled false).map (fun p => (p.2.val 1, p.2.val 0)) =
      [(1, 0), (0, -10), (0, 18), (0, 18), (0, 0), (1, 13 / 20), (0, 1)] := by
  decide +kernel

/-- The same endpoints in the phone band. -/
theorem keyframe_table_narrow :
    (settled true).map (fun p => (p.2.val 1, p.2.val 0)) =
      [(1, 0), (0, -8), (0, 0), (0, 18), (0, -10), (1, 13 / 20), (0, 1)] := by
  decide +kernel

/-- The splash as a golden string. -/
def splashLabel : Splash → String
  | .prep => "prep"
  | .run => "run"
  | .done => "done"

/-- A rational as a golden number object. -/
def gRat (q : Rat) : Lean.Json := Lean.Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- An integer as a JSON number. -/
def gInt (n : Int) : Lean.Json := Lean.toJson n

/-- One golden line (keys sorted by `mkObj`'s rendering). -/
def gLine (fn : String) (inp : List (String × Lean.Json)) (out : Lean.Json) : String :=
  (Lean.Json.mkObj [("fn", .str fn), ("in", Lean.Json.mkObj inp), ("out", out)]).compress

/-- The sample geometries: `(T, h, v)` with the track top at scroll offset `T` (desktop and phone shapes, a nonzero
`T`, and a degenerate track). -/
def threadedGeoms : List (Int × Int × Int) := [(0, 1600, 800), (300, 1600, 800), (0, 1688, 844), (0, 100, 800)]

/-- The sample scroll offsets: before, at, inside (first/mid/last), at and after the end of the range, and the
pointer-off cut. -/
def threadedOffsets (T h v : Int) : List Int :=
  let n : Int := max 1 (h - v)
  [T - 50, T, T + 1, T + n / 4, T + n / 2, T + n * 19 / 20, T + n * 19 / 20 + 1, T + n - 1, T + n, T + n + 1, T + n + 500]

/-- **Golden lines of `hero-exit.threaded.jsonl`.** `keyframes`: the `0%`/`100%` values of each settled consumer.
`anim`: the animated value at offset `y` under RG11 next to the original's `calc()` value (equal: `consumer_eq_s`).
`sentinelTop`: where the sentinel sits below the track top. `sentinelAbove`: the pointer decision. `live`: the hand-over
table. -/
def threadedLines (_ : Unit := ()) : List String :=
  ([false, true].flatMap fun l => (settled l).map fun (n, k) =>
    gLine "keyframes" [("consumer", .str n), ("le600", .bool l)]
      (Lean.Json.mkObj [("from", gRat (k.val 1)), ("to", gRat (k.val 0))])) ++
  ([false, true].flatMap fun l => threadedGeoms.flatMap fun (T, h, v) => (threadedOffsets T h v).flatMap fun y =>
    (settled l).map fun (n, k) =>
      let prog := timelineProgress T (exitRange h v) y
      gLine "anim" [("consumer", .str n), ("le600", .bool l), ("T", gInt T), ("h", gInt h), ("v", gInt v), ("y", gInt y)]
        (Lean.Json.mkObj [("progress", gRat prog), ("anim", gRat (k.anim prog)),
          ("orig", gRat (k.val (exitOpacityAt T h v y)))])) ++
  (threadedGeoms.map fun (_, h, v) =>
    gLine "sentinelTop" [("h", gInt h), ("v", gInt v)] (gRat (19 / 20 * exitRange h v))) ++
  (threadedGeoms.flatMap fun (T, h, v) => (threadedOffsets T h v).map fun y =>
    gLine "sentinelAbove" [("T", gInt T), ("h", gInt h), ("v", gInt v), ("y", gInt y)]
      (.bool (sentinelAbove T h v y))) ++
  ([Splash.prep, .run, .done].flatMap fun s => [false, true].flatMap fun fin => [false, true].flatMap fun sup =>
    [false, true].map fun red =>
    gLine "live" [("splash", .str (splashLabel s)),
      ("entranceFinished", .bool fin), ("supported", .bool sup), ("reduced", .bool red)] (.bool (live s fin sup red))) ++
  ([false, true].flatMap fun prev => [false, true].flatMap fun left => [Splash.prep, .run, .done].flatMap fun s =>
    [false, true].flatMap fun fin => [false, true].flatMap fun sup => [false, true].map fun red =>
    gLine "liveNext" [("prev", .bool prev), ("left", .bool left), ("splash", .str (splashLabel s)),
      ("entranceFinished", .bool fin), ("supported", .bool sup), ("reduced", .bool red)]
      (.bool (liveNext prev left s fin sup red))) ++
  (exitNodes.flatMap fun n => [false, true].map fun l =>
    gLine "exitNames" [("node", .str n.label), ("le600", .bool l)] (Lean.toJson (exitNames n l))) ++
  (entrancePaths.flatMap fun e => exitNodes.flatMap fun n =>
    let attrs := attrRun e.le600 true false e.a0 e.passes
    let vs := varLists e true false n
    let os := origLists e n
    let vr := restarts vs
    let orr := restarts os
    (List.range e.passes.length).map fun (k : Nat) =>
      gLine "entrance" [("path", .str e.name), ("le600", .bool e.le600), ("node", .str n.label), ("pass", gInt (Int.ofNat k))]
        (Lean.Json.mkObj [("splash", .str (splashLabel (e.passes[k]!).s)), ("live", .bool attrs[k]!),
          ("orig", Lean.toJson os[k]!), ("variant", Lean.toJson vs[k]!),
          ("origRestart", Lean.toJson orr[k]!), ("variantRestart", Lean.toJson vr[k]!)]))

/-- The golden text. -/
def threadedText (_ : Unit := ()) : String := String.join ((threadedLines ()).map (· ++ "\n"))

#guard (([false, true].flatMap fun l => threadedGeoms.flatMap fun (T, h, v) => (threadedOffsets T h v).flatMap fun y =>
  (settled l).map fun (_, k) =>
    k.anim (timelineProgress T (exitRange h v) y) == k.val (exitOpacityAt T h v y)).all id)

/-- Print the golden, or with `--check <file>` compare it; exit 1 on a difference. -/
def runThreaded (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == threadedText () then
      IO.eprintln s!"exit threaded golden: {path} is up to date"
      return 0
    IO.eprintln s!"exit threaded golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (threadedText ())
    return 0

end Threaded

end Fw.Parts.HeroExitOpt
