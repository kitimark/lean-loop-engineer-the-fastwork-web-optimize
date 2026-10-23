import Lean.Data.Json
import Fw.Gate.Smooth
/-!
# Fw.Measure.WalkBudget: the wall budget of one CI Simulator job and the rep plan that fits it
-/
namespace Fw.Measure.WalkBudget

/-- Budget of one `webkit-sim` job in ms: job timeout, post-step allowance, grace on the walk step, slack for the named gaps. -/
structure Job where
  timeoutMs : Nat
  postMs : Nat
  graceMs : Nat
  slackMs : Nat
deriving Repr, BEq

/-- smoothness.yml `webkit-sim`: 45 min; post steps 10 min (host state 1, upload 2, upload retry 2, shutdown 2, telemetry 2 = 9 under 10); grace 2 min; slack 1 min. -/
def job : Job := ⟨2700000, 600000, 120000, 60000⟩

/-- The post steps of the job with their `timeout-minutes`, in ms. -/
def postSteps : List (String × Nat) :=
  [("host state", 60000), ("upload", 120000), ("upload retry", 120000), ("shutdown", 120000), ("telemetry", 120000)]

def postStepsMs : Nat := (postSteps.map (·.2)).foldl (· + ·) 0

theorem postSteps_fit : postStepsMs + 60000 = job.postMs := by decide

/-- Time the deadline does not see, each with the longest value of the three jobs of run 40003317485. -/
structure Gaps where
  clockMs : Nat
  driftMs : Nat
  completeMs : Nat
deriving Repr, BEq

/-- `clockMs`: runner job start to the Job clock step (3 to 6 s); `driftMs`: the Walk budget step reads the clock, the walk starts after the step ends (22 to 50 s on a starved host); `completeMs`: the runner's Post and Complete job steps (1 to 4 s). -/
def gaps : Gaps := ⟨6000, 50000, 4000⟩

def Gaps.total (g : Gaps) : Nat := g.clockMs + g.driftMs + g.completeMs

theorem gaps_total : gaps.total = job.slackMs := by decide

/-- The harness's process group is killed this long after the walk deadline. -/
def hardStopMs : Nat := 45000

def minuteMs : Nat := 60000

def deadlineAt (j : Job) : Nat := j.timeoutMs - j.postMs - j.graceMs - j.slackMs

def cappedDeadline (j : Job) (elapsed : Nat) : Option Nat → Nat
  | none => deadlineAt j
  | some cap => min (deadlineAt j) (elapsed + cap)

def stepMinutes (j : Job) (elapsed dl : Nat) : Nat := (dl + j.graceMs - elapsed) / minuteMs

def runsWalk (j : Job) (elapsed dl needMin : Nat) : Bool := decide (needMin ≤ stepMinutes j elapsed dl)

def startsWindow (dl now reserve : Nat) : Bool := decide (now + reserve ≤ dl)

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

theorem stepEnd_gt (j : Job) (elapsed dl : Nat) (h : elapsed ≤ dl + j.graceMs) :
    dl + j.graceMs < elapsed + stepMinutes j elapsed dl * minuteMs + minuteMs := by
  unfold stepMinutes
  have := Nat.lt_div_mul_add (a := dl + j.graceMs - elapsed) (b := minuteMs) (by decide)
  omega

theorem hardStop_inside_step (j : Job) (elapsed dl : Nat) (hg : minuteMs + hardStopMs ≤ j.graceMs) (h : elapsed ≤ dl + j.graceMs) :
    dl + hardStopMs < elapsed + stepMinutes j elapsed dl * minuteMs := by
  have := stepEnd_gt j elapsed dl h
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

theorem static_sum_exceeds : deadlineAt job < 18 * 145600 := by decide

theorem deadline_value : deadlineAt job = 1920000 := by decide

theorem job_ends_inside_gaps (elapsed : Nat) (hc : elapsed ≤ deadlineAt job + job.graceMs) :
    elapsed + gaps.clockMs + gaps.driftMs + stepMinutes job elapsed (deadlineAt job) * minuteMs + job.postMs + gaps.completeMs ≤ job.timeoutMs := by
  have h1 := job_ends_inside_uncapped job job_fits elapsed hc
  have h2 := gaps_total
  unfold Gaps.total at h2
  omega

/-- Kept end windows per arm that one job needs to decide (`Fw.Gate.Smooth.minReps`). -/
def minKept : Nat := Fw.Gate.Smooth.minReps

theorem minKept_value : minKept = 5 := by decide

/-- A rep is one hero and one end window of every arm. -/
def windowsPerRep (arms : Nat) : Nat := 2 * arms

/-- Time allowed per window: the mean over 144 windows of the four complete walks of runs 39934951574 and 39995201296 is 35.6 s, the slowest job 42.9 s. -/
def windowMs : Nat := 45000

/-- The Simulator tends to die after about 30 to 40 windows; one job plans at most this many. -/
def lifeWindows : Nat := 36

def repMs (arms : Nat) : Nat := windowsPerRep arms * windowMs

/-- Whole reps that fit between `now` and the deadline `dl`. -/
def repsFit (dl now arms : Nat) : Nat := (dl - now) / repMs arms

/-- Whole reps that fit in the Simulator's life. -/
def repsLife (arms : Nat) : Nat := lifeWindows / windowsPerRep arms

/-- Reps one job plans: both bounds. -/
def planReps (dl now arms : Nat) : Nat := min (repsLife arms) (repsFit dl now arms)

inductive Outcome where
  | ok
  | lifeShort
  | budgetShort
deriving Repr, BEq, DecidableEq

/-- Whether the planned reps give every arm `minKept` end windows; the life bound is decided first, it does not depend on the clock. -/
def outcome (dl now arms : Nat) : Outcome :=
  if repsLife arms < minKept then .lifeShort else if repsFit dl now arms < minKept then .budgetShort else .ok

def Outcome.name : Outcome → String
  | .ok => "ok"
  | .lifeShort => "lifeShort"
  | .budgetShort => "budgetShort"

/-- End windows of the arm at position `pos` of the rep order after `n` windows of the rep-major walk (hero then end per arm). -/
def endsDone (n arms pos : Nat) : Nat := n / windowsPerRep arms + if 2 * pos + 2 ≤ n % windowsPerRep arms then 1 else 0

theorem planReps_fits (dl now arms : Nat) : planReps dl now arms * repMs arms ≤ dl - now :=
  Nat.le_trans (Nat.mul_le_mul_right _ (Nat.min_le_right _ _)) (Nat.div_mul_le_self _ _)

theorem planReps_life (arms : Nat) (dl now : Nat) : planReps dl now arms * windowsPerRep arms ≤ lifeWindows :=
  Nat.le_trans (Nat.mul_le_mul_right _ (Nat.min_le_left _ _)) (Nat.div_mul_le_self _ _)

theorem outcome_lifeShort (dl now arms : Nat) (h : repsLife arms < minKept) : outcome dl now arms = .lifeShort := by
  simp [outcome, h]

theorem outcome_budgetShort (dl now arms : Nat) (hl : minKept ≤ repsLife arms) (h : repsFit dl now arms < minKept) :
    outcome dl now arms = .budgetShort := by
  have : ¬ repsLife arms < minKept := by omega
  simp [outcome, this, h]

theorem outcome_ok (dl now arms : Nat) (hl : minKept ≤ repsLife arms) (h : minKept ≤ repsFit dl now arms) :
    outcome dl now arms = .ok := by
  have h1 : ¬ repsLife arms < minKept := by omega
  have h2 : ¬ repsFit dl now arms < minKept := by omega
  simp [outcome, h1, h2]

theorem outcome_ok_plan (dl now arms : Nat) (h : outcome dl now arms = .ok) : minKept ≤ planReps dl now arms := by
  unfold outcome at h
  unfold planReps
  split at h
  · cases h
  · split at h
    · cases h
    · omega

theorem outcome_ok_time (dl now arms : Nat) (h : outcome dl now arms = .ok) :
    minKept * windowsPerRep arms * windowMs ≤ dl - now := by
  have := outcome_ok_plan dl now arms h
  have h2 := planReps_fits dl now arms
  unfold repMs at h2
  calc minKept * windowsPerRep arms * windowMs = minKept * (windowsPerRep arms * windowMs) := Nat.mul_assoc _ _ _
    _ ≤ planReps dl now arms * (windowsPerRep arms * windowMs) := Nat.mul_le_mul_right _ this
    _ ≤ dl - now := h2

theorem endsDone_ge (n arms pos : Nat) : n / windowsPerRep arms ≤ endsDone n arms pos := by
  unfold endsDone
  omega

theorem endsDone_le (n arms pos : Nat) : endsDone n arms pos ≤ n / windowsPerRep arms + 1 := by
  unfold endsDone
  split <;> omega

theorem kept_after (n arms pos : Nat) (ha : 0 < arms) (h : minKept * windowsPerRep arms ≤ n) : minKept ≤ endsDone n arms pos := by
  have hw : 0 < windowsPerRep arms := by unfold windowsPerRep; omega
  have := (Nat.le_div_iff_mul_le hw).2 h
  exact Nat.le_trans this (endsDone_ge n arms pos)

theorem planReps_complete (dl now arms : Nat) (ha : 0 < arms) (h : outcome dl now arms = .ok) (pos : Nat) :
    minKept ≤ endsDone (planReps dl now arms * windowsPerRep arms) arms pos :=
  kept_after _ arms pos ha (Nat.mul_le_mul_right _ (outcome_ok_plan dl now arms h))

def stepCases : List (String × Nat × Option Nat) := [
  ("walk starts after 4.6 min", 276000, none),
  ("walk starts at the job start", 0, none),
  ("walk starts at the deadline", 1920000, none),
  ("walk starts in the grace", 1950000, none),
  ("walk starts too late", 2100000, none),
  ("cap 8 min", 276000, some 480000),
  ("cap above the deadline", 276000, some 3000000)]

def startCases : List (String × Nat × Nat × Nat) := [
  ("plenty of time", 1920000, 100000, 30000),
  ("exactly the reserve", 1920000, 1890000, 30000),
  ("one ms short", 1920000, 1890001, 30000),
  ("past the deadline", 1920000, 2000000, 30000)]

def planCases : List (String × Nat × Option Nat × Nat) := [
  ("3 arms, walk starts after 4.6 min", 276000, none, 3),
  ("3 arms, walk starts after 8 min", 480000, none, 3),
  ("3 arms, walk starts after 10 min", 600000, none, 3),
  ("3 arms, cap 10 min", 276000, some 600000, 3),
  ("2 arms", 276000, none, 2),
  ("4 arms", 276000, none, 4),
  ("no arms", 276000, none, 0)]

open Lean in
def goldenLines (_ : Unit := ()) : List String :=
  let consts := (Json.mkObj [("op", "constants"), ("timeoutMs", toJson job.timeoutMs), ("postMs", toJson job.postMs),
    ("graceMs", toJson job.graceMs), ("slackMs", toJson job.slackMs), ("deadlineAt", toJson (deadlineAt job)),
    ("hardStopMs", toJson hardStopMs), ("postStepsMs", toJson postStepsMs), ("clockMs", toJson gaps.clockMs),
    ("driftMs", toJson gaps.driftMs), ("completeMs", toJson gaps.completeMs), ("minKept", toJson minKept),
    ("windowMs", toJson windowMs), ("lifeWindows", toJson lifeWindows)]).compress
  let ss := stepCases.map fun (name, elapsed, cap) =>
    let dl := cappedDeadline job elapsed cap
    let runs := runsWalk job elapsed dl 2
    let base := [("op", Json.str "step"), ("case", Json.str name), ("elapsedMs", toJson elapsed),
      ("capMs", match cap with | some v => toJson v | none => Json.null), ("deadlineMs", toJson dl),
      ("stepMinutes", toJson (stepMinutes job elapsed dl)), ("runs", toJson runs)]
    (Json.mkObj (if runs then base ++ [("hardStopInside", toJson (decide (dl + hardStopMs < elapsed + stepMinutes job elapsed dl * minuteMs)))] else base)).compress
  let ws := startCases.map fun (name, dl, now, reserve) =>
    (Json.mkObj [("op", "start"), ("case", Json.str name), ("deadlineMs", toJson dl), ("nowMs", toJson now),
      ("reserveMs", toJson reserve), ("starts", toJson (startsWindow dl now reserve)),
      ("remainingMs", toJson (remaining dl now))]).compress
  let ps := planCases.map fun (name, elapsed, cap, arms) =>
    let dl := cappedDeadline job elapsed cap
    (Json.mkObj [("op", "plan"), ("case", Json.str name), ("elapsedMs", toJson elapsed),
      ("capMs", match cap with | some v => toJson v | none => Json.null), ("deadlineMs", toJson dl), ("arms", toJson arms),
      ("repsFit", toJson (repsFit dl elapsed arms)), ("repsLife", toJson (repsLife arms)),
      ("reps", toJson (planReps dl elapsed arms)), ("outcome", Json.str (outcome dl elapsed arms).name)]).compress
  let es := [(3, 0, 0), (3, 7, 0), (3, 7, 1), (3, 8, 1), (3, 30, 2), (3, 29, 2), (3, 36, 0), (2, 17, 1)].map fun (arms, n, pos) =>
    (Json.mkObj [("op", "ends"), ("arms", toJson arms), ("windows", toJson n), ("pos", toJson pos),
      ("endsDone", toJson (endsDone n arms pos))]).compress
  [consts] ++ ss ++ ws ++ ps ++ es

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
