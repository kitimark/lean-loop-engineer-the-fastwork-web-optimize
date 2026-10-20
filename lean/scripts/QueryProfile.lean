import Fw.Serve
import Fw.Wire.Plan
import Fw.Plan.FastView
/-! Local debug profile of the pieces of `console.query` (task fwcore-query-speed; not a CI result).
Run from `lean/`: `lake env lean --run scripts/QueryProfile.lean <events.jsonl>`. Interpreted, so read the numbers
as a ratio between the pieces, not as seconds of the compiled binary. -/
open Lean Fw.Plan in
def timed (name : String) (f : Unit → Nat) : IO Unit := do
  let t0 ← IO.monoMsNow
  let n := f ()
  IO.println s!"{name}: {n} ({(← IO.monoMsNow) - t0} ms)"

open Lean Fw.Plan in
def main (args : List String) : IO Unit := do
  let txt ← IO.FS.readFile args.head!
  let evs := (txt.splitOn "\n").filter (· ≠ "") |>.filterMap fun l =>
    match Json.parse l with
    | .ok j => (Fw.Wire.Plan.eventOfJson j).toOption
    | .error _ => none
  let (v, _) := Fw.Serve.exec Fw.Serve.init (.replay evs)
  let p := Fw.Plan.unrev v.plan
  let q := Fw.Plan.quietMs
  let now := 1792400000000
  IO.println s!"events {evs.length} tasks {p.tasks.length} spawns {p.spawns.length} stops {p.stops.length} labels {p.labels.length}"
  let b := bound q now p
  timed "bound" fun _ => (boundF q now p).length
  timed "tstate" fun _ => (b.map (tstate b)).length
  timed "blockers" fun _ => (b.map (blockers b)).length
  timed "taskView" fun _ => (b.map (taskView p b)).length
  timed "readyIn" fun _ => (readyIn b .agent).length
  timed "groupsF" fun _ => (groupsF b).length
  timed "criticalPath" fun _ => (fastCriticalPath (kept p.tasks)).length
  timed "milestones" fun _ => (p.milestones.map (msView p.tasks)).length
  timed "view" fun _ => (fastView q now p).tasks.length
  timed "fastBoard" fun _ => (Fw.Serve.fastBoard v.st now 1).cards.length
