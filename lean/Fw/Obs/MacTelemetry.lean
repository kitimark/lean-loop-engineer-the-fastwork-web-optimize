import Lean.Data.Json
import Fw.Ops.Wire
/-!
# macOS CI telemetry (task `macos-telemetry`): what the macOS jobs of the last days cost, by workflow, provider and step class

A macOS job is the scarce resource of the experiment (GitHub has 5 macOS slots, the user allows up to 7 concurrent). This
module normalizes the macOS jobs of three providers (GitHub Actions, Codemagic, CircleCI m4pro) into one row, and reduces
a window of rows into the tables of `research/notes/2026/10-2x-macos-telemetry.md` and a ranked list of cuts. The I/O
(`gh`, the Codemagic and CircleCI APIs) is `apps/runner/src/ci-telemetry-mac.ts`; every decision is here.

What is decided here, each with its own theorem:
- `classOf`: the class of a step name (ordered substring rules, first match wins, no match is measured work);
- `matchedMs`: the job time that exists on every provider, wall minus the steps dropped from matched time (upload, telemetry, post);
- `billedMin`: rounded-up minutes (GitHub per job, Codemagic at least one minute, CircleCI with the m4pro.medium rate);
- `eligibleMs`: when a job could first start (run created, or the latest end of a job of the same run that ended before it
  started), so `queueMs` is the wait for a slot and not the wait for `needs`;
- `pick`: the sample of runs whose jobs are read (cap on the total, a quota per stratum, every pick a candidate);
- `groupSum`: grouped sums add up to the total;
- `rank`: the cuts sorted by saving, a permutation of the cuts.
Savings are INFERRED (they are what the measured steps add up to, not a measured change) until a cut lands.
-/
namespace Fw.Obs.MacTelemetry
open Lean

/-! ## Providers, outcomes, step classes -/

/-- The providers whose macOS jobs are counted. -/
inductive Prov where
  | github
  | codemagic
  | circleci
deriving DecidableEq, Repr

/-- The wire name of a provider. -/
def Prov.tag : Prov → String
  | .github => "github"
  | .codemagic => "codemagic"
  | .circleci => "circleci"

/-- Decode a provider name. -/
def Prov.ofTag : String → Option Prov
  | "github" => some .github
  | "codemagic" => some .codemagic
  | "circleci" => some .circleci
  | _ => none

theorem Prov.ofTag_tag (p : Prov) : Prov.ofTag p.tag = some p := by cases p <;> rfl

/-- All providers in table order. -/
def Prov.all : List Prov := [.github, .codemagic, .circleci]

/-- How a job ended. `other` is a conclusion this module does not know (an open job has none), never counted as success. -/
inductive Outcome where
  | success
  | failure
  | cancelled
  | skipped
  | other
deriving DecidableEq, Repr

/-- The outcome of a provider's conclusion word (GitHub job conclusion, Codemagic build status, CircleCI job status). -/
def outcomeOf : Prov → String → Outcome
  | .github, "success" => .success
  | .github, "failure" => .failure
  | .github, "timed_out" => .failure
  | .github, "cancelled" => .cancelled
  | .github, "skipped" => .skipped
  | .codemagic, "finished" => .success
  | .codemagic, "failed" => .failure
  | .codemagic, "timeout" => .failure
  | .codemagic, "canceled" => .cancelled
  | .circleci, "success" => .success
  | .circleci, "failed" => .failure
  | .circleci, "timedout" => .failure
  | .circleci, "canceled" => .cancelled
  | _, _ => .other

theorem outcomeOf_github_success : outcomeOf .github "success" = .success := rfl
theorem outcomeOf_github_failure : outcomeOf .github "failure" = .failure := rfl
theorem outcomeOf_github_cancelled : outcomeOf .github "cancelled" = .cancelled := rfl
theorem outcomeOf_codemagic_finished : outcomeOf .codemagic "finished" = .success := rfl
theorem outcomeOf_codemagic_failed : outcomeOf .codemagic "failed" = .failure := rfl
theorem outcomeOf_circleci_success : outcomeOf .circleci "success" = .success := rfl
theorem outcomeOf_circleci_failed : outcomeOf .circleci "failed" = .failure := rfl
/-- **An open job (no conclusion) is never a success** (the `success -> fail` of run 39629760037 was an open job read as a conclusion). -/
theorem outcomeOf_open (p : Prov) : outcomeOf p "" = .other := by cases p <;> rfl

/-- The step classes. -/
inductive Cls where
  | setup
  | cache
  | runtime
  | proxy
  | simBoot
  | measure
  | upload
  | teardown
  | telemetry
  | post
deriving DecidableEq, Repr

/-- The wire name of a class. -/
def Cls.tag : Cls → String
  | .setup => "setup"
  | .cache => "cache"
  | .runtime => "runtime"
  | .proxy => "proxy"
  | .simBoot => "simBoot"
  | .measure => "measure"
  | .upload => "upload"
  | .teardown => "teardown"
  | .telemetry => "telemetry"
  | .post => "post"

/-- All classes in table order. -/
def Cls.all : List Cls := [.setup, .cache, .runtime, .proxy, .simBoot, .measure, .upload, .teardown, .telemetry, .post]

/-- A class whose time exists on every provider; upload, telemetry and post are dropped from matched time (task spec said
3 to 6 min per job; MEASURED here 8.7 s per GitHub job, `research/notes/2026/10-2x-macos-telemetry.md`). -/
def Cls.matched : Cls → Bool
  | .upload => false
  | .telemetry => false
  | .post => false
  | _ => true

theorem Cls.matched_false_iff (c : Cls) : c.matched = false ↔ (c = .upload ∨ c = .telemetry ∨ c = .post) := by
  cases c <;> simp [Cls.matched]

theorem Cls.all_complete (c : Cls) : c ∈ Cls.all := by cases c <;> simp [Cls.all]

/-- Lower-case an ASCII letter. -/
def lowerC (c : Char) : Char := if 'A' ≤ c ∧ c ≤ 'Z' then Char.ofNat (c.toNat + 32) else c

/-- A name as lower-case characters. -/
def lowerL (s : String) : List Char := s.toList.map lowerC

/-- Whether `n` occurs inside `h` (structural on the haystack, so `decide` can run it). -/
def hasInfix : List Char → List Char → Bool
  | [], n => n.isEmpty
  | h :: t, n => n.isPrefixOf (h :: t) || hasInfix t n

theorem hasInfix_nil (h : List Char) : hasInfix h [] = true := by cases h <;> simp [hasInfix]

/-- The rules in order: the first class with a needle in the lower-case step name wins. -/
def rules : List (Cls × List String) :=
  [(.telemetry, ["telemetry", "tool and runner facts", "marks and host sampler", "mark time", "span checkout", "timings.json",
      "stop sampler"]),
   (.upload, ["upload-artifact", "publishing", "uploading artifacts"]),
   (.cache, ["actions/cache"]),
   (.post, ["post run", "complete job", "cleaning up"]),
   (.teardown, ["delete the simulator", "shut down", "keep logs", "host state on failure"]),
   (.simBoot, ["boot the simulator", "background boot", "pinned ios runtime", "pinned runtime"]),
   (.proxy, ["ios_webkit_debug_proxy"]),
   (.runtime, ["playwright webkit (macos build", "archive, extracted"]),
   (.setup, ["set up job", "actions/checkout", "setup-node", "setup-pnpm", "setup-lean", "select xcode", "verify the snapshot",
      "download-artifact", "preparing build machine", "fetching app sources", "checkout code", "spin up environment",
      "preparing environment", "toolchain", "deps install", "host quieting", "tip re-check", "stale:"])]

/-- The class of a step name; a name no rule names is measured work. -/
def classOf (name : String) : Cls :=
  let h := lowerL name
  match rules.find? (fun r => r.2.any (fun n => hasInfix h n.toList)) with
  | some r => r.1
  | none => .measure

theorem classOf_setup_job : classOf "Set up job" = .setup := by decide
theorem classOf_checkout : classOf "Run actions/checkout@d23441a" = .setup := by decide
theorem classOf_cache : classOf "Run actions/cache@abc" = .cache := by decide
theorem classOf_cache_save : classOf "Post Run actions/cache@abc" = .cache := by decide
theorem classOf_runtime : classOf "Playwright WebKit (macOS build; no system libraries to install)" = .runtime := by decide
theorem classOf_archive : classOf "Archive, extracted into an empty directory (size and sha256 verified)" = .runtime := by decide
theorem classOf_proxy : classOf "ios_webkit_debug_proxy" = .proxy := by decide
theorem classOf_simBoot : classOf "Boot the Simulator (kept booted for the whole job)" = .simBoot := by decide
theorem classOf_simBoot_pinned : classOf "Pinned iOS runtime build, then create the device" = .simBoot := by decide
theorem classOf_measure : classOf "Determinism sessions" = .measure := by decide
theorem classOf_measure_default : classOf "WKTR, fresh process per pass, per variant" = .measure := by decide
theorem classOf_upload : classOf "Run actions/upload-artifact@cf430e0" = .upload := by decide
theorem classOf_upload_codemagic : classOf "Publishing" = .upload := by decide
theorem classOf_teardown : classOf "Delete the Simulator device" = .teardown := by decide
theorem classOf_teardown_logs : classOf "Keep logs and host state" = .teardown := by decide
theorem classOf_telemetry : classOf "Run ./.github/actions/telemetry" = .telemetry := by decide
theorem classOf_telemetry_facts : classOf "Tool and runner facts" = .telemetry := by decide
theorem classOf_post : classOf "Post Run actions/checkout@d23441a" = .post := by decide
theorem classOf_post_setup : classOf "Post Run ./.github/actions/setup-pnpm" = .post := by decide
theorem classOf_complete : classOf "Complete job" = .post := by decide
theorem classOf_empty : classOf "" = .measure := by decide

/-! ## Rows -/

/-- One step of a job in epoch ms. -/
structure Step where
  name : String
  startMs : Nat
  endMs : Nat
deriving DecidableEq, Repr

/-- Duration of a step. -/
def Step.durMs (s : Step) : Nat := s.endMs - s.startMs

/-- One macOS job on one provider. `createdMs`: when the run, pipeline or build was created; `event`: what started it. -/
structure Job where
  prov : Prov
  wf : String
  run : String
  name : String
  runner : String
  event : String
  createdMs : Nat
  startMs : Nat
  endMs : Nat
  concl : String
  steps : List Step
deriving DecidableEq, Repr

/-- The job's outcome. -/
def Job.outcome (j : Job) : Outcome := outcomeOf j.prov j.concl

/-- Wall time of a job. -/
def Job.wallMs (j : Job) : Nat := j.endMs - j.startMs

/-- Total time of the steps of one class. -/
def Job.classMs (j : Job) (c : Cls) : Nat := ((j.steps.filter fun s => classOf s.name == c).map Step.durMs).sum

/-- Time of the steps whose class is dropped from matched time. -/
def unmatchedMs (ss : List Step) : Nat := ((ss.filter fun s => !(classOf s.name).matched).map Step.durMs).sum

/-- **Step-matched job time**: wall time minus the steps that only some providers have. -/
def matchedMs (wall : Nat) (ss : List Step) : Nat := wall - unmatchedMs ss

/-- Step-matched time of a job. -/
def Job.matched (j : Job) : Nat := matchedMs j.wallMs j.steps

theorem matchedMs_le (w : Nat) (ss : List Step) : matchedMs w ss ≤ w := Nat.sub_le _ _

/-- **Matched plus unmatched is the wall time** when the steps fit in the wall time. -/
theorem matchedMs_add (w : Nat) (ss : List Step) (h : unmatchedMs ss ≤ w) : matchedMs w ss + unmatchedMs ss = w := by
  unfold matchedMs; omega

/-- **With no unmatched step the matched time is the wall time.** -/
theorem matchedMs_none (w : Nat) (ss : List Step) (h : ∀ s ∈ ss, (classOf s.name).matched = true) : matchedMs w ss = w := by
  have : ss.filter (fun s => !(classOf s.name).matched) = [] :=
    List.filter_eq_nil_iff.2 (fun s hs => by simp [h s hs])
  simp [matchedMs, unmatchedMs, this]

theorem matchedMs_nil (w : Nat) : matchedMs w [] = w := matchedMs_none w [] (by simp)

/-- A job that is only an upload step: nothing of it is matched. -/
theorem matchedMs_upload (d : Nat) : matchedMs d [{ name := "Run actions/upload-artifact@x", startMs := 0, endMs := d }] = 0 := by
  have : classOf "Run actions/upload-artifact@x" = .upload := by decide
  simp [matchedMs, unmatchedMs, Step.durMs, this, Cls.matched]

/-! ## Billing -/

/-- Whole minutes, rounded up. -/
def ceilMin (ms : Nat) : Nat := (ms + 59999) / 60000

theorem ceilMin_ge (ms : Nat) : ms ≤ ceilMin ms * 60000 := by unfold ceilMin; omega

theorem ceilMin_lt (ms : Nat) : ceilMin ms * 60000 < ms + 60000 := by unfold ceilMin; omega

/-- CircleCI credits per minute of an m4pro.medium job (`docs/team/tools/circleci.md`). -/
def circleCreditsPerMin : Nat := 200

/-- Billed minutes of a job: GitHub rounds each job up (INFERRED from the billing doc, not read from an invoice); Codemagic
bills at least one minute per build; CircleCI bills credits per started minute (the minutes here, `credits` below). -/
def Job.billedMin (j : Job) : Nat :=
  match j.prov with
  | .codemagic => max 1 (ceilMin j.wallMs)
  | _ => ceilMin j.wallMs

/-- CircleCI credits of a job (0 on the other providers). -/
def Job.credits (j : Job) : Nat := if j.prov = .circleci then circleCreditsPerMin * j.billedMin else 0

/-- **A job is billed for at least its wall time.** -/
theorem billedMin_ge (j : Job) : j.wallMs ≤ j.billedMin * 60000 := by
  unfold Job.billedMin
  have h1 := ceilMin_ge j.wallMs
  split
  · have h2 : ceilMin j.wallMs ≤ max 1 (ceilMin j.wallMs) := Nat.le_max_right ..
    exact Nat.le_trans h1 (Nat.mul_le_mul_right _ h2)
  · exact h1

/-- **Codemagic bills a started build for a whole minute.** -/
theorem billedMin_codemagic_pos (j : Job) (h : j.prov = .codemagic) : 1 ≤ j.billedMin := by
  simp only [Job.billedMin, h]
  exact Nat.le_max_left ..

/-! ## Queue -/

/-- When a job could first have started: its run was created, or the latest end of another job of the same run (and
provider) that ended before it started (a `needs` edge). -/
def eligibleMs (j : Job) (all : List Job) : Nat :=
  ((all.filter fun o => o.prov == j.prov && o.run == j.run && o.name != j.name && o.endMs ≤ j.startMs).map (·.endMs)).foldl
    max j.createdMs

/-- The wait for a slot: from eligible to started. -/
def Job.queueMs (j : Job) (all : List Job) : Nat := j.startMs - eligibleMs j all

theorem foldl_max_ge (l : List Nat) (a : Nat) : a ≤ l.foldl max a := by
  induction l generalizing a with
  | nil => exact Nat.le_refl _
  | cons x t ih => exact Nat.le_trans (Nat.le_max_left a x) (ih _)

theorem foldl_max_le (l : List Nat) (a b : Nat) (ha : a ≤ b) (h : ∀ x ∈ l, x ≤ b) : l.foldl max a ≤ b := by
  induction l generalizing a with
  | nil => exact ha
  | cons x t ih =>
    exact ih _ (Nat.max_le.2 ⟨ha, h x (List.mem_cons_self ..)⟩) (fun y hy => h y (List.mem_cons_of_mem _ hy))

/-- **A job is never eligible before its run was created.** -/
theorem createdMs_le_eligibleMs (j : Job) (all : List Job) : j.createdMs ≤ eligibleMs j all := foldl_max_ge _ _

/-- **A job is eligible no later than it started** (given the run was created before it started). -/
theorem eligibleMs_le_startMs (j : Job) (all : List Job) (h : j.createdMs ≤ j.startMs) : eligibleMs j all ≤ j.startMs := by
  apply foldl_max_le _ _ _ h
  intro x hx
  simp only [List.mem_map, List.mem_filter, Bool.and_eq_true, beq_iff_eq, bne_iff_ne, ne_eq, decide_eq_true_eq] at hx
  obtain ⟨o, ⟨_, hle⟩, rfl⟩ := hx
  exact hle.2

/-- **Queue plus the wait before eligibility is the start time**: `eligible + queue = start`. -/
theorem eligible_add_queue (j : Job) (all : List Job) (h : j.createdMs ≤ j.startMs) :
    eligibleMs j all + j.queueMs all = j.startMs := by
  have := eligibleMs_le_startMs j all h
  unfold Job.queueMs; omega

/-- A job with no sibling waits from the run's creation. -/
theorem queueMs_alone (j : Job) : j.queueMs [] = j.startMs - j.createdMs := by
  simp [Job.queueMs, eligibleMs]

/-! ## The sample of runs whose jobs are read

GitHub shows the jobs of one run per request, so the jobs of at most `cap` runs are read. The candidates are the runs long
enough to hold a macOS job, in strata (workflow, dispatch or not); every stratum gets a quota in proportion to its size,
at least one run, and the picks of all strata never pass `cap`. -/

/-- `q` items of `xs` spread evenly over the list (all of them when `q` covers the list). -/
def evenly {α : Type} (xs : List α) (q : Nat) : List α :=
  if xs.length ≤ q then xs else (List.range q).filterMap fun i => xs[i * xs.length / q]?

/-- **At most `q` items are picked.** -/
theorem evenly_length_le {α : Type} (xs : List α) (q : Nat) : (evenly xs q).length ≤ q := by
  unfold evenly
  split
  · assumption
  · have := List.length_filterMap_le (fun i => xs[i * xs.length / q]?) (List.range q)
    simpa using this

/-- **A pick is an item of the list.** -/
theorem evenly_subset {α : Type} (xs : List α) (q : Nat) {x : α} (h : x ∈ evenly xs q) : x ∈ xs := by
  unfold evenly at h
  split at h
  · exact h
  · simp only [List.mem_filterMap] at h
    obtain ⟨_, _, hx⟩ := h
    exact List.mem_of_getElem? hx

/-- **When the list fits in `q`, every item is picked.** -/
theorem evenly_all {α : Type} (xs : List α) (q : Nat) (h : xs.length ≤ q) : evenly xs q = xs := by
  simp [evenly, h]

/-- The picks of the strata one after the other: each takes at most its quota and what is left of the cap. -/
def pickAux (cap total : Nat) : Nat → List (String × List String) → List String
  | _, [] => []
  | rem, (_, ids) :: rest =>
    let ch := evenly ids (min rem (max 1 (cap * ids.length / total)))
    ch ++ pickAux cap total (rem - ch.length) rest

/-- The sampled run ids: strata in the given order, ids in the order given inside a stratum. -/
def pick (cap : Nat) (strata : List (String × List String)) : List String :=
  pickAux cap (strata.map (fun s => s.2.length)).sum cap strata

theorem pickAux_length_le (cap total : Nat) (ss : List (String × List String)) (rem : Nat) :
    (pickAux cap total rem ss).length ≤ rem := by
  induction ss generalizing rem with
  | nil => simp [pickAux]
  | cons s rest ih =>
    obtain ⟨k, ids⟩ := s
    simp only [pickAux, List.length_append]
    have h1 := Nat.le_trans (evenly_length_le ids (min rem (max 1 (cap * ids.length / total)))) (Nat.min_le_left ..)
    have := ih (rem - (evenly ids (min rem (max 1 (cap * ids.length / total)))).length)
    omega

/-- **The sample never passes the cap.** -/
theorem pick_length_le (cap : Nat) (ss : List (String × List String)) : (pick cap ss).length ≤ cap :=
  pickAux_length_le _ _ _ _

theorem pickAux_subset (cap total : Nat) (ss : List (String × List String)) (rem : Nat) {x : String}
    (h : x ∈ pickAux cap total rem ss) : ∃ s ∈ ss, x ∈ s.2 := by
  induction ss generalizing rem with
  | nil => simp [pickAux] at h
  | cons s rest ih =>
    obtain ⟨k, ids⟩ := s
    simp only [pickAux, List.mem_append] at h
    rcases h with h | h
    · exact ⟨(k, ids), List.mem_cons_self .., evenly_subset _ _ h⟩
    · obtain ⟨t, ht, hx⟩ := ih _ h
      exact ⟨t, List.mem_cons_of_mem _ ht, hx⟩

/-- **Every sampled run is a candidate of some stratum.** -/
theorem pick_subset (cap : Nat) (ss : List (String × List String)) {x : String} (h : x ∈ pick cap ss) :
    ∃ s ∈ ss, x ∈ s.2 := pickAux_subset _ _ _ _ h

/-- **A cap that covers all candidates samples all of them** (one stratum). -/
theorem pick_all_one (cap : Nat) (k : String) (ids : List String) (h : ids.length ≤ cap) : pick cap [(k, ids)] = ids := by
  by_cases h0 : ids.length = 0
  · have : ids = [] := List.length_eq_zero_iff.1 h0
    subst this
    simp [pick, pickAux, evenly]
  · have hp : 0 < ids.length := Nat.pos_of_ne_zero h0
    have hq : cap * ids.length / ids.length = cap := Nat.mul_div_cancel cap hp
    have hc : 1 ≤ cap := Nat.le_trans hp h
    have hm : min cap (max 1 cap) = cap := by omega
    simp only [pick, pickAux, List.map_cons, List.map_nil, List.sum_cons, List.sum_nil, Nat.add_zero, hq, hm]
    rw [evenly_all _ _ h]
    simp

/-! ## Runs, strata, weights -/

/-- One workflow run (all runs of the macOS workflows are rows; they carry the run-level minutes). -/
structure Run where
  wf : String
  id : String
  event : String
  createdMs : Nat
  startMs : Nat
  endMs : Nat
  concl : String
deriving DecidableEq, Repr

/-- Wall time of a run. -/
def Run.wallMs (r : Run) : Nat := r.endMs - r.startMs

/-- The stratum of a run: its workflow, and whether a person or a script dispatched it. -/
def stratumOf (wf event : String) : String := wf ++ "/" ++ (if event == "workflow_dispatch" then "dispatch" else "other")

/-- A run that can hold a macOS job: finished and at least `minMs` long (a shorter run is a skipped or Linux-only run). -/
def Run.candidate (minMs : Nat) (r : Run) : Bool := r.concl != "" && minMs ≤ r.wallMs

/-- The candidates in strata, each stratum's ids in start order; strata in first-seen order. -/
def strataOf (minMs : Nat) (runs : List Run) : List (String × List String) :=
  let cs := (runs.filter (Run.candidate minMs)).mergeSort (fun a b => a.startMs ≤ b.startMs)
  let keys := (cs.map fun r => stratumOf r.wf r.event).eraseDups
  keys.map fun k => (k, (cs.filter fun r => stratumOf r.wf r.event == k).map (·.id))

/-- **The ids of the strata are candidates.** -/
theorem strataOf_ids (minMs : Nat) (runs : List Run) {k : String} {ids : List String} {x : String}
    (hs : (k, ids) ∈ strataOf minMs runs) (hx : x ∈ ids) : ∃ r ∈ runs, r.id = x ∧ r.candidate minMs = true := by
  simp only [strataOf, List.mem_map, Prod.mk.injEq] at hs
  obtain ⟨k', _, _, rfl⟩ := hs
  simp only [List.mem_map, List.mem_filter, List.mem_mergeSort] at hx
  obtain ⟨r, ⟨⟨hr, hc⟩, _⟩, hid⟩ := hx
  exact ⟨r, hr, hid, hc⟩

/-- Per-mille weight of a sampled job: candidates of its stratum per sampled run (1000 = the whole stratum was read). -/
def weightPm (cand sampled : Nat) : Nat := if sampled = 0 then 0 else cand * 1000 / sampled

/-- **Reading every candidate weighs 1000.** -/
theorem weightPm_full (n : Nat) (h : 0 < n) : weightPm n n = 1000 := by
  have hne : ¬ n = 0 := Nat.pos_iff_ne_zero.1 h
  simp only [weightPm, hne, ite_false]
  exact Nat.mul_div_cancel_left 1000 h

/-- **A job in an unread stratum weighs nothing.** -/
theorem weightPm_unread (n : Nat) : weightPm n 0 = 0 := by simp [weightPm]

/-- **Half the candidates read: weight 2000** (each read run stands for two). -/
theorem weightPm_half : weightPm 20 10 = 2000 := by decide

/-- The job name without its matrix suffix: `sim (a, b)` is `sim`. -/
def baseName (n : String) : String := (n.splitOn " (").headD n

/-- The GitHub jobs that run on a macOS runner, by workflow and base job name (the job list of the API carries no runner
label; the names are read from the workflow files, `.github/workflows/`). -/
def macJobs : List (String × String) :=
  [("trajectory-probe", "probe apple"), ("webkit-sim", "sim"), ("wktr", "wktr"), ("wktr-fixtures", "fixtures"),
   ("engine-premises", "webkit"), ("gate-gaps", "collect-macos"), ("sim-speed", "probe")]

/-- Whether a GitHub job of `wf` named `name` runs on macOS. -/
def isMacJob (wf name : String) : Bool := macJobs.any fun (w, n) => w == wf && n == baseName name

#guard isMacJob "webkit-sim" "sim" = true
#guard isMacJob "webkit-sim" "sim (iPhone 15)" = true
#guard isMacJob "webkit-sim" "guard" = false
#guard isMacJob "wktr" "sim" = false
#guard isMacJob "trajectory-probe" "probe apple" = true
#guard isMacJob "trajectory-probe" "probe chromium 390" = false

/-! ## Aggregates, grouped sums

Every measure is a weighted sum (weights in per mille, `weightPm`), so the table of a group and the table of the whole add up. -/

/-- The sums of a group of jobs. `n` rows, `wt` the weights, `raw` the unweighted wall ms, the others weighted
(per mille x ms, or per mille x minutes for `billed`). -/
structure Agg where
  n : Nat := 0
  wt : Nat := 0
  raw : Nat := 0
  wall : Nat := 0
  billed : Nat := 0
  matched : Nat := 0
  queue : Nat := 0
  bad : Nat := 0
deriving DecidableEq, Repr

/-- Add two aggregates. -/
def Agg.add (a b : Agg) : Agg :=
  { n := a.n + b.n, wt := a.wt + b.wt, raw := a.raw + b.raw, wall := a.wall + b.wall, billed := a.billed + b.billed,
    matched := a.matched + b.matched, queue := a.queue + b.queue, bad := a.bad + b.bad }

/-- The aggregate of one job with weight `w` among `all` (for the queue). -/
def Agg.ofJob (all : List Job) (w : Nat) (j : Job) : Agg :=
  { n := 1, wt := w, raw := j.wallMs, wall := w * j.wallMs, billed := w * j.billedMin, matched := w * j.matched,
    queue := w * j.queueMs all, bad := if j.outcome = .success then 0 else w * j.wallMs }

/-- Add a row to the group `k` of an association list (a new group at the end). -/
def addTo : List (String × Agg) → String → Agg → List (String × Agg)
  | [], k, a => [(k, a)]
  | (k', b) :: rest, k, a => if k' == k then (k', b.add a) :: rest else (k', b) :: addTo rest k a

/-- Group rows by a key, summing their aggregates; groups in first-seen order. -/
def groupAgg {α : Type} (key : α → String) (f : α → Agg) (xs : List α) : List (String × Agg) :=
  xs.foldl (fun acc x => addTo acc (key x) (f x)) []

/-- The sum of a number over the groups. -/
def sumBy (p : Agg → Nat) (g : List (String × Agg)) : Nat := (g.map fun kv => p kv.2).sum

theorem addTo_sum (p : Agg → Nat) (hp : ∀ a b, p (a.add b) = p a + p b) (g : List (String × Agg)) (k : String) (a : Agg) :
    sumBy p (addTo g k a) = sumBy p g + p a := by
  induction g with
  | nil => simp [addTo, sumBy]
  | cons kv rest ih =>
    obtain ⟨k', b⟩ := kv
    unfold addTo
    by_cases h : k' == k
    · simp only [h, ite_true, sumBy, List.map_cons, List.sum_cons, hp]
      omega
    · simp only [h, Bool.false_eq_true, ite_false, sumBy, List.map_cons, List.sum_cons] at ih ⊢
      omega

theorem foldl_addTo_sum {α : Type} (key : α → String) (f : α → Agg) (p : Agg → Nat) (hp : ∀ a b, p (a.add b) = p a + p b)
    (xs : List α) (g : List (String × Agg)) :
    sumBy p (xs.foldl (fun acc x => addTo acc (key x) (f x)) g) = sumBy p g + (xs.map fun x => p (f x)).sum := by
  induction xs generalizing g with
  | nil => simp
  | cons x t ih =>
    simp only [List.foldl_cons, List.map_cons, List.sum_cons]
    rw [ih, addTo_sum p hp]
    omega

/-- **Grouped sums add up to the total**, for every measure that adds (`hp`): no job is lost or counted twice by grouping. -/
theorem groupAgg_sum {α : Type} (key : α → String) (f : α → Agg) (p : Agg → Nat) (hp : ∀ a b, p (a.add b) = p a + p b)
    (xs : List α) : sumBy p (groupAgg key f xs) = (xs.map fun x => p (f x)).sum := by
  unfold groupAgg
  rw [foldl_addTo_sum key f p hp xs []]
  simp [sumBy]

/-- **Weighted wall time of the groups adds up to the total.** -/
theorem groupAgg_wall {α : Type} (key : α → String) (f : α → Agg) (xs : List α) :
    sumBy (·.wall) (groupAgg key f xs) = (xs.map fun x => (f x).wall).sum :=
  groupAgg_sum key f _ (fun _ _ => rfl) xs

/-- **Billed minutes of the groups add up to the total.** -/
theorem groupAgg_billed {α : Type} (key : α → String) (f : α → Agg) (xs : List α) :
    sumBy (·.billed) (groupAgg key f xs) = (xs.map fun x => (f x).billed).sum :=
  groupAgg_sum key f _ (fun _ _ => rfl) xs

/-- **Step-matched time of the groups adds up to the total.** -/
theorem groupAgg_matched {α : Type} (key : α → String) (f : α → Agg) (xs : List α) :
    sumBy (·.matched) (groupAgg key f xs) = (xs.map fun x => (f x).matched).sum :=
  groupAgg_sum key f _ (fun _ _ => rfl) xs

/-- **The job count of the groups adds up to the number of jobs** (`n` is 1 per job). -/
theorem groupAgg_count {α : Type} (key : α → String) (f : α → Agg) (hf : ∀ x, (f x).n = 1) (xs : List α) :
    sumBy (·.n) (groupAgg key f xs) = xs.length := by
  rw [groupAgg_sum key f _ (fun _ _ => rfl) xs]
  have : (xs.map fun x => (f x).n) = xs.map fun _ => 1 := List.map_congr_left (fun x _ => hf x)
  rw [this]
  clear this hf
  induction xs with
  | nil => rfl
  | cons x t ih => simp only [List.map_cons, List.sum_cons, List.length_cons] at ih ⊢; omega

/-- **A job is one row**: `Agg.ofJob` counts 1. -/
theorem Agg.ofJob_n (all : List Job) (w : Nat) (j : Job) : (Agg.ofJob all w j).n = 1 := rfl

/-! ## Median, sorting, weights per job -/

/-- The lower median of a list (0 for the empty list). -/
def median (xs : List Nat) : Nat := (xs.mergeSort (fun a b => decide (a ≤ b))).getD ((xs.length - 1) / 2) 0

/-- **The median is one of the numbers** (of a non-empty list). -/
theorem median_mem (xs : List Nat) (h : xs ≠ []) : median xs ∈ xs := by
  unfold median
  have hl : 0 < xs.length := List.length_pos_iff.2 h
  have hlen := List.length_mergeSort (le := fun a b => decide (a ≤ b)) xs
  have hi : (xs.length - 1) / 2 < (xs.mergeSort (fun a b => decide (a ≤ b))).length := by omega
  rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hi]
  exact List.mem_mergeSort.1 (List.getElem_mem hi)

#guard median [] == 0
#guard median [30, 10, 20] == 20
#guard median [40, 10, 30, 20] == 20
#guard median [7] == 7

/-- Sort descending by a number; ties keep the order of the list (the sort is stable). -/
def sortDesc {α : Type} (key : α → Nat) (xs : List α) : List α := xs.mergeSort (fun a b => decide (key b ≤ key a))

/-- **Sorting loses and adds nothing**: the result is a permutation. -/
theorem sortDesc_perm {α : Type} (key : α → Nat) (xs : List α) : (sortDesc key xs).Perm xs := List.mergeSort_perm _ _

/-- **The result is in descending order.** -/
theorem sortDesc_sorted {α : Type} (key : α → Nat) (xs : List α) :
    (sortDesc key xs).Pairwise (fun a b => key b ≤ key a) := by
  have := List.pairwise_mergeSort (le := fun a b => decide (key b ≤ key a))
    (fun a b c hab hbc => by simp at hab hbc ⊢; omega) (fun a b => by simp; omega) xs
  unfold sortDesc
  exact this.imp (fun h => of_decide_eq_true h)

/-- The sampled runs of a stratum: the distinct run ids among its GitHub jobs. -/
def sampledRuns (jobs : List Job) (k : String) : Nat :=
  ((jobs.filter fun j => j.prov == .github && stratumOf j.wf j.event == k).map (·.run)).eraseDups.length

/-- Weights per stratum: candidates per sampled run, in per mille. -/
def weights (minMs : Nat) (runs : List Run) (jobs : List Job) : List (String × Nat) :=
  (strataOf minMs runs).map fun (k, ids) => (k, weightPm ids.length (sampledRuns jobs k))

/-- The weight of a job: GitHub jobs by their stratum (1000 when the stratum is not in the table), the other providers
read every build (1000). -/
def Job.weight (ws : List (String × Nat)) (j : Job) : Nat :=
  if j.prov == .github then (ws.lookup (stratumOf j.wf j.event)).getD 1000 else 1000

/-- **Codemagic and CircleCI jobs weigh 1000** (all builds are read). -/
theorem Job.weight_other (ws : List (String × Nat)) (j : Job) (h : j.prov ≠ .github) : j.weight ws = 1000 := by
  unfold Job.weight
  have : (j.prov == .github) = false := by cases hp : j.prov <;> simp_all
  simp [this]

/-- Milliseconds of a weighted sum (per mille x ms) per day of a window of `win` ms. -/
def perDay (x win : Nat) : Nat := x * 86400000 / (max 1 win * 1000)

/-- **A window that is one day long: the per-day value is the value** (weight 1000, i.e. read in full). -/
theorem perDay_day (ms : Nat) : perDay (ms * 1000) 86400000 = ms := by
  unfold perDay
  have : max 1 86400000 = 86400000 := by decide
  rw [this]
  rw [Nat.mul_assoc, Nat.mul_comm 1000 86400000]
  exact Nat.mul_div_cancel ms (by decide)

/-! ## Number formatting -/

/-- `n / d` with one decimal, rounded down (`-` when `d` is 0). -/
def dec1 (n d : Nat) : String :=
  if d = 0 then "-" else
    let t := n * 10 / d
    s!"{t / 10}.{t % 10}"

/-- Minutes with one decimal from ms. -/
def minStr (ms : Nat) : String := dec1 ms 60000

/-- Seconds with one decimal from ms. -/
def secStr (ms : Nat) : String := dec1 ms 1000

/-- Percent of `b` that `a` is, one decimal. -/
def pctStr (a b : Nat) : String := if b = 0 then "-" else dec1 (a * 100) b ++ "%"

/-- A Markdown table row. -/
def mdRow (cells : List String) : String := "| " ++ " | ".intercalate cells ++ " |"

/-- A Markdown table: header, separator, rows. -/
def mdTable (hdr : List String) (rows : List (List String)) : String :=
  "\n".intercalate ([mdRow hdr, mdRow (hdr.map fun _ => "---")] ++ rows.map mdRow)

#guard mdTable ["a", "b"] [["1", "2"]] == "| a | b |\n| --- | --- |\n| 1 | 2 |"
#guard minStr 90000 == "1.5"
#guard minStr 59999 == "0.9"
#guard secStr 1234 == "1.2"
#guard pctStr 1 3 == "33.3%"
#guard pctStr 1 0 == "-"

/-! ## The reducer -/

/-- The window of rows to reduce. `jobs` holds every job of the read runs (the Linux jobs without steps: they only date a
`needs` edge), the macOS jobs of the other providers with steps. -/
structure Input where
  fromMs : Nat
  toMs : Nat
  minRunMs : Nat
  cap : Nat
  runs : List Run
  jobs : List Job

/-- The rows the tables count: macOS jobs only. -/
def Input.kept (i : Input) : List Job := i.jobs.filter fun j => j.prov != .github || isMacJob j.wf j.name

/-- **A kept GitHub job is a macOS job.** -/
theorem Input.kept_github (i : Input) (j : Job) (hj : j ∈ i.kept) (hg : j.prov = .github) : isMacJob j.wf j.name = true := by
  simp only [Input.kept, List.mem_filter, Bool.or_eq_true, bne_iff_ne, ne_eq] at hj
  rcases hj.2 with h | h
  · exact absurd hg h
  · exact h

/-- The earliest creation time in the rows (the data may start after the window does). -/
def Input.firstMs (i : Input) : Nat := ((i.runs.map (·.createdMs)) ++ (i.jobs.map (·.createdMs))).foldl min i.toMs

/-- The window the rates are per day of: from the later of the stated start and the first row. -/
def Input.winMs (i : Input) : Nat := i.toMs - max i.fromMs i.firstMs

/-- **The window of the rates is never longer than the stated one.** -/
theorem Input.winMs_le (i : Input) : i.winMs ≤ i.toMs - i.fromMs :=
  Nat.sub_le_sub_left (Nat.le_max_left ..) _

/-- **A window that starts at the stated start when the data does** has the stated length. -/
theorem Input.winMs_stated (i : Input) (h : i.fromMs ≥ i.firstMs) : i.winMs = i.toMs - i.fromMs := by
  unfold Input.winMs
  rw [Nat.max_eq_left h]

/-- The workflows with a macOS job, in table order. -/
def wfs : List String := macJobs.map (·.1)

/-- What the tables share. -/
structure Ctx where
  i : Input
  kept : List Job
  gh : List Job
  ws : List (String × Nat)
  win : Nat

/-- Prepare the shared parts. -/
def Ctx.of (i : Input) : Ctx :=
  let k := i.kept
  { i, kept := k, gh := k.filter (·.prov == .github), ws := weights i.minRunMs i.runs i.jobs, win := i.winMs }

/-- Weighted milliseconds of a job measure over the jobs of one provider, per job: `Σ w x / Σ w`. -/
def Ctx.mean (c : Ctx) (p : Prov) (x : Job → Nat) : Nat :=
  let js := c.kept.filter (·.prov == p)
  ((js.map fun j => j.weight c.ws * x j).sum) / max 1 ((js.map fun j => j.weight c.ws).sum)

/-- Weighted sum (per mille x ms) of a measure over some jobs. -/
def Ctx.wsum (c : Ctx) (js : List Job) (x : Job → Nat) : Nat := (js.map fun j => j.weight c.ws * x j).sum

/-- Per day, in ms, of a weighted sum. -/
def Ctx.day (c : Ctx) (x : Nat) : Nat := perDay x c.win

/-- Minutes per day of a weighted sum, as text. -/
def Ctx.dayMin (c : Ctx) (x : Nat) : String := minStr (c.day x)

/-- The run-level table: all runs of the macOS workflows. -/
def runsTable (c : Ctx) : String :=
  mdTable ["workflow", "runs", "dispatched", "success", "failure", "cancelled", "candidates", "read", "run wall min", "run wall min/day"]
    (wfs.map fun w =>
      let rs := c.i.runs.filter (·.wf == w)
      let cnt (o : Outcome) := (rs.filter fun r => outcomeOf .github r.concl == o).length
      let wall := ((rs.filter fun r => r.concl != "").map Run.wallMs).sum
      let read := (((c.gh.filter (·.wf == w)).map (·.run)).eraseDups).length
      [w, toString rs.length, toString (rs.filter fun r => r.event == "workflow_dispatch").length, toString (cnt .success),
       toString (cnt .failure), toString (cnt .cancelled), toString (rs.filter (Run.candidate c.i.minRunMs)).length,
       toString read, minStr wall, c.dayMin (wall * 1000)])

/-- The per-workflow table of GitHub macOS jobs, weighted to all candidate runs. -/
def jobsTable (c : Ctx) : String :=
  let g := groupAgg (·.wf) (fun j => Agg.ofJob c.i.jobs (j.weight c.ws) j) c.gh
  mdTable ["workflow", "jobs read", "mean wall min", "est. wall min/day", "est. billed min/day", "est. matched min/day",
      "est. queue min/day", "non-success wall min/day", "non-success share"]
    (wfs.map fun w =>
      let a := (g.lookup w).getD {}
      [w, toString a.n, minStr (a.wall / max 1 a.wt), c.dayMin a.wall, c.dayMin (a.billed * 60000), c.dayMin a.matched,
       c.dayMin a.queue, c.dayMin a.bad, pctStr a.bad a.wall])

/-- The per-provider table. -/
def providersTable (c : Ctx) : String :=
  let g := groupAgg (·.prov.tag) (fun j => Agg.ofJob c.i.jobs (j.weight c.ws) j) c.kept
  mdTable ["provider", "jobs", "mean wall min", "mean billed min", "mean matched min", "mean queue min", "est. wall min/day",
      "est. billed min/day", "CircleCI credits/day"]
    (Prov.all.map fun p =>
      let a := (g.lookup p.tag).getD {}
      let w := max 1 a.wt
      [p.tag, toString a.n, minStr (a.wall / w), minStr (a.billed * 60000 / w), minStr (a.matched / w), minStr (a.queue / w),
       c.dayMin a.wall, c.dayMin (a.billed * 60000),
       if p = .circleci then toString (c.day (a.billed * circleCreditsPerMin)) else "-"])

/-- Time of all steps of a job. -/
def Job.stepsMs (j : Job) : Nat := (j.steps.map Step.durMs).sum

/-- Wall time that no step covers (the runner's own start-up and the gaps between steps). -/
def Job.gapMs (j : Job) : Nat := j.wallMs - j.stepsMs

/-- The per-step-class table: mean seconds per job on each provider, and the GitHub share of the wall time. -/
def classTable (c : Ctx) : String :=
  let sec (p : Prov) (x : Job → Nat) := secStr (c.mean p x)
  let ghWall := c.wsum c.gh (·.wallMs)
  mdTable ["class", "in matched time", "GitHub s/job", "Codemagic s/job", "CircleCI s/job", "GitHub min/day", "GitHub share of wall"]
    (Cls.all.map (fun cl =>
      let x := c.wsum c.gh (·.classMs cl)
      [cl.tag, if cl.matched then "yes" else "no", sec .github (·.classMs cl), sec .codemagic (·.classMs cl),
       sec .circleci (·.classMs cl), c.dayMin x, pctStr x ghWall]) ++
     [["(gap: wall minus steps)", "-", sec .github (·.gapMs), sec .codemagic (·.gapMs), sec .circleci (·.gapMs),
       c.dayMin (c.wsum c.gh (·.gapMs)), pctStr (c.wsum c.gh (·.gapMs)) ghWall],
      ["(job wall)", "-", sec .github (·.wallMs), sec .codemagic (·.wallMs), sec .circleci (·.wallMs), c.dayMin ghWall, "100.0%"]])

/-- One executed step of a GitHub macOS job, keyed by workflow, job and step name. -/
structure SRow where
  key : String
  cls : Cls
  dur : Nat
  w : Nat

/-- All steps of the GitHub macOS jobs. -/
def Ctx.stepRows (c : Ctx) : List SRow :=
  c.gh.flatMap fun j => j.steps.map fun s =>
    { key := j.wf ++ " / " ++ baseName j.name ++ " / " ++ s.name, cls := classOf s.name, dur := s.durMs, w := j.weight c.ws }

/-- The statistics of one step key. -/
structure StepStat where
  key : String
  cls : Cls
  n : Nat
  wall : Nat
  med : Nat
  max : Nat
  tail : Nat

/-- Weighted time above the median: what bringing every slow occurrence down to the median would save. -/
def tailOf (rs : List SRow) (m : Nat) : Nat := (rs.map fun s => s.w * (s.dur - m)).sum

/-- Weighted time of some steps. -/
def wallOf (rs : List SRow) : Nat := (rs.map fun s => s.w * s.dur).sum

/-- **Bringing every step down to a median never saves more than the steps took.** -/
theorem tailOf_le (rs : List SRow) (m : Nat) : tailOf rs m ≤ wallOf rs := by
  unfold tailOf wallOf
  induction rs with
  | nil => simp
  | cons s t ih =>
    simp only [List.map_cons, List.sum_cons]
    have := Nat.mul_le_mul_left s.w (Nat.sub_le s.dur m)
    omega

/-- The groups of step keys with their statistics; a key seen fewer than three times has no tail (the median of one or two
numbers is not a norm). -/
def stepStats (rows : List SRow) : List StepStat :=
  (groupAgg (·.key) (fun s => ({ n := 1, wt := s.w, raw := s.dur, wall := s.w * s.dur } : Agg)) rows).map fun (k, a) =>
    let rs := rows.filter (·.key == k)
    let ds := rs.map (·.dur)
    let m := median ds
    { key := k, cls := (match rs with | [] => .measure | r :: _ => r.cls), n := a.n, wall := a.wall, med := m,
      max := ds.foldl Nat.max 0, tail := if rs.length < 3 then 0 else tailOf rs m }

/-- The busiest steps: top `k` keys by weighted time. -/
def stepsTable (c : Ctx) (k : Nat) : String :=
  let st := (sortDesc (·.wall) (stepStats c.stepRows)).take k
  mdTable ["step (workflow / job / step)", "class", "read", "est. min/day", "median s", "max s", "tail above median min/day"]
    (st.map fun s => [s.key, s.cls.tag, toString s.n, c.dayMin s.wall, secStr s.med, secStr s.max, c.dayMin s.tail])

theorem sum_map_le {α : Type} (l : List α) (f g : α → Nat) (h : ∀ x ∈ l, f x ≤ g x) : (l.map f).sum ≤ (l.map g).sum := by
  induction l with
  | nil => simp
  | cons x t ih =>
    simp only [List.map_cons, List.sum_cons]
    have h1 := h x (List.mem_cons_self ..)
    have h2 := ih (fun y hy => h y (List.mem_cons_of_mem _ hy))
    omega

/-- The wall time of the success runs of the same workflow and job. -/
def Ctx.successWalls (c : Ctx) (j : Job) : List Nat :=
  (c.gh.filter fun o => o.wf == j.wf && baseName o.name == baseName j.name && o.outcome == .success).map (·.wallMs)

/-- What a cap of 1.5 x the median success wall saves on one job (weighted ms): the wall time above the cap, for a
non-success job of a group with at least three successes. -/
def Ctx.capTerm (c : Ctx) (j : Job) : Nat :=
  if j.outcome == .success then 0
  else if (c.successWalls j).length < 3 then 0
  else j.weight c.ws * (j.wallMs - 3 * median (c.successWalls j) / 2)

/-- What the cap would save over all jobs (weighted ms). -/
def Ctx.capSaving (c : Ctx) : Nat := (c.gh.map c.capTerm).sum

/-- **The cap never saves more than the jobs took.** -/
theorem Ctx.capSaving_le (c : Ctx) : c.capSaving ≤ c.wsum c.gh (·.wallMs) := by
  unfold Ctx.capSaving Ctx.wsum
  apply sum_map_le
  intro j _
  unfold Ctx.capTerm
  split
  · exact Nat.zero_le _
  · split
    · exact Nat.zero_le _
    · exact Nat.mul_le_mul_left _ (Nat.sub_le _ _)

/-- **A success job is never capped.** -/
theorem Ctx.capTerm_success (c : Ctx) (j : Job) (h : j.outcome = .success) : c.capTerm j = 0 := by
  simp [Ctx.capTerm, h]

/-- **A group with fewer than three successes has no cap** (the median of one or two walls is not a norm). -/
theorem Ctx.capTerm_few (c : Ctx) (j : Job) (h : (c.successWalls j).length < 3) : c.capTerm j = 0 := by
  simp [Ctx.capTerm, h]

/-- **A failure in a group of three successes is capped above 1.5 x their median.** -/
theorem Ctx.capTerm_failure (c : Ctx) (j : Job) (h : j.outcome ≠ .success) (h3 : 3 ≤ (c.successWalls j).length) :
    c.capTerm j = j.weight c.ws * (j.wallMs - 3 * median (c.successWalls j) / 2) := by
  have h1 : (j.outcome == .success) = false := by simpa using h
  have h2 : ¬ (c.successWalls j).length < 3 := Nat.not_lt.2 h3
  simp [Ctx.capTerm, h1, h2]


/-- The Codemagic minutes the plan allows (the stop line of the pilot, `research/notes/2026/10-2x-codemagic-pilot.md`). -/
def codemagicStopMin : Nat := 400

/-- Days the allowance covers. -/
def codemagicDays : Nat := 30

/-- Saving of moving the `webkit-sim` `sim` job to Codemagic as far as the allowance goes (ms of GitHub wall per day): as
many jobs per day as the allowance covers, each freeing a GitHub job; never more than the GitHub sim jobs take. -/
def Ctx.shiftSaving (c : Ctx) : Nat :=
  let sim := c.gh.filter fun j => j.wf == "webkit-sim" && baseName j.name == "sim"
  let cm := c.kept.filter (·.prov == .codemagic)
  if sim.isEmpty || cm.isEmpty then 0
  else
    let ghMean := c.wsum sim (·.wallMs) / max 1 (c.wsum sim fun _ => 1)
    let cmMean := (cm.map (·.wallMs)).sum / cm.length
    min (c.day (c.wsum sim (·.wallMs))) (codemagicStopMin * 60000 / codemagicDays * ghMean / max 1 cmMean)

/-- **The move never frees more than the sim jobs take.** -/
theorem Ctx.shiftSaving_le (c : Ctx) :
    c.shiftSaving ≤ c.day (c.wsum (c.gh.filter fun j => j.wf == "webkit-sim" && baseName j.name == "sim") (·.wallMs)) := by
  unfold Ctx.shiftSaving
  dsimp only
  split
  · exact Nat.zero_le _
  · exact Nat.min_le_left ..

/-- **Without a Codemagic build there is no move.** -/
theorem Ctx.shiftSaving_no_codemagic (c : Ctx) (h : (c.kept.filter (·.prov == .codemagic)).isEmpty = true) :
    c.shiftSaving = 0 := by
  unfold Ctx.shiftSaving
  simp [h]

/-- One candidate cut: what it saves per day (ms of GitHub macOS time), and how sure the number is. -/
structure Cut where
  id : String
  title : String
  savedMs : Nat
  bound : String

/-- The classes whose slow occurrences are a cut of their own. -/
def tailClasses : List Cls := [.setup, .cache, .runtime, .proxy, .simBoot, .measure, .upload]

/-- All candidate cuts, in no order. -/
def Ctx.cuts (c : Ctx) : List Cut :=
  let st := stepStats c.stepRows
  [{ id := "cap-nonsuccess", title := "Stop a non-success job at 1.5 x the median success wall of its job", savedMs := c.day c.capSaving,
     bound := "estimate" },
   { id := "drop-telemetry", title := "Drop the telemetry steps (the telemetry action, runner facts, host sampler)",
     savedMs := c.day (c.wsum c.gh (·.classMs .telemetry)), bound := "upper bound" },
   { id := "trim-teardown", title := "Drop the teardown steps (device deletion, log keeping, shut down)",
     savedMs := c.day (c.wsum c.gh (·.classMs .teardown)), bound := "upper bound" },
   { id := "shift-codemagic", title := "Run the sim job on Codemagic up to the allowance", savedMs := c.shiftSaving, bound := "estimate" }] ++
  tailClasses.map fun cl =>
    { id := s!"tail-{cl.tag}", title := s!"Bring slow {cl.tag} steps down to their median",
      savedMs := c.day ((st.filter (·.cls == cl)).map (·.tail)).sum, bound := "upper bound" }

/-- The cuts, largest saving first. -/
def rankCuts (cs : List Cut) : List Cut := sortDesc (·.savedMs) cs

/-- **Ranking loses and adds no cut.** -/
theorem rankCuts_perm (cs : List Cut) : (rankCuts cs).Perm cs := sortDesc_perm _ _

/-- **Ranking orders by saving.** -/
theorem rankCuts_sorted (cs : List Cut) : (rankCuts cs).Pairwise (fun a b => b.savedMs ≤ a.savedMs) := sortDesc_sorted _ _

/-- The ranked cuts as a table. -/
def cutsTable (c : Ctx) : String :=
  let total := c.wsum c.gh (·.wallMs)
  mdTable ["rank", "cut", "saves min/day", "share of GitHub macOS wall", "kind"]
    ((rankCuts c.cuts).zipIdx.map fun (x, r) =>
      [toString (r + 1), x.title, minStr x.savedMs, pctStr (x.savedMs * 1000) (c.day total * 1000), x.bound])

/-- Every table of the report by name. -/
def tables (i : Input) : List (String × String) :=
  let c := Ctx.of i
  [("runs", runsTable c), ("jobs", jobsTable c), ("providers", providersTable c), ("classes", classTable c),
   ("steps", stepsTable c 12), ("cuts", cutsTable c)]

end Fw.Obs.MacTelemetry

