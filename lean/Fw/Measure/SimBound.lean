import Fw.Measure.SimPlan
/-!
# Time bounds and the dead-inspector rule of the WebKit Simulator lane (task `webkit-sim-failfast`)
The workflow copies the bounds from `measure.simPlan`; `measure.inspector` and `measure.simBounds` are what `session.mjs` follows.
-/
namespace Fw.Measure.SimBound

/-! ## Time bounds -/

/-- Minutes one determinism session may run (healthy: at most 31.1 min, MEASURED over 56 green jobs). -/
def perSessionMin : Nat := 35

/-- Minutes the quiet experiment may run: its length does not follow the session count. -/
def quietStepMin : Nat := 50

/-- Minutes kept for the log, shutdown and upload steps after the measuring step. -/
def tailMin : Nat := 10

/-- Minutes of the steps before the measuring step (checkout, runtime check, brew, tool facts, boot). -/
def setupMin : Nat := 6

/-- Seconds of the slowest setup seen: 3.85 min in run 39426562165, boot included (MEASURED). -/
def setupSeenS : Nat := 231

/-- Seconds of the slowest Simulator boot step seen (80 to 155 s in 10-17..10-20 jobs, research/notes/2026/10-20-macos-pool-v2.md). -/
def bootSeenS : Nat := 155

/-- Silence in ms after which the stall watchdog stops the process (longest healthy silence seen: 259 s, run 39435518921). -/
def stallMs : Nat := 360000

/-- The measuring step's timeout in minutes. -/
def stepMin (experiment : String) (sessions : Nat) : Nat :=
  if experiment == "quiet" then quietStepMin else sessions * perSessionMin

/-- The job's timeout in minutes: setup, measuring step, tail. -/
def jobMin (experiment : String) (sessions : Nat) : Nat := setupMin + stepMin experiment sessions + tailMin

/-- The session count of the request text; a refused count falls back to the largest allowed. -/
def sessionsOf (s : String) : Nat := (Fw.Measure.SimPlan.countOf 1 4 s).getD 4

#guard stepMin "determinism" 1 == 35 && stepMin "determinism" 2 == 70 && stepMin "quiet" 3 == 50
#guard jobMin "determinism" 1 == 51 && sessionsOf "2" == 2 && sessionsOf "9" == 4

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

/-- **The job timeout is setup plus step plus tail.** -/
theorem job_fits_step (e : String) (k : Nat) : setupMin + stepMin e k + tailMin = jobMin e k := rfl

/-- **A full-length step still leaves the tail its minutes.** Whatever the step uses of its bound, the job timeout minus
the setup and the step is `tailMin`. -/
theorem tail_after_full_step (e : String) (k : Nat) : jobMin e k - setupMin - stepMin e k = tailMin := by
  unfold jobMin; omega

/-- **The setup allowance covers the slowest setup and boot seen.** -/
theorem setup_covers_seen : bootSeenS ≤ setupSeenS ∧ setupSeenS ≤ setupMin * 60 := by decide

/-- **Every allowed session count keeps the job within GitHub's 6-hour limit.** -/
theorem job_le_six_hours (e : String) {k : Nat} (h : k ≤ 4) : jobMin e k ≤ 360 := by
  unfold jobMin setupMin stepMin tailMin perSessionMin quietStepMin
  split <;> omega

/-- **The stall limit is 6 minutes.** -/
theorem stall_is_six_minutes : stallMs = 6 * 60 * 1000 := by decide

/-! ## Time constants of the dead-inspector path (ms) -/

/-- Period of the liveness probe: the stall watchdog's tick, `min 30000 (stallMs / 10)`. -/
def tickMs : Nat := 30000

/-- A probe that is not done after this long counts as failed. It is shorter than a tick, so probes do not overlap. -/
def probeMs : Nat := 25000

/-- Failed probes in a row that make the inspector dead. -/
def failLimit : Nat := 2

/-- From a stretch's start to its first decision: the next tick, plus that probe. -/
def firstMs : Nat := tickMs + probeMs

/-- From the start of a stretch of failing probes to the decision that finds the inspector dead. -/
def detectMs : Nat := failLimit * tickMs + probeMs

/-- Bounds of the steps of one Safari relaunch. -/
def terminateMs : Nat := 20000
def launchMs : Nat := 90000
def socketMs : Nat := 60000
def proxyMs : Nat := 40000
def tabMs : Nat := 60000
def askMs : Nat := 20000
def connectMs : Nat := 30000

/-- One Safari relaunch: terminate, launch, wait for the socket, start the proxy, wait for the tab (one extra open-URL ask
may overrun it), attach. -/
def relaunchMs : Nat := terminateMs + launchMs + socketMs + proxyMs + tabMs + askMs + connectMs

/-- From the give-up to the process exit: cleanup and the watchdog's forced exit (20 s). -/
def exitMs : Nat := 40000

/-- The time from the inspector's death to the end of the run that the lane promises: detection, one relaunch, the stall
limit. -/
def deadEndMs : Nat := detectMs + relaunchMs + stallMs

#guard detectMs == 85000 && relaunchMs == 320000 && deadEndMs == 765000

/-- The probe period is the watchdog's tick for the lane's stall limit. -/
theorem tick_is_watchdog_tick : min 30000 (stallMs / 10) = tickMs := by decide

/-- A probe ends before the next tick starts. -/
theorem probe_before_tick : probeMs < tickMs := by decide

/-- Detection ends within the stall limit, so the stall limit covers a second detection after the relaunch. -/
theorem detect_le_stall : detectMs ≤ stallMs := by decide

/-! ## Probe, failure count, action -/

/-- What one liveness probe saw. -/
structure Probe where
  socket : Bool
  proxy : Bool
  page : Bool
deriving DecidableEq, Repr

/-- The probe found everything alive: the Simulator's inspector socket, a proxy listing the Simulator, a page tab. -/
def Probe.ok (p : Probe) : Bool := p.socket && p.proxy && p.page

/-- Failed probes in a row after a probe: a healthy probe resets the count, any other adds one. -/
def nextFails (fails : Nat) (p : Probe) : Nat := if p.ok then 0 else fails + 1

/-- The inspector is dead: its socket is gone, or `failLimit` probes failed in a row. -/
def dead (socket : Bool) (fails : Nat) : Bool := !socket || decide (failLimit ≤ fails)

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

/-- Exit code of a run that gave up on a dead inspector (the stall watchdog uses 3). -/
def deadExit : Nat := 4

/-- A live inspector proceeds, a dead one relaunches Safari the first time and gives up after that. -/
def act (relaunched socket : Bool) (fails : Nat) : Action :=
  if dead socket fails then (if relaunched then .giveUp else .relaunch) else .proceed

/-- The actions for successive probes, starting before any relaunch with `fails` failures in a row. A relaunch is
remembered and resets the count; a give-up ends the run, so nothing follows it. -/
def monitor (relaunched : Bool) (fails : Nat) : List Probe → List Action
  | [] => []
  | p :: rest =>
    match act relaunched p.socket (nextFails fails p) with
    | .proceed => .proceed :: monitor relaunched (nextFails fails p) rest
    | .relaunch => .relaunch :: monitor true 0 rest
    | .giveUp => [.giveUp]

private def ok : Probe := ⟨true, true, true⟩
private def noPage : Probe := ⟨true, true, false⟩
private def noProxy : Probe := ⟨true, false, true⟩
private def noSocket : Probe := ⟨false, true, true⟩

#guard act false true 0 == .proceed && act false false 0 == .relaunch
#guard act false true 2 == .relaunch && act true false 0 == .giveUp
#guard monitor false 0 [noPage, ok, noPage, noPage, noPage, noPage] == [.proceed, .proceed, .proceed, .relaunch, .proceed, .giveUp]

/-- **A healthy probe resets the count.** -/
theorem ok_resets (f : Nat) (p : Probe) (h : p.ok = true) : nextFails f p = 0 := by
  simp [nextFails, h]

/-- **A missing socket is a failed probe.** -/
theorem no_socket_fails (f : Nat) (p : Probe) (h : p.socket = false) : nextFails f p = f + 1 := by
  simp [nextFails, Probe.ok, h]

/-- **A proxy that does not list the Simulator (refused, zero devices, timeout) is a failed probe.** -/
theorem no_proxy_fails (f : Nat) (p : Probe) (h : p.proxy = false) : nextFails f p = f + 1 := by
  simp [nextFails, Probe.ok, h]

/-- **A missing page tab with the socket and proxy alive (Safari gone) is a failed probe.** -/
theorem no_page_fails (f : Nat) (p : Probe) (h : p.page = false) : nextFails f p = f + 1 := by
  simp [nextFails, Probe.ok, h]

/-- **A healthy probe proceeds.** -/
theorem ok_proceeds (r : Bool) (f : Nat) (p : Probe) (h : p.ok = true) : act r p.socket (nextFails f p) = .proceed := by
  have hs : p.socket = true := by simp [Probe.ok] at h; exact h.1.1
  simp [act, dead, ok_resets f p h, hs, failLimit]

/-- **One failed probe with the socket present does not yet make the inspector dead.** -/
theorem one_failure_proceeds (r : Bool) (p : Probe) (hs : p.socket = true) : act r p.socket (nextFails 0 p) = .proceed ∨ p.ok = true := by
  by_cases h : p.ok = true
  · exact Or.inr h
  · left
    have : nextFails 0 p = 1 := by simp [nextFails, h]
    simp [act, dead, this, hs, failLimit]

/-- **No socket relaunches the first time.** -/
theorem no_socket_relaunches (n : Nat) : act false false n = .relaunch := by
  simp [act, dead]

/-- **Two failed probes in a row with the socket present relaunch the first time.** -/
theorem two_failures_relaunch (p : Probe) (hs : p.socket = true) (h : p.ok = false) :
    act false p.socket (nextFails (nextFails 0 p) p) = .relaunch := by
  simp [act, dead, nextFails, h, hs, failLimit]

/-- **A dead inspector after the relaunch gives up.** Whether by a missing socket or by failed probes. -/
theorem dead_after_relaunch_gives_up {s : Bool} {n : Nat} (h : dead s n = true) : act true s n = .giveUp := by
  simp [act, h]

/-- A relaunch is only decided before any relaunch happened. -/
theorem relaunch_not_relaunched {r s : Bool} {n : Nat} (h : act r s n = .relaunch) : r = false := by
  unfold act at h
  split at h <;> cases r <;> simp_all

/-- **Safari is relaunched at most once.** Whatever the probes, the run holds at most one relaunch. -/
theorem relaunch_at_most_once (r : Bool) (f : Nat) (ps : List Probe) :
    (monitor r f ps).count .relaunch ≤ (if r then 0 else 1) := by
  induction ps generalizing r f with
  | nil => simp [monitor]
  | cons p rest ih =>
    unfold monitor
    cases h : act r p.socket (nextFails f p) with
    | proceed => simpa [List.count_cons] using ih r (nextFails f p)
    | relaunch =>
      have hr := relaunch_not_relaunched h
      subst hr
      have := ih true 0
      simp at this ⊢
      omega
    | giveUp => simp

/-- **A give-up ends the run.** If the run holds a give-up, it is the last action and the only one. -/
theorem giveUp_last (r : Bool) (f : Nat) (ps : List Probe) (h : Action.giveUp ∈ monitor r f ps) :
    ∃ pre, monitor r f ps = pre ++ [Action.giveUp] ∧ Action.giveUp ∉ pre := by
  induction ps generalizing r f with
  | nil => simp [monitor] at h
  | cons p rest ih =>
    unfold monitor at h ⊢
    cases hd : act r p.socket (nextFails f p) with
    | proceed =>
      rw [hd] at h
      simp only [List.mem_cons] at h
      obtain ⟨pre, hp, hn⟩ := ih r (nextFails f p) (by simpa using h)
      exact ⟨.proceed :: pre, by simp [hp], by simpa using hn⟩
    | relaunch =>
      rw [hd] at h
      simp only [List.mem_cons] at h
      obtain ⟨pre, hp, hn⟩ := ih true 0 (by simpa using h)
      exact ⟨.relaunch :: pre, by simp [hp], by simpa using hn⟩
    | giveUp => exact ⟨[], by simp, by simp⟩

/-! ## A dead inspector ends the run -/

/-- Worst-case time from the start of a stretch to the decision of the last of `acts`. A stretch starts at the inspector's
death and again at the end of each relaunch. Its first probe decides within `firstMs`, every later one a tick after the
one before, and a relaunch takes `relaunchMs` and starts the next stretch. `k` counts the probes of the stretch so far. -/
def decideMs : List Action → Nat → Nat
  | [], _ => 0
  | .relaunch :: rest, k => (if k = 0 then firstMs else tickMs) + relaunchMs + decideMs rest 0
  | _ :: rest, k => (if k = 0 then firstMs else tickMs) + decideMs rest (k + 1)

#guard decideMs [.proceed, .relaunch, .proceed, .giveUp] 0 == 2 * detectMs + relaunchMs

/-- The time of `acts` is at most one tick per probe, one probe time and one relaunch time per relaunch, and one probe
time more when the stretch has no probe yet (`k = 0`). -/
theorem decideMs_le (acts : List Action) (k : Nat) :
    decideMs acts k ≤ acts.length * tickMs + (acts.count .relaunch + (if k = 0 then 1 else 0)) * probeMs
      + acts.count .relaunch * relaunchMs := by
  induction acts generalizing k with
  | nil => simp [decideMs]
  | cons a rest ih =>
    have h0 := ih 0
    have h1 := ih (k + 1)
    cases a <;> by_cases hk : k = 0 <;>
      simp [decideMs, firstMs, tickMs, probeMs, relaunchMs, terminateMs, launchMs, socketMs, proxyMs, tabMs, askMs, connectMs,
        hk] at * <;> omega

/-- All probes failed from the start: the inspector is dead for good. -/
def AllFail (ps : List Probe) : Prop := ∀ p ∈ ps, p.ok = false

/-- After a relaunch with `f < failLimit` failures counted, failing probes make the run give up within `failLimit - f`
probes, and no later. -/
theorem giveUp_after_relaunch (f : Nat) (hf : f < failLimit) (ps : List Probe) (h : AllFail ps) :
    (monitor true f ps).length ≤ failLimit - f ∧ (failLimit - f ≤ ps.length → Action.giveUp ∈ monitor true f ps) := by
  induction ps generalizing f with
  | nil =>
    refine ⟨by simp [monitor], fun hl => ?_⟩
    simp [failLimit] at hl hf; omega
  | cons p rest ih =>
    have hp : p.ok = false := h p (by simp)
    have hrest : AllFail rest := fun q hq => h q (by simp [hq])
    have hn : nextFails f p = f + 1 := by simp [nextFails, hp]
    unfold monitor
    cases hd : act true p.socket (nextFails f p) with
    | giveUp => simp [failLimit] at hf ⊢; omega
    | relaunch => exact absurd (relaunch_not_relaunched hd) (by simp)
    | proceed =>
      have hlt : f + 1 < failLimit := by
        by_cases hc : f + 1 < failLimit
        · exact hc
        · have hdead : dead p.socket (nextFails f p) = true := by simp [dead, hn, failLimit] at hc ⊢; omega
          simp [act, hdead] at hd
      obtain ⟨h1, h2⟩ := ih (f + 1) hlt hrest
      rw [hn] at *
      simp only [List.length_cons, List.mem_cons]
      refine ⟨by omega, fun hl => Or.inr (h2 (by omega))⟩

/-- Before any relaunch, with `f < failLimit` failures counted, failing probes make the run give up within
`(failLimit - f) + failLimit` probes, and a give-up has a relaunch before it. -/
theorem giveUp_before_relaunch (f : Nat) (hf : f < failLimit) (ps : List Probe) (h : AllFail ps) :
    (monitor false f ps).length ≤ (failLimit - f) + failLimit
    ∧ ((failLimit - f) + failLimit ≤ ps.length → Action.giveUp ∈ monitor false f ps)
    ∧ (Action.giveUp ∈ monitor false f ps → Action.relaunch ∈ monitor false f ps) := by
  induction ps generalizing f with
  | nil =>
    refine ⟨by simp [monitor], fun hl => ?_, by simp [monitor]⟩
    simp [failLimit] at hl hf; try omega
  | cons p rest ih =>
    have hp : p.ok = false := h p (by simp)
    have hrest : AllFail rest := fun q hq => h q (by simp [hq])
    have hn : nextFails f p = f + 1 := by simp [nextFails, hp]
    unfold monitor
    cases hd : act false p.socket (nextFails f p) with
    | giveUp =>
      exfalso
      by_cases hdead : dead p.socket (nextFails f p) = true <;> simp [act, hdead] at hd
    | relaunch =>
      obtain ⟨h1, h2⟩ := giveUp_after_relaunch 0 (by simp [failLimit]) rest hrest
      refine ⟨?_, fun hl => ?_, fun _ => by simp⟩
      · simp [failLimit] at h1 hf ⊢; omega
      · simp only [List.mem_cons]
        exact Or.inr (h2 (by simp [failLimit] at hl hf ⊢; omega))
    | proceed =>
      have hlt : f + 1 < failLimit := by
        by_cases hc : f + 1 < failLimit
        · exact hc
        · have hdead : dead p.socket (nextFails f p) = true := by simp [dead, hn, failLimit] at hc ⊢; omega
          have hr : act false p.socket (nextFails f p) = .relaunch := by simp [act, hdead]
          rw [hd] at hr; cases hr
      obtain ⟨h1, h2, h3⟩ := ih (f + 1) hlt hrest
      rw [hn] at *
      simp only [List.length_cons, List.mem_cons]
      refine ⟨by simp [failLimit] at h1 hlt hf ⊢; omega, fun hl => Or.inr (h2 (by simp [failLimit] at hl hlt hf ⊢; omega)), ?_⟩
      intro hg
      rcases hg with hg | hg
      · cases hg
      · exact Or.inr (h3 hg)

/-- **A permanently dead inspector gives up.** From a healthy start (`monitor false 0`), a run of failing probes at least
`2 * failLimit` long ends with one give-up, after exactly one relaunch and fewer than `2 * failLimit` actions before it. -/
theorem dead_forever_gives_up (ps : List Probe) (h : AllFail ps) (hl : 2 * failLimit ≤ ps.length) :
    ∃ pre, monitor false 0 ps = pre ++ [Action.giveUp] ∧ pre.length < 2 * failLimit ∧ pre.count Action.relaunch = 1 := by
  obtain ⟨h1, h2, h3⟩ := giveUp_before_relaunch 0 (by simp [failLimit]) ps h
  have hg := h2 (by simp [failLimit] at hl ⊢; omega)
  obtain ⟨pre, hp, hn⟩ := giveUp_last false 0 ps hg
  have hle := relaunch_at_most_once false 0 ps
  have hge : 1 ≤ (monitor false 0 ps).count Action.relaunch := List.count_pos_iff.mpr (h3 hg)
  refine ⟨pre, hp, ?_, ?_⟩
  · rw [hp] at h1; simp [failLimit, Nat.sub_zero] at h1 ⊢; omega
  · rw [hp] at hle hge
    simp [List.count_append] at hle hge
    have := List.count_pos_iff.mpr hge
    omega

/-- **From the death of the inspector the run ends within `deadEndMs`.** When the inspector stays dead, probes keep
failing: the run holds one relaunch, then a give-up (exit code `deadExit`), no second relaunch, and the time up to the
give-up is at most `2 * detectMs + relaunchMs`, and with `exitMs` for the exit it is within
`deadEndMs = detectMs + relaunchMs + stallMs`. A probe in
flight at the moment of death may still pass; the bound counts from the first probe that starts after it. -/
theorem dead_run_ends (ps : List Probe) (h : AllFail ps) (hl : 2 * failLimit ≤ ps.length) :
    ∃ pre, monitor false 0 ps = pre ++ [Action.giveUp] ∧ pre.count Action.relaunch = 1
      ∧ decideMs (monitor false 0 ps) 0 ≤ 2 * detectMs + relaunchMs ∧ 2 * detectMs + relaunchMs + exitMs ≤ deadEndMs := by
  obtain ⟨pre, hp, hlen, hc⟩ := dead_forever_gives_up ps h hl
  refine ⟨pre, hp, hc, ?_, ?_⟩
  · have := decideMs_le (monitor false 0 ps) 0
    rw [hp] at this ⊢
    simp [List.count_append, hc] at this
    simp [detectMs, failLimit, tickMs, probeMs, relaunchMs, terminateMs, launchMs, socketMs, proxyMs, tabMs, askMs, connectMs] at hlen ⊢ this
    omega
  · simp [deadEndMs, exitMs, detectMs, stallMs, failLimit, tickMs, probeMs, relaunchMs, terminateMs, launchMs, socketMs, proxyMs, tabMs, askMs, connectMs]

end Fw.Measure.SimBound
