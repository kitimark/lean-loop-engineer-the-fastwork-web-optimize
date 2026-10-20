import Lean.Data.Json
import Fw.Gate.Pixel
import Fw.Gate.Settle

/-!
# The drawn-size image arm, judged part by part (task image-arm-v2)

Task image-audit closed "a pixel-identical copy at the drawn size" as a measured negative finding: a copy is resampled by the
tool that made it and then again by the browser, so the page differs from the original at every edge (two stages). This module
re-plans the arm on two questions, both pure.

**Q1, is a copy drawn 1:1 reachable?** A draw whose destination rectangle is a whole number of device pixels, at the copy's own
pixel size, resamples nothing: the browser's second stage vanishes and the page differs from the original only by the copy tool's
one stage. Engine facts (CONFIRMED, source read): Chromium snaps the destination rectangle of an `<img>` to device pixels
(`third_party/blink/renderer/core/paint/image_painter.cc:210,224,228-235@f842f52`) and hands the picture to Skia, whose shader
turns a bilinear sample into a nearest one when the matrix is an integer translation (`src/shaders/SkImageShader.cpp:472-483@95ee33d7`,
Skia as pinned by Chromium's `DEPS`); WebKit snaps with `snapRectToDevicePixels`
(`Source/WebCore/rendering/RenderImage.cpp:569,693,774-808@862f17d`) and its Skia port draws through the same shader rule
(`Source/WebCore/platform/graphics/skia/GraphicsContextSkia.cpp:188-201,229-295@862f17d`); Apple WebKit hands the draw to CoreGraphics
(closed source: "1:1 draws nothing" is INFERRED there). The snapped size of a rectangle depends on where it sits
(`snapSize_position_dependent`), except when its size is a whole number of device pixels (`snapSize_shift`): that is the only
size a single copy can match wherever the image is. So a copy is reachable only for an `<img>` (`Why.notImg`) that fills its box
(`Why.cropped`), under no scale (`Why.scaled`), of whole device-pixel size (`Why.fractional`), and smaller than the file
(`Why.noSaving`); `exact_copy_is_snapped_size` proves the copy then equals the snapped size at every position. Every other image
has no 1:1 copy: its drawn size moves with a transform or with the position, so any copy is resampled twice.

**Q2, which parts may take copies?** Each part is judged on its own: one cell is one (engine, probe width, DPR, rep) with the
visual-diff verdict (`Fw.Gate.Pixel.Verdict`, PL tolerance) of the part with the original files (`base`) and with the part's
copies (`drawn`). `partDecision` is `admissible` only when there is a cell and every cell passes
(`partDecision_admissible_iff`); a failing cell can never be pooled away (`append_fail_not_admissible`). A fail where the
baseline passed is a look change (`lookChange`), which the lead puts in the user's review queue; a fail where the baseline did not
pass is `shippedFails`; any other missing pass (unsettled, invalid, nc, an error cell) is `undecided`.

The TS twin is `packages/gate-breakpoints/src/images/armplan.mjs`, checked against `goldenText`
(`packages/contracts/golden/measure/image-arm.jsonl`). Sizes are milli-CSS-pixels, DPR a whole number, so no float enters a decision.
-/
namespace Fw.Measure.ImageArm
open Lean Fw.Gate.Pixel

/-! ## Snapping -/

/-- A device edge: milli-CSS-pixels times the DPR, rounded half up to a device pixel. -/
def snapEdge (dpr m : Nat) : Nat := (m * dpr + 500) / 1000

/-- The snapped device width of a rectangle from `left` to `right`. -/
def snapSize (dpr left right : Nat) : Nat := snapEdge dpr right - snapEdge dpr left

/-- A milli-CSS-pixel size is a whole number of device pixels at `dpr`. -/
def integral (dpr m : Nat) : Bool := m * dpr % 1000 == 0

theorem snapEdge_mono (dpr : Nat) {a b : Nat} (h : a ≤ b) : snapEdge dpr a ≤ snapEdge dpr b :=
  Nat.div_le_div_right (Nat.add_le_add_right (Nat.mul_le_mul_right dpr h) 500)

/-- A rectangle whose size is whole device pixels snaps to that size wherever its left edge is. -/
theorem snapSize_shift (dpr l w : Nat) (h : integral dpr w = true) : snapSize dpr l (l + w) = w * dpr / 1000 := by
  have h1 : w * dpr % 1000 = 0 := by simpa [integral] using h
  obtain ⟨k, hk⟩ : 1000 ∣ w * dpr := Nat.dvd_of_mod_eq_zero h1
  have e : (l + w) * dpr + 500 = (l * dpr + 500) + 1000 * k := by rw [Nat.add_mul, hk]; omega
  have hq : w * dpr / 1000 = k := by rw [hk]; exact Nat.mul_div_cancel_left k (by decide)
  unfold snapSize snapEdge
  rw [e, Nat.add_mul_div_left _ _ (by decide), hq]
  omega

/-- Otherwise the snapped size depends on the position: 1.5 device pixels snap to 2 at the origin and to 1 half a pixel on (DPR 1);
the same at DPR 3 for half a CSS pixel. -/
theorem snapSize_position_dependent :
    (snapSize 1 0 1500 = 2 ∧ snapSize 1 500 2000 = 1) ∧ (snapSize 3 0 500 = 2 ∧ snapSize 3 333 833 = 1) := by decide

/-! ## Reachability of a 1:1 copy -/

/-- Which kind of thing draws the image: an `<img>` or a CSS image. -/
inductive Kind where
  | img | bg
deriving DecidableEq, Repr

/-- One image as the part draws it. Sizes in milli-CSS-pixels: `w`, `h` the rectangle the picture is drawn into on screen;
`plain` the picture fills its box (no object-fit crop or letterbox, no size taken from the natural size); `scaleMin`, `scaleMax`
the least and the greatest visual scale of its transform chain over every reading (1000 = none). -/
structure Img where
  kind : Kind
  natW : Nat
  natH : Nat
  w : Nat
  h : Nat
  plain : Bool
  scaleMin : Nat
  scaleMax : Nat
deriving DecidableEq, Repr

/-- The device width the picture is drawn at, when its size is whole device pixels. -/
def devW (dpr : Nat) (i : Img) : Nat := i.w * dpr / 1000
/-- The device height. -/
def devH (dpr : Nat) (i : Img) : Nat := i.h * dpr / 1000

/-- A copy at the device size is a smaller image: positive, at most the file in each side, smaller in one. -/
def smaller (dpr : Nat) (i : Img) : Bool :=
  decide (0 < devW dpr i ∧ 0 < devH dpr i ∧ devW dpr i ≤ i.natW ∧ devH dpr i ≤ i.natH ∧ (devW dpr i < i.natW ∨ devH dpr i < i.natH))

/-- Why an image has or has no 1:1 copy; the first reason that holds, in this order. -/
inductive Why where
  | ok | notImg | cropped | scaled | fractional | noSaving
deriving DecidableEq, Repr

/-- The reason an image has or has no 1:1 copy at `dpr`. -/
def reachWhy (dpr : Nat) (i : Img) : Why :=
  if i.kind ≠ .img then .notImg
  else if i.plain = false then .cropped
  else if i.scaleMin ≠ 1000 ∨ i.scaleMax ≠ 1000 then .scaled
  else if ¬ (integral dpr i.w = true ∧ integral dpr i.h = true) then .fractional
  else if smaller dpr i = false then .noSaving
  else .ok

/-- The `exact` copy of one image: its snapped device size, or none. -/
def exactCopy (dpr : Nat) (i : Img) : Option (Nat × Nat) :=
  if reachWhy dpr i = .ok then some (devW dpr i, devH dpr i) else none

/-- A CSS image has no 1:1 copy (its positioning area is not an `<img>` rectangle the engine snaps alone). -/
theorem reach_notImg (dpr : Nat) (i : Img) (h : i.kind = .bg) : reachWhy dpr i = .notImg := by
  simp [reachWhy, h]

/-- A cropped or letterboxed picture has no 1:1 copy. -/
theorem reach_cropped (dpr : Nat) (i : Img) (h1 : i.kind = .img) (h2 : i.plain = false) : reachWhy dpr i = .cropped := by
  simp [reachWhy, h1, h2]

/-- A picture under a scale has no 1:1 copy. -/
theorem reach_scaled (dpr : Nat) (i : Img) (h1 : i.kind = .img) (h2 : i.plain = true) (h3 : i.scaleMin ≠ 1000 ∨ i.scaleMax ≠ 1000) :
    reachWhy dpr i = .scaled := by
  simp [reachWhy, h1, h2, h3]

/-- A picture of fractional device size has no 1:1 copy. -/
theorem reach_fractional (dpr : Nat) (i : Img) (h1 : i.kind = .img) (h2 : i.plain = true) (h3 : i.scaleMin = 1000) (h4 : i.scaleMax = 1000)
    (h5 : ¬ (integral dpr i.w = true ∧ integral dpr i.h = true)) : reachWhy dpr i = .fractional := by
  simp [reachWhy, h1, h2, h3, h4, h5]

/-- A picture the copy would not make smaller has no copy. -/
theorem reach_noSaving (dpr : Nat) (i : Img) (h1 : i.kind = .img) (h2 : i.plain = true) (h3 : i.scaleMin = 1000) (h4 : i.scaleMax = 1000)
    (h5 : integral dpr i.w = true ∧ integral dpr i.h = true) (h6 : smaller dpr i = false) : reachWhy dpr i = .noSaving := by
  have h5' : ¬ ¬ (integral dpr i.w = true ∧ integral dpr i.h = true) := fun hn => hn h5
  simp [reachWhy, h1, h2, h3, h4, h5', h6]

/-- An image has a 1:1 copy exactly when every reason against it fails. -/
theorem reach_ok_iff (dpr : Nat) (i : Img) :
    reachWhy dpr i = .ok ↔ i.kind = .img ∧ i.plain = true ∧ i.scaleMin = 1000 ∧ i.scaleMax = 1000 ∧
      integral dpr i.w = true ∧ integral dpr i.h = true ∧ smaller dpr i = true := by
  unfold reachWhy
  by_cases a : i.kind = .img <;> by_cases b : i.plain = true <;> by_cases c : i.scaleMin = 1000 <;> by_cases d : i.scaleMax = 1000 <;>
    by_cases e : integral dpr i.w = true <;> by_cases f : integral dpr i.h = true <;> by_cases g : smaller dpr i = true <;>
    simp_all

/-- The central 1:1 statement: the copy of an image that has one is the snapped device size of its rectangle at every
position, in width and in height. -/
theorem exact_copy_is_snapped_size (dpr : Nat) (i : Img) (c : Nat × Nat) (hc : exactCopy dpr i = some c) :
    (∀ l, snapSize dpr l (l + i.w) = c.1) ∧ (∀ t, snapSize dpr t (t + i.h) = c.2) := by
  unfold exactCopy at hc
  by_cases hr : reachWhy dpr i = .ok
  · simp only [hr, ↓reduceIte] at hc
    have := (reach_ok_iff dpr i).1 hr
    have hcc : (devW dpr i, devH dpr i) = c := Option.some.inj hc
    subst hcc
    exact ⟨fun l => snapSize_shift dpr l i.w this.2.2.2.2.1, fun t => snapSize_shift dpr t i.h this.2.2.2.2.2.1⟩
  · simp only [hr, ↓reduceIte] at hc
    exact absurd hc (by simp)

/-- A copy is a strictly smaller image than the file: it saves decoded bytes. -/
theorem exact_copy_smaller (dpr : Nat) (i : Img) (c : Nat × Nat) (hc : exactCopy dpr i = some c) :
    0 < c.1 ∧ 0 < c.2 ∧ c.1 ≤ i.natW ∧ c.2 ≤ i.natH ∧ (c.1 < i.natW ∨ c.2 < i.natH) := by
  unfold exactCopy at hc
  by_cases hr : reachWhy dpr i = .ok
  · simp only [hr, ↓reduceIte] at hc
    have := (reach_ok_iff dpr i).1 hr
    have hcc : (devW dpr i, devH dpr i) = c := Option.some.inj hc
    subst hcc
    simpa [smaller] using this.2.2.2.2.2.2
  · simp only [hr, ↓reduceIte] at hc
    exact absurd hc (by simp)

/-! ## One file, several elements -/

/-- The `exact` copy of a file drawn by the elements `i` and `rest`: the one copy size they all agree on, else none (one file
cannot be two sizes). -/
def exactFile (dpr : Nat) (i : Img) (rest : List Img) : Option (Nat × Nat) :=
  match exactCopy dpr i with
  | none => none
  | some c => if rest.all (fun j => exactCopy dpr j == some c) then some c else none

/-- A file's `exact` copy is the `exact` copy of every element that draws it. -/
theorem exactFile_agrees (dpr : Nat) (i : Img) (rest : List Img) (c : Nat × Nat) (h : exactFile dpr i rest = some c) :
    ∀ j ∈ i :: rest, exactCopy dpr j = some c := by
  unfold exactFile at h
  cases hc : exactCopy dpr i with
  | none => rw [hc] at h; simp at h
  | some c' =>
    rw [hc] at h
    dsimp only at h
    by_cases hall : rest.all (fun j => exactCopy dpr j == some c') = true
    · simp only [hall, ↓reduceIte] at h
      have hcc : c' = c := Option.some.inj h
      subst hcc
      intro j hj
      rcases List.mem_cons.1 hj with rfl | hj
      · exact hc
      · have := List.all_eq_true.1 hall j hj
        simpa using this
    · simp only [hall] at h
      simp at h

/-! ## The control policy: every image at its largest drawn size

`fit` copies every image at the device size of its largest drawn rectangle (scale and DPR included), at the file's own aspect
ratio. Any scaled image drawn from it is resampled twice, so it is the control that shows what the two-stage resampling costs. -/

/-- The least integer at least `n / d`. -/
def ceilDiv (n d : Nat) : Nat := (n + d - 1) / d

/-- Device width an image needs: `w` milli-CSS-pixels, scaled by the largest visual scale (at least 1) and the DPR, rounded up. -/
def needW (dpr : Nat) (i : Img) : Nat := ceilDiv (i.w * (max i.scaleMax 1000) * dpr) 1000000

/-- The copy height at the file's aspect ratio for width `w`, at least one pixel. -/
def aspectH (natW natH w : Nat) : Nat := max 1 ((w * natH * 2 + natW) / (2 * natW))

/-- The `fit` copy of one image: its need at the file's aspect ratio, or none when that does not make the file smaller. -/
def fitCopy (dpr : Nat) (i : Img) : Option (Nat × Nat) :=
  if 0 < i.natW ∧ 0 < needW dpr i ∧ needW dpr i < i.natW then some (needW dpr i, aspectH i.natW i.natH (needW dpr i)) else none

/-- The greatest of a list of numbers. -/
def maxOf (l : List Nat) : Nat := l.foldr max 0

theorem le_maxOf {x : Nat} {l : List Nat} (h : x ∈ l) : x ≤ maxOf l := by
  induction l with
  | nil => simp at h
  | cons a rest ih =>
    rcases List.mem_cons.1 h with rfl | h
    · exact Nat.le_max_left _ _
    · exact Nat.le_trans (ih h) (Nat.le_max_right _ _)

/-- The `fit` copy of a file drawn by the elements `i` and `rest`: the need of the greatest, at the file's aspect ratio. -/
def fitFile (dpr : Nat) (i : Img) (rest : List Img) : Option (Nat × Nat) :=
  if 0 < i.natW ∧ 0 < maxOf ((i :: rest).map (needW dpr)) ∧ maxOf ((i :: rest).map (needW dpr)) < i.natW then
    some (maxOf ((i :: rest).map (needW dpr)), aspectH i.natW i.natH (maxOf ((i :: rest).map (needW dpr))))
  else none

/-- A `fit` copy is wide enough for every element that draws the file. -/
theorem fitFile_covers (dpr : Nat) (i : Img) (rest : List Img) (c : Nat × Nat) (h : fitFile dpr i rest = some c) :
    ∀ j ∈ i :: rest, needW dpr j ≤ c.1 := by
  intro j hj
  unfold fitFile at h
  by_cases hc : 0 < i.natW ∧ 0 < maxOf ((i :: rest).map (needW dpr)) ∧ maxOf ((i :: rest).map (needW dpr)) < i.natW
  · simp only [hc] at h
    have hcc := Option.some.inj h
    rw [← hcc]
    exact le_maxOf (List.mem_map.2 ⟨j, hj, rfl⟩)
  · simp only [hc, ↓reduceIte] at h
    simp at h

/-! ## Decoded memory -/

/-- Decoded bytes of a `w` by `h` image: four bytes a pixel (RGBA, the accepted limit: decode memory only, no frame time). -/
def decoded (w h : Nat) : Nat := 4 * w * h

/-- The decoded bytes a copy of `cw` by `ch` saves over the file `nw` by `nh`. -/
def saving (nw nh cw ch : Nat) : Nat := decoded nw nh - decoded cw ch

/-- The saving plus what the copy decodes is what the file decodes, when the copy has no more pixels. -/
theorem saving_add (nw nh cw ch : Nat) (h : cw * ch ≤ nw * nh) : saving nw nh cw ch + decoded cw ch = decoded nw nh := by
  unfold saving decoded
  have : 4 * cw * ch ≤ 4 * nw * nh := by
    have := Nat.mul_le_mul_left 4 h
    simpa [Nat.mul_assoc] using this
  omega

/-- A copy that is at most the file in each side never saves a negative amount, and saves something when one side is smaller. -/
theorem saving_pos (nw nh cw ch : Nat) (h1 : cw ≤ nw) (h2 : ch ≤ nh) (h3 : 0 < cw) (h4 : 0 < ch) (h5 : cw < nw ∨ ch < nh) :
    0 < saving nw nh cw ch := by
  unfold saving decoded
  have hlt : cw * ch < nw * nh := by
    rcases h5 with h | h
    · calc cw * ch < nw * ch := Nat.mul_lt_mul_of_pos_right h h4
        _ ≤ nw * nh := Nat.mul_le_mul_left nw h2
    · calc cw * ch < cw * nh := Nat.mul_lt_mul_of_pos_left h h3
        _ ≤ nw * nh := Nat.mul_le_mul_right nh h1
  have := Nat.mul_lt_mul_of_pos_left hlt (by decide : 0 < 4)
  simp only [Nat.mul_assoc]
  omega

/-- The decoded bytes an `exact` copy saves for one file, 0 when it has none. -/
def exactSaving (dpr : Nat) (i : Img) (rest : List Img) : Nat :=
  match exactFile dpr i rest with
  | some c => saving i.natW i.natH c.1 c.2
  | none => 0

/-- The decoded bytes of a part: the sum over its files. -/
def partSaving (dpr : Nat) (files : List (Img × List Img)) : Nat := (files.map (fun f => exactSaving dpr f.1 f.2)).sum

/-! ## The decision of a part -/

/-- One cell: the verdict of the part with the original files (`base`) and with its copies (`drawn`); `none` is an error cell
(the run produced no verdict). -/
structure Cell where
  base : Option Verdict
  drawn : Option Verdict
deriving DecidableEq, Repr

/-- The decision about a part's copies. -/
inductive Decision where
  | admissible   -- every cell passes: equal-look within the PL tolerance at every engine, width and DPR
  | lookChange   -- a cell passes with the original files and fails with the copies: the copies change the look
  | shippedFails -- a cell fails with the copies, and none of the failing cells passed with the original files
  | undecided    -- no cell fails, but not every cell passes (unsettled, invalid, nc, an error cell), or there is no cell
deriving DecidableEq, Repr

/-- The copies change the look in this cell. -/
def Cell.regresses (c : Cell) : Bool := c.drawn == some .fail && c.base == some .pass

/-- The decision from three facts about the cells: some cell regresses, some cell fails, some cell is not a pass (or none exists). -/
def decisionOf (regress fails notPass : Bool) : Decision :=
  if regress then .lookChange else if fails then .shippedFails else if notPass then .undecided else .admissible

/-- The decision of a part from its cells, each cell on its own (no pooled count or ratio). -/
def partDecision (cs : List Cell) : Decision :=
  decisionOf (cs.any Cell.regresses) (cs.any (fun c => c.drawn == some .fail)) (cs.isEmpty || cs.any (fun c => c.drawn != some .pass))

theorem any_regresses (cs : List Cell) :
    cs.any Cell.regresses = true ↔ ∃ c ∈ cs, c.drawn = some .fail ∧ c.base = some .pass := by
  simp [List.any_eq_true, Cell.regresses]

theorem any_fails (cs : List Cell) : cs.any (fun c => c.drawn == some .fail) = true ↔ ∃ c ∈ cs, c.drawn = some .fail := by
  simp [List.any_eq_true]

theorem any_notPass (cs : List Cell) :
    (cs.isEmpty || cs.any (fun c => c.drawn != some .pass)) = true ↔ cs = [] ∨ ∃ c ∈ cs, c.drawn ≠ some .pass := by
  simp [List.any_eq_true]

theorem bool_false_iff {b : Bool} {P : Prop} (h : b = true ↔ P) : b = false ↔ ¬ P := by
  cases b <;> simp_all

theorem decisionOf_lookChange_iff (a b c : Bool) : decisionOf a b c = .lookChange ↔ a = true := by
  cases a <;> cases b <;> cases c <;> simp [decisionOf]

theorem decisionOf_shippedFails_iff (a b c : Bool) : decisionOf a b c = .shippedFails ↔ a = false ∧ b = true := by
  cases a <;> cases b <;> cases c <;> simp [decisionOf]

theorem decisionOf_undecided_iff (a b c : Bool) : decisionOf a b c = .undecided ↔ a = false ∧ b = false ∧ c = true := by
  cases a <;> cases b <;> cases c <;> simp [decisionOf]

theorem decisionOf_admissible_iff (a b c : Bool) : decisionOf a b c = .admissible ↔ a = false ∧ b = false ∧ c = false := by
  cases a <;> cases b <;> cases c <;> simp [decisionOf]

/-- A cell fails with the copies where the baseline passed. -/
theorem partDecision_lookChange_iff (cs : List Cell) :
    partDecision cs = .lookChange ↔ ∃ c ∈ cs, c.drawn = some .fail ∧ c.base = some .pass := by
  unfold partDecision
  rw [decisionOf_lookChange_iff, any_regresses]

/-- Some cell fails with the copies, and none of them passed with the original files. -/
theorem partDecision_shippedFails_iff (cs : List Cell) :
    partDecision cs = .shippedFails ↔
      (∃ c ∈ cs, c.drawn = some .fail) ∧ ¬ ∃ c ∈ cs, c.drawn = some .fail ∧ c.base = some .pass := by
  unfold partDecision
  rw [decisionOf_shippedFails_iff, bool_false_iff (any_regresses cs), any_fails]
  exact and_comm

/-- No cell fails, and there is no cell or one is not a pass. -/
theorem partDecision_undecided_iff (cs : List Cell) :
    partDecision cs = .undecided ↔
      (¬ ∃ c ∈ cs, c.drawn = some .fail) ∧ (cs = [] ∨ ∃ c ∈ cs, c.drawn ≠ some .pass) := by
  unfold partDecision
  rw [decisionOf_undecided_iff, bool_false_iff (any_regresses cs), bool_false_iff (any_fails cs), any_notPass]
  constructor
  · rintro ⟨_, h2, h3⟩
    exact ⟨h2, h3⟩
  · rintro ⟨h2, h3⟩
    exact ⟨fun ⟨c, hc, h1, _⟩ => h2 ⟨c, hc, h1⟩, h2, h3⟩

/-- The only way to be admissible: there is a cell and every cell passes. -/
theorem partDecision_admissible_iff (cs : List Cell) :
    partDecision cs = .admissible ↔ cs ≠ [] ∧ ∀ c ∈ cs, c.drawn = some .pass := by
  unfold partDecision
  rw [decisionOf_admissible_iff, bool_false_iff (any_regresses cs), bool_false_iff (any_fails cs), bool_false_iff (any_notPass cs)]
  constructor
  · rintro ⟨_, _, h3⟩
    exact ⟨fun e => h3 (Or.inl e), fun c hc => Classical.byContradiction fun hn => h3 (Or.inr ⟨c, hc, hn⟩)⟩
  · rintro ⟨hne, hp⟩
    refine ⟨fun ⟨c, hc, h1, _⟩ => ?_, fun ⟨c, hc, h1⟩ => ?_, fun h => h.elim hne fun ⟨c, hc, hn⟩ => hn (hp c hc)⟩
    · rw [hp c hc] at h1
      exact absurd h1 (by decide)
    · rw [hp c hc] at h1
      exact absurd h1 (by decide)

/-- A failing cell is never pooled away: adding one to any part makes it not admissible. -/
theorem append_fail_not_admissible (cs : List Cell) (b : Option Verdict) :
    partDecision (cs ++ [⟨b, some .fail⟩]) ≠ .admissible := by
  intro h
  have := (partDecision_admissible_iff _).1 h
  have h2 : (some Verdict.fail : Option Verdict) = some .pass := this.2 ⟨b, some .fail⟩ (by simp)
  exact absurd h2 (by decide)

/-- An admissible part passes at every cell: no engine, width or DPR is left out. -/
theorem admissible_all_pass (cs : List Cell) (h : partDecision cs = .admissible) : ∀ c ∈ cs, c.drawn = some .pass :=
  ((partDecision_admissible_iff cs).1 h).2

/-- A look change needs a baseline that passed: a part whose baseline fails everywhere it fails is never a look change. -/
theorem lookChange_needs_baseline_pass (cs : List Cell) (h : partDecision cs = .lookChange) :
    ∃ c ∈ cs, c.base = some .pass ∧ c.drawn = some .fail := by
  obtain ⟨c, hc, h1, h2⟩ := (partDecision_lookChange_iff cs).1 h
  exact ⟨c, hc, h2, h1⟩

/-! ## Golden vectors -/

/-- The verdict word of a cell side. -/
def verdictWord : Option Verdict → String
  | none => "error"
  | some .pass => "pass"
  | some .fail => "fail"
  | some .unsettled => "unsettled"
  | some .invalid => "invalid"
  | some .nc => "nc"

/-- The decision word. -/
def decisionWord : Decision → String
  | .admissible => "admissible"
  | .lookChange => "lookChange"
  | .shippedFails => "shippedFails"
  | .undecided => "undecided"

/-- The reason word. -/
def whyWord : Why → String
  | .ok => "ok" | .notImg => "notImg" | .cropped => "cropped" | .scaled => "scaled" | .fractional => "fractional" | .noSaving => "noSaving"

def kindWord : Kind → String
  | .img => "img" | .bg => "bg"

def imgJson (i : Img) : Json :=
  Json.mkObj [("kind", toJson (kindWord i.kind)), ("natW", toJson i.natW), ("natH", toJson i.natH), ("w", toJson i.w), ("h", toJson i.h),
    ("plain", toJson i.plain), ("scaleMin", toJson i.scaleMin), ("scaleMax", toJson i.scaleMax)]

def pairJson : Option (Nat × Nat) → Json
  | none => Json.null
  | some (a, b) => Json.arr #[toJson a, toJson b]

def cellJson (c : Cell) : Json := Json.arr #[toJson (verdictWord c.base), toJson (verdictWord c.drawn)]

/-- A plain `<img>` of `w` by `h` CSS pixels (milli) cut from a `nw` by `nh` file. -/
def img (nw nh w h : Nat) : Img := { kind := .img, natW := nw, natH := nh, w := w, h := h, plain := true, scaleMin := 1000, scaleMax := 1000 }

/-- Images the reach rule is pinned on: each reason once, and the avatars of the people carousel (30 by 30 CSS pixels, untransformed). -/
def imgCases : List (String × Img) :=
  [ ("avatar 30x30", img 200 200 30000 30000),
    ("avatar 30x30 from a file as large as the copy", img 60 60 30000 30000),
    ("avatar upscaled", img 20 20 30000 30000),
    ("fractional width", img 400 300 29600 30000),
    ("half a pixel at dpr 3", img 400 400 500 500),
    ("wide whole device size", img 1200 800 320000 213000),
    ("css image", { img 200 200 30000 30000 with kind := .bg }),
    ("cover crop", { img 400 400 30000 30000 with plain := false }),
    ("card scaled down", { img 400 400 100000 100000 with scaleMin := 350, scaleMax := 1190 }),
    ("card scaled up only", { img 400 400 100000 100000 with scaleMin := 1000, scaleMax := 1500 }),
    ("zero width", img 400 400 0 30000) ]

def dprCases : List Nat := [1, 2, 3]

/-- Cell lists the decision is pinned on. -/
def cellCases : List (String × List Cell) :=
  let p : Option Verdict := some .pass
  let f : Option Verdict := some .fail
  let u : Option Verdict := some .unsettled
  [ ("no cells", []),
    ("all pass", [⟨p, p⟩, ⟨p, p⟩, ⟨p, p⟩]),
    ("baseline fails, copies pass", [⟨f, p⟩, ⟨p, p⟩]),
    ("one fail where the baseline passes", [⟨p, p⟩, ⟨p, f⟩, ⟨p, p⟩]),
    ("a fail where the baseline fails", [⟨f, f⟩, ⟨p, p⟩]),
    ("a fail where the baseline is unsettled", [⟨u, f⟩, ⟨p, p⟩]),
    ("a fail with and without baseline pass", [⟨f, f⟩, ⟨p, f⟩]),
    ("unsettled", [⟨u, u⟩, ⟨p, p⟩]),
    ("an error cell", [⟨p, none⟩, ⟨p, p⟩]),
    ("invalid and nc", [⟨p, some .invalid⟩, ⟨p, some .nc⟩]),
    ("fail and unsettled", [⟨p, f⟩, ⟨p, u⟩]),
    ("one cell passes", [⟨p, p⟩]) ]

/-- File groups the one-file rules are pinned on: (name, first element, the others). -/
def fileCases : List (String × Img × List Img) :=
  [ ("one avatar", img 200 200 30000 30000, []),
    ("two avatars of one file, same size", img 200 200 30000 30000, [img 200 200 30000 30000]),
    ("two sizes of one file", img 200 200 30000 30000, [img 200 200 40000 40000]),
    ("one avatar and one scaled", img 200 200 30000 30000, [{ img 200 200 30000 30000 with scaleMax := 1400 }]),
    ("a scaled card", { img 400 400 100000 100000 with scaleMax := 1190 }, []),
    ("a scaled card seen twice", { img 400 400 100000 100000 with scaleMax := 1190 }, [{ img 400 400 100000 100000 with scaleMax := 1000 }]) ]

def snapCases : List (Nat × Nat × Nat) :=
  [ (1, 0, 1500), (1, 500, 2000), (2, 0, 30000), (2, 7300, 37300), (3, 0, 500), (3, 333, 833), (3, 17100, 17600), (2, 123, 30123) ]

def savingCases : List (Nat × Nat × Nat × Nat) := [(200, 200, 60, 60), (1035, 1400, 640, 866), (400, 400, 400, 400), (100, 100, 101, 100)]

/-- One golden line per case: snaps, reach and copies per image and DPR, file copies, decisions, savings. -/
def goldenLines (_ : Unit := ()) : List String :=
  snapCases.map (fun (d, l, r) =>
    (Json.mkObj [("kind", "snap"), ("dpr", toJson d), ("left", toJson l), ("right", toJson r), ("integral", toJson (integral d (r - l))),
      ("size", toJson (snapSize d l r))]).compress)
  ++ (imgCases.flatMap fun (n, i) => dprCases.map fun d =>
    (Json.mkObj [("kind", "reach"), ("name", toJson n), ("dpr", toJson d), ("img", imgJson i),
      ("why", toJson (whyWord (reachWhy d i))), ("exact", pairJson (exactCopy d i)),
      ("need", toJson (needW d i)), ("fit", pairJson (fitCopy d i))]).compress)
  ++ (fileCases.flatMap fun (n, i, rest) => dprCases.map fun d =>
    (Json.mkObj [("kind", "file"), ("name", toJson n), ("dpr", toJson d), ("imgs", Json.arr ((i :: rest).map imgJson).toArray),
      ("exact", pairJson (exactFile d i rest)), ("fit", pairJson (fitFile d i rest)), ("exactSaving", toJson (exactSaving d i rest))]).compress)
  ++ cellCases.map (fun (n, cs) =>
    (Json.mkObj [("kind", "part"), ("name", toJson n), ("cells", Json.arr (cs.map cellJson).toArray),
      ("decision", toJson (decisionWord (partDecision cs)))]).compress)
  ++ savingCases.map (fun (nw, nh, cw, ch) =>
    (Json.mkObj [("kind", "saving"), ("nat", Json.arr #[toJson nw, toJson nh]), ("copy", Json.arr #[toJson cw, toJson ch]),
      ("decoded", toJson (decoded nw nh)), ("saving", toJson (saving nw nh cw ch))]).compress)

/-- The exact bytes of `packages/contracts/golden/measure/image-arm.jsonl`. -/
def goldenText (_ : Unit := ()) : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

/-- Command-line driver: print the golden text, or with `--check <file>` exit 0 exactly when the file holds these bytes. -/
def run (args : List String) : IO UInt32 := do
  match Fw.Gate.Settle.argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"image-arm golden: {path} is up to date ({goldenLines.length} lines)"
      return 0
    IO.eprintln s!"image-arm golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print goldenText
    return 0

-- pins of the vectors (the proofs above are the statement)
#guard exactCopy 2 (img 200 200 30000 30000) == some (60, 60)
#guard exactCopy 3 (img 200 200 30000 30000) == some (90, 90)
#guard reachWhy 2 (img 60 60 30000 30000) == .noSaving
#guard reachWhy 1 (img 400 300 29600 30000) == .fractional
#guard reachWhy 3 (img 400 400 500 500) == .fractional
#guard partDecision [⟨some .pass, some .pass⟩] == .admissible
#guard partDecision [⟨some .pass, some .fail⟩] == .lookChange
#guard partDecision [] == .undecided

end Fw.Measure.ImageArm
