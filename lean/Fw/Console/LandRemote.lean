import Lean.Data.Json
import Fw.Console.LandTier
/-!
# Land remote verdict: the combined land verdict over the local tier and normalized lane runs of any CI provider

Golden: `packages/contracts/golden/console/land-remote.jsonl`; ops `console.landRemote`, `console.landDigest` (`Fw.Wire.Console`).
-/
namespace Fw.Console.LandRemote
open Lean

/-- A CI provider. -/
inductive Provider where
  | github | circleci
deriving DecidableEq, Repr

/-- The word printed for a provider. -/
def Provider.name : Provider → String
  | .github => "github" | .circleci => "circleci"

/-- The provider a word names. -/
def Provider.ofName : String → Option Provider
  | "github" => some .github | "circleci" => some .circleci | _ => none

/-- Where a lane run is. -/
inductive RunState where
  | queued | running | pass | fail | cancelled | timeout | unavailable
deriving DecidableEq, Repr

/-- The word printed for a run state. -/
def RunState.name : RunState → String
  | .queued => "queued" | .running => "running" | .pass => "pass" | .fail => "fail"
  | .cancelled => "cancelled" | .timeout => "timeout" | .unavailable => "unavailable"

/-- The state a word names. -/
def RunState.ofName : String → Option RunState
  | "queued" => some .queued | "running" => some .running | "pass" => some .pass | "fail" => some .fail
  | "cancelled" => some .cancelled | "timeout" => some .timeout | "unavailable" => some .unavailable | _ => none

/-- One lane run of one provider, bound to the commit and the suite list it ran. -/
structure Run where
  provider : Provider
  sha : String
  laneId : String
  laneDigest : String
  state : RunState
deriving DecidableEq, Repr

/-- What the land needs: the merge commit and the digest of the suites the remote tier must run. -/
structure Want where
  sha : String
  laneId : String
  laneDigest : String
deriving DecidableEq, Repr

/-- The digest of a lane: the tier word and the suite ids in order, as text (the identity, not a hash). -/
def laneDigest (t : LandTier.Tier) (ids : List String) : String := t.name ++ ":" ++ ",".intercalate ids

/-- A run counts only when its sha, lane and digest are the wanted ones. -/
def Want.binds (w : Want) (r : Run) : Bool := r.sha == w.sha && r.laneId == w.laneId && r.laneDigest == w.laneDigest

/-- Some bound run failed. -/
def hasFail (rel : List Run) : Bool := rel.any fun r => r.state == .fail

/-- Some bound run of an allowed provider passed. -/
def hasPass (allow : List Provider) (rel : List Run) : Bool := rel.any fun r => r.state == .pass && allow.contains r.provider

/-- Some bound run is still going. -/
def hasPending (rel : List Run) : Bool := rel.any fun r => r.state == .queued || r.state == .running

/-- The provider has a bound run. -/
def started (rel : List Run) (p : Provider) : Bool := rel.any fun r => r.provider == p

/-- Why the remote tier must run locally. -/
inductive LocalWhy where
  | unavailable | timeout | cancelled | noProvider
deriving DecidableEq, Repr

/-- The most telling dead state among the bound runs. -/
def whyLocal (rel : List Run) : LocalWhy :=
  if rel.any (·.state == .unavailable) then .unavailable
  else if rel.any (·.state == .timeout) then .timeout
  else if rel.any (·.state == .cancelled) then .cancelled
  else .noProvider

/-- Why the land is refused. -/
inductive Refusal where
  | localTier | remoteFail
deriving DecidableEq, Repr

/-- Why the land keeps waiting. -/
inductive Hold where
  | pending | degraded
deriving DecidableEq, Repr

/-- The combined land verdict. -/
inductive Verdict where
  | accept
  | refuse (r : Refusal)
  | wait (h : Hold)
  | tryProvider (p : Provider)
  | runLocal (w : LocalWhy)
deriving DecidableEq, Repr

/-- What to do when no bound run decided or is going: try the first allowed provider without a run, else wait while polls are left, else run locally. -/
def fallback (allow : List Provider) (waitsLeft : Nat) (rel : List Run) : Verdict :=
  match allow.find? (fun p => !started rel p) with
  | some p => .tryProvider p
  | none => if 0 < waitsLeft then .wait .degraded else .runLocal (whyLocal rel)

/-- The land verdict: the local tier, then the remote runs bound to `w` (`allow`: the providers whose pass counts, in preference order). -/
def verdict (localOk needed : Bool) (allow : List Provider) (w : Want) (waitsLeft : Nat) (runs : List Run) : Verdict :=
  if !localOk then .refuse .localTier else
  if !needed then .accept else
  let rel := runs.filter w.binds
  if hasFail rel then .refuse .remoteFail else
  if hasPass allow rel then .accept else
  if hasPending rel then .wait .pending else
  fallback allow waitsLeft rel

/-- The state `fw ci wait` reports by its exit code: 0 pass, 1 fail, 3 the slice ran out with the run still going (`timedOut`: its
output said `timed out after`; any other exit 3 is a stopped poller or a refused gh call), 4 not run, else gh unavailable. -/
def waitState (code : Nat) (timedOut : Bool) : RunState :=
  match code with
  | 0 => .pass | 1 => .fail | 3 => if timedOut then .running else .unavailable | 4 => .cancelled | _ => .unavailable

/-- A run that completed with conclusion `failure` (a view without a `status` field counts as completed). -/
def completedFailure (status conclusion : String) : Bool := conclusion == "failure" && (status == "completed" || status == "")

/-- The state of a lane run: the run's own conclusion decides when the run completed with a failure, whatever the waiter returned;
otherwise the waiter's outcome stands. Identity (the run's record) over inference (an exit code). -/
def laneState (code : Nat) (timedOut : Bool) (status conclusion : String) : RunState :=
  if completedFailure status conclusion then .fail else waitState code timedOut

/-- The reason word on the `VERDICT` line. -/
def Verdict.reason : Verdict → String
  | .accept => "remote-pass"
  | .refuse .localTier => "local-tier-failed"
  | .refuse .remoteFail => "remote-lane-failed"
  | .wait .pending => "lane-running"
  | .wait .degraded => "provider-degraded-waiting"
  | .tryProvider p => "provider-unavailable-trying-" ++ p.name
  | .runLocal .unavailable => "remote-unavailable-run-locally"
  | .runLocal .timeout => "remote-timeout-run-locally"
  | .runLocal .cancelled => "remote-cancelled-run-locally"
  | .runLocal .noProvider => "no-provider-run-locally"

/-- The kind word: what the caller does next. -/
def Verdict.kind : Verdict → String
  | .accept => "accept" | .refuse _ => "refuse" | .wait _ => "wait" | .tryProvider _ => "try" | .runLocal _ => "local"

/-- The provider a `try` verdict names. -/
def Verdict.provider : Verdict → Option Provider
  | .tryProvider p => some p | _ => none

/-- The land may proceed only on `accept`. -/
def Verdict.ok : Verdict → Bool
  | .accept => true | _ => false

theorem hasFail_false (rel : List Run) (h : ∀ r ∈ rel, r.state ≠ .fail) : hasFail rel = false := by
  simp only [hasFail, Bool.eq_false_iff, ne_eq, List.any_eq_true, not_exists, not_and]
  intro x hx hs
  exact h x hx (by simpa using hs)

theorem hasPass_false (a : List Provider) (rel : List Run) (h : ∀ r ∈ rel, r.state = .pass → r.provider ∉ a) :
    hasPass a rel = false := by
  simp only [hasPass, Bool.eq_false_iff, ne_eq, List.any_eq_true, not_exists, not_and]
  intro x hx hs
  simp only [Bool.and_eq_true, beq_iff_eq, List.contains_iff_mem] at hs
  exact h x hx hs.1 hs.2

theorem hasPending_false (rel : List Run) (h : ∀ r ∈ rel, r.state ≠ .queued ∧ r.state ≠ .running) :
    hasPending rel = false := by
  simp only [hasPending, Bool.eq_false_iff, ne_eq, List.any_eq_true, not_exists, not_and]
  intro x hx hs
  simp only [Bool.or_eq_true, beq_iff_eq] at hs
  rcases hs with e | e
  · exact (h x hx).1 e
  · exact (h x hx).2 e

theorem mem_filter_binds (w : Want) (rs : List Run) (r : Run) : r ∈ rs.filter w.binds ↔ r ∈ rs ∧ w.binds r = true := by
  simp [List.mem_filter]

/-- A failed local tier refuses, whatever the remote runs say. -/
theorem verdict_local_fail (n : Bool) (a : List Provider) (w : Want) (k : Nat) (rs : List Run) :
    verdict false n a w k rs = .refuse .localTier := by
  simp [verdict]

/-- A tier with no remote check needs no run. -/
theorem verdict_not_needed (a : List Provider) (w : Want) (k : Nat) (rs : List Run) :
    verdict true false a w k rs = .accept := by
  simp [verdict]

/-- A bound fail refuses, even next to a pass of another provider. -/
theorem verdict_fail (a : List Provider) (w : Want) (k : Nat) (rs : List Run)
    (h : ∃ r ∈ rs, w.binds r = true ∧ r.state = .fail) : verdict true true a w k rs = .refuse .remoteFail := by
  obtain ⟨r, hr, hb, hs⟩ := h
  have : hasFail (rs.filter w.binds) = true := by
    simp only [hasFail, List.any_eq_true, mem_filter_binds]
    exact ⟨r, ⟨hr, hb⟩, by simp [hs]⟩
  simp [verdict, this]

/-- No bound fail, a bound pass of an allowed provider: accept. -/
theorem verdict_pass (a : List Provider) (w : Want) (k : Nat) (rs : List Run)
    (hf : ∀ r ∈ rs, w.binds r = true → r.state ≠ .fail)
    (h : ∃ r ∈ rs, w.binds r = true ∧ r.state = .pass ∧ r.provider ∈ a) : verdict true true a w k rs = .accept := by
  obtain ⟨r, hr, hb, hs, hp⟩ := h
  have nf := hasFail_false (rs.filter w.binds) fun x hx => hf x ((mem_filter_binds w rs x).mp hx).1 ((mem_filter_binds w rs x).mp hx).2
  have ps : hasPass a (rs.filter w.binds) = true := by
    simp only [hasPass, List.any_eq_true, mem_filter_binds]
    exact ⟨r, ⟨hr, hb⟩, by simp [hs, hp]⟩
  simp [verdict, nf, ps]

/-- Bound runs: none failed, none passed for an allowed provider, one going: wait. -/
theorem verdict_pending (a : List Provider) (w : Want) (k : Nat) (rs : List Run)
    (hf : ∀ r ∈ rs, w.binds r = true → r.state ≠ .fail)
    (hp : ∀ r ∈ rs, w.binds r = true → r.state = .pass → r.provider ∉ a)
    (h : ∃ r ∈ rs, w.binds r = true ∧ (r.state = .queued ∨ r.state = .running)) :
    verdict true true a w k rs = .wait .pending := by
  obtain ⟨r, hr, hb, hs⟩ := h
  have nf := hasFail_false (rs.filter w.binds) fun x hx => hf x ((mem_filter_binds w rs x).mp hx).1 ((mem_filter_binds w rs x).mp hx).2
  have np := hasPass_false a (rs.filter w.binds) fun x hx => hp x ((mem_filter_binds w rs x).mp hx).1 ((mem_filter_binds w rs x).mp hx).2
  have pd : hasPending (rs.filter w.binds) = true := by
    simp only [hasPending, List.any_eq_true, mem_filter_binds]
    exact ⟨r, ⟨hr, hb⟩, by rcases hs with hs | hs <;> simp [hs]⟩
  simp [verdict, nf, np, pd]

/-- Nothing bound failed, passed for an allowed provider or is going: the first allowed provider without a bound run is tried. -/
theorem verdict_try (a : List Provider) (w : Want) (k : Nat) (rs : List Run) (p : Provider)
    (hf : ∀ r ∈ rs, w.binds r = true → r.state ≠ .fail)
    (hp : ∀ r ∈ rs, w.binds r = true → r.state = .pass → r.provider ∉ a)
    (hq : ∀ r ∈ rs, w.binds r = true → r.state ≠ .queued ∧ r.state ≠ .running)
    (hfirst : a.find? (fun q => !started (rs.filter w.binds) q) = some p) :
    verdict true true a w k rs = .tryProvider p := by
  have nf := hasFail_false (rs.filter w.binds) fun x hx => hf x ((mem_filter_binds w rs x).mp hx).1 ((mem_filter_binds w rs x).mp hx).2
  have np := hasPass_false a (rs.filter w.binds) fun x hx => hp x ((mem_filter_binds w rs x).mp hx).1 ((mem_filter_binds w rs x).mp hx).2
  have nq := hasPending_false (rs.filter w.binds) fun x hx => hq x ((mem_filter_binds w rs x).mp hx).1 ((mem_filter_binds w rs x).mp hx).2
  simp [verdict, fallback, nf, np, nq, hfirst]

/-- Every allowed provider has a bound run, nothing is decided or going, polls are left: wait. -/
theorem verdict_wait_degraded (a : List Provider) (w : Want) (k : Nat) (rs : List Run)
    (hf : ∀ r ∈ rs, w.binds r = true → r.state ≠ .fail)
    (hp : ∀ r ∈ rs, w.binds r = true → r.state = .pass → r.provider ∉ a)
    (hq : ∀ r ∈ rs, w.binds r = true → r.state ≠ .queued ∧ r.state ≠ .running)
    (hall : a.find? (fun q => !started (rs.filter w.binds) q) = none) (hk : 0 < k) :
    verdict true true a w k rs = .wait .degraded := by
  have nf := hasFail_false (rs.filter w.binds) fun x hx => hf x ((mem_filter_binds w rs x).mp hx).1 ((mem_filter_binds w rs x).mp hx).2
  have np := hasPass_false a (rs.filter w.binds) fun x hx => hp x ((mem_filter_binds w rs x).mp hx).1 ((mem_filter_binds w rs x).mp hx).2
  have nq := hasPending_false (rs.filter w.binds) fun x hx => hq x ((mem_filter_binds w rs x).mp hx).1 ((mem_filter_binds w rs x).mp hx).2
  simp [verdict, fallback, nf, np, nq, hall, hk]

/-- Every allowed provider has a bound run, nothing is decided or going, no polls left: the remote tier runs locally, named. -/
theorem verdict_run_local (a : List Provider) (w : Want) (rs : List Run)
    (hf : ∀ r ∈ rs, w.binds r = true → r.state ≠ .fail)
    (hp : ∀ r ∈ rs, w.binds r = true → r.state = .pass → r.provider ∉ a)
    (hq : ∀ r ∈ rs, w.binds r = true → r.state ≠ .queued ∧ r.state ≠ .running)
    (hall : a.find? (fun q => !started (rs.filter w.binds) q) = none) :
    verdict true true a w 0 rs = .runLocal (whyLocal (rs.filter w.binds)) := by
  have nf := hasFail_false (rs.filter w.binds) fun x hx => hf x ((mem_filter_binds w rs x).mp hx).1 ((mem_filter_binds w rs x).mp hx).2
  have np := hasPass_false a (rs.filter w.binds) fun x hx => hp x ((mem_filter_binds w rs x).mp hx).1 ((mem_filter_binds w rs x).mp hx).2
  have nq := hasPending_false (rs.filter w.binds) fun x hx => hq x ((mem_filter_binds w rs x).mp hx).1 ((mem_filter_binds w rs x).mp hx).2
  simp [verdict, fallback, nf, np, nq, hall]

/-- Accept exactly when the local tier passed and the remote tier is not needed, or no bound run failed and a bound run of an allowed provider passed. -/
theorem verdict_accept_iff (n : Bool) (a : List Provider) (w : Want) (k : Nat) (rs : List Run) (l : Bool) :
    verdict l n a w k rs = .accept ↔
      l = true ∧ (n = false ∨ ((∀ r ∈ rs, w.binds r = true → r.state ≠ .fail) ∧
        ∃ r ∈ rs, w.binds r = true ∧ r.state = .pass ∧ r.provider ∈ a)) := by
  cases l
  · simp [verdict]
  cases n
  · simp [verdict]
  by_cases hf : ∃ r ∈ rs, w.binds r = true ∧ r.state = .fail
  · rw [verdict_fail a w k rs hf]
    constructor
    · intro h; cases h
    · rintro ⟨_, h | ⟨hall, _⟩⟩
      · cases h
      · obtain ⟨x, hx, hb, hs⟩ := hf
        exact absurd hs (hall x hx hb)
  · have nf : ∀ r ∈ rs, w.binds r = true → r.state ≠ .fail := fun r hr hb hs => hf ⟨r, hr, hb, hs⟩
    by_cases hp : ∃ r ∈ rs, w.binds r = true ∧ r.state = .pass ∧ r.provider ∈ a
    · rw [verdict_pass a w k rs nf hp]
      exact ⟨fun _ => ⟨rfl, Or.inr ⟨nf, hp⟩⟩, fun _ => rfl⟩
    · have np : hasPass a (rs.filter w.binds) = false := by
        apply hasPass_false
        intro x hx hs hm
        exact hp ⟨x, ((mem_filter_binds w rs x).mp hx).1, ((mem_filter_binds w rs x).mp hx).2, hs, hm⟩
      have nf' := hasFail_false (rs.filter w.binds) fun x hx => nf x ((mem_filter_binds w rs x).mp hx).1 ((mem_filter_binds w rs x).mp hx).2
      have hne : verdict true true a w k rs ≠ .accept := by
        unfold verdict
        simp only [nf', np, Bool.false_eq_true, ite_false, Bool.not_true]
        split
        · simp
        · unfold fallback
          split <;> (try split) <;> simp
      constructor
      · intro h; exact absurd h hne
      · rintro ⟨_, h | ⟨_, h⟩⟩
        · cases h
        · exact absurd h hp

/-- An accepted land that needed a remote tier has a pass of an allowed provider for the merge sha and the expected digest. -/
theorem verdict_accept_binds (a : List Provider) (w : Want) (k : Nat) (rs : List Run) (l : Bool) (n : Bool)
    (h : verdict l n a w k rs = .accept) (hn : n = true) :
    ∃ r ∈ rs, r.state = .pass ∧ r.sha = w.sha ∧ r.laneId = w.laneId ∧ r.laneDigest = w.laneDigest ∧ r.provider ∈ a := by
  rw [verdict_accept_iff] at h
  obtain ⟨_, h | ⟨_, r, hr, hb, hs, hm⟩⟩ := h
  · simp [hn] at h
  · simp only [Want.binds, Bool.and_eq_true, beq_iff_eq] at hb
    exact ⟨r, hr, hs, hb.1.1, hb.1.2, hb.2, hm⟩

/-- Without a bound pass there is no accept when a remote run is needed (a pass for another sha or digest is no pass). -/
theorem verdict_no_pass_no_accept (a : List Provider) (w : Want) (k : Nat) (rs : List Run) (l : Bool)
    (h : ∀ r ∈ rs, w.binds r = true → r.state ≠ .pass) : verdict l true a w k rs ≠ .accept := by
  intro e
  obtain ⟨r, hr, hs, hsha, hid, hd, _⟩ := verdict_accept_binds a w k rs l true e rfl
  exact h r hr (by simp [Want.binds, hsha, hid, hd]) hs

/-- A pass on one provider never hides a fail on the other. -/
theorem verdict_cross_provider_fail (a : List Provider) (w : Want) (k : Nat) (rs : List Run) (q : Run)
    (hq : q ∈ rs) (hbq : w.binds q = true) (hqs : q.state = .fail) :
    verdict true true a w k rs = .refuse .remoteFail :=
  verdict_fail a w k rs ⟨q, hq, hbq, hqs⟩

/-- Runs that do not bind to the want change nothing. -/
theorem verdict_other_runs_ignored (n l : Bool) (a : List Provider) (w : Want) (k : Nat) (rs ex : List Run)
    (h : ∀ r ∈ ex, w.binds r = false) : verdict l n a w k (rs ++ ex) = verdict l n a w k rs := by
  have e : ex.filter w.binds = [] := List.filter_eq_nil_iff.mpr (fun r hr => by simp [h r hr])
  have : (rs ++ ex).filter w.binds = rs.filter w.binds := by simp [List.filter_append, e]
  simp [verdict, this]

/-- Runs of another sha are ignored. -/
theorem verdict_other_sha_ignored (n l : Bool) (a : List Provider) (w : Want) (k : Nat) (rs ex : List Run)
    (h : ∀ r ∈ ex, r.sha ≠ w.sha) : verdict l n a w k (rs ++ ex) = verdict l n a w k rs :=
  verdict_other_runs_ignored n l a w k rs ex fun r hr => by simp [Want.binds, h r hr]

/-- Runs of another digest are ignored. -/
theorem verdict_other_digest_ignored (n l : Bool) (a : List Provider) (w : Want) (k : Nat) (rs ex : List Run)
    (h : ∀ r ∈ ex, r.laneDigest ≠ w.laneDigest) : verdict l n a w k (rs ++ ex) = verdict l n a w k rs :=
  verdict_other_runs_ignored n l a w k rs ex fun r hr => by simp [Want.binds, h r hr]

/-- The fallback does not depend on the order of the runs. -/
theorem fallback_perm (a : List Provider) (k : Nat) (rel rel' : List Run) (h : rel.Perm rel') : fallback a k rel = fallback a k rel' := by
  have e4 : (fun p => !started rel p) = (fun p => !started rel' p) := funext fun q => by simp only [started, List.Perm.any_eq h]
  have e5 : whyLocal rel = whyLocal rel' := by simp only [whyLocal, List.Perm.any_eq h]
  simp only [fallback, e4, e5]

/-- The verdict does not depend on the order of the runs. -/
theorem verdict_perm (n l : Bool) (a : List Provider) (w : Want) (k : Nat) (rs rs' : List Run) (h : rs.Perm rs') :
    verdict l n a w k rs = verdict l n a w k rs' := by
  have hp := h.filter w.binds
  have e1 : hasFail (rs.filter w.binds) = hasFail (rs'.filter w.binds) := List.Perm.any_eq hp
  have e2 : hasPass a (rs.filter w.binds) = hasPass a (rs'.filter w.binds) := List.Perm.any_eq hp
  have e3 : hasPending (rs.filter w.binds) = hasPending (rs'.filter w.binds) := List.Perm.any_eq hp
  simp only [verdict, e1, e2, e3, fallback_perm a k _ _ hp]

/-- With no bound fail, pass or run going, the verdict is the fallback. -/
theorem verdict_eq_fallback (a : List Provider) (w : Want) (k : Nat) (rs : List Run)
    (h1 : hasFail (rs.filter w.binds) = false) (h2 : hasPass a (rs.filter w.binds) = false)
    (h3 : hasPending (rs.filter w.binds) = false) : verdict true true a w k rs = fallback a k (rs.filter w.binds) := by
  simp [verdict, h1, h2, h3]

/-- A verdict of `try` or `local` comes from the fallback. -/
theorem verdict_fallback_of (a : List Provider) (w : Want) (k : Nat) (rs : List Run) (v : Verdict)
    (h : verdict true true a w k rs = v) (hv : (∃ p, v = .tryProvider p) ∨ (∃ y, v = .runLocal y)) :
    fallback a k (rs.filter w.binds) = v := by
  have key : hasFail (rs.filter w.binds) = false ∧ hasPass a (rs.filter w.binds) = false ∧ hasPending (rs.filter w.binds) = false := by
    by_cases h1 : hasFail (rs.filter w.binds) = true
    · simp [verdict, h1] at h; subst h; rcases hv with ⟨p, hp⟩ | ⟨y, hy⟩
      · simp at hp
      · simp at hy
    by_cases h2 : hasPass a (rs.filter w.binds) = true
    · simp [verdict, h1, h2] at h; subst h; rcases hv with ⟨p, hp⟩ | ⟨y, hy⟩
      · simp at hp
      · simp at hy
    by_cases h3 : hasPending (rs.filter w.binds) = true
    · simp [verdict, h1, h2, h3] at h; subst h; rcases hv with ⟨p, hp⟩ | ⟨y, hy⟩
      · simp at hp
      · simp at hy
    simp_all
  rw [verdict_eq_fallback a w k rs key.1 key.2.1 key.2.2] at h
  exact h

/-- A provider is tried only when it is allowed and has no bound run. -/
theorem verdict_try_fresh (n l : Bool) (a : List Provider) (w : Want) (k : Nat) (rs : List Run) (p : Provider)
    (h : verdict l n a w k rs = .tryProvider p) : p ∈ a ∧ ∀ r ∈ rs, w.binds r = true → r.provider ≠ p := by
  cases l
  · simp [verdict] at h
  cases n
  · simp [verdict] at h
  have hf := verdict_fallback_of a w k rs _ h (Or.inl ⟨p, rfl⟩)
  unfold fallback at hf
  split at hf
  · rename_i q hq
    simp only [Verdict.tryProvider.injEq] at hf
    subst hf
    constructor
    · exact List.mem_of_find?_eq_some hq
    · have := List.find?_some hq
      intro r hr hb hp
      simp only [started, Bool.not_eq_true', List.any_eq_false] at this
      exact absurd (by simpa using hp) (this r ((mem_filter_binds w rs r).mpr ⟨hr, hb⟩))
  · split at hf <;> simp at hf

/-- A local run happens only when no polls are left and every allowed provider has a bound run. -/
theorem verdict_local_exhausted (n l : Bool) (a : List Provider) (w : Want) (k : Nat) (rs : List Run) (y : LocalWhy)
    (h : verdict l n a w k rs = .runLocal y) : k = 0 ∧ ∀ p ∈ a, ∃ r ∈ rs, w.binds r = true ∧ r.provider = p := by
  cases l
  · simp [verdict] at h
  cases n
  · simp [verdict] at h
  have hf := verdict_fallback_of a w k rs _ h (Or.inr ⟨y, rfl⟩)
  unfold fallback at hf
  split at hf
  · simp at hf
  · rename_i hnone
    split at hf
    · simp at hf
    · refine ⟨by omega, fun p hp => ?_⟩
      have := List.find?_eq_none.mp hnone p hp
      have hs : started (rs.filter w.binds) p = true := by simpa using this
      obtain ⟨r, hr, hrp⟩ := List.any_eq_true.mp hs
      obtain ⟨hr', hb⟩ := (mem_filter_binds w rs r).mp hr
      exact ⟨r, hr', hb, beq_iff_eq.mp hrp⟩

/-- A fallback is never silent: with no bound pass, fail or run going, the verdict waits, tries a provider or runs locally with a reason. -/
theorem verdict_degraded_named (a : List Provider) (w : Want) (k : Nat) (rs : List Run)
    (hf : ∀ r ∈ rs, w.binds r = true → r.state ≠ .fail)
    (hp : ∀ r ∈ rs, w.binds r = true → r.state = .pass → r.provider ∉ a)
    (hq : ∀ r ∈ rs, w.binds r = true → r.state ≠ .queued ∧ r.state ≠ .running) :
    (verdict true true a w k rs = .wait .degraded) ∨ (∃ p, verdict true true a w k rs = .tryProvider p) ∨
      (∃ y, verdict true true a w k rs = .runLocal y) := by
  by_cases hs : ∃ p, a.find? (fun q => !started (rs.filter w.binds) q) = some p
  · obtain ⟨p, hp'⟩ := hs
    exact Or.inr (Or.inl ⟨p, verdict_try a w k rs p hf hp hq hp'⟩)
  · have hall : a.find? (fun q => !started (rs.filter w.binds) q) = none := by
      cases h : a.find? (fun q => !started (rs.filter w.binds) q) with
      | none => rfl
      | some p => exact absurd ⟨p, h⟩ hs
    by_cases hk : 0 < k
    · exact Or.inl (verdict_wait_degraded a w k rs hf hp hq hall hk)
    · have : k = 0 := by omega
      subst this
      exact Or.inr (Or.inr ⟨_, verdict_run_local a w rs hf hp hq hall⟩)

/-- A completed run with conclusion failure is `fail`, for every waiter exit and output. -/
theorem laneState_completed_failure (code : Nat) (t : Bool) (status conclusion : String) (h : completedFailure status conclusion = true) :
    laneState code t status conclusion = .fail := by
  simp [laneState, h]

/-- Without a completed failure the waiter's outcome stands. -/
theorem laneState_waiter (code : Nat) (t : Bool) (status conclusion : String) (h : completedFailure status conclusion = false) :
    laneState code t status conclusion = waitState code t := by
  simp [laneState, h]

/-- The run record a lane run yields, bound to the sha and digest it printed. -/
def laneRun (p : Provider) (sha laneId digest : String) (code : Nat) (t : Bool) (status conclusion : String) : Run :=
  { provider := p, sha := sha, laneId := laneId, laneDigest := digest, state := laneState code t status conclusion }

/-- A completed bound failed lane run refuses the land, whatever exit code the waiter returned and whatever the other runs say. -/
theorem verdict_completed_failure_refuses (a : List Provider) (w : Want) (k : Nat) (rs : List Run) (p : Provider)
    (code : Nat) (t : Bool) (status conclusion : String) (hc : completedFailure status conclusion = true)
    (hb : w.binds (laneRun p w.sha w.laneId w.laneDigest code t status conclusion) = true)
    (hm : laneRun p w.sha w.laneId w.laneDigest code t status conclusion ∈ rs) :
    verdict true true a w k rs = .refuse .remoteFail :=
  verdict_fail a w k rs ⟨_, hm, hb, laneState_completed_failure code t status conclusion hc⟩

/-- A fallback to the local tier is impossible while a completed bound failed run is among the runs. -/
theorem verdict_no_local_after_failure (a : List Provider) (w : Want) (k : Nat) (rs : List Run) (p : Provider)
    (code : Nat) (t : Bool) (status conclusion : String) (hc : completedFailure status conclusion = true)
    (hb : w.binds (laneRun p w.sha w.laneId w.laneDigest code t status conclusion) = true)
    (hm : laneRun p w.sha w.laneId w.laneDigest code t status conclusion ∈ rs) (y : LocalWhy) :
    verdict true true a w k rs ≠ .runLocal y := by
  rw [verdict_completed_failure_refuses a w k rs p code t status conclusion hc hb hm]
  intro h; cases h

#guard laneDigest .onCi ["apps/runner", "packages/gh-budget"] == "remote:apps/runner,packages/gh-budget"
#guard laneDigest .onCi [] == "remote:"
#guard LandTier.remoteIds.all (fun i => !i.contains ',')


private def strs (xs : List String) : Json := .arr (xs.map Json.str).toArray

/-- The request JSON of a verdict case. -/
def runJson (r : Run) : Json :=
  Json.mkObj [("provider", .str r.provider.name), ("sha", .str r.sha), ("laneId", .str r.laneId),
    ("laneDigest", .str r.laneDigest), ("state", .str r.state.name)]

/-- The response JSON of a verdict. -/
def verdictJson (v : Verdict) : Json :=
  Json.mkObj [("kind", .str v.kind), ("reason", .str v.reason), ("ok", .bool v.ok),
    ("provider", match v.provider with | some p => .str p.name | none => .null)]

/-- One verdict golden line. -/
def line (name : String) (l n : Bool) (a : List Provider) (w : Want) (k : Nat) (rs : List Run) : Json :=
  Json.mkObj [("name", .str name),
    ("request", Json.mkObj [("op", .str "console.landRemote"), ("localOk", .bool l), ("needed", .bool n),
      ("allow", strs (a.map Provider.name)),
      ("want", Json.mkObj [("sha", .str w.sha), ("laneId", .str w.laneId), ("laneDigest", .str w.laneDigest)]),
      ("waitsLeft", .num k), ("runs", .arr (rs.map runJson).toArray)]),
    ("response", verdictJson (verdict l n a w k rs))]

/-- One digest golden line. -/
def digestLine (name : String) (ids : List String) : Json :=
  Json.mkObj [("name", .str name), ("request", Json.mkObj [("op", .str "console.landDigest"), ("ids", strs ids)]),
    ("response", Json.mkObj [("digest", .str (laneDigest .onCi ids))])]

/-- The wanted lane of the golden cases. -/
def gw : Want := { sha := "aaaa111", laneId := "land", laneDigest := "remote:apps/runner,packages/gh-budget" }

private def run (p : Provider) (s : RunState) (sha := "aaaa111") (d := "remote:apps/runner,packages/gh-budget") : Run :=
  { provider := p, sha := sha, laneId := "land", laneDigest := d, state := s }

/-- The golden cases: every branch of `verdict`. -/
def cases : List Json :=
  let gh := [Provider.github]
  let both := [Provider.github, Provider.circleci]
  [line "local tier failed, remote passed" false true gh gw 0 [run .github .pass],
   line "no remote check needed" true false gh gw 0 [],
   line "github pass" true true gh gw 0 [run .github .pass],
   line "github fail" true true gh gw 0 [run .github .fail],
   line "github pass, circleci fail: the fail wins" true true both gw 0 [run .github .pass, run .circleci .fail],
   line "circleci fail first, github pass" true true both gw 0 [run .circleci .fail, run .github .pass],
   line "circleci pass only" true true both gw 0 [run .circleci .pass],
   line "pass from a provider off the allowlist" true true gh gw 0 [run .circleci .pass],
   line "fail from a provider off the allowlist still refuses" true true gh gw 0 [run .circleci .fail, run .github .pass],
   line "pass for another sha" true true gh gw 0 [run .github .pass "bbbb222"],
   line "fail for another sha is ignored, pass for the sha" true true gh gw 0 [run .github .fail "bbbb222", run .github .pass],
   line "pass for another digest" true true gh gw 0 [run .github .pass "aaaa111" "remote:apps/runner"],
   line "fail for another digest is ignored" true true gh gw 0 [run .github .fail "aaaa111" "remote:apps/runner"],
   line "queued" true true gh gw 0 [run .github .queued],
   line "running" true true gh gw 0 [run .github .running],
   line "github running, circleci pass" true true both gw 0 [run .github .running, run .circleci .pass],
   line "no run yet, github first" true true both gw 0 [],
   line "no run yet, circleci only" true true [.circleci] gw 0 [],
   line "no providers, no polls" true true [] gw 0 [],
   line "github unavailable, try circleci" true true both gw 0 [run .github .unavailable],
   line "github cancelled, try circleci" true true both gw 0 [run .github .cancelled],
   line "github timeout, try circleci" true true both gw 0 [run .github .timeout],
   line "github unavailable, no other provider, wait" true true gh gw 2 [run .github .unavailable],
   line "github unavailable, no other provider, run locally" true true gh gw 0 [run .github .unavailable],
   line "github timeout, run locally" true true gh gw 0 [run .github .timeout],
   line "github cancelled, run locally" true true gh gw 0 [run .github .cancelled],
   line "both providers unavailable, run locally" true true both gw 0 [run .github .unavailable, run .circleci .unavailable],
   line "unavailable beats timeout in the reason" true true both gw 0 [run .github .timeout, run .circleci .unavailable],
   line "cancelled run of another sha leaves no reason" true true gh gw 0 [run .github .cancelled "bbbb222"]]

/-- One lane-state golden line. -/
def stateLine (name : String) (code : Nat) (t : Bool) (status conclusion : String) : Json :=
  Json.mkObj [("name", .str name),
    ("request", Json.mkObj [("op", .str "console.landLaneState"), ("exit", .num code), ("timedOut", .bool t),
      ("status", .str status), ("conclusion", .str conclusion)]),
    ("response", Json.mkObj [("state", .str (laneState code t status conclusion).name)])]

/-- The lane-state golden cases: each waiter exit next to a completed failure, and next to a pass and a run going. -/
def stateCases : List Json :=
  [0, 1, 2, 3, 4, 5].map (fun c => stateLine s!"completed failure, waiter exit {c}: fail" c false "completed" "failure") ++
  [stateLine "completed failure, exit 3 timed out: fail" 3 true "completed" "failure",
   stateLine "completed failure, no status field: fail" 0 false "" "failure",
   stateLine "pass, exit 0" 0 false "completed" "success",
   stateLine "fail by the waiter, no view" 1 false "" "",
   stateLine "exit 3 timed out, run going" 3 true "in_progress" "",
   stateLine "exit 3 without timed out: unavailable" 3 false "" "",
   stateLine "exit 4: cancelled" 4 false "completed" "success",
   stateLine "exit 2: unavailable" 2 false "" "",
   stateLine "cancelled conclusion keeps the waiter outcome" 4 false "completed" "cancelled",
   stateLine "failure conclusion on a run still going is no completed failure" 3 true "in_progress" "failure"]

/-- The golden file text. -/
def goldenText : String :=
  String.join ((cases ++ stateCases ++ [digestLine "two suites" ["apps/runner", "packages/gh-budget"], digestLine "no suites" [],
    digestLine "order is kept" ["packages/gh-budget", "apps/runner"]]).map fun c => c.compress ++ "\n")

/-- The golden file, relative to `lean/`. -/
def goldenPath : System.FilePath := "../packages/contracts/golden/console/land-remote.jsonl"

/-- Write the golden file. -/
def writeGolden : IO Unit := IO.FS.writeFile goldenPath goldenText

/-- Is the golden file the Lean output? -/
def checkGolden : IO Bool := do return (← IO.FS.readFile goldenPath) == goldenText

end Fw.Console.LandRemote
