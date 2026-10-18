import Lean.Data.Json

/-!
# Salvage of a builder that ends without a structured result (task `workflow-salvage`)

A workflow stage runs one builder agent in its own worktree and expects a structured result. When the builder exits
without one (batch-5: `gate-shard-balance`), the stage has nothing to verify and the worktree holds unrecorded work.
`decide` is the rule for that one case. The glue (`apps/runner/src/workflow/salvage.ts`) gathers the facts (`Facts`:
the task id, whether a result came back, whether the worktree is dirty, how many commits it is ahead of its base) and
performs the `Out` it gets: a WIP commit of the worktree and one `handback` event.

Threat model: a builder exit without a result always leaves a WIP commit of its worktree and a handback event, and a
builder exit with a result leaves nothing. Accepted limits: no retry of the builder (`salvage_iff_missing`), and the rule
does not judge the work, it only names the state (`dirty`, `committed`, `empty`) from the facts.
-/
namespace Fw.Ops.Salvage

/-- What the glue observed. `hasResult` is true when the builder returned a structured result.
$$\mathrm{Facts} = \mathrm{String} \times \mathbb B \times \mathbb B \times \mathbb N \quad (\mathit{task}, \mathit{hasResult}, \mathit{dirty}, \mathit{ahead})$$ -/
structure Facts where
  task : String
  hasResult : Bool
  dirty : Bool
  ahead : Nat
deriving Repr, DecidableEq

/-- What the glue must do: run the salvage at all, commit, allow an empty commit, append a handback event, and the
state and commit message to use.
$$\mathrm{Out} = (\mathit{salvage}, \mathit{commit}, \mathit{allowEmpty}, \mathit{handback}, \mathit{state}, \mathit{message})$$ -/
structure Out where
  salvage : Bool
  commit : Bool
  allowEmpty : Bool
  handback : Bool
  state : String
  message : String
deriving Repr, DecidableEq

/-- A task id is a non-empty string of lowercase letters, digits and `-`.
$$\mathrm{idOk}(t) \iff t \ne \varepsilon \land \forall c \in t.\ c \in [a\text{-}z0\text{-}9\text{-}]$$ -/
def idOk (t : String) : Bool :=
  t != "" && t.all fun c => (c.isLower && c.isAlpha) || c.isDigit || c == '-'

/-- The state of the worktree, named from the facts only.
$$\mathrm{stateOf}(d, a) = \begin{cases}\mathtt{dirty} & d\\ \mathtt{committed} & \lnot d \land a > 0\\ \mathtt{empty} & \text{otherwise}\end{cases}$$ -/
def stateOf (dirty : Bool) (ahead : Nat) : String :=
  if dirty then "dirty" else if ahead > 0 then "committed" else "empty"

/-- The salvage decision.
the tuple is ordered (salvage, commit, allowEmpty, handback, state, message), and $\tau$ is the task id or `unknown`.
$$\mathrm{decide}(f) = \begin{cases}(\bot,\bot,\bot,\bot,\varepsilon,\varepsilon) & f.\mathit{hasResult}\\ (\top,\top,\lnot f.\mathit{dirty},\top,\mathrm{stateOf}(f.\mathit{dirty}, f.\mathit{ahead}),\ \texttt{"WIP salvage "} \Vert \tau \Vert \texttt{": builder exited without a result"}) & \text{otherwise}\end{cases},\quad \tau = \begin{cases} f.\mathit{task} & \mathrm{idOk}(f.\mathit{task})\\ \texttt{"unknown"} & \text{otherwise}\end{cases}$$ -/
def decide (f : Facts) : Out :=
  if f.hasResult then
    { salvage := false, commit := false, allowEmpty := false, handback := false, state := "", message := "" }
  else
    { salvage := true, commit := true, allowEmpty := !f.dirty, handback := true,
      state := stateOf f.dirty f.ahead,
      message := s!"WIP salvage {if idOk f.task then f.task else "unknown"}: builder exited without a result" }

/-- A builder that returned a result is left alone.
$$\mathit{hasResult} \Rightarrow \lnot\mathit{salvage} \land \lnot\mathit{commit} \land \lnot\mathit{handback}$$ -/
theorem result_untouched (f : Facts) (h : f.hasResult = true) :
    (decide f).salvage = false ∧ (decide f).commit = false ∧ (decide f).handback = false := by
  simp [decide, h]

/-- A builder that returned no result always gets a WIP commit and a handback event.
$$\lnot\mathit{hasResult} \Rightarrow \mathit{commit} \land \mathit{handback}$$ -/
theorem missing_commits_and_hands_back (f : Facts) (h : f.hasResult = false) :
    (decide f).commit = true ∧ (decide f).handback = true := by
  simp [decide, h]

/-- An empty commit is allowed exactly when the worktree is clean, so a dirty tree is never recorded as empty.
$$\lnot\mathit{hasResult} \Rightarrow (\mathit{allowEmpty} = \lnot\mathit{dirty})$$ -/
theorem empty_iff_clean (f : Facts) (h : f.hasResult = false) :
    (decide f).allowEmpty = !f.dirty := by
  simp [decide, h]

/-- The salvage runs exactly when the result is missing. That no retry happens follows from `Out` having no retry field,
not from this statement.
$$\mathit{salvage} = \lnot\mathit{hasResult}$$ -/
theorem salvage_iff_missing (f : Facts) : (decide f).salvage = !f.hasResult := by
  cases h : f.hasResult <;> simp [decide, h]

/-- The state depends on the dirty flag and the ahead count only, not on the task or the work itself.
$$\lnot f.\mathit{hasResult} \Rightarrow \mathrm{decide}(f).\mathit{state} = \mathrm{stateOf}(f.\mathit{dirty}, f.\mathit{ahead})$$ -/
theorem state_from_facts (f : Facts) (h : f.hasResult = false) :
    (decide f).state = stateOf f.dirty f.ahead := by
  simp [decide, h]

#guard (decide ⟨"a-1", true, true, 3⟩).commit == false
#guard (decide ⟨"a-1", false, true, 0⟩).state == "dirty"
#guard (decide ⟨"a-1", false, false, 2⟩).state == "committed"
#guard (decide ⟨"a-1", false, false, 0⟩).allowEmpty == true
#guard (decide ⟨"A b", false, false, 0⟩).message == "WIP salvage unknown: builder exited without a result"

open Lean in
/-- A golden case as JSON: the request facts and `decide` of them.
$$\mathrm{caseJson}(n, f) = \{\mathit{name}: n,\ \mathit{request}: \{\mathit{op}: \texttt{"ops.salvage"}\} \cup f,\ \mathit{response}: \mathrm{decide}(f)\}$$ -/
def caseJson (name : String) (f : Facts) : Json :=
  let o := decide f
  Json.mkObj [("name", .str name),
    ("request", Json.mkObj [("op", .str "ops.salvage"), ("task", .str f.task), ("hasResult", .bool f.hasResult),
      ("dirty", .bool f.dirty), ("ahead", toJson f.ahead)]),
    ("response", Json.mkObj [("salvage", .bool o.salvage), ("commit", .bool o.commit), ("allowEmpty", .bool o.allowEmpty),
      ("handback", .bool o.handback), ("state", .str o.state), ("message", .str o.message)])]

/-- The golden cases, covering result or none, dirty or clean, commits or none, and bad task ids.
$$\mathrm{cases} \in \mathrm{List}(\mathrm{String} \times \mathrm{Facts}),\ |\mathrm{cases}| = 8$$ -/
def cases : List (String × Facts) := [
  ("a result came back: nothing to do", ⟨"gate-shard-balance", true, false, 2⟩),
  ("a result came back and the tree is dirty: still left alone", ⟨"gate-shard-balance", true, true, 0⟩),
  ("no result, dirty tree", ⟨"gate-shard-balance", false, true, 0⟩),
  ("no result, dirty tree with commits", ⟨"gate-shard-balance", false, true, 4⟩),
  ("no result, clean tree with commits", ⟨"gate-shard-balance", false, false, 4⟩),
  ("no result, clean tree, no commits: empty commit", ⟨"gate-shard-balance", false, false, 0⟩),
  ("no result, task id outside the allowlist", ⟨"Gate Shard; rm", false, true, 1⟩),
  ("no result, empty task id", ⟨"", false, false, 0⟩)]

open Lean in
/-- The golden text, one JSON line per case.
$$\mathrm{goldenText} = \mathop{\Vert}_{(n,f) \in \mathrm{cases}} \mathrm{caseJson}(n, f)\ \Vert\ \texttt{"\textbackslash n"}$$ -/
def goldenText : String :=
  String.join (cases.map fun (n, f) => (caseJson n f).compress ++ "\n")

end Fw.Ops.Salvage
