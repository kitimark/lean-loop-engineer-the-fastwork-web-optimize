/-!
# platform and platform.stageBg: the shrink state of the section and the stage geometry (P5 port, `faithful`)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`
  * 12434-12448 (`p`, the scroll callback): `r = 0.85 vh`, `i = 0.35 vh`, `a = 0` if the card bottom is at or below `r`,
    `1` if at or above `i`, else `(r - bottom)/(r - i)`; the shrink is the smoothstep of `a`
    (a fixed step `a ≥ 0.5` under reduced motion); the "shrinking" class is on while `a > 0.04`;
* `snapshot/site-pretty/_app/immutable/assets/2.gBuqKVzi.css`
  * 5530: `--platform-shrink-scale: calc(1 - 0.083333 * shrink)`; 5531, 7830: radius `32` px (`24` px at width `≤ 720`);
    10989-10997: scale 1 and radius 0 at the 860 combo;
  * 6330 (`.stage`): `aspect-ratio: 640/512` (`361/288` at the 860 combo, `640/512` again at `≤ 640`), `border-radius: 5%`;
  * 6369-6385: `.stage-bg` `filter: blur(16px)`, `opacity: 0.5` (`0.15` for the quote background); 6358: the grain is an
    overlay at `opacity: 0.55` (`0.42` on the secure mesh) tiled at `128` px;
  * 6396-6405: the artboard is a `640 × 512` box scaled by `100 cqw / 640` inside a container-type inline-size box.

All values `Rat`. No `Float`.
-/
namespace Fw.Parts.PlatformSection

/-! ## The shrink state -/

/-- Clamp to `[0, 1]`. -/
def clamp01 (x : Rat) : Rat := min 1 (max 0 x)

/-- Smoothstep (JS `p`). -/
def smooth (x : Rat) : Rat :=
  clamp01 x * clamp01 x * (3 - 2 * clamp01 x)

/-- Raw progress from the card bottom (px from the viewport top) and the viewport height. -/
def raw (bottom vh : Rat) : Rat :=
  if 17 * vh / 20 ≤ bottom then 0
  else if bottom ≤ 7 * vh / 20 then 1
  else (17 * vh / 20 - bottom) / (vh / 2)

/-- The shrink value `--platform-shrink`. -/
def shrink (reduced : Bool) (bottom vh : Rat) : Rat :=
  if reduced then (if 1 / 2 ≤ raw bottom vh then 1 else 0) else smooth (raw bottom vh)

/-- The `is-platform-shrinking` class. -/
def shrinking (bottom vh : Rat) : Bool := decide (1 / 25 < raw bottom vh)

/-- Card scale (CSS `1 - 0.083333 s`). -/
def scale (s : Rat) : Rat := 1 - 83333 / 1000000 * s

/-- Card radius in px; the base radius is 32 (24 at width at most 720, 0 at the 860 combo). -/
def radius (r0 s : Rat) : Rat := r0 * s

#guard raw 900 1000 == 0
#guard raw 850 1000 == 0
#guard raw 350 1000 == 1
#guard raw 600 1000 == 1 / 2
#guard shrink false 600 1000 == 1 / 2
#guard shrink true 600 1000 == 1
#guard shrink true 700 1000 == 0

/-- The clamp lies in `[0, 1]`. -/
theorem clamp01_mem (x : Rat) : 0 ≤ clamp01 x ∧ clamp01 x ≤ 1 := by unfold clamp01; grind

/-- The smoothstep lies in `[0, 1]`. -/
theorem smooth_mem (x : Rat) : 0 ≤ smooth x ∧ smooth x ≤ 1 := by
  have h := clamp01_mem x
  unfold smooth
  generalize clamp01 x = c at *
  have h0 : 0 ≤ c * c := Rat.mul_nonneg h.1 h.1
  have h1 : c * c ≤ c := by
    have := Rat.mul_le_mul_of_nonneg_left h.2 h.1
    grind
  have h2 : 0 ≤ c * c * (3 - 2 * c) := Rat.mul_nonneg h0 (by grind)
  have h3 : c * c * (3 - 2 * c) ≤ 1 := by
    -- 3c^2 - 2c^3 <= 1 on [0,1]: (1 - c)^2 (1 + 2c) >= 0
    have h4 : 0 ≤ (1 - c) * (1 - c) := Rat.mul_nonneg (by grind) (by grind)
    have h5 : 0 ≤ (1 - c) * (1 - c) * (1 + 2 * c) := Rat.mul_nonneg h4 (by grind)
    grind
  exact ⟨h2, h3⟩

/-- The smoothstep is symmetric. -/
theorem smooth_symm (x : Rat) (h0 : 0 ≤ x) (h1 : x ≤ 1) : smooth (1 - x) = 1 - smooth x := by
  have a : clamp01 x = x := by unfold clamp01; grind
  have b : clamp01 (1 - x) = 1 - x := by unfold clamp01; grind
  unfold smooth
  rw [a, b]
  grind

/-- Raw progress is in `[0, 1]` for a positive viewport. -/
theorem raw_mem (bottom vh : Rat) (hv : 0 < vh) : 0 ≤ raw bottom vh ∧ raw bottom vh ≤ 1 := by
  unfold raw
  split
  · grind
  split
  · grind
  · rename_i h1 h2
    have e : (17 * vh / 20 - bottom) / (vh / 2) * (vh / 2) = 17 * vh / 20 - bottom := Rat.div_mul_cancel (by grind)
    generalize (17 * vh / 20 - bottom) / (vh / 2) = q at *
    constructor
    · by_cases hq : 0 ≤ q
      · exact hq
      · have := Rat.mul_pos (show 0 < -q by grind) (show 0 < vh / 2 by grind)
        grind
    · by_cases hq : q ≤ 1
      · exact hq
      · have := Rat.mul_pos (show 0 < q - 1 by grind) (show 0 < vh / 2 by grind)
        grind

/-- At or below `0.85 vh` the card is not shrunk; at or above `0.35 vh` it is fully shrunk.

(for `h > 0`, both motion modes) -/
theorem shrink_ends (reduced : Bool) (bottom vh : Rat) (hv : 0 < vh) :
    (17 * vh / 20 ≤ bottom → shrink reduced bottom vh = 0) ∧ (bottom ≤ 7 * vh / 20 → shrink reduced bottom vh = 1) := by
  constructor
  · intro h
    have : raw bottom vh = 0 := by unfold raw; simp [h]
    unfold shrink
    rw [this]
    cases reduced <;> decide +kernel
  · intro h
    have hn : ¬ 17 * vh / 20 ≤ bottom := by grind
    have : raw bottom vh = 1 := by unfold raw; simp [hn, h]
    unfold shrink
    rw [this]
    cases reduced <;> decide +kernel

/-- Under reduced motion the shrink is 0 or 1 and nothing between. -/
theorem shrink_reduced_two (bottom vh : Rat) : shrink true bottom vh = 0 ∨ shrink true bottom vh = 1 := by
  unfold shrink
  simp only [ite_true]
  split <;> simp

/-- The shrink is in `[0, 1]`. -/
theorem shrink_mem (reduced : Bool) (bottom vh : Rat) : 0 ≤ shrink reduced bottom vh ∧ shrink reduced bottom vh ≤ 1 := by
  unfold shrink
  cases reduced
  · simp only [Bool.false_eq_true, ↓reduceIte]; exact smooth_mem _
  · simp only [↓reduceIte]; split <;> grind

/-- The card scale stays in `[0.916667, 1]` for `s ∈ [0,1]`. -/
theorem scale_mem (s : Rat) (h0 : 0 ≤ s) (h1 : s ≤ 1) : 916667 / 1000000 ≤ scale s ∧ scale s ≤ 1 := by
  unfold scale; grind

/-! ## The stage -/

/-- Height of a stage of width `w` (`aspect-ratio: 640/512`). -/
def stageHeight (w : Rat) : Rat := w * 512 / 640

/-- Scale of the artboard inside a stage of width `w` (`calc(100cqw / 640px)`). -/
def artboardScale (w : Rat) : Rat := w / 640

/-- The scaled artboard exactly fills the stage. -/
theorem artboard_fills (w : Rat) : 512 * artboardScale w = stageHeight w := by
  unfold artboardScale stageHeight; grind

/-- The scaled artboard width is the stage width. -/
theorem artboard_width (w : Rat) : 640 * artboardScale w = w := by
  unfold artboardScale; grind

/-- Stage background opacity: `0.5`, or `0.15` for the quote background. -/
def bgOpacity (quote : Bool) : Rat := if quote then 3 / 20 else 1 / 2

/-- Blur radius of the stage background in px. -/
def bgBlur : Rat := 16

/-- Opacity of the grain overlay: `0.55`, or `0.42` on the secure mesh. -/
def grainOpacity (secureMesh : Bool) : Rat := if secureMesh then 21 / 50 else 11 / 20

/-- Tile size of the grain in px. -/
def grainTile : Rat := 128

/-- Which stage a row has. -/
inductive Row | document | discovered | payment | relationship
deriving Repr, DecidableEq

/-- The stage background of a row: a mesh gradient (+ grain) for document and payment, the photo for discovered, the quote image for relationship. -/
inductive Bg | mesh | secureMesh | photo | quote
deriving Repr, DecidableEq

/-- Row to background. document: secure mesh; payment: mesh; discovered: photo; relationship: quote. -/
def bgOf : Row → Bg
  | .document => .secureMesh
  | .payment => .mesh
  | .discovered => .photo
  | .relationship => .quote

/-- Rows flipped (copy left, stage right): discovered and relationship. -/
def flip : Row → Bool
  | .discovered => true
  | .relationship => true
  | _ => false

/-- The quote background is fainter than the photo. -/
theorem quote_fainter : bgOpacity true < bgOpacity false := by decide +kernel

/-- The secure mesh grain is fainter than the plain grain. -/
theorem secure_grain_fainter : grainOpacity true < grainOpacity false := by decide +kernel

end Fw.Parts.PlatformSection
