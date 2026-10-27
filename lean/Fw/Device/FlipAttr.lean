import Lean.Data.Json
/-! Which work holds a long frame of the phone push (phone-flip-p95).

A frame interval runs from one rAF time to the next. The Timeline records that overlap it are cut to the interval,
the time of a nested record is taken off its parent (self time), and the self times are summed per kind of work. The
frame is called idle when the busy work fills less than half of it, else it is called by the work with the most time. -/
namespace Fw.Device.FlipAttr
open Lean

/-- The kinds of work a frame is called by; `idle` is the main thread waiting (compositor, GPU or decode off the main thread). -/
inductive Work where
  | script | style | layout | paint | commit | idle
  deriving DecidableEq, Repr

def Work.name : Work → String
  | .script => "script" | .style => "style" | .layout => "layout" | .paint => "paint" | .commit => "commit" | .idle => "idle"

/-- The works a record can count to, in the order that settles a tie. -/
def busyWorks : List Work := [.script, .style, .layout, .paint, .commit]

/-- The work a Timeline record type counts to; `none` for containers and bookkeeping records. -/
def workOf (t : String) : Option Work :=
  if ["EventDispatch", "TimerFire", "EvaluateScript", "FunctionCall", "FireAnimationFrame", "ObserverCallback"].contains t then some .script
  else if t == "RecalculateStyles" then some .style
  else if t == "Layout" then some .layout
  else if t == "Paint" then some .paint
  else if t == "Composite" then some .commit
  else none

/-- A Timeline record: type, start and end (hundredths of a ms, page clock). A record without an end has `e = s`. -/
structure Rec where
  type : String
  s : Int
  e : Int
  deriving Repr, DecidableEq

/-- Insert `t` into a list sorted ascending. -/
def insertSorted (t : Int) : List Int → List Int
  | [] => [t]
  | x :: xs => if t ≤ x then t :: x :: xs else x :: insertSorted t xs

/-- Insertion sort, ascending. -/
def sortInts : List Int → List Int
  | [] => []
  | x :: xs => insertSorted x (sortInts xs)

/-- The cut points of the frame interval `a..b`: both ends and every record end between them, in order. -/
def cuts (a b : Int) (rs : List Rec) : List Int :=
  sortInts ([a, b] ++ (rs.flatMap fun r => [r.s, r.e]).filter fun t => a < t && t < b)

/-- The index of the record that holds the piece `x..y` of time: of the records that cover it, the one that started last (the later one in the list on a tie, so a nested record wins over its parent). -/
def innerIdx (x y : Int) (rs : List Rec) : Option Nat :=
  (List.range rs.length).foldl (fun best i =>
    match rs[i]? with
    | some r =>
      if r.s ≤ x && y ≤ r.e && x < y then
        (match best with | none => some i | some j => if (rs.getD j r).s ≤ r.s then some i else best)
      else best
    | none => best) none

/-- The work the piece `x..y` counts to: the work of its innermost record. -/
def charged (x y : Int) (rs : List Rec) : Option Work := (innerIdx x y rs).bind fun i => (rs[i]?).bind fun r => workOf r.type

/-- The time of work `w` inside the frame interval: the length of all pieces between cut points whose innermost record counts to `w`. -/
def workTime (a b : Int) (rs : List Rec) (w : Work) : Int :=
  ((((cuts a b rs).zip (cuts a b rs).tail).filter fun p => charged p.1 p.2 rs == some w).map fun p => p.2 - p.1).sum

/-- The time the record with index `i` holds inside the frame interval (pieces whose innermost record it is). -/
def held (a b : Int) (rs : List Rec) (i : Nat) : Int :=
  ((((cuts a b rs).zip (cuts a b rs).tail).filter fun p => innerIdx p.1 p.2 rs == some i).map fun p => p.2 - p.1).sum

/-- The record that names a frame called by work `w`: the one of that work that holds the most time (the earliest on a tie); `none` when none holds any. -/
def lead (a b : Int) (rs : List Rec) (w : Work) : Option Nat :=
  ((List.range rs.length).filter fun i => ((rs[i]?).bind fun r => workOf r.type) == some w).foldl
    (fun best i => match best with
      | none => if 0 < held a b rs i then some i else none
      | some j => if held a b rs j < held a b rs i then some i else best) none

/-- The busy time: the self time of all records that count to a work. -/
def busy (a b : Int) (rs : List Rec) : Int := (busyWorks.map (workTime a b rs)).sum

/-- The busy work fills less than this share of the frame (numerator over denominator) for the frame to be idle. -/
def idleNum : Int := 1
def idleDen : Int := 2

def pick (f : Work → Int) (best w : Work) : Work := if f best < f w then w else best

/-- The work a frame is called by: idle when the busy time is under half the interval, else the work with the most time (the earliest in `busyWorks` on a tie). -/
def dominant (a b : Int) (rs : List Rec) : Work :=
  if busy a b rs * idleDen < (b - a) * idleNum then .idle else busyWorks.foldl (pick (workTime a b rs)) .script

/-- A record inside the interval counts its whole length. -/
theorem workTime_single : workTime 0 10000 [⟨"FunctionCall", 1000, 9000⟩] .script = 8000 := by decide

/-- A nested record is taken off its parent: the parent keeps the rest. -/
theorem workTime_nested :
    workTime 0 10000 [⟨"FunctionCall", 1000, 9000⟩, ⟨"Paint", 2000, 8000⟩] .script = 2000 ∧
    workTime 0 10000 [⟨"FunctionCall", 1000, 9000⟩, ⟨"Paint", 2000, 8000⟩] .paint = 6000 := by decide

/-- A record is cut to the interval. -/
theorem workTime_cut : workTime 5000 15000 [⟨"Layout", 0, 8000⟩] .layout = 3000 := by decide

/-- A record outside the interval counts nothing. -/
theorem workTime_outside : workTime 0 10000 [⟨"Paint", 20000, 30000⟩] .paint = 0 := by decide

/-- Branch 1: a frame whose busy time is under half of it is idle. -/
theorem dominant_idle (a b : Int) (rs : List Rec) (h : busy a b rs * idleDen < (b - a) * idleNum) : dominant a b rs = .idle := by
  simp [dominant, h]

/-- Branch 2: otherwise the call is one of the busy works. -/
theorem dominant_busy (a b : Int) (rs : List Rec) (h : ¬ busy a b rs * idleDen < (b - a) * idleNum) : dominant a b rs ∈ busyWorks := by
  unfold dominant
  simp only [h, ↓reduceIte]
  have key : ∀ (l : List Work) (best : Work), best ∈ busyWorks → (∀ w ∈ l, w ∈ busyWorks) →
      l.foldl (pick (workTime a b rs)) best ∈ busyWorks := by
    intro l
    induction l with
    | nil => intro best hb _; simpa using hb
    | cons x t ih =>
      intro best hb hl
      simp only [List.foldl_cons]
      apply ih
      · unfold pick
        split
        · exact hl x (by simp)
        · exact hb
      · intro w hw; exact hl w (by simp [hw])
  exact key busyWorks .script (by simp [busyWorks]) (fun w hw => hw)

private theorem fold_max (f : Work → Int) : ∀ (l : List Work) (best : Work),
    f best ≤ f (l.foldl (pick f) best) ∧ ∀ w ∈ l, f w ≤ f (l.foldl (pick f) best) := by
  intro l
  induction l with
  | nil => intro best; simp
  | cons x t ih =>
    intro best
    simp only [List.foldl_cons]
    obtain ⟨h1, h2⟩ := ih (pick f best x)
    have hp : f best ≤ f (pick f best x) ∧ f x ≤ f (pick f best x) := by
      unfold pick; split <;> omega
    refine ⟨by omega, ?_⟩
    intro w hw
    rcases List.mem_cons.mp hw with rfl | hw
    · omega
    · exact h2 w hw

/-- Branch 2, maximal: the work a busy frame is called by has at least the time of every other work. -/
theorem dominant_max (a b : Int) (rs : List Rec) (h : ¬ busy a b rs * idleDen < (b - a) * idleNum) :
    ∀ w ∈ busyWorks, workTime a b rs w ≤ workTime a b rs (dominant a b rs) := by
  intro w hw
  unfold dominant
  simp only [h, ↓reduceIte]
  have := (fold_max (workTime a b rs) busyWorks .script).2 w hw
  exact this

private theorem fold_stay (f : Work → Int) (best : Work) : ∀ (l : List Work), (∀ w ∈ l, f w ≤ f best) → l.foldl (pick f) best = best := by
  intro l
  induction l with
  | nil => intro _; rfl
  | cons x t ih =>
    intro h
    simp only [List.foldl_cons]
    have hx : ¬ f best < f x := by have := h x (by simp); omega
    have : pick f best x = best := by simp [pick, hx]
    rw [this]
    exact ih (fun w hw => h w (by simp [hw]))

/-- Branch 2, tie: when script has the most time (also in a tie) a busy frame is called script. -/
theorem dominant_script (a b : Int) (rs : List Rec) (h : ¬ busy a b rs * idleDen < (b - a) * idleNum)
    (hs : ∀ w ∈ busyWorks, workTime a b rs w ≤ workTime a b rs .script) : dominant a b rs = .script := by
  unfold dominant
  simp only [h, ↓reduceIte]
  exact fold_stay (workTime a b rs) .script busyWorks hs

private theorem lead_fold (a b : Int) (rs : List Rec) (w : Work) : ∀ (l : List Nat) (best : Option Nat),
    (∀ i ∈ l, ((rs[i]?).bind fun r => workOf r.type) == some w) → (∀ j, best = some j → ((rs[j]?).bind fun r => workOf r.type) == some w) →
    ∀ j, (l.foldl (fun best i => match best with
      | none => if 0 < held a b rs i then some i else none
      | some j => if held a b rs j < held a b rs i then some i else best) best) = some j →
      ((rs[j]?).bind fun r => workOf r.type) == some w := by
  intro l
  induction l with
  | nil => intro best _ hb j hj; exact hb j (by simpa using hj)
  | cons x t ih =>
    intro best hl hb j hj
    simp only [List.foldl_cons] at hj
    refine ih _ (fun i hi => hl i (by simp [hi])) ?_ j hj
    intro k hk
    cases best with
    | none =>
      simp only at hk
      split at hk
      · cases hk; exact hl x (by simp)
      · cases hk
    | some j0 =>
      simp only at hk
      split at hk
      · cases hk; exact hl x (by simp)
      · exact hb k (by simpa using hk)

/-- The record that names a frame is of the work the frame is called by. -/
theorem lead_work (a b : Int) (rs : List Rec) (w : Work) (i : Nat) (h : lead a b rs w = some i) :
    ((rs[i]?).bind fun r => workOf r.type) == some w := by
  unfold lead at h
  refine lead_fold a b rs w _ none ?_ (by intro j hj; cases hj) i h
  intro i hi
  exact (List.mem_filter.mp hi).2

/-- The record that names a frame: the lead record of its dominant work, none for an idle frame. -/
def leadOf (a b : Int) (rs : List Rec) : Option Nat := if dominant a b rs = .idle then none else lead a b rs (dominant a b rs)

/-- The records of the tail: the intervals of at least the given length (the p95 of a visit, or the 50 ms limit plus one). -/
def tailOf (limit : Int) (ds : List Int) : List Int := ds.filter fun d => limit ≤ d

theorem tailOf_mem (limit : Int) (ds : List Int) (d : Int) : d ∈ tailOf limit ds ↔ d ∈ ds ∧ limit ≤ d := by
  simp [tailOf]

/-! ## Golden vectors (packages/contracts/golden/device/phone-arms.jsonl, kinds `flipwork`, `flipattr`, `fliptail`) -/

private def typeCases : List String :=
  ["EventDispatch", "TimerFire", "EvaluateScript", "FunctionCall", "FireAnimationFrame", "ObserverCallback", "RecalculateStyles",
   "Layout", "Paint", "Composite", "RenderingFrame", "TimeStamp", "ScheduleStyleRecalculation", "GarbageCollected", ""]

private def attrCases : List (String × Int × Int × List Rec) :=
  [("one script record", 0, 10000, [⟨"FunctionCall", 1000, 9000⟩]),
   ("a nested paint is taken off its parent", 0, 10000, [⟨"FunctionCall", 1000, 9000⟩, ⟨"Paint", 2000, 8000⟩]),
   ("a record is cut to the interval", 5000, 15000, [⟨"Layout", 0, 8000⟩, ⟨"RecalculateStyles", 12000, 30000⟩]),
   ("a record outside the interval counts nothing", 0, 10000, [⟨"Paint", 20000, 30000⟩, ⟨"Layout", 10000, 12000⟩]),
   ("busy under half of the frame is idle", 0, 10000, [⟨"Paint", 0, 2000⟩, ⟨"Layout", 3000, 4900⟩]),
   ("busy at half of the frame is not idle", 0, 10000, [⟨"Paint", 0, 5000⟩]),
   ("a tie goes to the earlier work", 0, 10000, [⟨"Layout", 0, 3000⟩, ⟨"RecalculateStyles", 4000, 7000⟩]),
   ("a later work wins by more time", 0, 10000, [⟨"Layout", 0, 3000⟩, ⟨"Composite", 4000, 7001⟩]),
   ("a container and an instant count nothing", 0, 10000, [⟨"RenderingFrame", 0, 10000⟩, ⟨"TimeStamp", 500, 500⟩, ⟨"Paint", 1000, 9000⟩]),
   ("script keeps its self time around nested work", 0, 20000,
    [⟨"EventDispatch", 0, 12000⟩, ⟨"Layout", 1000, 5000⟩, ⟨"Paint", 6000, 8000⟩]),
   ("on a partial overlap the record that started last holds the overlap", 0, 10000, [⟨"Layout", 0, 6000⟩, ⟨"Paint", 4000, 9000⟩]),
   ("on equal starts the later record in the list is the inner one", 0, 10000, [⟨"FunctionCall", 0, 8000⟩, ⟨"Layout", 0, 3000⟩])]

private def tailCases : List (Int × List Int) :=
  [(5000, [1667, 5000, 5001, 12000, 4999]), (6000, []), (1, [1667, 1666])]

private def recJ (r : Rec) : Json :=
  Json.arr #[Json.str r.type, toJson r.s, toJson r.e]

def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "flipwork"), ("types", Json.arr (typeCases.map Json.str).toArray),
    ("works", Json.arr (typeCases.map fun t => match workOf t with | some w => Json.str w.name | none => Json.null).toArray),
    ("busyWorks", Json.arr (busyWorks.map fun w => Json.str w.name).toArray), ("idleNum", idleNum), ("idleDen", idleDen)]).compress] ++
  (attrCases.map fun (n, a, b, rs) =>
    (Json.mkObj [("kind", "flipattr"), ("name", n), ("a", a), ("b", b), ("recs", Json.arr (rs.map recJ).toArray),
      ("times", Json.arr (busyWorks.map fun w => toJson (workTime a b rs w)).toArray), ("busy", busy a b rs),
      ("work", (dominant a b rs).name), ("lead", match leadOf a b rs with | some i => toJson i | none => Json.null)]).compress) ++
  (tailCases.map fun (l, ds) =>
    (Json.mkObj [("kind", "fliptail"), ("limit", l), ("ds", toJson ds), ("tail", toJson (tailOf l ds))]).compress)

end Fw.Device.FlipAttr
