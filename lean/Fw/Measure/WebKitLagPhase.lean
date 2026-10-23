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
  | noPush
  | fewWheels
  | settled
  | atEnd
  | stalled
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
  | .noPush => "noPush"
  | .fewWheels => "fewWheels"
  | .settled => "settled"
  | .atEnd => "atEnd"
  | .stalled => "stalled"

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

/-! ## A push that lands while the scroll is still in flight -/

/-- Frames after a scroll wheel's frame in which that scroll still counts as in flight: the quiet gap the drives wait between two scroll wheels. -/
def flightHold : Nat := 2

/-- Fewest scroll wheels before the push for the run to count as a scroll (one wheel is a nudge, not a gesture). -/
def minWheels : Nat := 2

/-- Frame `k` has a scroll in flight when some scroll wheel arrived at frame `s` with `s ≤ k ≤ s + flightHold`. -/
def inFlight (scrolls : List Nat) (k : Nat) : Bool := scrolls.any fun s => decide (s ≤ k ∧ k ≤ s + flightHold)

/-- How many of the `n` frames from frame `p` on (the open phase when `p` is the push frame) have a scroll in flight. -/
def flightFrames (scrolls : List Nat) (p n : Nat) : Nat := ((List.range n).filter fun i => inFlight scrolls (p + i)).length

theorem inFlight_wheel {scrolls : List Nat} {s : Nat} (h : s ∈ scrolls) : inFlight scrolls s = true := by
  simp only [inFlight, List.any_eq_true, decide_eq_true_eq]
  exact ⟨s, h, Nat.le_refl s, by omega⟩

theorem inFlight_after {scrolls : List Nat} {s k : Nat} (h : s ∈ scrolls) (h1 : s ≤ k) (h2 : k ≤ s + flightHold) :
    inFlight scrolls k = true := by
  simp only [inFlight, List.any_eq_true, decide_eq_true_eq]
  exact ⟨s, h, h1, h2⟩

theorem inFlight_settled {scrolls : List Nat} {k : Nat} (h : ∀ s ∈ scrolls, s + flightHold < k) :
    inFlight scrolls k = false := by
  rw [Bool.eq_false_iff]
  intro hb
  simp only [inFlight, List.any_eq_true, decide_eq_true_eq] at hb
  obtain ⟨s, hs, _, h2⟩ := hb
  have := h s hs
  omega

theorem inFlight_nil (k : Nat) : inFlight [] k = false := rfl

theorem flightFrames_le (scrolls : List Nat) (p n : Nat) : flightFrames scrolls p n ≤ n := by
  have := List.length_filter_le (fun i => inFlight scrolls (p + i)) (List.range n)
  simpa [flightFrames] using this

theorem flightFrames_settled {scrolls : List Nat} {p : Nat} (h : ∀ s ∈ scrolls, s + flightHold < p) (n : Nat) :
    flightFrames scrolls p n = 0 := by
  have hf : ∀ i, inFlight scrolls (p + i) = false := fun i => inFlight_settled fun s hs => by have := h s hs; omega
  simp [flightFrames, hf]

theorem flightFrames_pos {scrolls : List Nat} {s p n : Nat} (h : s ∈ scrolls) (h1 : s ≤ p) (h2 : p ≤ s + flightHold)
    (hn : 0 < n) : 0 < flightFrames scrolls p n := by
  unfold flightFrames
  apply List.length_pos_of_mem (a := 0)
  simp only [List.mem_filter, List.mem_range, Nat.add_zero]
  exact ⟨hn, inFlight_after h h1 h2⟩

/-- Wheel events as (frame, marked as a push). The scroll wheels are those before the first marked one; the push is the first marked. -/
def splitPush (evs : List (Nat × Bool)) : List Nat × Option Nat :=
  ((evs.takeWhile fun e => !e.2).map Prod.fst, (evs.find? fun e => e.2).map Prod.fst)

theorem splitPush_nil : splitPush [] = ([], none) := rfl

theorem splitPush_marked_first (f : Nat) (rest : List (Nat × Bool)) : splitPush ((f, true) :: rest) = ([], some f) := by
  simp [splitPush]

theorem splitPush_unmarked (f : Nat) (rest : List (Nat × Bool)) :
    splitPush ((f, false) :: rest) = (f :: (splitPush rest).1, (splitPush rest).2) := by
  simp [splitPush]

theorem splitPush_none {evs : List (Nat × Bool)} (h : ∀ e ∈ evs, e.2 = false) : (splitPush evs).2 = none := by
  simp only [splitPush, Option.map_eq_none_iff, List.find?_eq_none, Bool.not_eq_true]
  intro e he
  simp [h e he]

/-- The run that sends the push while the scroll is in flight is used only if the scroll-in rule holds, a push was seen, at least `minWheels` scroll wheels came before it, and the last of them is within `flightHold` frames of the push. -/
def acceptMomentum (o : Outcome) (startY pushY morphMilli : Int) (scrolls : List Nat) (p : Option Nat) : Outcome :=
  match acceptScrollIn o startY pushY morphMilli with
  | .refused r => .refused r
  | .ok a b c =>
    match p with
    | none => .refused .noPush
    | some p =>
      if scrolls.length < minWheels then .refused .fewWheels
      else if inFlight scrolls p = false then .refused .settled
      else .ok a b c

theorem acceptMomentum_scrollIn {o : Outcome} {r : Refusal} {s y m : Int} (h : acceptScrollIn o s y m = .refused r)
    (scrolls : List Nat) (p : Option Nat) : acceptMomentum o s y m scrolls p = .refused r := by
  simp [acceptMomentum, h]

theorem acceptMomentum_noPush {o : Outcome} {s y m : Int} {a b c : Nat} (h : acceptScrollIn o s y m = .ok a b c)
    (scrolls : List Nat) : acceptMomentum o s y m scrolls none = .refused .noPush := by
  simp [acceptMomentum, h]

theorem acceptMomentum_fewWheels {o : Outcome} {s y m : Int} {a b c : Nat} (h : acceptScrollIn o s y m = .ok a b c)
    {scrolls : List Nat} (hl : scrolls.length < minWheels) (p : Nat) :
    acceptMomentum o s y m scrolls (some p) = .refused .fewWheels := by
  simp [acceptMomentum, h, hl]

theorem acceptMomentum_settled {o : Outcome} {s y m : Int} {a b c : Nat} (h : acceptScrollIn o s y m = .ok a b c)
    {scrolls : List Nat} (hl : ¬ scrolls.length < minWheels) {p : Nat} (hf : inFlight scrolls p = false) :
    acceptMomentum o s y m scrolls (some p) = .refused .settled := by
  simp [acceptMomentum, h, hl, hf]

theorem acceptMomentum_ok {o : Outcome} {s y m : Int} {a b c : Nat} (h : acceptScrollIn o s y m = .ok a b c)
    {scrolls : List Nat} (hl : ¬ scrolls.length < minWheels) {p : Nat} (hf : inFlight scrolls p = true) :
    acceptMomentum o s y m scrolls (some p) = .ok a b c := by
  simp [acceptMomentum, h, hl, hf]

theorem acceptMomentum_spec {o : Outcome} {s y m : Int} {scrolls : List Nat} {p : Option Nat} {a b c : Nat}
    (h : acceptMomentum o s y m scrolls p = .ok a b c) :
    acceptScrollIn o s y m = .ok a b c ∧ minWheels ≤ scrolls.length ∧ ∃ q, p = some q ∧ inFlight scrolls q = true := by
  unfold acceptMomentum at h
  split at h
  · cases h
  · rename_i a' b' c' hs
    cases p with
    | none => simp at h
    | some q =>
      by_cases h1 : scrolls.length < minWheels
      · simp [h1] at h
      · by_cases h2 : inFlight scrolls q = false
        · simp [h1, h2] at h
        · simp only [h1, h2, ite_false] at h
          obtain ⟨rfl, rfl, rfl⟩ := h
          exact ⟨hs, by omega, q, rfl, by simpa using h2⟩

/-! ## A page pulled off the scroll lock while the morph is open

The site holds the scroll while the morph is open: it prevents every wheel and puts the scroll position back after every scroll event, so a wheel
cannot move the page then. The pull drive moves the page itself once a frame; the page reads the position right after its own pull, before the site
puts it back, and a frame in which that reading is not the lock position (the position when the push arrived) is a frame in which the pull took
effect; the frame is still drawn at the lock. -/

/-- Frames after an open-phase frame in which a record off the lock still counts for that frame (the scroll event of a pull arrives in the frame after it). -/
def pullLook : Nat := 2

/-- The frame numbers, counted from `k`, of the per-frame positions `ys` that are not the lock position `lock`. -/
def offFrames (lock : Int) : Nat → List Int → List Nat
  | _, [] => []
  | k, y :: rest => (if y ≠ lock then [k] else []) ++ offFrames lock (k + 1) rest

theorem offFrames_lock (lock : Int) (k : Nat) (ys : List Int) (h : ∀ y ∈ ys, y = lock) : offFrames lock k ys = [] := by
  induction ys generalizing k with
  | nil => rfl
  | cons y rest ih =>
    have hy : y = lock := h y (by simp)
    simp [offFrames, hy, ih (k + 1) (fun z hz => h z (by simp [hz]))]

theorem offFrames_off (lock : Int) (k : Nat) (ys : List Int) (h : ∀ y ∈ ys, y ≠ lock) :
    offFrames lock k ys = List.range' k ys.length := by
  induction ys generalizing k with
  | nil => rfl
  | cons y rest ih =>
    have hy : y ≠ lock := h y (by simp)
    simp [offFrames, hy, ih (k + 1) (fun z hz => h z (by simp [hz])), List.range'_succ]

theorem offFrames_mem {lock : Int} {k f : Nat} {ys : List Int} (h : f ∈ offFrames lock k ys) : k ≤ f ∧ f < k + ys.length := by
  induction ys generalizing k with
  | nil => simp [offFrames] at h
  | cons y rest ih =>
    simp only [offFrames, List.mem_append] at h
    rcases h with h | h
    · split at h <;> simp at h <;> simp [h]
    · have := ih h
      simp only [List.length_cons]
      omega

/-- Open-phase frame `p + i` is covered when a moved sample came in that frame or within `pullLook` frames after it. -/
def pullCovered (ds : List Nat) (p i : Nat) : Bool := ds.any fun f => decide (p + i ≤ f ∧ f ≤ p + i + pullLook)

/-- How many of the `n` open-phase frames from the push frame `p` on are covered. -/
def pullFrames (ds : List Nat) (p n : Nat) : Nat := ((List.range n).filter fun i => pullCovered ds p i).length

theorem pullCovered_event {ds : List Nat} {f p i : Nat} (h : f ∈ ds) (h1 : p + i ≤ f) (h2 : f ≤ p + i + pullLook) :
    pullCovered ds p i = true := by
  simp only [pullCovered, List.any_eq_true, decide_eq_true_eq]
  exact ⟨f, h, h1, h2⟩

theorem pullCovered_silent {ds : List Nat} {p i : Nat} (h : ∀ f ∈ ds, f < p + i ∨ p + i + pullLook < f) :
    pullCovered ds p i = false := by
  rw [Bool.eq_false_iff]
  intro hb
  simp only [pullCovered, List.any_eq_true, decide_eq_true_eq] at hb
  obtain ⟨f, hf, h1, h2⟩ := hb
  rcases h f hf with h3 | h3 <;> omega

theorem pullFrames_le (ds : List Nat) (p n : Nat) : pullFrames ds p n ≤ n := by
  have := List.length_filter_le (fun i => pullCovered ds p i) (List.range n)
  simpa [pullFrames] using this

theorem pullFrames_full {ds : List Nat} {p n : Nat} (h : ∀ i, i < n → pullCovered ds p i = true) :
    pullFrames ds p n = n := by
  unfold pullFrames
  rw [List.filter_eq_self.mpr (fun i hi => by simpa using h i (List.mem_range.mp hi))]
  simp

theorem pullFrames_lt {ds : List Nat} {p n i : Nat} (hi : i < n) (h : pullCovered ds p i = false) :
    pullFrames ds p n < n := by
  unfold pullFrames
  have := (List.length_filter_lt_length_iff_exists (l := List.range n) (p := fun i => pullCovered ds p i)).mpr
    ⟨i, List.mem_range.mpr hi, by simp [h]⟩
  simpa using this

theorem pullFrames_nil (p : Nat) {n : Nat} (hn : 0 < n) : pullFrames [] p n < n :=
  pullFrames_lt hn (pullCovered_silent (fun f hf => by simp at hf))

/-- A page that stays on the lock leaves no open-phase frame covered. -/
theorem pullFrames_lock (lock : Int) (ys : List Int) (p : Nat) {n : Nat} (hn : 0 < n) (h : ∀ y ∈ ys, y = lock) :
    pullFrames (offFrames lock 0 ys) p n < n := by
  rw [offFrames_lock lock 0 ys h]
  exact pullFrames_nil p hn

/-- The run that pulls the page while the morph is open is used only if the scroll-in rule holds, a push was seen, the page was not already at the end `maxY` when the push arrived (`pushEvY` is the position its event reported), and every open-phase frame has, within `pullLook` frames after it, a reading off the lock position `pushEvY` (`ys` are the per-frame positions). -/
def acceptPull (o : Outcome) (startY pushY morphMilli maxY pushEvY : Int) (p : Option Nat) (ys : List Int) : Outcome :=
  match acceptScrollIn o startY pushY morphMilli with
  | .refused r => .refused r
  | .ok a b c =>
    match p with
    | none => .refused .noPush
    | some p =>
      if maxY ≤ pushEvY then .refused .atEnd
      else if pullFrames (offFrames pushEvY 0 ys) p b < b then .refused .stalled
      else .ok a b c

theorem acceptPull_scrollIn {o : Outcome} {r : Refusal} {s y m : Int} (h : acceptScrollIn o s y m = .refused r)
    (maxY e : Int) (p : Option Nat) (ys : List Int) : acceptPull o s y m maxY e p ys = .refused r := by
  simp [acceptPull, h]

theorem acceptPull_noPush {o : Outcome} {s y m : Int} {a b c : Nat} (h : acceptScrollIn o s y m = .ok a b c)
    (maxY e : Int) (ys : List Int) : acceptPull o s y m maxY e none ys = .refused .noPush := by
  simp [acceptPull, h]

theorem acceptPull_atEnd {o : Outcome} {s y m : Int} {a b c : Nat} (h : acceptScrollIn o s y m = .ok a b c)
    {maxY e : Int} (he : maxY ≤ e) (p : Nat) (ys : List Int) :
    acceptPull o s y m maxY e (some p) ys = .refused .atEnd := by
  simp [acceptPull, h, he]

theorem acceptPull_stalled {o : Outcome} {s y m : Int} {a b c : Nat} (h : acceptScrollIn o s y m = .ok a b c)
    {maxY e : Int} (he : e < maxY) {p : Nat} {ys : List Int} (hs : pullFrames (offFrames e 0 ys) p b < b) :
    acceptPull o s y m maxY e (some p) ys = .refused .stalled := by
  simp [acceptPull, h, Int.not_le.mpr he, hs]

theorem acceptPull_ok {o : Outcome} {s y m : Int} {a b c : Nat} (h : acceptScrollIn o s y m = .ok a b c)
    {maxY e : Int} (he : e < maxY) {p : Nat} {ys : List Int} (hs : ¬ pullFrames (offFrames e 0 ys) p b < b) :
    acceptPull o s y m maxY e (some p) ys = .ok a b c := by
  simp [acceptPull, h, Int.not_le.mpr he, hs]

theorem acceptPull_spec {o : Outcome} {s y m maxY e : Int} {p : Option Nat} {ys : List Int} {a b c : Nat}
    (h : acceptPull o s y m maxY e p ys = .ok a b c) :
    acceptScrollIn o s y m = .ok a b c ∧ e < maxY ∧ ∃ q, p = some q ∧ pullFrames (offFrames e 0 ys) q b = b := by
  unfold acceptPull at h
  split at h
  · cases h
  · rename_i a' b' c' hs
    cases p with
    | none => simp at h
    | some q =>
      by_cases h1 : maxY ≤ e
      · simp [h1] at h
      · by_cases h2 : pullFrames (offFrames e 0 ys) q b' < b'
        · simp [h1, h2] at h
        · simp only [h1, h2, ite_false] at h
          obtain ⟨rfl, rfl, rfl⟩ := h
          exact ⟨hs, by omega, q, rfl, Nat.le_antisymm (pullFrames_le _ _ _) (by omega)⟩

/-- The label of a job in a table: the matrix index when the run file names it, else `this job` for a lone file or the position (from 1) among several. -/
def jobLabel (idx : Option Nat) (pos n : Nat) : String :=
  match idx with
  | some i => s!"job {i}"
  | none => if n ≤ 1 then "this job" else s!"job {pos + 1}"

theorem jobLabel_named (i pos n : Nat) : jobLabel (some i) pos n = s!"job {i}" := rfl

theorem jobLabel_lone (pos : Nat) : jobLabel none pos 1 = "this job" := by simp [jobLabel]

theorem jobLabel_position {pos n : Nat} (h : 2 ≤ n) : jobLabel none pos n = s!"job {pos + 1}" := by
  simp [jobLabel, show ¬ n ≤ 1 by omega]

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

private def flightCases : List (List Nat × Nat × Nat) :=
  [([10, 12, 14], 16, 60), ([10, 12, 14], 17, 60), ([10, 12, 14], 14, 60), ([10, 12, 14], 19, 60), ([], 10, 60),
   ([10], 12, 5), ([10, 12, 14], 9, 60), ([10, 12, 14], 30, 60), ([3, 5], 5, 1), ([3, 5], 8, 0)]

private def flightLine (c : List Nat × Nat × Nat) : String :=
  let (sc, p, n) := c
  (Json.mkObj [("kind", "flight"), ("scrolls", toJson sc), ("push", p), ("n", n), ("inFlight", toJson (inFlight sc p)),
    ("frames", flightFrames sc p n)]).compress

private def splitCases : List (List (Nat × Bool)) :=
  [[], [(5, true)], [(5, false), (7, false), (9, true), (70, true)], [(5, false), (7, false)], [(5, false), (7, true), (9, false), (70, true)],
   [(9, true), (70, true)]]

private def splitLine (evs : List (Nat × Bool)) : String :=
  let (sc, p) := splitPush evs
  (Json.mkObj [("kind", "splitPush"), ("events", toJson (evs.map fun e => toJson [toJson e.1, toJson e.2])), ("scrolls", toJson sc),
    ("push", oj (p.map (fun x => (x : Int))))]).compress

private def momentumCases (_ : Unit) :
    List (List Int × Option Int × Option Int × Int × Int × Int × List Nat × Option Nat) :=
  let m := fixedMarks 130
  [(m, some 19, some 139, 4800, 5102, 1000, [10, 12, 14], some 16), (m, some 19, some 139, 4800, 5102, 1000, [10, 12, 14], some 17),
   (m, some 19, some 139, 4800, 5102, 1000, [10, 12, 14], some 19), (m, some 19, some 139, 4800, 5102, 1000, [10, 12, 14], some 14),
   (m, some 19, some 139, 4800, 5102, 1000, [14], some 14), (m, some 19, some 139, 4800, 5102, 1000, [], some 14),
   (m, some 19, some 139, 4800, 5102, 1000, [10, 12, 14], none), (m, some 19, some 139, 5102, 5102, 1000, [10, 12, 14], some 16),
   (m, some 19, some 139, 4800, 5102, 899, [10, 12, 14], some 16), (m, some 19, none, 4800, 5102, 1000, [10, 12, 14], some 16),
   (fixedMarks 40, some 9, some 41, 4800, 5102, 1000, [10, 12, 14], some 16), (m, some 19, some 139, 4800, 5102, 900, [10, 12], some 14)]

private def momentumLine (c : List Int × Option Int × Option Int × Int × Int × Int × List Nat × Option Nat) : String :=
  let (ms, d, u, s, y, mm, sc, p) := c
  let out := acceptMomentum (classify ms d u) s y mm sc p
  let rest : List (String × Json) :=
    match out with
    | .ok a b c => [("outcome", "ok"), ("idle", a), ("open", b), ("close", c)]
    | .refused r => [("outcome", r.name)]
  let base : List (String × Json) :=
    [("kind", "momentum"), ("marks", mj ms), ("down", oj d), ("up", oj u), ("startY", toJson s), ("pushY", toJson y),
     ("morphMilli", toJson mm), ("scrolls", toJson sc), ("push", oj (p.map (fun x => (x : Int))))]
  (Json.mkObj (base ++ rest)).compress

/-- `n` per-frame positions on the lock `lock`, 2 below it at every frame `k` for which `off k` holds. -/
private def ySeries (lock : Int) (n : Nat) (off : Nat → Bool) : List Int :=
  (List.range n).map fun k => if off k then lock - 2 else lock

private def pullCases (_ : Unit) :
    List (List Int × Option Int × Option Int × Int × Int × Int × Int × Int × Option Nat × List Int) :=
  let m := fixedMarks 130
  let ok := ySeries 5098 130 fun k => decide (11 ≤ k)
  [(m, some 19, some 139, 4802, 5098, 1000, 5102, 5098, some 10, ok),
   (m, some 19, some 139, 4802, 5098, 1000, 5102, 5098, some 10, ySeries 5098 130 fun k => decide (10 ≤ k ∧ (k - 10) % 3 = 0)),
   (m, some 19, some 139, 4802, 5098, 1000, 5102, 5098, some 10, ySeries 5098 130 fun k => decide (10 ≤ k ∧ (k - 10) % 4 = 0)),
   (m, some 19, some 139, 4802, 5098, 1000, 5102, 5098, some 10, ySeries 5098 130 fun _ => false),
   (m, some 19, some 139, 4802, 5098, 1000, 5102, 5098, some 10, ySeries 5098 130 fun k => decide (11 ≤ k ∧ k < 41)),
   (m, some 19, some 139, 4802, 5102, 1000, 5102, 5102, some 10, ySeries 5102 130 fun k => decide (11 ≤ k)),
   (m, some 19, some 139, 4802, 5103, 1000, 5102, 5103, some 10, ySeries 5103 130 fun k => decide (11 ≤ k)),
   (m, some 19, some 139, 4802, 5101, 1000, 5102, 5101, some 10, ySeries 5101 130 fun k => decide (11 ≤ k)),
   (m, some 19, some 139, 4802, 5098, 1000, 5102, 5098, none, ok),
   (m, some 19, some 139, 5098, 5098, 1000, 5102, 5098, some 10, ok),
   (m, some 19, some 139, 4802, 5098, 899, 5102, 5098, some 10, ok),
   (m, some 19, none, 4802, 5098, 1000, 5102, 5098, some 10, ok),
   (m, some 19, some 139, 4802, 5098, 1000, 5102, 5098, some 10, ySeries 5098 130 fun k => decide (11 ≤ k ∧ k % 2 = 1)),
   (m, some 19, some 139, 4802, 5098, 1000, 5102, 5098, some 10, ySeries 5098 130 fun k => decide (13 ≤ k)),
   (m, some 19, some 139, 4802, 5098, 1000, 5102, 5098, some 10, []),
   (fixedMarks 40, some 9, some 41, 4802, 5098, 1000, 5102, 5098, some 10, ok)]

private def pullLine (c : List Int × Option Int × Option Int × Int × Int × Int × Int × Int × Option Nat × List Int) : String :=
  let (ms, d, u, s, y, mm, mx, e, p, ys) := c
  let out := acceptPull (classify ms d u) s y mm mx e p ys
  let rest : List (String × Json) :=
    match out with
    | .ok a b c => [("outcome", "ok"), ("idle", a), ("open", b), ("close", c)]
    | .refused r => [("outcome", r.name)]
  let base : List (String × Json) :=
    [("kind", "pull"), ("marks", mj ms), ("down", oj d), ("up", oj u), ("startY", toJson s), ("pushY", toJson y),
     ("morphMilli", toJson mm), ("maxY", toJson mx), ("pushEvY", toJson e), ("push", oj (p.map (fun x => (x : Int)))),
     ("ys", toJson ys), ("off", toJson (offFrames e 0 ys))]
  (Json.mkObj (base ++ rest)).compress

private def labelCases : List (Option Nat × Nat × Nat) :=
  [(some 2, 0, 1), (some 3, 1, 3), (none, 0, 1), (none, 0, 3), (none, 2, 3), (none, 0, 2)]

private def labelLine (c : Option Nat × Nat × Nat) : String :=
  let (i, pos, n) := c
  (Json.mkObj [("kind", "jobLabel"), ("index", oj (i.map fun x => (x : Int))), ("pos", pos), ("n", n), ("label", jobLabel i pos n)]).compress

private def geometryCases : List (Nat × Nat × Nat) :=
  [(0, 0, 130), (10, 0, 130), (13, 0, 130), (10, 59, 130), (70, 59, 130), (70, 60, 130), (72, 59, 130), (73, 59, 130),
   (74, 59, 130), (10, 0, 5), (0, 3, 0), (12, 5, 1)]

def phaseGoldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "phaseConst"), ("minIdle", minIdle), ("minOpen", minOpen), ("minClose", minClose)]).compress]
    ++ (cases ()).map line
    ++ [(Json.mkObj [("kind", "scrollInConst"), ("minOpenMilli", minOpenMilli)]).compress]
    ++ (scrollCases ()).map scrollLine
    ++ geometryCases.map (fun (st, i, n) =>
      (Json.mkObj [("kind", "geometryIndex"), ("start", st), ("i", i), ("n", n), ("index", geometryIndex st i n)]).compress)
    ++ [(Json.mkObj [("kind", "momentumConst"), ("flightHold", flightHold), ("minWheels", minWheels)]).compress]
    ++ flightCases.map flightLine
    ++ splitCases.map splitLine
    ++ (momentumCases ()).map momentumLine
    ++ [(Json.mkObj [("kind", "pullConst"), ("pullLook", pullLook)]).compress]
    ++ (pullCases ()).map pullLine
    ++ labelCases.map labelLine

end Fw.Measure.WebKitLagPhase
