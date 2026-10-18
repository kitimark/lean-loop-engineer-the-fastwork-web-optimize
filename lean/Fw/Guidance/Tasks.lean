import Fw.Guidance.Basic
/-!
# Guidance rules on main-thread tasks: long tasks, heavy compute, interval polling, offscreen work

Rules `perf.inp.break-long-tasks`, `perf.inp.split-ui-from-heavy-compute`, `perf.inp.no-heavy-interval-polling` and
`perf.background.pause-offscreen-work`. A task is modelled by the work it adds to the frame it lands in.
-/
namespace Fw.Guidance.Tasks

open Fw.Engine

/-- **Splitting a task lowers each slice (any engine).** Each part of a task split across two frames is no more work
than the whole task in one frame.

$$\forall E,\ \forall g, h \in \mathrm{FrameIn}(P):\ \operatorname{frameWork}_E(g) \preceq \operatorname{frameWork}_E(\operatorname{join}(g, h)) \land \operatorname{frameWork}_E(h) \preceq \operatorname{frameWork}_E(\operatorname{join}(g, h))$$

The largest slice shrinks or stays the same. -/
theorem split_slices {P M : Type} (E : Engine P M) (g h : FrameIn P) :
    (frameWork E g).le (frameWork E (join g h)) ∧ (frameWork E h).le (frameWork E (join g h)) :=
  ⟨frame_le_join E g h, frame_le_join_right E g h⟩

/-- **Counterexample: splitting a task raises total work (Chromium).** A task of two callbacks run as one frame and
an idle frame, against the same callbacks in two frames: the split run pays two property-tree passes instead of one,
so it is not a shift of the same work.

$$(\Sigma S).\mathrm{passes}(\mathrm{props}) = 2 \land (\Sigma L).\mathrm{passes}(\mathrm{props}) = 1 \land \lnot\operatorname{Shift}([0, 1], S, L)$$
$$\text{where } E = \operatorname{chromiumAt}(\mathrm{realChrome}),\ S = [\operatorname{frameWork}_E(\operatorname{jsWrite}(1, [\,])), \operatorname{frameWork}_E(\operatorname{jsWrite}(1, [\,]))],\ L = [\operatorname{frameWork}_E(\operatorname{jsWrite}(2, [\,])), \operatorname{frameWork}_E(\operatorname{idle})]$$

Each slice's frame runs its own update, so the guide's "total stays the same" fails. -/
theorem cr_split_total :
    (total [frameWork (Chromium.chromiumAt Chromium.realChrome) (Chromium.jsWrite 1 []),
        frameWork (Chromium.chromiumAt Chromium.realChrome) (Chromium.jsWrite 1 [])]).passes .props = 2 ∧
      (total [frameWork (Chromium.chromiumAt Chromium.realChrome) (Chromium.jsWrite 2 []),
        frameWork (Chromium.chromiumAt Chromium.realChrome) idle]).passes .props = 1 ∧
      ¬ Shift [0, 1]
        [frameWork (Chromium.chromiumAt Chromium.realChrome) (Chromium.jsWrite 1 []),
          frameWork (Chromium.chromiumAt Chromium.realChrome) (Chromium.jsWrite 1 [])]
        [frameWork (Chromium.chromiumAt Chromium.realChrome) (Chromium.jsWrite 2 []),
          frameWork (Chromium.chromiumAt Chromium.realChrome) idle] := by
  refine ⟨rfl, rfl, by decide⟩

/-- **Counterexample: splitting a task raises total work (WebKit).** The same pair on WebKit: the split run pays two
commit passes instead of one.

$$(\Sigma S).\mathrm{passes}(\mathrm{commit}) = 2 \land (\Sigma L).\mathrm{passes}(\mathrm{commit}) = 1 \land \lnot\operatorname{Shift}([0, 1], S, L)$$
$$\text{where } E = \operatorname{webkitAt}(\mathrm{safari}),\ S = [\operatorname{frameWork}_E(\operatorname{scriptOnly}(1)), \operatorname{frameWork}_E(\operatorname{scriptOnly}(1))],\ L = [\operatorname{frameWork}_E(\operatorname{scriptOnly}(2)), \operatorname{frameWork}_E(\operatorname{idle})]$$

On WebKit too each slice's frame commits. -/
theorem wk_split_total :
    (total [frameWork (WebKit.webkitAt WebKit.WkMode.safari) (scriptOnly 1),
        frameWork (WebKit.webkitAt WebKit.WkMode.safari) (scriptOnly 1)]).passes .commit = 2 ∧
      (total [frameWork (WebKit.webkitAt WebKit.WkMode.safari) (scriptOnly 2),
        frameWork (WebKit.webkitAt WebKit.WkMode.safari) idle]).passes .commit = 1 ∧
      ¬ Shift [0, 1]
        [frameWork (WebKit.webkitAt WebKit.WkMode.safari) (scriptOnly 1),
          frameWork (WebKit.webkitAt WebKit.WkMode.safari) (scriptOnly 1)]
        [frameWork (WebKit.webkitAt WebKit.WkMode.safari) (scriptOnly 2),
          frameWork (WebKit.webkitAt WebKit.WkMode.safari) idle] := by
  refine ⟨rfl, rfl, by decide⟩

/-- **Moving compute off the feedback frame lowers it (any engine).** The frame that shows input feedback is strictly
less work without a computation that runs at least one callback.

$$\forall E,\ \forall f, g \in \mathrm{FrameIn}(P):\ 0 < g.\mathrm{script} \Rightarrow \operatorname{frameWork}_E(f) \prec \operatorname{frameWork}_E(\operatorname{join}(f, g))$$

The premise is that the moved work leaves the frame; a worker's reply that lands in the same frame is not covered. -/
theorem off_feedback_lt {P M : Type} (E : Engine P M) (f g : FrameIn P) (hg : 0 < g.script) :
    (frameWork E f).lt (frameWork E (join f g)) :=
  frame_lt_join_script E f g hg

/-- **Each landed callback raises the frame's work (any engine).** `k` copies of a callback that runs script are no
more work than `n ≥ k` copies in the same frame, and strictly less when `k < n`.

$$\forall E,\ \forall h \in \mathrm{FrameIn}(P),\ \forall k, n \in \mathbb{N}:\ 0 < h.\mathrm{script} \Rightarrow \big(k \le n \Rightarrow \operatorname{frameWork}_E(\operatorname{rep}(k, h)) \preceq \operatorname{frameWork}_E(\operatorname{rep}(n, h))\big) \land \big(k < n \Rightarrow \operatorname{frameWork}_E(\operatorname{rep}(k, h)) \prec \operatorname{frameWork}_E(\operatorname{rep}(n, h))\big)$$

The model counts a timer callback as script in the frame it lands in; it has no timer or task-queue term. -/
theorem poll_lt {P M : Type} (E : Engine P M) (h : FrameIn P) (hs : 0 < h.script) (k n : Nat) :
    (k ≤ n → (frameWork E (rep k h)).le (frameWork E (rep n h))) ∧
      (k < n → (frameWork E (rep k h)).lt (frameWork E (rep n h))) :=
  ⟨rep_le E h k n, rep_lt E h hs k n⟩

/-- **Pausing a script loop removes its work (any engine).** A frame without the loop's callbacks and writes is
strictly less work than the frame with them.

$$\forall E,\ \forall f, g \in \mathrm{FrameIn}(P):\ 0 < g.\mathrm{script} \Rightarrow \operatorname{frameWork}_E(f) \prec \operatorname{frameWork}_E(\operatorname{join}(f, g))$$

A paused requestAnimationFrame loop saves its whole frame share. -/
theorem pause_loop_lt {P M : Type} (E : Engine P M) (f g : FrameIn P) (hg : 0 < g.script) :
    (frameWork E f).lt (frameWork E (join f g)) :=
  frame_lt_join_script E f g hg

/-- **Pausing a compositor animation saves nothing on the main thread (real Chrome).** Every stage but `comp` has the
same passes and units with or without one more compositor animation.

$$\forall f \in \mathrm{FrameIn}(\mathrm{CrProp}),\ \forall s \in \mathrm{Stage} \setminus \{\mathrm{comp}\}:\ \operatorname{frameWork}_E(f \oplus \mathrm{anim}).\mathrm{passes}(s) = \operatorname{frameWork}_E(f).\mathrm{passes}(s) \land \operatorname{units}_E(f \oplus \mathrm{anim}, s) = \operatorname{units}_E(f, s)\quad\text{where } E = \operatorname{chromiumAt}(\mathrm{realChrome})$$

The guide's saving is empty for a compositor animation in shipping Chrome. -/
theorem cr_pause_comp_real (f : FrameIn Chromium.CrProp) (s : Stage) (hs : s ≠ .comp) :
    (frameWork (Chromium.chromiumAt Chromium.realChrome) f.addAnim).passes s =
        (frameWork (Chromium.chromiumAt Chromium.realChrome) f).passes s ∧
      stageUnits (Chromium.chromiumAt Chromium.realChrome) f.addAnim s =
        stageUnits (Chromium.chromiumAt Chromium.realChrome) f s :=
  pause_no_main _ f (by simp [Chromium.chromiumAt, Chromium.crCompStages, Chromium.realChrome]) s hs

/-- **In the CI lane a paused compositor animation saves a style unit (Chromium).**

$$\forall f \in \mathrm{FrameIn}(\mathrm{CrProp}):\ \operatorname{units}_E(f \oplus \mathrm{anim}, \mathrm{style}) = \operatorname{units}_E(f, \mathrm{style}) + 1\quad\text{where } E = \operatorname{chromiumAt}(\mathrm{lane})$$

The lane's every-BeginFrame main frame restyles each running animation. -/
theorem cr_pause_comp_lane (f : FrameIn Chromium.CrProp) :
    stageUnits (Chromium.chromiumAt Chromium.lane) f.addAnim .style =
      stageUnits (Chromium.chromiumAt Chromium.lane) f .style + 1 := by
  simp [stageUnits, FrameIn.addAnim, Chromium.chromiumAt, Chromium.crCompStages, Chromium.lane]
  omega

/-- **Pausing a UI-process animation saves nothing on the main thread (WebKit).** Every stage but `comp` has the same
passes and units with or without one more compositor animation, in every mode.

$$\forall m \in \mathrm{WkMode},\ \forall f \in \mathrm{FrameIn}(\mathrm{WkProp}),\ \forall s \in \mathrm{Stage} \setminus \{\mathrm{comp}\}:\ \operatorname{frameWork}_E(f \oplus \mathrm{anim}).\mathrm{passes}(s) = \operatorname{frameWork}_E(f).\mathrm{passes}(s) \land \operatorname{units}_E(f \oplus \mathrm{anim}, s) = \operatorname{units}_E(f, s)\quad\text{where } E = \operatorname{webkitAt}(m)$$

The time-based case; a scroll-driven one also restyles its target (`wk_pause_scroll`). -/
theorem wk_pause_comp (m : WebKit.WkMode) (f : FrameIn WebKit.WkProp) (s : Stage) (hs : s ≠ .comp) :
    (frameWork (WebKit.webkitAt m) f.addAnim).passes s = (frameWork (WebKit.webkitAt m) f).passes s ∧
      stageUnits (WebKit.webkitAt m) f.addAnim s = stageUnits (WebKit.webkitAt m) f s :=
  pause_no_main _ f (by simp [WebKit.webkitAt]) s hs

/-- **Pausing a scroll-driven UI-process animation saves a style unit (WebKit).** In a frame that updates, the
animation adds one style unit.

$$\forall m \in \mathrm{WkMode},\ \forall a \in \mathrm{WkAnim},\ \forall e \in \mathbb{N},\ \forall \ell \in \mathrm{LayerState},\ \forall \mathit{cs} \in \mathrm{Change}(\mathrm{WkProp}^{X})^{*},\ \forall f \in \mathrm{FrameIn}(\mathrm{WkProp}^{X}),\ \forall \sigma \in \mathbb{B}:\ \operatorname{wkThread}(m, a) = \mathrm{comp} \land a.\tau = \mathrm{scroll} \land \operatorname{updates}(f) \Rightarrow \operatorname{units}_E(\operatorname{withAnim}(m, a, e, \ell, \mathit{cs}, f, \sigma), \mathrm{style}) = \operatorname{units}_E(f, \mathrm{style}) + 1\quad\text{where } E = \operatorname{webkitX}(m)$$

A scroll-driven animation ticks on the main thread when the frame updates. -/
theorem wk_pause_scroll (m : WebKit.WkMode) (a : WebKit.WkAnim) (e : Nat) (ℓ : LayerState)
    (cs : List (Change WebKit.WkPropX)) (f : FrameIn WebKit.WkPropX) (σ : Bool) (hc : WebKit.wkThread m a = .comp)
    (hs : a.timeline = .scroll) (hu : f.updates = true) :
    stageUnits (WebKit.webkitX m) (WebKit.withAnim m a e ℓ cs f σ) .style = stageUnits (WebKit.webkitX m) f .style + 1 :=
  (WebKit.scroll_comp_ride m a e ℓ cs f σ hc hs hu).2

end Fw.Guidance.Tasks
