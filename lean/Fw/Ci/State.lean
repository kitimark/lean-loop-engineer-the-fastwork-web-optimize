import Lean.Data.Json
namespace Fw.Ci.State
/-! `fw ci state`: read the run list, growing the limit, until the run shows up. -/

/-- Assumed bound on how far a later-listed run id may exceed an earlier-listed one (INFERRED; MEASURED max 345 over the 129
rows of ci/earn-webkit-smooth at --limit 400). -/
def burst : Nat := 1000

def limits : List Nat := [100, 400, 1000]

inductive Step where
  | found
  | ended
  | older
  | absent
  | grow (next : Nat)
  | exhausted
  deriving DecidableEq, Repr

def nextLimit : Nat → Option Nat
  | 100 => some 400
  | 400 => some 1000
  | _ => none

def mayHide (id : Nat) (ids : List Nat) : Bool := ids.all (fun x => decide (id ≤ x + burst))

def step (narrowed : Bool) (limit id : Nat) (ids : List Nat) : Step :=
  if id ∈ ids then .found
  else if ids.length < limit then .ended
  else if mayHide id ids then
    if narrowed then (match nextLimit limit with | some n => .grow n | none => .exhausted) else .older
  else .absent

def Bounded (L : List Nat) : Prop := L.Pairwise (fun a b => b ≤ a + burst)

theorem step_found (n : Bool) (l id : Nat) (ids : List Nat) (h : id ∈ ids) : step n l id ids = .found := by
  simp [step, h]

theorem step_ended (n : Bool) (l id : Nat) (ids : List Nat) (h : id ∉ ids) (hl : ids.length < l) :
    step n l id ids = .ended := by
  simp [step, h, hl]

theorem step_older (l id : Nat) (ids : List Nat) (h : id ∉ ids) (hl : ¬ ids.length < l) (ha : mayHide id ids = true) :
    step false l id ids = .older := by
  simp [step, h, hl, ha]

theorem step_grow (l id n : Nat) (ids : List Nat) (h : id ∉ ids) (hl : ¬ ids.length < l)
    (ha : mayHide id ids = true) (hn : nextLimit l = some n) : step true l id ids = .grow n := by
  simp [step, h, hl, ha, hn]

theorem step_exhausted (l id : Nat) (ids : List Nat) (h : id ∉ ids) (hl : ¬ ids.length < l)
    (ha : mayHide id ids = true) (hn : nextLimit l = none) : step true l id ids = .exhausted := by
  simp [step, h, hl, ha, hn]

theorem step_absent (n : Bool) (l id : Nat) (ids : List Nat) (h : id ∉ ids) (hl : ¬ ids.length < l)
    (ha : ¬ mayHide id ids = true) : step n l id ids = .absent := by
  simp [step, h, hl, ha]

theorem absent_witness (n : Bool) (l id : Nat) (ids : List Nat) (h : step n l id ids = .absent) :
    ∃ x ∈ ids, x + burst < id := by
  refine Classical.byContradiction fun hc => ?_
  have hm : mayHide id ids = true := by
    simp only [mayHide, List.all_eq_true, decide_eq_true_eq]
    intro x hx
    refine Classical.byContradiction fun hx2 => ?_
    exact hc ⟨x, hx, by omega⟩
  unfold step at h
  by_cases h1 : id ∈ ids
  · simp [h1] at h
  by_cases h2 : ids.length < l
  · simp [h1, h2] at h
  simp only [h1, h2, hm] at h
  cases n <;> simp at h <;> split at h <;> simp at h

theorem absent_never_in_burst (n : Bool) (l id : Nat) (ids : List Nat) (h : ∀ x ∈ ids, id ≤ x + burst) :
    step n l id ids ≠ .absent := by
  intro ha
  obtain ⟨x, hx, hlt⟩ := absent_witness n l id ids ha
  have := h x hx
  omega

theorem unfiltered_one_list (l id : Nat) (ids : List Nat) : ∀ n, step false l id ids ≠ .grow n := by
  intro n
  unfold step
  split <;> try simp
  split <;> try simp
  split <;> simp

theorem grow_bigger (l n : Nat) (h : nextLimit l = some n) : l < n ∧ n ∈ limits := by
  unfold nextLimit at h
  split at h <;> simp_all [limits] <;> omega

theorem grow_inv (n : Bool) (l id m : Nat) (ids : List Nat) (h : step n l id ids = .grow m) : nextLimit l = some m := by
  unfold step at h
  by_cases h1 : id ∈ ids
  · simp [h1] at h
  by_cases h2 : ids.length < l
  · simp [h1, h2] at h
  by_cases h3 : mayHide id ids = true
  · simp only [h1, h2, h3] at h
    cases n
    · simp at h
    · simp at h
      split at h <;> simp_all
  · simp [h1, h2, h3] at h

def go : Nat → Bool → Nat → Nat → (Nat → List Nat) → Option Step
  | 0, _, _, _, _ => none
  | f + 1, n, l, id, p =>
    match step n l id (p l) with
    | .grow m => go f n m id p
    | s => some s

theorem go_terminates (n : Bool) (id : Nat) (p : Nat → List Nat) : (go 3 n 100 id p).isSome = true := by
  have h1 : ∀ m, step n 100 id (p 100) = .grow m → m = 400 := fun m h => by
    have := grow_inv _ _ _ _ _ h; simpa [nextLimit] using this.symm
  have h2 : ∀ m, step n 400 id (p 400) = .grow m → m = 1000 := fun m h => by
    have := grow_inv _ _ _ _ _ h; simpa [nextLimit] using this.symm
  have h3 : ∀ m, step n 1000 id (p 1000) ≠ .grow m := fun m h => by
    have := grow_inv _ _ _ _ _ h; simp [nextLimit] at this
  cases e1 : step n 100 id (p 100) with
  | grow m =>
    have := h1 m e1; subst this
    cases e2 : step n 400 id (p 400) with
    | grow k =>
      have := h2 k e2; subst this
      cases e3 : step n 1000 id (p 1000) with
      | grow j => exact absurd e3 (h3 j)
      | _ => simp [go, e1, e2, e3]
    | _ => simp [go, e1, e2]
  | _ => simp [go, e1]

private theorem take_hides (L : List Nat) (hb : Bounded L) (id l : Nat) (hid : id ∈ L) (hn : id ∉ L.take l) :
    mayHide id (L.take l) = true := by
  have hs : (L.take l ++ L.drop l).Pairwise (fun a b => b ≤ a + burst) := by rw [List.take_append_drop]; exact hb
  rw [List.pairwise_append] at hs
  have hd : id ∈ L.drop l := by
    have : id ∈ L.take l ++ L.drop l := by rw [List.take_append_drop]; exact hid
    rcases List.mem_append.mp this with h | h
    · exact absurd h hn
    · exact h
  simp only [mayHide, List.all_eq_true, decide_eq_true_eq]
  intro x hx
  exact hs.2.2 x hx id hd

private theorem miss_not_ended (L : List Nat) (id l : Nat) (hid : id ∈ L) (hn : id ∉ L.take l) :
    ¬ (L.take l).length < l := by
  intro h
  have : L.take l = L := List.take_of_length_le (by simp [List.length_take] at h; omega)
  exact hn (by rw [this]; exact hid)

theorem present_found (L : List Nat) (hb : Bounded L) (id : Nat) (hid : id ∈ L.take 1000) :
    go 3 true 100 id (fun l => L.take l) = some .found := by
  have hL : id ∈ L := List.mem_of_mem_take hid
  have key : ∀ l, id ∉ L.take l → ∀ n, nextLimit l = some n → step true l id (L.take l) = .grow n :=
    fun l hn n h => step_grow l id n _ hn (miss_not_ended L id l hL hn) (take_hides L hb id l hL hn) h
  by_cases a : id ∈ L.take 100
  · simp [go, step_found _ _ _ _ a]
  · by_cases b : id ∈ L.take 400
    · simp [go, key 100 a 400 rfl, step_found _ _ _ _ b]
    · simp [go, key 100 a 400 rfl, key 400 b 1000 rfl, step_found _ _ _ _ hid]

def realHead : List Nat := (List.range' 40113000000 90).reverse
def realPage100 : List Nat := realHead ++ [40100783690, 40100783607, 40100783673, 40100783629, 40100783703, 40100783603, 40100783865, 40100783783, 40100783657, 40100783643]
def realPage400 : List Nat := realPage100 ++ [40100783732, 40100783604, 40100783625, 40100783587, 40100783590, 40100783678, 40100783726, 40100783656]

def cases : List (String × Bool × Nat × Nat × List Nat × Step) := [
  ("found in first list", false, 100, 7, [9, 8, 7], .found),
  ("short list ends", false, 100, 5, [9, 8, 7], .ended),
  ("short filtered list ends", true, 100, 5, [9, 8, 7], .ended),
  ("empty short list ends", false, 100, 5, [], .ended),
  ("unfiltered, id below the whole full list", false, 3, 5, [9, 8, 7], .older),
  ("filtered, id below the whole page, grow 100 to 400", true, 100, 5, (List.range' 7 100).reverse, .grow 400),
  ("filtered, id below, grow 400 to 1000", true, 400, 5, (List.range' 7 400).reverse, .grow 1000),
  ("filtered, id below at last limit", true, 1000, 5, (List.range' 7 1000).reverse, .exhausted),
  ("id far above the newest row", false, 3, 5000, [9, 8, 7], .absent),
  ("id above the page min but inside the burst margin, filtered", true, 3, 8, [9, 7, 6], .exhausted),
  ("id inside the margin, unfiltered", false, 3, 8, [9, 7, 6], .older),
  ("id exactly page min plus burst still may hide", true, 100, 1006, 6 :: (List.range' 7 99).reverse, .grow 400),
  ("id one past page min plus burst is absent", true, 100, 1007, 6 :: (List.range' 7 99).reverse, .absent),
  ("run 40100783726, limit 100: page min 40100783603 is below it, still grows", true, 100, 40100783726, realPage100, .grow 400),
  ("run 40100783726, limit 400: listed at entry 106 when captured, found", true, 400, 40100783726, realPage400, .found),
  ("run 40100783726 unfiltered, limit 100: older, not absent", false, 100, 40100783726, realPage100, .older),
  ("a run well above the real page min is absent", true, 100, 40100790000, realPage100, .absent)]

#guard cases.all fun (_, n, l, id, ids, e) => step n l id ids == e
#guard realPage100.length == 100 && realPage400.length == 108

open Lean in
def stepJson : Step → Json
  | .found => Json.mkObj [("step", "found")]
  | .ended => Json.mkObj [("step", "ended")]
  | .older => Json.mkObj [("step", "older")]
  | .absent => Json.mkObj [("step", "absent")]
  | .grow n => Json.mkObj [("step", "grow"), ("next", n)]
  | .exhausted => Json.mkObj [("step", "exhausted")]

open Lean in
def goldenText (_ : Unit := ()) : String :=
  String.join (cases.map fun (n, nr, l, id, ids, e) =>
    (Json.mkObj [("name", n), ("narrowed", nr), ("limit", l), ("id", id), ("ids", Json.arr (ids.map fun x => Json.num (JsonNumber.fromNat x)).toArray),
      ("response", stepJson e)]).compress ++ "\n")

end Fw.Ci.State
