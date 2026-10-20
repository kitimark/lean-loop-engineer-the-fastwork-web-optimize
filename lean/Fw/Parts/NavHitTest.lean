/-!
# nav.hitTest: what lies under the nav, and when the answer can be skipped (M2 pilot part)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`
  * 12936-12937: `closest()` selector lists: exclude `.commission-card, .start-selling-future-card, .hero`;
    include `.pain, .start-selling-platform-card, .start-selling-platform`;
  * 12950-12954 `j`: no element → false; inside an excluded section → false; else inside an included section or
    `.commission.shrinking` → true;
  * 12955-12963 `F`: probe at the nav rect's horizontal centre and the middle of its first 64 px; the nav root's
    inline `pointer-events` is set to `none`, `document.elementFromPoint` is called, the old value restored;
  * 13001 `z(g, F(), !0)`: the state is set every frame (Svelte skips equal values);
  * 13228: `is-on-dark = g || morph > 0.2` — the only reader of `g` in the nav component (12884-13259).
* `assets/2.gBuqKVzi.css`: nav boxes that set `pointer-events` explicitly and so stay hit-testable under the
  root's inline `none`: `.start-selling-top-nav-actions` (`auto`, 11442), `.start-selling-morph-panel` while the nav
  `.is-expanded` (`auto`, 10556-10557), `.start-selling-morph-pill` while the morph is active and not expanded
  (`auto`, 10518-10519), the earn button in the phone band (11497-11498).

Two different "hit-skip" fixes exist in v1: `fixes/nav-hit-test` (`elementsFromPoint`, skip the nav's own subtree
except the re-enabled boxes) and `fixes/hit-skip` (skip the test while `morph > 0.2`, where `is-on-dark` is forced).
Both are specified below. The TS part's `firstOutside` skips the whole nav subtree, re-enabled boxes included.
-/
namespace Fw.Parts.NavHitTest

/-! ## Probe point -/

/-- A DOMRect. The nav's bounding box. -/
structure Rect where
  left : Rat
  top : Rat
  width : Rat
  height : Rat
deriving Repr, BEq, DecidableEq

/-- Probe point (JS 12957-12958): horizontal centre; vertical centre of the first 64 px.

Where the nav looks for the section underneath it. -/
def hitPoint (r : Rect) : Rat × Rat := (r.left + r.width / 2, r.top + min r.height 64 / 2)

#guard hitPoint ⟨0, 0, 390, 64⟩ == (195, 32)
#guard hitPoint ⟨12, 8, 361, 100⟩ == (12 + 361/2, 40)

/-- The probe point lies inside the nav rect, in its top 32 px band.

The probe never samples outside the nav's own box, and never below its first 64 px. -/
theorem hitPoint_inside (r : Rect) (hw : 0 ≤ r.width) (hh : 0 ≤ r.height) :
    r.left ≤ (hitPoint r).1 ∧ (hitPoint r).1 ≤ r.left + r.width ∧
      r.top ≤ (hitPoint r).2 ∧ (hitPoint r).2 ≤ r.top + r.height ∧ (hitPoint r).2 ≤ r.top + 32 := by
  unfold hitPoint
  refine ⟨by grind, by grind, by grind, by grind, by grind⟩

/-! ## Classification -/

/-- `closest()` flags of the hit element. What the element under the probe is inside of. -/
structure HitFlags where
  hasElement : Bool
  inExclude : Bool
  inInclude : Bool
  inShrinking : Bool
deriving Repr, BEq, DecidableEq

/-- `j` (JS 12950-12954): over a dark section.

Whether the nav sits over a dark section (pain, platform, or the shrinking commission), with light sections winning. -/
def classifyHit (f : HitFlags) : Bool :=
  if !f.hasElement || f.inExclude then false else f.inInclude || f.inShrinking

#guard classifyHit ⟨false, false, true, true⟩ == false
#guard classifyHit ⟨true, true, true, true⟩ == false
#guard classifyHit ⟨true, false, true, false⟩ == true
#guard classifyHit ⟨true, false, false, true⟩ == true
#guard classifyHit ⟨true, false, false, false⟩ == false

/-- The classification in closed form; an excluded ancestor always wins.

Dark only when there is an element, it is not inside a light section, and it is inside a dark one. -/
theorem classifyHit_eq (f : HitFlags) :
    classifyHit f = (f.hasElement && !f.inExclude && (f.inInclude || f.inShrinking)) := by
  cases f with
  | mk a b c d => cases a <;> cases b <;> cases c <;> cases d <;> rfl

/-! ## Hit stacks: faithful `elementFromPoint` vs the skip variants -/

/-- One box at the probe point, top-most first (`elementsFromPoint` order, the nav at its normal
`pointer-events`): whether it is inside the nav, and whether it sets `pointer-events` itself (so stays hit-testable
when the nav root is forced to `none`).

A candidate element under the probe. -/
structure Hit where
  insideNav : Bool
  reEnabled : Bool
deriving Repr, BEq, DecidableEq

/-- First index satisfying a test, or `-1` (JS `findIndex`).

Position of the first element that passes, or -1. -/
def findIdx {α : Type} (p : α → Bool) (xs : List α) : Int :=
  match xs.findIdx? p with
  | some i => i
  | none => -1

/-- Faithful (JS 12959-12961): with the nav root at `pointer-events: none`, `elementFromPoint` returns the first box
that is outside the nav or re-enabled inside it.

Which box the original's hit test returns. -/
def faithfulHit (stack : List Hit) : Int := findIdx (fun h => !h.insideNav || h.reEnabled) stack

/-- TS `firstOutside` (hit-skip as built): the first box outside the nav subtree.

Which box the TS hit-skip variant returns. -/
def firstOutside (insideNav : List Bool) : Int := findIdx (fun b => !b) insideNav

/-- v1 `nav-hit-test`: first box outside the nav, or inside an allow-listed (re-enabled) nav box.

The v1 fix: skip the nav's own boxes except the ones known to set `pointer-events` themselves. -/
def allowHit (allow : Hit → Bool) (stack : List Hit) : Int := findIdx (fun h => !h.insideNav || allow h) stack

#guard faithfulHit [⟨true, false⟩, ⟨false, false⟩] == 1
#guard firstOutside [true, false] == 1
#guard faithfulHit [⟨true, true⟩, ⟨false, false⟩] == 0
#guard firstOutside [true, false] == 1
#guard firstOutside [true, true] == -1
#guard firstOutside [] == -1

/-- Searching with two tests that agree on the list finds the same index. -/
theorem findIdx?_congr' {α : Type} (p q : α → Bool) (xs : List α) (h : ∀ x ∈ xs, p x = q x) :
    xs.findIdx? p = xs.findIdx? q := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
    simp only [List.findIdx?_cons, h x (by simp), ih (fun y hy => h y (by simp [hy]))]

/-- The same for the -1-defaulted search. -/
theorem findIdx_congr {α : Type} (p q : α → Bool) (xs : List α) (h : ∀ x ∈ xs, p x = q x) :
    findIdx p xs = findIdx q xs := by
  unfold findIdx
  rw [findIdx?_congr' p q xs h]

/-- **TS hit-skip = faithful** whenever no re-enabled nav box is at the probe point.

Skipping the whole nav subtree finds the same element as the original, unless the probe lands on the nav's
actions, the expanded morph panel, the active morph pill or the phone earn button. -/
theorem firstOutside_eq_faithful (stack : List Hit) (h : ∀ b ∈ stack, b.insideNav = true → b.reEnabled = false) :
    firstOutside (stack.map (·.insideNav)) = faithfulHit stack := by
  unfold firstOutside faithfulHit findIdx
  rw [List.findIdx?_map, findIdx?_congr' _ (fun h => !h.insideNav || h.reEnabled)]
  intro b hb
  have := h b hb
  cases hi : b.insideNav <;> simp_all

/-- The skip condition is needed: a re-enabled nav box on top makes the two answers differ.

Over the nav's actions the original reports the actions (not dark), the TS variant the section below. -/
theorem firstOutside_ne_faithful :
    firstOutside ([(⟨true, true⟩ : Hit), ⟨false, false⟩].map (·.insideNav)) ≠
      faithfulHit [⟨true, true⟩, ⟨false, false⟩] := by decide

/-- v1 `nav-hit-test` = faithful whenever its allow-list agrees with the re-enabled flag on the nav's boxes.

Allow-listing exactly the boxes that set `pointer-events` themselves reproduces the original's answer. -/
theorem allowHit_eq_faithful (allow : Hit → Bool) (stack : List Hit)
    (h : ∀ b ∈ stack, b.insideNav = true → allow b = b.reEnabled) :
    allowHit allow stack = faithfulHit stack := by
  unfold allowHit faithfulHit
  apply findIdx_congr
  intro b hb
  cases hi : b.insideNav <;> simp_all

/-! ## Visible class and the morph skip -/

/-- `is-on-dark` (JS 13228): the hit answer or morph strictly past 0.2.

Whether the nav renders in its dark style. -/
def isOnDark (hit : Bool) (morph : Rat) : Bool := hit || decide (morph > 1 / 5)

#guard isOnDark false (1/5) == false && isOnDark false (201/1000) == true && isOnDark true 0 == true

/-- **v1 hit-skip**: past morph 0.2 the hit answer is invisible, so skipping (keeping a stale `g`) changes nothing.

While the end morph stands past 0.2 the nav is dark whatever the hit test says. -/
theorem hitSkip_morph (g g' : Bool) (m : Rat) (hm : m > 1 / 5) :
    isOnDark g m = isOnDark g' m ∧ isOnDark g m = true := by
  unfold isOnDark; simp [hm]

/-- The expanded panel (re-enabled, morph `> 0.92`) never shows a difference: `is-on-dark` is already forced.

When the morph panel covers the probe, the classes do not depend on the hit test at all. -/
theorem expanded_masks (g : Bool) (m : Rat) (hm : m > 23 / 25) : isOnDark g m = true :=
  (hitSkip_morph g g m (by grind)).2

/-- Write on change only (TS `changed`; Svelte's equality-gated `set`).

Whether the stored hit answer must be written. -/
def changed (prev next : Bool) : Bool := prev != next

/-- Writing only on change ends in the same state as always writing.

Skipping equal writes never leaves a stale value. -/
theorem changed_write (p n : Bool) : (if changed p n then n else p) = n := by
  cases p <;> cases n <;> rfl

#guard changed true false == true && changed true true == false

end Fw.Parts.NavHitTest
