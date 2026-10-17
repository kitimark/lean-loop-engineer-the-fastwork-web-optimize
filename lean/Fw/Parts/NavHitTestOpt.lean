import Lean.Data.Json
import Fw.Engine
import Fw.Parts.EngineScroll
import Fw.Parts.NavHitTest

/-!
# nav.hitTest, variants `hit-skip` and `elements-skip`: less work, same pixels (NH-W)

The nav's scroll callback probes "is the nav over a dark section" once per frame. The faithful probe
(`apps/site/src/parts/nav.hitTest/probe.ts` `probeFaithful`, original JS 12950-12964) reads the nav rect, writes
`pointer-events: none` inline, calls `elementFromPoint`, and restores the inline value. Two variants:

* `hit-skip` skips the probe while `morph > 0.2` (the answer is invisible then: `NavHitTest.hitSkip_morph`);
* `elements-skip` calls `elementsFromPoint` with an allow-list instead (no style write:
  `NavHitTest.allowHit_eq_faithful`).

Design: `research/notes/2026/10-18-engine-proof-design.md` §2-§3 and §4.2 row NH-W.

**Cost model.** A frame's accesses run through `EngineScroll.forced` with `styleRole` and `layoutRole`
(premise R4, INFERRED: a style read on dirty style forces one style recalc; `elementFromPoint` and rect reads are
layout reads). The probe sits between an arbitrary prefix (other callbacks, `ee()`) and an arbitrary suffix (the
hero-track rect read, later callbacks), so every result holds for every frame context, hence for every width band:
the width only changes the context, never the probe.

**What the toggle leaves behind** (CONFIRMED in source, modelled as an arbitrary change list `pes`): Chromium
`third_party/blink/renderer/core/layout/layout_object.cc:3476-3480`@f842f52 marks paint for hit testing on a used
`pointer-events` change; WebKit `Source/WebCore/style/StyleDifference.cpp:921-922`@862f17d maps a `pointer-events`
change to `RecompositeLayer` and `Source/WebCore/rendering/RenderElement.cpp:970-971`@862f17d invalidates the event
region. Neither engine table has a `pointer-events` property, so `pes` stays a hypothesis-free parameter: the
theorems hold for every `pes`.

**Finding.** The graph row says "forced style −1"; the model gives −2 per skipped frame (`hitSkip_style_two`),
because the hero-track read after the probe pays for the restore write. The v1 README says the same for
elements-skip ("two extra forced style passes per frame").
-/
namespace Fw.Parts.NavHitTestOpt

open Lean (Json)
open Fw.Engine
open Fw.Parts.EngineScroll (Access Role forced styleRole layoutRole navAccesses forced_mono)
open Fw.Parts.NavHitTest (Hit isOnDark hitSkip_morph faithfulHit allowHit allowHit_eq_faithful changed changed_write)

/-! ## The probe's accesses -/

/-- `ee()`: the sticky profile reads (`position`, `top`, two rects).

$$\mathit{ee} = [\mathrm{RS}, \mathrm{RS}, \mathrm{RL}, \mathrm{RL}]$$

The reads the nav callback makes before the probe. -/
def navEe : List Access := [.readStyle, .readStyle, .readLayout, .readLayout]

/-- The faithful probe: nav rect, `pointer-events` write, `elementFromPoint`, restore write.

$$\mathit{probe}_o = [\mathrm{RL}, \mathrm{WS}, \mathrm{RL}, \mathrm{WS}]$$

The original's probe accesses. -/
def probeFaithful : List Access := [.readLayout, .writeStyle, .readLayout, .writeStyle]

/-- The elements-skip probe: nav rect, `elementsFromPoint`, no write.

$$\mathit{probe}_e = [\mathrm{RL}, \mathrm{RL}]$$

The elements-skip probe accesses. -/
def probeElements : List Access := [.readLayout, .readLayout]

/-- The hero-track rect read after the probe.

$$\mathit{track} = [\mathrm{RL}]$$

The read the nav callback makes after the probe. -/
def navTrack : List Access := [.readLayout]

/-- The original nav callback is `ee`, the faithful probe, then the track read.

$$\mathit{nav} = \mathit{ee} \mathbin{+\!\!+} \mathit{probe}_o \mathbin{+\!\!+} \mathit{track}$$

The pilot's nav accesses split around the probe. -/
theorem navAccesses_eq : navAccesses = navEe ++ probeFaithful ++ navTrack := rfl

/-! ## `forced` over a concatenation -/

/-- The dirty flag after a run of accesses: a check cleans it, a dirtier sets it, a neutral access keeps it.

$$\operatorname{fin}_\rho(d, [\,]) = d,\qquad \operatorname{fin}_\rho(d, a :: \mathit{as}) = \begin{cases} \operatorname{fin}_\rho(\mathrm{false}, \mathit{as}) & \rho(a) = \mathrm{check} \\ \operatorname{fin}_\rho(\mathrm{true}, \mathit{as}) & \rho(a) = \mathrm{dirty} \\ \operatorname{fin}_\rho(d, \mathit{as}) & \rho(a) = \mathrm{neutral} \end{cases}$$

Whether the state is still dirty after the accesses. -/
def fin (ρ : Access → Role) : Bool → List Access → Bool
  | d, [] => d
  | d, a :: as =>
    match ρ a with
    | .check => fin ρ false as
    | .dirty => fin ρ true as
    | .neutral => fin ρ d as

#guard fin styleRole false probeFaithful == true
#guard fin styleRole true probeElements == false
#guard fin layoutRole true probeFaithful == false
#guard fin layoutRole true [] == true

/-- `forced` splits at a concatenation; the second part starts from the first part's final flag.

$$\forall \rho,\ \forall \mathit{as}, \mathit{bs},\ \forall d \in \mathbb{B}:\ \operatorname{forced}_\rho(d, \mathit{as} \mathbin{+\!\!+} \mathit{bs}) = \operatorname{forced}_\rho(d, \mathit{as}) + \operatorname{forced}_\rho(\operatorname{fin}_\rho(d, \mathit{as}), \mathit{bs})$$

Forced updates add up over consecutive runs of accesses. -/
theorem forced_append (ρ : Access → Role) (as bs : List Access) :
    ∀ d, forced ρ d (as ++ bs) = forced ρ d as + forced ρ (fin ρ d as) bs := by
  induction as with
  | nil => intro d; simp [forced, fin]
  | cons a as ih =>
    intro d
    cases h : ρ a <;> simp [forced, fin, h, ih] <;> omega

/-- Starting dirty costs at most one more forced update than starting clean.

$$\forall \rho,\ \forall \mathit{as}:\ \operatorname{forced}_\rho(\mathrm{true}, \mathit{as}) \le \operatorname{forced}_\rho(\mathrm{false}, \mathit{as}) + 1$$

A dirty start is paid for at most once. -/
theorem forced_true_le (ρ : Access → Role) (as : List Access) :
    forced ρ true as ≤ forced ρ false as + 1 := by
  induction as with
  | nil => simp [forced]
  | cons a as ih =>
    cases h : ρ a <;> simp [forced, h] <;> omega

/-- The final flag after a concatenation is the second part's final flag, started from the first part's.

$$\forall \rho,\ \forall \mathit{as}, \mathit{bs},\ \forall d \in \mathbb{B}:\ \operatorname{fin}_\rho(d, \mathit{as} \mathbin{+\!\!+} \mathit{bs}) = \operatorname{fin}_\rho(\operatorname{fin}_\rho(d, \mathit{as}), \mathit{bs})$$

The final flag composes over consecutive runs. -/
theorem fin_append (ρ : Access → Role) (as bs : List Access) :
    ∀ d, fin ρ d (as ++ bs) = fin ρ (fin ρ d as) bs := by
  induction as with
  | nil => intro d; rfl
  | cons a as ih => intro d; cases h : ρ a <;> simp [fin, h, ih]

/-! ## The probes under the style and layout roles -/

/-- The faithful probe under the style role: one forced recalc for a dirty start, one for the `pointer-events` write,
and it leaves style dirty.

$$\forall e \in \mathbb{B}:\ \operatorname{forced}_{\mathrm{style}}(e, \mathit{probe}_o) = [e] + 1 \ \land\ \operatorname{fin}_{\mathrm{style}}(e, \mathit{probe}_o) = \mathrm{true}$$

The faithful probe forces one extra style recalc and leaves the restore write pending. -/
theorem probeFaithful_style (e : Bool) :
    forced styleRole e probeFaithful = (if e then 1 else 0) + 1 ∧ fin styleRole e probeFaithful = true := by
  cases e <;> decide

/-- The elements probe under the style role: only a dirty start is paid, and style ends clean.

$$\forall e \in \mathbb{B}:\ \operatorname{forced}_{\mathrm{style}}(e, \mathit{probe}_e) = [e] \ \land\ \operatorname{fin}_{\mathrm{style}}(e, \mathit{probe}_e) = \mathrm{false}$$

The elements probe writes no style. -/
theorem probeElements_style (e : Bool) :
    forced styleRole e probeElements = (if e then 1 else 0) ∧ fin styleRole e probeElements = false := by
  cases e <;> decide

/-- Both probes under the layout role: only a dirty start is paid, and layout ends clean.

$$\forall e \in \mathbb{B}:\ \operatorname{forced}_{\mathrm{layout}}(e, \mathit{probe}_o) = \operatorname{forced}_{\mathrm{layout}}(e, \mathit{probe}_e) = [e] \ \land\ \operatorname{fin}_{\mathrm{layout}}(e, \mathit{probe}_o) = \operatorname{fin}_{\mathrm{layout}}(e, \mathit{probe}_e) = \mathrm{false}$$

Neither probe writes layout. -/
theorem probes_layout (e : Bool) :
    forced layoutRole e probeFaithful = (if e then 1 else 0) ∧ forced layoutRole e probeElements = (if e then 1 else 0) ∧
      fin layoutRole e probeFaithful = false ∧ fin layoutRole e probeElements = false := by
  cases e <;> decide

/-! ## Forced passes in a whole frame -/

/-- Dropping the faithful probe saves at least one forced style recalc, whatever runs before and after it.

$$\forall \mathit{pre}, \mathit{post},\ \forall d \in \mathbb{B}:\ \operatorname{forced}_{\mathrm{style}}(d, \mathit{pre} \mathbin{+\!\!+} [\,] \mathbin{+\!\!+} \mathit{post}) + 1 \le \operatorname{forced}_{\mathrm{style}}(d, \mathit{pre} \mathbin{+\!\!+} \mathit{probe}_o \mathbin{+\!\!+} \mathit{post})$$

The skipped frame has strictly fewer forced style recalcs. -/
theorem skip_style_lt (pre post : List Access) (d : Bool) :
    forced styleRole d (pre ++ [] ++ post) + 1 ≤ forced styleRole d (pre ++ probeFaithful ++ post) := by
  simp only [List.append_nil, forced_append, fin_append]
  obtain ⟨h1, h2⟩ := probeFaithful_style (fin styleRole d pre)
  have hm := forced_mono styleRole post (fin styleRole d pre) true (fun _ => rfl)
  rw [h2, h1]
  omega

/-- With the hero-track read first after the probe, dropping the probe saves exactly two forced style recalcs.

$$\forall \mathit{pre}, \mathit{post},\ \forall d \in \mathbb{B}:\ \operatorname{forced}_{\mathrm{style}}(d, \mathit{pre} \mathbin{+\!\!+} [\,] \mathbin{+\!\!+} (\mathit{track} \mathbin{+\!\!+} \mathit{post})) + 2 = \operatorname{forced}_{\mathrm{style}}(d, \mathit{pre} \mathbin{+\!\!+} \mathit{probe}_o \mathbin{+\!\!+} (\mathit{track} \mathbin{+\!\!+} \mathit{post}))$$

In the original's nav callback, hit-skip saves two forced style recalcs per skipped frame. -/
theorem hitSkip_style_two (pre post : List Access) (d : Bool) :
    forced styleRole d (pre ++ [] ++ (navTrack ++ post)) + 2 =
      forced styleRole d (pre ++ probeFaithful ++ (navTrack ++ post)) := by
  simp only [List.append_nil, forced_append, fin_append]
  obtain ⟨h1, h2⟩ := probeFaithful_style (fin styleRole d pre)
  rw [h2, h1]
  cases fin styleRole d pre <;> simp [navTrack, forced, fin, styleRole] <;> omega

/-- Replacing the faithful probe by the elements probe saves at least one forced style recalc.

$$\forall \mathit{pre}, \mathit{post},\ \forall d \in \mathbb{B}:\ \operatorname{forced}_{\mathrm{style}}(d, \mathit{pre} \mathbin{+\!\!+} \mathit{probe}_e \mathbin{+\!\!+} \mathit{post}) + 1 \le \operatorname{forced}_{\mathrm{style}}(d, \mathit{pre} \mathbin{+\!\!+} \mathit{probe}_o \mathbin{+\!\!+} \mathit{post})$$

The elements-skip frame has strictly fewer forced style recalcs. -/
theorem elements_style_lt (pre post : List Access) (d : Bool) :
    forced styleRole d (pre ++ probeElements ++ post) + 1 ≤ forced styleRole d (pre ++ probeFaithful ++ post) := by
  simp only [forced_append, fin_append]
  obtain ⟨h1, h2⟩ := probeFaithful_style (fin styleRole d pre)
  obtain ⟨h3, h4⟩ := probeElements_style (fin styleRole d pre)
  have hm := forced_mono styleRole post false true (fun _ => rfl)
  rw [h2, h1, h4, h3]
  omega

/-- With the hero-track read first after the probe, elements-skip saves exactly two forced style recalcs.

$$\forall \mathit{pre}, \mathit{post},\ \forall d \in \mathbb{B}:\ \operatorname{forced}_{\mathrm{style}}(d, \mathit{pre} \mathbin{+\!\!+} \mathit{probe}_e \mathbin{+\!\!+} (\mathit{track} \mathbin{+\!\!+} \mathit{post})) + 2 = \operatorname{forced}_{\mathrm{style}}(d, \mathit{pre} \mathbin{+\!\!+} \mathit{probe}_o \mathbin{+\!\!+} (\mathit{track} \mathbin{+\!\!+} \mathit{post}))$$

In the original's nav callback, elements-skip saves two forced style recalcs per frame. -/
theorem elements_style_two (pre post : List Access) (d : Bool) :
    forced styleRole d (pre ++ probeElements ++ (navTrack ++ post)) + 2 =
      forced styleRole d (pre ++ probeFaithful ++ (navTrack ++ post)) := by
  simp only [forced_append, fin_append]
  obtain ⟨h1, h2⟩ := probeFaithful_style (fin styleRole d pre)
  obtain ⟨h3, h4⟩ := probeElements_style (fin styleRole d pre)
  rw [h2, h1, h4, h3]
  simp [navTrack, forced, fin, styleRole]
  omega

/-- Dropping the faithful probe never adds a forced layout.

$$\forall \mathit{pre}, \mathit{post},\ \forall d \in \mathbb{B}:\ \operatorname{forced}_{\mathrm{layout}}(d, \mathit{pre} \mathbin{+\!\!+} [\,] \mathbin{+\!\!+} \mathit{post}) \le \operatorname{forced}_{\mathrm{layout}}(d, \mathit{pre} \mathbin{+\!\!+} \mathit{probe}_o \mathbin{+\!\!+} \mathit{post})$$

The skipped frame has no more forced layouts. -/
theorem skip_layout_le (pre post : List Access) (d : Bool) :
    forced layoutRole d (pre ++ [] ++ post) ≤ forced layoutRole d (pre ++ probeFaithful ++ post) := by
  simp only [List.append_nil, forced_append, fin_append]
  obtain ⟨h1, -, h3, -⟩ := probes_layout (fin layoutRole d pre)
  rw [h3, h1]
  have ht := forced_true_le layoutRole post
  cases fin layoutRole d pre <;> simp <;> omega

/-- The elements probe forces exactly the layouts the faithful probe forces.

$$\forall \mathit{pre}, \mathit{post},\ \forall d \in \mathbb{B}:\ \operatorname{forced}_{\mathrm{layout}}(d, \mathit{pre} \mathbin{+\!\!+} \mathit{probe}_e \mathbin{+\!\!+} \mathit{post}) = \operatorname{forced}_{\mathrm{layout}}(d, \mathit{pre} \mathbin{+\!\!+} \mathit{probe}_o \mathbin{+\!\!+} \mathit{post})$$

Elements-skip keeps the forced layouts. -/
theorem elements_layout_eq (pre post : List Access) (d : Bool) :
    forced layoutRole d (pre ++ probeElements ++ post) = forced layoutRole d (pre ++ probeFaithful ++ post) := by
  simp only [forced_append, fin_append]
  obtain ⟨h1, h2, h3, h4⟩ := probes_layout (fin layoutRole d pre)
  rw [h1, h2, h3, h4]

/-! ## Frames -/

/-- The frame around the nav probe: accesses before and after it, the style and layout dirty flags at frame start,
callbacks, other hit tests, other changes and compositor animations. Width, touch and DPR enter only through these
fields.

$$\mathrm{NavCtx}(P) = \underbrace{\mathrm{Access}^{*}}_{\mathrm{pre}} \times \underbrace{\mathrm{Access}^{*}}_{\mathrm{post}} \times \underbrace{\mathbb{B}}_{d_S} \times \underbrace{\mathbb{B}}_{d_L} \times \underbrace{\mathbb{N}}_{\mathrm{script}} \times \underbrace{\mathbb{N}}_{\mathrm{hits}} \times \underbrace{\mathrm{Change}(P)^{*}}_{\mathrm{changes}} \times \underbrace{\mathbb{N}}_{\mathrm{compAnims}}$$
-/
structure NavCtx (P : Type) where
  pre       : List Access
  post      : List Access
  dS        : Bool
  dL        : Bool
  script    : Nat
  hits      : Nat
  changes   : List (Change P)
  compAnims : Nat

/-- The frame with a given probe: forced passes from the access sequence, the probe's hit tests added to the others,
the probe's changes appended.

$$\operatorname{frame}(c, \pi, h, x) = \big(c.\mathrm{script},\ \operatorname{forced}_{\mathrm{style}}(c.d_S, c.\mathrm{pre} \mathbin{+\!\!+} \pi \mathbin{+\!\!+} c.\mathrm{post}),\ \operatorname{forced}_{\mathrm{layout}}(c.d_L, c.\mathrm{pre} \mathbin{+\!\!+} \pi \mathbin{+\!\!+} c.\mathrm{post}),\ c.\mathrm{hits} + h,\ c.\mathrm{changes} \mathbin{+\!\!+} x,\ c.\mathrm{compAnims}\big)$$
-/
def probeFrame {P : Type} (c : NavCtx P) (probe : List Access) (probeHits : Nat) (extra : List (Change P)) :
    FrameIn P where
  script := c.script
  forcedStyle := forced styleRole c.dS (c.pre ++ probe ++ c.post)
  forcedLayout := forced layoutRole c.dL (c.pre ++ probe ++ c.post)
  hits := c.hits + probeHits
  changes := c.changes ++ extra
  compAnims := c.compAnims

/-- The original's frame: the faithful probe, one hit test, and the changes `pes` the `pointer-events` toggle leaves.

$$\operatorname{orig}(c, \mathit{pes}) = \operatorname{frame}(c, \mathit{probe}_o, 1, \mathit{pes})$$
-/
def origFrame {P : Type} (c : NavCtx P) (pes : List (Change P)) : FrameIn P := probeFrame c probeFaithful 1 pes

/-- hit-skip's decision: skip the hit test when `morph > 0.2` (`logic.ts` `skipHitTest`).

$$\operatorname{skip}(m) = \mathrm{true} \iff m > \tfrac{1}{5}$$

Whether hit-skip drops the probe at morph `m`. -/
def skipHitTest (m : Rat) : Bool := decide (m > 1 / 5)

#guard skipHitTest (1 / 5) == false
#guard skipHitTest (21 / 100) == true
#guard skipHitTest 0 == false
#guard skipHitTest 1 == true

/-- hit-skip's frame: no probe, no hit test and no toggle when it skips; otherwise the original's frame.

$$\operatorname{hitSkip}(c, m, \mathit{pes}) = \begin{cases} \operatorname{frame}(c, [\,], 0, [\,]) & m > \tfrac{1}{5} \\ \operatorname{orig}(c, \mathit{pes}) & \text{otherwise} \end{cases}$$
-/
def hitSkipFrame {P : Type} (c : NavCtx P) (m : Rat) (pes : List (Change P)) : FrameIn P :=
  if skipHitTest m then probeFrame c [] 0 [] else origFrame c pes

/-- elements-skip's frame: the elements probe, one hit test, no toggle.

$$\operatorname{elements}(c) = \operatorname{frame}(c, \mathit{probe}_e, 1, [\,])$$
-/
def elementsFrame {P : Type} (c : NavCtx P) : FrameIn P := probeFrame c probeElements 1 []

/-! ## Frame work, every engine -/

/-- Every change list covers itself.

$$\forall \varepsilon,\ \forall L \in \mathrm{Change}(P)^{*}:\ \operatorname{cover}_\varepsilon(L, L) = \mathrm{true}$$

A list of changes is its own pairwise cover. -/
theorem coverB_refl {P M : Type} (ε : Engine P M) : ∀ l : List (Change P), coverB ε l l = true
  | [] => rfl
  | c :: cs => by simp [coverB, coverB_refl ε cs]

/-- The variants' changes plus the toggle's changes are the original's changes.

$$\forall c \in \mathrm{NavCtx}(P),\ \forall \mathit{pes}:\ (c.\mathrm{changes} \mathbin{+\!\!+} [\,]) \mathbin{+\!\!+} \mathit{pes} \sim \operatorname{orig}(c, \mathit{pes}).\mathrm{changes}$$

The original's changes split into the shared ones and the toggle's. -/
theorem orig_perm {P : Type} (c : NavCtx P) (pes : List (Change P)) :
    ((c.changes ++ []) ++ pes).Perm (origFrame c pes).changes := by
  rw [List.append_nil]; exact List.Perm.refl _

/-- Strictness from forced style: under the hypotheses of `frame_le_of_cover`, fewer forced style passes give
strictly less frame work.

$$\forall \varepsilon,\ \forall v, o,\ \forall m, r:\ (m \mathbin{+\!\!+} r) \sim o.\mathrm{changes} \land \operatorname{cover}_\varepsilon(v.\mathrm{changes}, m) = \mathrm{true} \land v.\mathrm{script} \le o.\mathrm{script} \land v.\mathrm{forcedStyle} < o.\mathrm{forcedStyle} \land v.\mathrm{forcedLayout} \le o.\mathrm{forcedLayout} \land v.\mathrm{hits} \le o.\mathrm{hits} \land v.\mathrm{compAnims} \le o.\mathrm{compAnims} \Rightarrow \operatorname{frameWork}_\varepsilon(v) \prec \operatorname{frameWork}_\varepsilon(o)$$

A frame with fewer forced style passes and nothing else more does strictly less work. -/
theorem frame_lt_of_style {P M : Type} (ε : Engine P M) {v o : FrameIn P} (m rest : List (Change P))
    (hperm : (m ++ rest).Perm o.changes) (hcov : coverB ε v.changes m = true)
    (hs : v.script ≤ o.script) (hfs : v.forcedStyle < o.forcedStyle) (hfl : v.forcedLayout ≤ o.forcedLayout)
    (hh : v.hits ≤ o.hits) (hc : v.compAnims ≤ o.compAnims) :
    (frameWork ε v).lt (frameWork ε o) := by
  refine ⟨frame_le_of_cover ε m rest hperm hcov hs (Nat.le_of_lt hfs) hfl hh hc, Or.inl ⟨.style, Or.inl ?_⟩⟩
  have h := (frame_le_of_cover ε (v := { v with forcedStyle := o.forcedStyle }) m rest hperm hcov hs
    (Nat.le_refl _) hfl hh hc).1 .style
  have ht : touched ε { v with forcedStyle := o.forcedStyle } = touched ε v := rfl
  simp only [frameWork, forcedPasses, ht] at h ⊢
  omega

/-- Strictness from hit tests: under the hypotheses of `frame_le_of_cover`, fewer hit tests give strictly less work.

$$\forall \varepsilon,\ \forall v, o,\ \forall m, r:\ (m \mathbin{+\!\!+} r) \sim o.\mathrm{changes} \land \operatorname{cover}_\varepsilon(v.\mathrm{changes}, m) = \mathrm{true} \land v.\mathrm{script} \le o.\mathrm{script} \land v.\mathrm{forcedStyle} \le o.\mathrm{forcedStyle} \land v.\mathrm{forcedLayout} \le o.\mathrm{forcedLayout} \land v.\mathrm{hits} < o.\mathrm{hits} \land v.\mathrm{compAnims} \le o.\mathrm{compAnims} \Rightarrow \operatorname{frameWork}_\varepsilon(v) \prec \operatorname{frameWork}_\varepsilon(o)$$

A frame with fewer hit tests and nothing else more does strictly less work. -/
theorem frame_lt_of_hits {P M : Type} (ε : Engine P M) {v o : FrameIn P} (m rest : List (Change P))
    (hperm : (m ++ rest).Perm o.changes) (hcov : coverB ε v.changes m = true)
    (hs : v.script ≤ o.script) (hfs : v.forcedStyle ≤ o.forcedStyle) (hfl : v.forcedLayout ≤ o.forcedLayout)
    (hh : v.hits < o.hits) (hc : v.compAnims ≤ o.compAnims) :
    (frameWork ε v).lt (frameWork ε o) :=
  ⟨frame_le_of_cover ε m rest hperm hcov hs hfs hfl (Nat.le_of_lt hh) hc, Or.inr hh⟩

/-- **hit-skip, one frame, any engine, any morph:** never more work than the original.

$$\forall \varepsilon,\ \forall c \in \mathrm{NavCtx}(P),\ \forall m \in \mathbb{Q},\ \forall \mathit{pes} \in \mathrm{Change}(P)^{*}:\ \operatorname{frameWork}_\varepsilon(\operatorname{hitSkip}(c, m, \mathit{pes})) \preceq \operatorname{frameWork}_\varepsilon(\operatorname{orig}(c, \mathit{pes}))$$

hit-skip never costs more than the original in any frame. -/
theorem hitSkip_le_any {P M : Type} (ε : Engine P M) (c : NavCtx P) (m : Rat) (pes : List (Change P)) :
    (frameWork ε (hitSkipFrame c m pes)).le (frameWork ε (origFrame c pes)) := by
  unfold hitSkipFrame
  split
  · exact frame_le_of_cover ε (c.changes ++ []) pes (orig_perm c pes) (coverB_refl ε _) (Nat.le_refl _)
      (Nat.le_of_succ_le (skip_style_lt c.pre c.post c.dS)) (skip_layout_le c.pre c.post c.dL)
      (Nat.le_succ c.hits) (Nat.le_refl _)
  · exact Work.le_refl _

/-- **hit-skip, one frame, any engine:** when it skips (`morph > 0.2`), strictly less work: one hit test and at least
one forced style recalc fewer.

$$\forall \varepsilon,\ \forall c \in \mathrm{NavCtx}(P),\ \forall m \in \mathbb{Q},\ \forall \mathit{pes} \in \mathrm{Change}(P)^{*}:\ m > \tfrac{1}{5} \Rightarrow \operatorname{frameWork}_\varepsilon(\operatorname{hitSkip}(c, m, \mathit{pes})) \prec \operatorname{frameWork}_\varepsilon(\operatorname{orig}(c, \mathit{pes}))$$

A skipped frame is strictly cheaper than the original's frame. -/
theorem hitSkip_lt_any {P M : Type} (ε : Engine P M) (c : NavCtx P) (m : Rat) (pes : List (Change P))
    (hm : m > 1 / 5) : (frameWork ε (hitSkipFrame c m pes)).lt (frameWork ε (origFrame c pes)) := by
  have hk : skipHitTest m = true := by simp [skipHitTest, hm]
  simp only [hitSkipFrame, hk, ↓reduceIte]
  exact frame_lt_of_hits ε (c.changes ++ []) pes (orig_perm c pes) (coverB_refl ε _) (Nat.le_refl _)
    (Nat.le_of_succ_le (skip_style_lt c.pre c.post c.dS)) (skip_layout_le c.pre c.post c.dL)
    (Nat.lt_succ_self c.hits) (Nat.le_refl _)

/-- **elements-skip, one frame, any engine:** strictly less work, at least one forced style recalc fewer, the same
hit tests.

$$\forall \varepsilon,\ \forall c \in \mathrm{NavCtx}(P),\ \forall \mathit{pes} \in \mathrm{Change}(P)^{*}:\ \operatorname{frameWork}_\varepsilon(\operatorname{elements}(c)) \prec \operatorname{frameWork}_\varepsilon(\operatorname{orig}(c, \mathit{pes}))$$

Every elements-skip frame is strictly cheaper than the original's frame. -/
theorem elementsSkip_lt_any {P M : Type} (ε : Engine P M) (c : NavCtx P) (pes : List (Change P)) :
    (frameWork ε (elementsFrame c)).lt (frameWork ε (origFrame c pes)) :=
  frame_lt_of_style ε (c.changes ++ []) pes (orig_perm c pes) (coverB_refl ε _) (Nat.le_refl _)
    (elements_style_lt c.pre c.post c.dS) (Nat.le_of_eq (elements_layout_eq c.pre c.post c.dL))
    (Nat.le_refl _) (Nat.le_refl _)

/-! ## The two engines -/

/-- **hit-skip work (NH-W), Chromium and WebKit, every frame context:** a skipped frame does strictly less work on
both engines (that no frame does more is `hitSkip_le_any`).

$$\forall m \in \mathbb{Q}:\ m > \tfrac{1}{5} \Rightarrow \Big(\forall c \in \mathrm{NavCtx}(\mathrm{CrProp}),\ \forall \mathit{pes}:\ \operatorname{frameWork}_{\mathrm{cr}}(\operatorname{hitSkip}(c, m, \mathit{pes})) \prec \operatorname{frameWork}_{\mathrm{cr}}(\operatorname{orig}(c, \mathit{pes}))\Big) \land \Big(\forall c \in \mathrm{NavCtx}(\mathrm{WkProp}),\ \forall \mathit{pes}:\ \operatorname{frameWork}_{\mathrm{wk}}(\operatorname{hitSkip}(c, m, \mathit{pes})) \prec \operatorname{frameWork}_{\mathrm{wk}}(\operatorname{orig}(c, \mathit{pes}))\Big)$$

On Chromium and WebKit, hit-skip is strictly cheaper in every frame where morph is past 0.2. -/
theorem hitSkip_work_lt (m : Rat) (hm : m > 1 / 5) :
    (∀ (c : NavCtx Chromium.CrProp) pes,
      (frameWork Chromium.chromium (hitSkipFrame c m pes)).lt (frameWork Chromium.chromium (origFrame c pes))) ∧
    (∀ (c : NavCtx WebKit.WkProp) pes,
      (frameWork WebKit.webkit (hitSkipFrame c m pes)).lt (frameWork WebKit.webkit (origFrame c pes))) :=
  ⟨fun c pes => hitSkip_lt_any _ c m pes hm, fun c pes => hitSkip_lt_any _ c m pes hm⟩

/-- **elements-skip work (NH-W), Chromium and WebKit, every frame context:** every frame does strictly less work on
both engines.

$$\Big(\forall c \in \mathrm{NavCtx}(\mathrm{CrProp}),\ \forall \mathit{pes}:\ \operatorname{frameWork}_{\mathrm{cr}}(\operatorname{elements}(c)) \prec \operatorname{frameWork}_{\mathrm{cr}}(\operatorname{orig}(c, \mathit{pes}))\Big) \land \Big(\forall c \in \mathrm{NavCtx}(\mathrm{WkProp}),\ \forall \mathit{pes}:\ \operatorname{frameWork}_{\mathrm{wk}}(\operatorname{elements}(c)) \prec \operatorname{frameWork}_{\mathrm{wk}}(\operatorname{orig}(c, \mathit{pes}))\Big)$$

On Chromium and WebKit, elements-skip is strictly cheaper in every frame. -/
theorem elementsSkip_work_lt :
    (∀ (c : NavCtx Chromium.CrProp) pes,
      (frameWork Chromium.chromium (elementsFrame c)).lt (frameWork Chromium.chromium (origFrame c pes))) ∧
    (∀ (c : NavCtx WebKit.WkProp) pes,
      (frameWork WebKit.webkit (elementsFrame c)).lt (frameWork WebKit.webkit (origFrame c pes))) :=
  ⟨fun c pes => elementsSkip_lt_any _ c pes, fun c pes => elementsSkip_lt_any _ c pes⟩

/-! ## Runs -/

/-- Frame-by-frame `≤` over a mapped list gives `leAll`.

$$\forall f, g : \alpha \to \mathrm{Work},\ \forall X \in \alpha^{*}:\ (\forall x \in X:\ f(x) \preceq g(x)) \Rightarrow \operatorname{leAll}(\operatorname{map} f\, X, \operatorname{map} g\, X) = \mathrm{true}$$

Aligned frames that are each no costlier give an all-frames comparison. -/
theorem leAll_map {α : Type} (f g : α → Work) :
    ∀ xs : List α, (∀ x ∈ xs, (f x).le (g x)) → leAll (xs.map f) (xs.map g) = true
  | [], _ => rfl
  | x :: xs, h => by
    simp only [List.map_cons, leAll, Bool.and_eq_true]
    exact ⟨(Work.leb_iff _ _).mpr (h x (by simp)), leAll_map f g xs (fun y hy => h y (by simp [hy]))⟩

/-- One strictly cheaper frame in a mapped list gives `someLt`.

$$\forall f, g : \alpha \to \mathrm{Work},\ \forall X \in \alpha^{*}:\ (\exists x \in X:\ f(x) \prec g(x)) \Rightarrow \operatorname{someLt}(\operatorname{map} f\, X, \operatorname{map} g\, X) = \mathrm{true}$$

One strictly cheaper aligned frame is found by `someLt`. -/
theorem someLt_map {α : Type} (f g : α → Work) :
    ∀ xs : List α, (∃ x ∈ xs, (f x).lt (g x)) → someLt (xs.map f) (xs.map g) = true
  | [], ⟨_, hx, _⟩ => by simp at hx
  | x :: xs, ⟨y, hy, hlt⟩ => by
    have hrec : someLt (xs.map f) (xs.map g) = (xs.map f |>.zip (xs.map g)).any fun p => p.1.ltb p.2 := rfl
    simp only [List.map_cons, someLt, List.zip_cons_cons, List.any_cons, Bool.or_eq_true]
    rcases List.mem_cons.mp hy with rfl | hy'
    · exact Or.inl ((Work.ltb_iff _ _).mpr hlt)
    · exact Or.inr (hrec ▸ someLt_map f g xs ⟨y, hy', hlt⟩)

/-- **hit-skip, a whole run, any engine:** if some frame has morph past 0.2, the run screen says the variant
dominates.

$$\forall \varepsilon,\ \forall R \in (\mathrm{NavCtx}(P) \times \mathbb{Q} \times \mathrm{Change}(P)^{*})^{*}:\ \big(\exists (c, m, \mathit{pes}) \in R:\ m > \tfrac{1}{5}\big) \Rightarrow \operatorname{screen}\big(\operatorname{toRun}[\operatorname{frameWork}_\varepsilon(\operatorname{orig}(c, \mathit{pes}))]_{(c, m, \mathit{pes}) \in R},\ \operatorname{toRun}[\operatorname{frameWork}_\varepsilon(\operatorname{hitSkip}(c, m, \mathit{pes}))]_{(c, m, \mathit{pes}) \in R}\big) = \mathrm{ok}(\mathrm{dominates})$$

A run with one skipped frame is screened as dominated by hit-skip. -/
theorem hitSkip_run_dominates_any {P M : Type} (ε : Engine P M) (run : List (NavCtx P × Rat × List (Change P)))
    (h : ∃ x ∈ run, x.2.1 > 1 / 5) :
    Screen.screen (toRun (run.map fun x => frameWork ε (origFrame x.1 x.2.2)))
      (toRun (run.map fun x => frameWork ε (hitSkipFrame x.1 x.2.1 x.2.2))) = .ok .dominates :=
  run_dominates (leAll_map _ _ run fun x _ => hitSkip_le_any ε x.1 x.2.1 x.2.2)
    (someLt_map _ _ run (let ⟨x, hx, hm⟩ := h; ⟨x, hx, hitSkip_lt_any ε x.1 x.2.1 x.2.2 hm⟩))

/-- **elements-skip, a whole run, any engine:** every non-empty run is screened as dominated.

$$\forall \varepsilon,\ \forall R \in (\mathrm{NavCtx}(P) \times \mathrm{Change}(P)^{*})^{*}:\ R \ne [\,] \Rightarrow \operatorname{screen}\big(\operatorname{toRun}[\operatorname{frameWork}_\varepsilon(\operatorname{orig}(c, \mathit{pes}))]_{(c, \mathit{pes}) \in R},\ \operatorname{toRun}[\operatorname{frameWork}_\varepsilon(\operatorname{elements}(c))]_{(c, \mathit{pes}) \in R}\big) = \mathrm{ok}(\mathrm{dominates})$$

Any run with at least one frame is screened as dominated by elements-skip. -/
theorem elementsSkip_run_dominates_any {P M : Type} (ε : Engine P M) (run : List (NavCtx P × List (Change P)))
    (h : run ≠ []) :
    Screen.screen (toRun (run.map fun x => frameWork ε (origFrame x.1 x.2)))
      (toRun (run.map fun x => frameWork ε (elementsFrame x.1))) = .ok .dominates := by
  obtain ⟨x, xs, rfl⟩ := List.exists_cons_of_ne_nil h
  exact run_dominates (leAll_map _ _ _ fun y _ => (elementsSkip_lt_any ε y.1 y.2).1)
    (someLt_map _ _ _ ⟨x, List.mem_cons_self .., elementsSkip_lt_any ε x.1 x.2⟩)

/-- **hit-skip run dominance (NH-W), Chromium and WebKit.**

$$\Big(\forall R \in (\mathrm{NavCtx}(\mathrm{CrProp}) \times \mathbb{Q} \times \mathrm{Change}(\mathrm{CrProp})^{*})^{*}:\ \big(\exists (c, m, \mathit{pes}) \in R:\ m > \tfrac{1}{5}\big) \Rightarrow \operatorname{screen}\big(\operatorname{toRun}[\operatorname{frameWork}_{\mathrm{cr}}(\operatorname{orig}(c, \mathit{pes}))]_{R},\ \operatorname{toRun}[\operatorname{frameWork}_{\mathrm{cr}}(\operatorname{hitSkip}(c, m, \mathit{pes}))]_{R}\big) = \mathrm{ok}(\mathrm{dominates})\Big) \land \Big(\text{the same for } \mathrm{WkProp} \text{ and } \operatorname{frameWork}_{\mathrm{wk}}\Big)$$

On both engines, a run with one frame past morph 0.2 is screened as dominated by hit-skip. -/
theorem hitSkip_run_dominates :
    (∀ run : List (NavCtx Chromium.CrProp × Rat × List (Change Chromium.CrProp)), (∃ x ∈ run, x.2.1 > 1 / 5) →
      Screen.screen (toRun (run.map fun x => frameWork Chromium.chromium (origFrame x.1 x.2.2)))
        (toRun (run.map fun x => frameWork Chromium.chromium (hitSkipFrame x.1 x.2.1 x.2.2))) = .ok .dominates) ∧
    (∀ run : List (NavCtx WebKit.WkProp × Rat × List (Change WebKit.WkProp)), (∃ x ∈ run, x.2.1 > 1 / 5) →
      Screen.screen (toRun (run.map fun x => frameWork WebKit.webkit (origFrame x.1 x.2.2)))
        (toRun (run.map fun x => frameWork WebKit.webkit (hitSkipFrame x.1 x.2.1 x.2.2))) = .ok .dominates) :=
  ⟨fun run h => hitSkip_run_dominates_any _ run h, fun run h => hitSkip_run_dominates_any _ run h⟩

/-- **elements-skip run dominance (NH-W), Chromium and WebKit.**

$$\Big(\forall R \in (\mathrm{NavCtx}(\mathrm{CrProp}) \times \mathrm{Change}(\mathrm{CrProp})^{*})^{*}:\ R \ne [\,] \Rightarrow \operatorname{screen}\big(\operatorname{toRun}[\operatorname{frameWork}_{\mathrm{cr}}(\operatorname{orig}(c, \mathit{pes}))]_{R},\ \operatorname{toRun}[\operatorname{frameWork}_{\mathrm{cr}}(\operatorname{elements}(c))]_{R}\big) = \mathrm{ok}(\mathrm{dominates})\Big) \land \Big(\text{the same for } \mathrm{WkProp} \text{ and } \operatorname{frameWork}_{\mathrm{wk}}\Big)$$

On both engines, every non-empty run is screened as dominated by elements-skip. -/
theorem elementsSkip_run_dominates :
    (∀ run : List (NavCtx Chromium.CrProp × List (Change Chromium.CrProp)), run ≠ [] →
      Screen.screen (toRun (run.map fun x => frameWork Chromium.chromium (origFrame x.1 x.2)))
        (toRun (run.map fun x => frameWork Chromium.chromium (elementsFrame x.1))) = .ok .dominates) ∧
    (∀ run : List (NavCtx WebKit.WkProp × List (Change WebKit.WkProp)), run ≠ [] →
      Screen.screen (toRun (run.map fun x => frameWork WebKit.webkit (origFrame x.1 x.2)))
        (toRun (run.map fun x => frameWork WebKit.webkit (elementsFrame x.1))) = .ok .dominates) :=
  ⟨fun run h => elementsSkip_run_dominates_any _ run h, fun run h => elementsSkip_run_dominates_any _ run h⟩

/-! ## Write on change -/

/-- A frame with the `is-on-dark` class write `w` added when `b` holds.

$$\operatorname{withWrite}(f, w, b) = f \text{ with } \mathrm{changes} := f.\mathrm{changes} \mathbin{+\!\!+} \begin{cases} [w] & b \\ [\,] & \text{otherwise} \end{cases}$$
-/
def withWrite {P : Type} (f : FrameIn P) (w : Change P) (b : Bool) : FrameIn P :=
  { f with changes := f.changes ++ (if b then [w] else []) }

/-- **Write on change, any engine:** writing the class only when it changes never costs more than writing it every
frame, and leaves the same class.

$$\forall \varepsilon,\ \forall f, w,\ \forall p, n \in \mathbb{B}:\ \operatorname{frameWork}_\varepsilon(\operatorname{withWrite}(f, w, p \ne n)) \preceq \operatorname{frameWork}_\varepsilon(\operatorname{withWrite}(f, w, \mathrm{true})) \ \land\ \begin{cases} n & p \ne n \\ p & \text{otherwise} \end{cases} = n$$

Skipping an unchanged class write saves work and shows the same class. -/
theorem writeOnChange_le {P M : Type} (ε : Engine P M) (f : FrameIn P) (w : Change P) (p n : Bool) :
    (frameWork ε (withWrite f w (changed p n))).le (frameWork ε (withWrite f w true)) ∧
      (if changed p n then n else p) = n := by
  refine ⟨?_, changed_write p n⟩
  cases changed p n
  · exact frame_le_of_cover ε (f.changes ++ []) [w] (by simp [withWrite])
      (coverB_refl ε _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _)
  · exact Work.le_refl _

/-! ## The visual side in the `VisSame` shape -/

/-- hit-skip's hit answer: the stale answer when it skips, else the fresh one.

$$\operatorname{answer}(s, g, m) = \begin{cases} s & m > \tfrac{1}{5} \\ g & \text{otherwise} \end{cases}$$

The hit answer hit-skip uses at morph `m`. -/
def hitSkipAnswer (stale fresh : Bool) (m : Rat) : Bool := if skipHitTest m then stale else fresh

#guard hitSkipAnswer true false (1 / 2) == true
#guard hitSkipAnswer true false (1 / 5) == false
#guard isOnDark (hitSkipAnswer false true (1 / 2)) (1 / 2) == isOnDark true (1 / 2)

/-- hit-skip shows the same `is-on-dark` value as the original, for every stale answer.

$$\forall s, g \in \mathbb{B},\ \forall m \in \mathbb{Q}:\ \operatorname{isOnDark}(\operatorname{answer}(s, g, m), m) = \operatorname{isOnDark}(g, m)$$

The stale answer never shows. -/
theorem hitSkipAnswer_onDark (s g : Bool) (m : Rat) : isOnDark (hitSkipAnswer s g m) m = isOnDark g m := by
  unfold hitSkipAnswer
  by_cases h : m > 1 / 5
  · have hk : skipHitTest m = true := by simp [skipHitTest, h]
    simp only [hk, ↓reduceIte]
    exact (hitSkip_morph s g m h).1
  · have hk : skipHitTest m = false := by simp [skipHitTest, h]
    simp only [hk, Bool.false_eq_true, ↓reduceIte]

/-- **hit-skip is visually E-equal (`VisSame` under E):** for every environment (width band, touch, DPR) and instant,
the scene drawn from the original's `is-on-dark` and the one drawn from hit-skip's are equal after the viewport cut.

$$\forall \mathit{vp},\ \forall \mathit{scene},\ \forall \mathit{fresh}, \mathit{stale} : \mathrm{Env} \to T \to \mathbb{B},\ \forall \mathit{morph} : \mathrm{Env} \to T \to \mathbb{Q}:\ \operatorname{VisSame}_{\mathrm{E}}\big(\mathit{vp},\ (\mathit{env}, t) \mapsto \mathit{scene}(\mathit{env}, t, \operatorname{isOnDark}(\mathit{fresh}(\mathit{env}, t), \mathit{morph}(\mathit{env}, t))),\ (\mathit{env}, t) \mapsto \mathit{scene}(\mathit{env}, t, \operatorname{isOnDark}(\operatorname{answer}(\mathit{stale}(\mathit{env}, t), \mathit{fresh}(\mathit{env}, t), \mathit{morph}(\mathit{env}, t)), \mathit{morph}(\mathit{env}, t)))\big)$$

hit-skip draws exactly what the original draws, at every width and instant. -/
theorem hitSkip_visSame {Env T : Type} (vp : Env → Fw.Engine.Rect) (scene : Env → T → Bool → Scene)
    (fresh stale : Env → T → Bool) (morph : Env → T → Rat) :
    VisSame E vp (fun env t => scene env t (isOnDark (fresh env t) (morph env t)))
      (fun env t => scene env t (isOnDark (hitSkipAnswer (stale env t) (fresh env t) (morph env t)) (morph env t))) :=
  visSame_of_eq vp fun env t => by rw [hitSkipAnswer_onDark]

/-- **elements-skip is visually E-equal (`VisSame` under E):** if, at every environment and instant, the allow-list
agrees with the re-enabled flag on the boxes inside the nav, the scene drawn from the faithful hit index and the one
drawn from the allow-list index are equal after the viewport cut.

$$\forall \mathit{vp},\ \forall \mathit{scene},\ \forall \mathit{stack} : \mathrm{Env} \to T \to \mathrm{Hit}^{*},\ \forall \mathit{allow}:\ \big(\forall \mathit{env}, t,\ \forall b \in \mathit{stack}(\mathit{env}, t):\ b.\mathrm{insideNav} \Rightarrow \mathit{allow}(b) = b.\mathrm{reEnabled}\big) \Rightarrow \operatorname{VisSame}_{\mathrm{E}}\big(\mathit{vp},\ (\mathit{env}, t) \mapsto \mathit{scene}(\mathit{env}, t, \operatorname{faithfulHit}(\mathit{stack}(\mathit{env}, t))),\ (\mathit{env}, t) \mapsto \mathit{scene}(\mathit{env}, t, \operatorname{allowHit}_{\mathit{allow}}(\mathit{stack}(\mathit{env}, t)))\big)$$

With a correct allow-list, elements-skip draws exactly what the original draws, at every width and instant. -/
theorem elementsSkip_visSame {Env T : Type} (vp : Env → Fw.Engine.Rect) (scene : Env → T → Int → Scene)
    (stack : Env → T → List Hit) (allow : Hit → Bool)
    (h : ∀ env t, ∀ b ∈ stack env t, b.insideNav = true → allow b = b.reEnabled) :
    VisSame E vp (fun env t => scene env t (faithfulHit (stack env t)))
      (fun env t => scene env t (allowHit allow (stack env t))) :=
  visSame_of_eq vp fun env t => by rw [allowHit_eq_faithful allow (stack env t) (h env t)]

/-- The port's allow-list reads the re-enabled flag itself, so elements-skip is E-equal with no further premise.

$$\forall \mathit{vp},\ \forall \mathit{scene},\ \forall \mathit{stack}:\ \operatorname{VisSame}_{\mathrm{E}}\big(\mathit{vp},\ (\mathit{env}, t) \mapsto \mathit{scene}(\mathit{env}, t, \operatorname{faithfulHit}(\mathit{stack}(\mathit{env}, t))),\ (\mathit{env}, t) \mapsto \mathit{scene}(\mathit{env}, t, \operatorname{allowHit}_{b \mapsto b.\mathrm{reEnabled}}(\mathit{stack}(\mathit{env}, t)))\big)$$

`probe.ts` passes `h => h.reEnabled`, which meets the premise trivially. -/
theorem elementsSkip_visSame_port {Env T : Type} (vp : Env → Fw.Engine.Rect) (scene : Env → T → Int → Scene)
    (stack : Env → T → List Hit) :
    VisSame E vp (fun env t => scene env t (faithfulHit (stack env t)))
      (fun env t => scene env t (allowHit (·.reEnabled) (stack env t))) :=
  elementsSkip_visSame vp scene stack _ fun _ _ _ _ _ => rfl

/-! ## Golden prediction rows for `engine-check` -/

/-- One golden row in the `engine-check` schema, with the comparison base.

$$\mathrm{Row} = \mathrm{String}^{7}$$
-/
structure Row where
  engine     : String
  scenario   : String
  variant    : String
  stage      : String
  prediction : String
  countType  : String
  base       : String
deriving Repr, DecidableEq

/-- The Chromium count types and the model stage and prediction for each, per variant. `trace.Layout` is not in the
rewrite arm's frozen classes, so its rows come back unusable until it is.

$$\mathrm{crTypes} = [(\text{trace.FunctionCall}, \mathrm{script}, =o, =o), (\text{trace.FireAnimationFrame}, \mathrm{script}, =o, =o), (\text{trace.UpdateLayoutTree}, \mathrm{style}, <o, <o), (\text{trace.Layout}, \mathrm{layout}, \le o, \le o), (\text{trace.PrePaint}, \mathrm{paint}, \le o, \le o), (\text{trace.Paint}, \mathrm{paint}, \le o, \le o), (\text{raster.invalidationAreaPx}, \mathrm{raster}, \le o, \le o), (\text{trace.cc.Commit}, \mathrm{commit}, \le o, \le o), (\text{trace.HitTest}, \mathrm{hits}, <o, =o)]$$
-/
def crTypes : List (String × String × String × String) :=
  [("trace.FunctionCall", "script", "=o", "=o"), ("trace.FireAnimationFrame", "script", "=o", "=o"),
   ("trace.UpdateLayoutTree", "style", "<o", "<o"), ("trace.Layout", "layout", "≤o", "≤o"),
   ("trace.PrePaint", "paint", "≤o", "≤o"), ("trace.Paint", "paint", "≤o", "≤o"),
   ("raster.invalidationAreaPx", "raster", "≤o", "≤o"), ("trace.cc.Commit", "commit", "≤o", "≤o"),
   ("trace.HitTest", "hits", "<o", "=o")]

/-- The WebKit count types (the lane is not wired yet: `engine-check` answers `unusable`).

$$\mathrm{wkTypes} = [(\text{FireAnimationFrame}, \mathrm{script}, =o, =o), (\text{RecalculateStyles}, \mathrm{style}, <o, <o), (\text{Layout}, \mathrm{layout}, \le o, \le o), (\text{Paint}, \mathrm{paint}, \le o, \le o), (\text{Composite}, \mathrm{commit}, \le o, \le o)]$$
-/
def wkTypes : List (String × String × String × String) :=
  [("FireAnimationFrame", "script", "=o", "=o"), ("RecalculateStyles", "style", "<o", "<o"),
   ("Layout", "layout", "≤o", "≤o"), ("Paint", "paint", "≤o", "≤o"), ("Composite", "commit", "≤o", "≤o")]

/-- The variant key of a nav.hitTest flag variant in the rewrite (`meta.target + "+" + search`).

$$\operatorname{key}(n) = \texttt{rewrite+?fw=nav.hitTest:} \mathbin{+\!\!+} n$$
-/
def variantKey (n : String) : String := "rewrite+?fw=nav.hitTest:" ++ n

#guard variantKey "hit-skip" == "rewrite+?fw=nav.hitTest:hit-skip"

/-- The golden rows: per engine, per variant (hit-skip, elements-skip), per count type, scenario `swipe-v1`, base the
faithful rewrite.

$$\mathrm{rows} = [\,(\mathit{eng}, \texttt{swipe-v1}, \operatorname{key}(n), s, p_n, k, \texttt{rewrite}) \mid (\mathit{eng}, T) \in [(\mathrm{chromium}, \mathrm{crTypes}), (\mathrm{webkit}, \mathrm{wkTypes})],\ n \in [\text{hit-skip}, \text{elements-skip}],\ (k, s, p_{\text{hit-skip}}, p_{\text{elements-skip}}) \in T\,]$$
-/
def goldenRows : List Row :=
  [("chromium", crTypes), ("webkit", wkTypes)].flatMap fun (eng, ts) =>
    ["hit-skip", "elements-skip"].flatMap fun n =>
      ts.map fun (k, s, ph, pe) =>
        ⟨eng, "swipe-v1", variantKey n, s, if n == "hit-skip" then ph else pe, k, "rewrite"⟩

/-- One row as compact JSON (keys sorted by the JSON writer).

$$\operatorname{json}(r) = \{\mathrm{base}, \mathrm{countType}, \mathrm{engine}, \mathrm{prediction}, \mathrm{scenario}, \mathrm{stage}, \mathrm{variant}\}$$
-/
def Row.json (r : Row) : String :=
  (Json.mkObj [("engine", .str r.engine), ("scenario", .str r.scenario), ("variant", .str r.variant),
    ("stage", .str r.stage), ("prediction", .str r.prediction), ("countType", .str r.countType),
    ("base", .str r.base)]).compress

/-- The contents of `packages/contracts/golden/engine/nav-hittest.jsonl`: one JSON row per line, newline-terminated.

$$\mathrm{goldenJsonl} = \mathop{\Vert}_{r \in \mathrm{rows}} \big(\operatorname{json}(r) \mathbin{+\!\!+} \texttt{\textbackslash n}\big)$$
-/
def goldenJsonl : String := String.join (goldenRows.map fun r => r.json ++ "\n")

/-! ### Rows against the model on a sample frame -/

/-- The model quantity a count type reads from a frame's work.

$$\operatorname{read}(\mathrm{st}, w) = \begin{cases} w.\mathrm{units}(\mathrm{script}) & \mathrm{st} = \text{script} \\ w.\mathrm{hits} & \mathrm{st} = \text{hits} \\ w.\mathrm{units}(\mathrm{raster}) & \mathrm{st} = \text{raster} \\ w.\mathrm{passes}(s) & \mathrm{st} \text{ names stage } s \in \{\mathrm{style}, \mathrm{layout}, \mathrm{paint}, \mathrm{commit}\} \\ 0 & \text{otherwise} \end{cases}$$
-/
def readStage (st : String) (w : Work) : Nat :=
  match st with
  | "script" => w.units .script
  | "hits" => w.hits
  | "raster" => w.units .raster
  | "style" => w.passes .style
  | "layout" => w.passes .layout
  | "paint" => w.passes .paint
  | "commit" => w.passes .commit
  | _ => 0

/-- Whether a prediction holds for a variant value `v` and base value `o`.

$$\operatorname{holds}(p, v, o) = \begin{cases} v = o & p = \text{"=o"} \\ v < o & p = \text{"<o"} \\ v \le o & p = \text{"≤o"} \\ v = 0 & p = \text{"=0"} \\ \mathrm{true} & p = \text{"any"} \\ \mathrm{false} & \text{otherwise} \end{cases}$$
-/
def holds (p : String) (v o : Nat) : Bool :=
  match p with
  | "=o" => v == o
  | "<o" => decide (v < o)
  | "≤o" => decide (v ≤ o)
  | "=0" => v == 0
  | "any" => true
  | _ => false

#guard holds "<o" 1 2 && !holds "<o" 2 2 && holds "≤o" 2 2 && holds "=o" 3 3 && !holds "x" 0 0

/-- The sample frame context: the original's nav callback around the probe, clean start, one callback.

$$c_0 = (\mathit{ee}, \mathit{track}, \mathrm{false}, \mathrm{false}, 1, 0, [\,], 0)$$
-/
def sampleCtx : NavCtx Chromium.CrProp := ⟨navEe, navTrack, false, false, 1, 0, [], 0⟩

/-- Whether every Chromium row of variant `n` holds on frames `v` against `o`.

$$\operatorname{rowsHold}(n, v, o) \iff \forall r \in \mathrm{rows}:\ r.\mathrm{engine} = \text{chromium} \land r.\mathrm{variant} = \operatorname{key}(n) \Rightarrow \operatorname{holds}(r.\mathrm{prediction}, \operatorname{read}(r.\mathrm{stage}, v), \operatorname{read}(r.\mathrm{stage}, o))$$
-/
def rowsHold (n : String) (v o : Work) : Bool :=
  goldenRows.all fun r =>
    !(r.engine == "chromium" && r.variant == variantKey n) || holds r.prediction (readStage r.stage v) (readStage r.stage o)

#guard goldenRows.length == 28
#guard rowsHold "hit-skip" (frameWork Chromium.chromium (hitSkipFrame sampleCtx (1 / 2) []))
  (frameWork Chromium.chromium (origFrame sampleCtx []))
#guard rowsHold "elements-skip" (frameWork Chromium.chromium (elementsFrame sampleCtx))
  (frameWork Chromium.chromium (origFrame sampleCtx []))
-- The sample shows the two saved forced style passes.
#guard (frameWork Chromium.chromium (origFrame sampleCtx [])).passes .style ==
  (frameWork Chromium.chromium (elementsFrame sampleCtx)).passes .style + 2

end Fw.Parts.NavHitTestOpt
