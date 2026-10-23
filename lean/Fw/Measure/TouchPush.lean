import Lean.Data.Json
/-!
# Fw.Measure.TouchPush: time bounds of one real-touch push in the CI Simulator
-/
namespace Fw.Measure.TouchPush

/-- Millisecond deadlines of one touch window and of the driver start. -/
structure Budget where
  readyMs : Nat
  beginMs : Nat
  swipeMs : Nat
  tailMs : Nat
  answerMs : Nat
  doneMs : Nat
deriving Repr, BEq

/-- Ready: 240 s (runs 39901005729 and 39909042070: 51 to 214 s). Begin, swipe, answer and done: several times the 3.1 s a push takes. -/
def budget : Budget := ⟨240000, 45000, 20000, 600, 20000, 60000⟩

/-- What the harness saw of one touch window, in ms from the `go` file; `none` is a point never reached. -/
structure Obs where
  beginAt : Option Nat
  swipeAt : Option Nat
  moves : Nat
  answered : Bool
  doneAt : Option Nat
deriving Repr, BEq

inductive Outcome where
  | ok | pageLost | beginLate | swipeLate | noMove
deriving Repr, BEq, DecidableEq

def Outcome.name : Outcome → String
  | .ok => "ok"
  | .pageLost => "pageLost"
  | .beginLate => "beginLate"
  | .swipeLate => "swipeLate"
  | .noMove => "noMove"

def within (x : Option Nat) (cap : Nat) : Bool :=
  match x with
  | some v => decide (v ≤ cap)
  | none => false

/-- The window's verdict: the first failing check in this order. -/
def classify (b : Budget) (o : Obs) : Outcome :=
  if o.answered = false then .pageLost
  else if within o.beginAt b.beginMs = false then .beginLate
  else if within o.swipeAt b.swipeMs = false then .swipeLate
  else if o.moves = 0 then .noMove
  else .ok

/-- The driver ended its push in time. -/
def doneInTime (b : Budget) (o : Obs) : Bool := within o.doneAt (b.beginMs + b.swipeMs + b.doneMs)

/-- The lane stays on after a window iff it was on, the window is ok and the driver finished in time. -/
def laneAfter (b : Budget) (on : Bool) (o : Obs) : Bool :=
  on && decide (classify b o = .ok) && doneInTime b o

/-- Longest wait of the harness for one window: each deadline at most once. -/
def windowCap (b : Budget) : Nat := b.beginMs + b.swipeMs + b.tailMs + b.answerMs

/-- Time the harness waits for one window, given what it saw. -/
def spent (b : Budget) (o : Obs) : Nat :=
  (match o.beginAt with | some v => min v b.beginMs | none => b.beginMs)
  + (match o.swipeAt with | some v => min v b.swipeMs | none => b.swipeMs)
  + b.tailMs + (if o.answered then 0 else b.answerMs)

/-- Windows of one job: touch time and failures while the lane is on. -/
def lane (b : Budget) : Bool → List Obs → Nat × Nat
  | _, [] => (0, 0)
  | false, _ :: rest => lane b false rest
  | true, o :: rest =>
    let (t, f) := lane b (laneAfter b true o) rest
    (spent b o + b.doneMs + t, (if classify b o = .ok then 0 else 1) + f)

/-- Timeline plan of a window: a touch window records none. -/
inductive Plan where
  | off
  | stopWithin (ms : Nat)
deriving Repr, BEq

def Plan.name : Plan → String
  | .off => "off"
  | .stopWithin ms => s!"stopWithin {ms}"

def timelinePlan (touch : Bool) (stopMs : Nat) : Plan :=
  if touch then .off else .stopWithin stopMs

theorem classify_pageLost (b : Budget) (o : Obs) (h : o.answered = false) : classify b o = .pageLost := by
  simp [classify, h]

theorem classify_beginLate (b : Budget) (o : Obs) (h1 : o.answered = true) (h2 : within o.beginAt b.beginMs = false) :
    classify b o = .beginLate := by
  simp [classify, h1, h2]

theorem classify_swipeLate (b : Budget) (o : Obs) (h1 : o.answered = true) (h2 : within o.beginAt b.beginMs = true)
    (h3 : within o.swipeAt b.swipeMs = false) : classify b o = .swipeLate := by
  simp [classify, h1, h2, h3]

theorem classify_noMove (b : Budget) (o : Obs) (h1 : o.answered = true) (h2 : within o.beginAt b.beginMs = true)
    (h3 : within o.swipeAt b.swipeMs = true) (h4 : o.moves = 0) : classify b o = .noMove := by
  simp [classify, h1, h2, h3, h4]

theorem classify_ok (b : Budget) (o : Obs) (h1 : o.answered = true) (h2 : within o.beginAt b.beginMs = true)
    (h3 : within o.swipeAt b.swipeMs = true) (h4 : 0 < o.moves) : classify b o = .ok := by
  have : o.moves ≠ 0 := by omega
  simp [classify, h1, h2, h3, this]

theorem classify_ok_iff (b : Budget) (o : Obs) :
    classify b o = .ok ↔ o.answered = true ∧ within o.beginAt b.beginMs = true ∧ within o.swipeAt b.swipeMs = true ∧ o.moves ≠ 0 := by
  unfold classify
  cases h1 : o.answered <;> cases h2 : within o.beginAt b.beginMs <;> cases h3 : within o.swipeAt b.swipeMs <;> by_cases h4 : o.moves = 0 <;>
    simp [h4]

theorem laneAfter_off (b : Budget) (o : Obs) : laneAfter b false o = false := by
  simp [laneAfter]

theorem laneAfter_fail (b : Budget) (on : Bool) (o : Obs) (h : classify b o ≠ .ok) : laneAfter b on o = false := by
  simp [laneAfter, h]

theorem laneAfter_slowDone (b : Budget) (on : Bool) (o : Obs) (h : doneInTime b o = false) : laneAfter b on o = false := by
  simp [laneAfter, h]

theorem laneAfter_ok (b : Budget) (o : Obs) (h : classify b o = .ok) (hd : doneInTime b o = true) : laneAfter b true o = true := by
  simp [laneAfter, h, hd]

theorem spent_le_windowCap (b : Budget) (o : Obs) : spent b o ≤ windowCap b := by
  unfold spent windowCap
  have h1 : (match o.beginAt with | some v => min v b.beginMs | none => b.beginMs) ≤ b.beginMs := by
    cases o.beginAt <;> simp [Nat.min_le_right]
  have h2 : (match o.swipeAt with | some v => min v b.swipeMs | none => b.swipeMs) ≤ b.swipeMs := by
    cases o.swipeAt <;> simp [Nat.min_le_right]
  have h3 : (if o.answered then 0 else b.answerMs) ≤ b.answerMs := by
    split <;> omega
  omega

/-- Time and failures of a job are bounded: at most one failure, and `n` windows cost at most `n` window caps plus `n` done waits. -/
theorem lane_failures_le_one (b : Budget) (on : Bool) (os : List Obs) : (lane b on os).2 ≤ 1 := by
  induction os generalizing on with
  | nil => simp [lane]
  | cons o rest ih =>
    cases on with
    | false => simpa [lane] using ih false
    | true =>
      simp only [lane]
      by_cases h : classify b o = .ok
      · have := ih (laneAfter b true o); simp [h]; omega
      · have hoff : laneAfter b true o = false := laneAfter_fail b true o h
        have h0 : (lane b false rest).2 = 0 := by
          clear ih
          induction rest with
          | nil => simp [lane]
          | cons o' r ih' => simpa [lane] using ih'
        simp [h, hoff, h0]

theorem lane_time_le (b : Budget) (on : Bool) (os : List Obs) : (lane b on os).1 ≤ os.length * (windowCap b + b.doneMs) := by
  induction os generalizing on with
  | nil => simp [lane]
  | cons o rest ih =>
    cases on with
    | false =>
      simp only [lane]
      have := ih false
      simp only [List.length_cons]
      calc (lane b false rest).1 ≤ rest.length * (windowCap b + b.doneMs) := this
        _ ≤ (rest.length + 1) * (windowCap b + b.doneMs) := Nat.mul_le_mul_right _ (Nat.le_succ _)
    | true =>
      simp only [lane]
      have h1 := ih (laneAfter b true o)
      have h2 := spent_le_windowCap b o
      simp only [List.length_cons]
      calc spent b o + b.doneMs + (lane b (laneAfter b true o) rest).1
          ≤ (windowCap b + b.doneMs) + rest.length * (windowCap b + b.doneMs) := by omega
        _ = (rest.length + 1) * (windowCap b + b.doneMs) := by rw [Nat.add_mul, Nat.one_mul]; omega

theorem timelinePlan_touch (ms : Nat) : timelinePlan true ms = .off := by
  simp [timelinePlan]

theorem timelinePlan_other (ms : Nat) : timelinePlan false ms = .stopWithin ms := by
  simp [timelinePlan]

def okObs : Obs := ⟨some 4000, some 7000, 12, true, some 20000⟩

def obsCases : List (String × Obs) := [
  ("ok", okObs),
  ("ok at the deadlines", ⟨some 45000, some 20000, 1, true, some 125000⟩),
  ("page lost", { okObs with answered := false }),
  ("page lost and no begin", ⟨none, none, 0, false, none⟩),
  ("begin at the deadline plus 1", { okObs with beginAt := some 45001 }),
  ("never began", { okObs with beginAt := none }),
  ("swipe at the deadline plus 1", { okObs with swipeAt := some 20001 }),
  ("never finished the swipe", { okObs with swipeAt := none }),
  ("no touchmove", { okObs with moves := 0 }),
  ("ok, driver done late", { okObs with doneAt := some 125001 }),
  ("ok, driver never done", { okObs with doneAt := none })]

def laneCases : List (String × List Obs) := [
  ("empty", []),
  ("all ok", [okObs, okObs, okObs]),
  ("second fails, third is not run", [okObs, { okObs with moves := 0 }, okObs]),
  ("first fails", [{ okObs with answered := false }, okObs, okObs]),
  ("slow driver ends the lane after an ok window", [{ okObs with doneAt := some 200000 }, okObs])]

def planCases : List (Bool × Nat) := [(true, 7500), (false, 7500), (true, 60000), (false, 0)]

open Lean in
def obsJson (o : Obs) : Json :=
  Json.mkObj [("beginAt", match o.beginAt with | some v => toJson v | none => Json.null),
    ("swipeAt", match o.swipeAt with | some v => toJson v | none => Json.null), ("moves", toJson o.moves),
    ("answered", toJson o.answered), ("doneAt", match o.doneAt with | some v => toJson v | none => Json.null)]

open Lean in
def goldenLines (_ : Unit := ()) : List String :=
  let consts := (Json.mkObj [("op", "constants"), ("readyMs", toJson budget.readyMs), ("beginMs", toJson budget.beginMs),
    ("swipeMs", toJson budget.swipeMs), ("tailMs", toJson budget.tailMs), ("answerMs", toJson budget.answerMs),
    ("doneMs", toJson budget.doneMs), ("windowCap", toJson (windowCap budget))]).compress
  let cs := obsCases.map fun (name, o) =>
    (Json.mkObj [("op", "classify"), ("case", Json.str name), ("obs", obsJson o), ("out", Json.str (classify budget o).name),
      ("doneInTime", toJson (doneInTime budget o)), ("laneAfter", toJson (laneAfter budget true o)),
      ("spent", toJson (spent budget o))]).compress
  let ls := laneCases.map fun (name, os) =>
    (Json.mkObj [("op", "lane"), ("case", Json.str name), ("obs", Json.arr (os.map obsJson).toArray),
      ("time", toJson (lane budget true os).1), ("failures", toJson (lane budget true os).2)]).compress
  let ps := planCases.map fun (touch, ms) =>
    (Json.mkObj [("op", "timelinePlan"), ("touch", toJson touch), ("stopMs", toJson ms),
      ("out", Json.str (timelinePlan touch ms).name)]).compress
  [consts] ++ cs ++ ls ++ ps

def goldenText (_ : Unit := ()) : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

def argAfter : List String → String → Option String
  | a :: b :: rest, flag => if a == flag then some b else argAfter (b :: rest) flag
  | _, _ => none

def run (args : List String) : IO UInt32 := do
  match argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"touch-push golden: {path} is up to date ({goldenLines.length} lines)"
      return 0
    IO.eprintln s!"touch-push golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print goldenText
    return 0

#guard classify budget okObs == .ok
#guard classify budget { okObs with beginAt := some 45001 } == .beginLate
#guard (lane budget true [okObs, { okObs with moves := 0 }, okObs]).2 == 1
#guard windowCap budget == 85600

end Fw.Measure.TouchPush
