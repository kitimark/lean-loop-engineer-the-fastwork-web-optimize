import Fw.Parts.PlatformEntries
import Fw.Parts.PlatformSweep
/-!
# platform scene: `data-start-selling-scene` and the paused rule (P5 port, `faithful`)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js` 2733-2736 (`lE`: the element is near the viewport),
  2749-2780 (`dE`: the scene registration, default `rootMargin: 100% 0px`, writes `data-start-selling-scene`
  `active` or `paused`), 13196 (the platform section's own binding of that attribute).
* `assets/2.gBuqKVzi.css` 11754-11758: under `.start-selling`, a `[data-start-selling-scene="paused"]` element and every
  descendant get `will-change: auto` and `animation-play-state: paused`, both `!important`.

**The premise.** The original does not seek animations; it sets the CSS property `animation-play-state: paused`. For a CSS
animation that freezes the animation's local time: it advances only on frames where the property is not `paused`. This file
models that local time (`advance`, `local'`) and proves, for the animations the platform section runs (`Anim`: the one-shot
entries with fill `both` and per-index delays, and the loops of 90 s, 4 s and 1 s):

* the faithful arm applies the same rule to the same activity trace, so its local times are the original's
  (`faithful_eq_original`);
* a paused span does not move local time (`local_paused_span`) and a trace with a paused span inserted ends where the trace
  without it does (`local_append_paused`): resume continues from the frozen phase, nothing is re-seeked;
* each animation shows a value that is a function of its local time only (`sample`), so a frozen local time freezes the
  shown value (`sample_paused_span`); loops are periodic in it (`loop_periodic`) and one-shots hold their first value
  through the delay and their last value after the end (`oneShot_before`, `oneShot_after`).

Pixel equality of a paused section against the original is left to the gate and visual run.
-/
namespace Fw.Parts.PlatformScene
open Fw.Parts.PlatformSweep (frac)
open Fw.Parts.PlatformEntries (Entry progress progress_before progress_after)

/-! ## 1. The scene attribute -/

/-- The original's `lE`: the element lies within one viewport above or two below the viewport.

$$\forall t, b, h \in \mathbb{Q}:\ \operatorname{near}(t, b, h) \iff b \ge -h \ \land\ t \le 2h$$ -/
def near (top bottom vh : Rat) : Bool := decide (-vh ≤ bottom) && decide (top ≤ 2 * vh)

/-- The scene attribute value for an activity flag.

$$\operatorname{attr}(\top) = \texttt{active},\quad \operatorname{attr}(\bot) = \texttt{paused}$$ -/
def attr (active : Bool) : String := if active then "active" else "paused"

/-- Whether the CSS rule pauses animations under an element with this attribute value.

$$\operatorname{pauses}(v) \iff v = \texttt{paused}$$ -/
def pauses (v : String) : Bool := v == "paused"

/-- Only the `paused` value pauses; `active` does not.

$$\forall a \in \mathbb{B}:\ \operatorname{pauses}(\operatorname{attr}(a)) = \lnot a$$ -/
theorem pauses_attr (a : Bool) : pauses (attr a) = !a := by
  cases a <;> decide

/-- The scene value of an element at a rect, the initial write of `dE`.

$$\operatorname{sceneOf}(t, b, h) = \operatorname{attr}(\operatorname{near}(t, b, h))$$ -/
def sceneOf (top bottom vh : Rat) : String := attr (near top bottom vh)

/-! ## 2. Animation local time -/

/-- One frame: its length in ms and whether the animation's `animation-play-state` is `paused` during it.

$$\mathrm{Frame} = \mathbb{Q} \times \mathbb{B}$$ -/
abbrev Frame := Rat × Bool

/-- Local time after one frame: it advances by the frame length unless the animation is paused.

$$\operatorname{advance}(\ell, (\Delta, p)) = \begin{cases} \ell & p \\ \ell + \Delta & \lnot p \end{cases}$$ -/
def advance (ℓ : Rat) (f : Frame) : Rat := if f.2 then ℓ else ℓ + f.1

/-- Local time after a frame list.

$$\operatorname{local}(\ell_0, F) = \operatorname{foldl}(\operatorname{advance}, \ell_0, F)$$ -/
def local' (ℓ0 : Rat) (fs : List Frame) : Rat := fs.foldl advance ℓ0

/-- A trace of frame lengths and activities (scene attribute `active` as `true`), as frames under the CSS rule.

$$\operatorname{frames}(A) = [(\Delta, \lnot a) \mid (\Delta, a) \in A]$$ -/
def frames (tr : List (Rat × Bool)) : List Frame := tr.map fun x => (x.1, !x.2)

/-- The original's frames: the rule pauses exactly when the attribute is `paused`.

$$\operatorname{orig}(A) = [(\Delta, \operatorname{pauses}(\operatorname{attr}(a))) \mid (\Delta, a) \in A]$$ -/
def origFrames (tr : List (Rat × Bool)) : List Frame := tr.map fun x => (x.1, pauses (attr x.2))

/-- The faithful arm writes the same attribute from the same observer and restates the same rule, so its frames are the
original's.

$$\forall A:\ \operatorname{frames}(A) = \operatorname{orig}(A) \ \land\ \forall \ell_0:\ \operatorname{local}(\ell_0, \operatorname{frames}(A)) = \operatorname{local}(\ell_0, \operatorname{orig}(A))$$ -/
theorem faithful_eq_original (tr : List (Rat × Bool)) (ℓ0 : Rat) :
    frames tr = origFrames tr ∧ local' ℓ0 (frames tr) = local' ℓ0 (origFrames tr) := by
  have h : frames tr = origFrames tr := by
    unfold frames origFrames
    apply List.map_congr_left
    intro x _
    rw [pauses_attr]
  exact ⟨h, by rw [h]⟩

/-- A paused span leaves local time where it was.

$$\forall \ell \in \mathbb{Q},\ \forall \Delta_1..\Delta_n:\ \operatorname{local}(\ell, [(\Delta_1, \top), \dots, (\Delta_n, \top)]) = \ell$$ -/
theorem local_paused_span (ℓ : Rat) (ds : List Rat) : local' ℓ (ds.map fun d => (d, true)) = ℓ := by
  induction ds generalizing ℓ with
  | nil => rfl
  | cons d ds ih =>
    simp only [List.map_cons, local', List.foldl_cons, advance, ite_true] at *
    exact ih ℓ

/-- Local time of a concatenation. $$\operatorname{local}(\ell, F \mathbin{+\!\!+} G) = \operatorname{local}(\operatorname{local}(\ell, F), G)$$ -/
theorem local_append (ℓ : Rat) (fs gs : List Frame) : local' ℓ (fs ++ gs) = local' (local' ℓ fs) gs := by
  simp [local', List.foldl_append]

/-- **Resume continues the frozen phase.** Putting a paused span before a trace does not change where the trace ends.

$$\operatorname{local}(\ell, P \mathbin{+\!\!+} F) = \operatorname{local}(\ell, F)\quad\text{for a paused span } P$$ -/
theorem local_append_paused (ℓ : Rat) (ds : List Rat) (fs : List Frame) :
    local' ℓ ((ds.map fun d => (d, true)) ++ fs) = local' ℓ fs := by
  rw [local_append, local_paused_span]

/-- Local time never goes back when frame lengths are non-negative.

$$\forall F \text{ with } \Delta \ge 0:\ \ell \le \operatorname{local}(\ell, F)$$ -/
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

$$\mathrm{Anim} = \mathrm{OneShot}(e) \mid \mathrm{Loop}(P)$$

A one-shot is an `Entry` (duration, per-index delay, fill `both`); a loop has a period $P$ in ms. -/
inductive Anim where
  | oneShot (e : Entry)
  | loop (period : Rat)

/-- The loops of the section: the 90 s review marquee, the 4 s title sweep, the 1 s search caret.

$$\mathrm{loops} = [90000, 4000, 1000]$$ -/
def loops : List Rat := [90000, 4000, 1000]

open Fw.Parts.PlatformEntries in
/-- The one-shot entries of the section (the entries golden's table): cred cards with delay $70i$, the phone, the network
pieces and flags, the invoice card and rows, the ask rows with delay $140i$.

$$\mathrm{oneShots} = [\mathrm{credCard}(0), \mathrm{credCard}(3), \mathrm{profilePhone}, \mathrm{rings}, \dots, \mathrm{askOut}(1)]$$ -/
def oneShots : List Entry :=
  [credCard 0, credCard 3, profilePhone, rings, faceLeft, faceRight, dash, shield, logo, flag 1, flag 3, flag 6,
   invoiceCard, orderRow 0, orderRow 3, askIn 0, askIn 2, askOut 1]

/-- Every listed one-shot has a positive duration.

$$\forall e \in \mathrm{oneShots}:\ D_e > 0$$ -/
theorem oneShots_dur_pos : ∀ e ∈ oneShots, 0 < e.dur := by
  decide +kernel

/-- Every listed loop has a positive period.

$$\forall P \in \mathrm{loops}:\ P > 0$$ -/
theorem loops_pos : ∀ P ∈ loops, 0 < P := by
  decide +kernel

/-- The shown value of an animation at local time $\ell$: the eased progress of a one-shot, the cycle position of a loop.

$$\operatorname{sample}(\mathrm{OneShot}(e), \ell) = p_e(\ell),\quad \operatorname{sample}(\mathrm{Loop}(P), \ell) = \operatorname{frac}(\ell / P)$$ -/
def sample : Anim → Rat → Rat
  | .oneShot e, ℓ => progress e ℓ
  | .loop P, ℓ => frac (ℓ / P)

/-- **The shown value freezes with local time.** After a paused span the animation shows what it showed before the span.

$$\forall a, \ell, \Delta_1..\Delta_n:\ \operatorname{sample}(a, \operatorname{local}(\ell, P)) = \operatorname{sample}(a, \ell)$$ -/
theorem sample_paused_span (a : Anim) (ℓ : Rat) (ds : List Rat) :
    sample a (local' ℓ (ds.map fun d => (d, true))) = sample a ℓ := by
  rw [local_paused_span]

/-- Loops are periodic in local time.

$$\forall P > 0:\ \operatorname{sample}(\mathrm{Loop}(P), \ell + P) = \operatorname{sample}(\mathrm{Loop}(P), \ell)$$ -/
theorem loop_periodic (P ℓ : Rat) (hP : 0 < P) : sample (.loop P) (ℓ + P) = sample (.loop P) ℓ := by
  have h : (ℓ + P) / P = ℓ / P + 1 := by grind
  simp only [sample, h, frac]
  have : ((ℓ / P + 1).floor : Rat) = ((ℓ / P).floor : Rat) + 1 := by
    rw [Rat.floor_add_one]; push_cast; rfl
  rw [this]; grind

/-- A one-shot holds its first value through the delay (fill `backwards` of `both`), also while paused in it.

$$e = (\cdot, D, d, \cdot),\ D > 0,\ \ell \le d \Rightarrow \operatorname{sample}(\mathrm{OneShot}(e), \ell) = 0$$ -/
theorem oneShot_before (e : Entry) (ℓ : Rat) (hD : 0 < e.dur) (h : ℓ ≤ e.delay) : sample (.oneShot e) ℓ = 0 :=
  progress_before e ℓ hD h

/-- A one-shot holds its last value after its end (fill `forwards` of `both`), under any pause trace.

$$e = (\cdot, D, d, \cdot),\ D > 0,\ d + D \le \ell,\ \Delta \ge 0 \Rightarrow \operatorname{sample}(\mathrm{OneShot}(e), \operatorname{local}(\ell, F)) = 1$$ -/
theorem oneShot_after (e : Entry) (ℓ : Rat) (fs : List Frame) (hD : 0 < e.dur) (h : e.delay + e.dur ≤ ℓ)
    (hf : ∀ f ∈ fs, 0 ≤ f.1) : sample (.oneShot e) (local' ℓ fs) = 1 :=
  progress_after e _ hD (Rat.le_trans h (local_mono ℓ fs hf))

end Fw.Parts.PlatformScene
