import Fw.Parts.MorphTween
import Fw.Parts.HeroExit
/-!
# nav: the floating pill, its state classes and its geometry (M2 port, `faithful`)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`
  * 12683-12684: constants $0.55$ and $0.92$ (`KM`, `qM`); 12685: the clamp;
  * 12897-12906: the nav component state: `p` past the hero, `h` chrome ready, `g` over a dark section, `v` profile
    sticky, `y` locale menu open, `x` morph; derived `E = x > 0.001` (morphing), `O = !p && !E` (hero pill),
    `A = O || x > 0.55`;
  * 12921-12935 (`ee`): the profile-sticky test (sticky position, top within 1 px of its `top`, section bottom more
    than 1 px below the item bottom);
  * 12996-13007: chrome ready at once under reduced motion or `max-width: 600px`, else after 1140 ms, or earlier when
    one of those queries changes to true or the hero carries `is-ring-splash-done` (`m`); 13008-13018 (`_`): past the
    hero iff there is no `.hero-track`, or reduced motion, or
    $\min(r, \max(0, -\mathit{top}))/r \ge 0.72$ with $r = \max(1, h - \mathit{innerHeight})$;
  * 13224-13231: the classes `is-hero-pill is-hero-chrome-ready is-morphing is-expanded(x>0.92) is-on-dark(g || x>0.2)
    is-locale-open is-scroll-hidden(v && !E) is-profile-sticky-hidden(v && !E)`; 13243-13245: earn button
    `tabindex -1` iff $x > 0.4 \lor O$, `aria-hidden` iff $A$.
* `assets/2.gBuqKVzi.css` 11320-11640 (nav, bar, logo, actions, earn button, phone band `width<=640px`): the widths,
  height, top, radius, blur and the earn button's collapse as functions of `--morph` and `--nav-expand`; the
  transitions. (The earlier `.start-selling-top-nav, .start-selling-morph` override of `--panel-w/h` at 11075 has lower
  specificity than the scoped rule and never applies to the nav.)

All values `Rat` (CSS px and scroll offsets can be fractional). No `Float`.
-/
namespace Fw.Parts.Nav
open Fw.Parts.MorphTween Fw.Parts.HeroExit

/-! ## Constants -/

/-- The nav counts as morphing above this morph value (JS 12899). $$\varepsilon = 0.001 = \tfrac{1}{1000}$$ The cut. -/
def morphingCut : Rat := 1 / 1000

/-- The nav counts as expanded above this value (JS 12684). $$q = 0.92 = \tfrac{23}{25}$$ The cut. -/
def expandedCut : Rat := 23 / 25

/-- The nav is forced to the dark look above this value; the earn button has collapsed by it (JS 13228, CSS 11477).
$$d = 0.2 = \tfrac{1}{5}$$ The cut and the span of the earn collapse. -/
def darkCut : Rat := 1 / 5

/-- Share of the hero track after which the pill leaves the hero state (JS 13016). $$\pi = 0.72 = \tfrac{18}{25}$$ The cut. -/
def pastCut : Rat := 18 / 25

/-- Earn button leaves the tab order above this value (JS 13244). $$\tau = 0.4 = \tfrac{2}{5}$$ The cut. -/
def earnTabCut : Rat := 2 / 5

/-- Earn button is `aria-hidden` above this value (JS 12903). $$\alpha = 0.55 = \tfrac{11}{20}$$ The cut. -/
def earnAriaCut : Rat := 11 / 20

/-- Delay in ms after which the chrome fades in when no query allows it earlier (JS 13003). $$T = 1140$$ The delay. -/
def readyDelay : Nat := 1140

/-- Narrow-viewport query of the chrome-ready rule (JS 12997). $$\text{max-width: } 600\ \mathrm{px}$$ The edge. -/
def readyPhoneMax : Rat := 600

/-- The phone band of the nav CSS (CSS 11563). $$w \le 640$$ Whether the phone rules apply. -/
def phone (w : Rat) : Bool := decide (w ≤ 640)

/-! ## Decisions -/

/-- Progress through the hero track (JS 13013-13015).

$$p(t, h, v) = \frac{\min(r, \max(0, -t))}{r},\quad r = \max(1, h - v)$$

How far the track has scrolled past the top. -/
def progress (top height vh : Rat) : Rat :=
  let r := max 1 (height - vh)
  min r (max 0 (-top)) / r

/-- Past the hero (JS 13008-13018, the state `p`).

$$\operatorname{past}(\mathit{present}, \mathit{rm}, t, h, v) = \lnot\mathit{present} \lor \mathit{rm} \lor p(t, h, v) \ge \tfrac{18}{25}$$

True when there is no hero track, under reduced motion, or after 72 % of the track. -/
def pastHero (present reduced : Bool) (top height vh : Rat) : Bool :=
  !present || reduced || decide (pastCut ≤ progress top height vh)

/-- Measurements of the profile sticky item (JS 12921-12935); `top` is the parsed CSS `top`, `none` when not a finite number. -/
structure Sticky where
  present : Bool
  isSticky : Bool
  hasSection : Bool
  top : Option Rat
  itemTop : Rat
  itemBottom : Rat
  sectionBottom : Rat
deriving Repr, BEq

/-- The profile sticky item is stuck (JS 12921-12935, state `v`).

$$\operatorname{stuck}(s) = \mathit{present} \land \mathit{sticky} \land \mathit{sec} \land (\exists r.\ \mathit{top} = r \land \mathit{it}_t \le r + 1) \land \mathit{sec}_b > \mathit{it}_b + 1$$

When true (and the nav is not morphing) the pill slides away. -/
def stuck (s : Sticky) : Bool :=
  s.present && s.isSticky && s.hasSection &&
    (match s.top with | some r => decide (s.itemTop ≤ r + 1) | none => false) &&
    decide (s.itemBottom + 1 < s.sectionBottom)

/-- The classes on the header. $$c = (\mathit{pill}, \mathit{ready}, \mathit{morphing}, \mathit{expanded}, \mathit{dark}, \mathit{locale}, \mathit{hidden}) \in \{\top,\bot\}^7$$ What the nav carries. -/
structure View where
  heroPill : Bool
  ready : Bool
  morphing : Bool
  expanded : Bool
  onDark : Bool
  localeOpen : Bool
  scrollHidden : Bool
deriving Repr, BEq, DecidableEq

/-- The class set (JS 12897-12906, 13224-13231).

$$\begin{aligned}
\mathit{morphing} &= m > 0.001, & \mathit{pill} &= \lnot\mathit{past} \land \lnot\mathit{morphing}, & \mathit{expanded} &= m > 0.92,\\
\mathit{dark} &= \mathit{hit} \lor m > 0.2, & \mathit{hidden} &= \mathit{stuck} \land \lnot\mathit{morphing}
\end{aligned}$$

Everything the header's `class` is, from the six inputs and the morph. -/
def view (past ready localeOpen hit stuck : Bool) (m : Rat) : View :=
  let morphing := decide (morphingCut < m)
  { heroPill := !past && !morphing, ready, morphing, expanded := decide (expandedCut < m),
    onDark := hit || decide (darkCut < m), localeOpen, scrollHidden := stuck && !morphing }

/-- Earn button attributes. $$(\mathit{tabindex}{=}{-}1,\ \mathit{aria\text{-}hidden})$$ Whether the button is out of the tab order, and hidden. -/
structure Earn where
  tabOff : Bool
  ariaHidden : Bool
deriving Repr, BEq, DecidableEq

/-- Earn button attributes (JS 13243-13245).

$$\mathit{tabOff} = m > 0.4 \lor \mathit{pill},\qquad \mathit{ariaHidden} = \mathit{pill} \lor m > 0.55$$

A collapsed or pill-state button is not focusable. -/
def earn (heroPill : Bool) (m : Rat) : Earn :=
  { tabOff := decide (earnTabCut < m) || heroPill, ariaHidden := heroPill || decide (earnAriaCut < m) }

/-- Chrome ready at mount (JS 13005): at once under reduced motion or on a narrow viewport, else after 1140 ms.

$$\mathit{ready}_0 = \mathit{rm} \lor w \le 600$$ -/
def readyInit (reduced phoneQuery : Bool) : Bool := reduced || phoneQuery

/-- Chrome ready after a query change or a splash-done check (JS 12998-13004 `m`).

$$\mathit{ready}' = \mathit{ready} \lor \mathit{rm} \lor \mathit{narrow} \lor \mathit{splash}$$

It never goes back to false. -/
def readyChange (ready reduced phoneQuery splash : Bool) : Bool := ready || reduced || phoneQuery || splash

/-- Ready once the timer has run (JS 13003). $$\mathit{ready}(t) = [t \ge 1140]$$ -/
def readyAt (t : Nat) : Bool := decide (readyDelay ≤ t)

#guard pastHero false false 0 0 0 == true
#guard pastHero true true 0 2000 800 == true
#guard pastHero true false (-864) 2000 800 == true
#guard pastHero true false (-863) 2000 800 == false
#guard pastHero true false 10 2000 800 == false
#guard (view false false false false false 0).heroPill == true
#guard (view false false false false false (1/1000)).heroPill == true
#guard (view false false false false false (11/10000)).heroPill == false
#guard stuck ⟨true, true, true, some 80, 81, 400, 900⟩ == true
#guard stuck ⟨true, true, true, some 80, 82, 400, 900⟩ == false
#guard stuck ⟨true, true, true, none, 0, 400, 900⟩ == false
#guard readyAt 1139 == false && readyAt 1140 == true

/-! ## Decision theorems -/

/-- The hero pill and morphing are exclusive.

$$\forall \ldots:\quad \mathit{pill}(v) = \top \Rightarrow \mathit{morphing}(v) = \bot$$

While the morph runs the pill state is off, so the width does not collapse back to the hero pill. -/
theorem heroPill_not_morphing (a b c d e : Bool) (m : Rat) :
    (view a b c d e m).heroPill = true → (view a b c d e m).morphing = false := by
  unfold view; cases a <;> cases (decide (morphingCut < m)) <;> simp

/-- Expanded implies the dark look.

$$m > 0.92 \Rightarrow \mathit{dark}$$

The classifier is moot at the end of the morph: the dark look is forced. -/
theorem expanded_onDark (a b c d e : Bool) (m : Rat) :
    (view a b c d e m).expanded = true → (view a b c d e m).onDark = true := by
  unfold view darkCut expandedCut
  intro h
  have h' : (23 / 25 : Rat) < m := by simpa using h
  have : (1 / 5 : Rat) < m := by grind
  simp [this]

/-- A morphing nav never slides away.

$$\mathit{morphing} \Rightarrow \lnot\mathit{hidden}$$

The profile sticky cannot hide the pill during the morph. -/
theorem morphing_not_hidden (a b c d e : Bool) (m : Rat) :
    (view a b c d e m).morphing = true → (view a b c d e m).scrollHidden = false := by
  unfold view; cases (decide (morphingCut < m)) <;> simp

/-- Pill and expanded never hold together.

$$\lnot(\mathit{pill} \land \mathit{expanded})$$

An expanded panel is never the hero pill. -/
theorem heroPill_not_expanded (a b c d e : Bool) (m : Rat) :
    ¬((view a b c d e m).heroPill = true ∧ (view a b c d e m).expanded = true) := by
  intro ⟨h1, h2⟩
  have hm := heroPill_not_morphing a b c d e m h1
  unfold view morphingCut expandedCut at *
  simp at hm h2
  grind

/-- The earn button is out of the tab order whenever it is aria-hidden by the pill.

$$\mathit{pill} \Rightarrow \mathit{tabOff}$$

A hidden-by-state button cannot be focused. -/
theorem earn_pill_tabOff (m : Rat) : (earn true m).tabOff = true := by simp [earn]

/-- Ready never goes back.

$$\mathit{ready} = \top \Rightarrow \mathit{ready}' = \top$$

Once the chrome has faded in it stays. -/
theorem readyChange_mono (r a b c : Bool) (h : r = true) : readyChange r a b c = true := by
  simp [readyChange, h]

/-- The timer is the only path to ready on a wide, motion-allowing page without a splash flag.

$$\lnot\mathit{rm} \land \lnot\mathit{narrow} \land \lnot\mathit{splash} \Rightarrow \mathit{ready}' = \mathit{ready}$$ -/
theorem readyChange_idle (r : Bool) : readyChange r false false false = r := by simp [readyChange]

/-- Past the hero without a track: the nav is never the hero pill.

$$\lnot\mathit{present} \Rightarrow \mathit{past}$$ -/
theorem pastHero_absent (rm : Bool) (t h v : Rat) : pastHero false rm t h v = true := by simp [pastHero]

/-- Progress lies in the unit interval.

$$\forall t, h, v:\quad 0 \le p(t, h, v) \le 1$$

The track fraction is a fraction. -/
theorem progress_mem (t h v : Rat) : 0 ≤ progress t h v ∧ progress t h v ≤ 1 := by
  unfold progress
  simp only []
  have hr : (0 : Rat) < max 1 (h - v) := by grind
  generalize max 1 (h - v) = r at *
  have h0 : 0 ≤ min r (max 0 (-t)) := by grind
  have h1 : min r (max 0 (-t)) ≤ r := by grind
  exact div_unit _ _ hr h0 h1

/-! ## Geometry as a function of `--morph` -/

/-- A viewport. $$(w, h) \in \mathbb{Q}^2$$ Its width and height in px (`100vw`, `100vh`). -/
structure Vp where
  w : Rat
  h : Rat

/-- `--pill-w` and `--hero-pill-w` (CSS 11323-11324, 11566-11567).

$$\operatorname{pillW} = \min(984,\ w - 48)\ \ (w > 640),\qquad \min(984,\ w - 32)\ \ (w \le 640)$$ -/
def pillW (v : Vp) : Rat := min 984 (v.w - if phone v.w then 32 else 48)

/-- `--pill-h` (CSS 11325, 11568). $$\operatorname{pillH} = 64\ (w > 640),\quad 52\ (w \le 640)$$ -/
def pillH (v : Vp) : Rat := if phone v.w then 52 else 64

/-- `--panel-w` (CSS 11326, 11569).

$$\operatorname{panelW} = \min(1398,\ w - 40)\ \ (w > 640),\qquad w - 24\ \ (w \le 640)$$ -/
def panelW (v : Vp) : Rat := if phone v.w then v.w - 24 else min 1398 (v.w - 40)

/-- `--panel-h` (CSS 11327, 11570).

$$\operatorname{panelH} = \min(820,\ h - 40)\ \ (w > 640),\qquad h - 24\ \ (w \le 640)$$ -/
def panelH (v : Vp) : Rat := if phone v.w then v.h - 24 else min 820 (v.h - 40)

/-- `--nav-expand`: 0 while the hero pill, else 1 (CSS 11322, 11366-11368). $$e = [\lnot\mathit{pill}]$$ -/
def expand (heroPill : Bool) : Rat := if heroPill then 0 else 1

/-- Nav width (CSS 11331-11334).

$$W(m) = W_h + (W_p - W_h)\,e + (W_P - W_p)\,m$$

with $W_h = W_p = \operatorname{pillW}$ (the two variables carry the same expression), so the expand factor drops out. -/
def navWidth (v : Vp) (heroPill : Bool) (m : Rat) : Rat :=
  pillW v + (pillW v - pillW v) * expand heroPill + (panelW v - pillW v) * m

/-- Nav height (CSS 11335). $$H(m) = H_p + (H_P - H_p)\,m$$ -/
def navHeight (v : Vp) (m : Rat) : Rat := pillH v + (panelH v - pillH v) * m

/-- Nav top (CSS 11329, 11571). $$T(m) = 16 + (20 - 16)\,m\ \ (w > 640),\qquad 16 + (12 - 16)\,m\ \ (w \le 640)$$ -/
def navTop (v : Vp) (m : Rat) : Rat := 16 + ((if phone v.w then 12 else 20) - 16) * m

/-- Nav corner radius (CSS 11340). $$R(m) = 32 - 12\,m$$ -/
def navRadius (m : Rat) : Rat := 32 - 12 * m

/-- Nav backdrop blur in px (CSS 11342). $$B(m) = 20\,(1 - m)$$ -/
def navBlur (m : Rat) : Rat := 20 * (1 - m)

/-- Weight of the glass fill in the background mix, in percent (CSS 11336-11339). $$\omega(m) = 100\,(1 - m)$$ (the dark fill takes $100\,m$). -/
def glassWeight (m : Rat) : Rat := 100 * (1 - m)

/-- The earn button's collapse (CSS 11478): $$o(m) = \operatorname{clamp}(m / 0.2)$$ 0 at rest, 1 once the morph is a fifth done. -/
def earnOut (m : Rat) : Rat := clamp01 (m / darkCut)

/-- `--earn-layout` (CSS 11480). $$\lambda = e\,(1 - o(m))$$ The share of the button's width that is kept. -/
def earnLayout (heroPill : Bool) (m : Rat) : Rat := expand heroPill * (1 - earnOut m)

/-- Earn button max-width in px (CSS 11483, 11594-11596). $$\lambda \cdot 176\ (w > 640),\qquad \lambda \cdot 152\ (w \le 640)$$ (11 rem and 9.5 rem at 16 px). -/
def earnMaxW (v : Vp) (heroPill : Bool) (m : Rat) : Rat := earnLayout heroPill m * (if phone v.w then 152 else 176)

/-- Earn button inline padding in px (CSS 11484, 11594-11596). $$\lambda \cdot 24\ (w > 640),\qquad \lambda \cdot 16\ (w \le 640)$$ -/
def earnPad (v : Vp) (heroPill : Bool) (m : Rat) : Rat := earnLayout heroPill m * (if phone v.w then 16 else 24)

/-- Earn button opacity (CSS 11485). $$(1 - o(m))\,e$$ -/
def earnOpacity (heroPill : Bool) (m : Rat) : Rat := (1 - earnOut m) * expand heroPill

/-- Earn button blur in px (CSS 11486). $$10\,o(m)$$ -/
def earnBlur (m : Rat) : Rat := earnOut m * 10

/-- Earn button vertical shift in px (CSS 11488). $$-8\,o(m)$$ -/
def earnShift (m : Rat) : Rat := earnOut m * -8

/-- Gap between the language switch and the button in px (CSS 11440, 11584-11586).

$$g = e\,(1 - \operatorname{clamp}(m / 0.2)) \cdot 8\ (w > 640),\qquad \cdot 4\ (w \le 640)$$ -/
def actionsGap (v : Vp) (heroPill : Bool) (m : Rat) : Rat :=
  expand heroPill * (1 - earnOut m) * (if phone v.w then 4 else 8)

/-- Logo left in px, while morphing (CSS 11432-11436, bar inset 24, phone 16).

$$\ell(m) = x + (\tfrac{W}{2} - x)\,m$$ with $x$ the bar inset and $W$ the bar width (the pill width at rest). -/
def logoLeft (inset barW m : Rat) : Rat := inset + (barW / 2 - inset) * m

#guard navWidth ⟨1280, 800⟩ true 0 == 984
#guard navWidth ⟨1280, 800⟩ true 1 == 1240
#guard navWidth ⟨1920, 1080⟩ false 1 == 1398
#guard navWidth ⟨390, 844⟩ false 0 == 358
#guard navWidth ⟨390, 844⟩ false 1 == 366
#guard navHeight ⟨1280, 800⟩ 0 == 64
#guard navHeight ⟨1280, 800⟩ 1 == 760
#guard navHeight ⟨390, 844⟩ 0 == 52
#guard navTop ⟨1280, 800⟩ 1 == 20
#guard navTop ⟨390, 844⟩ 1 == 12
#guard earnMaxW ⟨1280, 800⟩ false 0 == 176
#guard earnMaxW ⟨1280, 800⟩ false (1/10) == 88
#guard earnMaxW ⟨1280, 800⟩ true 0 == 0

/-- The unit-interval output of the earn collapse. $$0 \le o(m) \le 1$$ -/
theorem earnOut_mem (m : Rat) : 0 ≤ earnOut m ∧ earnOut m ≤ 1 := clamp01_mem _

/-- The earn button is gone by a fifth of the morph.

$$m \ge \tfrac15 \Rightarrow o(m) = 1,\ \lambda = 0,\ \text{opacity} = 0,\ \text{gap} = 0$$

Before the dark look is forced the button has collapsed, so no two steps overlap. -/
theorem earn_gone (v : Vp) (hp : Bool) (m : Rat) (h : darkCut ≤ m) :
    earnOut m = 1 ∧ earnLayout hp m = 0 ∧ earnOpacity hp m = 0 ∧ actionsGap v hp m = 0 := by
  have h1 : earnOut m = 1 := by
    unfold earnOut clamp01 darkCut at *
    have : m / (1 / 5 : Rat) = m * 5 := by rw [Rat.div_def]; grind
    grind
  refine ⟨h1, ?_, ?_, ?_⟩ <;> simp [earnLayout, earnOpacity, actionsGap, h1] <;> grind

/-- At rest the button is fully kept (outside the hero pill).

$$o(0) = 0,\quad \lambda = 1,\quad \text{opacity} = 1$$ -/
theorem earn_rest : earnOut 0 = 0 ∧ earnLayout false 0 = 1 ∧ earnOpacity false 0 = 1 := by
  refine ⟨by decide +kernel, by decide +kernel, by decide +kernel⟩

/-- The nav starts at the pill box.

$$H(0) = H_p,\quad W(0) = W_p,\quad T(0) = 16$$ -/
theorem rest_box (v : Vp) (hp : Bool) : navHeight v 0 = pillH v ∧ navWidth v hp 0 = pillW v ∧ navTop v 0 = 16 := by
  unfold navHeight navWidth navTop; refine ⟨by grind, by grind, by grind⟩

/-- The nav ends at the panel box.

$$H(1) = H_P,\quad W(1) = W_P,\quad R(1) = 20$$ -/
theorem end_box (v : Vp) (hp : Bool) : navHeight v 1 = panelH v ∧ navWidth v hp 1 = panelW v ∧ navRadius 1 = 20 := by
  unfold navHeight navWidth navRadius; refine ⟨by grind, by grind, by grind⟩

/-- The expand factor does not move the width.

$$W(m)\text{ is the same for pill and non-pill}$$

The two variables `--hero-pill-w` and `--pill-w` carry the same expression. -/
theorem navWidth_expand_irrel (v : Vp) (m : Rat) : navWidth v true m = navWidth v false m := by
  unfold navWidth; grind

/-- The panel is at least as wide as the pill.

$$W_P \ge W_p$$

So the width grows with the morph. -/
theorem panel_ge_pill (v : Vp) : pillW v ≤ panelW v := by
  unfold pillW panelW
  cases hph : phone v.w <;> simp <;> grind

/-- The width is monotone in the morph.

$$m \le m' \Rightarrow W(m) \le W(m')$$

The pill only widens. -/
theorem navWidth_mono (v : Vp) (hp : Bool) (m m' : Rat) (h : m ≤ m') : navWidth v hp m ≤ navWidth v hp m' := by
  have := panel_ge_pill v
  unfold navWidth
  have h2 : (panelW v - pillW v) * m ≤ (panelW v - pillW v) * m' :=
    Rat.mul_le_mul_of_nonneg_left h (by grind)
  grind

/-- The radius shrinks by 12 px over the morph and stays between 20 and 32 on the unit interval.

$$0 \le m \le 1 \Rightarrow 20 \le R(m) \le 32$$ -/
theorem navRadius_mem (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) : 20 ≤ navRadius m ∧ navRadius m ≤ 32 := by
  unfold navRadius; grind

/-- The blur and the glass weight reach 0 at the end.

$$B(1) = 0,\quad \omega(1) = 0,\quad B(0) = 20,\quad \omega(0) = 100$$ -/
theorem glass_ends : navBlur 1 = 0 ∧ glassWeight 1 = 0 ∧ navBlur 0 = 20 ∧ glassWeight 0 = 100 := by
  unfold navBlur glassWeight; refine ⟨by grind, by grind, by grind, by grind⟩

/-! ## Timing and curves of the transitions (the "original" an optimised version is compared with) -/

/-- A CSS cubic-bezier timing function. $$(x_1, y_1, x_2, y_2)$$ Control points of the curve from $(0,0)$ to $(1,1)$. -/
structure Bezier where
  x1 : Rat
  y1 : Rat
  x2 : Rat
  y2 : Rat

/-- The curve's $x$ at parameter $s$.

$$X(s) = 3(1-s)^2 s\,x_1 + 3(1-s)s^2\,x_2 + s^3$$ -/
def Bezier.x (b : Bezier) (s : Rat) : Rat := 3 * (1 - s) * (1 - s) * s * b.x1 + 3 * (1 - s) * s * s * b.x2 + s * s * s

/-- The curve's $y$ at parameter $s$.

$$Y(s) = 3(1-s)^2 s\,y_1 + 3(1-s)s^2\,y_2 + s^3$$ -/
def Bezier.y (b : Bezier) (s : Rat) : Rat := 3 * (1 - s) * (1 - s) * s * b.y1 + 3 * (1 - s) * s * s * b.y2 + s * s * s

/-- The curve starts at the origin and ends at (1, 1).

$$(X(0), Y(0)) = (0, 0),\quad (X(1), Y(1)) = (1, 1)$$

So an eased transition begins at its start value and ends at its end value. -/
theorem Bezier.ends (b : Bezier) : b.x 0 = 0 ∧ b.y 0 = 0 ∧ b.x 1 = 1 ∧ b.y 1 = 1 := by
  unfold Bezier.x Bezier.y; refine ⟨by grind, by grind, by grind, by grind⟩

/-- `cubic-bezier(0.33, 0, 0.2, 1)`: width, background, gap, earn collapse, unmask and sheen (CSS 11353, 11358, 11441, 11487). -/
def easeSettle : Bezier := ⟨33 / 100, 0, 1 / 5, 1⟩

/-- `cubic-bezier(0.16, 1, 0.3, 1)`: opacity and transform of the nav (CSS 11349-11351, 11401). -/
def easeOut : Bezier := ⟨4 / 25, 1, 3 / 10, 1⟩

/-- `cubic-bezier(0.4, 0, 0.2, 1)`: logo colour and language switch (CSS 11425, 11129). -/
def easeStd : Bezier := ⟨2 / 5, 0, 1 / 5, 1⟩

/-- Width transition in ms (CSS 11358). $$680$$ How long the pill takes to change width. -/
def widthMs : Nat := 680

/-- Background transition in ms (CSS 11358). $$700$$ -/
def backgroundMs : Nat := 700

/-- Chrome fade-in in ms (CSS 11397-11403). $$700$$ -/
def chromeFadeMs : Nat := 700

/-- Transform (slide away) transition in ms (CSS 11351). $$320$$ -/
def slideMs : Nat := 320

/-- Opacity transition in ms (CSS 11350). $$280$$ -/
def fadeMs : Nat := 280

/-- Earn unmask and sheen: $$980$$ ms after a delay of $520$ ms (CSS 11535, 11543). -/
def earnUnmaskMs : Nat := 980

/-- Delay of the earn unmask in ms. $$520$$ -/
def earnUnmaskDelayMs : Nat := 520

/-- Nav slide-away offset in px (CSS 11382). $$y = -(h + 24)$$ Fully above the viewport edge. -/
def slideOffset (navH : Rat) : Rat := -(navH + 24)

/-- The earn sheen travels from $-130\,\%$ to $130\,\%$ of the button width (CSS 11522, 11556-11559).

$$\operatorname{sheen}(e) = -130 + 260\,e,\quad e \in [0,1]$$ in percent, $e$ the eased progress. -/
def sheenX (e : Rat) : Rat := -130 + 260 * e

/-- The unmask moves the mask from `100% 0` to `0 0` (CSS 11546-11555).

$$\operatorname{maskX}(e) = 100\,(1 - e)$$ in percent. -/
def maskX (e : Rat) : Rat := 100 * (1 - e)

/-- The sheen ends are $\mp 130$, the mask ends 100 and 0.

$$\operatorname{sheen}(0) = -130,\ \operatorname{sheen}(1) = 130,\ \operatorname{mask}(0) = 100,\ \operatorname{mask}(1) = 0$$ -/
theorem unmask_ends : sheenX 0 = -130 ∧ sheenX 1 = 130 ∧ maskX 0 = 100 ∧ maskX 1 = 0 := by
  unfold sheenX maskX; refine ⟨by grind, by grind, by grind, by grind⟩

end Fw.Parts.Nav
