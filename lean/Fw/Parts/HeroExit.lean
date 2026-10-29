/-!
# hero.exit: scroll position → exit opacity, scatter and the CSS consumers (M2 pilot part)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`
  * 4155-4172: per frame, under `prefers-reduced-motion` write `--exit-opacity: 1` and clear `pointer-events`;
    else read the `.hero-track` rect, `n = max(1, h - innerHeight)`,
    `e = 1 - min(n, max(0, -top))/n`, write `--exit-opacity` on `.hero` and
    `pointer-events: none` iff `e < 0.05`;
  * 4173-4175: the frame body is its own `requestAnimationFrame` (`i ||= rAF(s)`), requested by the callback the
    scroll engine runs (4239, `dE(c, {deferRendering, element: track})`): see `Fw.Parts.EngineScroll`;
  * 12996-13007: the nav restates the same progress, `min(r, max(0, -top))/r ≥ 0.72`
    (`is-hero-pill` off, the 0.72 triple flip).
* `assets/2.gBuqKVzi.css`: track `height: 200vh` (1523-1527, `auto` under reduced motion 2128); `.hero` sticky,
  `height: 100svh; min-height: 680px` (1528-1543; `min-height: 100svh` at `width<=600px`, 2032-2034);
  `--exit-scatter: calc(1 - var(--exit-opacity))` (1530; `0` under reduced motion, 2132); cards 1577, 1586-1587;
  hero copy 1734-1736, 1746-1747, 2039-2046; scroll cue 1907-1913, 1925-1937.

Bands: `(width<=600px)` vs `(width>600px)` (complementary, no gap: `le600` below), plus reduced motion.
All values `Rat` (CSS px and scroll offsets can be fractional). No `Float`.
-/
namespace Fw.Parts.HeroExit

/-! ## Rational helpers -/

/-- Division by a positive number undoes multiplication.

Dividing and multiplying back by the same positive number gives the original value. -/
theorem div_mul_pos (c n : Rat) (hn : 0 < n) : c / n * n = c := Rat.div_mul_cancel (by grind)

/-- A share between 0 and the whole is a fraction between 0 and 1.

Part of a positive length divided by the length lies in the unit interval. -/
theorem div_unit (c n : Rat) (hn : 0 < n) (h0 : 0 ≤ c) (h1 : c ≤ n) : 0 ≤ c / n ∧ c / n ≤ 1 := by
  have hq := div_mul_pos c n hn
  constructor
  · apply Classical.byContradiction; intro hneg
    have := Rat.mul_lt_mul_of_pos_right (show c / n < 0 by grind) hn
    grind
  · apply Classical.byContradiction; intro hgt
    have := Rat.mul_lt_mul_of_pos_right (show 1 < c / n by grind) hn
    grind

/-- Dividing by a positive number keeps order.

A larger numerator over the same positive denominator is never a smaller fraction. -/
theorem div_mono (c1 c2 n : Rat) (hn : 0 < n) (h : c1 ≤ c2) : c1 / n ≤ c2 / n := by
  have h1 := div_mul_pos c1 n hn
  have h2 := div_mul_pos c2 n hn
  apply Classical.byContradiction; intro hlt
  have := Rat.mul_lt_mul_of_pos_right (show c2 / n < c1 / n by grind) hn
  grind

/-! ## Exit opacity -/

/-- Scroll range of the exit: `n = max(1, h - v)` (JS 4168).

How many px the sticky hero travels inside its track, never less than 1 so the division is safe. -/
def exitRange (trackHeight viewportHeight : Rat) : Rat := max 1 (trackHeight - viewportHeight)

/-- Clamped distance scrolled past the track top: `min(n, max(0, -top))`.

How far the track's top has moved above the viewport, held between 0 and the range. -/
def exitClamp (trackTop n : Rat) : Rat := min n (max 0 (-trackTop))

/-- `--exit-opacity` from the track rect (JS 4168-4170).

The hero fades from 1 (track top at or below the viewport top) to 0 (scrolled through the whole range). -/
def exitOpacity (trackTop trackHeight viewportHeight : Rat) : Rat :=
  1 - exitClamp trackTop (exitRange trackHeight viewportHeight) / exitRange trackHeight viewportHeight

#guard exitOpacity 0 1600 800 == 1
#guard exitOpacity 100 1600 800 == 1
#guard exitOpacity (-400) 1600 800 == 1/2
#guard exitOpacity (-800) 1600 800 == 0
#guard exitOpacity (-5000) 1600 800 == 0
#guard exitRange 100 800 == 1
#guard exitOpacity (-3) 100 800 == 0
#guard exitOpacity (-100) 1500 800 == 6/7

/-- The exit range is positive. -/
theorem exitRange_pos (h v : Rat) : 0 < exitRange h v := by unfold exitRange; grind

/-- Clamping: the exit opacity is always in `[0, 1]`.

Whatever the track geometry and scroll position, the opacity written is a valid opacity. -/
theorem exitOpacity_mem (t h v : Rat) : 0 ≤ exitOpacity t h v ∧ exitOpacity t h v ≤ 1 := by
  have hn := exitRange_pos h v
  have := div_unit (exitClamp t (exitRange h v)) (exitRange h v) hn
    (by unfold exitClamp; grind) (by unfold exitClamp; grind)
  unfold exitOpacity; constructor <;> grind

/-- Exit opacity at document scroll `y` for a track whose top sits at document offset `T` (rect top `= T - y`).

The same opacity, written as a function of the page's scroll position. -/
def exitOpacityAt (T h v y : Rat) : Rat := exitOpacity (T - y) h v

/-- Monotone in scroll: scrolling further down never raises the opacity.

The hero only fades out as you scroll down, and only fades back in as you scroll up. -/
theorem exitOpacity_antitone (T h v y1 y2 : Rat) (hy : y1 ≤ y2) :
    exitOpacityAt T h v y2 ≤ exitOpacityAt T h v y1 := by
  unfold exitOpacityAt exitOpacity
  have := div_mono (exitClamp (T - y1) (exitRange h v)) (exitClamp (T - y2) (exitRange h v)) (exitRange h v)
    (exitRange_pos h v) (by unfold exitClamp; grind)
  grind

/-- Lipschitz in scroll (hence continuous, including at both clamp edges `y = T` and `y = T + n`):
the opacity changes by at most `|Δ y| / n`.

The fade has no jumps: one px of scroll moves the opacity by at most one n-th. -/
theorem exitOpacity_lipschitz (T h v y1 y2 : Rat) (hy : y1 ≤ y2) :
    0 ≤ exitRange h v * (exitOpacityAt T h v y1 - exitOpacityAt T h v y2) ∧
      exitRange h v * (exitOpacityAt T h v y1 - exitOpacityAt T h v y2) ≤ y2 - y1 := by
  have hn := exitRange_pos h v
  have q1 := div_mul_pos (exitClamp (T - y1) (exitRange h v)) (exitRange h v) hn
  have q2 := div_mul_pos (exitClamp (T - y2) (exitRange h v)) (exitRange h v) hn
  have c1 : exitClamp (T - y1) (exitRange h v) ≤ exitClamp (T - y2) (exitRange h v) := by
    unfold exitClamp; grind
  have c2 : exitClamp (T - y2) (exitRange h v) - exitClamp (T - y1) (exitRange h v) ≤ y2 - y1 := by
    unfold exitClamp; grind
  unfold exitOpacityAt exitOpacity
  constructor <;> grind

/-- Before the exit: with the track top at or below the viewport top, the hero is fully opaque.

Nothing fades until the track starts to scroll past the top of the viewport. -/
theorem exitOpacity_before (t h v : Rat) (ht : 0 ≤ t) : exitOpacity t h v = 1 := by
  unfold exitOpacity exitClamp
  have hn := exitRange_pos h v
  have : min (exitRange h v) (max 0 (-t)) = 0 := by grind
  rw [this]; grind

/-- After the exit: once scrolled through the whole range, the hero is fully transparent.

Past the end of the range the opacity stays at exactly 0. -/
theorem exitOpacity_after (t h v : Rat) (ht : exitRange h v ≤ -t) : exitOpacity t h v = 0 := by
  unfold exitOpacity exitClamp
  have hn := exitRange_pos h v
  have : min (exitRange h v) (max 0 (-t)) = exitRange h v := by grind
  rw [this, Rat.div_def, Rat.mul_inv_cancel _ (by grind)]; grind

/-- Inside the range the fade is linear: `n e = n + t`.

Between the two clamp edges the opacity falls in a straight line with the scroll offset. -/
theorem exitOpacity_linear (t h v : Rat) (h0 : 0 ≤ -t) (h1 : -t ≤ exitRange h v) :
    exitRange h v * exitOpacity t h v = exitRange h v + t := by
  have hn := exitRange_pos h v
  have q := div_mul_pos (exitClamp t (exitRange h v)) (exitRange h v) hn
  have : exitClamp t (exitRange h v) = -t := by unfold exitClamp; grind
  unfold exitOpacity; grind

/-- `--exit-scatter` (CSS 1530): `s = 1 - e`.

How far the hero has scattered: 0 at rest, 1 when fully gone. -/
def exitScatter (opacity : Rat) : Rat := 1 - opacity

/-- Pointer events are switched off below opacity 0.05 (JS 4171; strict).

The hero stops taking taps once it is almost invisible. -/
def pointerOff (opacity : Rat) : Bool := decide (opacity < 1 / 20)

#guard pointerOff (1/20) == false
#guard pointerOff (499/10000) == true

/-- One frame's output: the opacity written and whether pointer events are off.

What one hero exit frame writes. -/
structure ExitFrame where
  opacity : Rat
  pointerNone : Bool
deriving Repr, BEq, DecidableEq

/-- One frame (JS 4162-4171): reduced motion writes opacity 1 and clears pointer events without reading the rect.

The hero exit's per-frame result, including the reduced-motion short cut. -/
def exitFrame (reduced : Bool) (trackTop trackHeight viewportHeight : Rat) : ExitFrame :=
  if reduced then ⟨1, false⟩
  else
    let e := exitOpacity trackTop trackHeight viewportHeight
    ⟨e, pointerOff e⟩

#guard exitFrame true (-9999) 1600 800 == ⟨1, false⟩
#guard exitFrame false (-800) 1600 800 == ⟨0, true⟩
#guard exitFrame false (-760) 1600 800 == ⟨1/20, false⟩

/-- Pointer-off is an upper set in scroll: once off, scrolling further keeps it off.

Once the hero ignores taps, scrolling further down keeps it that way; it never flickers back on while scrolling
down. -/
theorem pointerOff_mono (T h v y1 y2 : Rat) (hy : y1 ≤ y2) (hp : pointerOff (exitOpacityAt T h v y1) = true) :
    pointerOff (exitOpacityAt T h v y2) = true := by
  have := exitOpacity_antitone T h v y1 y2 hy
  unfold pointerOff at *
  simp only [decide_eq_true_eq] at *
  grind

/-- The pointer-off threshold: pointer events are off exactly when the scroll is strictly past
`T + 19/20 n`.

There is a single scroll position, 95% of the way through the exit range, past which the hero ignores taps. -/
theorem pointerOff_iff_threshold (T h v y : Rat) :
    pointerOff (exitOpacityAt T h v y) = true ↔ T + 19 / 20 * exitRange h v < y := by
  have hn := exitRange_pos h v
  have q := div_mul_pos (exitClamp (T - y) (exitRange h v)) (exitRange h v) hn
  unfold pointerOff exitOpacityAt exitOpacity
  simp only [decide_eq_true_eq]
  generalize hx : exitClamp (T - y) (exitRange h v) / exitRange h v = x at q
  have hc : exitClamp (T - y) (exitRange h v) = min (exitRange h v) (max 0 (-(T - y))) := rfl
  constructor
  · intro hlt
    have := Rat.mul_lt_mul_of_pos_right (show 19 / 20 < x by grind) hn
    grind
  · intro hgt
    apply Classical.byContradiction; intro hge
    have hx' : x ≤ 19 / 20 := by grind
    rcases Rat.le_iff_lt_or_eq.mp hx' with hl | he
    · have := Rat.mul_lt_mul_of_pos_right hl hn
      grind
    · subst he; grind

/-! ## The nav's restatement and the 0.72 threshold (single owner) -/

/-- The nav's own hero progress (JS 13002-13007): `min(r, max(0, -t))/r`, `r = max(1, h - v)`.

How far through the hero the page is, as the nav computes it independently. -/
def navHeroProgress (trackTop trackHeight viewportHeight : Rat) : Rat :=
  let r := max 1 (trackHeight - viewportHeight)
  min r (max 0 (-trackTop)) / r

/-- The two code sites agree: the nav's progress is exactly one minus the exit opacity.

The original computes the hero progress twice; both are the same number, so one owner can serve both. -/
theorem navHeroProgress_eq (t h v : Rat) : navHeroProgress t h v = 1 - exitOpacity t h v := by
  unfold navHeroProgress exitOpacity exitClamp exitRange; grind

/-- The 0.72 flip (`is-hero-pill` off, people reveal, pain dark) in exit-opacity terms.

The nav's 0.72 threshold is the moment the hero's opacity drops to 0.28. -/
theorem pill_threshold (t h v : Rat) : navHeroProgress t h v ≥ 18 / 25 ↔ exitOpacity t h v ≤ 7 / 25 := by
  rw [navHeroProgress_eq]; constructor <;> intro <;> grind

/-- The hero's pointer cut-off comes after the 0.72 flip.

By the time the hero ignores taps, the nav has already dropped its hero pill. -/
theorem pointerOff_after_pill (t h v : Rat) (hp : pointerOff (exitOpacity t h v) = true) :
    navHeroProgress t h v ≥ 18 / 25 := by
  rw [pill_threshold]; unfold pointerOff at hp; simp only [decide_eq_true_eq] at hp; grind

/-! ## Geometry and bands -/

/-- The phone band: `(width<=600px)` (its complement `(width>600px)` is the other band; no gap for fractional widths).

Whether the viewport is in the phone layout of the hero. -/
def le600 (width : Rat) : Bool := decide (width ≤ 600)

#guard le600 600 == true && le600 (1201/2) == false && le600 601 == false

/-- Track height: `200vh`, or `auto` (none) under reduced motion (CSS 1523-1527, 2128).

How tall the hero's scroll track is; under reduced motion it is sized by its content. -/
def trackHeightPx (viewportHeight : Rat) (reduced : Bool) : Option Rat :=
  if reduced then none else some (2 * viewportHeight)

/-- Hero height: `100svh` with `min-height: 680px` outside the phone band (CSS 1531-1543, 2032-2034).

How tall the sticky hero is in each band. -/
def heroHeightPx (svh : Rat) (le600 : Bool) : Rat := if le600 then svh else max svh 680

/-- With a `200vh` track and `innerHeight = vh`, the exit range is the viewport height (at least 1).

On desktop the hero fades over exactly one screen of scrolling. -/
theorem exitRange_200vh (v : Rat) : exitRange (2 * v) v = max 1 v := by unfold exitRange; grind

/-! ## CSS consumers (calc() restated) -/

/-- Hero copy opacity (CSS 1734; phone 2043 with `--copy-in: 1`): `copyIn· e`.

The headline block's opacity: its entrance amount times the exit opacity. -/
def copyOpacity (copyIn exitOpacityValue : Rat) : Rat := copyIn * exitOpacityValue

/-- Hero copy blur px (CSS 1735; `filter: none` in the phone band, 2044).

How blurred the headline block is while entering and exiting. -/
def copyBlurPx (copyIn scatter : Rat) (le600 : Bool) : Rat :=
  if le600 then 0 else (1 - copyIn) * 16 + scatter * 18

/-- Hero copy translateY px (CSS 1736; phone 2045 `translate(-50%, scatter·-8px)`).

How far the headline block moves up while exiting (and down before entering). -/
def copyTranslateYPx (copyIn scatter : Rat) (le600 : Bool) : Rat :=
  if le600 then scatter * -8 else (1 - copyIn) * 12 + scatter * -10

/-- Scroll-cue blur px, TS form (assumes the cue has entered, `--copy-in: 1`): `18 s`.

The scroll cue's blur once its entrance has finished. -/
def cueBlurPx (scatter : Rat) : Rat := scatter * 18

/-- Scroll-cue translateY px, TS form: `-10 s` in the phone band, `0` otherwise (assumes entered and, above 600 px,
`is-ring-splash-done`).

The scroll cue's vertical exit motion in its settled state. -/
def cueTranslateYPx (scatter : Rat) (le600 : Bool) : Rat := if le600 then scatter * -10 else 0

/-- Scroll-cue opacity, TS form: `e`. The cue's rule is `opacity: calc(var(--copy-in) * var(--exit-opacity))`, and
its settled rule `--copy-in: 1; opacity: var(--exit-opacity)`, in both bands.

The scroll cue fades with the exit opacity once its entrance has finished. -/
def cueOpacity (exitOpacityValue : Rat) : Rat := exitOpacityValue

/-- Scroll-cue blur px, full reading (CSS 1911, 1925-1928, 1930-1933): includes the entrance and the splash state.

The scroll cue's blur at any moment, before or after the desktop ring splash (`d`) completes. -/
def cueBlurPxFull (copyIn scatter : Rat) (le600 splashDone : Bool) : Rat :=
  if le600 || splashDone then scatter * 18 else (1 - copyIn) * 16 + scatter * 18

/-- Scroll-cue translateY px, full reading (CSS 1913, 1930-1935).

The scroll cue's vertical motion at any moment, including its entrance. -/
def cueTranslateYPxFull (copyIn scatter : Rat) (le600 splashDone : Bool) : Rat :=
  if !le600 && splashDone then 0 else (1 - copyIn) * 12 + scatter * -10

/-- The TS reading of the cue is the full reading in the settled state (cue entered; above 600 px, splash done).

The two readings differ only during the load entrance, never while the user scrolls a settled page. -/
theorem cue_ts_eq_full (c s : Rat) (l d : Bool) (h1 : l = true → c = 1) (h2 : l = false → d = true) :
    cueBlurPx s = cueBlurPxFull c s l d ∧ cueTranslateYPx s l = cueTranslateYPxFull c s l d := by
  unfold cueBlurPx cueBlurPxFull cueTranslateYPx cueTranslateYPxFull
  cases l <;> cases d <;> simp_all <;> grind

/-- Card opacity (CSS 1577): `1 - 0.35 s`.

Orbit and deck cards dim to 65% as the hero exits. -/
def cardOpacity (scatter : Rat) : Rat := 1 - scatter * (7 / 20)

/-- Card translate component (CSS 1586-1587): `(1 - entered) enter + s scatterOffset`.

Where a card sits along one axis: its entrance offset fading out plus its scatter offset growing in. -/
def cardTranslate (entered enter scatter scatterOffset : Rat) : Rat :=
  (1 - entered) * enter + scatter * scatterOffset

/-- Ranges of the settled consumers for `e ∈ [0,1]` (`s = 1 - e`, `copyIn ∈ [0,1]`).

Copy and card opacities stay valid opacities, and cards never dim below 65%. -/
theorem consumers_range (c e : Rat) (hc0 : 0 ≤ c) (hc1 : c ≤ 1) (he0 : 0 ≤ e) (he1 : e ≤ 1) :
    0 ≤ copyOpacity c e ∧ copyOpacity c e ≤ 1 ∧
      13 / 20 ≤ cardOpacity (exitScatter e) ∧ cardOpacity (exitScatter e) ≤ 1 := by
  have m0 := Rat.mul_le_mul_of_nonneg_left he0 hc0
  have m1 := Rat.mul_le_mul_of_nonneg_left he1 hc0
  unfold copyOpacity cardOpacity exitScatter
  refine ⟨by grind, by grind, by grind, by grind⟩

/-- Monotone in scroll, per band: as `s` grows, translations move up (decrease), blurs grow, opacities fall.

Every exit effect moves in one direction as the page scrolls down, in both bands. -/
theorem consumers_mono (c s1 s2 : Rat) (l : Bool) (hc : 0 ≤ c) (hs : s1 ≤ s2) :
    copyTranslateYPx c s2 l ≤ copyTranslateYPx c s1 l ∧ copyBlurPx c s1 l ≤ copyBlurPx c s2 l ∧
      cardOpacity s2 ≤ cardOpacity s1 ∧ copyOpacity c (1 - s2) ≤ copyOpacity c (1 - s1) := by
  have m := Rat.mul_le_mul_of_nonneg_left (show 1 - s2 ≤ 1 - s1 by grind) hc
  unfold copyTranslateYPx copyBlurPx cardOpacity copyOpacity
  cases l <;> simp <;> refine ⟨by grind, by grind, by grind⟩

/-- The band edge at 600 px is a jump unless the hero is at rest: settled copy (`c = 1`) moves `-8s` vs `-10s` and
blurs `0` vs `18 s`; the settled cue moves `-10 s` vs `0`.

Resizing across 600 px mid-exit makes the copy and cue jump; at the top of the page (`s = 0`) the two bands agree. -/
theorem band_edge_jump (s : Rat) :
    copyTranslateYPx 1 s true - copyTranslateYPx 1 s false = 2 * s ∧
      copyBlurPx 1 s false - copyBlurPx 1 s true = 18 * s ∧
      cueTranslateYPx s false - cueTranslateYPx s true = 10 * s := by
  unfold copyTranslateYPx copyBlurPx cueTranslateYPx
  simp; refine ⟨by grind, by grind, by grind⟩

end Fw.Parts.HeroExit
