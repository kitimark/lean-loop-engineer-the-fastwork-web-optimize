import Fw.Parts.PeopleOBlock
/-!
# people.card title: `text-wrap: wrap` instead of `balance` above 860 px

Stock desktop Chrome crashes (SIGSEGV, run 39878812594) while it balances the title, whose line holds the inline-flex word
with the `o`. Measured in run 39890158715 (stock Chrome 156.0.8078.4, rewrite page at 1280): `text-wrap: wrap` on the title
does not crash; the `o` as a block of any width above zero crashes (`block-w`, `block-w1px`, also with `overflow: visible`,
`position: static`, `height: auto`); `display: inline-block` with `width: auto` or `0` and `position: absolute` do not
crash but change the look. So the option kept is the title's `text-wrap`. `Fw.Parts.PeopleOBlock` proves the look of the
block `o` and is kept as the record of the refuted option.

What the change touches. The title is `clamp(36px, 4vw, 48px)` with the `o` word on one line; above 860 px the card pads
`56px` on each side. The balancing code returns at once for a one-line paragraph
(`score_line_breaker.cc:139-142`, `paragraph_line_breaker.cc:210`@f842f52). At 860 px and below the title is `text-wrap: unset`
and a flex column, never balanced. So the only width range in which the declaration does anything is the one where the
title fits one line, and there no break position exists to differ.

Flag, not default (`people.card:title-wrap`). The breakpoint gate reads the title's `text-wrap-style`. With the change as the
default it failed 111 readings on Chromium and 105 on WebKit, all `balance` against `auto` on the title at the widths above
860 px (run 39891679733), so the faithful default keeps `balance` and the gate stays green.
-/
namespace Fw.Parts.PeopleTitleWrap

/-- Font size of the title in px at viewport width `vw`: `clamp(36, 4vw, 48)`. -/
def fontPx (vw : Rat) : Rat := min 48 (max 36 (vw * 4 / 100))

/-- Upper bound of the title's max-content width in em. Measured `10.515` em in WebKit (378.53 px at 36 px, 504.72 px at 48 px);
the bound is 12 so that a different face or hinting cannot break the proof. -/
def titleEm : Rat := 12

/-- Content width the title can use in px: the viewport, minus a scrollbar of `sb` px, minus the card padding `56 + 56`. -/
def avail (vw sb : Rat) : Rat := vw - sb - 112

/-- **One line.** Above 860 px, at any width, with a scrollbar of up to 40 px, the title's widest line is no wider than the
space it has. The proof needs only `fontPx ≤ 48`. -/
theorem fits_one_line (vw sb : Rat) (hv : 860 < vw) (hs : sb ≤ 40) : titleEm * fontPx vw ≤ avail vw sb := by
  have h : fontPx vw ≤ 48 := by unfold fontPx; grind
  unfold titleEm avail
  grind

/-- **Narrowest case.** At 861 px the title is `36 px` and needs at most `432 px` of `709 px`. -/
theorem narrowest : fontPx 861 = 36 ∧ titleEm * fontPx 861 = 432 ∧ avail 861 40 = 709 := by decide +kernel

/-- A line-breaking policy: the break offsets it picks for a run of box widths in a space `a`. -/
structure Policy where
  breaks : List Rat → Rat → List Nat

/-- A policy that places no break when the whole run fits (CSS Text: a soft wrap opportunity is used only when needed).
Greedy filling satisfies it by definition; the balancing code returns early for one line
(`score_line_breaker.cc:139-142`, `paragraph_line_breaker.cc:210`@f842f52). -/
def Policy.NoBreakWhenFits (p : Policy) : Prop := ∀ ws a, ws.sum ≤ a → p.breaks ws a = []

/-- **No look change.** Two policies that break nothing when everything fits agree on every run that fits. With
`fits_one_line`, `wrap` and `balance` give the same lines for the title above 860 px. -/
theorem same_when_fits (p q : Policy) (hp : p.NoBreakWhenFits) (hq : q.NoBreakWhenFits) (ws : List Rat) (a : Rat)
    (h : ws.sum ≤ a) : p.breaks ws a = q.breaks ws a := by
  rw [hp ws a h, hq ws a h]

end Fw.Parts.PeopleTitleWrap
