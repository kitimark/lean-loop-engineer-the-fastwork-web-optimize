import Fw.Ops.Cache

/-! Which modules a Lake build rebuilds from a cache entry saved on another source tree, and the shortest wall time
of that rebuild (task `fwcore-rebuild-fanout`). -/
namespace Fw.Ops.Rebuild

open Fw.Ops.Cache (InCone inCone_trans Rebuilds afterBuild Entry)

/-- `s` followed by every element of `xs` not already present. -/
def addNew (s xs : List String) : List String :=
  xs.foldl (fun acc x => if acc.contains x then acc else acc ++ [x]) s

theorem mem_addNew (s xs : List String) (y : String) : y ∈ addNew s xs ↔ y ∈ s ∨ y ∈ xs := by
  induction xs generalizing s with
  | nil => simp [addNew]
  | cons x xs ih =>
    simp only [addNew, List.foldl_cons] at *
    rw [ih]
    by_cases h : s.contains x = true
    · have hx : x ∈ s := by simpa using h
      simp only [h, ite_true, List.mem_cons]
      constructor
      · rintro (h1 | h1)
        · exact Or.inl h1
        · exact Or.inr (Or.inr h1)
      · rintro (h1 | rfl | h1)
        · exact Or.inl h1
        · exact Or.inl hx
        · exact Or.inr h1
    · simp only [h, Bool.false_eq_true, ite_false, List.mem_append, List.mem_cons, List.not_mem_nil, or_false]
      exact or_assoc

/-- One closure step: add the imports of every member. -/
def step (d : String → List String) (s : List String) : List String := addNew s (s.flatMap d)

/-- Every import of every member is a member. -/
def closedB (d : String → List String) (s : List String) : Bool := s.all fun m => (d m).all s.contains

/-- Close `s` under `d`, at most `n` steps. -/
def close (d : String → List String) : Nat → List String → List String
  | 0, s => s
  | n + 1, s => if closedB d s then s else close d n (step d s)

/-- The cone of `ts` under `d`, or `none` when `n` steps do not close it. -/
def cone? (d : String → List String) (n : Nat) (ts : List String) : Option (List String) :=
  let s := close d n ts
  if closedB d s then some s else none

theorem close_sound (d : String → List String) (ts : List String) :
    ∀ (n : Nat) (s : List String), (∀ x ∈ s, InCone d ts x) → ∀ x ∈ close d n s, InCone d ts x
  | 0, _, h => h
  | n + 1, s, h => by
    simp only [close]
    split
    · exact h
    · refine close_sound d ts n _ fun x hx => ?_
      rcases (mem_addNew _ _ _).1 hx with hx | hx
      · exact h x hx
      · obtain ⟨m, hm, hxm⟩ := List.mem_flatMap.1 hx
        exact InCone.dep (h m hm) hxm

theorem closed_complete (d : String → List String) (ts s : List String) (hc : closedB d s = true)
    (hr : ∀ t ∈ ts, t ∈ s) {m : String} (h : InCone d ts m) : m ∈ s := by
  induction h with
  | root hm => exact hr _ hm
  | dep _ hd ih =>
    have := List.all_eq_true.1 hc _ ih
    simpa using List.all_eq_true.1 this _ hd

theorem close_roots (d : String → List String) :
    ∀ (n : Nat) (s : List String), ∀ t ∈ s, t ∈ close d n s
  | 0, _, _, h => h
  | n + 1, s, t, h => by
    simp only [close]
    split
    · exact h
    · exact close_roots d n _ t ((mem_addNew _ _ _).2 (Or.inl h))

theorem cone?_spec (d : String → List String) (n : Nat) (ts s : List String) (h : cone? d n ts = some s)
    (m : String) : m ∈ s ↔ InCone d ts m := by
  simp only [cone?] at h
  split at h
  · cases h
    exact ⟨close_sound d ts n ts (fun _ hx => InCone.root hx) m,
      closed_complete d ts _ (by assumption) (close_roots d n ts)⟩
  · cases h

/-- `r` lists exactly the importers of each module. -/
def Reverses (d r : String → List String) : Prop := ∀ x y, y ∈ r x ↔ x ∈ d y

theorem rev_cone (d r : String → List String) (hr : Reverses d r) (ch : List String) (m : String) :
    InCone r ch m ↔ ∃ c ∈ ch, InCone d [m] c := by
  constructor
  · intro h
    induction h with
    | root hm => exact ⟨_, hm, InCone.root (List.mem_singleton_self _)⟩
    | dep _ hd ih =>
      obtain ⟨c, hc, hp⟩ := ih
      refine ⟨c, hc, inCone_trans d _ _ ?_ hp⟩
      intro t ht
      rw [List.mem_singleton.1 ht]
      exact InCone.dep (InCone.root (List.mem_singleton_self _)) ((hr _ _).1 hd)
  · rintro ⟨c, hc, hp⟩
    have key : InCone r [c] m := by
      clear hc
      induction hp with
      | root hm => rw [List.mem_singleton.1 hm]; exact InCone.root (List.mem_singleton_self _)
      | dep _ hd ih =>
        refine inCone_trans r _ _ ?_ ih
        intro t ht
        rw [List.mem_singleton.1 ht]
        exact InCone.dep (InCone.root (List.mem_singleton_self _)) ((hr _ _).2 hd)
    exact inCone_trans r _ _ (fun t ht => by rw [List.mem_singleton.1 ht]; exact InCone.root hc) key

/-- The modules of the cone of `ts` that import a module of `ch`, or `none` when `n` steps close neither cone. -/
def rebuildSet? (d r : String → List String) (n : Nat) (ts ch : List String) : Option (List String) := do
  let down ← cone? d n ts
  let up ← cone? r n ch
  pure (down.filter up.contains)

theorem rebuildSet?_spec (d r : String → List String) (hr : Reverses d r) (n : Nat) (ts ch R : List String)
    (h : rebuildSet? d r n ts ch = some R) (m : String) :
    m ∈ R ↔ InCone d ts m ∧ ∃ c ∈ ch, InCone d [m] c := by
  simp only [rebuildSet?, Option.bind_eq_bind, Option.bind_eq_some_iff, Option.pure_def,
    Option.some.injEq] at h
  obtain ⟨down, hd, up, hu, rfl⟩ := h
  rw [List.mem_filter, cone?_spec d n ts down hd, List.contains_iff_mem, cone?_spec r n ch up hu,
    rev_cone d r hr]

/-- `tr` gives each module the trace Lake mixes from its source and its imports' traces (the legacy, non-`module`
rule, `Lake/Build/Module.lean:320-349,603@eb6cafb`). -/
def IsTrace {S H : Type} (F : S → List H → H) (src : String → S) (deps : String → List String)
    (tr : String → H) : Prop :=
  ∀ m, tr m = F (src m) ((deps m).map tr)

theorem trace_stable {S H : Type} (F : S → List H → H) (src0 src1 : String → S)
    (deps0 deps1 : String → List String) (tr0 tr1 : String → H) (rank : String → Nat)
    (hrank : ∀ m d, d ∈ deps1 m → rank d < rank m) (hd : ∀ m, src0 m = src1 m → deps0 m = deps1 m)
    (h0 : IsTrace F src0 deps0 tr0) (h1 : IsTrace F src1 deps1 tr1) :
    ∀ m, (∀ c, InCone deps1 [m] c → src0 c = src1 c) → tr0 m = tr1 m := by
  suffices H : ∀ k m, rank m < k → (∀ c, InCone deps1 [m] c → src0 c = src1 c) → tr0 m = tr1 m from
    fun m => H _ m (Nat.lt_succ_self _)
  intro k
  induction k with
  | zero => intro m hk; exact absurd hk (Nat.not_lt_zero _)
  | succ k ih =>
    intro m hk hs
    have hsm := hs m (InCone.root (List.mem_singleton_self _))
    rw [h0 m, h1 m, hsm, hd m hsm]
    congr 1
    refine List.map_congr_left fun x hx => ih x (Nat.lt_of_lt_of_le (hrank m x hx) (Nat.le_of_lt_succ hk))
      fun c hc => hs c ?_
    refine inCone_trans deps1 _ _ (fun t ht => ?_) hc
    rw [List.mem_singleton.1 ht]
    exact InCone.dep (InCone.root (List.mem_singleton_self _)) hx

theorem trace_changes {S H : Type} (F : S → List H → H)
    (hF : ∀ s s' l l', F s l = F s' l' → s = s' ∧ l = l') (src0 src1 : String → S)
    (deps0 deps1 : String → List String) (tr0 tr1 : String → H)
    (hd : ∀ m, src0 m = src1 m → deps0 m = deps1 m)
    (h0 : IsTrace F src0 deps0 tr0) (h1 : IsTrace F src1 deps1 tr1) (m c : String)
    (hp : InCone deps1 [m] c) (hc : src0 c ≠ src1 c) : tr0 m ≠ tr1 m := by
  intro he
  have all : ∀ c', InCone deps1 [m] c' → tr0 c' = tr1 c' := by
    intro c' hp'
    induction hp' with
    | root ht => rw [List.mem_singleton.1 ht]; exact he
    | @dep x y _ hy ih =>
      have e := ih
      rw [h0 x, h1 x] at e
      obtain ⟨hs, hl⟩ := hF _ _ _ _ e
      rw [hd x hs] at hl
      exact List.map_inj_left.1 hl y hy
  have e := all c hp
  rw [h0 c, h1 c] at e
  exact hc (hF _ _ _ _ e).1

theorem lake_rebuilds_in_changed_cone {S H : Type} (F : S → List H → H) (src0 src1 : String → S)
    (deps0 deps1 : String → List String) (tr0 tr1 : String → H) (rank : String → Nat)
    (hrank : ∀ m d, d ∈ deps1 m → rank d < rank m) (hd : ∀ m, src0 m = src1 m → deps0 m = deps1 m)
    (h0 : IsTrace F src0 deps0 tr0) (h1 : IsTrace F src1 deps1 tr1) (C : Entry H) (tw tj : List String)
    (m : String) (hw : (∀ c, InCone deps1 [m] c → src0 c = src1 c) → InCone deps0 tw m)
    (h : Rebuilds deps1 tr1 (afterBuild deps0 tr0 C tw) tj m) :
    InCone deps1 tj m ∧ ∃ c, InCone deps1 [m] c ∧ src0 c ≠ src1 c := by
  refine ⟨h.1, Classical.byContradiction fun hn => ?_⟩
  have hs : ∀ c, InCone deps1 [m] c → src0 c = src1 c := fun c hc =>
    Classical.byContradiction fun hne => hn ⟨c, hc, hne⟩
  exact h.2 (Or.inr ⟨m, hw hs, trace_stable F src0 src1 deps0 deps1 tr0 tr1 rank hrank hd h0 h1 m hs⟩)

/-- The largest of `l`, `0` when empty. -/
def maxOf (l : List Nat) : Nat := l.foldl max 0

theorem foldl_max_le (l : List Nat) (a b : Nat) (ha : a ≤ b) (hl : ∀ x ∈ l, x ≤ b) : l.foldl max a ≤ b := by
  induction l generalizing a with
  | nil => exact ha
  | cons x l ih =>
    exact ih _ (Nat.max_le.2 ⟨ha, hl x (List.mem_cons_self ..)⟩) fun y hy => hl y (List.mem_cons_of_mem _ hy)

/-- The value stored for `x` in a table, `0` when absent. -/
def lookup (tab : List (String × Nat)) (x : String) : Nat := ((tab.find? (·.1 == x)).map (·.2)).getD 0

theorem lookup_cases (tab : List (String × Nat)) (x : String) :
    lookup tab x = 0 ∨ ∃ p ∈ tab, p.1 = x ∧ lookup tab x = p.2 := by
  unfold lookup
  cases h : tab.find? (·.1 == x) with
  | none => exact Or.inl rfl
  | some p =>
    refine Or.inr ⟨p, List.mem_of_find?_eq_some h, ?_, rfl⟩
    simpa using List.find?_some h

/-- One relaxation: each module of `R` finishes `t m` after the latest of its imports in `R`. -/
def relax (d : String → List String) (R : List String) (t : String → Nat) (tab : List (String × Nat)) :
    List (String × Nat) :=
  R.map fun m => (m, t m + maxOf (((d m).filter R.contains).map (lookup tab)))

/-- The finish times of `R` after `n` relaxations from nothing. -/
def finishes (d : String → List String) (R : List String) (t : String → Nat) : Nat → List (String × Nat)
  | 0 => []
  | n + 1 => relax d R t (finishes d R t n)

/-- The critical path of `R`: the latest finish after `R.length` relaxations. -/
def critical (d : String → List String) (R : List String) (t : String → Nat) : Nat :=
  maxOf ((finishes d R t R.length).map (·.2))

/-- A schedule of `R` that starts each module after every import in `R` has finished. -/
def Respects (d : String → List String) (R : List String) (t start : String → Nat) : Prop :=
  ∀ m ∈ R, ∀ x ∈ d m, x ∈ R → start x + t x ≤ start m

theorem finishes_le (d : String → List String) (R : List String) (t start : String → Nat)
    (hs : Respects d R t start) : ∀ n, ∀ p ∈ finishes d R t n, p.1 ∈ R ∧ p.2 ≤ start p.1 + t p.1
  | 0, _, h => absurd h List.not_mem_nil
  | n + 1, p, h => by
    obtain ⟨m, hm, rfl⟩ := List.mem_map.1 h
    refine ⟨hm, ?_⟩
    rw [Nat.add_comm (start m)]
    refine Nat.add_le_add_left (foldl_max_le _ _ _ (Nat.zero_le _) fun y hy => ?_) _
    obtain ⟨x, hx, rfl⟩ := List.mem_map.1 hy
    obtain ⟨hxd, hxR⟩ := List.mem_filter.1 hx
    have hxR' : x ∈ R := by simpa using hxR
    rcases lookup_cases (finishes d R t n) x with h0 | ⟨q, hq, rfl, he⟩
    · rw [h0]; exact Nat.zero_le _
    · rw [he]
      exact Nat.le_trans (finishes_le d R t start hs n q hq).2 (hs m hm _ hxd hxR')

theorem critical_le_makespan (d : String → List String) (R : List String) (t start : String → Nat)
    (hs : Respects d R t start) (T : Nat) (hT : ∀ m ∈ R, start m + t m ≤ T) : critical d R t ≤ T :=
  foldl_max_le _ _ _ (Nat.zero_le _) fun y hy => by
    obtain ⟨p, hp, rfl⟩ := List.mem_map.1 hy
    have h := finishes_le d R t start hs _ p hp
    exact Nat.le_trans h.2 (hT _ h.1)

/-- The sample graph of the guards: `Main` imports `A` and `B`, both import `C`; `D` is outside `Main`'s cone. -/
def sample : List (String × List String) := [("Main", ["A", "B"]), ("A", ["C"]), ("B", ["C"]), ("C", []), ("D", ["C"])]

/-- The imports of `m` in a graph listed as pairs. -/
def imps (g : List (String × List String)) (m : String) : List String :=
  g.flatMap fun p => if p.1 == m then p.2 else []

/-- The importers of `x` in a graph listed as pairs. -/
def importers (g : List (String × List String)) (x : String) : List String :=
  (g.filter fun p => p.2.contains x).map (·.1)

theorem importers_reverses (g : List (String × List String)) : Reverses (imps g) (importers g) := by
  intro x y
  simp [imps, importers, List.mem_flatMap]
  constructor
  · rintro ⟨l, hl, hx⟩
    exact ⟨y, l, hl, rfl, hx⟩
  · rintro ⟨p, l, hl, rfl, hx⟩
    exact ⟨l, hl, hx⟩

#guard (rebuildSet? (imps sample) (importers sample) 5 ["Main"] ["C"]).map (·.length) == some 4
#guard rebuildSet? (imps sample) (importers sample) 5 ["Main"] ["A"] == some ["Main", "A"]
#guard rebuildSet? (imps sample) (importers sample) 5 ["Main"] ["D"] == some []
#guard rebuildSet? (imps sample) (importers sample) 5 ["Main"] [] == some []
#guard rebuildSet? (imps sample) (importers sample) 0 ["Main"] ["C"] == none
#guard cone? (imps sample) 5 ["A"] == some ["A", "C"]
#guard cone? (imps sample) 1 ["Main"] == none
#guard closedB (imps sample) ["A", "C"] && !closedB (imps sample) ["A"]
#guard addNew ["A"] ["B", "A", "B"] == ["A", "B"]
#guard critical (imps sample) ["Main", "A", "B", "C"] (fun m => if m == "B" then 5 else 1) == 7
#guard critical (imps sample) ["Main", "A"] (fun _ => 3) == 6
#guard critical (imps sample) [] (fun _ => 3) == 0
#guard critical (imps sample) ["Main", "C"] (fun _ => 2) == 2
#guard lookup [("A", 4)] "A" == 4 && lookup [("A", 4)] "B" == 0
#guard maxOf [3, 9, 2] == 9 && maxOf [] == 0

end Fw.Ops.Rebuild
