import Fw.Oracle.Core
import Fw.Oracle.Labels
/-! The registered questions and the seeded option order of a request. -/
namespace Fw.Oracle

/-- The CI-triage question: why did this failed CI run fail? Options `flake`. -/
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

theorem ciTriage_wf : ciTriage.spec.wf = true := by decide

theorem ciTriage_criteria : ciTriage.criteria.map Prod.fst = ciTriage.spec.keys := by decide

/-- The no-match option of the incident question. -/
def noClass : String := "none"

/-- The 13 mistake classes of the incident ledger, with their criteria. -/
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

/-- The incident-class question of set D1. -/
def incidentClass : Question where
  name := "incident-class"
  instructions := "An incident from a software project's incident ledger: an agent or a script made a mistake. The " ++
    "state holds its title, the symptom seen and the cause found. Classify the incident by the kind of mistake " ++
    "that caused it."
  spec := .choice (incidentClasses.map (·.1) ++ [noClass]) noClass
  criteria := incidentClasses ++ [(noClass, "None of the other classes fits this incident.")]
  target := 9 / 10
  perOption := 5
  fields := ["title", "symptom", "cause", "files"]

theorem incidentClass_wf : incidentClass.spec.wf = true := by decide

theorem incidentClass_criteria : incidentClass.criteria.map Prod.fst = incidentClass.spec.keys := by decide

theorem incidentClass_labels : ∀ c ∈ incidentClasses.map (·.1), Labels.d1Label c = some c := by decide

/-- The no-match option of the severity question. -/
def noGrade : String := "unclear"

/-- The finding-severity question of set D2. -/
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

theorem findingSeverity_wf : findingSeverity.spec.wf = true := by decide

theorem findingSeverity_criteria : findingSeverity.criteria.map Prod.fst = findingSeverity.spec.keys := by decide

theorem findingSeverity_labels : findingSeverity.spec.keys.filter (· != noGrade) = Labels.exactWords := by decide

/-- The J-pick step-1 question of jev-retrieval-trace: which one candidate file, named by its slot, would most help
classify the incident, or none. -/
def filePick : Question where
  name := "file-pick"
  instructions := "An incident from a software project's incident ledger: an agent or a script made a mistake. The " ++
    "state holds its title, the symptom seen, the cause found, and the project's candidate source files at the " ++
    "incident's time, one per line as slot: path. A later question classifies the incident by the kind of mistake " ++
    "that caused it and sees the start of one file you pick here. Pick the one file whose text would most help that " ++
    "classification, or none if no file would help."
  spec := .choice ["f1", "f2", "f3", "f4", noClass] noClass
  criteria := [("f1", "The candidate file listed as f1."), ("f2", "The candidate file listed as f2."),
    ("f3", "The candidate file listed as f3."), ("f4", "The candidate file listed as f4."),
    (noClass, "No candidate file would help classify the incident.")]
  target := 9 / 10
  perOption := 5
  fields := ["title", "symptom", "cause", "candidates"]

theorem filePick_wf : filePick.spec.wf = true := by decide

theorem filePick_criteria : filePick.criteria.map Prod.fst = filePick.spec.keys := by decide

/-- The registered questions. -/
def questions : List Question := [ciTriage, incidentClass, findingSeverity, filePick]

/-- The registered question with this name, if any. -/
def question (x : String) : Option Question := questions.find? (·.name == x)

theorem questions_names_nodup : (questions.map (·.name)).Nodup := by decide

/-- 64-bit FNV-1a over the code points of a text (offset basis 14695981039346656037, prime 1099511628211). -/
def fnv (s : String) : Nat :=
  s.toList.foldl (fun h c => ((h ^^^ c.toNat) * 1099511628211) % 2 ^ 64) 14695981039346656037

def shuffleKey (seed : Nat) (o : String) : Nat := fnv (toString seed ++ ":" ++ o)

/-- The seeded shuffle: the options sorted by their key under the seed. -/
def shuffle (seed : Nat) (os : List String) : List String :=
  os.mergeSort fun a b => decide (shuffleKey seed a ≤ shuffleKey seed b)

theorem shuffle_perm (seed : Nat) (os : List String) : (shuffle seed os).Perm os :=
  List.mergeSort_perm _ _

#guard fnv "" == 14695981039346656037 && fnv "a" == 12638187200555641996
#guard (shuffle 1 ["flake", "infra", "real", "unknown"]).length == 4
#guard (List.range 8).any fun s => (shuffle s ["flake", "infra", "real", "unknown"]).head? != some "flake"
#guard (question "ci-triage").map (·.name) == some "ci-triage"
#guard (question "ci-triage").map (·.perOption) == some 5
#guard (question "nope").isNone
#guard (question "incident-class").map (·.fields) == some ["title", "symptom", "cause", "files"]
#guard (incidentClass.spec.keys.length, findingSeverity.spec.keys.length) == (14, 4)

end Fw.Oracle
