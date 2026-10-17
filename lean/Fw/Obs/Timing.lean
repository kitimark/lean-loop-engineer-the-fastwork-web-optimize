import Lean.Data.Json
/-!
# Timing: when an automation step took too long

Every automation step (an `fw` command, a `fw land` phase, a `check.sh` stage, a CI job) records a timing sample
(task `timing-spans`). This module is the pure decision over those samples: is the latest run of a step **slow**
against its own history, and is one step of a parallel stage **structural**, i.e. the one that sets the stage's wall
time by a wide margin (the sweeps-vs-shards case of the breakpoint gate). A step flagged either way is handed to an
agent to investigate and improve (task `timing-alert` wires the op and the alert).

Definitions (all durations in whole ms, `Nat`):
* A sample is $(\mathit{tool}, \mathit{step}, d, h, \lambda)$ with host $h \in \{\mathsf{local}, \mathsf{ci}\}$ and
  $\lambda$ the floor of the 1-min load average when it ran. Its key is $(\mathit{tool}, \mathit{step}, h)$.
* A local sample with $\lambda > L$ is **noisy**: it gets the verdict `noisy` and never enters a window. A CI sample is
  never noisy.
* The **window** of a sample is the last $N$ non-noisy samples with the same key that come before it in the input.
* The **baseline** is the nearest-rank p90 of the window: the $\lceil 9n/10 \rceil$-th smallest of its $n$ values,
  defined by counting (`ord`), so no sort is needed and the proofs are about counts.
* Verdict of one sample, first match: `noBaseline` when the window has fewer than $n_{\min}$ samples; `noisy`; `slow`
  when $d > \max(B, k \cdot b)$ with $B$ the step's budget and $b$ the baseline; otherwise `ok`.
* A **ceiling** is an absolute limit $C(\mathit{tool}, \mathit{step})$ for one step. A non-noisy sample above its
  ceiling is `slow` at once, with no window needed: a step that is slow from its first run (the 2-minute `fw land`)
  has no history to be slow against, so the relative rule alone never alerts for it. `landCeilings` sets 30 s for the
  whole `fw land` and 5 s for the time its lock is held.
* **Structural**: a stage is a list of groups (a group is the list of keys of one job, e.g. the matrix legs of
  `sweeps`); a group's baseline is the largest final baseline of its keys (defined when every key has one). A group is
  structural when its baseline exceeds twice every sibling group's baseline.

Proved (main results; helper lemmas below): `slow_iff`, `ceilingBreach_iff`, `land_budget_alert`, `no_alert_within_budget`, `no_alert_within_budget_list`, `slow_mono_dur`, `noBaseline_iff`,
`noBaseline_below_nmin`, `ord_spec`, `ord_le_iff`, `ord_mono`, `ord_interlace`, `ord_between`, `outlier_between`, `outlier_bound`, `outlier_shift`,
`structural_iff`, `mem_structural`, `deterministic`, `timingVerdicts_total`.

Wire: `timingVerdicts` is the entry point (op `obs.timing`, wired by `timing-alert`); the golden is
`packages/contracts/golden/obs/timing.jsonl`, rendered by `Fw.Wire.Obs.Timing.goldenText` at the end of this file.
-/
namespace Fw.Obs.Timing

/-! ## Samples and parameters -/

/-- Where a sample was taken: on the local machine or on a CI runner.

$$h \in \{\mathsf{local}, \mathsf{ci}\}$$
-/
inductive Host where
  | «local»
  | ci
deriving DecidableEq, Repr

/-- One timing sample: tool, step, duration in ms, host, and the floor of the 1-min load average when it ran.

$$s = (\mathit{tool}, \mathit{step}, d, h, \lambda) \in \mathrm{String} \times \mathrm{String} \times \mathbb N \times \mathrm{Host} \times \mathbb N$$
-/
structure Sample where
  tool  : String
  step  : String
  durMs : Nat
  host  : Host
  load  : Nat := 0
deriving DecidableEq, Repr

/-- The history a sample belongs to: same tool, same step, same host.

$$\kappa = (\mathit{tool}, \mathit{step}, h)$$
-/
structure Key where
  tool : String
  step : String
  host : Host
deriving DecidableEq, Repr

/-- The key of a sample.

$$\operatorname{key}(\mathit{tool}, \mathit{step}, d, h, \lambda) = (\mathit{tool}, \mathit{step}, h)$$
-/
def Sample.key (s : Sample) : Key := { tool := s.tool, step := s.step, host := s.host }

/-- One job of a parallel stage: a name and its keys (the matrix legs of one job, or a single key).

$$g = (\mathit{name}, K),\quad K \text{ a list of keys}$$
-/
structure Group where
  name : String
  keys : List Key
deriving DecidableEq, Repr

/-- A parallel stage: an id and the groups that run side by side in it (the input grouping that defines siblings).

$$S = (\mathit{id}, G),\quad G \text{ a list of groups}$$
-/
structure Stage where
  id     : String
  groups : List Group
deriving DecidableEq, Repr

/-- The parameters: $n_{\min}$ (`nMin`), the window length $N$ (`window`), the multiplier $k = k_n / k_d$
(`kNum`, `kDen`), the default budget $B_0$ in ms (`budgetMs`), per-tool budget overrides (`budgets`, first match
wins), per-step ceilings (`ceilings`, first match wins), the load limit $L$ (`loadMax`, compared with the floor of the 1-min load average; the default 16 is twice the
8 cores of the local Mac), and the parallel stages (`stages`).

$$p = (n_{\min}, N, k_n, k_d, B_0, \beta, \gamma, L, \Sigma) \in \mathbb N^5 \times \mathrm{List}(\mathrm{String} \times \mathbb N) \times \mathrm{List}(\mathrm{String} \times \mathrm{String} \times \mathbb N) \times \mathbb N \times \mathrm{List}(\mathrm{Stage})$$
-/
structure Params where
  nMin     : Nat := 5
  window   : Nat := 20
  kNum     : Nat := 3
  kDen     : Nat := 2
  budgetMs : Nat := 30000
  budgets  : List (String × Nat) := []
  ceilings : List (String × String × Nat) := []
  loadMax  : Nat := 16
  stages   : List Stage := []
deriving Repr

/-! ## Nearest-rank quantile -/

/-- The number of values of `xs` at or below `v`.

$$\operatorname{cntLe}(X, v) = |[x \in X \mid x \le v]|$$
-/
def cntLe (xs : List Nat) (v : Nat) : Nat := xs.countP (fun x => decide (x ≤ v))

/-- The values of `xs` with at least `j + 1` values of `xs` at or below them (in list order).

$$\operatorname{cands}(X, j) = [v \in X \mid \operatorname{cntLe}(X, v) \ge j + 1]$$
-/
def cands (xs : List Nat) (j : Nat) : List Nat := xs.filter (fun v => decide (j + 1 ≤ cntLe xs v))

/-- The order statistic of index `j` (0-based): the least value of `xs` with at least `j + 1` values of `xs` at or
below it, that is the `(j+1)`-th smallest value; 0 when there is none (exactly when $j \ge |X|$).

$$\operatorname{ord}(X, j) = \begin{cases} \min \operatorname{cands}(X, j) & \operatorname{cands}(X, j) \ne [\,] \\ 0 & \text{otherwise} \end{cases}$$
-/
def ord (xs : List Nat) (j : Nat) : Nat := ((cands xs j).min?).getD 0

/-- The nearest rank of the 90th percentile among `n` values: $\lceil 9n/10 \rceil$ (1-based; 0 for `n = 0`).

$$\operatorname{rank}_{90}(n) = \left\lfloor \frac{9n + 9}{10} \right\rfloor = \left\lceil \frac{9n}{10} \right\rceil$$
-/
def rank90 (n : Nat) : Nat := (9 * n + 9) / 10

/-- The nearest-rank p90 of a list: its $\lceil 9n/10 \rceil$-th smallest value; 0 for the empty list.

$$\operatorname{p90}(X) = \operatorname{ord}(X, \operatorname{rank}_{90}(|X|) \mathbin{\dot-} 1)$$
-/
def p90 (xs : List Nat) : Nat := ord xs (rank90 xs.length - 1)

#guard rank90 0 == 0 && rank90 1 == 1 && rank90 9 == 9 && rank90 10 == 9 && rank90 11 == 10 && rank90 20 == 18
#guard ord [5, 1, 4, 1, 3] 0 == 1 && ord [5, 1, 4, 1, 3] 1 == 1 && ord [5, 1, 4, 1, 3] 2 == 3
#guard ord [5, 1, 4, 1, 3] 4 == 5 && ord [5, 1, 4, 1, 3] 5 == 0 && ord [] 0 == 0
#guard p90 [] == 0 && p90 [7] == 7 && p90 [3, 9, 1] == 9
#guard p90 [10, 20, 30, 40, 50, 60, 70, 80, 90, 100] == 90
#guard p90 [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110] == 100

/-! ## The verdict of one sample -/

/-- A sample is noisy when it ran locally at a load above the limit (CI samples never are).

$$\operatorname{noisy}_p(s) \iff h_s = \mathsf{local} \wedge \lambda_s > L$$
-/
def noisy (p : Params) (s : Sample) : Bool := decide (s.host = .«local») && decide (p.loadMax < s.load)

/-- The last `n` elements of a list (all of it when it is shorter).

$$\operatorname{lastN}(n, X) = \operatorname{drop}(|X| \mathbin{\dot-} n, X)$$
-/
def lastN (n : Nat) (xs : List Nat) : List Nat := xs.drop (xs.length - n)

/-- The window of key `k` in a history: the durations of the last $N$ samples of `hist` with key `k` that are not
noisy, oldest first.

$$\operatorname{win}_p(H, \kappa) = \operatorname{lastN}\bigl(N, [\, d_s \mid s \in H,\ \operatorname{key}(s) = \kappa,\ \neg\operatorname{noisy}_p(s) \,]\bigr)$$
-/
def windowOf (p : Params) (hist : List Sample) (k : Key) : List Nat :=
  lastN p.window ((hist.filter (fun s => decide (s.key = k) && !noisy p s)).map (·.durMs))

/-- The budget of a tool: its first override in `budgets`, else the default $B_0$.

$$B_p(\mathit{tool}) = \begin{cases} b & (\mathit{tool}, b) \text{ is the first pair of } \beta \text{ with that tool} \\ B_0 & \text{no pair of } \beta \text{ has that tool} \end{cases}$$
-/
def budgetOf (p : Params) (tool : String) : Nat := (p.budgets.lookup tool).getD p.budgetMs

/-- The ceiling of a step: the limit of the first entry of `ceilings` with that tool and step, if any.

$$C_p(\mathit{tool}, \mathit{step}) = \begin{cases} c & (\mathit{tool}, \mathit{step}, c) \text{ is the first triple of } \gamma \text{ with that tool and step} \\ \bot & \text{no such triple} \end{cases}$$
-/
def ceilingOf (p : Params) (tool step : String) : Option Nat :=
  (p.ceilings.find? (fun c => decide (c.1 = tool) && decide (c.2.1 = step))).map (·.2.2)

/-- A sample breaches its ceiling when its step has one, the sample is not noisy, and it took longer than the ceiling.
No window is involved.

$$\operatorname{breach}_p(s) \iff \exists c.\ C_p(\mathit{tool}_s, \mathit{step}_s) = c \wedge d_s > c \wedge \neg\operatorname{noisy}_p(s)$$
-/
def ceilingBreach (p : Params) (s : Sample) : Bool :=
  match ceilingOf p s.tool s.step with
  | some c => decide (c < s.durMs) && !noisy p s
  | none => false

/-- The budget a sample is held to: its tool's budget, lowered to the step's ceiling when the step has one.

$$B^*_p(s) = \begin{cases} \min(B_p(\mathit{tool}_s), c) & C_p(\mathit{tool}_s, \mathit{step}_s) = c \\ B_p(\mathit{tool}_s) & \text{no ceiling} \end{cases}$$
-/
def budgetFor (p : Params) (s : Sample) : Nat :=
  match ceilingOf p s.tool s.step with
  | some c => min (budgetOf p s.tool) c
  | none => budgetOf p s.tool

/-- The slow test, exact over the rationals: $d > \max(B, k \cdot b)$ with $k = k_n / k_d$, cross-multiplied so no
division happens (for $k_d \ge 1$ it is the same as $d > B \wedge d > k \cdot b$; for $k_d = 0$ the second half is
false and nothing is slow).

$$\operatorname{over}_p(B, b, d) \iff d > B \wedge k_d \cdot d > k_n \cdot b$$
-/
def overLimit (p : Params) (budget base d : Nat) : Bool :=
  decide (budget < d) && decide (p.kNum * base < p.kDen * d)

/-- The verdict code of one sample.

$$c \in \{\mathsf{noBaseline}, \mathsf{noisy}, \mathsf{ok}, \mathsf{slow}\}$$
-/
inductive Code where
  | noBaseline
  | noisy
  | ok
  | slow
deriving DecidableEq, Repr

/-- The code of sample `s` against window `w`, first match: too short a window, noisy, slow, ok (with
$n_{\min} = 0$ an empty window passes the first test and has baseline 0).

$$\operatorname{code}_p(w, s) = \begin{cases} \mathsf{noBaseline} & |w| < n_{\min} \\ \mathsf{noisy} & \operatorname{noisy}_p(s) \\ \mathsf{slow} & \operatorname{over}_p(B_p(\mathit{tool}_s), \operatorname{p90}(w), d_s) \\ \mathsf{ok} & \text{otherwise} \end{cases}$$
-/
def codeOf (p : Params) (w : List Nat) (s : Sample) : Code :=
  if w.length < p.nMin then .noBaseline
  else if noisy p s then .noisy
  else if overLimit p (budgetOf p s.tool) (p90 w) s.durMs then .slow
  else .ok

/-- The verdict of one sample: its index, key and duration, the code, the window size, the baseline (p90 of the
window, 0 for an empty window) and the budget.

$$v = (i, \mathit{tool}, \mathit{step}, h, d, c, n, b, B)$$
-/
structure SampleVerdict where
  idx      : Nat
  tool     : String
  step     : String
  host     : Host
  durMs    : Nat
  code     : Code
  n        : Nat
  baseline : Nat
  budgetMs : Nat
deriving DecidableEq, Repr

/-- The verdict of sample `s` at index `i` with the earlier samples `hist`: `slow` when it breaches its step's ceiling
(whatever the window), else the code against the window.

$$\operatorname{judge}_p(H, i, s) = (i, \mathit{tool}_s, \mathit{step}_s, h_s, d_s, c, |w|, \operatorname{p90}(w), B^*_p(s)),\quad c = \begin{cases} \mathsf{slow} & \operatorname{breach}_p(s) \\ \operatorname{code}_p(w, s) & \text{otherwise} \end{cases},\quad w = \operatorname{win}_p(H, \operatorname{key}(s))$$
-/
def judge (p : Params) (hist : List Sample) (i : Nat) (s : Sample) : SampleVerdict :=
  let w := windowOf p hist s.key
  { idx := i, tool := s.tool, step := s.step, host := s.host, durMs := s.durMs,
    code := if ceilingBreach p s then .slow else codeOf p w s,
    n := w.length, baseline := p90 w, budgetMs := budgetFor p s }

/-- One verdict per sample, in input order; sample $i$ is judged against the samples before it.

$$\operatorname{sv}_p([s_0, \dots, s_{m-1}]) = [\operatorname{judge}_p([s_0, \dots, s_{i-1}], i, s_i) \mid 0 \le i < m]$$
-/
def sampleVerdicts (p : Params) (ss : List Sample) : List SampleVerdict :=
  ss.mapIdx (fun i s => judge p (ss.take i) i s)

/-! ## Structural verdicts -/

/-- The final baseline of a key: the p90 of its window over all samples, defined when that window has at least
$n_{\min}$ samples.

$$\operatorname{fb}_p(H, \kappa) = \begin{cases} \operatorname{p90}(\operatorname{win}_p(H, \kappa)) & |\operatorname{win}_p(H, \kappa)| \ge n_{\min} \\ \bot & \text{otherwise} \end{cases}$$
-/
def finalBaseline (p : Params) (ss : List Sample) (k : Key) : Option Nat :=
  if p.nMin ≤ (windowOf p ss k).length then some (p90 (windowOf p ss k)) else none

/-- The largest value of a list, 0 for the empty list.

$$\operatorname{maxL}([x_1, \dots, x_m]) = \max(0, x_1, \dots, x_m)$$
-/
def maxL (xs : List Nat) : Nat := xs.foldl max 0

/-- A group's baseline: the largest final baseline of its keys, defined when the group has a key and every key has a
final baseline.

$$\operatorname{gb}_p(H, (\mathit{name}, K)) = \begin{cases} \max_{\kappa \in K} \operatorname{fb}_p(H, \kappa) & K \ne [\,] \wedge \forall \kappa \in K.\ \operatorname{fb}_p(H, \kappa) \ne \bot \\ \bot & \text{otherwise} \end{cases}$$
-/
def groupBaseline (p : Params) (ss : List Sample) (g : Group) : Option Nat :=
  let bs := g.keys.filterMap (finalBaseline p ss)
  if !g.keys.isEmpty && bs.length == g.keys.length then some (maxL bs) else none

/-- A structural verdict: the stage, the group that sets its wall time, its baseline and the largest sibling
baseline.

$$\sigma = (\mathit{stage}, \mathit{group}, b, c_{\max})$$
-/
structure StructVerdict where
  stage      : String
  group      : String
  baseline   : Nat
  siblingMax : Nat
deriving DecidableEq, Repr

/-- The test on the sibling baselines: every sibling has one and twice it is below `b`.

$$\operatorname{below}(b, o) \iff \exists c.\ o = \mathsf{some}(c) \wedge 2c < b$$
-/
def below (b : Nat) : Option Nat → Bool
  | some c => decide (2 * c < b)
  | none => false

/-- The structural verdict of group `g` in stage `S`: present when `g` has a baseline $b$, the stage has another
group, and every other group of the stage has a baseline $c$ with $2c < b$ (a group listed twice is not its own
sibling).

$$\operatorname{st}_p(H, S, g) = \begin{cases} (\mathit{id}_S, \mathit{name}_g, b, \max_{g'} c_{g'}) & \operatorname{gb}_p(H, g) = b \wedge [g' \in G_S \mid g' \ne g] \ne [\,] \wedge \forall g' \in G_S.\ g' \ne g \Rightarrow \exists c_{g'}.\ \operatorname{gb}_p(H, g') = c_{g'} \wedge 2 c_{g'} < b \\ \bot & \text{otherwise} \end{cases}$$
-/
def structuralOf (p : Params) (ss : List Sample) (st : Stage) (g : Group) : Option StructVerdict :=
  match groupBaseline p ss g with
  | none => none
  | some b =>
    let sib := (st.groups.filter (fun g' => decide (g' ≠ g))).map (groupBaseline p ss)
    if !sib.isEmpty && sib.all (below b) then
      some { stage := st.id, group := g.name, baseline := b, siblingMax := maxL (sib.filterMap id) }
    else none

/-- All structural verdicts: stage by stage, group by group.

$$\operatorname{sts}_p(H) = [\operatorname{st}_p(H, S, g) \mid S \in \Sigma,\ g \in G_S,\ \operatorname{st}_p(H, S, g) \ne \bot]$$
-/
def structuralVerdicts (p : Params) (ss : List Sample) : List StructVerdict :=
  p.stages.flatMap (fun st => st.groups.filterMap (structuralOf p ss st))

/-- A verdict: one per sample, or a structural one.

$$V = \mathrm{SampleVerdict} \sqcup \mathrm{StructVerdict}$$
-/
inductive Verdict where
  | sample (v : SampleVerdict)
  | structural (v : StructVerdict)
deriving DecidableEq, Repr

/-- The entry point (wire op `obs.timing`): the samples in time order give one verdict each, in order, followed by
the structural verdicts.

$$\operatorname{timingVerdicts}(p, H) = \operatorname{map}(\mathsf{sample}, \operatorname{sv}_p(H)) \mathbin{+\!\!+} \operatorname{map}(\mathsf{structural}, \operatorname{sts}_p(H))$$
-/
def timingVerdicts (p : Params) (ss : List Sample) : List Verdict :=
  (sampleVerdicts p ss).map .sample ++ (structuralVerdicts p ss).map .structural

/-- A local key for the examples below. -/
private def lk : Key := { tool := "t", step := "s", host := .«local» }

#guard (codeOf {} [] { tool := "t", step := "s", durMs := 999999, host := .ci }) == .noBaseline
#guard (codeOf {} [100, 100, 100, 100, 100] { tool := "t", step := "s", durMs := 30000, host := .ci }) == .ok
#guard (codeOf {} [100, 100, 100, 100, 100] { tool := "t", step := "s", durMs := 30001, host := .ci }) == .slow
#guard (codeOf {} [100000, 100000, 100000, 100000, 100000]
  { tool := "t", step := "s", durMs := 150000, host := .ci }) == .ok
#guard (codeOf {} [100000, 100000, 100000, 100000, 100000]
  { tool := "t", step := "s", durMs := 150001, host := .ci }) == .slow
#guard (codeOf {} [100000, 100000, 100000, 100000, 100000]
  { tool := "t", step := "s", durMs := 150001, host := .«local», load := 17 }) == .noisy
#guard (codeOf {} [100000, 100000, 100000, 100000, 100000]
  { tool := "t", step := "s", durMs := 150001, host := .ci, load := 99 }) == .slow
#guard budgetOf { budgets := [("ci", 120000), ("ci", 1)] } "ci" == 120000 && budgetOf {} "x" == 30000
#guard windowOf { window := 2 } [{ tool := "t", step := "s", durMs := 1, host := .«local» },
  { tool := "t", step := "s", durMs := 2, host := .«local», load := 17 },
  { tool := "t", step := "s", durMs := 3, host := .«local» },
  { tool := "t", step := "s", durMs := 4, host := .ci },
  { tool := "t", step := "s", durMs := 5, host := .«local» }] lk == [3, 5]
#guard (timingVerdicts { nMin := 1, stages := [{ id := "x", groups := [{ name := "a", keys := [lk] },
  { name := "b", keys := [{ lk with step := "b" }] }] }] }
  [{ tool := "t", step := "s", durMs := 100, host := .«local» },
   { tool := "t", step := "b", durMs := 49, host := .«local» }]).length == 3
#guard (structuralOf { nMin := 1 } [{ tool := "t", step := "s", durMs := 100, host := .«local» },
   { tool := "t", step := "b", durMs := 50, host := .«local» }]
  { id := "x", groups := [{ name := "a", keys := [lk] }, { name := "b", keys := [{ lk with step := "b" }] }] }
  { name := "a", keys := [lk] }).isNone

/-! ## Proofs: the verdict of one sample -/

/-- A sample breaches its ceiling exactly when its step has a ceiling $c$, it is not noisy and it took longer than $c$.

$$\forall p, s:\quad \operatorname{breach}_p(s) \iff \exists c.\ C_p(\mathit{tool}_s, \mathit{step}_s) = c \wedge c < d_s \wedge \neg\operatorname{noisy}_p(s)$$
-/
theorem ceilingBreach_iff (p : Params) (s : Sample) :
    ceilingBreach p s = true ↔
      ∃ c, ceilingOf p s.tool s.step = some c ∧ c < s.durMs ∧ noisy p s = false := by
  unfold ceilingBreach
  cases h : ceilingOf p s.tool s.step with
  | none => simp
  | some c => simp

/-- The relative rule alone: the code against a window is `slow` exactly when the window is long enough, the sample is
not noisy, and its duration exceeds both the budget and $k$ times the baseline.

$$\forall p, w, s:\quad \operatorname{code}_p(w, s) = \mathsf{slow} \iff |w| \ge n_{\min} \wedge \neg\operatorname{noisy}_p(s) \wedge d_s > B_p(\mathit{tool}_s) \wedge k_d \cdot d_s > k_n \cdot \operatorname{p90}(w)$$
-/
theorem codeOf_slow_iff (p : Params) (w : List Nat) (s : Sample) :
    codeOf p w s = .slow ↔
      p.nMin ≤ w.length ∧ noisy p s = false ∧ budgetOf p s.tool < s.durMs ∧
        p.kNum * p90 w < p.kDen * s.durMs := by
  unfold codeOf overLimit
  split
  · constructor
    · intro h; cases h
    · intro h; omega
  · rename_i h1
    split
    · rename_i h2
      constructor
      · intro h; cases h
      · intro h; rw [h2] at h; cases h.2.1
    · rename_i h2
      have h2' : noisy p s = false := by simpa using h2
      split
      · rename_i h3
        simp only [Bool.and_eq_true, decide_eq_true_eq] at h3
        exact ⟨fun _ => ⟨by omega, h2', h3⟩, fun _ => rfl⟩
      · rename_i h3
        simp only [Bool.and_eq_true, decide_eq_true_eq] at h3
        constructor
        · intro h; cases h
        · intro h; exact absurd ⟨h.2.2.1, h.2.2.2⟩ h3

/-- When a sample's verdict is `slow`: it breaches its step's ceiling (no window needed), or the window is long
enough, the sample is not noisy, and its duration exceeds both the budget and $k$ times the baseline.

$$\forall p, H, i, s:\quad \operatorname{judge}_p(H, i, s).c = \mathsf{slow} \iff \operatorname{breach}_p(s) \vee \bigl(|w| \ge n_{\min} \wedge \neg\operatorname{noisy}_p(s) \wedge d_s > B_p(\mathit{tool}_s) \wedge k_d \cdot d_s > k_n \cdot \operatorname{p90}(w)\bigr),\quad w = \operatorname{win}_p(H, \operatorname{key}(s))$$
-/
theorem slow_iff (p : Params) (hist : List Sample) (i : Nat) (s : Sample) :
    (judge p hist i s).code = .slow ↔
      ceilingBreach p s = true ∨
      (p.nMin ≤ (windowOf p hist s.key).length ∧ noisy p s = false ∧ budgetOf p s.tool < s.durMs ∧
        p.kNum * p90 (windowOf p hist s.key) < p.kDen * s.durMs) := by
  unfold judge
  simp only
  by_cases hb : ceilingBreach p s = true
  · simp [hb]
  · simp only [hb, Bool.false_eq_true, ite_false, false_or]
    exact codeOf_slow_iff p _ s

/-- No alert within budget: a sample whose duration is at most its budget (its tool's budget, lowered to the step's
ceiling) is never `slow`.

$$\forall p, H, i, s:\quad d_s \le B^*_p(s) \Rightarrow \operatorname{judge}_p(H, i, s).c \ne \mathsf{slow}$$
-/
theorem no_alert_within_budget (p : Params) (hist : List Sample) (i : Nat) (s : Sample)
    (h : s.durMs ≤ budgetFor p s) : (judge p hist i s).code ≠ .slow := by
  intro hs
  unfold budgetFor at h
  rcases (slow_iff p hist i s).1 hs with hb | hr
  · obtain ⟨c, hc, hlt, _⟩ := (ceilingBreach_iff p s).1 hb
    rw [hc] at h
    simp only at h
    omega
  · have := hr.2.2.1
    cases hc : ceilingOf p s.tool s.step with
    | none => rw [hc] at h; simp only at h; omega
    | some c => rw [hc] at h; simp only at h; omega

/-- Every sample verdict of the entry point is `judge` of its sample against the samples before it.

$$\forall p, H, v:\quad \mathsf{sample}(v) \in \operatorname{timingVerdicts}(p, H) \Rightarrow \exists i < |H|.\ v = \operatorname{judge}_p(\operatorname{take}(i, H), i, H_i)$$
-/
theorem mem_sample (p : Params) (hist : List Sample) (v : SampleVerdict)
    (h : Verdict.sample v ∈ timingVerdicts p hist) :
    ∃ i, ∃ hi : i < hist.length, v = judge p (hist.take i) i hist[i] := by
  simp only [timingVerdicts, List.mem_append, List.mem_map] at h
  rcases h with ⟨w, hw, he⟩ | ⟨w, _, he⟩
  · cases he
    obtain ⟨i, hi, he⟩ := List.mem_iff_getElem.1 hw
    have hi' : i < hist.length := by simpa [sampleVerdicts, List.length_mapIdx] using hi
    refine ⟨i, hi', ?_⟩
    rw [← he]
    simp [sampleVerdicts, List.getElem_mapIdx]
  · cases he

/-- No alert within budget, over the whole output: a sample verdict whose duration is at most its budget is not
`slow`.

$$\forall p, H, v:\quad \mathsf{sample}(v) \in \operatorname{timingVerdicts}(p, H) \wedge d_v \le B_v \Rightarrow c_v \ne \mathsf{slow}$$
-/
theorem no_alert_within_budget_list (p : Params) (hist : List Sample) (v : SampleVerdict)
    (h : Verdict.sample v ∈ timingVerdicts p hist) (hb : v.durMs ≤ v.budgetMs) : v.code ≠ .slow := by
  obtain ⟨i, hi, rfl⟩ := mem_sample p hist v h
  exact no_alert_within_budget p _ i _ hb

/-- The ceilings of `fw land`, from the land-speed research targets (a Lean-touching land under 20 s p50, the lock
held under 5 s): 30 s for the whole land (step `total`) and 5 s for the time its lock is held (step `lock held`).

$$\gamma_{\mathrm{land}} = [(\texttt{fw land}, \texttt{total}, 30000),\ (\texttt{fw land}, \texttt{lock held}, 5000)]$$
-/
def landCeilings : List (String × String × Nat) :=
  [("fw land", "total", 30000), ("fw land", "lock held", 5000)]

/-- A land over budget alerts. With the land ceilings first in `ceilings`, a non-noisy `fw land` sample over 30 s for
its `total`, or over 5 s for its `lock held`, has the verdict `slow`, whatever its history (even none: a land that is
slow from its first run is flagged).

$$\forall p, H, i, s:\quad \gamma_{\mathrm{land}} \mathbin{+\!\!+} \gamma' = \gamma_p \wedge \neg\operatorname{noisy}_p(s) \wedge \mathit{tool}_s = \texttt{fw land} \wedge \bigl(\mathit{step}_s = \texttt{total} \wedge d_s > 30000 \vee \mathit{step}_s = \texttt{lock held} \wedge d_s > 5000\bigr) \Rightarrow \operatorname{judge}_p(H, i, s).c = \mathsf{slow}$$
-/
theorem land_budget_alert (p : Params) (hp : ∃ rest, p.ceilings = landCeilings ++ rest)
    (hist : List Sample) (i : Nat) (s : Sample) (hn : noisy p s = false)
    (hs : (s.tool = "fw land" ∧ s.step = "total" ∧ 30000 < s.durMs) ∨
          (s.tool = "fw land" ∧ s.step = "lock held" ∧ 5000 < s.durMs)) :
    (judge p hist i s).code = .slow := by
  obtain ⟨rest, hr⟩ := hp
  refine (slow_iff p hist i s).2 (Or.inl ((ceilingBreach_iff p s).2 ?_))
  rcases hs with ⟨ht, hst, hd⟩ | ⟨ht, hst, hd⟩
  · exact ⟨30000, by simp [ceilingOf, hr, landCeilings, ht, hst], hd, hn⟩
  · exact ⟨5000, by simp [ceilingOf, hr, landCeilings, ht, hst], hd, hn⟩

/-- Slow is monotone in the duration: with the same history, a sample that is `slow` stays `slow` when it takes
longer.

$$\forall p, H, i, s, d':\quad \operatorname{judge}_p(H, i, s).c = \mathsf{slow} \wedge d_s \le d' \Rightarrow \operatorname{judge}_p(H, i, s[d := d']).c = \mathsf{slow}$$
-/
theorem slow_mono_dur (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (d : Nat)
    (h : (judge p hist i s).code = .slow) (hd : s.durMs ≤ d) :
    (judge p hist i { s with durMs := d }).code = .slow := by
  rcases (slow_iff p hist i s).1 h with hb | ⟨h1, h2, h3, h4⟩
  · obtain ⟨c, hc, hlt, hn⟩ := (ceilingBreach_iff p s).1 hb
    exact (slow_iff p hist i _).2 (Or.inl ((ceilingBreach_iff p _).2 ⟨c, hc, by simp only; omega, hn⟩))
  · refine (slow_iff p hist i _).2 (Or.inr ⟨h1, h2, by simp only; omega, ?_⟩)
    exact Nat.lt_of_lt_of_le h4 (Nat.mul_le_mul_left _ hd)

/-- The verdict is `noBaseline` exactly when the window has fewer than $n_{\min}$ samples and the sample does not
breach a ceiling (a breach is `slow` whatever the window).

$$\forall p, H, i, s:\quad \operatorname{judge}_p(H, i, s).c = \mathsf{noBaseline} \iff |\operatorname{win}_p(H, \operatorname{key}(s))| < n_{\min} \wedge \neg\operatorname{breach}_p(s)$$
-/
theorem noBaseline_iff (p : Params) (hist : List Sample) (i : Nat) (s : Sample) :
    (judge p hist i s).code = .noBaseline ↔
      (windowOf p hist s.key).length < p.nMin ∧ ceilingBreach p s = false := by
  by_cases hb : ceilingBreach p s = true
  · simp [judge, hb]
  · have hb' : ceilingBreach p s = false := by simpa using hb
    simp only [judge, hb', Bool.false_eq_true, ite_false, and_true, codeOf]
    by_cases h1 : (windowOf p hist s.key).length < p.nMin
    · simp [h1]
    · simp only [h1, ite_false, iff_false]
      split
      · intro h; cases h
      · split <;> (intro h; cases h)

/-- The window is at most $N$ long and at most as long as the number of earlier samples with the same key.

$$\forall p, H, \kappa:\quad |\operatorname{win}_p(H, \kappa)| \le N \wedge |\operatorname{win}_p(H, \kappa)| \le |[s \in H \mid \operatorname{key}(s) = \kappa]|$$
-/
theorem window_length (p : Params) (hist : List Sample) (k : Key) :
    (windowOf p hist k).length ≤ p.window ∧
      (windowOf p hist k).length ≤ hist.countP (fun s => decide (s.key = k)) := by
  have hc : (hist.filter (fun s => decide (s.key = k) && !noisy p s)).length ≤
      hist.countP (fun s => decide (s.key = k)) := by
    rw [← List.countP_eq_length_filter]
    exact List.countP_mono_left (by intro x _ hx; simp only [Bool.and_eq_true] at hx; exact hx.1)
  simp only [windowOf, lastN, List.length_drop, List.length_map]
  omega

/-- Below $n_{\min}$, no verdict: with fewer than $n_{\min}$ earlier samples of the same key, or a window shorter than
$n_{\min}$, the verdict is `noBaseline` (unless the sample breaches a ceiling, which needs no window).

$$\forall p, H, i, s:\quad \neg\operatorname{breach}_p(s) \wedge \bigl(|[t \in H \mid \operatorname{key}(t) = \operatorname{key}(s)]| < n_{\min} \vee N < n_{\min}\bigr) \Rightarrow \operatorname{judge}_p(H, i, s).c = \mathsf{noBaseline}$$
-/
theorem noBaseline_below_nmin (p : Params) (hist : List Sample) (i : Nat) (s : Sample)
    (hb : ceilingBreach p s = false)
    (h : hist.countP (fun t => decide (t.key = s.key)) < p.nMin ∨ p.window < p.nMin) :
    (judge p hist i s).code = .noBaseline := by
  have := window_length p hist s.key
  exact (noBaseline_iff p hist i s).2 ⟨by omega, hb⟩

/-- Deterministic and local: the verdict of a sample depends only on the parameters, the sample, its index and the
earlier samples with the same key (samples of other steps or hosts, in any interleaving, change nothing).

$$\forall p, H, i, s:\quad \operatorname{judge}_p(H, i, s) = \operatorname{judge}_p([t \in H \mid \operatorname{key}(t) = \operatorname{key}(s)], i, s)$$
-/
theorem deterministic (p : Params) (hist : List Sample) (i : Nat) (s : Sample) :
    judge p hist i s = judge p (hist.filter (fun t => decide (t.key = s.key))) i s := by
  have : windowOf p hist s.key = windowOf p (hist.filter (fun t => decide (t.key = s.key))) s.key := by
    simp only [windowOf, List.filter_filter]
    congr 3
    funext x
    cases decide (x.key = s.key) <;> simp
  simp only [judge, this]

/-- Total: the output holds one verdict per sample, in input order (sample $i$ judged against the samples before
it), followed by the structural verdicts.

$$\forall p, H:\quad |\operatorname{timingVerdicts}(p, H)| = |H| + |\operatorname{sts}_p(H)| \wedge \forall i < |H|.\ \operatorname{timingVerdicts}(p, H)_i = \mathsf{sample}(\operatorname{judge}_p(\operatorname{take}(i, H), i, H_i))$$
-/
theorem timingVerdicts_total (p : Params) (hist : List Sample) :
    (timingVerdicts p hist).length = hist.length + (structuralVerdicts p hist).length ∧
      ∀ i (hi : i < hist.length),
        (timingVerdicts p hist)[i]? = some (.sample (judge p (hist.take i) i hist[i])) := by
  refine ⟨by simp [timingVerdicts, sampleVerdicts], ?_⟩
  intro i hi
  have hl : i < ((sampleVerdicts p hist).map Verdict.sample).length := by simpa [sampleVerdicts] using hi
  rw [timingVerdicts, List.getElem?_append_left hl]
  simp [sampleVerdicts, hi]

/-! ## Proofs: the order statistic and the outlier bound -/

/-- Every non-empty list of naturals has a largest element.

$$\forall X:\quad X \ne [\,] \Rightarrow \exists u \in X.\ \forall x \in X.\ x \le u$$
-/
theorem exists_max (xs : List Nat) (h : xs ≠ []) : ∃ u ∈ xs, ∀ x ∈ xs, x ≤ u := by
  induction xs with
  | nil => exact absurd rfl h
  | cons a t ih =>
    by_cases ht : t = []
    · subst ht
      exact ⟨a, by simp, by simp⟩
    · obtain ⟨u, hu, hm⟩ := ih ht
      by_cases hau : a ≤ u
      · refine ⟨u, List.mem_cons_of_mem _ hu, ?_⟩
        intro x hx
        rcases List.mem_cons.1 hx with rfl | hx
        · exact hau
        · exact hm x hx
      · refine ⟨a, List.mem_cons_self, ?_⟩
        intro x hx
        rcases List.mem_cons.1 hx with rfl | hx
        · exact Nat.le_refl _
        · have := hm x hx; omega

/-- `cntLe` is monotone in the bound.

$$\forall X, v, w:\quad v \le w \Rightarrow \operatorname{cntLe}(X, v) \le \operatorname{cntLe}(X, w)$$
-/
theorem cntLe_mono (xs : List Nat) (v w : Nat) (h : v ≤ w) : cntLe xs v ≤ cntLe xs w :=
  List.countP_mono_left (by intro x _ hx; simp only [decide_eq_true_eq] at hx ⊢; omega)

/-- For an index inside the list, `ord` is a value of the list with at least `j + 1` values at or below it, and it is
the least such value.

$$\forall X, j:\quad j < |X| \Rightarrow \operatorname{ord}(X, j) \in X \wedge \operatorname{cntLe}(X, \operatorname{ord}(X, j)) \ge j + 1 \wedge \forall v \in X.\ \operatorname{cntLe}(X, v) \ge j + 1 \Rightarrow \operatorname{ord}(X, j) \le v$$
-/
theorem ord_spec (xs : List Nat) (j : Nat) (hj : j < xs.length) :
    ord xs j ∈ xs ∧ j + 1 ≤ cntLe xs (ord xs j) ∧ ∀ v ∈ xs, j + 1 ≤ cntLe xs v → ord xs j ≤ v := by
  have hne : xs ≠ [] := by intro h'; subst h'; simp at hj
  obtain ⟨u, hu, hm⟩ := exists_max xs hne
  have hcu : cntLe xs u = xs.length :=
    List.countP_eq_length.2 (by intro a ha; simpa using hm a ha)
  have huC : u ∈ cands xs j := List.mem_filter.2 ⟨hu, by simp only [decide_eq_true_eq]; omega⟩
  cases hmin : (cands xs j).min? with
  | none =>
    rw [List.min?_eq_none_iff] at hmin
    rw [hmin] at huC; simp at huC
  | some m =>
    have hord : ord xs j = m := by simp [ord, hmin]
    obtain ⟨hmC, hle⟩ := List.min?_eq_some_iff.1 hmin
    obtain ⟨hmX, hmc⟩ := List.mem_filter.1 hmC
    simp only [decide_eq_true_eq] at hmc
    rw [hord]
    refine ⟨hmX, hmc, ?_⟩
    intro v hv hc
    exact hle v (List.mem_filter.2 ⟨hv, by simpa using hc⟩)

/-- The counting characterization of the order statistic: `ord xs j` is at most `v` exactly when at least `j + 1`
values of the list are at most `v`.

$$\forall X, j, v:\quad j < |X| \Rightarrow \bigl(\operatorname{ord}(X, j) \le v \iff \operatorname{cntLe}(X, v) \ge j + 1\bigr)$$
-/
theorem ord_le_iff (xs : List Nat) (j v : Nat) (hj : j < xs.length) :
    ord xs j ≤ v ↔ j + 1 ≤ cntLe xs v := by
  obtain ⟨_, hc, hmin⟩ := ord_spec xs j hj
  constructor
  · intro h; exact Nat.le_trans hc (cntLe_mono xs _ _ h)
  · intro h
    have hF : xs.filter (fun x => decide (x ≤ v)) ≠ [] := by
      intro hF
      have : cntLe xs v = 0 := by simp [cntLe, List.countP_eq_length_filter, hF]
      omega
    obtain ⟨u, hu, hm⟩ := exists_max _ hF
    obtain ⟨huX, huv⟩ := List.mem_filter.1 hu
    simp only [decide_eq_true_eq] at huv
    have hcu : cntLe xs u = cntLe xs v := by
      apply List.countP_congr
      intro x hx
      simp only [decide_eq_true_eq]
      constructor
      · intro hxu; omega
      · intro hxv; exact hm x (List.mem_filter.2 ⟨hx, by simpa using hxv⟩)
    exact Nat.le_trans (hmin u huX (by omega)) huv

/-- The order statistics are sorted: a larger index gives a value at least as large.

$$\forall X, j, j':\quad j \le j' < |X| \Rightarrow \operatorname{ord}(X, j) \le \operatorname{ord}(X, j')$$
-/
theorem ord_mono (xs : List Nat) (j j' : Nat) (h : j ≤ j') (hj' : j' < xs.length) :
    ord xs j ≤ ord xs j' := by
  rw [ord_le_iff xs j _ (by omega)]
  have := (ord_spec xs j' hj').2.1
  omega

/-- Counting after one replacement: the count at any bound moves by at most one.

$$\forall a, b, x, y, v:\quad \operatorname{cntLe}(a \mathbin{+\!\!+} [y] \mathbin{+\!\!+} b, v) \le \operatorname{cntLe}(a \mathbin{+\!\!+} [x] \mathbin{+\!\!+} b, v) + 1$$
-/
theorem cntLe_replace (a b : List Nat) (x y v : Nat) :
    cntLe (a ++ y :: b) v ≤ cntLe (a ++ x :: b) v + 1 := by
  simp only [cntLe, List.countP_append, List.countP_cons]
  split <;> split <;> omega

/-- Counting after one replacement, at a bound not below the new value or below it.

$$\forall a, b, x, y, v:\quad (y \le v \Rightarrow \operatorname{cntLe}(a \mathbin{+\!\!+} [x] \mathbin{+\!\!+} b, v) \le \operatorname{cntLe}(a \mathbin{+\!\!+} [y] \mathbin{+\!\!+} b, v)) \wedge (v < y \Rightarrow \operatorname{cntLe}(a \mathbin{+\!\!+} [y] \mathbin{+\!\!+} b, v) \le \operatorname{cntLe}(a \mathbin{+\!\!+} [x] \mathbin{+\!\!+} b, v))$$
-/
theorem cntLe_replace_y (a b : List Nat) (x y v : Nat) :
    (y ≤ v → cntLe (a ++ x :: b) v ≤ cntLe (a ++ y :: b) v) ∧
      (v < y → cntLe (a ++ y :: b) v ≤ cntLe (a ++ x :: b) v) := by
  simp only [cntLe, List.countP_append, List.countP_cons]
  constructor <;> intro h <;> split <;> split <;> simp_all <;> omega

/-- Interlacing: replacing one value of a list moves its order statistic of index `j` at most to the neighbouring
order statistics of the old list (indices `j - 1` and `j + 1`, where they exist).

$$\forall a, b, x, y, j:\quad X = a \mathbin{+\!\!+} [x] \mathbin{+\!\!+} b,\ X' = a \mathbin{+\!\!+} [y] \mathbin{+\!\!+} b:\quad (1 \le j < |X| \Rightarrow \operatorname{ord}(X, j-1) \le \operatorname{ord}(X', j)) \wedge (j + 1 < |X| \Rightarrow \operatorname{ord}(X', j) \le \operatorname{ord}(X, j+1))$$
-/
theorem ord_interlace (a b : List Nat) (x y j : Nat) :
    (1 ≤ j → j < (a ++ x :: b).length → ord (a ++ x :: b) (j - 1) ≤ ord (a ++ y :: b) j) ∧
      (j + 1 < (a ++ x :: b).length → ord (a ++ y :: b) j ≤ ord (a ++ x :: b) (j + 1)) := by
  have hlen : (a ++ y :: b).length = (a ++ x :: b).length := by simp
  constructor
  · intro h1 hj
    rw [ord_le_iff _ _ _ (by omega)]
    have := (ord_spec (a ++ y :: b) j (by omega)).2.1
    have := cntLe_replace a b x y (ord (a ++ y :: b) j)
    omega
  · intro hj
    rw [ord_le_iff _ _ _ (by omega)]
    have := (ord_spec (a ++ x :: b) (j + 1) hj).2.1
    have := cntLe_replace a b y x (ord (a ++ x :: b) (j + 1))
    omega

/-- The new order statistic lies between the old one and the new value.

$$\forall a, b, x, y, j:\quad j < |X| \Rightarrow \min(\operatorname{ord}(X, j), y) \le \operatorname{ord}(X', j) \le \max(\operatorname{ord}(X, j), y),\quad X = a \mathbin{+\!\!+} [x] \mathbin{+\!\!+} b,\ X' = a \mathbin{+\!\!+} [y] \mathbin{+\!\!+} b$$
-/
theorem ord_between (a b : List Nat) (x y j : Nat) (hj : j < (a ++ x :: b).length) :
    min (ord (a ++ x :: b) j) y ≤ ord (a ++ y :: b) j ∧ ord (a ++ y :: b) j ≤ max (ord (a ++ x :: b) j) y := by
  have hlen : (a ++ y :: b).length = (a ++ x :: b).length := by simp
  constructor
  · apply Nat.le_of_not_lt
    intro hlt
    have hq : ord (a ++ y :: b) j < ord (a ++ x :: b) j := by omega
    have hy : ord (a ++ y :: b) j < y := by omega
    have h1 := (ord_spec (a ++ y :: b) j (by omega)).2.1
    have h2 : ¬ (ord (a ++ x :: b) j ≤ ord (a ++ y :: b) j) := by omega
    rw [ord_le_iff _ _ _ hj] at h2
    have h3 := (cntLe_replace_y a b x y (ord (a ++ y :: b) j)).2 hy
    omega
  · rw [ord_le_iff _ _ _ (by omega)]
    have h1 := (ord_spec (a ++ x :: b) j hj).2.1
    have h2 := cntLe_mono (a ++ x :: b) _ (max (ord (a ++ x :: b) j) y) (Nat.le_max_left _ _)
    have h3 := (cntLe_replace_y a b x y (max (ord (a ++ x :: b) j) y)).1 (Nat.le_max_right _ _)
    omega

/-- The rank of p90 is an index of the list: $1 \le \operatorname{rank}_{90}(n) \le n$ for $n \ge 1$, and
$2 \le \operatorname{rank}_{90}(n) < n$ for $n \ge 10$.

$$\forall n:\quad (n \ge 1 \Rightarrow 1 \le \operatorname{rank}_{90}(n) \le n) \wedge (n \ge 10 \Rightarrow 2 \le \operatorname{rank}_{90}(n) < n)$$
-/
theorem rank90_bounds (n : Nat) :
    (1 ≤ n → 1 ≤ rank90 n ∧ rank90 n ≤ n) ∧ (10 ≤ n → 2 ≤ rank90 n ∧ rank90 n < n) := by
  simp only [rank90]; omega

/-- An outlier moves the baseline only toward itself: replacing one window value $x$ by $y$ leaves the new p90
between the old p90 and $y$ (any window length; for a window of fewer than 10 values the p90 is the maximum, so a
large $y$ can raise it all the way to $y$).

$$\forall a, b, x, y:\quad \min(\operatorname{p90}(X), y) \le \operatorname{p90}(X') \le \max(\operatorname{p90}(X), y),\quad X = a \mathbin{+\!\!+} [x] \mathbin{+\!\!+} b,\ X' = a \mathbin{+\!\!+} [y] \mathbin{+\!\!+} b$$
-/
theorem outlier_between (a b : List Nat) (x y : Nat) :
    min (p90 (a ++ x :: b)) y ≤ p90 (a ++ y :: b) ∧ p90 (a ++ y :: b) ≤ max (p90 (a ++ x :: b)) y := by
  have hlen : (a ++ y :: b).length = (a ++ x :: b).length := by simp
  have hpos : 1 ≤ (a ++ x :: b).length := by
    simp only [List.length_append, List.length_cons]; omega
  have := (rank90_bounds (a ++ x :: b).length).1 hpos
  simp only [p90, hlen]
  exact ord_between a b x y _ (by omega)

/-- The outlier bound: for a window of at least 10 values with p90 rank $r = \lceil 9n/10 \rceil$, replacing any one
value (by anything, however large or small) leaves the new p90 between the old $(r-1)$-th and $(r+1)$-th smallest
values, that is between the old order statistics adjacent to the old p90 (`ord` is 0-based, so these are the indices
$r-2$ and $r$; $r \ge 2$ here, so $r - 2$ does not truncate).

$$\forall a, b, x, y:\quad n = |X| \ge 10 \Rightarrow \operatorname{ord}(X, r - 2) \le \operatorname{p90}(X') \le \operatorname{ord}(X, r),\quad r = \operatorname{rank}_{90}(n),\ X = a \mathbin{+\!\!+} [x] \mathbin{+\!\!+} b,\ X' = a \mathbin{+\!\!+} [y] \mathbin{+\!\!+} b$$
-/
theorem outlier_bound (a b : List Nat) (x y : Nat) (hn : 10 ≤ (a ++ x :: b).length) :
    ord (a ++ x :: b) (rank90 (a ++ x :: b).length - 2) ≤ p90 (a ++ y :: b) ∧
      p90 (a ++ y :: b) ≤ ord (a ++ x :: b) (rank90 (a ++ x :: b).length) := by
  have hlen : (a ++ y :: b).length = (a ++ x :: b).length := by simp
  have hr := (rank90_bounds (a ++ x :: b).length).2 hn
  have hi := ord_interlace a b x y (rank90 (a ++ x :: b).length - 1)
  simp only [p90, hlen]
  have e1 : rank90 (a ++ x :: b).length - 1 - 1 = rank90 (a ++ x :: b).length - 2 := by omega
  have e2 : rank90 (a ++ x :: b).length - 1 + 1 = rank90 (a ++ x :: b).length := by omega
  rw [e1, e2] at hi
  exact ⟨hi.1 (by omega) (by omega), hi.2 (by omega)⟩

/-- The outlier bound as a shift: for a window of at least 10 values, one replaced value raises the p90 by at most
the gap from the old p90 to the next order statistic, and lowers it by at most the gap to the previous one
(truncated differences; the gaps are non-negative because `ord` is sorted).

$$\forall a, b, x, y:\quad n = |X| \ge 10 \Rightarrow \operatorname{p90}(X') \mathbin{\dot-} \operatorname{p90}(X) \le \operatorname{ord}(X, r) \mathbin{\dot-} \operatorname{ord}(X, r-1) \wedge \operatorname{p90}(X) \mathbin{\dot-} \operatorname{p90}(X') \le \operatorname{ord}(X, r-1) \mathbin{\dot-} \operatorname{ord}(X, r-2),\quad r = \operatorname{rank}_{90}(n),\ X = a \mathbin{+\!\!+} [x] \mathbin{+\!\!+} b,\ X' = a \mathbin{+\!\!+} [y] \mathbin{+\!\!+} b$$
-/
theorem outlier_shift (a b : List Nat) (x y : Nat) (hn : 10 ≤ (a ++ x :: b).length) :
    p90 (a ++ y :: b) - p90 (a ++ x :: b) ≤
        ord (a ++ x :: b) (rank90 (a ++ x :: b).length) - ord (a ++ x :: b) (rank90 (a ++ x :: b).length - 1) ∧
      p90 (a ++ x :: b) - p90 (a ++ y :: b) ≤
        ord (a ++ x :: b) (rank90 (a ++ x :: b).length - 1) - ord (a ++ x :: b) (rank90 (a ++ x :: b).length - 2) := by
  have hb := outlier_bound a b x y hn
  have hp : p90 (a ++ x :: b) = ord (a ++ x :: b) (rank90 (a ++ x :: b).length - 1) := rfl
  rw [hp]
  omega

/-! ## Proofs: structural verdicts -/

/-- When a group is structural: it has a baseline $b$, its stage has another group, and every other group of the
stage has a baseline $c$ with $2c < b$.

$$\forall p, H, S, g:\quad \operatorname{st}_p(H, S, g) \ne \bot \iff \exists b.\ \operatorname{gb}_p(H, g) = b \wedge (\exists g' \in G_S.\ g' \ne g) \wedge \forall g' \in G_S.\ g' \ne g \Rightarrow \exists c.\ \operatorname{gb}_p(H, g') = c \wedge 2c < b$$
-/
theorem structural_iff (p : Params) (ss : List Sample) (st : Stage) (g : Group) :
    (structuralOf p ss st g).isSome = true ↔
      ∃ b, groupBaseline p ss g = some b ∧ (∃ g' ∈ st.groups, g' ≠ g) ∧
        ∀ g' ∈ st.groups, g' ≠ g → ∃ c, groupBaseline p ss g' = some c ∧ 2 * c < b := by
  unfold structuralOf
  cases hg : groupBaseline p ss g with
  | none => simp
  | some b =>
    have hall : ((st.groups.filter (fun g' => decide (g' ≠ g))).map (groupBaseline p ss)).all (below b) = true ↔
        ∀ g' ∈ st.groups, g' ≠ g → ∃ c, groupBaseline p ss g' = some c ∧ 2 * c < b := by
      simp only [List.all_eq_true, List.mem_map, List.mem_filter, decide_eq_true_eq]
      constructor
      · intro h g' hg' hne
        have := h _ ⟨g', ⟨hg', hne⟩, rfl⟩
        cases hc : groupBaseline p ss g' with
        | none => rw [hc] at this; simp [below] at this
        | some c => rw [hc] at this; exact ⟨c, rfl, by simpa [below] using this⟩
      · rintro h o ⟨g', ⟨hg', hne⟩, rfl⟩
        obtain ⟨c, hc, hlt⟩ := h g' hg' hne
        simp [hc, below, hlt]
    have hne : (!((st.groups.filter (fun g' => decide (g' ≠ g))).map (groupBaseline p ss)).isEmpty) = true ↔
        ∃ g' ∈ st.groups, g' ≠ g := by
      constructor
      · intro h; simpa using h
      · rintro ⟨g', hg', hne⟩
        have : g' ∈ st.groups.filter (fun g' => decide (g' ≠ g)) := List.mem_filter.2 ⟨hg', by simpa using hne⟩
        cases hf : st.groups.filter (fun g' => decide (g' ≠ g)) with
        | nil => rw [hf] at this; simp at this
        | cons _ _ => simp
    by_cases hc : (!((st.groups.filter (fun g' => decide (g' ≠ g))).map (groupBaseline p ss)).isEmpty &&
        ((st.groups.filter (fun g' => decide (g' ≠ g))).map (groupBaseline p ss)).all (below b)) = true
    · simp only [hc, ite_true, Option.isSome_some, true_iff]
      rw [Bool.and_eq_true] at hc
      exact ⟨b, rfl, hne.1 hc.1, hall.1 hc.2⟩
    · simp only [hc, ite_false, Option.isSome_none, Bool.false_eq_true, false_iff]
      rintro ⟨b', hb', h1, h2⟩
      cases hb'
      exact hc (Bool.and_eq_true _ _ ▸ ⟨hne.2 h1, hall.2 h2⟩)

/-- The structural verdicts of the entry point are exactly the structural verdicts of the groups of the stages.

$$\forall p, H, v:\quad \mathsf{structural}(v) \in \operatorname{timingVerdicts}(p, H) \iff \exists S \in \Sigma.\ \exists g \in G_S.\ \operatorname{st}_p(H, S, g) = \mathsf{some}(v)$$
-/
theorem mem_structural (p : Params) (ss : List Sample) (v : StructVerdict) :
    Verdict.structural v ∈ timingVerdicts p ss ↔
      ∃ st ∈ p.stages, ∃ g ∈ st.groups, structuralOf p ss st g = some v := by
  simp [timingVerdicts, structuralVerdicts, List.mem_flatMap, List.mem_filterMap]

end Fw.Obs.Timing

/-!
# Wire face and golden of `Fw.Obs.Timing`

JSON encoders for the future op `obs.timing` (wired by task `timing-alert` in `Fw.Wire.Obs`) and the golden
`packages/contracts/golden/obs/timing.jsonl`: one line per case, `{"name", "request", "response"}`, where `request`
is `{"op":"obs.timing","params","samples"}` and `response` is `{"verdicts"}` as `timingVerdicts` computes it.
Regenerate from `lean/` with `lake env lean --run` on a script `import Fw.Obs.Timing` +
`def main : IO Unit := Fw.Wire.Obs.Timing.writeGolden`; `checkGolden` compares the file with the Lean output.
(Namespace `Fw.Wire.Obs.Timing`: wire code for the math view.)
-/
namespace Fw.Wire.Obs.Timing
open Lean
open Fw.Obs.Timing

def hostStr : Host → String
  | .«local» => "local"
  | .ci => "ci"

def codeStr : Code → String
  | .noBaseline => "noBaseline"
  | .noisy => "noisy"
  | .ok => "ok"
  | .slow => "slow"

def keyJson (k : Key) : Json :=
  Json.mkObj [("tool", .str k.tool), ("step", .str k.step), ("host", .str (hostStr k.host))]

def sampleJson (s : Sample) : Json :=
  Json.mkObj [("tool", .str s.tool), ("step", .str s.step), ("durMs", toJson s.durMs),
    ("host", .str (hostStr s.host)), ("load", toJson s.load)]

def paramsJson (p : Params) : Json :=
  Json.mkObj [("nMin", toJson p.nMin), ("window", toJson p.window), ("kNum", toJson p.kNum),
    ("kDen", toJson p.kDen), ("budgetMs", toJson p.budgetMs),
    ("budgets", .arr (p.budgets.map (fun (t, b) => Json.mkObj [("tool", .str t), ("ms", toJson b)])).toArray),
    ("ceilings", .arr (p.ceilings.map (fun (t, s, c) =>
      Json.mkObj [("tool", .str t), ("step", .str s), ("ms", toJson c)])).toArray),
    ("loadMax", toJson p.loadMax),
    ("stages", .arr (p.stages.map (fun st => Json.mkObj [("id", .str st.id),
      ("groups", .arr (st.groups.map (fun g => Json.mkObj [("name", .str g.name),
        ("keys", .arr (g.keys.map keyJson).toArray)])).toArray)])).toArray)]

def verdictJson : Verdict → Json
  | .sample v => Json.mkObj [("kind", "sample"), ("idx", toJson v.idx), ("tool", .str v.tool),
      ("step", .str v.step), ("host", .str (hostStr v.host)), ("durMs", toJson v.durMs),
      ("code", .str (codeStr v.code)), ("n", toJson v.n), ("baseline", toJson v.baseline),
      ("budgetMs", toJson v.budgetMs)]
  | .structural v => Json.mkObj [("kind", "structural"), ("stage", .str v.stage), ("group", .str v.group),
      ("baseline", toJson v.baseline), ("siblingMax", toJson v.siblingMax)]

def caseJson (name : String) (p : Params) (ss : List Sample) : Json :=
  Json.mkObj [("name", .str name),
    ("request", Json.mkObj [("op", "obs.timing"), ("params", paramsJson p),
      ("samples", .arr (ss.map sampleJson).toArray)]),
    ("response", Json.mkObj [("verdicts", .arr ((timingVerdicts p ss).map verdictJson).toArray)])]

/-- The tool name of the breakpoint-gate CI jobs. -/
def gateTool : String := "ci:breakpoint-gate"

def gateJob (step : String) (s : Nat) : Sample := { tool := gateTool, step, durMs := s * 1000, host := .ci }

def gateKey (step : String) : Key := { tool := gateTool, step, host := .ci }

/-- Breakpoint-gate run 39067656223: the real job durations in s (`gh run view 39067656223 --json jobs`,
completedAt − startedAt), in the listed order. -/
def gateRun : List Sample :=
  [gateJob "plan" 5, gateJob "site" 35, gateJob "sweeps (chromium)" 342, gateJob "sweeps (playwright-webkit)" 345,
   gateJob "gate (chromium, s4)" 59, gateJob "gate (chromium, s7)" 53, gateJob "gate (chromium, s6)" 53,
   gateJob "gate (chromium, s1)" 57, gateJob "gate (playwright-webkit, s3)" 147, gateJob "gate (chromium, s0)" 63,
   gateJob "gate (chromium, s3)" 55, gateJob "gate (playwright-webkit, s1)" 120,
   gateJob "gate (playwright-webkit, s0)" 113, gateJob "gate (chromium, s2)" 53, gateJob "gate (chromium, s5)" 76,
   gateJob "gate (playwright-webkit, s2)" 120, gateJob "gate (playwright-webkit, s5)" 117,
   gateJob "gate (playwright-webkit, s4)" 132, gateJob "gate (playwright-webkit, s7)" 109,
   gateJob "gate (playwright-webkit, s6)" 141, gateJob "merge (playwright-webkit)" 34, gateJob "merge (chromium)" 36]

/-- One run gives one sample per job key, so `nMin := 1`; CI jobs get a 120 s budget. -/
def gateParams : Params :=
  { nMin := 1, budgets := [(gateTool, 120000)],
    stages := [
      { id := "breakpoint-gate:test",
        groups := [{ name := "gate", keys := ((["chromium", "playwright-webkit"].flatMap fun e =>
            (List.range 8).map fun i => s!"gate ({e}, s{i})")).map gateKey },
          { name := "sweeps", keys := [gateKey "sweeps (chromium)", gateKey "sweeps (playwright-webkit)"] }] },
      { id := "breakpoint-gate:merge",
        groups := [{ name := "merge (chromium)", keys := [gateKey "merge (chromium)"] },
          { name := "merge (playwright-webkit)", keys := [gateKey "merge (playwright-webkit)"] }] }] }

/-- The parameters with the `fw land` ceilings (30 s total, 5 s lock held). -/
def landParams : Params := { ceilings := landCeilings }

def run (tool step : String) (host : Host) (load : Nat) (ds : List Nat) : List Sample :=
  ds.map fun d => { tool, step, durMs := d, host, load }

/-- A check.sh history around 2 min (handoffs report 117 s and up to 136 s for check.sh). -/
def checkHist : List Nat := [117000, 124000, 131000, 119000, 136000, 122000]

def cases : List (String × Params × List Sample) :=
  [("breakpoint-gate run 39067656223: sweeps (345 s) is structural in stage {gate, sweeps} (gate shards <= 147 s); merge is not; one run, so every sample is noBaseline",
      gateParams, gateRun),
   ("lean check.sh 128 s after a history of 117-136 s: ok (not slow)",
      {}, run "lean" "check.sh" .«local» 9 (checkHist ++ [128000])),
   ("lean check.sh 205 s after a history of 117-136 s: slow (2 * 205000 > 3 * 136000)",
      {}, run "lean" "check.sh" .«local» 9 (checkHist ++ [205000])),
   ("below n_min: 4 earlier samples (nMin 5), a 10 min run is noBaseline",
      {}, run "lean" "lake build" .«local» 3 [60000, 61000, 59000, 60000, 600000]),
   ("exactly k * baseline (150000 = 3/2 * 100000): ok",
      {}, run "ci:lean" "check" .ci 0 [100000, 100000, 100000, 100000, 100000, 150000]),
   ("1 ms above k * baseline: slow",
      {}, run "ci:lean" "check" .ci 0 [100000, 100000, 100000, 100000, 100000, 150001]),
   ("exactly at the budget (30000 ms, 3x the baseline): ok",
      {}, run "fw" "land" .«local» 2 [10000, 10000, 10000, 10000, 10000, 30000]),
   ("1 ms above the budget and above k * baseline: slow",
      {}, run "fw" "land" .«local» 2 [10000, 10000, 10000, 10000, 10000, 30001]),
   ("noisy local sample (load 24 > 16): verdict noisy, and it stays out of the next window (n = 5)",
      {}, run "lean" "check.sh" .«local» 4 [60000, 60000, 60000, 60000, 60000] ++
        run "lean" "check.sh" .«local» 24 [300000] ++ run "lean" "check.sh" .«local» 4 [61000]),
   ("CI sample at load 40 is never noisy: slow",
      {}, run "ci:lean" "check" .ci 40 [60000, 60000, 60000, 60000, 60000, 300000]),
   ("window N = 5 drops the old 400 s outlier: 160 s after five 100 s runs is slow",
      { window := 5 }, run "ci:lean" "check" .ci 0 [400000, 100000, 100000, 100000, 100000, 100000, 160000]),
   ("land ceilings: three real check.sh spans of 2026-10-17 (112.5, 124.1, 152.8 s at load 8-9, lower bounds of the lock-held time) as lock-held samples with no history: all slow at once (5 s ceiling); the relative rule alone gives noBaseline",
      landParams, run "fw land" "lock held" .«local» 9 [112483, 124065, 152813]),
   ("land ceilings: a total of exactly 30000 ms after five 12 s lands: ok",
      landParams, run "fw land" "total" .«local» 4 [12000, 12000, 12000, 12000, 12000, 30000]),
   ("land ceilings: a first-ever total of 30001 ms (no history) is slow",
      landParams, run "fw land" "total" .«local» 4 [30001]),
   ("land ceilings: a lock held of exactly 5000 ms after five 1 s locks: ok",
      landParams, run "fw land" "lock held" .«local» 4 [1000, 1000, 1000, 1000, 1000, 5000]),
   ("land ceilings: a first-ever lock held of 5001 ms is slow",
      landParams, run "fw land" "lock held" .«local» 4 [5001]),
   ("land ceilings: a lock held of 150 s at load 24 on the local Mac is noisy, not an alert",
      landParams, run "fw land" "lock held" .«local» 4 [1000, 1000, 1000, 1000, 1000] ++
        run "fw land" "lock held" .«local» 24 [150000])]

/-- The last verdict code of each case's samples, and the structural groups: the expected outcomes. -/
def lastCode (p : Params) (ss : List Sample) : Option Code :=
  ((sampleVerdicts p ss).getLast?).map (·.code)

#guard (structuralVerdicts gateParams gateRun).map (fun v => (v.stage, v.group, v.baseline, v.siblingMax)) ==
  [("breakpoint-gate:test", "sweeps", 345000, 147000)]
#guard (sampleVerdicts gateParams gateRun).all (·.code == .noBaseline)
#guard (cases.drop 1).map (fun (_, p, ss) => lastCode p ss) ==
  [some .ok, some .slow, some .noBaseline, some .ok, some .slow, some .ok, some .slow, some .ok, some .slow, some .slow,
   some .slow, some .ok, some .slow, some .ok, some .slow, some .noisy]
#guard (sampleVerdicts landParams (run "fw land" "lock held" .«local» 9 [112483, 124065, 152813])).all (·.code == .slow)
#guard (sampleVerdicts {} (run "fw land" "lock held" .«local» 9 [112483, 124065, 152813])).all (·.code == .noBaseline)
#guard (sampleVerdicts {} (run "lean" "check.sh" .«local» 4 [60000, 60000, 60000, 60000, 60000] ++
  run "lean" "check.sh" .«local» 24 [300000] ++ run "lean" "check.sh" .«local» 4 [61000])).map (·.code) ==
  [.noBaseline, .noBaseline, .noBaseline, .noBaseline, .noBaseline, .noisy, .ok]

def goldenText : String :=
  String.join (cases.map fun (n, p, ss) => (caseJson n p ss).compress ++ "\n")

def goldenPath : System.FilePath := "../packages/contracts/golden/obs/timing.jsonl"

def writeGolden : IO Unit := IO.FS.writeFile goldenPath goldenText

def checkGolden : IO Bool := do return (← IO.FS.readFile goldenPath) == goldenText

end Fw.Wire.Obs.Timing
