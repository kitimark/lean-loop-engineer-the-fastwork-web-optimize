/-!
# morph.panel: the expanded end-of-page panel and what reads the morph value (port-morph-panel)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`
  * 12879: the panel markup (`.start-selling-morph-panel`: backdrop, veil, centre with title, countdown slot and
    call-to-action stack, footer); it is a child of the nav, which writes `--morph` on its own root (13243);
  * 12947 `E = morph > 0.001` (the scene flag), 13196 `data-start-selling-scene = E ? active : paused`;
  * 13197 `aria-hidden = morph < 0.35` on the panel; 13199 the call-to-action `tabindex = -1` iff `morph < 0.55`;
  * 12683-12687 `KM = 0.55`, `qM = 0.92` (`is-expanded` iff `morph > qM`), `JM` = clamp to $[0,1]$.
* `assets/2.gBuqKVzi.css`: the panel root reads the morph value in `calc()`
  (`opacity: clamp(0, (m - .08)/.72, 1)`, `filter: blur((1 - that) * 12px)`, `transform: scale(.96 + .04 m)`;
  `pointer-events: auto` while the nav is expanded).

The CSS does the arithmetic in the browser; this module is the spec of the same readings and of the three
attribute flags the part writes (the only decisions in the part). All values `Rat`, no `Float`.
-/
namespace Fw.Parts.MorphPanel

/-! ## The morph value and the panel's readings -/

/-- Clamp to the unit interval (`JM`, JS 12685).

$$\operatorname{clamp01}(x) = \max(0, \min(1, x))$$

Keeps the morph value between closed (0) and open (1). -/
def clamp01 (x : Rat) : Rat := max 0 (min 1 x)

/-- The panel's own progress: starts at $m = 0.08$ and ends at $m = 0.8$.

$$\operatorname{panelProgress}(m) = \operatorname{clamp01}\!\Big(\frac{m - 0.08}{0.72}\Big)$$

How far the panel has appeared (CSS `clamp(0, (var(--morph) - .08) / .72, 1)`). -/
def panelProgress (m : Rat) : Rat := clamp01 ((m - 2 / 25) / (18 / 25))

/-- Panel opacity.

$$\mathrm{opacity}(m) = \operatorname{panelProgress}(m)$$

The panel fades in with its progress. -/
def panelOpacity (m : Rat) : Rat := panelProgress m

/-- Panel blur in px.

$$\mathrm{blur}(m) = 12\,(1 - \operatorname{panelProgress}(m))$$

It sharpens as it appears. -/
def panelBlurPx (m : Rat) : Rat := (1 - panelProgress m) * 12

/-- Panel scale.

$$\mathrm{scale}(m) = 0.96 + 0.04\,m$$

It grows slightly while opening. -/
def panelScale (m : Rat) : Rat := 24 / 25 + m / 25

#guard panelProgress 0 == 0
#guard panelProgress (2 / 25) == 0
#guard panelProgress (4 / 5) == 1
#guard panelProgress 1 == 1
#guard panelProgress (11 / 25) == 1 / 2
#guard panelBlurPx 0 == 12
#guard panelScale 1 == 1

/-- The progress lies in the unit interval.

$$\forall m \in \mathbb{Q}:\quad 0 \le \operatorname{panelProgress}(m) \le 1$$

Opacity and blur never leave their range for any morph value. -/
theorem panelProgress_mem (m : Rat) : 0 ≤ panelProgress m ∧ panelProgress m ≤ 1 := by
  unfold panelProgress clamp01
  constructor <;> grind

/-- Nothing shows before $m = 0.08$.

$$m \le 0.08 \;\Rightarrow\; \operatorname{panelProgress}(m) = 0$$

The closed pill state (m = 0) has an invisible panel. -/
theorem panelProgress_zero (m : Rat) (h : m ≤ 2 / 25) : panelProgress m = 0 := by
  unfold panelProgress clamp01
  have : (m - 2 / 25) / (18 / 25) ≤ 0 := by
    have : (m - 2 / 25) / (18 / 25) = (m - 2 / 25) * (25 / 18) := by grind
    rw [this]; grind
  grind

/-- The panel is fully shown from $m = 0.8$.

$$m \ge 0.8 \;\Rightarrow\; \operatorname{panelProgress}(m) = 1$$

Past four fifths of the morph the panel is opaque and sharp. -/
theorem panelProgress_one (m : Rat) (h : 4 / 5 ≤ m) : panelProgress m = 1 := by
  unfold panelProgress clamp01
  have : 1 ≤ (m - 2 / 25) / (18 / 25) := by
    have : (m - 2 / 25) / (18 / 25) = (m - 2 / 25) * (25 / 18) := by grind
    rw [this]; grind
  grind

/-- The progress never goes down as the morph grows.

$$m_1 \le m_2 \;\Rightarrow\; \operatorname{panelProgress}(m_1) \le \operatorname{panelProgress}(m_2)$$

Opening the menu further never hides more of the panel. -/
theorem panelProgress_mono (a b : Rat) (h : a ≤ b) : panelProgress a ≤ panelProgress b := by
  unfold panelProgress clamp01
  have : (a - 2 / 25) / (18 / 25) ≤ (b - 2 / 25) / (18 / 25) := by
    have e1 : (a - 2 / 25) / (18 / 25) = (a - 2 / 25) * (25 / 18) := by grind
    have e2 : (b - 2 / 25) / (18 / 25) = (b - 2 / 25) * (25 / 18) := by grind
    rw [e1, e2]; grind
  grind

/-- Blur and opacity move together: blur is zero exactly when the panel is fully shown.

$$\operatorname{blur}(m) = 12\,(1 - \operatorname{opacity}(m)),\qquad 0 \le \operatorname{blur}(m) \le 12$$

The sharp panel is the opaque one. -/
theorem panelBlur_eq (m : Rat) :
    panelBlurPx m = 12 * (1 - panelOpacity m) ∧ 0 ≤ panelBlurPx m ∧ panelBlurPx m ≤ 12 := by
  have := panelProgress_mem m
  unfold panelBlurPx panelOpacity
  refine ⟨by grind, by grind, by grind⟩

/-! ## The three flags -/

/-- The scene flag (`E`, JS 12947).

$$\mathit{scene}(m) \iff m > 0.001$$

Whether the morph has started. -/
def sceneActive (m : Rat) : Bool := decide (1 / 1000 < m)

/-- The panel is hidden from assistive tech (JS 13197).

$$\mathit{hidden}(m) \iff m < 0.35$$

Below 0.35 nobody is told about the panel. -/
def ariaHidden (m : Rat) : Bool := decide (m < 7 / 20)

/-- The call-to-action leaves the tab order (JS 13199).

$$\mathit{tabOff}(m) \iff m < 0.55$$

Below 0.55 the button cannot be tabbed to. -/
def ctaTabOff (m : Rat) : Bool := decide (m < 11 / 20)

/-- The nav counts as expanded (`qM`, JS 12684).

$$\mathit{exp}(m) \iff m > 0.92$$

The panel then takes pointer events. -/
def expanded (m : Rat) : Bool := decide (23 / 25 < m)

#guard sceneActive 0 == false
#guard sceneActive (1 / 1000) == false
#guard sceneActive (1 / 999) == true
#guard ariaHidden (7 / 20) == false
#guard ariaHidden (69 / 200) == true
#guard ctaTabOff (11 / 20) == false
#guard expanded (23 / 25) == false
#guard expanded (24 / 25) == true

/-- The closed state: nothing visible, hidden, out of the tab order, scene paused.

$$m = 0 \;\Rightarrow\; \mathrm{opacity} = 0,\ \mathrm{blur} = 12,\ \mathrm{scale} = 0.96,\ \mathit{hidden},\ \mathit{tabOff},\ \lnot\mathit{scene},\ \lnot\mathit{exp}$$

What the server-rendered panel shows before anything morphs. -/
theorem closed_state :
    panelOpacity 0 = 0 ∧ panelBlurPx 0 = 12 ∧ panelScale 0 = 24 / 25 ∧
      ariaHidden 0 = true ∧ ctaTabOff 0 = true ∧ sceneActive 0 = false ∧ expanded 0 = false := by
  decide +kernel

/-- Hidden implies the call-to-action is out of the tab order.

$$m < 0.35 \;\Rightarrow\; m < 0.55,\ \text{i.e. } \mathit{hidden}(m) \Rightarrow \mathit{tabOff}(m)$$

A control that assistive tech cannot see cannot be tabbed to. -/
theorem hidden_tabOff (m : Rat) (h : ariaHidden m = true) : ctaTabOff m = true := by
  unfold ariaHidden ctaTabOff at *
  simp only [decide_eq_true_eq] at *
  grind

/-- An expanded panel is reachable by assistive tech and the tab order.

$$m > 0.92 \;\Rightarrow\; \lnot\mathit{hidden}(m) \wedge \lnot\mathit{tabOff}(m) \wedge \mathit{scene}(m)$$

Once the nav is expanded the panel is interactive. -/
theorem expanded_reachable (m : Rat) (h : expanded m = true) :
    ariaHidden m = false ∧ ctaTabOff m = false ∧ sceneActive m = true := by
  unfold expanded ariaHidden ctaTabOff sceneActive at *
  simp only [decide_eq_true_eq, decide_eq_false_iff_not] at *
  refine ⟨by grind, by grind, by grind⟩

/-- A hidden panel is mostly transparent.

$$m < 0.35 \;\Rightarrow\; \operatorname{opacity}(m) \le \tfrac{3}{8}$$

Between 0.08 and 0.35 the panel is already fading in, but it is announced to nobody yet. -/
theorem hidden_dim (m : Rat) (h : ariaHidden m = true) : panelOpacity m ≤ 3 / 8 := by
  unfold ariaHidden at h
  simp only [decide_eq_true_eq] at h
  unfold panelOpacity panelProgress clamp01
  have : (m - 2 / 25) / (18 / 25) ≤ 3 / 8 := by
    have e : (m - 2 / 25) / (18 / 25) = (m - 2 / 25) * (25 / 18) := by grind
    rw [e]; grind
  grind

end Fw.Parts.MorphPanel
