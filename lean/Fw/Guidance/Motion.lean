import Fw.Guidance.Basic
/-!
# Guidance rules on motion: compositor properties, transform over inset, box-size animation, will-change

Rules `motion.compositor-props`, `transitions.transform-over-inset`, `css.box-size-animation-triggers-layout` and
`perf.will-change-overuse` of Chrome Modern Web Guidance (GoogleChrome/modern-web-guidance@b31dc0a43ff5), each stated
under `Fw.Engine.Chromium` and `Fw.Engine.WebKit`; verdicts in `research/notes/2026/10-18-guidance-proofs.md`.
-/
namespace Fw.Guidance.Motion

open Fw.Engine

section Cr

open Fw.Engine.Chromium

/-- The properties the guide names as compositor properties: transform, translate, scale, rotate, opacity.

$$\operatorname{guide}_{\mathrm{cr}}(k) \iff k \in \{\mathrm{transform}, \mathrm{translate}, \mathrm{scale}, \mathrm{rotate}, \mathrm{opacity}\}$$

The guide's compositor property list on Chromium keys. -/
def guideKey : CrKey → Bool
  | .transform | .translate | .scale | .rotate | .opacity => true
  | _ => false

#guard guideKey .translate && guideKey .opacity && !guideKey (.filter false) && !guideKey .top

/-- **Guide properties run on the compositor (Chromium).** An animation of guide properties only, on a valid target,
with threaded animation on and a timeline that is not a scroll timeline on a non-user-scrollable source, runs on the
compositor.

$$\forall m \in \mathrm{CrMode},\ \forall a \in \mathrm{CrAnim}:\ m.\mathrm{threadedAnim} \land a.\mathrm{validTarget} \land a.\mathrm{timeline} \ne \mathrm{scroll}(\mathrm{false}) \land \big(\forall p \in a.\mathrm{props},\ \exists k \in \mathrm{CrKey}:\ p = \mathrm{css}(k) \land \operatorname{guide}_{\mathrm{cr}}(k)\big) \Rightarrow \operatorname{crThread}(m, a) = \mathrm{comp}$$

The guide's list is inside Chromium's compositable set and moves no pixels. -/
theorem cr_guide_comp (m : CrMode) (a : CrAnim) (ht : m.threadedAnim = true) (hv : a.validTarget = true)
    (hτ : a.timeline ≠ .scroll false) (hp : ∀ p ∈ a.props, ∃ k, p = .css k ∧ guideKey k = true) :
    crThread m a = .comp := by
  rw [crThread_comp_iff]
  refine ⟨fun p hp' => ?_, ht, hv, fun p hp' => ?_, hτ⟩
  · obtain ⟨k, rfl, hk⟩ := hp p hp'
    cases k <;> simp_all [guideKey, CrProp.eligible]
  · obtain ⟨k, rfl, hk⟩ := hp p hp'
    cases k <;> simp_all [guideKey, CrProp.movesPixels]

/-- **No main-thread work in real Chrome.** If every running animation is on the compositor, the frame has no pass and
no unit on any stage but `comp`.

$$\forall A \in \mathrm{CrAnim}^{*}:\ (\forall a \in A:\ \operatorname{crThread}(\mathrm{realChrome}, a) = \mathrm{comp}) \Rightarrow \forall s \in \mathrm{Stage} \setminus \{\mathrm{comp}\}:\ W.\mathrm{passes}(s) = 0 \land W.\mathrm{units}(s) = 0\quad\text{where } W = \operatorname{frameWork}_{\operatorname{chromiumAt}(\mathrm{realChrome})}(\operatorname{animFrame}(\mathrm{realChrome}, A))$$

Compositor animations cost the main thread nothing in shipping Chrome. -/
theorem cr_comp_free_realChrome (as : List CrAnim) (h : ∀ a ∈ as, crThread realChrome a = .comp) (s : Stage)
    (hs : s ≠ .comp) :
    (frameWork (chromiumAt realChrome) (animFrame realChrome as)).passes s = 0 ∧
      (frameWork (chromiumAt realChrome) (animFrame realChrome as)).units s = 0 := by
  have hfr : animFrame realChrome as = ⟨0, 0, 0, 0, [], as.length⟩ := by
    have hnil : (as.filter fun a => decide (crThread realChrome a = .main)) = [] := by
      rw [List.filter_eq_nil_iff]; intro a ha; simp [h a ha]
    have hf : (as.filter fun a => decide (crThread realChrome a = .comp)) = as := by
      rw [List.filter_eq_self]; intro a ha; simp [h a ha]
    simp only [animFrame, hnil, hf, List.flatMap_nil]
  rw [hfr]
  cases s <;> first
    | exact absurd rfl hs
    | (constructor <;>
        simp [frameWork, touched, stageUnits, FrameIn.updates, chromiumAt, crCompStages, realChrome,
          forcedPasses] <;> (try split) <;> simp)

/-- **The lane's ride-along.** In the CI lane, one compositor animation still costs a main-thread style pass and a
property-tree pass.

$$\forall A \in \mathrm{CrAnim}^{*}:\ (\forall a \in A:\ \operatorname{crThread}(\mathrm{lane}, a) = \mathrm{comp}) \land A \ne [\,] \Rightarrow W.\mathrm{passes}(\mathrm{style}) = 1 \land W.\mathrm{passes}(\mathrm{props}) = 1\quad\text{where } W = \operatorname{frameWork}_{\operatorname{chromiumAt}(\mathrm{lane})}(\operatorname{animFrame}(\mathrm{lane}, A))$$

The lane runs a main frame on every BeginFrame, so the guide's claim holds only for real Chrome. -/
theorem cr_lane_ride (as : List CrAnim) (h : ∀ a ∈ as, crThread lane a = .comp) (hne : as ≠ []) :
    (frameWork (chromiumAt lane) (animFrame lane as)).passes .style = 1 ∧
      (frameWork (chromiumAt lane) (animFrame lane as)).passes .props = 1 := by
  have hfr : animFrame lane as = ⟨0, 0, 0, 0, [], as.length⟩ := by
    have hnil : (as.filter fun a => decide (crThread lane a = .main)) = [] := by
      rw [List.filter_eq_nil_iff]; intro a ha; simp [h a ha]
    have hf : (as.filter fun a => decide (crThread lane a = .comp)) = as := by
      rw [List.filter_eq_self]; intro a ha; simp [h a ha]
    simp only [animFrame, hnil, hf, List.flatMap_nil]
  have hpos : 0 < as.length := List.length_pos_iff.mpr hne
  rw [hfr]
  constructor <;>
    simp [frameWork, touched, chromiumAt, crCompStages, lane, forcedPasses, hpos, FrameIn.updates]

/-- **Chromium composites more than the guide lists, and not blur.** A filter that moves no pixels and a
backdrop-filter run on the compositor with threaded animation on; a blur filter never does.

$$\forall m \in \mathrm{CrMode},\ \forall e \in \mathbb{N},\ \forall l \in \mathrm{LayerState}:\ \big(m.\mathrm{threadedAnim} \Rightarrow \operatorname{crThread}(m, (e, [\mathrm{css}(\mathrm{filter}(\mathrm{false}))], l, \mathrm{true}, \mathrm{document})) = \mathrm{comp} \land \operatorname{crThread}(m, (e, [\mathrm{css}(\mathrm{backdropFilter})], l, \mathrm{true}, \mathrm{document})) = \mathrm{comp}\big) \land \operatorname{crThread}(m, (e, [\mathrm{css}(\mathrm{filter}(\mathrm{true}))], l, \mathrm{true}, \mathrm{document})) = \mathrm{main}$$

The guide omits filter and backdrop-filter, and its rule does not hold for a blur on Chromium. -/
theorem cr_filter_thread (m : CrMode) (e : Nat) (l : LayerState) :
    (m.threadedAnim = true →
      crThread m ⟨e, [.css (.filter false)], l, true, .document⟩ = .comp ∧
        crThread m ⟨e, [.css .backdropFilter], l, true, .document⟩ = .comp) ∧
      crThread m ⟨e, [.css (.filter true)], l, true, .document⟩ = .main := by
  refine ⟨fun ht => ⟨?_, ?_⟩, ?_⟩ <;> simp [crThread, failBits, CrProp.eligible, CrProp.movesPixels, *]

/-- **A non-compositable property runs on the main thread (Chromium).**

$$\forall m \in \mathrm{CrMode},\ \forall a \in \mathrm{CrAnim}:\ (\exists p \in a.\mathrm{props}:\ \lnot\operatorname{elig}(p)) \Rightarrow \operatorname{crThread}(m, a) = \mathrm{main}$$

One property outside the compositable set keeps the whole animation on main. -/
theorem cr_noneligible_main (m : CrMode) (a : CrAnim) (h : ∃ p ∈ a.props, p.eligible = false) :
    crThread m a = .main := by
  cases hc : crThread m a with
  | main => rfl
  | comp =>
    obtain ⟨p, hp, he⟩ := h
    have := ((crThread_comp_iff m a).mp hc).1 p hp
    simp_all

/-- **Transform over inset (Chromium).** A transform or translate write is strictly less work than a top or left
write on a box of the same layer state, in every mode, for any callback count and any elements.

$$\forall m \in \mathrm{CrMode},\ \forall n, e, e' \in \mathbb{N},\ \forall l \in \mathrm{LayerState},\ \forall t \in \{\mathrm{transform}, \mathrm{translate}\},\ \forall k \in \{\mathrm{top}, \mathrm{left}\}:\ \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}\big(\operatorname{jsWrite}(n, [(e, \mathrm{css}(t), l)])\big) \prec \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}\big(\operatorname{jsWrite}(n, [(e', \mathrm{css}(k), l)])\big)$$

The inset write adds layout on every layer state; the transform write adds none. -/
theorem cr_transform_lt_inset (m : CrMode) (n e e' : Nat) (l : LayerState) (t k : CrKey)
    (ht : t = .transform ∨ t = .translate) (hk : k = .top ∨ k = .left) :
    (frameWork (chromiumAt m) (jsWrite n [⟨e, .css t, l⟩])).lt
      (frameWork (chromiumAt m) (jsWrite n [⟨e', .css k, l⟩])) := by
  refine lt_of_le_units .layout (frame_le_of_cover (chromiumAt m) [⟨e', .css k, l⟩] [] (by simp [jsWrite]) ?_
    (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _)) ?_
  · rcases ht with rfl | rfl <;> rcases hk with rfl | rfl <;> cases l <;> rfl
  · show stageUnits (chromiumAt m) _ .layout < stageUnits (chromiumAt m) _ .layout
    rcases ht with rfl | rfl <;> rcases hk with rfl | rfl <;> cases l <;>
      simp [stageUnits, jsWrite, chromiumAt, crCompStages, crStagesOf, crLevel, keyLevel, CrLevel.stages,
        CrProp.extra]

/-- **Box-size animation (Chromium).** An animation that animates width or height runs on the main thread, and its
frame has a layout pass and a paint pass, in every mode and on every layer state.

$$\forall m \in \mathrm{CrMode},\ \forall a \in \mathrm{CrAnim},\ \forall k \in \{\mathrm{width}, \mathrm{height}\}:\ \mathrm{css}(k) \in a.\mathrm{props} \Rightarrow \operatorname{crThread}(m, a) = \mathrm{main} \land 1 \le W.\mathrm{passes}(\mathrm{layout}) \land 1 \le W.\mathrm{passes}(\mathrm{paint})\quad\text{where } W = \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}(\operatorname{animFrame}(m, [a]))$$

A size animation lays out and paints every frame on the main thread. -/
theorem cr_size_anim (m : CrMode) (a : CrAnim) (k : CrKey) (hk : k = .width ∨ k = .height)
    (h : CrProp.css k ∈ a.props) :
    crThread m a = .main ∧ 1 ≤ (frameWork (chromiumAt m) (animFrame m [a])).passes .layout ∧
      1 ≤ (frameWork (chromiumAt m) (animFrame m [a])).passes .paint := by
  have hm : crThread m a = .main :=
    cr_noneligible_main m a ⟨_, h, by rcases hk with rfl | rfl <;> rfl⟩
  have hch : (animFrame m [a]).changes = a.changes := by simp [animFrame, hm]
  have hc : (⟨a.elem, .css k, a.layer⟩ : Change CrProp) ∈ (animFrame m [a]).changes := by
    rw [hch]; exact List.mem_map.mpr ⟨_, h, rfl⟩
  have hst : ∀ s ∈ [Stage.layout, .paint], s ∈ crStagesOf ⟨a.elem, .css k, a.layer⟩ := by
    have hsz : ∀ l : LayerState, Stage.layout ∈ crStagesOf ⟨0, .css k, l⟩ ∧ Stage.paint ∈ crStagesOf ⟨0, .css k, l⟩ := by
      intro l; rcases hk with rfl | rfl <;> cases l <;> decide
    intro s hs
    show s ∈ crStagesOf ⟨0, .css k, a.layer⟩
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hs
    rcases hs with rfl | rfl
    · exact (hsz a.layer).1
    · exact (hsz a.layer).2
  have ht : ∀ s ∈ [Stage.layout, .paint], s ∈ touched (chromiumAt m) (animFrame m [a]) := by
    intro s hs
    simp only [touched, List.mem_append]
    exact .inl (.inl (.inl (List.mem_flatMap.mpr ⟨_, hc, hst s hs⟩)))
  refine ⟨hm, ?_, ?_⟩ <;> simp [frameWork, ht]

/-- **An own layer lowers a moving box's work (Chromium).** A transform write on a box with its own composited layer
is strictly less work than the same write on a box without one.

$$\forall m \in \mathrm{CrMode},\ \forall n, e \in \mathbb{N},\ \forall l \in \{\mathrm{none}, \mathrm{layer}\}:\ \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}\big(\operatorname{jsWrite}(n, [(e, \mathrm{css}(\mathrm{transform}), \mathrm{own})])\big) \prec \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}\big(\operatorname{jsWrite}(n, [(e, \mathrm{css}(\mathrm{transform}), l)])\big)$$

Without its own layer the moved box is re-rastered every frame. -/
theorem cr_own_moving (m : CrMode) (n e : Nat) (l : LayerState) (hl : l = .none ∨ l = .layer) :
    (frameWork (chromiumAt m) (jsWrite n [⟨e, .css .transform, .own⟩])).lt
      (frameWork (chromiumAt m) (jsWrite n [⟨e, .css .transform, l⟩])) := by
  refine lt_of_le_units .raster (frame_le_of_cover (chromiumAt m) [⟨e, .css .transform, l⟩] [] (by simp [jsWrite])
    ?_ (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _)) ?_
  · rcases hl with rfl | rfl <;> rfl
  · show stageUnits (chromiumAt m) _ .raster < stageUnits (chromiumAt m) _ .raster
    rcases hl with rfl | rfl <;>
      simp [stageUnits, jsWrite, chromiumAt, crCompStages, crStagesOf, crLevel, keyLevel, CrLevel.stages,
        CrProp.extra]

end Cr

section Wk

open Fw.Engine.WebKit

/-- The properties the guide names as compositor properties, on WebKit's animated-property type.

$$\operatorname{guide}_{\mathrm{wk}}(q) \iff q \in \{\mathrm{transform}, \mathrm{translate}, \mathrm{scale}, \mathrm{rotate}, \mathrm{opacity}\}$$

The guide's compositor property list on WebKit properties. -/
def wkGuide : CssProp → Bool
  | .transform | .translate | .scale | .rotate | .opacity => true
  | _ => false

#guard wkGuide .rotate && !wkGuide .filter && !wkGuide .inset

/-- A frame of `n` callbacks and the given changes on WebKit.

$$\operatorname{wkWrite}(n, C) = (n, 0, 0, 0, C, 0)$$

A script frame that writes styles. -/
def wkWrite (n : Nat) (cs : List (Change WkProp)) : FrameIn WkProp := ⟨n, 0, 0, 0, cs, 0⟩

/-- **Guide properties run in the UI process (WebKit).** An animation with no disqualifier (`WkAnim.clean`) of a
non-empty list of guide properties runs in the UI process when its timeline is time-based or threaded scroll-driven
animations are on.

$$\forall m \in \mathrm{WkMode},\ \forall P \in \mathrm{CssProp}^{*},\ \forall \tau \in \mathrm{Timeline}:\ P \ne [\,] \land (\forall q \in P:\ \operatorname{guide}_{\mathrm{wk}}(q)) \land (\tau = \mathrm{time} \lor m.\mathrm{threadedScrollDriven}) \Rightarrow \operatorname{wkThread}(m, \operatorname{clean}(P, \tau)) = \mathrm{comp}$$

Every guide property is accelerated on both WebKit paths. -/
theorem wk_guide_comp (m : WkMode) (ps : List CssProp) (τ : Timeline) (hne : ps ≠ [])
    (hg : ∀ q ∈ ps, wkGuide q = true) (hτ : τ = .time ∨ m.threadedScrollDriven = true) :
    wkThread m (.clean ps τ) = .comp := by
  have hacc : ∀ p q, wkGuide q = true → accelerated p q = true := by
    intro p q h; cases p <;> cases q <;> simp_all [wkGuide, accelerated]
  have hall : ∀ p, ps.all (accelerated p) = true := fun p =>
    List.all_eq_true.mpr fun q hq => hacc p q (hg q hq)
  have hany : ∀ p, ps.any (accelerated p) = true := by
    intro p
    obtain ⟨q, qs, rfl⟩ := List.exists_cons_of_ne_nil hne
    simp [hacc p q (hg q (List.mem_cons_self ..))]
  have hfil : ps.any isFilter = false := by
    rw [List.any_eq_false]
    intro q hq
    have := hg q hq
    cases q <;> simp_all [wkGuide, isFilter]
  obtain ⟨tsd, ttb, pol⟩ := m
  unfold wkThread canBeAccelerated caAccepts
  cases τ <;> cases tsd <;> cases ttb <;> simp_all [pathOf, WkAnim.clean]

/-- **No main-thread work for a time-based UI-process animation (WebKit).** Adding a UI-process animation on a
document timeline with no scheduled update leaves every stage but `comp` as it was, for any frame.

$$\forall m, a, e, \ell, \mathit{cs}, f,\ \forall s \in \mathrm{Stage} \setminus \{\mathrm{comp}\}:\ \operatorname{wkThread}(m, a) = \mathrm{comp} \land a.\tau = \mathrm{time} \Rightarrow W'.\mathrm{passes}(s) = W.\mathrm{passes}(s) \land \operatorname{units}(g, s) = \operatorname{units}(f, s)$$
$$\text{where } g = \operatorname{withAnim}(m, a, e, \ell, \mathit{cs}, f, \mathrm{false}),\ W' = \operatorname{frameWork}_{\operatorname{webkitX}(m)}(g),\ W = \operatorname{frameWork}_{\operatorname{webkitX}(m)}(f),\ \operatorname{units} = \operatorname{units}_{\operatorname{webkitX}(m)}$$

A time-based accelerated animation costs WebKit's main thread nothing. -/
theorem wk_time_comp_free (m : WkMode) (a : WkAnim) (e : Nat) (ℓ : LayerState) (cs : List (Change WkPropX))
    (f : FrameIn WkPropX) (hc : wkThread m a = .comp) (ht : a.timeline = .time) (s : Stage) (hs : s ≠ .comp) :
    (frameWork (webkitX m) (withAnim m a e ℓ cs f false)).passes s = (frameWork (webkitX m) f).passes s ∧
      stageUnits (webkitX m) (withAnim m a e ℓ cs f false) s = stageUnits (webkitX m) f s := by
  have hw : withAnim m a e ℓ cs f false = f.addAnim := by
    cases f; simp [withAnim, hc, wkTicks, ht, FrameIn.addAnim]
  rw [hw]
  exact pause_no_main (webkitX m) f (by simp [webkitX]) s hs

/-- A non-accelerated property runs on the main thread (WebKit).

$$\forall m \in \mathrm{WkMode},\ \forall a \in \mathrm{WkAnim},\ \forall q \in \mathrm{CssProp}:\ (\forall p \in \mathrm{Path}:\ \lnot\operatorname{accel}(p, q)) \land q \in a.\mathrm{props} \Rightarrow \operatorname{wkThread}(m, a) = \mathrm{main}$$

One property neither path accelerates keeps the animation on main. -/
theorem wk_unaccel_main (m : WkMode) (a : WkAnim) (q : CssProp) (hq : ∀ p, accelerated p q = false)
    (h : q ∈ a.props) : wkThread m a = .main := by
  have : a.props.all (accelerated (pathOf m a)) = false := by
    rw [List.all_eq_false]; exact ⟨_, h, by simp [hq]⟩
  simp [wkThread, this]

/-- **Transform over inset on an own layer (WebKit).** On a box with its own composited layer, a transform write is
strictly less work than an inset write, absolute or not.

$$\forall m \in \mathrm{WkMode},\ \forall n, e, e' \in \mathbb{N},\ \forall k \in \{\mathrm{insetAbs}, \mathrm{inset}\}:\ \operatorname{frameWork}_{\operatorname{webkitAt}(m)}\big(\operatorname{wkWrite}(n, [(e, \mathrm{transform}, \mathrm{own})])\big) \prec \operatorname{frameWork}_{\operatorname{webkitAt}(m)}\big(\operatorname{wkWrite}(n, [(e', k, \mathrm{own})])\big)$$

With its own layer the moved box only recomposites. -/
theorem wk_transform_lt_inset_own (m : WkMode) (n e e' : Nat) (k : WkProp) (hk : k = .insetAbs ∨ k = .inset) :
    (frameWork (webkitAt m) (wkWrite n [⟨e, .transform, .own⟩])).lt
      (frameWork (webkitAt m) (wkWrite n [⟨e', k, .own⟩])) := by
  have h1 : wkStages ⟨e, .transform, .own⟩ = [.style, .props] := rfl
  refine lt_of_le_units .layout (frame_le_of_cover (webkitAt m) [⟨e', k, .own⟩] [] (by simp [wkWrite]) ?_
    (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _)) ?_
  · rcases hk with rfl | rfl <;> rfl
  · show stageUnits (webkitAt m) _ .layout < stageUnits (webkitAt m) _ .layout
    rcases hk with rfl | rfl
    · have h2 : wkStages ⟨e', .insetAbs, .own⟩ = [.style, .layout, .props] := rfl
      simp [stageUnits, wkWrite, webkitAt, h1, h2]
    · have h2 : wkStages ⟨e', .inset, .own⟩ = [.style, .layout, .props, .paint] := rfl
      simp [stageUnits, wkWrite, webkitAt, h1, h2]

/-- **Counterexample: without an own layer the transform write costs more (WebKit).** On a box with no layer or a
paint layer it does not own, an absolute-inset write is strictly less work than a transform write: the transform write
also repaints.

$$\forall m \in \mathrm{WkMode},\ \forall n, e, e' \in \mathbb{N},\ \forall l \in \{\mathrm{none}, \mathrm{layer}\}:\ \operatorname{frameWork}_{\operatorname{webkitAt}(m)}\big(\operatorname{wkWrite}(n, [(e', \mathrm{insetAbs}, l)])\big) \prec \operatorname{frameWork}_{\operatorname{webkitAt}(m)}\big(\operatorname{wkWrite}(n, [(e, \mathrm{transform}, l)])\big)$$

Following the guide on a non-composited WebKit box raises the frame's work. -/
theorem wk_inset_lt_transform (m : WkMode) (n e e' : Nat) (l : LayerState) (hl : l = .none ∨ l = .layer) :
    (frameWork (webkitAt m) (wkWrite n [⟨e', .insetAbs, l⟩])).lt
      (frameWork (webkitAt m) (wkWrite n [⟨e, .transform, l⟩])) := by
  refine lt_of_le_units .paint (frame_le_of_cover (webkitAt m) [⟨e, .transform, l⟩] [] (by simp [wkWrite]) ?_
    (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _)) ?_
  · rcases hl with rfl | rfl <;> rfl
  · show stageUnits (webkitAt m) _ .paint < stageUnits (webkitAt m) _ .paint
    rcases hl with rfl | rfl
    · have h1 : wkStages ⟨e', .insetAbs, .none⟩ = [.style, .layout, .props] := rfl
      have h2 : wkStages ⟨e, .transform, .none⟩ = [.style, .layout, .props, .paint] := rfl
      simp [stageUnits, wkWrite, webkitAt, h1, h2]
    · have h1 : wkStages ⟨e', .insetAbs, .layer⟩ = [.style, .layout, .props] := rfl
      have h2 : wkStages ⟨e, .transform, .layer⟩ = [.style, .layout, .props, .paint] := rfl
      simp [stageUnits, wkWrite, webkitAt, h1, h2]

/-- **Box-size animation (WebKit).** An animation of a box size runs on the main thread, and a frame that carries a
size change of any element on any layer state has a layout pass and a paint pass.

$$\forall m \in \mathrm{WkMode},\ \forall a \in \mathrm{WkAnim},\ \forall \mathit{cs} \in \mathrm{Change}(\mathrm{WkProp})^{*},\ \forall e \in \mathbb{N},\ \forall \ell \in \mathrm{LayerState}:\ \mathrm{size} \in a.\mathrm{props} \land (e, \mathrm{size}, \ell) \in \mathit{cs} \Rightarrow \operatorname{wkThread}(m, a) = \mathrm{main} \land 1 \le W.\mathrm{passes}(\mathrm{layout}) \land 1 \le W.\mathrm{passes}(\mathrm{paint})\quad\text{where } W = \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(\operatorname{animFrame}(m, a, \mathit{cs}))$$

A size animation lays out and paints every frame on WebKit's main thread. -/
theorem wk_size_anim (m : WkMode) (a : WkAnim) (cs : List (Change WkProp)) (e : Nat) (ℓ : LayerState)
    (h : CssProp.size ∈ a.props) (hc : ⟨e, .size, ℓ⟩ ∈ cs) :
    wkThread m a = .main ∧ 1 ≤ (frameWork (webkitAt m) (animFrame m a cs)).passes .layout ∧
      1 ≤ (frameWork (webkitAt m) (animFrame m a cs)).passes .paint := by
  have hm : wkThread m a = .main := wk_unaccel_main m a .size (fun p => by cases p <;> rfl) h
  have hf : animFrame m a cs = ⟨0, 0, 0, 0, cs, 0⟩ := by simp [animFrame, hm]
  have hst : ∀ s ∈ [Stage.layout, .paint], s ∈ wkStages ⟨e, .size, ℓ⟩ := by
    intro s hs
    show s ∈ wkStages ⟨0, .size, ℓ⟩
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hs
    rcases hs with rfl | rfl <;> cases ℓ <;> decide
  have ht : ∀ s ∈ [Stage.layout, .paint], s ∈ touched (webkitAt m) (animFrame m a cs) := by
    intro s hs
    rw [hf]
    simp only [touched, List.mem_append]
    exact .inl (.inl (.inl (List.mem_flatMap.mpr ⟨_, hc, hst s hs⟩)))
  refine ⟨hm, ?_, ?_⟩ <;> simp [frameWork, ht]

/-- **will-change makes a layer under the normal policy only (WebKit).**

$$\operatorname{composites}(\mathrm{normal}, \mathrm{willChange}) = \mathrm{true} \land \operatorname{composites}(\mathrm{conservative}, \mathrm{willChange}) = \mathrm{false} \land \forall A \in \mathbb{N}:\ \operatorname{resident}(\mathrm{false}, \mathrm{false}, A) = 0 \land \operatorname{resident}(\mathrm{true}, \mathrm{false}, A) = A$$

A will-change layer holds a backing store only when it draws content or delegates display. -/
theorem wk_willChange_memory :
    composites .normal .willChange = true ∧ composites .conservative .willChange = false ∧
      ∀ A, residentKpx false false A = 0 ∧ residentKpx true false A = A :=
  ⟨rfl, rfl, fun _ => ⟨rfl, rfl⟩⟩

/-- **An own layer lowers a moving box's work (WebKit).** A transform write on a box with its own composited layer is
strictly less work than the same write on a box without one.

$$\forall m \in \mathrm{WkMode},\ \forall n, e \in \mathbb{N},\ \forall l \in \{\mathrm{none}, \mathrm{layer}\}:\ \operatorname{frameWork}_{\operatorname{webkitAt}(m)}\big(\operatorname{wkWrite}(n, [(e, \mathrm{transform}, \mathrm{own})])\big) \prec \operatorname{frameWork}_{\operatorname{webkitAt}(m)}\big(\operatorname{wkWrite}(n, [(e, \mathrm{transform}, l)])\big)$$

Without its own layer the moved box lays out and repaints every frame. -/
theorem wk_own_moving (m : WkMode) (n e : Nat) (l : LayerState) (hl : l = .none ∨ l = .layer) :
    (frameWork (webkitAt m) (wkWrite n [⟨e, .transform, .own⟩])).lt
      (frameWork (webkitAt m) (wkWrite n [⟨e, .transform, l⟩])) := by
  have h1 : wkStages ⟨e, .transform, .own⟩ = [.style, .props] := rfl
  refine lt_of_le_units .layout (frame_le_of_cover (webkitAt m) [⟨e, .transform, l⟩] [] (by simp [wkWrite]) ?_
    (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _)) ?_
  · rcases hl with rfl | rfl <;> rfl
  · show stageUnits (webkitAt m) _ .layout < stageUnits (webkitAt m) _ .layout
    rcases hl with rfl | rfl
    · have h2 : wkStages ⟨e, .transform, .none⟩ = [.style, .layout, .props, .paint] := rfl
      simp [stageUnits, wkWrite, webkitAt, h1, h2]
    · have h2 : wkStages ⟨e, .transform, .layer⟩ = [.style, .layout, .props, .paint] := rfl
      simp [stageUnits, wkWrite, webkitAt, h1, h2]

end Wk

/-- **A layer that does nothing per frame is never a dominating claim.** Any variant that holds more composited layers
than the original is not reported as dominating, whatever its per-frame work.

$$\forall x,\ \forall r_v, r_o \in \mathrm{Resident}:\ r_o.\mathrm{layers} < r_v.\mathrm{layers} \Rightarrow \operatorname{claim}(x, r_v, r_o) \ne \mathrm{dominates}$$

Extra will-change layers are at best a trade. -/
theorem willChange_not_dominates (x : Except String Screen.Result) (rv ro : Resident) (h : ro.layers < rv.layers) :
    claim x rv ro ≠ .dominates :=
  claim_ne_dominates_of_layers x rv ro h

end Fw.Guidance.Motion
