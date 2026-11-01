import Lean.Data.Json
import Fw.Gate.Smooth
import Fw.Measure.WktrLayout
namespace Fw.Measure.WalkBudget

open Fw.Gate.Smooth (Verdict)

structure Job where
  timeoutMs : Nat
  postMs : Nat
  graceMs : Nat
  slackMs : Nat
deriving Repr, BEq

def job : Job := ⟨3600000, 600000, 120000, 480000⟩

def postSteps : List (String × Nat) :=
  [("host state", 60000), ("upload", 120000), ("upload retry", 120000), ("shutdown", 120000), ("telemetry", 120000)]

def postStepsMs : Nat := (postSteps.map (·.2)).foldl (· + ·) 0

theorem postSteps_fit : postStepsMs + 60000 = job.postMs := by decide

structure Gaps where
  clockMs : Nat
  driftMs : Nat
  completeMs : Nat
  overrunMs : Nat
deriving Repr, BEq

def gaps : Gaps := ⟨6000, 50000, 4000, 420000⟩

def Gaps.total (g : Gaps) : Nat := g.clockMs + g.driftMs + g.completeMs + g.overrunMs

theorem gaps_total : gaps.total = job.slackMs := by decide

/-- A walk step that ran 380 s past its step timeout (run 41285184069) still ends inside the job. -/
theorem overrun_covers_seen : 380000 ≤ gaps.overrunMs := by decide

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

theorem deadline_value : deadlineAt job = 2400000 := by decide

theorem job_ends_inside_gaps (elapsed : Nat) (hc : elapsed ≤ deadlineAt job + job.graceMs) :
    elapsed + gaps.clockMs + gaps.driftMs + gaps.overrunMs + stepMinutes job elapsed (deadlineAt job) * minuteMs + job.postMs + gaps.completeMs ≤ job.timeoutMs := by
  have h1 := job_ends_inside_uncapped job job_fits elapsed hc
  have h2 := gaps_total
  unfold Gaps.total at h2
  omega

/-! ## The window budget: a tail quantile, not the mean -/

/-- Seconds each Simulator window took, sorted, from the walk logs of runs 40023506144, 41270567124, 41275699141, 41285184069 and 41289882234 (n = 216; the slowest are 285, 383, 398, 432 and 744 s). -/
def windowSecs : List Nat := [
  7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 9, 9, 9, 9,
  9, 9, 9, 9, 9, 9, 9, 9, 9, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 11, 11, 11, 11, 11,
  11, 11, 11, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 13, 13, 13, 13, 13, 13, 13, 13, 14, 14,
  14, 14, 14, 14, 14, 14, 14, 15, 15, 15, 15, 15, 15, 15, 16, 16, 16, 16, 16, 16, 16, 16, 16, 17,
  17, 17, 17, 17, 17, 17, 17, 17, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 19, 19, 19, 19, 19, 19,
  19, 19, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 21, 21, 21, 21, 21, 21, 21, 22, 22, 22, 23,
  23, 24, 24, 24, 24, 25, 25, 25, 25, 25, 25, 26, 26, 26, 27, 28, 28, 29, 29, 29, 29, 31, 31, 31,
  31, 33, 33, 33, 34, 36, 36, 37, 38, 39, 39, 42, 43, 44, 47, 48, 52, 53, 53, 53, 53, 54, 54, 55,
  63, 66, 69, 71, 74, 75, 81, 84, 84, 85, 85, 85, 125, 152, 172, 175, 196, 208, 217, 285, 383, 398, 432, 744]

/-- The `pct`-th percentile of a sorted list (nearest rank). -/
def quantile (xs : List Nat) (pct : Nat) : Nat := xs.getD ((pct * xs.length + 99) / 100 - 1) 0

def bodyMs : Nat := quantile windowSecs 75 * 1000

def tailMs : Nat := quantile windowSecs 99 * 1000

def meanMs : Nat := windowSecs.sum * 1000 / windowSecs.length

/-- One tail-length slot is budgeted per this many windows. -/
def tailEvery : Nat := 20

/-- The time reserved for `n` windows: the body quantile each, plus one tail quantile slot per started `tailEvery` windows. -/
def blockMs (n : Nat) : Nat := n * bodyMs + (n + tailEvery - 1) / tailEvery * (tailMs - bodyMs)

theorem bodyMs_value : bodyMs = 29000 := by decide +kernel

theorem tailMs_value : tailMs = 398000 := by decide +kernel

theorem meanMs_value : meanMs = 37490 := by decide +kernel

theorem blockMs_zero : blockMs 0 = 0 := by decide +kernel

theorem blockMs_mono (n m : Nat) (h : n ≤ m) : blockMs n ≤ blockMs m := by
  unfold blockMs
  exact Nat.add_le_add (Nat.mul_le_mul_right _ h) (Nat.mul_le_mul_right _ (by unfold tailEvery; omega))

/-- The block budget is above what the mean window time would need. -/
theorem blockMs_over_mean (n : Nat) : n * meanMs ≤ blockMs n := by
  rw [meanMs_value]
  unfold blockMs tailEvery
  rw [bodyMs_value, tailMs_value]
  omega

/-! ## Shapes, reps and the plan -/

def minKept : Nat := Fw.Gate.Smooth.minReps

theorem minKept_value : minKept = 5 := by decide

/-- `full` walks a hero and an end window per arm and rep; `endOnly` only the end window (the touch lanes decide on it). -/
inductive Shape where
  | full
  | endOnly
deriving Repr, BEq, DecidableEq

def Shape.perArm : Shape → Nat
  | .full => 2
  | .endOnly => 1

def Shape.name : Shape → String
  | .full => "full"
  | .endOnly => "endOnly"

def windowsPerRep (s : Shape) (arms : Nat) : Nat := s.perArm * arms

def lifeWindows : Nat := 36

/-- The largest rep count up to `fuel` whose windows fit `budget` ms. -/
def repsFitAux (budget w : Nat) : Nat → Nat
  | 0 => 0
  | k + 1 => if blockMs ((k + 1) * w) ≤ budget then k + 1 else repsFitAux budget w k

def repsFit (dl now : Nat) (s : Shape) (arms : Nat) : Nat :=
  if windowsPerRep s arms = 0 then 0 else repsFitAux (dl - now) (windowsPerRep s arms) lifeWindows

def repsLife (s : Shape) (arms : Nat) : Nat := lifeWindows / windowsPerRep s arms

/-- The reps a plan asks for at most: the minimum plus one for a refused window, so a healthy job ends early and a slow one is cut by the deadline. -/
def repsWant : Nat := 6

theorem minKept_le_repsWant : minKept ≤ repsWant := by decide

def planReps (dl now : Nat) (s : Shape) (arms : Nat) : Nat := min (min (repsLife s arms) (repsFit dl now s arms)) repsWant

inductive Outcome where
  | ok
  | lifeShort
  | budgetShort
deriving Repr, BEq, DecidableEq

def outcome (dl now : Nat) (s : Shape) (arms : Nat) : Outcome :=
  if repsLife s arms < minKept then .lifeShort else if repsFit dl now s arms < minKept then .budgetShort else .ok

def Outcome.name : Outcome → String
  | .ok => "ok"
  | .lifeShort => "lifeShort"
  | .budgetShort => "budgetShort"

def endsDone (s : Shape) (n arms pos : Nat) : Nat :=
  n / windowsPerRep s arms + if s.perArm * (pos + 1) ≤ n % windowsPerRep s arms then 1 else 0

theorem repsFitAux_le (b w : Nat) : ∀ k, repsFitAux b w k ≤ k
  | 0 => Nat.le_refl _
  | k + 1 => by
    unfold repsFitAux
    split
    · exact Nat.le_refl _
    · exact Nat.le_succ_of_le (repsFitAux_le b w k)

theorem repsFitAux_fits (b w : Nat) : ∀ k, blockMs (repsFitAux b w k * w) ≤ b
  | 0 => by simp [repsFitAux, blockMs_zero]
  | k + 1 => by
    unfold repsFitAux
    split
    · assumption
    · exact repsFitAux_fits b w k

/-- The reps of a plan fit the time left, at the block budget. -/
theorem planReps_fits (dl now : Nat) (s : Shape) (arms : Nat) :
    blockMs (planReps dl now s arms * windowsPerRep s arms) ≤ dl - now := by
  have hle : planReps dl now s arms ≤ repsFit dl now s arms := Nat.le_trans (Nat.min_le_left _ _) (Nat.min_le_right _ _)
  unfold repsFit at hle
  split at hle
  · rename_i h0
    have : planReps dl now s arms = 0 := by omega
    rw [this]; simp [blockMs_zero]
  · exact Nat.le_trans (blockMs_mono _ _ (Nat.mul_le_mul_right _ hle)) (repsFitAux_fits _ _ _)

theorem planReps_life (s : Shape) (arms dl now : Nat) : planReps dl now s arms * windowsPerRep s arms ≤ lifeWindows :=
  Nat.le_trans (Nat.mul_le_mul_right _ (Nat.le_trans (Nat.min_le_left _ _) (Nat.min_le_left _ _))) (Nat.div_mul_le_self _ _)

theorem outcome_lifeShort (dl now : Nat) (s : Shape) (arms : Nat) (h : repsLife s arms < minKept) : outcome dl now s arms = .lifeShort := by
  simp [outcome, h]

theorem outcome_budgetShort (dl now : Nat) (s : Shape) (arms : Nat) (hl : minKept ≤ repsLife s arms) (h : repsFit dl now s arms < minKept) :
    outcome dl now s arms = .budgetShort := by
  have : ¬ repsLife s arms < minKept := by omega
  simp [outcome, this, h]

theorem outcome_ok (dl now : Nat) (s : Shape) (arms : Nat) (hl : minKept ≤ repsLife s arms) (h : minKept ≤ repsFit dl now s arms) :
    outcome dl now s arms = .ok := by
  have h1 : ¬ repsLife s arms < minKept := by omega
  have h2 : ¬ repsFit dl now s arms < minKept := by omega
  simp [outcome, h1, h2]

theorem outcome_ok_plan (dl now : Nat) (s : Shape) (arms : Nat) (h : outcome dl now s arms = .ok) : minKept ≤ planReps dl now s arms := by
  have hw := minKept_le_repsWant
  unfold outcome at h
  unfold planReps
  split at h
  · cases h
  · split at h
    · cases h
    · omega

/-- An ok plan reserves the block budget of its five kept reps inside the time left. -/
theorem outcome_ok_time (dl now : Nat) (s : Shape) (arms : Nat) (h : outcome dl now s arms = .ok) :
    blockMs (minKept * windowsPerRep s arms) ≤ dl - now :=
  Nat.le_trans (blockMs_mono _ _ (Nat.mul_le_mul_right _ (outcome_ok_plan dl now s arms h))) (planReps_fits dl now s arms)

/-- A plan started at or before the deadline ends its windows, the grace, the post steps and the slack inside the job timeout. -/
theorem plan_inside_job (now : Nat) (s : Shape) (arms : Nat) (hn : now ≤ deadlineAt job) :
    now + blockMs (planReps (deadlineAt job) now s arms * windowsPerRep s arms) + job.graceMs + job.postMs + job.slackMs ≤ job.timeoutMs := by
  have h1 := planReps_fits (deadlineAt job) now s arms
  have h2 := deadline_add_le job job_fits
  omega

theorem endsDone_ge (s : Shape) (n arms pos : Nat) : n / windowsPerRep s arms ≤ endsDone s n arms pos := by
  unfold endsDone
  omega

theorem endsDone_le (s : Shape) (n arms pos : Nat) : endsDone s n arms pos ≤ n / windowsPerRep s arms + 1 := by
  unfold endsDone
  split <;> omega

theorem windowsPerRep_pos (s : Shape) (arms : Nat) (ha : 0 < arms) : 0 < windowsPerRep s arms := by
  cases s <;> simp [windowsPerRep, Shape.perArm] <;> omega

theorem kept_after (s : Shape) (n arms pos : Nat) (ha : 0 < arms) (h : minKept * windowsPerRep s arms ≤ n) : minKept ≤ endsDone s n arms pos := by
  have := (Nat.le_div_iff_mul_le (windowsPerRep_pos s arms ha)).2 h
  exact Nat.le_trans this (endsDone_ge s n arms pos)

theorem planReps_complete (dl now : Nat) (s : Shape) (arms : Nat) (ha : 0 < arms) (h : outcome dl now s arms = .ok) (pos : Nat) :
    minKept ≤ endsDone s (planReps dl now s arms * windowsPerRep s arms) arms pos :=
  kept_after s _ arms pos ha (Nat.mul_le_mul_right _ (outcome_ok_plan dl now s arms h))

/-! ## Arms beyond one job -/

/-- The arms in one of `g` jobs: every control and an equal share of the candidates. -/
def groupArms (controls cands g : Nat) : Nat := controls + (cands + g - 1) / g

/-- The fewest jobs, at most one per candidate, whose share of the arms plans ok. -/
def groupsFor (dl now : Nat) (s : Shape) (controls cands : Nat) : Option Nat :=
  (List.range' 1 (cands + 1)).find? fun g => decide (outcome dl now s (groupArms controls cands g) = .ok)

theorem groupsFor_ok (dl now : Nat) (s : Shape) (controls cands g : Nat) (h : groupsFor dl now s controls cands = some g) :
    outcome dl now s (groupArms controls cands g) = .ok := by
  unfold groupsFor at h
  exact of_decide_eq_true (List.find?_some (p := fun g => decide (outcome dl now s (groupArms controls cands g) = .ok)) h)

theorem groupsFor_pos (dl now : Nat) (s : Shape) (controls cands g : Nat) (h : groupsFor dl now s controls cands = some g) : 0 < g := by
  have := List.mem_of_find?_eq_some h
  simp [List.mem_range'] at this
  omega

/-- The shares of the candidates cover all of them. -/
theorem groupArms_cover (controls cands g : Nat) (hg : 0 < g) : cands ≤ g * (groupArms controls cands g - controls) := by
  unfold groupArms
  have h1 := Nat.div_add_mod (cands + g - 1) g
  have h2 := Nat.mod_lt (cands + g - 1) hg
  have h3 : controls + (cands + g - 1) / g - controls = (cands + g - 1) / g := Nat.add_sub_cancel_left _ _
  rw [h3]
  generalize (cands + g - 1) / g = q at *
  obtain ⟨t, ht⟩ : ∃ t, t = g * q := ⟨_, rfl⟩
  rw [← ht] at h1 ⊢
  omega

/-! ## Jobs: how many, and what a lost job costs -/

/-- Jobs started beyond the ones a decision needs, so a lost job (a `simctl openurl` timeout, a runner that never starts) does not leave it short. -/
def margin : Nat := 2

def jobsNeeded : Nat := Fw.Gate.Smooth.minSamples + margin

/-- The jobs of one run fit the free macOS slots, so none waits behind another of the run. -/
theorem jobsNeeded_le_slots : jobsNeeded ≤ Fw.Measure.WktrLayout.macSlots := by decide

theorem jobsNeeded_value : jobsNeeded = 5 := by decide

theorem decisive_add_insufficient (vs : List Verdict) :
    Fw.Gate.Smooth.decisive vs + vs.count .insufficient = vs.length := by
  induction vs with
  | nil => simp [Fw.Gate.Smooth.decisive]
  | cons x xs ih =>
    simp only [Fw.Gate.Smooth.decisive, List.count_cons, List.length_cons] at ih ⊢
    cases x <;> simp (config := { decide := true }) only [ite_true, ite_false] <;> omega

/-- With the planned jobs and at most `margin` of them without a verdict, the decisive jobs reach the minimum the across-jobs rule asks. -/
theorem plan_decisive (vs : List Verdict) (hn : jobsNeeded ≤ vs.length) (hl : vs.count .insufficient ≤ margin) :
    Fw.Gate.Smooth.minSamples ≤ Fw.Gate.Smooth.decisive vs := by
  have := decisive_add_insufficient vs
  unfold jobsNeeded at hn
  omega

theorem hitchJudge_ne_insufficient (a b : List Nat) : Fw.Gate.Smooth.hitchJudge a b ≠ .insufficient := by
  unfold Fw.Gate.Smooth.hitchJudge
  split
  · simp
  · split <;> simp

/-- A job with the minimum of kept end windows in each of its four lists never judges insufficient. -/
theorem job_decisive (a b aa1 aa2 : List Nat) (hok : Fw.Gate.Smooth.okN a b aa1 aa2 = true) :
    Fw.Gate.Smooth.hitchVerdict a b aa1 aa2 ≠ .insufficient := by
  unfold Fw.Gate.Smooth.hitchVerdict
  simp only [hok, ite_true]
  have h1 := hitchJudge_ne_insufficient aa1 aa2
  have h2 := hitchJudge_ne_insufficient a b
  split
  · exact h2
  · simp

theorem across_decisive_ne_insufficient (vs : List Verdict) (h : Fw.Gate.Smooth.minSamples ≤ Fw.Gate.Smooth.decisive vs) :
    Fw.Gate.Smooth.acrossDecisive vs ≠ .insufficient := by
  have hk : 0 < Fw.Gate.Smooth.agreeNeeded (Fw.Gate.Smooth.decisive vs) := by
    unfold Fw.Gate.Smooth.agreeNeeded Fw.Gate.Smooth.minSamples at *
    omega
  unfold Fw.Gate.Smooth.acrossDecisive Fw.Gate.Smooth.across
  have h' : ¬ (Fw.Gate.Smooth.decisive vs < Fw.Gate.Smooth.minSamples ∨ Fw.Gate.Smooth.agreeNeeded (Fw.Gate.Smooth.decisive vs) = 0) := by omega
  simp only [h', ite_false]
  split <;> try split
  all_goals simp

/-- The plan's end to end: planned jobs, at most `margin` lost, give an across-jobs verdict that is not insufficient. -/
theorem plan_across (vs : List Verdict) (hn : jobsNeeded ≤ vs.length) (hl : vs.count .insufficient ≤ margin) :
    Fw.Gate.Smooth.acrossDecisive vs ≠ .insufficient :=
  across_decisive_ne_insufficient vs (plan_decisive vs hn hl)

/-- How long the harness waits for the touch driver to answer, counted from its start. A driver that is late only moves the plan clock, which is read after it answers. -/
def readyAllowMs : Nat := 480000

/-- The longest setup measured before the plan clock: 5 min of job steps, 1.5 min to a tab and `readyAllowMs` for the driver (run 41345594217: job steps 4.9 min, a driver ready after 107 s, a tab after 40 s; two jobs waited out 240 s). -/
def setupWorstMs : Nat := 900000

theorem setup_worst_fits : 300000 + 90000 + readyAllowMs ≤ setupWorstMs := by decide

/-- A plan clocked at the worst setup is still ok for 3 and for 4 arms of end windows. -/
theorem ok_at_worst_setup (arms : Nat) (h3 : 3 ≤ arms) (h4 : arms ≤ 4) : outcome (deadlineAt job) setupWorstMs .endOnly arms = .ok := by
  have : arms = 3 ∨ arms = 4 := by omega
  rcases this with rfl | rfl <;> decide +kernel

theorem worst_setup_inside_job : setupWorstMs ≤ deadlineAt job := by decide

/-! ## Golden -/

def stepCases : List (String × Nat × Option Nat) := [
  ("walk starts after 4.6 min", 276000, none),
  ("walk starts at the job start", 0, none),
  ("walk starts at the deadline", 2400000, none),
  ("walk starts in the grace", 2430000, none),
  ("walk starts too late", 2700000, none),
  ("cap 8 min", 276000, some 480000),
  ("cap above the deadline", 276000, some 3000000)]

def startCases : List (String × Nat × Nat × Nat) := [
  ("plenty of time", 1500000, 100000, 30000),
  ("exactly the reserve", 1500000, 1470000, 30000),
  ("one ms short", 1500000, 1470001, 30000),
  ("past the deadline", 1500000, 1600000, 30000)]

def planCases : List (String × Nat × Option Nat × Shape × Nat) := [
  ("3 arms end only, walk starts after 4.6 min", 276000, none, .endOnly, 3),
  ("3 arms end only, walk starts after 15 min", 900000, none, .endOnly, 3),
  ("3 arms end only, 6 reps still fit", 1509000, none, .endOnly, 3),
  ("3 arms end only, 6 reps one ms too late", 1509001, none, .endOnly, 3),
  ("3 arms end only, walk starts after 26.6 min", 1596000, none, .endOnly, 3),
  ("3 arms end only, one ms too late", 1596001, none, .endOnly, 3),
  ("3 arms end only, cap 10 min", 276000, some 600000, .endOnly, 3),
  ("2 arms end only", 276000, none, .endOnly, 2),
  ("4 arms end only", 276000, none, .endOnly, 4),
  ("4 arms end only, walk starts after 15 min", 900000, none, .endOnly, 4),
  ("4 arms end only, walk starts after 24.2 min", 1451000, none, .endOnly, 4),
  ("4 arms end only, one ms too late", 1451001, none, .endOnly, 4),
  ("5 arms end only", 276000, none, .endOnly, 5),
  ("5 arms end only, walk starts after 15 min", 900000, none, .endOnly, 5),
  ("10 arms end only", 276000, none, .endOnly, 10),
  ("no arms", 276000, none, .endOnly, 0),
  ("2 arms full", 276000, none, .full, 2),
  ("3 arms full", 276000, none, .full, 3),
  ("4 arms full", 276000, none, .full, 4)]

def blockCases : List Nat := [0, 1, 5, 15, 19, 20, 21, 30, 36, 40]

def endsCases : List (Shape × Nat × Nat × Nat) :=
  [(.full, 3, 0, 0), (.full, 3, 7, 0), (.full, 3, 7, 1), (.full, 3, 8, 1), (.full, 3, 30, 2), (.full, 3, 29, 2), (.full, 3, 36, 0), (.full, 2, 17, 1),
   (.endOnly, 3, 0, 0), (.endOnly, 3, 1, 0), (.endOnly, 3, 1, 1), (.endOnly, 3, 15, 2), (.endOnly, 3, 17, 2), (.endOnly, 4, 20, 3), (.endOnly, 4, 19, 3)]

def groupCases : List (String × Nat × Shape × Nat × Nat) := [
  ("3 arms fit one job", 276000, .endOnly, 2, 1),
  ("5 arms fit one job", 276000, .endOnly, 2, 3),
  ("7 arms fit one job", 276000, .endOnly, 2, 5),
  ("8 arms need two jobs", 276000, .endOnly, 2, 6),
  ("11 arms need two jobs", 276000, .endOnly, 2, 9),
  ("5 arms full need three jobs", 276000, .full, 2, 3),
  ("no candidates", 276000, .endOnly, 2, 0)]

def verdictCases : List (List Verdict) := [
  [.first, .first, .first, .first, .first],
  [.first, .first, .first, .insufficient, .insufficient],
  [.first, .first, .insufficient, .insufficient, .insufficient],
  [.second, .same, .first, .insufficient, .insufficient],
  [.same, .same, .same, .same, .same],
  [.first, .first, .first, .second, .insufficient],
  [.first, .same, .insufficient, .insufficient],
  [.first, .first, .first, .insufficient]]

open Lean in
def goldenLines (_ : Unit := ()) : List String :=
  let consts := (Json.mkObj [("op", "constants"), ("timeoutMs", toJson job.timeoutMs), ("postMs", toJson job.postMs),
    ("graceMs", toJson job.graceMs), ("slackMs", toJson job.slackMs), ("deadlineAt", toJson (deadlineAt job)),
    ("hardStopMs", toJson hardStopMs), ("postStepsMs", toJson postStepsMs), ("clockMs", toJson gaps.clockMs),
    ("driftMs", toJson gaps.driftMs), ("completeMs", toJson gaps.completeMs), ("overrunMs", toJson gaps.overrunMs),
    ("minKept", toJson minKept), ("repsWant", toJson repsWant), ("lifeWindows", toJson lifeWindows), ("windowSamples", toJson windowSecs.length),
    ("bodyMs", toJson bodyMs), ("tailMs", toJson tailMs), ("meanMs", toJson meanMs), ("tailEvery", toJson tailEvery),
    ("margin", toJson margin), ("readyAllowMs", toJson readyAllowMs), ("setupWorstMs", toJson setupWorstMs), ("jobsNeeded", toJson jobsNeeded), ("macSlots", toJson Fw.Measure.WktrLayout.macSlots),
    ("minSamples", toJson Fw.Gate.Smooth.minSamples)]).compress
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
  let bs := blockCases.map fun n =>
    (Json.mkObj [("op", "block"), ("windows", toJson n), ("blockMs", toJson (blockMs n))]).compress
  let ps := planCases.map fun (name, elapsed, cap, s, arms) =>
    let dl := cappedDeadline job elapsed cap
    (Json.mkObj [("op", "plan"), ("case", Json.str name), ("elapsedMs", toJson elapsed),
      ("capMs", match cap with | some v => toJson v | none => Json.null), ("deadlineMs", toJson dl), ("shape", Json.str s.name),
      ("arms", toJson arms), ("repsFit", toJson (repsFit dl elapsed s arms)), ("repsLife", toJson (repsLife s arms)),
      ("reps", toJson (planReps dl elapsed s arms)), ("outcome", Json.str (outcome dl elapsed s arms).name)]).compress
  let es := endsCases.map fun (s, arms, n, pos) =>
    (Json.mkObj [("op", "ends"), ("shape", Json.str s.name), ("arms", toJson arms), ("windows", toJson n), ("pos", toJson pos),
      ("endsDone", toJson (endsDone s n arms pos))]).compress
  let gs := groupCases.map fun (name, elapsed, s, controls, cands) =>
    let dl := deadlineAt job
    let g := groupsFor dl elapsed s controls cands
    (Json.mkObj [("op", "groups"), ("case", Json.str name), ("elapsedMs", toJson elapsed), ("shape", Json.str s.name),
      ("controls", toJson controls), ("candidates", toJson cands), ("groups", match g with | some v => toJson v | none => Json.null),
      ("groupArms", match g with | some v => toJson (groupArms controls cands v) | none => Json.null)]).compress
  let js := verdictCases.map fun vs =>
    (Json.mkObj [("op", "jobs"), ("verdicts", toJson (vs.map Verdict.name)), ("decisive", toJson (Fw.Gate.Smooth.decisive vs)),
      ("lost", toJson (vs.count .insufficient)), ("across", Json.str (Fw.Gate.Smooth.acrossDecisive vs).name)]).compress
  [consts] ++ ss ++ ws ++ bs ++ ps ++ es ++ gs ++ js

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
