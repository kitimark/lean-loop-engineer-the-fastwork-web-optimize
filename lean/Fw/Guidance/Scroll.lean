import Fw.Guidance.Basic
/-!
# Guidance rules on scrolling: native scroll-driven animation, scroll-state queries, throttling, `scrollend`

Rules `scroll-driven.native-over-js-listener`, `sticky.scroll-state-over-listener`, `perf.inp.throttle-scroll-resize`
and `scroll.defer-to-scrollend`, stated under `Fw.Engine.Chromium` and `Fw.Engine.WebKit` or for every engine.
-/
namespace Fw.Guidance.Scroll

open Fw.Engine

/-- **A native scroll-driven animation does no more main-thread work than a scroll listener (Chromium).** In a
scrolled frame, a scroll-driven animation that runs on the compositor costs no more off `comp` than a listener
callback that writes a transform, on any element and layer state, and it runs no callback.

The premise is that Chromium threads the animation: threaded animation on and a user-scrollable source. -/
theorem cr_native_scroll (m : Chromium.CrMode) (a : Chromium.CrAnim) (hc : Chromium.crThread m a = .comp) (r : Bool)
    (e : Nat) (l : LayerState) :
    offLe .comp (frameWork (Chromium.chromiumAt m) (join (changesOnly [⟨0, .scroll r, .own⟩]) (Chromium.animFrame m [a])))
        (frameWork (Chromium.chromiumAt m)
          (join (changesOnly [⟨0, .scroll r, .own⟩]) (Chromium.jsWrite 1 [⟨e, .css .transform, l⟩]))) = true ∧
      (frameWork (Chromium.chromiumAt m)
          (join (changesOnly [⟨0, .scroll r, .own⟩]) (Chromium.animFrame m [a]))).units .script <
        (frameWork (Chromium.chromiumAt m)
          (join (changesOnly [⟨0, .scroll r, .own⟩]) (Chromium.jsWrite 1 [⟨e, .css .transform, l⟩]))).units .script := by
  have hf : Chromium.animFrame m [a] = ⟨0, 0, 0, 0, [], 1⟩ := by simp [Chromium.animFrame, hc]
  rw [hf]
  obtain ⟨t, b⟩ := m
  refine ⟨?_, ?_⟩
  · cases t <;> cases b <;> cases r <;> cases l <;> rfl
  · cases t <;> cases b <;> cases r <;> cases l <;> exact Nat.zero_lt_one

/-- **The scroll-driven transform animation is threaded under the premise (Chromium).** A transform animation on a
scroll timeline whose source is user-scrollable, on a valid target, runs on the compositor when threaded animation is
on; on a source that is not user-scrollable it runs on the main thread.

The native animation stays on main when its scroller cannot be scrolled by the user. -/
theorem cr_scroll_anim_thread (m : Chromium.CrMode) (e : Nat) (l : LayerState) :
    (m.threadedAnim = true → Chromium.crThread m ⟨e, [.css .transform], l, true, .scroll true⟩ = .comp) ∧
      Chromium.crThread m ⟨e, [.css .transform], l, true, .scroll false⟩ = .main := by
  refine ⟨fun ht => ?_, ?_⟩ <;>
    simp [Chromium.crThread, Chromium.failBits, Chromium.CrProp.eligible, Chromium.CrProp.movesPixels, *]

/-- **A native scroll-driven animation does no more main-thread work than a scroll listener (WebKit).** In a scrolled
frame, a UI-process scroll-driven animation (with its style ride-along) costs no more off `comp` than a listener
callback that writes a transform, on any elements and layer states, and it runs no callback.

The premise is that WebKit accelerates the animation, which needs threaded scroll-driven animations. -/
theorem wk_native_scroll (m : WebKit.WkMode) (a : WebKit.WkAnim) (hc : WebKit.wkThread m a = .comp)
    (hs : a.timeline = .scroll) (e e' : Nat) (ℓ ℓ' : LayerState) (cs : List (Change WebKit.WkPropX)) (σ : Bool) :
    offLe .comp (frameWork (WebKit.webkitX m) (WebKit.withAnim m a e ℓ cs (WebKit.scrollStepX WebKit.emptyX) σ))
        (frameWork (WebKit.webkitX m) (WebKit.scrollStepX ⟨1, 0, 0, 0, [⟨e', .base .transform, ℓ'⟩], 0⟩)) = true ∧
      (frameWork (WebKit.webkitX m) (WebKit.withAnim m a e ℓ cs (WebKit.scrollStepX WebKit.emptyX) σ)).units .script <
        (frameWork (WebKit.webkitX m) (WebKit.scrollStepX ⟨1, 0, 0, 0, [⟨e', .base .transform, ℓ'⟩], 0⟩)).units
          .script := by
  have hf : WebKit.withAnim m a e ℓ cs (WebKit.scrollStepX WebKit.emptyX) σ =
      ⟨0, 0, 0, 0, [⟨0, .base .scrollPos, .none⟩, ⟨e, .restyle, ℓ⟩], 1⟩ := by
    simp [WebKit.withAnim, hc, WebKit.wkTicks, hs, WebKit.scrollStepX, WebKit.emptyX, FrameIn.updates]
  rw [hf]
  refine ⟨?_, ?_⟩
  · cases ℓ' <;> rfl
  · cases ℓ <;> cases ℓ' <;> exact Nat.zero_lt_one

/-- **A listener callback is strict extra work (any engine).** Adding `n > 0` callbacks to a frame is strictly more
work, whatever the frame and the engine.

When the native feature makes the same style changes as the listener, the listener's callbacks are pure overhead. -/
theorem listener_lt {P M : Type} (E : Engine P M) (f : FrameIn P) (n : Nat) (hn : 0 < n) :
    (frameWork E f).lt (frameWork E (join f (scriptOnly n))) :=
  frame_lt_join_script E f (scriptOnly n) hn

/-- **Throttling helps only when the handler runs more than once per frame (any engine).** `k` handler runs in a
frame are no more work than `n ≥ k`, and strictly less when `k < n` and the handler runs a callback.

With `n = k` (events already one per frame) throttling saves nothing. -/
theorem throttle {P M : Type} (E : Engine P M) (h : FrameIn P) (k n : Nat) :
    (k ≤ n → (frameWork E (rep k h)).le (frameWork E (rep n h))) ∧
      (0 < h.script → k < n → (frameWork E (rep k h)).lt (frameWork E (rep n h))) :=
  ⟨rep_le E h k n, fun hs hk => rep_lt E h hs k n hk⟩

/-- The run total's units on a stage are the sum of the frames' units.

The total is componentwise. -/
theorem total_units (ws : List Work) (s : Stage) : (total ws).units s = (ws.map fun w => w.units s).sum := by
  induction ws with
  | nil => rfl
  | cons w ws ih => simp [total, List.foldr, Work.add] at *; rw [← ih]

/-- The run of a scroll where the handler's work `w` runs in every scrolled frame.

The handler joins each scroll frame. -/
def perFrame {P M : Type} (E : Engine P M) (fs : List (FrameIn P)) (w : FrameIn P) : List Work :=
  fs.map fun f => frameWork E (join f w)

/-- The run of a scroll where the handler's work `w` runs once, in its own frame after the last scrolled frame.

The handler waits for `scrollend`. -/
def deferred {P M : Type} (E : Engine P M) (fs : List (FrameIn P)) (w : FrameIn P) : List Work :=
  (fs ++ [w]).map (frameWork E)

/-- Units of the per-frame run.

Each scrolled frame pays the handler's units once more. -/
theorem perFrame_units {P M : Type} (E : Engine P M) (fs : List (FrameIn P)) (w : FrameIn P) (s : Stage) :
    (total (perFrame E fs w)).units s =
      (fs.map fun f => stageUnits E f s).sum + fs.length * stageUnits E w s := by
  rw [total_units]
  induction fs with
  | nil => simp [perFrame]
  | cons f fs ih =>
    simp only [perFrame, List.map_cons, List.sum_cons, List.length_cons] at *
    rw [ih]; simp only [frameWork, units_join, Nat.succ_mul]; omega

/-- Units of the deferred run.

The handler's units are paid once. -/
theorem deferred_units {P M : Type} (E : Engine P M) (fs : List (FrameIn P)) (w : FrameIn P) (s : Stage) :
    (total (deferred E fs w)).units s = (fs.map fun f => stageUnits E f s).sum + stageUnits E w s := by
  rw [total_units]; simp [deferred, frameWork, Function.comp_def]

/-- **Deferring to `scrollend` lowers the run's units (any engine).** Over a scroll of at least one frame the deferred
run has no more units on any stage than the per-frame run, and strictly fewer on a stage the handler touches when the
scroll has at least two frames.

The claim is about units; passes are a separate question (`cr_defer_more_props`). -/
theorem defer_units {P M : Type} (E : Engine P M) (fs : List (FrameIn P)) (w : FrameIn P) (s : Stage) :
    (fs ≠ [] → (total (deferred E fs w)).units s ≤ (total (perFrame E fs w)).units s) ∧
      (2 ≤ fs.length → 0 < stageUnits E w s →
        (total (deferred E fs w)).units s < (total (perFrame E fs w)).units s) := by
  rw [deferred_units, perFrame_units]
  refine ⟨fun h => ?_, fun h hw => ?_⟩
  · have : 1 ≤ fs.length := List.length_pos_iff.mpr h
    have := Nat.mul_le_mul_right (stageUnits E w s) this
    omega
  · have := Nat.mul_le_mul_right (stageUnits E w s) h
    omega

/-- **Deferring to `scrollend` pays the handler's forced passes once (any frame inputs).** Over the scroll frames `F`,
the per-frame run's forced passes on a stage are the frames' own plus `|F|` times the handler's; the deferred run pays
the handler's once.

A layout read in the handler forces layout in every scrolled frame, or once after the scroll. -/
theorem defer_forced {P : Type} (fs : List (FrameIn P)) (w : FrameIn P) (s : Stage) :
    (fs.map fun f => forcedPasses (join f w) s).sum =
        (fs.map fun f => forcedPasses f s).sum + fs.length * forcedPasses w s ∧
      ((fs ++ [w]).map fun f => forcedPasses f s).sum = (fs.map fun f => forcedPasses f s).sum + forcedPasses w s := by
  refine ⟨?_, by simp⟩
  induction fs with
  | nil => simp
  | cons f fs ih =>
    simp only [List.map_cons, List.sum_cons, List.length_cons, forced_join, Nat.succ_mul] at *
    omega

/-- **Counterexample on passes (Chromium).** Two scrolled frames and a handler that writes a transform on an own
layer: the deferred run pays three property-tree passes, the per-frame run two, because the handler's own frame
commits again.

Deferring trades per-frame units for one extra frame's passes, so neither run dominates. -/
theorem cr_defer_more_props :
    (total (deferred (Chromium.chromiumAt Chromium.realChrome) [changesOnly [⟨0, .scroll false, .own⟩],
        changesOnly [⟨0, .scroll false, .own⟩]] (Chromium.jsWrite 1 [⟨1, .css .transform, .own⟩]))).passes .props = 3 ∧
      (total (perFrame (Chromium.chromiumAt Chromium.realChrome) [changesOnly [⟨0, .scroll false, .own⟩],
        changesOnly [⟨0, .scroll false, .own⟩]] (Chromium.jsWrite 1 [⟨1, .css .transform, .own⟩]))).passes .props = 2 ∧
      (total (deferred (Chromium.chromiumAt Chromium.realChrome) [changesOnly [⟨0, .scroll false, .own⟩],
        changesOnly [⟨0, .scroll false, .own⟩]] (Chromium.jsWrite 1 [⟨1, .css .transform, .own⟩]))).passes .script = 1 ∧
      (total (perFrame (Chromium.chromiumAt Chromium.realChrome) [changesOnly [⟨0, .scroll false, .own⟩],
        changesOnly [⟨0, .scroll false, .own⟩]] (Chromium.jsWrite 1 [⟨1, .css .transform, .own⟩]))).passes .script = 2 :=
  ⟨rfl, rfl, rfl, rfl⟩

/-- **Counterexample on passes (WebKit).** Two scrolled frames and a handler that writes a transform on an own layer:
the deferred run pays three commit passes, the per-frame run two.

On WebKit too the deferred handler's own frame commits once more. -/
theorem wk_defer_more_commit :
    (total (deferred (WebKit.webkitAt WebKit.WkMode.safari) [changesOnly [⟨0, .scrollPos, .none⟩],
        changesOnly [⟨0, .scrollPos, .none⟩]] (WebKit.jsFrame [⟨1, .transform, .own⟩]))).passes .commit = 3 ∧
      (total (perFrame (WebKit.webkitAt WebKit.WkMode.safari) [changesOnly [⟨0, .scrollPos, .none⟩],
        changesOnly [⟨0, .scrollPos, .none⟩]] (WebKit.jsFrame [⟨1, .transform, .own⟩]))).passes .commit = 2 ∧
      (total (deferred (WebKit.webkitAt WebKit.WkMode.safari) [changesOnly [⟨0, .scrollPos, .none⟩],
        changesOnly [⟨0, .scrollPos, .none⟩]] (WebKit.jsFrame [⟨1, .transform, .own⟩]))).passes .script = 1 ∧
      (total (perFrame (WebKit.webkitAt WebKit.WkMode.safari) [changesOnly [⟨0, .scrollPos, .none⟩],
        changesOnly [⟨0, .scrollPos, .none⟩]] (WebKit.jsFrame [⟨1, .transform, .own⟩]))).passes .script = 2 :=
  ⟨rfl, rfl, rfl, rfl⟩

end Fw.Guidance.Scroll
