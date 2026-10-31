import Fw.Parts.PlatformSweepPause
/-!
# Offscreen pause, any looping animation: the shown local time equals the unpaused one on every visible frame

`Fw.Parts.PlatformSweepPause` proves it for the local time of one animation: after any trace the seeked local time on a
visible frame is `orig`. A looping animation shows a function of its local time, so every such look is the same on a
visible frame. This module states that once; `HeroAccentPause` and `HeroCuePause` instantiate it.
-/
namespace Fw.Parts.OffscreenPause
open Fw.Parts.PlatformSweepPause

/-- **Look identity.** Whatever the animation shows as a function `g` of its local time, the paused variant shows the
original's value on every frame the viewport reports visible. Named premise: `Lag` (PlatformSweepPause), the observer
reports an element only after the frame it left. -/
theorem look_same {α : Type} (g : Rat → α) (o : Rat) (pre : List Step) (f : Step) (hok : Ok f) (hv : f.2.1 = true) :
    g (seek (run (init o) pre) f).loc = g (orig o pre) := by
  rw [visible_same o pre f hok hv]

/-- The same on any frame the engine does not report offscreen (`seek` shows the resumed time then too). -/
theorem look_same_unreported {α : Type} (g : Rat → α) (o : Rat) (pre : List Step) (f : Step) (hh : f.2.2 = false) :
    g (seek (run (init o) pre) f).loc = g (orig o pre) := by
  rw [shown_same o pre f hh]

/-- Several animations that start together (the accent's three boxes) read the same local time, so all agree. -/
theorem look_same_all {α : Type} (gs : List (Rat → α)) (o : Rat) (pre : List Step) (f : Step) (hok : Ok f)
    (hv : f.2.1 = true) : gs.map (fun g => g (seek (run (init o) pre) f).loc) = gs.map (fun g => g (orig o pre)) := by
  rw [visible_same o pre f hok hv]

end Fw.Parts.OffscreenPause
