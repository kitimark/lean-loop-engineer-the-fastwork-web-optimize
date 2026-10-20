import Std.Data.HashMap
import Std.Data.HashSet
import Fw.Plan.Core
/-!
# Derived agents, quiet times and marks from hash indexes

`Fw.Plan.bound` gives every row its derived agent, quiet time and outcome mark (`bindRow`). Each of those reads five
facts about life keys: the keys of a name (`keysOf`), whether a key was seen (`openedK`), is live (`liveK`), when it was
last seen (`lastAt`), and the last mark of a task (`markOf`). The specification answers each by scanning the label,
spawn, stop or mark list, so a board of `n` rows over a log of `m` events costs `n * m`. This module answers the same
five questions from hash indexes built in one pass.

* `Prims` holds the five questions; `Prims.spec s` is the scan, `Prims.fast s` the indexes. `Prims.fast_eq` proves them
  equal, from one lemma per index: `labIdx_get`, `seenSet_get`, `lastIdx_get`, `endedF_eq`, `markIdx_get`.
* `bindRowP` is `bindRow` over any `Prims`; `bindRowP_spec` says that over the scan it is `bindRow` (by unfolding).
* `boundF_eq`: `boundF`, which uses the indexes, is `bound`.
-/
namespace Fw.Plan

/-! ## The five questions -/

/-- The five questions a row's derived fields ask about life keys. -/
structure Prims where
  keys   : String → List String
  opened : String → Bool
  live   : String → Bool
  last   : String → Nat
  mark   : String → Option Mark

/-- The questions answered by scanning the state. -/
def Prims.spec (s : State) : Prims := ⟨keysOf s, openedK s, liveK s, lastAt s, markOf s⟩

/-- `runs` over the questions. -/
def runsP (q now : Nat) (P : Prims) (a : String) : Bool := (P.keys a).any fun k => P.live k && decide (now ≤ P.last k + q)

/-- `agentOf` over the questions. -/
def agentOfP (q now : Nat) (P : Prims) (t : Task) : Option String := (names t).find? (runsP q now P)

/-- `tkeys` over the questions. -/
def tkeysP (P : Prims) (t : Task) : List String := (names t).flatMap P.keys

/-- `quietOf` over the questions. -/
def quietOfP (q now : Nat) (P : Prims) (t : Task) : Option Nat :=
  if (agentOfP q now P t).isNone && (tkeysP P t).any P.live then
    some ((((tkeysP P t).filter P.live).map P.last).foldr max 0)
  else none

/-- `outcomeOf` over the questions. -/
def outcomeOfP (P : Prims) (t : Task) : Option Mark :=
  P.mark t.id <|>
    (if (tkeysP P t).any P.opened && !(tkeysP P t).any P.live then some (.parked noHandback) else none)

/-- `bindRow` over the questions. -/
def bindRowP (q now : Nat) (P : Prims) (t : Task) : Task :=
  { t with agent := agentOfP q now P t, quiet := quietOfP q now P t, mark := outcomeOfP P t }

/-- Over the scanning questions, `bindRowP` is `bindRow`. -/
theorem bindRowP_spec (q now : Nat) (s : State) (t : Task) : bindRowP q now (Prims.spec s) t = bindRow q now s t := rfl

/-! ## The indexes -/

/-- The keys of each name, in label order. -/
def labIdx (s : State) : Std.HashMap String (List String) :=
  s.labels.foldr (fun p m => m.insert p.2 (p.1 :: (m[p.2]?).getD [])) {}

theorem labIdx_aux (a : String) : ∀ L : List (String × String),
    ((L.foldr (fun p m => m.insert p.2 (p.1 :: (m[p.2]?).getD [])) ({} : Std.HashMap String (List String)))[a]?).getD [] =
      (L.filter (·.2 == a)).map (·.1)
  | [] => by simp
  | p :: L => by
    have ih := labIdx_aux a L
    simp only [List.foldr_cons, Std.HashMap.getElem?_insert, List.filter_cons]
    by_cases h : (p.2 == a) = true
    · have e : p.2 = a := by simpa using h
      subst e
      simp [ih]
    · have h' : (p.2 == a) = false := by simpa using h
      simp [h', ih]

theorem labIdx_get (s : State) (a : String) : ((labIdx s)[a]?).getD [] = keysOf s a := labIdx_aux a s.labels

/-- The keys with a spawn. -/
def seenSet (s : State) : Std.HashSet String := s.spawns.foldr (fun p m => m.insert p.1) {}

theorem seenSet_get (s : State) (k : String) : (seenSet s).contains k = openedK s k := by
  unfold seenSet openedK sights
  generalize s.spawns = L
  induction L with
  | nil => simp
  | cons p L ih =>
    simp only [List.foldr_cons, Std.HashSet.contains_insert, List.any_cons, ih]

/-- The latest sighting time of each key. -/
def lastIdx (s : State) : Std.HashMap String Nat :=
  s.spawns.foldr (fun p m => m.insert p.1 (max p.2 ((m[p.1]?).getD 0))) {}

theorem lastIdx_aux (k : String) : ∀ L : List (String × Nat),
    ((L.foldr (fun p m => m.insert p.1 (max p.2 ((m[p.1]?).getD 0))) ({} : Std.HashMap String Nat))[k]?).getD 0 =
      (L.filter (·.1 == k)).foldr (fun p m => max p.2 m) 0
  | [] => by simp
  | p :: L => by
    have ih := lastIdx_aux k L
    simp only [List.foldr_cons, Std.HashMap.getElem?_insert, List.filter_cons]
    by_cases h : (p.1 == k) = true
    · have e : p.1 = k := by simpa using h
      subst e
      simp [ih]
    · have h' : (p.1 == k) = false := by simpa using h
      simp [h', ih]

theorem lastIdx_get (s : State) (k : String) : ((lastIdx s)[k]?).getD 0 = lastAt s k := lastIdx_aux k s.spawns

/-- The latest stop time of each key. -/
def stopIdx (s : State) : Std.HashMap String Nat :=
  s.stops.foldr (fun p m => m.insert p.1 (max p.2 ((m[p.1]?).getD 0))) {}

/-- The keys with a stop. -/
def stopSet (s : State) : Std.HashSet String := s.stops.foldr (fun p m => m.insert p.1) {}

/-- A key has ended: it has a stop and its last sighting is at or before the latest stop. -/
def endedF (s : State) (la : String → Nat) (k : String) : Bool :=
  (stopSet s).contains k && decide (la k ≤ ((stopIdx s)[k]?).getD 0)

theorem stopSet_get (s : State) (k : String) : (stopSet s).contains k = s.stops.any (·.1 == k) := by
  unfold stopSet
  generalize s.stops = L
  induction L with
  | nil => simp
  | cons p L ih =>
    simp only [List.foldr_cons, Std.HashSet.contains_insert, List.any_cons, ih]

theorem stopIdx_get (s : State) (k : String) :
    ((stopIdx s)[k]?).getD 0 = (s.stops.filter (·.1 == k)).foldr (fun p m => max p.2 m) 0 := by
  unfold stopIdx
  generalize s.stops = L
  induction L with
  | nil => simp
  | cons p L ih =>
    simp only [List.foldr_cons, Std.HashMap.getElem?_insert, List.filter_cons]
    by_cases h : (p.1 == k) = true
    · have e : p.1 = k := by simpa using h
      subst e
      simp [ih]
    · have h' : (p.1 == k) = false := by simpa using h
      simp [h', ih]

/-- A stop of `k` at or after `c` exists exactly when `k` has a stop and `c` is at most the latest stop time. -/
theorem any_stop (k : String) (c : Nat) : ∀ L : List (String × Nat),
    (L.any fun q => q.1 == k && decide (c ≤ q.2)) =
      (L.any (·.1 == k) && decide (c ≤ (L.filter (·.1 == k)).foldr (fun p m => max p.2 m) 0)) ∧
    (L.any (·.1 == k) = false → (L.filter (·.1 == k)).foldr (fun p m => max p.2 m) 0 = 0)
  | [] => by simp
  | q :: L => by
    obtain ⟨ih1, ih2⟩ := any_stop k c L
    by_cases h : (q.1 == k) = true
    · simp only [List.any_cons, List.filter_cons, h, List.foldr_cons, ite_true, Bool.true_or, Bool.true_and]
      refine ⟨?_, fun h2 => by simp at h2⟩
      rw [Bool.eq_iff_iff]
      cases ha : L.any (·.1 == k)
      · have h0 := ih2 ha
        rw [ha] at ih1
        simp only [Bool.false_and] at ih1
        rw [h0]
        simp only [Bool.or_eq_true, decide_eq_true_eq, ih1, Bool.false_eq_true, or_false]
        omega
      · rw [ha] at ih1
        simp only [Bool.true_and] at ih1
        rw [ih1]
        simp only [Bool.or_eq_true, decide_eq_true_eq]
        omega
    · have h' : (q.1 == k) = false := by simpa using h
      simp only [List.any_cons, List.filter_cons, h', Bool.false_and, Bool.false_or, Bool.false_eq_true, ite_false]
      exact ⟨ih1, ih2⟩

/-- `all` of the sightings of a key are at or before `t` exactly when the latest sighting is. -/
theorem all_sights (k : String) (t : Nat) : ∀ L : List (String × Nat),
    (L.all fun p => p.1 != k || decide (p.2 ≤ t)) =
      decide ((L.filter (·.1 == k)).foldr (fun p m => max p.2 m) 0 ≤ t)
  | [] => by simp
  | p :: L => by
    have ih := all_sights k t L
    simp only [List.all_cons, List.filter_cons, ih]
    by_cases h : (p.1 == k) = true
    · have e : p.1 = k := by simpa using h
      subst e
      simp only [bne_self_eq_false, Bool.false_or, List.foldr_cons, beq_self_eq_true, ite_true, Nat.max_le]
      simp
    · have h' : (p.1 == k) = false := by simpa using h
      have h'' : (p.1 != k) = true := by simpa using h'
      simp [h', h'']

theorem endedF_eq (s : State) (k : String) : endedF s (lastAt s) k = endedK s k := by
  unfold endedF endedK
  have hs : ∀ t, ((sights s).all fun p => p.1 != k || decide (p.2 ≤ t)) = decide (lastAt s k ≤ t) := by
    intro t
    exact all_sights k t _
  simp only [hs]
  rw [(any_stop k (lastAt s k) s.stops).1, stopSet_get, stopIdx_get]

/-- The last mark of each task. -/
def markIdx (s : State) : Std.HashMap String (Option Mark) := s.marks.foldl (fun m p => m.insert p.1 p.2) {}

theorem markIdx_aux (x : String) : ∀ (L : List (String × Option Mark)) (m : Std.HashMap String (Option Mark)),
    ((L.foldl (fun m p => m.insert p.1 p.2) m)[x]?).getD none =
      match (L.filter (·.1 == x)).getLast? with
      | some p => p.2
      | none => (m[x]?).getD none
  | [], m => by simp
  | p :: L, m => by
    rw [List.foldl_cons, markIdx_aux x L]
    by_cases h : (p.1 == x) = true
    · have e : p.1 = x := by simpa using h
      subst e
      simp only [List.filter_cons, beq_self_eq_true, ite_true, List.getLast?_cons, Std.HashMap.getElem?_insert]
      cases L.filter (·.1 == p.1) <;> simp [List.getLast?]
    · have h' : (p.1 == x) = false := by simpa using h
      simp [h', Std.HashMap.getElem?_insert]

theorem markIdx_get (s : State) (x : String) : ((markIdx s)[x]?).getD none = markOf s x := by
  unfold markIdx markOf
  rw [markIdx_aux]
  cases (s.marks.filter (·.1 == x)).getLast? <;> simp

/-- The indexes, built once per query. -/
structure Idx where
  lab   : Std.HashMap String (List String)
  seen  : Std.HashSet String
  last  : Std.HashMap String Nat
  stopS : Std.HashSet String
  stopM : Std.HashMap String Nat
  mark  : Std.HashMap String (Option Mark)

/-- Build the indexes (one pass over each list). -/
@[noinline] def Idx.build (s : State) : Idx :=
  ⟨labIdx s, seenSet s, lastIdx s, stopSet s, stopIdx s, markIdx s⟩

/-- The five questions answered from the indexes. -/
@[noinline] def Prims.ofIdx (ix : Idx) : Prims :=
  let lastF : String → Nat := fun k => (ix.last[k]?).getD 0
  ⟨fun a => (ix.lab[a]?).getD [], fun k => ix.seen.contains k,
    fun k => ix.seen.contains k && !(ix.stopS.contains k && decide (lastF k ≤ (ix.stopM[k]?).getD 0)), lastF,
    fun x => (ix.mark[x]?).getD none⟩

theorem Prims.fast_eq (s : State) : Prims.ofIdx (Idx.build s) = Prims.spec s := by
  have h1 : (fun a => ((labIdx s)[a]?).getD []) = keysOf s := funext (labIdx_get s)
  have h2 : (fun k => (seenSet s).contains k) = openedK s := funext (seenSet_get s)
  have h3 : (fun k => ((lastIdx s)[k]?).getD 0) = lastAt s := funext (lastIdx_get s)
  have h4 : (fun x => ((markIdx s)[x]?).getD none) = markOf s := funext (markIdx_get s)
  have h6 : (fun k => (seenSet s).contains k &&
      !((stopSet s).contains k && decide (((lastIdx s)[k]?).getD 0 ≤ ((stopIdx s)[k]?).getD 0))) = liveK s := by
    funext k
    have := endedF_eq s k
    unfold endedF at this
    rw [lastIdx_get, seenSet_get]
    unfold liveK
    rw [← this]
  simp only [Prims.ofIdx, Idx.build, Prims.spec, Prims.mk.injEq]
  exact ⟨h1, h2, h6, h3, h4⟩

/-! ## The bound rows from the indexes -/

/-- `bound` with the questions answered from the indexes. -/
def boundF (q now : Nat) (s : State) : List Task :=
  let ix := Idx.build s
  s.tasks.map (bindRowP q now (Prims.ofIdx ix))

/-- **The rows bound from the indexes are the bound rows.** -/
theorem boundF_eq (q now : Nat) (s : State) : boundF q now s = bound q now s := by
  simp only [boundF, bound, Prims.fast_eq]
  rfl

end Fw.Plan
