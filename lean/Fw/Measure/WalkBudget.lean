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

def windowSecs : List Nat := [
  7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 9, 9, 9, 9,
  9, 9, 9, 9, 9, 9, 9, 9, 9, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 11, 11, 11, 11, 11,
  11, 11, 11, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 13, 13, 13, 13, 13, 13, 13, 13, 14, 14,
  14, 14, 14, 14, 14, 14, 14, 14, 15, 15, 15, 15, 15, 15, 15, 15, 15, 16, 16, 16, 16, 16, 16, 16,
  16, 16, 16, 16, 16, 16, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 18, 18, 18, 18, 18, 18,
  18, 18, 18, 18, 18, 18, 18, 19, 19, 19, 19, 19, 19, 19, 19, 19, 20, 20, 20, 20, 20, 20, 20, 20,
  20, 20, 20, 20, 20, 20, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 22, 22, 22, 22, 22, 22, 23,
  23, 23, 23, 23, 23, 24, 24, 24, 24, 24, 24, 24, 24, 25, 25, 25, 25, 25, 25, 25, 25, 25, 26, 26,
  26, 26, 26, 27, 27, 27, 27, 28, 28, 28, 28, 28, 28, 29, 29, 29, 29, 29, 29, 29, 29, 30, 30, 31,
  31, 31, 31, 31, 32, 33, 33, 33, 33, 34, 35, 35, 35, 35, 35, 36, 36, 36, 36, 37, 37, 38, 38, 38,
  39, 39, 39, 39, 40, 41, 41, 42, 42, 43, 43, 43, 44, 44, 44, 44, 47, 47, 48, 48, 48, 48, 49, 50,
  51, 52, 52, 52, 53, 53, 53, 53, 54, 54, 55, 55, 56, 56, 60, 61, 62, 63, 63, 63, 65, 66, 66, 69,
  71, 74, 75, 81, 83, 84, 84, 85, 85, 85, 93, 96, 125, 131, 143, 152, 156, 170, 172, 175, 196, 208, 217, 225,
  285, 319, 383, 398, 432, 744]

def quantile (xs : List Nat) (pct : Nat) : Nat := xs.getD ((pct * xs.length + 99) / 100 - 1) 0

def bodyMs : Nat := quantile windowSecs 75 * 1000

def tailMs : Nat := quantile windowSecs 99 * 1000

def meanMs : Nat := windowSecs.sum * 1000 / windowSecs.length

/-- A window of at least this many seconds is a tail window. -/
def tailFloorSecs : Nat := 100

/-- Windows per tail window of the sample, rounded down so the budget holds one tail slot at least as often as the sample shows one. -/
def tailEvery : Nat := windowSecs.length / (windowSecs.filter (tailFloorSecs ≤ ·)).length

def blockMs (n : Nat) : Nat := n * bodyMs + (n + tailEvery - 1) / tailEvery * (tailMs - bodyMs)

theorem windows_count : windowSecs.length = 318 := by decide +kernel

theorem tail_windows : (windowSecs.filter (tailFloorSecs ≤ ·)).length = 18 := by decide +kernel

theorem tailEvery_value : tailEvery = 17 := by decide +kernel

theorem bodyMs_value : bodyMs = 38000 := by decide +kernel

theorem tailMs_value : tailMs = 383000 := by decide +kernel

theorem meanMs_value : meanMs = 39647 := by decide +kernel

theorem blockMs_zero : blockMs 0 = 0 := by decide +kernel

theorem blockMs_mono (n m : Nat) (h : n ≤ m) : blockMs n ≤ blockMs m := by
  unfold blockMs
  exact Nat.add_le_add (Nat.mul_le_mul_right _ h) (Nat.mul_le_mul_right _ (by rw [tailEvery_value]; omega))

theorem blockMs_over_mean (n : Nat) : n * meanMs ≤ blockMs n := by
  rw [meanMs_value]
  unfold blockMs
  rw [bodyMs_value, tailMs_value, tailEvery_value]
  omega

def minKept : Nat := Fw.Gate.Smooth.minReps

theorem minKept_value : minKept = 5 := by decide

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

def repsFitAux (budget w : Nat) : Nat → Nat
  | 0 => 0
  | k + 1 => if blockMs ((k + 1) * w) ≤ budget then k + 1 else repsFitAux budget w k

def repsFit (dl now : Nat) (s : Shape) (arms : Nat) : Nat :=
  if windowsPerRep s arms = 0 then 0 else repsFitAux (dl - now) (windowsPerRep s arms) lifeWindows

def repsLife (s : Shape) (arms : Nat) : Nat := lifeWindows / windowsPerRep s arms

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

theorem outcome_ok_time (dl now : Nat) (s : Shape) (arms : Nat) (h : outcome dl now s arms = .ok) :
    blockMs (minKept * windowsPerRep s arms) ≤ dl - now :=
  Nat.le_trans (blockMs_mono _ _ (Nat.mul_le_mul_right _ (outcome_ok_plan dl now s arms h))) (planReps_fits dl now s arms)

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

def groupArms (controls cands g : Nat) : Nat := controls + (cands + g - 1) / g

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

/-- What kept a job of the two verdict runs from a decisive end-touch verdict. -/
inductive Fault where
  | none
  | budget
  | driver
  | hang
  | crash
deriving DecidableEq, Repr

def Fault.name : Fault → String
  | .none => "none"
  | .budget => "budget"
  | .driver => "touch-driver-not-ready"
  | .hang => "page-lost-or-evaluate-timeout"
  | .crash => "socket-crash"

/-- The jobs of runs 41345594217 (run 1), 41349666358 (run 2) and 41357917479 (run 3, the 10-job matrix): run, job, fault. -/
def observedJobs : List (Nat × Nat × Fault) :=
  [(1, 1, .budget), (1, 2, .driver), (1, 3, .driver), (1, 4, .crash), (1, 5, .budget),
   (2, 1, .none), (2, 2, .none), (2, 3, .hang), (2, 4, .hang), (2, 5, .driver),
   (3, 1, .none), (3, 2, .none), (3, 3, .driver), (3, 4, .driver), (3, 5, .hang),
   (3, 6, .driver), (3, 7, .driver), (3, 8, .driver), (3, 9, .none), (3, 10, .driver)]

def faultCount (f : Fault) (js : List (Nat × Nat × Fault) := observedJobs) : Nat := (js.filter (·.2.2 == f)).length

/-- The fault with the most jobs among the faulty ones (the first on a tie). -/
def dominant : Fault :=
  [Fault.budget, .driver, .hang, .crash].foldl (fun best f => if faultCount best < faultCount f then f else best) .budget

theorem observed_twenty : observedJobs.length = 20 := by decide

theorem observed_decisive : faultCount .none = 5 := by decide

theorem dominant_driver : dominant = .driver := by decide

theorem driver_count : faultCount .driver = 9 := by decide

theorem driver_others : faultCount .budget + faultCount .hang + faultCount .crash = 6 := by decide

/-- Decisive jobs over jobs, as a fraction, for the jobs of the listed runs. -/
def decisiveRate (runs : List Nat) : Nat × Nat :=
  let js := observedJobs.filter fun j => runs.contains j.1
  (faultCount .none js, js.length)

/-- The rate of runs 1 and 2, the 10 jobs the plan was derived from. -/
def pooledRate : Nat × Nat := decisiveRate [1, 2]

theorem pooled_rate : pooledRate = (2, 10) := by decide

/-- Run 3 ran the 10-job plan: 3 jobs decisive (1, 2, 9), 6 lost to the touch driver, 1 to a hang (job 5). -/
theorem run3_rate : decisiveRate [3] = (3, 10) := by decide

theorem run3_driver : faultCount .driver (observedJobs.filter fun j => j.1 == 3) = 6 := by decide

/-- The rate of runs 2 and 3, the two runs of the current code (run 3 = the 10-job matrix): 5 of 15. -/
def lateRate : Nat × Nat := decisiveRate [2, 3]

theorem late_rate : lateRate = (5, 15) := by decide

/-- The rate the plan uses: run 2 ran the code of the matrix (the 60 min job, the 480 s driver wait and the socket guard fix the faults `budget` and `crash` of run 1). -/
def planRate : Nat × Nat := decisiveRate [2]

theorem planRate_value : planRate = (2, 5) := by decide

def pascal : Nat → List Nat
  | 0 => [1]
  | n + 1 => let r := pascal n; List.zipWith (· + ·) (0 :: r) (r ++ [0])

def choose (n k : Nat) : Nat := (pascal n).getD k 0

/-- The numerator, over `b ^ n`, of the chance that at least `k` of `n` jobs are decisive when each is with chance `a / b`. -/
def tailNum (n k a b : Nat) : Nat :=
  (List.range (n + 1)).foldl (fun s i => if k ≤ i then s + choose n i * a ^ i * (b - a) ^ (n - i) else s) 0

def reaches (n k a b tn td : Nat) : Bool := decide (tn * b ^ n ≤ td * tailNum n k a b)

theorem tailNum_total : ∀ n, n ≤ 12 → tailNum n 0 2 5 = 5 ^ n := by decide +kernel

/-- Chance target of the plan: at least 4 in 5 that the run has `minSamples` decisive jobs. -/
def target : Nat × Nat := (4, 5)

def jobsCap : Nat := 30

/-- The least job count of at least `k` that reaches `k` decisive jobs with the target chance. -/
def jobsFor (k a b tn td cap : Nat) : Option Nat :=
  (List.range (cap + 1)).find? fun n => decide (k ≤ n) && reaches n k a b tn td

def jobsNeeded : Nat :=
  (jobsFor Fw.Gate.Smooth.minSamples planRate.1 planRate.2 target.1 target.2 jobsCap).getD jobsCap

/-- Lost jobs the plan survives: every job past the `minSamples` decisive ones. -/
def margin : Nat := jobsNeeded - Fw.Gate.Smooth.minSamples

theorem jobsNeeded_value : jobsNeeded = 10 := by decide +kernel

theorem margin_value : margin = 7 := by decide +kernel

theorem margin_add : Fw.Gate.Smooth.minSamples + margin = jobsNeeded := by
  unfold margin
  have : Fw.Gate.Smooth.minSamples ≤ jobsNeeded := by decide +kernel
  omega

/-- **Reach**: at the plan rate (2 of 5 jobs decisive) 10 jobs give at least 3 decisive ones with chance at least 4 in 5. -/
theorem reach_at_plan : reaches jobsNeeded Fw.Gate.Smooth.minSamples planRate.1 planRate.2 target.1 target.2 = true := by
  decide +kernel

theorem reach_least : ∀ n, n < jobsNeeded → Fw.Gate.Smooth.minSamples ≤ n →
    reaches n Fw.Gate.Smooth.minSamples planRate.1 planRate.2 target.1 target.2 = false := by
  decide +kernel

/-- The exact chance at the plan rate, in parts per 10000 (rounded down): 8327. -/
def reachPer10k (n k a b : Nat) : Nat := 10000 * tailNum n k a b / b ^ n

theorem reach_plan_value : reachPer10k jobsNeeded Fw.Gate.Smooth.minSamples planRate.1 planRate.2 = 8327 := by decide +kernel

/-- At the rate of all ten jobs (2 of 10) the same 10 jobs reach with a chance of only 3222 in 10000: the plan bets on run 2's rate. -/
theorem reach_at_pooled : reachPer10k jobsNeeded Fw.Gate.Smooth.minSamples 1 5 = 3222 := by decide +kernel

/-- Jobs for the target chance at the pooled rate: 21. -/
theorem pooled_jobs : jobsFor Fw.Gate.Smooth.minSamples 1 5 target.1 target.2 jobsCap = some 21 := by decide +kernel

/-- Run 3 (the 10-job matrix) reached `minSamples` decisive jobs with none to spare: 3 of 3. -/
theorem run3_reached : Fw.Gate.Smooth.minSamples ≤ (decisiveRate [3]).1 ∧ (decisiveRate [3]).1 ≤ Fw.Gate.Smooth.minSamples := by decide

/-- At the rate of runs 2 and 3 (5 of 15, that is 1 of 3) the same 10 jobs reach with a chance of 7008 in 10000: the 4 in 5 target needs 12 jobs, so the next matrix is sized by `lateRate`. -/
theorem reach_at_late : reachPer10k jobsNeeded Fw.Gate.Smooth.minSamples 1 3 = 7008 := by decide +kernel

theorem late_jobs : jobsFor Fw.Gate.Smooth.minSamples 1 3 target.1 target.2 jobsCap = some 12 := by decide +kernel

theorem decisive_add_insufficient (vs : List Verdict) :
    Fw.Gate.Smooth.decisive vs + vs.count .insufficient = vs.length := by
  induction vs with
  | nil => simp [Fw.Gate.Smooth.decisive]
  | cons x xs ih =>
    simp only [Fw.Gate.Smooth.decisive, List.count_cons, List.length_cons] at ih ⊢
    cases x <;> simp (config := { decide := true }) only [ite_true, ite_false] <;> omega

theorem plan_decisive (vs : List Verdict) (hn : jobsNeeded ≤ vs.length) (hl : vs.count .insufficient ≤ margin) :
    Fw.Gate.Smooth.minSamples ≤ Fw.Gate.Smooth.decisive vs := by
  have := decisive_add_insufficient vs
  have := margin_add
  omega

theorem hitchJudge_ne_insufficient (a b : List Nat) : Fw.Gate.Smooth.hitchJudge a b ≠ .insufficient := by
  unfold Fw.Gate.Smooth.hitchJudge
  split
  · simp
  · split <;> simp

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

theorem plan_across (vs : List Verdict) (hn : jobsNeeded ≤ vs.length) (hl : vs.count .insufficient ≤ margin) :
    Fw.Gate.Smooth.acrossDecisive vs ≠ .insufficient :=
  across_decisive_ne_insufficient vs (plan_decisive vs hn hl)

/-! ## Waves and the macOS legs of one run -/

/-- Rounds of `slots` jobs that `jobs` jobs need. -/
def waves (jobs slots : Nat) : Nat := (jobs + slots - 1) / slots

theorem jobs_le_waves (jobs slots : Nat) (h : 0 < slots) : jobs ≤ waves jobs slots * slots := by
  unfold waves
  have h1 := Nat.div_add_mod (jobs + slots - 1) slots
  have h2 := Nat.mod_lt (jobs + slots - 1) h
  rw [Nat.mul_comm] at h1
  omega

/-- **Waves**: a pool of `p` slots that starts a job as soon as one of the `p` before it has ended, jobs of at most `T`, starts job `i` by `(i / p) * T`. -/
theorem wave_start (p T : Nat) (hp : 0 < p) (start : Nat → Nat) (h0 : ∀ i, i < p → start i = 0)
    (hs : ∀ i, p ≤ i → start i ≤ start (i - p) + T) : ∀ i, start i ≤ i / p * T := by
  intro i
  induction i using Nat.strongRecOn with
  | _ i ih =>
    by_cases hi : i < p
    · rw [h0 i hi]; exact Nat.zero_le _
    · have hle : p ≤ i := by omega
      have h1 := ih (i - p) (by omega)
      have h2 := hs i hle
      have h3 : i / p = (i - p) / p + 1 := by
        have e : i = (i - p) + p := by omega
        have := Nat.add_div_right (i - p) hp
        rw [← e] at this
        exact this
      rw [h3, Nat.add_mul, Nat.one_mul]
      omega

/-- Every job of the pool ends by `waves * T`. -/
theorem wave_end (p T jobs : Nat) (hp : 0 < p) (start : Nat → Nat) (h0 : ∀ i, i < p → start i = 0)
    (hs : ∀ i, p ≤ i → start i ≤ start (i - p) + T) : ∀ i, i < jobs → start i + T ≤ waves jobs p * T := by
  intro i hi
  have h1 := wave_start p T hp start h0 hs i
  have h2 := jobs_le_waves jobs p hp
  have h3 : i / p + 1 ≤ waves jobs p := by
    have : i / p < waves jobs p := (Nat.div_lt_iff_lt_mul hp).2 (by omega)
    omega
  have h4 := Nat.mul_le_mul_right T h3
  rw [Nat.add_mul, Nat.one_mul] at h4
  omega

/-- One macOS leg of a smoothness run: the matrix size and its `max-parallel`. -/
structure Leg where
  name : String
  jobs : Nat
  parallel : Nat
deriving DecidableEq, Repr

def macJobs : Nat := 3

/-- The legs of a run on the free macOS runners: `webkit-mac` unless `[sim-only]`, `webkit-sim` with the control job when `[sim-touch-control]`. -/
def legs (simOnly control : Bool) : List Leg :=
  (if simOnly then [] else [⟨"webkit-mac", macJobs, 1⟩]) ++
    [⟨"webkit-sim", jobsNeeded + (if control then 1 else 0), Fw.Measure.WktrLayout.macSlots⟩]

def Leg.peak (l : Leg) : Nat := min l.jobs l.parallel

def peak (ls : List Leg) : Nat := (ls.map Leg.peak).sum

def totalJobs (ls : List Leg) : Nat := (ls.map (·.jobs)).sum

def runWaves (ls : List Leg) : Nat := waves (totalJobs ls) Fw.Measure.WktrLayout.macSlots

/-- Every job of the run starts at once: they all fit the free slots. -/
def startAtOnce (ls : List Leg) : Bool := decide (totalJobs ls ≤ Fw.Measure.WktrLayout.macSlots)

theorem never_at_once : ∀ s c : Bool, startAtOnce (legs s c) = false := by decide +kernel

theorem sim_only_waves : runWaves (legs true false) = 2 := by decide +kernel

theorem sim_only_peak : peak (legs true false) = Fw.Measure.WktrLayout.macSlots := by decide +kernel

theorem mac_leg_waves : runWaves (legs false false) = 3 := by decide +kernel

theorem control_waves : runWaves (legs true true) = 3 := by decide +kernel

theorem mac_leg_peak : peak (legs false false) = Fw.Measure.WktrLayout.macSlots + 1 := by decide +kernel

theorem sim_only_wall : runWaves (legs true false) * job.timeoutMs = 7200000 := by decide +kernel

/-- A walk with the touch driver asked for ends at once when the driver is not on: no untouched windows follow. -/
def driverFault (requested on : Bool) : Bool := requested && !on

def driverFaultName : String := Fault.driver.name

theorem driverFault_untouched (r o : Bool) (h : driverFault r o = true) : r = true ∧ o = false := by
  cases r <;> cases o <;> simp_all [driverFault]

theorem driverFault_on (r : Bool) : driverFault r true = false := by cases r <;> rfl

theorem driverFault_unasked (o : Bool) : driverFault false o = false := rfl

theorem driverFault_asked_off : driverFault true false = true := rfl

def readyAllowMs : Nat := 480000

def setupWorstMs : Nat := 900000

theorem setup_worst_fits : 300000 + 90000 + readyAllowMs ≤ setupWorstMs := by decide

theorem ok_at_worst_setup (arms : Nat) (h3 : 3 ≤ arms) (h4 : arms ≤ 4) : outcome (deadlineAt job) setupWorstMs .endOnly arms = .ok := by
  have : arms = 3 ∨ arms = 4 := by omega
  rcases this with rfl | rfl <;> decide +kernel

theorem worst_setup_inside_job : setupWorstMs ≤ deadlineAt job := by decide

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
  ("3 arms end only, 6 reps still fit", 1026000, none, .endOnly, 3),
  ("3 arms end only, 6 reps one ms too late", 1026001, none, .endOnly, 3),
  ("3 arms end only, walk starts after 24.75 min", 1485000, none, .endOnly, 3),
  ("3 arms end only, one ms too late", 1485001, none, .endOnly, 3),
  ("3 arms end only, cap 10 min", 276000, some 600000, .endOnly, 3),
  ("2 arms end only", 276000, none, .endOnly, 2),
  ("4 arms end only", 276000, none, .endOnly, 4),
  ("4 arms end only, walk starts after 15 min", 900000, none, .endOnly, 4),
  ("4 arms end only, walk starts after 15.83 min", 950000, none, .endOnly, 4),
  ("4 arms end only, one ms too late", 950001, none, .endOnly, 4),
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
  [.first, .first, .first, .insufficient],
  [.first, .first, .insufficient, .insufficient, .insufficient, .insufficient, .insufficient, .insufficient, .insufficient, .insufficient],
  [.insufficient, .insufficient, .insufficient, .insufficient, .insufficient, .insufficient, .insufficient, .first, .first, .first],
  [.insufficient, .insufficient, .insufficient, .insufficient, .insufficient, .insufficient, .insufficient, .insufficient, .first, .first]]

def reachCases : List (Nat × Nat × Nat × Nat) :=
  [(10, 3, 2, 5), (9, 3, 2, 5), (11, 3, 2, 5), (10, 3, 1, 5), (20, 3, 1, 5), (21, 3, 1, 5), (5, 3, 2, 5), (3, 3, 1, 2), (2, 3, 1, 2), (0, 0, 1, 2), (12, 3, 2, 7)]

def jobsForCases : List (Nat × Nat × Nat × Nat) := [(3, 2, 5, 30), (3, 1, 5, 30), (3, 1, 2, 30), (3, 1, 10, 30), (3, 2, 5, 8)]

def wavesCases : List (Nat × Nat) := [(0, 5), (1, 5), (5, 5), (6, 5), (10, 5), (11, 5), (13, 5), (14, 5)]

def faultCases : List (Bool × Bool) := [(true, true), (true, false), (false, true), (false, false)]

open Lean in
def goldenLines (_ : Unit := ()) : List String :=
  let consts := (Json.mkObj [("op", "constants"), ("timeoutMs", toJson job.timeoutMs), ("postMs", toJson job.postMs),
    ("graceMs", toJson job.graceMs), ("slackMs", toJson job.slackMs), ("deadlineAt", toJson (deadlineAt job)),
    ("hardStopMs", toJson hardStopMs), ("postStepsMs", toJson postStepsMs), ("clockMs", toJson gaps.clockMs),
    ("driftMs", toJson gaps.driftMs), ("completeMs", toJson gaps.completeMs), ("overrunMs", toJson gaps.overrunMs),
    ("minKept", toJson minKept), ("repsWant", toJson repsWant), ("lifeWindows", toJson lifeWindows), ("windowSamples", toJson windowSecs.length),
    ("bodyMs", toJson bodyMs), ("tailMs", toJson tailMs), ("meanMs", toJson meanMs), ("tailEvery", toJson tailEvery),
    ("margin", toJson margin), ("readyAllowMs", toJson readyAllowMs), ("setupWorstMs", toJson setupWorstMs), ("jobsNeeded", toJson jobsNeeded), ("macSlots", toJson Fw.Measure.WktrLayout.macSlots),
    ("planDecisive", toJson planRate.1), ("planJobs", toJson planRate.2), ("pooledDecisive", toJson pooledRate.1), ("pooledJobs", toJson pooledRate.2), ("run3Decisive", toJson (decisiveRate [3]).1), ("run3Jobs", toJson (decisiveRate [3]).2),
    ("lateDecisive", toJson lateRate.1), ("lateJobs", toJson lateRate.2),
    ("reachLatePer10k", toJson (reachPer10k jobsNeeded Fw.Gate.Smooth.minSamples 1 3)),
    ("jobsLate", match jobsFor Fw.Gate.Smooth.minSamples 1 3 target.1 target.2 jobsCap with | some v => toJson v | none => Json.null),
    ("targetNum", toJson target.1), ("targetDen", toJson target.2), ("jobsCap", toJson jobsCap),
    ("reachPer10k", toJson (reachPer10k jobsNeeded Fw.Gate.Smooth.minSamples planRate.1 planRate.2)),
    ("reachPooledPer10k", toJson (reachPer10k jobsNeeded Fw.Gate.Smooth.minSamples 1 5)), ("dominant", Json.str dominant.name),
    ("macJobs", toJson macJobs),
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
  let rs := reachCases.map fun (n, k, a, b) =>
    (Json.mkObj [("op", "reach"), ("jobs", toJson n), ("k", toJson k), ("decisiveNum", toJson a), ("den", toJson b),
      ("tailNum", toJson (tailNum n k a b)), ("per10k", toJson (reachPer10k n k a b)),
      ("reaches", toJson (reaches n k a b target.1 target.2))]).compress
  let fs := jobsForCases.map fun (k, a, b, cap) =>
    (Json.mkObj [("op", "jobsFor"), ("k", toJson k), ("decisiveNum", toJson a), ("den", toJson b), ("cap", toJson cap),
      ("jobs", match jobsFor k a b target.1 target.2 cap with | some v => toJson v | none => Json.null)]).compress
  let wv := wavesCases.map fun (j, sl) =>
    (Json.mkObj [("op", "waves"), ("jobs", toJson j), ("slots", toJson sl), ("waves", toJson (waves j sl))]).compress
  let lg := [(true, false), (true, true), (false, false), (false, true)].map fun (so, c) =>
    (Json.mkObj [("op", "legs"), ("simOnly", toJson so), ("control", toJson c),
      ("legs", toJson ((legs so c).map fun l => Json.mkObj [("name", Json.str l.name), ("jobs", toJson l.jobs), ("parallel", toJson l.parallel)])),
      ("totalJobs", toJson (totalJobs (legs so c))), ("peak", toJson (peak (legs so c))), ("waves", toJson (runWaves (legs so c))),
      ("startAtOnce", toJson (startAtOnce (legs so c)))]).compress
  let fl := faultCases.map fun (r, o) =>
    (Json.mkObj [("op", "driverFault"), ("requested", toJson r), ("on", toJson o), ("fault", toJson (driverFault r o)),
      ("name", Json.str driverFaultName)]).compress
  let ob := observedJobs.map fun (run, j, f) =>
    (Json.mkObj [("op", "observed"), ("run", toJson run), ("job", toJson j), ("fault", Json.str f.name)]).compress
  [consts] ++ ss ++ ws ++ bs ++ ps ++ es ++ gs ++ js ++ rs ++ fs ++ wv ++ lg ++ fl ++ ob

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
