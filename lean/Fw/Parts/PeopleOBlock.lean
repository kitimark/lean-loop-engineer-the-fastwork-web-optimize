import Fw.Parts.PeopleO
/-!
# people.o `block`: the "o" as a block box instead of an inline grid

Why. Stock desktop Chrome crashes (SIGSEGV, `chrome-balance-repro`, run 39878812594) when an `h2` with
`text-wrap: balance` has a line that holds an inline-grid atomic inline, in a window wider than 860 px. Two changes stopped
it in that run: the `o` as `inline-block`, and `text-wrap: wrap` on the `h2`.

What each option changes (restated from CSS Box Alignment, Flexbox and Grid, the title is in `people.card`):

* `block` (this file). The `o` is a flex item of the inline-flex word (`white-space: nowrap; display: inline-flex;
  align-items: flex-start`), so `inline-grid` and `inline-block` both compute to a blockified box and its baseline is not
  read: with `flex-start` (or `center`) the item's cross position depends on heights only. Width: the grid's one column
  `minmax(0, c)` has max-content size `c`, and a flex item with `flex-shrink: 0` keeps its max-content basis, so the used
  width is `c`; the block states `width: c`. Height is declared in both. The `stage` fills the grid area (`width: 100%`,
  `height: 100%`) and, as a block child, fills the content box; both are the `o` box. The width transition interpolates the
  same length with the same curve as the track transition. No look change.
* `text-wrap: wrap` on the `h2` (not taken). It keeps the `o` as it is, and changes only where lines break: balanced
  breaks are the greedy breaks when the title fits one line, and differ when it wraps. It lives in `people.card`.
-/
namespace Fw.Parts.PeopleOBlock

open Fw.Parts.PeopleO

/-- A box in em. -/
structure Box where
  w : Rat
  h : Rat
deriving DecidableEq, Repr

/-- Size of the grid track `minmax(0, c)` when the container is sized by its content (`avail = none`) or has `a` to give. -/
def track (c : Rat) : Option Rat → Rat
  | none => c
  | some a => min c a

/-- Column width of the `o` in em (closed or expanded). -/
def col (expanded : Bool) : Rat := if expanded then openWidth else closedWidth

/-- Height of the `o` in em. -/
def hgt (expanded : Bool) : Rat := if expanded then openHeight else closedHeight

/-- The faithful `o`: an inline grid with one column `minmax(0, col)`. As a flex item with `flex-shrink: 0` its
width is its max-content size, the track's. -/
def gridBox (e : Bool) : Box := ⟨track (col e) none, hgt e⟩

/-- The `block` `o`: a block with `width` and `height` declared. -/
def blockBox (e : Bool) : Box := ⟨col e, hgt e⟩

/-- **Same box.** Closed and expanded, the two `o` boxes are equal. -/
theorem box_eq (e : Bool) : gridBox e = blockBox e := rfl

/-- The `stage` child: `width: 100%` and `height: 100%` of the grid area (grid) or of the content box (block). -/
def stage (b : Box) : Box := b

/-- **Same stage.** The stage fills the same box, so the absolutely placed vector and stack have the same containing block. -/
theorem stage_eq (e : Bool) : stage (gridBox e) = stage (blockBox e) := by rw [box_eq]

/-- Linear interpolation. -/
def lerp (a b p : Rat) : Rat := a + (b - a) * p

/-- Used width `p` of the way through the opening transition: the grid animates the track length, the block the width. -/
def gridWidthAt (p : Rat) : Rat := track (lerp (col false) (col true) p) none
def blockWidthAt (p : Rat) : Rat := lerp (col false) (col true) p

/-- **Same transition.** Every frame of the opening has the same width in both. -/
theorem width_at_eq (p : Rat) : gridWidthAt p = blockWidthAt p := rfl

/-- **The closed box is the declared one.** `0.6042 em` by `1.0417 em`, as in the original. -/
theorem closed_box : blockBox false = ⟨3021 / 5000, 10417 / 10000⟩ := rfl

/-- **The opened box is the declared one.** `5.25 em` by `1.0833 em`. -/
theorem open_box : blockBox true = ⟨21 / 4, 10833 / 10000⟩ := rfl

/-- Cross-axis alignment of a flex item. -/
inductive Align where
  | flexStart | center | baseline
deriving DecidableEq, Repr

/-- Cross offset of an item of height `h` in a line of cross size `line` whose shared baseline is at `lb`, when the
item's own baseline is at `ib` (read only by `baseline`). -/
def crossPos : Align → (line h lb ib : Rat) → Rat
  | .flexStart, _, _, _, _ => 0
  | .center, line, h, _, _ => (line - h) / 2
  | .baseline, _, _, lb, ib => lb - ib

/-- **The baseline is not read.** For `flex-start` and `center` (the title and the standalone `o`) the offset is the same
whatever baseline the item has, so the baseline of an inline grid and of a block cannot move the `o`. -/
theorem crossPos_baseline_free (a : Align) (h : a ≠ .baseline) (line hh lb ib ib' : Rat) :
    crossPos a line hh lb ib = crossPos a line hh lb ib' := by
  cases a <;> simp_all [crossPos]

/-- **Same position.** Equal boxes in an equal line sit at equal offsets, for every non-baseline alignment and any baseline. -/
theorem pos_eq (a : Align) (h : a ≠ .baseline) (e : Bool) (line lb ib ib' : Rat) :
    crossPos a line (gridBox e).h lb ib = crossPos a line (blockBox e).h lb ib' := by
  rw [box_eq]; exact crossPos_baseline_free a h _ _ _ _ _

/-- The cross size of a flex line of two items (the text run and the `o`). -/
def lineSize (text : Rat) (b : Box) : Rat := max text b.h

/-- **Same line box.** The inline-flex word is as high with either `o`. -/
theorem lineSize_eq (text : Rat) (e : Bool) : lineSize text (gridBox e) = lineSize text (blockBox e) := by rw [box_eq]

end Fw.Parts.PeopleOBlock
