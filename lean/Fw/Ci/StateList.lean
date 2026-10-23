import Lean.Data.Json
/-!
# `fw ci state`: which list to read next (task `ci-state-fast`)
`gh run list` returns the newest runs first, run ids grow with time. One list that does not hold the id is read by this rule,
which says whether a longer list can hold it. A run id older than the first unfiltered list is not chased through 400 and 1000
rows (MEASURED 2026-10-23: 2.8, 9.3 and 22.3 s per list); a caller that knows the branch or the workflow narrows the list instead.
-/
namespace Fw.Ci.StateList

/-- The list sizes tried in turn. -/
def limits : List Nat := [100, 400, 1000]

/-- What the command does after one list. -/
inductive Step where
  /-- The id is in the list. -/
  | found
  /-- The list holds fewer rows than asked for: the repository (or the filter) has no more, so no longer list adds one. -/
  | ended
  /-- Unfiltered list, id older than its oldest row: stop and tell the caller to pass the branch. -/
  | older
  /-- The id lies inside or above the listed ids but is absent (another branch, deleted): a longer list adds only older runs. -/
  | absent
  /-- Filtered list, id older than its oldest row, a longer limit exists: read it. -/
  | grow (next : Nat)
  /-- Filtered list at the last limit, id still older: nothing is left to read. -/
  | exhausted
  deriving DecidableEq, Repr

/-- The limit after `limit` in `limits`, if any. -/
def nextLimit : Nat → Option Nat
  | 100 => some 400
  | 400 => some 1000
  | _ => none

/-- The decision after reading a list of `limit` rows (`ids`, newest first) for `id`; `narrowed` says `--branch` or `--workflow` was given. -/
def step (narrowed : Bool) (limit id : Nat) (ids : List Nat) : Step :=
  if id ∈ ids then .found
  else if ids.length < limit then .ended
  else if ids.all (id < ·) then
    if narrowed then (match nextLimit limit with | some n => .grow n | none => .exhausted) else .older
  else .absent

theorem step_found (n : Bool) (l id : Nat) (ids : List Nat) (h : id ∈ ids) : step n l id ids = .found := by
  simp [step, h]

theorem step_ended (n : Bool) (l id : Nat) (ids : List Nat) (h : id ∉ ids) (hl : ids.length < l) :
    step n l id ids = .ended := by
  simp [step, h, hl]

theorem step_older (l id : Nat) (ids : List Nat) (h : id ∉ ids) (hl : ¬ ids.length < l) (ha : ids.all (id < ·) = true) :
    step false l id ids = .older := by
  simp [step, h, hl, ha]

theorem step_grow (l id n : Nat) (ids : List Nat) (h : id ∉ ids) (hl : ¬ ids.length < l)
    (ha : ids.all (id < ·) = true) (hn : nextLimit l = some n) :
    step true l id ids = .grow n := by
  simp [step, h, hl, ha, hn]

theorem step_exhausted (l id : Nat) (ids : List Nat) (h : id ∉ ids) (hl : ¬ ids.length < l)
    (ha : ids.all (id < ·) = true) (hn : nextLimit l = none) :
    step true l id ids = .exhausted := by
  simp [step, h, hl, ha, hn]

theorem step_absent (n : Bool) (l id : Nat) (ids : List Nat) (h : id ∉ ids) (hl : ¬ ids.length < l)
    (ha : ¬ ids.all (id < ·) = true) : step n l id ids = .absent := by
  simp [step, h, hl, ha]

/-- Unfiltered, the command reads one list at most: `grow` is never the answer. -/
theorem unfiltered_one_list (l id : Nat) (ids : List Nat) : ∀ n, step false l id ids ≠ .grow n := by
  intro n
  unfold step
  split <;> try simp
  split <;> try simp
  split <;> simp

/-- Every `grow` goes to a larger limit of `limits`, so a filtered read ends after at most `limits.length` lists. -/
theorem grow_bigger (l n : Nat) (h : nextLimit l = some n) : l < n ∧ n ∈ limits := by
  unfold nextLimit at h
  split at h <;> simp_all [limits] <;> omega

theorem limits_three_distinct : limits.length = 3 ∧ limits.Nodup := by decide

/-- Cases: (name, narrowed, limit, id, ids, expected). -/
def cases : List (String × Bool × Nat × Nat × List Nat × Step) := [
  ("found in first list", false, 100, 7, [9, 8, 7], .found),
  ("short list ends", false, 100, 5, [9, 8, 7], .ended),
  ("short filtered list ends", true, 100, 5, [9, 8, 7], .ended),
  ("unfiltered, id older than the oldest of a full list", false, 3, 5, [9, 8, 7], .older),
  ("filtered, id older than the oldest, grow 100 to 400", true, 100, 5, List.range' 7 100, .grow 400),
  ("filtered, id older, grow 400 to 1000", true, 400, 5, List.range' 7 400, .grow 1000),
  ("filtered, id older at last limit", true, 1000, 5, List.range' 7 1000, .exhausted),
  ("id newer than the newest row", false, 3, 99, [9, 8, 7], .absent),
  ("id inside the range but absent", true, 3, 8, [9, 7, 6], .absent),
  ("empty short list ends", false, 100, 5, [], .ended)]

#guard cases.all fun (_, n, l, id, ids, e) => step n l id ids == e

open Lean in
def stepJson : Step → Json
  | .found => Json.mkObj [("step", "found")]
  | .ended => Json.mkObj [("step", "ended")]
  | .older => Json.mkObj [("step", "older")]
  | .absent => Json.mkObj [("step", "absent")]
  | .grow n => Json.mkObj [("step", "grow"), ("next", n)]
  | .exhausted => Json.mkObj [("step", "exhausted")]

open Lean in
/-- The golden file: one line per case, `{name, narrowed, limit, id, ids, response}`. -/
def goldenText (_ : Unit := ()) : String :=
  String.join (cases.map fun (n, nr, l, id, ids, e) =>
    (Json.mkObj [("name", n), ("narrowed", nr), ("limit", l), ("id", id), ("ids", Json.arr (ids.map fun x => Json.num (JsonNumber.fromNat x)).toArray),
      ("response", stepJson e)]).compress ++ "\n")

end Fw.Ci.StateList
