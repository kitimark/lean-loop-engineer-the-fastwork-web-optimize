import Fw.Engine.Core
import Fw.Engine.Chromium
import Fw.Engine.WebKit
/-!
# people.o: the "o" of "people" that opens into a row of faces (`faithful`)

Restated (not copied) from `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`, read independently of the TS part:

* 6214-6245 (`a`, `i`): when the heading enters the viewport (an `IntersectionObserver`, threshold `0.35`, JS 6252)
  the part sets `stack` after 1300 ms and `expanded` 120 ms after that; the `standalone` option (not used on the home
  page, kept for faithfulness) sets `stack` at once and `expanded` after 120 ms. Leaving the viewport clears both,
  unless reduced motion is on, in which case both are set at once, on entering and on leaving;
* 6190-6213 (`j`, `A`, `P`): hovering or focusing a face (only once `expanded`, and only wider than 860 px) opens a
  preview card at a position computed from the face's rect: width `min(320, w_v - 24)`, left centred and clamped into
  `[12, w_v - w - 12]`, top `12` px below the face, or `12` px above the 440 px card when it would not fit;
* CSS `assets/2.gBuqKVzi.css` 2429-2540: the `o` box is a one-column grid, `0.6042` em wide and `1.0417` em high,
  growing to `5.25` em and `1.0833` em when expanded (0.92 s); six faces of `1` em with margin-right `-1/6` em stack in
  a box `5.1667` em wide; the face with index `i` enters with a delay of `0.17 i` s when stacked but not expanded.

Times are whole ms (`Nat`); lengths are `Rat`.
-/
namespace Fw.Parts.PeopleO

/-! ## Timeline -/

/-- Delay from entering the viewport to the stack, in ms (JS 6236). -/
def stackDelay : Nat := 1300

/-- Delay from the stack to the expansion, in ms (JS 6229, 6238). -/
def expandDelay : Nat := 120

/-- Visibility threshold of the observer (JS 6252). -/
def threshold : Rat := 7 / 20

/-- The two flags `(stack, expanded)` `t` ms after the heading entered the viewport.

Reduced motion shows the opened row at once. -/
def phase (reduced standalone : Bool) (t : Nat) : Bool × Bool :=
  if reduced then (true, true)
  else if standalone then (true, decide (expandDelay ≤ t))
  else (decide (stackDelay ≤ t), decide (stackDelay + expandDelay ≤ t))

/-- `decide` of a Nat comparison is true iff the comparison holds. -/
theorem dle {a t : Nat} : decide (a ≤ t) = true ↔ a ≤ t := decide_eq_true_iff

#guard phase false false 0 == (false, false)
#guard phase false false 1299 == (false, false)
#guard phase false false 1300 == (true, false)
#guard phase false false 1419 == (true, false)
#guard phase false false 1420 == (true, true)
#guard phase false true 0 == (true, false)
#guard phase false true 120 == (true, true)
#guard phase true false 0 == (true, true)

/-- **Expanded implies stacked.** The faces never open before the stack shows. -/
theorem expanded_imp_stack (rm sa : Bool) (t : Nat) : (phase rm sa t).2 = true → (phase rm sa t).1 = true := by
  unfold phase
  split
  · simp
  · split <;> dsimp only <;> (try simp only [dle]) <;> (try simp only [stackDelay, expandDelay]) <;> first | omega | simp

/-- **Both flags are monotone in time.** Once on, they stay on until the heading leaves the viewport. -/
theorem phase_mono (rm sa : Bool) (t t' : Nat) (h : t ≤ t') :
    ((phase rm sa t).1 = true → (phase rm sa t').1 = true) ∧
    ((phase rm sa t).2 = true → (phase rm sa t').2 = true) := by
  unfold phase
  split
  · simp
  · split <;> dsimp only <;> refine ⟨?_, ?_⟩ <;> (try simp only [dle]) <;> (try simp only [stackDelay, expandDelay]) <;> first | omega | simp

/-- **Opening gap.** In the normal case (`rm = sa = ⊥`) the stack shows at `a = 1300` but not at
1299, and the row expands at `a + b = 1420` but not at 1419.

The row opens 120 ms after the stack shows. -/
theorem opening_gap :
    (phase false false stackDelay).1 = true ∧ (phase false false (stackDelay - 1)).1 = false ∧
    (phase false false (stackDelay + expandDelay)).2 = true ∧
    (phase false false (stackDelay + expandDelay - 1)).2 = false := by decide

/-- Leaving the viewport restores the closed row (normal motion): at time `0` of the next entry both flags are off. -/
theorem reenter_closed : phase false false 0 = (false, false) := by decide

/-- Under reduced motion the row is open at every instant. -/
theorem reduced_open (sa : Bool) (t : Nat) : phase true sa t = (true, true) := by simp [phase]

/-! ## Geometry (em) -/

/-- Width of the closed `o` in em (CSS 2434). -/
def closedWidth : Rat := 3021 / 5000

/-- Width of the opened `o` in em (CSS 2450). -/
def openWidth : Rat := 21 / 4

/-- Height of the closed `o` in em (CSS 2436). -/
def closedHeight : Rat := 10417 / 10000

/-- Height of the opened `o` in em (CSS 2451). -/
def openHeight : Rat := 10833 / 10000

/-- Face diameter in em (CSS 2530). -/
def faceSize : Rat := 1

/-- Negative overlap between faces in em (CSS 2535). -/
def faceOverlap : Rat := 1 / 6

/-- Number of faces (the six professions). -/
def faces : Nat := 6

/-- Offset of the stack inside the stage in em (CSS 2512). -/
def stackLeft : Rat := 417 / 10000

/-- Width of the stack of faces in em: `k` faces, the last without the negative margin. -/
def stackWidth : Rat := faces * faceSize - (faces - 1) * faceOverlap

/-- **The stack is 5.1667 em wide.** The CSS declares `width: 5.1667em` for the stack. -/
theorem stack_width_value : stackWidth = 31 / 6 ∧ stackWidth - 51667 / 10000 < 1 / 10000 ∧ 51667 / 10000 - stackWidth < 1 / 10000 := by
  unfold stackWidth faces faceSize faceOverlap
  grind

/-- **The opened row fits its grid column.** The stack plus its left offset is inside the `5.25` em column.

So the faces are never clipped once expanded. -/
theorem stack_fits_open : stackLeft + stackWidth ≤ openWidth := by
  unfold stackLeft stackWidth openWidth faces faceSize faceOverlap
  grind

/-- Opening makes the box wider and taller. -/
theorem opens_larger : closedWidth < openWidth ∧ closedHeight < openHeight := by
  unfold closedWidth openWidth closedHeight openHeight
  grind

/-- Entry delay of face `i` when stacked but not expanded, in ms (CSS 2551). -/
def faceDelay (i : Nat) : Nat := 170 * i

/-- Last face's delay. Ms: the faces appear one after another over 0.85 s. -/
theorem last_face_delay : faceDelay (faces - 1) = 850 := by decide

/-! ## Preview card position -/

/-- Card width for a viewport of width `w_v` (JS 6192). -/
def cardWidth (vw : Rat) : Rat := min 320 (vw - 24)

/-- Card height used for the flip test, in px (JS 6196). -/
def cardHeight : Rat := 440

/-- Card left edge for a face rect with left `x` and width `s` (JS 6193-6194). -/
def cardLeft (vw x s : Rat) : Rat :=
  max 12 (min (x + s / 2 - cardWidth vw / 2) (vw - cardWidth vw - 12))

/-- Card top for a face rect with top `y` and bottom `z` (JS 6195-6197). -/
def cardTop (vh y z : Rat) : Rat :=
  if vh - 12 < z + 12 + cardHeight then max 12 (y - 12 - cardHeight) else z + 12

/-- **The card stays inside the viewport horizontally.** For any face position the card keeps 12 px from both sides. -/
theorem card_inside_x (vw x s : Rat) :
    12 ≤ cardLeft vw x s ∧ cardLeft vw x s + cardWidth vw ≤ vw - 12 := by
  unfold cardLeft cardWidth
  constructor
  · grind
  · grind

/-- **The card keeps 12 px from the top** when the face bottom `z` is not above the viewport top. -/
theorem card_top_ge (vh y z : Rat) (h : 12 ≤ z + 12) : 12 ≤ cardTop vh y z := by
  unfold cardTop
  split <;> grind

/-- **Below when it fits.** If the card fits under the face it opens 12 px under it. -/
theorem card_below (vh y z : Rat) (h : z + 12 + cardHeight ≤ vh - 12) : cardTop vh y z = z + 12 := by
  unfold cardTop
  grind

#guard cardLeft 1280 400 56 == 400 + 28 - 160
#guard cardLeft 1280 0 56 == 12
#guard cardLeft 1280 1270 56 == 1280 - 320 - 12
#guard cardTop 900 50 90 == 102
#guard cardTop 900 600 640 == 600 - 12 - 440

/-! ## The FLIP variant's work inside the transition (ledger n=18)

The original opens the `o` by a 0.92 s CSS transition of `grid-template-columns` and `height`: every frame strictly
inside the transition carries one main-thread size change `oc` and no script. The FLIP variant (people-gpu) sets the
final size once and moves the parts with `m` compositor translate animations, so a frame inside the motion carries no
main-thread change and no script, only the `m` running animations. Both frames are stated over any engine `E` of
`Fw.Engine.Core`; the premises on `E` are hypotheses, not a table lookup.

Layout leaves this part's frame strictly inside the transition (part alone; on the page a layout pass is saved only
if no other part touches layout, `Compose.passes_absorb_part`).

Not covered: the first and last frames (where FLIP pays the size change and the cleanup), resident layers (the
spans' transient composited layers, ledger `claim_ne_dominates_of_layers`) and pixels (class L). -/

section Flip

open Fw.Engine (Stage Change FrameIn Engine Work frameWork touched stageUnits forcedPasses)

/-- Length of the open transition in ms (CSS 2450, `0.92s`). -/
def openMs : Nat := 920

/-- The original's frame strictly inside the transition: one main-thread change `oc` (the animated grid size), no
script, no forced passes, no hit tests, no compositor animation. -/
def origMid {P : Type} (oc : Change P) : FrameIn P := ⟨0, 0, 0, 0, [oc], 0⟩

/-- The FLIP variant's frame strictly inside the motion: no main-thread change, no script, `m` running compositor
animations (the translated parts). -/
def flipMid {P : Type} (m : Nat) : FrameIn P := ⟨0, 0, 0, 0, [], m⟩

/-- **The FLIP frame pays only the compositor-animation stages.** Its passes are one on each stage of
`E.compStages` when an animation runs, its units are `m` on those stages, zero elsewhere, and no hit tests.

Nothing runs on the main thread while the parts slide. -/
theorem flipMid_work {P M : Type} (E : Engine P M) (m : Nat) (s : Stage) :
    (frameWork E (flipMid (P := P) m)).passes s = (if 0 < m ∧ s ∈ E.compStages then 1 else 0) ∧
      (frameWork E (flipMid (P := P) m)).units s = (if s ∈ E.compStages then m else 0) ∧
      (frameWork E (flipMid (P := P) m)).hits = 0 := by
  refine ⟨?_, ?_, rfl⟩
  · simp only [frameWork, touched, flipMid, FrameIn.updates, forcedPasses]
    by_cases hm : 0 < m <;> by_cases hs : s ∈ E.compStages <;> cases s <;> simp_all
  · simp only [frameWork, stageUnits, flipMid]
    cases s <;> simp

/-- **The original frame pays the size change's stages and the base stages.** One pass on each stage the change
dirties or the engine pays per updating frame, one unit on each stage the change dirties, no hit tests.

The grid transition runs style, layout and everything after it each frame. -/
theorem origMid_work {P M : Type} (E : Engine P M) (oc : Change P) (s : Stage) :
    (frameWork E (origMid oc)).passes s = (if s ∈ E.stagesOf oc ∨ s ∈ E.base then 1 else 0) ∧
      (frameWork E (origMid oc)).units s = (if s ∈ E.stagesOf oc then 1 else 0) ∧
      (frameWork E (origMid oc)).hits = 0 := by
  refine ⟨?_, ?_, rfl⟩
  · simp only [frameWork, touched, origMid, FrameIn.updates, forcedPasses]
    cases s <;> simp
  · simp only [frameWork, stageUnits, origMid]
    cases s <;> simp [List.countP_cons]

/-- **Main-thread work falls inside the motion.** On every stage outside the compositor-animation stages the FLIP
frame does at most the original's passes and units (it does none), and when `layout` is dirtied by the size change but
is not a compositor-animation stage, the FLIP frame has strictly fewer layout passes.

Layout leaves this part's frame strictly inside the transition (part alone; on the page a layout pass is saved only
if no other part touches layout, `Compose.passes_absorb_part`). -/
theorem flip_main_lt {P M : Type} (E : Engine P M) (oc : Change P) (m : Nat)
    (hL : Stage.layout ∈ E.stagesOf oc) (hLc : Stage.layout ∉ E.compStages) :
    (∀ s, s ∉ E.compStages →
      (frameWork E (flipMid (P := P) m)).passes s ≤ (frameWork E (origMid oc)).passes s ∧
      (frameWork E (flipMid (P := P) m)).units s ≤ (frameWork E (origMid oc)).units s) ∧
    (frameWork E (flipMid (P := P) m)).passes .layout = 0 ∧ (frameWork E (origMid oc)).passes .layout = 1 := by
  refine ⟨fun s hs => ?_, ?_, ?_⟩
  · obtain ⟨v1, v2, -⟩ := flipMid_work (P := P) E m s
    rw [v1, v2]
    simp [hs]
  · rw [(flipMid_work (P := P) E m .layout).1]
    simp [hLc]
  · rw [(origMid_work E oc .layout).1]
    simp [hL]

/-- **FLIP is not below the original in Core's order (a trade).** If an animation runs and some compositor-animation
stage is neither dirtied by the size change nor a base stage, the FLIP frame is not `≼` the original frame:
it pays a pass there that the original does not.

Both engine tables have such a stage (`comp`) for the height change: the `#guard` lines after this theorem check
the refutation on `Fw.Engine.Chromium.chromium` (`height`) and `Fw.Engine.WebKit.webkit` (`size`). So `flip_work_lt`
as `≺` is false there; the variant trades compositor work for main-thread work. -/
theorem flip_not_le {P M : Type} (E : Engine P M) (oc : Change P) (m : Nat) (s : Stage) (hm : 0 < m)
    (hs : s ∈ E.compStages) (hso : s ∉ E.stagesOf oc) (hsb : s ∉ E.base) :
    ¬ (frameWork E (flipMid (P := P) m)).le (frameWork E (origMid oc)) := by
  intro h
  have h1 := (h.1 s).1
  rw [(flipMid_work (P := P) E m s).1, (origMid_work E oc s).1] at h1
  simp [hm, hs, hso, hsb] at h1

#guard !(frameWork Fw.Engine.Chromium.chromium (flipMid 1)).leb
  (frameWork Fw.Engine.Chromium.chromium (origMid ⟨0, .css .height, .none⟩))
#guard !(frameWork Fw.Engine.WebKit.webkit (flipMid 1)).leb
  (frameWork Fw.Engine.WebKit.webkit (origMid ⟨0, .size, .none⟩))

/-- **When FLIP is strictly below.** If every compositor-animation stage is dirtied by the size change, at most one
animation runs, and `layout` is dirtied by the size change but is not a compositor-animation stage, the FLIP frame is
`≺` the original frame.

These are the conditions the ledger's `flip_work_lt` needs. -/
theorem flip_lt_of_comp_sub {P M : Type} (E : Engine P M) (oc : Change P) (m : Nat) (hm : m ≤ 1)
    (hc : ∀ s ∈ E.compStages, s ∈ E.stagesOf oc) (hL : Stage.layout ∈ E.stagesOf oc)
    (hLc : Stage.layout ∉ E.compStages) :
    (frameWork E (flipMid (P := P) m)).lt (frameWork E (origMid oc)) := by
  refine ⟨⟨fun s => ?_, Nat.zero_le _⟩, ?_⟩
  · obtain ⟨v1, v2, -⟩ := flipMid_work (P := P) E m s
    obtain ⟨o1, o2, -⟩ := origMid_work E oc s
    rw [v1, v2, o1, o2]
    by_cases hs : s ∈ E.compStages
    · have := hc s hs
      by_cases h0 : 0 < m <;> simp [hs, this, h0] <;> omega
    · simp [hs]
  · refine Or.inl ⟨.layout, Or.inl ?_⟩
    rw [(flipMid_work (P := P) E m .layout).1, (origMid_work E oc .layout).1]
    simp [hL, hLc]

/-- A stage table restating the Chromium `layoutFull` row with one compositor stage `comp` and base `props`, for the
examples below. -/
def layoutTable : Engine Unit Unit :=
  ⟨(), fun _ => [.style, .layout, .props, .paint, .raster, .commit], [.comp], [.props]⟩

/-- The example size change. -/
def oc0 : Change Unit := ⟨0, (), .none⟩

#guard (frameWork layoutTable (flipMid (P := Unit) 3)).passes .layout == 0
#guard (frameWork layoutTable (origMid oc0)).passes .layout == 1
#guard (frameWork layoutTable (flipMid (P := Unit) 3)).units .comp == 3
#guard (frameWork layoutTable (origMid oc0)).passes .comp == 0
#guard !(frameWork layoutTable (flipMid (P := Unit) 1)).leb (frameWork layoutTable (origMid oc0))
#guard (frameWork layoutTable (flipMid (P := Unit) 0)).ltb (frameWork layoutTable (origMid oc0))

end Flip

end Fw.Parts.PeopleO
