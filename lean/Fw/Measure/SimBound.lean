import Fw.Measure.SimPlan
/-!
# Time bounds and the dead-inspector rule of the WebKit Simulator lane (task `webkit-sim-failfast`)
The workflow copies the bounds from `measure.simPlan`; `measure.inspector` is the rule `session.mjs` follows.
-/
namespace Fw.Measure.SimBound

/-! ## Time bounds -/

/-- Minutes one determinism session may run (healthy: at most 31.1 min, MEASURED over 56 green jobs). -/
def perSessionMin : Nat := 35

/-- Minutes the quiet experiment may run: its length does not follow the session count. -/
def quietStepMin : Nat := 50

/-- Minutes kept for the log, shutdown and upload steps after the measuring step. -/
def tailMin : Nat := 10

/-- Silence in ms after which the stall watchdog stops the process (longest healthy silence: 239 s). -/
def stallMs : Nat := 360000

/-- The measuring step's timeout in minutes. -/
def stepMin (experiment : String) (sessions : Nat) : Nat :=
  if experiment == "quiet" then quietStepMin else sessions * perSessionMin

/-- The job's timeout in minutes. -/
def jobMin (experiment : String) (sessions : Nat) : Nat := stepMin experiment sessions + tailMin

/-- The session count of the request text; a refused count falls back to the largest allowed. -/
def sessionsOf (s : String) : Nat := (Fw.Measure.SimPlan.countOf 1 4 s).getD 4

#guard stepMin "determinism" 1 == 35 && stepMin "determinism" 2 == 70 && stepMin "quiet" 3 == 50
#guard jobMin "determinism" 1 == 45 && sessionsOf "2" == 2 && sessionsOf "9" == 4

/-- **The step timeout follows the session count.** `k` determinism sessions get `k` times the per-session bound. -/
theorem stepMin_determinism (k : Nat) : stepMin "determinism" k = k * perSessionMin := by
  simp [stepMin]

/-- **The quiet experiment keeps its fixed bound.** -/
theorem stepMin_quiet (k : Nat) : stepMin "quiet" k = quietStepMin := by
  simp [stepMin]

/-- **More sessions never get a shorter step.** -/
theorem stepMin_mono (e : String) {a b : Nat} (h : a ≤ b) : stepMin e a ≤ stepMin e b := by
  unfold stepMin
  split
  · exact Nat.le_refl _
  · exact Nat.mul_le_mul_right _ h

/-- **A default dispatch is tighter than the old fixed 50.** One determinism session gets under 50 minutes. -/
theorem one_session_below_old : stepMin "determinism" 1 < 50 := by decide

/-- **The tail steps fit inside the job.** The measuring step plus the tail is the job timeout, so a step that uses its
whole bound still leaves the log, shutdown and upload steps their time. -/
theorem job_fits_step (e : String) (k : Nat) : stepMin e k + tailMin = jobMin e k := rfl

/-- **Every allowed session count keeps the job within GitHub's 6-hour limit.** -/
theorem job_le_six_hours (e : String) {k : Nat} (h : k ≤ 4) : jobMin e k ≤ 360 := by
  unfold jobMin stepMin tailMin perSessionMin quietStepMin
  split <;> omega

/-- **The stall limit is 6 minutes.** -/
theorem stall_is_six_minutes : stallMs = 6 * 60 * 1000 := by decide

/-! ## Dead inspector: relaunch Safari once, then stop -/

/-- What the session does when it finds the inspector. -/
inductive Action where
  | proceed
  | relaunch
  | giveUp
deriving DecidableEq, Repr

/-- The action's wire name. -/
def Action.name : Action → String
  | .proceed => "proceed"
  | .relaunch => "relaunch"
  | .giveUp => "giveUp"

/-- Refused connections to the proxy that count as a dead inspector. -/
def refusalLimit : Nat := 2

/-- Exit code of a run that gave up on a dead inspector (the stall watchdog uses 3). -/
def deadExit : Nat := 4

/-- The inspector is dead: Safari's inspector socket is gone, or the proxy refused `refusalLimit` times. -/
def dead (socket : Bool) (refusals : Nat) : Bool := !socket || decide (refusalLimit ≤ refusals)

/-- The action: a live inspector proceeds, a dead one relaunches Safari the first time and gives up after that. -/
def act (relaunched socket : Bool) (refusals : Nat) : Action :=
  if dead socket refusals then (if relaunched then .giveUp else .relaunch) else .proceed

/-- The actions for successive findings `(socket, refusals)`, starting before any relaunch. A relaunch is remembered;
a give-up ends the run, so nothing follows it.
-/
def run (relaunched : Bool) : List (Bool × Nat) → List Action
  | [] => []
  | (s, n) :: rest =>
    match act relaunched s n with
    | .proceed => .proceed :: run relaunched rest
    | .relaunch => .relaunch :: run true rest
    | .giveUp => [.giveUp]

#guard act false true 0 == .proceed && act false false 0 == .relaunch
#guard act false true 2 == .relaunch && act true false 0 == .giveUp
#guard run false [(false, 0), (true, 0), (false, 0), (true, 0)] == [.relaunch, .proceed, .giveUp]

/-- **A live inspector proceeds.** With the socket present and fewer than two refusals, nothing is relaunched. -/
theorem live_proceeds (r : Bool) {n : Nat} (h : n < refusalLimit) : act r true n = .proceed := by
  have : ¬ refusalLimit ≤ n := by omega
  simp [act, dead, this]

/-- **No socket relaunches the first time.** -/
theorem no_socket_relaunches (n : Nat) : act false false n = .relaunch := by
  simp [act, dead]

/-- **Refused twice relaunches the first time.** -/
theorem refused_relaunches {n : Nat} (h : refusalLimit ≤ n) : act false true n = .relaunch := by
  simp [act, dead, h]

/-- **A dead inspector after the relaunch gives up.** Whether by a missing socket or by refusals. -/
theorem dead_after_relaunch_gives_up {s : Bool} {n : Nat} (h : dead s n = true) : act true s n = .giveUp := by
  simp [act, h]

/-- A relaunch is only decided before any relaunch happened. -/
theorem relaunch_not_relaunched {r s : Bool} {n : Nat} (h : act r s n = .relaunch) : r = false := by
  unfold act at h
  split at h <;> cases r <;> simp_all

/-- **Safari is relaunched at most once.** Whatever the findings, the run holds at most one relaunch. -/
theorem relaunch_at_most_once (r : Bool) (fs : List (Bool × Nat)) :
    (run r fs).count .relaunch ≤ (if r then 0 else 1) := by
  induction fs generalizing r with
  | nil => simp [run]
  | cons f rest ih =>
    obtain ⟨s, n⟩ := f
    unfold run
    cases h : act r s n with
    | proceed => simpa [List.count_cons] using ih r
    | relaunch =>
      have hr := relaunch_not_relaunched h
      subst hr
      have := ih true
      simp at this ⊢
      omega
    | giveUp => simp

/-- **A give-up ends the run.** If the run holds a give-up, it is the last action and the only one. -/
theorem giveUp_last (r : Bool) (fs : List (Bool × Nat)) (h : Action.giveUp ∈ run r fs) :
    ∃ pre, run r fs = pre ++ [Action.giveUp] ∧ Action.giveUp ∉ pre := by
  induction fs generalizing r with
  | nil => simp [run] at h
  | cons f rest ih =>
    obtain ⟨s, n⟩ := f
    unfold run at h ⊢
    cases hd : act r s n with
    | proceed =>
      rw [hd] at h
      simp only [List.mem_cons] at h
      obtain ⟨pre, hp, hn⟩ := ih r (by simpa using h)
      exact ⟨.proceed :: pre, by simp [hp], by simpa using hn⟩
    | relaunch =>
      rw [hd] at h
      simp only [List.mem_cons] at h
      obtain ⟨pre, hp, hn⟩ := ih true (by simpa using h)
      exact ⟨.relaunch :: pre, by simp [hp], by simpa using hn⟩
    | giveUp => exact ⟨[], by simp, by simp⟩

/-- **One relaunch costs one relaunch.** With a relaunch taking `ms` at most, the relaunch time of a run is at most `ms`:
a dead inspector ends the run within one relaunch plus the stall limit.
-/
theorem relaunch_time_le (ms : Nat) (fs : List (Bool × Nat)) :
    (run false fs).count .relaunch * ms ≤ ms := by
  have := relaunch_at_most_once false fs
  simp only [Bool.false_eq_true, ite_false] at this
  calc _ ≤ 1 * ms := Nat.mul_le_mul_right ms this
    _ = ms := Nat.one_mul ms

end Fw.Measure.SimBound
