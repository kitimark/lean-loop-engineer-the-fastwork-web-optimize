import Fw.Parts.MorphTween
import Fw.Parts.HeroExit
/-!
# nav: the floating pill, its state classes and its geometry (M2 port, `faithful`)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`
  * 12683-12684: constants `0.55` and `0.92` (`KM`, `qM`); 12685: the clamp;
  * 12897-12906: the nav component state: `p` past the hero, `h` chrome ready, `g` over a dark section, `v` profile
    sticky, `y` locale menu open, `x` morph; derived `E = x > 0.001` (morphing), `O = !p && !E` (hero pill),
    `A = O || x > 0.55`;
  * 12921-12935 (`ee`): the profile-sticky test (sticky position, top within 1 px of its `top`, section bottom more
    than 1 px below the item bottom);
  * 12996-13007: chrome ready at once under reduced motion or `max-width: 600px`, else after 1140 ms, or earlier when
    one of those queries changes to true or the hero carries `is-ring-splash-done` (`m`); 13008-13018 (`_`): past the
    hero iff there is no `.hero-track`, or reduced motion, or
    `min(r, max(0, -top))/r ≥ 0.72` with `r = max(1, h - innerHeight)`;
  * 13224-13231: the classes `is-hero-pill is-hero-chrome-ready is-morphing is-expanded(x>0.92) is-on-dark(g || x>0.2)
    is-locale-open is-scroll-hidden(v && !E) is-profile-sticky-hidden(v && !E)`; 13243-13245: earn button
    `tabindex -1` iff `x > 0.4 ∨ O`, `aria-hidden` iff `A`.
* `assets/2.gBuqKVzi.css` 11320-11640 (nav, bar, logo, actions, earn button, phone band `width<=640px`): the widths,
  height, top, radius, blur and the earn button's collapse as functions of `--morph` and `--nav-expand`; the
  transitions. (The earlier `.start-selling-top-nav, .start-selling-morph` override of `--panel-w/h` at 11075 has lower
  specificity than the scoped rule and never applies to the nav.)

All values `Rat` (CSS px and scroll offsets can be fractional). No `Float`.
-/
namespace Fw.Parts.Nav
open Fw.Parts.MorphTween Fw.Parts.HeroExit

/-! ## Constants -/

/-- The nav counts as morphing above this morph value (JS 12899). The cut. -/
def morphingCut : Rat := 1 / 1000

/-- The nav counts as expanded above this value (JS 12684). The cut. -/
def expandedCut : Rat := 23 / 25

/-- The nav is forced to the dark look above this value; the earn button has collapsed by it (JS 13228, CSS 11477).
The cut and the span of the earn collapse. -/
def darkCut : Rat := 1 / 5

/-- Share of the hero track after which the pill leaves the hero state (JS 13016). The cut. -/
def pastCut : Rat := 18 / 25

/-- Earn button leaves the tab order above this value (JS 13244). The cut. -/
def earnTabCut : Rat := 2 / 5

/-- Earn button is `aria-hidden` above this value (JS 12903). The cut. -/
def earnAriaCut : Rat := 11 / 20

/-- Delay in ms after which the chrome fades in when no query allows it earlier (JS 13003). The delay. -/
def readyDelay : Nat := 1140

/-- Narrow-viewport query of the chrome-ready rule (JS 12997). The edge. -/
def readyPhoneMax : Rat := 600

/-- The phone band of the nav CSS (CSS 11563). Whether the phone rules apply. -/
def phone (w : Rat) : Bool := decide (w ≤ 640)

/-! ## Decisions -/

/-- Progress through the hero track (JS 13013-13015).

How far the track has scrolled past the top. -/
def progress (top height vh : Rat) : Rat :=
  let r := max 1 (height - vh)
  min r (max 0 (-top)) / r

/-- Past the hero (JS 13008-13018, the state `p`).

True when there is no hero track, under reduced motion, or after 72 % of the track. -/
def pastHero (present reduced : Bool) (top height vh : Rat) : Bool :=
  !present || reduced || decide (pastCut ≤ progress top height vh)

/-- Measurements of the profile sticky item (JS 12921-12935); `top` is the parsed CSS `top`, `none` when not a finite number.
What the test reads. -/
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

When true (and the nav is not morphing) the pill slides away. -/
def stuck (s : Sticky) : Bool :=
  s.present && s.isSticky && s.hasSection &&
    (match s.top with | some r => decide (s.itemTop ≤ r + 1) | none => false) &&
    decide (s.itemBottom + 1 < s.sectionBottom)

/-- The classes on the header. What the nav carries. -/
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

Everything the header's `class` is, from the six inputs and the morph. -/
def view (past ready localeOpen hit stuck : Bool) (m : Rat) : View :=
  let morphing := decide (morphingCut < m)
  { heroPill := !past && !morphing, ready, morphing, expanded := decide (expandedCut < m),
    onDark := hit || decide (darkCut < m), localeOpen, scrollHidden := stuck && !morphing }

/-- Earn button attributes. Whether the button is out of the tab order, and hidden. -/
structure Earn where
  tabOff : Bool
  ariaHidden : Bool
deriving Repr, BEq, DecidableEq

/-- Earn button attributes (JS 13243-13245).

A collapsed or pill-state button is not focusable. -/
def earn (heroPill : Bool) (m : Rat) : Earn :=
  { tabOff := decide (earnTabCut < m) || heroPill, ariaHidden := heroPill || decide (earnAriaCut < m) }

/-- Chrome ready at mount (JS 13005): at once under reduced motion or on a narrow viewport, else after 1140 ms. -/
def readyInit (reduced phoneQuery : Bool) : Bool := reduced || phoneQuery

/-- Chrome ready after a query change or a splash-done check (JS 12998-13004 `m`).

It never goes back to false. -/
def readyChange (ready reduced phoneQuery splash : Bool) : Bool := ready || reduced || phoneQuery || splash

/-- Ready once the timer has run (JS 13003). -/
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

While the morph runs the pill state is off, so the width does not collapse back to the hero pill. -/
theorem heroPill_not_morphing (a b c d e : Bool) (m : Rat) :
    (view a b c d e m).heroPill = true → (view a b c d e m).morphing = false := by
  unfold view; cases a <;> cases (decide (morphingCut < m)) <;> simp

/-- Expanded implies the dark look.

The classifier is moot at the end of the morph: the dark look is forced. -/
theorem expanded_onDark (a b c d e : Bool) (m : Rat) :
    (view a b c d e m).expanded = true → (view a b c d e m).onDark = true := by
  unfold view darkCut expandedCut
  intro h
  have h' : (23 / 25 : Rat) < m := by simpa using h
  have : (1 / 5 : Rat) < m := by grind
  simp [this]

/-- A morphing nav never slides away.

The profile sticky cannot hide the pill during the morph. -/
theorem morphing_not_hidden (a b c d e : Bool) (m : Rat) :
    (view a b c d e m).morphing = true → (view a b c d e m).scrollHidden = false := by
  unfold view; cases (decide (morphingCut < m)) <;> simp

/-- Pill and expanded never hold together.

An expanded panel is never the hero pill. -/
theorem heroPill_not_expanded (a b c d e : Bool) (m : Rat) :
    ¬((view a b c d e m).heroPill = true ∧ (view a b c d e m).expanded = true) := by
  intro ⟨h1, h2⟩
  have hm := heroPill_not_morphing a b c d e m h1
  unfold view morphingCut expandedCut at *
  simp at hm h2
  grind

/-- The earn button is out of the tab order whenever it is aria-hidden by the pill.

A hidden-by-state button cannot be focused. -/
theorem earn_pill_tabOff (m : Rat) : (earn true m).tabOff = true := by simp [earn]

/-- Ready never goes back.

Once the chrome has faded in it stays. -/
theorem readyChange_mono (r a b c : Bool) (h : r = true) : readyChange r a b c = true := by
  simp [readyChange, h]

/-- The timer is the only path to ready on a wide, motion-allowing page without a splash flag. -/
theorem readyChange_idle (r : Bool) : readyChange r false false false = r := by simp [readyChange]

/-- Past the hero without a track: the nav is never the hero pill. -/
theorem pastHero_absent (rm : Bool) (t h v : Rat) : pastHero false rm t h v = true := by simp [pastHero]

/-- Progress lies in the unit interval.

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

/-- A viewport. Its width and height in px (`100vw`, `100vh`). -/
structure Vp where
  w : Rat
  h : Rat

/-- `--pill-w` and `--hero-pill-w` (CSS 11323-11324, 11566-11567). -/
def pillW (v : Vp) : Rat := min 984 (v.w - if phone v.w then 32 else 48)

/-- `--pill-h` (CSS 11325, 11568). -/
def pillH (v : Vp) : Rat := if phone v.w then 52 else 64

/-- `--panel-w` (CSS 11326, 11569). -/
def panelW (v : Vp) : Rat := if phone v.w then v.w - 24 else min 1398 (v.w - 40)

/-- `--panel-h` (CSS 11327, 11570). -/
def panelH (v : Vp) : Rat := if phone v.w then v.h - 24 else min 820 (v.h - 40)

/-- `--nav-expand`: 0 while the hero pill, else 1 (CSS 11322, 11366-11368). -/
def expand (heroPill : Bool) : Rat := if heroPill then 0 else 1

/-- Nav width (CSS 11331-11334).

The two variables carry the same expression, so the expand factor drops out. -/
def navWidth (v : Vp) (heroPill : Bool) (m : Rat) : Rat :=
  pillW v + (pillW v - pillW v) * expand heroPill + (panelW v - pillW v) * m

/-- Nav height (CSS 11335). -/
def navHeight (v : Vp) (m : Rat) : Rat := pillH v + (panelH v - pillH v) * m

/-- Nav top (CSS 11329, 11571). -/
def navTop (v : Vp) (m : Rat) : Rat := 16 + ((if phone v.w then 12 else 20) - 16) * m

/-- Nav corner radius (CSS 11340). -/
def navRadius (m : Rat) : Rat := 32 - 12 * m

/-- Nav backdrop blur in px (CSS 11342). -/
def navBlur (m : Rat) : Rat := 20 * (1 - m)

/-- Weight of the glass fill in the background mix, in percent (CSS 11336-11339). (the dark fill takes `100 m`). -/
def glassWeight (m : Rat) : Rat := 100 * (1 - m)

/-- The earn button's collapse (CSS 11478). 0 at rest, 1 once the morph is a fifth done. -/
def earnOut (m : Rat) : Rat := clamp01 (m / darkCut)

/-- `--earn-layout` (CSS 11480). The share of the button's width that is kept. -/
def earnLayout (heroPill : Bool) (m : Rat) : Rat := expand heroPill * (1 - earnOut m)

/-- Earn button max-width in px (CSS 11483, 11594-11596). (11 rem and 9.5 rem at 16 px). -/
def earnMaxW (v : Vp) (heroPill : Bool) (m : Rat) : Rat := earnLayout heroPill m * (if phone v.w then 152 else 176)

/-- Earn button inline padding in px (CSS 11484, 11594-11596). -/
def earnPad (v : Vp) (heroPill : Bool) (m : Rat) : Rat := earnLayout heroPill m * (if phone v.w then 16 else 24)

/-- Earn button opacity (CSS 11485). -/
def earnOpacity (heroPill : Bool) (m : Rat) : Rat := (1 - earnOut m) * expand heroPill

/-- Earn button blur in px (CSS 11486). -/
def earnBlur (m : Rat) : Rat := earnOut m * 10

/-- Earn button vertical shift in px (CSS 11488). -/
def earnShift (m : Rat) : Rat := earnOut m * -8

/-- Gap between the language switch and the button in px (CSS 11440, 11584-11586). -/
def actionsGap (v : Vp) (heroPill : Bool) (m : Rat) : Rat :=
  expand heroPill * (1 - earnOut m) * (if phone v.w then 4 else 8)

/-- Logo left in px, while morphing (CSS 11432-11436, bar inset 24, phone 16). -/
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

/-- The unit-interval output of the earn collapse. -/
theorem earnOut_mem (m : Rat) : 0 ≤ earnOut m ∧ earnOut m ≤ 1 := clamp01_mem _

/-- The earn button is gone by a fifth of the morph.

Before the dark look is forced the button has collapsed, so no two steps overlap. -/
theorem earn_gone (v : Vp) (hp : Bool) (m : Rat) (h : darkCut ≤ m) :
    earnOut m = 1 ∧ earnLayout hp m = 0 ∧ earnOpacity hp m = 0 ∧ actionsGap v hp m = 0 := by
  have h1 : earnOut m = 1 := by
    unfold earnOut clamp01 darkCut at *
    have : m / (1 / 5 : Rat) = m * 5 := by rw [Rat.div_def]; grind
    grind
  refine ⟨h1, ?_, ?_, ?_⟩ <;> simp [earnLayout, earnOpacity, actionsGap, h1] <;> grind

/-- At rest the button is fully kept (outside the hero pill). -/
theorem earn_rest : earnOut 0 = 0 ∧ earnLayout false 0 = 1 ∧ earnOpacity false 0 = 1 := by
  refine ⟨by decide +kernel, by decide +kernel, by decide +kernel⟩

/-- The nav starts at the pill box. -/
theorem rest_box (v : Vp) (hp : Bool) : navHeight v 0 = pillH v ∧ navWidth v hp 0 = pillW v ∧ navTop v 0 = 16 := by
  unfold navHeight navWidth navTop; refine ⟨by grind, by grind, by grind⟩

/-- The nav ends at the panel box. -/
theorem end_box (v : Vp) (hp : Bool) : navHeight v 1 = panelH v ∧ navWidth v hp 1 = panelW v ∧ navRadius 1 = 20 := by
  unfold navHeight navWidth navRadius; refine ⟨by grind, by grind, by grind⟩

/-- The expand factor does not move the width.

The two variables `--hero-pill-w` and `--pill-w` carry the same expression. -/
theorem navWidth_expand_irrel (v : Vp) (m : Rat) : navWidth v true m = navWidth v false m := by
  unfold navWidth; grind

/-- The panel is at least as wide as the pill.

So the width grows with the morph. -/
theorem panel_ge_pill (v : Vp) : pillW v ≤ panelW v := by
  unfold pillW panelW
  cases hph : phone v.w <;> simp <;> grind

/-- The width is monotone in the morph.

The pill only widens. -/
theorem navWidth_mono (v : Vp) (hp : Bool) (m m' : Rat) (h : m ≤ m') : navWidth v hp m ≤ navWidth v hp m' := by
  have := panel_ge_pill v
  unfold navWidth
  have h2 : (panelW v - pillW v) * m ≤ (panelW v - pillW v) * m' :=
    Rat.mul_le_mul_of_nonneg_left h (by grind)
  grind

/-- The radius shrinks by 12 px over the morph and stays between 20 and 32 on the unit interval. -/
theorem navRadius_mem (m : Rat) (h0 : 0 ≤ m) (h1 : m ≤ 1) : 20 ≤ navRadius m ∧ navRadius m ≤ 32 := by
  unfold navRadius; grind

/-- The blur and the glass weight reach 0 at the end. -/
theorem glass_ends : navBlur 1 = 0 ∧ glassWeight 1 = 0 ∧ navBlur 0 = 20 ∧ glassWeight 0 = 100 := by
  unfold navBlur glassWeight; refine ⟨by grind, by grind, by grind, by grind⟩

/-! ## Timing and curves of the transitions (the "original" an optimised version is compared with) -/

/-- A CSS cubic-bezier timing function. Control points of the curve from `(0,0)` to `(1,1)`. -/
structure Bezier where
  x1 : Rat
  y1 : Rat
  x2 : Rat
  y2 : Rat

/-- The curve's `x` at parameter `s`. -/
def Bezier.x (b : Bezier) (s : Rat) : Rat := 3 * (1 - s) * (1 - s) * s * b.x1 + 3 * (1 - s) * s * s * b.x2 + s * s * s

/-- The curve's `y` at parameter `s`. -/
def Bezier.y (b : Bezier) (s : Rat) : Rat := 3 * (1 - s) * (1 - s) * s * b.y1 + 3 * (1 - s) * s * s * b.y2 + s * s * s

/-- The curve starts at the origin and ends at (1, 1).

So an eased transition begins at its start value and ends at its end value. -/
theorem Bezier.ends (b : Bezier) : b.x 0 = 0 ∧ b.y 0 = 0 ∧ b.x 1 = 1 ∧ b.y 1 = 1 := by
  unfold Bezier.x Bezier.y; refine ⟨by grind, by grind, by grind, by grind⟩

/-- `cubic-bezier(0.33, 0, 0.2, 1)`: width, background, gap, earn collapse, unmask and sheen (CSS 11353, 11358, 11441, 11487). -/
def easeSettle : Bezier := ⟨33 / 100, 0, 1 / 5, 1⟩

/-- `cubic-bezier(0.16, 1, 0.3, 1)`: opacity and transform of the nav (CSS 11349-11351, 11401). -/
def easeOut : Bezier := ⟨4 / 25, 1, 3 / 10, 1⟩

/-- `cubic-bezier(0.4, 0, 0.2, 1)`: logo colour and language switch (CSS 11425, 11129). -/
def easeStd : Bezier := ⟨2 / 5, 0, 1 / 5, 1⟩

/-- Width transition in ms (CSS 11358). How long the pill takes to change width. -/
def widthMs : Nat := 680

/-- Background transition in ms (CSS 11358). -/
def backgroundMs : Nat := 700

/-- Chrome fade-in in ms (CSS 11397-11403). -/
def chromeFadeMs : Nat := 700

/-- Transform (slide away) transition in ms (CSS 11351). -/
def slideMs : Nat := 320

/-- Opacity transition in ms (CSS 11350). -/
def fadeMs : Nat := 280

/-- Earn unmask and sheen. Ms after a delay of `520` ms (CSS 11535, 11543). -/
def earnUnmaskMs : Nat := 980

/-- Delay of the earn unmask in ms. -/
def earnUnmaskDelayMs : Nat := 520

/-- Nav slide-away offset in px (CSS 11382). Fully above the viewport edge. -/
def slideOffset (navH : Rat) : Rat := -(navH + 24)

/-- The earn sheen travels from `-130 %` to `130 %` of the button width (CSS 11522, 11556-11559). -/
def sheenX (e : Rat) : Rat := -130 + 260 * e

/-- The unmask moves the mask from `100% 0` to `0 0` (CSS 11546-11555).

In percent. -/
def maskX (e : Rat) : Rat := 100 * (1 - e)

/-- The sheen ends are `∓ 130`, the mask ends 100 and 0. -/
theorem unmask_ends : sheenX 0 = -130 ∧ sheenX 1 = 130 ∧ maskX 0 = 100 ∧ maskX 1 = 0 := by
  unfold sheenX maskX; refine ⟨by grind, by grind, by grind, by grind⟩

end Fw.Parts.Nav
