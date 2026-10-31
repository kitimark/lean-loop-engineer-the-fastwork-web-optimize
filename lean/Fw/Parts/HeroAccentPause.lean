import Fw.Parts.OffscreenPause
import Fw.Parts.HeroAccentOpt
/-!
# `hero.accent:offscreen-pause`: the three idle boil loops pause while the accent is off screen, same look

The three `0.6s step-end infinite` boxes (`HeroAccentOpt.origVal`) are paused when the observer reports the accent
off screen and resumed with their saved start time, so the local time of each is the unpaused one (`PlatformSweepPause`
`shown_same`). A box shows `origVal j` at the position of its local time in the 600 ms cycle.
-/
namespace Fw.Parts.HeroAccentPause
open Fw.Parts.PlatformSweepPause (Step Ok seek run init orig ticks totalTicks LagList)
open Fw.Parts.PlatformSweep (frac)
open Fw.Parts.HeroAccentOpt (origVal)

/-- Cycle length in ms (the CSS `0.6s`). -/
def cycleMs : Rat := 600

/-- Opacity of box `j` at local time `t` ms (any `t ≥ 0`): the original's step-end value at the time in the cycle. -/
def shown (j : Nat) (t : Rat) : Rat := origVal j (cycleMs * frac (t / cycleMs))

#guard shown 0 0 == 1 && shown 1 0 == 0 && shown 2 0 == 0
#guard shown 0 300 == 0 && shown 1 300 == 1 && shown 2 300 == 0
#guard shown 2 500 == 1 && shown 2 1100 == 1 && shown 0 600 == 1

/-- **Look identity (each box).** On every visible frame the box shows the unpaused value. -/
theorem accent_visible_same (o : Rat) (pre : List Step) (f : Step) (hok : Ok f) (hv : f.2.1 = true) (j : Nat) :
    shown j (seek (run (init o) pre) f).loc = shown j (orig o pre) :=
  Fw.Parts.OffscreenPause.look_same (shown j) o pre f hok hv

/-- The three boxes together. -/
theorem accent_visible_same_all (o : Rat) (pre : List Step) (f : Step) (hok : Ok f) (hv : f.2.1 = true) :
    [shown 0, shown 1, shown 2].map (fun g => g (seek (run (init o) pre) f).loc)
      = [shown 0, shown 1, shown 2].map (fun g => g (orig o pre)) :=
  Fw.Parts.OffscreenPause.look_same_all [shown 0, shown 1, shown 2] o pre f hok hv

/-- A reported frame does not tick (no recalc from this animation). -/
theorem accent_reported_no_tick (s : Fw.Parts.PlatformSweepPause.St) (f : Step) (hr : f.2.2 = true) :
    (Fw.Parts.PlatformSweepPause.step s f).loc = s.loc ∧ ticks f = 0 :=
  Fw.Parts.PlatformSweepPause.reported_no_tick s f hr

/-- Under the observer-lag premise, an off-screen run ticks at most once (the leaving frame). -/
theorem accent_offscreen_ticks_le_one (g : Step) (rest : List Step) (hv : g.2.1 = false ∧ ∀ f ∈ rest, f.2.1 = false)
    (hl : LagList g rest) : totalTicks (g :: rest) ≤ 1 :=
  Fw.Parts.PlatformSweepPause.offscreen_ticks_le_one g rest hv hl

end Fw.Parts.HeroAccentPause
