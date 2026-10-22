import Fw.Ci.Provider
import Fw.Obs.CiStatus
import Fw.Console.LandLegs
import Fw.Console.LandRemote
/-!
# Land overflow: which land legs run on GitHub Actions and which on CircleCI
-/
namespace Fw.Ci.Overflow
open Fw.Console.LandLegs (Leg legs)
open Fw.Obs (GhComp ghOpenB)
open Fw.Obs.CiStatus (usable)

/-- Concurrent jobs the GitHub Free plan runs at once, all runners together (CONFIRMED:
https://docs.github.com/en/actions/reference/limits, "Job concurrency limits": Free, 20; the page does not name Arm runners,
so counting them against the 20 is INFERRED). Jobs over the cap queue. -/
def ghCap : Nat := 20

/-- The CircleCI resource class every overflow leg uses (MEASURED, `research/notes/2026/10-21-circleci-series.md`: the large class
costs more and is not faster). -/
def ccClass : String := "arm.medium.gen2"

/-- Policy estimate of one leg's wall time on CircleCI, in ms (cold `lake build fwcore` about 260 s plus the leg; a bound, to be
read against the live run in `research/notes/2026/10-21-land-lane-circleci.md`). -/
def estLegMs : Nat := 900000

/-- Credits kept back from the pool, a month's 20 % (policy), so the overflow never spends the pilot's last credits. -/
def creditReserve : Nat := 80000

/-! ## Slots GitHub is using -/

/-- Jobs a run of the workflow of this name can hold at once, at most (CONFIRMED by reading `.github/workflows`, derived and checked by
`apps/runner/test/land-overflow-widths.test.ts`, which fails when a row is not exactly the derived value).

The derivation: the heaviest set of jobs no two of which are ancestor and descendant in `needs`; a job counts its matrix size, at most
its `max-parallel`, and at most 5 on a macOS runner (https://docs.github.com/en/actions/reference/limits). A matrix from `fromJSON` counts
the maximum its inputs allow (over-count is safe, under-count is not). The set behind each row:
- breakpoint-gate 10: `gate` (breakpoint-gate.yml:226; `gate-jobs.mjs` plans at most 10 over the inputs of :171-:174)
- chromium-counts 20: `counts` (chromium-counts.yml:380; 2 targets x 10 runs, :145)
- device-replay 1: `replay` (device-replay.yml, one VM)
- difftest 2: `fixed`, `rotating` (difftest.yml:99,158)
- engine-premises 7: `chromium` 6 (engine-premises.yml:174, :110) and `webkit` 1 (:243)
- gate-gaps 29: `collect-linux` 2 (gate-gaps.yml:122), `collect-macos` 1 (:185), `images-audit` 8 (:264), `images-pages` 18 (:336)
- land 5: `land` (land.yml:95)
- lean-math 1, lean 1: one job after the guard
- linux-webkit-probe 2: `probe` (linux-webkit-probe.yml, max-parallel 2 over the VMs 1 and 2)
- mutants 24: `shard` (mutants.yml:126; shards 1 to 24, :110)
- path-pix 4: `sim` 2 (path-pix.yml, vms 1 and 2, max-parallel 2) and `chromium` 2 (runs 1 and 2), both after `site`; `report` runs after them
- premise-tests 2: `engine` (premise-tests.yml:66); preview-e2e 2: `engine` (preview-e2e.yml:65)
- sim-speed 5: `probe` (sim-speed.yml:121; any number of arms, so the 5 macOS slots bound it)
- smoothness 14: `cadence` 12 (smoothness.yml:146,155; up to 4 widths x 3 sets, the widths a push line allows in `trajectory-line.mjs:44`), `webkit-mac` 1 (max-parallel 1) and `webkit-sim` 1
- snapshot-extract 7: `tests` 1 (snapshot-extract.yml:96) and `extract` 6 (:137)
- toolbar-throttle 3: `sim` (toolbar-throttle.yml, vms 1 to 3, max-parallel 3); `report` runs after it
- trajectory-probe 12: `probe` 8 (trajectory-probe.yml:259; `plan.mjs`), `frames` 2 (:356), `probe-apple` 2 (:496)
- visual-diff 39: `shoot` 32 (visual-diff.yml:274; 2 engines x 16 shards), `port` 1, `port-fonts` 2, `navscroll` 2, `people-layout` 2
- webkit-sim 3: `merge`, `align`, `lag-report` after `sim` (webkit-sim.yml:446,517,592; `sim` is 2, max-parallel :274)
- wktr-fixtures 5: `fixtures` 4 (wktr-fixtures.yml:129; jobs 1 to 4, :110) and `fwcore` 1; wktr 2: `plan` and `fwcore` (wktr.yml)
A row can exceed the 20 slots (visual-diff 39): the free count then saturates at 0, which is the safe side. -/
def widths : List (String × Nat) := [
  ("breakpoint-gate", 10), ("chromium-counts", 20), ("device-replay", 1), ("difftest", 2), ("engine-premises", 7), ("gate-gaps", 29), ("land", 5),
  ("lean-math", 1), ("lean", 1), ("linux-webkit-probe", 2), ("mutants", 24), ("path-pix", 4), ("premise-tests", 2), ("preview-e2e", 2), ("sim-speed", 5),
  ("smoothness", 14), ("snapshot-extract", 7), ("toolbar-throttle", 3), ("trajectory-probe", 12), ("visual-diff", 39), ("webkit-sim", 3), ("wktr-fixtures", 5), ("wktr", 2)]

/-- Width of a workflow no row names: four jobs, so an unlisted workflow over-counts rather than under-counts. -/
def defaultWidth : Nat := 4

/-- Width of one workflow. -/
def width (name : String) : Nat := ((widths.find? (·.1 == name)).map (·.2)).getD defaultWidth

/-- Slots held by the active (queued or running) workflow runs: the sum of their widths. A run that has finished some of its jobs still
counts in full. Each listed run counts at least its real job count while its row is at least the derived width of its workflow (the
test of `widths`). The sum can still be below the real use: the list is the newest 100 runs of this repository only (`gh run list --limit
100`), so a run older than those and a run of another repository of the account are not in it, and it is up to 120 s old (named limits,
`research/notes/2026/10-21-land-lane-circleci.md`). -/
def used (active : List String) : Nat := (active.map width).sum

/-! ## What the decision reads -/

/-- Facts of one decision. Times are ms since the epoch. -/
structure Facts where
  /-- the legs the land needs, in matrix order -/
  legs : List Leg
  /-- names of the GitHub workflow runs now queued or running; none: the list could not be read -/
  ghActive : Option (List String)
  /-- status of the GitHub Actions component (wire name) -/
  ghActions : String
  /-- the last decision of the Actions flag, kept when the status could not be read -/
  ghPrev : Bool
  /-- verdict of the CircleCI arm lane (`healthy`, `degraded`, `unknown`) -/
  ccArm : String
  /-- when that verdict was read -/
  ccReadAt : Option Nat
  now : Nat
  /-- credits the pilot spent this month -/
  spent : Nat
  storage : Nat
  /-- usable checkout keys of the CircleCI project (none: the list answered 403) -/
  keys : Option Nat
  /-- result of the newest CircleCI clone -/
  checkout : Option Bool
  /-- test flag: GitHub counts as full -/
  forceFull : Bool
deriving DecidableEq, Repr

/-- Free job slots on GitHub: none under the test flag; all of them when the count is unknown (unknown means GitHub first); else
the cap less the used slots. -/
def ghFree (f : Facts) : Nat :=
  if f.forceFull then 0 else
  match f.ghActive with
  | none => ghCap
  | some a => ghCap - used a

/-- GitHub Actions is flagged (Lean `Fw.Obs.ghOpenB`: an unreadable status keeps the last decision). -/
def ghDegraded (f : Facts) : Bool := ghOpenB f.ghPrev (GhComp.ofName f.ghActions)

/-- CircleCI status is healthy and fresh. -/
def ccUp (f : Facts) : Bool := usable (Fw.Obs.CiStatus.Verdict.ofName f.ccArm) f.ccReadAt f.now

/-- `n` legs fit the credits left: the class is priced and their estimate, the credits spent and the reserve fit the free pool. -/
def ccFits (f : Facts) (n : Nat) : Bool :=
  match Provider.credits ccClass (n * estLegMs) with
  | none => false
  | some c => decide (c + f.spent + creditReserve ≤ Provider.poolCredits .oss)

def storageCharged (f : Facts) : Nat := f.storage + Provider.ownSaveMilli

def budgetFits (f : Facts) (n : Nat) : Bool :=
  match Provider.credits ccClass (n * estLegMs) with
  | none => false
  | some c => decide (c + f.spent + Provider.storageCredits (storageCharged f) + creditReserve ≤ Provider.poolCredits .oss)

/-- The checkout key check passes. -/
def keyClear (f : Facts) : Bool := Provider.keyProceed ⟨f.keys, f.checkout⟩

/-- CircleCI may take `n` legs. -/
def ccReady (f : Facts) (n : Nat) : Bool := ccUp f && budgetFits f n && keyClear f

/-! ## The split -/

/-- Legs that stay on GitHub: none when Actions is degraded, else as many as there are free slots. -/
def kept (f : Facts) : Nat := if ghDegraded f then 0 else min f.legs.length (ghFree f)

/-- The legs GitHub cannot take, the later ones of the matrix. -/
def overflowSet (f : Facts) : List Leg := f.legs.drop (kept f)

/-- The overflow goes to CircleCI: there is some, and CircleCI is ready for it. -/
def goesCc (f : Facts) : Bool := !(overflowSet f).isEmpty && ccReady f (overflowSet f).length

/-- Legs the GitHub land run takes. -/
def ghLegs (f : Facts) : List Leg := if goesCc f then f.legs.take (kept f) else f.legs

/-- Legs the CircleCI land runs. -/
def ccLegs (f : Facts) : List Leg := if goesCc f then overflowSet f else []

/-- Why the split is what it is, for the log. -/
def reason (f : Facts) : String :=
  if (overflowSet f).isEmpty then "github-first"
  else if goesCc f then (if ghDegraded f then "github-degraded" else "github-full")
  else if !ccUp f then "circleci-not-usable"
  else if !ccFits f (overflowSet f).length then "circleci-credits"
  else if !budgetFits f (overflowSet f).length then "circleci-storage"
  else "circleci-key"

/-- A leg is on GitHub or on CircleCI. -/
inductive Where where
  | github | circleci
deriving DecidableEq, Repr

/-- Where one leg runs. -/
def whereIs (f : Facts) (l : Leg) : Where := if l ∈ ccLegs f then .circleci else .github

/-! ## Theorems -/

theorem ghLegs_append_ccLegs (f : Facts) : ghLegs f ++ ccLegs f = f.legs := by
  unfold ghLegs ccLegs overflowSet
  split <;> simp

/-- `never_both`: the GitHub and CircleCI legs partition the legs (nothing is lost) and, for distinct legs, share none. -/
theorem never_both (f : Facts) (nd : f.legs.Nodup) (l : Leg) : ¬ (l ∈ ghLegs f ∧ l ∈ ccLegs f) := by
  unfold ghLegs ccLegs overflowSet
  split
  · intro ⟨h1, h2⟩
    have := List.take_append_drop (kept f) f.legs
    rw [← this] at nd
    exact (List.nodup_append.1 nd).2.2 l h1 l h2 rfl
  · simp

/-- The legs on CircleCI are legs of the land. -/
theorem ccLegs_sub (f : Facts) (l : Leg) (h : l ∈ ccLegs f) : l ∈ f.legs := by
  unfold ccLegs overflowSet at h
  split at h
  · exact List.mem_of_mem_drop h
  · simp at h

/-- `github_first`: GitHub always keeps the first `kept` legs; with free slots for all legs and Actions not degraded, it keeps all
of them and CircleCI gets none. -/
theorem github_first (f : Facts) : f.legs.take (kept f) <+: ghLegs f := by
  unfold ghLegs
  split
  · exact List.prefix_refl _
  · exact List.take_prefix _ _

theorem github_first_all (f : Facts) (hd : ghDegraded f = false) (hf : f.legs.length ≤ ghFree f) :
    ghLegs f = f.legs ∧ ccLegs f = [] := by
  have hk : kept f = f.legs.length := by
    unfold kept; rw [hd]; simp; omega
  have hn : overflowSet f = [] := by
    unfold overflowSet; rw [hk]; simp
  have hg : goesCc f = false := by
    unfold goesCc; rw [hn]; simp
  unfold ghLegs ccLegs
  rw [hg]; simp

/-- `overflow_only_when_full`: a leg goes to CircleCI only when Actions is degraded or the free slots are fewer than the legs. -/
theorem overflow_only_when_full (f : Facts) (h : ccLegs f ≠ []) : ghDegraded f = true ∨ ghFree f < f.legs.length := by
  by_cases hd : ghDegraded f = true
  · exact Or.inl hd
  · right
    by_cases hf : f.legs.length ≤ ghFree f
    · exact absurd (github_first_all f (by simpa using hd) hf).2 h
    · omega

/-- CircleCI takes legs only when it is ready for them: its status is healthy and fresh, ... -/
theorem overflow_needs_ready (f : Facts) (h : ccLegs f ≠ []) : ccReady f (ccLegs f).length = true := by
  unfold ccLegs at h ⊢
  by_cases g : goesCc f = true
  · simp only [g, ite_true]
    unfold goesCc at g
    simpa using (Bool.and_eq_true_iff.1 g).2
  · simp [g] at h

theorem overflow_needs_up (f : Facts) (h : ccLegs f ≠ []) : ccUp f = true := by
  have := overflow_needs_ready f h
  simp [ccReady] at this; exact this.1.1

theorem budgetFits_ccFits (f : Facts) (n : Nat) (h : budgetFits f n = true) : ccFits f n = true := by
  unfold budgetFits at h
  unfold ccFits
  split at h
  · simp at h
  · rename_i c hc
    simp only [decide_eq_true_eq] at h ⊢
    omega

theorem overflow_needs_budget (f : Facts) (h : ccLegs f ≠ []) : budgetFits f (ccLegs f).length = true := by
  have := overflow_needs_ready f h
  simp [ccReady] at this; exact this.1.2

theorem overflow_needs_credits (f : Facts) (h : ccLegs f ≠ []) : ccFits f (ccLegs f).length = true :=
  budgetFits_ccFits f _ (overflow_needs_budget f h)

/-- ... and the checkout key check passes. -/
theorem overflow_needs_key (f : Facts) (h : ccLegs f ≠ []) : keyClear f = true := by
  have := overflow_needs_ready f h
  simp [ccReady] at this; exact this.2

theorem budget_within_allow (f : Facts) (n : Nat) (h : storageCharged f ≤ Provider.storageAllowMilli) :
    budgetFits f n = ccFits f n := by
  unfold budgetFits ccFits
  rw [Provider.storageCredits_within_allow _ h]
  simp

theorem storage_alone_never_refuses (f : Facts) (n : Nat) (h : budgetFits f n = true) :
    ccReady f n = (ccUp f && keyClear f) := by
  simp [ccReady, h]

theorem reason_not_storage (f : Facts) (h : budgetFits f (overflowSet f).length = true) : reason f ≠ "circleci-storage" := by
  unfold reason
  repeat (first | split | simp_all)

theorem storage_over_budget_keeps_github (f : Facts)
    (h : Provider.poolCredits .oss < Provider.storageCredits (storageCharged f) + f.spent + creditReserve) : ccLegs f = [] := by
  refine Classical.byContradiction fun hne => ?_
  have := overflow_needs_budget f hne
  unfold budgetFits at this
  split at this
  · simp at this
  · simp only [decide_eq_true_eq] at this
    omega

theorem budgetFits_iff (f : Facts) (n c : Nat) (hc : Provider.credits ccClass (n * estLegMs) = some c) :
    budgetFits f n = true ↔
      c + f.spent + creditReserve ≤ Provider.poolCredits .oss ∧
        Provider.storageCredits (storageCharged f) ≤ Provider.poolCredits .oss - (c + f.spent + creditReserve) := by
  unfold budgetFits
  rw [hc]
  simp only [decide_eq_true_eq]
  omega

/-- An unreadable slot count means GitHub first: every leg stays on GitHub while Actions is not degraded, whatever the count of
legs (up to the cap) and the state of CircleCI. -/
theorem unknown_count_github (f : Facts) (hn : f.ghActive = none) (hf : f.forceFull = false) (hd : ghDegraded f = false)
    (hl : f.legs.length ≤ ghCap) : ghLegs f = f.legs ∧ ccLegs f = [] := by
  apply github_first_all f hd
  simp [ghFree, hn, hf]; exact hl

/-- The test flag forces every leg off GitHub (when CircleCI is ready). -/
theorem force_full_free (f : Facts) (h : f.forceFull = true) : ghFree f = 0 := by simp [ghFree, h]

/-! ### The same verdict from either provider -/

/-- The verdict of the land (Lean `Fw.Console.LandRemote.verdict`) reads a provider only to ask whether it has a run and whether an
allowed one passed; a run bound to the wanted commit, lane and digest therefore decides identically from GitHub and from CircleCI. -/
theorem verdict_same (localOk needed : Bool) (w : Fw.Console.LandRemote.Want) (k : Nat) (p q : Fw.Console.LandRemote.Provider)
    (s : Fw.Console.LandRemote.RunState) :
    Fw.Console.LandRemote.verdict localOk needed [p] w k [⟨p, w.sha, w.laneId, w.laneDigest, s⟩] =
    Fw.Console.LandRemote.verdict localOk needed [q] w k [⟨q, w.sha, w.laneId, w.laneDigest, s⟩] := by
  cases s <;> simp [Fw.Console.LandRemote.verdict, Fw.Console.LandRemote.Want.binds, Fw.Console.LandRemote.hasFail,
    Fw.Console.LandRemote.hasPass, Fw.Console.LandRemote.hasPending, Fw.Console.LandRemote.fallback,
    Fw.Console.LandRemote.started, Fw.Console.LandRemote.whyLocal]

/-- Whether a run binds to the wanted lane does not depend on its provider. -/
theorem binds_provider_blind (w : Fw.Console.LandRemote.Want) (r : Fw.Console.LandRemote.Run) (p : Fw.Console.LandRemote.Provider) :
    w.binds { r with provider := p } = w.binds r := rfl

/-! ### Combining the verdicts of the two providers' legs -/

/-- The kind that decides when the legs of each provider have a verdict of their own (kinds as in
`Fw.Console.LandRemote.Verdict.kind`): `refuse` if any, else `local` if any, else the first kind that is not `accept` (`wait`,
`try`), else `accept`; none for no verdict. -/
def pickKind (ks : List String) : Option String :=
  if "refuse" ∈ ks then some "refuse"
  else if "local" ∈ ks then some "local"
  else match ks.find? (· != "accept") with
    | some k => some k
    | none => if ks.isEmpty then none else some "accept"

/-- A refusal in either provider's legs refuses the land. -/
theorem pickKind_refuse (ks : List String) (h : "refuse" ∈ ks) : pickKind ks = some "refuse" := by
  simp [pickKind, h]

/-- With no refusal, a leg that must run locally decides. -/
theorem pickKind_local (ks : List String) (h : "local" ∈ ks) (nr : "refuse" ∉ ks) : pickKind ks = some "local" := by
  simp [pickKind, h, nr]

/-- `combine_accept`: the combined verdict accepts exactly when there is a verdict and every one accepts. -/
theorem pickKind_accept_iff (ks : List String) : pickKind ks = some "accept" ↔ ks ≠ [] ∧ ∀ k ∈ ks, k = "accept" := by
  unfold pickKind
  split
  · rename_i h; constructor
    · intro e; simp at e
    · rintro ⟨_, a⟩; have := a "refuse" h; simp at this
  · split
    · rename_i h1 h2; constructor
      · intro e; simp at e
      · rintro ⟨_, a⟩; have := a "local" h2; simp at this
    · rename_i h1 h2
      split
      · rename_i k hk
        have := List.find?_some hk
        have hm := List.mem_of_find?_eq_some hk
        constructor
        · intro e; simp at e; subst e; simp at this
        · rintro ⟨_, a⟩; have := a k hm; simp [this] at *
      · rename_i hn
        rw [List.find?_eq_none] at hn
        split
        · rename_i he; simp at he; subst he; simp
        · rename_i he
          simp at he
          constructor
          · intro _; exact ⟨he, fun k hk => by simpa using hn k hk⟩
          · intro _; rfl

/-! ### A CircleCI start that failed -/

/-- Where the legs run once the CircleCI group has tried to start. -/
structure Settled where
  /-- legs of the GitHub run the plan gave GitHub -/
  gh : List Leg
  /-- legs on CircleCI -/
  cc : List Leg
  /-- legs re-dispatched on a second GitHub run -/
  again : List Leg
deriving DecidableEq, Repr

/-- The plan gave `gh` to GitHub and `cc` to CircleCI. If CircleCI could not start (the key check, the trigger or the push failed, so no
pipeline exists), its legs run on a second GitHub run: CircleCI keeps none and the local tier is not used. A pipeline that started is
left as planned. -/
def settle (gh cc : List Leg) (ccStarted : Bool) : Settled :=
  if ccStarted || cc.isEmpty then ⟨gh, cc, []⟩ else ⟨gh, [], cc⟩

/-- A CircleCI group that started, or had no leg, changes nothing. -/
theorem settle_started (gh cc : List Leg) (ccStarted : Bool) (h : ccStarted = true ∨ cc = []) : settle gh cc ccStarted = ⟨gh, cc, []⟩ := by
  unfold settle
  rcases h with h | h <;> simp [h]

/-- A failed start with legs on CircleCI: CircleCI keeps none and GitHub's second run takes all of them. -/
theorem settle_failed (gh cc : List Leg) (hc : cc ≠ []) : settle gh cc false = ⟨gh, [], cc⟩ := by
  unfold settle
  simp [List.isEmpty_iff, hc]

/-- Whatever the start did, the legs are the same legs: the three lists together are a permutation of `gh ++ cc`. -/
theorem settle_perm (gh cc : List Leg) (st : Bool) :
    ((settle gh cc st).gh ++ (settle gh cc st).again ++ (settle gh cc st).cc).Perm (gh ++ cc) := by
  unfold settle
  split
  · simp
  · simp

/-- `failed_start_covered_once`: after a failed CircleCI start every leg of the plan runs on GitHub, on exactly one of its two runs, and on
CircleCI on none (for distinct legs). -/
theorem failed_start_covered_once (gh cc : List Leg) (nd : (gh ++ cc).Nodup) (hc : cc ≠ []) :
    (∀ l ∈ gh ++ cc, ((settle gh cc false).gh ++ (settle gh cc false).again).count l = 1 ∧ l ∉ (settle gh cc false).cc) := by
  intro l hl
  rw [settle_failed gh cc hc]
  simp only [List.not_mem_nil, not_false_eq_true, and_true]
  exact nd.count_of_mem hl

/-- A leg is never run twice, whatever the start did: the three lists are duplicate free for distinct legs. -/
theorem settle_nodup (gh cc : List Leg) (st : Bool) (nd : (gh ++ cc).Nodup) :
    ((settle gh cc st).gh ++ (settle gh cc st).again ++ (settle gh cc st).cc).Nodup :=
  (settle_perm gh cc st).nodup_iff.2 nd

/-- The CircleCI land jobs of `Provider.landJobs` (the jobs that save the Lake cache) are the legs of the lane, in matrix order, each as `land-<leg>`. -/
theorem landJobs_eq_legs : Provider.landJobs = legs.map fun l => "land-" ++ l.name := by decide

def reserveOf (p : Provider.Pool) : Nat := Provider.poolCredits p / 5

theorem creditReserve_eq : creditReserve = reserveOf .oss := by decide

def classLeft (cls : String) (spent : Nat) : Nat :=
  match Provider.rateOf cls with
  | none => 0
  | some r => Provider.poolCredits r.pool - reserveOf r.pool - spent

theorem classLeft_spec {cls : String} {spent c : Nat} (h : c ≤ classLeft cls spent) (hc : 0 < c) :
    ∃ r, Provider.rateOf cls = some r ∧ c + spent + reserveOf r.pool ≤ Provider.poolCredits r.pool := by
  unfold classLeft at h
  cases hr : Provider.rateOf cls with
  | none => simp [hr] at h; omega
  | some r => simp only [hr] at h; exact ⟨r, rfl, by omega⟩

def facts20261021 : Facts :=
  { legs := legs, ghActive := some ["webkit-sim", "webkit-sim", "visual-diff", "path-pix"], ghActions := "degraded_performance",
    ghPrev := false, ccArm := "healthy", ccReadAt := some 1792592446000, now := 1792592506000, spent := 819,
    storage := Provider.storageNow [Provider.ledger20261021] 1792592506000, keys := some 1, checkout := none, forceFull := false }

theorem overflow_20261021 : ccLegs facts20261021 = legs ∧ reason facts20261021 = "github-degraded" := by decide

theorem overflow_20261021_hold30 : ccLegs { facts20261021 with storage := 1297 } = legs := by decide

#guard reserveOf .oss == 80000 && reserveOf .base == 6000
#guard classLeft "m4pro.medium" 3575 == 20425 && classLeft "m4pro.medium" 30000 == 0 && classLeft "none" 0 == 0

#guard storageCharged { facts20261021 with storage := 0 } == Provider.ownSaveMilli
#guard budgetFits { facts20261021 with storage := 1765 } 5 && ccFits { facts20261021 with storage := 1765 } 5
#guard !budgetFits { facts20261021 with spent := 319550, storage := 3765 } 5 && ccFits { facts20261021 with spent := 319550, storage := 3765 } 5
#guard reason { facts20261021 with spent := 319550, storage := 3765 } == "circleci-storage"
#guard reason { facts20261021 with spent := 320000 } == "circleci-credits"
#guard reason { facts20261021 with ccArm := "degraded" } == "circleci-not-usable"
#guard reason { facts20261021 with keys := some 0 } == "circleci-key"
#guard reason { facts20261021 with storage := 100000 } == "github-degraded"
#guard reason { facts20261021 with storage := 1000000 } == "circleci-storage"

end Fw.Ci.Overflow
