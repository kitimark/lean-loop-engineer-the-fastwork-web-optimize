import Fw.Obs.Timing
/-!
# CI shape: imbalance, growth, timeout headroom and queue time of CI runs (task `ci-shape-obs`)

The collector (`apps/runner/src/ci-shape.ts`) records one **row** per finished run × job in
`.fw-console/ci-shape.jsonl`: run id, workflow, branch, head sha, event, run creation and start time, job name,
conclusion, job start and end, and the job's `timeout-minutes` in seconds when known. This module is the pure decision
over those rows: which **cause classes** fire for a run, and when a `ci.shape` alert is raised. Design note:
`research/notes/2026/10-18-ci-shape-obs.md`.

Definitions (all times in whole seconds, `Nat`; `∸` is truncated subtraction):
* A job **ran** unless its conclusion is `skipped`; it is **counted** when it ran and was not `cancelled`.
  Its run time is $\mathit{end} \mathbin{\dot-} \mathit{start}$.
* **Sibling group** (`groupOf`): the job name split into tokens at blanks, `(`, `)` and `,`; the first token (the job
  id) is mapped through the alias table (default `sweeps ↦ gate`), and the **shard tokens** (one of `s j r v` followed
  by at least one digit) are dropped. So `gate (chromium, s0)`, `gate chromium j0` and `sweeps (chromium)` are all in
  group `gate chromium`, across the s→j rename.
* **imbalance** of a group with run times $D$ ($|D| \ge 2$): $\max D / \operatorname{mean} D > \rho$ and
  $\max D \ge m_s$, decided as $\rho_n \sum D < \rho_d \cdot |D| \cdot \max D$ (default $\rho = 3/2$, $m_s = 300$ s).
* **growth** of a run with job seconds $x$ (the sum over counted jobs), against the job seconds of the earlier runs of
  the same workflow (any branch): the window $w$ is the last $N$ of them; growth when $|w| \ge n_{\min}$,
  $x \ge m_j$ and $g_d \cdot x > g_n \cdot \operatorname{p50}(w)$ (default $N = 5$, $n_{\min} = 3$, $g = 2$,
  $m_j = 600$ s). The median is `Fw.Obs.Timing.p50`.
* **nearTimeout**: a job that ran with $\theta_d \cdot \mathit{run} > \theta_n \cdot T$, where $T$ is the row's
  timeout, else the `timeouts` table entry for (workflow, job id), else 21600 s (GitHub's 360 min default); default
  $\theta = 3/4$.
* **queue**: a job that ran and waited more than $q$ (default 1200 s) between its ready time and its start. The ready
  time is the later of the run start and the latest end among the run's jobs that ran, are of another family (aliased
  job id) and ended by this job's start: an under-estimate of the true wait whatever the `needs` graph is
  (`queued_le`).
* **Raised** (dedup): per workflow the runs are ordered by (creation time, run id); class $c$ is raised at run $i$
  when it fires at $i$ and did not fire at $i - 1$. It stays **open** while it fires on the workflow's latest run.

Proved: `imbalance_ge_one`, `imbalanced_iff`, `growth_iff`, `nearTimeout_iff`, `queued_iff`, `alert_iff`,
`no_alert_on_balanced`, `no_imbalance_on_balanced_run`, `growth_of_few_above`, `growth_within`, `growth_mono`,
`raised_iff`, `dedup`, `open_iff`, `caught_before_timeout`, `caught_series`, `queued_le`, `imbWitness_spec`.

Wire: op `obs.ciShape` (`Fw.Wire.Ops.opCiShape`); goldens `packages/contracts/golden/obs/obs.ciShape.jsonl`.
-/
namespace Fw.Obs.CiShape
open Fw.Obs.Timing (p50 lastN p50_le_of_few_above)

/-! ## Rows, classes, parameters -/

/-- One row of the CI-shape ledger: one job of one finished run (times in epoch seconds).

$$\rho = (\mathit{run}, \mathit{wf}, \mathit{branch}, \mathit{sha}, \mathit{event}, t_c, t_r, \mathit{job}, \mathit{concl}, t_s, t_e, T) \in \mathbb N \times \mathrm{String}^5 \times \mathbb N^2 \times \mathrm{String}^2 \times \mathbb N^3$$

A row holds the measured facts of one job, with $T = 0$ when the timeout is unknown.
-/
structure Row where
  run        : Nat
  workflow   : String
  branch     : String := ""
  sha        : String := ""
  event      : String := ""
  createdS   : Nat := 0
  startedS   : Nat := 0
  job        : String
  conclusion : String := "success"
  startS     : Nat
  endS       : Nat
  timeoutS   : Nat := 0
deriving DecidableEq, Repr

/-- The cause classes of a `ci.shape` alert.

$$c \in \{\mathsf{imbalance}, \mathsf{growth}, \mathsf{nearTimeout}, \mathsf{queue}\}$$

The four reasons a run's shape can drift.
-/
inductive Cls where
  | imbalance
  | growth
  | nearTimeout
  | queue
deriving DecidableEq, Repr

/-- The parameters: imbalance ratio $\rho = \rho_n/\rho_d$ and floor $m_s$; window $N$, $n_{\min}$, growth factor
$g = g_n/g_d$ and floor $m_j$; headroom $\theta = \theta_n/\theta_d$ and default timeout $T_0$; queue limit $q$; the
alias table $\alpha$ (first match) and the timeout table $\tau$ of (workflow, job id, seconds) (first match).

$$p = (\rho_n, \rho_d, m_s, N, n_{\min}, g_n, g_d, m_j, \theta_n, \theta_d, T_0, q, \alpha, \tau)$$

The thresholds and tables every decision reads.
-/
structure Params where
  rhoNum          : Nat := 3
  rhoDen          : Nat := 2
  minShardS       : Nat := 300
  window          : Nat := 5
  nMin            : Nat := 3
  gNum            : Nat := 2
  gDen            : Nat := 1
  minJobS         : Nat := 600
  thetaNum        : Nat := 3
  thetaDen        : Nat := 4
  defaultTimeoutS : Nat := 21600
  queueMaxS       : Nat := 1200
  aliases         : List (String × String) := [("sweeps", "gate")]
  timeouts        : List (String × String × Nat) := []
deriving Repr

/-! ## Small list functions -/

/-- The sum of a list.

$$\Sigma(X) = \sum_{x \in X} x \quad (\Sigma([]) = 0)$$

Adds the values.
-/
def sumL : List Nat → Nat
  | [] => 0
  | x :: xs => x + sumL xs

/-- The largest value of a list, 0 for the empty list.

$$\max(X) = \max_{x \in X} x \quad (\max([]) = 0)$$

The biggest value.
-/
def mx : List Nat → Nat
  | [] => 0
  | x :: xs => max x (mx xs)

/-- Every member of a list is at most its maximum.

$$\forall X, x:\quad x \in X \Rightarrow x \le \max(X)$$

The maximum bounds every value.
-/
theorem le_mx {xs : List Nat} {x : Nat} (h : x ∈ xs) : x ≤ mx xs := by
  induction xs with
  | nil => cases h
  | cons y ys ih =>
    simp only [mx]
    rcases List.mem_cons.mp h with rfl | h'
    · exact Nat.le_max_left _ _
    · exact Nat.le_trans (ih h') (Nat.le_max_right _ _)

/-- The maximum is monotone under inclusion of members.

$$\forall X, Y:\quad (\forall x \in X,\ x \in Y) \Rightarrow \max(X) \le \max(Y)$$

A list whose values all occur in another has no larger maximum.
-/
theorem mx_le_of_subset {xs ys : List Nat} (h : ∀ x ∈ xs, x ∈ ys) : mx xs ≤ mx ys := by
  induction xs with
  | nil => exact Nat.zero_le _
  | cons x xs ih =>
    simp only [mx]
    exact Nat.max_le.mpr ⟨le_mx (h x (List.mem_cons_self ..)), ih (fun y hy => h y (List.mem_cons_of_mem _ hy))⟩

/-- The ratio max/mean of a non-empty list is at least 1: the sum is at most the length times the maximum.

$$\forall X:\quad \Sigma(X) \le |X| \cdot \max(X)$$

No shard can be above the largest one, so the mean never exceeds the maximum.
-/
theorem imbalance_ge_one (xs : List Nat) : sumL xs ≤ xs.length * mx xs := by
  induction xs with
  | nil => simp [sumL]
  | cons x xs ih =>
    simp only [sumL, mx, List.length_cons, Nat.succ_mul]
    have h1 : xs.length * mx xs ≤ xs.length * max x (mx xs) := Nat.mul_le_mul_left _ (Nat.le_max_right _ _)
    have h2 : x ≤ max x (mx xs) := Nat.le_max_left _ _
    omega

/-! ## Job names and sibling groups -/

/-- The tokens of a job name: split at blanks, `(`, `)` and `,`, empty pieces dropped.

$$\operatorname{tokens}(s) = [t \in \operatorname{split}(s, \{\texttt{' '}, \texttt{'('}, \texttt{')'}, \texttt{','}\}) \mid t \ne \texttt{""}]$$

The words of a job name.
-/
def tokens (name : String) : List String :=
  ((name.map fun c => if c == '(' || c == ')' || c == ',' then ' ' else c).splitOn " ").filter (· ≠ "")

/-- A shard token: one of `s`, `j`, `r`, `v` followed by one or more digits (`s0`, `j3`, `r2`, `v1`).

$$\operatorname{shard}(t) \iff t = c\,d_1 \cdots d_k,\ c \in \{s, j, r, v\},\ k \ge 1,\ d_i \in \{0..9\}$$

Recognises the matrix index of a sharded job.
-/
def isShard (t : String) : Bool :=
  match t.toList with
  | c :: d :: ds => (c == 's' || c == 'j' || c == 'r' || c == 'v') && (d :: ds).all Char.isDigit
  | _ => false

/-- The alias of a job id (first match in the table), the id itself when there is none.

$$\operatorname{alias}_p(f) = \begin{cases} f' & (f, f') \text{ the first pair of } \alpha \text{ with first component } f \\ f & \text{no such pair} \end{cases}$$

Old job ids that ran as siblings of a new one map onto it.
-/
def aliasOf (p : Params) (f : String) : String := (p.aliases.lookup f).getD f

/-- The job id of a job name: its first token (the whole name when it has none).

$$\operatorname{id}(s) = \begin{cases} t_0 & \operatorname{tokens}(s) = t_0 :: \_ \\ s & \operatorname{tokens}(s) = [] \end{cases}$$

The workflow's job key the name starts with.
-/
def idOf (job : String) : String := (tokens job).headD job

/-- The family of a job: its aliased job id.

$$\operatorname{fam}_p(s) = \operatorname{alias}_p(\operatorname{id}(s))$$

Jobs of one family never wait for each other.
-/
def familyOf (p : Params) (job : String) : String := aliasOf p (idOf job)

/-- The sibling group of a job: the aliased first token followed by the other non-shard tokens, joined by blanks.

$$\operatorname{group}_p(s) = \begin{cases} \operatorname{join}_{\texttt{' '}}(\operatorname{alias}_p(t_0) :: [t \in T \mid \neg\operatorname{shard}(t)]) & \operatorname{tokens}(s) = t_0 :: T \\ s & \operatorname{tokens}(s) = [] \end{cases}$$

Shards of one matrix leg land in one group whatever their index.
-/
def groupOf (p : Params) (job : String) : String :=
  match tokens job with
  | [] => job
  | t :: ts => " ".intercalate (aliasOf p t :: ts.filter (fun x => !isShard x))

#guard groupOf {} "gate (chromium, s0)" == "gate chromium"
#guard groupOf {} "gate chromium j0" == "gate chromium"
#guard groupOf {} "sweeps (playwright-webkit)" == "gate playwright-webkit"
#guard groupOf {} "gate playwright-webkit j3" == "gate playwright-webkit"
#guard groupOf {} "merge (chromium)" == "merge chromium"
#guard groupOf {} "counts (original, r1)" == "counts original"
#guard groupOf {} "collect-linux (r2)" == "collect-linux"
#guard groupOf {} "sim (v1, original)" == "sim original" && groupOf {} "sim (v1)" == "sim"
#guard groupOf {} "fixtures (j3)" == "fixtures" && groupOf {} "plan" == "plan" && groupOf {} "" == ""
#guard isShard "s0" && isShard "j12" && !isShard "s" && !isShard "site" && !isShard "x1" && !isShard "r1a"
#guard idOf "gate (chromium, s0)" == "gate" && idOf "sweeps (chromium)" == "sweeps" && familyOf {} "sweeps (chromium)" == "gate"

/-! ## Per-job facts -/

/-- A job ran unless it was skipped.

$$\operatorname{ran}(\rho) \iff \mathit{concl} \ne \texttt{skipped}$$

Skipped jobs carry no time.
-/
def ran (r : Row) : Bool := r.conclusion != "skipped"

/-- A job is counted (for imbalance and job seconds) when it ran and was not cancelled.

$$\operatorname{counted}(\rho) \iff \mathit{concl} \notin \{\texttt{skipped}, \texttt{cancelled}\}$$

A cancelled job's time is cut short, so it is no sample of its work.
-/
def counted (r : Row) : Bool := ran r && r.conclusion != "cancelled"

/-- The run time of a job.

$$\operatorname{dur}(\rho) = t_e \mathbin{\dot-} t_s$$

How long the job ran.
-/
def runS (r : Row) : Nat := r.endS - r.startS

/-- The timeout of a job: the row's own when positive, else the first `timeouts` entry for (workflow, job id), else
$T_0$.

$$T_p(\rho) = \begin{cases} T_\rho & T_\rho > 0 \\ t & T_\rho = 0,\ (\mathit{wf}_\rho, \operatorname{id}(\mathit{job}_\rho), t) \text{ the first match in } \tau \\ T_0 & \text{otherwise} \end{cases}$$

The limit the job is killed at.
-/
def timeoutOf (p : Params) (r : Row) : Nat :=
  if 0 < r.timeoutS then r.timeoutS else
  match p.timeouts.find? (fun (w, j, _) => w == r.workflow && j == idOf r.job) with
  | some (_, _, t) => t
  | none => p.defaultTimeoutS

/-- Headroom bound on numbers: a run time $d$ is near a timeout $T$ when $\theta_d d > \theta_n T$.

$$\operatorname{near}_p(T, d) \iff \theta_n T < \theta_d d$$

The job used more than the fraction theta of its limit.
-/
def near (p : Params) (t d : Nat) : Bool := decide (p.thetaNum * t < p.thetaDen * d)

/-- A job is near its timeout when it ran and its run time is near its timeout.

$$\operatorname{nearT}_p(\rho) \iff \operatorname{ran}(\rho) \wedge \theta_n T_p(\rho) < \theta_d \operatorname{dur}(\rho)$$

Flags a job before it hits the limit.
-/
def nearTimeout (p : Params) (r : Row) : Bool := ran r && near p (timeoutOf p r) (runS r)

/-- The ready time of a job within its run's rows $R$: the later of the run start and the latest end among the jobs
of $R$ that ran, are of another family and ended by the job's start.

$$\operatorname{ready}_p(R, \rho) = \max\bigl(t_r(\rho), \max[\,t_e(o) \mid o \in R,\ \operatorname{ran}(o),\ \operatorname{fam}_p(o) \ne \operatorname{fam}_p(\rho),\ t_e(o) \le t_s(\rho)\,]\bigr)$$

The earliest moment the job could have been waiting for a runner.
-/
def readyS (p : Params) (rows : List Row) (r : Row) : Nat :=
  max r.startedS (mx ((rows.filter fun o => ran o && familyOf p o.job != familyOf p r.job && decide (o.endS ≤ r.startS)).map (·.endS)))

/-- The queue estimate of a job: its start minus its ready time.

$$\operatorname{queued}_p(R, \rho) = t_s(\rho) \mathbin{\dot-} \operatorname{ready}_p(R, \rho)$$

How long the job waited for a runner, at most.
-/
def queuedS (p : Params) (rows : List Row) (r : Row) : Nat := r.startS - readyS p rows r

/-- A job queued too long: it ran and its queue estimate exceeds $q$.

$$\operatorname{queue}_p(R, \rho) \iff \operatorname{ran}(\rho) \wedge \operatorname{queued}_p(R, \rho) > q$$

Flags a job that waited for a runner longer than the limit.
-/
def queued (p : Params) (rows : List Row) (r : Row) : Bool := ran r && decide (p.queueMaxS < queuedS p rows r)

/-! ## Per-run facts -/

/-- The job seconds of a run: the sum of the run times of its counted jobs.

$$x(R) = \Sigma[\,\operatorname{dur}(\rho) \mid \rho \in R,\ \operatorname{counted}(\rho)\,]$$

The runner time a run cost.
-/
def jobS (rows : List Row) : Nat := sumL ((rows.filter counted).map runS)

/-- The sibling groups of a run: the distinct groups of its counted jobs, in first-appearance order.

$$G_p(R) = \operatorname{dedup}[\,\operatorname{group}_p(\mathit{job}_\rho) \mid \rho \in R,\ \operatorname{counted}(\rho)\,]$$

The parallel legs of the run.
-/
def groupNames (p : Params) (rows : List Row) : List String :=
  ((rows.filter counted).map fun r => groupOf p r.job).eraseDups

/-- The run times of the counted jobs of group $g$ in a run.

$$D_p(R, g) = [\,\operatorname{dur}(\rho) \mid \rho \in R,\ \operatorname{counted}(\rho),\ \operatorname{group}_p(\mathit{job}_\rho) = g\,]$$

The sibling shards side by side.
-/
def groupDurs (p : Params) (rows : List Row) (g : String) : List Nat :=
  ((rows.filter counted).filter fun r => groupOf p r.job == g).map runS

/-- A list of sibling run times is imbalanced when it has at least two values, its maximum is at least $m_s$ and
max/mean exceeds $\rho$.

$$\operatorname{imb}_p(D) \iff |D| \ge 2 \wedge \max(D) \ge m_s \wedge \rho_n \Sigma(D) < \rho_d |D| \max(D)$$

One shard takes much longer than its siblings on average.
-/
def imbalanced (p : Params) (ds : List Nat) : Bool :=
  decide (2 ≤ ds.length) && decide (p.minShardS ≤ mx ds) && decide (p.rhoNum * sumL ds < p.rhoDen * (ds.length * mx ds))

/-- Growth of a run with job seconds $x$ against the job seconds $P$ of the earlier runs of its workflow; the window is
$w = \operatorname{lastN}(N, P)$.

$$\operatorname{grow}_p(P, x) \iff |w| \ge n_{\min} \wedge x \ge m_j \wedge g_n \operatorname{p50}(w) < g_d x$$

The run cost much more than the recent runs of its workflow.
-/
def growthAt (p : Params) (prev : List Nat) (x : Nat) : Bool :=
  decide (p.nMin ≤ (lastN p.window prev).length) && decide (p.minJobS ≤ x) &&
    decide (p.gNum * p50 (lastN p.window prev) < p.gDen * x)

/-- The classes that fire for a run with rows $R$ and earlier job seconds $P$, in the order imbalance, growth,
nearTimeout, queue.

$$F_p(R, P) = [\,c \in (\mathsf{imbalance}, \mathsf{growth}, \mathsf{nearTimeout}, \mathsf{queue}) \mid \phi_c\,],\quad \begin{aligned} \phi_{\mathsf{imbalance}} &\iff \exists g \in G_p(R),\ \operatorname{imb}_p(D_p(R, g)) \\ \phi_{\mathsf{growth}} &\iff \operatorname{grow}_p(P, x(R)) \\ \phi_{\mathsf{nearTimeout}} &\iff \exists \rho \in R,\ \operatorname{nearT}_p(\rho) \\ \phi_{\mathsf{queue}} &\iff \exists \rho \in R,\ \operatorname{queue}_p(R, \rho) \end{aligned}$$

Everything that is wrong with the shape of one run.
-/
def firesRun (p : Params) (rows : List Row) (prev : List Nat) : List Cls :=
  (if (groupNames p rows).any (fun g => imbalanced p (groupDurs p rows g)) then [.imbalance] else []) ++
  (if growthAt p prev (jobS rows) then [.growth] else []) ++
  (if rows.any (nearTimeout p) then [.nearTimeout] else []) ++
  (if rows.any (queued p rows) then [.queue] else [])

/-! ## Runs in order, raised and open alerts -/

/-- The rows of run `id`.

$$R(\mathit{id}) = [\,\rho \in \mathit{rows} \mid \mathit{run}_\rho = \mathit{id}\,]$$

All jobs of one run.
-/
def runRows (rows : List Row) (id : Nat) : List Row := rows.filter (·.run == id)

/-- The order key of a run: (creation time of its first row, run id); (0, id) when it has no row.

$$\kappa(\mathit{id}) = (t_c(\rho_0), \mathit{id}),\ \rho_0 \text{ the first row of } R(\mathit{id})$$

Runs are compared by when they were created.
-/
def runKey (rows : List Row) (id : Nat) : Nat × Nat := (((runRows rows id).head?.map (·.createdS)).getD 0, id)

/-- The workflows of the rows, in first-appearance order.

$$W = \operatorname{dedup}[\,\mathit{wf}_\rho \mid \rho \in \mathit{rows}\,]$$

Every workflow seen.
-/
def workflows (rows : List Row) : List String := (rows.map (·.workflow)).eraseDups

/-- The runs of workflow `wf`, ordered by $\kappa$ (lexicographic; a stable merge sort).

$$\operatorname{runs}(\mathit{wf}) = \operatorname{sort}_\kappa\bigl(\operatorname{dedup}[\,\mathit{run}_\rho \mid \rho \in \mathit{rows},\ \mathit{wf}_\rho = \mathit{wf}\,]\bigr)$$

The history of one workflow, oldest first.
-/
def orderedRuns (rows : List Row) (wf : String) : List Nat :=
  ((rows.filter (·.workflow == wf)).map (·.run)).eraseDups.mergeSort fun a b =>
    let ka := runKey rows a; let kb := runKey rows b
    decide (ka.1 < kb.1) || (decide (ka.1 = kb.1) && decide (ka.2 ≤ kb.2))

/-- The fired classes of each run of a list of runs (in order): run $i$ is judged against the job seconds of runs
$0..i-1$.

$$\operatorname{fs}(\mathit{ids})_i = F_p\bigl(R(\mathit{id}_i), [x(R(\mathit{id}_0)), \dots, x(R(\mathit{id}_{i-1}))]\bigr)$$

Each run's verdict, given its history.
-/
def firesSeq (p : Params) (rows : List Row) (ids : List Nat) : List (List Cls) :=
  let xs := ids.map fun id => jobS (runRows rows id)
  (List.range ids.length).map fun i => firesRun p (runRows rows (ids.getD i 0)) (xs.take i)

/-- Class $c$ is raised at run $i$ of a sequence of fired sets when it fires at $i$ and did not fire at $i-1$ (always
at $i = 0$; an index past the end fires nothing).

$$\operatorname{raised}(\mathit{fs}, i, c) \iff c \in \mathit{fs}_i \wedge (i = 0 \vee c \notin \mathit{fs}_{i-1}),\quad \mathit{fs}_j = [] \text{ for } j \ge |\mathit{fs}|$$

An alert starts when its cause appears.
-/
def raised (fs : List (List Cls)) (i : Nat) (c : Cls) : Bool :=
  decide (c ∈ fs.getD i []) && (i == 0 || !decide (c ∈ fs.getD (i - 1) []))

/-- The open classes: those that fire on the latest run ([] when there is none).

$$\operatorname{open}(\mathit{fs}) = \begin{cases} \mathit{fs}_{|\mathit{fs}|-1} & \mathit{fs} \ne [] \\ [] & \mathit{fs} = [] \end{cases}$$

What is still wrong now.
-/
def openOf (fs : List (List Cls)) : List Cls := fs.getLast?.getD []

/-! ## Alerts with their witness -/

/-- An alert: workflow, class, the run (with branch, sha, creation time) and the witness: `subject` (group, job or
`job seconds`), `value` (max shard, job seconds, run time or queue estimate) and `bound` (mean shard, median of the
window, timeout or queue limit).

$$a = (\mathit{wf}, c, \mathit{run}, \mathit{branch}, \mathit{sha}, t_c, \mathit{subject}, v, b)$$

What fired, where, and by how much.
-/
structure Alert where
  workflow : String
  cls      : Cls
  run      : Nat
  branch   : String
  sha      : String
  createdS : Nat
  subject  : String
  value    : Nat
  bound    : Nat
deriving DecidableEq, Repr

/-- The first imbalanced group of a run (in group order), if any.

$$\operatorname{wit}_p(R) = \text{the first } g \in G_p(R) \text{ with } \operatorname{imb}_p(D_p(R, g)),\ \text{or none}$$

Names the group that broke the ratio.
-/
def imbWitness (p : Params) (rows : List Row) : Option String :=
  (groupNames p rows).find? fun g => imbalanced p (groupDurs p rows g)

/-- The alert of class `c` for a run with rows `rows` and earlier job seconds `prev`. Witnesses: imbalance, the first
imbalanced group with its maximum and floored mean; growth, the job seconds and the window median; nearTimeout, the
first near job with its run time and timeout; queue, the first queued job with its estimate and $q$. A class that has
no witness gets subject `""` and value and bound 0.

$$\operatorname{alert}_p(c, R, P) = (\mathit{wf}_{\rho_0}, c, \mathit{run}_{\rho_0}, \mathit{branch}_{\rho_0}, \mathit{sha}_{\rho_0}, t_c(\rho_0), s, v, b),\quad \rho_0 = \text{the first row of } R \ (\text{empty strings and } 0 \text{ when } R = [])$$

$$(s, v, b) = \begin{cases} (g, \max D, \lfloor \Sigma(D) / |D| \rfloor),\ D = D_p(R, g) & c = \mathsf{imbalance},\ \operatorname{wit}_p(R) = g \\ (\texttt{job seconds}, x(R), \operatorname{p50}(\operatorname{lastN}(N, P))) & c = \mathsf{growth} \\ (\mathit{job}_\rho, \operatorname{dur}(\rho), T_p(\rho)) & c = \mathsf{nearTimeout},\ \rho \text{ the first } \rho \in R \text{ with } \operatorname{nearT}_p(\rho) \\ (\mathit{job}_\rho, \operatorname{queued}_p(R, \rho), q) & c = \mathsf{queue},\ \rho \text{ the first } \rho \in R \text{ with } \operatorname{queue}_p(R, \rho) \\ (\texttt{""}, 0, 0) & c \in \{\mathsf{imbalance}, \mathsf{nearTimeout}, \mathsf{queue}\} \text{ without such a } g \text{ or } \rho \end{cases}$$

Builds the alert line for one class of one run.
-/
def alertOf (p : Params) (rows : List Row) (prev : List Nat) (c : Cls) : Alert :=
  let r0 : Row := rows.headD { run := 0, workflow := "", job := "", startS := 0, endS := 0 }
  let base : Alert :=
    { workflow := r0.workflow, cls := c, run := r0.run, branch := r0.branch, sha := r0.sha, createdS := r0.createdS,
      subject := "", value := 0, bound := 0 }
  match c with
  | .imbalance => match imbWitness p rows with
    | some g => let ds := groupDurs p rows g
      { base with subject := g, value := mx ds, bound := sumL ds / ds.length }
    | none => base
  | .growth => { base with subject := "job seconds", value := jobS rows, bound := p50 (lastN p.window prev) }
  | .nearTimeout => match rows.find? (nearTimeout p) with
    | some r => { base with subject := r.job, value := runS r, bound := timeoutOf p r }
    | none => base
  | .queue => match rows.find? (queued p rows) with
    | some r => { base with subject := r.job, value := queuedS p rows r, bound := p.queueMaxS }
    | none => base

/-- The raised alerts of one workflow, oldest run first, classes in fired order.

$$\operatorname{events}(\mathit{wf}) = [\,\operatorname{alert}_p(c, R(\mathit{id}_i), P_i) \mid i < |\mathit{ids}|,\ c \in \mathit{fs}_i,\ \operatorname{raised}(\mathit{fs}, i, c)\,]$$

Every time a cause appeared in the workflow's history.
-/
def raisedOf (p : Params) (rows : List Row) (wf : String) : List Alert :=
  let ids := orderedRuns rows wf
  let fs := firesSeq p rows ids
  let xs := ids.map fun id => jobS (runRows rows id)
  (List.range ids.length).flatMap fun i =>
    ((fs.getD i []).filter fun c => raised fs i c).map fun c =>
      alertOf p (runRows rows (ids.getD i 0)) (xs.take i) c

/-- The open alerts of one workflow: the classes that fire on its latest run, with that run's witnesses.

$$\operatorname{open}(\mathit{wf}) = [\,\operatorname{alert}_p(c, R(\mathit{id}_{n-1}), P_{n-1}) \mid c \in \operatorname{open}(\mathit{fs})\,],\ n = |\mathit{ids}| \ge 1;\ [] \text{ when } n = 0$$

What the workflow's newest run still shows.
-/
def openAlertsOf (p : Params) (rows : List Row) (wf : String) : List Alert :=
  let ids := orderedRuns rows wf
  let fs := firesSeq p rows ids
  let xs := ids.map fun id => jobS (runRows rows id)
  match ids.length with
  | 0 => []
  | n + 1 => (openOf fs).map fun c => alertOf p (runRows rows (ids.getD n 0)) (xs.take n) c

/-! ## Theorems -/

/-- The imbalance alert of a group is raised exactly when its three bounds are crossed.

$$\forall p, D:\quad \operatorname{imb}_p(D) \iff |D| \ge 2 \wedge m_s \le \max(D) \wedge \rho_n \Sigma(D) < \rho_d |D| \max(D)$$

Imbalance means at least two shards, a long enough maximum, and max/mean above rho.
-/
theorem imbalanced_iff (p : Params) (ds : List Nat) :
    imbalanced p ds = true ↔
      2 ≤ ds.length ∧ p.minShardS ≤ mx ds ∧ p.rhoNum * sumL ds < p.rhoDen * (ds.length * mx ds) := by
  simp [imbalanced, Bool.and_eq_true, decide_eq_true_eq, and_assoc]

/-- The growth alert is raised exactly when the window is long enough, the run is above the floor and above $g$ times
the window median.

$$\forall p, P, x:\quad \operatorname{grow}_p(P, x) \iff |w| \ge n_{\min} \wedge m_j \le x \wedge g_n \operatorname{p50}(w) < g_d x,\quad w = \operatorname{lastN}(N, P)$$

Growth is a run costing more than g times the median of the recent runs.
-/
theorem growth_iff (p : Params) (prev : List Nat) (x : Nat) :
    growthAt p prev x = true ↔
      p.nMin ≤ (lastN p.window prev).length ∧ p.minJobS ≤ x ∧ p.gNum * p50 (lastN p.window prev) < p.gDen * x := by
  simp [growthAt, Bool.and_eq_true, decide_eq_true_eq, and_assoc]

/-- A job is near its timeout exactly when it ran and its run time is above $\theta$ times its timeout.

$$\forall p, \rho:\quad \operatorname{nearT}_p(\rho) \iff \operatorname{ran}(\rho) \wedge \theta_n T_p(\rho) < \theta_d (t_e \mathbin{\dot-} t_s)$$

The headroom alert is a job past theta of its limit.
-/
theorem nearTimeout_iff (p : Params) (r : Row) :
    nearTimeout p r = true ↔ ran r = true ∧ p.thetaNum * timeoutOf p r < p.thetaDen * (r.endS - r.startS) := by
  unfold nearTimeout near runS
  simp only [Bool.and_eq_true]
  exact ⟨fun ⟨a, b⟩ => ⟨a, of_decide_eq_true b⟩, fun ⟨a, b⟩ => ⟨a, decide_eq_true b⟩⟩

/-- A job is queued too long exactly when it ran and its queue estimate is above $q$.

$$\forall p, R, \rho:\quad \operatorname{queue}_p(R, \rho) \iff \operatorname{ran}(\rho) \wedge q < t_s(\rho) \mathbin{\dot-} \operatorname{ready}_p(R, \rho)$$

The queue alert is a job that waited longer than the limit.
-/
theorem queued_iff (p : Params) (rows : List Row) (r : Row) :
    queued p rows r = true ↔ ran r = true ∧ p.queueMaxS < r.startS - readyS p rows r := by
  unfold queued queuedS
  simp only [Bool.and_eq_true]
  exact ⟨fun ⟨a, b⟩ => ⟨a, of_decide_eq_true b⟩, fun ⟨a, b⟩ => ⟨a, decide_eq_true b⟩⟩

/-- A class fires for a run exactly when its metric crosses its bound.

$$\forall p, R, P:\quad \begin{aligned} \mathsf{imbalance} \in F_p(R, P) &\iff \exists g \in G_p(R),\ \operatorname{imb}_p(D_p(R, g)) \\ \mathsf{growth} \in F_p(R, P) &\iff \operatorname{grow}_p(P, x(R)) \\ \mathsf{nearTimeout} \in F_p(R, P) &\iff \exists \rho \in R,\ \operatorname{nearT}_p(\rho) \\ \mathsf{queue} \in F_p(R, P) &\iff \exists \rho \in R,\ \operatorname{queue}_p(R, \rho) \end{aligned}$$

Each alert class fires on exactly its own condition.
-/
theorem alert_iff (p : Params) (rows : List Row) (prev : List Nat) :
    (Cls.imbalance ∈ firesRun p rows prev ↔ ∃ g ∈ groupNames p rows, imbalanced p (groupDurs p rows g) = true) ∧
    (Cls.growth ∈ firesRun p rows prev ↔ growthAt p prev (jobS rows) = true) ∧
    (Cls.nearTimeout ∈ firesRun p rows prev ↔ ∃ r ∈ rows, nearTimeout p r = true) ∧
    (Cls.queue ∈ firesRun p rows prev ↔ ∃ r ∈ rows, queued p rows r = true) := by
  refine ⟨?_, ?_, ?_, ?_⟩ <;>
  · simp only [firesRun, List.mem_append]
    split <;> split <;> split <;> split <;>
      simp_all [List.any_eq_true]

/-- Equal sibling run times never raise an imbalance alert when $\rho \ge 1$.

$$\forall p, n, d:\quad \rho_d \le \rho_n \Rightarrow \neg\operatorname{imb}_p([\underbrace{d, \dots, d}_{n}])$$

Perfectly balanced shards are never flagged.
-/
theorem no_alert_on_balanced (p : Params) (n d : Nat) (h : p.rhoDen ≤ p.rhoNum) :
    imbalanced p (List.replicate n d) = false := by
  have hs : sumL (List.replicate n d) = n * d := by
    induction n with
    | zero => simp [sumL]
    | succ k ih => simp only [List.replicate_succ, sumL, ih, Nat.succ_mul]; omega
  have hm : ∀ k, mx (List.replicate (k + 1) d) = d := by
    intro k
    induction k with
    | zero => simp [mx]
    | succ j ih => rw [List.replicate_succ, mx, ih, Nat.max_self]
  cases hb : imbalanced p (List.replicate n d) with
  | false => rfl
  | true =>
    exfalso
    rw [imbalanced_iff, hs, List.length_replicate] at hb
    obtain ⟨h2, _, hlt⟩ := hb
    obtain ⟨k, rfl⟩ : ∃ k, n = k + 1 := ⟨n - 1, by omega⟩
    rw [hm k] at hlt
    exact absurd (Nat.lt_of_lt_of_le hlt (Nat.mul_le_mul_right _ h)) (Nat.lt_irrefl _)

/-- A run whose every sibling group has equal run times raises no imbalance alert when $\rho \ge 1$.

$$\forall p, R, P:\quad \rho_d \le \rho_n \wedge \bigl(\forall g \in G_p(R)\ \exists d,\ D_p(R, g) = [d, \dots, d]\bigr) \Rightarrow \mathsf{imbalance} \notin F_p(R, P)$$

Balanced runs never carry the imbalance class.
-/
theorem no_imbalance_on_balanced_run (p : Params) (rows : List Row) (prev : List Nat) (h : p.rhoDen ≤ p.rhoNum)
    (hb : ∀ g ∈ groupNames p rows, ∃ d, groupDurs p rows g = List.replicate (groupDurs p rows g).length d) :
    Cls.imbalance ∉ firesRun p rows prev := by
  rw [(alert_iff p rows prev).1]
  rintro ⟨g, hg, hi⟩
  obtain ⟨d, hd⟩ := hb g hg
  rw [hd, no_alert_on_balanced p _ d h] at hi
  exact Bool.false_ne_true hi

/-- No self-masking: if at most half of the window exceeds a level $t$ and the run is above $g$ times $t$ (with a long
enough window and a run above the floor), growth fires.

$$\forall p, P, x, t:\quad |w| \ge n_{\min} \wedge m_j \le x \wedge 2 \cdot |[y \in w \mid y > t]| \le |w| \wedge g_n t < g_d x \Rightarrow \operatorname{grow}_p(P, x),\quad w = \operatorname{lastN}(N, P)$$

A jump is caught as long as at most half of the recent runs were already above the old level.
-/
theorem growth_of_few_above (p : Params) (prev : List Nat) (x t : Nat)
    (hn : p.nMin ≤ (lastN p.window prev).length) (hx : p.minJobS ≤ x)
    (hf : 2 * (lastN p.window prev).countP (fun y => decide (t < y)) ≤ (lastN p.window prev).length)
    (hg : p.gNum * t < p.gDen * x) : growthAt p prev x = true := by
  have hm := p50_le_of_few_above _ t hf
  rw [growth_iff]
  exact ⟨hn, hx, Nat.lt_of_le_of_lt (Nat.mul_le_mul_left _ hm) hg⟩

/-- Growth within the window: write the window as $a \mathbin{+\!\!+} [v] \mathbin{+\!\!+} b$ with every value of $a$
at most $v$ (a non-decreasing series puts every older run there) and $v$ at most $\lfloor |w|/2 \rfloor + 1$ runs back
($2|b| \le |w|$). A run above $g$ times $v$ fires growth: in a growing series, growth by more than $g$ within
$\lfloor N/2 \rfloor + 1 \le N$ runs is caught.

$$\forall p, P, a, v, b, x:\quad w = a \mathbin{+\!\!+} [v] \mathbin{+\!\!+} b \wedge (\forall y \in a,\ y \le v) \wedge 2|b| \le |w| \wedge |w| \ge n_{\min} \wedge m_j \le x \wedge g_n v < g_d x \Rightarrow \operatorname{grow}_p(P, x),\quad w = \operatorname{lastN}(N, P)$$

A series that grows by more than g within half a window plus one run raises growth.
-/
theorem growth_within (p : Params) (prev : List Nat) (a b : List Nat) (v x : Nat)
    (hw : lastN p.window prev = a ++ v :: b) (ha : ∀ y ∈ a, y ≤ v)
    (hb : 2 * b.length ≤ (lastN p.window prev).length)
    (hn : p.nMin ≤ (lastN p.window prev).length) (hx : p.minJobS ≤ x) (hg : p.gNum * v < p.gDen * x) :
    growthAt p prev x = true := by
  apply growth_of_few_above p prev x v hn hx _ hg
  have h0 : a.countP (fun y => decide (v < y)) = 0 :=
    List.countP_eq_zero.mpr (fun y hy hc => by have := ha y hy; simp at hc; omega)
  have hc : (a ++ v :: b).countP (fun y => decide (v < y)) ≤ b.length := by
    rw [List.countP_append, List.countP_cons, h0]
    have := List.countP_le_length (p := fun y => decide (v < y)) (l := b)
    simp
    omega
  rw [hw] at hb ⊢
  omega

/-- Growth detection is monotone in the run's job seconds.

$$\forall p, P, x, x':\quad x \le x' \wedge \operatorname{grow}_p(P, x) \Rightarrow \operatorname{grow}_p(P, x')$$

A run that costs even more is flagged too.
-/
theorem growth_mono (p : Params) (prev : List Nat) (x x' : Nat) (hle : x ≤ x') (h : growthAt p prev x = true) :
    growthAt p prev x' = true := by
  rw [growth_iff] at h ⊢
  obtain ⟨h1, h2, h3⟩ := h
  exact ⟨h1, Nat.le_trans h2 hle, Nat.lt_of_lt_of_le h3 (Nat.mul_le_mul_left _ hle)⟩

/-- Raised exactly when the class fires at $i$ and not at $i - 1$.

$$\forall \mathit{fs}, i, c:\quad \operatorname{raised}(\mathit{fs}, i, c) \iff c \in \mathit{fs}_i \wedge (i = 0 \vee c \notin \mathit{fs}_{i-1})$$

An alert starts on the run where its cause first shows again.
-/
theorem raised_iff (fs : List (List Cls)) (i : Nat) (c : Cls) :
    raised fs i c = true ↔ c ∈ fs.getD i [] ∧ (i = 0 ∨ c ∉ fs.getD (i - 1) []) := by
  simp [raised, Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq]

/-- Dedup: between two raises of the same class there is a run where it did not fire (it cleared), so a class that
keeps firing is raised once.

$$\forall \mathit{fs}, i, j, c:\quad i < j \wedge \operatorname{raised}(\mathit{fs}, i, c) \wedge \operatorname{raised}(\mathit{fs}, j, c) \Rightarrow \exists m,\ i < m < j \wedge c \notin \mathit{fs}_m$$

One alert per workflow and class until it clears.
-/
theorem dedup (fs : List (List Cls)) (i j : Nat) (c : Cls) (hij : i < j)
    (hi : raised fs i c = true) (hj : raised fs j c = true) :
    ∃ m, i < m ∧ m < j ∧ c ∉ fs.getD m [] := by
  rw [raised_iff] at hi hj
  rcases hj.2 with h0 | hn
  · omega
  · refine ⟨j - 1, ?_, by omega, hn⟩
    rcases Nat.lt_or_ge i (j - 1) with h | h
    · exact h
    · have : i = j - 1 := by omega
      subst this
      exact absurd hi.1 hn

/-- The open classes are those of the last run (none for the empty sequence, as $\mathit{fs}_j = []$ past the end).

$$\forall \mathit{fs}, c:\quad c \in \operatorname{open}(\mathit{fs}) \iff c \in \mathit{fs}_{|\mathit{fs}| \mathbin{\dot-} 1}$$

An alert is open exactly while the newest run still fires it.
-/
theorem open_iff (fs : List (List Cls)) (c : Cls) :
    c ∈ openOf fs ↔ c ∈ fs.getD (fs.length - 1) [] := by
  simp only [openOf, List.getLast?_eq_getElem?, List.getD_eq_getElem?_getD]

/-- One step: if a job's run time grows from $a$ to $b$ by at most $(1 - \theta) T$ and $b$ passes the timeout $T$,
then $a$ was already near the timeout (with $0 < \theta_d$ and $\theta_n \le \theta_d$).

$$\forall p, T, a, b:\quad 0 < \theta_d \wedge \theta_n \le \theta_d \wedge \theta_d b \le \theta_d a + (\theta_d \mathbin{\dot-} \theta_n) T \wedge T < b \Rightarrow \theta_n T < \theta_d a$$

A job that jumps past its limit in one small step was flagged on the run before.
-/
theorem caught_before_timeout (p : Params) (t a b : Nat) (hd : 0 < p.thetaDen) (hθ : p.thetaNum ≤ p.thetaDen)
    (hstep : p.thetaDen * b ≤ p.thetaDen * a + (p.thetaDen - p.thetaNum) * t) (hb : t < b) :
    near p t a = true := by
  simp only [near, decide_eq_true_eq]
  have hsub : (p.thetaDen - p.thetaNum) * t = p.thetaDen * t - p.thetaNum * t := Nat.sub_mul _ _ _
  have hle : p.thetaNum * t ≤ p.thetaDen * t := Nat.mul_le_mul_right _ hθ
  have hlt : p.thetaDen * t < p.thetaDen * b := (Nat.mul_lt_mul_left hd).mpr hb
  omega

/-- A series of run times of one job, starting within its timeout $T$ and growing by at most $(1 - \theta) T$ per run,
has a run within $T$ that is near the timeout before any run that passes $T$.

$$\forall p, T, d:\quad 0 < \theta_d \wedge \theta_n \le \theta_d \wedge d_0 \le T \wedge \bigl(\forall i,\ i + 1 < |d| \Rightarrow \theta_d d_{i+1} \le \theta_d d_i + (\theta_d \mathbin{\dot-} \theta_n) T\bigr) \Rightarrow \forall j < |d|,\ T < d_j \Rightarrow \exists i < j,\ d_i \le T \wedge \theta_n T < \theta_d d_i$$

With bounded growth per run, the alert always comes before the timeout (here $d_i$ is the $i$-th value, 0 past the end).
-/
theorem caught_series (p : Params) (t : Nat) (ds : List Nat) (hd : 0 < p.thetaDen) (hθ : p.thetaNum ≤ p.thetaDen)
    (h0 : ds.getD 0 0 ≤ t)
    (hstep : ∀ i, i + 1 < ds.length →
      p.thetaDen * ds.getD (i + 1) 0 ≤ p.thetaDen * ds.getD i 0 + (p.thetaDen - p.thetaNum) * t) :
    ∀ j, j < ds.length → t < ds.getD j 0 → ∃ i, i < j ∧ ds.getD i 0 ≤ t ∧ near p t (ds.getD i 0) = true := by
  intro j
  induction j with
  | zero => intro _ h; omega
  | succ k ih =>
    intro hj hk
    rcases Nat.lt_or_ge t (ds.getD k 0) with hgt | hle
    · obtain ⟨i, hi, h1, h2⟩ := ih (by omega) hgt
      exact ⟨i, by omega, h1, h2⟩
    · exact ⟨k, by omega, hle, caught_before_timeout p t _ _ hd hθ (hstep k hj) hk⟩

/-- The queue estimate never exceeds the true wait: for any set $N$ of the run's jobs that ran, are of another family
and ended by the job's start (its `needs`, whatever the graph), the estimate is at most the start minus the later of
the run start and the last end in $N$.

$$\forall p, R, \rho, N:\quad (\forall o \in N,\ o \in R \wedge \operatorname{ran}(o) \wedge \operatorname{fam}_p(o) \ne \operatorname{fam}_p(\rho) \wedge t_e(o) \le t_s(\rho)) \Rightarrow \operatorname{queued}_p(R, \rho) \le t_s(\rho) \mathbin{\dot-} \max(t_r(\rho), \max[t_e(o) \mid o \in N])$$

The estimate is conservative, so a queue alert is never caused by the estimate itself.
-/
theorem queued_le (p : Params) (rows : List Row) (r : Row) (needs : List Row)
    (hN : ∀ o ∈ needs, o ∈ rows ∧ ran o = true ∧ familyOf p o.job ≠ familyOf p r.job ∧ o.endS ≤ r.startS) :
    queuedS p rows r ≤ r.startS - max r.startedS (mx (needs.map (·.endS))) := by
  unfold queuedS readyS
  apply Nat.sub_le_sub_left
  refine Nat.max_le.mpr ⟨Nat.le_max_left _ _, Nat.le_trans ?_ (Nat.le_max_right _ _)⟩
  apply mx_le_of_subset
  intro x hx
  obtain ⟨o, ho, rfl⟩ := List.mem_map.mp hx
  obtain ⟨hr, hran, hf, he⟩ := hN o ho
  exact List.mem_map.mpr ⟨o, List.mem_filter.mpr ⟨hr, by simp [hran, hf, he]⟩, rfl⟩

/-- The imbalance witness names a group of the run that is imbalanced, so it has at least two sibling jobs.

$$\forall p, R, g:\quad \operatorname{wit}_p(R) = g \Rightarrow g \in G_p(R) \wedge \operatorname{imb}_p(D_p(R, g)) \wedge |D_p(R, g)| \ge 2$$

The alert always points at real siblings.
-/
theorem imbWitness_spec (p : Params) (rows : List Row) (g : String) (h : imbWitness p rows = some g) :
    g ∈ groupNames p rows ∧ imbalanced p (groupDurs p rows g) = true ∧ 2 ≤ (groupDurs p rows g).length := by
  have hm := List.mem_of_find?_eq_some h
  have hi := List.find?_some h
  exact ⟨hm, hi, ((imbalanced_iff p _).mp hi).1⟩

/-! ## Examples -/

/-- Example row: job `job` of run `run` (workflow `breakpoint-gate`), created at `created`, lasting `d` s.

$$\mathrm{gateRow}(r, c, j, d) = \{\mathit{run}=r,\ \mathit{createdS}=\mathit{startedS}=c,\ \mathit{job}=j,\ \mathit{startS}=c+60,\ \mathit{endS}=c+60+d,\ \mathit{timeoutS}=3600\}$$

A test row that started one minute after its run was created and has a 60 min timeout. -/
def gateRow (run created : Nat) (job : String) (d : Nat) : Row :=
  { run, workflow := "breakpoint-gate", createdS := created, startedS := created, job,
    startS := created + 60, endS := created + 60 + d, timeoutS := 3600 }

/-- Example: run 39101532038 (b35b541, integrate-ports-3) as the rows of run 3, created at 0.

$$\mathrm{run3} = [\mathrm{gateRow}(3, 0, \texttt{gate chromium j}i, c_i)]_{i<3} \mathbin{+\!\!+} [\mathrm{gateRow}(3, 0, \texttt{gate playwright-webkit j}i, w_i)]_{i<4},\quad c = (1756, 1444, 2749),\ w = (1249, 1270, 1295, 2986)$$

The measured shard durations of the run that showed the webkit j3 imbalance. -/
def run3 : List Row :=
  [gateRow 3 0 "gate chromium j0" 1756, gateRow 3 0 "gate chromium j1" 1444, gateRow 3 0 "gate chromium j2" 2749,
   gateRow 3 0 "gate playwright-webkit j0" 1249, gateRow 3 0 "gate playwright-webkit j1" 1270,
   gateRow 3 0 "gate playwright-webkit j2" 1295, gateRow 3 0 "gate playwright-webkit j3" 2986]

#guard groupDurs {} run3 "gate playwright-webkit" == [1249, 1270, 1295, 2986]
#guard imbalanced {} (groupDurs {} run3 "gate playwright-webkit")   -- 4 * 2986 / 6800 = 1.76 > 3/2
#guard !imbalanced {} (groupDurs {} run3 "gate chromium")           -- 3 * 2749 / 5949 = 1.39
#guard imbWitness {} run3 == some "gate playwright-webkit"
#guard run3.any (nearTimeout {})                                    -- 2986 > 3/4 * 3600 = 2700
#guard firesRun {} run3 [1560, 1600, 1550] == [.imbalance, .growth, .nearTimeout]
#guard !imbalanced {} [100, 100, 100] && !imbalanced {} [200, 400] && imbalanced {} [100, 400]
#guard !imbalanced {} [10, 40]                                       -- below the 300 s floor
#guard growthAt {} [1600, 1700, 1500] 3201 && !growthAt {} [1600, 1700, 1500] 3200 && !growthAt {} [1600, 1700] 9000
#guard raised [[.imbalance], [.imbalance], [], [.imbalance]] 0 .imbalance &&
  !raised [[.imbalance], [.imbalance], [], [.imbalance]] 1 .imbalance &&
  raised [[.imbalance], [.imbalance], [], [.imbalance]] 3 .imbalance
#guard openOf [[.growth], [.queue]] == [.queue] && openOf [] == []
-- queue: plan ends at 100, site 100..200, the shard starts at 2000 with ready 200: 1800 s > 1200 s
#guard queuedS {} [{ run := 1, workflow := "w", job := "site", startS := 100, endS := 200 },
  { run := 1, workflow := "w", job := "gate chromium j0", startS := 2000, endS := 2100 },
  { run := 1, workflow := "w", job := "gate chromium j1", startS := 210, endS := 1990 }]
  { run := 1, workflow := "w", job := "gate chromium j0", startS := 2000, endS := 2100 } == 1800
#guard timeoutOf { timeouts := [("w", "gate", 3600)] } { run := 1, workflow := "w", job := "gate chromium j0", startS := 0, endS := 1 } == 3600
#guard timeoutOf {} { run := 1, workflow := "w", job := "x", startS := 0, endS := 1 } == 21600
#guard groupNames {} run3 == ["gate chromium", "gate playwright-webkit"]   -- first appearance, no duplicates
#guard alertOf {} run3 [] .imbalance ==
  { workflow := "breakpoint-gate", cls := .imbalance, run := 3, branch := "", sha := "",
    createdS := 0, subject := "gate playwright-webkit", value := 2986, bound := 1700 }
#guard (alertOf {} run3 [] .nearTimeout).subject == "gate chromium j2" && (alertOf {} run3 [] .queue).value == 0
#guard (alertOf {} [] [] .growth).workflow == "" && (alertOf {} [] [] .growth).bound == 0

/-- Example: three runs of one workflow, listed newest first.

$$\mathrm{seq3} = [g(30, 300, \texttt{t (s0)}, 100),\ g(30, 300, \texttt{t (s1)}, 400),\ g(20, 200, \texttt{t (s0)}, 300),\ g(20, 200, \texttt{t (s1)}, 300),\ g(10, 100, \texttt{t (s0)}, 100),\ g(10, 100, \texttt{t (s1)}, 400)],\quad g = \mathrm{gateRow}$$

Runs 10 and 30 are imbalanced (400 vs 100) and run 20 is balanced, so ordering and dedup can be checked. -/
def seq3 : List Row :=
  [gateRow 30 300 "t (s0)" 100, gateRow 30 300 "t (s1)" 400, gateRow 20 200 "t (s0)" 300, gateRow 20 200 "t (s1)" 300,
   gateRow 10 100 "t (s0)" 100, gateRow 10 100 "t (s1)" 400]

#guard orderedRuns seq3 "breakpoint-gate" == [10, 20, 30]
#guard firesSeq {} seq3 [10, 20, 30] == [[.imbalance], [], [.imbalance]]
#guard (raisedOf {} seq3 "breakpoint-gate").map (·.run) == [10, 30]
#guard (openAlertsOf {} seq3 "breakpoint-gate").map (·.run) == [30] && openAlertsOf {} seq3 "other" == []

end Fw.Obs.CiShape
