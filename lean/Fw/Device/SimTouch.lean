import Lean.Data.Json
/-!
# Simulator touch pass guard: readiness, stall verdict, one restart
Twin: `packages/measure-webkit/src/throttle/driver.mjs`; golden `packages/contracts/golden/device/sim-touch.jsonl`.
-/
namespace Fw.Device.SimTouch
open Lean

def probeTries (_ : Unit := ()) : Nat := 6

def probeGapS (_ : Unit := ()) : Nat := 10

def probeBudgetS (_ : Unit := ()) : Nat := probeTries * probeGapS

def startS (_ : Unit := ()) : Nat := 300

def gapS (_ : Unit := ()) : Nat := 120

def capBaseS (_ : Unit := ()) : Nat := 300

def capPressS (_ : Unit := ()) : Nat := 45

def pollS (_ : Unit := ()) : Nat := 5

def restartS (_ : Unit := ()) : Nat := 600

def stepLimitS (_ : Unit := ()) : Nat := 90 * 60

def typicalPassS (_ : Unit := ()) : Nat := 420

inductive Mode | drags | finish
  deriving DecidableEq, Repr

def Mode.name : Mode → String
  | .drags => "drags"
  | .finish => "finish"

def presses (m : Mode) (cycles : Nat) : Nat :=
  match m with
  | .drags => 2 * cycles
  | .finish => 3 * cycles

def capS (n : Nat) : Nat := capBaseS + n * capPressS

inductive Stall | ok | startup | press | cap
  deriving DecidableEq, Repr

def Stall.name : Stall → String
  | .ok => "ok"
  | .startup => "startup"
  | .press => "press"
  | .cap => "cap"

def stall (n elapsed marks since : Nat) : Stall :=
  if capS n ≤ elapsed then .cap
  else if marks = 0 then (if startS ≤ elapsed then .startup else .ok)
  else if n + 1 ≤ marks then .ok
  else if gapS ≤ since then .press else .ok

theorem stall_cap {n elapsed marks since : Nat} (h : capS n ≤ elapsed) : stall n elapsed marks since = .cap := by
  simp [stall, h]

theorem stall_startup {n elapsed since : Nat} (hc : elapsed < capS n) (h : startS ≤ elapsed) :
    stall n elapsed 0 since = .startup := by
  simp [stall, Nat.not_le.mpr hc, h]

theorem stall_press {n elapsed marks since : Nat} (hc : elapsed < capS n) (hm : 0 < marks) (hn : marks < n + 1)
    (h : gapS ≤ since) : stall n elapsed marks since = .press := by
  have : marks ≠ 0 := Nat.pos_iff_ne_zero.mp hm
  simp [stall, Nat.not_le.mpr hc, this, Nat.not_le.mpr hn, h]

theorem stall_ok_early {n elapsed since : Nat} (hs : elapsed < startS) (hc : elapsed < capS n) :
    stall n elapsed 0 since = .ok := by
  simp [stall, Nat.not_le.mpr hc, Nat.not_le.mpr hs]

theorem stall_ok_moving {n elapsed marks since : Nat} (hc : elapsed < capS n) (hm : 0 < marks) (h : since < gapS) :
    stall n elapsed marks since = .ok := by
  have : marks ≠ 0 := Nat.pos_iff_ne_zero.mp hm
  simp only [stall, Nat.not_le.mpr hc, this, Nat.not_le.mpr h]
  simp

theorem stall_ok_done {n elapsed marks since : Nat} (hc : elapsed < capS n) (hm : n + 1 ≤ marks) :
    stall n elapsed marks since = .ok := by
  have : marks ≠ 0 := by omega
  simp [stall, Nat.not_le.mpr hc, this, hm]

theorem startS_lt_capS {n : Nat} (h : 0 < n) : startS < capS n := by
  simp only [startS, capS, capBaseS, capPressS]
  omega

theorem stall_ne_ok_of_cap {n elapsed marks since : Nat} (h : capS n ≤ elapsed) : stall n elapsed marks since ≠ .ok := by
  rw [stall_cap h]; simp

def samples : List (Nat × Mode × Nat) :=
  [(4, .drags, 252), (4, .finish, 269), (4, .finish, 277), (1, .drags, 145), (1, .drags, 220)]

theorem cap_covers_samples : samples.all (fun (c, m, s) => decide (s < capS (presses m c))) = true := by decide

theorem cap_twice_covers_passes : [(4, Mode.drags, 252), (4, Mode.finish, 269), (4, Mode.finish, 277)].all
    (fun (c, m, s) => decide (2 * s ≤ capS (presses m c))) = true := by decide

theorem startS_covers_warm : 220 < startS := by decide

def ready (sim page driver : Bool) : Bool := sim && page && driver

theorem ready_all : ready true true true = true := rfl

theorem not_ready_sim (page driver : Bool) : ready false page driver = false := rfl

theorem not_ready_page (sim driver : Bool) : ready sim false driver = false := by simp [ready]

theorem not_ready_driver (sim page : Bool) : ready sim page false = false := by simp [ready]

inductive Ev | readyYes | readyNo | touchesOk | touchesFail | restartOk | restartFail
  deriving DecidableEq, Repr

def Ev.name : Ev → String
  | .readyYes => "readyYes"
  | .readyNo => "readyNo"
  | .touchesOk => "touchesOk"
  | .touchesFail => "touchesFail"
  | .restartOk => "restartOk"
  | .restartFail => "restartFail"

inductive Fail | notReady | touchesFailed | restartFailed | protocol
  deriving DecidableEq, Repr

def Fail.name : Fail → String
  | .notReady => "notReady"
  | .touchesFailed => "touchesFailed"
  | .restartFailed => "restartFailed"
  | .protocol => "protocol"

inductive Phase | probing | touching | restarting | done | failed (f : Fail)
  deriving DecidableEq, Repr

structure St where
  phase : Phase
  attempt : Nat
  restarts : Nat
  deriving DecidableEq, Repr

def init : St := ⟨.probing, 1, 0⟩

def terminal (s : St) : Bool :=
  match s.phase with
  | .done => true
  | .failed _ => true
  | _ => false

def lose (s : St) (f : Fail) : St :=
  if s.restarts = 0 then ⟨.restarting, s.attempt, 1⟩ else ⟨.failed f, s.attempt, s.restarts⟩

def step (s : St) (e : Ev) : St :=
  match s.phase, e with
  | .probing, .readyYes => ⟨.touching, s.attempt, s.restarts⟩
  | .probing, .readyNo => lose s .notReady
  | .touching, .touchesOk => ⟨.done, s.attempt, s.restarts⟩
  | .touching, .touchesFail => lose s .touchesFailed
  | .restarting, .restartOk => ⟨.probing, s.attempt + 1, s.restarts⟩
  | .restarting, .restartFail => ⟨.failed .restartFailed, s.attempt, s.restarts⟩
  | .done, _ => s
  | .failed _, _ => s
  | _, _ => ⟨.failed .protocol, s.attempt, s.restarts⟩

def exec (s : St) : List Ev → St
  | [] => s
  | e :: es => exec (step s e) es

def used (s : St) : List Ev → Nat
  | [] => 0
  | e :: es => if terminal s then 0 else 1 + used (step s e) es

theorem step_probing_ready (s : St) (h : s.phase = .probing) : step s .readyYes = ⟨.touching, s.attempt, s.restarts⟩ := by
  simp [step, h]

theorem step_probing_not_ready_first (s : St) (h : s.phase = .probing) (r : s.restarts = 0) :
    step s .readyNo = ⟨.restarting, s.attempt, 1⟩ := by
  simp [step, h, lose, r]

theorem step_probing_not_ready_again (s : St) (h : s.phase = .probing) (r : s.restarts ≠ 0) :
    step s .readyNo = ⟨.failed .notReady, s.attempt, s.restarts⟩ := by
  simp [step, h, lose, r]

theorem step_touching_ok (s : St) (h : s.phase = .touching) : step s .touchesOk = ⟨.done, s.attempt, s.restarts⟩ := by
  simp [step, h]

theorem step_touching_fail_first (s : St) (h : s.phase = .touching) (r : s.restarts = 0) :
    step s .touchesFail = ⟨.restarting, s.attempt, 1⟩ := by
  simp [step, h, lose, r]

theorem step_touching_fail_again (s : St) (h : s.phase = .touching) (r : s.restarts ≠ 0) :
    step s .touchesFail = ⟨.failed .touchesFailed, s.attempt, s.restarts⟩ := by
  simp [step, h, lose, r]

theorem step_restart_ok (s : St) (h : s.phase = .restarting) :
    step s .restartOk = ⟨.probing, s.attempt + 1, s.restarts⟩ := by
  simp [step, h]

theorem step_restart_fail (s : St) (h : s.phase = .restarting) :
    step s .restartFail = ⟨.failed .restartFailed, s.attempt, s.restarts⟩ := by
  simp [step, h]

theorem step_terminal (s : St) (h : terminal s = true) (e : Ev) : step s e = s := by
  obtain ⟨p, a, r⟩ := s
  cases p <;> simp [terminal] at h <;> simp [step]

theorem exec_terminal (s : St) (h : terminal s = true) (es : List Ev) : exec s es = s := by
  induction es with
  | nil => rfl
  | cons e es ih => simp [exec, step_terminal s h, ih]

theorem step_protocol_probing (s : St) (h : s.phase = .probing) (e : Ev) (he : e ≠ .readyYes ∧ e ≠ .readyNo) :
    (step s e).phase = .failed .protocol := by
  obtain ⟨p, a, r⟩ := s
  simp at h; subst h
  cases e <;> simp_all [step]

theorem step_protocol_touching (s : St) (h : s.phase = .touching) (e : Ev) (he : e ≠ .touchesOk ∧ e ≠ .touchesFail) :
    (step s e).phase = .failed .protocol := by
  obtain ⟨p, a, r⟩ := s
  simp at h; subst h
  cases e <;> simp_all [step]

theorem step_protocol_restarting (s : St) (h : s.phase = .restarting) (e : Ev) (he : e ≠ .restartOk ∧ e ≠ .restartFail) :
    (step s e).phase = .failed .protocol := by
  obtain ⟨p, a, r⟩ := s
  simp at h; subst h
  cases e <;> simp_all [step]

def Inv (s : St) : Prop :=
  s.restarts ≤ 1 ∧ 1 ≤ s.attempt ∧ s.attempt ≤ s.restarts + 1 ∧ (s.phase = .restarting → s.restarts = 1 ∧ s.attempt = 1)

theorem inv_init : Inv init := by simp [Inv, init]

theorem inv_step {s : St} (h : Inv s) (e : Ev) : Inv (step s e) := by
  obtain ⟨p, a, r⟩ := s
  obtain ⟨h1, h0, h2, h3⟩ := h
  simp only at h1 h0 h2 h3
  by_cases hr : r = 0 <;> cases p <;> cases e <;> simp_all [step, lose, Inv] <;> omega

theorem inv_exec {s : St} (h : Inv s) (es : List Ev) : Inv (exec s es) := by
  induction es generalizing s with
  | nil => exact h
  | cons e es ih => exact ih (inv_step h e)

theorem restarts_le_one (es : List Ev) : (exec init es).restarts ≤ 1 := (inv_exec inv_init es).1

theorem attempt_le_two (es : List Ev) : (exec init es).attempt ≤ 2 := by
  obtain ⟨h1, _, h2, _⟩ := inv_exec inv_init es
  omega

theorem touching_after_ready (s : St) (e : Ev) (h : (step s e).phase = .touching) : s.phase = .probing ∧ e = .readyYes := by
  obtain ⟨p, a, r⟩ := s
  cases p <;> cases e <;> simp_all [step, lose] <;> split at h <;> simp_all

theorem retry_after_restart (s : St) (e : Ev) (h : Inv s) (h2 : (step s e).phase = .touching) (ha : (step s e).attempt = 2) :
    s.phase = .probing ∧ e = .readyYes ∧ s.restarts = 1 := by
  obtain ⟨hp, he⟩ := touching_after_ready s e h2
  subst he
  obtain ⟨p, a, r⟩ := s
  simp at hp; subst hp
  obtain ⟨h1, h0, h4, h3⟩ := h
  simp [step] at ha
  simp only at h1 h0 h4
  refine ⟨rfl, rfl, ?_⟩
  simp only
  omega

theorem done_after_touches (s : St) (e : Ev) (h : (step s e).phase = .done) (hs : ¬ s.phase = .done) :
    s.phase = .touching ∧ e = .touchesOk := by
  obtain ⟨p, a, r⟩ := s
  cases p <;> cases e <;> simp_all [step, lose] <;> split at h <;> simp_all

def rank (s : St) : Nat :=
  match s.phase with
  | .probing => if s.restarts = 0 then 5 else 2
  | .touching => if s.restarts = 0 then 4 else 1
  | .restarting => 3
  | _ => 0

def passEvents (_ : Unit := ()) : Nat := 5

theorem rank_init : rank init = passEvents := rfl

theorem rank_step {s : St} (h : Inv s) (hn : terminal s = false) (e : Ev) : rank (step s e) < rank s := by
  obtain ⟨p, a, r⟩ := s
  obtain ⟨h1, h0, h2, h3⟩ := h
  simp only at h1 h0 h2 h3
  by_cases hr : r = 0 <;> cases p <;> cases e <;> simp_all [step, lose, rank, terminal]

theorem rank_zero_terminal {s : St} (h : rank s = 0) : terminal s = true := by
  obtain ⟨p, a, r⟩ := s
  cases p <;> simp_all [rank, terminal] <;> split at h <;> simp_all

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

def passWorstS (n : Nat) : Nat := 2 * (probeBudgetS + capS n) + restartS

def jobWorstS (n k : Nat) : Nat := capS 2 + (k - 1) * typicalPassS + passWorstS n

theorem job_fits :
    jobWorstS (presses .drags 4) 6 ≤ stepLimitS ∧ jobWorstS (presses .finish 4) 6 ≤ stepLimitS := by decide

def jobWorstExtraS (n k : Nat) : Nat := capS 2 + (k - 1) * typicalPassS + typicalPassS + passWorstS n

theorem job_fits_extra :
    jobWorstExtraS (presses .drags 4) 6 ≤ stepLimitS ∧ jobWorstExtraS (presses .finish 4) 6 ≤ stepLimitS := by decide

private def evsOf (l : List Ev) : Json := Json.arr (l.map fun e => Json.str e.name).toArray

private def phaseJ : Phase → Json
  | .probing => "probing"
  | .touching => "touching"
  | .restarting => "restarting"
  | .done => "done"
  | .failed f => Json.str s!"failed:{f.name}"

private def execCases : List (String × List Ev) :=
  [("clean", [.readyYes, .touchesOk]),
   ("touches fail then recover", [.readyYes, .touchesFail, .restartOk, .readyYes, .touchesOk]),
   ("touches fail twice", [.readyYes, .touchesFail, .restartOk, .readyYes, .touchesFail]),
   ("not ready then recover", [.readyNo, .restartOk, .readyYes, .touchesOk]),
   ("not ready twice", [.readyNo, .restartOk, .readyNo]),
   ("restart fails", [.readyYes, .touchesFail, .restartFail]),
   ("not ready, restart fails", [.readyNo, .restartFail]),
   ("recovered pass loses touches again", [.readyNo, .restartOk, .readyYes, .touchesFail]),
   ("touches before ready", [.touchesOk]),
   ("ready while touching", [.readyYes, .readyYes]),
   ("restart answer while probing", [.restartOk]),
   ("touch answer while restarting", [.readyYes, .touchesFail, .touchesOk]),
   ("events after done", [.readyYes, .touchesOk, .touchesFail, .readyNo]),
   ("events after failure", [.readyNo, .restartFail, .readyYes]),
   ("stops while touching", [.readyYes]),
   ("stops while restarting", [.readyYes, .touchesFail]),
   ("no events", [])]

private def stallCases : List (Nat × Nat × Nat × Nat) :=
  [(8, 0, 0, 0), (8, 299, 0, 0), (8, 300, 0, 0), (8, 659, 0, 0), (8, 660, 0, 0), (8, 661, 0, 0),
   (8, 100, 3, 119), (8, 100, 3, 120), (8, 659, 3, 5), (8, 660, 3, 5), (8, 400, 1, 0), (8, 400, 1, 200), (8, 400, 9, 200), (8, 660, 9, 200), (8, 400, 8, 200),
   (12, 659, 0, 0), (12, 839, 5, 0), (12, 840, 5, 0), (2, 389, 0, 0), (2, 390, 0, 0), (2, 350, 0, 0), (0, 299, 0, 0), (0, 300, 0, 0)]

private def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("probeTries", probeTries), ("probeGapS", probeGapS), ("probeBudgetS", probeBudgetS),
    ("startS", startS), ("gapS", gapS), ("capBaseS", capBaseS), ("capPressS", capPressS), ("pollS", pollS),
    ("restartS", restartS), ("stepLimitS", stepLimitS), ("typicalPassS", typicalPassS), ("passEvents", passEvents)]).compress] ++
  (stallCases.map fun ((n, el, m, sc) : Nat × Nat × Nat × Nat) =>
    (Json.mkObj [("kind", "stall"), ("presses", n), ("elapsed", el), ("marks", m), ("since", sc),
      ("verdict", (stall n el m sc).name)]).compress) ++
  ([Mode.drags, Mode.finish].flatMap fun m => [1, 2, 3, 4, 6].map fun (c : Nat) =>
    (Json.mkObj [("kind", "cap"), ("mode", m.name), ("cycles", c), ("presses", presses m c), ("capS", capS (presses m c)),
      ("passWorstS", passWorstS (presses m c)), ("jobWorstS", jobWorstS (presses m c) 6)]).compress) ++
  ([true, false].flatMap fun (a : Bool) => [true, false].flatMap fun (b : Bool) => [true, false].map fun (c : Bool) =>
    (Json.mkObj [("kind", "ready"), ("sim", a), ("page", b), ("driver", c), ("ready", ready a b c)]).compress) ++
  (execCases.map fun (name, evs) =>
    let s := exec init evs
    (Json.mkObj [("kind", "exec"), ("name", name), ("events", evsOf evs), ("phase", phaseJ s.phase), ("attempt", s.attempt),
      ("restarts", s.restarts), ("terminal", terminal s), ("used", used init evs)]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

/-- Print the golden, or with `--check <file>` compare its bytes; exit 1 when they differ. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"device-sim-touch golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"device-sim-touch golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Device.SimTouch
