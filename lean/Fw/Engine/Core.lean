import Fw.Spec.Screen
import Fw.Spec.Cost
import Fw.Measure.Tolerance
/-!
# The shared core of the engine model (PLAN §4.7, design note 2026-10-18 §1.1 and §3.1)

A frame of a page variant is a `FrameIn`: script callbacks, forced style and layout passes, hit tests, the
main-thread property changes and the running compositor animations. An `Engine` maps each change to the list of
pipeline stages it dirties (`stagesOf`); the Chromium and WebKit tables (`Fw.Engine.Chromium`, `Fw.Engine.WebKit`)
instantiate it, each row citing engine source. `frameWork` turns a frame into a `Work` vector (passes and units per
stage, plus hit tests).

Work dominance is proved on the **per-frame union of stages**, never on an engine's level order: WebKit's stage map is
not monotone in its `StyleDifference` order (design note C-2). The route:
* `frame_le_of_cover`: a cover of the variant's changes by a sub-multiset of the original's changes, stage set by
  stage set, plus `≤` on script, forced passes, hits and compositor animations, gives `Work.le`;
* `frame_le_union`: the decidable union check, closed by `decide` on concrete frames;
* `run_dominates`: `≤` in every frame and `<` in one gives `Screen.screen = ok dominates`, hence `screen_sound`;
* `toCost_mono` / `mainUs_toCost_le`: the bridge into `Cost.mainUs_mono`;
* `claim`: a resident-state increase (layers, backing store) turns "dominates" into "trade";
* `Shift`: work moved across frames, judged by the peak over the motion window and the run total.

Mathlib-free (lakefile): stage sets are lists with decidable membership.
-/
namespace Fw.Engine

/-! ## Types -/

/-- The pipeline stages of one frame. `props` is Chromium's PrePaint property-tree update or WebKit's compositing
update (S3); `commit` is Chromium's `cc.Commit` or WebKit's rendering-update commit; `comp` is the compositor-thread
(Chromium impl) or UI-process (Core Animation) animation tick.

$$\mathrm{Stage} = \{\mathrm{script}, \mathrm{style}, \mathrm{layout}, \mathrm{props}, \mathrm{paint}, \mathrm{raster}, \mathrm{commit}, \mathrm{comp}\}$$
-/
inductive Stage where
  | script | style | layout | props | paint | raster | commit | comp
deriving Repr, DecidableEq, Inhabited

/-- Every stage once, in the fixed order used by `toCounts`.

$$\mathrm{Stage.all} = [\mathrm{script}, \mathrm{style}, \mathrm{layout}, \mathrm{props}, \mathrm{paint}, \mathrm{raster}, \mathrm{commit}, \mathrm{comp}]$$
-/
def Stage.all : List Stage := [.script, .style, .layout, .props, .paint, .raster, .commit, .comp]

/-- The fixed stage order lists every stage.

$$\forall s \in \mathrm{Stage}:\ s \in \mathrm{Stage.all}$$
-/
theorem Stage.mem_all (s : Stage) : s ∈ Stage.all := by
  cases s <;> simp [Stage.all]

/-- The thread a piece of work runs on: the main thread, or the compositor (Chromium impl thread, WebKit UI process).

$$\mathrm{Thread} = \{\mathrm{main}, \mathrm{comp}\}$$
-/
inductive Thread where
  | main | comp
deriving Repr, DecidableEq, Inhabited

/-- The layer state of a change's target box: no layer, a paint layer, or its own composited layer (WebKit
noLayer/layer/composited; Chromium "own cc layer").

$$\mathrm{LayerState} = \{\mathrm{none}, \mathrm{layer}, \mathrm{own}\}$$
-/
inductive LayerState where
  | none | layer | own
deriving Repr, DecidableEq, Inhabited

/-- One main-thread property change in a frame: the target element, the property (the type `P` is chosen by the
engine table), and the target's layer state.

$$\mathrm{Change}(P) = \mathbb{N} \times P \times \mathrm{LayerState}$$
-/
structure Change (P : Type) where
  elem  : Nat
  prop  : P
  layer : LayerState
deriving Repr, DecidableEq

/-- What a variant does in one frame: script callbacks (rAF and listeners, unit `FunctionCall`), forced style and
forced layout passes, hit tests, main-thread property changes, and running compositor animations.

$$\mathrm{FrameIn}(P) = \underbrace{\mathbb{N}}_{\mathrm{script}} \times \underbrace{\mathbb{N}}_{\mathrm{fStyle}} \times \underbrace{\mathbb{N}}_{\mathrm{fLayout}} \times \underbrace{\mathbb{N}}_{\mathrm{hits}} \times \underbrace{\mathrm{Change}(P)^{*}}_{\mathrm{changes}} \times \underbrace{\mathbb{N}}_{\mathrm{compAnims}}$$
-/
structure FrameIn (P : Type) where
  script       : Nat
  forcedStyle  : Nat
  forcedLayout : Nat
  hits         : Nat
  changes      : List (Change P)
  compAnims    : Nat
deriving Repr

/-- **The engine interface** the Chromium and WebKit tables implement. `mode` is the engine's run mode (its own type
`M`, e.g. threaded animation on or off). `stagesOf c` lists the stages change `c` dirties. `compStages` lists the
stages one running compositor animation costs per frame (Chromium lane: `comp` and the style ride-along; WebKit:
`comp` only). `base` lists the stages every frame with a rendering update pays (WebKit: `commit`, "commit even if
nothing changed").

$$\mathrm{Engine}(P, M) = \underbrace{M}_{\mathrm{mode}} \times \underbrace{(\mathrm{Change}(P) \to \mathrm{Stage}^{*})}_{\mathrm{stagesOf}} \times \underbrace{\mathrm{Stage}^{*}}_{\mathrm{compStages}} \times \underbrace{\mathrm{Stage}^{*}}_{\mathrm{base}}$$
-/
structure Engine (P M : Type) where
  mode       : M
  stagesOf   : Change P → List Stage
  compStages : List Stage
  base       : List Stage

/-- The work of one frame: passes and units per stage, plus hit tests.

$$\mathrm{Work} = (\mathrm{Stage} \to \mathbb{N}) \times (\mathrm{Stage} \to \mathbb{N}) \times \mathbb{N},\qquad w = (w.\mathrm{passes}, w.\mathrm{units}, w.\mathrm{hits})$$
-/
structure Work where
  passes : Stage → Nat
  units  : Stage → Nat
  hits   : Nat

/-- Resident state, kept apart from per-frame work: composited layers and backing-store area in kpx.

$$\mathrm{Resident} = \underbrace{\mathbb{N}}_{\mathrm{layers}} \times \underbrace{\mathbb{N}}_{\mathrm{backingKpx}}$$
-/
structure Resident where
  layers     : Nat
  backingKpx : Nat
deriving Repr, DecidableEq

/-! ## Frame work -/

/-- A frame has a rendering update when it has a property change or a script callback.

$$\operatorname{updates}(f) \iff f.\mathrm{changes} \ne [\,] \ \lor\ 0 < f.\mathrm{script}$$
-/
def FrameIn.updates {P : Type} (f : FrameIn P) : Bool := !f.changes.isEmpty || decide (0 < f.script)

/-- The stages a frame touches at least once: the union of its changes' stages, the compositor-animation stages when
an animation runs, the base stages when the frame updates, and `script` when a callback runs.

$$\operatorname{touched}_E(f) = \bigcup_{c \in f.\mathrm{changes}} E.\mathrm{stagesOf}(c) \ \cup\ \begin{cases} E.\mathrm{compStages} & 0 < f.\mathrm{compAnims} \\ \emptyset & \text{otherwise} \end{cases} \ \cup\ \begin{cases} E.\mathrm{base} & \operatorname{updates}(f) \\ \emptyset & \text{otherwise} \end{cases} \ \cup\ \begin{cases} \{\mathrm{script}\} & 0 < f.\mathrm{script} \\ \emptyset & \text{otherwise} \end{cases}$$
-/
def touched {P M : Type} (E : Engine P M) (f : FrameIn P) : List Stage :=
  f.changes.flatMap E.stagesOf ++ (if 0 < f.compAnims then E.compStages else []) ++
    (if f.updates then E.base else []) ++ (if 0 < f.script then [.script] else [])

/-- Extra passes a frame forces: forced style passes on `style`, forced layout passes on `layout`.

$$\operatorname{forced}(f, s) = \begin{cases} f.\mathrm{forcedStyle} & s = \mathrm{style} \\ f.\mathrm{forcedLayout} & s = \mathrm{layout} \\ 0 & \text{otherwise} \end{cases}$$
-/
def forcedPasses {P : Type} (f : FrameIn P) : Stage → Nat
  | .style => f.forcedStyle
  | .layout => f.forcedLayout
  | _ => 0

/-- The units of stage `s` in a frame: the number of changes that dirty `s`, plus the compositor animations when `s`
is one of their stages, plus the callbacks when `s` is `script`.

$$\operatorname{units}_E(f, s) = \big|[\,c \in f.\mathrm{changes} \mid s \in E.\mathrm{stagesOf}(c)\,]\big| + [s \in E.\mathrm{compStages}]\cdot f.\mathrm{compAnims} + [s = \mathrm{script}]\cdot f.\mathrm{script}$$
-/
def stageUnits {P M : Type} (E : Engine P M) (f : FrameIn P) (s : Stage) : Nat :=
  f.changes.countP (fun c => decide (s ∈ E.stagesOf c)) + (if s ∈ E.compStages then f.compAnims else 0) +
    (if s = .script then f.script else 0)

/-- **The work of one frame** under engine `E`: a stage runs once if the frame touches it, plus its forced passes;
units count per `stageUnits`; hit tests are carried over.

$$\operatorname{frameWork}_E(f) = \Big(s \mapsto [s \in \operatorname{touched}_E(f)] + \operatorname{forced}(f, s),\ \ s \mapsto \operatorname{units}_E(f, s),\ \ f.\mathrm{hits}\Big)$$
-/
def frameWork {P M : Type} (E : Engine P M) (f : FrameIn P) : Work where
  passes s := (if s ∈ touched E f then 1 else 0) + forcedPasses f s
  units s := stageUnits E f s
  hits := f.hits

/-! ## Order on work -/

/-- Componentwise order: every stage's passes and units, and the hit tests, at most the other's.

$$a \preceq b \iff \big(\forall s \in \mathrm{Stage}:\ a.\mathrm{passes}(s) \le b.\mathrm{passes}(s) \land a.\mathrm{units}(s) \le b.\mathrm{units}(s)\big) \land a.\mathrm{hits} \le b.\mathrm{hits}$$
-/
def Work.le (a b : Work) : Prop :=
  (∀ s, a.passes s ≤ b.passes s ∧ a.units s ≤ b.units s) ∧ a.hits ≤ b.hits

/-- Strict order: `le` plus one strictly smaller component.

$$a \prec b \iff a \preceq b \land \Big(\big(\exists s \in \mathrm{Stage}:\ a.\mathrm{passes}(s) < b.\mathrm{passes}(s) \lor a.\mathrm{units}(s) < b.\mathrm{units}(s)\big) \lor a.\mathrm{hits} < b.\mathrm{hits}\Big)$$
-/
def Work.lt (a b : Work) : Prop :=
  a.le b ∧ ((∃ s, a.passes s < b.passes s ∨ a.units s < b.units s) ∨ a.hits < b.hits)

/-- The order as a Boolean, checked over the fixed stage list.

$$\operatorname{leb}(a, b) = \mathrm{true} \iff \big(\forall s \in \mathrm{Stage.all}:\ a.\mathrm{passes}(s) \le b.\mathrm{passes}(s) \land a.\mathrm{units}(s) \le b.\mathrm{units}(s)\big) \land a.\mathrm{hits} \le b.\mathrm{hits}$$
-/
def Work.leb (a b : Work) : Bool :=
  Stage.all.all (fun s => decide (a.passes s ≤ b.passes s) && decide (a.units s ≤ b.units s)) &&
    decide (a.hits ≤ b.hits)

/-- The strict order as a Boolean.

$$\operatorname{ltb}(a, b) = \mathrm{true} \iff \operatorname{leb}(a, b) \land \Big(\big(\exists s \in \mathrm{Stage.all}:\ a.\mathrm{passes}(s) < b.\mathrm{passes}(s) \lor a.\mathrm{units}(s) < b.\mathrm{units}(s)\big) \lor a.\mathrm{hits} < b.\mathrm{hits}\Big)$$
-/
def Work.ltb (a b : Work) : Bool :=
  a.leb b &&
    (Stage.all.any (fun s => decide (a.passes s < b.passes s) || decide (a.units s < b.units s)) ||
      decide (a.hits < b.hits))

/-- The Boolean order is the order.

$$\forall a, b \in \mathrm{Work}:\ \operatorname{leb}(a, b) = \mathrm{true} \iff a \preceq b$$
-/
theorem Work.leb_iff (a b : Work) : a.leb b = true ↔ a.le b := by
  simp only [Work.leb, Work.le, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq]
  exact ⟨fun ⟨h, hh⟩ => ⟨fun s => h s (Stage.mem_all s), hh⟩, fun ⟨h, hh⟩ => ⟨fun s _ => h s, hh⟩⟩

/-- The Boolean strict order is the strict order.

$$\forall a, b \in \mathrm{Work}:\ \operatorname{ltb}(a, b) = \mathrm{true} \iff a \prec b$$
-/
theorem Work.ltb_iff (a b : Work) : a.ltb b = true ↔ a.lt b := by
  simp only [Work.ltb, Work.lt, Bool.and_eq_true, Bool.or_eq_true, List.any_eq_true, decide_eq_true_eq,
    Work.leb_iff]
  constructor
  · rintro ⟨hle, ⟨s, _, hs⟩ | hh⟩
    · exact ⟨hle, .inl ⟨s, hs⟩⟩
    · exact ⟨hle, .inr hh⟩
  · rintro ⟨hle, ⟨s, hs⟩ | hh⟩
    · exact ⟨hle, .inl ⟨s, Stage.mem_all s, hs⟩⟩
    · exact ⟨hle, .inr hh⟩

instance (a b : Work) : Decidable (a.le b) := decidable_of_iff _ (Work.leb_iff a b)
instance (a b : Work) : Decidable (a.lt b) := decidable_of_iff _ (Work.ltb_iff a b)

/-- The order is reflexive.

$$\forall a \in \mathrm{Work}:\ a \preceq a$$
-/
theorem Work.le_refl (a : Work) : a.le a := ⟨fun _ => ⟨Nat.le_refl _, Nat.le_refl _⟩, Nat.le_refl _⟩

/-- The order is transitive.

$$\forall a, b, c \in \mathrm{Work}:\ a \preceq b \land b \preceq c \Rightarrow a \preceq c$$
-/
theorem Work.le_trans {a b c : Work} (h1 : a.le b) (h2 : b.le c) : a.le c :=
  ⟨fun s => ⟨Nat.le_trans (h1.1 s).1 (h2.1 s).1, Nat.le_trans (h1.1 s).2 (h2.1 s).2⟩, Nat.le_trans h1.2 h2.2⟩

/-! ## Into the screen and the cost model -/

/-- The count vector of a work value, in the fixed stage order: the 8 passes, the 8 units, then the hit tests.

$$\operatorname{toCounts}(w) = [w.\mathrm{passes}(s)]_{s \in \mathrm{Stage.all}} \mathbin{+\!\!+} [w.\mathrm{units}(s)]_{s \in \mathrm{Stage.all}} \mathbin{+\!\!+} [w.\mathrm{hits}]$$
-/
def toCounts (w : Work) : Screen.Counts := Stage.all.map w.passes ++ Stage.all.map w.units ++ [w.hits]

/-- The run of a list of frame works, one count vector per frame.

$$\operatorname{toRun}(W) = [\operatorname{toCounts}(w)]_{w \in W}$$
-/
def toRun (ws : List Work) : Screen.Run := ws.map toCounts

/-- The bridge into the linear cost model: script units, style units, layout units and paint units become
`scriptUs`, `styleElems`, `layoutObjs` and `paintKpx` (script units stand in for µs, one per callback; only
monotonicity is used).

$$\operatorname{toCost}(w) = \big(w.\mathrm{units}(\mathrm{script}),\ w.\mathrm{units}(\mathrm{style}),\ w.\mathrm{units}(\mathrm{layout}),\ w.\mathrm{units}(\mathrm{paint})\big)$$
-/
def toCost (w : Work) : Cost.Work :=
  ⟨w.units .script, w.units .style, w.units .layout, w.units .paint⟩

/-- `toCost` is monotone.

$$\forall a, b \in \mathrm{Work}:\ a \preceq b \Rightarrow \operatorname{toCost}(a) \preceq \operatorname{toCost}(b)$$
-/
theorem toCost_mono {a b : Work} (h : a.le b) : (toCost a).le (toCost b) :=
  ⟨(h.1 .script).2, (h.1 .style).2, (h.1 .layout).2, (h.1 .paint).2⟩

/-- No frame costs more main-thread time, under any unit costs, when its work is `≤`.

$$\forall u \in \mathbb{N}^{3},\ \forall a, b \in \mathrm{Work}:\ a \preceq b \Rightarrow \operatorname{mainUs}(u, \operatorname{toCost}(a)) \le \operatorname{mainUs}(u, \operatorname{toCost}(b))$$
-/
theorem mainUs_toCost_le (u : Cost.UnitCost) {a b : Work} (h : a.le b) :
    Cost.mainUs u (toCost a) ≤ Cost.mainUs u (toCost b) :=
  Cost.mainUs_mono u (toCost_mono h)

/-! ## Cover lemmas -/

/-- Pairwise stage cover: the two change lists have the same length and each change's stages are among its
partner's stages.

$$\operatorname{cover}_E(L, M) = \mathrm{true} \iff |L| = |M| \ \land\ \forall i < |L|:\ E.\mathrm{stagesOf}(L_i) \subseteq E.\mathrm{stagesOf}(M_i)$$
-/
def coverB {P M : Type} (E : Engine P M) : List (Change P) → List (Change P) → Bool
  | [], [] => true
  | c :: cs, d :: ds => (E.stagesOf c).all (fun s => decide (s ∈ E.stagesOf d)) && coverB E cs ds
  | _, _ => false

/-- A pairwise cover has equal lengths.

$$\forall E,\ \forall L, M \in \mathrm{Change}(P)^{*}:\ \operatorname{cover}_E(L, M) = \mathrm{true} \Rightarrow |L| = |M|$$
-/
theorem coverB_length {P M : Type} (E : Engine P M) :
    ∀ {l m : List (Change P)}, coverB E l m = true → l.length = m.length
  | [], [], _ => rfl
  | [], _ :: _, h => by simp [coverB] at h
  | _ :: _, [], h => by simp [coverB] at h
  | _ :: _, _ :: _, h => by
    simp only [coverB, Bool.and_eq_true] at h
    simp [coverB_length E h.2]

/-- A stage that some covered change dirties is dirtied by some covering change.

$$\forall E,\ \forall s \in \mathrm{Stage},\ \forall L, M \in \mathrm{Change}(P)^{*}:\ \operatorname{cover}_E(L, M) = \mathrm{true} \land s \in \bigcup_{c \in L} E.\mathrm{stagesOf}(c) \Rightarrow s \in \bigcup_{d \in M} E.\mathrm{stagesOf}(d)$$
-/
theorem coverB_mem {P M : Type} (E : Engine P M) (s : Stage) :
    ∀ {l m : List (Change P)}, coverB E l m = true → s ∈ l.flatMap E.stagesOf → s ∈ m.flatMap E.stagesOf
  | [], [], _, h => h
  | [], _ :: _, h, _ => by simp [coverB] at h
  | _ :: _, [], h, _ => by simp [coverB] at h
  | c :: cs, d :: ds, h, hs => by
    simp only [coverB, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq] at h
    simp only [List.flatMap_cons, List.mem_append] at hs ⊢
    rcases hs with hs | hs
    · exact .inl (h.1 s hs)
    · exact .inr (coverB_mem E s h.2 hs)

/-- Under a pairwise cover, no more covered changes than covering changes dirty any stage.

$$\forall E,\ \forall s \in \mathrm{Stage},\ \forall L, M \in \mathrm{Change}(P)^{*}:\ \operatorname{cover}_E(L, M) = \mathrm{true} \Rightarrow \big|[\,c \in L \mid s \in E.\mathrm{stagesOf}(c)\,]\big| \le \big|[\,d \in M \mid s \in E.\mathrm{stagesOf}(d)\,]\big|$$
-/
theorem coverB_countP {P M : Type} (E : Engine P M) (s : Stage) :
    ∀ {l m : List (Change P)}, coverB E l m = true →
      l.countP (fun c => decide (s ∈ E.stagesOf c)) ≤ m.countP (fun c => decide (s ∈ E.stagesOf c))
  | [], [], _ => Nat.le_refl _
  | [], _ :: _, h => by simp [coverB] at h
  | _ :: _, [], h => by simp [coverB] at h
  | c :: cs, d :: ds, h => by
    simp only [coverB, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq] at h
    have ih := coverB_countP E s h.2
    simp only [List.countP_cons, decide_eq_true_eq]
    by_cases hc : s ∈ E.stagesOf c
    · have hd : s ∈ E.stagesOf d := h.1 s hc
      simp only [hc, hd, ↓reduceIte]
      omega
    · simp only [hc, ↓reduceIte]; omega

/-! ## Frame dominance -/

/-- Componentwise `≤` on the forced passes.

$$\forall f, g \in \mathrm{FrameIn}(P),\ \forall s \in \mathrm{Stage}:\ f.\mathrm{forcedStyle} \le g.\mathrm{forcedStyle} \land f.\mathrm{forcedLayout} \le g.\mathrm{forcedLayout} \Rightarrow \operatorname{forced}(f, s) \le \operatorname{forced}(g, s)$$
-/
theorem forcedPasses_le {P : Type} {f g : FrameIn P} (s : Stage) (h1 : f.forcedStyle ≤ g.forcedStyle)
    (h2 : f.forcedLayout ≤ g.forcedLayout) : forcedPasses f s ≤ forcedPasses g s := by
  cases s <;> simp [forcedPasses, h1, h2]

/-- **Frame dominance from a cover.** If the variant's changes are covered pairwise, stage set inside stage set, by
a sub-multiset `m` of the original's changes (`m ++ rest` is a permutation of them, so `i ↦ m_i` is an injection
into the original's changes), and the variant has no more callbacks, forced passes, hit tests or compositor
animations, then the variant's frame work is at most the original's, under every engine `E`.

$$\forall E,\ \forall v, o \in \mathrm{FrameIn}(P),\ \forall m, r \in \mathrm{Change}(P)^{*}:\ (m \mathbin{+\!\!+} r) \sim o.\mathrm{changes} \land \operatorname{cover}_E(v.\mathrm{changes}, m) = \mathrm{true} \land v.\mathrm{script} \le o.\mathrm{script} \land v.\mathrm{forcedStyle} \le o.\mathrm{forcedStyle} \land v.\mathrm{forcedLayout} \le o.\mathrm{forcedLayout} \land v.\mathrm{hits} \le o.\mathrm{hits} \land v.\mathrm{compAnims} \le o.\mathrm{compAnims} \Rightarrow \operatorname{frameWork}_E(v) \preceq \operatorname{frameWork}_E(o)$$
-/
theorem frame_le_of_cover {P M : Type} (E : Engine P M) {v o : FrameIn P} (m rest : List (Change P))
    (hperm : (m ++ rest).Perm o.changes) (hcov : coverB E v.changes m = true)
    (hs : v.script ≤ o.script) (hfs : v.forcedStyle ≤ o.forcedStyle) (hfl : v.forcedLayout ≤ o.forcedLayout)
    (hh : v.hits ≤ o.hits) (hc : v.compAnims ≤ o.compAnims) :
    (frameWork E v).le (frameWork E o) := by
  have hmem : ∀ d, d ∈ m → d ∈ o.changes := fun d hd => hperm.mem_iff.mp (List.mem_append_left _ hd)
  have hlen : v.changes.length ≤ o.changes.length := by
    rw [coverB_length E hcov, ← hperm.length_eq, List.length_append]; omega
  have hupd : v.updates = true → o.updates = true := by
    unfold FrameIn.updates
    cases h1 : v.changes <;> cases h2 : o.changes <;> simp_all <;> omega
  have htouch : ∀ s, s ∈ touched E v → s ∈ touched E o := by
    intro s h
    simp only [touched, List.mem_append] at h ⊢
    rcases h with ((h | h) | h) | h
    · left; left; left
      obtain ⟨d, hd, hs'⟩ := List.mem_flatMap.mp (coverB_mem E s hcov h)
      exact List.mem_flatMap.mpr ⟨d, hmem d hd, hs'⟩
    · left; left; right
      split at h
      · simp only [show 0 < o.compAnims by omega, ↓reduceIte]; exact h
      · simp at h
    · left; right
      split at h
      · rename_i hu; simp only [hupd hu, ↓reduceIte]; exact h
      · simp at h
    · right
      split at h
      · simp only [show 0 < o.script by omega, ↓reduceIte]; exact h
      · simp at h
  have hcount : ∀ s, v.changes.countP (fun c => decide (s ∈ E.stagesOf c)) ≤
      o.changes.countP (fun c => decide (s ∈ E.stagesOf c)) := by
    intro s
    have h1 := coverB_countP E s hcov
    rw [← hperm.countP_eq, List.countP_append]
    omega
  refine ⟨fun s => ⟨?_, ?_⟩, hh⟩
  · simp only [frameWork]
    have hf := forcedPasses_le s hfs hfl
    by_cases ht : s ∈ touched E v
    · simp only [ht, htouch s ht, ↓reduceIte]; omega
    · simp only [ht, ↓reduceIte]; split <;> omega
  · simp only [frameWork, stageUnits]
    have h1 := hcount s
    have h2 : (if s ∈ E.compStages then v.compAnims else 0) ≤ (if s ∈ E.compStages then o.compAnims else 0) := by
      split <;> omega
    have h3 : (if s = .script then v.script else 0) ≤ (if s = .script then o.script else 0) := by
      split <;> omega
    omega

/-- The decidable union check for two concrete frames: every stage the variant touches the original touches, every
stage's units and forced passes are at most the original's, and the hit tests too.

$$\operatorname{unionLe}_E(v, o) = \mathrm{true} \iff \Big(\forall s \in \mathrm{Stage.all}:\ \big(s \in \operatorname{touched}_E(v) \Rightarrow s \in \operatorname{touched}_E(o)\big) \land \operatorname{units}_E(v, s) \le \operatorname{units}_E(o, s) \land \operatorname{forced}(v, s) \le \operatorname{forced}(o, s)\Big) \land v.\mathrm{hits} \le o.\mathrm{hits}$$
-/
def unionLe {P M : Type} (E : Engine P M) (v o : FrameIn P) : Bool :=
  Stage.all.all (fun s =>
      (!decide (s ∈ touched E v) || decide (s ∈ touched E o)) &&
        decide (stageUnits E v s ≤ stageUnits E o s) && decide (forcedPasses v s ≤ forcedPasses o s)) &&
    decide (v.hits ≤ o.hits)

/-- **Frame dominance from the union check.** The decidable form: if the union of the variant's stages lies inside
the original's, and units, forced passes and hit tests are `≤`, the variant's frame work is at most the original's.
On concrete frames the hypothesis closes by `decide`; this is how a WebKit repaint-to-recomposite change is accepted
when the original's frame already pays `props` some other way (design note C-2).

$$\forall E,\ \forall v, o \in \mathrm{FrameIn}(P):\ \operatorname{unionLe}_E(v, o) = \mathrm{true} \Rightarrow \operatorname{frameWork}_E(v) \preceq \operatorname{frameWork}_E(o)$$
-/
theorem frame_le_union {P M : Type} (E : Engine P M) {v o : FrameIn P} (h : unionLe E v o = true) :
    (frameWork E v).le (frameWork E o) := by
  simp only [unionLe, Bool.and_eq_true, List.all_eq_true, Bool.or_eq_true, Bool.not_eq_true',
    decide_eq_false_iff_not, decide_eq_true_eq] at h
  refine ⟨fun s => ?_, h.2⟩
  obtain ⟨⟨ht, hu⟩, hf⟩ := h.1 s (Stage.mem_all s)
  refine ⟨?_, hu⟩
  simp only [frameWork]
  rcases ht with ht | ht
  · simp only [ht, ↓reduceIte]; split <;> omega
  · have h1 : (if s ∈ touched E o then 1 else 0) = 1 := by simp [ht]
    split <;> omega

end Fw.Engine
