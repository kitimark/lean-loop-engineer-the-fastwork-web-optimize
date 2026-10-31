import Fw.Parts.OffscreenPause
/-!
# `hero.cue:offscreen-pause`: the cue float loop pauses while the cue is off screen, same look

`.float` runs `2.2s ease-in-out infinite scrollFloat`: `translateY` 0 at 0 %, -8 px at 50 %, 0 at 100 %, the timing
function applied on each half. The easing `e` (a cubic-bezier, not rational) is a parameter: the identity below holds
for every `e`, so no fact about the engine's easing is assumed.
-/
namespace Fw.Parts.HeroCuePause
open Fw.Parts.PlatformSweepPause (Step Ok seek run init orig ticks totalTicks LagList)
open Fw.Parts.PlatformSweep (frac)

/-- Cycle length in ms (the CSS `2.2s`). -/
def cycleMs : Rat := 2200

/-- `translateY` in px at local time `t` ms for easing `e` (progress in `[0, 1]` to eased progress). -/
def cueY (e : Rat → Rat) (t : Rat) : Rat :=
  let p := frac (t / cycleMs)
  if p < 1 / 2 then -8 * e (2 * p) else -8 * (1 - e (2 * p - 1))

#guard cueY id 0 == 0 && cueY id 1100 == -8 && cueY id 550 == -4 && cueY id 2200 == 0 && cueY id 1650 == -4

/-- **Look identity.** For every easing, on every visible frame the paused float is at the unpaused offset. -/
theorem cue_visible_same (e : Rat → Rat) (o : Rat) (pre : List Step) (f : Step) (hok : Ok f) (hv : f.2.1 = true) :
    cueY e (seek (run (init o) pre) f).loc = cueY e (orig o pre) :=
  Fw.Parts.OffscreenPause.look_same (cueY e) o pre f hok hv

/-- A reported frame does not tick (no recalc from this animation). -/
theorem cue_reported_no_tick (s : Fw.Parts.PlatformSweepPause.St) (f : Step) (hr : f.2.2 = true) :
    (Fw.Parts.PlatformSweepPause.step s f).loc = s.loc ∧ ticks f = 0 :=
  Fw.Parts.PlatformSweepPause.reported_no_tick s f hr

/-- Under the observer-lag premise, an off-screen run ticks at most once (the leaving frame). -/
theorem cue_offscreen_ticks_le_one (g : Step) (rest : List Step) (hv : g.2.1 = false ∧ ∀ f ∈ rest, f.2.1 = false)
    (hl : LagList g rest) : totalTicks (g :: rest) ≤ 1 :=
  Fw.Parts.PlatformSweepPause.offscreen_ticks_le_one g rest hv hl

end Fw.Parts.HeroCuePause
