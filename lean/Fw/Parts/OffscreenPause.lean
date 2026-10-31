import Fw.Parts.PlatformSweepPause
/-! # Offscreen pause, any looping animation: the look equals the unpaused one on every visible frame -/
namespace Fw.Parts.OffscreenPause
open Fw.Parts.PlatformSweepPause

theorem look_same {α : Type} (g : Rat → α) (o : Rat) (pre : List Step) (f : Step) (hok : Ok f) (hv : f.2.1 = true) :
    g (seek (run (init o) pre) f).loc = g (orig o pre) := by
  rw [visible_same o pre f hok hv]

theorem look_same_unreported {α : Type} (g : Rat → α) (o : Rat) (pre : List Step) (f : Step) (hh : f.2.2 = false) :
    g (seek (run (init o) pre) f).loc = g (orig o pre) := by
  rw [shown_same o pre f hh]

theorem look_same_all {α : Type} (gs : List (Rat → α)) (o : Rat) (pre : List Step) (f : Step) (hok : Ok f)
    (hv : f.2.1 = true) : gs.map (fun g => g (seek (run (init o) pre) f).loc) = gs.map (fun g => g (orig o pre)) := by
  rw [visible_same o pre f hok hv]

/-- A loop the scene rule started again (no start time) resumes at `resumeTime`: any looking function of it equals the unpaused one. -/
theorem look_same_pending {α : Type} (g : Rat → α) (h : Held) (now : Rat) :
    g (resumeTime h now) = g (Unpaused h now) := rfl

end Fw.Parts.OffscreenPause
