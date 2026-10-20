import Fw.Spec.Verdict
import Fw.Spec.Null

/-!
# Parallel-work metrics (E9 of `docs/team/parallel-plan.md`)

The metrics of section 1 of the parallel plan, as pure functions with their laws:

* **Interval merge** (`merge`): busy intervals of one agent, sorted and fused; the result is
  pairwise disjoint, sorted, non-empty per interval, and covers exactly the input points.
* **Busy time** (`busy`): merged length inside the window `[a, b)`; never more than `b - a`.
* **Speedup** `S = Σ_a busy_a / W` (`speedup`), at most the number of agents.
* **Serial share** (`serialShare`): the share of the window with at most one agent busy; at most 1.
* **Critical path** (`cp`): the heaviest path through a node-weighted DAG, by a Kahn topological
  pass with fuel `|V|` that reports `cycle` exactly when the graph has a cycle.
* **Stretch** `d / d_solo` (`stretch`) and the **bench verdict** of section 5 (`benchVerdict`)
  via `Fw.Verdict` over one of the 70 labelings of `Fw.Null.arr 8 4`.

Times are natural numbers (seconds or milliseconds); intervals are half-open `[s, e)`.
-/

namespace Fw.Sched.ParMetrics

/-! ## Intervals and merge -/

/-- A half-open time interval `[s, e)`. -/
structure Iv where
  s : Nat
  e : Nat
deriving DecidableEq, Repr

/-- The length of an interval (0 when empty). -/
def Iv.len (i : Iv) : Nat := i.e - i.s

/-- The interval contains the point `p`. -/
def covers (i : Iv) (p : Nat) : Bool := decide (i.s ≤ p ∧ p < i.e)

/-- Fuse a start-sorted list into the current interval: overlapping or touching intervals join it,
otherwise it is emitted.
-/
def mergeGo (cur : Iv) : List Iv → List Iv
  | [] => [cur]
  | y :: ys => if y.s ≤ cur.e then mergeGo ⟨cur.s, max cur.e y.e⟩ ys else cur :: mergeGo y ys

/-- Sort intervals by start (stable merge sort). -/
def sortS (l : List Iv) : List Iv := l.mergeSort fun a b => decide (a.s ≤ b.s)

/-- Merge: drop empty intervals, sort by start, fuse. -/
def merge (l : List Iv) : List Iv :=
  match sortS (l.filter fun i => decide (i.s < i.e)) with
  | [] => []
  | x :: xs => mergeGo x xs

/-- `sortS` sorts by start. -/
theorem sortS_sorted (l : List Iv) : (sortS l).Pairwise fun a b => a.s ≤ b.s := by
  have := List.pairwise_mergeSort (le := fun a b : Iv => decide (a.s ≤ b.s))
    (fun a b c h1 h2 => by simp only [decide_eq_true_eq] at *; omega)
    (fun a b => by simp only [Bool.or_eq_true, decide_eq_true_eq]; omega) l
  exact this.imp fun h => by simpa using h

/-- Every interval emitted by `mergeGo` starts no earlier than the current interval. -/
theorem mergeGo_start : ∀ (c : Iv) (ys : List Iv), ys.Pairwise (fun a b => a.s ≤ b.s) →
    (∀ y ∈ ys, c.s ≤ y.s) → ∀ o ∈ mergeGo c ys, c.s ≤ o.s
  | c, [], _, _, o, ho => by simp [mergeGo] at ho; subst ho; exact Nat.le_refl _
  | c, y :: ys, hs, hc, o, ho => by
    rw [List.pairwise_cons] at hs
    simp only [mergeGo] at ho
    split at ho
    · exact mergeGo_start ⟨c.s, max c.e y.e⟩ ys hs.2 (fun y' hy' => hc y' (by simp [hy'])) o ho
    · rcases List.mem_cons.mp ho with rfl | ho
      · exact Nat.le_refl _
      · have := mergeGo_start y ys hs.2 hs.1 o ho
        have := hc y (by simp); omega

/-- `mergeGo` emits disjoint, separated, non-empty intervals. -/
theorem mergeGo_ok : ∀ (c : Iv) (ys : List Iv), ys.Pairwise (fun a b => a.s ≤ b.s) →
    (∀ y ∈ ys, c.s ≤ y.s) → c.s < c.e → (∀ y ∈ ys, y.s < y.e) →
    (mergeGo c ys).Pairwise (fun a b => a.e < b.s) ∧ ∀ o ∈ mergeGo c ys, o.s < o.e
  | c, [], _, _, hc, _ => by simp [mergeGo, hc]
  | c, y :: ys, hs, hcs, hc, hy => by
    rw [List.pairwise_cons] at hs
    simp only [mergeGo]
    split
    · exact mergeGo_ok ⟨c.s, max c.e y.e⟩ ys hs.2 (fun y' hy' => hcs y' (by simp [hy']))
        (by simp only; omega) (fun y' hy' => hy y' (by simp [hy']))
    · rename_i hlt
      have ih := mergeGo_ok y ys hs.2 hs.1 (hy y (by simp)) (fun y' hy' => hy y' (by simp [hy']))
      refine ⟨List.pairwise_cons.mpr ⟨fun o ho => ?_, ih.1⟩, fun o ho => ?_⟩
      · have := mergeGo_start y ys hs.2 hs.1 o ho; omega
      · rcases List.mem_cons.mp ho with rfl | ho
        · exact hc
        · exact ih.2 o ho

/-- Every interval emitted by `mergeGo` lies in a window containing all inputs. -/
theorem mergeGo_within (a b : Nat) : ∀ (c : Iv) (ys : List Iv), a ≤ c.s → c.e ≤ b →
    (∀ y ∈ ys, a ≤ y.s ∧ y.e ≤ b) → ∀ o ∈ mergeGo c ys, a ≤ o.s ∧ o.e ≤ b
  | c, [], h1, h2, _, o, ho => by simp [mergeGo] at ho; subst ho; exact ⟨h1, h2⟩
  | c, y :: ys, h1, h2, hy, o, ho => by
    have hy0 := hy y (by simp)
    have hys : ∀ y' ∈ ys, a ≤ y'.s ∧ y'.e ≤ b := fun y' h => hy y' (by simp [h])
    simp only [mergeGo] at ho
    split at ho
    · exact mergeGo_within a b ⟨c.s, max c.e y.e⟩ ys h1 (by simp only; omega) hys o ho
    · rcases List.mem_cons.mp ho with rfl | ho
      · exact ⟨h1, h2⟩
      · exact mergeGo_within a b y ys hy0.1 hy0.2 hys o ho

/-- `mergeGo` covers exactly the points of its inputs. -/
theorem mergeGo_cover : ∀ (c : Iv) (ys : List Iv) (p : Nat), ys.Pairwise (fun a b => a.s ≤ b.s) →
    (∀ y ∈ ys, c.s ≤ y.s) →
    ((covers c p = true ∨ ∃ y ∈ ys, covers y p = true) ↔ ∃ o ∈ mergeGo c ys, covers o p = true)
  | c, [], p, _, _ => by simp [mergeGo]
  | c, y :: ys, p, hs, hcs => by
    rw [List.pairwise_cons] at hs
    have hcy := hcs y (by simp)
    simp only [mergeGo]
    split
    · rename_i hle
      rw [← mergeGo_cover ⟨c.s, max c.e y.e⟩ ys p hs.2 (fun y' hy' => hcs y' (by simp [hy']))]
      simp only [covers, decide_eq_true_eq, List.mem_cons, exists_eq_or_imp]
      constructor
      · rintro (h | h | h)
        · left; omega
        · left; omega
        · right; exact h
      · rintro (h | h)
        · by_cases hp : p < c.e
          · left; omega
          · right; left; omega
        · right; right; exact h
    · simp only [List.mem_cons, or_and_right, exists_or, exists_eq_left]
      rw [← mergeGo_cover y ys p hs.2 hs.1]

/-- **Merge is disjoint and sorted**: every merged interval ends before any later one starts, and
every merged interval is non-empty (so they are also strictly sorted by start).
-/
theorem merge_disjoint_sorted (l : List Iv) :
    (merge l).Pairwise (fun a b => a.e < b.s) ∧ ∀ o ∈ merge l, o.s < o.e := by
  have hs := sortS_sorted (l.filter fun i => decide (i.s < i.e))
  have hm : ∀ x ∈ sortS (l.filter fun i => decide (i.s < i.e)), x.s < x.e := by
    intro x hx
    simp only [sortS, List.mem_mergeSort, List.mem_filter, decide_eq_true_eq] at hx
    exact hx.2
  unfold merge
  split
  · simp
  · rename_i x xs hx
    rw [hx] at hs hm
    rw [List.pairwise_cons] at hs
    exact mergeGo_ok x xs hs.2 hs.1 (hm x (by simp)) (fun y hy => hm y (by simp [hy]))

/-- **Merge keeps coverage**: a point is in some input interval iff it is in some merged interval. -/
theorem merge_cover (l : List Iv) (p : Nat) :
    (∃ i ∈ l, covers i p = true) ↔ ∃ o ∈ merge l, covers o p = true := by
  have hs := sortS_sorted (l.filter fun i => decide (i.s < i.e))
  have hmem : ∀ x, x ∈ sortS (l.filter fun i => decide (i.s < i.e)) ↔ x ∈ l ∧ x.s < x.e := by
    intro x; simp [sortS, List.mem_mergeSort]
  have hl : (∃ i ∈ l, covers i p = true) ↔
      ∃ i ∈ sortS (l.filter fun i => decide (i.s < i.e)), covers i p = true := by
    constructor
    · rintro ⟨i, hi, hc⟩
      refine ⟨i, (hmem i).mpr ⟨hi, ?_⟩, hc⟩
      simp only [covers, decide_eq_true_eq] at hc; omega
    · rintro ⟨i, hi, hc⟩; exact ⟨i, ((hmem i).mp hi).1, hc⟩
  rw [hl]
  unfold merge
  split
  · rename_i hx; rw [hx]
  · rename_i x xs hx
    rw [hx] at hs ⊢
    rw [List.pairwise_cons] at hs
    rw [← mergeGo_cover x xs p hs.2 hs.1]
    simp only [List.mem_cons, or_and_right, exists_or, exists_eq_left]

/-- Every merged interval lies in a window containing all inputs. -/
theorem merge_within (a b : Nat) (l : List Iv) (h : ∀ i ∈ l, a ≤ i.s ∧ i.e ≤ b) :
    ∀ o ∈ merge l, a ≤ o.s ∧ o.e ≤ b := by
  have hm : ∀ x ∈ sortS (l.filter fun i => decide (i.s < i.e)), a ≤ x.s ∧ x.e ≤ b := by
    intro x hx
    simp only [sortS, List.mem_mergeSort, List.mem_filter] at hx
    exact h x hx.1
  unfold merge
  split
  · simp
  · rename_i x xs hx
    rw [hx] at hm
    have h0 := hm x (by simp)
    exact mergeGo_within a b x xs h0.1 h0.2 (fun y hy => hm y (by simp [hy]))

/-! ## Busy time and speedup -/

/-- Clip an interval to the window `[a, b)`. -/
def clip (a b : Nat) (i : Iv) : Iv := ⟨max i.s a, min i.e b⟩

/-- The busy time of one agent inside the window `[a, b)`: the total length of its merged,
clipped intervals.
-/
def busy (a b : Nat) (l : List Iv) : Nat := ((merge (l.map (clip a b))).map Iv.len).sum

/-- Separated non-empty intervals inside `[a, b]` have total length at most `b - a`. -/
theorem sum_len_le : ∀ (l : List Iv) (a b : Nat), l.Pairwise (fun x y => x.e < y.s) →
    (∀ o ∈ l, a ≤ o.s ∧ o.e ≤ b) → (∀ o ∈ l, o.s < o.e) → (l.map Iv.len).sum ≤ b - a
  | [], _, _, _, _, _ => by simp
  | x :: xs, a, b, hp, hw, hse => by
    rw [List.pairwise_cons] at hp
    have hx := hw x (by simp)
    have hxs := hse x (by simp)
    have ih := sum_len_le xs x.e b hp.2
      (fun o ho => ⟨Nat.le_of_lt (hp.1 o ho), (hw o (by simp [ho])).2⟩)
      (fun o ho => hse o (by simp [ho]))
    simp only [List.map_cons, List.sum_cons, Iv.len] at ih ⊢
    omega

/-- **Busy time never exceeds the window** (an agent cannot be busy longer than it is alive). -/
theorem busy_le_alive (a b : Nat) (l : List Iv) : busy a b l ≤ b - a := by
  have hd := merge_disjoint_sorted (l.map (clip a b))
  refine sum_len_le _ a b hd.1 (merge_within a b _ ?_) hd.2
  intro i hi
  simp only [List.mem_map] at hi
  obtain ⟨j, _, rfl⟩ := hi
  simp only [clip]; omega

/-- Speedup over the window: summed busy time divided, as a rational, by the window length (0 for an
empty window).
-/
def speedup (a b : Nat) (agents : List (List Iv)) : Rat :=
  (((agents.map (busy a b)).sum : Nat) : Rat) / ((b - a : Nat) : Rat)

/-- The rational quotient of two naturals is at most `k` when the numerator is at most `k` times the
denominator.
-/
theorem div_le_of_le_mul (x y k : Nat) (h : x ≤ k * y) : (x : Rat) / (y : Rat) ≤ (k : Rat) := by
  rw [Rat.div_def]
  cases y with
  | zero => simp [Rat.inv_zero]; exact Rat.natCast_nonneg
  | succ y =>
    have hpos : (0 : Rat) < ((y + 1 : Nat) : Rat) := by
      have := Rat.natCast_lt_natCast.mpr (Nat.succ_pos y)
      simpa using this
    have hinv : (0 : Rat) ≤ ((y + 1 : Nat) : Rat)⁻¹ := Rat.le_of_lt (Rat.inv_pos.mpr hpos)
    have hle : (x : Rat) ≤ ((k * (y + 1) : Nat) : Rat) := Rat.natCast_le_natCast.mpr h
    have := Rat.mul_le_mul_of_nonneg_right hle hinv
    rw [Rat.natCast_mul, Rat.mul_assoc, Rat.mul_inv_cancel _ (Rat.ne_of_gt hpos), Rat.mul_one] at this
    exact this

/-- Summed busy time is at most (number of agents) times the window. -/
theorem busy_sum_le (a b : Nat) : ∀ (agents : List (List Iv)),
    (agents.map (busy a b)).sum ≤ agents.length * (b - a)
  | [] => by simp
  | l :: ls => by
    have := busy_le_alive a b l
    have := busy_sum_le a b ls
    simp only [List.map_cons, List.sum_cons, List.length_cons, Nat.succ_mul]
    omega

/-- **Speedup is at most the number of agents.** -/
theorem speedup_le_agents (a b : Nat) (agents : List (List Iv)) :
    speedup a b agents ≤ (agents.length : Rat) :=
  div_le_of_le_mul _ _ _ (busy_sum_le a b agents)

/-! ## Serial share -/

/-- The number of agents busy at point `p`. -/
def busyAt (agents : List (List Iv)) (p : Nat) : Nat :=
  (agents.filter fun l => l.any fun i => covers i p).length

/-- The breakpoints of the window: `a`, `b` and every interval start and end inside `[a, b]`, sorted
ascending, repeats kept.
-/
def points (a b : Nat) (agents : List (List Iv)) : List Nat :=
  ((a :: b :: agents.flatMap fun l => l.flatMap fun i => [i.s, i.e]).filter
    fun p => decide (a ≤ p ∧ p ≤ b)).mergeSort fun x y => decide (x ≤ y)

/-- Sum the gaps between consecutive points whose left end satisfies `f`. -/
def segSum (f : Nat → Bool) : List Nat → Nat
  | p :: q :: rest => (if f p then q - p else 0) + segSum f (q :: rest)
  | _ => 0

/-- Serial time: the part of the window with at most one agent busy (the busy count is constant
between consecutive breakpoints).
-/
def serial (a b : Nat) (agents : List (List Iv)) : Nat :=
  segSum (fun p => decide (busyAt agents p ≤ 1)) (points a b agents)

/-- Serial share: serial time divided, as a rational, by the window length (0 for an empty window). -/
def serialShare (a b : Nat) (agents : List (List Iv)) : Rat :=
  ((serial a b agents : Nat) : Rat) / ((b - a : Nat) : Rat)

/-- Gap sums of a sorted list inside `[a, b]` are at most `b - a`. -/
theorem segSum_le (f : Nat → Bool) : ∀ (l : List Nat) (a b : Nat), l.Pairwise (· ≤ ·) →
    (∀ p ∈ l, a ≤ p ∧ p ≤ b) → segSum f l ≤ b - a
  | [], _, _, _, _ => by simp [segSum]
  | [_], _, _, _, _ => by simp [segSum]
  | p :: q :: rest, a, b, hs, hw => by
    have hp := hw p (by simp)
    have hq := hw q (by simp)
    have hpq : p ≤ q := List.rel_of_pairwise_cons hs (by simp)
    have hs' := (List.pairwise_cons.mp hs).2
    have ih := segSum_le f (q :: rest) q b hs' (by
      intro r hr
      refine ⟨?_, (hw r (by simp [hr])).2⟩
      rcases List.mem_cons.mp hr with rfl | hr
      · exact Nat.le_refl _
      · exact List.rel_of_pairwise_cons hs' hr)
    simp only [segSum]
    split <;> omega

/-- **The serial share is at most 1.** -/
theorem serial_share_le_one (a b : Nat) (agents : List (List Iv)) : serialShare a b agents ≤ 1 := by
  have hs : (points a b agents).Pairwise (· ≤ ·) := by
    have := List.pairwise_mergeSort (le := fun x y : Nat => decide (x ≤ y))
      (fun x y z h1 h2 => by simp only [decide_eq_true_eq] at *; omega)
      (fun x y => by simp only [Bool.or_eq_true, decide_eq_true_eq]; omega)
      ((a :: b :: agents.flatMap fun l => l.flatMap fun i => [i.s, i.e]).filter
        fun p => decide (a ≤ p ∧ p ≤ b))
    exact this.imp fun h => by simpa using h
  have hw : ∀ p ∈ points a b agents, a ≤ p ∧ p ≤ b := by
    intro p hp
    simp only [points, List.mem_mergeSort, List.mem_filter, decide_eq_true_eq] at hp
    exact hp.2
  have := segSum_le (fun p => decide (busyAt agents p ≤ 1)) _ a b hs hw
  have h1 := div_le_of_le_mul (serial a b agents) (b - a) 1 (by simp only [serial]; omega)
  simpa [serialShare] using h1

/-! ## Stretch -/

/-- Stretch of one job: its duration divided, as a rational, by its solo duration (0 when the solo
duration is 0).
-/
def stretch (d dsolo : Nat) : Rat := (d : Rat) / (dsolo : Rat)

/-! ## Critical path -/

/-- An edge of the graph on nodes `0, ..., n-1` (edges with an endpoint `≥ n` are ignored). -/
def Edge (n : Nat) (E : List (Nat × Nat)) (u v : Nat) : Prop := (u, v) ∈ E ∧ u < n ∧ v < n

/-- Reachability by one or more edges (a cycle is `Plus(v, v)`). -/
inductive Plus (n : Nat) (E : List (Nat × Nat)) : Nat → Nat → Prop where
  | edge {u v : Nat} : Edge n E u v → Plus n E u v
  | snoc {u w v : Nat} : Plus n E u w → Edge n E w v → Plus n E u v

/-- A path given as its node list, ending at `v`. -/
inductive PathTo (n : Nat) (E : List (Nat × Nat)) : List Nat → Nat → Prop where
  | single {v : Nat} : v < n → PathTo n E [v] v
  | snoc {p : List Nat} {u v : Nat} : PathTo n E p u → Edge n E u v → PathTo n E (p ++ [v]) v

/-- The weight of a path: the sum of its node weights (missing weights are 0). -/
def weight (w : List Nat) (p : List Nat) : Nat := (p.map fun v => w.getD v 0).sum

/-- The maximum of a list (0 for the empty list). -/
def maxl : List Nat → Nat
  | [] => 0
  | x :: xs => max x (maxl xs)

/-- The in-graph predecessors of `v`. -/
def preds (n : Nat) (E : List (Nat × Nat)) (v : Nat) : List Nat :=
  (E.filter fun e => e.2 == v && decide (e.1 < n)).map Prod.fst

/-- The recorded heaviest-path weight of `u` (0 if not recorded). -/
def look (done : List (Nat × Nat)) (u : Nat) : Nat := ((done.find? (·.1 == u)).map Prod.snd).getD 0

/-- Kahn's topological pass with fuel: repeatedly take the first remaining node whose
predecessors are all done and record `w_v + max` over its predecessors; fail when stuck.
-/
def kahn (n : Nat) (w : List Nat) (E : List (Nat × Nat)) :
    Nat → List (Nat × Nat) → List Nat → Option (List (Nat × Nat))
  | 0, done, rem => if rem.isEmpty then some done else none
  | f + 1, done, rem =>
    match rem.find? (fun v => (preds n E v).all fun u => (done.map Prod.fst).contains u) with
    | none => if rem.isEmpty then some done else none
    | some v =>
      kahn n w E f ((v, w.getD v 0 + maxl ((preds n E v).map (look done))) :: done)
        (rem.filter (· != v))

/-- The result of the critical-path computation. -/
inductive CP where
  | ok (c : Nat)
  | cycle
deriving DecidableEq, Repr

/-- The critical path: Kahn's pass with fuel `|V| = n` from nothing done and all nodes remaining; the
largest finish time, 0 when there are no nodes.
-/
def cp (n : Nat) (w : List Nat) (E : List (Nat × Nat)) : CP :=
  match kahn n w E n [] (List.range n) with
  | some d => .ok (maxl (d.map Prod.snd))
  | none => .cycle

/-- Membership in `preds`. -/
theorem mem_preds {n : Nat} {E : List (Nat × Nat)} {u v : Nat} :
    u ∈ preds n E v ↔ (u, v) ∈ E ∧ u < n := by
  simp only [preds, List.mem_map, List.mem_filter, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq]
  constructor
  · rintro ⟨⟨a, b⟩, ⟨h, rfl, hl⟩, rfl⟩; exact ⟨h, hl⟩
  · rintro ⟨h, hl⟩; exact ⟨(u, v), ⟨h, rfl, hl⟩, rfl⟩

/-- Every member is at most the maximum. -/
theorem le_maxl : ∀ {l : List Nat} {x : Nat}, x ∈ l → x ≤ maxl l
  | y :: ys, x, h => by
    simp only [maxl]
    rcases List.mem_cons.mp h with rfl | h
    · exact Nat.le_max_left _ _
    · exact Nat.le_trans (le_maxl h) (Nat.le_max_right _ _)

/-- The maximum of a non-empty list is a member. -/
theorem maxl_mem : ∀ {l : List Nat}, l ≠ [] → maxl l ∈ l
  | [y], _ => by simp [maxl]
  | y :: z :: zs, _ => by
    have ih := maxl_mem (l := z :: zs) (by simp)
    simp only [maxl] at ih ⊢
    rcases Nat.le_total y (max z (maxl zs)) with h | h
    · rw [Nat.max_eq_right h]; exact List.mem_cons_of_mem _ ih
    · rw [Nat.max_eq_left h]; simp

/-- With unique keys, `look` returns the recorded value. -/
theorem look_eq {done : List (Nat × Nat)} {u d : Nat} (hnd : (done.map Prod.fst).Nodup)
    (hm : (u, d) ∈ done) : look done u = d := by
  unfold look
  cases hf : done.find? (·.1 == u) with
  | none =>
    have := List.find?_eq_none.mp hf _ hm
    simp at this
  | some x =>
    have hx := List.mem_of_find?_eq_some hf
    have hxu : x.1 = u := by simpa using List.find?_some hf
    simp only [Option.map_some, Option.getD_some]
    have key : ∀ (l : List (Nat × Nat)), (l.map Prod.fst).Nodup → x ∈ l → (u, d) ∈ l → x.2 = d := by
      intro l
      induction l with
      | nil => intro _ h; cases h
      | cons a l ih =>
        intro hn h1 h2
        simp only [List.map_cons, List.nodup_cons, List.mem_map] at hn
        rcases List.mem_cons.mp h1 with rfl | h1 <;> rcases List.mem_cons.mp h2 with h2 | h2
        · rw [← h2]
        · exact absurd ⟨(u, d), h2, hxu.symm⟩ hn.1
        · exact absurd ⟨x, h1, by rw [hxu, ← h2]⟩ hn.1
        · exact ih hn.2 h1 h2
    exact key done hnd hx hm

/-- Weight of an extended path. -/
theorem weight_snoc (w p : List Nat) (v : Nat) : weight w (p ++ [v]) = weight w p + w.getD v 0 := by
  simp [weight, List.sum_append]

/-- Path ends are nodes. -/
theorem PathTo.lt {n : Nat} {E : List (Nat × Nat)} {p : List Nat} {v : Nat} (h : PathTo n E p v) :
    v < n := by
  cases h with
  | single h => exact h
  | snoc _ he => exact he.2.2

/-- Reachability ends are nodes. -/
theorem Plus.lt {n : Nat} {E : List (Nat × Nat)} {u v : Nat} (h : Plus n E u v) : u < n ∧ v < n := by
  induction h with
  | edge he => exact ⟨he.2.1, he.2.2⟩
  | snoc _ he ih => exact ⟨ih.1, he.2.2⟩

/-- Prepend an edge to a reachability chain. -/
theorem Plus.cons {n : Nat} {E : List (Nat × Nat)} {u' u v : Nat} (he : Edge n E u' u)
    (h : Plus n E u v) : Plus n E u' v := by
  induction h with
  | edge h2 => exact .snoc (.edge he) h2
  | snoc _ h2 ih => exact .snoc ih h2

/-- Every entry's predecessors were recorded before it (later in the list). -/
def TopoOk (n : Nat) (E : List (Nat × Nat)) : List (Nat × Nat) → Prop
  | [] => True
  | x :: rest => (∀ u ∈ preds n E x.1, u ∈ rest.map Prod.fst) ∧ TopoOk n E rest

/-- The invariant of Kahn's pass: done keys and remaining nodes partition the nodes without
repetition, every recorded value bounds every path to its node and is attained, and the record
is in topological order.
-/
structure KInv (n : Nat) (w : List Nat) (E : List (Nat × Nat)) (done : List (Nat × Nat))
    (rem : List Nat) : Prop where
  part   : ∀ v, v < n ↔ (v ∈ done.map Prod.fst ∨ v ∈ rem)
  nodup  : (done.map Prod.fst ++ rem).Nodup
  bound  : ∀ x ∈ done, ∀ p, PathTo n E p x.1 → weight w p ≤ x.2
  attain : ∀ x ∈ done, ∃ p, PathTo n E p x.1 ∧ weight w p = x.2
  topo   : TopoOk n E done

/-- The invariant holds at the start. -/
theorem kinv_init (n : Nat) (w : List Nat) (E : List (Nat × Nat)) : KInv n w E [] (List.range n) :=
  ⟨fun v => by simp, by simpa using List.nodup_range, by simp, by simp, trivial⟩

/-- One step of Kahn's pass keeps the invariant. -/
theorem kinv_step {n : Nat} {w : List Nat} {E : List (Nat × Nat)} {done : List (Nat × Nat)}
    {rem : List Nat} {v : Nat} (h : KInv n w E done rem) (hv : v ∈ rem)
    (hp : ∀ u ∈ preds n E v, u ∈ done.map Prod.fst) :
    KInv n w E ((v, w.getD v 0 + maxl ((preds n E v).map (look done))) :: done)
      (rem.filter (· != v)) := by
  have hnd := h.nodup
  rw [List.nodup_append] at hnd
  have hvd : v ∉ done.map Prod.fst := fun hm => hnd.2.2 v hm v hv rfl
  have hvn : v < n := (h.part v).mpr (.inr hv)
  refine ⟨?_, ?_, ?_, ?_, ⟨hp, h.topo⟩⟩
  · intro u
    rw [h.part u]
    simp only [List.map_cons, List.mem_cons, List.mem_filter, bne_iff_ne, ne_eq]
    constructor
    · rintro (hu | hu)
      · exact .inl (.inr hu)
      · by_cases huv : u = v
        · exact .inl (.inl huv)
        · exact .inr ⟨hu, huv⟩
    · rintro ((rfl | hu) | ⟨hu, _⟩)
      · exact .inr hv
      · exact .inl hu
      · exact .inr hu
  · simp only [List.map_cons, List.cons_append, List.nodup_cons, List.mem_append, List.mem_filter,
      bne_self_eq_false, Bool.false_eq_true, and_false, or_false]
    refine ⟨hvd, ?_⟩
    exact List.Pairwise.sublist (List.Sublist.append (List.Sublist.refl _) List.filter_sublist) h.nodup
  · intro x hx p hpx
    rcases List.mem_cons.mp hx with rfl | hx
    · cases hpx with
      | single _ => simp [weight]
      | snoc hq he =>
        rename_i q u
        have hu : u ∈ preds n E v := mem_preds.mpr ⟨he.1, he.2.1⟩
        obtain ⟨⟨u', du⟩, hud, rfl⟩ := List.mem_map.mp (hp u hu)
        have h1 := h.bound _ hud q hq
        have h2 : look done u' = du := look_eq hnd.1 hud
        have h3 : du ≤ maxl ((preds n E v).map (look done)) := by
          rw [← h2]; exact le_maxl (List.mem_map_of_mem hu)
        rw [weight_snoc]
        simp only at h1 ⊢
        omega
    · exact h.bound x hx p hpx
  · intro x hx
    rcases List.mem_cons.mp hx with rfl | hx
    · by_cases hpe : preds n E v = []
      · refine ⟨[v], .single hvn, ?_⟩
        simp [weight, hpe, maxl]
      · have hne : (preds n E v).map (look done) ≠ [] := by simpa using hpe
        obtain ⟨u, hu, hlu⟩ := List.mem_map.mp (maxl_mem hne)
        obtain ⟨⟨u', du⟩, hud, rfl⟩ := List.mem_map.mp (hp u hu)
        obtain ⟨q, hq, hwq⟩ := h.attain _ hud
        have hpu := mem_preds.mp hu
        refine ⟨q ++ [v], .snoc hq ⟨hpu.1, hpu.2, hvn⟩, ?_⟩
        rw [weight_snoc, hwq, ← hlu, look_eq hnd.1 hud]
        simp only; omega
    · exact h.attain x hx

/-- A successful pass ends with the invariant and nothing remaining. -/
theorem kahn_some {n : Nat} {w : List Nat} {E : List (Nat × Nat)} :
    ∀ (f : Nat) (done : List (Nat × Nat)) (rem : List Nat) (out : List (Nat × Nat)),
    KInv n w E done rem → kahn n w E f done rem = some out → KInv n w E out []
  | 0, done, rem, out, h, hk => by
    simp only [kahn] at hk
    split at hk
    · rename_i he; cases hk; rw [List.isEmpty_iff.mp he] at h; exact h
    · cases hk
  | f + 1, done, rem, out, h, hk => by
    simp only [kahn] at hk
    split at hk
    · split at hk
      · rename_i he; cases hk; rw [List.isEmpty_iff.mp he] at h; exact h
      · cases hk
    · rename_i v hv
      have hvr := List.mem_of_find?_eq_some hv
      have hpv := List.find?_some hv
      simp only [List.all_eq_true, List.contains_iff_mem] at hpv
      exact kahn_some f _ _ out (kinv_step h hvr hpv) hk

/-- A non-empty node set in which every node has a predecessor inside the set contains a cycle. -/
theorem cycle_of_closed (n : Nat) (E : List (Nat × Nat)) :
    ∀ (S : List Nat), (∃ v, v ∈ S) → (∀ v ∈ S, ∃ u ∈ S, Edge n E u v) → ∃ v, Plus n E v v := by
  intro S
  generalize hk : S.length = k
  induction k using Nat.strongRecOn generalizing S with
  | _ k ih =>
    intro ⟨v0, hv0⟩ hcl
    by_cases hc : Plus n E v0 v0
    · exact ⟨v0, hc⟩
    · have : DecidablePred fun u => Plus n E u v0 := fun _ => Classical.propDecidable _
      let R := S.filter fun u => decide (Plus n E u v0)
      have hlt : R.length < k := by
        rw [← hk]
        exact List.length_filter_lt_length_iff_exists.mpr ⟨v0, hv0, by simp [hc]⟩
      obtain ⟨u1, hu1, he1⟩ := hcl v0 hv0
      refine ih R.length hlt R rfl ⟨u1, List.mem_filter.mpr ⟨hu1, by simpa using Plus.edge he1⟩⟩ ?_
      intro u hu
      obtain ⟨huS, hup⟩ := List.mem_filter.mp hu
      obtain ⟨u', hu', he'⟩ := hcl u huS
      refine ⟨u', List.mem_filter.mpr ⟨hu', ?_⟩, he'⟩
      simp only [decide_eq_true_eq] at hup ⊢
      exact Plus.cons he' hup

/-- A failed pass (with enough fuel) means the graph has a cycle. -/
theorem kahn_none {n : Nat} {w : List Nat} {E : List (Nat × Nat)} :
    ∀ (f : Nat) (done : List (Nat × Nat)) (rem : List Nat),
    KInv n w E done rem → rem.length ≤ f → kahn n w E f done rem = none → ∃ v, Plus n E v v
  | 0, done, rem, _, hl, hk => by
    have : rem = [] := List.eq_nil_of_length_eq_zero (Nat.le_zero.mp hl)
    simp [kahn, this] at hk
  | f + 1, done, rem, h, hl, hk => by
    simp only [kahn] at hk
    split at hk
    · rename_i hf
      split at hk
      · cases hk
      · rename_i hne
        have hall := List.find?_eq_none.mp hf
        apply cycle_of_closed n E rem
        · cases rem with
          | nil => simp at hne
          | cons a _ => exact ⟨a, by simp⟩
        · intro v hv
          have := hall v hv
          simp only [List.all_eq_true, List.contains_iff_mem, Classical.not_forall] at this
          obtain ⟨u, hu, hud⟩ := this
          have hpu := mem_preds.mp hu
          have hur : u ∈ rem := ((h.part u).mp hpu.2).resolve_left hud
          exact ⟨u, hur, hpu.1, hpu.2, (h.part v).mpr (.inr hv)⟩
    · rename_i v hv
      have hvr := List.mem_of_find?_eq_some hv
      have hpv := List.find?_some hv
      simp only [List.all_eq_true, List.contains_iff_mem] at hpv
      have hlt : (rem.filter (· != v)).length < rem.length :=
        List.length_filter_lt_length_iff_exists.mpr ⟨v, hvr, by simp⟩
      exact kahn_none f _ _ (kinv_step h hvr hpv) (by omega) hk

/-- In a topologically ordered record with unique keys, everything that reaches a recorded node is
recorded and differs from it.
-/
theorem topo_closed {n : Nat} {E : List (Nat × Nat)} :
    ∀ (L : List (Nat × Nat)), TopoOk n E L → (L.map Prod.fst).Nodup →
    ∀ v ∈ L.map Prod.fst, ∀ u, Plus n E u v → u ∈ L.map Prod.fst ∧ u ≠ v
  | [], _, _, v, hv, _, _ => by simp at hv
  | x :: rest, ⟨hx, ht⟩, hn, v, hv, u, hp => by
    simp only [List.map_cons, List.nodup_cons] at hn
    have ih := topo_closed rest ht hn.2
    rcases List.mem_cons.mp hv with rfl | hv
    · cases hp with
      | edge he =>
        have hu := hx u (mem_preds.mpr ⟨he.1, he.2.1⟩)
        exact ⟨List.mem_cons_of_mem _ hu, fun h => hn.1 (h ▸ hu)⟩
      | snoc hq he =>
        rename_i w0
        have hw := hx w0 (mem_preds.mpr ⟨he.1, he.2.1⟩)
        have := (ih w0 hw u hq).1
        exact ⟨List.mem_cons_of_mem _ this, fun h => hn.1 (h ▸ this)⟩
    · have := ih v hv u hp
      exact ⟨List.mem_cons_of_mem _ this.1, this.2⟩

/-- **The critical path bounds every path.** -/
theorem cp_ge_path {n : Nat} {w : List Nat} {E : List (Nat × Nat)} {c : Nat}
    (h : cp n w E = .ok c) {p : List Nat} {v : Nat} (hp : PathTo n E p v) : weight w p ≤ c := by
  unfold cp at h
  split at h
  · rename_i d hk
    cases h
    have hi := kahn_some n [] _ d (kinv_init n w E) hk
    have hv := (hi.part v).mp hp.lt
    simp only [List.not_mem_nil, or_false, List.mem_map] at hv
    obtain ⟨x, hx, rfl⟩ := hv
    exact Nat.le_trans (hi.bound x hx p hp) (le_maxl (List.mem_map_of_mem hx))
  · cases h

/-- **The critical path is attained** by some path (when there is at least one node). -/
theorem cp_attained {n : Nat} {w : List Nat} {E : List (Nat × Nat)} {c : Nat}
    (h : cp n w E = .ok c) (hn : 0 < n) : ∃ p v, PathTo n E p v ∧ weight w p = c := by
  unfold cp at h
  split at h
  · rename_i d hk
    cases h
    have hi := kahn_some n [] _ d (kinv_init n w E) hk
    have h0 := (hi.part 0).mp hn
    simp only [List.not_mem_nil, or_false] at h0
    have hne : d.map Prod.snd ≠ [] := by
      intro he; rw [List.map_eq_nil_iff] at he; subst he; simp at h0
    obtain ⟨x, hx, hxc⟩ := List.mem_map.mp (maxl_mem hne)
    obtain ⟨p, hp, hw⟩ := hi.attain x hx
    exact ⟨p, x.1, hp, hw.trans hxc⟩
  · cases h

/-- **The pass reports a cycle exactly on cyclic graphs.** -/
theorem cp_acyclic_or_error (n : Nat) (w : List Nat) (E : List (Nat × Nat)) :
    cp n w E = .cycle ↔ ∃ v, Plus n E v v := by
  unfold cp
  split
  · rename_i d hk
    simp only [reduceCtorEq, false_iff]
    rintro ⟨v, hv⟩
    have hi := kahn_some n [] _ d (kinv_init n w E) hk
    have hvd := ((hi.part v).mp hv.lt.1).resolve_right (by simp)
    exact (topo_closed d hi.topo (by simpa using hi.nodup) v hvd v hv).2 rfl
  · rename_i hk
    simp only [true_iff]
    exact kahn_none n [] _ (kinv_init n w E) (by simp) hk

/-! ## The bench verdict (section 5) -/

/-- The bench verdict for one block: control makespans are those labelled `false`, variant
makespans those labelled `true`; lower is better.
-/
def benchVerdict (labels : List Bool) (ms : List Int) : Fw.Verdict.Verdict :=
  Fw.Verdict.verdict .lower (Fw.Null.sel false labels ms) (Fw.Null.sel true labels ms)

/-- The labeling drawn for a seed: one of the 70 ways to put 4 variant blocks among 8. -/
def labeling (seed : Nat) : List Bool := ((Fw.Null.arr 8 4)[seed % 70]?).getD []

/-- **At most one labeling says "better"** for any 8 makespans, so a uniform draw from the 70
labelings gives a false "better" with probability at most 1/70 (`Fw.Null.null_bound_4v4_5v5`).
-/
theorem bench_wins_le_one (v : List Int) (hv : v.length = 8) :
    ((Fw.Null.arr 8 4).filter fun b => benchVerdict b v == .better).length ≤ 1 :=
  Fw.Null.winsAt_le_one v 4 4 hv

/-! ## Examples -/

#guard merge [⟨5, 7⟩, ⟨1, 3⟩, ⟨2, 4⟩, ⟨4, 4⟩, ⟨9, 8⟩] == [⟨1, 4⟩, ⟨5, 7⟩]
#guard merge [⟨1, 3⟩, ⟨3, 5⟩] == [⟨1, 5⟩] && merge [] == []
#guard busy 0 10 [⟨1, 3⟩, ⟨2, 4⟩, ⟨8, 12⟩] == 5 && busy 10 0 [⟨1, 3⟩] == 0
#guard speedup 0 10 [[⟨0, 6⟩], [⟨4, 10⟩]] == 6 / 5 && speedup 5 5 [[⟨0, 6⟩]] == 0
#guard busyAt [[⟨0, 6⟩], [⟨4, 10⟩]] 5 == 2 && busyAt [[⟨0, 6⟩], [⟨4, 10⟩]] 6 == 1
#guard serial 0 10 [[⟨0, 6⟩], [⟨4, 10⟩]] == 8 && serialShare 0 10 [[⟨0, 6⟩], [⟨4, 10⟩]] == 4 / 5
#guard serial 0 10 [[⟨0, 10⟩], [⟨0, 10⟩], [⟨2, 3⟩]] == 0 && serialShare 0 10 [] == 1
#guard stretch 13 10 == 13 / 10 && stretch 5 0 == 0
#guard cp 3 [2, 3, 4] [(0, 1), (1, 2), (0, 2)] == .ok 9
#guard cp 4 [5, 1, 1, 1] [(1, 2), (2, 3)] == .ok 5
#guard cp 2 [1, 1] [(0, 1), (1, 0)] == .cycle && cp 1 [5] [(0, 0)] == .cycle
#guard cp 2 [1, 2] [(0, 5), (7, 1)] == .ok 2 && cp 0 [] [] == .ok 0
-- the bench draw: 70 distinct labelings, 4 variant blocks each, false-"better" chance 1/70
#guard (Fw.Null.arr 8 4).length == 70 && ((List.range 70).map labeling).Nodup
#guard (List.range 70).all fun s => (labeling s).length == 8 && (labeling s).count true == 4
#guard Fw.Null.falseBetterProb 4 4 == 1 / 70
#guard benchVerdict (labeling 0) [10, 10, 10, 10, 20, 20, 20, 20] != .noise
#guard ((List.range 70).filter fun s => benchVerdict (labeling s) [3, 1, 4, 1, 5, 9, 2, 6] == .better).length ≤ 1

end Fw.Sched.ParMetrics
