import Fw.Gate.Schedule

/-!
# Gate shard plan: longest processing time first over measured load units (task `gate-shard-balance`)

`Fw.Gate.Schedule` fixes how many jobs each engine gets and models a job's time as setup plus probes times one
mean per-probe cost plus whole sweeps; the probes were dealt by matrix index mod `k` in JS. Run 39101532038 showed
that the loads of one engine do not cost the same (a reduced-motion probe settles at once, a moving one waited its
whole budget), so a mean cost and an index deal leave the jobs unbalanced.

This module deals **load units** instead: unit `i < n` is probe `i` of the matrix, unit `n + j` is sweep `j`
(whole). Each unit has a measured cost (`costOf`, a missing unit costs the table's maximum: `costOf_missing`,
`costOf_le_dflt`). The plan is LPT: sort the units by cost, largest first, ties by index (`isort`), and put each on
the job that is least loaded so far, the first such job on a tie (`deal`).

* `plan_partition`: every unit runs exactly once, on one of the `m` jobs.
* `plan_makespan_bound`: Graham's bound, `m · C_max ≤ Σ c + (m - 1) max c`.
* `plan_deterministic`: the plan depends on the units only as a set, not on their order.
* `plan_valid` and `plan_verdict_eq`: the jobs run each probe and each whole sweep once, so the merged verdict is
  the unsharded one (`Fw.Gate.sharded_verdict_eq`, `Fw.Gate.Schedule.layout_merge_sound`).
-/
namespace Fw.Gate.Shard
open Fw.Gate.Schedule

/-! ## 1. The cost table -/

/-- The conservative default cost: the largest cost in the table (0 for an empty table).

A unit nobody measured is charged like the slowest unit measured. -/
def dflt (tbl : List (String × Nat)) : Nat := lmax (tbl.map (·.2))

/-- The cost of a unit: the first entry of the table with its name, else the default.

Measured where measured, conservative where not. -/
def costOf (tbl : List (String × Nat)) (u : String) : Nat :=
  match tbl.find? (·.1 == u) with
  | some p => p.2
  | none => dflt tbl

#guard costOf [("a", 5), ("b", 9)] "a" == 5
#guard costOf [("a", 5), ("b", 9)] "z" == 9
#guard costOf [] "z" == 0

/-- A unit missing from the table costs the default.

Missing units are never free. -/
theorem costOf_missing (tbl : List (String × Nat)) (u : String) (h : ∀ p ∈ tbl, p.1 ≠ u) :
    costOf tbl u = dflt tbl := by
  have : tbl.find? (·.1 == u) = none := by
    rw [List.find?_eq_none]; intro p hp; simpa using h p hp
  simp [costOf, this]

/-- Every cost, measured or defaulted, is at most the default.

The default is an upper bound of the table, so charging it never under-estimates a job. -/
theorem costOf_le_dflt (tbl : List (String × Nat)) (u : String) : costOf tbl u ≤ dflt tbl := by
  unfold costOf
  split
  · rename_i p hp
    exact le_lmax (List.mem_map.2 ⟨p, List.mem_of_find?_eq_some hp, rfl⟩)
  · exact Nat.le_refl _

/-! ## 2. Longest processing time first -/

/-- The LPT order on unit indices: larger cost first, the smaller index first on equal cost.

A strict total order on distinct indices. -/
def before (c : Nat → Nat) (a b : Nat) : Bool := decide (c b < c a) || (decide (c a = c b) && decide (a < b))

/-- The LPT order unfolded. -/
theorem before_iff (c : Nat → Nat) (a b : Nat) : before c a b = true ↔ c b < c a ∨ (c a = c b ∧ a < b) := by
  simp [before]

/-- Insert into an LPT-sorted list. -/
def ins (c : Nat → Nat) (x : Nat) : List Nat → List Nat
  | [] => [x]
  | y :: ys => if before c x y then x :: y :: ys else y :: ins c x ys

/-- Insertion sort in LPT order. -/
def isort (c : Nat → Nat) : List Nat → List Nat
  | [] => []
  | x :: xs => ins c x (isort c xs)

#guard isort (fun i => [3, 7, 7, 1].getD i 0) [0, 1, 2, 3] == [1, 2, 0, 3]

/-- The load of a job: the sum of its units' costs. -/
def load (c : Nat → Nat) (b : List Nat) : Nat := (b.map c).sum

/-- The loads of all jobs, in job order. -/
def loads (c : Nat → Nat) (bs : List (List Nat)) : List Nat := bs.map (load c)

/-- Append unit `u` to the first job whose load is `v` (no change if none is). -/
def putFirst (c : Nat → Nat) (v u : Nat) : List (List Nat) → List (List Nat)
  | [] => []
  | b :: bs => if load c b = v then (b ++ [u]) :: bs else b :: putFirst c v u bs

/-- One LPT step: put the unit on the first least-loaded job. -/
def step (c : Nat → Nat) (bs : List (List Nat)) (u : Nat) : List (List Nat) :=
  putFirst c (pickMin (loads c bs)) u bs

/-- Deal units in the given order. -/
def deal (c : Nat → Nat) (bs : List (List Nat)) (us : List Nat) : List (List Nat) := us.foldl (step c) bs

/-- **The LPT plan** of units `us` on `m` jobs: sort by cost, largest first, then deal onto `m` empty jobs.

Big units first, each on the job that frees first. -/
def lpt (c : Nat → Nat) (m : Nat) (us : List Nat) : List (List Nat) :=
  deal c (List.replicate m []) (isort c us)

#guard lpt (fun i => [5, 4, 3, 3, 3].getD i 0) 2 [0, 1, 2, 3, 4] == [[0, 3], [1, 2, 4]]
#guard lpt (fun i => [5, 4, 3, 3, 3].getD i 0) 2 [4, 3, 2, 1, 0] == [[0, 3], [1, 2, 4]]
#guard lpt (fun _ => 1) 3 [] == [[], [], []]

/-! ### Sorting -/

/-- Inserting only adds the element. -/
theorem ins_perm (c : Nat → Nat) (x : Nat) : ∀ l : List Nat, (ins c x l).Perm (x :: l)
  | [] => List.Perm.refl _
  | y :: ys => by
    unfold ins
    split
    · exact List.Perm.refl _
    · exact ((ins_perm c x ys).cons y).trans (List.Perm.swap x y ys)

/-- Sorting only reorders. -/
theorem isort_perm (c : Nat → Nat) : ∀ l : List Nat, (isort c l).Perm l
  | [] => List.Perm.refl _
  | x :: xs => (ins_perm c x (isort c xs)).trans ((isort_perm c xs).cons x)

/-- The LPT order is transitive. -/
theorem before_trans (c : Nat → Nat) {a b d : Nat} (h1 : before c a b = true) (h2 : before c b d = true) :
    before c a d = true := by
  rw [before_iff] at *; omega

/-- Two distinct indices are ordered one way or the other. -/
theorem before_total (c : Nat → Nat) {a b : Nat} (h : a ≠ b) : before c a b = true ∨ before c b a = true := by
  rw [before_iff, before_iff]; omega

/-- The LPT order is asymmetric. -/
theorem before_asymm (c : Nat → Nat) {a b : Nat} (h1 : before c a b = true) : ¬ before c b a = true := by
  rw [before_iff] at *; omega

/-- Inserting a new element keeps a sorted list sorted. -/
theorem ins_sorted (c : Nat → Nat) (x : Nat) : ∀ l : List Nat, x ∉ l → l.Pairwise (fun a b => before c a b = true) →
    (ins c x l).Pairwise (fun a b => before c a b = true)
  | [], _, _ => List.pairwise_singleton _ _
  | y :: ys, hx, hs => by
    unfold ins
    have hxy : x ≠ y := fun h => hx (h ▸ List.mem_cons_self)
    have hys : x ∉ ys := fun h => hx (List.mem_cons_of_mem _ h)
    rw [List.pairwise_cons] at hs
    split
    · rename_i hb
      refine List.pairwise_cons.2 ⟨?_, List.pairwise_cons.2 hs⟩
      intro z hz
      rcases List.mem_cons.1 hz with rfl | hz
      · exact hb
      · exact before_trans c hb (hs.1 z hz)
    · rename_i hb
      have hyx : before c y x = true := by
        rcases before_total c hxy with h | h
        · exact absurd h hb
        · exact h
      refine List.pairwise_cons.2 ⟨?_, ins_sorted c x ys hys hs.2⟩
      intro z hz
      rcases List.mem_cons.1 ((ins_perm c x ys).mem_iff.1 hz) with rfl | hz
      · exact hyx
      · exact hs.1 z hz

/-- Sorting distinct indices gives a strictly LPT-ordered list. -/
theorem isort_sorted (c : Nat → Nat) : ∀ l : List Nat, l.Nodup →
    (isort c l).Pairwise (fun a b => before c a b = true)
  | [], _ => List.Pairwise.nil
  | x :: xs, h => by
    rw [List.nodup_cons] at h
    exact ins_sorted c x _ (fun hm => h.1 ((isort_perm c xs).mem_iff.1 hm)) (isort_sorted c xs h.2)

/-- Two lists sorted by an asymmetric relation that are permutations of each other are equal. -/
theorem eq_of_perm_of_pairwise {R : Nat → Nat → Prop} (hR : ∀ a b, R a b → ¬ R b a) :
    ∀ {l₁ l₂ : List Nat}, l₁.Perm l₂ → l₁.Pairwise R → l₂.Pairwise R → l₁ = l₂
  | [], l₂, hp, _, _ => List.Perm.nil_eq hp
  | a :: t, [], hp, _, _ => absurd hp.length_eq (by simp)
  | a :: t, b :: s, hp, h1, h2 => by
    rw [List.pairwise_cons] at h1 h2
    by_cases hab : a = b
    · subst hab
      rw [eq_of_perm_of_pairwise hR (List.Perm.cons_inv hp) h1.2 h2.2]
    · have ha : a ∈ s := by
        have := hp.mem_iff.1 List.mem_cons_self
        rcases List.mem_cons.1 this with h | h
        · exact absurd h hab
        · exact h
      have hb : b ∈ t := by
        have := hp.mem_iff.2 List.mem_cons_self
        rcases List.mem_cons.1 this with h | h
        · exact absurd h.symm hab
        · exact h
      exact absurd (h1.1 b hb) (hR _ _ (h2.1 a ha))

/-- Sorting distinct indices does not depend on their order. -/
theorem isort_eq_of_perm (c : Nat → Nat) {l₁ l₂ : List Nat} (hp : l₁.Perm l₂) (hn : l₁.Nodup) :
    isort c l₁ = isort c l₂ :=
  eq_of_perm_of_pairwise (fun _ _ h => before_asymm c h)
    (((isort_perm c l₁).trans hp).trans (isort_perm c l₂).symm)
    (isort_sorted c l₁ hn) (isort_sorted c l₂ (hp.nodup_iff.1 hn))

/-- **The plan is deterministic in the set of units**: dealing the same distinct units listed in any order gives
the same jobs, unit for unit.

The plan never depends on the order the units were listed in. -/
theorem plan_deterministic (c : Nat → Nat) (m : Nat) {us₁ us₂ : List Nat} (hp : us₁.Perm us₂) (hn : us₁.Nodup) :
    lpt c m us₁ = lpt c m us₂ := by
  unfold lpt; rw [isort_eq_of_perm c hp hn]

/-! ### Dealing -/

/-- Putting a unit keeps the number of jobs. -/
theorem putFirst_length (c : Nat → Nat) (v u : Nat) : ∀ bs : List (List Nat), (putFirst c v u bs).length = bs.length
  | [] => rfl
  | b :: bs => by unfold putFirst; split <;> simp [putFirst_length c v u bs]

/-- When some job has load `v`, `putFirst` adds exactly the unit `u`. -/
theorem putFirst_flatten (c : Nat → Nat) (v u : Nat) : ∀ bs : List (List Nat), v ∈ loads c bs →
    (putFirst c v u bs).flatten.Perm (u :: bs.flatten)
  | [], h => by simp [loads] at h
  | b :: bs, h => by
    unfold putFirst
    split
    · simp only [List.flatten_cons, List.append_assoc, List.singleton_append]
      exact List.perm_middle
    · rename_i hb
      have h' : v ∈ loads c bs := by
        simp only [loads, List.map_cons, List.mem_cons] at h
        rcases h with h | h
        · exact absurd h.symm hb
        · exact h
      simp only [List.flatten_cons]
      exact ((putFirst_flatten c v u bs h').append_left b).trans List.perm_middle

/-- When some job has load `v`, `putFirst` raises one load `v` to `v + c(u)`.

(`∖_1` removes the first occurrence.) -/
theorem putFirst_loads (c : Nat → Nat) (v u : Nat) : ∀ bs : List (List Nat), v ∈ loads c bs →
    (loads c (putFirst c v u bs)).Perm ((v + c u) :: (loads c bs).erase v)
  | [], h => by simp [loads] at h
  | b :: bs, h => by
    unfold putFirst
    split
    · rename_i hb
      simp only [loads, List.map_cons, load, List.map_append, List.sum_append, List.map_cons, List.map_nil,
        List.sum_cons, List.sum_nil] at hb ⊢
      rw [hb, List.erase_cons_head]
      simp
    · rename_i hb
      have h' : v ∈ loads c bs := by
        simp only [loads, List.map_cons, List.mem_cons] at h
        rcases h with h | h
        · exact absurd h.symm hb
        · exact h
      simp only [loads, List.map_cons] at h' ⊢
      rw [List.erase_cons_tail (by simpa using hb)]
      exact ((putFirst_loads c v u bs h').cons _).trans (List.Perm.swap _ _ _)

/-- The maximum does not depend on the order. -/
theorem lmax_perm {l₁ l₂ : List Nat} (h : l₁.Perm l₂) : lmax l₁ = lmax l₂ := by
  induction h with
  | nil => rfl
  | cons x _ ih => simp [lmax, ih]
  | swap x y l => simp only [lmax]; omega
  | trans _ _ ih1 ih2 => exact ih1.trans ih2

/-- A non-empty list of jobs has a non-empty list of loads. -/
theorem loads_ne (c : Nat → Nat) {bs : List (List Nat)} (h : bs ≠ []) : loads c bs ≠ [] := by
  simpa [loads] using h

/-- One LPT step changes the loads as list scheduling's `place` does (up to the order of the jobs). -/
theorem step_loads (c : Nat → Nat) (bs : List (List Nat)) (u : Nat) (h : bs ≠ []) :
    (loads c (step c bs u)).Perm (place (loads c bs) (c u)) :=
  putFirst_loads c _ u bs (pickMin_mem (loads_ne c h))

/-- A step keeps the number of jobs. -/
theorem step_length (c : Nat → Nat) (bs : List (List Nat)) (u : Nat) : (step c bs u).length = bs.length :=
  putFirst_length c _ u bs

/-- A step on at least one job adds exactly the unit. -/
theorem step_flatten (c : Nat → Nat) (bs : List (List Nat)) (u : Nat) (h : bs ≠ []) :
    (step c bs u).flatten.Perm (u :: bs.flatten) :=
  putFirst_flatten c _ u bs (pickMin_mem (loads_ne c h))

/-- Dealing keeps the number of jobs. -/
theorem deal_length (c : Nat → Nat) : ∀ (us : List Nat) (bs : List (List Nat)), (deal c bs us).length = bs.length
  | [], _ => rfl
  | u :: us, bs => by
    simp only [deal, List.foldl_cons]
    exact (deal_length c us (step c bs u)).trans (step_length c bs u)

/-- Dealing onto at least one job adds exactly the dealt units. -/
theorem deal_flatten (c : Nat → Nat) : ∀ (us : List Nat) (bs : List (List Nat)), bs ≠ [] →
    (deal c bs us).flatten.Perm (bs.flatten ++ us)
  | [], bs, _ => by simp [deal]
  | u :: us, bs, h => by
    simp only [deal, List.foldl_cons]
    have hne : step c bs u ≠ [] := by
      intro he; have := step_length c bs u; rw [he] at this; cases bs <;> simp_all
    refine (deal_flatten c us (step c bs u) hne).trans ?_
    refine ((step_flatten c bs u h).append_right us).trans ?_
    simp only [List.cons_append]
    exact List.perm_middle.symm

/-- **Every unit runs exactly once**: with at least one job the plan has `m` jobs and its units, all jobs
together, are a permutation of the units.

No unit is dropped or run twice. -/
theorem plan_partition (c : Nat → Nat) (m : Nat) (hm : 0 < m) (us : List Nat) :
    (lpt c m us).length = m ∧ (lpt c m us).flatten.Perm us := by
  refine ⟨by simp [lpt, deal_length], ?_⟩
  have hne : List.replicate m ([] : List Nat) ≠ [] := by
    cases m with
    | zero => omega
    | succ m => simp [List.replicate_succ]
  have := deal_flatten c (isort c us) _ hne
  simp only [List.flatten_replicate_nil, List.nil_append] at this
  exact this.trans (isort_perm c us)

/-- Graham's invariant of the deal on `k + 1` jobs.

The `max` of the empty list is 0. -/
theorem deal_inv (c : Nat → Nat) (k : Nat) : ∀ (us : List Nat) (bs : List (List Nat)) (M : Nat),
    bs.length = k + 1 → (k + 1) * lmax (loads c bs) ≤ (loads c bs).sum + k * M →
    (k + 1) * lmax (loads c (deal c bs us)) ≤ (loads c bs).sum + (us.map c).sum + k * max M (lmax (us.map c))
  | [], bs, M, _, h => by
    simp only [deal, List.foldl_nil, List.map_nil, List.sum_nil, Nat.add_zero, lmax]
    have : k * M ≤ k * max M 0 := Nat.mul_le_mul_left k (Nat.le_max_left _ _)
    omega
  | u :: us, bs, M, hlen, hinv => by
    have hne : bs ≠ [] := by intro h; subst h; simp at hlen
    have hl : (loads c bs).length = k + 1 := by simpa [loads] using hlen
    have hp := step_loads c bs u hne
    have h1 := place_inv (loads c bs) k M (max M (c u)) (c u) hl hinv (Nat.le_max_left _ _) (Nat.le_max_right _ _)
    rw [← lmax_perm hp, ← hp.sum_nat] at h1
    have hlen' : (step c bs u).length = k + 1 := (step_length c bs u).trans hlen
    have h2 := deal_inv c k us (step c bs u) (max M (c u)) hlen' h1
    rw [hp.sum_nat, place_sum _ _ (loads_ne c hne)] at h2
    have e : max (max M (c u)) (lmax (us.map c)) = max M (lmax (c u :: us.map c)) := by
      simp only [lmax]; omega
    rw [e] at h2
    simp only [deal, List.foldl_cons, List.map_cons, List.sum_cons]
    simp only [deal] at h2
    omega

/-- The maximum cost does not depend on the order of the units. -/
theorem lmax_perm_map (c : Nat → Nat) {l₁ l₂ : List Nat} (h : l₁.Perm l₂) : lmax (l₁.map c) = lmax (l₂.map c) :=
  lmax_perm (h.map c)

/-- **Graham's bound for the LPT plan.** On `m ≥ 1` jobs the most loaded job carries at most the mean load plus
`(1 - 1/m)` of the largest unit.

No job is longer than the average plus one unit. -/
theorem plan_makespan_bound (c : Nat → Nat) (m : Nat) (hm : 0 < m) (us : List Nat) :
    m * lmax (loads c (lpt c m us)) ≤ (us.map c).sum + (m - 1) * lmax (us.map c) := by
  obtain ⟨k, rfl⟩ : ∃ k, m = k + 1 := ⟨m - 1, by omega⟩
  have e0 : loads c (List.replicate (k + 1) []) = List.replicate (k + 1) 0 := by
    simp [loads, load, List.map_replicate]
  have hz : ∀ n, (List.replicate n 0).sum = 0 := by
    intro n
    induction n with
    | zero => rfl
    | succ n ih => rw [List.replicate_succ, List.sum_cons, ih]
  have h0 : (k + 1) * lmax (loads c (List.replicate (k + 1) [])) ≤ (loads c (List.replicate (k + 1) [])).sum + k * 0 := by
    rw [e0, lmax_replicate_zero, hz]; simp
  have h := deal_inv c k (isort c us) _ 0 (by simp) h0
  have hs : ((isort c us).map c).sum = (us.map c).sum := ((isort_perm c us).map c).sum_nat
  have hx : lmax ((isort c us).map c) = lmax (us.map c) := lmax_perm_map c (isort_perm c us)
  rw [e0, hz, hs, hx, Nat.zero_max, Nat.zero_add] at h
  simpa [lpt] using h

/-! ## 3. The units of one engine: the probes, then the whole sweeps -/

/-- The units of an engine with `n` probes and `w` sweeps: indices `0, ..., n + w - 1`. -/
def units (n w : Nat) : List Nat := List.range (n + w)

/-- The probe a unit stands for: unit `i` is probe `S_i` when `i < |S|`. -/
def probeOf {α : Type} (S : List α) (i : Nat) : Option α := S[i]?

/-- The sweep a unit stands for: unit `n + j` is sweep `W_j`. -/
def sweepOf {β : Type} (n : Nat) (W : List β) (i : Nat) : Option β := if n ≤ i then W[i - n]? else none

#guard (units 2 2).filterMap (probeOf ["p0", "p1"]) == ["p0", "p1"]
#guard (units 2 2).filterMap (sweepOf 2 ["w0", "w1"]) == ["w0", "w1"]

/-- `filterMap` commutes with flattening. -/
theorem filterMap_flatten_map {γ : Type} (f : Nat → Option γ) :
    ∀ bs : List (List Nat), (bs.map (·.filterMap f)).flatten = bs.flatten.filterMap f
  | [] => rfl
  | b :: bs => by
    simp only [List.map_cons, List.flatten_cons, List.filterMap_append, filterMap_flatten_map f bs]

/-- Reading indices `0, ..., n - 1` of `S` gives the first `n` elements. -/
theorem range_filterMap_take {α : Type} (S : List α) : ∀ n, (List.range n).filterMap (fun i => S[i]?) = S.take n
  | 0 => rfl
  | n + 1 => by
    rw [List.range_succ, List.filterMap_append, range_filterMap_take S n, List.take_add_one]
    congr 1

/-- Reading all indices of `S` gives `S`. -/
theorem range_filterMap_getElem {α : Type} (S : List α) : (List.range S.length).filterMap (fun i => S[i]?) = S := by
  rw [range_filterMap_take, List.take_length]

/-- The probe units, in order, are the probes. -/
theorem units_probes {α : Type} (S : List α) (w : Nat) : (units S.length w).filterMap (probeOf S) = S := by
  rw [units, List.range_add, List.filterMap_append]
  have h2 : ((List.range w).map (S.length + ·)).filterMap (probeOf S) = [] := by
    rw [List.filterMap_eq_nil_iff]
    intro i hi
    obtain ⟨j, _, rfl⟩ := List.mem_map.1 hi
    simp [probeOf]
  rw [h2, List.append_nil]
  exact range_filterMap_getElem S

/-- The sweep units, in order, are the sweeps. -/
theorem units_sweeps {β : Type} (n : Nat) (W : List β) : (units n W.length).filterMap (sweepOf n W) = W := by
  rw [units, List.range_add, List.filterMap_append]
  have h1 : (List.range n).filterMap (sweepOf n W) = [] := by
    rw [List.filterMap_eq_nil_iff]
    intro i hi
    rw [List.mem_range] at hi
    simp [sweepOf]; omega
  rw [h1, List.nil_append, List.filterMap_map]
  have hf : (sweepOf n W ∘ (n + ·)) = (fun i => W[i]?) := by
    funext i; simp [sweepOf]
  rw [hf]
  exact range_filterMap_getElem W

/-- **The shard plan keeps every verdict.** Deal the units of probes `S` and whole sweeps `K` with LPT on `m ≥ 1`
jobs, and let job `j` run the probes `S_j` and sweeps `K_j` of its units. Every part's verdict over the jobs equals
its verdict over the unsharded run, for every cost function `c`.

Costs move work between jobs, never a verdict. -/
theorem plan_verdict_eq {κ : Type} [DecidableEq κ] (reach : Fw.Site.Breakpoints.Env → Option Fw.Gate.Reason)
    (key : Fw.Site.Breakpoints.Env → κ) (hv : List κ → Fw.Gate.Verdict) (S : List _) (K : List Fw.Gate.Sweep)
    (c : Nat → Nat) (m : Nat) (hm : 0 < m) :
    Fw.Gate.scopedVerdict reach key hv
        ((lpt c m (units S.length K.length)).map (·.filterMap (probeOf S))).flatten
        ((lpt c m (units S.length K.length)).map (·.filterMap (sweepOf S.length K))).flatten
      = Fw.Gate.scopedVerdict reach key hv S K := by
  have hp := (plan_partition c m hm (units S.length K.length)).2
  apply Fw.Gate.sharded_verdict_eq
  · rw [filterMap_flatten_map]
    exact (hp.filterMap _).trans (List.Perm.of_eq (units_probes S K.length))
  · rw [filterMap_flatten_map]
    exact (hp.filterMap _).trans (List.Perm.of_eq (units_sweeps S.length K))

/-- The job a set of units makes for engine `e`: its probe count and its whole sweeps, in unit order. -/
def jobOf (e : Eng) (n : Nat) (b : List Nat) : Job :=
  ⟨e, (b.filter (· < n)).length, b.filterMap (sweepOf n Sw.all)⟩

/-- The units below `n` are the probe units. -/
theorem units_filter_lt (n w : Nat) : (units n w).filter (· < n) = List.range n := by
  rw [units, List.range_add, List.filter_append]
  have h1 : (List.range n).filter (· < n) = List.range n := by
    rw [List.filter_eq_self]; intro i hi; simpa using List.mem_range.1 hi
  have h2 : ((List.range w).map (n + ·)).filter (· < n) = [] := by
    rw [List.filter_eq_nil_iff]; intro i hi
    obtain ⟨j, _, rfl⟩ := List.mem_map.1 hi
    simp
  rw [h1, h2, List.append_nil]

/-- Counting a property job by job counts it over all jobs. -/
theorem sum_filter_length (p : Nat → Bool) :
    ∀ bs : List (List Nat), (bs.map fun b => (b.filter p).length).sum = (bs.flatten.filter p).length
  | [] => rfl
  | b :: bs => by simp [List.filter_append, sum_filter_length p bs]

/-- The sweeps of the jobs, in job order, are the sweep units of the plan. -/
theorem jobs_sweeps (e : Eng) (n : Nat) : ∀ bs : List (List Nat),
    (bs.map (jobOf e n)).flatMap Job.sweeps = (bs.map (·.filterMap (sweepOf n Sw.all))).flatten
  | [] => rfl
  | b :: bs => by
    simp only [List.map_cons, List.flatMap_cons, List.flatten_cons, jobs_sweeps e n bs, jobOf]

/-- **The LPT plan is a valid layout** of the 124 probes and four whole sweeps of an engine, so the by-id merge of its
run files is the unsharded run (`layout_merge_sound`).

Each probe and each whole sweep is in exactly one job. -/
theorem plan_valid (c : Nat → Nat) (m : Nat) (hm : 0 < m) (e : Eng) :
    ValidEng ((lpt c m (units probesPerEngine Sw.all.length)).map (jobOf e probesPerEngine)) := by
  have hp := (plan_partition c m hm (units probesPerEngine Sw.all.length)).2
  constructor
  · have : ((lpt c m (units probesPerEngine Sw.all.length)).map (jobOf e probesPerEngine)).map Job.probes
        = (lpt c m (units probesPerEngine Sw.all.length)).map fun b => (b.filter (· < probesPerEngine)).length := by
      simp [jobOf]
    rw [this, sum_filter_length, (hp.filter _).length_eq, units_filter_lt]
    simp [probesPerEngine]
  · rw [jobs_sweeps, filterMap_flatten_map]
    exact (hp.filterMap _).trans (List.Perm.of_eq (units_sweeps probesPerEngine Sw.all))

/-! ## 4. The plan of both engines: measured costs, job counts, Graham's bound for the pool -/

/-- The measured costs of one engine, in milliseconds: the fixed cost of a job and the cost table of its units
(probe ids and the sweep names `desktop`, `phone`, `touch`, `pain`).
-/
structure EngCosts where
  setup : Nat
  costs : List (String × Nat)
deriving Repr

/-- The measured costs of both engines. -/
structure Costs where
  chromium : EngCosts
  webkit : EngCosts
deriving Repr

/-- The costs of one engine. -/
def Costs.of (C : Costs) : Eng → EngCosts
  | .chromium => C.chromium
  | .webkit => C.webkit

/-- The name of a sweep unit in the cost table and the golden file. -/
def swName : Sw → String
  | .desktop => "desktop"
  | .phone => "phone"
  | .touch => "touch"
  | .pain => "pain"

/-- The names of an engine's units: the probe ids in matrix order, then the four sweeps in spec order. -/
def unitNames (ids : List String) : List String := ids ++ Sw.all.map swName

/-- The cost vector of an engine's units, computed once per plan: entry `i` is the cost of unit name `i`. -/
def costVec (T : EngCosts) (ids : List String) : Array Nat := ((unitNames ids).map (costOf T.costs)).toArray

/-- The cost of unit `i` of an engine: its name's entry in the table, the table's maximum if it has none. -/
def unitCost (T : EngCosts) (ids : List String) (i : Nat) : Nat := (costVec T ids).getD i (dflt T.costs)

#guard unitCost { setup := 0, costs := [("a", 5), ("desktop", 9)] } ["a", "b"] 0 == 5
#guard unitCost { setup := 0, costs := [("a", 5), ("desktop", 9)] } ["a", "b"] 1 == 9
#guard unitCost { setup := 0, costs := [("a", 5), ("desktop", 7)] } ["a", "b"] 2 == 7
#guard unitCost { setup := 0, costs := [("a", 5), ("desktop", 7)] } ["a", "b"] 99 == 7

/-- The LPT plan of one engine on `k` jobs (the `let`s share one cost vector; `engPlan_eq`). -/
def engPlan (T : EngCosts) (ids : List String) (k : Nat) : List (List Nat) :=
  let v := costVec T ids
  let d := dflt T.costs
  lpt (fun i => v.getD i d) k (units ids.length Sw.all.length)

/-- `engPlan` is LPT over `unitCost`. -/
theorem engPlan_eq (T : EngCosts) (ids : List String) (k : Nat) :
    engPlan T ids k = lpt (unitCost T ids) k (units ids.length Sw.all.length) := rfl

/-- The durations of one engine's jobs: setup plus the job's load (`engDurs_eq`). -/
def engDurs (T : EngCosts) (ids : List String) (k : Nat) : List Nat :=
  let v := costVec T ids
  let d := dflt T.costs
  let c := fun i => v.getD i d
  (lpt c k (units ids.length Sw.all.length)).map fun b => T.setup + load c b

/-- `engDurs` is setup plus the `unitCost` load of each job of `engPlan`. -/
theorem engDurs_eq (T : EngCosts) (ids : List String) (k : Nat) :
    engDurs T ids k = (engPlan T ids k).map fun b => T.setup + load (unitCost T ids) b := rfl

/-- The job counts considered, as an ordered list: 1 to 8 jobs per engine, Chromium's count first, in lexicographic order.
`chooseK` takes the first pair on a tie, so this order is part of the answer.
-/
def kCands : List (Nat × Nat) := (List.range 8).flatMap fun a => (List.range 8).map fun b => (a + 1, b + 1)

/-- The durations of all jobs of a run: Chromium's, then WebKit's. -/
def shardDurs (C : Costs) (ids : List String) (kk : Nat × Nat) : List Nat :=
  engDurs C.chromium ids kk.1 ++ engDurs C.webkit ids kk.2

/-- Graham's bound (times `m`) for `r` concurrent runs of this plan on `m` free runners. -/
def shardBound (C : Costs) (ids : List String) (m r : Nat) (kk : Nat × Nat) : Nat :=
  let ds := shardDurs C ids kk
  r * ds.sum + (m - 1) * lmax ds

/-- The job durations of one engine for `k = 1, ..., 8` jobs (entry `k - 1`). -/
def durTab (T : EngCosts) (ids : List String) : List (List Nat) := (List.range 8).map fun a => engDurs T ids (a + 1)

/-- Graham's bound from the two duration tables (`boundOf_eq`: equal to `shardBound` on every candidate).

(An index past the end of a table reads the empty list.) -/
def boundOf (tc tw : List (List Nat)) (m r : Nat) (kk : Nat × Nat) : Nat :=
  let ds := tc.getD (kk.1 - 1) [] ++ tw.getD (kk.2 - 1) []
  r * ds.sum + (m - 1) * lmax ds

/-- **The job counts**: the pair of `kCands` with the least bound, the first such pair on a tie.

More jobs pay more setups; fewer jobs run longer. Computed from one duration table per engine (`durTab`,
`boundOf`), so each plan is dealt once; `chooseK_eq` states it as the argmin of `shardBound`. -/
def chooseK (C : Costs) (ids : List String) (m r : Nat) : Nat × Nat :=
  let tc := durTab C.chromium ids
  let tw := durTab C.webkit ids
  argminBy (boundOf tc tw m r) (1, 1) kCands

/-- Every candidate has at least one job per engine. -/
theorem kCands_pos : ∀ kk ∈ kCands, 0 < kk.1 ∧ 0 < kk.2 := by
  intro kk h
  simp only [kCands, List.mem_flatMap, List.mem_map, List.mem_range] at h
  obtain ⟨a, _, b, _, rfl⟩ := h
  exact ⟨Nat.succ_pos _, Nat.succ_pos _⟩

/-- Every candidate has at most eight jobs per engine. -/
theorem kCands_le : ∀ kk ∈ kCands, kk.1 ≤ 8 ∧ kk.2 ≤ 8 := by
  intro kk h
  simp only [kCands, List.mem_flatMap, List.mem_map, List.mem_range] at h
  obtain ⟨a, ha, b, hb, rfl⟩ := h
  exact ⟨ha, hb⟩

/-- Entry `k - 1` of the duration table is the plan on `k` jobs, for `1 ≤ k ≤ 8`. -/
theorem durTab_getD (T : EngCosts) (ids : List String) (k : Nat) (h1 : 0 < k) (h8 : k ≤ 8) :
    (durTab T ids).getD (k - 1) [] = engDurs T ids k := by
  unfold durTab
  rw [List.getD_eq_getElem?_getD, List.getElem?_map, List.getElem?_range (by omega)]
  simp only [Option.map_some, Option.getD_some]
  congr 1
  omega

/-- On every candidate the table bound is `shardBound`. -/
theorem boundOf_eq (C : Costs) (ids : List String) (m r : Nat) :
    ∀ kk ∈ kCands, boundOf (durTab C.chromium ids) (durTab C.webkit ids) m r kk = shardBound C ids m r kk := by
  intro kk h
  have hp := kCands_pos kk h
  have hl := kCands_le kk h
  simp only [boundOf, shardBound, shardDurs, durTab_getD _ _ _ hp.1 hl.1, durTab_getD _ _ _ hp.2 hl.2]

/-- `argminBy` depends only on the values of `f` on the start and the list. -/
theorem argminBy_congr {α : Type} (f g : α → Nat) :
    ∀ (xs : List α) (b : α), (∀ x, x = b ∨ x ∈ xs → f x = g x) → argminBy f b xs = argminBy g b xs := by
  intro xs
  induction xs with
  | nil => intro b _; rfl
  | cons x xs ih =>
    intro b h
    have hx : f x = g x := h x (Or.inr List.mem_cons_self)
    have hb : f b = g b := h b (Or.inl rfl)
    simp only [argminBy, hx, hb]
    apply ih
    intro y hy
    rcases hy with rfl | hy
    · split
      · exact h _ (Or.inr List.mem_cons_self)
      · exact h _ (Or.inl rfl)
    · exact h y (Or.inr (List.mem_cons_of_mem _ hy))

/-- `chooseK` is the argmin of `shardBound` over `kCands`, starting from `(1, 1)`. -/
theorem chooseK_eq (C : Costs) (ids : List String) (m r : Nat) :
    chooseK C ids m r = argminBy (shardBound C ids m r) (1, 1) kCands := by
  apply argminBy_congr
  intro x hx
  rcases hx with rfl | hx
  · exact boundOf_eq C ids m r (1, 1) (by decide)
  · exact boundOf_eq C ids m r x hx

/-- The chosen counts are in range and have the least bound of all candidates. -/
theorem chooseK_spec (C : Costs) (ids : List String) (m r : Nat) :
    (0 < (chooseK C ids m r).1 ∧ 0 < (chooseK C ids m r).2) ∧
    ∀ kk ∈ kCands, shardBound C ids m r (chooseK C ids m r) ≤ shardBound C ids m r kk := by
  rw [chooseK_eq]
  refine ⟨?_, (argminBy_le (shardBound C ids m r) kCands (1, 1)).2⟩
  rcases argminBy_mem (shardBound C ids m r) kCands (1, 1) with h | h
  · rw [h]; exact ⟨Nat.one_pos, Nat.one_pos⟩
  · exact kCands_pos _ h

/-- **The pool finishes by the bound**: list scheduling of `r` concurrent runs of the plan on `m ≥ 1` runners. -/
theorem shardBound_sound (C : Costs) (ids : List String) (m : Nat) (hm : 0 < m) (r : Nat) (kk : Nat × Nat) :
    m * makespan m (copies r (shardDurs C ids kk)) ≤ shardBound C ids m r kk :=
  graham_runs m hm r (shardDurs C ids kk)

/-- **The chosen plan of each engine is valid** (every probe and every whole sweep once, so the merged verdict
is the unsharded one: `layout_merge_sound`, `plan_verdict_eq`).
-/
theorem chosen_valid (C : Costs) (ids : List String) (hids : ids.length = probesPerEngine) (m r : Nat) :
    ValidEng ((engPlan C.chromium ids (chooseK C ids m r).1).map (jobOf .chromium probesPerEngine)) ∧
    ValidEng ((engPlan C.webkit ids (chooseK C ids m r).2).map (jobOf .webkit probesPerEngine)) := by
  have hk := (chooseK_spec C ids m r).1
  rw [engPlan_eq, engPlan_eq, hids]
  exact ⟨plan_valid _ _ hk.1 .chromium, plan_valid _ _ hk.2 .webkit⟩

end Fw.Gate.Shard
