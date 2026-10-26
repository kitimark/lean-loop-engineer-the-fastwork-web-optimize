import Fw.Measure.SimPlan
/-!
# Time bounds and the dead-inspector rule of the WebKit Simulator lane (task `webkit-sim-failfast`)
The workflow copies the bounds from `measure.simPlan`; `measure.inspector` and `measure.simBounds` are what `session.mjs` follows.
-/
namespace Fw.Measure.SimBound

/-! ## Time bounds -/

/-- Minutes one determinism session may run. -/
def perSessionMin : Nat := 35

/-- Minutes the quiet experiment may run: its length does not follow the session count. -/
def quietStepMin : Nat := 50

/-- Minutes kept for the log, shutdown and upload steps after the measuring step. -/
def tailMin : Nat := 10

/-! Measured maxima: the one home of the numbers the bounds below are checked against, each with its CI run id. -/
namespace Seen

/-- Longest silence of a green run, seconds (run 39343967737, census y=4500 line at 00:08:44Z to 00:16:55Z). -/
def silenceMaxS : Nat := 491

/-- Other long silences of green runs, seconds: runs 39357736128 (318), 39447981526 (266), 39435518921 (259). -/
def silenceOtherS : List Nat := [318, 266, 259]

/-- Slowest Simulator boot step, seconds (run 39444758495). -/
def bootS : Nat := 305

/-- Slowest setup before the measuring step, boot included, seconds (run 39444758495, job start 15:08:26Z to 15:14:09Z). -/
def setupS : Nat := 343

end Seen

/-- Minutes of the steps before the measuring step (checkout, runtime check, brew, tool facts, boot): at least 1.3 times `Seen.setupS`. -/
def setupMin : Nat := 8

/-- Silence in ms after which the stall watchdog stops the process: main's limit, `FW_WK_TIMEOUT_SCALE` 8 times the
watchdog default of 90000 ms. -/
def stallMs : Nat := 720000

/-- The measuring step's timeout in minutes. -/
def stepMin (experiment : String) (sessions : Nat) : Nat :=
  if experiment == "quiet" then quietStepMin else sessions * perSessionMin

/-- The job's timeout in minutes: setup, measuring step, tail. -/
def jobMin (experiment : String) (sessions : Nat) : Nat := setupMin + stepMin experiment sessions + tailMin

/-- The session count of the request text; a refused count falls back to the largest allowed. -/
def sessionsOf (s : String) : Nat := (Fw.Measure.SimPlan.countOf 1 4 s).getD 4

#guard stepMin "determinism" 1 == 35 && stepMin "determinism" 2 == 70 && stepMin "quiet" 3 == 50
#guard jobMin "determinism" 1 == 53 && sessionsOf "2" == 2 && sessionsOf "9" == 4

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

/-- **The setup allowance is at least 1.3 times the slowest setup seen.** -/
theorem setup_covers_seen : Seen.bootS ≤ Seen.setupS ∧ 13 * Seen.setupS ≤ setupMin * 60 * 10 := by decide

/-- **Every allowed session count keeps the job within GitHub's 6-hour limit.** -/
theorem job_le_six_hours (e : String) {k : Nat} (h : k ≤ 4) : jobMin e k ≤ 360 := by
  unfold jobMin setupMin stepMin tailMin perSessionMin quietStepMin
  split <;> omega

/-- **The stall limit is main's.** `FW_WK_TIMEOUT_SCALE` 8 times the watchdog default of 90000 ms. -/
theorem stall_is_main_limit : stallMs = 8 * 90000 := by decide

/-- **The stall limit is at least 1.3 times the longest silence seen.** -/
theorem stall_covers_seen : 13 * (Seen.silenceMaxS * 1000) ≤ 10 * stallMs ∧ ∀ s ∈ Seen.silenceOtherS, s ≤ Seen.silenceMaxS := by
  decide

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

/-- Bounds of one proxy restart (`restartProxy`, session.mjs): `proc.stop` waits at most 20 x 100 ms (sim.mjs `startProxy`,
`stop`), the `lsof` call is capped at `lsofMs` (session.mjs `lsofMs: 5000`), the proxy gets `proxyMs - 5000` to list the
Simulator (session.mjs `timeoutMs: BOUNDS.proxyMs - 5000`). -/
def stopMs : Nat := 2000
def lsofMs : Nat := 5000
def proxyStartMs : Nat := proxyMs - 5000

/-- One repair: stop the proxy, look up the socket, start the proxy. -/
def repairMs : Nat := stopMs + lsofMs + proxyStartMs

/-- From the give-up to the process exit: cleanup and the watchdog's forced exit (20 s). -/
def exitMs : Nat := 40000

/-- The time from the inspector's death to the exit that the lane promises: two detections, two repairs (one per stretch,
after the stretch's first failed probe), one relaunch, the exit. The stall limit is a separate backstop (`detect_le_stall`). -/
def deadEndMs : Nat := 2 * detectMs + 2 * repairMs + relaunchMs + exitMs

#guard detectMs == 85000 && relaunchMs == 320000 && repairMs == 42000 && deadEndMs == 614000

/-- The probe period is the watchdog's tick for the lane's stall limit. -/
theorem tick_is_watchdog_tick : min 30000 (stallMs / 10) = tickMs := by decide

/-- A probe ends before the next tick starts. -/
theorem probe_before_tick : probeMs < tickMs := by decide

/-- One detection takes less than the stall limit. -/
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

/-- What the session does after the relaunch it started: a failed relaunch gives up, a good one goes on (the failure count is
reset). -/
def afterRelaunch (ok : Bool) : Action := if ok then .proceed else .giveUp

/-- The actions for successive probes, starting before any relaunch with `fails` failures in a row. `ok` is whether the one
relaunch works. A relaunch is remembered and resets the count; a give-up ends the run, so nothing follows it. -/
def monitor (ok : Bool) : Bool → Nat → List Probe → List Action
  | _, _, [] => []
  | relaunched, fails, p :: rest =>
    match act relaunched p.socket (nextFails fails p) with
    | .proceed => .proceed :: monitor ok relaunched (nextFails fails p) rest
    | .relaunch =>
      .relaunch :: (match afterRelaunch ok with
        | .giveUp => [.giveUp]
        | _ => monitor ok true 0 rest)
    | .giveUp => [.giveUp]

private def ok : Probe := ⟨true, true, true⟩
private def noPage : Probe := ⟨true, true, false⟩
private def noProxy : Probe := ⟨true, false, true⟩
private def noSocket : Probe := ⟨false, true, true⟩

#guard act false true 0 == .proceed && act false false 0 == .relaunch
#guard act false true 2 == .relaunch && act true false 0 == .giveUp
#guard afterRelaunch true == .proceed && afterRelaunch false == .giveUp
#guard monitor true false 0 [noPage, ok, noPage, noPage, noPage, noPage] == [.proceed, .proceed, .proceed, .relaunch, .proceed, .giveUp]
#guard monitor false false 0 [noPage, noPage, ok] == [.proceed, .relaunch, .giveUp]

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

/-- **Safari is relaunched at most once.** Whatever the probes and the relaunch outcome. -/
theorem relaunch_at_most_once (ok r : Bool) (f : Nat) (ps : List Probe) :
    (monitor ok r f ps).count .relaunch ≤ (if r then 0 else 1) := by
  induction ps generalizing r f with
  | nil => simp [monitor]
  | cons p rest ih =>
    unfold monitor
    cases h : act r p.socket (nextFails f p) with
    | proceed => simpa [List.count_cons] using ih r (nextFails f p)
    | relaunch =>
      have hr := relaunch_not_relaunched h
      subst hr
      cases ok
      · simp [afterRelaunch]
      · have := ih true 0
        simp [afterRelaunch] at this ⊢
        omega
    | giveUp => simp

/-- **A give-up ends the run.** If the run holds a give-up, it is the last action and the only one. -/
theorem giveUp_last (ok r : Bool) (f : Nat) (ps : List Probe) (h : Action.giveUp ∈ monitor ok r f ps) :
    ∃ pre, monitor ok r f ps = pre ++ [Action.giveUp] ∧ Action.giveUp ∉ pre := by
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
      cases ok
      · exact ⟨[.relaunch], by simp [afterRelaunch], by simp⟩
      · rw [hd] at h
        simp only [afterRelaunch, List.mem_cons] at h
        obtain ⟨pre, hp, hn⟩ := ih true 0 (by simpa using h)
        exact ⟨.relaunch :: pre, by simp [afterRelaunch, hp], by simpa using hn⟩
    | giveUp => exact ⟨[], by simp, by simp⟩

/-! ## A dead inspector ends the run -/

/-- Worst-case time from the start of a stretch to the decision of the last of `acts`. A stretch starts at the inspector's
death and again at the end of each relaunch. Its first probe decides within `firstMs`, every later one a tick after the
one before, and a relaunch takes `relaunchMs` and starts the next stretch. `k` counts the probes of the stretch so far.
Repairs and skipped ticks are not in it (`timeMs` adds the repairs). -/
def decideMs : List Action → Nat → Nat
  | [], _ => 0
  | .relaunch :: rest, k => (if k = 0 then firstMs else tickMs) + relaunchMs + decideMs rest 0
  | _ :: rest, k => (if k = 0 then firstMs else tickMs) + decideMs rest (k + 1)

/-- `decideMs` plus one repair per `.proceed` (a failed probe that does not yet make the inspector dead repairs the proxy). -/
def timeMs (acts : List Action) : Nat := decideMs acts 0 + acts.count .proceed * repairMs

#guard decideMs [.proceed, .relaunch, .proceed, .giveUp] 0 == 2 * detectMs + relaunchMs
#guard timeMs [.proceed, .relaunch, .proceed, .giveUp] + exitMs == deadEndMs

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

/-- The three actions partition a list. -/
theorem count_actions (l : List Action) : l.count .proceed + l.count .relaunch + l.count .giveUp = l.length := by
  induction l with
  | nil => simp
  | cons a rest ih => cases a <;> simp <;> omega

/-- All probes failed from the start: the inspector is dead for good. -/
def AllFail (ps : List Probe) : Prop := ∀ p ∈ ps, p.ok = false

/-- After a relaunch with `f < failLimit` failures counted, failing probes make the run give up within `failLimit - f`
probes, and no later. -/
theorem giveUp_after_relaunch (ok : Bool) (f : Nat) (hf : f < failLimit) (ps : List Probe) (h : AllFail ps) :
    (monitor ok true f ps).length ≤ failLimit - f ∧ (failLimit - f ≤ ps.length → Action.giveUp ∈ monitor ok true f ps) := by
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
theorem giveUp_before_relaunch (ok : Bool) (f : Nat) (hf : f < failLimit) (ps : List Probe) (h : AllFail ps) :
    (monitor ok false f ps).length ≤ (failLimit - f) + failLimit
    ∧ ((failLimit - f) + failLimit ≤ ps.length → Action.giveUp ∈ monitor ok false f ps)
    ∧ (Action.giveUp ∈ monitor ok false f ps → Action.relaunch ∈ monitor ok false f ps) := by
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
      cases ok
      · refine ⟨?_, fun _ => ?_, fun _ => by simp⟩
        · simp [afterRelaunch, failLimit] at hf ⊢
        · simp [afterRelaunch]
      · obtain ⟨h1, h2⟩ := giveUp_after_relaunch true 0 (by simp [failLimit]) rest hrest
        refine ⟨?_, fun hl => ?_, fun _ => by simp⟩
        · simp [afterRelaunch, failLimit] at h1 hf ⊢; omega
        · simp only [afterRelaunch, ite_true, List.mem_cons]
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

/-- **A permanently dead inspector gives up.** From a healthy start (`monitor ok false 0`), a run of failing probes at least
`2 * failLimit` long ends with one give-up, after exactly one relaunch and fewer than `2 * failLimit` actions before it. -/
theorem dead_forever_gives_up (ok : Bool) (ps : List Probe) (h : AllFail ps) (hl : 2 * failLimit ≤ ps.length) :
    ∃ pre, monitor ok false 0 ps = pre ++ [Action.giveUp] ∧ pre.length < 2 * failLimit ∧ pre.count Action.relaunch = 1 := by
  obtain ⟨h1, h2, h3⟩ := giveUp_before_relaunch ok 0 (by simp [failLimit]) ps h
  have hg := h2 (by simp [failLimit] at hl ⊢; omega)
  obtain ⟨pre, hp, hn⟩ := giveUp_last ok false 0 ps hg
  have hle := relaunch_at_most_once ok false 0 ps
  have hge : 1 ≤ (monitor ok false 0 ps).count Action.relaunch := List.count_pos_iff.mpr (h3 hg)
  refine ⟨pre, hp, ?_, ?_⟩
  · rw [hp] at h1; simp [failLimit, Nat.sub_zero] at h1 ⊢; omega
  · rw [hp] at hle hge
    simp [List.count_append] at hle hge
    have := List.count_pos_iff.mpr hge
    omega

/-- **A failed relaunch ends the run.** When the inspector stays dead and the relaunch fails, the run is `n < failLimit`
proceeds, the relaunch and the give-up. -/
theorem failed_relaunch_shape (f : Nat) (hf : f < failLimit) (ps : List Probe) (h : AllFail ps) (hl : failLimit - f ≤ ps.length) :
    ∃ n, n < failLimit - f ∧ monitor false false f ps = List.replicate n Action.proceed ++ [.relaunch, .giveUp] := by
  induction ps generalizing f with
  | nil => simp [failLimit] at hl hf; omega
  | cons p rest ih =>
    have hp : p.ok = false := h p (by simp)
    have hrest : AllFail rest := fun q hq => h q (by simp [hq])
    have hn : nextFails f p = f + 1 := by simp [nextFails, hp]
    unfold monitor
    cases hd : act false p.socket (nextFails f p) with
    | giveUp =>
      exfalso
      by_cases hdead : dead p.socket (nextFails f p) = true <;> simp [act, hdead] at hd
    | relaunch => exact ⟨0, by simp [failLimit] at hf ⊢; omega, by simp [afterRelaunch]⟩
    | proceed =>
      have hlt : f + 1 < failLimit := by
        by_cases hc : f + 1 < failLimit
        · exact hc
        · have hdead : dead p.socket (nextFails f p) = true := by simp [dead, hn, failLimit] at hc ⊢; omega
          have hr : act false p.socket (nextFails f p) = .relaunch := by simp [act, hdead]
          rw [hd] at hr; cases hr
      rw [hn] at *
      obtain ⟨n, hn', he⟩ := ih (f + 1) hlt hrest (by simp [failLimit] at hl hlt ⊢; omega)
      exact ⟨n + 1, by simp [failLimit] at hn' hf ⊢; omega, by simp [he, List.replicate_succ]⟩

/-- The failed-relaunch path in numbers: detection, one repair, the relaunch and the exit fit `deadEndMs`. -/
theorem failed_path_le_deadEnd : detectMs + repairMs + relaunchMs + exitMs ≤ deadEndMs := by decide

/-- **Failed-relaunch path: the exit comes within `deadEndMs`.** The path that CI showed (the fault keeps killing during the
relaunch). From the death: detection, at most one repair, the failed relaunch, the exit. -/
theorem failed_relaunch_ends (ps : List Probe) (h : AllFail ps) (hl : failLimit ≤ ps.length) :
    ∃ n, n < failLimit ∧ monitor false false 0 ps = List.replicate n Action.proceed ++ [.relaunch, .giveUp]
      ∧ timeMs (List.replicate n Action.proceed ++ [.relaunch]) + exitMs ≤ detectMs + repairMs + relaunchMs + exitMs
      ∧ detectMs + repairMs + relaunchMs + exitMs ≤ deadEndMs := by
  obtain ⟨n, hn, he⟩ := failed_relaunch_shape 0 (by simp [failLimit]) ps h (by simpa using hl)
  refine ⟨n, by simpa using hn, he, ?_, failed_path_le_deadEnd⟩
  have hn2 : n < 2 := by simpa [failLimit] using hn
  obtain rfl | rfl : n = 0 ∨ n = 1 := by omega
  all_goals decide

/-- The dead-again path in numbers: up to 4 decisions (2 proceeds, a relaunch, a give-up), 2 repairs, the exit. -/
theorem dead_again_arith (D P L : Nat) (hd : D ≤ (L + 1) * tickMs + 2 * probeMs + relaunchMs) (hL : L < 4) (hP : P + 2 = L + 1) :
    D + P * repairMs + exitMs ≤ deadEndMs := by
  have h3 : L ≤ 3 := by omega
  have hP2 : P ≤ 2 := by omega
  have e : tickMs = 30000 := rfl
  have e2 : probeMs = 25000 := rfl
  have e3 : relaunchMs = 320000 := rfl
  have e4 : repairMs = 42000 := rfl
  have e5 : exitMs = 40000 := rfl
  have e6 : deadEndMs = 614000 := rfl
  rw [e, e2, e3] at hd
  rw [e4, e5, e6]
  omega

/-- **Dead-again path: the exit comes within `deadEndMs`.** When the inspector stays dead and the relaunch works, the run
holds one relaunch, then a give-up (exit code `deadExit`): detection, at most one repair, the relaunch, again detection and
at most one repair, the exit. A probe in flight at the moment of death may still pass; the bound counts from the first probe
that starts after it. -/
theorem dead_run_ends (ps : List Probe) (h : AllFail ps) (hl : 2 * failLimit ≤ ps.length) :
    ∃ pre, monitor true false 0 ps = pre ++ [Action.giveUp] ∧ pre.count Action.relaunch = 1
      ∧ timeMs (monitor true false 0 ps) + exitMs ≤ deadEndMs := by
  obtain ⟨pre, hp, hlen, hc⟩ := dead_forever_gives_up true ps h hl
  refine ⟨pre, hp, hc, ?_⟩
  obtain ⟨q, hq1, hq2⟩ := giveUp_last true false 0 ps (by rw [hp]; simp)
  have hqq : pre = q := List.append_cancel_right (hp.symm.trans hq1)
  have hz : pre.count Action.giveUp = 0 := List.count_eq_zero.mpr (hqq ▸ hq2)
  have hd := decideMs_le (monitor true false 0 ps) 0
  have hcnt := count_actions pre
  rw [hp] at hd ⊢
  have hpc : (pre ++ [Action.giveUp]).count Action.proceed = pre.count Action.proceed := by
    simp [List.count_append]
  have hd' : decideMs (pre ++ [Action.giveUp]) 0 ≤ (pre.length + 1) * tickMs + 2 * probeMs + relaunchMs := by
    simpa [List.count_append, hc] using hd
  have hlen' : pre.length < 4 := by simpa [failLimit] using hlen
  have hcnt' : pre.count Action.proceed + 2 = pre.length + 1 := by omega
  unfold timeMs
  rw [hpc]
  exact dead_again_arith _ _ _ hd' hlen' hcnt'

/-! ## Page target lost (task `webkit-sim-target-lost`): the proxy and the socket are up, the tab is listed, the page target is gone -/

/-- The wait for the page target before a relaunch: 480 s, `FW_WK_TIMEOUT_SCALE` 8 times `reconnect`'s 60000 ms. -/
def targetWaitMs : Nat := 480000

/-- The wait for the page target after the relaunch: the relaunch has just connected once, so the tab wait and the connect bound. -/
def targetAfterMs : Nat := tabMs + connectMs

/-- Exit code of a session that lost its page target for good (4 is a dead inspector, 3 the stall watchdog). -/
def targetLostExit : Nat := 5

/-- What the session does at one poll of the page-target wait. -/
inductive TargetAction where
  | connect
  | wait
  | relaunch
  | failSession
deriving DecidableEq, Repr

/-- The action's wire name. -/
def TargetAction.name : TargetAction → String
  | .connect => "connect"
  | .wait => "wait"
  | .relaunch => "relaunch"
  | .failSession => "failSession"

/-- The wait bound of a stretch: before the relaunch `targetWaitMs`, after it `targetAfterMs`. -/
def targetLimit (relaunched : Bool) : Nat := if relaunched then targetAfterMs else targetWaitMs

/-- The action at a poll `elapsedMs` into the stretch: connect to a found target, wait while inside the bound, past it relaunch
once, then fail the session. -/
def targetAction (relaunched : Bool) (elapsedMs : Nat) (found : Bool) : TargetAction :=
  if found then .connect
  else if elapsedMs < targetLimit relaunched then .wait
  else if relaunched then .failSession else .relaunch

/-- The action after the relaunch: a working one goes back to the wait, a failed one fails the session. -/
def targetAfterRelaunch (ok : Bool) : TargetAction := if ok then .wait else .failSession

/-- The longest time one poll of the wait may take: what is left of the bound. -/
def targetCapMs (relaunched : Bool) (elapsedMs : Nat) : Nat := targetLimit relaunched - elapsedMs

/-- From the start of the page-target wait to the exit: first wait, relaunch, second wait, exit (the timed-out command, the close and the proxy check before the wait are not counted). -/
def targetEndMs : Nat := targetWaitMs + relaunchMs + targetAfterMs + exitMs

/-- The cells of a matrix that still run after `failed` failed its session. -/
def cellsAfter (cells : List String) (failed : String) : List String := cells.filter (· != failed)

#guard targetAction false 0 false == .wait && targetAction false 480000 false == .relaunch
#guard targetAction true 90000 false == .failSession && targetEndMs == 930000

/-- **A found target connects.** Whatever the clock and the relaunch. -/
theorem target_found_connects (r : Bool) (e : Nat) : targetAction r e true = .connect := by
  simp [targetAction]

/-- **Inside the bound the wait goes on.** -/
theorem target_waits_inside (r : Bool) (e : Nat) (h : e < targetLimit r) : targetAction r e false = .wait := by
  simp [targetAction, h]

/-- **Past the bound, before any relaunch, Safari is relaunched.** -/
theorem target_relaunches_once (e : Nat) (h : targetWaitMs ≤ e) : targetAction false e false = .relaunch := by
  have : ¬ e < targetLimit false := by simp [targetLimit]; omega
  simp [targetAction, this]

/-- **Past the bound after the relaunch, the session fails.** -/
theorem target_fails_after_relaunch (e : Nat) (h : targetAfterMs ≤ e) : targetAction true e false = .failSession := by
  have : ¬ e < targetLimit true := by simp [targetLimit]; omega
  simp [targetAction, this]

/-- **Safari is relaunched only before a relaunch.** -/
theorem target_relaunch_not_relaunched {r : Bool} {e : Nat} {f : Bool} (h : targetAction r e f = .relaunch) : r = false := by
  cases r
  · rfl
  · exfalso
    unfold targetAction at h
    by_cases hf : f = true <;> by_cases he : e < targetLimit true <;> simp [hf, he] at h

/-- **A session ends only after the bound.** A failed session needs a relaunch before it and the second bound used up. -/
theorem target_fail_needs_bound {r : Bool} {e : Nat} {f : Bool} (h : targetAction r e f = .failSession) :
    r = true ∧ targetAfterMs ≤ e := by
  unfold targetAction at h
  by_cases hf : f = true
  · simp [hf] at h
  · by_cases he : e < targetLimit r
    · simp [hf, he] at h
    · cases r
      · simp [hf, he] at h
      · simp [targetLimit] at he
        exact ⟨rfl, he⟩

/-- **The first bound is 480 s.** -/
theorem target_first_bound : targetLimit false = 480000 := by decide

/-- **A poll capped at the rest of the bound ends within it.** A poll started inside the bound (the wait branch) and given
`targetCapMs` finishes by the bound, so one blocked poll cannot hold the wait past it (the 876 s of 480 s of the lost runs). -/
theorem target_cap_fits (r : Bool) (e : Nat) (h : e < targetLimit r) : e + targetCapMs r e ≤ targetLimit r := by
  unfold targetCapMs; omega

/-- **A wait of any length reaches a final action.** Once the clock passes the bound, a missing target never waits again. -/
theorem target_never_waits_past (r : Bool) (e : Nat) (h : targetLimit r ≤ e) : targetAction r e false ≠ .wait := by
  have : ¬ e < targetLimit r := by omega
  cases r <;> simp [targetAction, this]

/-- **A working relaunch goes back to the wait, a failed one fails the session.** -/
theorem target_after_relaunch (ok : Bool) :
    (ok = true → targetAfterRelaunch ok = .wait) ∧ (ok = false → targetAfterRelaunch ok = .failSession) := by
  cases ok <;> simp [targetAfterRelaunch]

/-- **The lost-target exit is its own code.** Not the dead inspector's, the watchdog's or an ordinary failure's. -/
theorem target_exit_distinct : targetLostExit ≠ deadExit ∧ targetLostExit ≠ 3 ∧ targetLostExit ≠ 1 := by decide

/-- **From the start of the page-target wait to the exit: first wait, relaunch, second wait, exit (the timed-out command, the close and the proxy check before the wait are not counted). It takes at most `targetEndMs`, under the 38-minute job cap of the lag cells.** -/
theorem target_end_bound : targetEndMs = 930000 ∧ targetEndMs < 38 * 60 * 1000 := by decide

/-- **A failed session fails no other cell.** Every other cell of the matrix still runs. The workflow side is strategy.fail-fast: false (.github/workflows/webkit-sim.yml:273); this theorem covers only the cell list. -/
theorem siblings_unaffected (cells : List String) (failed c : String) (hc : c ∈ cells) (hne : c ≠ failed) :
    c ∈ cellsAfter cells failed := by
  simp [cellsAfter, hc, hne]

/-- **The failed cell is the only one left out.** -/
theorem cellsAfter_sub (cells : List String) (failed : String) : ∀ c ∈ cellsAfter cells failed, c ∈ cells ∧ c ≠ failed := by
  intro c hc
  simp [cellsAfter] at hc
  exact hc

end Fw.Measure.SimBound
