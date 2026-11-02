import Lean.Data.Json
import Fw.Measure.TouchLock
import Fw.Measure.WalkBudget
import Fw.Measure.FaultNames
/-!
# Fw.Measure.WindowLoss: the outcome class of every planned touch-lock window, the class counts, and the harness vs Simulator split
-/
namespace Fw.Measure.WindowLoss

open Fw.Measure.TouchLock (Arm Refusal repOrder)
open Fw.Measure.FaultNames (hasText)

inductive Class where
  | ok | noOpen | tooShort | lockMoved
  | pageLost | beginLate | swipeLate | noMove | refusedPage
  | driverNotReady | restartFailed | inspectorDead | evaluateTimeout
  | walkDeadline | jobCut | planShort | noArtifact | other
deriving DecidableEq, Repr

def Class.all : List Class :=
  [.ok, .noOpen, .tooShort, .lockMoved, .pageLost, .beginLate, .swipeLate, .noMove, .refusedPage,
   .driverNotReady, .restartFailed, .inspectorDead, .evaluateTimeout, .walkDeadline, .jobCut, .planShort, .noArtifact, .other]

def Class.name : Class → String
  | .ok => "ok" | .noOpen => "noOpen" | .tooShort => "tooShort" | .lockMoved => "lockMoved"
  | .pageLost => "pageLost" | .beginLate => "beginLate" | .swipeLate => "swipeLate" | .noMove => "noMove"
  | .refusedPage => "refusedPage" | .driverNotReady => "driverNotReady" | .restartFailed => "restartFailed"
  | .inspectorDead => "inspectorDead" | .evaluateTimeout => "evaluateTimeout" | .walkDeadline => "walkDeadline"
  | .jobCut => "jobCut" | .planShort => "planShort" | .noArtifact => "noArtifact" | .other => "other"

theorem names_nodup : (Class.all.map Class.name).Nodup := by decide

theorem all_complete (c : Class) : c ∈ Class.all := by cases c <;> decide

theorem all_nodup : Class.all.Nodup := by decide

def rowClass (status : String) (refusal : Option Refusal) : Class :=
  if status = "ok" then
    match refusal with
    | none => .ok
    | some .noOpen => .noOpen
    | some .tooShort => .tooShort
    | some .lockMoved => .lockMoved
  else if status = "push:pageLost" ∨ status = "pageLost" then .pageLost
  else if status = "push:beginLate" ∨ status = "beginLate" then .beginLate
  else if status = "push:swipeLate" ∨ status = "swipeLate" then .swipeLate
  else if status = "push:noMove" ∨ status = "noMove" then .noMove
  else if status.startsWith "refused:" then .refusedPage
  else .other

structure End where
  present : Bool
  reps : Nat
  incomplete : Option String
  logReason : Option String
  restartOpen : Bool
  attemptTimedOut : Bool
deriving Repr

def End.reason (e : End) : Option String := e.logReason.orElse fun _ => e.incomplete

def endClass (e : End) : Class :=
  if !e.present then .noArtifact
  else match e.reason with
    | none => .other
    | some s =>
      if hasText s "touch-driver-not-ready" then .driverNotReady
      else if hasText s "restart failed" then .restartFailed
      else if hasText s "the inspector is dead" then .inspectorDead
      else if e.restartOpen then .restartFailed
      else if hasText s "walk deadline" then (if e.attemptTimedOut then .evaluateTimeout else .walkDeadline)
      else if hasText s "walk not finished" then .jobCut
      else .other

structure Job where
  fin : End
  rows : List (String × Option Refusal)
deriving Repr

def armsN : Nat := 4

def planned : Nat := Fw.Measure.WalkBudget.repsWant * armsN

theorem planned_value : planned = 24 := by decide

def slotArm (i : Nat) : Arm := (repOrder (i / armsN)).getD (i % armsN) .orig

def windowClass (j : Job) (i : Nat) : Class :=
  if !j.fin.present then .noArtifact
  else match j.rows[i]? with
    | some (s, r) => rowClass s r
    | none => if j.fin.reps ≠ 0 ∧ j.fin.reps * armsN ≤ i then .planShort else endClass j.fin

def jobWindows (j : Job) : List (Arm × Class) := (List.range planned).map fun i => (slotArm i, windowClass j i)

theorem jobWindows_length (j : Job) : (jobWindows j).length = planned := by simp [jobWindows]

theorem jobWindows_arms (j : Job) : (jobWindows j).map (·.1) = (List.range planned).map slotArm := by
  simp [jobWindows, List.map_map, Function.comp_def]

theorem arm_planned (j : Job) (a : Arm) : ((jobWindows j).map (·.1)).count a = Fw.Measure.WalkBudget.repsWant := by
  rw [jobWindows_arms]; cases a <;> decide

theorem windowClass_absent (j : Job) (i : Nat) : windowClass ⟨{ j.fin with present := false }, j.rows⟩ i = .noArtifact := by
  simp [windowClass]

theorem windowClass_row (j : Job) (i : Nat) (s : String) (r : Option Refusal) (hp : j.fin.present = true)
    (h : j.rows[i]? = some (s, r)) : windowClass j i = rowClass s r := by
  simp [windowClass, hp, h]

theorem windowClass_planShort (j : Job) (i : Nat) (hp : j.fin.present = true) (h : j.rows[i]? = none)
    (h0 : j.fin.reps ≠ 0) (hr : j.fin.reps * armsN ≤ i) : windowClass j i = .planShort := by
  simp [windowClass, hp, h, h0, hr]

theorem windowClass_end (j : Job) (i : Nat) (hp : j.fin.present = true) (h : j.rows[i]? = none)
    (hr : j.fin.reps = 0 ∨ i < j.fin.reps * armsN) : windowClass j i = endClass j.fin := by
  have : ¬ (j.fin.reps ≠ 0 ∧ j.fin.reps * armsN ≤ i) := by omega
  simp [windowClass, hp, h, this]

structure Counts where
  ok : Nat := 0
  noOpen : Nat := 0
  tooShort : Nat := 0
  lockMoved : Nat := 0
  pageLost : Nat := 0
  beginLate : Nat := 0
  swipeLate : Nat := 0
  noMove : Nat := 0
  refusedPage : Nat := 0
  driverNotReady : Nat := 0
  restartFailed : Nat := 0
  inspectorDead : Nat := 0
  evaluateTimeout : Nat := 0
  walkDeadline : Nat := 0
  jobCut : Nat := 0
  planShort : Nat := 0
  noArtifact : Nat := 0
  other : Nat := 0
deriving Repr, DecidableEq

def Counts.get (k : Counts) : Class → Nat
  | .ok => k.ok | .noOpen => k.noOpen | .tooShort => k.tooShort | .lockMoved => k.lockMoved
  | .pageLost => k.pageLost | .beginLate => k.beginLate | .swipeLate => k.swipeLate | .noMove => k.noMove
  | .refusedPage => k.refusedPage | .driverNotReady => k.driverNotReady | .restartFailed => k.restartFailed
  | .inspectorDead => k.inspectorDead | .evaluateTimeout => k.evaluateTimeout | .walkDeadline => k.walkDeadline
  | .jobCut => k.jobCut | .planShort => k.planShort | .noArtifact => k.noArtifact | .other => k.other

def Counts.bump (k : Counts) : Class → Counts
  | .ok => { k with ok := k.ok + 1 } | .noOpen => { k with noOpen := k.noOpen + 1 }
  | .tooShort => { k with tooShort := k.tooShort + 1 } | .lockMoved => { k with lockMoved := k.lockMoved + 1 }
  | .pageLost => { k with pageLost := k.pageLost + 1 } | .beginLate => { k with beginLate := k.beginLate + 1 }
  | .swipeLate => { k with swipeLate := k.swipeLate + 1 } | .noMove => { k with noMove := k.noMove + 1 }
  | .refusedPage => { k with refusedPage := k.refusedPage + 1 } | .driverNotReady => { k with driverNotReady := k.driverNotReady + 1 }
  | .restartFailed => { k with restartFailed := k.restartFailed + 1 } | .inspectorDead => { k with inspectorDead := k.inspectorDead + 1 }
  | .evaluateTimeout => { k with evaluateTimeout := k.evaluateTimeout + 1 } | .walkDeadline => { k with walkDeadline := k.walkDeadline + 1 }
  | .jobCut => { k with jobCut := k.jobCut + 1 } | .planShort => { k with planShort := k.planShort + 1 }
  | .noArtifact => { k with noArtifact := k.noArtifact + 1 } | .other => { k with other := k.other + 1 }

def Counts.total (k : Counts) : Nat :=
  k.ok + k.noOpen + k.tooShort + k.lockMoved + k.pageLost + k.beginLate + k.swipeLate + k.noMove + k.refusedPage
    + k.driverNotReady + k.restartFailed + k.inspectorDead + k.evaluateTimeout + k.walkDeadline + k.jobCut
    + k.planShort + k.noArtifact + k.other

def tally (cs : List Class) : Counts := cs.foldl Counts.bump {}

theorem get_bump_self (k : Counts) (c : Class) : (k.bump c).get c = k.get c + 1 := by cases c <;> rfl

theorem get_bump_ne (k : Counts) (c d : Class) (h : c ≠ d) : (k.bump c).get d = k.get d := by
  cases c <;> cases d <;> first | exact absurd rfl h | rfl

theorem total_bump (k : Counts) (c : Class) : (k.bump c).total = k.total + 1 := by
  cases c <;> simp only [Counts.total, Counts.bump] <;> omega

theorem total_empty : (({} : Counts)).total = 0 := by decide

theorem total_foldl (cs : List Class) (k : Counts) : (cs.foldl Counts.bump k).total = k.total + cs.length := by
  induction cs generalizing k with
  | nil => simp
  | cons c cs ih => simp [List.foldl, ih, total_bump]; omega

theorem tally_total (cs : List Class) : (tally cs).total = cs.length := by
  simp [tally, total_foldl, total_empty]

theorem get_foldl (cs : List Class) (k : Counts) (c : Class) : (cs.foldl Counts.bump k).get c = k.get c + cs.count c := by
  induction cs generalizing k with
  | nil => simp
  | cons d cs ih =>
    by_cases h : d = c
    · subst h; simp [List.foldl, ih, get_bump_self]; omega
    · simp [List.foldl, ih, get_bump_ne _ d c h, h]

theorem tally_get (cs : List Class) (c : Class) : (tally cs).get c = cs.count c := by
  simp [tally, get_foldl]
  cases c <;> rfl

def jobCounts (j : Job) : Counts := tally ((jobWindows j).map (·.2))

theorem jobCounts_total (j : Job) : (jobCounts j).total = planned := by
  simp [jobCounts, tally_total, jobWindows_length]

def armCounts (j : Job) (a : Arm) : Counts := tally (((jobWindows j).filter (·.1 == a)).map (·.2))

theorem armCounts_total (j : Job) (a : Arm) : (armCounts j a).total = Fw.Measure.WalkBudget.repsWant := by
  have h := arm_planned j a
  rw [armCounts, tally_total]
  simp only [List.length_map]
  rw [← List.countP_eq_length_filter, ← h, List.count_eq_countP, List.countP_map]
  rfl

def runCounts (js : List Job) : Counts := tally (js.flatMap fun j => (jobWindows j).map (·.2))

theorem runCounts_total (js : List Job) : (runCounts js).total = js.length * planned := by
  have : ∀ (l : List Job), (l.flatMap fun j => (jobWindows j).map (·.2)).length = l.length * planned := by
    intro l
    induction l with
    | nil => simp
    | cons j l ih => simp [List.flatMap_cons, jobWindows_length, ih, Nat.add_mul]; omega
  simp [runCounts, tally_total, this]

inductive Side where
  | ok | harness | simulator
deriving DecidableEq, Repr

def Side.name : Side → String
  | .ok => "ok" | .harness => "harness" | .simulator => "simulator"

def Class.side : Class → Side
  | .ok => .ok
  | .noOpen | .tooShort | .lockMoved | .refusedPage | .walkDeadline | .jobCut | .planShort | .noArtifact | .other => .harness
  | .pageLost | .beginLate | .swipeLate | .noMove | .driverNotReady | .restartFailed | .inspectorDead | .evaluateTimeout => .simulator

def Counts.side (k : Counts) (s : Side) : Nat := ((Class.all.filter (·.side == s)).map k.get).sum

theorem side_partition (k : Counts) : k.side .ok + k.side .harness + k.side .simulator = k.total := by
  simp [Counts.side, Counts.total, Class.all, Class.side, Counts.get]
  omega

theorem side_ok_iff (c : Class) : c.side = .ok ↔ c = .ok := by cases c <;> decide

theorem side_total (j : Job) : (jobCounts j).side .ok + (jobCounts j).side .harness + (jobCounts j).side .simulator = planned := by
  rw [side_partition, jobCounts_total]

def insertDesc (x : Class × Nat) : List (Class × Nat) → List (Class × Nat)
  | [] => [x]
  | y :: ys => if y.2 ≤ x.2 then x :: y :: ys else y :: insertDesc x ys

def sortDesc : List (Class × Nat) → List (Class × Nat)
  | [] => []
  | x :: xs => insertDesc x (sortDesc xs)

theorem mem_insertDesc (x z : Class × Nat) (l : List (Class × Nat)) (h : z ∈ insertDesc x l) : z = x ∨ z ∈ l := by
  induction l with
  | nil => simpa [insertDesc] using h
  | cons y ys ih =>
    unfold insertDesc at h
    split at h
    · simp at h; rcases h with h | h | h <;> simp [h]
    · simp at h; rcases h with h | h
      · simp [h]
      · rcases ih h with h' | h' <;> simp [h']

theorem insertDesc_pairwise (x : Class × Nat) (l : List (Class × Nat)) (hl : l.Pairwise fun a b => b.2 ≤ a.2) :
    (insertDesc x l).Pairwise fun a b => b.2 ≤ a.2 := by
  induction l with
  | nil => simp [insertDesc]
  | cons y ys ih =>
    unfold insertDesc
    rw [List.pairwise_cons] at hl
    split
    · rename_i h
      refine List.Pairwise.cons ?_ (List.Pairwise.cons hl.1 hl.2)
      intro z hz
      simp at hz
      rcases hz with rfl | hz
      · exact h
      · exact Nat.le_trans (hl.1 z hz) h
    · rename_i h
      refine List.Pairwise.cons ?_ (ih hl.2)
      intro z hz
      rcases mem_insertDesc x z ys hz with rfl | hz'
      · omega
      · exact hl.1 z hz'

theorem sortDesc_pairwise (l : List (Class × Nat)) : (sortDesc l).Pairwise fun a b => b.2 ≤ a.2 := by
  induction l with
  | nil => simp [sortDesc]
  | cons x xs ih => exact insertDesc_pairwise x _ ih

theorem insertDesc_length (x : Class × Nat) (l : List (Class × Nat)) : (insertDesc x l).length = l.length + 1 := by
  induction l with
  | nil => simp [insertDesc]
  | cons y ys ih => unfold insertDesc; split <;> simp [ih]

theorem sortDesc_length (l : List (Class × Nat)) : (sortDesc l).length = l.length := by
  induction l with
  | nil => simp [sortDesc]
  | cons x xs ih => simp [sortDesc, insertDesc_length, ih]

def rank (k : Counts) : List (Class × Nat) := sortDesc ((Class.all.filter (· ≠ .ok)).map fun c => (c, k.get c))

theorem rank_sorted (k : Counts) : (rank k).Pairwise fun a b => b.2 ≤ a.2 := sortDesc_pairwise _

theorem rank_length (k : Counts) : (rank k).length = 17 := by
  simp [rank, sortDesc_length, Class.all]

def top (k : Counts) : Option (Class × Nat) := (rank k).head?

theorem top_max (k : Counts) (t : Class × Nat) (h : top k = some t) (p : Class × Nat) (hp : p ∈ rank k) : p.2 ≤ t.2 := by
  unfold top at h
  cases hr : rank k with
  | nil => simp [hr] at h
  | cons a l =>
    rw [hr] at h hp
    simp at h
    subst h
    have := rank_sorted k
    rw [hr, List.pairwise_cons] at this
    simp at hp
    rcases hp with rfl | hp
    · exact Nat.le_refl _
    · exact this.1 p hp

def sufficient (j : Job) : Bool :=
  [Arm.orig, .base, .lock, .pin].all fun a => decide (Fw.Measure.WalkBudget.minKept ≤ (armCounts j a).ok)

def sufficientRate (js : List Job) : Nat × Nat := ((js.filter sufficient).length, js.length)

theorem sufficientRate_le (js : List Job) : (sufficientRate js).1 ≤ (sufficientRate js).2 := by
  simp [sufficientRate]; exact List.length_filter_le _ _

def jobsImplied (a b : Nat) : Option Nat :=
  Fw.Measure.WalkBudget.jobsFor Fw.Gate.Smooth.minSamples a b Fw.Measure.WalkBudget.target.1 Fw.Measure.WalkBudget.target.2 Fw.Measure.WalkBudget.jobsCap

theorem jobsImplied_plan : jobsImplied 2 5 = some Fw.Measure.WalkBudget.jobsNeeded := by
  decide +kernel

def okRows (n : Nat) : List (String × Option Refusal) := List.replicate n ("ok", none)

def endOf (reps : Nat) (inc log : Option String) (ro to : Bool := false) : End :=
  ⟨true, reps, inc, log, ro, to⟩

def endCases : List (String × End) :=
  [("absent", ⟨false, 0, none, none, false, false⟩),
   ("driver", endOf 0 (some "fault touch-driver-not-ready: no ready file after 150 s") none),
   ("restart", endOf 2 (some "fault lost-mid-walk: restart failed: push server: no ready file after 470 s") none),
   ("inspector", endOf 2 (some "the inspector is dead and rebooting the Simulator failed: no Safari tab in 60 s") none),
   ("deadlineEval", endOf 3 (some "walk deadline: abandoned a window in flight after 12 windows") none false true),
   ("deadline", endOf 3 (some "walk deadline: no time left to start lock rep 4") none),
   ("cut", endOf 3 (some "walk not finished: written after a window") none),
   ("cutLog", endOf 3 (some "walk not finished: written after a window") (some "walk deadline: no time left to start pin rep 5")),
   ("cutRestartOpen", endOf 3 (some "walk not finished: written after a window") none true),
   ("deadlineRestartOpen", endOf 3 (some "walk deadline: no time left to start lock rep 4") none true),
   ("noReason", endOf 3 none none),
   ("unknown", endOf 3 (some "something else") none)]

def rowCases : List (String × Option Refusal) :=
  [("ok", none), ("ok", some .noOpen), ("ok", some .tooShort), ("ok", some .lockMoved),
   ("push:pageLost", none), ("push:beginLate", none), ("push:swipeLate", none), ("push:noMove", none),
   ("swipeLate", none), ("refused:nav", none), ("refused:config", none), ("refused:hook", none), ("weird", none)]

def jobCases : List (String × Job) :=
  [("allOk", ⟨endOf 6 none none, okRows 24⟩),
   ("absent", ⟨⟨false, 0, none, none, false, false⟩, []⟩),
   ("driver", ⟨endOf 0 (some "fault touch-driver-not-ready: no ready file after 150 s") none, []⟩),
   ("restartAfterStall", ⟨endOf 2 (some "fault lost-mid-walk: restart failed: push server: no ready file after 470 s") none,
      okRows 8 ++ [("push:pageLost", none)]⟩),
   ("planShort", ⟨endOf 4 none none, okRows 16⟩),
   ("mixed", ⟨endOf 6 none none,
      okRows 4 ++ [("ok", some .noOpen), ("ok", some .tooShort), ("ok", some .lockMoved), ("push:beginLate", none),
        ("push:swipeLate", none), ("push:noMove", none), ("refused:nav", none), ("weird", none)] ++ okRows 16⟩),
   ("deadlineEval", ⟨endOf 6 (some "walk deadline: abandoned a window in flight after 12 windows") none false true, okRows 12⟩),
   ("cutBy", ⟨endOf 6 (some "walk not finished: written after a window") (some "touch restart failed") , okRows 6⟩),
   ("other", ⟨endOf 6 none none, okRows 20⟩)]

def jobsPairs : List (Nat × Nat) := [(2, 5), (1, 4), (3, 12), (1, 12), (9, 12), (0, 5), (4, 5)]

def refusalJson : Option Refusal → Lean.Json
  | none => Lean.Json.null
  | some r => Lean.Json.str r.name

def optStr : Option String → Lean.Json
  | none => Lean.Json.null
  | some s => Lean.Json.str s

def endJson (e : End) : Lean.Json :=
  Lean.Json.mkObj [("present", Lean.toJson e.present), ("reps", Lean.toJson e.reps), ("incomplete", optStr e.incomplete),
    ("logReason", optStr e.logReason), ("restartOpen", Lean.toJson e.restartOpen), ("attemptTimedOut", Lean.toJson e.attemptTimedOut)]

def countsJson (k : Counts) : Lean.Json := Lean.Json.mkObj (Class.all.map fun c => (c.name, Lean.toJson (k.get c)))

def armsList : List Arm := [.orig, .base, .lock, .pin]

open Lean in
def goldenLines (_ : Unit := ()) : List String :=
  let consts := (Json.mkObj [("op", "constants"), ("planned", toJson planned), ("repsWant", toJson Fw.Measure.WalkBudget.repsWant),
    ("minKept", toJson Fw.Measure.WalkBudget.minKept), ("minSamples", toJson Fw.Gate.Smooth.minSamples),
    ("jobsCap", toJson Fw.Measure.WalkBudget.jobsCap), ("jobsNeeded", toJson Fw.Measure.WalkBudget.jobsNeeded),
    ("target", toJson [Fw.Measure.WalkBudget.target.1, Fw.Measure.WalkBudget.target.2]),
    ("classes", toJson (Class.all.map Class.name)),
    ("sides", Json.mkObj (Class.all.map fun c => (c.name, Json.str c.side.name))),
    ("slotArms", toJson ((List.range planned).map fun i => (slotArm i).name))]).compress
  let rs := rowCases.map fun (st, r) =>
    (Json.mkObj [("op", "row"), ("status", Json.str st), ("refusal", refusalJson r), ("class", Json.str (rowClass st r).name)]).compress
  let es := endCases.map fun (nm, e) =>
    (Json.mkObj [("op", "end"), ("case", Json.str nm), ("end", endJson e), ("class", Json.str (endClass e).name)]).compress
  let js := jobCases.map fun (nm, j) =>
    let ws := jobWindows j
    (Json.mkObj [("op", "job"), ("case", Json.str nm), ("end", endJson j.fin),
      ("rows", Json.arr (j.rows.map fun (st, r) => Json.arr #[Json.str st, refusalJson r]).toArray),
      ("windows", toJson (ws.map fun w => w.2.name)),
      ("counts", countsJson (jobCounts j)),
      ("armOk", toJson (armsList.map fun a => (armCounts j a).ok)),
      ("sufficient", toJson (sufficient j)),
      ("sides", toJson ([Side.ok, .harness, .simulator].map fun s => (jobCounts j).side s)),
      ("rank", toJson ((rank (jobCounts j)).map fun (c, n) => s!"{c.name}:{n}"))]).compress
  let all := jobCases.map (·.2)
  let run := (Json.mkObj [("op", "run"), ("jobs", toJson all.length), ("counts", countsJson (runCounts all)),
    ("total", toJson (runCounts all).total), ("sufficient", toJson (sufficientRate all).1),
    ("rank", toJson ((rank (runCounts all)).map fun (c, n) => s!"{c.name}:{n}"))]).compress
  let ns := jobsPairs.map fun (a, b) =>
    (Json.mkObj [("op", "jobs"), ("a", toJson a), ("b", toJson b),
      ("needed", match jobsImplied a b with | none => Json.null | some n => toJson n)]).compress
  [consts] ++ rs ++ es ++ js ++ [run] ++ ns

def goldenText (_ : Unit := ()) : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

def argAfter : List String → String → Option String
  | a :: b :: rest, flag => if a == flag then some b else argAfter (b :: rest) flag
  | _, _ => none

def goldenMain (args : List String) : IO UInt32 := do
  match argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"window-loss golden: {path} is up to date ({goldenLines.length} lines)"
      return 0
    IO.eprintln s!"window-loss golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print goldenText
    return 0

#guard rowClass "ok" none == .ok
#guard rowClass "push:pageLost" none == .pageLost
#guard (jobCounts ⟨endOf 6 none none, okRows 24⟩).ok == 24

end Fw.Measure.WindowLoss
