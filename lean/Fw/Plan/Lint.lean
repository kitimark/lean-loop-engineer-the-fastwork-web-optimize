import Fw.Plan.Graph
import Fw.Plan.Trailer
/-!
# `plan.lint`: what is wrong with the work graph file, before `fw plan sync` or a landing finds out

A pure check over the rows of `docs/team/work-graph.json` and the `Task:` trailers of main
(task `pa-evidence-lint`). Per task it reports codes with a severity:

| code | severity | holds when |
|---|---|---|
| `unknownDep` | error | a dep id is not a task id |
| `evOther` | error | evidence is none of: main commit, CI run id, user decision, prose that names a commit |
| `evLong` | error | evidence is longer than 64 characters |
| `trailerNoEvidence` | error | a `Task:` trailer on main names the task, the row has no evidence |
| `evNotOnMain` | error | the evidence is a commit id that is not an ancestor of main (`git merge-base --is-ancestor`, fact from the glue; task `evidence-on-main`) |
| `evUser` | warn | evidence is a user decision (`user…`): allowed, tagged |
| `evProse` | warn | evidence is prose that names a commit (`abc1234: …`): allowed, tagged |
| `longTitle` | warn | the title is longer than 200 characters (sync clips it) |
| `evidenceNoTrailer` | info | the row has evidence, no trailer on main names it (normal before trailers) |

One graph-wide error, `cycle`, when the dependency graph has a cycle (`acyclicB`).
-/
namespace Fw.Plan.Lint
open Fw.Plan

/-- The kind of an evidence string.

$$\mathrm{EvKind} = \{\mathrm{commit}, \mathrm{run}, \mathrm{user}, \mathrm{prose}, \mathrm{other}\}$$
-/
inductive EvKind | commit | run | user | prose | other
deriving DecidableEq, Repr

/-- Lowercase hex digit.

$$\operatorname{isHex}(c) \iff c \in [0\text{-}9a\text{-}f]$$
-/
def isHex (c : Char) : Bool := c.isDigit || ('a' ≤ c && c ≤ 'f')

/-- A commit id: 7 to 40 lowercase hex characters.

$$\operatorname{isCommit}(s) \iff 7 \le |s| \le 40 \land \forall c \in s:\ c \in [0\text{-}9a\text{-}f]$$
-/
def isCommit (s : String) : Bool := 7 ≤ s.length && s.length ≤ 40 && s.toList.all isHex

/-- A CI run id: 8 or more decimal digits.

$$\operatorname{isRun}(s) \iff |s| \ge 8 \land \forall c \in s:\ c \in [0\text{-}9]$$
-/
def isRun (s : String) : Bool := 8 ≤ s.length && s.toList.all Char.isDigit

/-- Prose that names a commit: some maximal alphanumeric run is a commit id containing a digit.

$$\operatorname{hasCommitToken}(s) \iff \exists w \in \operatorname{words}(s):\ \operatorname{isCommit}(w) \land \exists c \in w:\ c \in [0\text{-}9]$$
-/
def hasCommitToken (s : String) : Bool :=
  (s.toList.splitOnP (fun c => !c.isAlphanum)).any fun w =>
    isCommit (String.ofList w) && w.any Char.isDigit

/-- The kind of an evidence string.

$$\operatorname{kind}(s) = \begin{cases}\mathrm{run} & \operatorname{isRun}(s)\\ \mathrm{commit} & \operatorname{isCommit}(s)\\ \mathrm{user} & s \text{ starts with } \texttt{user}\\ \mathrm{prose} & \operatorname{hasCommitToken}(s)\\ \mathrm{other} & \text{otherwise}\end{cases}$$

Checked in this order.
-/
def evKind (s : String) : EvKind :=
  if isRun s then .run else if isCommit s then .commit
  else if s.startsWith "user" then .user else if hasCommitToken s then .prose else .other

/-- A lint code.

$$\mathrm{Code} = \{\mathrm{unknownDep}, \mathrm{evOther}, \mathrm{evLong}, \mathrm{trailerNoEvidence}, \mathrm{evNotOnMain}, \mathrm{evUser}, \mathrm{evProse}, \mathrm{longTitle}, \mathrm{evidenceNoTrailer}\}$$
-/
inductive Code
  | unknownDep | evOther | evLong | trailerNoEvidence | evNotOnMain | evUser | evProse | longTitle
  | evidenceNoTrailer
deriving DecidableEq, Repr

/-- Every code, in report order.

$$\mathrm{Codes} = [\mathrm{unknownDep}, \mathrm{evOther}, \mathrm{evLong}, \mathrm{trailerNoEvidence}, \mathrm{evNotOnMain}, \mathrm{evUser}, \mathrm{evProse}, \mathrm{longTitle}, \mathrm{evidenceNoTrailer}]$$
-/
def Code.all : List Code :=
  [.unknownDep, .evOther, .evLong, .trailerNoEvidence, .evNotOnMain, .evUser, .evProse, .longTitle,
    .evidenceNoTrailer]

/-- The name of a code (the wire string).

$$\operatorname{name}(k) = \text{the constructor name of } k$$
-/
def Code.name : Code → String
  | .unknownDep => "unknownDep" | .evOther => "evOther" | .evLong => "evLong"
  | .trailerNoEvidence => "trailerNoEvidence" | .evNotOnMain => "evNotOnMain"
  | .evUser => "evUser" | .evProse => "evProse"
  | .longTitle => "longTitle" | .evidenceNoTrailer => "evidenceNoTrailer"

/-- The severity of a code: `error`, `warn` or `info`.

$$\operatorname{sev}(k) = \begin{cases}\mathrm{error} & k \in \{\mathrm{unknownDep}, \mathrm{evOther}, \mathrm{evLong}, \mathrm{trailerNoEvidence}, \mathrm{evNotOnMain}\}\\ \mathrm{warn} & k \in \{\mathrm{evUser}, \mathrm{evProse}, \mathrm{longTitle}\}\\ \mathrm{info} & k = \mathrm{evidenceNoTrailer}\end{cases}$$
-/
def Code.severity : Code → String
  | .unknownDep | .evOther | .evLong | .trailerNoEvidence | .evNotOnMain => "error"
  | .evUser | .evProse | .longTitle => "warn"
  | .evidenceNoTrailer => "info"

/-- What the check reads besides the row: every task id, the ids that `Task:` trailers on main name,
and `off`, the ids of the tasks whose evidence the glue found not to be an ancestor of main (default
empty: a task the glue did not name counts as on main).

$$\mathit{ctx} = (\mathit{ids}, \mathit{named}, \mathit{off})$$
-/
structure Ctx where
  ids   : List String
  named : List String
  off   : List String := []

/-- Does `code` hold for row `t`?

$$\begin{aligned}
\mathrm{unknownDep}(t) &\iff \exists d \in t.\mathit{deps}:\ d \notin \mathit{ids}\\
\mathrm{evOther}(t) &\iff t.\mathit{evidence} = e \land \operatorname{kind}(e) = \mathrm{other}\\
\mathrm{evLong}(t) &\iff t.\mathit{evidence} = e \land |e| > 64\\
\mathrm{trailerNoEvidence}(t) &\iff t.\mathit{id} \in \mathit{named} \land t.\mathit{evidence} = \bot\\
\mathrm{evNotOnMain}(t) &\iff t.\mathit{evidence} = e \land \operatorname{kind}(e) = \mathrm{commit} \land t.\mathit{id} \in \mathit{off}\\
\mathrm{evUser}(t) &\iff t.\mathit{evidence} = e \land \operatorname{kind}(e) = \mathrm{user}\\
\mathrm{evProse}(t) &\iff t.\mathit{evidence} = e \land \operatorname{kind}(e) = \mathrm{prose}\\
\mathrm{longTitle}(t) &\iff |t.\mathit{title}| > 200\\
\mathrm{evidenceNoTrailer}(t) &\iff t.\mathit{evidence} \ne \bot \land t.\mathit{id} \notin \mathit{named}
\end{aligned}$$
-/
def holds (c : Ctx) (t : Task) : Code → Bool
  | .unknownDep => t.deps.any (fun d => !c.ids.contains d)
  | .evOther => match t.evidence with | some e => evKind e == .other | none => false
  | .evLong => match t.evidence with | some e => decide (64 < e.length) | none => false
  | .trailerNoEvidence => c.named.contains t.id && t.evidence.isNone
  | .evNotOnMain => match t.evidence with
    | some e => evKind e == .commit && c.off.contains t.id
    | none => false
  | .evUser => match t.evidence with | some e => evKind e == .user | none => false
  | .evProse => match t.evidence with | some e => evKind e == .prose | none => false
  | .longTitle => decide (200 < t.title.length)
  | .evidenceNoTrailer => t.evidence.isSome && !c.named.contains t.id

/-- The codes that hold for a row.

$$\operatorname{codes}(t) = [\, k \in \mathrm{Codes} : \operatorname{holds}(t, k) \,]$$
-/
def codes (c : Ctx) (t : Task) : List Code := Code.all.filter (holds c t)

/-- **Each reported code holds, and each code that holds is reported.**

$$\forall t, k:\quad k \in \operatorname{codes}(t) \iff \operatorname{holds}(t, k)$$
-/
theorem mem_codes (c : Ctx) (t : Task) (k : Code) : k ∈ codes c t ↔ holds c t k = true := by
  unfold codes
  rw [List.mem_filter]
  have : k ∈ Code.all := by cases k <;> decide
  simp [this]

/-- **Unknown deps are exactly the deps outside the graph.**

$$\operatorname{holds}(t, \mathrm{unknownDep}) \iff \exists d \in t.\mathit{deps}:\ d \notin \mathit{ids}$$
-/
theorem unknownDep_iff (c : Ctx) (t : Task) :
    holds c t .unknownDep = true ↔ ∃ d ∈ t.deps, d ∉ c.ids := by
  simp [holds]

/-- **A long-evidence finding means more than 64 characters.**

$$\operatorname{holds}(t, \mathrm{evLong}) \iff \exists e:\ t.\mathit{evidence} = e \land 64 < |e|$$
-/
theorem evLong_iff (c : Ctx) (t : Task) :
    holds c t .evLong = true ↔ ∃ e, t.evidence = some e ∧ 64 < e.length := by
  unfold holds
  cases h : t.evidence <;> simp

/-- **A long-title finding means more than 200 characters.**

$$\operatorname{holds}(t, \mathrm{longTitle}) \iff 200 < |t.\mathit{title}|$$
-/
theorem longTitle_iff (c : Ctx) (t : Task) :
    holds c t .longTitle = true ↔ 200 < t.title.length := by
  simp [holds]

/-- **A missing-evidence finding means a trailer names the task and the row has none.**

$$\operatorname{holds}(t, \mathrm{trailerNoEvidence}) \iff t.\mathit{id} \in \mathit{named} \land t.\mathit{evidence} = \bot$$
-/
theorem trailerNoEvidence_iff (c : Ctx) (t : Task) :
    holds c t .trailerNoEvidence = true ↔ t.id ∈ c.named ∧ t.evidence = none := by
  unfold holds
  cases h : t.evidence <;> simp

/-- **The reverse finding: evidence on the row, no trailer names it.**

$$\operatorname{holds}(t, \mathrm{evidenceNoTrailer}) \iff t.\mathit{evidence} \ne \bot \land t.\mathit{id} \notin \mathit{named}$$
-/
theorem evidenceNoTrailer_iff (c : Ctx) (t : Task) :
    holds c t .evidenceNoTrailer = true ↔ t.evidence ≠ none ∧ t.id ∉ c.named := by
  unfold holds
  cases h : t.evidence <;> simp

/-- **A not-on-main finding means commit evidence the glue found off main.** Evidence of another
kind (CI run id, user decision, prose) is never checked for ancestry.

$$\operatorname{holds}(t, \mathrm{evNotOnMain}) \iff \exists e:\ t.\mathit{evidence} = e \land \operatorname{kind}(e) = \mathrm{commit} \land t.\mathit{id} \in \mathit{off}$$
-/
theorem evNotOnMain_iff (c : Ctx) (t : Task) :
    holds c t .evNotOnMain = true ↔ ∃ e, t.evidence = some e ∧ evKind e = .commit ∧ t.id ∈ c.off := by
  unfold holds
  cases h : t.evidence <;> simp

/-- A finding: the task (or `*` for the whole graph), the code name, its severity, a detail.

$$f = (\mathit{task}, \mathit{code}, \mathit{severity}, \mathit{detail})$$
-/
structure Finding where
  task     : String
  code     : String
  severity : String
  detail   : String
deriving Repr

/-- Tasks left by Kahn's pass (those in a cycle or behind one): each round keeps the rows that still have a dep
among the remaining rows, at most `fuel` rounds, and stops early when a round drops nothing.

$$\begin{aligned} \forall R:\quad &\operatorname{stuck}(0, R) = R, \\ \forall f \in \mathbb N,\ \forall R:\quad &\operatorname{stuck}(f+1, R) = \begin{cases} R & |R'| = |R| \\ \operatorname{stuck}(f, R') & |R'| \ne |R| \end{cases} \\ &\text{with } R' = [\, t \in R \mid \exists d \in t.\mathit{deps},\ \exists r \in R:\ r.\mathit{id} = d \,] \text{ (order kept)} \end{aligned}$$
-/
def stuck : Nat → List Task → List Task
  | 0, r => r
  | f + 1, r =>
    let r' := r.filter fun t => t.deps.any fun d => r.any (·.id == d)
    if r'.length == r.length then r else stuck f r'

/-- The ids named by `Task:` trailers of the commits, as a list: commit order kept, repeats kept.

$$\forall C = [c_1, \dots, c_n]:\quad \mathit{named}(C) = \operatorname{trailers}(c_1.\mathit{body}) \mathbin{+\!\!+} \cdots \mathbin{+\!\!+} \operatorname{trailers}(c_n.\mathit{body}) \quad (\mathit{named}([\,]) = [\,])$$
-/
def namedIds (cs : List Fw.Plan.Trailer.Commit) : List String :=
  cs.flatMap fun c => Fw.Plan.Trailer.trailers c.body

/-- The detail text of a finding.

$$\forall \mathit{ctx} = (\mathit{ids}, \mathit{named}),\ \forall t, k:\quad \operatorname{detail}(\mathit{ctx}, t, k) = \begin{cases}\operatorname{join}(\texttt{", "}, [\, d \in t.\mathit{deps} \mid d \notin \mathit{ids} \,]) & k = \mathrm{unknownDep}\\ \varepsilon & k \in \{\mathrm{evidenceNoTrailer}, \mathrm{trailerNoEvidence}, \mathrm{longTitle}\}\\ e & k \in \{\mathrm{evOther}, \mathrm{evLong}, \mathrm{evUser}, \mathrm{evProse}\} \land t.\mathit{evidence} = e \\ \varepsilon & k \in \{\mathrm{evOther}, \mathrm{evLong}, \mathrm{evUser}, \mathrm{evProse}\} \land t.\mathit{evidence} = \bot \end{cases}$$
-/
def detailOf (c : Ctx) (t : Task) : Code → String
  | .unknownDep => ", ".intercalate (t.deps.filter (fun d => !c.ids.contains d))
  | .evidenceNoTrailer | .trailerNoEvidence | .longTitle => ""
  | _ => t.evidence.getD ""

/-- All findings: per task in file order, codes in report order; then the graph-wide `cycle`.

$$\begin{aligned} \forall T, C:\quad \operatorname{lint}(T, C) = {} &[\, (t.\mathit{id}, \operatorname{name}(k), \operatorname{sev}(k), \operatorname{detail}(\mathit{ctx}, t, k)) \mid t \in T,\ k \in \operatorname{codes}(\mathit{ctx}, t) \,] \\ \mathbin{+\!\!+} {} &\begin{cases} [\,] & \operatorname{acyclicB}(T) \\ [(\texttt{*}, \texttt{cycle}, \texttt{error}, \operatorname{join}(\texttt{", "}, [\, r.\mathit{id} \mid r \in \operatorname{stuck}(|T|, T) \,]))] & \neg\operatorname{acyclicB}(T) \end{cases} \\ \text{with } \mathit{ctx} = {} &([\, t.\mathit{id} \mid t \in T \,],\ \mathit{named}(C),\ \mathit{off}) \end{aligned}$$

for every list $\mathit{off}$ of task ids whose evidence is not on main (default $[\,]$).
-/
def lint (ts : List Task) (cs : List Fw.Plan.Trailer.Commit) (off : List String := []) :
    List Finding :=
  let c : Ctx := { ids := ts.map (·.id), named := namedIds cs, off }
  let per := ts.flatMap fun t =>
    (codes c t).map fun k =>
      { task := t.id, code := k.name, severity := k.severity, detail := detailOf c t k : Finding }
  let cyc := if acyclicB ts then [] else
    [{ task := "*", code := "cycle", severity := "error",
       detail := ", ".intercalate ((stuck ts.length ts).map (·.id)) : Finding }]
  per ++ cyc

/-- Ok: no finding of severity `error`.

$$\operatorname{ok}(T, C, \mathit{off}) \iff \forall f \in \operatorname{lint}(T, C, \mathit{off}):\ f.\mathit{severity} \ne \mathrm{error}$$
-/
def ok (ts : List Task) (cs : List Fw.Plan.Trailer.Commit) (off : List String := []) : Bool :=
  (lint ts cs off).all fun f => f.severity != "error"

/-- **Lint ok means the graph has no unknown dep and no cycle** (what `fw plan sync` refuses).

$$\forall T, C, \mathit{off}:\quad \operatorname{ok}(T, C, \mathit{off}) \Rightarrow (\forall t \in T,\ \forall d \in t.\mathit{deps}:\ d \in \operatorname{ids}(T)) \land \operatorname{Acyclic}(T)$$
-/
theorem ok_sound (ts : List Task) (cs : List Fw.Plan.Trailer.Commit) (off : List String)
    (h : ok ts cs off = true) :
    (∀ t ∈ ts, ∀ d ∈ t.deps, d ∈ ts.map (·.id)) ∧ Acyclic ts := by
  have hall : ∀ f ∈ lint ts cs off, f.severity != "error" := by
    intro f hf; simpa [ok] using (List.all_eq_true.mp h f hf)
  constructor
  · intro t ht d hd
    refine Classical.byContradiction fun hn => ?_
    have hu : holds { ids := ts.map (·.id), named := namedIds cs, off } t .unknownDep = true :=
      (unknownDep_iff _ _).2 ⟨d, hd, hn⟩
    have hm := (mem_codes { ids := ts.map (·.id), named := namedIds cs, off } t .unknownDep).2 hu
    have hf : (⟨t.id, "unknownDep", "error", detailOf { ids := ts.map (·.id), named := namedIds cs, off } t .unknownDep⟩ : Finding) ∈ lint ts cs off := by
      unfold lint
      simp only [List.mem_append, List.mem_flatMap, List.mem_map]
      left
      exact ⟨t, ht, .unknownDep, hm, rfl⟩
    have := hall _ hf
    simp at this
  · rw [← acyclicB_iff]
    refine Classical.byContradiction fun hn => ?_
    have hf : (⟨"*", "cycle", "error", ", ".intercalate ((stuck ts.length ts).map (·.id))⟩ : Finding) ∈ lint ts cs off := by
      unfold lint
      simp [hn]
    have := hall _ hf
    simp at this

#guard evKind "bf4d660" == .commit
#guard evKind "39053169745" == .run
#guard evKind "user: never pay (2026-10-17)" == .user
#guard evKind "5ced4f6: Light mode 8/8" == .prose
#guard evKind "merge of c54c7bf; x" == .prose
#guard evKind "finished, trust me" == .other
#guard evKind "abc" == .other
-- evNotOnMain: commit evidence named off main is an error; other kinds and unnamed tasks are not
private def tk (x : String) (e : Option String) : Task :=
  { id := x, title := "", stream := "", milestone := none, deps := [], owner := "", writes := [],
    devices := [], needs := [], evidence := e, agent := none }
#guard holds { ids := [], named := [], off := ["a"] } (tk "a" (some "9a5c552")) .evNotOnMain
#guard !holds { ids := [], named := [] } (tk "a" (some "9a5c552")) .evNotOnMain
#guard !holds { ids := [], named := [], off := ["a"] } (tk "a" (some "39053169745")) .evNotOnMain
#guard !holds { ids := [], named := [], off := ["a"] } (tk "a" none) .evNotOnMain
#guard (lint [tk "a" (some "9a5c552")] [] ["a"]).map (·.code) == ["evNotOnMain", "evidenceNoTrailer"]
#guard !ok [tk "a" (some "9a5c552")] [] ["a"] && ok [tk "a" (some "9a5c552")] []

end Fw.Plan.Lint
