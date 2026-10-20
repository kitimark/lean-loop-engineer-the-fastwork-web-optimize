/-!
# WebKit image cost: natural pixels times repaints that resample (task image-audit)

Citations are WebKit @862f17d (`WC` = `Source/WebCore`). Which premise holds in shipped Safari is a measured claim, not a theorem here.
-/
namespace Fw.Engine.WebKitImage

/-! ## Decode policy -/

inductive Mode where
  | sync | async
deriving Repr, DecidableEq

/-- Decoded bytes of `px` pixels (4 bytes each). -/
def bytes (px : Nat) : Nat := 4 * px

/-- `BitmapImageSource::isLargeForDecoding` for a still image: decoded size above 500 KB (`WC/platform/graphics/BitmapImageSource.cpp:349-353`, CONFIRMED). -/
def isLarge (natPx : Nat) : Bool := decide (500 * 1024 < bytes natPx)

/-- The mode `RenderBoxModelObject::decodingModeForImageDraw` picks for a still, unforced image (`WC/rendering/RenderBoxModelObject.cpp:256-320`, CONFIRMED). -/
def modeFor (large visible firstPaintAsync : Bool) : Mode :=
  if !large then .sync else if firstPaintAsync then .async else if visible then .sync else .async

/-- Pixels one decode produces: the whole image when synchronous, the smaller of the image and the drawn size when asynchronous (`WC/platform/graphics/cg/ImageDecoderCG.cpp:676-698`, CONFIRMED). -/
def decodedPx (m : Mode) (natPx drawnPx : Nat) : Nat :=
  match m with
  | .sync => natPx
  | .async => min natPx drawnPx

theorem isLarge_true (natPx : Nat) (h : 500 * 1024 < 4 * natPx) : isLarge natPx = true := by
  simp [isLarge, bytes, h]

theorem isLarge_false (natPx : Nat) (h : 4 * natPx ≤ 500 * 1024) : isLarge natPx = false := by
  unfold isLarge bytes
  simp only [decide_eq_false_iff_not]
  omega

theorem small_sync (natPx : Nat) (v f : Bool) (h : isLarge natPx = false) : modeFor (isLarge natPx) v f = .sync := by
  simp [modeFor, h]

theorem large_firstPaint_async (v : Bool) : modeFor true v true = .async := by
  simp [modeFor]

theorem large_visible_sync : modeFor true true false = .sync := by
  simp [modeFor]

theorem large_hidden_async : modeFor true false false = .async := by
  simp [modeFor]

theorem sync_decodes_all (natPx drawnPx : Nat) : decodedPx .sync natPx drawnPx = natPx := rfl

theorem async_decodes_drawn (natPx drawnPx : Nat) (h : drawnPx ≤ natPx) : decodedPx .async natPx drawnPx = drawnPx := by
  simp [decodedPx, Nat.min_eq_right h]

theorem async_never_more (natPx drawnPx : Nat) : decodedPx .async natPx drawnPx ≤ decodedPx .sync natPx drawnPx :=
  Nat.min_le_left _ _

/-! ## Subsampling -/

/-- The area below which the highest subsampling level stops (`WC/platform/graphics/BitmapImageDescriptor.cpp:244`, CONFIRMED). -/
def areaLimit : Nat := 5 * 1024 * 1024

/-- `maximumSubsamplingLevel`: the first level whose area is under the limit, at most 3 (`BitmapImageDescriptor.cpp:229-256`, CONFIRMED). -/
def maxLevel (natPx : Nat) : Nat :=
  if natPx < areaLimit then 0
  else if natPx / 4 < areaLimit then 1
  else if natPx / 16 < areaLimit then 2
  else 3

/-- `subsamplingLevelForScaleFactor`: the least level l with `nat ≤ drawn * 2^l`, capped at `maxLevel` (`BitmapImageDescriptor.cpp:258-273`, CONFIRMED). -/
def level (natDim drawnDim maxL : Nat) : Nat :=
  min maxL (if natDim ≤ drawnDim then 0 else if natDim ≤ 2 * drawnDim then 1 else if natDim ≤ 4 * drawnDim then 2 else 3)

theorem no_subsampling_under_limit (natPx natDim drawnDim : Nat) (h : natPx < areaLimit) :
    level natDim drawnDim (maxLevel natPx) = 0 := by
  simp [level, maxLevel, h]

theorem level_le_max (natDim drawnDim maxL : Nat) : level natDim drawnDim maxL ≤ maxL :=
  Nat.min_le_left _ _

/-- One theorem per branch of `maxLevel`: level 1 from 5 Mpx, 2 from 20 Mpx, 3 from 80 Mpx. -/
theorem maxLevel_one (natPx : Nat) (h0 : areaLimit ≤ natPx) (h1 : natPx / 4 < areaLimit) : maxLevel natPx = 1 := by
  simp [maxLevel, Nat.not_lt.mpr h0, h1]

theorem maxLevel_two (natPx : Nat) (h1 : areaLimit ≤ natPx / 4) (h2 : natPx / 16 < areaLimit) : maxLevel natPx = 2 := by
  have h0 : areaLimit ≤ natPx := by omega
  simp [maxLevel, Nat.not_lt.mpr h0, Nat.not_lt.mpr h1, h2]

theorem maxLevel_three (natPx : Nat) (h2 : areaLimit ≤ natPx / 16) : maxLevel natPx = 3 := by
  have h0 : areaLimit ≤ natPx := by omega
  have h1 : areaLimit ≤ natPx / 4 := by omega
  simp [maxLevel, Nat.not_lt.mpr h0, Nat.not_lt.mpr h1, Nat.not_lt.mpr h2]

/-- One theorem per branch of `level` when the cap allows it (`maxL = 3`): drawn at least the natural size, at least half, at least a quarter, less. -/
theorem level_zero (natDim drawnDim : Nat) (h : natDim ≤ drawnDim) : level natDim drawnDim 3 = 0 := by
  simp [level, h]

theorem level_one (natDim drawnDim : Nat) (h0 : drawnDim < natDim) (h1 : natDim ≤ 2 * drawnDim) : level natDim drawnDim 3 = 1 := by
  simp [level, Nat.not_le.mpr h0, h1]

theorem level_two (natDim drawnDim : Nat) (h1 : 2 * drawnDim < natDim) (h2 : natDim ≤ 4 * drawnDim) : level natDim drawnDim 3 = 2 := by
  have h0 : drawnDim < natDim := by omega
  simp [level, Nat.not_le.mpr h0, Nat.not_le.mpr h1, h2]

theorem level_three (natDim drawnDim : Nat) (h2 : 4 * drawnDim < natDim) : level natDim drawnDim 3 = 3 := by
  have h0 : drawnDim < natDim := by omega
  have h1 : 2 * drawnDim < natDim := by omega
  simp [level, Nat.not_le.mpr h0, Nat.not_le.mpr h1, Nat.not_le.mpr h2]

/-! ## Memory cache -/

/-- The decoded-data budget of the primary-browser cache model on a device with at least 2 GB (`WebKit/Shared/CacheModel.cpp:88-102`, CONFIRMED; the model Safari uses is INFERRED). -/
def cacheBytes : Nat := 128 * 1024 * 1024

/-- Decoded data of the live images fits the cache, so the pruner has nothing to destroy (`WC/loader/cache/MemoryCache.cpp:224-233`, CONFIRMED). -/
def fits (decodedTotal : Nat) : Bool := decide (decodedTotal ≤ cacheBytes)

theorem fits_mono (a b : Nat) (h : a ≤ b) (hb : fits b = true) : fits a = true := by
  simp only [fits, decide_eq_true_eq] at hb ⊢
  omega

/-! ## Repaints -/

/-- What a layer's image sits under, from the audit. -/
inductive Under where
  | compositedFilter | softwareFilter | opacityAnim | transformAnim | backdrop | nothing
deriving Repr, DecidableEq

/-- Repaints of the image content over `frames` frames (`WC/rendering/RenderLayer.cpp:1068`, `WC/platform/graphics/ca/GraphicsLayerCA.cpp:925-945`; the compositor rows are INFERRED). -/
def repaints (u : Under) (frames : Nat) : Nat :=
  match u with
  | .softwareFilter => frames
  | .compositedFilter | .opacityAnim | .transformAnim | .backdrop | .nothing => 0

theorem composited_filter_no_repaint (n : Nat) : repaints .compositedFilter n = 0 := rfl
theorem opacity_anim_no_repaint (n : Nat) : repaints .opacityAnim n = 0 := rfl
theorem transform_anim_no_repaint (n : Nat) : repaints .transformAnim n = 0 := rfl
theorem backdrop_no_repaint (n : Nat) : repaints .backdrop n = 0 := rfl
theorem nothing_no_repaint (n : Nat) : repaints .nothing n = 0 := rfl
theorem software_filter_repaints_each_frame (n : Nat) : repaints .softwareFilter n = n := rfl

/-! ## The cost term -/

/-- Decode work once plus resample work per repaint: `decodedPx` pixels read by each repaint when it resamples (PREMISE P-resample, INFERRED: `GraphicsContextCG.cpp:433` hands the whole frame to CoreGraphics). -/
def cost (m : Mode) (resamples : Bool) (natPx drawnPx reps : Nat) : Nat :=
  decodedPx m natPx drawnPx * (1 + if resamples then reps else 0)

theorem cost_no_resample (m : Mode) (natPx drawnPx reps : Nat) :
    cost m false natPx drawnPx reps = decodedPx m natPx drawnPx := by
  simp [cost]

theorem cost_sync_resample (natPx drawnPx reps : Nat) :
    cost .sync true natPx drawnPx reps = natPx * (1 + reps) := by
  simp [cost, decodedPx]

theorem cost_async_resample (natPx drawnPx reps : Nat) (h : drawnPx ≤ natPx) :
    cost .async true natPx drawnPx reps = drawnPx * (1 + reps) := by
  simp [cost, decodedPx, Nat.min_eq_right h]

theorem cost_no_repaint (m : Mode) (natPx drawnPx : Nat) :
    cost m true natPx drawnPx 0 = decodedPx m natPx drawnPx := by
  simp [cost]

theorem cost_mono_reps (m : Mode) (r : Bool) (natPx drawnPx a b : Nat) (h : a ≤ b) :
    cost m r natPx drawnPx a ≤ cost m r natPx drawnPx b := by
  unfold cost
  apply Nat.mul_le_mul_left
  cases r <;> simp [h]

theorem cost_mono_nat (m : Mode) (r : Bool) (a b drawnPx reps : Nat) (h : a ≤ b) :
    cost m r a drawnPx reps ≤ cost m r b drawnPx reps := by
  unfold cost decodedPx
  apply Nat.mul_le_mul_right
  cases m <;> simp <;> omega

/-- Pixels the file holds beyond what it draws. -/
def wastePx (natPx drawnPx : Nat) : Nat := natPx - drawnPx

/-- The saving of a copy with `copyPx` pixels over the source under a synchronous resampling draw, exact. -/
theorem sync_saving (natPx copyPx drawnPx reps : Nat) (h : copyPx ≤ natPx) :
    cost .sync true natPx drawnPx reps = cost .sync true copyPx drawnPx reps + (natPx - copyPx) * (1 + reps) := by
  simp only [cost_sync_resample]
  rw [← Nat.add_mul, Nat.add_sub_cancel' h]

/-- A copy at the drawn size never costs more than the source, for either decode mode. -/
theorem drawn_copy_le (m : Mode) (r : Bool) (natPx drawnPx reps : Nat) (h : drawnPx ≤ natPx) :
    cost m r drawnPx drawnPx reps ≤ cost m r natPx drawnPx reps :=
  cost_mono_nat m r drawnPx natPx drawnPx reps h

/-- A copy at the drawn size makes sync and async decode the same work: asynchronous already decodes the drawn size, so only synchronous gains. -/
theorem drawn_copy_modes_equal (r : Bool) (drawnPx reps : Nat) :
    cost .sync r drawnPx drawnPx reps = cost .async r drawnPx drawnPx reps := by
  simp [cost, decodedPx]

/-- Async decode of the source already costs the copy's amount: no saving for an image decoded asynchronously. -/
theorem async_source_equals_copy (r : Bool) (natPx drawnPx reps : Nat) (h : drawnPx ≤ natPx) :
    cost .async r natPx drawnPx reps = cost .async r drawnPx drawnPx reps := by
  simp [cost, decodedPx, Nat.min_eq_right h]

end Fw.Engine.WebKitImage
