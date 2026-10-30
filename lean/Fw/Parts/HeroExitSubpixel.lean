import Fw.Parts.HeroExit
import Fw.Parts.HeroOrbit
import Fw.Parts.HeroDeck

/-! WebKit's card `translate` under `hero.exit:threaded` at scroll 0: a float32 timeline time against a double range start,
and the bound of the resulting residue. -/

namespace Fw.Parts.HeroExitSubpixel

/-- `q` rounded to the nearest multiple of `2^-k`. -/
def roundBits (k : Nat) (q : Rat) : Rat := ((q * 2 ^ k + 1 / 2).floor : Rat) / 2 ^ k

/-- `roundBits k q` is IEEE round-to-nearest for a `p`-bit significand: `q` sits in the binade of spacing `2^-k`, off a tie. -/
def ieeeStep (p k : Nat) (q : Rat) : Bool :=
  decide ((2 : Rat) ^ (p - 1) ≤ q * 2 ^ k) && decide (q * 2 ^ k < 2 ^ p) &&
    decide ((q * 2 ^ k + 1 / 2).floor ≠ q * 2 ^ k + 1 / 2)

/-- Significand bits of `float`. -/
def single : Nat := 24

/-- Significand bits of `double`. -/
def double : Nat := 53

/-- The view timeline's subject at scroll 0 on a viewport of height `v`: offset 0, height `200vh`. -/
def trackPx (v : Rat) : Rat := 2 * v

theorem trackPx_eq (v : Rat) : HeroExit.trackHeightPx v false = some (trackPx v) := rfl

/-- Timeline progress at scroll 0, `distance / range` (ViewTimeline.cpp:509-511, ScrollTimeline.cpp:389-395@862f17d). -/
def ratio (v : Rat) : Rat := (0 - (0 - v)) / ((0 + trackPx v) - (0 - v))

theorem ratio_third (v : Rat) (hv : 0 < v) : ratio v = 1 / 3 := by
  unfold ratio trackPx
  have : v ≠ 0 := by grind
  grind

-- ScrollTimeline.h:102-105 and ScrollTimeline.cpp:395-396@862f17d: float quotient, float times 100.
/-- The timeline's current time in percent at scroll 0. -/
def timeline32 : Rat := roundBits 18 (roundBits 25 (1 / 3) * 100)

-- ViewTimeline.cpp:584-592,626-642@862f17d: double offset over the timeline range, times 100.
/-- The `contain` range start in percent (the animation's start time, WebAnimation.cpp:1531-1545@862f17d). -/
def start64 : Rat := roundBits 47 (roundBits 54 (1 / 3) * 100)

/-- The `contain` range end in percent. -/
def end64 : Rat := roundBits 46 (roundBits 53 (2 / 3) * 100)

/-- Local time, `current - start` (WebAnimation.cpp:518@862f17d). -/
def local64 : Rat := timeline32 - start64

/-- Iteration duration of `animation-duration: auto`, the range length (AnimationEffect.cpp:458-460@862f17d). -/
def duration64 : Rat := end64 - start64

/-- Iteration progress, `active time / iteration duration` (AnimationEffectTiming.cpp:279@862f17d). -/
def progress64 : Rat := roundBits 76 (local64 / duration64)

theorem ieee_steps :
    ieeeStep single 25 (1 / 3) ∧ ieeeStep single 18 (roundBits 25 (1 / 3) * 100) ∧
    ieeeStep double 54 (1 / 3) ∧ ieeeStep double 47 (roundBits 54 (1 / 3) * 100) ∧
    ieeeStep double 53 (2 / 3) ∧ ieeeStep double 46 (roundBits 53 (2 / 3) * 100) ∧
    ieeeStep double 76 (local64 / duration64) := by
  decide +kernel

theorem subtractions_exact : roundBits 71 local64 = local64 ∧ roundBits 47 duration64 = duration64 := by
  decide +kernel

-- WebAnimationTime.cpp:165-171@862f17d: percentages compare exactly, so the effect is in its active phase.
theorem after_start : start64 < timeline32 := by decide +kernel

theorem progress_pos : 0 < progress64 := by decide +kernel

theorem ideal_progress : (timeline32 - 100 / 3) / (100 / 3) = 1 / (100 * 2 ^ 17) := by decide +kernel

theorem progress_near_ideal :
    progress64 - 1 / (100 * 2 ^ 17) < 1 / (10 ^ 6 * 100 * 2 ^ 17) ∧
    1 / (100 * 2 ^ 17) - progress64 < 1 / (10 ^ 6 * 100 * 2 ^ 17) := by
  decide +kernel

/-- Largest scatter component of a card, in `vw` or `vh`. -/
def maxScatter : Rat := 48

theorem orbit_scatter_le (l t : Rat) :
    -maxScatter ≤ HeroOrbit.scatterX l ∧ HeroOrbit.scatterX l ≤ maxScatter ∧
    -maxScatter ≤ HeroOrbit.scatterY l t ∧ HeroOrbit.scatterY l t ≤ maxScatter := by
  unfold HeroOrbit.scatterX HeroOrbit.scatterY maxScatter
  refine ⟨?_, ?_, ?_, ?_⟩ <;> split <;> (try split) <;> (try split) <;> decide +kernel

theorem deck_scatter_le :
    HeroDeck.slots.all (fun s => decide (-maxScatter ≤ s.sx ∧ s.sx ≤ maxScatter ∧ -maxScatter ≤ s.sy ∧ s.sy ≤ maxScatter)) := by
  decide +kernel

/-- Card translate residue in px for a scatter of magnitude `a` (`vw` or `vh`) on a viewport side of `v` px. -/
def residue (a v : Rat) : Rat := a / 100 * v * progress64

/-- Widest viewport side the bound covers, px. -/
def widest : Rat := 2560

/-- Absolute tolerance a gate would need on a `translate` component, px. -/
def gateTol : Rat := 1 / 10 ^ 4

theorem residue_le_max (a v : Rat) (ha : a ≤ maxScatter) (hv0 : 0 ≤ v) (hv : v ≤ widest) :
    residue a v ≤ residue maxScatter widest := by
  have hp : 0 ≤ progress64 := by decide +kernel
  have h1 : a / 100 * v ≤ maxScatter / 100 * v :=
    Rat.mul_le_mul_of_nonneg_right (by unfold maxScatter at *; grind) hv0
  have h2 : maxScatter / 100 * v ≤ maxScatter / 100 * widest :=
    Rat.mul_le_mul_of_nonneg_left hv (by decide +kernel)
  exact Rat.mul_le_mul_of_nonneg_right (Rat.le_trans h1 h2) hp

theorem residue_lt_gateTol (a v : Rat) (ha : a ≤ maxScatter) (hv0 : 0 ≤ v) (hv : v ≤ widest) :
    residue a v < gateTol := by
  have hm := residue_le_max a v ha hv0 hv
  have hb : residue maxScatter widest < gateTol := by decide +kernel
  grind

/-- Device pixels per CSS px the bound covers. -/
def dprMax : Rat := 3

theorem residue_level_change_lt (a v : Rat) (ha : a ≤ maxScatter) (hv0 : 0 ≤ v) (hv : v ≤ widest) :
    dprMax * 255 * residue a v < 1 / 10 := by
  have hm := residue_le_max a v ha hv0 hv
  have hb : dprMax * 255 * residue maxScatter widest < 1 / 10 := by decide +kernel
  have hk : dprMax * 255 * residue a v ≤ dprMax * 255 * residue maxScatter widest :=
    Rat.mul_le_mul_of_nonneg_left hm (by decide +kernel)
  grind

end Fw.Parts.HeroExitSubpixel
