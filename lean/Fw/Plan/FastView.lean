import Std.Data.HashMap
import Fw.Plan.Core
/-!
# A fast board plan: the critical path from hash indexes

`Fw.Plan.view` is the specification of the board plan. Two of its parts cost more than linear in the number of rows:
`criticalPath` builds its table `tab` with fuel `|ts|`, and each round scans the rows for the dependents of every task
and scans the table for every lookup (cubic overall). This module computes the same value from two indexes and stops
when a round changes nothing.

* `depIdx_get`: the dependents index answers `dependents ts x` for every task id.
* `mkMap_get`: the table index answers `look`.
* `stepF_eq`: one round from the indexes is one round of `tab`.
* `fastTabAux_eq`: stopping at a round that changes nothing loses nothing, because a round is a function of the
  previous table, so a repeated table repeats forever.
* `fastCriticalPath_eq`: the fast critical path is `criticalPath`.
-/
namespace Fw.Plan

/-! ## The dependents index -/

/-- The distinct members of a list (each member once). -/
def dd : List String → List String
  | [] => []
  | x :: xs => x :: (dd xs).filter (· != x)

theorem mem_dd {x : String} : ∀ {l : List String}, x ∈ dd l ↔ x ∈ l
  | [] => by simp [dd]
  | y :: ys => by
    simp only [dd, List.mem_cons, List.mem_filter, mem_dd (l := ys), bne_iff_ne, ne_eq]
    by_cases h : x = y <;> simp [h]

theorem nodup_dd : ∀ l : List String, (dd l).Nodup
  | [] => by simp [dd]
  | y :: ys => by
    simp only [dd, List.nodup_cons, List.mem_filter]
    exact ⟨by simp, (nodup_dd ys).filter _⟩

/-- Add `t` to the dependents list of each of its distinct deps, in front. -/
def addDeps (t : Task) (m : Std.HashMap String (List String)) : Std.HashMap String (List String) :=
  (dd t.deps).foldl (fun m d => m.insert d (t.id :: (m[d]?).getD [])) m

/-- Distinct dep lists add `t` once to each listed dep and touch no other entry. -/
theorem foldl_addDeps (t : Task) : ∀ (ds : List String), ds.Nodup → ∀ (m : Std.HashMap String (List String)) (x : String),
    ((ds.foldl (fun m d => m.insert d (t.id :: (m[d]?).getD [])) m)[x]?).getD [] =
      if x ∈ ds then t.id :: (m[x]?).getD [] else (m[x]?).getD []
  | [], _, m, x => by simp
  | d :: ds, hn, m, x => by
    rw [List.foldl_cons, foldl_addDeps t ds (List.nodup_cons.mp hn).2]
    simp only [Std.HashMap.getElem?_insert, List.mem_cons]
    by_cases h : d = x
    · subst h
      have : d ∉ ds := (List.nodup_cons.mp hn).1
      simp [this]
    · have h' : (d == x) = false := by simpa using h
      have h'' : ¬ x = d := fun e => h e.symm
      simp [h', h'']

/-- The dependents index: for each id, the ids of the undone rows that list it as a dep, in row order. -/
def depIdx (ts : List Task) : Std.HashMap String (List String) :=
  (undone ts).foldr addDeps {}

/-- The index lookup of `depIdx` is `dependents`. -/
theorem depIdx_get (ts : List Task) (x : String) : ((depIdx ts)[x]?).getD [] = dependents ts x := by
  unfold depIdx dependents
  generalize undone ts = L
  induction L with
  | nil => simp
  | cons t L ih =>
    simp only [List.foldr_cons, addDeps, foldl_addDeps t _ (nodup_dd _), ih,
      mem_dd, List.filter_cons]
    by_cases h : x ∈ t.deps <;> simp [h]

/-! ## The table index -/

/-- A hash index of a table of pairs; the first pair of a key wins (as `List.find?`). -/
def mkMap (tb : List (String × List String)) : Std.HashMap String (List String) :=
  tb.foldr (fun p m => m.insert p.1 p.2) {}

/-- The index finds what `find?` finds. -/
theorem mkMap_get (tb : List (String × List String)) (y : String) :
    (mkMap tb)[y]? = (tb.find? (·.1 == y)).map (·.2) := by
  induction tb with
  | nil => simp [mkMap]
  | cons p tb ih =>
    simp only [mkMap, List.foldr_cons] at ih ⊢
    rw [Std.HashMap.getElem?_insert, List.find?_cons]
    by_cases h : (p.1 == y) = true
    · simp [h]
    · simp [h, ih]

/-- The indexed `look`. -/
def lookH (m : Std.HashMap String (List String)) (x : String) : List String := (m[x]?).getD [x]

theorem lookH_mkMap (tb : List (String × List String)) (x : String) : lookH (mkMap tb) x = look tb x := by
  simp [lookH, look, mkMap_get]

/-! ## One round and the table by rounds -/

/-- One round of `tab`: the chain of each undone task is the task followed by the best chain of its dependents. -/
def stepS (ts : List Task) (p : List (String × List String)) : List (String × List String) :=
  (uids ts).map fun x => (x, x :: best ((dependents ts x).map (look p)))

/-- One round from the indexes. -/
def stepF (ts : List Task) (idx : Std.HashMap String (List String)) (p : List (String × List String)) :
    List (String × List String) :=
  let hm := mkMap p
  (uids ts).map fun x => (x, x :: best (((idx[x]?).getD []).map (lookH hm)))

theorem stepF_eq (ts : List Task) (p : List (String × List String)) : stepF ts (depIdx ts) p = stepS ts p := by
  unfold stepF stepS
  apply List.map_congr_left
  intro x _
  have : (dependents ts x).map (lookH (mkMap p)) = (dependents ts x).map (look p) :=
    List.map_congr_left fun y _ => lookH_mkMap p y
  simp only [depIdx_get, this]

/-- The table at fuel `k + 1` is one round of the table at fuel `k`. -/
theorem tab_succ (ts : List Task) (k : Nat) : tab ts (k + 1) = stepS ts (tab ts k) := rfl

/-- A round that changes nothing changes nothing later. -/
theorem tab_fix (ts : List Task) (j : Nat) (h : tab ts (j + 1) = tab ts j) : ∀ m, tab ts (j + m) = tab ts j
  | 0 => rfl
  | m + 1 => by
    rw [← Nat.add_assoc, tab_succ, tab_fix ts j h m, ← tab_succ, h]

/-- The table by rounds from table `p`, at most `k` rounds, stopping at a round that changes nothing. -/
def fastTabAux (ts : List Task) (idx : Std.HashMap String (List String)) :
    Nat → List (String × List String) → List (String × List String)
  | 0, p => p
  | k + 1, p => let p' := stepF ts idx p; if p' = p then p else fastTabAux ts idx k p'

/-- Starting at the table of fuel `j`, `k` fast rounds reach the table of fuel `j + k`. -/
theorem fastTabAux_eq (ts : List Task) : ∀ (k j : Nat),
    fastTabAux ts (depIdx ts) k (tab ts j) = tab ts (j + k)
  | 0, j => rfl
  | k + 1, j => by
    simp only [fastTabAux, stepF_eq]
    rw [← tab_succ]
    by_cases h : tab ts (j + 1) = tab ts j
    · simp only [h, ↓reduceIte]
      exact (tab_fix ts j h (k + 1)).symm
    · simp only [h, ↓reduceIte]
      rw [fastTabAux_eq ts k (j + 1)]
      congr 1
      omega

/-- The critical path from the indexes. -/
def fastCriticalPath (ts : List Task) : List String :=
  let hm := mkMap (fastTabAux ts (depIdx ts) ts.length ((uids ts).map fun x => (x, [x])))
  best ((uids ts).map (lookH hm))

/-- **The fast critical path is the critical path.** -/
theorem fastCriticalPath_eq (ts : List Task) : fastCriticalPath ts = criticalPath ts := by
  have h := fastTabAux_eq ts ts.length 0
  rw [Nat.zero_add] at h
  have h1 : fastCriticalPath ts = best ((uids ts).map (lookH (mkMap (tab ts ts.length)))) := by
    rw [← h]; rfl
  rw [h1, criticalPath]
  congr 1
  apply List.map_congr_left
  intro x _
  rw [lookH_mkMap]

/-! ## The fast board plan -/

/-- `viewWith` with the critical path from the indexes. -/
def fastViewWith (s : State) (b : List Task) : View :=
  { tasks := b.map (taskView s b), milestones := s.milestones.map (msView s.tasks),
    criticalPath := fastCriticalPath (kept s.tasks), parallelSafe := (groups b).map ids }

theorem fastViewWith_eq (s : State) (b : List Task) : fastViewWith s b = viewWith s b := by
  simp only [fastViewWith, viewWith, fastCriticalPath_eq]

/-- The board plan at time `now` under quiet limit `q`, from the fast parts. -/
def fastView (q now : Nat) (s : State) : View := fastViewWith s (bound q now s)

/-- **The fast board plan is the board plan.** -/
theorem fastView_eq (q now : Nat) (s : State) : fastView q now s = view q now s :=
  fastViewWith_eq s _

end Fw.Plan
