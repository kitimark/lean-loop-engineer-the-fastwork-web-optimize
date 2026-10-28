import Lean.Data.Json
-- WebKit@862f17d Source/WebCore/page/Page.cpp:2587-2594 opens the Composite record in Page::willStartRenderingUpdateDisplay, :2600-2609 closes it in didCompleteRenderingUpdateDisplay.
-- Source/WebKit/WebProcess/WebPage/RemoteLayerTree/RemoteLayerTreeDrawingArea.mm:357 calls the opening hook on the main thread; :431-448 flushes on m_commitQueue and calls the closing hook after a main-run-loop dispatch hop.
namespace Fw.Device.FlipAttr
open Lean

inductive Work where
  | script | style | layout | paint | commitWait | idle
  deriving DecidableEq, Repr

def Work.name : Work → String
  | .script => "script" | .style => "style" | .layout => "layout" | .paint => "paint" | .commitWait => "commitWait" | .idle => "idle"

def busyWorks : List Work := [.script, .style, .layout, .paint]

def workOf (t : String) : Option Work :=
  if ["EventDispatch", "TimerFire", "EvaluateScript", "FunctionCall", "FireAnimationFrame", "ObserverCallback"].contains t then some .script
  else if t == "RecalculateStyles" then some .style
  else if t == "Layout" then some .layout
  else if t == "Paint" then some .paint
  else if t == "Composite" then some .commitWait
  else none

structure Rec where
  type : String
  s : Int
  e : Int
  deriving Repr, DecidableEq

def insertSorted (t : Int) : List Int → List Int
  | [] => [t]
  | x :: xs => if t ≤ x then t :: x :: xs else x :: insertSorted t xs

def sortInts : List Int → List Int
  | [] => []
  | x :: xs => insertSorted x (sortInts xs)

def cuts (a b : Int) (rs : List Rec) : List Int :=
  sortInts ([a, b] ++ (rs.flatMap fun r => [r.s, r.e]).filter fun t => a < t && t < b)

def innerIdx (x y : Int) (rs : List Rec) : Option Nat :=
  (List.range rs.length).foldl (fun best i =>
    match rs[i]? with
    | some r =>
      if r.s ≤ x && y ≤ r.e && x < y then
        (match best with | none => some i | some j => if (rs.getD j r).s ≤ r.s then some i else best)
      else best
    | none => best) none

def charged (x y : Int) (rs : List Rec) : Option Work := (innerIdx x y rs).bind fun i => (rs[i]?).bind fun r => workOf r.type

def workTime (a b : Int) (rs : List Rec) (w : Work) : Int :=
  ((((cuts a b rs).zip (cuts a b rs).tail).filter fun p => charged p.1 p.2 rs == some w).map fun p => p.2 - p.1).sum

def held (a b : Int) (rs : List Rec) (i : Nat) : Int :=
  ((((cuts a b rs).zip (cuts a b rs).tail).filter fun p => innerIdx p.1 p.2 rs == some i).map fun p => p.2 - p.1).sum

def lead (a b : Int) (rs : List Rec) (w : Work) : Option Nat :=
  ((List.range rs.length).filter fun i => ((rs[i]?).bind fun r => workOf r.type) == some w).foldl
    (fun best i => match best with
      | none => if 0 < held a b rs i then some i else none
      | some j => if held a b rs j < held a b rs i then some i else best) none

def busy (a b : Int) (rs : List Rec) : Int := (busyWorks.map (workTime a b rs)).sum

def idleNum : Int := 1
def idleDen : Int := 2

def pick (f : Work → Int) (best w : Work) : Work := if f best < f w then w else best

def dominant (a b : Int) (rs : List Rec) : Work :=
  if busy a b rs * idleDen < (b - a) * idleNum then
    (if (b - a) * idleNum ≤ workTime a b rs .commitWait * idleDen then .commitWait else .idle)
  else busyWorks.foldl (pick (workTime a b rs)) .script

theorem workTime_single : workTime 0 10000 [⟨"FunctionCall", 1000, 9000⟩] .script = 8000 := by decide

theorem workTime_nested :
    workTime 0 10000 [⟨"FunctionCall", 1000, 9000⟩, ⟨"Paint", 2000, 8000⟩] .script = 2000 ∧
    workTime 0 10000 [⟨"FunctionCall", 1000, 9000⟩, ⟨"Paint", 2000, 8000⟩] .paint = 6000 := by decide

theorem workTime_cut : workTime 5000 15000 [⟨"Layout", 0, 8000⟩] .layout = 3000 := by decide

theorem workTime_outside : workTime 0 10000 [⟨"Paint", 20000, 30000⟩] .paint = 0 := by decide

theorem commitWait_not_busy : workOf "Composite" = some .commitWait ∧ Work.commitWait ∉ busyWorks := by decide

theorem composite_not_busy : busy 0 10000 [⟨"Composite", 0, 10000⟩] = 0 := by decide

theorem dominant_commitWait (a b : Int) (rs : List Rec) (h : busy a b rs * idleDen < (b - a) * idleNum)
    (hw : (b - a) * idleNum ≤ workTime a b rs .commitWait * idleDen) : dominant a b rs = .commitWait := by
  simp [dominant, h, hw]

theorem dominant_idle (a b : Int) (rs : List Rec) (h : busy a b rs * idleDen < (b - a) * idleNum)
    (hw : ¬ (b - a) * idleNum ≤ workTime a b rs .commitWait * idleDen) : dominant a b rs = .idle := by
  simp [dominant, h, hw]

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

theorem dominant_not_busy (a b : Int) (rs : List Rec) (h : dominant a b rs = .commitWait ∨ dominant a b rs = .idle) :
    busy a b rs * idleDen < (b - a) * idleNum := by
  refine Decidable.byContradiction fun hb => ?_
  have := dominant_busy a b rs hb
  rcases h with h | h <;> rw [h] at this <;> simp [busyWorks] at this

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

theorem lead_work (a b : Int) (rs : List Rec) (w : Work) (i : Nat) (h : lead a b rs w = some i) :
    ((rs[i]?).bind fun r => workOf r.type) == some w := by
  unfold lead at h
  refine lead_fold a b rs w _ none ?_ (by intro j hj; cases hj) i h
  intro i hi
  exact (List.mem_filter.mp hi).2

def leadOf (a b : Int) (rs : List Rec) : Option Nat := if dominant a b rs = .idle then none else lead a b rs (dominant a b rs)

def tailOf (limit : Int) (ds : List Int) : List Int := ds.filter fun d => limit ≤ d

theorem tailOf_mem (limit : Int) (ds : List Int) (d : Int) : d ∈ tailOf limit ds ↔ d ∈ ds ∧ limit ≤ d := by
  simp [tailOf]

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
   ("a later work wins by more time", 0, 10000, [⟨"Layout", 0, 3000⟩, ⟨"Paint", 4000, 7001⟩]),
   ("a Composite span of at least half the frame is commitWait, not busy", 0, 10000, [⟨"Composite", 1000, 6000⟩]),
   ("a Composite span under half of the frame is idle", 0, 10000, [⟨"Composite", 1000, 5999⟩]),
   ("a Composite span does not make a frame busy", 0, 10000, [⟨"Composite", 0, 9000⟩, ⟨"Layout", 9000, 9500⟩]),
   ("busy at half with a long Composite span is the busy work", 0, 10000, [⟨"Paint", 0, 5000⟩, ⟨"Composite", 5000, 10000⟩]),
   ("busy under half with Composite under half is idle", 0, 10000, [⟨"Layout", 0, 4000⟩, ⟨"Composite", 4000, 8000⟩]),
   ("a record nested in a Composite span is taken off it", 0, 10000, [⟨"Composite", 0, 10000⟩, ⟨"Paint", 2000, 4000⟩]),
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
      ("times", Json.arr (busyWorks.map fun w => toJson (workTime a b rs w)).toArray), ("wait", workTime a b rs .commitWait), ("busy", busy a b rs),
      ("work", (dominant a b rs).name), ("lead", match leadOf a b rs with | some i => toJson i | none => Json.null)]).compress) ++
  (tailCases.map fun (l, ds) =>
    (Json.mkObj [("kind", "fliptail"), ("limit", l), ("ds", toJson ds), ("tail", toJson (tailOf l ds))]).compress)

end Fw.Device.FlipAttr
