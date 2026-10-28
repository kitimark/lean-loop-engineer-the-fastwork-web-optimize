import Lean.Data.Json
/-!
# The sweep-paused verdict
Reads `packages/measure-wktr/src/sweep-pause.mjs`: per job, paused against unpaused sweepDoc animations in a flip and in idle.
-/
namespace Fw.Device.SweepPause
open Lean

structure Arm where
  frames : Nat
  recalcs : Nat
  styleFrames : Nat
  styleUs : Nat
  layoutUs : Nat
  deriving DecidableEq, Repr

def Arm.rpf100 (a : Arm) : Nat := if a.frames = 0 then 0 else a.recalcs * 100 / a.frames

def Arm.styleUsPerFrame (a : Arm) : Nat := if a.styleFrames = 0 then 0 else a.styleUs / a.styleFrames

structure Job where
  flipU : Arm
  flipP : Arm
  idleU : Arm
  idleP : Arm
  deriving DecidableEq, Repr

/-- Recalcs per frame times 100 that idle unpaused must show for the pause to have something to remove (reference 2 per frame, INFERRED). -/
def idleOnMin : Nat := 150

def idleOffMax : Nat := 25

def explainMin : Int := 750

def notMax : Int := 250

def minStyleUs : Nat := 100

def dropPm (u p : Nat) : Int := if u = 0 then 0 else ((u : Int) - p) * 1000 / u

def Job.hasFrames (j : Job) : Bool := 0 < j.flipU.frames && 0 < j.flipP.frames && 0 < j.idleU.frames && 0 < j.idleP.frames

def Job.idleOn (j : Job) : Bool := idleOnMin ≤ j.idleU.rpf100

def Job.idleOff (j : Job) : Bool := j.idleP.rpf100 ≤ idleOffMax

def Job.rpfDrop (j : Job) : Int := dropPm j.flipU.rpf100 j.flipP.rpf100

def Job.styleUsable (j : Job) : Bool := minStyleUs ≤ j.flipU.styleUsPerFrame

def Job.styleDrop (j : Job) : Int := dropPm j.flipU.styleUsPerFrame j.flipP.styleUsPerFrame

def Job.explainsB (j : Job) : Bool := explainMin ≤ j.rpfDrop && j.styleUsable && explainMin ≤ j.styleDrop

def Job.notSweepB (j : Job) : Bool := j.rpfDrop < notMax && (!j.styleUsable || j.styleDrop < notMax)

inductive Why where
  | noFrames | idleNotOn | idleNotOff | explains | notSweep | mixed
  deriving DecidableEq

def Why.name : Why → String
  | .noFrames => "no-frames" | .idleNotOn => "idle-not-on" | .idleNotOff => "idle-not-off"
  | .explains => "explains" | .notSweep => "not-sweep" | .mixed => "partial"

def Job.why (j : Job) : Why :=
  if !j.hasFrames then .noFrames
  else if !j.idleOn then .idleNotOn
  else if !j.idleOff then .idleNotOff
  else if j.explainsB then .explains
  else if j.notSweepB then .notSweep
  else .mixed

def Why.valid : Why → Bool
  | .explains | .notSweep | .mixed => true
  | _ => false

theorem why_noFrames (j : Job) (h : j.hasFrames = false) : j.why = .noFrames := by
  simp [Job.why, h]

theorem why_idleNotOn (j : Job) (h1 : j.hasFrames = true) (h : j.idleOn = false) : j.why = .idleNotOn := by
  simp [Job.why, h1, h]

theorem why_idleNotOff (j : Job) (h1 : j.hasFrames = true) (h2 : j.idleOn = true) (h : j.idleOff = false) :
    j.why = .idleNotOff := by
  simp [Job.why, h1, h2, h]

theorem why_explains (j : Job) (h1 : j.hasFrames = true) (h2 : j.idleOn = true) (h3 : j.idleOff = true)
    (h : j.explainsB = true) : j.why = .explains := by
  simp [Job.why, h1, h2, h3, h]

theorem why_notSweep (j : Job) (h1 : j.hasFrames = true) (h2 : j.idleOn = true) (h3 : j.idleOff = true)
    (h : j.explainsB = false) (h' : j.notSweepB = true) : j.why = .notSweep := by
  simp [Job.why, h1, h2, h3, h, h']

theorem why_mixed (j : Job) (h1 : j.hasFrames = true) (h2 : j.idleOn = true) (h3 : j.idleOff = true)
    (h : j.explainsB = false) (h' : j.notSweepB = false) : j.why = .mixed := by
  simp [Job.why, h1, h2, h3, h, h']

theorem thresholds_ordered : notMax < explainMin := by decide

theorem explains_not_notSweep (j : Job) : ¬(j.explainsB = true ∧ j.notSweepB = true) := by
  rintro ⟨h1, h2⟩
  simp only [Job.explainsB, Job.notSweepB, Bool.and_eq_true, decide_eq_true_eq, Bool.or_eq_true, Bool.not_eq_true'] at h1 h2
  have := thresholds_ordered
  rcases h1 with ⟨⟨a, b⟩, c⟩
  rcases h2 with ⟨d, e | e⟩
  · rw [b] at e; exact absurd e (by decide)
  · omega

theorem why_explains_iff (j : Job) (h1 : j.hasFrames = true) (h2 : j.idleOn = true) (h3 : j.idleOff = true) :
    j.why = .explains ↔ j.explainsB = true := by
  unfold Job.why
  simp only [h1, h2, h3]
  cases j.explainsB <;> cases j.notSweepB <;> simp

theorem why_notSweep_iff (j : Job) (h1 : j.hasFrames = true) (h2 : j.idleOn = true) (h3 : j.idleOff = true) :
    j.why = .notSweep ↔ j.notSweepB = true := by
  have hx := explains_not_notSweep j
  unfold Job.why
  simp only [h1, h2, h3]
  cases hE : j.explainsB <;> cases hN : j.notSweepB <;> simp_all

inductive Verdict where
  | explains | mixed | notSweep | inconclusive
  deriving DecidableEq

def Verdict.name : Verdict → String
  | .explains => "sweep explains" | .mixed => "sweep partial" | .notSweep => "not the sweep" | .inconclusive => "inconclusive"

/-- At least this many jobs must be valid for a verdict. -/
def minValid : Nat := 2

def overall (js : List Job) : Verdict :=
  let ws := (js.map Job.why).filter Why.valid
  if ws.length < minValid then .inconclusive
  else if ws.all (· == .explains) then .explains
  else if ws.all (· == .notSweep) then .notSweep
  else .mixed

theorem overall_inconclusive (js : List Job) (h : ((js.map Job.why).filter Why.valid).length < minValid) :
    overall js = .inconclusive := by
  simp [overall, h]

theorem overall_explains (js : List Job) (h0 : ¬ ((js.map Job.why).filter Why.valid).length < minValid)
    (h : ((js.map Job.why).filter Why.valid).all (· == .explains) = true) : overall js = .explains := by
  simp only [overall, h0, h]
  simp

theorem overall_notSweep (js : List Job) (h0 : ¬ ((js.map Job.why).filter Why.valid).length < minValid)
    (h : ((js.map Job.why).filter Why.valid).all (· == .notSweep) = true)
    (hn : ((js.map Job.why).filter Why.valid).all (· == .explains) = false) : overall js = .notSweep := by
  simp only [overall, h0, h, hn]
  simp

theorem overall_mixed (js : List Job) (h0 : ¬ ((js.map Job.why).filter Why.valid).length < minValid)
    (he : ((js.map Job.why).filter Why.valid).all (· == .explains) = false)
    (hn : ((js.map Job.why).filter Why.valid).all (· == .notSweep) = false) : overall js = .mixed := by
  simp only [overall, h0, he, hn]
  simp

inductive Next where
  | compositorAndPhone | elementCountsThenCompositor | elementCounts | rerun
  deriving DecidableEq

def Next.name : Next → String
  | .compositorAndPhone => "geom-sweep-compositor and a phone session"
  | .elementCountsThenCompositor => "element counts per recalc, then geom-sweep-compositor for the sweep share"
  | .elementCounts => "element counts per recalc"
  | .rerun => "rerun with more valid jobs"

def Verdict.next : Verdict → Next
  | .explains => .compositorAndPhone
  | .mixed => .elementCountsThenCompositor
  | .notSweep => .elementCounts
  | .inconclusive => .rerun

theorem next_phone_iff (v : Verdict) : v.next = .compositorAndPhone ↔ v = .explains := by
  cases v <;> simp [Verdict.next]

private def arm (f r sf s l : Nat) : Arm := ⟨f, r, sf, s, l⟩

/-- Named cases; the first four are shaped like the reference readings (idle 2 recalcs per frame, flip 2 to 4). -/
def cases : List (String × Job) :=
  [("explains", ⟨arm 4 12 4 4000 0, arm 4 1 4 400 0, arm 40 80 40 6000 0, arm 40 0 40 0 0⟩),
   ("not the sweep", ⟨arm 4 12 4 4000 0, arm 4 12 4 3800 0, arm 40 80 40 6000 0, arm 40 0 40 0 0⟩),
   ("rpf drops, style stays", ⟨arm 4 12 4 4000 0, arm 4 1 4 3800 0, arm 40 80 40 6000 0, arm 40 0 40 0 0⟩),
   ("style drops, rpf stays", ⟨arm 4 12 4 4000 0, arm 4 12 4 400 0, arm 40 80 40 6000 0, arm 40 0 40 0 0⟩),
   ("partial half", ⟨arm 4 12 4 4000 0, arm 4 6 4 2000 0, arm 40 80 40 6000 0, arm 40 0 40 0 0⟩),
   ("style silent", ⟨arm 4 12 4 100 0, arm 4 1 4 0 0, arm 40 80 40 100 0, arm 40 0 40 0 0⟩),
   ("idle not on", ⟨arm 4 12 4 4000 0, arm 4 1 4 400 0, arm 40 20 40 600 0, arm 40 0 40 0 0⟩),
   ("idle not off", ⟨arm 4 12 4 4000 0, arm 4 1 4 400 0, arm 40 80 40 6000 0, arm 40 40 40 3000 0⟩),
   ("no frames", ⟨arm 0 0 0 0 0, arm 4 1 4 400 0, arm 40 80 40 6000 0, arm 40 0 40 0 0⟩),
   ("flip grew", ⟨arm 4 8 4 2000 0, arm 4 12 4 4000 0, arm 40 80 40 6000 0, arm 40 0 40 0 0⟩),
   ("edge explains", ⟨arm 4 16 4 4000 0, arm 4 4 4 1000 0, arm 40 60 40 6000 0, arm 40 10 40 0 0⟩),
   ("edge not", ⟨arm 4 16 4 4000 0, arm 4 13 4 3100 0, arm 40 60 40 6000 0, arm 40 10 40 0 0⟩)]

def caseJob (n : String) : Job := ((cases.find? (·.1 == n)).map (·.2)).getD ⟨arm 0 0 0 0 0, arm 0 0 0 0 0, arm 0 0 0 0 0, arm 0 0 0 0 0⟩

def combos : List (String × List String) :=
  [("three explain", ["explains", "explains", "explains"]),
   ("two explain, one void", ["explains", "idle not on", "explains"]),
   ("one explains, one valid void", ["explains", "idle not on", "no frames"]),
   ("three not", ["not the sweep", "not the sweep", "not the sweep"]),
   ("explain and not", ["explains", "not the sweep", "explains"]),
   ("explains and partial", ["explains", "partial half", "explains"]),
   ("all partial", ["partial half", "partial half", "rpf drops, style stays"]),
   ("not and partial", ["not the sweep", "partial half", "not the sweep"]),
   ("none valid", ["idle not on", "idle not off", "no frames"]),
   ("style silent three", ["style silent", "style silent", "style silent"]),
   ("two jobs", ["explains", "explains"]),
   ("no jobs", [])]

private def armJ (a : Arm) : Json :=
  Json.mkObj [("frames", a.frames), ("recalcs", a.recalcs), ("styleFrames", a.styleFrames), ("styleUs", a.styleUs), ("layoutUs", a.layoutUs)]

private def jobJ (j : Job) : Json :=
  Json.mkObj [("flipU", armJ j.flipU), ("flipP", armJ j.flipP), ("idleU", armJ j.idleU), ("idleP", armJ j.idleP)]

private def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("idleOnMin", idleOnMin), ("idleOffMax", idleOffMax), ("explainMin", explainMin),
    ("notMax", notMax), ("minStyleUs", minStyleUs), ("minValid", minValid)]).compress] ++
  (cases.map fun (n, j) =>
    (Json.mkObj [("kind", "job"), ("name", n), ("job", jobJ j), ("flipU", j.flipU.rpf100), ("flipP", j.flipP.rpf100),
      ("idleU", j.idleU.rpf100), ("idleP", j.idleP.rpf100), ("styleU", j.flipU.styleUsPerFrame), ("styleP", j.flipP.styleUsPerFrame),
      ("rpfDrop", j.rpfDrop), ("styleDrop", j.styleDrop), ("why", j.why.name), ("valid", j.why.valid)]).compress) ++
  (combos.map fun (n, ns) =>
    let v := overall (ns.map caseJob)
    (Json.mkObj [("kind", "overall"), ("name", n), ("jobs", Json.arr (ns.map Json.str).toArray), ("verdict", v.name),
      ("next", v.next.name)]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"device-sweep-pause golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"device-sweep-pause golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

def checkRepo (path : String) : IO Unit := do
  if (← run ["--check", path]) != 0 then throw (IO.userError "device-sweep-pause golden differs")

end Fw.Device.SweepPause
