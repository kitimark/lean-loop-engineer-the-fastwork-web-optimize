import Lean.Data.Json
/-!
# Morph phases from performance marks (`packages/measure-webkit/src/lag/phase.mjs`)
-/
namespace Fw.Measure.WebKitLagPhase
open Lean

inductive Phase where
  | idle
  | open_
  | close
  deriving DecidableEq, Repr

def Phase.name : Phase → String
  | .idle => "idle"
  | .open_ => "open"
  | .close => "close"

def phaseOf (down up t : Int) : Phase :=
  if t < down then .idle else if t < up then .open_ else .close

def framePhases (marks : List Int) (down up : Int) : List Phase := marks.map (phaseOf down up)

def nIdle (marks : List Int) (down up : Int) : Nat := (framePhases marks down up).count .idle

def nOpen (marks : List Int) (down up : Int) : Nat := (framePhases marks down up).count .open_

def nClose (marks : List Int) (down up : Int) : Nat := (framePhases marks down up).count .close

theorem phaseOf_idle {down up t : Int} (h : t < down) : phaseOf down up t = .idle := by
  simp [phaseOf, h]

theorem phaseOf_open {down up t : Int} (h1 : down ≤ t) (h2 : t < up) : phaseOf down up t = .open_ := by
  simp [phaseOf, Int.not_lt.mpr h1, h2]

theorem phaseOf_close {down up t : Int} (h1 : down ≤ t) (h2 : up ≤ t) : phaseOf down up t = .close := by
  simp [phaseOf, Int.not_lt.mpr h1, Int.not_lt.mpr h2]

theorem framePhases_length (marks : List Int) (down up : Int) : (framePhases marks down up).length = marks.length := by
  simp [framePhases]

theorem counts_sum (marks : List Int) (down up : Int) :
    nIdle marks down up + nOpen marks down up + nClose marks down up = marks.length := by
  induction marks with
  | nil => simp [nIdle, nOpen, nClose, framePhases]
  | cons m ms ih =>
    simp only [nIdle, nOpen, nClose, framePhases, List.map_cons, List.count_cons, List.length_cons] at ih ⊢
    by_cases h1 : m < down
    · simp [phaseOf, h1]; omega
    · by_cases h2 : m < up
      · simp [phaseOf, h1, h2]; omega
      · simp [phaseOf, h1, h2]; omega


theorem nIdle_eq_zero {marks : List Int} {down up : Int} (h : ∀ x ∈ marks, down ≤ x) : nIdle marks down up = 0 := by
  simp only [nIdle, framePhases, List.count_eq_zero, List.mem_map]
  rintro ⟨x, hx, hp⟩
  have := h x hx
  by_cases a : x < up <;> simp [phaseOf, show ¬ x < down by omega, a] at hp

theorem nOpen_eq_zero {marks : List Int} {down up : Int} (h : ∀ x ∈ marks, up ≤ x) : nOpen marks down up = 0 := by
  simp only [nOpen, framePhases, List.count_eq_zero, List.mem_map]
  rintro ⟨x, hx, hp⟩
  have := h x hx
  by_cases a : x < down <;> simp [phaseOf, a, show ¬ x < up by omega] at hp

theorem nIdle_cons (m : Int) (ms : List Int) (down up : Int) :
    nIdle (m :: ms) down up = nIdle ms down up + if phaseOf down up m = .idle then 1 else 0 := by
  simp only [nIdle, framePhases, List.map_cons, List.count_cons]
  simp

theorem nOpen_cons (m : Int) (ms : List Int) (down up : Int) :
    nOpen (m :: ms) down up = nOpen ms down up + if phaseOf down up m = .open_ then 1 else 0 := by
  simp only [nOpen, framePhases, List.map_cons, List.count_cons]
  simp

theorem nClose_cons (m : Int) (ms : List Int) (down up : Int) :
    nClose (m :: ms) down up = nClose ms down up + if phaseOf down up m = .close then 1 else 0 := by
  simp only [nClose, framePhases, List.map_cons, List.count_cons]
  simp

theorem framePhases_blocks {marks : List Int} (hs : marks.Pairwise (· ≤ ·)) {down up : Int} :
    framePhases marks down up =
      List.replicate (nIdle marks down up) .idle ++ List.replicate (nOpen marks down up) .open_ ++
        List.replicate (nClose marks down up) .close := by
  induction marks with
  | nil => simp [framePhases, nIdle, nOpen, nClose]
  | cons m ms ih =>
    rw [List.pairwise_cons] at hs
    obtain ⟨hm, hs'⟩ := hs
    have ih' := ih hs'
    have hc : framePhases (m :: ms) down up = phaseOf down up m :: framePhases ms down up := rfl
    rw [hc, ih', nIdle_cons, nOpen_cons, nClose_cons]
    by_cases h1 : m < down
    · simp [phaseOf, h1, List.replicate_succ]
    · by_cases h2 : m < up
      · have hno : nIdle ms down up = 0 := nIdle_eq_zero fun x hx => by have := hm x hx; omega
        simp [phaseOf, h1, h2, hno, List.replicate_succ]
      · have h0 : nIdle ms down up = 0 := nIdle_eq_zero fun x hx => by have := hm x hx; omega
        have h0' : nOpen ms down up = 0 := nOpen_eq_zero fun x hx => by have := hm x hx; omega
        simp [phaseOf, h1, h2, h0, h0', List.replicate_succ]


/-! ## Which runs are used -/

inductive Refusal where
  | unsorted
  | noDown
  | noUp
  | order
  | idleShort
  | openShort
  | closeShort
  | noScroll
  | noOpen
  deriving DecidableEq, Repr

def Refusal.name : Refusal → String
  | .unsorted => "unsorted"
  | .noDown => "noDown"
  | .noUp => "noUp"
  | .order => "order"
  | .idleShort => "idleShort"
  | .openShort => "openShort"
  | .closeShort => "closeShort"
  | .noScroll => "noScroll"
  | .noOpen => "noOpen"

inductive Outcome where
  | ok (idle open_ close : Nat)
  | refused (r : Refusal)
  deriving DecidableEq, Repr

def minIdle : Nat := 5

def minOpen : Nat := 30

def minClose : Nat := 30

def sortedB (marks : List Int) : Bool := decide (marks.Pairwise (· ≤ ·))

def classify (marks : List Int) (down up : Option Int) : Outcome :=
  if sortedB marks = false then .refused .unsorted
  else match down, up with
    | none, _ => .refused .noDown
    | some _, none => .refused .noUp
    | some d, some u =>
      if u < d then .refused .order
      else if nIdle marks d u < minIdle then .refused .idleShort
      else if nOpen marks d u < minOpen then .refused .openShort
      else if nClose marks d u < minClose then .refused .closeShort
      else .ok (nIdle marks d u) (nOpen marks d u) (nClose marks d u)

theorem classify_unsorted {marks : List Int} (h : sortedB marks = false) (down up : Option Int) :
    classify marks down up = .refused .unsorted := by
  simp [classify, h]

theorem classify_noDown {marks : List Int} (h : sortedB marks = true) (up : Option Int) :
    classify marks none up = .refused .noDown := by
  simp [classify, h]

theorem classify_noUp {marks : List Int} (h : sortedB marks = true) (d : Int) :
    classify marks (some d) none = .refused .noUp := by
  simp [classify, h]

theorem classify_order {marks : List Int} (h : sortedB marks = true) {d u : Int} (hl : u < d) :
    classify marks (some d) (some u) = .refused .order := by
  simp [classify, h, hl]

theorem classify_idleShort {marks : List Int} (h : sortedB marks = true) {d u : Int} (hl : ¬ u < d)
    (hi : nIdle marks d u < minIdle) : classify marks (some d) (some u) = .refused .idleShort := by
  simp [classify, h, hl, hi]

theorem classify_openShort {marks : List Int} (h : sortedB marks = true) {d u : Int} (hl : ¬ u < d)
    (hi : ¬ nIdle marks d u < minIdle) (ho : nOpen marks d u < minOpen) :
    classify marks (some d) (some u) = .refused .openShort := by
  simp [classify, h, hl, hi, ho]

theorem classify_closeShort {marks : List Int} (h : sortedB marks = true) {d u : Int} (hl : ¬ u < d)
    (hi : ¬ nIdle marks d u < minIdle) (ho : ¬ nOpen marks d u < minOpen) (hc : nClose marks d u < minClose) :
    classify marks (some d) (some u) = .refused .closeShort := by
  simp [classify, h, hl, hi, ho, hc]

theorem classify_ok {marks : List Int} (h : sortedB marks = true) {d u : Int} (hl : ¬ u < d)
    (hi : ¬ nIdle marks d u < minIdle) (ho : ¬ nOpen marks d u < minOpen) (hc : ¬ nClose marks d u < minClose) :
    classify marks (some d) (some u) = .ok (nIdle marks d u) (nOpen marks d u) (nClose marks d u) := by
  simp [classify, h, hl, hi, ho, hc]

theorem classify_ok_spec {marks : List Int} {down up : Option Int} {a b c : Nat}
    (h : classify marks down up = .ok a b c) :
    a + b + c = marks.length ∧ minIdle ≤ a ∧ minOpen ≤ b ∧ minClose ≤ c := by
  unfold classify at h
  split at h
  · cases h
  · split at h
    · cases h
    · cases h
    · rename_i d u
      split at h
      · cases h
      · rename_i h1
        split at h
        · cases h
        · rename_i h2
          split at h
          · cases h
          · rename_i h3
            split at h
            · cases h
            · rename_i h4
              cases h
              exact ⟨counts_sum marks d u, by omega, by omega, by omega⟩

def fixedMarks (n : Nat) : List Int := (List.range n).map fun (k : Nat) => (2 * k : Int)

theorem sortedB_fixedMarks (n : Nat) : sortedB (fixedMarks n) = true := by
  simp only [sortedB, fixedMarks, decide_eq_true_eq, List.pairwise_map]
  refine List.pairwise_lt_range.imp ?_
  intro a b hab
  have : (a : Int) + 1 ≤ b := by exact_mod_cast hab
  omega

set_option maxRecDepth 8000 in
theorem classify_fixed : classify (fixedMarks 130) (some 19) (some 139) = .ok 10 60 60 := by
  have h := sortedB_fixedMarks 130
  rw [classify_ok h (by decide) (by decide) (by decide) (by decide)]
  decide

/-- The geometry sample of frame `i` of a phase that starts at frame `start` of this run, held at the last of `n` samples. -/
def geometryIndex (start i n : Nat) : Nat := min (start + i) (n - 1)

theorem geometryIndex_exact {start i n : Nat} (h : start + i < n) : geometryIndex start i n = start + i := by
  simp [geometryIndex]; omega

theorem geometryIndex_clamp {start i n : Nat} (h : n ≤ start + i) : geometryIndex start i n = n - 1 := by
  simp [geometryIndex]; omega

theorem geometryIndex_lt {start i n : Nat} (h : 0 < n) : geometryIndex start i n < n := by
  simp [geometryIndex]; omega

theorem geometryIndex_follows_start : geometryIndex 13 0 130 ≠ geometryIndex 10 0 130 := by decide

/-- The morph value, in thousandths, that a push must reach for the morph to count as open. -/
def minOpenMilli : Int := 900

/-- The run that scrolls into the push is used only when the page scrolled down before the push and the push opened the morph. -/
def acceptScrollIn (o : Outcome) (startY pushY morphMilli : Int) : Outcome :=
  match o with
  | .refused r => .refused r
  | .ok a b c =>
    if pushY ≤ startY then .refused .noScroll
    else if morphMilli < minOpenMilli then .refused .noOpen
    else .ok a b c

theorem acceptScrollIn_refused (r : Refusal) (s p m : Int) : acceptScrollIn (.refused r) s p m = .refused r := rfl

theorem acceptScrollIn_noScroll (a b c : Nat) {s p : Int} (h : p ≤ s) (m : Int) :
    acceptScrollIn (.ok a b c) s p m = .refused .noScroll := by
  simp [acceptScrollIn, h]

theorem acceptScrollIn_noOpen (a b c : Nat) {s p m : Int} (h : s < p) (hm : m < minOpenMilli) :
    acceptScrollIn (.ok a b c) s p m = .refused .noOpen := by
  simp [acceptScrollIn, Int.not_le.mpr h, hm]

theorem acceptScrollIn_ok (a b c : Nat) {s p m : Int} (h : s < p) (hm : minOpenMilli ≤ m) :
    acceptScrollIn (.ok a b c) s p m = .ok a b c := by
  simp [acceptScrollIn, Int.not_le.mpr h, Int.not_lt.mpr hm]

theorem acceptScrollIn_spec {o : Outcome} {s p m : Int} {a b c : Nat} (h : acceptScrollIn o s p m = .ok a b c) :
    o = .ok a b c ∧ s < p ∧ minOpenMilli ≤ m := by
  cases o with
  | refused r => simp [acceptScrollIn] at h
  | ok a' b' c' =>
    by_cases h1 : p ≤ s
    · simp [acceptScrollIn, h1] at h
    · by_cases h2 : m < minOpenMilli
      · simp [acceptScrollIn, h1, h2] at h
      · simp only [acceptScrollIn, h1, h2, ite_false] at h
        cases h
        exact ⟨rfl, by omega, by omega⟩

private def mj (ms : List Int) : Json := toJson ms
private def oj (o : Option Int) : Json := match o with | some v => toJson v | none => Json.null

private def cases (_ : Unit) : List (List Int × Option Int × Option Int) :=
  [(fixedMarks 130, some 19, some 139), (fixedMarks 130, some 20, some 140), (fixedMarks 130, some 21, some 139),
   (fixedMarks 130, some 19, none), (fixedMarks 130, none, some 139), (fixedMarks 130, none, none),
   (fixedMarks 130, some 139, some 19), (fixedMarks 130, some 19, some 19), (fixedMarks 40, some 9, some 41),
   (fixedMarks 130, some 7, some 139), (fixedMarks 130, some 0, some 139), (fixedMarks 130, some 19, some 77),
   (fixedMarks 130, some 19, some 220), (fixedMarks 130, some 19, some 261), (fixedMarks 130, some 9, some 69),
   ([0, 2, 5, 4, 6], some 1, some 3), ([], some 1, some 3), (fixedMarks 150, some 19, some 100),
   (fixedMarks 150, some 21, some 100), ([0, 2, 2, 2, 4, 6, 6, 8], some 2, some 6)]

private def line (c : List Int × Option Int × Option Int) : String :=
  let (ms, d, u) := c
  let base : List (String × Json) := [("kind", "phase"), ("marks", mj ms), ("down", oj d), ("up", oj u)]
  let rest : List (String × Json) :=
    match classify ms d u with
    | .ok a b c => [("outcome", "ok"), ("idle", a), ("open", b), ("close", c)]
    | .refused r => [("outcome", r.name)]
  let ph : List (String × Json) :=
    match d, u with
    | some d, some u => [("phases", toJson ((framePhases ms d u).map Phase.name))]
    | _, _ => []
  (Json.mkObj (base ++ rest ++ ph)).compress

private def scrollCases (_ : Unit) : List (List Int × Option Int × Option Int × Int × Int × Int) :=
  [(fixedMarks 130, some 19, some 139, 4800, 5102, 1000), (fixedMarks 130, some 19, some 139, 5102, 5102, 1000),
   (fixedMarks 130, some 19, some 139, 5102, 5000, 1000), (fixedMarks 130, some 19, some 139, 4800, 5102, 0),
   (fixedMarks 130, some 19, some 139, 4800, 5102, 899), (fixedMarks 130, some 19, some 139, 4800, 5102, 900),
   (fixedMarks 130, some 19, none, 4800, 5102, 1000), (fixedMarks 130, some 19, some 139, 4800, 4801, 1000),
   (fixedMarks 40, some 9, some 41, 4800, 5102, 1000), (fixedMarks 130, some 19, some 139, 5102, 5102, 0)]

private def scrollLine (c : List Int × Option Int × Option Int × Int × Int × Int) : String :=
  let (ms, d, u, s, p, m) := c
  let out := acceptScrollIn (classify ms d u) s p m
  let rest : List (String × Json) :=
    match out with
    | .ok a b c => [("outcome", "ok"), ("idle", a), ("open", b), ("close", c)]
    | .refused r => [("outcome", r.name)]
  let base : List (String × Json) :=
    [("kind", "scrollIn"), ("marks", mj ms), ("down", oj d), ("up", oj u), ("startY", toJson s), ("pushY", toJson p),
     ("morphMilli", toJson m)]
  (Json.mkObj (base ++ rest)).compress

private def geometryCases : List (Nat × Nat × Nat) :=
  [(0, 0, 130), (10, 0, 130), (13, 0, 130), (10, 59, 130), (70, 59, 130), (70, 60, 130), (72, 59, 130), (73, 59, 130),
   (74, 59, 130), (10, 0, 5), (0, 3, 0), (12, 5, 1)]

def phaseGoldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "phaseConst"), ("minIdle", minIdle), ("minOpen", minOpen), ("minClose", minClose)]).compress]
    ++ (cases ()).map line
    ++ [(Json.mkObj [("kind", "scrollInConst"), ("minOpenMilli", minOpenMilli)]).compress]
    ++ (scrollCases ()).map scrollLine
    ++ geometryCases.map fun (st, i, n) =>
      (Json.mkObj [("kind", "geometryIndex"), ("start", st), ("i", i), ("n", n), ("index", geometryIndex st i n)]).compress

end Fw.Measure.WebKitLagPhase
