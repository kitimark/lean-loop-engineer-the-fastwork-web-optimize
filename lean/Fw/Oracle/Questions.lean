import Fw.Oracle.Core
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

/-- The registered questions. -/
def questions : List Question := [ciTriage]

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

end Fw.Oracle
