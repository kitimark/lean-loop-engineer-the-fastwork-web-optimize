import Lean.Data.Json
/-!
# Fw.Measure.WalkBudget: the wall budget of one CI Simulator job
-/
namespace Fw.Measure.WalkBudget

/-- Milliseconds from the job start: the job timeout, the sum of the post step timeouts, the harness teardown after its deadline, and slack. -/
structure Job where
  timeoutMs : Nat
  postMs : Nat
  graceMs : Nat
  slackMs : Nat
deriving Repr, BEq

/-- 45 min as in smoothness.yml; post steps: keep host 3, shutdown 2, upload 2, telemetry 2 min (run 39957772249 took 0.2 to 4 min); grace 2 min; slack 1 min. -/
def job : Job := ⟨2700000, 540000, 120000, 60000⟩

def minuteMs : Nat := 60000

/-- Latest moment the walk may still run, in ms from the job start. -/
def deadlineAt (j : Job) : Nat := j.timeoutMs - j.postMs - j.graceMs - j.slackMs

/-- The deadline under an optional cap in ms counted from the walk start at `elapsed`. -/
def cappedDeadline (j : Job) (elapsed : Nat) : Option Nat → Nat
  | none => deadlineAt j
  | some cap => min (deadlineAt j) (elapsed + cap)

/-- The walk step's timeout in whole minutes when it starts at `elapsed`; 0 means the walk is skipped. -/
def stepMinutes (j : Job) (elapsed dl : Nat) : Nat := (dl + j.graceMs - elapsed) / minuteMs

/-- Run the walk step only when at least `needMin` minutes of it remain. -/
def runsWalk (j : Job) (elapsed dl needMin : Nat) : Bool := decide (needMin ≤ stepMinutes j elapsed dl)

/-- Start a window only if it can still finish before the deadline, given the shortest time a window needs. -/
def startsWindow (dl now reserve : Nat) : Bool := decide (now + reserve ≤ dl)

/-- Time an in-flight window may still take before it is abandoned. -/
def remaining (dl now : Nat) : Nat := dl - now

def Job.fits (j : Job) : Prop := j.postMs + j.graceMs + j.slackMs ≤ j.timeoutMs

theorem deadline_add_le (j : Job) (h : j.fits) : deadlineAt j + j.graceMs + j.postMs + j.slackMs ≤ j.timeoutMs := by
  unfold deadlineAt Job.fits at *
  omega

theorem cappedDeadline_le (j : Job) (elapsed : Nat) (cap : Option Nat) : cappedDeadline j elapsed cap ≤ deadlineAt j := by
  cases cap with
  | none => simp [cappedDeadline]
  | some c => simp [cappedDeadline, Nat.min_le_left]

theorem stepEnd_le (j : Job) (elapsed dl : Nat) (h : elapsed ≤ dl + j.graceMs) :
    elapsed + stepMinutes j elapsed dl * minuteMs ≤ dl + j.graceMs := by
  unfold stepMinutes
  have := Nat.div_mul_le_self (dl + j.graceMs - elapsed) minuteMs
  omega

/-- Job level: a walk step started at `elapsed` and capped by its timeout ends, with the post steps, inside the job timeout. -/
theorem job_ends_inside (j : Job) (h : j.fits) (elapsed cap : Nat) (hc : elapsed ≤ cappedDeadline j elapsed cap + j.graceMs) :
    elapsed + stepMinutes j elapsed (cappedDeadline j elapsed cap) * minuteMs + j.postMs + j.slackMs ≤ j.timeoutMs := by
  have h1 := stepEnd_le j elapsed (cappedDeadline j elapsed cap) hc
  have h2 := cappedDeadline_le j elapsed cap
  have h3 := deadline_add_le j h
  omega

theorem job_ends_inside_uncapped (j : Job) (h : j.fits) (elapsed : Nat) (hc : elapsed ≤ deadlineAt j + j.graceMs) :
    elapsed + stepMinutes j elapsed (deadlineAt j) * minuteMs + j.postMs + j.slackMs ≤ j.timeoutMs := by
  have h1 := stepEnd_le j elapsed (deadlineAt j) hc
  have h3 := deadline_add_le j h
  omega

theorem job_fits : job.fits := by simp [Job.fits, job]

theorem startsWindow_false (dl now reserve : Nat) (h : dl < now + reserve) : startsWindow dl now reserve = false := by
  simp [startsWindow]; omega

theorem startsWindow_true (dl now reserve : Nat) (h : now + reserve ≤ dl) : startsWindow dl now reserve = true := by
  simp [startsWindow, h]

theorem startsWindow_ends (dl now reserve : Nat) (h : startsWindow dl now reserve = true) : now + reserve ≤ dl := by
  simpa [startsWindow] using h

theorem remaining_ends (dl now : Nat) (h : now ≤ dl) : now + remaining dl now = dl := by
  unfold remaining; omega

theorem runsWalk_false (j : Job) (elapsed dl needMin : Nat) (h : stepMinutes j elapsed dl < needMin) : runsWalk j elapsed dl needMin = false := by
  simp [runsWalk]; omega

theorem runsWalk_true (j : Job) (elapsed dl needMin : Nat) (h : needMin ≤ stepMinutes j elapsed dl) : runsWalk j elapsed dl needMin = true := by
  simp [runsWalk, h]

/-- A fixed sum of per-window bounds cannot be the rule: 18 touch windows at the 145,600 ms bound already exceed the deadline (run 39957772249 job 1). -/
theorem static_sum_exceeds : deadlineAt job < 18 * 145600 := by decide

theorem deadline_value : deadlineAt job = 1980000 := by decide

def stepCases : List (String × Nat × Option Nat) := [
  ("walk starts after 4.6 min", 276000, none),
  ("walk starts at the job start", 0, none),
  ("walk starts at the deadline", 1980000, none),
  ("walk starts in the grace", 2000000, none),
  ("walk starts too late", 2100000, none),
  ("cap 8 min", 276000, some 480000),
  ("cap above the deadline", 276000, some 3000000)]

def startCases : List (String × Nat × Nat × Nat) := [
  ("plenty of time", 1980000, 100000, 30000),
  ("exactly the reserve", 1980000, 1950000, 30000),
  ("one ms short", 1980000, 1950001, 30000),
  ("past the deadline", 1980000, 2000000, 30000)]

open Lean in
def goldenLines (_ : Unit := ()) : List String :=
  let consts := (Json.mkObj [("op", "constants"), ("timeoutMs", toJson job.timeoutMs), ("postMs", toJson job.postMs),
    ("graceMs", toJson job.graceMs), ("slackMs", toJson job.slackMs), ("deadlineAt", toJson (deadlineAt job))]).compress
  let ss := stepCases.map fun (name, elapsed, cap) =>
    let dl := cappedDeadline job elapsed cap
    (Json.mkObj [("op", "step"), ("case", Json.str name), ("elapsedMs", toJson elapsed),
      ("capMs", match cap with | some v => toJson v | none => Json.null), ("deadlineMs", toJson dl),
      ("stepMinutes", toJson (stepMinutes job elapsed dl)), ("runs", toJson (runsWalk job elapsed dl 2))]).compress
  let ws := startCases.map fun (name, dl, now, reserve) =>
    (Json.mkObj [("op", "start"), ("case", Json.str name), ("deadlineMs", toJson dl), ("nowMs", toJson now),
      ("reserveMs", toJson reserve), ("starts", toJson (startsWindow dl now reserve)),
      ("remainingMs", toJson (remaining dl now))]).compress
  [consts] ++ ss ++ ws

def goldenText (_ : Unit := ()) : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

def argAfter : List String → String → Option String
  | a :: b :: rest, flag => if a == flag then some b else argAfter (b :: rest) flag
  | _, _ => none

def run (args : List String) : IO UInt32 := do
  match argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"walk-budget golden: {path} is up to date ({goldenLines.length} lines)"
      return 0
    IO.eprintln s!"walk-budget golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print goldenText
    return 0

end Fw.Measure.WalkBudget
