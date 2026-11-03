import Lean.Data.Json
import Fw.Measure.WindowLoss
namespace Fw.Measure.WindowRetry

open Fw.Measure.TouchLock (Refusal)
open Fw.Measure.WalkBudget (blockMs bodyMs startsWindow deadlineAt job)
open Fw.Measure.WindowLoss (rowClass)

def redoable : Option Refusal → Bool
  | some .noOpen => true
  | some .tooShort => true
  | _ => false

def eligible (status : String) (r : Option Refusal) : Bool := decide (status = "ok") && redoable r

def redoFits (dl now reserve left : Nat) : Bool := decide (now + blockMs (left + 1) + reserve ≤ dl)

structure Ask where
  status : String
  refusal : Option Refusal
  redone : Bool
  driverOn : Bool
  dl : Nat
  now : Nat
  reserve : Nat
  left : Nat
deriving Repr

inductive Verdict where
  | kept | notRedoable | already | noDriver | noTime | redo
deriving DecidableEq, Repr

def Verdict.all : List Verdict := [.kept, .notRedoable, .already, .noDriver, .noTime, .redo]

def Verdict.name : Verdict → String
  | .kept => "kept" | .notRedoable => "notRedoable" | .already => "already"
  | .noDriver => "noDriver" | .noTime => "noTime" | .redo => "redo"

theorem verdict_names_nodup : (Verdict.all.map Verdict.name).Nodup := by decide

def verdict (a : Ask) : Verdict :=
  if a.status = "ok" ∧ a.refusal = none then .kept
  else if eligible a.status a.refusal = false then .notRedoable
  else if a.redone then .already
  else if !a.driverOn then .noDriver
  else if redoFits a.dl a.now a.reserve a.left = false then .noTime
  else .redo

theorem verdict_kept (a : Ask) (hs : a.status = "ok") (hr : a.refusal = none) : verdict a = .kept := by
  simp [verdict, hs, hr]

theorem verdict_status (a : Ask) (hs : a.status ≠ "ok") : verdict a = .notRedoable := by
  simp [verdict, eligible, hs]

theorem verdict_lockMoved (a : Ask) (hr : a.refusal = some .lockMoved) : verdict a = .notRedoable := by
  simp [verdict, eligible, hr, redoable]

theorem verdict_already (a : Ask) (he : eligible a.status a.refusal = true) (hd : a.redone = true) : verdict a = .already := by
  have hk : ¬ (a.status = "ok" ∧ a.refusal = none) := by
    rintro ⟨h1, h2⟩
    simp [eligible, redoable, h2] at he
  simp [verdict, hk, he, hd]

theorem verdict_noDriver (a : Ask) (he : eligible a.status a.refusal = true) (hd : a.redone = false) (hv : a.driverOn = false) :
    verdict a = .noDriver := by
  have hk : ¬ (a.status = "ok" ∧ a.refusal = none) := by
    rintro ⟨h1, h2⟩
    simp [eligible, redoable, h2] at he
  simp [verdict, hk, he, hd, hv]

theorem verdict_noTime (a : Ask) (he : eligible a.status a.refusal = true) (hd : a.redone = false) (hv : a.driverOn = true)
    (hf : redoFits a.dl a.now a.reserve a.left = false) : verdict a = .noTime := by
  have hk : ¬ (a.status = "ok" ∧ a.refusal = none) := by
    rintro ⟨h1, h2⟩
    simp [eligible, redoable, h2] at he
  simp [verdict, hk, he, hd, hv, hf]

theorem verdict_redo (a : Ask) (he : eligible a.status a.refusal = true) (hd : a.redone = false) (hv : a.driverOn = true)
    (hf : redoFits a.dl a.now a.reserve a.left = true) : verdict a = .redo := by
  have hk : ¬ (a.status = "ok" ∧ a.refusal = none) := by
    rintro ⟨h1, h2⟩
    simp [eligible, redoable, h2] at he
  simp [verdict, hk, he, hd, hv, hf]

theorem verdict_redo_elim (a : Ask) (h : verdict a = .redo) :
    eligible a.status a.refusal = true ∧ a.redone = false ∧ a.driverOn = true ∧ redoFits a.dl a.now a.reserve a.left = true := by
  unfold verdict at h
  by_cases h1 : a.status = "ok" ∧ a.refusal = none
  · simp [h1] at h
  by_cases h2 : eligible a.status a.refusal = false
  · simp [h1, h2] at h
  by_cases h3 : a.redone = true
  · simp [h1, h2, h3] at h
  by_cases h4 : a.driverOn = false
  · simp [h1, h2, h3, h4] at h
  by_cases h5 : redoFits a.dl a.now a.reserve a.left = false
  · simp [h1, h2, h3, h4, h5] at h
  simp only [Bool.not_eq_false] at h2 h3 h4 h5 ⊢
  simp at h2 h3 h4 h5
  exact ⟨by simpa using h2, h3, by simpa using h4, h5⟩

theorem redo_once (a : Ask) (h : a.redone = true) : verdict a ≠ .redo := by
  intro hv
  have := (verdict_redo_elim a hv).2.1
  simp [h] at this

theorem redo_inside_deadline (a : Ask) (h : verdict a = .redo) (hdl : a.dl ≤ deadlineAt job) :
    a.now + blockMs (a.left + 1) + a.reserve ≤ deadlineAt job := by
  have hf := (verdict_redo_elim a h).2.2.2
  simp [redoFits] at hf
  omega

theorem redo_starts_window (a : Ask) (h : verdict a = .redo) : startsWindow a.dl a.now a.reserve = true := by
  have hf := (verdict_redo_elim a h).2.2.2
  simp [redoFits] at hf
  simp only [startsWindow, decide_eq_true_eq]
  omega

theorem blockMs_succ (n : Nat) : blockMs n + bodyMs ≤ blockMs (n + 1) := by
  unfold blockMs
  rw [Fw.Measure.WalkBudget.tailEvery_value]
  have h : (n + 17 - 1) / 17 ≤ (n + 1 + 17 - 1) / 17 := Nat.div_le_div_right (by omega)
  have h2 := Nat.mul_le_mul_right (Fw.Measure.WalkBudget.tailMs - bodyMs) h
  have h3 : (n + 1) * bodyMs = n * bodyMs + bodyMs := by rw [Nat.succ_mul]
  omega

theorem redo_keeps_plan (a : Ask) (h : verdict a = .redo) :
    a.now + bodyMs + blockMs a.left + a.reserve ≤ a.dl := by
  have hf := (verdict_redo_elim a h).2.2.2
  simp [redoFits] at hf
  have := blockMs_succ a.left
  omega

theorem blockMs_one : blockMs 1 = 383000 := by decide +kernel

theorem redo_start_bound (a : Ask) (h : verdict a = .redo) (hdl : a.dl ≤ deadlineAt job) :
    a.now + a.reserve + 383000 ≤ deadlineAt job := by
  have h1 := redo_inside_deadline a h hdl
  have h2 : blockMs 1 ≤ blockMs (a.left + 1) := Fw.Measure.WalkBudget.blockMs_mono 1 (a.left + 1) (by omega)
  rw [blockMs_one] at h2
  omega

theorem late_noRedo (a : Ask) (he : eligible a.status a.refusal = true) (hd : a.redone = false) (hv : a.driverOn = true)
    (hdl : a.dl ≤ deadlineAt job) (hl : deadlineAt job < a.now + blockMs (a.left + 1) + a.reserve) : verdict a = .noTime := by
  apply verdict_noTime a he hd hv
  simp only [redoFits, decide_eq_false_iff_not]
  omega

inductive Outcome where
  | recovered | noOpen | tooShort | lockMoved | failed
deriving DecidableEq, Repr

def Outcome.all : List Outcome := [.recovered, .noOpen, .tooShort, .lockMoved, .failed]

def Outcome.name : Outcome → String
  | .recovered => "recovered" | .noOpen => "noOpen" | .tooShort => "tooShort"
  | .lockMoved => "lockMoved" | .failed => "failed"

theorem outcome_names_nodup : (Outcome.all.map Outcome.name).Nodup := by decide

def outcomeOf (status : String) (r : Option Refusal) : Outcome :=
  if status = "ok" then
    match r with
    | none => .recovered
    | some .noOpen => .noOpen
    | some .tooShort => .tooShort
    | some .lockMoved => .lockMoved
  else .failed

def Outcome.kept (o : Outcome) : Bool := decide (o = .recovered)

def clsOf : Refusal → WindowLoss.Class
  | .noOpen => WindowLoss.Class.noOpen
  | .tooShort => WindowLoss.Class.tooShort
  | .lockMoved => WindowLoss.Class.lockMoved

def finalClass (first : Refusal) (o : Outcome) : WindowLoss.Class :=
  if o.kept then WindowLoss.Class.ok else clsOf first

theorem rowClass_status (s : String) (r : Option Refusal) (hs : s ≠ "ok") : rowClass s r ≠ WindowLoss.Class.ok := by
  unfold rowClass
  simp only [hs, ite_false]
  split <;> first | (intro h; cases h) | skip
  all_goals (split <;> first | (intro h; cases h) | skip)
  all_goals (split <;> first | (intro h; cases h) | skip)
  all_goals (split <;> first | (intro h; cases h) | skip)
  all_goals (split <;> first | (intro h; cases h) | skip)

theorem outcome_recovered_iff (s : String) (r : Option Refusal) : outcomeOf s r = .recovered ↔ rowClass s r = WindowLoss.Class.ok := by
  by_cases hs : s = "ok"
  · subst hs
    cases r with
    | none => decide
    | some x => cases x <;> decide
  · have h1 : outcomeOf s r = .failed := by simp [outcomeOf, hs]
    rw [h1]
    exact ⟨fun h => (nomatch h), fun h => absurd h (rowClass_status s r hs)⟩

theorem outcome_status (s : String) (r : Option Refusal) (hs : s ≠ "ok") : outcomeOf s r = .failed := by
  simp [outcomeOf, hs]

theorem outcome_none : outcomeOf "ok" none = .recovered := by decide

theorem outcome_noOpen : outcomeOf "ok" (some .noOpen) = .noOpen := by decide

theorem outcome_tooShort : outcomeOf "ok" (some .tooShort) = .tooShort := by decide

theorem outcome_lockMoved : outcomeOf "ok" (some .lockMoved) = .lockMoved := by decide

theorem kept_iff (o : Outcome) : o.kept = true ↔ o = .recovered := by simp [Outcome.kept]

theorem failed_not_kept (s : String) (r : Option Refusal) (h : outcomeOf s r ≠ .recovered) : (outcomeOf s r).kept = false := by
  simp [Outcome.kept, h]

theorem never_pass_from_failed (first : Refusal) (o : Outcome) (h : o ≠ .recovered) : finalClass first o = clsOf first := by
  simp [finalClass, Outcome.kept, h]

theorem pass_only_recovered (first : Refusal) (o : Outcome) : finalClass first o = WindowLoss.Class.ok ↔ o = .recovered := by
  by_cases h : o = .recovered
  · simp [finalClass, Outcome.kept, h]
  · rw [never_pass_from_failed first o h]
    cases first <;> simp [clsOf, h]

theorem final_noOpen_kept (o : Outcome) (h : o ≠ .recovered) : finalClass .noOpen o = WindowLoss.Class.noOpen :=
  never_pass_from_failed _ _ h

theorem final_tooShort_kept (o : Outcome) (h : o ≠ .recovered) : finalClass .tooShort o = WindowLoss.Class.tooShort :=
  never_pass_from_failed _ _ h

def windowRuns (a : Ask) : Nat := if verdict a = .redo then 2 else 1

theorem windowRuns_le (a : Ask) : windowRuns a ≤ 2 := by unfold windowRuns; split <;> omega

def attempts (runs : List Nat) : Nat := runs.sum

theorem attempts_le (as : List Ask) : attempts (as.map windowRuns) ≤ 2 * as.length := by
  induction as with
  | nil => simp [attempts]
  | cons a rest ih =>
    simp only [attempts, List.map_cons, List.sum_cons, List.length_cons] at *
    have := windowRuns_le a
    omega

def slack (dl now reserve left : Nat) : Nat := dl - (now + reserve + blockMs left)

def redosFit (dl now reserve left : Nat) : Nat := slack dl now reserve left / bodyMs

theorem redos_fit (dl now reserve left k : Nat) (hk : k ≤ redosFit dl now reserve left) (h : now + reserve + blockMs left ≤ dl) :
    now + reserve + blockMs left + k * bodyMs ≤ dl := by
  have h1 : k * bodyMs ≤ slack dl now reserve left := by
    have := (Nat.le_div_iff_mul_le (by rw [Fw.Measure.WalkBudget.bodyMs_value]; omega : 0 < bodyMs)).1 hk
    exact this
  unfold slack at h1
  omega

theorem redos_at_start : redosFit 2400000 100000 30000 24 = 17 := by decide +kernel

theorem redos_late : redosFit 2400000 1500000 30000 7 = 6 := by decide +kernel

theorem redos_none_at_cut : redosFit 2400000 2100000 30000 4 = 0 := by decide +kernel

def statusCases : List (String × Option Refusal) :=
  [("ok", none), ("ok", some .noOpen), ("ok", some .tooShort), ("ok", some .lockMoved),
   ("push:pageLost", none), ("push:swipeLate", none), ("push:beginLate", none), ("refused:config", none)]

def askCases : List (String × Ask) :=
  [("kept", ⟨"ok", none, false, true, 2400000, 300000, 30000, 20⟩),
   ("status", ⟨"push:pageLost", none, false, true, 2400000, 300000, 30000, 20⟩),
   ("lockMoved", ⟨"ok", some .lockMoved, false, true, 2400000, 300000, 30000, 20⟩),
   ("already", ⟨"ok", some .noOpen, true, true, 2400000, 300000, 30000, 20⟩),
   ("noDriver", ⟨"ok", some .tooShort, false, false, 2400000, 300000, 30000, 20⟩),
   ("noTime", ⟨"ok", some .noOpen, false, true, 2400000, 2100000, 30000, 4⟩),
   ("noTimeLast", ⟨"ok", some .tooShort, false, true, 2400000, 2000000, 30000, 0⟩),
   ("redoNoOpen", ⟨"ok", some .noOpen, false, true, 2400000, 300000, 30000, 20⟩),
   ("redoTooShort", ⟨"ok", some .tooShort, false, true, 2400000, 1500000, 30000, 7⟩),
   ("redoEdge", ⟨"ok", some .noOpen, false, true, 2400000, 1987000, 30000, 0⟩),
   ("noTimeEdge", ⟨"ok", some .noOpen, false, true, 2400000, 1987001, 30000, 0⟩)]

def priceCases : List (Nat × Nat) := [(100000, 24), (300000, 20), (1500000, 7), (2100000, 4), (2400000, 0)]

def refusalJson : Option Refusal → Lean.Json
  | none => Lean.Json.null
  | some r => Lean.Json.str r.name

open Lean in
def goldenLines (_ : Unit := ()) : List String :=
  let consts := (Json.mkObj [("op", "constants"), ("verdicts", toJson (Verdict.all.map Verdict.name)),
    ("outcomes", toJson (Outcome.all.map Outcome.name)), ("redoMs", toJson (blockMs 1)),
    ("deadlineMs", toJson (deadlineAt job)), ("bodyMs", toJson bodyMs),
    ("blockMs", toJson ((List.range 26).map blockMs))]).compress
  let os := statusCases.map fun (st, r) =>
    (Json.mkObj [("op", "outcome"), ("status", Json.str st), ("refusal", refusalJson r),
      ("outcome", Json.str (outcomeOf st r).name), ("eligible", toJson (eligible st r)),
      ("final", match r with
        | some f => Json.str (finalClass f (outcomeOf st r)).name
        | none => Json.null)]).compress
  let vs := askCases.map fun (nm, a) =>
    (Json.mkObj [("op", "verdict"), ("case", Json.str nm), ("status", Json.str a.status), ("refusal", refusalJson a.refusal),
      ("redone", toJson a.redone), ("driverOn", toJson a.driverOn), ("dl", toJson a.dl), ("now", toJson a.now),
      ("reserve", toJson a.reserve), ("left", toJson a.left), ("verdict", Json.str (verdict a).name)]).compress
  let ps := priceCases.map fun (now, left) =>
    (Json.mkObj [("op", "price"), ("now", toJson now), ("left", toJson left), ("dl", toJson (deadlineAt job)), ("reserve", toJson 30000),
      ("slack", toJson (slack (deadlineAt job) now 30000 left)), ("redos", toJson (redosFit (deadlineAt job) now 30000 left))]).compress
  [consts] ++ os ++ vs ++ ps

def goldenText (_ : Unit := ()) : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

def argAfter : List String → String → Option String
  | a :: b :: rest, flag => if a == flag then some b else argAfter (b :: rest) flag
  | _, _ => none

def goldenMain (args : List String) : IO UInt32 := do
  match argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"window-retry golden: {path} is up to date ({goldenLines.length} lines)"
      return 0
    IO.eprintln s!"window-retry golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print goldenText
    return 0

#guard (askCases.map fun (_, a) => (verdict a).name) ==
  ["kept", "notRedoable", "notRedoable", "already", "noDriver", "noTime", "noTime", "redo", "redo", "redo", "noTime"]

end Fw.Measure.WindowRetry
