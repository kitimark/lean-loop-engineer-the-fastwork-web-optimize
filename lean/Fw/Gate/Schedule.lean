import Fw.Gate.Merge

/-!
# Gate job schedule (task `gate-speed-ci`)

The breakpoint gate fans out into jobs (probe shards, sweep jobs) that GitHub runs on a shared pool of
`m = 20` identical runners, together with the jobs of `r - 1` other runs started at the same time. This
module proves how long that can take and picks the job split of one run.

* **Graham's bound** (`graham`): list scheduling of any jobs with durations `d_j` on `m` identical
  runners finishes by `C_max ≤ Σ_j d_j / m + (1 - 1/m) max_j d_j`. It holds for any arrival
  order, so for any interleaving of the jobs of several runs (`graham_runs`).
* **The split choice** (`choose`): a split is a list of jobs, each with an engine, a number of probes
  and a list of **whole** sweeps. `choose P m r` takes the candidate split with the smallest Graham
  bound for `r` concurrent runs; it starts from the current split (8 probe shards plus one sweeps job per
  engine), so it changes the split only for a strictly smaller bound (`choose_le_current`).
* **Correctness of sharding** is not re-proved here. A sweep's verdicts depend on its whole history
  (`Fw.Gate.Scope.stopVerdicts`; `Fw.Gate.split_sweep_changes_verdict` shows a split sweep can change a
  verdict), so only whole sweeps move between jobs; `split_partitions` shows every candidate runs each
  probe and each sweep exactly once, and `layout_merge_sound` feeds that to
  `Fw.Gate.mergeGateById_eq_unsharded` (sweeps-lean) and `Fw.Gate.sharded_verdict_eq`.

Times are natural numbers (milliseconds). Everything the Graham bound says is about the combined job
list, not about one run's wall time, which also waits for the plan, site and merge jobs.
-/
namespace Fw.Gate.Schedule

/-! ## 1. Graham's bound for list scheduling -/

/-- The largest element of a list (0 for the empty list). -/
def lmax : List Nat → Nat
  | [] => 0
  | x :: xs => max x (lmax xs)

/-- The least element of a non-empty list (0 for the empty list): the runner that frees first. -/
def pickMin : List Nat → Nat
  | [] => 0
  | x :: xs => xs.foldl min x

/-- List scheduling places the next job on a least-loaded runner. `loads` holds the load of each runner. -/
def place (loads : List Nat) (d : Nat) : List Nat :=
  (pickMin loads + d) :: loads.erase (pickMin loads)

/-- All jobs in arrival order onto the given runner loads. -/
def sched : List Nat → List Nat → List Nat
  | l, [] => l
  | l, d :: ds => sched (place l d) ds

/-- The finish time of the last job: list scheduling of `ds` on `m` empty runners. -/
def makespan (m : Nat) (ds : List Nat) : Nat := lmax (sched (List.replicate m 0) ds)

/-- An element is at most the maximum. -/
theorem le_lmax {y : Nat} {l : List Nat} (h : y ∈ l) : y ≤ lmax l := by
  induction l with
  | nil => simp at h
  | cons x xs ih =>
    simp only [lmax]
    rcases List.mem_cons.1 h with rfl | h
    · exact Nat.le_max_left _ _
    · exact Nat.le_trans (ih h) (Nat.le_max_right _ _)

/-- Removing one element does not raise the maximum. -/
theorem lmax_erase_le (a : Nat) (l : List Nat) : lmax (l.erase a) ≤ lmax l := by
  induction l with
  | nil => simp [lmax]
  | cons x xs ih =>
    by_cases hx : x = a
    · subst hx; simp [List.erase_cons_head, lmax]; omega
    · have : (x :: xs).erase a = x :: xs.erase a := by
        simp [hx]
      rw [this]; simp only [lmax]; omega

/-- Removing a member lowers the sum by exactly that member. -/
theorem sum_erase (a : Nat) (l : List Nat) (h : a ∈ l) : (l.erase a).sum + a = l.sum := by
  induction l with
  | nil => simp at h
  | cons x xs ih =>
    by_cases hx : x = a
    · subst hx; simp [List.erase_cons_head]; omega
    · have hm : a ∈ xs := by
        rcases List.mem_cons.1 h with rfl | h
        · exact absurd rfl hx
        · exact h
      have : (x :: xs).erase a = x :: xs.erase a := by
        simp [hx]
      rw [this]; simp only [List.sum_cons]; have := ih hm; omega

/-- Folding `min` never goes above the start value. -/
theorem foldl_min_le_acc (xs : List Nat) : ∀ a, xs.foldl min a ≤ a := by
  induction xs with
  | nil => intro a; exact Nat.le_refl _
  | cons x xs ih => intro a; simp only [List.foldl_cons]; exact Nat.le_trans (ih _) (Nat.min_le_left _ _)

/-- Folding `min` is below every listed element. -/
theorem foldl_min_le_mem (xs : List Nat) : ∀ a y, y ∈ xs → xs.foldl min a ≤ y := by
  induction xs with
  | nil => intro a y h; simp at h
  | cons x xs ih =>
    intro a y h
    simp only [List.foldl_cons]
    rcases List.mem_cons.1 h with rfl | h
    · exact Nat.le_trans (foldl_min_le_acc xs _) (Nat.min_le_right _ _)
    · exact ih _ _ h

/-- Folding `min` returns the start value or a listed element. -/
theorem foldl_min_mem (xs : List Nat) : ∀ a, xs.foldl min a = a ∨ xs.foldl min a ∈ xs := by
  induction xs with
  | nil => intro a; left; rfl
  | cons x xs ih =>
    intro a
    simp only [List.foldl_cons]
    rcases ih (min a x) with h | h
    · rw [h]
      rcases Nat.le_total a x with hax | hxa
      · left; exact Nat.min_eq_left hax
      · right; rw [Nat.min_eq_right hxa]; exact List.mem_cons_self
    · right; exact List.mem_cons_of_mem _ h

/-- The least load is one of the loads. -/
theorem pickMin_mem {l : List Nat} (h : l ≠ []) : pickMin l ∈ l := by
  cases l with
  | nil => exact absurd rfl h
  | cons x xs =>
    simp only [pickMin]
    rcases foldl_min_mem xs x with h | h
    · rw [h]; exact List.mem_cons_self
    · exact List.mem_cons_of_mem _ h

/-- The least load is at most every load. -/
theorem pickMin_le {l : List Nat} {y : Nat} (h : y ∈ l) : pickMin l ≤ y := by
  cases l with
  | nil => simp at h
  | cons x xs =>
    simp only [pickMin]
    rcases List.mem_cons.1 h with rfl | h
    · exact foldl_min_le_acc xs _
    · exact foldl_min_le_mem xs _ _ h

/-- A lower bound on every element bounds the sum from below. -/
theorem mul_len_le_sum (a : Nat) (l : List Nat) (h : ∀ y ∈ l, a ≤ y) : a * l.length ≤ l.sum := by
  induction l with
  | nil => simp
  | cons x xs ih =>
    have h1 := h x List.mem_cons_self
    have h2 := ih (fun y hy => h y (List.mem_cons_of_mem _ hy))
    simp only [List.length_cons, List.sum_cons, Nat.mul_succ]
    omega

/-- Placing a job keeps the number of runners. -/
theorem place_length (l : List Nat) (d : Nat) (h : l ≠ []) : (place l d).length = l.length := by
  have := List.length_erase_of_mem (pickMin_mem h)
  have hpos : 0 < l.length := List.length_pos_iff.2 h
  simp only [place, List.length_cons]
  rw [this]; omega

/-- Placing a job adds its duration to the total load. -/
theorem place_sum (l : List Nat) (d : Nat) (h : l ≠ []) : (place l d).sum = l.sum + d := by
  have := sum_erase _ l (pickMin_mem h)
  simp only [place, List.sum_cons]; omega

/-- The new maximum is the old one or the chosen runner's new load. -/
theorem lmax_place_le (l : List Nat) (d : Nat) :
    lmax (place l d) ≤ max (pickMin l + d) (lmax l) := by
  simp only [place, lmax]
  have := lmax_erase_le (pickMin l) l
  omega

/-- One scheduling step keeps the invariant behind Graham's bound: with `k + 1` runners and largest job
so far at most `M`.
-/
theorem place_inv (l : List Nat) (k M M' d : Nat) (hlen : l.length = k + 1)
    (hinv : (k + 1) * lmax l ≤ l.sum + k * M) (hM : M ≤ M') (hd : d ≤ M') :
    (k + 1) * lmax (place l d) ≤ (place l d).sum + k * M' := by
  have hne : l ≠ [] := by intro h; subst h; simp at hlen
  rw [place_sum l d hne]
  have hmin : pickMin l * (k + 1) ≤ l.sum := by
    have := mul_len_le_sum (pickMin l) l (fun y hy => pickMin_le hy)
    rwa [hlen] at this
  have h1 : k * M ≤ k * M' := Nat.mul_le_mul_left k hM
  have h2 : k * d ≤ k * M' := Nat.mul_le_mul_left k hd
  have hb := lmax_place_le l d
  rcases Nat.le_total (pickMin l + d) (lmax l) with hle | hle
  · have : lmax (place l d) ≤ lmax l := by rw [Nat.max_eq_right hle] at hb; exact hb
    have := Nat.mul_le_mul_left (k + 1) this
    omega
  · have hl : lmax (place l d) ≤ pickMin l + d := by rw [Nat.max_eq_left hle] at hb; exact hb
    have h3 := Nat.mul_le_mul_left (k + 1) hl
    have h4 : (k + 1) * (pickMin l + d) = pickMin l * (k + 1) + (k * d + d) := by
      rw [Nat.mul_add, Nat.mul_comm (k + 1) (pickMin l), Nat.succ_mul]
    omega

/-- The invariant after any list of jobs. -/
theorem graham_gen (k : Nat) : ∀ (ds l : List Nat) (M : Nat), l.length = k + 1 →
    (k + 1) * lmax l ≤ l.sum + k * M →
    (k + 1) * lmax (sched l ds) ≤ l.sum + ds.sum + k * max M (lmax ds) := by
  intro ds
  induction ds with
  | nil => intro l M _ h; simpa [sched, lmax] using h
  | cons d ds ih =>
    intro l M hlen hinv
    have hne : l ≠ [] := by intro h; subst h; simp at hlen
    have h1 := place_inv l k M (max M d) d hlen hinv (Nat.le_max_left _ _) (Nat.le_max_right _ _)
    have h2 := ih (place l d) (max M d) (by rw [place_length l d hne]; exact hlen) h1
    rw [place_sum l d hne] at h2
    have e : max (max M d) (lmax ds) = max M (lmax (d :: ds)) := by simp only [lmax]; omega
    rw [e] at h2
    simp only [sched, List.sum_cons]
    omega

/-- The maximum of a list of zeros is 0. -/
theorem lmax_replicate_zero (n : Nat) : lmax (List.replicate n 0) = 0 := by
  induction n with
  | zero => rfl
  | succ n ih => simp [List.replicate_succ, lmax, ih]

/-- **Graham's bound** (list scheduling, integer form). -/
theorem graham (m : Nat) (hm : 0 < m) (ds : List Nat) :
    m * makespan m ds ≤ ds.sum + (m - 1) * lmax ds := by
  obtain ⟨k, rfl⟩ : ∃ k, m = k + 1 := ⟨m - 1, by omega⟩
  have h := graham_gen k ds (List.replicate (k + 1) 0) 0 (by simp)
    (by simp [lmax_replicate_zero])
  simpa [makespan, lmax_replicate_zero] using h

/-- `r` runs started at the same time put `r` copies of the same jobs on the pool, in any order of
arrival (here: one run after the other; Graham's bound holds for every order).
-/
def copies : Nat → List Nat → List Nat
  | 0, _ => []
  | r + 1, ds => ds ++ copies r ds

/-- The maximum of an append. -/
theorem lmax_append (a b : List Nat) : lmax (a ++ b) = max (lmax a) (lmax b) := by
  induction a with
  | nil => simp [lmax]
  | cons x xs ih => simp only [List.cons_append, lmax, ih]; omega

/-- The total of `r` copies is `r` times the total. -/
theorem sum_copies (r : Nat) (ds : List Nat) : (copies r ds).sum = r * ds.sum := by
  induction r with
  | zero => simp [copies]
  | succ r ih => simp only [copies, List.sum_append, ih, Nat.succ_mul]; omega

/-- Copies add no longer job. -/
theorem lmax_copies_le (r : Nat) (ds : List Nat) : lmax (copies r ds) ≤ lmax ds := by
  induction r with
  | zero => simp [copies, lmax]
  | succ r ih => simp only [copies, lmax_append]; omega

/-- **Graham's bound for `r` concurrent runs.** The jobs of `r` equal runs on `m` runners finish by. -/
theorem graham_runs (m : Nat) (hm : 0 < m) (r : Nat) (ds : List Nat) :
    m * makespan m (copies r ds) ≤ r * ds.sum + (m - 1) * lmax ds := by
  have h := graham m hm (copies r ds)
  rw [sum_copies] at h
  have := Nat.mul_le_mul_left (m - 1) (lmax_copies_le r ds)
  omega

/-! ### The lower bounds: work over runners, and the longest job -/

/-- The total of a list is at most its length times its maximum. -/
theorem sum_le_len_mul_lmax (l : List Nat) : l.sum ≤ l.length * lmax l := by
  induction l with
  | nil => simp [lmax]
  | cons x xs ih =>
    simp only [List.sum_cons, List.length_cons, lmax]
    have h1 : xs.length * lmax xs ≤ xs.length * max x (lmax xs) := Nat.mul_le_mul_left _ (Nat.le_max_right _ _)
    have h2 : x ≤ max x (lmax xs) := Nat.le_max_left _ _
    rw [Nat.succ_mul]
    omega

/-- Scheduling keeps the number of runners. -/
theorem sched_length : ∀ (ds l : List Nat), l ≠ [] → (sched l ds).length = l.length := by
  intro ds
  induction ds with
  | nil => intro l _; rfl
  | cons d ds ih =>
    intro l hl
    have hne : place l d ≠ [] := by simp [place]
    simp only [sched]
    rw [ih _ hne, place_length l d hl]

/-- Scheduling adds the jobs' total to the load. -/
theorem sched_sum : ∀ (ds l : List Nat), l ≠ [] → (sched l ds).sum = l.sum + ds.sum := by
  intro ds
  induction ds with
  | nil => intro l _; simp [sched]
  | cons d ds ih =>
    intro l hl
    have hne : place l d ≠ [] := by simp [place]
    simp only [sched, List.sum_cons]
    rw [ih _ hne, place_sum l d hl]; omega

/-- **Work lower bound.** `m` runners cannot finish `Σ d_j` of work in less than `Σ d_j / m`. -/
theorem sum_le_mul_makespan (m : Nat) (hm : 0 < m) (ds : List Nat) : ds.sum ≤ m * makespan m ds := by
  have hne : List.replicate m 0 ≠ [] := by
    intro h; have := congrArg List.length h; simp at this; omega
  have h1 := sched_sum ds _ hne
  have h2 := sched_length ds _ hne
  have h3 := sum_le_len_mul_lmax (sched (List.replicate m 0) ds)
  rw [h2] at h3
  simp only [makespan]
  simp at h1 h2
  rw [h1] at h3
  simpa using h3

/-- A member of a list is at most the maximum of the list with it removed, or is that member. -/
theorem lmax_le_erase (a : Nat) (l : List Nat) (h : a ∈ l) : lmax l ≤ max a (lmax (l.erase a)) := by
  induction l with
  | nil => simp at h
  | cons x xs ih =>
    by_cases hx : x = a
    · subst hx; simp [List.erase_cons_head, lmax]
    · have hxs : a ∈ xs := by
        rcases List.mem_cons.1 h with rfl | h'
        · exact absurd rfl hx
        · exact h'
      have : (x :: xs).erase a = x :: xs.erase a := by simp [hx]
      rw [this]; simp only [lmax]
      have := ih hxs
      omega

/-- Placing a job never lowers the maximum load. -/
theorem lmax_le_place (l : List Nat) (d : Nat) : lmax l ≤ lmax (place l d) := by
  by_cases hl : l = []
  · subst hl; simp [lmax]
  · have h1 := lmax_le_erase (pickMin l) l (pickMin_mem hl)
    simp only [place, lmax]
    omega

/-- Scheduling never lowers the maximum load. -/
theorem lmax_le_sched : ∀ (ds l : List Nat), lmax l ≤ lmax (sched l ds) := by
  intro ds
  induction ds with
  | nil => intro l; exact Nat.le_refl _
  | cons d ds ih => intro l; exact Nat.le_trans (lmax_le_place l d) (ih _)

/-- Every job ends on some runner, so the finish time is at least each job. -/
theorem mem_le_lmax_sched : ∀ (ds l : List Nat) (d : Nat), d ∈ ds → d ≤ lmax (sched l ds) := by
  intro ds
  induction ds with
  | nil => intro l d h; simp at h
  | cons x ds ih =>
    intro l d h
    simp only [sched]
    rcases List.mem_cons.1 h with rfl | h'
    · have : d ≤ lmax (place l d) := by
        simp only [place, lmax]; omega
      exact Nat.le_trans this (lmax_le_sched ds _)
    · exact ih _ d h'

/-- **Longest-job lower bound.** No job finishes before it has run. -/
theorem le_makespan (m : Nat) (ds : List Nat) (d : Nat) (h : d ∈ ds) : d ≤ makespan m ds :=
  mem_le_lmax_sched ds _ d h


/-! ## 2. The job split of one gate run -/

/-- The two browser engines of the gate. -/
inductive Eng where
  | chromium
  | webkit
deriving DecidableEq, Repr

/-- The four live-resize sweeps of the gate (`spec.mjs sweepDefs`). A sweep moves between jobs only as a whole. -/
inductive Sw where
  | desktop
  | phone
  | touch
  | pain
deriving DecidableEq, Repr

/-- Position of a sweep in spec order. -/
def Sw.idx : Sw → Nat
  | .desktop => 0
  | .phone => 1
  | .touch => 2
  | .pain => 3

/-- All sweeps, in spec order. -/
def Sw.all : List Sw := [.desktop, .phone, .touch, .pain]

/-- The three short sweeps (5 stops each). -/
def Sw.smalls : List Sw := [.phone, .touch, .pain]

/-- Measured times of one engine, in milliseconds: the fixed cost of a job (checkout, pnpm, build download,
engine install, smoke, the four reference loads), the time per probe, and the time per sweep.
-/
structure EngParams where
  setup : Nat
  perProbe : Nat
  desktop : Nat
  phone : Nat
  touch : Nat
  pain : Nat
deriving Repr

/-- Time of one sweep. -/
def EngParams.sw (p : EngParams) : Sw → Nat
  | .desktop => p.desktop
  | .phone => p.phone
  | .touch => p.touch
  | .pain => p.pain

/-- The times of both engines. -/
structure Params where
  chromium : EngParams
  webkit : EngParams
deriving Repr

/-- The times of one engine. -/
def Params.of (P : Params) : Eng → EngParams
  | .chromium => P.chromium
  | .webkit => P.webkit

/-- One job: an engine, a number of probes and a list of whole sweeps. -/
structure Job where
  eng : Eng
  probes : Nat
  sweeps : List Sw
deriving DecidableEq, Repr

/-- Duration of a job: setup, plus its probes, plus its sweeps. -/
def Job.dur (P : Params) (j : Job) : Nat :=
  let ep := P.of j.eng
  ep.setup + j.probes * ep.perProbe + (j.sweeps.map ep.sw).sum

/-- The matrix has 124 probes per engine (`breakpoints.gen.json` `loadsPerEngine`). -/
def probesPerEngine : Nat := 124

/-- How the sweeps ride with the probe jobs of one engine.

* `sep`: one extra job carries all four sweeps (the current layout).
* `deskSep`: the desktop sweep gets its own job; the three short sweeps ride on probe jobs round-robin.
* `inline`: no extra job; the four sweeps ride on probe jobs round-robin.
-/
inductive Mode where
  | sep
  | deskSep
  | inline
deriving DecidableEq, Repr

/-- The sweeps of `ss` that ride on probe job `i` of `k`: those with `(idx(s) - o) mod k = i`. -/
def ride (k off : Nat) (ss : List Sw) (i : Nat) : List Sw :=
  ss.filter fun s => (s.idx - off) % k == i

/-- The jobs of one engine for `k` probe jobs (probes dealt round-robin, so job `i` gets
`⌊ n/k ⌋ + [i < n mod k]` probes) and a sweep mode.
-/
def jobsOf (e : Eng) (n k : Nat) (md : Mode) : List Job :=
  let sw : Nat → List Sw := fun i => match md with
    | .sep => []
    | .deskSep => ride k 1 Sw.smalls i
    | .inline => ride k 0 Sw.all i
  let probeJobs := (List.range k).map fun i => Job.mk e (n / k + (if i < n % k then 1 else 0)) (sw i)
  let extra : List Job := match md with
    | .sep => [Job.mk e 0 Sw.all]
    | .deskSep => [Job.mk e 0 [Sw.desktop]]
    | .inline => []
  probeJobs ++ extra

/-- One engine's layout: `k` probe jobs and a sweep mode. -/
structure Cfg where
  k : Nat
  md : Mode
deriving DecidableEq, Repr

/-- A plan chooses a layout for each engine. -/
abbrev Plan := Cfg × Cfg

/-- All jobs of a plan: Chromium's, then WebKit's. -/
def planJobs (pl : Plan) : List Job :=
  jobsOf .chromium probesPerEngine pl.1.k pl.1.md ++ jobsOf .webkit probesPerEngine pl.2.k pl.2.md

/-- The job layout of one engine runs each probe once and each sweep once, whole. -/
def ValidEng (js : List Job) : Prop :=
  (js.map Job.probes).sum = probesPerEngine ∧ (js.flatMap Job.sweeps).Perm Sw.all

instance (js : List Job) : Decidable (ValidEng js) := by unfold ValidEng; infer_instance

/-- The current layout: 8 probe shards and one job with all four sweeps, for each engine. -/
def current : Plan := (⟨8, .sep⟩, ⟨8, .sep⟩)

/-- The layouts of one engine considered: 1 to 16 probe jobs and the three sweep modes. -/
def cfgs : List Cfg :=
  (List.range 16).flatMap fun i => [Mode.sep, .deskSep, .inline].map fun md => Cfg.mk (i + 1) md

/-- All plans considered (48 layouts per engine). -/
def plans : List Plan := cfgs.flatMap fun a => cfgs.map fun b => (a, b)

/-- Every layout considered is valid for both engines: each probe and each sweep runs once, whole. -/
theorem cfgs_valid : ∀ c ∈ cfgs, ∀ e : Eng,
    ValidEng (jobsOf e probesPerEngine c.k c.md) := by
  intro c hc e
  revert c
  cases e <;> decide

/-- **Whole sweeps, every probe once.** Every plan considered runs each probe and each sweep of each
engine exactly once; this is the premise of `Fw.Gate.Merge.mergeById_eq_unsharded`.
-/
theorem split_partitions (pl : Plan) (h : pl ∈ plans) :
    ValidEng (jobsOf .chromium probesPerEngine pl.1.k pl.1.md) ∧
    ValidEng (jobsOf .webkit probesPerEngine pl.2.k pl.2.md) := by
  obtain ⟨a, ha, h⟩ := List.mem_flatMap.1 h
  obtain ⟨b, hb, rfl⟩ := List.mem_map.1 h
  exact ⟨cfgs_valid _ ha _, cfgs_valid _ hb _⟩

/-- The current plan is one of the plans considered. -/
theorem current_mem : current ∈ plans :=
  List.mem_flatMap.2 ⟨⟨8, .sep⟩, by decide, List.mem_map.2 ⟨⟨8, .sep⟩, by decide, rfl⟩⟩

/-- Durations of the jobs of a plan. -/
def durs (P : Params) (pl : Plan) : List Nat := (planJobs pl).map (Job.dur P)

/-- Graham's bound for a plan with `r` concurrent runs on `m` runners, times `m`: the finish time of
all jobs of all runs is at most this divided by `m`.
-/
def bound (P : Params) (m r : Nat) (pl : Plan) : Nat :=
  r * (durs P pl).sum + (m - 1) * lmax (durs P pl)

/-- The bound is a bound on the list-scheduling finish time of the `r` runs' jobs. -/
theorem bound_sound (P : Params) (m : Nat) (hm : 0 < m) (r : Nat) (pl : Plan) :
    m * makespan m (copies r (durs P pl)) ≤ bound P m r pl :=
  graham_runs m hm r (durs P pl)

/-- The first plan with the least value of `f`, starting from `best` (a later plan wins only if strictly smaller). -/
def argminBy {α : Type} (f : α → Nat) : α → List α → α
  | best, [] => best
  | best, x :: xs => argminBy f (if f x < f best then x else best) xs

/-- The result is the start or one of the list. -/
theorem argminBy_mem {α : Type} (f : α → Nat) :
    ∀ (xs : List α) (b : α), argminBy f b xs = b ∨ argminBy f b xs ∈ xs := by
  intro xs
  induction xs with
  | nil => intro b; left; rfl
  | cons x xs ih =>
    intro b
    by_cases hx : f x < f b
    · have e : argminBy f b (x :: xs) = argminBy f x xs := by simp [argminBy, hx]
      rw [e]
      rcases ih x with h | h
      · right; rw [h]; exact List.mem_cons_self
      · right; exact List.mem_cons_of_mem _ h
    · have e : argminBy f b (x :: xs) = argminBy f b xs := by simp [argminBy, hx]
      rw [e]
      rcases ih b with h | h
      · left; exact h
      · right; exact List.mem_cons_of_mem _ h

/-- The result is at most the start and every listed element. -/
theorem argminBy_le {α : Type} (f : α → Nat) :
    ∀ (xs : List α) (b : α), f (argminBy f b xs) ≤ f b ∧ ∀ x ∈ xs, f (argminBy f b xs) ≤ f x := by
  intro xs
  induction xs with
  | nil => intro b; exact ⟨Nat.le_refl _, fun x hx => by simp at hx⟩
  | cons x xs ih =>
    intro b
    by_cases hx : f x < f b
    · have e : argminBy f b (x :: xs) = argminBy f x xs := by simp [argminBy, hx]
      rw [e]
      obtain ⟨h1, h2⟩ := ih x
      refine ⟨by omega, fun y hy => ?_⟩
      rcases List.mem_cons.1 hy with rfl | hy
      · exact h1
      · exact h2 y hy
    · have e : argminBy f b (x :: xs) = argminBy f b xs := by simp [argminBy, hx]
      rw [e]
      obtain ⟨h1, h2⟩ := ih b
      refine ⟨h1, fun y hy => ?_⟩
      rcases List.mem_cons.1 hy with rfl | hy
      · omega
      · exact h2 y hy

/-- **The split choice** for `m` runners and `r` concurrent runs: the plan with the least Graham bound,
starting from the current plan.
-/
def choose (P : Params) (m r : Nat) : Plan :=
  argminBy (bound P m r) current plans

/-- **The chosen split is never worse than the current one**, for any times, any `m` and any `r`. -/
theorem choose_le_current (P : Params) (m r : Nat) :
    bound P m r (choose P m r) ≤ bound P m r current :=
  (argminBy_le (bound P m r) plans current).1

/-- The chosen split has the least bound of all plans considered. -/
theorem choose_le_plan (P : Params) (m r : Nat) (pl : Plan) (h : pl ∈ plans) :
    bound P m r (choose P m r) ≤ bound P m r pl :=
  (argminBy_le (bound P m r) plans current).2 pl h

/-- The chosen split is a valid one: each probe and each sweep of each engine runs once, whole. -/
theorem choose_valid (P : Params) (m r : Nat) :
    ValidEng (jobsOf .chromium probesPerEngine (choose P m r).1.k (choose P m r).1.md) ∧
    ValidEng (jobsOf .webkit probesPerEngine (choose P m r).2.k (choose P m r).2.md) := by
  rcases argminBy_mem (bound P m r) plans current with h | h
  · have hc : choose P m r = current := h
    rw [hc]; exact split_partitions current current_mem
  · exact split_partitions _ h

/-- Mapping a record lookup over each job's sweeps and concatenating is mapping it over the concatenation. -/
theorem flatten_sweeps_map {β : Type} (rec : Sw → β) (js : List Job) :
    (js.map (fun j => j.sweeps.map rec)).flatten = (js.flatMap Job.sweeps).map rec := by
  induction js with
  | nil => rfl
  | cons j js ih => rw [List.map_cons, List.flatten_cons, List.flatMap_cons, List.map_append, ih]

/-- **Sharding by whole sweeps reproduces the unsharded run** (the merge law is the real
`Fw.Gate.mergeGateById_eq_unsharded`, not re-proved). Let `rec : Sw → β` give the record of each sweep and
`K = [rec s]_{s ∈ Sw}` the unsharded sweep records. If the run files `F` follow a valid layout `js` (file `j`
holds exactly the records of job `j`'s sweeps, whole), their probes are a permutation of the unsharded probes
`P`, and the headers agree, then the by-id merge gives the unsharded run.
-/
theorem layout_merge_sound {H α β : Type} [DecidableEq H] (hdrOk : H → Bool) (pid : α → String)
    (sid : β → String) (h : H) (P : List α) (rec : Sw → β) (js : List Job) (hv : ValidEng js)
    (files : List (Fw.Gate.RunFile H α β)) (hfj : files.map (·.sweeps) = js.map (fun j => j.sweeps.map rec))
    (hok : hdrOk h = true) (hnd : (P.map pid).Nodup) (hknd : ((Sw.all.map rec).map sid).Nodup)
    (hne : files ≠ []) (hh : ∀ f ∈ files, f.header = h) (hp : (files.flatMap (·.probes)).Perm P) :
    Fw.Gate.mergeGateById hdrOk pid sid (P.map pid) ((Sw.all.map rec).map sid) files
      = some ⟨h, P, Sw.all.map rec⟩ := by
  apply Fw.Gate.mergeGateById_eq_unsharded hdrOk pid sid h P _ files hok hnd hknd hne hh hp
  have e1 : files.flatMap (·.sweeps) = (files.map (·.sweeps)).flatten := by
    rw [List.flatMap_def]
  rw [e1, hfj, flatten_sweeps_map]
  exact hv.2.map rec

/-! ## 3. Times of the note (run 39067656223) -/

/-- Times measured in run 39067656223 (`research/notes/2026/10-18-sweeps-speed.md`, sections A and C),
engine install not cached.

Chromium: setup about 30 s, 23 s of probes per 15.5-probe shard (1.5 s each), sweeps 245, 21, 25, 21 s.
WebKit: setup about 78 s (55 s install and 23 s other), 60 s of probes per shard (3.9 s each), sweeps
191, 26, 27, 23 s.
-/
def noteBase : Params where
  chromium := { setup := 30000, perProbe := 1500, desktop := 245000, phone := 21000, touch := 25000, pain := 21000 }
  webkit := { setup := 78000, perProbe := 3900, desktop := 191000, phone := 26000, touch := 27000, pain := 23000 }

/-- The same with the engine install cached: about 8 s less setup on Chromium and 25 s less on WebKit
(INFERRED in the note; `gate-speed-ci` measures it).
-/
def noteCached : Params where
  chromium := { noteBase.chromium with setup := 22000 }
  webkit := { noteBase.webkit with setup := 53000 }

/-- The cached times with the reduced desktop sweep (35 stops instead of 57, `Fw.Gate.reduceSweep`,
`reducedDeskWidths_eq`), the desktop time scaled by 35/57 (INFERRED; the stops cost about the same each).
-/
def noteReduced : Params where
  chromium := { noteCached.chromium with desktop := 245000 * 35 / 57 }
  webkit := { noteCached.webkit with desktop := 191000 * 35 / 57 }

/-! ## 4. Wall time on `k` free runners, and the fixed jobs around the gate -/

/-- The wall time of one gate run when `k` runners are free for it (the rest of the 20 are held by other runs),
sharing them with `r - 1` other runs of the same split: the job before the gate (`pre`), the gate jobs
queued on `k` runners, and the job after (`post`).
-/
def wall (pre post k r : Nat) (ds : List Nat) : Nat := pre + makespan k (copies r ds) + post

/-- **Wall time is at least the chain and at least the work over the runners.** With `k ≥ 1` free runners and
`r ≥ 1` runs, for every gate job `d`.
-/
theorem wall_lower (pre post k : Nat) (hk : 0 < k) (r : Nat) (hr : 0 < r) (ds : List Nat) :
    (∀ d ∈ ds, pre + d + post ≤ wall pre post k r ds) ∧
    r * ds.sum + k * (pre + post) ≤ k * wall pre post k r ds := by
  refine ⟨fun d hd => ?_, ?_⟩
  · obtain ⟨r', rfl⟩ : ∃ r', r = r' + 1 := ⟨r - 1, by omega⟩
    have : d ∈ copies (r' + 1) ds := by simp only [copies]; exact List.mem_append_left _ hd
    have := le_makespan k _ d this
    simp only [wall]; omega
  · have := sum_le_mul_makespan k hk (copies r ds)
    rw [sum_copies] at this
    simp only [wall, Nat.mul_add]
    omega

/-- **Wall time is at most the chain plus Graham's term.** With `k ≥ 1` free runners and `r` runs. -/
theorem wall_upper (pre post k : Nat) (hk : 0 < k) (r : Nat) (ds : List Nat) :
    k * wall pre post k r ds ≤ k * (pre + post) + (r * ds.sum + (k - 1) * lmax ds) := by
  have := graham_runs k hk r ds
  simp only [wall, Nat.mul_add]
  omega

/-- The fixed jobs around the gate, in milliseconds: the plan job, the site build, the runner setup of a merge
job, the build of `fwcore` and the `summary` of one engine (`.github/workflows/breakpoint-gate.yml`).
-/
structure Fixed where
  plan : Nat
  site : Nat
  mergeSetup : Nat
  fwcore : Nat
  summary : Nat

/-- Before: a plan job, a site job and one merge job per engine, each building `fwcore`. -/
def Fixed.oldJobs (F : Fixed) : List Nat :=
  [F.plan, F.site, F.mergeSetup + F.fwcore + F.summary, F.mergeSetup + F.fwcore + F.summary]

/-- After: the plan runs inside the site job (it needs only the repository), and one merge job builds `fwcore`
once and summarizes both engines.
-/
def Fixed.newJobs (F : Fixed) : List Nat :=
  [F.plan + F.site, F.mergeSetup + F.fwcore + 2 * F.summary]

/-- The wall time with no queue, before: plan and site run side by side, then the gate, then one merge job. -/
def Fixed.oldChain (F : Fixed) (g : Nat) : Nat :=
  max F.plan F.site + g + (F.mergeSetup + F.fwcore + F.summary)

/-- The wall time with no queue, after: site job (with the plan), the gate, one merge job for both engines. -/
def Fixed.newChain (F : Fixed) (g : Nat) : Nat :=
  F.plan + F.site + g + (F.mergeSetup + F.fwcore + 2 * F.summary)

/-- **The new layout starts two jobs fewer** (each takes a runner of the shared 20). -/
theorem Fixed.two_fewer_jobs (F : Fixed) : F.newJobs.length + 2 = F.oldJobs.length := by
  simp [Fixed.newJobs, Fixed.oldJobs]

/-- **The new layout does less runner work, by one setup and one `fwcore` build** (the plan's time moves into
the site job, the second `summary` into the single merge job).
-/
theorem Fixed.work_saved (F : Fixed) : F.oldJobs.sum = F.newJobs.sum + (F.mergeSetup + F.fwcore) := by
  simp only [Fixed.oldJobs, Fixed.newJobs, List.sum_cons, List.sum_nil]
  omega

/-- **The no-queue wall time grows by at most the plan and one `summary`:** -/
theorem Fixed.chain_cost (F : Fixed) (g : Nat) : F.newChain g ≤ F.oldChain g + F.plan + F.summary := by
  simp only [Fixed.newChain, Fixed.oldChain]
  omega

/-- Fixed-job times of runs R1 to R3 of `gate-speed-ci`: plan 5 s, site 40 s, merge setup 20 s, `fwcore` build
36 s, `summary` 13 s (MEASURED from the job timings in `docs/team/handoffs/gate-speed-ci.md`).
-/
def noteFixed : Fixed := ⟨5000, 40000, 20000, 36000, 13000⟩

/-- On the measured times the new layout uses two fewer jobs and 56 s less runner time. -/
theorem noteFixed_savings : noteFixed.newJobs.length + 2 = noteFixed.oldJobs.length ∧
    noteFixed.oldJobs.sum = noteFixed.newJobs.sum + 56000 := by
  refine ⟨Fixed.two_fewer_jobs _, ?_⟩
  rw [Fixed.work_saved]; rfl

end Fw.Gate.Schedule
