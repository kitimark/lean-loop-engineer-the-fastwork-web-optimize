import Lean.Data.Json
/-!
# Timing: when an automation step took too long

Every automation step (an `fw` command, a `fw land` phase, a `check.sh` stage, a CI job) records a timing sample
(task `timing-spans`). This module is the pure decision over those samples: is the latest run of a step **slow**
against its own history, and is one step of a parallel stage **structural**, i.e. the one that sets the stage's wall
time by a wide margin (the sweeps-vs-shards case of the breakpoint gate). A step flagged either way is handed to an
agent to investigate and improve (task `timing-alert` wires the op and the alert).

Definitions (all durations in whole ms, `Nat`):
* A sample is `(tool, step, d, h, λ, kind)` with host `h ∈ {local, ci}` and
  `λ` the floor of the 1-min load average when it ran. Its key is `(tool, step, h, kind)`.
* A local sample with `λ > L` is **noisy**: it gets the verdict `noisy` and never enters a window. A CI sample is
  never noisy.
* The **window** of a sample is the last `N` non-noisy samples with the same key that come before it in the input.
* The **baseline** is the nearest-rank median (p50) of the window: the `⌈ n/2 ⌉`-th smallest of its `n`
  values, defined by counting (`ord`), so no sort is needed and the proofs are about counts. It was the p90 until
  task `timing-small-n`: with `n ≤ 9` the p90 is the window maximum, so a regression seen twice became its own
  baseline (history `[2,1,2,27,26]` s, then 40 s was `ok`). A median moves only once a shift fills more than half the window
  (`no_self_mask`), so the counterexample is now `slow` (`site_regression_slow`).
* Verdict of one sample, first match: `noBaseline` when the window has fewer than `n_min` samples; `noisy`; `slow`
  when `d > max(B, k · b)` with `B` the step's budget and `b` the baseline; otherwise `ok`.
* A **ceiling** is an absolute limit `C(tool, step)` for one step. A non-noisy sample above its
  ceiling is `slow` at once, with no window needed: a step that is slow from its first run (the 2-minute `fw land`)
  has no history to be slow against, so the relative rule alone never alerts for it. `landCeilings` sets 30 s for the
  whole `fw land` and 5 s for the time its lock is held.
* **Structural call**: a stage is a list of groups (a group is the list of keys of one job, e.g. the matrix legs of
  `sweeps`); a group's baseline is the largest final baseline of its keys (defined when every key has one). Every
  group of every stage gets a call: `structural` when its baseline exceeds twice every sibling group's baseline,
  `noise` when every sibling has a baseline but one is at least half of it, `undecided` otherwise.
* **Where stages come from**: `params.stages` when the caller gives any; otherwise (`fw watch` sends no params) they
  are derived from the CI job samples (`autoStages`): one stage per CI workflow with at least two job families, one
  group per job family (the job name up to its first `" ("`, so matrix legs share a group). A workflow is a coarser
  stage than its parallel jobs (sequential jobs count as siblings too), so an auto `structural` call reads "this job
  family dominates its workflow's job time".

Proved (main results; helper lemmas below): `slow_iff`, `ceilingBreach_iff`, `land_budget_alert`,
`no_alert_within_budget`, `no_alert_within_budget_list`, `slow_mono_dur`, `slow_mono_window`, `no_self_mask`,
`site_regression_slow`, `site_repeat_slow`, `stable_never_slow`, `noBaseline_iff`, `noBaseline_below_nmin`,
`ord_spec`, `ord_le_iff`, `ord_mono`, `ord_interlace`, `ord_between`, `cnt_split`, `p50_le_of_few_above`,
`le_p50_of_few_below`, `outlier_between`, `outlier_bound`, `outlier_shift`, `structural_iff`, `noise_iff`,
`calls_total`, `calls_given_stages`, `mem_structural`, `deterministic`, `timingVerdicts_total`.

Wire: `timingVerdicts` is the entry point (op `obs.timing`, wired by `timing-alert`); the golden is
`packages/contracts/golden/obs/timing.jsonl`, rendered by `Fw.Wire.Obs.Timing.goldenText` at the end of this file.
-/
namespace Fw.Obs.Timing

/-! ## Samples and parameters -/

/-- Where a sample was taken: on the local machine or on a CI runner. -/
inductive Host where
  | «local»
  | ci
deriving DecidableEq, Repr

/-- One timing sample: tool, step, duration in ms, host, the floor of the 1-min load average when it ran, and the run
kind (empty when the run has none; for a CI dispatch the digest of its inputs, so runs with different inputs are
different histories).
-/
structure Sample where
  tool  : String
  step  : String
  durMs : Nat
  host  : Host
  load  : Nat := 0
  kind  : String := ""
deriving DecidableEq, Repr

/-- The history a sample belongs to: same tool, same step, same host, same run kind. -/
structure Key where
  tool : String
  step : String
  host : Host
  kind : String := ""
deriving DecidableEq, Repr

/-- The key of a sample. -/
def Sample.key (s : Sample) : Key := { tool := s.tool, step := s.step, host := s.host, kind := s.kind }

/-- One job of a parallel stage: a name and its keys (the matrix legs of one job, or a single key). -/
structure Group where
  name : String
  keys : List Key
deriving DecidableEq, Repr

/-- A parallel stage: an id and the groups that run side by side in it (the input grouping that defines siblings). -/
structure Stage where
  id     : String
  groups : List Group
deriving DecidableEq, Repr

/-- The parameters: `n_min` (`nMin`), the window length `N` (`window`), the multiplier `k = k_n / k_d`
(`kNum`, `kDen`), the default budget `B_0` in ms (`budgetMs`), per-tool budget overrides (`budgets`, first match
wins), per-step ceilings (`ceilings`, first match wins), the load limit `L` (`loadMax`, compared with the floor of the 1-min load average; the default 16 is twice the
8 cores of the local Mac), and the parallel stages (`stages`).
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

/-- The number of values of `xs` at or below `v`. -/
def cntLe (xs : List Nat) (v : Nat) : Nat := xs.countP (fun x => decide (x ≤ v))

/-- The values of `xs` with at least `j + 1` values of `xs` at or below them (in list order). -/
def cands (xs : List Nat) (j : Nat) : List Nat := xs.filter (fun v => decide (j + 1 ≤ cntLe xs v))

/-- The order statistic of index `j` (0-based): the least value of `xs` with at least `j + 1` values of `xs` at or
below it, that is the `(j+1)`-th smallest value; 0 when there is none (exactly when `j ≥ |X|`).
-/
def ord (xs : List Nat) (j : Nat) : Nat := ((cands xs j).min?).getD 0

/-- The nearest rank of the 90th percentile among `n` values: `⌈ 9n/10 ⌉` (1-based; 0 for `n = 0`). -/
def rank90 (n : Nat) : Nat := (9 * n + 9) / 10

/-- The nearest-rank p90 of a list: its `⌈ 9n/10 ⌉`-th smallest value; 0 for the empty list. -/
def p90 (xs : List Nat) : Nat := ord xs (rank90 xs.length - 1)

#guard rank90 0 == 0 && rank90 1 == 1 && rank90 9 == 9 && rank90 10 == 9 && rank90 11 == 10 && rank90 20 == 18
#guard ord [5, 1, 4, 1, 3] 0 == 1 && ord [5, 1, 4, 1, 3] 1 == 1 && ord [5, 1, 4, 1, 3] 2 == 3
#guard ord [5, 1, 4, 1, 3] 4 == 5 && ord [5, 1, 4, 1, 3] 5 == 0 && ord [] 0 == 0
#guard p90 [] == 0 && p90 [7] == 7 && p90 [3, 9, 1] == 9
#guard p90 [10, 20, 30, 40, 50, 60, 70, 80, 90, 100] == 90
#guard p90 [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110] == 100

/-- The nearest rank of the median among `n` values: `⌈ n/2 ⌉` (1-based; 0 for `n = 0`). -/
def rank50 (n : Nat) : Nat := (n + 1) / 2

/-- The nearest-rank median (p50) of a list: its `⌈ n/2 ⌉`-th smallest value (the lower median for an even
length); 0 for the empty list. This is the baseline of the slow test.
-/
def p50 (xs : List Nat) : Nat := ord xs (rank50 xs.length - 1)

#guard rank50 0 == 0 && rank50 1 == 1 && rank50 2 == 1 && rank50 5 == 3 && rank50 6 == 3 && rank50 20 == 10
#guard p50 [] == 0 && p50 [7] == 7 && p50 [3, 9, 1] == 3 && p50 [4, 1, 3, 2] == 2
#guard p50 [2000, 1000, 2000, 27000, 26000] == 2000 && p90 [2000, 1000, 2000, 27000, 26000] == 27000

/-! ## The verdict of one sample -/

/-- A sample is noisy when it ran locally at a load above the limit (CI samples never are). -/
def noisy (p : Params) (s : Sample) : Bool := decide (s.host = .«local») && decide (p.loadMax < s.load)

/-- The last `n` elements of a list (all of it when it is shorter). -/
def lastN (n : Nat) (xs : List Nat) : List Nat := xs.drop (xs.length - n)

/-- The window of key `k` in a history: the durations of the last `N` samples of `hist` with key `k` that are not
noisy, oldest first.
-/
def windowOf (p : Params) (hist : List Sample) (k : Key) : List Nat :=
  lastN p.window ((hist.filter (fun s => decide (s.key = k) && !noisy p s)).map (·.durMs))

/-- The budget of a tool: its first override in `budgets`, else the default `B_0`. -/
def budgetOf (p : Params) (tool : String) : Nat := (p.budgets.lookup tool).getD p.budgetMs

/-- The ceiling of a step: the limit of the first entry of `ceilings` with that tool and step, if any. -/
def ceilingOf (p : Params) (tool step : String) : Option Nat :=
  (p.ceilings.find? (fun c => decide (c.1 = tool) && decide (c.2.1 = step))).map (·.2.2)

/-- A sample breaches its ceiling when its step has one, the sample is not noisy, and it took longer than the ceiling.
No window is involved.
-/
def ceilingBreach (p : Params) (s : Sample) : Bool :=
  match ceilingOf p s.tool s.step with
  | some c => decide (c < s.durMs) && !noisy p s
  | none => false

/-- The budget a sample is held to: its tool's budget, lowered to the step's ceiling when the step has one. -/
def budgetFor (p : Params) (s : Sample) : Nat :=
  match ceilingOf p s.tool s.step with
  | some c => min (budgetOf p s.tool) c
  | none => budgetOf p s.tool

/-- The slow test, exact over the rationals: `d > max(B, k · b)` with `k = k_n / k_d`, cross-multiplied so no
division happens (for `k_d ≥ 1` it is the same as `d > B ∧ d > k · b`; for `k_d = 0` the second half is
false and nothing is slow).
-/
def overLimit (p : Params) (budget base d : Nat) : Bool :=
  decide (budget < d) && decide (p.kNum * base < p.kDen * d)

/-- The verdict code of one sample. -/
inductive Code where
  | noBaseline
  | noisy
  | ok
  | slow
deriving DecidableEq, Repr

/-- The code of sample `s` against window `w`, first match: too short a window, noisy, slow, ok. The baseline is the
median of the window (with `n_min = 0` an empty window passes the first test and has baseline 0).
-/
def codeOf (p : Params) (w : List Nat) (s : Sample) : Code :=
  if w.length < p.nMin then .noBaseline
  else if noisy p s then .noisy
  else if overLimit p (budgetOf p s.tool) (p50 w) s.durMs then .slow
  else .ok

/-- The verdict of one sample: its index, key and duration, the code, the window size, the baseline (p50 of the
window, 0 for an empty window) and the budget.
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
  kind     : String := ""
deriving DecidableEq, Repr

/-- The verdict of sample `s` at index `i` with the earlier samples `hist`: `slow` when it breaches its step's ceiling
(whatever the window), else the code against the window.
-/
def judge (p : Params) (hist : List Sample) (i : Nat) (s : Sample) : SampleVerdict :=
  let w := windowOf p hist s.key
  { idx := i, tool := s.tool, step := s.step, host := s.host, durMs := s.durMs,
    code := if ceilingBreach p s then .slow else codeOf p w s,
    n := w.length, baseline := p50 w, budgetMs := budgetFor p s, kind := s.kind }

/-- One verdict per sample, in input order; sample `i` is judged against the samples before it. -/
def sampleVerdicts (p : Params) (ss : List Sample) : List SampleVerdict :=
  ss.mapIdx (fun i s => judge p (ss.take i) i s)

/-! ## Structural verdicts -/

/-- The final baseline of a key: the p50 of its window over all samples, defined when that window has at least
`n_min` samples.
-/
def finalBaseline (p : Params) (ss : List Sample) (k : Key) : Option Nat :=
  if p.nMin ≤ (windowOf p ss k).length then some (p50 (windowOf p ss k)) else none

/-- The largest value of a list, 0 for the empty list. -/
def maxL (xs : List Nat) : Nat := xs.foldl max 0

/-- A group's baseline: the largest final baseline of its keys, defined when the group has a key and every key has a
final baseline.
-/
def groupBaseline (p : Params) (ss : List Sample) (g : Group) : Option Nat :=
  let bs := g.keys.filterMap (finalBaseline p ss)
  if !g.keys.isEmpty && bs.length == g.keys.length then some (maxL bs) else none

/-- The call on one group of a stage: it sets the stage's time by a wide margin (`structural`), it does not
(`noise`), or there is not enough history to tell (`undecided`).
-/
inductive Call where
  | structural
  | noise
  | undecided
deriving DecidableEq, Repr

/-- A structural verdict: the stage, the group, the call on it, its baseline (0 when it has none) and the largest
sibling baseline (0 when no sibling has one).
-/
structure StructVerdict where
  stage      : String
  group      : String
  call       : Call
  baseline   : Nat
  siblingMax : Nat
deriving DecidableEq, Repr

/-- The test on the sibling baselines: every sibling has one and twice it is below `b`. -/
def below (b : Nat) : Option Nat → Bool
  | some c => decide (2 * c < b)
  | none => false

/-- The sibling baselines of group `g` in stage `S`: the group baselines of the other groups of the stage, in order
(a group listed twice is not its own sibling).
-/
def siblings (p : Params) (ss : List Sample) (st : Stage) (g : Group) : List (Option Nat) :=
  (st.groups.filter (fun g' => decide (g' ≠ g))).map (groupBaseline p ss)

/-- The call on group `g` in stage `S`, first match: `undecided` when `g` has no baseline or no sibling;
`structural` when every sibling has a baseline `c` with `2c < b`; `noise` when every sibling has a baseline (so one
of them has `2c ≥ b`); `undecided` otherwise (a sibling without a baseline).
-/
def callOf (p : Params) (ss : List Sample) (st : Stage) (g : Group) : Call :=
  match groupBaseline p ss g with
  | none => .undecided
  | some b =>
    let sib := siblings p ss st g
    if sib.isEmpty then .undecided
    else if sib.all (below b) then .structural
    else if sib.all Option.isSome then .noise
    else .undecided

/-- The structural verdict of group `g` in stage `S`: the call, the group's baseline (0 without one) and the largest
sibling baseline (0 without one).
-/
def stageVerdict (p : Params) (ss : List Sample) (st : Stage) (g : Group) : StructVerdict :=
  { stage := st.id, group := g.name, call := callOf p ss st g, baseline := (groupBaseline p ss g).getD 0,
    siblingMax := maxL ((siblings p ss st g).filterMap id) }

/-- A job-level CI sample: a CI sample whose step is a job name (no `/`; step spans are `<job>/<step>`). -/
def isJob (s : Sample) : Bool := decide (s.host = .ci) && !s.step.contains '/'

/-- The job family of a job name: the name up to its first `" ("`, so the matrix legs `gate (chromium, s4)` and
`gate (playwright-webkit, s0)` share the family `gate`; a name without `" ("` is its own family.
-/
def family (step : String) : String := (step.splitOn " (").headD step

/-- The keys of the job-level CI samples, first occurrence order, without repeats. -/
def jobKeys (ss : List Sample) : List Key := ((ss.filter isJob).map Sample.key).eraseDups

/-- The stages derived from the samples when the caller gives none: one stage per CI workflow (tool) that has at
least two job families, with one group per family (named by the family, holding that family's job keys), in first
occurrence order. A workflow is coarser than a parallel stage: sequential jobs count as siblings too.
-/
def autoStages (ss : List Sample) : List Stage :=
  let ks := jobKeys ss
  (ks.map (·.tool)).eraseDups.filterMap fun t =>
    let fams := ((ks.filter (fun k => decide (k.tool = t))).map (fun k => family k.step)).eraseDups
    if fams.length < 2 then none
    else some { id := t, groups := fams.map fun f =>
      { name := f, keys := ks.filter (fun k => decide (k.tool = t) && decide (family k.step = f)) } }

/-- The stages the structural calls are made on: the caller's stages when it gives any, else the derived ones. -/
def stagesOf (p : Params) (ss : List Sample) : List Stage :=
  if p.stages.isEmpty then autoStages ss else p.stages

/-- All structural verdicts: one per group of every stage, stage by stage, group by group. -/
def structuralVerdicts (p : Params) (ss : List Sample) : List StructVerdict :=
  (stagesOf p ss).flatMap (fun st => st.groups.map (stageVerdict p ss st))

/-- A verdict: one per sample, or a structural one. -/
inductive Verdict where
  | sample (v : SampleVerdict)
  | structural (v : StructVerdict)
deriving DecidableEq, Repr

/-- The entry point (wire op `obs.timing`): the samples in time order give one verdict each, in order, followed by
the structural verdicts.
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
   { tool := "t", step := "b", durMs := 49, host := .«local» }]).length == 4
#guard (callOf { nMin := 1 } [{ tool := "t", step := "s", durMs := 100, host := .«local» },
   { tool := "t", step := "b", durMs := 50, host := .«local» }]
  { id := "x", groups := [{ name := "a", keys := [lk] }, { name := "b", keys := [{ lk with step := "b" }] }] }
  { name := "a", keys := [lk] }) == .noise
#guard (callOf { nMin := 1 } [{ tool := "t", step := "s", durMs := 100, host := .«local» },
   { tool := "t", step := "b", durMs := 49, host := .«local» }]
  { id := "x", groups := [{ name := "a", keys := [lk] }, { name := "b", keys := [{ lk with step := "b" }] }] }
  { name := "a", keys := [lk] }) == .structural
#guard (callOf { nMin := 1 } [{ tool := "t", step := "s", durMs := 100, host := .«local» }]
  { id := "x", groups := [{ name := "a", keys := [lk] }, { name := "b", keys := [{ lk with step := "b" }] }] }
  { name := "a", keys := [lk] }) == .undecided
#guard (callOf { nMin := 1 } [{ tool := "t", step := "s", durMs := 100, host := .«local» }]
  { id := "x", groups := [{ name := "a", keys := [lk] }] } { name := "a", keys := [lk] }) == .undecided
#guard family "gate (chromium, s4)" == "gate" && family "site" == "site" && family "" == ""
#guard isJob { tool := "w", step := "site", durMs := 1, host := .ci } &&
  !isJob { tool := "w", step := "site/Build", durMs := 1, host := .ci } &&
  !isJob { tool := "w", step := "site", durMs := 1, host := .«local» }
#guard (autoStages [{ tool := "w", step := "gate (c, s0)", durMs := 1, host := .ci },
    { tool := "w", step := "sweeps (c)", durMs := 1, host := .ci },
    { tool := "w", step := "gate (c, s1)", durMs := 1, host := .ci },
    { tool := "w", step := "gate (c, s0)/Run", durMs := 1, host := .ci },
    { tool := "v", step := "only", durMs := 1, host := .ci },
    { tool := "w", step := "gate (c, s0)", durMs := 1, host := .ci }]).map
    (fun st => (st.id, st.groups.map (fun g => (g.name, g.keys.map (·.step))))) ==
  [("w", [("gate", ["gate (c, s0)", "gate (c, s1)"]), ("sweeps", ["sweeps (c)"])])]
#guard stagesOf { stages := [{ id := "x", groups := [] }] } [] == [{ id := "x", groups := [] }]

/-! ## Proofs: the verdict of one sample -/

/-- A sample breaches its ceiling exactly when its step has a ceiling `c`, it is not noisy and it took longer than `c`. -/
theorem ceilingBreach_iff (p : Params) (s : Sample) :
    ceilingBreach p s = true ↔
      ∃ c, ceilingOf p s.tool s.step = some c ∧ c < s.durMs ∧ noisy p s = false := by
  unfold ceilingBreach
  cases h : ceilingOf p s.tool s.step with
  | none => simp
  | some c => simp

/-- The relative rule alone: the code against a window is `slow` exactly when the window is long enough, the sample is
not noisy, and its duration exceeds both the budget and `k` times the baseline.
-/
theorem codeOf_slow_iff (p : Params) (w : List Nat) (s : Sample) :
    codeOf p w s = .slow ↔
      p.nMin ≤ w.length ∧ noisy p s = false ∧ budgetOf p s.tool < s.durMs ∧
        p.kNum * p50 w < p.kDen * s.durMs := by
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
enough, the sample is not noisy, and its duration exceeds both the budget and `k` times the baseline.
-/
theorem slow_iff (p : Params) (hist : List Sample) (i : Nat) (s : Sample) :
    (judge p hist i s).code = .slow ↔
      ceilingBreach p s = true ∨
      (p.nMin ≤ (windowOf p hist s.key).length ∧ noisy p s = false ∧ budgetOf p s.tool < s.durMs ∧
        p.kNum * p50 (windowOf p hist s.key) < p.kDen * s.durMs) := by
  unfold judge
  simp only
  by_cases hb : ceilingBreach p s = true
  · simp [hb]
  · simp only [hb, Bool.false_eq_true, ite_false, false_or]
    exact codeOf_slow_iff p _ s

/-- No alert within budget: a sample whose duration is at most its budget (its tool's budget, lowered to the step's
ceiling) is never `slow`.
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

/-- Every sample verdict of the entry point is `judge` of its sample against the samples before it. -/
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
-/
theorem no_alert_within_budget_list (p : Params) (hist : List Sample) (v : SampleVerdict)
    (h : Verdict.sample v ∈ timingVerdicts p hist) (hb : v.durMs ≤ v.budgetMs) : v.code ≠ .slow := by
  obtain ⟨i, hi, rfl⟩ := mem_sample p hist v h
  exact no_alert_within_budget p _ i _ hb

/-- The ceilings of `fw land`, from the land-speed research targets (a Lean-touching land under 20 s p50, the lock
held under 5 s): 30 s for the whole land (step `total`) and 5 s for the time its lock is held (step `lock held`).
-/
def landCeilings : List (String × String × Nat) :=
  [("fw land", "total", 30000), ("fw land", "lock held", 5000)]

/-- A land over budget alerts. With the land ceilings first in `ceilings`, a non-noisy `fw land` sample over 30 s for
its `total`, or over 5 s for its `lock held`, has the verdict `slow`, whatever its history (even none: a land that is
slow from its first run is flagged).
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
-/
theorem slow_mono_dur (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (d : Nat)
    (h : (judge p hist i s).code = .slow) (hd : s.durMs ≤ d) :
    (judge p hist i { s with durMs := d }).code = .slow := by
  rcases (slow_iff p hist i s).1 h with hb | ⟨h1, h2, h3, h4⟩
  · obtain ⟨c, hc, hlt, hn⟩ := (ceilingBreach_iff p s).1 hb
    exact (slow_iff p hist i _).2 (Or.inl ((ceilingBreach_iff p _).2 ⟨c, hc, by simp only; omega, hn⟩))
  · refine (slow_iff p hist i _).2 (Or.inr ⟨h1, h2, by simp only; omega, ?_⟩)
    exact Nat.lt_of_lt_of_le h4 (Nat.mul_le_mul_left _ hd)

/-- The verdict is `noBaseline` exactly when the window has fewer than `n_min` samples and the sample does not
breach a ceiling (a breach is `slow` whatever the window).
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

/-- The window is at most `N` long and at most as long as the number of earlier samples with the same key. -/
theorem window_length (p : Params) (hist : List Sample) (k : Key) :
    (windowOf p hist k).length ≤ p.window ∧
      (windowOf p hist k).length ≤ hist.countP (fun s => decide (s.key = k)) := by
  have hc : (hist.filter (fun s => decide (s.key = k) && !noisy p s)).length ≤
      hist.countP (fun s => decide (s.key = k)) := by
    rw [← List.countP_eq_length_filter]
    exact List.countP_mono_left (by intro x _ hx; simp only [Bool.and_eq_true] at hx; exact hx.1)
  simp only [windowOf, lastN, List.length_drop, List.length_map]
  omega

/-- Below `n_min`, no verdict: with fewer than `n_min` earlier samples of the same key, or a window shorter than
`n_min`, the verdict is `noBaseline` (unless the sample breaches a ceiling, which needs no window).
-/
theorem noBaseline_below_nmin (p : Params) (hist : List Sample) (i : Nat) (s : Sample)
    (hb : ceilingBreach p s = false)
    (h : hist.countP (fun t => decide (t.key = s.key)) < p.nMin ∨ p.window < p.nMin) :
    (judge p hist i s).code = .noBaseline := by
  have := window_length p hist s.key
  exact (noBaseline_iff p hist i s).2 ⟨by omega, hb⟩

/-- Deterministic and local: the verdict of a sample depends only on the parameters, the sample, its index and the
earlier samples with the same key (samples of other steps or hosts, in any interleaving, change nothing).
-/
theorem deterministic (p : Params) (hist : List Sample) (i : Nat) (s : Sample) :
    judge p hist i s = judge p (hist.filter (fun t => decide (t.key = s.key))) i s := by
  have : windowOf p hist s.key = windowOf p (hist.filter (fun t => decide (t.key = s.key))) s.key := by
    simp only [windowOf, List.filter_filter]
    congr 3
    funext x
    cases decide (x.key = s.key) <;> simp
  simp only [judge, this]

/-- Total: the output holds one verdict per sample, in input order (sample `i` judged against the samples before
it), followed by the structural verdicts.
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

/-- Every non-empty list of naturals has a largest element. -/
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

/-- `cntLe` is monotone in the bound. -/
theorem cntLe_mono (xs : List Nat) (v w : Nat) (h : v ≤ w) : cntLe xs v ≤ cntLe xs w :=
  List.countP_mono_left (by intro x _ hx; simp only [decide_eq_true_eq] at hx ⊢; omega)

/-- For an index inside the list, `ord` is a value of the list with at least `j + 1` values at or below it, and it is
the least such value.
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

/-- The order statistics are sorted: a larger index gives a value at least as large. -/
theorem ord_mono (xs : List Nat) (j j' : Nat) (h : j ≤ j') (hj' : j' < xs.length) :
    ord xs j ≤ ord xs j' := by
  rw [ord_le_iff xs j _ (by omega)]
  have := (ord_spec xs j' hj').2.1
  omega

/-- Counting after one replacement: the count at any bound moves by at most one. -/
theorem cntLe_replace (a b : List Nat) (x y v : Nat) :
    cntLe (a ++ y :: b) v ≤ cntLe (a ++ x :: b) v + 1 := by
  simp only [cntLe, List.countP_append, List.countP_cons]
  split <;> split <;> omega

/-- Counting after one replacement, at a bound not below the new value or below it. -/
theorem cntLe_replace_y (a b : List Nat) (x y v : Nat) :
    (y ≤ v → cntLe (a ++ x :: b) v ≤ cntLe (a ++ y :: b) v) ∧
      (v < y → cntLe (a ++ y :: b) v ≤ cntLe (a ++ x :: b) v) := by
  simp only [cntLe, List.countP_append, List.countP_cons]
  constructor <;> intro h <;> split <;> split <;> simp_all <;> omega

/-- Interlacing: replacing one value of a list moves its order statistic of index `j` at most to the neighbouring
order statistics of the old list (indices `j - 1` and `j + 1`, where they exist).
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

/-- The new order statistic lies between the old one and the new value. -/
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

/-- The rank of p90 is an index of the list: `1 ≤ rank_90(n) ≤ n` for `n ≥ 1`, and
`2 ≤ rank_90(n) < n` for `n ≥ 10`.
-/
theorem rank90_bounds (n : Nat) :
    (1 ≤ n → 1 ≤ rank90 n ∧ rank90 n ≤ n) ∧ (10 ≤ n → 2 ≤ rank90 n ∧ rank90 n < n) := by
  simp only [rank90]; omega

/-- An outlier moves the p90 (the baseline before task `timing-small-n`, still used by the outlier bounds below)
only toward itself: replacing one window value `x` by `y` leaves the new p90 between the old p90 and `y` (any window
length; for a window of fewer than 10 values the p90 is the maximum, so a large `y` can raise it all the way to `y`).
-/
theorem outlier_between (a b : List Nat) (x y : Nat) :
    min (p90 (a ++ x :: b)) y ≤ p90 (a ++ y :: b) ∧ p90 (a ++ y :: b) ≤ max (p90 (a ++ x :: b)) y := by
  have hlen : (a ++ y :: b).length = (a ++ x :: b).length := by simp
  have hpos : 1 ≤ (a ++ x :: b).length := by
    simp only [List.length_append, List.length_cons]; omega
  have := (rank90_bounds (a ++ x :: b).length).1 hpos
  simp only [p90, hlen]
  exact ord_between a b x y _ (by omega)

/-- The outlier bound: for a window of at least 10 values with p90 rank `r = ⌈ 9n/10 ⌉`, replacing any one
value (by anything, however large or small) leaves the new p90 between the old `(r-1)`-th and `(r+1)`-th smallest
values, that is between the old order statistics adjacent to the old p90 (`ord` is 0-based, so these are the indices
`r-2` and `r`; `r ≥ 2` here, so `r - 2` does not truncate).
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

/-! ## Proofs: the median baseline (task `timing-small-n`) -/

/-- Every value is at or below `t` or above it: the two counts add up to the length. -/
theorem cnt_split (xs : List Nat) (t : Nat) :
    cntLe xs t + xs.countP (fun x => decide (t < x)) = xs.length := by
  rw [List.length_eq_countP_add_countP (fun x => decide (x ≤ t))]
  unfold cntLe
  congr 1
  apply List.countP_congr
  intro x _
  simp only [decide_eq_true_eq]
  omega

/-- The median is at most `t` when at most half of the values exceed `t` (also for the empty list, whose median is
0).
-/
theorem p50_le_of_few_above (xs : List Nat) (t : Nat)
    (h : 2 * xs.countP (fun x => decide (t < x)) ≤ xs.length) : p50 xs ≤ t := by
  cases xs with
  | nil => simp [p50, ord, cands]
  | cons a r =>
    have hs := cnt_split (a :: r) t
    have hl : 1 ≤ (a :: r).length := by simp
    unfold p50
    rw [ord_le_iff _ _ _ (by simp only [rank50]; omega)]
    simp only [rank50]
    omega

/-- The median is at least `t` when fewer than half of the values are below `t`. -/
theorem le_p50_of_few_below (xs : List Nat) (t : Nat)
    (h : 2 * xs.countP (fun x => decide (x < t)) < xs.length) : t ≤ p50 xs := by
  rcases Nat.eq_zero_or_pos t with rfl | ht
  · exact Nat.zero_le _
  · apply Classical.byContradiction
    intro hlt
    have hle : p50 xs ≤ t - 1 := by omega
    unfold p50 at hle
    rw [ord_le_iff _ _ _ (by simp only [rank50]; omega)] at hle
    have hc : cntLe xs (t - 1) = xs.countP (fun x => decide (x < t)) :=
      List.countP_congr (by intro x _; simp only [decide_eq_true_eq]; omega)
    simp only [rank50] at hle
    omega

/-- No self-masking: a slowdown is judged against a median that it can only move once it fills more than half the
window. If at most half of the window exceeds a level `t`, a non-noisy sample over budget with `k_d · d > k_n · t` is `slow` (with the p90 baseline this failed for `n ≤ 9`, where the p90 is the maximum).
-/
theorem no_self_mask (p : Params) (w : List Nat) (s : Sample) (t : Nat)
    (hn : p.nMin ≤ w.length) (hq : noisy p s = false) (hB : budgetOf p s.tool < s.durMs)
    (hfew : 2 * w.countP (fun x => decide (t < x)) ≤ w.length) (hk : p.kNum * t < p.kDen * s.durMs) :
    codeOf p w s = .slow :=
  (codeOf_slow_iff p w s).2 ⟨hn, hq, hB,
    Nat.lt_of_le_of_lt (Nat.mul_le_mul_left _ (p50_le_of_few_above w t hfew)) hk⟩

/-- Slow is monotone in the window: a window of the same length with at least as many values at or below every bound
(no slower in distribution, e.g. some values lowered) keeps a `slow` sample `slow`.
-/
theorem slow_mono_window (p : Params) (w w' : List Nat) (s : Sample) (hl : w'.length = w.length)
    (hc : ∀ v, cntLe w v ≤ cntLe w' v) (h : codeOf p w s = .slow) : codeOf p w' s = .slow := by
  obtain ⟨h1, h2, h3, h4⟩ := (codeOf_slow_iff p w s).1 h
  refine (codeOf_slow_iff p w' s).2 ⟨by omega, h2, h3, ?_⟩
  have hle : p50 w' ≤ p50 w := by
    cases w with
    | nil =>
      have : w' = [] := List.eq_nil_of_length_eq_zero (by simpa using hl)
      subst this; exact Nat.le_refl _
    | cons a r =>
      have hpos : 1 ≤ (a :: r).length := by simp
      unfold p50
      rw [hl, ord_le_iff _ _ _ (by rw [hl]; simp only [rank50]; omega)]
      exact Nat.le_trans (ord_spec _ _ (by simp only [rank50]; omega)).2.1 (hc _)
  exact Nat.lt_of_le_of_lt (Nat.mul_le_mul_left _ hle) h4

/-- A value of a window is the duration of a sample of the history. -/
theorem mem_window (p : Params) (hist : List Sample) (k : Key) (x : Nat) (h : x ∈ windowOf p hist k) :
    ∃ s ∈ hist, s.durMs = x := by
  unfold windowOf lastN at h
  obtain ⟨s, hs, rfl⟩ := List.mem_map.1 (List.mem_of_mem_drop h)
  exact ⟨s, (List.mem_filter.1 hs).1, rfl⟩

/-- A value of a window comes from a sample of exactly that key, so a window never mixes run kinds. -/
theorem mem_window_key (p : Params) (hist : List Sample) (k : Key) (x : Nat) (h : x ∈ windowOf p hist k) :
    ∃ s ∈ hist, s.key = k ∧ s.durMs = x := by
  unfold windowOf lastN at h
  obtain ⟨s, hs, rfl⟩ := List.mem_map.1 (List.mem_of_mem_drop h)
  have := List.mem_filter.1 hs
  have hk : s.key = k := by
    have h2 := this.2
    simp only [Bool.and_eq_true, decide_eq_true_eq] at h2
    exact h2.1
  exact ⟨s, this.1, hk, rfl⟩

/-- A window never mixes run kinds: every value of the window of key `κ` comes from a sample whose run kind is the
kind of `κ`.
-/
theorem mem_window_kind (p : Params) (hist : List Sample) (k : Key) (x : Nat) (h : x ∈ windowOf p hist k) :
    ∃ s ∈ hist, s.kind = k.kind ∧ s.durMs = x := by
  obtain ⟨s, hs, hk, hd⟩ := mem_window_key p hist k x h
  exact ⟨s, hs, by rw [← hk]; rfl, hd⟩

/-- A stable series is never `slow`: when `n_min ≥ 1`, no sample breaches a ceiling, and every two durations of
the series are within the factor `k` (`k_d · d_s ≤ k_n · d_t`), no sample verdict is `slow`.
-/
theorem stable_never_slow (p : Params) (ss : List Sample) (h1 : 1 ≤ p.nMin)
    (hb : ∀ s ∈ ss, ceilingBreach p s = false)
    (ht : ∀ s ∈ ss, ∀ t ∈ ss, p.kDen * s.durMs ≤ p.kNum * t.durMs) :
    ∀ v ∈ sampleVerdicts p ss, v.code ≠ .slow := by
  intro v hv
  obtain ⟨i, hi, he⟩ := List.mem_iff_getElem.1 hv
  have hi' : i < ss.length := by simpa [sampleVerdicts, List.length_mapIdx] using hi
  have hv' : v = judge p (ss.take i) i ss[i] := by rw [← he]; simp [sampleVerdicts, List.getElem_mapIdx]
  subst hv'
  intro hs
  rcases (slow_iff p _ i _).1 hs with hbr | ⟨hn, _, _, hk⟩
  · rw [hb _ (List.getElem_mem hi')] at hbr; cases hbr
  · have hpos : 0 < (windowOf p (ss.take i) ss[i].key).length := by omega
    have hmem := (ord_spec (windowOf p (ss.take i) ss[i].key)
      (rank50 (windowOf p (ss.take i) ss[i].key).length - 1) (by simp only [rank50]; omega)).1
    obtain ⟨t, htm, hteq⟩ := mem_window p _ _ _ hmem
    have hst := ht ss[i] (List.getElem_mem hi') t (List.mem_of_mem_take htm)
    rw [hteq] at hst
    exact Nat.lt_irrefl _ (Nat.lt_of_lt_of_le hk hst)

/-- A site-build sample of the breakpoint gate (CI) with duration `d` ms, for the counterexample of task
`timing-small-n`.
-/
def siteBuild (d : Nat) : Sample := { tool := "breakpoint-gate", step := "site", durMs := d, host := .ci }

/-- The counterexample is now `slow`: after site builds of 2, 1, 2, 27 and 26 s, a 40 s build is `slow` with the
default parameters `p_0` (`{}`: `n_min = 5`, `N = 20`, `k = 3/2`, `B_0 = 30000`, no ceilings, no stages; median 2 s;
with the p90 baseline, 27 s, it was `ok` because `2 · 40 ≤ 3 · 27`).
-/
theorem site_regression_slow :
    (judge {} ([2000, 1000, 2000, 27000, 26000].map siteBuild) 5 (siteBuild 40000)).code = .slow := by
  decide

/-- A repeated regression stays `slow`: after site builds of 2, 1, 2, 27, 26 and 50 s, another 50 s build is `slow`
with the default parameters `p_0` (`{}`; the median is still 2 s; with the p90 baseline, 50 s, it was `ok`).
-/
theorem site_repeat_slow :
    (judge {} ([2000, 1000, 2000, 27000, 26000, 50000].map siteBuild) 6 (siteBuild 50000)).code = .slow := by
  decide

/-! ## Proofs: structural verdicts -/

/-- The sibling baselines are exactly the baselines of the other groups of the stage. -/
theorem mem_siblings (p : Params) (ss : List Sample) (st : Stage) (g : Group) (o : Option Nat) :
    o ∈ siblings p ss st g ↔ ∃ g' ∈ st.groups, g' ≠ g ∧ groupBaseline p ss g' = o := by
  simp [siblings, List.mem_map, List.mem_filter, and_assoc]

/-- A group has a sibling exactly when its sibling list is not empty. -/
theorem siblings_ne_nil (p : Params) (ss : List Sample) (st : Stage) (g : Group) :
    (siblings p ss st g).isEmpty = false ↔ ∃ g' ∈ st.groups, g' ≠ g := by
  constructor
  · intro h
    cases hs : siblings p ss st g with
    | nil => rw [hs] at h; simp at h
    | cons o _ =>
      obtain ⟨g', hg', hne, _⟩ := (mem_siblings p ss st g o).1 (by rw [hs]; simp)
      exact ⟨g', hg', hne⟩
  · rintro ⟨g', hg', hne⟩
    have hm := (mem_siblings p ss st g _).2 ⟨g', hg', hne, rfl⟩
    cases hs : siblings p ss st g with
    | nil => rw [hs] at hm; simp at hm
    | cons _ _ => rfl

/-- When a group is structural: it has a baseline `b`, its stage has another group, and every other group of the
stage has a baseline `c` with `2c < b`.
-/
theorem structural_iff (p : Params) (ss : List Sample) (st : Stage) (g : Group) :
    callOf p ss st g = .structural ↔
      ∃ b, groupBaseline p ss g = some b ∧ (∃ g' ∈ st.groups, g' ≠ g) ∧
        ∀ g' ∈ st.groups, g' ≠ g → ∃ c, groupBaseline p ss g' = some c ∧ 2 * c < b := by
  unfold callOf
  cases hg : groupBaseline p ss g with
  | none => simp
  | some b =>
    have hall : (siblings p ss st g).all (below b) = true ↔
        ∀ g' ∈ st.groups, g' ≠ g → ∃ c, groupBaseline p ss g' = some c ∧ 2 * c < b := by
      rw [List.all_eq_true]
      constructor
      · intro h g' hg' hne
        have := h _ ((mem_siblings p ss st g _).2 ⟨g', hg', hne, rfl⟩)
        cases hc : groupBaseline p ss g' with
        | none => rw [hc] at this; simp [below] at this
        | some c => rw [hc] at this; exact ⟨c, rfl, by simpa [below] using this⟩
      · intro h o ho
        obtain ⟨g', hg', hne, rfl⟩ := (mem_siblings p ss st g o).1 ho
        obtain ⟨c, hc, hlt⟩ := h g' hg' hne
        simp [hc, below, hlt]
    have hne := siblings_ne_nil p ss st g
    simp only
    by_cases he : (siblings p ss st g).isEmpty = true
    · simp only [he, ite_true]
      constructor
      · intro h; cases h
      · rintro ⟨_, _, h1, _⟩
        have := hne.2 h1; rw [he] at this; cases this
    · have he' : (siblings p ss st g).isEmpty = false := by simpa using he
      simp only [he', Bool.false_eq_true, ite_false]
      by_cases ha : (siblings p ss st g).all (below b) = true
      · simp only [ha, ite_true, true_iff]
        exact ⟨b, rfl, hne.1 he', hall.1 ha⟩
      · simp only [ha, Bool.false_eq_true, ite_false]
        constructor
        · intro h; split at h <;> cases h
        · rintro ⟨b', hb', _, h2⟩
          cases hb'
          exact absurd (hall.2 h2) ha

/-- When a group is noise: it has a baseline `b`, its stage has another group, every other group has a baseline, and
some other group has a baseline `c` with `2c ≥ b`.
-/
theorem noise_iff (p : Params) (ss : List Sample) (st : Stage) (g : Group) :
    callOf p ss st g = .noise ↔
      ∃ b, groupBaseline p ss g = some b ∧ (∃ g' ∈ st.groups, g' ≠ g) ∧
        (∀ g' ∈ st.groups, g' ≠ g → (groupBaseline p ss g').isSome = true) ∧
        ∃ g' ∈ st.groups, g' ≠ g ∧ ∃ c, groupBaseline p ss g' = some c ∧ b ≤ 2 * c := by
  unfold callOf
  cases hg : groupBaseline p ss g with
  | none => simp
  | some b =>
    have hsome : (siblings p ss st g).all Option.isSome = true ↔
        ∀ g' ∈ st.groups, g' ≠ g → (groupBaseline p ss g').isSome = true := by
      rw [List.all_eq_true]
      constructor
      · intro h g' hg' hne; exact h _ ((mem_siblings p ss st g _).2 ⟨g', hg', hne, rfl⟩)
      · intro h o ho
        obtain ⟨g', hg', hne, rfl⟩ := (mem_siblings p ss st g o).1 ho
        exact h g' hg' hne
    have hnotall : (siblings p ss st g).all (below b) = false ↔
        ∃ o ∈ siblings p ss st g, below b o = false := by
      constructor
      · intro h
        apply Classical.byContradiction
        intro hn
        have : (siblings p ss st g).all (below b) = true :=
          List.all_eq_true.2 (fun o ho => by
            cases hb : below b o
            · exact absurd ⟨o, ho, hb⟩ hn
            · rfl)
        rw [this] at h; cases h
      · rintro ⟨o, ho, hb⟩
        cases ha : (siblings p ss st g).all (below b)
        · rfl
        · rw [List.all_eq_true.1 ha o ho] at hb; cases hb
    have hne := siblings_ne_nil p ss st g
    simp only
    by_cases he : (siblings p ss st g).isEmpty = true
    · simp only [he, ite_true]
      constructor
      · intro h; cases h
      · rintro ⟨_, _, h1, _⟩
        have := hne.2 h1; rw [he] at this; cases this
    · have he' : (siblings p ss st g).isEmpty = false := by simpa using he
      simp only [he', Bool.false_eq_true, ite_false]
      by_cases ha : (siblings p ss st g).all (below b) = true
      · simp only [ha, ite_true]
        constructor
        · intro h; cases h
        · rintro ⟨b', hb', _, _, g', hg', hne', c, hc, hle⟩
          cases hb'
          have := List.all_eq_true.1 ha _ ((mem_siblings p ss st g _).2 ⟨g', hg', hne', rfl⟩)
          rw [hc] at this; simp [below] at this; omega
      · have ha' : (siblings p ss st g).all (below b) = false := by simpa using ha
        simp only [ha, Bool.false_eq_true, ite_false]
        by_cases hs : (siblings p ss st g).all Option.isSome = true
        · simp only [hs, ite_true, true_iff]
          obtain ⟨o, ho, hbo⟩ := hnotall.1 ha'
          obtain ⟨g', hg', hne', rfl⟩ := (mem_siblings p ss st g o).1 ho
          have hso := hsome.1 hs g' hg' hne'
          cases hc : groupBaseline p ss g' with
          | none => rw [hc] at hso; cases hso
          | some c =>
            rw [hc] at hbo
            simp only [below, decide_eq_false_iff_not] at hbo
            exact ⟨b, rfl, hne.1 he', hsome.1 hs, g', hg', hne', c, hc, by omega⟩
        · simp only [hs, Bool.false_eq_true, ite_false]
          constructor
          · intro h; cases h
          · rintro ⟨b', hb', _, h3, _⟩
            exact absurd (hsome.2 h3) hs

/-- The stages are the caller's whenever it gives any. -/
theorem stagesOf_given (p : Params) (ss : List Sample) (h : p.stages ≠ []) : stagesOf p ss = p.stages := by
  unfold stagesOf
  cases hs : p.stages with
  | nil => exact absurd hs h
  | cons _ _ => rfl

/-- The structural verdicts of the entry point are exactly the verdicts of the groups of the stages. -/
theorem mem_structural (p : Params) (ss : List Sample) (v : StructVerdict) :
    Verdict.structural v ∈ timingVerdicts p ss ↔
      ∃ st ∈ stagesOf p ss, ∃ g ∈ st.groups, stageVerdict p ss st g = v := by
  simp [timingVerdicts, structuralVerdicts, List.mem_flatMap]

/-- A call is made on every group of every stage: there is one structural verdict per group, and each group's verdict
(with its call) is in the output.
-/
theorem calls_total (p : Params) (ss : List Sample) :
    (structuralVerdicts p ss).length = ((stagesOf p ss).map (fun st => st.groups.length)).sum ∧
      ∀ st ∈ stagesOf p ss, ∀ g ∈ st.groups, Verdict.structural (stageVerdict p ss st g) ∈ timingVerdicts p ss := by
  refine ⟨by simp [structuralVerdicts, List.length_flatMap], ?_⟩
  intro st hst g hg
  exact (mem_structural p ss _).2 ⟨st, hst, g, hg, rfl⟩

/-- Whenever the caller gives stages, the structural call is made on every group of each of them. -/
theorem calls_given_stages (p : Params) (ss : List Sample) (h : p.stages ≠ []) :
    ∀ st ∈ p.stages, ∀ g ∈ st.groups, Verdict.structural (stageVerdict p ss st g) ∈ timingVerdicts p ss := by
  intro st hst g hg
  exact (calls_total p ss).2 st (by rw [stagesOf_given p ss h]; exact hst) g hg

end Fw.Obs.Timing

/-!
# Wire face and golden of `Fw.Obs.Timing`

JSON encoders for the future op `obs.timing` (wired by task `timing-alert` in `Fw.Wire.Obs`) and the golden
`packages/contracts/golden/obs/timing.jsonl`: one line per case, `{"name", "request", "response"}`, where `request`
is `{"op":"obs.timing","params","samples"}` and `response` is `{"verdicts"}` as `timingVerdicts` computes it.
Regenerate from `lean/` with `lake env lean --run scripts/TimingGolden.lean`; with `--check` it compares the file
with the Lean output (`checkGolden`). A structural verdict carries its `call` (`structural` / `noise` / `undecided`).
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

def callStr : Call → String
  | .structural => "structural"
  | .noise => "noise"
  | .undecided => "undecided"

def keyJson (k : Key) : Json :=
  Json.mkObj [("tool", .str k.tool), ("step", .str k.step), ("host", .str (hostStr k.host)),
    ("runKind", .str k.kind)]

def sampleJson (s : Sample) : Json :=
  Json.mkObj [("tool", .str s.tool), ("step", .str s.step), ("durMs", toJson s.durMs),
    ("host", .str (hostStr s.host)), ("load", toJson s.load), ("runKind", .str s.kind)]

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
      ("budgetMs", toJson v.budgetMs), ("runKind", .str v.kind)]
  | .structural v => Json.mkObj [("kind", "structural"), ("stage", .str v.stage), ("group", .str v.group),
      ("call", .str (callStr v.call)), ("baseline", toJson v.baseline), ("siblingMax", toJson v.siblingMax)]

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

def runK (tool step kind : String) (host : Host) (ds : List Nat) : List Sample :=
  ds.map fun d => { tool, step, durMs := d, host, kind }

/-- A check.sh history around 2 min (handoffs report 117 s and up to 136 s for check.sh). -/
def checkHist : List Nat := [117000, 124000, 131000, 119000, 136000, 122000]

/-- Five runs of a CI workflow `wf` with jobs `build`, `test (a)`, `test (b)`, `lint` and one step span. -/
def autoRuns : List Sample :=
  (List.range 5).flatMap fun _ =>
    [{ tool := "wf", step := "build", durMs := 10000, host := .ci },
     { tool := "wf", step := "test (a)", durMs := 100000, host := .ci },
     { tool := "wf", step := "test (b)", durMs := 110000, host := .ci },
     { tool := "wf", step := "lint", durMs := 20000, host := .ci },
     { tool := "wf", step := "test (a)/Run tests", durMs := 90000, host := .ci }]

def cases : List (String × Params × List Sample) :=
  [("breakpoint-gate run 39067656223: sweeps (345 s) is structural in stage {gate, sweeps} (gate shards <= 147 s), gate is noise, both merges are noise; one run, so every sample is noBaseline",
      gateParams, gateRun),
   ("lean check.sh 128 s after a history of 117-136 s: ok (not slow)",
      {}, run "lean" "check.sh" .«local» 9 (checkHist ++ [128000])),
   ("lean check.sh 205 s after a history of 117-136 s: slow (median 122 s; 2 * 205000 > 3 * 122000)",
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
        run "fw land" "lock held" .«local» 24 [150000]),
   ("slow-site-build regression: 40 s after 2, 1, 2, 27, 26 s is slow (median 2 s; the old p90 baseline 27 s gave ok)",
      {}, run "breakpoint-gate" "site" .ci 0 [2000, 1000, 2000, 27000, 26000, 40000]),
   ("repeated regression: a second 50 s site build after 2, 1, 2, 27, 26, 50 s is still slow (median 2 s)",
      {}, run "breakpoint-gate" "site" .ci 0 [2000, 1000, 2000, 27000, 26000, 50000, 50000]),
   ("stable series (every two durations within k = 3/2): 100-140 s, never slow",
      {}, run "ci:lean" "check" .ci 0 [100000, 120000, 140000, 110000, 130000, 100000, 140000]),
   ("a lasting shift is accepted once it fills more than half the window: 2 s x4 then 50 s x7, slow while the median is 2 s, ok from the 6th 50 s on (median 50 s)",
      {}, run "ci:w" "build" .ci 0 [2000, 2000, 2000, 2000, 50000, 50000, 50000, 50000, 50000, 50000, 50000]),
   ("auto stages (no params.stages): workflow wf over 5 runs; job family test (matrix legs 100 s and 110 s) is structural against build (10 s) and lint (20 s), which are noise; step spans are not jobs",
      {}, autoRuns),
   ("run kinds: chromium-counts of input digest d1 after 10 s x5 takes 60 s (slow); the first run of digest d2 takes 60 s (no baseline of its own)",
      {}, runK "ci:w" "chromium-counts" "d1" .ci [10000, 10000, 10000, 10000, 10000, 60000] ++ runK "ci:w" "chromium-counts" "d2" .ci [60000]),
   ("run kinds: a 60 s run of digest d1 after 10 s x5 (d1) and 60 s x5 (d2) is slow, d2 history does not hide it",
      {}, runK "ci:w" "chromium-counts" "d1" .ci [10000, 10000, 10000, 10000, 10000] ++
          runK "ci:w" "chromium-counts" "d2" .ci [60000, 60000, 60000, 60000, 60000] ++ runK "ci:w" "chromium-counts" "d1" .ci [60000])]

/-- The last verdict code of each case's samples, and the structural groups: the expected outcomes. -/
def lastCode (p : Params) (ss : List Sample) : Option Code :=
  ((sampleVerdicts p ss).getLast?).map (·.code)

#guard (structuralVerdicts gateParams gateRun).map (fun v => (v.stage, v.group, v.call, v.baseline, v.siblingMax)) ==
  [("breakpoint-gate:test", "gate", .noise, 147000, 345000), ("breakpoint-gate:test", "sweeps", .structural, 345000, 147000),
   ("breakpoint-gate:merge", "merge (chromium)", .noise, 36000, 34000),
   ("breakpoint-gate:merge", "merge (playwright-webkit)", .noise, 34000, 36000)]
#guard (sampleVerdicts gateParams gateRun).all (·.code == .noBaseline)
#guard (cases.drop 1).map (fun (_, p, ss) => lastCode p ss) ==
  [some .ok, some .slow, some .noBaseline, some .ok, some .slow, some .ok, some .slow, some .ok, some .slow, some .slow,
   some .slow, some .ok, some .slow, some .ok, some .slow, some .noisy, some .slow, some .slow, some .ok, some .ok,
   some .noBaseline, some .noBaseline, some .slow]
#guard (sampleVerdicts {} (run "ci:w" "build" .ci 0
    [2000, 2000, 2000, 2000, 50000, 50000, 50000, 50000, 50000, 50000, 50000])).map (·.code) ==
  [.noBaseline, .noBaseline, .noBaseline, .noBaseline, .noBaseline, .slow, .slow, .slow, .slow, .ok, .ok]
#guard (sampleVerdicts {} (run "ci:lean" "check" .ci 0
    [100000, 120000, 140000, 110000, 130000, 100000, 140000])).all (·.code != .slow)
#guard (structuralVerdicts {} autoRuns).map (fun v => (v.stage, v.group, v.call, v.baseline, v.siblingMax)) ==
  [("wf", "build", .noise, 10000, 110000), ("wf", "test", .structural, 110000, 20000),
   ("wf", "lint", .noise, 20000, 110000)]
#guard (sampleVerdicts landParams (run "fw land" "lock held" .«local» 9 [112483, 124065, 152813])).all (·.code == .slow)
#guard (sampleVerdicts {} (run "fw land" "lock held" .«local» 9 [112483, 124065, 152813])).all (·.code == .noBaseline)
#guard (sampleVerdicts {} (run "lean" "check.sh" .«local» 4 [60000, 60000, 60000, 60000, 60000] ++
  run "lean" "check.sh" .«local» 24 [300000] ++ run "lean" "check.sh" .«local» 4 [61000])).map (·.code) ==
  [.noBaseline, .noBaseline, .noBaseline, .noBaseline, .noBaseline, .noisy, .ok]

def goldenText (_ : Unit := ()) : String :=
  String.join (cases.map fun (n, p, ss) => (caseJson n p ss).compress ++ "\n")

def goldenPath : System.FilePath := "../packages/contracts/golden/obs/timing.jsonl"

def writeGolden : IO Unit := IO.FS.writeFile goldenPath goldenText

def checkGolden : IO Bool := do return (← IO.FS.readFile goldenPath) == goldenText

end Fw.Wire.Obs.Timing
