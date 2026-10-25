import Lean.Data.Json
import Fw.Measure.Retry
import Fw.Measure.SimBound
/-!
# Simulator recovery: bounded simctl calls, Safari relaunch, one device reboot per pass
Twin: `packages/measure-webkit/src/guard.mjs`; golden `packages/contracts/golden/device/sim-relaunch.jsonl`.
-/
namespace Fw.Device.SimRelaunch
open Lean

def callTries (_ : Unit := ()) : Nat := 2

def callGapS (_ : Unit := ()) : Nat := Fw.Measure.Retry.wait 1 / 1000

def callWorstS (limitS : Nat) : Nat := callTries * limitS + (callTries - 1) * callGapS

def stateCallS (_ : Unit := ()) : Nat := 30

def listCallS (_ : Unit := ()) : Nat := 90

def shutdownCallS (_ : Unit := ()) : Nat := 40

def bootCallS (_ : Unit := ()) : Nat := 60

def bootstatusCallS (_ : Unit := ()) : Nat := 120

def detectS (_ : Unit := ()) : Nat := Fw.Measure.SimBound.detectMs / 1000 + callWorstS stateCallS

def relaunchS (_ : Unit := ()) : Nat := Fw.Measure.SimBound.relaunchMs / 1000

def rebootS (_ : Unit := ()) : Nat :=
  callWorstS shutdownCallS + callWorstS bootCallS + callWorstS bootstatusCallS + relaunchS

def healthySessionMaxS (_ : Unit := ()) : Nat := 31 * 60 + 6

def sessionLimitS (_ : Unit := ()) : Nat := Fw.Measure.SimBound.perSessionMin * 60

def recoverMin (_ : Unit := ()) : Nat := (rebootS + 59) / 60

theorem callGapS_eq : callGapS = 2 := by decide

theorem relaunchS_eq : relaunchS = 320 := by decide

theorem rebootS_eq : rebootS = 766 := by decide

theorem reboot_exceeds_spare : sessionLimitS - healthySessionMaxS < rebootS := by decide

theorem step_with_recovery_fits : healthySessionMaxS + rebootS ≤ (Fw.Measure.SimBound.perSessionMin + recoverMin) * 60 := by
  decide

/-! ## One simctl call -/

inductive CallEv | answers | transient | permanent
  deriving DecidableEq, Repr

def CallEv.name : CallEv → String
  | .answers => "answers"
  | .transient => "transient"
  | .permanent => "permanent"

inductive CallFail | exhausted | refused
  deriving DecidableEq, Repr

def CallFail.name : CallFail → String
  | .exhausted => "exhausted"
  | .refused => "refused"

inductive CallPhase | trying (n : Nat) | done | failed (f : CallFail)
  deriving DecidableEq, Repr

def callInit : CallPhase := .trying 1

def callTerminal : CallPhase → Bool
  | .trying _ => false
  | _ => true

def callStep : CallPhase → CallEv → CallPhase
  | .trying _, .answers => .done
  | .trying n, .transient => if n < callTries then .trying (n + 1) else .failed .exhausted
  | .trying _, .permanent => .failed .refused
  | .done, _ => .done
  | .failed f, _ => .failed f

def callExec (p : CallPhase) : List CallEv → CallPhase
  | [] => p
  | e :: es => callExec (callStep p e) es

def callUsed (p : CallPhase) : List CallEv → Nat
  | [] => 0
  | e :: es => if callTerminal p then 0 else 1 + callUsed (callStep p e) es

theorem call_answers (n : Nat) : callStep (.trying n) .answers = .done := rfl

theorem call_transient_retries (n : Nat) (h : n < callTries) : callStep (.trying n) .transient = .trying (n + 1) := by
  simp [callStep, h]

theorem call_transient_exhausted (n : Nat) (h : callTries ≤ n) : callStep (.trying n) .transient = .failed .exhausted := by
  simp [callStep, Nat.not_lt.mpr h]

theorem call_permanent_refused (n : Nat) : callStep (.trying n) .permanent = .failed .refused := rfl

theorem call_retry_is_policy (n : Nat) :
    callStep (.trying n) .transient = .trying (n + 1) ↔ Fw.Measure.Retry.shouldRetry .transient n callTries = true := by
  simp only [callStep, Fw.Measure.Retry.shouldRetry]
  by_cases h : n < callTries <;> simp [h]

theorem call_terminal_stays (p : CallPhase) (h : callTerminal p = true) (e : CallEv) : callStep p e = p := by
  cases p <;> simp_all [callTerminal, callStep]

theorem call_exec_terminal (p : CallPhase) (h : callTerminal p = true) (es : List CallEv) : callExec p es = p := by
  induction es with
  | nil => rfl
  | cons e es ih => simp [callExec, call_terminal_stays p h, ih]

def CallInv : CallPhase → Prop
  | .trying n => 1 ≤ n ∧ n ≤ callTries
  | _ => True

theorem callInv_step {p : CallPhase} (h : CallInv p) (e : CallEv) : CallInv (callStep p e) := by
  cases p with
  | trying n =>
    obtain ⟨h1, h2⟩ := h
    cases e
    · simp [callStep, CallInv]
    · by_cases hl : n < callTries
      · rw [call_transient_retries n hl]; exact ⟨by omega, by omega⟩
      · rw [call_transient_exhausted n (by omega)]; simp [CallInv]
    · simp [callStep, CallInv]
  | done => cases e <;> simp [callStep, CallInv]
  | failed f => cases e <;> simp [callStep, CallInv]

theorem callInv_exec {p : CallPhase} (h : CallInv p) (es : List CallEv) : CallInv (callExec p es) := by
  induction es generalizing p with
  | nil => exact h
  | cons e es ih => exact ih (callInv_step h e)

def callRank : CallPhase → Nat
  | .trying n => callTries + 1 - n
  | _ => 0

theorem callRank_step {p : CallPhase} (h : CallInv p) (hn : callTerminal p = false) (e : CallEv) :
    callRank (callStep p e) < callRank p := by
  cases p with
  | trying n =>
    obtain ⟨h1, h2⟩ := h
    cases e
    · simp only [callStep, callRank]; omega
    · by_cases hl : n < callTries
      · rw [call_transient_retries n hl]; simp only [callRank]; omega
      · rw [call_transient_exhausted n (by omega)]; simp only [callRank]; omega
    · simp only [callStep, callRank]; omega
  | done => simp [callTerminal] at hn
  | failed f => simp [callTerminal] at hn

theorem call_ends_in_two (es : List CallEv) (h : callTries ≤ es.length) : callTerminal (callExec callInit es) = true := by
  have key : ∀ (p : CallPhase), CallInv p → ∀ es : List CallEv, callRank p ≤ es.length → callTerminal (callExec p es) = true := by
    intro p hp es
    induction es generalizing p with
    | nil =>
      intro hl
      cases p with
      | trying n => obtain ⟨h1, h2⟩ := hp; simp only [callRank, List.length_nil] at hl; exfalso; omega
      | done => rfl
      | failed f => rfl
    | cons e es ih =>
      intro hl
      by_cases ht : callTerminal p = true
      · rw [call_exec_terminal p ht]; exact ht
      · have hn : callTerminal p = false := by simpa using ht
        have := callRank_step hp hn e
        exact ih (callStep p e) (callInv_step hp e) (by simp only [List.length_cons] at hl; omega)
  exact key callInit ⟨Nat.le_refl 1, by decide⟩ es (by show callTries + 1 - 1 ≤ es.length; omega)

def callAttemptsOf : CallPhase → Nat
  | .trying n => n
  | _ => 0

theorem call_tries_le (es : List CallEv) : callAttemptsOf (callExec callInit es) ≤ callTries := by
  have := callInv_exec (p := callInit) (by simp [CallInv, callInit, callTries]) es
  generalize callExec callInit es = q at this
  cases q <;> simp_all [callAttemptsOf, CallInv]

theorem call_worst_two_limits (limitS : Nat) : callWorstS limitS = 2 * limitS + 2 := by
  simp [callWorstS, callTries, callGapS_eq]

/-! ## One pass -/

inductive Ev | passOk | deadUp | deadDown | relaunchOk | relaunchFail | rebootOk | rebootFail
  deriving DecidableEq, Repr

def Ev.name : Ev → String
  | .passOk => "passOk"
  | .deadUp => "deadUp"
  | .deadDown => "deadDown"
  | .relaunchOk => "relaunchOk"
  | .relaunchFail => "relaunchFail"
  | .rebootOk => "rebootOk"
  | .rebootFail => "rebootFail"

inductive Fail | deadAgain | relaunchFailed | rebootFailed | protocol
  deriving DecidableEq, Repr

def Fail.name : Fail → String
  | .deadAgain => "deadAgain"
  | .relaunchFailed => "relaunchFailed"
  | .rebootFailed => "rebootFailed"
  | .protocol => "protocol"

inductive Phase | running | relaunching | rebooting | done | failed (f : Fail)
  deriving DecidableEq, Repr

structure St where
  phase : Phase
  attempt : Nat
  relaunches : Nat
  reboots : Nat
  deriving DecidableEq, Repr

def init : St := ⟨.running, 1, 0, 0⟩

def terminal (s : St) : Bool :=
  match s.phase with
  | .done => true
  | .failed _ => true
  | _ => false

def step (s : St) (e : Ev) : St :=
  match s.phase, e with
  | .running, .passOk => ⟨.done, s.attempt, s.relaunches, s.reboots⟩
  | .running, .deadUp =>
    if s.relaunches = 0 then ⟨.relaunching, s.attempt, 1, s.reboots⟩
    else if s.reboots = 0 then ⟨.rebooting, s.attempt, s.relaunches, 1⟩
    else ⟨.failed .deadAgain, s.attempt, s.relaunches, s.reboots⟩
  | .running, .deadDown =>
    if s.reboots = 0 then ⟨.rebooting, s.attempt, s.relaunches, 1⟩
    else ⟨.failed .deadAgain, s.attempt, s.relaunches, s.reboots⟩
  | .relaunching, .relaunchOk => ⟨.running, s.attempt + 1, s.relaunches, s.reboots⟩
  | .relaunching, .relaunchFail =>
    if s.reboots = 0 then ⟨.rebooting, s.attempt, s.relaunches, 1⟩
    else ⟨.failed .relaunchFailed, s.attempt, s.relaunches, s.reboots⟩
  | .rebooting, .rebootOk => ⟨.running, s.attempt + 1, s.relaunches, s.reboots⟩
  | .rebooting, .rebootFail => ⟨.failed .rebootFailed, s.attempt, s.relaunches, s.reboots⟩
  | .done, _ => s
  | .failed _, _ => s
  | _, _ => ⟨.failed .protocol, s.attempt, s.relaunches, s.reboots⟩

def exec (s : St) : List Ev → St
  | [] => s
  | e :: es => exec (step s e) es

def used (s : St) : List Ev → Nat
  | [] => 0
  | e :: es => if terminal s then 0 else 1 + used (step s e) es

theorem step_pass_ok (s : St) (h : s.phase = .running) : step s .passOk = ⟨.done, s.attempt, s.relaunches, s.reboots⟩ := by
  simp [step, h]

theorem step_dead_up_relaunch (s : St) (h : s.phase = .running) (r : s.relaunches = 0) :
    step s .deadUp = ⟨.relaunching, s.attempt, 1, s.reboots⟩ := by
  simp [step, h, r]

theorem step_dead_up_reboot (s : St) (h : s.phase = .running) (r : s.relaunches ≠ 0) (b : s.reboots = 0) :
    step s .deadUp = ⟨.rebooting, s.attempt, s.relaunches, 1⟩ := by
  simp [step, h, r, b]

theorem step_dead_up_again (s : St) (h : s.phase = .running) (r : s.relaunches ≠ 0) (b : s.reboots ≠ 0) :
    step s .deadUp = ⟨.failed .deadAgain, s.attempt, s.relaunches, s.reboots⟩ := by
  simp [step, h, r, b]

theorem step_dead_down_reboot (s : St) (h : s.phase = .running) (b : s.reboots = 0) :
    step s .deadDown = ⟨.rebooting, s.attempt, s.relaunches, 1⟩ := by
  simp [step, h, b]

theorem step_dead_down_again (s : St) (h : s.phase = .running) (b : s.reboots ≠ 0) :
    step s .deadDown = ⟨.failed .deadAgain, s.attempt, s.relaunches, s.reboots⟩ := by
  simp [step, h, b]

theorem step_relaunch_ok (s : St) (h : s.phase = .relaunching) :
    step s .relaunchOk = ⟨.running, s.attempt + 1, s.relaunches, s.reboots⟩ := by
  simp [step, h]

theorem step_relaunch_fail_reboot (s : St) (h : s.phase = .relaunching) (b : s.reboots = 0) :
    step s .relaunchFail = ⟨.rebooting, s.attempt, s.relaunches, 1⟩ := by
  simp [step, h, b]

theorem step_relaunch_fail_named (s : St) (h : s.phase = .relaunching) (b : s.reboots ≠ 0) :
    step s .relaunchFail = ⟨.failed .relaunchFailed, s.attempt, s.relaunches, s.reboots⟩ := by
  simp [step, h, b]

theorem step_reboot_ok (s : St) (h : s.phase = .rebooting) :
    step s .rebootOk = ⟨.running, s.attempt + 1, s.relaunches, s.reboots⟩ := by
  simp [step, h]

theorem step_reboot_fail (s : St) (h : s.phase = .rebooting) :
    step s .rebootFail = ⟨.failed .rebootFailed, s.attempt, s.relaunches, s.reboots⟩ := by
  simp [step, h]

theorem step_terminal (s : St) (h : terminal s = true) (e : Ev) : step s e = s := by
  obtain ⟨p, a, r, b⟩ := s
  cases p <;> simp [terminal] at h <;> simp [step]

theorem exec_terminal (s : St) (h : terminal s = true) (es : List Ev) : exec s es = s := by
  induction es with
  | nil => rfl
  | cons e es ih => simp [exec, step_terminal s h, ih]

theorem step_protocol_running (s : St) (h : s.phase = .running) (e : Ev)
    (he : e ≠ .passOk ∧ e ≠ .deadUp ∧ e ≠ .deadDown) : (step s e).phase = .failed .protocol := by
  obtain ⟨p, a, r, b⟩ := s
  simp at h; subst h
  cases e <;> simp_all [step]

theorem step_protocol_relaunching (s : St) (h : s.phase = .relaunching) (e : Ev)
    (he : e ≠ .relaunchOk ∧ e ≠ .relaunchFail) : (step s e).phase = .failed .protocol := by
  obtain ⟨p, a, r, b⟩ := s
  simp at h; subst h
  cases e <;> simp_all [step]

theorem step_protocol_rebooting (s : St) (h : s.phase = .rebooting) (e : Ev)
    (he : e ≠ .rebootOk ∧ e ≠ .rebootFail) : (step s e).phase = .failed .protocol := by
  obtain ⟨p, a, r, b⟩ := s
  simp at h; subst h
  cases e <;> simp_all [step]

def Inv (s : St) : Prop :=
  s.relaunches ≤ 1 ∧ s.reboots ≤ 1 ∧ 1 ≤ s.attempt ∧ s.attempt ≤ s.relaunches + s.reboots + 1 ∧
  (s.phase = .relaunching → s.relaunches = 1 ∧ s.attempt ≤ s.relaunches + s.reboots) ∧
  (s.phase = .rebooting → s.reboots = 1 ∧ s.attempt ≤ s.relaunches + s.reboots)

theorem inv_init : Inv init := by simp [Inv, init]

theorem inv_step {s : St} (h : Inv s) (e : Ev) : Inv (step s e) := by
  obtain ⟨p, a, r, b⟩ := s
  obtain ⟨h1, h2, h3, h4, h5, h6⟩ := h
  simp only at h1 h2 h3 h4 h5 h6
  cases p <;> cases e <;> by_cases hr : r = 0 <;> by_cases hb : b = 0 <;> simp_all [step, Inv] <;> omega

theorem inv_exec {s : St} (h : Inv s) (es : List Ev) : Inv (exec s es) := by
  induction es generalizing s with
  | nil => exact h
  | cons e es ih => exact ih (inv_step h e)

theorem reboots_le_one (es : List Ev) : (exec init es).reboots ≤ 1 := (inv_exec inv_init es).2.1

theorem relaunches_le_one (es : List Ev) : (exec init es).relaunches ≤ 1 := (inv_exec inv_init es).1

theorem attempt_le_three (es : List Ev) : (exec init es).attempt ≤ 3 := by
  obtain ⟨h1, h2, _, h4, _⟩ := inv_exec inv_init es
  omega

theorem reboot_started_once {s : St} (h : Inv s) (e : Ev) (hn : (step s e).phase = .rebooting) (hs : s.phase ≠ .rebooting) :
    s.reboots = 0 ∧ (step s e).reboots = 1 := by
  obtain ⟨p, a, r, b⟩ := s
  obtain ⟨h1, h2, h3, h4, h5, h6⟩ := h
  simp only at h1 h2 h3 h4 h5 h6 hs
  cases p <;> cases e <;> by_cases hr : r = 0 <;> by_cases hb : b = 0 <;> simp_all [step]

theorem retry_after_answer (s : St) (e : Ev) (h : (step s e).attempt = s.attempt + 1) :
    (s.phase = .relaunching ∧ e = .relaunchOk) ∨ (s.phase = .rebooting ∧ e = .rebootOk) := by
  obtain ⟨p, a, r, b⟩ := s
  cases p <;> cases e <;> by_cases hr : r = 0 <;> by_cases hb : b = 0 <;> simp_all [step]

theorem running_after_answer (s : St) (e : Ev) (h : (step s e).phase = .running) (hs : s.phase ≠ .running) :
    (s.phase = .relaunching ∧ e = .relaunchOk) ∨ (s.phase = .rebooting ∧ e = .rebootOk) := by
  obtain ⟨p, a, r, b⟩ := s
  cases p <;> cases e <;> by_cases hr : r = 0 <;> by_cases hb : b = 0 <;> simp_all [step]

theorem done_after_pass (s : St) (e : Ev) (h : (step s e).phase = .done) (hs : s.phase ≠ .done) :
    s.phase = .running ∧ e = .passOk := by
  obtain ⟨p, a, r, b⟩ := s
  cases p <;> cases e <;> by_cases hr : r = 0 <;> by_cases hb : b = 0 <;> simp_all [step]

def rank (s : St) : Nat :=
  match s.phase with
  | .running => 1 + 2 * (1 - s.relaunches) + 2 * (1 - s.reboots)
  | .relaunching => 2 + 2 * (1 - s.reboots)
  | .rebooting => 2 + 2 * (1 - s.relaunches)
  | _ => 0

def passEvents (_ : Unit := ()) : Nat := 5

theorem rank_init : rank init = passEvents := rfl

theorem rank_step {s : St} (h : Inv s) (hn : terminal s = false) (e : Ev) : rank (step s e) < rank s := by
  obtain ⟨p, a, r, b⟩ := s
  obtain ⟨h1, h2, h3, h4, h5, h6⟩ := h
  simp only at h1 h2 h3 h4 h5 h6
  cases p <;> cases e <;> by_cases hr : r = 0 <;> by_cases hb : b = 0 <;> simp_all [step, rank, terminal] <;> omega

theorem rank_zero_terminal {s : St} (h : rank s = 0) : terminal s = true := by
  obtain ⟨p, a, r, b⟩ := s
  cases p <;> simp_all [rank, terminal] <;> omega

theorem exec_terminal_of_rank {s : St} (h : Inv s) :
    ∀ es : List Ev, rank s ≤ es.length → terminal (exec s es) = true := by
  intro es
  induction es generalizing s with
  | nil => intro hl; exact rank_zero_terminal (Nat.le_zero.mp hl)
  | cons e es ih =>
    intro hl
    by_cases ht : terminal s = true
    · rw [exec_terminal s ht]; exact ht
    · have hn : terminal s = false := by simpa using ht
      have := rank_step h hn e
      exact ih (inv_step h e) (by simp at hl; omega)

theorem pass_ends (es : List Ev) (h : passEvents ≤ es.length) : terminal (exec init es) = true :=
  exec_terminal_of_rank inv_init es (by rw [rank_init]; exact h)

theorem pass_ends_named (es : List Ev) (h : passEvents ≤ es.length) :
    (exec init es).phase = .done ∨ ∃ f, (exec init es).phase = .failed f := by
  have := pass_ends es h
  generalize exec init es = s at this
  obtain ⟨p, a, r, b⟩ := s
  cases p <;> simp_all [terminal]

/-! ## Seconds -/

def cost (s : St) (e : Ev) : Nat :=
  match s.phase, e with
  | .running, .deadUp => detectS
  | .running, .deadDown => detectS
  | .relaunching, .relaunchOk => relaunchS
  | .relaunching, .relaunchFail => relaunchS
  | .rebooting, .rebootOk => rebootS
  | .rebooting, .rebootFail => rebootS
  | _, _ => 0

def boundS (s : St) : Nat :=
  match s.phase with
  | .running => detectS * (1 + (1 - s.relaunches) + (1 - s.reboots)) + relaunchS * (1 - s.relaunches) + rebootS * (1 - s.reboots)
  | .relaunching => relaunchS + detectS * (1 + (1 - s.reboots)) + rebootS * (1 - s.reboots)
  | .rebooting => rebootS + detectS * (1 + (1 - s.relaunches)) + relaunchS * (1 - s.relaunches)
  | _ => 0

def timeUsed (s : St) : List Ev → Nat
  | [] => 0
  | e :: es => if terminal s then 0 else cost s e + timeUsed (step s e) es

def recoverWorstS (_ : Unit := ()) : Nat := boundS init

theorem recoverWorstS_eq : recoverWorstS = 1527 := by decide

theorem cost_step {s : St} (h : Inv s) (hn : terminal s = false) (e : Ev) : cost s e + boundS (step s e) ≤ boundS s := by
  obtain ⟨p, a, r, b⟩ := s
  obtain ⟨h1, h2, h3, h4, h5, h6⟩ := h
  simp only at h1 h2 h3 h4 h5 h6
  have hd : detectS = 147 := by decide
  have hl : relaunchS = 320 := relaunchS_eq
  have hb' : rebootS = 766 := rebootS_eq
  cases p <;> cases e <;> by_cases hr : r = 0 <;> by_cases hb : b = 0 <;>
    simp_all [step, cost, boundS, terminal] <;> omega

theorem time_used_le {s : St} (h : Inv s) : ∀ es : List Ev, timeUsed s es ≤ boundS s := by
  intro es
  induction es generalizing s with
  | nil => simp [timeUsed]
  | cons e es ih =>
    by_cases ht : terminal s = true
    · simp [timeUsed, ht]
    · have hn : terminal s = false := by simpa using ht
      have := cost_step h hn e
      have := ih (inv_step h e)
      simp [timeUsed, ht]
      omega

theorem pass_time_le (es : List Ev) : timeUsed init es ≤ recoverWorstS := time_used_le inv_init es

/-! ## Golden -/

private def evsOf (l : List Ev) : Json := Json.arr (l.map fun e => Json.str e.name).toArray

private def callEvsOf (l : List CallEv) : Json := Json.arr (l.map fun e => Json.str e.name).toArray

private def phaseJ : Phase → Json
  | .running => "running"
  | .relaunching => "relaunching"
  | .rebooting => "rebooting"
  | .done => "done"
  | .failed f => Json.str s!"failed:{f.name}"

private def callPhaseJ : CallPhase → Json
  | .trying n => Json.str s!"trying:{n}"
  | .done => "done"
  | .failed f => Json.str s!"failed:{f.name}"

private def callCases : List (String × List CallEv) :=
  [("answers at once", [.answers]),
   ("one transient then answers", [.transient, .answers]),
   ("transient twice", [.transient, .transient]),
   ("permanent", [.permanent]),
   ("transient then permanent", [.transient, .permanent]),
   ("events after done", [.answers, .transient]),
   ("events after failure", [.permanent, .answers]),
   ("transient then stops", [.transient]),
   ("no events", [])]

private def execCases : List (String × List Ev) :=
  [("clean", [.passOk]),
   ("safari relaunch recovers", [.deadUp, .relaunchOk, .passOk]),
   ("device down: reboot recovers", [.deadDown, .rebootOk, .passOk]),
   ("relaunch fails, reboot recovers", [.deadUp, .relaunchFail, .rebootOk, .passOk]),
   ("relaunch ok, dead again, reboot recovers", [.deadUp, .relaunchOk, .deadUp, .rebootOk, .passOk]),
   ("relaunch ok, device down, reboot recovers", [.deadUp, .relaunchOk, .deadDown, .rebootOk, .passOk]),
   ("reboot first, then dead with device up", [.deadDown, .rebootOk, .deadUp, .relaunchOk, .passOk]),
   ("dead after relaunch and reboot", [.deadUp, .relaunchOk, .deadUp, .rebootOk, .deadUp]),
   ("dead after reboot and relaunch", [.deadDown, .rebootOk, .deadUp, .relaunchOk, .deadUp]),
   ("device down after reboot", [.deadDown, .rebootOk, .deadDown]),
   ("reboot fails", [.deadDown, .rebootFail]),
   ("relaunch fails, reboot fails", [.deadUp, .relaunchFail, .rebootFail]),
   ("relaunch ok, relaunch-path reboot fails", [.deadUp, .relaunchOk, .deadUp, .rebootFail]),
   ("relaunch fails after reboot", [.deadDown, .rebootOk, .deadUp, .relaunchFail]),
   ("pass ends after a relaunch", [.deadUp, .relaunchOk, .passOk, .deadUp]),
   ("relaunch answer while running", [.relaunchOk]),
   ("pass ok while relaunching", [.deadUp, .passOk]),
   ("reboot answer while relaunching", [.deadUp, .rebootOk]),
   ("dead while rebooting", [.deadDown, .deadUp]),
   ("events after done", [.passOk, .deadUp, .deadDown]),
   ("events after failure", [.deadDown, .rebootFail, .rebootOk]),
   ("stops while relaunching", [.deadUp]),
   ("stops while rebooting", [.deadDown]),
   ("no events", [])]

private def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("callTries", callTries), ("callGapS", callGapS), ("stateCallS", stateCallS),
    ("listCallS", listCallS), ("shutdownCallS", shutdownCallS), ("bootCallS", bootCallS), ("bootstatusCallS", bootstatusCallS),
    ("detectS", detectS), ("relaunchS", relaunchS), ("rebootS", rebootS), ("recoverWorstS", recoverWorstS),
    ("recoverMin", recoverMin), ("healthySessionMaxS", healthySessionMaxS), ("sessionLimitS", sessionLimitS),
    ("passEvents", passEvents)]).compress] ++
  ([stateCallS, listCallS, shutdownCallS, bootCallS, bootstatusCallS].map fun (l : Nat) =>
    (Json.mkObj [("kind", "callWorst"), ("limitS", l), ("worstS", callWorstS l)]).compress) ++
  (callCases.map fun (name, evs) =>
    let p := callExec callInit evs
    (Json.mkObj [("kind", "call"), ("name", name), ("events", callEvsOf evs), ("phase", callPhaseJ p),
      ("terminal", callTerminal p), ("used", callUsed callInit evs)]).compress) ++
  (execCases.map fun (name, evs) =>
    let s := exec init evs
    (Json.mkObj [("kind", "exec"), ("name", name), ("events", evsOf evs), ("phase", phaseJ s.phase), ("attempt", s.attempt),
      ("relaunches", s.relaunches), ("reboots", s.reboots), ("terminal", terminal s), ("used", used init evs),
      ("timeS", timeUsed init evs)]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

/-- Print the golden, or with `--check <file>` compare its bytes; exit 1 when they differ. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"device-sim-relaunch golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"device-sim-relaunch golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Device.SimRelaunch
