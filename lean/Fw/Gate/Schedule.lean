import Fw.Gate.Merge

/-!
# Gate job schedule (task `gate-speed-ci`)

The breakpoint gate fans out into jobs (probe shards, sweep jobs) that GitHub runs on a shared pool of
$m = 20$ identical runners, together with the jobs of $r - 1$ other runs started at the same time. This
module proves how long that can take and picks the job split of one run.

* **Graham's bound** (`graham`): list scheduling of any jobs with durations $d_j$ on $m$ identical
  runners finishes by $C_{\max} \le \sum_j d_j / m + (1 - 1/m)\max_j d_j$. It holds for any arrival
  order, so for any interleaving of the jobs of several runs (`graham_runs`).
* **The split choice** (`choose`): a split is a list of jobs, each with an engine, a number of probes
  and a list of **whole** sweeps. `choose P m r` takes the candidate split with the smallest Graham
  bound for $r$ concurrent runs; it starts from the current split (8 probe shards plus one sweeps job per
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

/-- The largest element of a list (0 for the empty list).

$$\max([\,]) = 0, \qquad \max(x :: xs) = \max(x, \max(xs))$$
-/
def lmax : List Nat → Nat
  | [] => 0
  | x :: xs => max x (lmax xs)

/-- The least element of a non-empty list (0 for the empty list): the runner that frees first.

$$\operatorname{pickMin}(x :: xs) = \min(x, \min xs)$$
-/
def pickMin : List Nat → Nat
  | [] => 0
  | x :: xs => xs.foldl min x

/-- List scheduling places the next job on a least-loaded runner. `loads` holds the load of each runner.

$$\operatorname{place}(L, d) = (a + d) :: (L \setminus \{a\}), \qquad a = \min L$$
-/
def place (loads : List Nat) (d : Nat) : List Nat :=
  (pickMin loads + d) :: loads.erase (pickMin loads)

/-- All jobs in arrival order onto the given runner loads.

$$\operatorname{sched}(L, [\,]) = L, \qquad \operatorname{sched}(L, d :: ds) = \operatorname{sched}(\operatorname{place}(L, d), ds)$$
-/
def sched : List Nat → List Nat → List Nat
  | l, [] => l
  | l, d :: ds => sched (place l d) ds

/-- The finish time of the last job: list scheduling of `ds` on `m` empty runners.

$$C_{\max}(m, ds) = \max \operatorname{sched}(0^m, ds)$$
-/
def makespan (m : Nat) (ds : List Nat) : Nat := lmax (sched (List.replicate m 0) ds)

/-- An element is at most the maximum.

$$y \in L \Rightarrow y \le \max L$$
-/
theorem le_lmax {y : Nat} {l : List Nat} (h : y ∈ l) : y ≤ lmax l := by
  induction l with
  | nil => simp at h
  | cons x xs ih =>
    simp only [lmax]
    rcases List.mem_cons.1 h with rfl | h
    · exact Nat.le_max_left _ _
    · exact Nat.le_trans (ih h) (Nat.le_max_right _ _)

/-- Removing one element does not raise the maximum.

$$\max(L \setminus \{a\}) \le \max L$$
-/
theorem lmax_erase_le (a : Nat) (l : List Nat) : lmax (l.erase a) ≤ lmax l := by
  induction l with
  | nil => simp [lmax]
  | cons x xs ih =>
    by_cases hx : x = a
    · subst hx; simp [List.erase_cons_head, lmax]; omega
    · have : (x :: xs).erase a = x :: xs.erase a := by
        simp [hx]
      rw [this]; simp only [lmax]; omega

/-- Removing a member lowers the sum by exactly that member.

$$a \in L \Rightarrow \textstyle\sum (L \setminus \{a\}) + a = \sum L$$
-/
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

/-- Folding `min` never goes above the start value.

$$\min(a, x_1, \dots, x_n) \le a$$
-/
theorem foldl_min_le_acc (xs : List Nat) : ∀ a, xs.foldl min a ≤ a := by
  induction xs with
  | nil => intro a; exact Nat.le_refl _
  | cons x xs ih => intro a; simp only [List.foldl_cons]; exact Nat.le_trans (ih _) (Nat.min_le_left _ _)

/-- Folding `min` is below every listed element.

$$y \in xs \Rightarrow \min(a, xs) \le y$$
-/
theorem foldl_min_le_mem (xs : List Nat) : ∀ a y, y ∈ xs → xs.foldl min a ≤ y := by
  induction xs with
  | nil => intro a y h; simp at h
  | cons x xs ih =>
    intro a y h
    simp only [List.foldl_cons]
    rcases List.mem_cons.1 h with rfl | h
    · exact Nat.le_trans (foldl_min_le_acc xs _) (Nat.min_le_right _ _)
    · exact ih _ _ h

/-- Folding `min` returns the start value or a listed element.

$$\min(a, xs) = a \ \vee\ \min(a, xs) \in xs$$
-/
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

/-- The least load is one of the loads.

$$L \ne [\,] \Rightarrow \min L \in L$$
-/
theorem pickMin_mem {l : List Nat} (h : l ≠ []) : pickMin l ∈ l := by
  cases l with
  | nil => exact absurd rfl h
  | cons x xs =>
    simp only [pickMin]
    rcases foldl_min_mem xs x with h | h
    · rw [h]; exact List.mem_cons_self
    · exact List.mem_cons_of_mem _ h

/-- The least load is at most every load.

$$y \in L \Rightarrow \min L \le y$$
-/
theorem pickMin_le {l : List Nat} {y : Nat} (h : y ∈ l) : pickMin l ≤ y := by
  cases l with
  | nil => simp at h
  | cons x xs =>
    simp only [pickMin]
    rcases List.mem_cons.1 h with rfl | h
    · exact foldl_min_le_acc xs _
    · exact foldl_min_le_mem xs _ _ h

/-- A lower bound on every element bounds the sum from below.

$$(\forall y \in L.\; a \le y) \Rightarrow a \cdot |L| \le \textstyle\sum L$$
-/
theorem mul_len_le_sum (a : Nat) (l : List Nat) (h : ∀ y ∈ l, a ≤ y) : a * l.length ≤ l.sum := by
  induction l with
  | nil => simp
  | cons x xs ih =>
    have h1 := h x List.mem_cons_self
    have h2 := ih (fun y hy => h y (List.mem_cons_of_mem _ hy))
    simp only [List.length_cons, List.sum_cons, Nat.mul_succ]
    omega

/-- Placing a job keeps the number of runners.

$$L \ne [\,] \Rightarrow |\operatorname{place}(L, d)| = |L|$$
-/
theorem place_length (l : List Nat) (d : Nat) (h : l ≠ []) : (place l d).length = l.length := by
  have := List.length_erase_of_mem (pickMin_mem h)
  have hpos : 0 < l.length := List.length_pos_iff.2 h
  simp only [place, List.length_cons]
  rw [this]; omega

/-- Placing a job adds its duration to the total load.

$$L \ne [\,] \Rightarrow \textstyle\sum \operatorname{place}(L, d) = \sum L + d$$
-/
theorem place_sum (l : List Nat) (d : Nat) (h : l ≠ []) : (place l d).sum = l.sum + d := by
  have := sum_erase _ l (pickMin_mem h)
  simp only [place, List.sum_cons]; omega

/-- The new maximum is the old one or the chosen runner's new load.

$$\max \operatorname{place}(L, d) \le \max(\min L + d,\ \max L)$$
-/
theorem lmax_place_le (l : List Nat) (d : Nat) :
    lmax (place l d) ≤ max (pickMin l + d) (lmax l) := by
  simp only [place, lmax]
  have := lmax_erase_le (pickMin l) l
  omega

/-- One scheduling step keeps the invariant behind Graham's bound: with $k + 1$ runners and largest job
so far at most $M$.

$$(k+1)\max L \le \textstyle\sum L + kM,\ d \le M' ,\ M \le M' \Rightarrow (k+1)\max \operatorname{place}(L, d) \le \sum \operatorname{place}(L, d) + kM'$$
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

/-- The invariant after any list of jobs.

$$(k+1)\max L \le \textstyle\sum L + kM \Rightarrow (k+1)\max \operatorname{sched}(L, ds) \le \sum L + \sum ds + k\max(M, \max ds)$$
-/
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

/-- The maximum of a list of zeros is 0.

$$\max(0^n) = 0$$
-/
theorem lmax_replicate_zero (n : Nat) : lmax (List.replicate n 0) = 0 := by
  induction n with
  | zero => rfl
  | succ n ih => simp [List.replicate_succ, lmax, ih]

/-- **Graham's bound** (list scheduling, integer form). On $m \ge 1$ identical runners, list scheduling
of jobs $d_1, \dots, d_n$ in any order finishes by

$$m \cdot C_{\max} \le \sum_j d_j + (m - 1)\max_j d_j \qquad\Longleftrightarrow\qquad C_{\max} \le \frac{\sum_j d_j}{m} + \Big(1 - \frac1m\Big)\max_j d_j .$$
-/
theorem graham (m : Nat) (hm : 0 < m) (ds : List Nat) :
    m * makespan m ds ≤ ds.sum + (m - 1) * lmax ds := by
  obtain ⟨k, rfl⟩ : ∃ k, m = k + 1 := ⟨m - 1, by omega⟩
  have h := graham_gen k ds (List.replicate (k + 1) 0) 0 (by simp)
    (by simp [lmax_replicate_zero])
  simpa [makespan, lmax_replicate_zero] using h

/-- $r$ runs started at the same time put $r$ copies of the same jobs on the pool, in any order of
arrival (here: one run after the other; Graham's bound holds for every order).

$$\operatorname{copies}(0, ds) = [\,], \qquad \operatorname{copies}(r+1, ds) = ds \mathbin{+\!\!+} \operatorname{copies}(r, ds)$$
-/
def copies : Nat → List Nat → List Nat
  | 0, _ => []
  | r + 1, ds => ds ++ copies r ds

/-- The maximum of an append.

$$\max(A \mathbin{+\!\!+} B) = \max(\max A, \max B)$$
-/
theorem lmax_append (a b : List Nat) : lmax (a ++ b) = max (lmax a) (lmax b) := by
  induction a with
  | nil => simp [lmax]
  | cons x xs ih => simp only [List.cons_append, lmax, ih]; omega

/-- The total of $r$ copies is $r$ times the total.

$$\textstyle\sum \operatorname{copies}(r, ds) = r \sum ds$$
-/
theorem sum_copies (r : Nat) (ds : List Nat) : (copies r ds).sum = r * ds.sum := by
  induction r with
  | zero => simp [copies]
  | succ r ih => simp only [copies, List.sum_append, ih, Nat.succ_mul]; omega

/-- Copies add no longer job.

$$\max \operatorname{copies}(r, ds) \le \max ds$$
-/
theorem lmax_copies_le (r : Nat) (ds : List Nat) : lmax (copies r ds) ≤ lmax ds := by
  induction r with
  | zero => simp [copies, lmax]
  | succ r ih => simp only [copies, lmax_append]; omega

/-- **Graham's bound for $r$ concurrent runs.** The jobs of $r$ equal runs on $m$ runners finish by

$$m \cdot C_{\max}(m, \operatorname{copies}(r, ds)) \le r \sum_j d_j + (m-1)\max_j d_j .$$
-/
theorem graham_runs (m : Nat) (hm : 0 < m) (r : Nat) (ds : List Nat) :
    m * makespan m (copies r ds) ≤ r * ds.sum + (m - 1) * lmax ds := by
  have h := graham m hm (copies r ds)
  rw [sum_copies] at h
  have := Nat.mul_le_mul_left (m - 1) (lmax_copies_le r ds)
  omega


/-! ## 2. The job split of one gate run -/

/-- The two browser engines of the gate.

$$\mathrm{Eng} = \{\text{chromium}, \text{webkit}\}$$
-/
inductive Eng where
  | chromium
  | webkit
deriving DecidableEq, Repr

/-- The four live-resize sweeps of the gate (`spec.mjs sweepDefs`). A sweep moves between jobs only as a whole.

$$\mathrm{Sw} = \{\text{desktop}, \text{phone}, \text{touch}, \text{pain}\}$$
-/
inductive Sw where
  | desktop
  | phone
  | touch
  | pain
deriving DecidableEq, Repr

/-- Position of a sweep in spec order.

$$\operatorname{idx}(\text{desktop}) = 0,\ \operatorname{idx}(\text{phone}) = 1,\ \operatorname{idx}(\text{touch}) = 2,\ \operatorname{idx}(\text{pain}) = 3$$
-/
def Sw.idx : Sw → Nat
  | .desktop => 0
  | .phone => 1
  | .touch => 2
  | .pain => 3

/-- All sweeps, in spec order.

$$\mathrm{Sw} = [\text{desktop}, \text{phone}, \text{touch}, \text{pain}]$$
-/
def Sw.all : List Sw := [.desktop, .phone, .touch, .pain]

/-- The three short sweeps (5 stops each).

$$\mathrm{smalls} = [\text{phone}, \text{touch}, \text{pain}]$$
-/
def Sw.smalls : List Sw := [.phone, .touch, .pain]

/-- Measured times of one engine, in milliseconds: the fixed cost of a job (checkout, pnpm, build download,
engine install, smoke, the four reference loads), the time per probe, and the time per sweep.

$$\mathrm{EngParams} = (\text{setup}, \text{perProbe}, d_{\text{desktop}}, d_{\text{phone}}, d_{\text{touch}}, d_{\text{pain}})$$
-/
structure EngParams where
  setup : Nat
  perProbe : Nat
  desktop : Nat
  phone : Nat
  touch : Nat
  pain : Nat
deriving Repr

/-- Time of one sweep.

$$d(s) = \text{the field of } s$$
-/
def EngParams.sw (p : EngParams) : Sw → Nat
  | .desktop => p.desktop
  | .phone => p.phone
  | .touch => p.touch
  | .pain => p.pain

/-- The times of both engines.

$$P = (P_{\text{chromium}}, P_{\text{webkit}})$$
-/
structure Params where
  chromium : EngParams
  webkit : EngParams
deriving Repr

/-- The times of one engine.

$$P(e) = P_e$$
-/
def Params.of (P : Params) : Eng → EngParams
  | .chromium => P.chromium
  | .webkit => P.webkit

/-- One job: an engine, a number of probes and a list of whole sweeps.

$$\mathrm{Job} = \mathrm{Eng} \times \mathbb N \times \mathrm{Sw}^{*}$$
-/
structure Job where
  eng : Eng
  probes : Nat
  sweeps : List Sw
deriving DecidableEq, Repr

/-- Duration of a job: setup, plus its probes, plus its sweeps.

$$d(j) = \text{setup}_e + p_j \cdot \text{perProbe}_e + \sum_{s \in S_j} d_e(s)$$
-/
def Job.dur (P : Params) (j : Job) : Nat :=
  let ep := P.of j.eng
  ep.setup + j.probes * ep.perProbe + (j.sweeps.map ep.sw).sum

/-- The matrix has 124 probes per engine (`breakpoints.gen.json` `loadsPerEngine`).

$$n = 124$$
-/
def probesPerEngine : Nat := 124

/-- How the sweeps ride with the probe jobs of one engine.

* `sep`: one extra job carries all four sweeps (the current layout).
* `deskSep`: the desktop sweep gets its own job; the three short sweeps ride on probe jobs round-robin.
* `inline`: no extra job; the four sweeps ride on probe jobs round-robin.

$$\mathrm{Mode} = \{\text{sep}, \text{deskSep}, \text{inline}\}$$
-/
inductive Mode where
  | sep
  | deskSep
  | inline
deriving DecidableEq, Repr

/-- The sweeps of `ss` that ride on probe job `i` of `k`: those with $(\operatorname{idx}(s) - o) \bmod k = i$.

$$\operatorname{ride}(k, o, ss, i) = [\, s \in ss \mid (\operatorname{idx}(s) - o) \bmod k = i \,]$$
-/
def ride (k off : Nat) (ss : List Sw) (i : Nat) : List Sw :=
  ss.filter fun s => (s.idx - off) % k == i

/-- The jobs of one engine for `k` probe jobs (probes dealt round-robin, so job $i$ gets
$\lfloor n/k \rfloor + [i < n \bmod k]$ probes) and a sweep mode.

$$\operatorname{jobsOf}(e, n, k, \text{mode}) = [\,(e, \lfloor n/k \rfloor + [i < n \bmod k],\ \text{sweeps}_i)\,]_{i<k} \mathbin{+\!\!+} \text{extra}$$
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

/-- One engine's layout: `k` probe jobs and a sweep mode.

$$\mathrm{Cfg} = \mathbb N \times \mathrm{Mode}$$
-/
structure Cfg where
  k : Nat
  md : Mode
deriving DecidableEq, Repr

/-- A plan chooses a layout for each engine.

$$\mathrm{Plan} = \mathrm{Cfg} \times \mathrm{Cfg}$$
-/
abbrev Plan := Cfg × Cfg

/-- All jobs of a plan: Chromium's, then WebKit's.

$$\operatorname{planJobs}(c_c, c_w) = \operatorname{jobsOf}(\text{chromium}, c_c) \mathbin{+\!\!+} \operatorname{jobsOf}(\text{webkit}, c_w)$$
-/
def planJobs (pl : Plan) : List Job :=
  jobsOf .chromium probesPerEngine pl.1.k pl.1.md ++ jobsOf .webkit probesPerEngine pl.2.k pl.2.md

/-- The job layout of one engine runs each probe once and each sweep once, whole.

$$\sum_j p_j = 124 \ \wedge\ \operatorname{flatMap}(S_j) \text{ is a permutation of } [\text{desktop}, \text{phone}, \text{touch}, \text{pain}]$$
-/
def ValidEng (js : List Job) : Prop :=
  (js.map Job.probes).sum = probesPerEngine ∧ (js.flatMap Job.sweeps).Perm Sw.all

instance (js : List Job) : Decidable (ValidEng js) := by unfold ValidEng; infer_instance

/-- The current layout: 8 probe shards and one job with all four sweeps, for each engine.

$$\mathrm{current} = ((8, \text{sep}), (8, \text{sep}))$$
-/
def current : Plan := (⟨8, .sep⟩, ⟨8, .sep⟩)

/-- The layouts of one engine considered: 1 to 16 probe jobs and the three sweep modes.

$$\mathrm{cfgs} = \{1..16\} \times \mathrm{Mode}$$
-/
def cfgs : List Cfg :=
  (List.range 16).flatMap fun i => [Mode.sep, .deskSep, .inline].map fun md => Cfg.mk (i + 1) md

/-- All plans considered (48 layouts per engine).

$$\mathrm{plans} = \mathrm{cfgs} \times \mathrm{cfgs}$$
-/
def plans : List Plan := cfgs.flatMap fun a => cfgs.map fun b => (a, b)

/-- Every layout considered is valid for both engines: each probe and each sweep runs once, whole.

$$\forall c \in \mathrm{cfgs}, e.\; \operatorname{ValidEng}(\operatorname{jobsOf}(e, 124, c))$$
-/
theorem cfgs_valid : ∀ c ∈ cfgs, ∀ e : Eng,
    ValidEng (jobsOf e probesPerEngine c.k c.md) := by
  intro c hc e
  revert c
  cases e <;> decide

/-- **Whole sweeps, every probe once.** Every plan considered runs each probe and each sweep of each
engine exactly once; this is the premise of `Fw.Gate.Merge.mergeById_eq_unsharded`.

$$pl \in \mathrm{plans} \Rightarrow \operatorname{ValidEng}(\operatorname{jobsOf}(\text{chromium}, pl_1)) \wedge \operatorname{ValidEng}(\operatorname{jobsOf}(\text{webkit}, pl_2))$$
-/
theorem split_partitions (pl : Plan) (h : pl ∈ plans) :
    ValidEng (jobsOf .chromium probesPerEngine pl.1.k pl.1.md) ∧
    ValidEng (jobsOf .webkit probesPerEngine pl.2.k pl.2.md) := by
  obtain ⟨a, ha, h⟩ := List.mem_flatMap.1 h
  obtain ⟨b, hb, rfl⟩ := List.mem_map.1 h
  exact ⟨cfgs_valid _ ha _, cfgs_valid _ hb _⟩

/-- The current plan is one of the plans considered.

$$\mathrm{current} \in \mathrm{plans}$$
-/
theorem current_mem : current ∈ plans :=
  List.mem_flatMap.2 ⟨⟨8, .sep⟩, by decide, List.mem_map.2 ⟨⟨8, .sep⟩, by decide, rfl⟩⟩

/-- Durations of the jobs of a plan.

$$D(P, pl) = [\,d(j)\,]_{j \in \operatorname{planJobs}(pl)}$$
-/
def durs (P : Params) (pl : Plan) : List Nat := (planJobs pl).map (Job.dur P)

/-- Graham's bound for a plan with $r$ concurrent runs on $m$ runners, times $m$: the finish time of
all jobs of all runs is at most this divided by $m$.

$$B(P, m, r, pl) = r \sum_j d_j + (m - 1)\max_j d_j$$
-/
def bound (P : Params) (m r : Nat) (pl : Plan) : Nat :=
  r * (durs P pl).sum + (m - 1) * lmax (durs P pl)

/-- The bound is a bound on the list-scheduling finish time of the $r$ runs' jobs.

$$m \cdot C_{\max}(m, \operatorname{copies}(r, D(P, pl))) \le B(P, m, r, pl)$$
-/
theorem bound_sound (P : Params) (m : Nat) (hm : 0 < m) (r : Nat) (pl : Plan) :
    m * makespan m (copies r (durs P pl)) ≤ bound P m r pl :=
  graham_runs m hm r (durs P pl)

/-- The first plan with the least value of `f`, starting from `best` (a later plan wins only if strictly smaller).

$$\operatorname{argmin}(f, b, []) = b, \qquad \operatorname{argmin}(f, b, x :: xs) = \operatorname{argmin}(f,\ \text{if } f(x) < f(b) \text{ then } x \text{ else } b,\ xs)$$
-/
def argminBy {α : Type} (f : α → Nat) : α → List α → α
  | best, [] => best
  | best, x :: xs => argminBy f (if f x < f best then x else best) xs

/-- The result is the start or one of the list.

$$\operatorname{argmin}(f, b, xs) = b \ \vee\ \operatorname{argmin}(f, b, xs) \in xs$$
-/
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

/-- The result is at most the start and every listed element.

$$f(\operatorname{argmin}(f, b, xs)) \le f(b) \ \wedge\ \forall x \in xs.\; f(\operatorname{argmin}(f, b, xs)) \le f(x)$$
-/
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

/-- **The split choice** for $m$ runners and $r$ concurrent runs: the plan with the least Graham bound,
starting from the current plan.

$$\operatorname{choose}(P, m, r) = \operatorname{argmin}_{pl \in \mathrm{plans}} B(P, m, r, pl) \text{ (ties keep the current plan)}$$
-/
def choose (P : Params) (m r : Nat) : Plan :=
  argminBy (bound P m r) current plans

/-- **The chosen split is never worse than the current one**, for any times, any $m$ and any $r$.

$$B(P, m, r, \operatorname{choose}(P, m, r)) \le B(P, m, r, \mathrm{current})$$
-/
theorem choose_le_current (P : Params) (m r : Nat) :
    bound P m r (choose P m r) ≤ bound P m r current :=
  (argminBy_le (bound P m r) plans current).1

/-- The chosen split has the least bound of all plans considered.

$$pl \in \mathrm{plans} \Rightarrow B(P, m, r, \operatorname{choose}(P, m, r)) \le B(P, m, r, pl)$$
-/
theorem choose_le_plan (P : Params) (m r : Nat) (pl : Plan) (h : pl ∈ plans) :
    bound P m r (choose P m r) ≤ bound P m r pl :=
  (argminBy_le (bound P m r) plans current).2 pl h

/-- The chosen split is a valid one: each probe and each sweep of each engine runs once, whole.

$$\operatorname{ValidEng}(\operatorname{jobsOf}(\text{chromium}, \operatorname{choose}(P,m,r)_1)) \wedge \operatorname{ValidEng}(\operatorname{jobsOf}(\text{webkit}, \operatorname{choose}(P,m,r)_2))$$
-/
theorem choose_valid (P : Params) (m r : Nat) :
    ValidEng (jobsOf .chromium probesPerEngine (choose P m r).1.k (choose P m r).1.md) ∧
    ValidEng (jobsOf .webkit probesPerEngine (choose P m r).2.k (choose P m r).2.md) := by
  rcases argminBy_mem (bound P m r) plans current with h | h
  · have hc : choose P m r = current := h
    rw [hc]; exact split_partitions current current_mem
  · exact split_partitions _ h

/-- Mapping a record lookup over each job's sweeps and concatenating is mapping it over the concatenation.

$$\operatorname{flatten}\big([\,\operatorname{map}\ \mathrm{rec}\ S_j\,]_j\big) = \operatorname{map}\ \mathrm{rec}\ \big(\operatorname{flatMap}\ S\ J\big)$$
-/
theorem flatten_sweeps_map {β : Type} (rec : Sw → β) (js : List Job) :
    (js.map (fun j => j.sweeps.map rec)).flatten = (js.flatMap Job.sweeps).map rec := by
  induction js with
  | nil => rfl
  | cons j js ih => rw [List.map_cons, List.flatten_cons, List.flatMap_cons, List.map_append, ih]

/-- **Sharding by whole sweeps reproduces the unsharded run** (the merge law is the real
`Fw.Gate.mergeGateById_eq_unsharded`, not re-proved). Let `rec : Sw → β` give the record of each sweep and
`K = [rec s]_{s ∈ Sw}` the unsharded sweep records. If the run files `F` follow a valid layout `js` (file $j$
holds exactly the records of job $j$'s sweeps, whole), their probes are a permutation of the unsharded probes
`P`, and the headers agree, then the by-id merge gives the unsharded run.

$$\operatorname{ValidEng}(J) \wedge (\forall j.\ \mathrm{sw}(f_j) = [\mathrm{rec}(s)]_{s \in S_j}) \wedge \operatorname{flatMap}(\mathrm{pr}, F) \sim P \wedge \dots \Rightarrow \operatorname{mg}'\big([\iota(p)]_{p \in P}, [\sigma(k)]_{k \in K}, F\big) = \mathrm{some}(h, P, K)$$
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

$$P_{\text{base}}: \text{setup}\ (30, 78)\,\text{s},\ \text{perProbe}\ (1.5, 3.9)\,\text{s}$$
-/
def noteBase : Params where
  chromium := { setup := 30000, perProbe := 1500, desktop := 245000, phone := 21000, touch := 25000, pain := 21000 }
  webkit := { setup := 78000, perProbe := 3900, desktop := 191000, phone := 26000, touch := 27000, pain := 23000 }

/-- The same with the engine install cached: about 8 s less setup on Chromium and 25 s less on WebKit
(INFERRED in the note; `gate-speed-ci` measures it).

$$P_{\text{cached}}: \text{setup}\ (22, 53)\,\text{s}$$
-/
def noteCached : Params where
  chromium := { noteBase.chromium with setup := 22000 }
  webkit := { noteBase.webkit with setup := 53000 }

/-- The cached times with the reduced desktop sweep (35 stops instead of 57, `Fw.Gate.reduceSweep`,
`reducedDeskWidths_eq`), the desktop time scaled by 35/57 (INFERRED; the stops cost about the same each).

$$P_{\text{reduced}}: d_{\text{desktop}} = \lfloor d \cdot 35 / 57 \rfloor\ (150.4,\ 117.3)\,\text{s}$$
-/
def noteReduced : Params where
  chromium := { noteCached.chromium with desktop := 245000 * 35 / 57 }
  webkit := { noteCached.webkit with desktop := 191000 * 35 / 57 }

end Fw.Gate.Schedule
