import Lean.Data.Json
/-!
# Morph phases from performance marks (`packages/measure-webkit/src/lag/phase.mjs`)
A morph run marks every frame, the first push down and the first push up; a frame belongs to the phase its mark time falls in.
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

/-- The phase of a frame whose mark is at `t`, given the times of the first push down and the first push up. -/
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

/-- Every frame lands in exactly one phase. -/
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

/-- A sorted run reads as three runs of frames, so a phase is a step-index range. -/
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
  deriving DecidableEq, Repr

def Refusal.name : Refusal → String
  | .unsorted => "unsorted"
  | .noDown => "noDown"
  | .noUp => "noUp"
  | .order => "order"
  | .idleShort => "idleShort"
  | .openShort => "openShort"
  | .closeShort => "closeShort"

inductive Outcome where
  | ok (idle open_ close : Nat)
  | refused (r : Refusal)
  deriving DecidableEq, Repr

def minIdle : Nat := 5

def minOpen : Nat := 30

def minClose : Nat := 30

def sortedB (marks : List Int) : Bool := decide (marks.Pairwise (· ≤ ·))

/-- Frame counts per phase of one morph run, or the first reason the run is not used. -/
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

/-- A used run has every frame in a phase and at least the minimum in each. -/
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

/-- The marks of the fixed schedule of the synthetic drive: frame `k` at time `2k`. -/
def fixedMarks (n : Nat) : List Int := (List.range n).map fun (k : Nat) => (2 * k : Int)

theorem sortedB_fixedMarks (n : Nat) : sortedB (fixedMarks n) = true := by
  simp only [sortedB, fixedMarks, decide_eq_true_eq, List.pairwise_map]
  refine List.pairwise_lt_range.imp ?_
  intro a b hab
  have : (a : Int) + 1 ≤ b := by exact_mod_cast hab
  omega

set_option maxRecDepth 8000 in
/-- The fixed 10 / 60 / 60 frame schedule (`MORPH_FRAMES`) is the special case with the pushes between frames 9 and 10, and 69 and 70. -/
theorem classify_fixed : classify (fixedMarks 130) (some 19) (some 139) = .ok 10 60 60 := by
  have h := sortedB_fixedMarks 130
  rw [classify_ok h (by decide) (by decide) (by decide) (by decide)]
  decide

/-! ## The golden -/

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

def phaseGoldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "phaseConst"), ("minIdle", minIdle), ("minOpen", minOpen), ("minClose", minClose)]).compress]
    ++ (cases ()).map line

end Fw.Measure.WebKitLagPhase
