import Fw.Plan.Core
import Fw.Plan.Lint
/-!
# `plan.incidentLint`: is every tooling incident recorded with evidence, and is its fix done?

A pure check over `docs/team/incidents/ledger.json` (task `incident-lint`). The facts it reads are
collected by `fw incidents lint` and passed in (`Facts`): the work graph rows with their board state
(`Fw.Plan.Task`, done by `Fw.Plan.isDone`), the commit refs that are commits on main, and the file refs
that exist. Per incident it reports codes:

| code | severity | holds when |
|---|---|---|
| `noEvidence` | error | the evidence list is empty |
| `unknownKind` | error | an evidence kind is not `commit`, `ci`, `file`, `event` or `proc` |
| `badRef` | error | a ref does not have its kind's form: commit = `Fw.Plan.Lint.isCommit`, ci = `Fw.Plan.Lint.isRun`, file = repo-relative, event/proc = non-empty |
| `commitNotOnMain` | error | a commit ref is not in the main-commit fact set |
| `fileMissing` | error | a file ref is not in the existing-file fact set |
| `missingFixTask` | error | no `fix.task`, or `fix.task` / an `also` task is not a work graph id |
| `missingRepro` | error | `repro` missing or blank |
| `missingRegression` | error | `regression` missing or blank |
| `noStatusPrefix` | error | `cause` does not start with `CONFIRMED`, `INFERRED` or `MEASURED` |
| `statusField` | error | the record has a `status` field (status is derived, never stored) |
| `dupId` | error | another incident has the same id |
| `eventRef` | warn | an `event` ref (local-only, not reproducible from the public repo) |
| `procRef` | warn | a `proc` ref (a process shape, not reproducible) |

The status is derived (`status`): fixed iff `fix.task` and every `also` task are done; fixing iff not
fixed and one of them is claimed and not done; open otherwise.

Theorems: `mem_codes`, `status_fixed_iff`, `status_fixing_iff`, `fixed_no_missingFixTask`, `holds_addEvidence`
and `errors_addEvidence` (adding evidence never adds an error), `holds_mono_facts` (more facts never add
a finding), `lintAll_perm` and `okAll_perm` (order independence).
-/
namespace Fw.Plan.Incident
open Fw.Plan

/-- The evidence kinds of an incident.

$$\mathrm{EKind} = \{\mathrm{commit}, \mathrm{ci}, \mathrm{file}, \mathrm{event}, \mathrm{proc}\}$$
-/
inductive EKind | commit | ci | file | event | proc
deriving DecidableEq, Repr

/-- The evidence kind a `kind` string names, if any.

$$\operatorname{kindOf}(s) = \begin{cases}\mathrm{commit} & s = \texttt{"commit"}\\ \mathrm{ci} & s = \texttt{"ci"}\\ \mathrm{file} & s = \texttt{"file"}\\ \mathrm{event} & s = \texttt{"event"}\\ \mathrm{proc} & s = \texttt{"proc"}\\ \bot & \text{otherwise}\end{cases}$$
-/
def kindOf : String → Option EKind
  | "commit" => some .commit | "ci" => some .ci | "file" => some .file
  | "event" => some .event | "proc" => some .proc | _ => none

/-- One evidence item: its kind string (as written in the file) and its ref.

$$e = (\mathit{kind}, \mathit{ref})$$
-/
structure Ev where
  kind : String
  ref  : String
deriving Repr, DecidableEq

/-- One ledger record, as the lint reads it: id, cause, evidence, repro, the fix task and the `also`
tasks, regression, and whether the record carries a `status` field. Missing text fields are `none`.

$$i = (\mathit{id}, \mathit{cause}, \mathit{evidence}, \mathit{repro}_\bot, \mathit{fix}_\bot, \mathit{also}, \mathit{regression}_\bot, \mathit{hasStatus})$$
-/
structure Incident where
  id         : String
  cause      : String
  evidence   : List Ev
  repro      : Option String
  fixTask    : Option String
  also       : List String
  regression : Option String
  hasStatus  : Bool
deriving Repr, DecidableEq

/-- The facts the CLI collects: the work graph rows with their board state, the commit refs that are
commits on main, and the file refs that exist.

$$F = (\mathit{tasks}, \mathit{commits}, \mathit{files})$$
-/
structure Facts where
  tasks   : List Task
  commits : List String
  files   : List String

/-- A lint code.

$$\mathrm{Code} = \{\mathrm{noEvidence}, \mathrm{unknownKind}, \mathrm{badRef}, \mathrm{commitNotOnMain}, \mathrm{fileMissing}, \mathrm{missingFixTask}, \mathrm{missingRepro}, \mathrm{missingRegression}, \mathrm{noStatusPrefix}, \mathrm{statusField}, \mathrm{dupId}, \mathrm{eventRef}, \mathrm{procRef}\}$$
-/
inductive Code
  | noEvidence | unknownKind | badRef | commitNotOnMain | fileMissing | missingFixTask
  | missingRepro | missingRegression | noStatusPrefix | statusField | dupId | eventRef | procRef
deriving DecidableEq, Repr

/-- The codes in report order.

$$\mathrm{Codes} = [\mathrm{noEvidence}, \mathrm{unknownKind}, \mathrm{badRef}, \mathrm{commitNotOnMain}, \mathrm{fileMissing}, \mathrm{missingFixTask}, \mathrm{missingRepro}, \mathrm{missingRegression}, \mathrm{noStatusPrefix}, \mathrm{statusField}, \mathrm{dupId}, \mathrm{eventRef}, \mathrm{procRef}]$$
-/
def Code.all : List Code :=
  [.noEvidence, .unknownKind, .badRef, .commitNotOnMain, .fileMissing, .missingFixTask,
   .missingRepro, .missingRegression, .noStatusPrefix, .statusField, .dupId, .eventRef, .procRef]

/-- The wire name of a code: its constructor name.

$$\operatorname{name}(k) = \text{the identifier of } k \text{ as a string, e.g. } \operatorname{name}(\mathrm{noEvidence}) = \texttt{"noEvidence"}$$
-/
def Code.name : Code → String
  | .noEvidence => "noEvidence" | .unknownKind => "unknownKind" | .badRef => "badRef"
  | .commitNotOnMain => "commitNotOnMain" | .fileMissing => "fileMissing"
  | .missingFixTask => "missingFixTask" | .missingRepro => "missingRepro"
  | .missingRegression => "missingRegression" | .noStatusPrefix => "noStatusPrefix"
  | .statusField => "statusField" | .dupId => "dupId" | .eventRef => "eventRef" | .procRef => "procRef"

/-- Is the code an error (else a warning)? Only the two non-reproducible evidence kinds are warnings.

$$\operatorname{isError}(k) \iff k \notin \{\mathrm{eventRef}, \mathrm{procRef}\}$$
-/
def Code.isError : Code → Bool
  | .eventRef | .procRef => false
  | _ => true

/-- The severity name of a code.

$$\operatorname{sev}(k) = \begin{cases}\texttt{"error"} & \operatorname{isError}(k)\\ \texttt{"warn"} & \text{otherwise}\end{cases}$$
-/
def Code.severity (k : Code) : String := if k.isError then "error" else "warn"

/-- A text field that is missing or holds only whitespace (the empty string included).

$$\operatorname{blank}(o) \iff o = \bot \lor (o = s \land \forall c \in s:\ c \text{ is whitespace})$$
-/
def blank : Option String → Bool
  | none => true
  | some s => s.all Char.isWhitespace

/-- The claim status prefixes of the project rules.

$$\mathrm{Prefixes} = [\texttt{"CONFIRMED"}, \texttt{"INFERRED"}, \texttt{"MEASURED"}]$$
-/
def statusPrefixes : List String := ["CONFIRMED", "INFERRED", "MEASURED"]

/-- Does the cause start with a status prefix?

$$\operatorname{hasPrefix}(c) \iff \exists p \in \mathrm{Prefixes}:\ p \text{ is a prefix of } c$$
-/
def hasPrefix (c : String) : Bool := statusPrefixes.any fun p => c.startsWith p

/-- A file ref must be a repo-relative path: non-empty, not starting with `/` (an absolute or home
path) or `~`.

$$\operatorname{relPath}(r) \iff r \ne \varepsilon \land r_0 \ne \texttt{/} \land r_0 \ne \texttt{\textasciitilde}$$
-/
def relPath (r : String) : Bool := !r.isEmpty && !r.startsWith "/" && !r.startsWith "~"

/-- Does an evidence-level code hold for one evidence item? (Incident-level codes never do.)

$$\begin{aligned}
\mathrm{unknownKind}(e) &\iff \operatorname{kindOf}(e.\mathit{kind}) = \bot\\
\mathrm{badRef}(e) &\iff \begin{cases}\neg\operatorname{isCommit}(e.\mathit{ref}) & \operatorname{kindOf}(e.\mathit{kind}) = \mathrm{commit}\\ \neg\operatorname{isRun}(e.\mathit{ref}) & \operatorname{kindOf}(e.\mathit{kind}) = \mathrm{ci}\\ \neg\operatorname{relPath}(e.\mathit{ref}) & \operatorname{kindOf}(e.\mathit{kind}) = \mathrm{file}\\ e.\mathit{ref} = \varepsilon & \operatorname{kindOf}(e.\mathit{kind}) \in \{\mathrm{event}, \mathrm{proc}\}\\ \mathrm{false} & \operatorname{kindOf}(e.\mathit{kind}) = \bot\end{cases}\\
\mathrm{commitNotOnMain}(e) &\iff \operatorname{kindOf}(e.\mathit{kind}) = \mathrm{commit} \land e.\mathit{ref} \notin F.\mathit{commits}\\
\mathrm{fileMissing}(e) &\iff \operatorname{kindOf}(e.\mathit{kind}) = \mathrm{file} \land e.\mathit{ref} \notin F.\mathit{files}\\
\mathrm{eventRef}(e) &\iff \operatorname{kindOf}(e.\mathit{kind}) = \mathrm{event}\\
\mathrm{procRef}(e) &\iff \operatorname{kindOf}(e.\mathit{kind}) = \mathrm{proc}\\
k(e) &\iff \mathrm{false} \quad \text{for every other code } k
\end{aligned}$$
-/
def evHolds (F : Facts) (e : Ev) : Code → Bool
  | .unknownKind => (kindOf e.kind).isNone
  | .badRef => match kindOf e.kind with
    | some .commit => !Fw.Plan.Lint.isCommit e.ref
    | some .ci => !Fw.Plan.Lint.isRun e.ref
    | some .file => !relPath e.ref
    | some .event | some .proc => e.ref.isEmpty
    | none => false
  | .commitNotOnMain => kindOf e.kind == some .commit && !F.commits.contains e.ref
  | .fileMissing => kindOf e.kind == some .file && !F.files.contains e.ref
  | .eventRef => kindOf e.kind == some .event
  | .procRef => kindOf e.kind == some .proc
  | _ => false

/-- The fix tasks of an incident: `fix.task` (when present), then the `also` tasks.

$$\operatorname{fixTasks}(i) = [\, x \mid i.\mathit{fix} = x \,] \mathbin{+\!\!+} i.\mathit{also}$$
-/
def fixTasks (i : Incident) : List String := i.fixTask.toList ++ i.also

/-- Does code `k` hold for incident `i`, given the facts and whether its id is duplicated?

$$\begin{aligned}
\mathrm{noEvidence}(i) &\iff i.\mathit{evidence} = [\,]\\
\mathrm{missingFixTask}(i) &\iff i.\mathit{fix} = \bot \lor \exists x \in \operatorname{fixTasks}(i):\ x \notin \operatorname{ids}(F.\mathit{tasks})\\
\mathrm{missingRepro}(i) &\iff \operatorname{blank}(i.\mathit{repro})\\
\mathrm{missingRegression}(i) &\iff \operatorname{blank}(i.\mathit{regression})\\
\mathrm{noStatusPrefix}(i) &\iff \neg\operatorname{hasPrefix}(i.\mathit{cause})\\
\mathrm{statusField}(i) &\iff i.\mathit{hasStatus}\\
\mathrm{dupId}(i) &\iff \mathit{dup}\\
k(i) &\iff \exists e \in i.\mathit{evidence}:\ \operatorname{evHolds}_F(e, k) \quad \text{for } k \in \{\mathrm{unknownKind}, \mathrm{badRef}, \mathrm{commitNotOnMain}, \mathrm{fileMissing}, \mathrm{eventRef}, \mathrm{procRef}\}
\end{aligned}$$
-/
def holds (F : Facts) (dup : Bool) (i : Incident) : Code → Bool
  | .noEvidence => i.evidence.isEmpty
  | .missingFixTask => i.fixTask.isNone || (fixTasks i).any fun x => !(F.tasks.map (·.id)).contains x
  | .missingRepro => blank i.repro
  | .missingRegression => blank i.regression
  | .noStatusPrefix => !hasPrefix i.cause
  | .statusField => i.hasStatus
  | .dupId => dup
  | .unknownKind => i.evidence.any fun e => evHolds F e .unknownKind
  | .badRef => i.evidence.any fun e => evHolds F e .badRef
  | .commitNotOnMain => i.evidence.any fun e => evHolds F e .commitNotOnMain
  | .fileMissing => i.evidence.any fun e => evHolds F e .fileMissing
  | .eventRef => i.evidence.any fun e => evHolds F e .eventRef
  | .procRef => i.evidence.any fun e => evHolds F e .procRef

/-- Is `k` an evidence-level code (one that `evHolds` decides)?

$$\operatorname{isEv}(k) \iff k \in \{\mathrm{unknownKind}, \mathrm{badRef}, \mathrm{commitNotOnMain}, \mathrm{fileMissing}, \mathrm{eventRef}, \mathrm{procRef}\}$$
-/
def Code.isEv : Code → Bool
  | .unknownKind | .badRef | .commitNotOnMain | .fileMissing | .eventRef | .procRef => true
  | _ => false

/-- The codes that hold for an incident, in report order.

$$\operatorname{codes}_F(\mathit{dup}, i) = [\, k \in \mathrm{Codes} : \operatorname{holds}_F(\mathit{dup}, i, k) \,]$$
-/
def codes (F : Facts) (dup : Bool) (i : Incident) : List Code := Code.all.filter (holds F dup i)

/-- The derived status of an incident.

$$\mathrm{Status} = \{\mathrm{fixed}, \mathrm{fixing}, \mathrm{open}\}$$
-/
inductive Status | fixed | fixing | «open»
deriving DecidableEq, Repr

/-- The wire name of a status.

$$\operatorname{name}(\mathrm{fixed}) = \texttt{"fixed"},\ \operatorname{name}(\mathrm{fixing}) = \texttt{"fixing"},\ \operatorname{name}(\mathrm{open}) = \texttt{"open"}$$
-/
def Status.name : Status → String
  | .fixed => "fixed" | .fixing => "fixing" | .open => "open"

/-- A task is claimed: some row with that id has a claiming agent and no evidence (claimed or running,
not done).

$$\operatorname{claimed}(ts, x) \iff \exists t \in ts:\ t.\mathit{id} = x \land t.\mathit{agent} \ne \bot \land t.\mathit{evidence} = \bot$$
-/
def claimed (ts : List Task) (x : String) : Bool :=
  ts.any fun t => t.id == x && t.agent.isSome && t.evidence.isNone

/-- Every fix task is done: `fix.task` is present and done, and every `also` task is done.

$$\operatorname{fixedB}(ts, i) \iff \exists x:\ i.\mathit{fix} = x \land \operatorname{isDone}(ts, x) \land \forall a \in i.\mathit{also}:\ \operatorname{isDone}(ts, a)$$
-/
def fixedB (ts : List Task) (i : Incident) : Bool :=
  match i.fixTask with
  | none => false
  | some x => isDone ts x && i.also.all (isDone ts)

/-- The derived status; it is never read from the file.

$$\operatorname{status}(ts, i) = \begin{cases}\mathrm{fixed} & \operatorname{fixedB}(ts, i)\\ \mathrm{fixing} & \exists x \in \operatorname{fixTasks}(i):\ \operatorname{claimed}(ts, x)\\ \mathrm{open} & \text{otherwise}\end{cases}$$

Checked in this order.
-/
def status (ts : List Task) (i : Incident) : Status :=
  if fixedB ts i then .fixed
  else if (fixTasks i).any (claimed ts) then .fixing
  else .open

/-- One finding: a code and a detail text.

$$f = (\mathit{code}, \mathit{detail})$$
-/
structure Finding where
  code   : Code
  detail : String
deriving Repr, DecidableEq

/-- The detail text of a finding: the offending refs (kinds for `unknownKind`), the missing fix task
ids (`no fix.task` when there is none), the id for `dupId`, else empty.

$$\operatorname{detail}_F(i, k) = \begin{cases}\text{the kinds } e.\mathit{kind} \text{ with } \operatorname{evHolds}_F(e, k) & k = \mathrm{unknownKind}\\ \text{the refs } e.\mathit{ref} \text{ with } \operatorname{evHolds}_F(e, k) & \operatorname{isEv}(k) \land k \ne \mathrm{unknownKind}\\ \texttt{"no fix.task"} & k = \mathrm{missingFixTask} \land i.\mathit{fix} = \bot\\ \text{the } x \in \operatorname{fixTasks}(i) \text{ with } x \notin \operatorname{ids}(F.\mathit{tasks}) & k = \mathrm{missingFixTask} \land i.\mathit{fix} \ne \bot\\ i.\mathit{id} & k = \mathrm{dupId}\\ \varepsilon & \text{otherwise}\end{cases}$$

Lists are joined with `", "`.
-/
def detail (F : Facts) (i : Incident) (k : Code) : String :=
  if k == .unknownKind then ", ".intercalate ((i.evidence.filter (evHolds F · k)).map (·.kind))
  else if k.isEv then ", ".intercalate ((i.evidence.filter (evHolds F · k)).map (·.ref))
  else if k == .missingFixTask then
    if i.fixTask.isNone then "no fix.task"
    else ", ".intercalate ((fixTasks i).filter fun x => !(F.tasks.map (·.id)).contains x)
  else if k == .dupId then i.id
  else ""

/-- The lint result of one incident: id, derived status, findings.

$$r = (\mathit{id}, \mathit{status}, \mathit{findings})$$
-/
structure Result where
  id       : String
  status   : Status
  findings : List Finding
deriving Repr, DecidableEq

/-- Lint one incident.

$$\operatorname{lintOne}_F(\mathit{dup}, i) = \big(i.\mathit{id},\ \operatorname{status}(F.\mathit{tasks}, i),\ [\, (k, \operatorname{detail}_F(i, k)) : k \in \operatorname{codes}_F(\mathit{dup}, i) \,]\big)$$
-/
def lintOne (F : Facts) (dup : Bool) (i : Incident) : Result :=
  { id := i.id, status := status F.tasks i,
    findings := (codes F dup i).map fun k => { code := k, detail := detail F i k } }

/-- Is the id of `i` used by more than one incident of `l`?

$$\operatorname{dupIn}(l, i) \iff |[\, j \in l : j.\mathit{id} = i.\mathit{id} \,]| > 1$$
-/
def dupIn (l : List Incident) (i : Incident) : Bool := decide (1 < (l.map (·.id)).count i.id)

/-- Lint every incident, in file order.

$$\operatorname{lintAll}_F(l) = [\, \operatorname{lintOne}_F(\operatorname{dupIn}(l, i), i) : i \in l \,]$$
-/
def lintAll (F : Facts) (l : List Incident) : List Result :=
  l.map fun i => lintOne F (dupIn l i) i

/-- Ok: no finding of any incident is an error.

$$\operatorname{ok}_F(l) \iff \forall r \in \operatorname{lintAll}_F(l),\ \forall f \in r.\mathit{findings}:\ \neg\operatorname{isError}(f.\mathit{code})$$
-/
def okAll (F : Facts) (l : List Incident) : Bool :=
  (lintAll F l).all fun r => r.findings.all fun f => !f.code.isError

/-! ## Theorems -/

/-- **Each reported code holds, and each code that holds is reported.**

$$\forall F, \mathit{dup}, i, k:\quad k \in \operatorname{codes}_F(\mathit{dup}, i) \iff \operatorname{holds}_F(\mathit{dup}, i, k)$$
-/
theorem mem_codes (F : Facts) (dup : Bool) (i : Incident) (k : Code) :
    k ∈ codes F dup i ↔ holds F dup i k = true := by
  unfold codes
  cases k <;> simp [Code.all]

/-- **Fixed is exactly: the fix task and every `also` task are done.**

$$\forall ts, i:\quad \operatorname{status}(ts, i) = \mathrm{fixed} \iff \exists x:\ i.\mathit{fix} = x \land \operatorname{isDone}(ts, x) \land \forall a \in i.\mathit{also}:\ \operatorname{isDone}(ts, a)$$
-/
theorem status_fixed_iff (ts : List Task) (i : Incident) :
    status ts i = .fixed ↔
      ∃ x, i.fixTask = some x ∧ isDone ts x = true ∧ ∀ a ∈ i.also, isDone ts a = true := by
  have hf : fixedB ts i = true ↔
      ∃ x, i.fixTask = some x ∧ isDone ts x = true ∧ ∀ a ∈ i.also, isDone ts a = true := by
    unfold fixedB
    cases i.fixTask <;> simp
  rw [← hf]
  unfold status
  cases fixedB ts i
  · simp only [Bool.false_eq_true, ite_false, iff_false]
    split <;> simp
  · simp

/-- **Fixing is exactly: not fixed, and some fix task is claimed and not done.**

$$\forall ts, i:\quad \operatorname{status}(ts, i) = \mathrm{fixing} \iff \neg\operatorname{fixedB}(ts, i) \land \exists x \in \operatorname{fixTasks}(i),\ \exists t \in ts:\ t.\mathit{id} = x \land t.\mathit{agent} \ne \bot \land t.\mathit{evidence} = \bot$$
-/
theorem status_fixing_iff (ts : List Task) (i : Incident) :
    status ts i = .fixing ↔ fixedB ts i = false ∧
      ∃ x ∈ fixTasks i, ∃ t ∈ ts, t.id = x ∧ t.agent ≠ none ∧ t.evidence = none := by
  unfold status
  cases hf : fixedB ts i
  · simp only [Bool.false_eq_true, ite_false, true_and]
    by_cases hc : (fixTasks i).any (claimed ts) = true
    · simp only [hc, ite_true, true_iff]
      obtain ⟨x, hx, hcx⟩ := List.any_eq_true.mp hc
      obtain ⟨t, ht, h⟩ := List.any_eq_true.mp hcx
      simp only [Bool.and_eq_true, beq_iff_eq, Option.isSome_iff_ne_none, Option.isNone_iff_eq_none] at h
      exact ⟨x, hx, t, ht, h.1.1, h.1.2, h.2⟩
    · simp only [hc, Bool.false_eq_true, ite_false, reduceCtorEq, false_iff]
      rintro ⟨x, hx, t, ht, h1, h2, h3⟩
      apply hc
      refine List.any_eq_true.mpr ⟨x, hx, List.any_eq_true.mpr ⟨t, ht, ?_⟩⟩
      simp [h1, Option.isSome_iff_ne_none, h2, h3]
  · simp

/-- **A fixed incident never reports `missingFixTask`**: a done task is a row of the work graph.

$$\forall F, \mathit{dup}, i:\quad \operatorname{status}(F.\mathit{tasks}, i) = \mathrm{fixed} \Rightarrow \mathrm{missingFixTask} \notin \operatorname{codes}_F(\mathit{dup}, i)$$
-/
theorem fixed_no_missingFixTask (F : Facts) (dup : Bool) (i : Incident)
    (h : status F.tasks i = .fixed) : Code.missingFixTask ∉ codes F dup i := by
  rw [mem_codes]
  obtain ⟨x, hx, hd, ha⟩ := (status_fixed_iff _ _).mp h
  have hid : ∀ y, isDone F.tasks y = true → y ∈ F.tasks.map (·.id) := by
    intro y hy
    obtain ⟨t, ht, hti, _⟩ := isDone_iff.mp hy
    exact List.mem_map.mpr ⟨t, ht, hti⟩
  simp only [holds, hx, Option.isNone_some, Bool.false_or, Bool.not_eq_true, List.any_eq_false,
    Bool.not_eq_false']
  intro y hy
  simp only [fixTasks, hx, Option.toList_some, List.cons_append, List.nil_append, List.mem_cons] at hy
  rcases hy with rfl | hy
  · simpa using hid _ hd
  · simpa using hid _ (ha _ hy)

/-- **Adding evidence never adds a finding beyond those of the added items**: every code that holds
after appending evidence `es` held before, or holds for one of the added items.

$$\forall F, \mathit{dup}, i, es, k:\quad \operatorname{holds}_F(\mathit{dup}, i[\mathit{evidence} := i.\mathit{evidence} \mathbin{+\!\!+} es], k) \Rightarrow \operatorname{holds}_F(\mathit{dup}, i, k) \lor \exists e \in es:\ \operatorname{evHolds}_F(e, k)$$
-/
theorem holds_addEvidence (F : Facts) (dup : Bool) (i : Incident) (es : List Ev) (k : Code)
    (h : holds F dup { i with evidence := i.evidence ++ es } k = true) :
    holds F dup i k = true ∨ ∃ e ∈ es, evHolds F e k = true := by
  cases k <;> simp only [holds, List.any_append, Bool.or_eq_true, List.any_eq_true,
    List.isEmpty_iff, List.append_eq_nil_iff] at h ⊢
  all_goals first | exact h | exact .inl h | exact .inl h.1

/-- **Lint is monotone in evidence: adding evidence never adds an error.** When no added item has an
error-level finding by itself, every error code after the addition was already reported before.

$$\forall F, \mathit{dup}, i, es, k:\quad (\forall e \in es,\ \forall k':\ \operatorname{isError}(k') \Rightarrow \neg\operatorname{evHolds}_F(e, k')) \land \operatorname{isError}(k) \land k \in \operatorname{codes}_F(\mathit{dup}, i[\mathit{evidence} := i.\mathit{evidence} \mathbin{+\!\!+} es]) \Rightarrow k \in \operatorname{codes}_F(\mathit{dup}, i)$$
-/
theorem errors_addEvidence (F : Facts) (dup : Bool) (i : Incident) (es : List Ev) (k : Code)
    (hes : ∀ e ∈ es, ∀ k', k'.isError = true → evHolds F e k' = false)
    (hk : k.isError = true) (h : k ∈ codes F dup { i with evidence := i.evidence ++ es }) :
    k ∈ codes F dup i := by
  rw [mem_codes] at h ⊢
  rcases holds_addEvidence F dup i es k h with h | ⟨e, he, hek⟩
  · exact h
  · simp [hes e he k hk] at hek

/-- **More facts never add a finding**: with at least the same main commits, existing files and work
graph ids, every code that holds held already with the smaller facts.

$$\forall F, F', \mathit{dup}, i, k:\quad F.\mathit{commits} \subseteq F'.\mathit{commits} \land F.\mathit{files} \subseteq F'.\mathit{files} \land \operatorname{ids}(F.\mathit{tasks}) \subseteq \operatorname{ids}(F'.\mathit{tasks}) \land \operatorname{holds}_{F'}(\mathit{dup}, i, k) \Rightarrow \operatorname{holds}_F(\mathit{dup}, i, k)$$
-/
theorem holds_mono_facts (F F' : Facts) (dup : Bool) (i : Incident) (k : Code)
    (hc : ∀ c ∈ F.commits, c ∈ F'.commits) (hf : ∀ f ∈ F.files, f ∈ F'.files)
    (ht : ∀ x ∈ F.tasks.map (·.id), x ∈ F'.tasks.map (·.id))
    (h : holds F' dup i k = true) : holds F dup i k = true := by
  have he : ∀ e : Ev, ∀ k, evHolds F' e k = true → evHolds F e k = true := by
    intro e k hk
    cases k <;> simp only [evHolds, List.contains_eq_mem, Bool.and_eq_true, Bool.not_eq_true',
      decide_eq_false_iff_not] at hk ⊢
    all_goals first
      | exact hk
      | exact ⟨hk.1, fun hm => hk.2 (hc _ hm)⟩
      | exact ⟨hk.1, fun hm => hk.2 (hf _ hm)⟩
  cases k <;> simp only [holds, List.any_eq_true] at h ⊢
  all_goals first
    | exact h
    | (obtain ⟨e, he1, he2⟩ := h; exact ⟨e, he1, he _ _ he2⟩)
    | skip
  simp only [Bool.or_eq_true, List.any_eq_true, List.contains_eq_mem, Bool.not_eq_true',
    decide_eq_false_iff_not] at h ⊢
  rcases h with h | ⟨x, hx, hn⟩
  · exact .inl h
  · exact .inr ⟨x, hx, fun hm => hn (ht _ hm)⟩

/-- **Lint is order-independent**: a permutation of the incidents gives the same results, permuted.

$$\forall F, l_1, l_2:\quad l_1 \sim l_2 \Rightarrow \operatorname{lintAll}_F(l_1) \sim \operatorname{lintAll}_F(l_2)$$

($\sim$ is "is a permutation of".)
-/
theorem lintAll_perm (F : Facts) {l₁ l₂ : List Incident} (hp : l₁.Perm l₂) :
    (lintAll F l₁).Perm (lintAll F l₂) := by
  have hd : ∀ i, dupIn l₁ i = dupIn l₂ i := by
    intro i
    simp only [dupIn, (hp.map (·.id)).count_eq]
  unfold lintAll
  simp only [hd]
  exact hp.map _

/-- **The verdict is order-independent**: permuted incidents give the same ok.

$$\forall F, l_1, l_2:\quad l_1 \sim l_2 \Rightarrow \operatorname{ok}_F(l_1) = \operatorname{ok}_F(l_2)$$
-/
theorem okAll_perm (F : Facts) {l₁ l₂ : List Incident} (hp : l₁.Perm l₂) :
    okAll F l₁ = okAll F l₂ := by
  unfold okAll
  exact Bool.eq_iff_iff.mpr (by simp only [List.all_eq_true]; exact
    ⟨fun h r hr => h r ((lintAll_perm F hp).mem_iff.mpr hr),
     fun h r hr => h r ((lintAll_perm F hp).mem_iff.mp hr)⟩)

/-! ## Examples -/

/-- A sample fact set for the `#guard` examples: task `a` done, task `b` claimed, task `c` open; one main commit and one file.

$$F_0 = ([a \text{ done}, b \text{ claimed}, c \text{ open}],\ [\texttt{1c64c85}],\ [\texttt{README.md}])$$
-/
def sampleFacts : Facts :=
  let row (id : String) (ev ag : Option String) : Task :=
    { id, title := "", stream := "", milestone := none, deps := [], owner := "", writes := [],
      devices := [], needs := [], evidence := ev, agent := ag }
  { tasks := [row "a" (some "1c64c85") none, row "b" none (some "b"), row "c" none none],
    commits := ["1c64c85"], files := ["README.md"] }

/-- A sample incident for the `#guard` examples: one main commit as evidence, fixed by task `a`.

$$i_0 = (\texttt{inc}, \texttt{"CONFIRMED: x"}, [(\mathrm{commit}, \texttt{1c64c85})], \texttt{"r"}, a, [\,], \texttt{"g"}, \mathrm{false})$$
-/
def sampleIncident : Incident :=
  { id := "inc", cause := "CONFIRMED: x", evidence := [⟨"commit", "1c64c85"⟩], repro := some "r",
    fixTask := some "a", also := [], regression := some "g", hasStatus := false }

#guard codes sampleFacts false sampleIncident == []
#guard status sampleFacts.tasks sampleIncident == .fixed
#guard status sampleFacts.tasks { sampleIncident with also := ["b"] } == .fixing
#guard status sampleFacts.tasks { sampleIncident with fixTask := some "c" } == .open
#guard status sampleFacts.tasks { sampleIncident with fixTask := none } == .open
#guard status sampleFacts.tasks { sampleIncident with fixTask := none, also := ["b"] } == .fixing
#guard codes sampleFacts false { sampleIncident with evidence := [] } == [.noEvidence]
#guard codes sampleFacts false { sampleIncident with evidence := [⟨"commit", "abcdef0"⟩] } == [.commitNotOnMain]
#guard codes sampleFacts false { sampleIncident with evidence := [⟨"commit", "zz"⟩] } == [.badRef, .commitNotOnMain]
#guard codes sampleFacts false { sampleIncident with evidence := [⟨"ci", "39057124869"⟩] } == []
#guard codes sampleFacts false { sampleIncident with evidence := [⟨"ci", "abc"⟩] } == [.badRef]
#guard codes sampleFacts false { sampleIncident with evidence := [⟨"file", "README.md"⟩] } == []
#guard codes sampleFacts false { sampleIncident with evidence := [⟨"file", "/abs/a"⟩] } == [.badRef, .fileMissing]
#guard codes sampleFacts false { sampleIncident with evidence := [⟨"photo", "x"⟩] } == [.unknownKind]
#guard codes sampleFacts false { sampleIncident with evidence := [⟨"event", "480"⟩, ⟨"proc", "sleep"⟩] } == [.eventRef, .procRef]
#guard codes sampleFacts false { sampleIncident with fixTask := some "zz", also := ["c", "yy"] } == [.missingFixTask]
#guard detail sampleFacts { sampleIncident with fixTask := some "zz", also := ["c", "yy"] } .missingFixTask == "zz, yy"
#guard detail sampleFacts { sampleIncident with fixTask := none } .missingFixTask == "no fix.task"
#guard codes sampleFacts false { sampleIncident with repro := some "  ", regression := none } == [.missingRepro, .missingRegression]
#guard codes sampleFacts false { sampleIncident with cause := "maybe: x" } == [.noStatusPrefix]
#guard codes sampleFacts false { sampleIncident with cause := "INFERRED x" } == []
#guard codes sampleFacts false { sampleIncident with hasStatus := true } == [.statusField]
#guard codes sampleFacts true sampleIncident == [.dupId]
#guard dupIn [sampleIncident, sampleIncident] sampleIncident && !dupIn [sampleIncident] sampleIncident
#guard okAll sampleFacts [sampleIncident] && !okAll sampleFacts [sampleIncident, sampleIncident]
#guard okAll sampleFacts [{ sampleIncident with evidence := [⟨"event", "480"⟩] }]
#guard hasPrefix "MEASURED (x)" && !hasPrefix "confirmed" && !hasPrefix ""
#guard blank none && blank (some "") && blank (some " \n") && !blank (some "x")
#guard relPath "docs/a.md" && !relPath "" && !relPath "/tmp/x" && !relPath "~/x"
#guard kindOf "ci" == some .ci && kindOf "CI" == none

end Fw.Plan.Incident
