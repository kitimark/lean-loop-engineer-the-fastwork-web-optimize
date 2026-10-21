import Fw.Oracle.Core
/-!
# Fw.Oracle.Questions: the registered questions, and the seeded option order of a request

`questions` is the registry the wire looks names up in. It holds one question, `ciTriage` (why a failed CI run
failed); the questions of the trial's replay sets are registered with those sets. A System One model leans towards
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
(`Fw.Oracle.certify`). The state fields are `job`, `step` and `log`.

$$\mathrm{ciTriage}.\mathit{spec} = \mathrm{choice}([\texttt{flake}, \texttt{infra}, \texttt{real}, \texttt{unknown}], \texttt{unknown}),\quad q = 9/10,\quad k = 5,\quad \mathit{fields} = [\texttt{job}, \texttt{step}, \texttt{log}]$$ -/
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

/-- **The CI-triage answer space is well formed** (distinct options, the no-match option among them, 2 to 255 options).

$$\mathrm{wf}(\mathrm{ciTriage}.\mathit{spec}) = \top$$ -/
theorem ciTriage_wf : ciTriage.spec.wf = true := by decide

/-- **Every option of the CI-triage question has a description, in option order.**

$$\mathrm{map}(\pi_1, \mathrm{ciTriage}.\mathit{criteria}) = \mathrm{keys}(\mathrm{ciTriage}.\mathit{spec})$$ -/
theorem ciTriage_criteria : ciTriage.criteria.map Prod.fst = ciTriage.spec.keys := by decide

/-- The registered questions.

$$\mathrm{questions} = [\mathrm{ciTriage}]$$ -/
def questions : List Question := [ciTriage]

/-- The registered question with this name, if any.

$$\mathrm{question}(x) = \text{the first } Q \in \mathrm{questions} \text{ with } Q.\mathit{name} = x, \text{ else } \bot$$ -/
def question (x : String) : Option Question := questions.find? (·.name == x)

/-- **The registered names are distinct**, so a name finds exactly its question.

$$\mathrm{nodup}([\, Q.\mathit{name} : Q \in \mathrm{questions} \,])$$ -/
theorem questions_names_nodup : (questions.map (·.name)).Nodup := by decide

/-- 64-bit FNV-1a over the code points of a text (offset basis 14695981039346656037, prime 1099511628211).

$$h_0 = 14695981039346656037,\quad h_{i+1} = ((h_i \oplus c_i) \cdot 1099511628211) \bmod 2^{64},\quad \mathrm{fnv}(s) = h_{|s|}$$ -/
def fnv (s : String) : Nat :=
  s.toList.foldl (fun h c => ((h ^^^ c.toNat) * 1099511628211) % 2 ^ 64) 14695981039346656037

/-- The sort key of an option under a seed: the hash of the seed's decimal text, `:`, and the option.

$$\kappa(\sigma, o) = \mathrm{fnv}(\mathrm{str}(\sigma) \mathbin{+\!\!+} \texttt{:} \mathbin{+\!\!+} o)$$ -/
def shuffleKey (seed : Nat) (o : String) : Nat := fnv (toString seed ++ ":" ++ o)

/-- **The seeded shuffle**: the options sorted by their key under the seed (a stable merge sort; equal keys keep
their order).

$$\mathrm{shuffle}(\sigma, O) = \mathrm{mergeSort}_{\le}(O)\ \text{by}\ \kappa(\sigma, \cdot)$$ -/
def shuffle (seed : Nat) (os : List String) : List String :=
  os.mergeSort fun a b => decide (shuffleKey seed a ≤ shuffleKey seed b)

/-- **The shuffle is a permutation**: every option is listed, each exactly as often as before.

$$\forall \sigma, O:\ \mathrm{shuffle}(\sigma, O) \sim O$$ -/
theorem shuffle_perm (seed : Nat) (os : List String) : (shuffle seed os).Perm os :=
  List.mergeSort_perm _ _

#guard fnv "" == 14695981039346656037 && fnv "a" == 12638187200555641996
#guard (shuffle 1 ["flake", "infra", "real", "unknown"]).length == 4
#guard (List.range 8).any fun s => (shuffle s ["flake", "infra", "real", "unknown"]).head? != some "flake"
#guard (question "ci-triage").map (·.name) == some "ci-triage"
#guard (question "ci-triage").map (·.perOption) == some 5
#guard (question "nope").isNone

end Fw.Oracle
