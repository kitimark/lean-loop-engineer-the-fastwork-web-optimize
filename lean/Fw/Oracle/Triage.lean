import Fw.Oracle.Core
import Fw.Oracle.Redact
/-!
# Fw.Oracle.Triage: the registered questions, and the CI-triage question

A `Question` is everything the client sends besides the state: a name (the question id on the wire), the
instructions, the typed answer space (`Spec`), the option descriptions, and the calibration settings (precision
target, least number of covered rows). Questions live here, in Lean, so the answer space the policy reasons about is
the one that is sent. The model is pinned to a versioned id (`model`): aliases move, so a logged reply replays only
against the same version.

`ciTriage` asks why a failed CI run failed: `flake`, `infra`, `real`, or the no-match option `unknown`. Its state is
built by `triageState` from the workflow name and the lines of `gh run view --log-failed`: the job and failing step
of the last line, and the text of the last 60 lines (columns, timestamp and colour codes removed). The client
redacts that state before anything else.
-/
namespace Fw.Oracle

/-- The pinned model version (CONFIRMED at https://docs.typesafe.ai/models.md, read 2026-10-18: `jev-latest` is
`jev-1.13.0`, and aliases move, so pin a versioned id).

$$\mathrm{model} = \texttt{jev-1.13.0}$$ -/
def model : String := "jev-1.13.0"

/-- A registered question: wire id, instructions, answer space, option descriptions (choice options, or the `true` and
`false` meanings of a noul; score levels are the descriptions in the spec), precision target and least covered rows
for calibration.

$$\mathrm{Question} = \mathrm{String} \times \mathrm{String} \times \mathrm{Spec} \times (\mathrm{String} \times \mathrm{String})^{*} \times \mathbb{Q} \times \mathbb{N}$$ -/
structure Question where
  name : String
  instructions : String
  spec : Spec
  criteria : List (String × String)
  target : Rat
  minRows : Nat
deriving Repr

/-- **The CI-triage question**: why did this failed CI run fail? Options `flake`, `infra`, `real`, and the no-match
option `unknown`; calibration wants precision 9/10 over at least 10 covered rows.

$$\mathrm{ciTriage}.\mathit{spec} = \mathrm{choice}([\texttt{flake}, \texttt{infra}, \texttt{real}, \texttt{unknown}], \texttt{unknown}),\quad q = 9/10,\quad n = 10$$ -/
def ciTriage : Question where
  name := "ci-triage"
  instructions := "A GitHub Actions run of a repository failed. The state holds the workflow name, the failing job and " ++
    "step, and the last lines of the failed step's log. Classify the cause of the failure."
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
  minRows := 10

/-- The registered questions.

$$\mathrm{questions} = [\mathrm{ciTriage}]$$ -/
def questions : List Question := [ciTriage]

/-- The registered question with this name, if any.

$$\mathrm{question}(x) = \text{the first } Q \in \mathrm{questions} \text{ with } Q.\mathit{name} = x, \text{ else } \bot$$ -/
def question (x : String) : Option Question := questions.find? (·.name == x)

/-- **The CI-triage answer space is well formed** (distinct options, the no-match option among them, 2 to 255 options).

$$\mathrm{wf}(\mathrm{ciTriage}.\mathit{spec}) = \top$$ -/
theorem ciTriage_wf : ciTriage.spec.wf = true := by decide

/-- **Every option of the CI-triage question has a description, in option order.**

$$\mathrm{map}(\pi_1, \mathrm{ciTriage}.\mathit{criteria}) = \mathrm{keys}(\mathrm{ciTriage}.\mathit{spec})$$ -/
theorem ciTriage_criteria : ciTriage.criteria.map Prod.fst = ciTriage.spec.keys := by decide

/-- The last `n` elements of a list (all of it when shorter).

$$\mathrm{tail}_n(L) = \mathrm{drop}(|L| \mathbin{\dot-} n, L)$$ -/
def tailN {α : Type} (n : Nat) (l : List α) : List α := l.drop (l.length - n)

/-- **The tail has `min(n, |L|)` elements.**

$$\forall n, L:\ |\mathrm{tail}_n(L)| = \min(n, |L|)$$ -/
theorem tailN_length {α : Type} (n : Nat) (l : List α) : (tailN n l).length = min n l.length := by
  simp only [tailN, List.length_drop]; omega

/-- Remove terminal colour codes: from an escape character up to and including the next letter.

$$\mathrm{stripAnsi}(e, c :: cs) = \begin{cases} \mathrm{stripAnsi}(\top, cs) & \lnot e,\ c = \mathrm{ESC} \\ c :: \mathrm{stripAnsi}(\bot, cs) & \lnot e,\ c \ne \mathrm{ESC} \\ \mathrm{stripAnsi}(\bot, cs) & e,\ c \text{ a letter} \\ \mathrm{stripAnsi}(\top, cs) & e,\ c \text{ not a letter} \end{cases},\quad \mathrm{stripAnsi}(e, [\,]) = [\,]$$ -/
def stripAnsi : Bool → List Char → List Char
  | _, [] => []
  | false, c :: cs => if c == '\x1b' then stripAnsi true cs else c :: stripAnsi false cs
  | true, c :: cs => if c.isAlpha then stripAnsi false cs else stripAnsi true cs

/-- Drop a leading timestamp: the first space-free word, when it starts with a digit and ends in `Z`, and the space
after it.

$$\mathrm{dropStamp}(s) = \begin{cases} \mathrm{drop}(|w| + 1, s) & w = \mathrm{takeWhile}(\ne \texttt{' '}, s),\ w_0 \text{ a digit},\ w \text{ ends in } \texttt{Z} \\ s & \text{otherwise} \end{cases}$$ -/
def dropStamp (s : List Char) : List Char :=
  let w := s.takeWhile (· != ' ')
  match w.head?, w.getLast? with
  | some a, some 'Z' => if a.isDigit then s.drop (w.length + 1) else s
  | _, _ => s

/-- The text of one `--log-failed` line: the part after the job and step columns (the whole line when it has fewer
than two tabs), without its timestamp and colour codes.

$$\mathrm{logText}(\ell) = \mathrm{stripAnsi}(\bot, \mathrm{dropStamp}(t)),\quad t = \begin{cases} c_3 \cdots & \ell = c_1 \mathbin{\texttt{\textbackslash t}} c_2 \mathbin{\texttt{\textbackslash t}} c_3 \cdots \\ \ell & \text{otherwise} \end{cases}$$ -/
def logText (l : String) : String :=
  let t := match l.splitOn "\t" with
    | _ :: _ :: rest => "\t".intercalate rest
    | _ => l
  String.ofList (stripAnsi false (dropStamp t.toList))

/-- How many log lines the CI-triage state keeps.

$$\mathrm{logLines} = 60$$ -/
def logLines : Nat := 60

/-- **The CI-triage state**: the workflow name; the job and step columns of the last non-empty log line (empty when
there is none); and the text of the last 60 non-empty lines.

$$\mathrm{triageState}(w, L) = [(\texttt{workflow}, [w]), (\texttt{job}, [j]), (\texttt{step}, [p]), (\texttt{log}, \mathrm{map}(\mathrm{logText}, \mathrm{tail}_{60}(L')))]$$
where $L' = [\ell \in L : \ell \ne \texttt{""}]$ and $(j, p)$ are the first two tab columns of the last line of $L'$ (empty when $L' = [\,]$ or a column is missing). -/
def triageState (workflow : String) (raw : List String) : State :=
  let ls := raw.filter (· != "")
  let c := (ls.getLast?.getD "").splitOn "\t"
  let (job, step) := match c with
    | j :: p :: _ => (j, p)
    | _ => ("", "")
  [("workflow", [workflow]), ("job", [job]), ("step", [step]), ("log", (tailN logLines ls).map logText)]

/-- **The CI-triage state holds at most 60 log lines.**

$$\forall w, L:\ \forall (\texttt{log}, X) \in \mathrm{triageState}(w, L):\ |X| \le 60$$ -/
theorem triageState_log (w : String) (raw : List String) :
    ∀ x ∈ triageState w raw, x.1 = "log" → x.2.length ≤ logLines := by
  intro x hx hk
  simp only [triageState, List.mem_cons, List.not_mem_nil, or_false] at hx
  rcases hx with rfl | rfl | rfl | rfl <;> simp_all [tailN_length, Nat.min_le_left]

#guard logText "build\tRun tests\t2026-10-18T06:07:14.4719238Z error: x failed" == "error: x failed"
#guard logText "build\tRun\t2026-10-18T06:07:14Z \x1b[31mred\x1b[0m done" == "red done"
#guard logText "no tabs here" == "no tabs here"
#guard logText "a\tb\t12 apples Z" == "12 apples Z"
#guard (triageState "lean" ["j\ts\t2026-10-18T06:07:14Z one", "", "j\ts2\t2026-10-18T06:07:15Z two"]) ==
  [("workflow", ["lean"]), ("job", ["j"]), ("step", ["s2"]), ("log", ["one", "two"])]
#guard (triageState "w" []) == [("workflow", ["w"]), ("job", [""]), ("step", [""]), ("log", [])]
#guard ((triageState "w" ((List.range 100).map fun i => s!"j\ts\t{i}")).lookup "log").map List.length == some 60
#guard (question "ci-triage").map (·.name) == some "ci-triage"
#guard (question "nope").isNone

end Fw.Oracle
