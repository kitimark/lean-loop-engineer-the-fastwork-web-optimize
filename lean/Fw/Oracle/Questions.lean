import Fw.Oracle.Core
import Fw.Oracle.Labels
/-!
# Fw.Oracle.Questions: the registered questions, and the seeded option order of a request

`questions` is the registry the wire looks names up in: `ciTriage` (why a failed CI run failed), and the questions
of the trial's replay sets, `incidentClass` (set D1: the mistake class of an incident) and `findingSeverity` (set D2:
the grade of a review finding). Their options are the labels the sets carry (`incidentClass_labels`,
`findingSeverity_labels`), so every labeled row can be scored. A System One model leans towards
the first listed option (lead note, 2026-10-18), so the request lists a Choice question's options in an order
shuffled per call:
`shuffle` sorts the options by a 64-bit FNV-1a hash of the seed and the option, and the seed is the FNV-1a hash of
the request's redacted state text. The order is a permutation of the options (`shuffle_perm`), and the same state
gives the same order, so a logged request replays byte for byte.
-/
namespace Fw.Oracle

/-- **The CI-triage question**: why did this failed CI run fail? Options `flake`, `infra`, `real`, and the no-match
option `unknown`; an option keeps a threshold only when, on the held-out rows the policy advises as that option, the
one-sided 95 % Wilson lower bound of the precision is at least 9/10 and at least 5 of them are right
(`Fw.Oracle.certify`). The state fields are `job`, `step` and `log`. -/
def ciTriage : Question where
  name := "ci-triage"
  instructions := "A GitHub Actions run of a repository failed. The state holds the failing job and step, and the " ++
    "last lines of the failed step's log. Classify the cause of the failure."
  spec := .choice ["flake", "infra", "real", "unknown"] "unknown"
  criteria := [
    ("flake", "Nondeterministic: a timing race, a timeout of a slow test, or a resource that is usually there; " ++
      "the same commit would most likely pass on a rerun."),
    ("infra", "The CI platform or an external service failed: runner lost or out of disk, network or download " ++
      "error, rate limit, package registry or cache service down. Not caused by the repository's code."),
    ("real", "A deterministic failure caused by the repository's code, proofs, tests or configuration: a " ++
      "compile or type error, a failed assertion, a lint or check that reports a concrete problem."),
    ("unknown", "The log does not show enough to tell which of the other three it is.")]
  target := 9 / 10
  perOption := 5
  fields := ["job", "step", "log"]

/-- **The CI-triage answer space is well formed** (distinct options, the no-match option among them, 2 to 255 options). -/
theorem ciTriage_wf : ciTriage.spec.wf = true := by decide

/-- **Every option of the CI-triage question has a description, in option order.** -/
theorem ciTriage_criteria : ciTriage.criteria.map Prod.fst = ciTriage.spec.keys := by decide

/-- The no-match option of the incident question. -/
def noClass : String := "none"

/-- The 13 mistake classes the incident ledger's rows carry, each with what tells it apart (restated from
`research/mistakes/ledger.json`). `c-mathdoc` and `c-principle` label no incident, so they are not offered. -/
def incidentClasses : List (String × String) := [
  ("c-orphan-wait", "A wait loop or child process with no bound and no owner: a shell loop polls for text that " ++
    "never appears, or a background child outlives the task that started it."),
  ("c-order-derived", "State stored by hand or derived from event order or a naming convention instead of from " ++
    "recorded facts, so the same facts in another order give another state."),
  ("c-shared-no-lock", "A shared file, branch, directory or scratch name with no owner or lock, so parallel work " ++
    "collides or overwrites."),
  ("c-quota", "A shared capacity (API token rate limit, CI runner slots, CPU, disk, agent count, context) used " ++
    "with no budget at the point of use."),
  ("c-proxy-verdict", "A success signal (exit code, job conclusion, green check) taken as the verdict although " ++
    "it does not entail it."),
  ("c-identity-heuristic", "Who or what something is (an agent, a process, an owner, a role) inferred from " ++
    "command-line text, names or empty fields instead of a recorded identity."),
  ("c-late-check", "A cheap static check that existed or was trivial ran only in CI or at land, not on the " ++
    "changed files before the commit."),
  ("c-unearned-claim", "A claim given a status or a number it had not earned: called confirmed or measured " ++
    "without a source, a run or a proof behind it."),
  ("c-sample-validity", "A measurement used although its validity precondition (settled, aligned, same clock, " ++
    "same unit, same context) did not hold."),
  ("c-env-assume", "An unverified belief about a tool, flag, shell, platform, cache or runtime acted on without " ++
    "a cheap probe first."),
  ("c-spec-gap", "An instruction or task spec under-specified or not checked against what the task must " ++
    "deliver."),
  ("c-handcopy", "A value or model copied by hand with no generated or golden link to its source of truth."),
  ("c-policy-prose", "A safety or privacy rule written only in prose and not enforced at the tool boundary.")]

/-- **The incident-class question** (set D1): which mistake class does this incident belong to? The options are the
13 classes (`incidentClasses`) and the no-match option `none`; the state fields are the incident's `title`,
`symptom` and `cause`. Calibration constants as for CI triage: target 9/10, at least 5 right per option. -/
def incidentClass : Question where
  name := "incident-class"
  instructions := "An incident from a software project's incident ledger: an agent or a script made a mistake. The " ++
    "state holds its title, the symptom seen and the cause found. Classify the incident by the kind of mistake " ++
    "that caused it."
  spec := .choice (incidentClasses.map (·.1) ++ [noClass]) noClass
  criteria := incidentClasses ++ [(noClass, "None of the other classes fits this incident.")]
  target := 9 / 10
  perOption := 5
  fields := ["title", "symptom", "cause"]

/-- **The incident question's answer space is well formed** (14 distinct options, the no-match option among them). -/
theorem incidentClass_wf : incidentClass.spec.wf = true := by decide

/-- **Every option of the incident question has a description, in option order.** -/
theorem incidentClass_criteria : incidentClass.criteria.map Prod.fst = incidentClass.spec.keys := by decide

/-- **Every class offered is a label set D1 can carry** (`Labels.d1Label` keeps it). -/
theorem incidentClass_labels : ∀ c ∈ incidentClasses.map (·.1), Labels.d1Label c = some c := by decide

/-- The no-match option of the severity question. -/
def noGrade : String := "unclear"

/-- **The finding-severity question** (set D2): how serious is this review finding for the task's pinned unit? The
options are the three grades of the review rules and the no-match option `unclear`; the state fields are the
finding, where it points, the task text, the pinned unit and the accepted limits. -/
def findingSeverity : Question where
  name := "finding-severity"
  instructions := "A reviewer checked a builder's delivery of a task and wrote this finding. The state holds the " ++
    "finding, where it points, the task text, the task's pinned unit of decision and its accepted limits. Grade " ++
    "the finding by what it means for that pinned unit."
  spec := .choice ["blocker", "fix-before-land", "follow-up", noGrade] noGrade
  criteria := [
    ("blocker", "The pinned unit is wrong, unproved or undelivered: the delivery cannot land until the builder " ++
      "redoes this part."),
    ("fix-before-land", "Inside the pinned unit but small: an exact text change (a stale line, a wrong number, a " ++
      "missing word) that someone can apply as written before landing."),
    ("follow-up", "Outside the pinned unit or within an accepted limit: later work that does not stop the landing."),
    (noGrade, "The finding does not say enough to tell which of the other three it is.")]
  target := 9 / 10
  perOption := 5
  fields := ["finding", "where", "task", "unit", "limits"]

/-- **The severity question's answer space is well formed.** -/
theorem findingSeverity_wf : findingSeverity.spec.wf = true := by decide

/-- **Every option of the severity question has a description, in option order.** -/
theorem findingSeverity_criteria : findingSeverity.criteria.map Prod.fst = findingSeverity.spec.keys := by decide

/-- **The grades offered are exactly the grade names set D2 labels with** (`Labels.exactWords`), in order. -/
theorem findingSeverity_labels : findingSeverity.spec.keys.filter (· != noGrade) = Labels.exactWords := by decide

/-- The registered questions. -/
def questions : List Question := [ciTriage, incidentClass, findingSeverity]

/-- The registered question with this name, if any. -/
def question (x : String) : Option Question := questions.find? (·.name == x)

/-- **The registered names are distinct**, so a name finds exactly its question. -/
theorem questions_names_nodup : (questions.map (·.name)).Nodup := by decide

/-- 64-bit FNV-1a over the code points of a text (offset basis 14695981039346656037, prime 1099511628211). -/
def fnv (s : String) : Nat :=
  s.toList.foldl (fun h c => ((h ^^^ c.toNat) * 1099511628211) % 2 ^ 64) 14695981039346656037

/-- The sort key of an option under a seed: the hash of the seed's decimal text, `:`, and the option. -/
def shuffleKey (seed : Nat) (o : String) : Nat := fnv (toString seed ++ ":" ++ o)

/-- **The seeded shuffle**: the options sorted by their key under the seed (a stable merge sort; equal keys keep
their order). -/
def shuffle (seed : Nat) (os : List String) : List String :=
  os.mergeSort fun a b => decide (shuffleKey seed a ≤ shuffleKey seed b)

/-- **The shuffle is a permutation**: every option is listed, each exactly as often as before. -/
theorem shuffle_perm (seed : Nat) (os : List String) : (shuffle seed os).Perm os :=
  List.mergeSort_perm _ _

#guard fnv "" == 14695981039346656037 && fnv "a" == 12638187200555641996
#guard (shuffle 1 ["flake", "infra", "real", "unknown"]).length == 4
#guard (List.range 8).any fun s => (shuffle s ["flake", "infra", "real", "unknown"]).head? != some "flake"
#guard (question "ci-triage").map (·.name) == some "ci-triage"
#guard (question "ci-triage").map (·.perOption) == some 5
#guard (question "nope").isNone
#guard (question "incident-class").map (·.fields) == some ["title", "symptom", "cause"]
#guard (incidentClass.spec.keys.length, findingSeverity.spec.keys.length) == (14, 4)

end Fw.Oracle
