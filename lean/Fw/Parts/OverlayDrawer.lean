import Fw.Parts.Bezier
/-!
# overlays.drawer: the "why bring" drawer (wave 2 port, `faithful`)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`
  * 2893-2926 (`EE`): the mount/show state machine. The drawer is rendered only while `mounted`. When the `open` prop
    turns true: clear the pending timer, set `mounted`, then (after a microtask and one animation frame) set `shown` and
    focus the close button. When it turns false and the drawer is mounted: clear the timer, clear `shown`, and unmount
    after 480 ms (0 ms under `prefers-reduced-motion: reduce`). The frame callback is never cancelled;
  * 2927-2933: `document.body.style.overflow = hidden` while `open`, restored on cleanup;
  * 2934-2943: `Escape` on `window` closes when `mounted`;
  * 3006: class `is-open` follows `shown`; the close button, the backdrop button and the footer button all call `onClose`.
* `assets/2.gBuqKVzi.css` 684-734 (box, backdrop and panel, transitions `0.4s ease-in-out`), 899-914 (`width<=860px`),
  1145-1165 (`width<=640px`), 1215-1218 (reduced motion: `transition: none`).

All values `Rat` (sizes may be fractional). No `Float`.
-/
namespace Fw.Parts.OverlayDrawer
open Fw.Parts.Bezier

/-! ## Constants -/

/-- Panel and backdrop transition length in ms (CSS `0.4s`). $$T = 400$$ How long the slide and the fade take. -/
def transitionMs : Rat := 400

/-- Delay before the closed drawer is unmounted, ms (JS 2917). $$U = 480$$ A little longer than the transition. -/
def unmountMs : Rat := 480

/-- The extra off-screen distance of the hidden panel at the side and mid layouts, px (CSS `calc(100% + 48px)`). $$g = 48$$ -/
def hideGap : Rat := 48

/-! ## The show/hide state machine -/

/-- State of the drawer component: rendered, shown (class `is-open`), a frame callback waiting, and the unmount deadline.

$$S = (\mathit{mounted}, \mathit{shown}, \mathit{rafPending}, \mathit{timerAt} \in \mathbb{Q} \cup \{\bot\})$$ -/
structure St where
  mounted : Bool
  shown : Bool
  rafPending : Bool
  timerAt : Option Rat
deriving Repr, BEq, DecidableEq

/-- Not rendered. $$S_0 = (\bot, \bot, \bot, \bot)$$ The state before the first open. -/
def rest : St := ⟨false, false, false, none⟩

/-- The `open` prop changes to $b$ at time $now$ (the effect at JS 2906-2920).

$$\operatorname{setOpen}(S, b, now, r) = \begin{cases}
(\top, \mathit{shown}, \top, \bot) & b = \top \\
(\mathit{mounted}, \bot, \mathit{raf}, now + (r\ ?\ 0 : 480)) & b = \bot,\ \mathit{mounted} \\
(\mathit{mounted}, \mathit{shown}, \mathit{raf}, \bot) & b = \bot,\ \lnot \mathit{mounted}
\end{cases}$$

Here $r$ is "reduced motion". Opening never resets `shown` (so a re-open during the close delay slides in again, a
re-open after a quirky unmount does not). -/
def setOpen (s : St) (b : Bool) (now : Rat) (reduced : Bool) : St :=
  if b then ⟨true, s.shown, true, none⟩
  else if s.mounted then ⟨true, false, s.rafPending, some (now + (if reduced then 0 else unmountMs))⟩
  else ⟨s.mounted, s.shown, s.rafPending, none⟩

/-- The animation frame after an open fires (JS 2910-2912): `shown` is set whatever the prop is now.

$$\operatorname{raf}(S) = \begin{cases} (\mathit{mounted}, \top, \bot, \mathit{timerAt}) & \mathit{rafPending} \\ S & \text{otherwise}\end{cases}$$ -/
def raf (s : St) : St := if s.rafPending then ⟨s.mounted, true, false, s.timerAt⟩ else s

/-- The unmount timer is due at time $now$ (JS 2916-2919).

$$\operatorname{tick}(S, now) = \begin{cases} (\bot, \mathit{shown}, \mathit{raf}, \bot) & \mathit{timerAt} = d,\ d \le now \\ S & \text{otherwise}\end{cases}$$ -/
def tick (s : St) (now : Rat) : St :=
  match s.timerAt with
  | some d => if d ≤ now then ⟨false, s.shown, s.rafPending, none⟩ else s
  | none => s

/-- `Escape` on the window asks to close exactly when the drawer is mounted (JS 2934-2943).

$$\operatorname{escapeCloses}(S, k) \iff k = \text{"Escape"} \land \mathit{mounted}$$ -/
def escapeCloses (s : St) (key : String) : Bool := key == "Escape" && s.mounted

/-- The body overflow while the drawer is open (JS 2927-2933): `hidden`, else what it was.

$$\operatorname{overflow}(b, p) = \begin{cases} \text{hidden} & b \\ p & \text{otherwise}\end{cases}$$ -/
def bodyOverflow (open_ : Bool) (prev : String) : String := if open_ then "hidden" else prev

#guard (raf (setOpen rest true 0 false)) == ⟨true, true, false, none⟩
#guard (tick (setOpen (raf (setOpen rest true 0 false)) false 100 false) 579) ==
  ⟨true, false, false, some 580⟩
#guard (tick (setOpen (raf (setOpen rest true 0 false)) false 100 false) 580) == ⟨false, false, false, none⟩

/-- Opening then the frame shows the drawer. $$\operatorname{raf}(\operatorname{setOpen}(S, \top)) = (\top, \top, \bot, \bot)$$ -/
theorem open_raf (s : St) (now : Rat) (r : Bool) :
    raf (setOpen s true now r) = ⟨true, true, false, none⟩ := by
  simp [setOpen, raf]

/-- Closing a shown, mounted drawer hides it at once and schedules the unmount.

$$\mathit{mounted} \Rightarrow \operatorname{setOpen}(S, \bot, now, r) = (\top, \bot, \mathit{raf}, now + (r\ ?\ 0 : 480))$$ -/
theorem close_schedules (s : St) (now : Rat) (r : Bool) (h : s.mounted = true) :
    setOpen s false now r = ⟨true, false, s.rafPending, some (now + (if r then 0 else unmountMs))⟩ := by
  simp [setOpen, h]

/-- Before the deadline the drawer stays mounted. $$now < d \Rightarrow \operatorname{tick}(S, now) = S$$ -/
theorem tick_early (s : St) (d now : Rat) (h : s.timerAt = some d) (hn : now < d) : tick s now = s := by
  have : ¬ d ≤ now := by grind
  simp [tick, h, this]

/-- At the deadline the drawer unmounts. $$d \le now \Rightarrow \operatorname{mounted}(\operatorname{tick}(S, now)) = \bot$$ -/
theorem tick_due (s : St) (d now : Rat) (h : s.timerAt = some d) (hn : d ≤ now) :
    (tick s now).mounted = false ∧ (tick s now).timerAt = none := by
  simp [tick, h, hn]

/-- A whole open and close cycle ends at rest when the frame fired before the close.

$$\operatorname{tick}(\operatorname{setOpen}(\operatorname{raf}(\operatorname{setOpen}(S_0, \top, t_0)), \bot, t_1), t_1 + 480) = (\bot, \bot, \bot, \bot)$$

(motion allowed). -/
theorem full_cycle (t0 t1 : Rat) :
    tick (setOpen (raf (setOpen rest true t0 false)) false t1 false) (t1 + unmountMs) = rest := by
  have h : t1 + unmountMs ≥ t1 + (if false = true then 0 else unmountMs) := by simp
  simp [setOpen, raf, rest, tick]

/-- Under reduced motion the unmount is due at the close itself.

$$\operatorname{tick}(\operatorname{setOpen}(\operatorname{raf}(\operatorname{setOpen}(S_0, \top, t_0)), \bot, t_1, \top), t_1) = S_0$$ -/
theorem reduced_cycle (t0 t1 : Rat) :
    tick (setOpen (raf (setOpen rest true t0 true)) false t1 true) t1 = rest := by
  simp [setOpen, raf, rest, tick, Rat.add_zero]

/-- The original's quirk, kept: a close before the frame fires lets the frame set `shown` afterwards, and the unmount
leaves `shown` set, so the next open shows the panel without sliding.

$$\operatorname{tick}(\operatorname{raf}(\operatorname{setOpen}(\operatorname{setOpen}(S_0, \top, t_0), \bot, t_1)), t_1 + 480) = (\bot, \top, \bot, \bot)$$ -/
theorem quirk_close_before_frame (t0 t1 : Rat) :
    tick (raf (setOpen (setOpen rest true t0 false) false t1 false)) (t1 + unmountMs) = ⟨false, true, false, none⟩ := by
  simp [setOpen, raf, rest, tick]

/-- Escape closes only a mounted drawer. $$\operatorname{escapeCloses}(S, k) = \top \Rightarrow \mathit{mounted}$$ -/
theorem escape_needs_mounted (s : St) (k : String) (h : escapeCloses s k = true) : s.mounted = true := by
  simp [escapeCloses] at h
  exact h.2

/-! ## Layout and the slide -/

/-- The three layouts of the panel. $$\text{side} \,(w > 860),\ \text{mid} \,(641 \le w \le 860),\ \text{sheet} \,(w \le 640)$$ -/
inductive Layout where
  | side
  | mid
  | sheet
deriving Repr, BEq, DecidableEq

/-- Layout from the viewport width (CSS 899 `width<=860px`, 1133 `width<=640px`).

$$\operatorname{layout}(w) = \begin{cases} \text{sheet} & w \le 640 \\ \text{mid} & 640 < w \le 860 \\ \text{side} & w > 860 \end{cases}$$ -/
def layoutOf (w : Rat) : Layout := if w ≤ 640 then .sheet else if w ≤ 860 then .mid else .side

/-- Where the hidden panel sits, relative to its shown position, for a panel of size $p_w \times p_h$ (CSS `transform`).

$$\operatorname{hidden}(\ell, p_w, p_h) = \begin{cases} (p_w + 48,\ 0) & \ell = \text{side} \\ (0,\ p_h + 48) & \ell = \text{mid} \\ (0,\ p_h) & \ell = \text{sheet}\end{cases}$$ -/
def hidden (l : Layout) (pw ph : Rat) : Rat × Rat :=
  match l with
  | .side => (pw + hideGap, 0)
  | .mid => (0, ph + hideGap)
  | .sheet => (0, ph)

/-- Progress of the transition $e$ ms after the class flips.

$$p(e, r) = \begin{cases} 1 & r \\ \operatorname{ease}_{\text{ease-in-out}}(e / 400) & \lnot r\end{cases}$$

Reduced motion sets `transition: none` (CSS 1215), so the end state is immediate. -/
def progress (elapsed : Rat) (reduced : Bool) : Rat :=
  if reduced then 1 else ease easeInOut (elapsed / transitionMs)

/-- The panel's translation $e$ ms after `shown` became $s$ (from the settled opposite state).

$$\operatorname{pos}(s, e) = \begin{cases} (1 - p)\,\mathrm{hidden} & s = \top \\ p\,\mathrm{hidden} & s = \bot\end{cases}$$ -/
def panelPos (l : Layout) (pw ph : Rat) (shown : Bool) (elapsed : Rat) (reduced : Bool) : Rat × Rat :=
  let p := progress elapsed reduced
  let f := if shown then 1 - p else p
  let h := hidden l pw ph
  (h.1 * f, h.2 * f)

/-- The backdrop opacity $e$ ms after `shown` became $s$.

$$\operatorname{alpha}(s, e) = \begin{cases} p & s = \top \\ 1 - p & s = \bot\end{cases}$$ -/
def backdropAlpha (shown : Bool) (elapsed : Rat) (reduced : Bool) : Rat :=
  let p := progress elapsed reduced
  if shown then p else 1 - p

#guard layoutOf 641 == .mid && layoutOf 640 == .sheet && layoutOf 860 == .mid && layoutOf 861 == .side
#guard panelPos .side 600 500 true 0 false == (648, 0)
#guard panelPos .side 600 500 true 400 false == (0, 0)
#guard panelPos .sheet 390 700 false 400 false == (0, 700)

/-- The sheet layout is below 641 px, the mid layout 641-860 px, the side layout above.

$$w \le 640 \Rightarrow \text{sheet};\quad 640 < w \le 860 \Rightarrow \text{mid};\quad w > 860 \Rightarrow \text{side}$$ -/
theorem layout_bands (w : Rat) :
    (w ≤ 640 → layoutOf w = .sheet) ∧ (640 < w → w ≤ 860 → layoutOf w = .mid) ∧ (860 < w → layoutOf w = .side) := by
  refine ⟨fun h => ?_, fun h1 h2 => ?_, fun h => ?_⟩ <;> simp [layoutOf] <;> grind

/-- Opening starts at the hidden position. $$\operatorname{pos}(\top, 0) = \mathrm{hidden}$$ -/
theorem pos_start_open (l : Layout) (pw ph : Rat) :
    panelPos l pw ph true 0 false = hidden l pw ph := by
  have h : progress 0 false = 0 := by
    have z : (0 : Rat) / transitionMs = 0 := by unfold transitionMs; grind
    simp [progress, z, ease_zero]
  unfold panelPos; rw [h]; exact Prod.ext (by grind) (by grind)

/-- Opening ends at the shown position after 400 ms. $$e \ge 400 \Rightarrow \operatorname{pos}(\top, e) = (0, 0)$$ -/
theorem pos_end_open (l : Layout) (pw ph e : Rat) (he : 400 ≤ e) :
    panelPos l pw ph true e false = (0, 0) := by
  have h1 : 1 ≤ e / transitionMs := by
    have : e / transitionMs = e * (1 / 400) := by unfold transitionMs; grind
    grind
  have h : progress e false = 1 := by
    simp [progress, ease_ge_one _ _ h1]
  unfold panelPos; rw [h]; exact Prod.ext (by grind) (by grind)

/-- Closing ends at the hidden position after 400 ms. $$e \ge 400 \Rightarrow \operatorname{pos}(\bot, e) = \mathrm{hidden}$$ -/
theorem pos_end_close (l : Layout) (pw ph e : Rat) (he : 400 ≤ e) :
    panelPos l pw ph false e false = hidden l pw ph := by
  have h1 : 1 ≤ e / transitionMs := by
    have : e / transitionMs = e * (1 / 400) := by unfold transitionMs; grind
    grind
  have h : progress e false = 1 := by
    simp [progress, ease_ge_one _ _ h1]
  simp [panelPos, h]

/-- Under reduced motion the panel is at its end state at once. $$\forall e:\ \operatorname{pos}(\top, e, \top) = (0,0)$$ -/
theorem pos_reduced_open (l : Layout) (pw ph e : Rat) : panelPos l pw ph true e true = (0, 0) := by
  simp [panelPos, progress]; grind

/-- The backdrop is clear before opening starts and opaque after it ends.
$$\operatorname{alpha}(\top, 0) = 0,\quad e \ge 400 \Rightarrow \operatorname{alpha}(\top, e) = 1$$ -/
theorem alpha_open_ends (e : Rat) (he : 400 ≤ e) :
    backdropAlpha true 0 false = 0 ∧ backdropAlpha true e false = 1 := by
  have h1 : 1 ≤ e / transitionMs := by
    have : e / transitionMs = e * (1 / 400) := by unfold transitionMs; grind
    grind
  have z : (0 : Rat) / transitionMs = 0 := by unfold transitionMs; grind
  have h0 : progress 0 false = 0 := by simp [progress, z, ease_zero]
  have h : progress e false = 1 := by simp [progress, ease_ge_one _ _ h1]
  simp [backdropAlpha, h0, h]

/-- The opacity stays in $[0,1]$. $$\forall s, e, r:\ 0 \le \operatorname{alpha}(s, e, r) \le 1$$ -/
theorem alpha_mem (shown : Bool) (e : Rat) (r : Bool) : 0 ≤ backdropAlpha shown e r ∧ backdropAlpha shown e r ≤ 1 := by
  have hp : 0 ≤ progress e r ∧ progress e r ≤ 1 := by
    unfold progress
    split
    · grind
    · exact ease_mem _ _ (by decide) (by decide) (by decide) (by decide)
  unfold backdropAlpha
  split <;> grind

end Fw.Parts.OverlayDrawer
