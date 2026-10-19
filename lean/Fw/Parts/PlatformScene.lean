import Fw.Parts.PlatformEntries
import Fw.Parts.PlatformSweep
/-!
# platform scene: `data-start-selling-scene` and the paused rule (P5 port, `faithful`)

Restated (not copied) from `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`: `lE` 2715-2718 (initial activity),
`cE` 2709-2713 (attribute on each observer change), `uE` 2719-2748 (shared IntersectionObserver), `dE` 2749-2782
(registration; `rootMargin` defaults to `100% 0px`, `manageAnimations` to true when an element is given); the platform
section registers at 12448 (`dE(r, {deferRendering: !0, element: o})`, `o` bound to the section root at 12668-12672).
CSS: `assets/2.gBuqKVzi.css` 11754-11758. Consumers: `platform/scene.ts` (golden `platform.scene.jsonl`) and
`HiddenPausePlatform` (the engine.scene variant's clock).

Not covered, in the original and the port alike: the SMIL glint (`platform.glint`) and the JS count-up (2.DyWL8TcE.js
11996-12040), which `animation-play-state` does not pause. Not ported: the scheduler's per-frame gate
`e.active && e.callback()` (2670-2673) on the section's shrink callback (12436-12448); the port runs `platform.shrink`
every scroll frame. INFERRED same visual: while inactive the section lies more than one viewport from the viewport; the
work differs and is not claimed. Pixel equality is left to the gate and visual run.
-/
namespace Fw.Parts.PlatformScene
open Fw.Parts.PlatformSweep (frac)
open Fw.Parts.PlatformEntries (Entry progress progress_before progress_after)

/-! ## 1. The scene attribute -/

/-- The original's `lE` (2.DyWL8TcE.js 2715-2718), with `t, b` the element's top and bottom relative to the viewport's top
and `h` the viewport height.

The element's bottom is not more than one viewport above the viewport's top edge, and its top not more than one viewport
below the viewport's bottom edge. -/
def near (top bottom vh : Rat) : Bool := decide (-vh ≤ bottom) && decide (top ≤ 2 * vh)

/-- The scene attribute value for an activity flag.

An active element gets `active`, any other gets `paused`. -/
def attr (active : Bool) : String := if active then "active" else "paused"

/-- Whether the CSS rule pauses animations under an element with this attribute value.

The rule matches the exact value `paused` and nothing else. -/
def pauses (v : String) : Bool := v == "paused"

/-- Only the `paused` value pauses; `active` does not.

The rule pauses an element exactly when it is not active. -/
theorem pauses_attr (a : Bool) : pauses (attr a) = !a := by
  cases a <;> decide

/-- The scene value of an element at a rect, the initial write of `dE`.

A near element is `active`, a far one `paused`. -/
def sceneOf (top bottom vh : Rat) : String := attr (near top bottom vh)

/-! ## 2. Animation local time -/

/-- One frame: its length in ms and whether the animation's `animation-play-state` is `paused` during it.

A frame is a duration paired with a paused flag. -/
abbrev Frame := Rat × Bool

/-- Local time after one frame. This is the premise of the module, CONFIRMED for a CSS animation on which script never
called `play()` or `pause()`: css-animations-1 `animation-play-state` (a paused animation keeps its current time, resuming
continues from it); Blink `third_party/blink/renderer/core/animation/css/css_animations.cc:2021-2046@f842f52` (a play
state change toggles pause unless `GetIgnoreCSSPlayState`, which `css_animation.cc:45-57` sets on script `play()` or
`pause()` and `setCurrentTime` does not); WebKit `Source/WebCore/animation/CSSAnimation.cpp:162-185@862f17d` (newly
paused runs `pause()`, newly running `play(AutoRewind::No)`, skipped once bindings `play()`/`pause()` set
`m_overriddenProperties`) and `WebAnimation.cpp:1349-1379@862f17d` (`pause()` stores the current time as hold time).

Local time advances by the frame length unless the animation is paused. -/
def advance (ℓ : Rat) (f : Frame) : Rat := if f.2 then ℓ else ℓ + f.1

/-- Local time after a frame list.

Local time after the frames in order, from `ℓ_0`; the empty list leaves `ℓ_0`. -/
def local' (ℓ0 : Rat) (fs : List Frame) : Rat := fs.foldl advance ℓ0

/-- A trace of frame lengths and activities (scene attribute `active` as `true`), as frames under the CSS rule.

The port pauses a frame exactly when the section is not active. -/
def frames (tr : List (Rat × Bool)) : List Frame := tr.map fun x => (x.1, !x.2)

/-- The original's frames: the rule pauses exactly when the attribute is `paused`.

The original pauses a frame when its attribute value matches the paused rule. -/
def origFrames (tr : List (Rat × Bool)) : List Frame := tr.map fun x => (x.1, pauses (attr x.2))

/-- The faithful arm's frames are the original's.

The port writes `data-fw-scene` where the original writes `data-start-selling-scene`, with the same values and rule; the
TS link to this model is the golden and the gate. -/
theorem faithful_eq_original (tr : List (Rat × Bool)) (ℓ0 : Rat) :
    frames tr = origFrames tr ∧ local' ℓ0 (frames tr) = local' ℓ0 (origFrames tr) := by
  have h : frames tr = origFrames tr := by
    unfold frames origFrames
    apply List.map_congr_left
    intro x _
    rw [pauses_attr]
  exact ⟨h, by rw [h]⟩

/-- A paused span leaves local time where it was.

Paused frames of any lengths, none included, do not move local time. -/
theorem local_paused_span (ℓ : Rat) (ds : List Rat) : local' ℓ (ds.map fun d => (d, true)) = ℓ := by
  induction ds generalizing ℓ with
  | nil => rfl
  | cons d ds ih =>
    simp only [List.map_cons, local', List.foldl_cons, advance, ite_true] at *
    exact ih ℓ

/-- Local time of a concatenation.

Running two frame lists in a row is running the first, then the second from where it ended. -/
theorem local_append (ℓ : Rat) (fs gs : List Frame) : local' ℓ (fs ++ gs) = local' (local' ℓ fs) gs := by
  simp [local', List.foldl_append]

/-- **Resume continues the frozen phase.** Putting a paused span before a trace does not change where the trace ends.

A paused span is skipped: nothing is re-seeked on resume. -/
theorem local_append_paused (ℓ : Rat) (ds : List Rat) (fs : List Frame) :
    local' ℓ ((ds.map fun d => (d, true)) ++ fs) = local' ℓ fs := by
  rw [local_append, local_paused_span]

/-- Local time never goes back when frame lengths are non-negative.

With no negative frame length, local time ends at or after where it started. -/
theorem local_mono (ℓ : Rat) (fs : List Frame) (h : ∀ f ∈ fs, 0 ≤ f.1) : ℓ ≤ local' ℓ fs := by
  induction fs generalizing ℓ with
  | nil => exact Rat.le_refl
  | cons f fs ih =>
    have h0 : 0 ≤ f.1 := h f (by simp)
    have h1 := ih (advance ℓ f) (fun g hg => h g (by simp [hg]))
    have h2 : ℓ ≤ advance ℓ f := by unfold advance; split <;> grind
    simp only [local', List.foldl_cons] at *
    grind

/-! ## 3. The platform animations -/

/-- The kinds of animation in the platform section.

A one-shot is an `Entry` (duration, per-index delay, fill `both`); a loop has a period `T` in ms. -/
inductive Anim where
  | oneShot (e : Entry)
  | loop (period : Rat)

/-- The loops of the section: the 90 s review marquee, the 4 s title sweep, the 1 s search caret.

The three loop periods in ms. -/
def loops : List Rat := [90000, 4000, 1000]

open Fw.Parts.PlatformEntries in
/-- The one-shot entries sampled by the entries golden's table; every theorem below holds for any `Entry`.

A representative sample, not every rendered entry. -/
def oneShots : List Entry :=
  [credCard 0, credCard 3, profilePhone, rings, faceLeft, faceRight, dash, shield, logo, flag 1, flag 3, flag 6,
   invoiceCard, orderRow 0, orderRow 3, askIn 0, askIn 2, askOut 1]

/-- Every listed one-shot has a positive duration.

No sampled entry has zero duration. -/
theorem oneShots_dur_pos : ∀ e ∈ oneShots, 0 < e.dur := by
  decide +kernel

/-- Every listed loop has a positive period.

No loop has a zero or negative period. -/
theorem loops_pos : ∀ P ∈ loops, 0 < P := by
  decide +kernel

/-- The shown value of an animation at local time `ℓ`: the eased progress of a one-shot, the cycle position of a loop.

The value depends on local time only; `ℓ / 0 = 0` in `Rat`, so a zero period samples 0. -/
def sample : Anim → Rat → Rat
  | .oneShot e, ℓ => progress e ℓ
  | .loop P, ℓ => frac (ℓ / P)

/-- **The shown value freezes with local time.** After a paused span the animation shows what it showed before the span.

A paused span leaves the shown value unchanged. -/
theorem sample_paused_span (a : Anim) (ℓ : Rat) (ds : List Rat) :
    sample a (local' ℓ (ds.map fun d => (d, true))) = sample a ℓ := by
  rw [local_paused_span]

/-- Loops are periodic in local time.

One period later a loop shows the same value. -/
theorem loop_periodic (P ℓ : Rat) (hP : 0 < P) : sample (.loop P) (ℓ + P) = sample (.loop P) ℓ := by
  have h : (ℓ + P) / P = ℓ / P + 1 := by grind
  simp only [sample, h, frac]
  have : ((ℓ / P + 1).floor : Rat) = ((ℓ / P).floor : Rat) + 1 := by
    rw [Rat.floor_add_one]; push_cast; rfl
  rw [this]; grind

/-- A one-shot holds its first value through the delay (fill `backwards` of `both`), also while paused in it.

Before its delay has passed, a one-shot shows its first keyframe. -/
theorem oneShot_before (e : Entry) (ℓ : Rat) (hD : 0 < e.dur) (h : ℓ ≤ e.delay) : sample (.oneShot e) ℓ = 0 :=
  progress_before e ℓ hD h

/-- A one-shot holds its last value after its end (fill `forwards` of `both`), under any pause trace.

Once ended, a one-shot keeps its last keyframe whatever frames follow. -/
theorem oneShot_after (e : Entry) (ℓ : Rat) (fs : List Frame) (hD : 0 < e.dur) (h : e.delay + e.dur ≤ ℓ)
    (hf : ∀ f ∈ fs, 0 ≤ f.1) : sample (.oneShot e) (local' ℓ fs) = 1 :=
  progress_after e _ hD (Rat.le_trans h (local_mono ℓ fs hf))

end Fw.Parts.PlatformScene
