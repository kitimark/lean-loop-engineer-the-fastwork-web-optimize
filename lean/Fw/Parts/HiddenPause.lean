import Lean.Data.Json
import Fw.Engine
import Fw.Parts.EndFlags
/-!
# Hidden pause (design note 2026-10-18 §4.2 rank 4, HP): morph.columns, morph.countdown, engine.scene

The optimization: stop an animation while the box it moves paints nothing, and let it pick up the original's value
again before it paints. Three parts use it:

* **morph.columns**: five `.track` marquees (CSS keyframes `up`/`down`, 16 s, `ease-in-out infinite alternate`,
  `translateY(±56px)`; `2.gBuqKVzi.css`, rule `.start-selling-morph-backdrop` and the column rules) inside
  `.start-selling-morph-panel`. Columns 4 and 5 are `display: none` at width ≤ 640, so 3 tracks run there; under
  `prefers-reduced-motion: reduce` no track animates.
* **morph.countdown**: the clock in the panel's centre column; each digit face is written by a JS spring per
  `requestAnimationFrame` (`2.DyWL8TcE.js` pretty 3789-3803 `GE`, 3823-3874 `$E`).
* **engine.scene**: the section scheduler (`dE`/`uE`, `IntersectionObserver` with `rootMargin` 100%) pauses CSS
  animations of a section only when it is more than one viewport away; the variant pauses a box once its ink lies in
  a rect that does not meet the viewport (`offscreen_hidden`).

**The visibility condition, from the parts.** The panel's opacity is
`clamp(0, (var(--morph) - .08) / .72, 1)` (`.start-selling-morph-panel`, one rule, no `@media` override, so it is the
same in every width band). The original's scene scheduler pauses the panel's CSS animations only at morph ≤ 0.001
(`E = s(x) > .001`, `data-start-selling-scene`). Between 0.001 and 0.08 the original's marquees run on a panel of
opacity 0: every box in it has effective opacity 0, so `Fw.Engine.visible` drops it (`panelOpacity_eq_zero_iff`).
Occlusion is not modelled (`Fw.Engine.BoxVis.drop`), so "covered" never counts as hidden here.

**What is proved.**
* Vision, class E: `hidden_pause_eq` (any box value gives the same visible scene once the moving boxes are dropped),
  `hiddenPause_visSame` (the trace form: for every environment and instant), `panel_visSame` (the parts' form with
  the morph panel's rule). The variant must show the *original's* value whenever it is not paused (`hsync`): a plain
  `animation-play-state: paused` shifts the marquee's phase (`naive_pause_shifts`), so the variant seeks to
  `origClock` on resume.
* Work, per engine:
  * Chromium lane: a paused compositor marquee loses its main-frame ride-along, style 1 → 0 per frame
    (`cr_marquee_bands`, `cr_pause_style_units`); in real Chrome the main thread is already idle
    (`cr_realChrome_pause_eq`).
  * WebKit: a compositor marquee costs the web process nothing, so pausing it changes no web-process count
    (`wk_pause_eq`, `wk_marquee_bands`): equality, not a win. Only the UI-process `comp` tick goes.
  * The countdown's skipped face writes never add work in any engine (`skipWrites_le`) and drop the style pass in
    both (`cr_countdown_style`, `wk_countdown_style`).
* Golden rows for `pnpm fw engine-check` (`goldenRows`, `packages/contracts/golden/engine/hidden-pause.jsonl`).

Premises are hypotheses. Exact arithmetic: `Rat` for morph, opacity and times; `Nat` for counts.
-/
namespace Fw.Parts.HiddenPause

open Fw.Engine

/-! ## 1. Scenes driven by an animation value -/

/-- A scene template: each box's look as a function of the animation value $a \in A$ (a box the animation does not
touch is a constant function).

$$\mathrm{Tmpl}(A) = (\mathrm{BoxId} \times (A \to \mathrm{BoxVis}))^{*}$$

The boxes of a part, each with its look as a function of the animation's current value. -/
abbrev Tmpl (A : Type) := List (BoxId × (A → BoxVis))

/-- The scene a template shows at animation value `a`.

$$\forall T \in \mathrm{Tmpl}(A),\ \forall a \in A:\ \operatorname{inst}(T, a) = [\,(i, f(a)) \mid (i, f) \in T\,]$$

Every box of the template, evaluated at the value `a`, in template order. -/
def inst {A : Type} (tm : Tmpl A) (a : A) : Scene := tm.map fun e => (e.1, e.2 a)

/-- A box look that does not depend on the animation value.

$$\forall f : A \to \mathrm{BoxVis}:\ \operatorname{Still}(f) \iff \forall a, a' \in A:\ f(a) = f(a')$$

The box looks the same whatever the animation's value. -/
def Still {A : Type} (f : A → BoxVis) : Prop := ∀ a a', f a = f a'

/-- A box look that `visible` drops for every animation value.

$$\forall \mathit{vp} \in \mathrm{Rect},\ \forall f : A \to \mathrm{BoxVis}:\ \operatorname{Hidden}_{\mathit{vp}}(f) \iff \forall a \in A:\ \operatorname{drop}_{\mathit{vp}}(f(a))$$

Whatever the animation's value, the box paints nothing in the viewport. -/
def Hidden {A : Type} (vp : Rect) (f : A → BoxVis) : Prop := ∀ a, (f a).drop vp = true

/-- Every box of the template is still or hidden.

$$\forall \mathit{vp} \in \mathrm{Rect},\ \forall T \in \mathrm{Tmpl}(A):\ \operatorname{HiddenOrStill}_{\mathit{vp}}(T) \iff \forall (i, f) \in T:\ \operatorname{Still}(f) \lor \operatorname{Hidden}_{\mathit{vp}}(f)$$

Each box either ignores the animation or is invisible for every value of it. -/
def HiddenOrStill {A : Type} (vp : Rect) (tm : Tmpl A) : Prop := ∀ e ∈ tm, Still e.2 ∨ Hidden vp e.2

/-- **Hidden pause, one instant (class E).** If every box the animation moves is dropped by `visible`, any two
animation values give the same visible scene; so a paused value and the running value look the same.

$$\forall \mathit{vp} \in \mathrm{Rect},\ \forall T \in \mathrm{Tmpl}(A):\ \operatorname{HiddenOrStill}_{\mathit{vp}}(T) \Rightarrow \forall a, a' \in A:\ \operatorname{visible}_{\mathit{vp}}(\operatorname{inst}(T, a)) = \operatorname{visible}_{\mathit{vp}}(\operatorname{inst}(T, a'))$$

While the moving boxes paint nothing, freezing the animation at any value leaves the visible scene unchanged. -/
theorem hidden_pause_eq {A : Type} (vp : Rect) :
    ∀ (tm : Tmpl A), HiddenOrStill vp tm → ∀ a a', visible vp (inst tm a) = visible vp (inst tm a')
  | [], _, _, _ => rfl
  | e :: tm, h, a, a' => by
    have ih := hidden_pause_eq vp tm (fun x hx => h x (List.mem_cons_of_mem _ hx)) a a'
    simp only [visible, inst, List.map_cons, List.filter_cons] at ih ⊢
    rcases h e List.mem_cons_self with hs | hh
    · rw [hs a a', ih]
    · simp only [hh a, hh a', Bool.not_true]
      exact ih

/-- **Hidden pause over time (class E, every environment and instant).** The original shows the animation value
$a_o(\mathit{env}, t)$, the variant $a_v(\mathit{env}, t)$. If at every instant where the variant may differ
(`hid`) every moving box is dropped, and elsewhere the variant shows the original's value, the visible scenes are
equal for every environment (every width band) and every instant.

$$\forall \mathit{vp} : \mathrm{Env} \to \mathrm{Rect},\ \forall T : \mathrm{Env} \to \mathcal{T} \to \mathrm{Tmpl}(A),\ \forall a_o, a_v : \mathrm{Env} \to \mathcal{T} \to A,\ \forall \mathit{hid} : \mathrm{Env} \to \mathcal{T} \to \mathrm{Prop}:\ \Big(\forall \mathit{env}, t:\ \mathit{hid}(\mathit{env}, t) \Rightarrow \operatorname{HiddenOrStill}_{\mathit{vp}(\mathit{env})}(T(\mathit{env}, t))\Big) \land \Big(\forall \mathit{env}, t:\ \lnot\mathit{hid}(\mathit{env}, t) \Rightarrow a_v(\mathit{env}, t) = a_o(\mathit{env}, t)\Big) \Rightarrow \operatorname{VisSame}_{\mathrm{E}}\big(\mathit{vp},\ (\mathit{env}, t) \mapsto \operatorname{inst}(T(\mathit{env}, t), a_o(\mathit{env}, t)),\ (\mathit{env}, t) \mapsto \operatorname{inst}(T(\mathit{env}, t), a_v(\mathit{env}, t))\big)$$

Pausing only while hidden, and showing the original's value otherwise, gives the original's visible scene at every
width and every instant. -/
theorem hiddenPause_visSame {A Env T : Type} (vp : Env → Rect) (tm : Env → T → Tmpl A) (aO aV : Env → T → A)
    (hid : Env → T → Prop) (hH : ∀ env t, hid env t → HiddenOrStill (vp env) (tm env t))
    (hsync : ∀ env t, ¬ hid env t → aV env t = aO env t) :
    VisSame E vp (fun env t => inst (tm env t) (aO env t)) (fun env t => inst (tm env t) (aV env t)) := by
  intro env t
  show visible (vp env) (inst (tm env t) (aO env t)) = visible (vp env) (inst (tm env t) (aV env t))
  by_cases h : hid env t
  · exact hidden_pause_eq (vp env) (tm env t) (hH env t h) _ _
  · rw [hsync env t h]

/-! ## 2. The parts' hidden condition: the morph panel's opacity -/

/-- **The morph panel's opacity** at morph value $m$ (`.start-selling-morph-panel`:
`opacity: clamp(0, calc((var(--morph) - .08) / .72), 1)`; the same rule in every width band).

$$\forall m \in \mathbb{Q}:\ \operatorname{panelOpacity}(m) = \max\!\Big(0, \min\!\Big(1, \frac{m - 0.08}{0.72}\Big)\Big)$$

The panel fades in linearly between morph 0.08 and 0.8. -/
def panelOpacity (m : Rat) : Rat := max 0 (min 1 ((m - 2/25) / (18/25)))

/-- **The exact visibility condition.** The panel's opacity is 0 exactly when morph is at most 0.08.

$$\forall m \in \mathbb{Q}:\ \operatorname{panelOpacity}(m) = 0 \iff m \le 0.08$$

The panel is fully transparent exactly up to morph 0.08 and has positive opacity above it. -/
theorem panelOpacity_eq_zero_iff (m : Rat) : panelOpacity m = 0 ↔ m ≤ 2/25 := by
  unfold panelOpacity
  constructor
  · intro h
    refine Classical.byContradiction fun hm => ?_
    grind
  · intro h; grind

/-- **The variant's pause rule** (decision function): pause the panel's animations while the panel's opacity is 0.

$$\forall m \in \mathbb{Q}:\ \operatorname{hiddenPause}(m) = \mathrm{true} \iff m \le 0.08$$

Pause exactly while morph is at most 0.08. -/
def hiddenPause (m : Rat) : Bool := decide (m ≤ 2/25)

/-- **The original's pause rule** (`E = s(x) > .001`, `data-start-selling-scene`): paused unless morph exceeds 0.001.

$$\forall m \in \mathbb{Q}:\ \operatorname{scenePaused}(m) = \mathrm{true} \iff m \le 0.001$$

The original pauses only while morph is at most 0.001. -/
def scenePaused (m : Rat) : Bool := !decide (1/1000 < m)

#guard hiddenPause 0 && hiddenPause (2/25) && !hiddenPause (81/1000) && !hiddenPause 1
#guard scenePaused 0 && scenePaused (1/1000) && !scenePaused (2/1000) && !scenePaused (1/20)
#guard panelOpacity 0 == 0 && panelOpacity (2/25) == 0 && panelOpacity (4/5) == 1 && panelOpacity 1 == 1
#guard panelOpacity (11/25) == 1/2 && panelOpacity (-1) == 0

/-- The variant pauses whenever the original does.

$$\forall m \in \mathbb{Q}:\ \operatorname{scenePaused}(m) = \mathrm{true} \Rightarrow \operatorname{hiddenPause}(m) = \mathrm{true}$$

Every morph value at which the original pauses is one at which the variant pauses too. -/
theorem scenePaused_imp_hiddenPause (m : Rat) (h : scenePaused m = true) : hiddenPause m = true := by
  simp only [scenePaused, Bool.not_eq_true', decide_eq_false_iff_not] at h
  simp only [hiddenPause, decide_eq_true_eq]
  grind

/-- A template lies under the morph panel at morph $m$: every box is still, or its effective opacity is the panel's
opacity times a factor (in the parts, the product of its own and its other ancestors' opacities; no bound on the
factor is needed).

$$\forall m \in \mathbb{Q},\ \forall T \in \mathrm{Tmpl}(A):\ \operatorname{UnderPanel}(m, T) \iff \forall (i, f) \in T:\ \operatorname{Still}(f) \lor \exists c : A \to \mathbb{Q}\ \forall a \in A:\ f(a).\mathrm{alpha} = \operatorname{panelOpacity}(m) \cdot c(a)$$

Every moving box sits inside the morph panel, so its opacity carries the panel's opacity as a factor. -/
def UnderPanel {A : Type} (m : Rat) (tm : Tmpl A) : Prop :=
  ∀ e ∈ tm, Still e.2 ∨ ∃ c : A → Rat, ∀ a, (e.2 a).alpha = panelOpacity m * c a

/-- Under the panel, the pause rule makes every moving box hidden, in every viewport.

$$\forall m \in \mathbb{Q},\ \forall \mathit{vp} \in \mathrm{Rect},\ \forall T \in \mathrm{Tmpl}(A):\ \operatorname{UnderPanel}(m, T) \land \operatorname{hiddenPause}(m) = \mathrm{true} \Rightarrow \operatorname{HiddenOrStill}_{\mathit{vp}}(T)$$

When the variant pauses, every box under the panel that moves has opacity 0 and is dropped. -/
theorem underPanel_hidden {A : Type} (m : Rat) (vp : Rect) (tm : Tmpl A) (hU : UnderPanel m tm)
    (hp : hiddenPause m = true) : HiddenOrStill vp tm := by
  have h0 : panelOpacity m = 0 := (panelOpacity_eq_zero_iff m).mpr (by simpa [hiddenPause] using hp)
  intro e he
  rcases hU e he with hs | ⟨c, hc⟩
  · exact Or.inl hs
  · refine Or.inr fun a => ?_
    have : (e.2 a).alpha ≤ 0 := by rw [hc a, h0, Rat.zero_mul]; exact Rat.le_refl
    simp [BoxVis.drop, this]

/-- **Hidden pause for the morph panel's parts (class E).** For every environment (width band, touch, hover, DPR)
and instant: if the part's boxes lie under the panel at morph $m(\mathit{env}, t)$, and the variant shows the
original's animation value whenever its pause rule does not hold, the visible scenes are equal.

$$\forall \mathit{vp} : \mathrm{Env} \to \mathrm{Rect},\ \forall m : \mathrm{Env} \to \mathcal{T} \to \mathbb{Q},\ \forall T : \mathrm{Env} \to \mathcal{T} \to \mathrm{Tmpl}(A),\ \forall a_o, a_v : \mathrm{Env} \to \mathcal{T} \to A:\ \Big(\forall \mathit{env}, t:\ \operatorname{UnderPanel}(m(\mathit{env}, t), T(\mathit{env}, t))\Big) \land \Big(\forall \mathit{env}, t:\ \operatorname{hiddenPause}(m(\mathit{env}, t)) = \mathrm{false} \Rightarrow a_v(\mathit{env}, t) = a_o(\mathit{env}, t)\Big) \Rightarrow \operatorname{VisSame}_{\mathrm{E}}\big(\mathit{vp},\ (\mathit{env}, t) \mapsto \operatorname{inst}(T(\mathit{env}, t), a_o(\mathit{env}, t)),\ (\mathit{env}, t) \mapsto \operatorname{inst}(T(\mathit{env}, t), a_v(\mathit{env}, t))\big)$$

Pausing the panel's columns and clock while the panel is transparent looks exactly like the original. -/
theorem panel_visSame {A Env T : Type} (vp : Env → Rect) (m : Env → T → Rat) (tm : Env → T → Tmpl A)
    (aO aV : Env → T → A) (hU : ∀ env t, UnderPanel (m env t) (tm env t))
    (hsync : ∀ env t, hiddenPause (m env t) = false → aV env t = aO env t) :
    VisSame E vp (fun env t => inst (tm env t) (aO env t)) (fun env t => inst (tm env t) (aV env t)) :=
  hiddenPause_visSame vp tm aO aV (fun env t => hiddenPause (m env t) = true)
    (fun env t h => underPanel_hidden (m env t) (vp env) (tm env t) (hU env t) h)
    (fun env t h => hsync env t (by simpa using h))

/-! ## 3. The offscreen form (engine.scene) -/

/-- Rectangle $s$ lies inside rectangle $R$.

$$\forall s, R \in \mathrm{Rect}:\ \operatorname{inside}(s, R) \iff R.x \le s.x \land s.x + s.w \le R.x + R.w \land R.y \le s.y \land s.y + s.h \le R.y + R.h$$

Every edge of `s` is on or within the matching edge of `R`. -/
def inside (s R : Rect) : Prop := R.x ≤ s.x ∧ s.x + s.w ≤ R.x + R.w ∧ R.y ≤ s.y ∧ s.y + s.h ≤ R.y + R.h

/-- Meeting is monotone: a rectangle that meets the viewport meets every rectangle containing it.

$$\forall \mathit{vp}, s, R \in \mathrm{Rect}:\ \operatorname{meets}(\mathit{vp}, s) \land \operatorname{inside}(s, R) \Rightarrow \operatorname{meets}(\mathit{vp}, R)$$

If a rectangle overlaps the viewport, so does anything that contains it. -/
theorem meets_of_inside (vp s R : Rect) (h : vp.meets s = true) (hi : inside s R) : vp.meets R = true := by
  simp only [Rect.meets, Bool.and_eq_true, decide_eq_true_eq] at h ⊢
  obtain ⟨hx0, hx1, hx2, hx3⟩ := hi
  grind

/-- **The offscreen form of hidden.** If, for every animation value, the box's transformed ink lies inside a rect
$R$ that does not meet the viewport, the box is hidden.

$$\forall \mathit{vp}, R \in \mathrm{Rect},\ \forall f : A \to \mathrm{BoxVis}:\ \Big(\forall a \in A:\ \operatorname{inside}\big(\operatorname{bbox}(f(a).\mathrm{xf}, f(a).\mathrm{ink}), R\big)\Big) \land \lnot\operatorname{meets}(\mathit{vp}, R) \Rightarrow \operatorname{Hidden}_{\mathit{vp}}(f)$$

A box that stays inside an offscreen section, however it moves, paints nothing. -/
theorem offscreen_hidden {A : Type} (vp R : Rect) (f : A → BoxVis)
    (hin : ∀ a, inside ((f a).xf.bbox (f a).ink) R) (hR : vp.meets R = false) : Hidden vp f := by
  intro a
  have hm : vp.meets ((f a).xf.bbox (f a).ink) = false := by
    cases h : vp.meets ((f a).xf.bbox (f a).ink)
    · rfl
    · rw [meets_of_inside vp _ R h (hin a)] at hR; exact absurd hR (by decide)
  simp [BoxVis.drop, hm]

/-- **The engine.scene pause rule** (decision function): pause a section's animations while the section's rect does
not meet the viewport.

$$\forall \mathit{vp}, R \in \mathrm{Rect}:\ \operatorname{sceneHidden}(\mathit{vp}, R) = \lnot\operatorname{meets}(\mathit{vp}, R)$$

Pause a section once it has no positive-area overlap with the viewport. -/
def sceneHidden (vp R : Rect) : Bool := !vp.meets R

#guard sceneHidden ⟨0, 0, 100, 100⟩ ⟨0, 100, 100, 50⟩
#guard !sceneHidden ⟨0, 0, 100, 100⟩ ⟨0, 99, 100, 50⟩
#guard sceneHidden ⟨0, 0, 100, 100⟩ ⟨0, 0, 100, 0⟩

/-! ## 4. The original's animation clock (what the variant seeks to on resume) -/

/-- One frame of the original marquee's local clock: it advances by the frame's duration $\Delta$ unless the
original's scene rule pauses it at the frame's morph value $m$.

$$\forall \ell, \Delta, m \in \mathbb{Q}:\ \operatorname{clockStep}(\ell, (\Delta, m)) = \begin{cases} \ell & \operatorname{scenePaused}(m) \\ \ell + \Delta & \text{otherwise} \end{cases}$$

The original's marquee time stands still only while morph is at most 0.001. -/
def clockStep (ℓ : Rat) (fr : Rat × Rat) : Rat := if scenePaused fr.2 then ℓ else ℓ + fr.1

/-- **The original's marquee clock** after frames $(\Delta_1, m_1), \dots, (\Delta_n, m_n)$, from $\ell_0$; the
variant sets its animation's current time to this value when it resumes.

$$\forall \ell_0 \in \mathbb{Q},\ \forall F \in (\mathbb{Q} \times \mathbb{Q})^{*}:\ \operatorname{origClock}(\ell_0, F) = \operatorname{foldl}(\operatorname{clockStep}, \ell_0, F)$$

The marquee time the original would show after these frames. -/
def origClock (ℓ0 : Rat) (frs : List (Rat × Rat)) : Rat := frs.foldl clockStep ℓ0

/-- The clock of a naive pause (`animation-play-state: paused` under the variant's own rule): it stands still while
the variant pauses.

$$\forall \ell_0 \in \mathbb{Q},\ \forall F \in (\mathbb{Q} \times \mathbb{Q})^{*}:\ \operatorname{naiveClock}(\ell_0, F) = \operatorname{foldl}\Big((\ell, (\Delta, m)) \mapsto \begin{cases} \ell & \operatorname{hiddenPause}(m) \\ \ell + \Delta & \text{otherwise} \end{cases},\ \ell_0,\ F\Big)$$

The marquee time a plain pause would show. -/
def naiveClock (ℓ0 : Rat) (frs : List (Rat × Rat)) : Rat :=
  frs.foldl (fun ℓ fr => if hiddenPause fr.2 then ℓ else ℓ + fr.1) ℓ0

#guard origClock 0 [(16, 0), (16, 1/20), (16, 1)] == 32
#guard naiveClock 0 [(16, 0), (16, 1/20), (16, 1)] == 16
#guard origClock 5 [] == 5 && origClock 0 [(16, 1/1000)] == 0 && origClock 0 [(16, 1/500)] == 16

/-- **A naive pause is not E.** One frame at morph 0.05 (panel transparent, original running) puts the naive clock
behind the original's, so after resuming the marquee would show a different phase; the variant must seek to
`origClock` instead.

$$\operatorname{origClock}(0, [(16, 0.05)]) = 16 \ne 0 = \operatorname{naiveClock}(0, [(16, 0.05)])$$

Freezing the marquee with a plain pause shifts its phase for good. -/
theorem naive_pause_shifts : origClock 0 [(16, 1/20)] ≠ naiveClock 0 [(16, 1/20)] := by decide +kernel

/-! ## 5. Work: frames with paused compositor animations or skipped writes -/

/-- A frame with its compositor animations paused; everything else unchanged.

$$\forall f \in \mathrm{FrameIn}(P):\ \operatorname{paused}(f) = f[\mathrm{compAnims} := 0]$$

The same frame without the running compositor animations. -/
def paused {P : Type} (f : FrameIn P) : FrameIn P := { f with compAnims := 0 }

/-- A frame with its style writes skipped; script, forced passes, hit tests and compositor animations unchanged.

$$\forall f \in \mathrm{FrameIn}(P):\ \operatorname{skipWrites}(f) = f[\mathrm{changes} := [\,]]$$

The same frame, with the callbacks still running but writing nothing. -/
def skipWrites {P : Type} (f : FrameIn P) : FrameIn P := { f with changes := [] }

private theorem coverB_self {P M : Type} (E : Engine P M) : ∀ (l : List (Change P)), coverB E l l = true
  | [] => rfl
  | c :: cs => by simp [coverB, coverB_self E cs]

/-- **Pausing never adds work**, in every engine.

$$\forall E,\ \forall f \in \mathrm{FrameIn}(P):\ \operatorname{frameWork}_E(\operatorname{paused}(f)) \preceq \operatorname{frameWork}_E(f)$$

A frame without its compositor animations costs at most the frame with them. -/
theorem pause_le {P M : Type} (E : Engine P M) (f : FrameIn P) :
    (frameWork E (paused f)).le (frameWork E f) :=
  frame_le_of_cover E f.changes [] (by simp) (coverB_self E f.changes)
    (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.zero_le _)

/-- **Skipping writes never adds work**, in every engine.

$$\forall E,\ \forall f \in \mathrm{FrameIn}(P):\ \operatorname{frameWork}_E(\operatorname{skipWrites}(f)) \preceq \operatorname{frameWork}_E(f)$$

A frame whose callbacks write nothing costs at most the frame that writes. -/
theorem skipWrites_le {P M : Type} (E : Engine P M) (f : FrameIn P) :
    (frameWork E (skipWrites f)).le (frameWork E f) :=
  frame_le_of_cover E [] f.changes (by simp) rfl
    (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _)

/-! ### Chromium -/

open Fw.Engine.Chromium in
/-- **Chromium lane: the ride-along style units go.** In every frame, pausing removes exactly one style unit per
compositor animation (the main-frame style ride-along, `crCompStages lane`).

$$\forall f \in \mathrm{FrameIn}(\mathrm{CrProp}):\ \operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{paused}(f)).\mathrm{units}(\mathrm{style}) + f.\mathrm{compAnims} = \operatorname{frameWork}_{\mathrm{chromium}}(f).\mathrm{units}(\mathrm{style})$$

Each paused compositor animation takes one style unit off the frame in the CI lane. -/
theorem cr_pause_style_units (f : FrameIn CrProp) :
    (frameWork chromium (paused f)).units .style + f.compAnims = (frameWork chromium f).units .style := by
  simp [frameWork, stageUnits, paused, chromium, chromiumAt, crCompStages, lane]

open Fw.Engine.Chromium in
/-- **Real Chrome: pausing changes no main-thread stage.** Without the lane's ride-along, a compositor animation
touches only `comp`, so every other stage's passes and units are equal.

$$\forall f \in \mathrm{FrameIn}(\mathrm{CrProp}),\ \forall s \ne \mathrm{comp}:\ W_v.\mathrm{passes}(s) = W_o.\mathrm{passes}(s) \land W_v.\mathrm{units}(s) = W_o.\mathrm{units}(s)\quad\text{where } W_v = \operatorname{frameWork}_{\operatorname{chromiumAt}(\mathrm{realChrome})}(\operatorname{paused}(f)),\ W_o = \operatorname{frameWork}_{\operatorname{chromiumAt}(\mathrm{realChrome})}(f)$$

In real Chrome the main thread already sleeps through a compositor animation, so pausing it saves nothing there. -/
theorem cr_realChrome_pause_eq (f : FrameIn CrProp) (s : Stage) (hs : s ≠ .comp) :
    (frameWork (chromiumAt realChrome) (paused f)).passes s = (frameWork (chromiumAt realChrome) f).passes s ∧
      (frameWork (chromiumAt realChrome) (paused f)).units s = (frameWork (chromiumAt realChrome) f).units s := by
  cases s <;> by_cases h : 0 < f.script <;>
    simp_all [frameWork, touched, stageUnits, paused, forcedPasses, chromiumAt, crCompStages, realChrome,
      FrameIn.updates]

open Fw.Engine.Chromium in
/-- One morph.columns marquee in Chromium: a `transform` animation on its own layer (`will-change: transform`),
valid target, document timeline.

$$\mathrm{crMarquee}(e) = (e, [\mathrm{css}(\mathrm{transform})], \mathrm{own}, \mathrm{true}, \mathrm{document})$$

A track's CSS marquee as the Chromium table sees it. -/
def crMarquee (e : Nat) : CrAnim := ⟨e, [.css .transform], .own, true, .document⟩

/-- The number of running marquees in a width/motion band: none under reduced motion, 3 at width ≤ 640 (columns 4
and 5 are `display: none`), else 5.

$$\forall \mathit{narrow}, \mathit{reduce} \in \mathbb{B}:\ \operatorname{marquees}(\mathit{narrow}, \mathit{reduce}) = \begin{cases} 0 & \mathit{reduce} \\ 3 & \lnot\mathit{reduce} \land \mathit{narrow} \\ 5 & \text{otherwise} \end{cases}\qquad (\mathit{narrow}: \text{width} \le 640,\ \mathit{reduce}: \text{prefers-reduced-motion})$$

How many tracks animate in each band. -/
def marquees (narrow reduce : Bool) : Nat := if reduce then 0 else if narrow then 3 else 5

#guard marquees false false == 5 && marquees true false == 3 && marquees false true == 0 && marquees true true == 0

open Fw.Engine.Chromium in
/-- The frame of $n$ running marquees, nothing else.

$$\forall n \in \mathbb{N}:\ \operatorname{crMarqueeFrame}(n) = \operatorname{animFrame}\big(\mathrm{lane}, [\mathrm{crMarquee}(0), \dots, \mathrm{crMarquee}(n-1)]\big)$$

One frame of the columns' marquees in the lane. -/
def crMarqueeFrame (n : Nat) : FrameIn CrProp := animFrame lane ((List.range n).map crMarquee)

open Fw.Engine.Chromium in
private theorem crMarqueeFrame_eq (n : Nat) : crMarqueeFrame n = ⟨0, 0, 0, 0, [], n⟩ := by
  have hc : ∀ e, crThread lane (crMarquee e) = .comp := fun e => transformAnim_comp lane e .own rfl
  simp [crMarqueeFrame, animFrame, List.filter_map, Function.comp_def, hc]
  rw [List.filter_eq_self.2 (fun _ _ => rfl)]; simp

open Fw.Engine.Chromium in
/-- **Chromium lane, every band: the marquee's style pass goes (1 → 0 per frame).** In a frame with only the
columns' marquees, the original pays one style pass and one style unit per marquee when any runs; the paused
variant pays none, and its work is strictly below whenever a marquee runs.

$$\forall \mathit{narrow}, \mathit{reduce} \in \mathbb{B}:\ W_v.\mathrm{passes}(\mathrm{style}) = 0 \land W_v.\mathrm{units}(\mathrm{style}) = 0 \land W_o.\mathrm{passes}(\mathrm{style}) = [\lnot\mathit{reduce}] \land W_o.\mathrm{units}(\mathrm{style}) = n \land (0 < n \Rightarrow W_v \prec W_o)$$
$$\text{where } n = \operatorname{marquees}(\mathit{narrow}, \mathit{reduce}),\ W_o = \operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{crMarqueeFrame}(n)),\ W_v = \operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{paused}(\operatorname{crMarqueeFrame}(n)))$$

In the CI lane, pausing the hidden marquees removes the per-frame style recalc in every band that animates. -/
theorem cr_marquee_bands (narrow reduce : Bool) :
    (frameWork chromium (paused (crMarqueeFrame (marquees narrow reduce)))).passes .style = 0 ∧
    (frameWork chromium (paused (crMarqueeFrame (marquees narrow reduce)))).units .style = 0 ∧
    (frameWork chromium (crMarqueeFrame (marquees narrow reduce))).passes .style = (if reduce then 0 else 1) ∧
    (frameWork chromium (crMarqueeFrame (marquees narrow reduce))).units .style = marquees narrow reduce ∧
    (0 < marquees narrow reduce →
      (frameWork chromium (paused (crMarqueeFrame (marquees narrow reduce)))).lt
        (frameWork chromium (crMarqueeFrame (marquees narrow reduce)))) := by
  rw [crMarqueeFrame_eq]
  refine ⟨?_, ?_, ?_, ?_, fun hn => ⟨pause_le _ _, Or.inl ⟨.style, Or.inl ?_⟩⟩⟩ <;>
    cases narrow <;> cases reduce <;>
    simp_all [frameWork, touched, stageUnits, forcedPasses, paused, chromium, chromiumAt, crCompStages, lane,
      FrameIn.updates, marquees]

/-! ### WebKit -/

open Fw.Engine.WebKit in
/-- **WebKit: pausing changes no web-process count.** A compositor animation costs only the UI-process `comp`
stage, so pausing it leaves every other stage's passes and units equal, in every mode and every frame.

$$\forall m \in \mathrm{WkMode},\ \forall f \in \mathrm{FrameIn}(\mathrm{WkProp}),\ \forall s \ne \mathrm{comp}:\ W_v.\mathrm{passes}(s) = W_o.\mathrm{passes}(s) \land W_v.\mathrm{units}(s) = W_o.\mathrm{units}(s)\quad\text{where } W_v = \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(\operatorname{paused}(f)),\ W_o = \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(f)$$

On WebKit the hidden marquee pause is an equality for the web process, not a win. -/
theorem wk_pause_eq (m : WkMode) (f : FrameIn WkProp) (s : Stage) (hs : s ≠ .comp) :
    (frameWork (webkitAt m) (paused f)).passes s = (frameWork (webkitAt m) f).passes s ∧
      (frameWork (webkitAt m) (paused f)).units s = (frameWork (webkitAt m) f).units s := by
  cases s <;> by_cases h : 0 < f.script <;>
    simp_all [frameWork, touched, stageUnits, paused, forcedPasses, webkitAt, FrameIn.updates]

open Fw.Engine.WebKit in
/-- One morph.columns marquee in WebKit: a time-based `transform` animation with a cubic easing in $[0, 1]$
(`ease-in-out`), rate 1, direction `alternate` (which `directionIsForwards` accepts,
`GraphicsLayerAnimation.h:80`@862f17d), positive duration, 2 keyframes, no blocker.

$$\mathrm{wkMarquee} = \operatorname{clean}([\mathrm{transform}], \mathrm{time})$$

A track's CSS marquee as the WebKit table sees it. -/
def wkMarquee : WkAnim := WkAnim.clean [.transform] .time

open Fw.Engine.WebKit in
/-- **WebKit, every band: the marquee runs in the UI process, and pausing it is web-process neutral.** The marquee
takes the legacy Core Animation path in Safari's mode and is accepted there; a frame of $n$ marquees costs no
web-process pass or unit, before and after pausing.

$$\operatorname{wkThread}(\mathrm{safari}, \mathrm{wkMarquee}) = \mathrm{comp} \land \forall \mathit{narrow}, \mathit{reduce} \in \mathbb{B},\ \forall s \ne \mathrm{comp}:\ W_o.\mathrm{passes}(s) = 0 \land W_o.\mathrm{units}(s) = 0 \land W_v.\mathrm{passes}(s) = 0 \land W_v.\mathrm{units}(s) = 0$$
$$\text{where } n = \operatorname{marquees}(\mathit{narrow}, \mathit{reduce}),\ W_o = \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{compFrame}(n)),\ W_v = \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{paused}(\operatorname{compFrame}(n)))$$

Safari already runs the marquee off the web process, so the pause shows no change there in any band. -/
theorem wk_marquee_bands :
    wkThread .safari wkMarquee = .comp ∧ ∀ (narrow reduce : Bool) (s : Stage), s ≠ .comp →
      (frameWork webkit (compFrame (marquees narrow reduce))).passes s = 0 ∧
      (frameWork webkit (compFrame (marquees narrow reduce))).units s = 0 ∧
      (frameWork webkit (paused (compFrame (marquees narrow reduce)))).passes s = 0 ∧
      (frameWork webkit (paused (compFrame (marquees narrow reduce)))).units s = 0 := by
  refine ⟨by decide, fun narrow reduce s hs => ?_⟩
  have h1 := compFrame_zero WkMode.safari (marquees narrow reduce) s hs
  have h2 := compFrame_zero WkMode.safari 0 s hs
  have hp : paused (compFrame (marquees narrow reduce)) = compFrame 0 := rfl
  exact ⟨h1.1, h1.2, hp ▸ h2.1, hp ▸ h2.2⟩

/-! ### morph.countdown: the spring keeps integrating, its face writes are skipped -/

/-- The countdown's frame while a digit springs: one `requestAnimationFrame` callback per animating digit and one
`transform` write per face (16 faces per digit), all on targets in layer state $l$ (the faces carry
`will-change: transform`, dropped to `auto` while the original's scene is paused).

$$\forall P,\ \forall p \in P,\ \forall d \in \mathbb{N},\ \forall l \in \mathrm{LayerState}:\ \operatorname{cdFrame}(p, d, l) = \big(d, 0, 0, 0, [\,(i, p, l) \mid i \in [0, 1, \dots, 16 d - 1]\,], 0\big)\qquad (|\mathrm{changes}| = 16 d;\ d = 0 \text{ gives } [\,])$$

One frame of the clock's digit spring: the callbacks and their face writes. -/
def cdFrame {P : Type} (p : P) (digits : Nat) (l : LayerState) : FrameIn P :=
  ⟨digits, 0, 0, 0, (List.range (16 * digits)).map fun i => ⟨i, p, l⟩, 0⟩

open Fw.Engine.Chromium in
/-- **Chromium lane: skipping the countdown's face writes drops the style pass.** For any number of springing digits
$d > 0$ and any layer state, the original's frame pays a style pass and the variant's (callbacks kept, writes skipped)
none; the variant's work is strictly below.

$$\forall d \in \mathbb{N},\ \forall l \in \mathrm{LayerState}:\ 0 < d \Rightarrow W_v.\mathrm{passes}(\mathrm{style}) = 0 \land W_o.\mathrm{passes}(\mathrm{style}) = 1 \land W_v \prec W_o$$
$$\text{where } W_o = \operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{cdFrame}(\mathrm{css}(\mathrm{transform}), d, l)),\ W_v = \operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{skipWrites}(\operatorname{cdFrame}(\mathrm{css}(\mathrm{transform}), d, l)))$$

In the CI lane, a hidden clock that keeps its spring but skips its writes saves the style recalc. -/
theorem cr_countdown_style (d : Nat) (l : LayerState) (hd : 0 < d) :
    (frameWork chromium (skipWrites (cdFrame (.css .transform) d l))).passes .style = 0 ∧
    (frameWork chromium (cdFrame (.css .transform) d l)).passes .style = 1 ∧
    (frameWork chromium (skipWrites (cdFrame (.css .transform) d l))).lt
      (frameWork chromium (cdFrame (.css .transform) d l)) := by
  have hst : Stage.style ∈ crStagesOf ⟨0, .css .transform, l⟩ := by cases l <;> decide
  have hne : (List.range (16 * d)).map (fun i => (⟨i, CrProp.css .transform, l⟩ : Change CrProp)) ≠ [] := by
    simp; omega
  have hmem : Stage.style ∈ touched chromium (cdFrame (.css .transform) d l) := by
    simp only [touched, List.mem_append]
    left; left; left
    refine List.mem_flatMap.mpr ⟨⟨0, .css .transform, l⟩, ?_, hst⟩
    simp [cdFrame]; omega
  have hv : (frameWork chromium (skipWrites (cdFrame (.css .transform) d l))).passes .style = 0 := by
    simp [frameWork, touched, skipWrites, cdFrame, chromium, chromiumAt, crCompStages, lane, FrameIn.updates,
      forcedPasses]
    simp [hd]
  have ho : (frameWork chromium (cdFrame (.css .transform) d l)).passes .style = 1 := by
    simp only [frameWork, hmem, ↓reduceIte]; rfl
  exact ⟨hv, ho, skipWrites_le _ _, Or.inl ⟨.style, Or.inl (by rw [hv, ho]; decide)⟩⟩

open Fw.Engine.WebKit in
/-- **WebKit: skipping the countdown's face writes drops the style pass** (a web-process win, unlike the marquee).
For any number of springing digits $d > 0$ and any layer state, the original's frame pays a style pass and the
variant's none; the variant's work is strictly below.

$$\forall d \in \mathbb{N},\ \forall l \in \mathrm{LayerState}:\ 0 < d \Rightarrow W_v.\mathrm{passes}(\mathrm{style}) = 0 \land W_o.\mathrm{passes}(\mathrm{style}) = 1 \land W_v \prec W_o$$
$$\text{where } W_o = \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{cdFrame}(\mathrm{transform}, d, l)),\ W_v = \operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{skipWrites}(\operatorname{cdFrame}(\mathrm{transform}, d, l)))$$

In Safari too, a hidden clock that skips its writes saves the style recalc. -/
theorem wk_countdown_style (d : Nat) (l : LayerState) (hd : 0 < d) :
    (frameWork webkit (skipWrites (cdFrame WkProp.transform d l))).passes .style = 0 ∧
    (frameWork webkit (cdFrame WkProp.transform d l)).passes .style = 1 ∧
    (frameWork webkit (skipWrites (cdFrame WkProp.transform d l))).lt
      (frameWork webkit (cdFrame WkProp.transform d l)) := by
  have hst : Stage.style ∈ webkit.stagesOf ⟨0, WkProp.transform, l⟩ := by cases l <;> decide
  have hmem : Stage.style ∈ touched webkit (cdFrame WkProp.transform d l) := by
    simp only [touched, List.mem_append]
    left; left; left
    refine List.mem_flatMap.mpr ⟨⟨0, WkProp.transform, l⟩, ?_, hst⟩
    simp [cdFrame]; omega
  have hv : (frameWork webkit (skipWrites (cdFrame WkProp.transform d l))).passes .style = 0 := by
    simp [frameWork, touched, skipWrites, cdFrame, webkit, webkitAt, FrameIn.updates, forcedPasses]
    simp [hd]
  have ho : (frameWork webkit (cdFrame WkProp.transform d l)).passes .style = 1 := by
    simp only [frameWork, hmem, ↓reduceIte]; rfl
  exact ⟨hv, ho, skipWrites_le _ _, Or.inl ⟨.style, Or.inl (by rw [hv, ho]; decide)⟩⟩

/-! ## 6. Golden rows for `pnpm fw engine-check` -/

/-- The relational prediction of one stage over the hidden-pause frame pairs $(v, o)$ the model knows: equal passes in
every pair give `=o`; otherwise passes at most the original's in every pair give `≤o` (not `<o`: whether a scenario
reaches a hidden frame is not modelled); else `any`.

$$\forall Q \in (\mathrm{Work} \times \mathrm{Work})^{*},\ \forall s \in \mathrm{Stage}:\ \operatorname{relPred}(Q, s) = \begin{cases} \texttt{"=o"} & \forall (v, o) \in Q:\ v.\mathrm{passes}(s) = o.\mathrm{passes}(s) \\ \texttt{"\char"2264o"} & \text{else if } \forall (v, o) \in Q:\ v.\mathrm{passes}(s) \le o.\mathrm{passes}(s) \\ \texttt{"any"} & \text{otherwise} \end{cases}\qquad (Q = [\,] \text{ gives } \texttt{"=o"})$$

Equal when no modelled hidden frame changes the stage, at most when some lowers it. -/
def relPred (pairs : List (Work × Work)) (s : Stage) : String :=
  if pairs.all (fun p => p.1.passes s == p.2.passes s) then "=o"
  else if pairs.all (fun p => decide (p.1.passes s ≤ p.2.passes s)) then "≤o" else "any"

open Fw.Engine.Chromium in
/-- The Chromium lane's hidden-pause frame pairs (variant, original): the marquee frame of every band, and the
countdown's frame for 1 and 6 springing digits in every layer state.

$$\mathrm{crPairs} = \big[(\operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{paused}(F)), \operatorname{frameWork}_{\mathrm{chromium}}(F)) \mid F = \operatorname{crMarqueeFrame}(\operatorname{marquees}(\mathit{narrow}, \mathit{reduce})),\ \mathit{narrow} \in [\mathrm{false}, \mathrm{true}],\ \mathit{reduce} \in [\mathrm{false}, \mathrm{true}]\big] \mathbin{+\!\!+} \big[(\operatorname{frameWork}_{\mathrm{chromium}}(\operatorname{skipWrites}(F)), \operatorname{frameWork}_{\mathrm{chromium}}(F)) \mid F = \operatorname{cdFrame}(\mathrm{css}(\mathrm{transform}), d, l),\ d \in [1, 6],\ l \in [\mathrm{none}, \mathrm{layer}, \mathrm{own}]\big]$$

The Chromium frames that hidden pause changes, each with its original. -/
def crPairs : List (Work × Work) :=
  ([false, true].flatMap fun ν => [false, true].map fun ρ =>
      let f := crMarqueeFrame (marquees ν ρ); (frameWork chromium (paused f), frameWork chromium f)) ++
    ([1, 6].flatMap fun d => [LayerState.none, .layer, .own].map fun l =>
      let f := cdFrame (CrProp.css .transform) d l; (frameWork chromium (skipWrites f), frameWork chromium f))

open Fw.Engine.WebKit in
/-- The WebKit hidden-pause frame pairs (variant, original), as `crPairs` with the WebKit table.

$$\mathrm{wkPairs} = \big[(\operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{paused}(F)), \operatorname{frameWork}_{\mathrm{webkit}}(F)) \mid F = \operatorname{compFrame}(\operatorname{marquees}(\mathit{narrow}, \mathit{reduce})),\ \mathit{narrow} \in [\mathrm{false}, \mathrm{true}],\ \mathit{reduce} \in [\mathrm{false}, \mathrm{true}]\big] \mathbin{+\!\!+} \big[(\operatorname{frameWork}_{\mathrm{webkit}}(\operatorname{skipWrites}(F)), \operatorname{frameWork}_{\mathrm{webkit}}(F)) \mid F = \operatorname{cdFrame}(\mathrm{transform}, d, l),\ d \in [1, 6],\ l \in [\mathrm{none}, \mathrm{layer}, \mathrm{own}]\big]$$

The WebKit frames that hidden pause changes, each with its original. -/
def wkPairs : List (Work × Work) :=
  ([false, true].flatMap fun ν => [false, true].map fun ρ =>
      let f := compFrame (marquees ν ρ); (frameWork webkit (paused f), frameWork webkit f)) ++
    ([1, 6].flatMap fun d => [LayerState.none, .layer, .own].map fun l =>
      let f := cdFrame WkProp.transform d l; (frameWork webkit (skipWrites f), frameWork webkit f))

/-- The scenario, variant label and base of every row: `swipe-v1`, runs labelled `meta.variant = "hidden-pause"`,
compared with the plain `rewrite` arm.

$$(\mathrm{scenario}, \mathrm{variant}, \mathrm{base}) = (\texttt{"swipe-v1"}, \texttt{"hidden-pause"}, \texttt{"rewrite"})$$

Where the rows apply. -/
def target : String × String × String := ("swipe-v1", "hidden-pause", "rewrite")

/-- One row in the `engine-check` schema, keys sorted.

$$\operatorname{row}(e, s, c, p) = \{\texttt{base}: \texttt{"rewrite"}, \texttt{countType}: c, \texttt{engine}: e, \texttt{prediction}: p, \texttt{scenario}: \texttt{"swipe-v1"}, \texttt{stage}: s, \texttt{variant}: \texttt{"hidden-pause"}\}$$

A prediction row as `pnpm fw engine-check --rows` reads it. -/
def row (engine stage countType pred : String) : Lean.Json :=
  Lean.Json.mkObj [("base", .str target.2.2), ("countType", .str countType), ("engine", .str engine),
    ("prediction", .str pred), ("scenario", .str target.1), ("stage", .str stage), ("variant", .str target.2.1)]

/-- **The golden rows.** Chromium (frozen classes: FireAnimationFrame, UpdateLayoutTree and cc.Commit deterministic,
Layout stable): script, style, layout and commit from `relPred crPairs`. No `compositeFailedBits` row: the model
does not say which failure bits a paused animation logs, and the class is deterministic only in the original arm.
WebKit Simulator types (no lane yet, so `unusable` until one exists): script, style, layout, commit from
`relPred wkPairs`.

$$\mathrm{goldenRows} = [\operatorname{row}(\texttt{chromium}, n, c, \operatorname{relPred}(\mathrm{crPairs}, s)) \mid (s, n, c) \in C_{\mathrm{cr}}] \mathbin{+\!\!+} [\operatorname{row}(\texttt{webkit}, n, c, \operatorname{relPred}(\mathrm{wkPairs}, s)) \mid (s, n, c) \in C_{\mathrm{wk}}]$$
$$C_{\mathrm{cr}} = [(\mathrm{script}, \texttt{"script"}, \texttt{trace.FireAnimationFrame}), (\mathrm{style}, \texttt{"style"}, \texttt{trace.UpdateLayoutTree}), (\mathrm{layout}, \texttt{"layout"}, \texttt{trace.Layout}), (\mathrm{commit}, \texttt{"commit"}, \texttt{trace.cc.Commit})],\quad C_{\mathrm{wk}} = [(\mathrm{script}, \texttt{"script"}, \texttt{FireAnimationFrame}), (\mathrm{style}, \texttt{"style"}, \texttt{RecalculateStyles}), (\mathrm{layout}, \texttt{"layout"}, \texttt{Layout}), (\mathrm{commit}, \texttt{"commit"}, \texttt{Composite})]$$

The predictions CI checks for the hidden-pause variant, eight rows. -/
def goldenRows (_ : Unit := ()) : List Lean.Json :=
  ([(Stage.script, "script", "trace.FireAnimationFrame"), (.style, "style", "trace.UpdateLayoutTree"),
      (.layout, "layout", "trace.Layout"), (.commit, "commit", "trace.cc.Commit")].map fun (s, n, c) =>
      row "chromium" n c (relPred crPairs s)) ++
    ([(Stage.script, "script", "FireAnimationFrame"), (.style, "style", "RecalculateStyles"),
      (.layout, "layout", "Layout"), (.commit, "commit", "Composite")].map fun (s, n, c) =>
      row "webkit" n c (relPred wkPairs s))

/-- The contents of `packages/contracts/golden/engine/hidden-pause.jsonl`: one compact JSON row per line.

$$\mathrm{goldenJsonl} = \mathop{\Vert}_{r \in \mathrm{goldenRows}} \big(\operatorname{json}(r) \mathbin{+\!\!+} \texttt{\textbackslash n}\big)$$

The file text the exporter writes. -/
def goldenJsonl (_ : Unit := ()) : String := String.join (goldenRows.map fun r => r.compress ++ "\n")

#guard relPred crPairs .script == "=o" && relPred crPairs .style == "≤o" && relPred crPairs .layout == "=o"
#guard relPred wkPairs .script == "=o" && relPred wkPairs .style == "≤o" && relPred wkPairs .layout == "≤o"
#guard relPred crPairs .commit == "≤o"
#guard relPred wkPairs .commit == "=o"
#guard goldenRows.length == 8
#guard relPred [] .style == "=o"
#guard relPred [(Work.zero, paintW 1)] .paint == "≤o" && relPred [(paintW 1, Work.zero)] .paint == "any"

/-! ## Under the frame-end pass (`frameWorkE`, ledger n=1)

Pausing and skipping writes keep the frame's script and reads, so both frames force the same passes. Removing writes
or animations under the same reads cannot leave a stage dirtier at frame end, so the variant's end flags imply the
original's (hypothesis `hm`), and both verdicts carry over (`Fw.Parts.EndFlags.frameE_le_mono`). -/

section EndPass

open Fw.Parts.EndFlags

/-- **Pausing never adds work, under `frameWorkE`.** For end flags where the paused frame's stage is dirty only if the
running frame's is, the paused frame costs at most the running one.

$$\forall E,\ \forall f,\ \forall e_v, e_o:\ \big(\forall s \in \operatorname{touched}_E(\operatorname{paused}(f)):\ e_v(s) = \top \Rightarrow e_o(s) = \top\big) \Rightarrow \operatorname{frameWork}^{e_v}_E(\operatorname{paused}(f)) \preceq \operatorname{frameWork}^{e_o}_E(f)$$

The frame-end pass does not undo the pause. -/
theorem pause_leE {P M : Type} (E : Engine P M) (f : FrameIn P) (ev eo : Stage → Bool)
    (hm : ∀ s, s ∈ touched E (paused f) → ev s = true → eo s = true) :
    (frameWorkE E (paused f) ev).le (frameWorkE E f eo) :=
  frameE_le_mono E ev eo (fun s => by cases s <;> rfl) (pause_le E f) hm

/-- **Skipping writes never adds work, under `frameWorkE`.**

$$\forall E,\ \forall f,\ \forall e_v, e_o:\ \big(\forall s \in \operatorname{touched}_E(\operatorname{skipWrites}(f)):\ e_v(s) = \top \Rightarrow e_o(s) = \top\big) \Rightarrow \operatorname{frameWork}^{e_v}_E(\operatorname{skipWrites}(f)) \preceq \operatorname{frameWork}^{e_o}_E(f)$$

A frame that writes nothing ends no dirtier than one that writes. -/
theorem skipWrites_leE {P M : Type} (E : Engine P M) (f : FrameIn P) (ev eo : Stage → Bool)
    (hm : ∀ s, s ∈ touched E (skipWrites f) → ev s = true → eo s = true) :
    (frameWorkE E (skipWrites f) ev).le (frameWorkE E f eo) :=
  frameE_le_mono E ev eo (fun s => by cases s <;> rfl) (skipWrites_le E f) hm

/-! ## The unhide frame (ledger n=25, row 3)

When the hidden clock becomes visible again, `hsync` writes the faces whose value differs from the original's: a
sub-list of the $16d$ face writes the original makes in every springing frame. -/

/-- The variant's unhide frame: the springing frame with only the face writes `keep` selects.

$$\forall P,\ \forall p \in P,\ \forall d,\ \forall l,\ \forall q:\ \operatorname{unhide}(p, d, l, q) = \operatorname{cdFrame}(p, d, l)\big[\mathrm{changes} := [\,c \in \operatorname{cdFrame}(p, d, l).\mathrm{changes} \mid q(c)\,]\big]$$

The re-sync writes some faces, never more than the original. -/
def unhideFrame {P : Type} (p : P) (d : Nat) (l : LayerState) (keep : Change P → Bool) : FrameIn P :=
  { cdFrame p d l with changes := (cdFrame p d l).changes.filter keep }

private theorem coverB_refl {P M : Type} (E : Engine P M) : ∀ (l : List (Change P)), coverB E l l = true
  | [] => rfl
  | c :: cs => by simp [coverB, coverB_refl E cs]

/-- **The unhide frame is `≤` (ledger n=25, row 3).** Writing any sub-list of the faces, with the same callbacks,
costs at most the original's springing frame, in every engine.

$$\forall E,\ \forall p, d, l,\ \forall q:\ \operatorname{frameWork}_E(\operatorname{unhide}(p, d, l, q)) \preceq \operatorname{frameWork}_E(\operatorname{cdFrame}(p, d, l))$$

The re-sync frame repeats a subset of the writes the original makes every frame. -/
theorem unhide_le {P M : Type} (E : Engine P M) (p : P) (d : Nat) (l : LayerState) (keep : Change P → Bool) :
    (frameWork E (unhideFrame p d l keep)).le (frameWork E (cdFrame p d l)) :=
  frame_le_of_cover E ((cdFrame p d l).changes.filter keep) ((cdFrame p d l).changes.filter (fun c => !keep c))
    (List.filter_append_perm _ _) (coverB_refl E _)
    (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _) (Nat.le_refl _)

/-- **The unhide frame under `frameWorkE`.** Neither frame reads, so every touched stage ends dirty; the bound carries
over.

$$\forall E, p, d, l, q,\ \forall e_v, e_o:\ (\forall s \in \operatorname{touched}_E(\operatorname{unhide}(p, d, l, q)):\ e_v(s) = \top) \land (\forall s \in \operatorname{touched}_E(\operatorname{cdFrame}(p, d, l)):\ e_o(s) = \top) \Rightarrow \operatorname{frameWork}^{e_v}_E(\operatorname{unhide}(p, d, l, q)) \preceq \operatorname{frameWork}^{e_o}_E(\operatorname{cdFrame}(p, d, l))$$

Read-free frames count the same in both models. -/
theorem unhide_leE {P M : Type} (E : Engine P M) (p : P) (d : Nat) (l : LayerState) (keep : Change P → Bool)
    (ev eo : Stage → Bool) (hv : ∀ s, s ∈ touched E (unhideFrame p d l keep) → ev s = true)
    (ho : ∀ s, s ∈ touched E (cdFrame p d l) → eo s = true) :
    (frameWorkE E (unhideFrame p d l keep) ev).le (frameWorkE E (cdFrame p d l) eo) :=
  frameE_le_of_dirty E ev eo hv ho (unhide_le E p d l keep)

#guard (unhideFrame (0 : Nat) 1 .none (fun c => c.elem < 3)).changes.length == 3
#guard (unhideFrame (0 : Nat) 2 .none (fun _ => true)).changes.length == 32

end EndPass

/-! ## Gate hysteresis (ledger n=25, row 2)

The scene gate turns on when the visible ratio reaches $a$ and off when it drops below $b$. Deferral moves the ratio
by its own state (a feedback loop). With a fixed scroll offset, the ratio stays within a band of width $\delta$. -/

section Hysteresis

/-- One gate step: on stays on while the ratio is at least $b$; off turns on when it reaches $a$.

$$\operatorname{step}_{a,b}(g, r) = \begin{cases} [b \le r] & g \\ [a \le r] & \lnot g \end{cases}$$

The gate with an enter and an exit threshold. -/
def gateStep (a b : Rat) (g : Bool) (r : Rat) : Bool := if g then decide (b ≤ r) else decide (a ≤ r)

/-- Gate flips over $n$ frames from frame $k$ in state $g$, where the ratio $r(k, g)$ may depend on the frame and on
the gate's own state.

$$\operatorname{flips}(0, k, g) = 0,\quad \operatorname{flips}(n + 1, k, g) = [g' \ne g] + \operatorname{flips}(n, k + 1, g')\ \text{ with } g' = \operatorname{step}_{a,b}(g, r(k, g))$$

How often the gate toggles. -/
def flips (a b : Rat) (r : Nat → Bool → Rat) : Nat → Nat → Bool → Nat
  | 0, _, _ => 0
  | n + 1, k, g =>
    let g' := gateStep a b g (r k g)
    (if g' = g then 0 else 1) + flips a b r n (k + 1) g'

#guard flips (1/2) (1/2) (fun _ g => 1/2 - if g then 1/10 else 0) 4 0 false == 4
#guard flips (1/2) (3/10) (fun _ g => 1/2 - if g then 1/10 else 0) 4 0 false == 1
#guard gateStep (1/2) (3/10) true (3/10) && !gateStep (1/2) (3/10) false (49/100)

/-- A first flip needs the ratio on the far side of the threshold the current state watches.

$$\forall a, b, r,\ \forall n, k, g:\ 0 < \operatorname{flips}(n, k, g) \Rightarrow \big(g = \bot \Rightarrow \exists j, h:\ a \le r(j, h)\big) \land \big(g = \top \Rightarrow \exists j, h:\ r(j, h) < b\big)$$

Turning on needs a ratio of at least $a$; turning off needs one below $b$. -/
theorem flips_pos (a b : Rat) (r : Nat → Bool → Rat) : ∀ (n k : Nat) (g : Bool), 0 < flips a b r n k g →
    (g = false → ∃ j h, a ≤ r j h) ∧ (g = true → ∃ j h, r j h < b)
  | 0, _, _, h => absurd h (by simp [flips])
  | n + 1, k, g, h => by
    by_cases hg : gateStep a b g (r k g) = g
    · have h' : 0 < flips a b r n (k + 1) g := by
        have e : flips a b r (n + 1) k g = flips a b r n (k + 1) g := by simp only [flips, hg, ↓reduceIte]; omega
        omega
      exact flips_pos a b r n (k + 1) g h'
    · cases g
      · refine ⟨fun _ => ⟨k, false, ?_⟩, fun h => absurd h (by simp)⟩
        simp only [gateStep, Bool.false_eq_true, ↓reduceIte, decide_eq_false_iff_not, Decidable.not_not] at hg
        exact hg
      · refine ⟨fun h => absurd h (by simp), fun _ => ⟨k, true, ?_⟩⟩
        simp only [gateStep, ↓reduceIte, decide_eq_true_eq] at hg
        exact Rat.not_le.mp hg

/-- Two flips need both a ratio of at least $a$ and one below $b$.

$$\forall a, b, r,\ \forall n, k, g:\ 1 < \operatorname{flips}(n, k, g) \Rightarrow \big(\exists j, h:\ a \le r(j, h)\big) \land \big(\exists j, h:\ r(j, h) < b\big)$$

Flips alternate between on and off. -/
theorem flips_two (a b : Rat) (r : Nat → Bool → Rat) : ∀ (n k : Nat) (g : Bool), 1 < flips a b r n k g →
    (∃ j h, a ≤ r j h) ∧ (∃ j h, r j h < b)
  | 0, _, _, h => absurd h (by simp [flips])
  | n + 1, k, g, h => by
    by_cases hg : gateStep a b g (r k g) = g
    · have e : flips a b r (n + 1) k g = flips a b r n (k + 1) g := by simp only [flips, hg, ↓reduceIte]; omega
      exact flips_two a b r n (k + 1) g (by omega)
    · have e : flips a b r (n + 1) k g = 1 + flips a b r n (k + 1) (!g) := by
        have hn : gateStep a b g (r k g) = !g := by cases g <;> simp_all
        simp only [flips, hn]; cases g <;> simp
      have hp := flips_pos a b r n (k + 1) (!g) (by omega)
      cases g
      · have h2 : a ≤ r k false := by
          simp only [gateStep, Bool.false_eq_true, ↓reduceIte, decide_eq_false_iff_not, Decidable.not_not] at hg
          exact hg
        exact ⟨⟨k, false, h2⟩, hp.2 rfl⟩
      · have h2 : r k true < b := by
          simp only [gateStep, ↓reduceIte, decide_eq_true_eq] at hg
          exact Rat.not_le.mp hg
        exact ⟨hp.1 rfl, ⟨k, true, h2⟩⟩

/-- **Hysteresis wider than the swing: at most one flip (ledger n=25, row 2).** If the ratio, over all frames and both
gate states, varies by at most $\delta$ and the gap between the thresholds exceeds $\delta$, the gate flips at most
once.

$$\forall a, b, \delta \in \mathbb{Q},\ \forall r : \mathbb{N} \times \mathbb{B} \to \mathbb{Q}:\ \delta < a - b \land \big(\forall j, h, j', h':\ r(j, h) - r(j', h') \le \delta\big) \Rightarrow \forall n, k, g:\ \operatorname{flips}(n, k, g) \le 1$$

One flip would need the ratio at least $a$ and a second one below $b$, further apart than the swing allows. -/
theorem flips_le_one (a b δ : Rat) (r : Nat → Bool → Rat) (hab : δ < a - b)
    (hδ : ∀ j h j' h', r j h - r j' h' ≤ δ) (n k : Nat) (g : Bool) : flips a b r n k g ≤ 1 := by
  apply Nat.le_of_not_lt
  intro h2
  obtain ⟨⟨j, h, hj⟩, ⟨j', h', hj'⟩⟩ := flips_two a b r n k g h2
  have := hδ j h j' h'
  grind

/-- **No hysteresis: the gate flips every frame (ledger n=25, row 2).** With equal thresholds $t$ and a deferral that
lowers the ratio by $\delta > 0$ while the gate is on, a frame sitting exactly at $t$ toggles in every frame.

$$\forall t, \delta \in \mathbb{Q}:\ 0 < \delta \Rightarrow \forall n, k, g:\ \operatorname{flips}_{t,t,\,r}(n, k, g) = n\quad\text{where } r(j, h) = t - [h]\,\delta$$

The gate's own deferral pushes the ratio across the single threshold and back. -/
theorem flips_oscillate (t δ : Rat) (hδ : 0 < δ) :
    ∀ (n k : Nat) (g : Bool), flips t t (fun _ h => t - if h then δ else 0) n k g = n
  | 0, _, _ => rfl
  | n + 1, k, g => by
    have ih := flips_oscillate t δ hδ n (k + 1) (!g)
    have hs : gateStep t t g (t - if g then δ else 0) = !g := by
      cases g
      · simp only [gateStep, Bool.false_eq_true, ↓reduceIte]; grind
      · simp only [gateStep, ite_true, Bool.not_true, decide_eq_false_iff_not]; grind
    simp only [flips, hs, ih]
    cases g <;> simp <;> omega

end Hysteresis

end Fw.Parts.HiddenPause
