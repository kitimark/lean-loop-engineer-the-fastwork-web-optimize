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
| `missingLeanVerdict` | error | `leanVerdict` missing or blank |
| `badLeanVerdict` | error | `leanVerdict` is not blank and not `provable`, `partly` or `no` |
| `missingLeanReason` | error | `leanReason` missing or blank |
| `missingHardening` | error | the verdict is `provable` or `partly` and `hardening` (a work graph task id) is missing or blank |
| `unknownHardening` | error | `hardening` is present and not a work graph id |
| `missingEmpiricalCheck` | error | the verdict is `no` and `empiricalCheck` (the test or CI check that covers it) is missing or blank |
| `unknownMistakeClass` | error | `mistakeClass` is present and not a class id of `research/mistakes/ledger.json` (fact set `classes`) |
| `dupId` | error | another incident has the same id |
| `eventRef` | warn | an `event` ref (local-only, not reproducible from the public repo) |
| `procRef` | warn | a `proc` ref (a process shape, not reproducible) |

The status is derived (`status`): fixed iff `fix.task` and every `also` task are done; fixing iff not
fixed and one of them is claimed and not done; open otherwise.

Theorems: `mem_codes`, `status_fixed_iff`, `status_fixing_iff`, `fixed_no_missingFixTask`, `holds_addEvidence`
and `errors_addEvidence` (adding evidence never adds an error), `holds_mono_facts` (more facts never add
a finding), `lintAll_perm` and `okAll_perm` (order independence), `lint_ok_iff` (ok iff every entry
is complete and every referenced task and class exists), `no_without_empiricalCheck_refused` and
`ok_hardening_exists`.

The Lean fields (task `incident-lean-fields`) link each incident to the mistake retro
(`research/mistakes/ledger.json`): a Lean verdict with its reason, and what covers it: a work graph
hardening task for `provable` / `partly`, the empirical check for `no` (a `no` may also name a
hardening task, which must then exist).
-/
namespace Fw.Plan.Incident
open Fw.Plan

/-- The evidence kinds of an incident. -/
inductive EKind | commit | ci | file | event | proc
deriving DecidableEq, Repr

/-- The evidence kind a `kind` string names, if any. -/
def kindOf : String → Option EKind
  | "commit" => some .commit | "ci" => some .ci | "file" => some .file
  | "event" => some .event | "proc" => some .proc | _ => none

/-- One evidence item: its kind string (as written in the file) and its ref. -/
structure Ev where
  kind : String
  ref  : String
deriving Repr, DecidableEq

/-- One ledger record, as the lint reads it: id, cause, evidence, repro, the fix task and the `also`
tasks, regression, whether the record carries a `status` field, and the Lean fields of the mistake
retro (verdict, reason, hardening task, empirical check, mistake class). Missing text fields are `none`.
-/
structure Incident where
  id             : String
  cause          : String
  evidence       : List Ev
  repro          : Option String
  fixTask        : Option String
  also           : List String
  regression     : Option String
  hasStatus      : Bool
  leanVerdict    : Option String := none
  leanReason     : Option String := none
  hardening      : Option String := none
  empiricalCheck : Option String := none
  mistakeClass   : Option String := none
deriving Repr, DecidableEq

/-- The Lean verdict of an incident: provable, partly provable, or not provable in Lean. -/
inductive Verdict | provable | partly | no
deriving DecidableEq, Repr

/-- The verdict a `leanVerdict` string names, if any (exact and case-sensitive). -/
def verdictOf : String → Option Verdict
  | "provable" => some .provable | "partly" => some .partly | "no" => some .no | _ => none

/-- The verdict of an incident: its `leanVerdict` read by `verdictOf`; none when the field is missing
or names no verdict.
-/
def verdict (i : Incident) : Option Verdict := i.leanVerdict.bind verdictOf

/-- The facts the CLI collects: the work graph rows with their board state, the commit refs that are
commits on main, the file refs that exist, and the class ids of `research/mistakes/ledger.json`.
-/
structure Facts where
  tasks   : List Task
  commits : List String
  files   : List String
  classes : List String := []

/-- A lint code. -/
inductive Code
  | noEvidence | unknownKind | badRef | commitNotOnMain | fileMissing | missingFixTask
  | missingRepro | missingRegression | noStatusPrefix | statusField
  | missingLeanVerdict | badLeanVerdict | missingLeanReason | missingHardening | unknownHardening
  | missingEmpiricalCheck | unknownMistakeClass
  | dupId | eventRef | procRef
deriving DecidableEq, Repr

/-- The codes in report order. -/
def Code.all : List Code :=
  [.noEvidence, .unknownKind, .badRef, .commitNotOnMain, .fileMissing, .missingFixTask,
   .missingRepro, .missingRegression, .noStatusPrefix, .statusField,
   .missingLeanVerdict, .badLeanVerdict, .missingLeanReason, .missingHardening, .unknownHardening,
   .missingEmpiricalCheck, .unknownMistakeClass, .dupId, .eventRef, .procRef]

/-- The wire name of a code: its constructor name. -/
def Code.name : Code → String
  | .noEvidence => "noEvidence" | .unknownKind => "unknownKind" | .badRef => "badRef"
  | .commitNotOnMain => "commitNotOnMain" | .fileMissing => "fileMissing"
  | .missingFixTask => "missingFixTask" | .missingRepro => "missingRepro"
  | .missingRegression => "missingRegression" | .noStatusPrefix => "noStatusPrefix"
  | .statusField => "statusField" | .missingLeanVerdict => "missingLeanVerdict"
  | .badLeanVerdict => "badLeanVerdict" | .missingLeanReason => "missingLeanReason"
  | .missingHardening => "missingHardening" | .unknownHardening => "unknownHardening"
  | .missingEmpiricalCheck => "missingEmpiricalCheck" | .unknownMistakeClass => "unknownMistakeClass"
  | .dupId => "dupId" | .eventRef => "eventRef" | .procRef => "procRef"

/-- Is the code an error (else a warning)? Only the two non-reproducible evidence kinds are warnings. -/
def Code.isError : Code → Bool
  | .eventRef | .procRef => false
  | _ => true

/-- The severity name of a code. -/
def Code.severity (k : Code) : String := if k.isError then "error" else "warn"

/-- A text field that is missing or holds only whitespace (the empty string included). -/
def blank : Option String → Bool
  | none => true
  | some s => s.all Char.isWhitespace

/-- The claim status prefixes of the project rules. -/
def statusPrefixes : List String := ["CONFIRMED", "INFERRED", "MEASURED"]

/-- Does the cause start with a status prefix? -/
def hasPrefix (c : String) : Bool := statusPrefixes.any fun p => c.startsWith p

/-- A file ref must be a repo-relative path: non-empty, not starting with `/` (an absolute or home
path) or `~`.
-/
def relPath (r : String) : Bool := !r.isEmpty && !r.startsWith "/" && !r.startsWith "~"

/-- Does an evidence-level code hold for one evidence item? (Incident-level codes never do.) -/
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

/-- The fix tasks of an incident: `fix.task` (when present), then the `also` tasks. -/
def fixTasks (i : Incident) : List String := i.fixTask.toList ++ i.also

/-- The work graph ids of the facts. -/
def taskIds (F : Facts) : List String := F.tasks.map (·.id)

/-- Does the verdict ask for a hardening task (provable or partly)? -/
def needsHardening (i : Incident) : Bool :=
  verdict i == some .provable || verdict i == some .partly

/-- Does code `k` hold for incident `i`, given the facts and whether its id is duplicated? -/
def holds (F : Facts) (dup : Bool) (i : Incident) : Code → Bool
  | .noEvidence => i.evidence.isEmpty
  | .missingFixTask => i.fixTask.isNone || (fixTasks i).any fun x => !(F.tasks.map (·.id)).contains x
  | .missingRepro => blank i.repro
  | .missingRegression => blank i.regression
  | .noStatusPrefix => !hasPrefix i.cause
  | .statusField => i.hasStatus
  | .missingLeanVerdict => blank i.leanVerdict
  | .badLeanVerdict => !blank i.leanVerdict && (verdict i).isNone
  | .missingLeanReason => blank i.leanReason
  | .missingHardening => needsHardening i && blank i.hardening
  | .unknownHardening => match i.hardening with
    | none => false
    | some h => !(taskIds F).contains h
  | .missingEmpiricalCheck => verdict i == some .no && blank i.empiricalCheck
  | .unknownMistakeClass => match i.mistakeClass with
    | none => false
    | some c => !F.classes.contains c
  | .dupId => dup
  | .unknownKind => i.evidence.any fun e => evHolds F e .unknownKind
  | .badRef => i.evidence.any fun e => evHolds F e .badRef
  | .commitNotOnMain => i.evidence.any fun e => evHolds F e .commitNotOnMain
  | .fileMissing => i.evidence.any fun e => evHolds F e .fileMissing
  | .eventRef => i.evidence.any fun e => evHolds F e .eventRef
  | .procRef => i.evidence.any fun e => evHolds F e .procRef

/-- Is `k` an evidence-level code (one that `evHolds` decides)? -/
def Code.isEv : Code → Bool
  | .unknownKind | .badRef | .commitNotOnMain | .fileMissing | .eventRef | .procRef => true
  | _ => false

/-- The codes that hold for an incident, in report order. -/
def codes (F : Facts) (dup : Bool) (i : Incident) : List Code := Code.all.filter (holds F dup i)

/-- The derived status of an incident. -/
inductive Status | fixed | fixing | «open»
deriving DecidableEq, Repr

/-- The wire name of a status. -/
def Status.name : Status → String
  | .fixed => "fixed" | .fixing => "fixing" | .open => "open"

/-- A task is claimed: some row with that id has a claiming agent and no evidence (claimed or running,
not done).
-/
def claimed (ts : List Task) (x : String) : Bool :=
  ts.any fun t => t.id == x && t.agent.isSome && t.evidence.isNone

/-- Every fix task is done: `fix.task` is present and done, and every `also` task is done. -/
def fixedB (ts : List Task) (i : Incident) : Bool :=
  match i.fixTask with
  | none => false
  | some x => isDone ts x && i.also.all (isDone ts)

/-- The derived status; it is never read from the file.

Checked in this order.
-/
def status (ts : List Task) (i : Incident) : Status :=
  if fixedB ts i then .fixed
  else if (fixTasks i).any (claimed ts) then .fixing
  else .open

/-- One finding: a code and a detail text. -/
structure Finding where
  code   : Code
  detail : String
deriving Repr, DecidableEq

/-- The detail text of a Lean-field finding: it names the field and what it must hold, so an entry
written after this lint learns exactly which field is missing (`⟨ x ⟩` is the field's value,
`v` the verdict name).

A missing value prints as empty.
-/
def leanDetail (i : Incident) : Code → String
  | .missingLeanVerdict => "leanVerdict missing: one of provable, partly (both also need hardening), no (also needs empiricalCheck)"
  | .badLeanVerdict => s!"leanVerdict '{i.leanVerdict.getD ""}' is not one of provable, partly, no"
  | .missingLeanReason => "leanReason missing: why Lean can or cannot prove it"
  | .missingHardening =>
    s!"hardening missing: a work graph task id (required when leanVerdict is {i.leanVerdict.getD ""})"
  | .unknownHardening => s!"hardening '{i.hardening.getD ""}' is not a work graph task id"
  | .missingEmpiricalCheck =>
    "empiricalCheck missing: the test or CI check that covers it (required when leanVerdict is no)"
  | .unknownMistakeClass =>
    s!"mistakeClass '{i.mistakeClass.getD ""}' is not a class id of research/mistakes/ledger.json"
  | _ => ""

/-- The detail text of a finding: the offending refs (kinds for `unknownKind`), the missing fix task
ids (`no fix.task` when there is none), the id for `dupId`, the field text of `leanDetail` for the
Lean-field codes, else empty.

Lists are joined with `", "`; the cases are checked in this order.
-/
def detail (F : Facts) (i : Incident) (k : Code) : String :=
  if k == .unknownKind then ", ".intercalate ((i.evidence.filter (evHolds F · k)).map (·.kind))
  else if k.isEv then ", ".intercalate ((i.evidence.filter (evHolds F · k)).map (·.ref))
  else if k == .missingFixTask then
    if i.fixTask.isNone then "no fix.task"
    else ", ".intercalate ((fixTasks i).filter fun x => !(F.tasks.map (·.id)).contains x)
  else if k == .dupId then i.id
  else leanDetail i k

/-- The lint result of one incident: id, derived status, findings. -/
structure Result where
  id       : String
  status   : Status
  findings : List Finding
deriving Repr, DecidableEq

/-- Lint one incident. -/
def lintOne (F : Facts) (dup : Bool) (i : Incident) : Result :=
  { id := i.id, status := status F.tasks i,
    findings := (codes F dup i).map fun k => { code := k, detail := detail F i k } }

/-- Is the id of `i` used by more than one incident of `l`? -/
def dupIn (l : List Incident) (i : Incident) : Bool := decide (1 < (l.map (·.id)).count i.id)

/-- Lint every incident, in file order. -/
def lintAll (F : Facts) (l : List Incident) : List Result :=
  l.map fun i => lintOne F (dupIn l i) i

/-- Ok: no finding of any incident is an error. -/
def okAll (F : Facts) (l : List Incident) : Bool :=
  (lintAll F l).all fun r => r.findings.all fun f => !f.code.isError

/-! ## Theorems -/

/-- **Each reported code holds, and each code that holds is reported.** -/
theorem mem_codes (F : Facts) (dup : Bool) (i : Incident) (k : Code) :
    k ∈ codes F dup i ↔ holds F dup i k = true := by
  unfold codes
  cases k <;> simp [Code.all]

/-- **Fixed is exactly: the fix task and every `also` task are done.** -/
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

/-- **Fixing is exactly: not fixed, and some fix task is claimed and not done.** -/
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

/-- **A fixed incident never reports `missingFixTask`**: a done task is a row of the work graph. -/
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
-/
theorem holds_addEvidence (F : Facts) (dup : Bool) (i : Incident) (es : List Ev) (k : Code)
    (h : holds F dup { i with evidence := i.evidence ++ es } k = true) :
    holds F dup i k = true ∨ ∃ e ∈ es, evHolds F e k = true := by
  cases k <;> simp only [holds, List.any_append, Bool.or_eq_true, List.any_eq_true,
    List.isEmpty_iff, List.append_eq_nil_iff] at h ⊢
  all_goals first | exact h | exact .inl h | exact .inl h.1

/-- **Lint is monotone in evidence: adding evidence never adds an error.** When no added item has an
error-level finding by itself, every error code after the addition was already reported before.
-/
theorem errors_addEvidence (F : Facts) (dup : Bool) (i : Incident) (es : List Ev) (k : Code)
    (hes : ∀ e ∈ es, ∀ k', k'.isError = true → evHolds F e k' = false)
    (hk : k.isError = true) (h : k ∈ codes F dup { i with evidence := i.evidence ++ es }) :
    k ∈ codes F dup i := by
  rw [mem_codes] at h ⊢
  rcases holds_addEvidence F dup i es k h with h | ⟨e, he, hek⟩
  · exact h
  · simp [hes e he k hk] at hek

/-- **More facts never add a finding**: with at least the same main commits, existing files, work
graph ids and mistake classes, every code that holds held already with the smaller facts.
-/
theorem holds_mono_facts (F F' : Facts) (dup : Bool) (i : Incident) (k : Code)
    (hc : ∀ c ∈ F.commits, c ∈ F'.commits) (hf : ∀ f ∈ F.files, f ∈ F'.files)
    (ht : ∀ x ∈ F.tasks.map (·.id), x ∈ F'.tasks.map (·.id))
    (hcl : ∀ c ∈ F.classes, c ∈ F'.classes)
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
  case missingFixTask =>
    simp only [Bool.or_eq_true, List.any_eq_true, List.contains_eq_mem, Bool.not_eq_true',
      decide_eq_false_iff_not] at h ⊢
    rcases h with h | ⟨x, hx, hn⟩
    · exact .inl h
    · exact .inr ⟨x, hx, fun hm => hn (ht _ hm)⟩
  case unknownHardening =>
    simp only [taskIds] at h ⊢
    split at h
    · exact h
    · simp only [Bool.not_eq_true', List.contains_eq_mem, decide_eq_false_iff_not] at h ⊢
      exact fun hm => h (ht _ hm)
  case unknownMistakeClass =>
    split at h
    · exact h
    · simp only [Bool.not_eq_true', List.contains_eq_mem, decide_eq_false_iff_not] at h ⊢
      exact fun hm => h (hcl _ hm)

/-- **Lint is order-independent**: a permutation of the incidents gives the same results, permuted.

(`∼` is "is a permutation of".)
-/
theorem lintAll_perm (F : Facts) {l₁ l₂ : List Incident} (hp : l₁.Perm l₂) :
    (lintAll F l₁).Perm (lintAll F l₂) := by
  have hd : ∀ i, dupIn l₁ i = dupIn l₂ i := by
    intro i
    simp only [dupIn, (hp.map (·.id)).count_eq]
  unfold lintAll
  simp only [hd]
  exact hp.map _

/-- **The verdict is order-independent**: permuted incidents give the same ok. -/
theorem okAll_perm (F : Facts) {l₁ l₂ : List Incident} (hp : l₁.Perm l₂) :
    okAll F l₁ = okAll F l₂ := by
  unfold okAll
  exact Bool.eq_iff_iff.mpr (by simp only [List.all_eq_true]; exact
    ⟨fun h r hr => h r ((lintAll_perm F hp).mem_iff.mpr hr),
     fun h r hr => h r ((lintAll_perm F hp).mem_iff.mp hr)⟩)

/-! ## Completeness: what a passing lint means -/

/-- The Lean fields of an entry are complete and their refs exist: the verdict is one of the three and
is covered (an empirical check for `no`, a hardening task for `provable` / `partly`), the reason is not
blank, a named hardening task is a work graph id, and a named mistake class is a retro class.
-/
def LeanComplete (F : Facts) (i : Incident) : Prop :=
  (∃ v, verdict i = some v ∧ (v = .no → blank i.empiricalCheck = false) ∧
      (v ≠ .no → blank i.hardening = false)) ∧
    blank i.leanReason = false ∧
    (∀ h, i.hardening = some h → h ∈ taskIds F) ∧
    (∀ c, i.mistakeClass = some c → c ∈ F.classes)

/-- An entry is complete: its id is not duplicated, it has evidence, every evidence item has a known
kind and a well-formed ref, every commit ref is on main and every file ref exists, it has a fix task
and every fix and `also` task is a work graph id, repro and regression are not blank, the cause has a
status prefix, it has no `status` field, and its Lean fields are complete (`LeanComplete`).
-/
def Complete (F : Facts) (dup : Bool) (i : Incident) : Prop :=
  dup = false ∧ i.evidence ≠ [] ∧
    (∀ e ∈ i.evidence, kindOf e.kind ≠ none) ∧
    (∀ e ∈ i.evidence, evHolds F e .badRef = false) ∧
    (∀ e ∈ i.evidence, kindOf e.kind = some .commit → e.ref ∈ F.commits) ∧
    (∀ e ∈ i.evidence, kindOf e.kind = some .file → e.ref ∈ F.files) ∧
    i.fixTask ≠ none ∧ (∀ x ∈ fixTasks i, x ∈ taskIds F) ∧
    blank i.repro = false ∧ blank i.regression = false ∧ hasPrefix i.cause = true ∧
    i.hasStatus = false ∧ LeanComplete F i

/-- A string that names a verdict is not blank. -/
theorem verdictOf_not_blank (s : String) (v : Verdict) (h : verdictOf s = some v) :
    blank (some s) = false := by
  unfold verdictOf at h
  split at h <;> first | (simp at h; done) | decide | simp [blank]

/-- **The four verdict codes are silent exactly when the verdict is known and covered.**

(The four codes do not read the facts or `dup`.)
-/
theorem verdict_codes_iff (F : Facts) (dup : Bool) (i : Incident) :
    (holds F dup i .missingLeanVerdict = false ∧ holds F dup i .badLeanVerdict = false ∧
      holds F dup i .missingHardening = false ∧ holds F dup i .missingEmpiricalCheck = false) ↔
    ∃ v, verdict i = some v ∧ (v = .no → blank i.empiricalCheck = false) ∧
      (v ≠ .no → blank i.hardening = false) := by
  have hb : ∀ v, verdict i = some v → blank i.leanVerdict = false := by
    intro v hv
    unfold verdict at hv
    cases hl : i.leanVerdict with
    | none => simp [hl] at hv
    | some s => simp only [hl, Option.bind_some] at hv; exact verdictOf_not_blank s v hv
  simp only [holds, needsHardening]
  cases hv : verdict i with
  | none =>
    simp only [Option.isNone_none, Bool.and_true, Bool.not_eq_false', reduceCtorEq, false_and,
      exists_false, iff_false]
    intro h
    exact absurd h.1 (by cases blank i.leanVerdict <;> simp_all)
  | some v =>
    have := hb v hv
    cases v <;> simp [this]

/-- **One entry passes exactly when it is complete**: no error code holds iff `complete`. -/
theorem okOne_iff (F : Facts) (dup : Bool) (i : Incident) :
    (∀ k : Code, k.isError = true → holds F dup i k = false) ↔ Complete F dup i := by
  have hall : (∀ k : Code, k.isError = true → holds F dup i k = false) ↔
      (holds F dup i .dupId = false ∧ holds F dup i .noEvidence = false ∧
        holds F dup i .unknownKind = false ∧ holds F dup i .badRef = false ∧
        holds F dup i .commitNotOnMain = false ∧ holds F dup i .fileMissing = false ∧
        holds F dup i .missingFixTask = false ∧ holds F dup i .missingRepro = false ∧
        holds F dup i .missingRegression = false ∧ holds F dup i .noStatusPrefix = false ∧
        holds F dup i .statusField = false ∧
        (holds F dup i .missingLeanVerdict = false ∧ holds F dup i .badLeanVerdict = false ∧
          holds F dup i .missingHardening = false ∧ holds F dup i .missingEmpiricalCheck = false) ∧
        holds F dup i .missingLeanReason = false ∧ holds F dup i .unknownHardening = false ∧
        holds F dup i .unknownMistakeClass = false) := by
    constructor
    · intro h
      exact ⟨h _ rfl, h _ rfl, h _ rfl, h _ rfl, h _ rfl, h _ rfl, h _ rfl, h _ rfl, h _ rfl,
        h _ rfl, h _ rfl, ⟨h _ rfl, h _ rfl, h _ rfl, h _ rfl⟩, h _ rfl, h _ rfl, h _ rfl⟩
    · rintro ⟨h1, h2, h3, h4, h5, h6, h7, h8, h9, h10, h11, ⟨h12, h13, h14, h15⟩, h16, h17, h18⟩ k hk
      cases k <;> first | assumption | exact absurd hk (by decide)
  rw [hall, verdict_codes_iff]
  unfold Complete LeanComplete
  have hU : holds F dup i .unknownHardening = false ↔ ∀ h, i.hardening = some h → h ∈ taskIds F := by
    simp only [holds]
    cases i.hardening <;> simp
  have hC : holds F dup i .unknownMistakeClass = false ↔
      ∀ c, i.mistakeClass = some c → c ∈ F.classes := by
    simp only [holds]
    cases i.mistakeClass <;> simp
  rw [hU, hC]
  have hK : holds F dup i .unknownKind = false ↔ ∀ e ∈ i.evidence, kindOf e.kind ≠ none := by
    simp [holds, evHolds]
  have hR : holds F dup i .badRef = false ↔ ∀ e ∈ i.evidence, evHolds F e .badRef = false := by
    simp [holds]
  have hM : holds F dup i .commitNotOnMain = false ↔
      ∀ e ∈ i.evidence, kindOf e.kind = some .commit → e.ref ∈ F.commits := by
    simp [holds, evHolds]
  have hF : holds F dup i .fileMissing = false ↔
      ∀ e ∈ i.evidence, kindOf e.kind = some .file → e.ref ∈ F.files := by
    simp [holds, evHolds]
  have hX : holds F dup i .missingFixTask = false ↔
      i.fixTask ≠ none ∧ ∀ x ∈ fixTasks i, x ∈ taskIds F := by
    simp [holds, taskIds, Option.isSome_iff_ne_none]
  rw [hK, hR, hM, hF, hX]
  simp only [holds, List.isEmpty_eq_false_iff, Bool.not_eq_false', ne_eq, and_assoc]

/-- **The lint passes exactly when every entry is complete and every referenced task and class
exists** (`complete` includes: fix and `also` tasks and the hardening task are work graph ids, the
mistake class is a retro class, and the id is not duplicated in the list).
-/
theorem lint_ok_iff (F : Facts) (l : List Incident) :
    okAll F l = true ↔ ∀ i ∈ l, Complete F (dupIn l i) i := by
  unfold okAll lintAll
  simp only [List.all_eq_true, List.mem_map, forall_exists_index, and_imp,
    forall_apply_eq_imp_iff₂, lintOne, Bool.not_eq_true']
  refine forall₂_congr fun i _ => ?_
  rw [← okOne_iff]
  constructor
  · intro h k hk
    cases hh : holds F (dupIn l i) i k
    · rfl
    · have := h k ((mem_codes _ _ _ _).mpr hh)
      simp_all
  · intro h k hk
    have := (mem_codes _ _ _ _).mp hk
    cases he : k.isError
    · rfl
    · simp_all

/-- **A `no` verdict without an empirical check is refused**: if some entry's verdict is `no` and its
`empiricalCheck` is missing or blank, the lint does not pass.
-/
theorem no_without_empiricalCheck_refused (F : Facts) (l : List Incident) (i : Incident)
    (hi : i ∈ l) (hv : verdict i = some .no) (he : blank i.empiricalCheck = true) :
    okAll F l = false := by
  cases h : okAll F l
  · rfl
  · obtain ⟨-, -, -, -, -, -, -, -, -, -, -, -, ⟨v, hv', hno, -⟩, -⟩ := (lint_ok_iff F l).mp h i hi
    rw [hv] at hv'
    cases hv'
    simp [hno rfl] at he

/-- **A passing provable or partly entry names an existing hardening task.** -/
theorem ok_hardening_exists (F : Facts) (l : List Incident) (i : Incident)
    (hok : okAll F l = true) (hi : i ∈ l)
    (hv : verdict i = some .provable ∨ verdict i = some .partly) :
    ∃ h, i.hardening = some h ∧ h ∈ taskIds F := by
  obtain ⟨-, -, -, -, -, -, -, -, -, -, -, -, ⟨v, hv', -, hh⟩, -, hex, -⟩ :=
    (lint_ok_iff F l).mp hok i hi
  have hne : v ≠ .no := by
    rcases hv with hv | hv <;> rw [hv] at hv' <;> cases hv' <;> decide
  have hb := hh hne
  cases hx : i.hardening with
  | none => simp [blank, hx] at hb
  | some x => exact ⟨x, rfl, hex x hx⟩

/-! ## Examples -/

/-- A sample fact set for the `#guard` examples: task `a` done, task `b` claimed, task `c` open; one main commit, one file and one mistake class. -/
def sampleFacts : Facts :=
  let row (id : String) (ev ag : Option String) : Task :=
    { id, title := "", stream := "", milestone := none, deps := [], owner := "", writes := [],
      devices := [], needs := [], evidence := ev, agent := ag }
  { tasks := [row "a" (some "1c64c85") none, row "b" none (some "b"), row "c" none none],
    commits := ["1c64c85"], files := ["README.md"], classes := ["c-quota"] }

/-- A sample incident for the `#guard` examples: one main commit as evidence, fixed by task `a`,
verdict provable with hardening task `c`, no empirical check, class `c-quota`.
-/
def sampleIncident : Incident :=
  { id := "inc", cause := "CONFIRMED: x", evidence := [⟨"commit", "1c64c85"⟩], repro := some "r",
    fixTask := some "a", also := [], regression := some "g", hasStatus := false,
    leanVerdict := some "provable", leanReason := some "why", hardening := some "c",
    mistakeClass := some "c-quota" }

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
-- the Lean fields
#guard codes sampleFacts false { sampleIncident with leanVerdict := none } == [.missingLeanVerdict]
#guard codes sampleFacts false { sampleIncident with leanVerdict := some " " } == [.missingLeanVerdict]
#guard codes sampleFacts false { sampleIncident with leanVerdict := some "Provable" } == [.badLeanVerdict]
#guard codes sampleFacts false { sampleIncident with leanVerdict := some "maybe", hardening := none } == [.badLeanVerdict]
#guard codes sampleFacts false { sampleIncident with leanReason := none } == [.missingLeanReason]
#guard codes sampleFacts false { sampleIncident with leanReason := some "" } == [.missingLeanReason]
#guard codes sampleFacts false { sampleIncident with hardening := none } == [.missingHardening]
#guard codes sampleFacts false { sampleIncident with leanVerdict := some "partly", hardening := none } == [.missingHardening]
#guard codes sampleFacts false { sampleIncident with hardening := some "zz" } == [.unknownHardening]
#guard codes sampleFacts false { sampleIncident with hardening := some "" } == [.missingHardening, .unknownHardening]
#guard codes sampleFacts false { sampleIncident with leanVerdict := some "no", hardening := none } == [.missingEmpiricalCheck]
#guard codes sampleFacts false { sampleIncident with leanVerdict := some "no", hardening := none, empiricalCheck := some "ci: gate" } == []
#guard codes sampleFacts false { sampleIncident with leanVerdict := some "no", empiricalCheck := some "ci: gate" } == []
#guard codes sampleFacts false { sampleIncident with leanVerdict := some "no", hardening := some "zz", empiricalCheck := some "t" } == [.unknownHardening]
#guard codes sampleFacts false { sampleIncident with mistakeClass := none } == []
#guard codes sampleFacts false { sampleIncident with mistakeClass := some "c-nope" } == [.unknownMistakeClass]
#guard detail sampleFacts { sampleIncident with hardening := none } .missingHardening ==
  "hardening missing: a work graph task id (required when leanVerdict is provable)"
#guard detail sampleFacts { sampleIncident with mistakeClass := some "c-nope" } .unknownMistakeClass ==
  "mistakeClass 'c-nope' is not a class id of research/mistakes/ledger.json"
#guard verdictOf "no" == some .no && verdictOf "No" == none && verdictOf "" == none
#guard !okAll sampleFacts [{ sampleIncident with leanVerdict := some "no", empiricalCheck := some "  " }]

end Fw.Plan.Incident
