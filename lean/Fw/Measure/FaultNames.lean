import Lean.Data.Json
/-!
# Fw.Measure.FaultNames: the named faults of a Simulator job and the report's `faultOf`
-/
namespace Fw.Measure.FaultNames

inductive Fault where
  | none
  | budget
  | driver
  | lost
  | hang
  | crash
  | deadline
deriving DecidableEq, Repr

def Fault.name : Fault → String
  | .none => "none"
  | .budget => "budget"
  | .driver => "touch-driver-not-ready"
  | .lost => "lost-mid-walk"
  | .hang => "page-lost-or-evaluate-timeout"
  | .crash => "socket-crash"
  | .deadline => "walk-deadline-or-other"

def Fault.all : List Fault := [.none, .budget, .driver, .lost, .hang, .crash, .deadline]

theorem names_nodup : (Fault.all.map Fault.name).Nodup := by decide

theorem driver_ne_lost : Fault.driver.name ≠ Fault.lost.name := by decide

inductive Phase where
  | start
  | walk
deriving DecidableEq, Repr

def Phase.name : Phase → String
  | .start => "start"
  | .walk => "walk"

def driverFault (requested on : Bool) : Bool := requested && !on

def driverEnd (requested on : Bool) (ph : Phase) : Option Fault :=
  if driverFault requested on then
    some (match ph with | .start => Fault.driver | .walk => Fault.lost)
  else Option.none

theorem driverFault_untouched (r o : Bool) (h : driverFault r o = true) : r = true ∧ o = false := by
  cases r <;> cases o <;> simp_all [driverFault]

theorem driverFault_on (r : Bool) : driverFault r true = false := by cases r <;> rfl

theorem driverFault_unasked (o : Bool) : driverFault false o = false := rfl

theorem driverFault_asked_off : driverFault true false = true := rfl

theorem driverEnd_start : driverEnd true false .start = some .driver := rfl

theorem driverEnd_walk : driverEnd true false .walk = some .lost := rfl

theorem driverEnd_on (ph : Phase) : driverEnd true true ph = Option.none := rfl

theorem driverEnd_unasked (o : Bool) (ph : Phase) : driverEnd false o ph = Option.none := by cases o <;> rfl

theorem driverEnd_iff (r o : Bool) (ph : Phase) : (driverEnd r o ph).isSome = driverFault r o := by
  cases r <;> cases o <;> cases ph <;> rfl

structure Report where
  fault : Option Fault
  budgetShort : Bool
  kept : Nat
  incomplete : Bool
  text : String
deriving Repr

def hasText (msg pat : String) : Bool := decide (1 < (msg.splitOn pat).length)

def hasAny (msg : String) (pats : List String) : Bool := pats.any fun p => hasText msg.toLower p.toLower

def socketWords : List String := ["setTypeOfService", "socket"]

def lostWords : List String := ["pageLost", "page lost", "timed out"]

def faultOf (minKept : Nat) (r : Report) : Fault :=
  match r.fault with
  | some f => f
  | Option.none =>
    if r.budgetShort then .budget
    else if minKept ≤ r.kept then .none
    else if hasAny r.text socketWords then .crash
    else if hasAny r.text lostWords then .hang
    else if r.incomplete then .deadline
    else .none

theorem faultOf_named (m : Nat) (r : Report) (f : Fault) (h : r.fault = some f) : faultOf m r = f := by
  simp [faultOf, h]

theorem faultOf_budget (m : Nat) (r : Report) (h0 : r.fault = Option.none) (h : r.budgetShort = true) :
    faultOf m r = .budget := by
  simp [faultOf, h0, h]

theorem faultOf_kept (m : Nat) (r : Report) (h0 : r.fault = Option.none) (h1 : r.budgetShort = false) (h : m ≤ r.kept) :
    faultOf m r = .none := by
  simp [faultOf, h0, h1, h]

theorem faultOf_socket (m : Nat) (r : Report) (h0 : r.fault = Option.none) (h1 : r.budgetShort = false)
    (h2 : r.kept < m) (h : hasAny r.text socketWords = true) : faultOf m r = .crash := by
  have : ¬ m ≤ r.kept := by omega
  simp [faultOf, h0, h1, this, h]

theorem faultOf_hang (m : Nat) (r : Report) (h0 : r.fault = Option.none) (h1 : r.budgetShort = false)
    (h2 : r.kept < m) (h3 : hasAny r.text socketWords = false) (h : hasAny r.text lostWords = true) :
    faultOf m r = .hang := by
  have : ¬ m ≤ r.kept := by omega
  simp [faultOf, h0, h1, this, h3, h]

theorem faultOf_deadline (m : Nat) (r : Report) (h0 : r.fault = Option.none) (h1 : r.budgetShort = false)
    (h2 : r.kept < m) (h3 : hasAny r.text socketWords = false) (h4 : hasAny r.text lostWords = false)
    (h : r.incomplete = true) : faultOf m r = .deadline := by
  have : ¬ m ≤ r.kept := by omega
  simp [faultOf, h0, h1, this, h3, h4, h]

theorem faultOf_quiet (m : Nat) (r : Report) (h0 : r.fault = Option.none) (h1 : r.budgetShort = false)
    (h2 : r.kept < m) (h3 : hasAny r.text socketWords = false) (h4 : hasAny r.text lostWords = false)
    (h : r.incomplete = false) : faultOf m r = .none := by
  have : ¬ m ≤ r.kept := by omega
  simp [faultOf, h0, h1, this, h3, h4, h]

def optName : Option Fault → String
  | some f => f.name
  | Option.none => "-"

def reportCases : List (String × Report) := [
  ("a named fault wins", ⟨some .driver, true, 9, true, "socket"⟩),
  ("a named mid-walk loss", ⟨some .lost, false, 0, true, ""⟩),
  ("a short plan is the budget", ⟨Option.none, true, 4, false, ""⟩),
  ("enough kept windows", ⟨Option.none, false, 5, true, "pageLost"⟩),
  ("just short of enough, a clean end", ⟨Option.none, false, 4, false, ""⟩),
  ("a socket error", ⟨Option.none, false, 2, true, "EINVAL setTypeOfService"⟩),
  ("a socket error in capitals", ⟨Option.none, false, 2, true, "SOCKET hang up"⟩),
  ("a lost page", ⟨Option.none, false, 0, true, "walk deadline: x pageLost"⟩),
  ("a page lost, spaced", ⟨Option.none, false, 1, true, "the page lost its tab"⟩),
  ("an evaluate timeout", ⟨Option.none, false, 1, false, "Runtime.evaluate timed out after 120000 ms"⟩),
  ("socket before lost", ⟨Option.none, false, 3, true, "pageLost then socket closed"⟩),
  ("a walk deadline", ⟨Option.none, false, 2, true, "walk deadline: x"⟩),
  ("no text and no end", ⟨Option.none, false, 0, false, ""⟩)]

open Lean in
def goldenLines (minKept : Nat) : List String :=
  let ds := [Phase.start, Phase.walk].flatMap fun ph => [(true, true), (true, false), (false, true), (false, false)].map fun (r, o) =>
    (Json.mkObj [("op", "driverEnd"), ("requested", toJson r), ("on", toJson o), ("phase", Json.str ph.name),
      ("fault", Json.str (optName (driverEnd r o ph)))]).compress
  let fs := reportCases.map fun (name, r) =>
    (Json.mkObj [("op", "faultOf"), ("case", Json.str name), ("fault", Json.str (optName r.fault)),
      ("budgetShort", toJson r.budgetShort), ("kept", toJson r.kept), ("incomplete", toJson r.incomplete),
      ("text", Json.str r.text), ("minKept", toJson minKept), ("out", Json.str (faultOf minKept r).name)]).compress
  let ns := Fault.all.map fun f => (Json.mkObj [("op", "faultName"), ("name", Json.str f.name)]).compress
  ns ++ ds ++ fs

end Fw.Measure.FaultNames
