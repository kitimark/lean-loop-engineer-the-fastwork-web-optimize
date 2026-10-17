import Fw.Spec.DeviceQueue

/-! # Mutant killers for `Fw.Spec.DeviceQueue` (task m0-mutants)

Golden cases for the aging constant, `eff` at the step boundaries, the window edges of `fits`,
`dispatch` and `dispatchHoL` (queue bookkeeping included) and both stop conditions of `tick`.
Jobs are written `⟨seq, enq, base, dur⟩`. -/

namespace FwTest.Mutants.DeviceQueue
open Fw.DeviceQueue

/-- The aging step is the specified constant.

$$A = 300$$

The constant is part of the spec (one priority level per five minutes of waiting). -/
theorem A_eq : A = 300 := rfl

-- eff: one level per full A seconds, never below 0, no aging before the enqueue time
#guard eff 1299 ⟨0, 100, 5, 60⟩ == 2 && eff 1300 ⟨0, 100, 5, 60⟩ == 1 && eff 1000 ⟨0, 100, 5, 60⟩ == 2
#guard eff 99999 ⟨0, 100, 5, 60⟩ == 0 && eff 50 ⟨0, 100, 5, 60⟩ == 5 && eff 400 ⟨0, 100, 5, 60⟩ == 4
-- before: lower eff first, ties by arrival
#guard before 0 ⟨0, 0, 1, 1⟩ ⟨1, 0, 2, 1⟩ && !before 0 ⟨1, 0, 2, 1⟩ ⟨0, 0, 1, 1⟩
#guard before 0 ⟨0, 0, 1, 1⟩ ⟨1, 0, 1, 1⟩ && !before 0 ⟨1, 0, 1, 1⟩ ⟨0, 0, 1, 1⟩
-- pick scans the whole list (the minimum may sit anywhere)
#guard pick 0 [⟨0, 0, 3, 1⟩, ⟨1, 0, 2, 1⟩, ⟨2, 0, 1, 1⟩, ⟨3, 0, 2, 1⟩] == some ⟨2, 0, 1, 1⟩
#guard pick 0 [⟨2, 0, 1, 1⟩, ⟨0, 0, 3, 1⟩, ⟨1, 0, 1, 1⟩] == some ⟨1, 0, 1, 1⟩
#guard pick 0 ([] : List Job) == none
-- fits: both window edges are inclusive
#guard fits 10 20 10 ⟨0, 0, 0, 10⟩ && !fits 10 20 9 ⟨0, 0, 0, 1⟩ && !fits 10 20 11 ⟨0, 0, 0, 10⟩
-- dispatch: starts the best fitting job, removes it from the queue, keeps the others in order
#guard
  let p : Phone := { queue := [⟨0, 0, 3, 50⟩, ⟨1, 0, 1, 500⟩, ⟨2, 0, 2, 50⟩, ⟨3, 0, 1, 50⟩], window := some (0, 100) }
  let q := dispatch p 0
  q.running == some (⟨3, 0, 1, 50⟩, 0) && q.queue == [⟨0, 0, 3, 50⟩, ⟨1, 0, 1, 500⟩, ⟨2, 0, 2, 50⟩] && q.window == p.window
#guard (dispatch { queue := [⟨0, 0, 0, 10⟩], window := some (5, 100) } 4).running == none
#guard (dispatch { queue := [⟨0, 0, 0, 10⟩], window := none } 4).running == none
#guard (dispatch { queue := [⟨0, 0, 0, 10⟩], window := some (0, 100), running := some (⟨9, 0, 0, 10⟩, 0) } 4).queue.length == 1
#guard
  let p : Phone := { queue := [⟨0, 0, 1, 50⟩, ⟨1, 0, 2, 50⟩], window := some (0, 100) }
  let q := dispatchHoL p 0
  q.running == some (⟨0, 0, 1, 50⟩, 0) && q.queue == [⟨1, 0, 2, 50⟩]
#guard (dispatchHoL { queue := [⟨0, 0, 1, 50⟩], window := some (10, 100) } 9).running == none
#guard (dispatchHoL { queue := [⟨0, 0, 1, 50⟩], window := some (10, 100) } 10).running == some (⟨0, 0, 1, 50⟩, 10)
#guard (dispatchHoL { queue := [⟨0, 0, 1, 50⟩], window := some (0, 59) } 10).running == none
#guard (dispatchHoL { queue := [⟨0, 0, 1, 50⟩], window := some (0, 60) } 10).running == some (⟨0, 0, 1, 50⟩, 10)
#guard (dispatchHoL { queue := [⟨0, 0, 1, 50⟩], window := some (0, 60), running := some (⟨9, 0, 0, 1⟩, 0) } 10).running
  == some (⟨9, 0, 0, 1⟩, 0)
-- tick: stops at the end of the duration or of the window, not before
#guard (tick { running := some (⟨0, 0, 0, 100⟩, 10), window := some (0, 1000) } 109).running == some (⟨0, 0, 0, 100⟩, 10)
#guard (tick { running := some (⟨0, 0, 0, 100⟩, 10), window := some (0, 1000) } 110).running == none
#guard (tick { running := some (⟨0, 0, 0, 100⟩, 10), window := some (0, 50) } 49).running == some (⟨0, 0, 0, 100⟩, 10)
#guard (tick { running := some (⟨0, 0, 0, 100⟩, 10), window := some (0, 50) } 50).running == none
#guard (tick { running := some (⟨0, 0, 0, 100⟩, 10), window := none } 500).running == some (⟨0, 0, 0, 100⟩, 10)
#guard (tick { running := some (⟨0, 0, 0, 100⟩, 10), queue := [⟨1, 0, 0, 1⟩], window := some (0, 50) } 50).queue.length == 1

end FwTest.Mutants.DeviceQueue
