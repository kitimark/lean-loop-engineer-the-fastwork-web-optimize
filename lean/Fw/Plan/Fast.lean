import Fw.Plan.Core
/-!
# A fast `task.define` check: the cycle test follows only the new edges

`Fw.Plan.check` decides "would this definition close a cycle" by running Kahn's pass over the whole work graph
(`acyclicB`), which costs `O(n²)` per definition. On an acyclic graph (`Inv`, kept by every accepted command) only the
edges of the new definition can close a cycle, so the test is a search from its deps for the defined task. This module
proves the search decides exactly as `acyclicB` on an invariant state, and `Fw.Serve` runs the search.

* `dep_upsert`: the edges of `upsert ts d` are the edges of `ts` that do not leave `d.task`, plus `d.task → x` for each
  dep `x` of `d`.
* `acyclic_upsert_iff`: on an acyclic `ts`, `upsert ts d` is acyclic exactly when no dep of `d` reaches `d.task` along
  the edges of `ts` that do not leave `d.task`.
* `reach_iff`: the depth-first search `reach` finds `d.task` from a list of start nodes exactly when one of them reaches it.
* `checkFast_eq`: on an invariant state `checkFast` gives the answer of `check`, for every command.
-/
namespace Fw.Plan

/-- Reachability along a relation: zero or more steps, written head first. -/
inductive Reach (E : String → String → Prop) : String → String → Prop where
  | refl (a : String) : Reach E a a
  | head {a b c : String} : E a b → Reach E b c → Reach E a c

/-- One step at the end of a path. -/
theorem Reach.tail {E : String → String → Prop} {a b c : String} (h : Reach E a b) (e : E b c) :
    Reach E a c := by
  induction h with
  | refl => exact .head e (.refl _)
  | head h1 _ ih => exact .head h1 (ih e)

/-- Paths join. -/
theorem Reach.trans {E : String → String → Prop} {a b c : String} (h : Reach E a b) (h2 : Reach E b c) :
    Reach E a c := by
  induction h with
  | refl => exact h2
  | head h1 _ ih => exact .head h1 (ih h2)

/-- A smaller relation reaches less. -/
theorem Reach.mono {E F : String → String → Prop} (hs : ∀ x y, E x y → F x y) {a b : String}
    (h : Reach E a b) : Reach F a b := by
  induction h with
  | refl => exact .refl _
  | head h1 _ ih => exact .head (hs _ _ h1) ih

/-- A path of one or more steps is a path. -/
theorem tg_reach {R : String → String → Prop} {a b : String} (h : Relation.TransGen R a b) : Reach R a b := by
  induction h with
  | single h => exact .head h (.refl _)
  | tail _ h2 ih => exact ih.tail h2

/-- A step then a path is a path of one or more steps. -/
theorem reach_tg {R : String → String → Prop} {a b c : String} (h : Relation.TransGen R a b)
    (h2 : Reach R b c) : Relation.TransGen R a c := by
  induction h2 generalizing a with
  | refl => exact h
  | head h1 _ ih => exact ih (.tail h h1)

/-- The edges of `ts` that do not leave `x`. -/
def Edge (ts : List Task) (x a b : String) : Prop := a ≠ x ∧ Dep ts a b

/-- **The edges of an upsert**: an edge of `upsert ts d` is an edge of `ts` that does not leave `d.task`, or an edge
from `d.task` to a dep of `d`.
-/
theorem dep_upsert (ts : List Task) (d : Def) (a b : String) :
    Dep (upsert ts d) a b ↔ (a ≠ d.task ∧ Dep ts a b) ∨ (a = d.task ∧ b ∈ d.deps) := by
  unfold upsert
  split
  · rename_i hc
    have hx : ∃ t ∈ ts, t.id = d.task := by
      have := List.contains_iff_mem.mp hc
      simp only [ids, List.mem_map] at this
      exact this
    simp only [setRow, Dep, List.mem_map]
    constructor
    · rintro ⟨t, ⟨t0, h0, rfl⟩, h1, h2⟩
      by_cases hi : t0.id = d.task
      · simp only [hi, ite_true, Def.row] at h1 h2
        exact .inr ⟨h1.symm, h2⟩
      · simp only [hi, ite_false] at h1 h2
        exact .inl ⟨by rw [← h1]; exact hi, t0, h0, h1, h2⟩
    · rintro (⟨hne, t, ht, h1, h2⟩ | ⟨rfl, hb⟩)
      · exact ⟨t, ⟨t, ht, by simp [show t.id ≠ d.task from h1 ▸ hne]⟩, h1, h2⟩
      · obtain ⟨t0, h0, hi⟩ := hx
        exact ⟨_, ⟨t0, h0, rfl⟩, by simp [hi, Def.row], by simpa [hi, Def.row] using hb⟩
  · rename_i hc
    have hn : ∀ t ∈ ts, t.id ≠ d.task := by
      intro t ht hi
      apply hc
      exact List.contains_iff_mem.mpr (List.mem_map.mpr ⟨t, ht, hi⟩)
    simp only [Dep, List.mem_append, List.mem_singleton]
    constructor
    · rintro ⟨t, (ht | rfl), h1, h2⟩
      · exact .inl ⟨h1 ▸ hn t ht, t, ht, h1, h2⟩
      · exact .inr ⟨h1.symm, h2⟩
    · rintro (⟨_, t, ht, h1, h2⟩ | ⟨rfl, hb⟩)
      · exact ⟨t, .inl ht, h1, h2⟩
      · exact ⟨_, .inr rfl, rfl, hb⟩

/-- A path to `x` in `upsert ts d`, with `x = d.task`, never needs an edge that leaves `x` before it first arrives. -/
theorem reach_first {ts : List Task} {d : Def} {y x : String} (hx : x = d.task)
    (h : Reach (Dep (upsert ts d)) y x) : Reach (Edge ts d.task) y x := by
  induction h with
  | refl => exact .refl _
  | @head a b c h1 _ ih =>
    by_cases ha : a = d.task
    · rw [ha, ← hx] at *; exact .refl _
    · have := (dep_upsert ts d a b).mp h1
      rcases this with ⟨_, h3⟩ | ⟨h3, _⟩
      · exact .head ⟨ha, h3⟩ (ih hx)
      · exact absurd h3 ha

/-- A path of one or more edges in `upsert ts d` is a path of `ts`, or it reaches `d.task` and then a dep of `d` that
reaches its end.
-/
theorem path_split {ts : List Task} {d : Def} {p q : String}
    (h : Relation.TransGen (Dep (upsert ts d)) p q) :
    Relation.TransGen (Edge ts d.task) p q ∨
      (Reach (Dep (upsert ts d)) p d.task ∧ ∃ y ∈ d.deps, Reach (Dep (upsert ts d)) y q) := by
  induction h with
  | @single b h1 =>
    by_cases hp : p = d.task
    · subst hp
      rcases (dep_upsert ts d _ b).mp h1 with ⟨h2, _⟩ | ⟨_, h2⟩
      · exact absurd rfl h2
      · exact .inr ⟨.refl _, b, h2, .refl _⟩
    · rcases (dep_upsert ts d p b).mp h1 with ⟨_, h2⟩ | ⟨h2, _⟩
      · exact .inl (.single ⟨hp, h2⟩)
      · exact absurd h2 hp
  | @tail b c h1 h2 ih =>
    by_cases hb : b = d.task
    · subst hb
      rcases (dep_upsert ts d _ c).mp h2 with ⟨h3, _⟩ | ⟨_, h3⟩
      · exact absurd rfl h3
      · refine .inr ⟨?_, c, h3, .refl _⟩
        rcases ih with ih | ⟨ih, _⟩
        · exact (tg_reach ih).mono (fun x y h => (dep_upsert ts d x y).mpr (.inl h))
        · exact ih
    · rcases (dep_upsert ts d b c).mp h2 with ⟨_, h3⟩ | ⟨h3, _⟩
      · rcases ih with ih | ⟨ih, y, hy, ih2⟩
        · exact .inl (.tail ih ⟨hb, h3⟩)
        · exact .inr ⟨ih, y, hy, ih2.tail ((dep_upsert ts d b c).mpr (.inl ⟨hb, h3⟩))⟩
      · exact absurd h3 hb

/-- **Cycle test by the new edges.** On an acyclic `ts`, `upsert ts d` is acyclic exactly when no dep of `d` reaches
`d.task` along the edges of `ts` that do not leave `d.task`.
-/
theorem acyclic_upsert_iff {ts : List Task} (d : Def) (h : Acyclic ts) :
    Acyclic (upsert ts d) ↔ ∀ x ∈ d.deps, ¬ Reach (Edge ts d.task) x d.task := by
  constructor
  · intro hu x hx hr
    apply hu d.task
    have e1 : Dep (upsert ts d) d.task x := (dep_upsert ts d _ x).mpr (.inr ⟨rfl, hx⟩)
    have e2 : Reach (Dep (upsert ts d)) x d.task :=
      hr.mono (fun a b hab => (dep_upsert ts d a b).mpr (.inl hab))
    exact reach_tg (.single e1) e2
  · intro hn a ha
    rcases path_split ha with h1 | ⟨h1, y, hy, h2⟩
    · exact h a (tg_mono (fun _ _ hab => hab.2) h1)
    · exact hn y hy (reach_first rfl (h2.trans h1))

/-- Start nodes not yet seen, among the ids of `ts` (the measure of `reach`). -/
def unseen (ts : List Task) (seen : List String) : Nat := ((ids ts).filter fun z => !seen.contains z).length

/-- Seeing one more id shrinks the unseen ones. -/
theorem unseen_lt (ts : List Task) (seen : List String) (y : String) (hy : y ∈ ids ts)
    (hs : seen.contains y = false) : unseen ts (y :: seen) < unseen ts seen := by
  unfold unseen
  have e : (ids ts).filter (fun z => !(y :: seen).contains z) =
      ((ids ts).filter (fun z => !seen.contains z)).filter (fun z => !(y :: seen).contains z) := by
    rw [List.filter_filter]
    congr 1
    funext z
    cases h : seen.contains z <;> simp_all
  rw [e]
  apply List.length_filter_lt_length_iff_exists.mpr
  have hn : y ∉ seen := by simpa using hs
  refine ⟨y, List.mem_filter.mpr ⟨hy, by simpa using hn⟩, by simp⟩

/-- **The search.** Whether a node in `todo` reaches `t` along the edges of `ts` that do not leave `t`: take a node
off `todo`; `t` itself answers yes; a seen node or an unknown id is dropped; any other node is marked seen and its deps
are queued.
-/
def reach (ts : List Task) (t : String) : List String → List String → Bool
  | _, [] => false
  | seen, y :: rest =>
    if y = t then true
    else if seen.contains y then reach ts t seen rest
    else if (ids ts).contains y then reach ts t (y :: seen) (succ ts y ++ rest)
    else reach ts t seen rest
termination_by seen todo => (unseen ts seen, todo.length)
decreasing_by
  · exact Prod.Lex.right _ (by simp)
  · rename_i _ hs hi
    exact Prod.Lex.left _ _ (unseen_lt ts _ _ (List.contains_iff_mem.mp hi) (by simpa using hs))
  · exact Prod.Lex.right _ (by simp)

/-- A found node is a start node that reaches `t`. -/
theorem reach_true : ∀ (ts : List Task) (t : String) (seen todo : List String),
    reach ts t seen todo = true → ∃ y ∈ todo, Reach (Edge ts t) y t := by
  intro ts t seen todo
  induction seen, todo using reach.induct ts t with
  | case1 seen => intro h; simp [reach] at h
  | case2 seen rest =>
    intro _; exact ⟨t, by simp, .refl _⟩
  | case3 seen y rest hy hs ih =>
    intro h
    simp only [reach, hy, hs, ite_true, ite_false] at h
    obtain ⟨z, hz, hr⟩ := ih h
    exact ⟨z, List.mem_cons_of_mem _ hz, hr⟩
  | case4 seen y rest hy hs hi ih =>
    intro h
    simp only [reach, hy, hs, hi, ite_false] at h
    obtain ⟨z, hz, hr⟩ := ih h
    rcases List.mem_append.mp hz with hz | hz
    · exact ⟨y, by simp, .head ⟨hy, mem_succ.mp hz⟩ hr⟩
    · exact ⟨z, List.mem_cons_of_mem _ hz, hr⟩
  | case5 seen y rest hy hs hi ih =>
    intro h
    simp only [reach, hy, hs, hi, ite_false] at h
    obtain ⟨z, hz, hr⟩ := ih h
    exact ⟨z, List.mem_cons_of_mem _ hz, hr⟩

/-- The state of a search: nothing seen is `t`, and every edge out of a seen node ends at a seen node, a queued node or
an unknown id other than `t`.
-/
def SearchInv (ts : List Task) (t : String) (seen todo : List String) : Prop :=
  (∀ z ∈ seen, z ≠ t) ∧ ∀ z ∈ seen, ∀ w, Edge ts t z w →
    w ∈ seen ∨ w ∈ todo ∨ (w ∉ ids ts ∧ w ≠ t)

/-- A search that finds nothing leaves a set that holds the start nodes, is closed under the edges and misses `t`. -/
theorem reach_false : ∀ (ts : List Task) (t : String) (seen todo : List String),
    reach ts t seen todo = false → SearchInv ts t seen todo →
    ∃ S : String → Prop, (∀ z, S z → ∀ w, Edge ts t z w → S w) ∧ ¬ S t ∧ (∀ y ∈ todo, S y) ∧
      (∀ z ∈ seen, S z) ∧ (∀ z, z ∉ ids ts → z ≠ t → S z) := by
  intro ts t seen todo
  induction seen, todo using reach.induct ts t with
  | case1 seen =>
    intro _ hinv
    refine ⟨fun z => z ∈ seen ∨ (z ∉ ids ts ∧ z ≠ t), ?_, ?_, by simp, fun z hz => .inl hz, fun z h1 h2 => .inr ⟨h1, h2⟩⟩
    · rintro z (hz | ⟨hz, _⟩) w hw
      · rcases hinv.2 z hz w hw with h | h | h
        · exact .inl h
        · simp at h
        · exact .inr h
      · exact absurd (by obtain ⟨_, t', ht, h1, _⟩ := hw; exact h1 ▸ List.mem_map_of_mem (f := Task.id) ht) hz
    · rintro (h | ⟨_, h⟩)
      · exact hinv.1 t h rfl
      · exact h rfl
  | case2 seen rest => intro h; simp [reach] at h
  | case3 seen y rest hy hs ih =>
    intro h hinv
    simp only [reach, hy, hs, ite_true, ite_false] at h
    obtain ⟨S, h1, h2, h3, h4, h5⟩ := ih h (by
      refine ⟨hinv.1, fun z hz w hw => ?_⟩
      rcases hinv.2 z hz w hw with h | h | h
      · exact .inl h
      · rcases List.mem_cons.mp h with rfl | h
        · exact .inl (List.contains_iff_mem.mp hs)
        · exact .inr (.inl h)
      · exact .inr (.inr h))
    exact ⟨S, h1, h2, fun z hz => by
      rcases List.mem_cons.mp hz with rfl | hz
      · exact h4 _ (List.contains_iff_mem.mp hs)
      · exact h3 z hz, h4, h5⟩
  | case4 seen y rest hy hs hi ih =>
    intro h hinv
    simp only [reach, hy, hs, hi, ite_false] at h
    obtain ⟨S, h1, h2, h3, h4, h5⟩ := ih h (by
      refine ⟨fun z hz => ?_, fun z hz w hw => ?_⟩
      · rcases List.mem_cons.mp hz with rfl | hz
        · exact hy
        · exact hinv.1 z hz
      · rcases List.mem_cons.mp hz with rfl | hz
        · exact .inr (.inl (List.mem_append.mpr (.inl (mem_succ.mpr hw.2))))
        · rcases hinv.2 z hz w hw with h | h | h
          · exact .inl (List.mem_cons_of_mem _ h)
          · rcases List.mem_cons.mp h with rfl | h
            · exact .inl (List.mem_cons_self ..)
            · exact .inr (.inl (List.mem_append.mpr (.inr h)))
          · exact .inr (.inr h))
    exact ⟨S, h1, h2, fun z hz => by
      rcases List.mem_cons.mp hz with rfl | hz
      · exact h4 _ (List.mem_cons_self ..)
      · exact h3 z (List.mem_append.mpr (.inr hz)), fun z hz => h4 z (List.mem_cons_of_mem _ hz), h5⟩
  | case5 seen y rest hy hs hi ih =>
    intro h hinv
    simp only [reach, hy, hs, hi, ite_false] at h
    have hni : y ∉ ids ts := fun hm => hi (List.contains_iff_mem.mpr hm)
    obtain ⟨S, h1, h2, h3, h4, h5⟩ := ih h (by
      refine ⟨hinv.1, fun z hz w hw => ?_⟩
      rcases hinv.2 z hz w hw with h | h | h
      · exact .inl h
      · rcases List.mem_cons.mp h with rfl | h
        · exact .inr (.inr ⟨hni, hy⟩)
        · exact .inr (.inl h)
      · exact .inr (.inr h))
    exact ⟨S, h1, h2, fun z hz => by
      rcases List.mem_cons.mp hz with rfl | hz
      · exact h5 _ hni hy
      · exact h3 z hz, h4, h5⟩

/-- **The search is exact**: from the start nodes it finds `t` exactly when one of them reaches `t`. -/
theorem reach_iff (ts : List Task) (t : String) (todo : List String) :
    reach ts t [] todo = true ↔ ∃ y ∈ todo, Reach (Edge ts t) y t := by
  constructor
  · exact reach_true ts t [] todo
  · rintro ⟨y, hy, hr⟩
    cases hb : reach ts t [] todo
    · exfalso
      obtain ⟨S, h1, h2, h3, _⟩ := reach_false ts t [] todo hb ⟨by simp, by simp⟩
      have : ∀ a b, Reach (Edge ts t) a b → S a → S b := by
        intro a b hrb
        induction hrb with
        | refl => exact id
        | head he _ ih => exact fun hs => ih (h1 _ hs _ he)
      exact h2 (this y t hr (h3 y hy))
    · rfl

/-- The define check with the cycle test replaced by the search from the deps. -/
def checkFast (s : State) (c : Cmd) : Option String :=
  match c with
  | .define d =>
    let u := upsert s.tasks d
    if d.title.length > 200 then some "title: at most 200 characters"
    else if d.deps.length > 32 then some "deps: at most 32"
    else if d.writes.length > 32 then some "writes: at most 32"
    else if d.devices.length > 8 then some "devices: at most 8"
    else if d.needs.length > 8 then some "needs: at most 8"
    else match d.offMain with
    | some e => some s!"evidence not on main: {e}"
    | none => match d.deps.find? (fun x => !(ids u).contains x) with
      | some x => some s!"dep not defined: {x}"
      | none => if reach s.tasks d.task [] d.deps then some "dependency cycle" else none
  | c => check s c

/-- On an acyclic graph the search says "cycle" exactly when Kahn's pass does. -/
theorem reach_eq_acyclicB {ts : List Task} (d : Def) (h : Acyclic ts) :
    reach ts d.task [] d.deps = !acyclicB (upsert ts d) := by
  rw [Bool.eq_iff_iff, Bool.not_eq_true', ← Bool.not_eq_true, acyclicB_iff, acyclic_upsert_iff d h, reach_iff]
  constructor
  · rintro ⟨y, hy, hr⟩ hall
    exact hall y hy hr
  · intro hall
    exact Classical.byContradiction fun hno => hall fun y hy hr => hno ⟨y, hy, hr⟩

/-- **`checkFast` is `check`** on a state whose graph is acyclic. -/
theorem checkFast_eq {s : State} (h : Acyclic s.tasks) (c : Cmd) : checkFast s c = check s c := by
  cases c with
  | define d =>
    simp only [checkFast, check]
    rw [reach_eq_acyclicB d h]
    cases acyclicB (upsert s.tasks d) <;> rfl
  | _ => rfl

/-! ## Constant-time life records

`exec` appends a spawn, stop, label or mark at the end of its list (`s.stops ++ [x]`), which copies the list. A server
that replays many thousand events stores those four lists newest first (`execR` conses) and reads them back in log
order through `unrev`.
-/

/-- The state with its four record lists (spawns, stops, marks, labels) in log order, from one stored newest first. -/
def unrev (s : State) : State :=
  { s with spawns := s.spawns.reverse, stops := s.stops.reverse, marks := s.marks.reverse, labels := s.labels.reverse }

/-- `exec` on a state whose record lists are stored newest first: a record is consed, not appended. -/
def execR (s : State) (c : Cmd) : State :=
  match c with
  | .spawn a n => { s with spawns := (a, n) :: s.spawns }
  | .stop a n => { s with stops := (a, n) :: s.stops }
  | .handback x a p => { s with marks := (x, some (.handedBack a p)) :: s.marks }
  | .integrate x b p => { s with marks := (x, some (.integrated b p)) :: s.marks }
  | .park x r => { s with marks := (x, some (.parked r)) :: s.marks }
  | .unpark x => { s with marks := (x, none) :: s.marks }
  | .label k a => { s with labels := (k, a) :: s.labels }
  | c => exec s c

/-- **`execR` is `exec` read through `unrev`**: storing the records newest first and reading them back gives what `exec`
does on the log-order state.
-/
theorem unrev_execR (s : State) (c : Cmd) : unrev (execR s c) = exec (unrev s) c := by
  cases c with
  | milestone m title =>
    show unrev (exec s _) = exec (unrev s) _
    by_cases h : s.milestones.any (·.id == m) = true <;> simp [exec, unrev, h]
  | _ => simp [execR, exec, unrev]

/-- `check` reads only the tasks, so it ignores the order the records are stored in. -/
theorem check_unrev (s : State) (c : Cmd) : check (unrev s) c = check s c := by
  cases c <;> rfl

/-- The plan invariant is about the tasks, so it does not depend on the order the records are stored in. -/
theorem inv_unrev (s : State) : Inv (unrev s) ↔ Inv s := Iff.rfl

end Fw.Plan
