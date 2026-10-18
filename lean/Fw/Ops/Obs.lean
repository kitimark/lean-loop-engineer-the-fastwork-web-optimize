import Fw.Console.Alert
import Fw.Plan.Core

/-!
# Observed tool calls: the obs key and the per-(agent type, tool) summary (`ops.obs`)

Replaces console-api's TS stand-ins in `apps/console-api/src/spool/drain.ts` (task `lean-console-gaps`):

* **Key join.** An observation's idempotency key is `agent|event|id`, where `agent` is the
  `agent_id` (or `main` when there is none), and `id` is the `tool_use_id`, or the record's
  timestamp when the event carries no tool use (hook-only events). A hook record and a transcript
  record of the same tool call therefore get the same key, whatever their timestamps
  (`obsKey_tool_ts`).
* **Summary.** Tool calls (`PostToolUse`, `PostToolUseFailure`) grouped by (agent type, tool), with
  `main` and `?` for a missing agent type or tool name: the number of calls, of errors
  (`is_error = true`) and the summed `duration_ms` (missing = 0). Groups appear in the order of
  their first call. Proved: the groups are exactly the groups of the tool calls
  (`mem_groups`), each group appears once (`groups_nodup`), and every row holds the counts of its
  group (`summarize_row`).
-/
namespace Fw.Ops.Obs

/-! ## Key join -/

/-- The idempotency key of an observation: agent id (or `main`), event and tool-use id (or the
timestamp), joined by `|`.

$$\operatorname{obsKey}(i, e, u, t) = a \mathbin{+\!\!+} \texttt{"|"} \mathbin{+\!\!+} e \mathbin{+\!\!+} \texttt{"|"} \mathbin{+\!\!+} x, \quad a = \begin{cases} s & i = s \\ \texttt{"main"} & i = \bot \end{cases}, \quad x = \begin{cases} v & u = v \\ \operatorname{dec}(t) & u = \bot \end{cases} \qquad (i, u \in \mathrm{String} \cup \{\bot\},\ e \in \mathrm{String},\ t \in \mathbb{N}),\quad \text{where } \operatorname{dec}(t) = \text{the decimal numeral of } t\ \text{(an empty string } s \text{ or } v \text{ is kept as it is; only } \bot \text{ is replaced)}$$

The key names who did what, and which tool call or moment it was.
-/
def obsKey (agentId : Option String) (event : String) (toolUseId : Option String) (ts : Nat) : String :=
  agentId.getD "main" ++ "|" ++ event ++ "|" ++ toolUseId.getD (toString ts)

/-- With a tool-use id the key does not depend on the timestamp, so the hook record and the
transcript record of one tool call share a key.

$$\forall i \in \mathrm{String} \cup \{\bot\},\ e, v \in \mathrm{String},\ t_1, t_2 \in \mathbb{N}:\quad \operatorname{obsKey}(i, e, v, t_1) = \operatorname{obsKey}(i, e, v, t_2)$$

Two records of the same tool call get the same key at any times.
-/
theorem obsKey_tool_ts (i : Option String) (e v : String) (t₁ t₂ : Nat) :
    obsKey i e (some v) t₁ = obsKey i e (some v) t₂ := rfl

/-- Without a tool-use id the timestamp is the last part of the key.

$$\forall i \in \mathrm{String} \cup \{\bot\},\ e \in \mathrm{String},\ t \in \mathbb{N}:\quad \operatorname{obsKey}(i, e, \bot, t) = \operatorname{obsKey}(i, e, \operatorname{dec}(t), 0)$$

A hook-only event is keyed by its timestamp, exactly as if the timestamp were its tool-use id.
-/
theorem obsKey_no_tool (i : Option String) (e : String) (t : Nat) :
    obsKey i e none t = obsKey i e (some (toString t)) 0 := rfl

#guard obsKey none "Stop" none 42 == "main|Stop|42"
#guard obsKey (some "a1") "PostToolUse" (some "toolu_1") 7 == "a1|PostToolUse|toolu_1"
#guard obsKey (some "") "X" (some "") 7 == "|X|"

/-! ## Summary -/

/-- One observed line, as far as the summary reads it.

$$\ell = (\mathit{event}, \mathit{agentType}_\bot, \mathit{toolName}_\bot, \mathit{isError}_\bot, \mathit{durationMs}_\bot)$$

The fields of an `obs.jsonl` line that the tool-call summary uses.
-/
structure Line where
  event      : String
  agentType  : Option String := none
  toolName   : Option String := none
  isError    : Option Bool := none
  durationMs : Option Nat := none
deriving Repr, DecidableEq

/-- A line is a tool call when its event is `PostToolUse` or `PostToolUseFailure`.

$$\operatorname{isCall}(\ell) \iff \ell.\mathit{event} \in \{\texttt{"PostToolUse"}, \texttt{"PostToolUseFailure"}\}$$

Only finished tool calls count; every other hook event is ignored by the summary.
-/
def isCall (l : Line) : Bool := l.event == "PostToolUse" || l.event == "PostToolUseFailure"

/-- The group of a line: its agent type (`main` when missing) and its tool name (`?` when missing).

$$\operatorname{group}(\ell) = (\ell.\mathit{agentType} \text{ or } \texttt{"main"},\ \ell.\mathit{toolName} \text{ or } \texttt{"?"})$$

Lines are grouped by who called which tool.
-/
def group (l : Line) : String × String := (l.agentType.getD "main", l.toolName.getD "?")

/-- One summary row: a group and its counts.

$$r = (\mathit{agentType}, \mathit{toolName}, \mathit{calls}, \mathit{errors}, \mathit{totalMs})$$

The totals of one (agent type, tool) group.
-/
structure Row where
  agentType : String
  toolName  : String
  calls     : Nat
  errors    : Nat
  totalMs   : Nat
deriving Repr, DecidableEq

/-- The list without repeats, keeping first occurrences, skipping the elements of `seen`.

$$\operatorname{uniqAux}(S, [\,]) = [\,], \qquad \operatorname{uniqAux}(S, a :: w) = \begin{cases} \operatorname{uniqAux}(S, w) & a \in S \\ a :: \operatorname{uniqAux}(\{a\} \cup S, w) & a \notin S \end{cases}$$

Walk the list and keep each element the first time it is met.
-/
def uniqAux {α : Type} [DecidableEq α] : List α → List α → List α
  | _, [] => []
  | seen, a :: as => if a ∈ seen then uniqAux seen as else a :: uniqAux (a :: seen) as

/-- The list without repeats, in first-occurrence order.

$$\operatorname{uniq}(w) = \operatorname{uniqAux}(\emptyset, w)$$

Each element once, in the order it first appears.
-/
def uniq {α : Type} [DecidableEq α] (l : List α) : List α := uniqAux [] l

/-- The groups of the tool calls, in the order of their first call.

$$\operatorname{groups}(L) = \operatorname{uniq}([\operatorname{group}(\ell) \mid \ell \in L,\ \operatorname{isCall}(\ell)])$$

Every (agent type, tool) pair that made at least one call, once each.
-/
def groups (ls : List Line) : List (String × String) := uniq ((ls.filter isCall).map group)

/-- The row of group $k$: its tool calls, their errors and their summed duration.

$$\operatorname{row}(L, k) = (k_1, k_2, |C|, |[\ell \in C \mid \ell.\mathit{isError} = \mathrm{true}]|, \textstyle\sum_{\ell \in C} (\ell.\mathit{durationMs} \text{ or } 0)), \quad C = [\ell \in L \mid \operatorname{isCall}(\ell) \land \operatorname{group}(\ell) = k]$$

The counts of one group, read straight off the lines.
-/
def rowFor (ls : List Line) (k : String × String) : Row :=
  let c := ls.filter fun l => isCall l && group l == k
  ⟨k.1, k.2, c.length, (c.filter (·.isError == some true)).length, (c.map (·.durationMs.getD 0)).sum⟩

/-- The tool-call summary: one row per group, in the order of the group's first call.

$$\operatorname{summarize}(L) = [\operatorname{row}(L, k) \mid k \in \operatorname{groups}(L)]$$

Count calls, errors and time per (agent type, tool).
-/
def summarize (ls : List Line) : List Row := (groups ls).map (rowFor ls)

/-! ## Proofs -/

/-- Membership in `uniqAux`: an element of the list not already seen.

$$\forall S, w, x:\quad x \in \operatorname{uniqAux}(S, w) \iff x \in w \land x \notin S$$

`uniqAux` keeps exactly the unseen elements.
-/
theorem mem_uniqAux {α : Type} [DecidableEq α] (seen l : List α) (x : α) :
    x ∈ uniqAux seen l ↔ x ∈ l ∧ x ∉ seen := by
  induction l generalizing seen with
  | nil => simp [uniqAux]
  | cons a as ih =>
    by_cases h : a ∈ seen
    · simp only [uniqAux, h, ↓reduceIte, ih, List.mem_cons]
      constructor
      · rintro ⟨h1, h2⟩; exact ⟨Or.inr h1, h2⟩
      · rintro ⟨h1 | h1, h2⟩
        · subst h1; exact absurd h h2
        · exact ⟨h1, h2⟩
    · simp only [uniqAux, h, ↓reduceIte, List.mem_cons, ih]
      constructor
      · rintro (h1 | ⟨h1, h2⟩)
        · subst h1; exact ⟨Or.inl rfl, h⟩
        · exact ⟨Or.inr h1, fun h3 => h2 (Or.inr h3)⟩
      · rintro ⟨h1 | h1, h2⟩
        · exact Or.inl h1
        · by_cases hx : x = a
          · exact Or.inl hx
          · exact Or.inr ⟨h1, fun h3 => h3.elim hx h2⟩

/-- `uniqAux` has no repeats.

$$\forall S, w:\quad \operatorname{uniqAux}(S, w) \text{ has pairwise distinct elements}$$

Each kept element is kept once.
-/
theorem uniqAux_nodup {α : Type} [DecidableEq α] (seen l : List α) : (uniqAux seen l).Nodup := by
  induction l generalizing seen with
  | nil => exact List.nodup_nil
  | cons a as ih =>
    by_cases h : a ∈ seen
    · simp only [uniqAux, h, ↓reduceIte]; exact ih seen
    · simp only [uniqAux, h, ↓reduceIte]
      refine List.nodup_cons.mpr ⟨?_, ih _⟩
      intro hm
      exact ((mem_uniqAux _ _ _).mp hm).2 (List.mem_cons_self ..)

/-- The groups are exactly the groups of the tool calls.

$$\forall L, k:\quad k \in \operatorname{groups}(L) \iff \exists \ell \in L:\ \operatorname{isCall}(\ell) \land \operatorname{group}(\ell) = k$$

A group has a row exactly when some tool call falls in it.
-/
theorem mem_groups (ls : List Line) (k : String × String) :
    k ∈ groups ls ↔ ∃ l ∈ ls, isCall l = true ∧ group l = k := by
  simp [groups, uniq, mem_uniqAux, and_assoc]

/-- Each group appears once.

$$\forall L:\quad \operatorname{groups}(L) \text{ has pairwise distinct elements}$$

No (agent type, tool) pair gets two rows.
-/
theorem groups_nodup (ls : List Line) : (groups ls).Nodup := uniqAux_nodup _ _

/-- Every summary row holds the counts of its own group.

$$\forall L, r:\quad r \in \operatorname{summarize}(L) \implies (r.\mathit{agentType}, r.\mathit{toolName}) \in \operatorname{groups}(L) \land r = \operatorname{row}(L, (r.\mathit{agentType}, r.\mathit{toolName}))$$

A row's calls, errors and time are the counts over the tool calls of that group.
-/
theorem summarize_row (ls : List Line) (r : Row) (h : r ∈ summarize ls) :
    (r.agentType, r.toolName) ∈ groups ls ∧ r = rowFor ls (r.agentType, r.toolName) := by
  simp only [summarize, List.mem_map] at h
  obtain ⟨k, hk, rfl⟩ := h
  exact ⟨hk, rfl⟩

/-- Lines that are not tool calls change nothing.

$$\forall L, \ell:\quad \lnot\operatorname{isCall}(\ell) \implies \operatorname{summarize}(\ell :: L) = \operatorname{summarize}(L)$$

Non-tool events (starts, stops, prompts) never show up in the summary.
-/
theorem summarize_skip (ls : List Line) (l : Line) (h : isCall l = false) :
    summarize (l :: ls) = summarize ls := by
  simp [summarize, groups, rowFor, h]

/-! ## Examples -/

#guard summarize [] == []
#guard summarize [⟨"SubagentStart", some "b", none, none, none⟩] == []
#guard summarize [⟨"PostToolUse", some "b", some "Bash", none, some 100⟩,
    ⟨"PostToolUseFailure", some "b", some "Bash", some true, some 50⟩,
    ⟨"PostToolUse", none, none, some false, none⟩] ==
  [⟨"b", "Bash", 2, 1, 150⟩, ⟨"main", "?", 1, 0, 0⟩]
#guard groups [⟨"PostToolUse", some "x", some "T", none, none⟩, ⟨"PostToolUse", some "y", some "T", none, none⟩,
    ⟨"PostToolUse", some "x", some "T", none, none⟩] == [("x", "T"), ("y", "T")]

/-! ## Admission of spool records (task `task-state-truth`)

**Root cause (MEASURED on the main checkout's spool, 2026-10-18).** Since `emit.mjs` started writing
`background_tasks` on every `SubagentStop` record, the drain's strict zod schema refused each of
those records as an unknown key, counted it only as `invalid`, and so 6376 stops never became an
`agent.stop`: the board kept every such agent running. The schema decision now lives here: a record
is the list of its JSON fields. Only the **decision fields** are strict (`strict`): the event name,
the agent id, the time and the spawn guard's agent name (the task binding); a record whose decision
field is missing or does not fit is rejected with its reason. Every other known field is soft: a
missing required or ill-typed value is kept as null (an ill-typed optional one is left out) and noted; a missing optional one is left out; never a rejection;
an unknown field is kept out and named. Rejections, notes and unknown fields are all counted and
raised as one spool alert (`issuesOf`, `fieldAlert`). Proved: only decision fields decide a
rejection (`soft_never_rejects`), an extra unknown field never turns an accepted record into a
rejected one (`accept_extra`), the drain counts every line as accepted or rejected
(`drop_counted`), it reports every unknown field of an accepted line (`mem_unknown`), and every
rejected line raises the spool alert with its reason counted (`reject_alerts`).
-/

/-- The length of a string in UTF-16 code units, what zod's `.max` counts: 2 for a character above
U+FFFF, else 1.

$$\operatorname{len}_{16}(s) = \sum_{c \in s} \begin{cases} 2 & \operatorname{ord}(c) > \mathtt{0xFFFF} \\ 1 & \text{otherwise} \end{cases}$$

Count a string the way JavaScript does.
-/
def utf16Len (s : String) : Nat := s.toList.foldl (fun n c => n + if 0xFFFF < c.val.toNat then 2 else 1) 0

/-- A JSON field value as admission reads it: null, a string, a non-negative integer, a boolean, or
anything else (a negative or fractional number, an array, an object).

$$\mathrm{Val} = \{\mathrm{null}\} \cup \mathrm{str}(\mathrm{String}) \cup \mathrm{nat}(\mathbb{N}) \cup \mathrm{bool}(\mathbb{B}) \cup \{\mathrm{other}\}$$
-/
inductive Val where
  | null
  | str (s : String)
  | nat (n : Nat)
  | bool (b : Bool)
  | other
deriving Repr, DecidableEq

/-- The type of a known field: a string of at most `max` UTF-16 units, a non-empty such string, a
non-negative integer, or a boolean.

$$\mathrm{Ty} = \mathrm{str}(m) \cup \mathrm{name}(m) \cup \{\mathrm{nat}, \mathrm{bool}\}$$
-/
inductive Ty where
  | str (max : Nat)
  | name (max : Nat)
  | nat
  | bool
deriving Repr, DecidableEq

/-- The spec of a known field: name, type, whether null is allowed, whether the field must be
present, and whether it is a decision field (strict: a bad value rejects the record).

$$\mathit{sp} = (\mathit{name}, \mathit{ty}, \mathit{nullable}, \mathit{required}, \mathit{strict})$$
-/
structure Spec where
  name     : String
  ty       : Ty
  nullable : Bool
  required : Bool
  strict   : Bool
deriving Repr, DecidableEq

/-- The known spool fields, as in the zod `ObsRecord` (`packages/contracts/src/obs.ts`). Strict
(decision fields, marked $^{s}$): `agent_id` (required, nullable, non-empty, at most 120 units: a
contract id, since it is a life key), `hook_event_name`
(required, not null, non-empty), `agent_name` (optional, nullable, non-empty, at most 120 units: a
contract id), `ts` (required, not null). All others are soft: six required nullable fields and ten
optional nullable fields.

$$\mathit{specs} = [\texttt{agent\_id}{:}\,\mathrm{name}(120)^{s}, \texttt{agent\_type}{:}\,\mathrm{str}(200), \texttt{hook\_event\_name}{:}\,\mathrm{name}(200)^{!s}, \texttt{tool\_name}{:}\,\mathrm{str}(200), \texttt{tool\_use\_id}{:}\,\mathrm{str}(200), \texttt{duration\_ms}{:}\,\mathrm{nat}, \texttt{is\_error}{:}\,\mathrm{bool}, \texttt{verb}{:}\,\mathrm{str}(40), \texttt{agent\_name}{:}\,\mathrm{name}(120)^{?s}, \texttt{seen\_by}{:}\,\mathrm{str}(40)^{?}, \texttt{role}{:}\,\mathrm{str}(200)^{?}, \texttt{want\_kind}{:}\,\mathrm{str}(40)^{?}, \texttt{got\_kind}{:}\,\mathrm{str}(40)^{?}, \texttt{isolation}{:}\,\mathrm{bool}^{?}, \texttt{depth}{:}\,\mathrm{nat}^{?}, \texttt{has\_name}{:}\,\mathrm{bool}^{?}, \texttt{notification\_type}{:}\,\mathrm{str}(40)^{?}, \texttt{message\_len}{:}\,\mathrm{nat}^{?}, \texttt{background\_tasks}{:}\,\mathrm{nat}^{?}, \texttt{ts}{:}\,\mathrm{nat}^{!s}]$$

Unmarked: required and nullable; $^{?}$: optional and nullable; $^{!}$: required, not nullable;
$^{s}$: strict.
-/
def specs : List Spec := [
  ⟨"agent_id", .name 120, true, true, true⟩, ⟨"agent_type", .str 200, true, true, false⟩,
  ⟨"hook_event_name", .name 200, false, true, true⟩, ⟨"tool_name", .str 200, true, true, false⟩,
  ⟨"tool_use_id", .str 200, true, true, false⟩, ⟨"duration_ms", .nat, true, true, false⟩,
  ⟨"is_error", .bool, true, true, false⟩, ⟨"verb", .str 40, true, true, false⟩,
  ⟨"agent_name", .name 120, true, false, true⟩, ⟨"seen_by", .str 40, true, false, false⟩,
  ⟨"role", .str 200, true, false, false⟩, ⟨"want_kind", .str 40, true, false, false⟩,
  ⟨"got_kind", .str 40, true, false, false⟩, ⟨"isolation", .bool, true, false, false⟩,
  ⟨"depth", .nat, true, false, false⟩, ⟨"has_name", .bool, true, false, false⟩,
  ⟨"notification_type", .str 40, true, false, false⟩, ⟨"message_len", .nat, true, false, false⟩,
  ⟨"background_tasks", .nat, true, false, false⟩, ⟨"ts", .nat, false, true, true⟩]

/-- Does a value fit a spec: null when nullable, a string within the length (non-empty for a name),
a natural for `nat`, a boolean for `bool`; `other` never fits.

$$\operatorname{fits}(\mathit{sp}, v) \iff (v = \mathrm{null} \land \mathit{sp}.\mathit{nullable}) \lor (v = \mathrm{str}(s) \land \mathit{sp}.\mathit{ty} = \mathrm{str}(m) \land \operatorname{len}_{16}(s) \le m) \lor (v = \mathrm{str}(s) \land \mathit{sp}.\mathit{ty} = \mathrm{name}(m) \land 0 < \operatorname{len}_{16}(s) \le m) \lor (v = \mathrm{nat}(n) \land \mathit{sp}.\mathit{ty} = \mathrm{nat}) \lor (v = \mathrm{bool}(b) \land \mathit{sp}.\mathit{ty} = \mathrm{bool})$$

Check one value against its field's type.
-/
def Spec.fits (sp : Spec) : Val → Bool
  | .null => sp.nullable
  | .str s => match sp.ty with
    | .str m => decide (utf16Len s ≤ m)
    | .name m => decide (0 < utf16Len s ∧ utf16Len s ≤ m)
    | _ => false
  | .nat _ => sp.ty == .nat
  | .bool _ => sp.ty == .bool
  | .other => false

/-- A field name is known when some spec has it.

$$\operatorname{known}(x) \iff \exists \mathit{sp} \in \mathit{specs}:\ \mathit{sp}.\mathit{name} = x$$

Is the field in the spec list.
-/
def known (x : String) : Bool := specs.any (·.name == x)

/-- The value of field `x` in a record: that of its first occurrence, none when absent.

$$\operatorname{look}(F, x) = \begin{cases} v & (x, v) \text{ is the first pair of } F \text{ with name } x \\ \bot & \text{no pair of } F \text{ has name } x \end{cases}$$

Read one field of a record.
-/
def look (fs : List (String × Val)) (x : String) : Option Val := (fs.find? (·.1 == x)).map (·.2)

/-- Why a spool line was rejected, or why a soft field was noted: not a JSON object, a field missing,
or a field whose value does not fit its spec.

$$\mathrm{Why} = \{\mathrm{json}\} \cup \mathrm{missing}(\mathrm{String}) \cup \mathrm{invalid}(\mathrm{String})$$
-/
inductive Why where
  | json
  | missing (field : String)
  | invalid (field : String)
deriving Repr, DecidableEq

/-- The name of a reason, as the wire and `spool-rejects.jsonl` write it.

$$\operatorname{name}(\mathrm{json}) = \texttt{json},\quad \operatorname{name}(\mathrm{missing}(x)) = x \cdot \texttt{:missing},\quad \operatorname{name}(\mathrm{invalid}(x)) = x \cdot \texttt{:invalid}$$

Spell a reason as text.
-/
def Why.name : Why → String
  | .json => "json"
  | .missing x => x ++ ":missing"
  | .invalid x => x ++ ":invalid"

/-- The error of one spec on a record: missing when required and absent, invalid when present and not
fitting, none otherwise.

$$\operatorname{err}(F, \mathit{sp}) = \begin{cases} \mathrm{missing}(\mathit{sp}.\mathit{name}) & \operatorname{look}(F, \mathit{sp}.\mathit{name}) = \bot \land \mathit{sp}.\mathit{required} \\ \mathrm{invalid}(\mathit{sp}.\mathit{name}) & \operatorname{look}(F, \mathit{sp}.\mathit{name}) = v \land \lnot\operatorname{fits}(\mathit{sp}, v) \\ \bot & \text{otherwise} \end{cases}$$

Find what is wrong with one field.
-/
def Spec.err (fs : List (String × Val)) (sp : Spec) : Option Why :=
  match look fs sp.name with
  | none => if sp.required then some (.missing sp.name) else none
  | some v => if sp.fits v then none else some (.invalid sp.name)

/-- The kept pair of one spec: the value when it fits; null when it is missing or does not fit and
the field is required; nothing otherwise.

$$\operatorname{keep}(F, \mathit{sp}) = \begin{cases} (\mathit{sp}.\mathit{name}, v) & \operatorname{look}(F, \mathit{sp}.\mathit{name}) = v \land \operatorname{fits}(\mathit{sp}, v) \\ (\mathit{sp}.\mathit{name}, \mathrm{null}) & \lnot(\operatorname{look}(F, \mathit{sp}.\mathit{name}) = v \land \operatorname{fits}(\mathit{sp}, v)) \land \mathit{sp}.\mathit{required} \\ \bot & \text{otherwise} \end{cases}$$

Keep a good value, and put null in place of a bad or missing required one.
-/
def Spec.keep (fs : List (String × Val)) (sp : Spec) : Option (String × Val) :=
  match look fs sp.name with
  | some v => if sp.fits v then some (sp.name, v) else if sp.required then some (sp.name, .null) else none
  | none => if sp.required then some (sp.name, .null) else none

/-- The verdict on a record: accepted with its kept known fields, the names of its unknown fields and
the notes on its soft fields, or rejected with a reason.

$$\mathrm{Verdict} = \mathrm{accept}(K, U, N) \cup \mathrm{reject}(w)$$
-/
inductive Verdict where
  | accept (kept : List (String × Val)) (unknown : List String) (notes : List Why)
  | reject (why : Why)
deriving Repr, DecidableEq

/-- The rejection reason of a verdict, none for an accepted record.

$$\operatorname{why}(\mathrm{reject}(w)) = w,\qquad \operatorname{why}(\mathrm{accept}(K, U, N)) = \bot$$

The reason a record was refused, if it was.
-/
def Verdict.why? : Verdict → Option Why
  | .reject w => some w
  | .accept .. => none

/-- The decision fields: the specs marked strict.

$$\mathit{strictSpecs} = [\mathit{sp} \in \mathit{specs} \mid \mathit{sp}.\mathit{strict}]$$

The fields whose value a decision reads.
-/
def strictSpecs : List Spec := specs.filter (·.strict)

/-- **Admission of a record**: rejected with the first error of a decision field, in spec order;
otherwise accepted, keeping the known fields in spec order (a soft field that is missing or does not
fit becomes null when required and is left out when optional), listing the unknown field names in
record order and the errors of the soft fields in spec order.

$$\operatorname{admit}(F) = \begin{cases} \mathrm{reject}(w) & w = \text{the first } \operatorname{err}(F, \mathit{sp}) \ne \bot,\ \mathit{sp} \in \mathit{strictSpecs} \\ \mathrm{accept}\big([\, \operatorname{keep}(F, \mathit{sp}) \ne \bot : \mathit{sp} \in \mathit{specs} \,],\ [\, x : (x, \_) \in F,\ \lnot\operatorname{known}(x) \,],\ [\, \operatorname{err}(F, \mathit{sp}) \ne \bot : \mathit{sp} \in \mathit{specs},\ \lnot\mathit{sp}.\mathit{strict} \,]\big) & \text{no strict spec has an error} \end{cases}$$

Refuse a record only for a bad decision field; keep everything else, noting what was wrong.
-/
def admit (fs : List (String × Val)) : Verdict :=
  match strictSpecs.findSome? (Spec.err fs) with
  | some w => .reject w
  | none => .accept (specs.filterMap (Spec.keep fs)) ((fs.map (·.1)).filter (!known ·))
      ((specs.filter (!·.strict)).filterMap (Spec.err fs))

/-- Appending a pair adds a value only for a name that had none.

$$\forall F, x, v, y:\quad \operatorname{look}(F \mathbin{+\!\!+} [(x, v)], y) = \begin{cases} \operatorname{look}(F, y) & \operatorname{look}(F, y) \ne \bot \\ v & \operatorname{look}(F, y) = \bot \land x = y \\ \bot & \operatorname{look}(F, y) = \bot \land x \ne y \end{cases}$$

A later duplicate of a field never changes its value.
-/
theorem look_append (fs : List (String × Val)) (x : String) (v : Val) (y : String) :
    look (fs ++ [(x, v)]) y = (look fs y).or (if x = y then some v else none) := by
  unfold look
  rw [List.find?_append]
  cases fs.find? (·.1 == y) with
  | some p => simp
  | none => by_cases h : x = y <;> simp [h]

/-- `findSome?` agrees for two functions that agree on the list.

$$\forall f, g, l:\quad (\forall a \in l:\ f(a) = g(a)) \Rightarrow \operatorname{findSome}(f, l) = \operatorname{findSome}(g, l)$$
-/
private theorem findSome?_congr {α β : Type} {f g : α → Option β} :
    ∀ {l : List α}, (∀ a ∈ l, f a = g a) → l.findSome? f = l.findSome? g
  | [], _ => rfl
  | a :: l, h => by
    simp only [List.findSome?_cons, h a (List.mem_cons_self ..),
      findSome?_congr (fun b hb => h b (List.mem_cons_of_mem _ hb))]

/-- `filterMap` agrees for two functions that agree on the list.

$$\forall f, g, l:\quad (\forall a \in l:\ f(a) = g(a)) \Rightarrow \operatorname{filterMap}(f, l) = \operatorname{filterMap}(g, l)$$
-/
private theorem filterMap_congr' {α β : Type} {f g : α → Option β} :
    ∀ {l : List α}, (∀ a ∈ l, f a = g a) → l.filterMap f = l.filterMap g
  | [], _ => rfl
  | a :: l, h => by
    simp only [List.filterMap_cons, h a (List.mem_cons_self ..),
      filterMap_congr' (fun b hb => h b (List.mem_cons_of_mem _ hb))]

/-- Every spec name is known.

$$\forall \mathit{sp} \in \mathit{specs}:\quad \operatorname{known}(\mathit{sp}.\mathit{name}) = \mathrm{true}$$
-/
private theorem known_of_spec {sp : Spec} (h : sp ∈ specs) : known sp.name = true :=
  List.any_eq_true.mpr ⟨sp, h, by simp⟩

/-- **Only decision fields decide a rejection** (`soft_never_rejects`): two records whose decision
fields read the same get the same rejection reason (or are both accepted), whatever their soft and
unknown fields hold.

$$\forall F, G:\quad (\forall \mathit{sp} \in \mathit{strictSpecs}:\ \operatorname{look}(F, \mathit{sp}.\mathit{name}) = \operatorname{look}(G, \mathit{sp}.\mathit{name})) \Rightarrow \operatorname{why}(\operatorname{admit}(F)) = \operatorname{why}(\operatorname{admit}(G))$$

A soft or unknown field never decides whether a line is refused.
-/
theorem soft_never_rejects {fs gs : List (String × Val)}
    (h : ∀ sp ∈ strictSpecs, look fs sp.name = look gs sp.name) :
    (admit fs).why? = (admit gs).why? := by
  have he : strictSpecs.findSome? (Spec.err fs) = strictSpecs.findSome? (Spec.err gs) :=
    findSome?_congr fun sp hs => by simp only [Spec.err, h sp hs]
  unfold admit
  rw [he]
  split <;> rfl

/-- **A soft or unknown field never rejects**: adding a field whose name no strict spec has, with any
value, leaves the rejection reason as it was.

$$\forall F, x, v:\quad (\forall \mathit{sp} \in \mathit{strictSpecs}:\ \mathit{sp}.\mathit{name} \ne x) \Rightarrow \operatorname{why}(\operatorname{admit}(F \mathbin{+\!\!+} [(x, v)])) = \operatorname{why}(\operatorname{admit}(F))$$

Whatever a non-decision field holds, a line is refused only if it was refused without it.
-/
theorem soft_extra (fs : List (String × Val)) {x : String} (v : Val)
    (hx : ∀ sp ∈ strictSpecs, sp.name ≠ x) :
    (admit (fs ++ [(x, v)])).why? = (admit fs).why? :=
  soft_never_rejects fun sp hs => by
    rw [look_append]; simp [Ne.symm (hx sp hs)]

/-- **An extra unknown field never rejects a record** (`accept_extra`): a record that differs from an
accepted one only by one more field of an unknown name is accepted, with the same kept fields and
notes and that name added to its unknown names.

$$\forall F, K, U, N, x, v:\quad \operatorname{admit}(F) = \mathrm{accept}(K, U, N) \land \lnot\operatorname{known}(x) \Rightarrow \operatorname{admit}(F \mathbin{+\!\!+} [(x, v)]) = \mathrm{accept}(K, U \mathbin{+\!\!+} [x], N)$$

An unknown field is only named, never judged.
-/
theorem accept_extra {fs k : List (String × Val)} {u : List String} {n : List Why}
    (h : admit fs = .accept k u n) (x : String) (v : Val) (hx : known x = false) :
    admit (fs ++ [(x, v)]) = .accept k (u ++ [x]) n := by
  have hl : ∀ sp ∈ specs, look (fs ++ [(x, v)]) sp.name = look fs sp.name := by
    intro sp hs
    have hne : x ≠ sp.name := fun e => by rw [e, known_of_spec hs] at hx; cases hx
    rw [look_append]; simp [hne]
  have hsub : ∀ {l : List Spec}, (∀ sp ∈ l, sp ∈ specs) →
      ∀ sp ∈ l, Spec.err (fs ++ [(x, v)]) sp = Spec.err fs sp := fun hl' sp hs => by
    simp only [Spec.err, hl sp (hl' sp hs)]
  have he : strictSpecs.findSome? (Spec.err (fs ++ [(x, v)])) = strictSpecs.findSome? (Spec.err fs) :=
    findSome?_congr (hsub fun sp hs => (List.mem_filter.mp hs).1)
  have hn : ((specs.filter (!·.strict)).filterMap (Spec.err (fs ++ [(x, v)]))) =
      (specs.filter (!·.strict)).filterMap (Spec.err fs) :=
    filterMap_congr' (hsub fun sp hs => (List.mem_filter.mp hs).1)
  have hk : specs.filterMap (Spec.keep (fs ++ [(x, v)])) = specs.filterMap (Spec.keep fs) :=
    filterMap_congr' fun sp hs => by simp only [Spec.keep, hl sp hs]
  unfold admit at h ⊢
  rw [he, hk, hn]
  split at h
  · cases h
  · cases h
    simp [hx]

/-- The verdict on a spool line: a line that is not a JSON object is rejected (`json`); an object is
admitted by its fields.

$$\operatorname{verdict}(\bot) = \mathrm{reject}(\mathrm{json}),\qquad \operatorname{verdict}(F) = \operatorname{admit}(F)$$

Judge one raw line.
-/
def verdictOf : Option (List (String × Val)) → Verdict
  | none => .reject .json
  | some fs => admit fs

/-- The accepted lines of a drain: kept fields, unknown names and notes, in line order.

$$\operatorname{acc}(L) = [\, (K, U, N) : \ell \in L,\ \operatorname{verdict}(\ell) = \mathrm{accept}(K, U, N) \,]$$

The lines that got in.
-/
def acceptedOf (ls : List (Option (List (String × Val)))) :
    List (List (String × Val) × List String × List Why) :=
  ls.filterMap fun l => match verdictOf l with
    | .accept k u n => some (k, u, n)
    | .reject _ => none

/-- The rejection reasons of a drain, one per rejected line, in line order.

$$\operatorname{rej}(L) = [\, w : \ell \in L,\ \operatorname{verdict}(\ell) = \mathrm{reject}(w) \,]$$

Why each refused line was refused.
-/
def rejectedOf (ls : List (Option (List (String × Val)))) : List Why :=
  ls.filterMap fun l => (verdictOf l).why?

/-- The unknown field names of a drain's accepted lines, one entry per occurrence.

$$\operatorname{unk}(L) = \operatorname{concat}[\, U : (K, U, N) \in \operatorname{acc}(L) \,]$$

Every unknown field seen, with repeats.
-/
def unknownOf (ls : List (Option (List (String × Val)))) : List String :=
  (acceptedOf ls).flatMap (·.2.1)

/-- **The drain drops no line uncounted** (`drop_counted`): every line is accepted or rejected with a
reason, so the two counts add up to the number of lines.

$$\forall L:\quad |\operatorname{acc}(L)| + |\operatorname{rej}(L)| = |L|$$

No line disappears without being counted.
-/
theorem drop_counted (ls : List (Option (List (String × Val)))) :
    (acceptedOf ls).length + (rejectedOf ls).length = ls.length := by
  induction ls with
  | nil => rfl
  | cons l ls ih =>
    simp only [acceptedOf, rejectedOf, List.filterMap_cons] at ih ⊢
    rcases h : verdictOf l with ⟨k, u, n⟩ | w
    · have e : (Verdict.accept k u n).why? = none := rfl
      simp only [e, List.length_cons]; omega
    · have e : (Verdict.reject w).why? = some w := rfl
      simp only [e, List.length_cons]; omega

/-- The unknown names of an accepted record are its field names that are not known.

$$\forall F, K, U, N:\quad \operatorname{admit}(F) = \mathrm{accept}(K, U, N) \Rightarrow U = [\, x : (x, \_) \in F,\ \operatorname{known}(x) = \mathrm{false} \,]$$
-/
private theorem unknown_of_accept {fs k : List (String × Val)} {u : List String} {n : List Why}
    (ha : admit fs = .accept k u n) : u = (fs.map (·.1)).filter (!known ·) := by
  unfold admit at ha; split at ha
  · cases ha
  · cases ha; rfl

/-- **Every unknown field is reported**: a name is among the drain's unknown names exactly when some
accepted line has a field of that name and the name is not known.

$$\forall L, x:\quad x \in \operatorname{unk}(L) \iff \exists F:\ \mathrm{some}(F) \in L \land (\exists K, U, N:\ \operatorname{admit}(F) = \mathrm{accept}(K, U, N)) \land x \in [\, y : (y, \_) \in F \,] \land \lnot\operatorname{known}(x)$$

An unknown field of an accepted line is always named.
-/
theorem mem_unknown (ls : List (Option (List (String × Val)))) (x : String) :
    x ∈ unknownOf ls ↔ ∃ fs, some fs ∈ ls ∧ (∃ k u n, admit fs = .accept k u n) ∧
      x ∈ fs.map (·.1) ∧ known x = false := by
  simp only [unknownOf, acceptedOf, List.mem_flatMap, List.mem_filterMap]
  constructor
  · rintro ⟨⟨k, u, n⟩, ⟨l, hl, hv⟩, hx⟩
    cases l with
    | none => simp [verdictOf] at hv
    | some fs =>
      simp only [verdictOf] at hv
      split at hv
      · rename_i k' u' n' ha
        cases hv
        rw [unknown_of_accept ha, List.mem_filter] at hx
        exact ⟨fs, hl, ⟨k, u, n, ha⟩, hx.1, by simpa using hx.2⟩
      · cases hv
  · rintro ⟨fs, hl, ⟨k, u, n, ha⟩, hx, hk⟩
    refine ⟨(k, u, n), ⟨some fs, hl, by simp [verdictOf, ha]⟩, ?_⟩
    rw [unknown_of_accept ha, List.mem_filter]
    exact ⟨hx, by simp [hk]⟩

/-- The issues of one verdict: a rejection as `rejected:` and its reason; for an accepted record its
soft-field notes, then its unknown fields marked `:unknown`.

$$\operatorname{issues}(\mathrm{reject}(w)) = [\texttt{rejected:} \cdot \operatorname{name}(w)],\qquad \operatorname{issues}(\mathrm{accept}(K, U, N)) = [\, \operatorname{name}(w) : w \in N \,] \mathbin{+\!\!+} [\, x \cdot \texttt{:unknown} : x \in U \,]$$

What a person should look at in one line.
-/
def Verdict.issues : Verdict → List String
  | .reject w => ["rejected:" ++ w.name]
  | .accept _ u n => n.map Why.name ++ u.map (· ++ ":unknown")

/-- The issues of a drain, one entry per occurrence, in line order.

$$\operatorname{issues}(L) = \operatorname{concat}[\, \operatorname{issues}(\operatorname{verdict}(\ell)) : \ell \in L \,]$$

Everything about the drained lines a person should look at.
-/
def issuesOf (ls : List (Option (List (String × Val)))) : List String :=
  ls.flatMap fun l => (verdictOf l).issues

/-- The issue names with their counts, in first-seen order.

$$\operatorname{counts}(U) = [\, (x, |[\, y \in U : y = x \,]|) : x \in \operatorname{uniq}(U) \,]$$

Count each issue once per occurrence.
-/
def fieldCounts (u : List String) : List (String × Nat) := (uniq u).map fun x => (x, u.count x)

/-- The owner name of the spool alert step (`Fw.Console.Alert.stepId (some "spool") now`).

$$\operatorname{spoolOwner} = \texttt{spool}$$
-/
def spoolOwner : String := "spool"

/-- The JavaScript (UTF-16) length of one character: 2 above U+FFFF, else 1.

$$u(c) = \begin{cases} 2 & \operatorname{code}(c) > \texttt{0xFFFF} \\ 1 & \text{otherwise} \end{cases}$$

How many UTF-16 units JavaScript spends on the character.
-/
def u16 (c : Char) : Nat := if 0xFFFF < c.val.toNat then 2 else 1

/-- The longest prefix of a character list whose UTF-16 length fits a budget.

$$\operatorname{take}_{16}(b, [\,]) = [\,],\qquad \operatorname{take}_{16}(b, c :: l) = \begin{cases} c :: \operatorname{take}_{16}(b - u(c), l) & u(c) \le b \\ [\,] & \text{otherwise} \end{cases}$$

Keep characters from the front while they still fit.
-/
def takeU16 : Nat → List Char → List Char
  | _, [] => []
  | b, c :: l => if u16 c ≤ b then c :: takeU16 (b - u16 c) l else []

/-- The JavaScript length of a string is the sum of its characters' UTF-16 lengths.

$$\forall s:\quad \operatorname{utf16}(s) = \textstyle\sum_{c \in s} u(c)$$

Counting the whole string equals adding up each character.
-/
theorem utf16Len_eq (s : String) : utf16Len s = (s.toList.map u16).sum := by
  unfold utf16Len
  suffices h : ∀ (l : List Char) (a : Nat),
      l.foldl (fun n c => n + if 0xFFFF < c.val.toNat then 2 else 1) a = a + (l.map u16).sum by
    simpa using h s.toList 0
  intro l
  induction l with
  | nil => intro a; simp
  | cons c l ih => intro a; simp only [List.foldl_cons, ih, List.map_cons, List.sum_cons, u16]; omega

/-- A capped prefix fits its budget.

$$\forall b, l:\quad \textstyle\sum_{c \in \operatorname{take}_{16}(b, l)} u(c) \le b$$

The kept prefix never exceeds the budget.
-/
theorem takeU16_le (b : Nat) (l : List Char) : ((takeU16 b l).map u16).sum ≤ b := by
  induction l generalizing b with
  | nil => simp [takeU16]
  | cons c l ih =>
    unfold takeU16
    split
    · have := ih (b - u16 c); simp only [List.map_cons, List.sum_cons]; omega
    · simp

/-- The fixed start of the spool alert title (25 UTF-16 units).

$$H = \text{“Spool lines need a look: ”}$$

What every spool alert title starts with.
-/
def alertHead : String := "Spool lines need a look: "
/-- The fixed end of the spool alert title (51 UTF-16 units).

$$T = \text{“; fix emit.mjs or Fw.Ops.Obs.specs, then press Done”}$$

What every spool alert title ends with.
-/
def alertTail : String := "; fix emit.mjs or Fw.Ops.Obs.specs, then press Done"

/-- The issue list of the spool alert as characters: `x₁ xn₁, x₂ xn₂, …`.

$$N(C) = \text{“}x_1\ \texttt{x}n_1\texttt{, }\dots\texttt{, }x_k\ \texttt{x}n_k\text{”},\quad C = [(x_1, n_1), \dots, (x_k, n_k)]\ (N([\,]) = \varepsilon)$$

Each issue with its count, comma separated.
-/
def alertNames (cs : List (String × Nat)) : List Char :=
  (", ".intercalate (cs.map fun (x, n) => s!"{x} x{n}")).toList

/-- The spool alert title: the issue list `x₁ xn₁, …` cut to 123 UTF-16 units (an ellipsis marks a cut)
between a fixed head and tail, so it fits the 200-unit step title.

$$\operatorname{title}(C) = H \cdot \operatorname{take}_{16}(123, N) \cdot e \cdot T,\quad N = N(C),\quad e = \begin{cases} \text{“…”} & |\operatorname{take}_{16}(123, N)| < |N| \\ \varepsilon & \text{otherwise} \end{cases}$$

Name every issue with its count, cut short when the list is long.
-/
def alertTitle (cs : List (String × Nat)) : String :=
  let names := alertNames cs
  let kept := takeU16 123 names
  String.ofList (alertHead.toList ++ kept ++ (if kept.length < names.length then ['…'] else []) ++ alertTail.toList)

/-- **The title fits**: the spool alert title is at most 200 UTF-16 units (the contract's step title).

$$\forall C:\quad \operatorname{utf16}(\operatorname{title}(C)) \le 200$$

The alert title is never too long for the board.
-/
theorem alertTitle_le (cs : List (String × Nat)) : utf16Len (alertTitle cs) ≤ 200 := by
  rw [utf16Len_eq]
  unfold alertTitle
  simp only [String.toList_ofList]
  have hk := takeU16_le 123 (alertNames cs)
  have hh : (alertHead.toList.map u16).sum = 25 := by decide
  have ht : (alertTail.toList.map u16).sum = 51 := by decide
  have he : u16 '…' = 1 := by decide
  split <;> simp only [List.map_append, List.sum_append, hh, ht, List.map_cons, List.map_nil,
    List.sum_cons, List.sum_nil, he] <;> omega

/-- **The spool alert**: none when there is no issue or a spool alert is still open; otherwise a step
`alert-spool-<now>` titled with each issue and its count (`alertTitle`).

$$\operatorname{fieldAlert}(t, O, C) = \begin{cases} \bot & C = [\,] \lor \exists \mathit{id} \in O:\ \operatorname{owner}(\mathit{id}) = \texttt{spool} \\ (s, \texttt{alert:} \cdot s, \operatorname{title}(C)) & \text{otherwise} \end{cases},\quad s = \operatorname{stepId}(\texttt{spool}, t)$$

Raise one alert for all spool problems, unless one is already open.
-/
def fieldAlert (now : Nat) (opn : List String) (cs : List (String × Nat)) :
    Option (String × String × String) :=
  if cs.isEmpty || opn.any (fun id => Fw.Console.Alert.owner id == some spoolOwner) then none
  else
    let id := Fw.Console.Alert.stepId (some spoolOwner) now
    some (id, "alert:" ++ id, alertTitle cs)

/-- A spool alert is raised exactly when there is an issue and no spool alert is open.

$$\forall t, O, C:\quad \operatorname{fieldAlert}(t, O, C) \ne \bot \iff C \ne [\,] \land \lnot\exists \mathit{id} \in O:\ \operatorname{owner}(\mathit{id}) = \texttt{spool}$$

The alert fires on any issue while none is open.
-/
theorem fieldAlert_some_iff (t : Nat) (opn : List String) (cs : List (String × Nat)) :
    fieldAlert t opn cs ≠ none ↔
      cs ≠ [] ∧ ¬ ∃ id ∈ opn, Fw.Console.Alert.owner id = some spoolOwner := by
  unfold fieldAlert
  by_cases h : (cs.isEmpty || opn.any (fun id => Fw.Console.Alert.owner id == some spoolOwner)) = true
  · simp only [h, ↓reduceIte, ne_eq, not_true_eq_false, false_iff, not_and, Classical.not_not]
    simp only [Bool.or_eq_true, List.isEmpty_iff, List.any_eq_true, beq_iff_eq] at h
    intro hc
    rcases h with h | h
    · exact absurd h hc
    · exact h
  · simp only [h, Bool.false_eq_true, ↓reduceIte, ne_eq, reduceCtorEq, not_false_eq_true, true_iff]
    simp only [Bool.or_eq_true, List.isEmpty_iff, List.any_eq_true, beq_iff_eq, not_or] at h
    exact ⟨h.1, h.2⟩

/-- **Every issue raises the alert, counted**: an issue in the list makes the spool alert fire (when
none is open) and appears in the counts with a positive count.

$$\forall t, O, I, x:\quad x \in I \land \lnot\exists \mathit{id} \in O:\ \operatorname{owner}(\mathit{id}) = \texttt{spool} \Rightarrow \operatorname{fieldAlert}(t, O, \operatorname{counts}(I)) \ne \bot \land \exists n > 0:\ (x, n) \in \operatorname{counts}(I)$$

No issue goes unreported.
-/
theorem issue_alerts (t : Nat) (opn : List String) {is : List String} {x : String} (hx : x ∈ is)
    (ho : ¬ ∃ id ∈ opn, Fw.Console.Alert.owner id = some spoolOwner) :
    fieldAlert t opn (fieldCounts is) ≠ none ∧ ∃ n, 0 < n ∧ (x, n) ∈ fieldCounts is := by
  have hu : x ∈ uniq is := (mem_uniqAux [] is x).mpr ⟨hx, List.not_mem_nil⟩
  have hm : (x, is.count x) ∈ fieldCounts is := List.mem_map.mpr ⟨x, hu, rfl⟩
  refine ⟨(fieldAlert_some_iff t opn _).mpr ⟨List.ne_nil_of_mem hm, ho⟩, is.count x, ?_, hm⟩
  exact List.count_pos_iff.mpr hx

/-- **Every rejected line raises the spool alert** (`reject_alerts`): when a line of the drain was
rejected with reason $w$ and no spool alert is open, the alert over the drain's issues (plus any
extra issues, such as `lifeOf:error`) fires and counts `rejected:` $w$ at least once.

$$\forall t, O, L, E, w:\quad w \in \operatorname{rej}(L) \land \lnot\exists \mathit{id} \in O:\ \operatorname{owner}(\mathit{id}) = \texttt{spool} \Rightarrow \operatorname{fieldAlert}(t, O, \operatorname{counts}(\operatorname{issues}(L) \mathbin{+\!\!+} E)) \ne \bot \land \exists n > 0:\ (\texttt{rejected:} \cdot \operatorname{name}(w), n) \in \operatorname{counts}(\operatorname{issues}(L) \mathbin{+\!\!+} E)$$

A refused line is never silent: it shows in the spool alert with its reason.
-/
theorem reject_alerts (t : Nat) (opn : List String) (ls : List (Option (List (String × Val))))
    (extra : List String) {w : Why} (hw : w ∈ rejectedOf ls)
    (ho : ¬ ∃ id ∈ opn, Fw.Console.Alert.owner id = some spoolOwner) :
    fieldAlert t opn (fieldCounts (issuesOf ls ++ extra)) ≠ none ∧
      ∃ n, 0 < n ∧ ("rejected:" ++ w.name, n) ∈ fieldCounts (issuesOf ls ++ extra) := by
  obtain ⟨l, hl, hv⟩ := List.mem_filterMap.mp hw
  have hi : "rejected:" ++ w.name ∈ issuesOf ls := by
    refine List.mem_flatMap.mpr ⟨l, hl, ?_⟩
    revert hv
    cases verdictOf l with
    | accept k u n => intro hv; cases hv
    | reject w' => intro hv; cases hv; simp [Verdict.issues]
  exact issue_alerts t opn (List.mem_append_left _ hi) ho

/-! ## Agent life from spool records (task `task-state-truth`)

Liveness is decided **by identity** (`Fw.Plan.liveK`, `Fw.Plan.ended`): every life command of a
record is keyed by the record's agent id or by its obs key, never by a name. A name only labels a key
(`labelOf`, `agent.label`, from the health index; a spawn guard's own label), which is how the name's
task row sees the key (`Fw.Plan.keysOf`). The decision never reads `background_tasks` (MEASURED: a
session-wide count, 6 to 31 on every one of the spool's SubagentStop records, never 0).

* `SubagentStart` of id $i$ spawns $i$ at the record time (event key `start:<obs key>`);
* `SubagentStop` of id $i$ stops $i$ at the record time (`stop:<obs key>`), named or not, and nothing
  else: two agents of one name are two keys, and the stop of one leaves the other live
  (`Fw.Plan.concurrent_keep`);
* **any other event** of id $i$, named or unnamed, is a heartbeat: a spawn of $i$ at the record time
  with event key `seen:<i>|<epoch>|<time / 10 min>`, so at most one per id and 10 minutes between
  stops, and the first event after a stop gets a new key. A heartbeat later than the stop revives
  the id (`event_revives`, by `Fw.Plan.revive_on_event`); an id with no sighting within the quiet
  limit shows quiet with its last-seen time, never ended by the time
  (`Fw.Plan.running_needs_recent_sighting`, `Fw.Plan.timeout_never_ends`); a lead or user mark ends
  it (`Fw.Plan.mark_ends_quiet`);
* a named `SpawnGuard` record (the spawner's guard, before the new agent has an id) spawns its own
  obs key $k$ (event key `guard:<k>`) and labels $k$ with the requested name (event key
  `guard-label:<k>`): the task row is running from the spawn on, before the health index labels the
  new id. A `SubagentStop` record carries no obs key of the guard, so no record stops $k$: it runs
  for the quiet limit after its record and then shows quiet (`Fw.Plan.no_forever_running`), never
  ended.
-/

/-- The heartbeat bucket: 10 minutes in milliseconds.

$$\mathit{seenBucketMs} = 600000$$
-/
def seenBucketMs : Nat := 10 * 60000

/-- What a record does to agent life: a spawn or stop of a life key (event key, life key, time), or a
label of a life key with a name (event key, life key, name).

$$\mathrm{Life} = \mathrm{spawn}(e, k, t) \cup \mathrm{stop}(e, k, t) \cup \mathrm{label}(e, k, n)$$
-/
inductive Life where
  | spawn (key agent : String) (time : Nat)
  | stop (key agent : String) (time : Nat)
  | label (key agent name : String)
deriving Repr, DecidableEq

/-- The life key a life command names.

$$\operatorname{agent}(\mathrm{spawn}(e, k, t)) = \operatorname{agent}(\mathrm{stop}(e, k, t)) = \operatorname{agent}(\mathrm{label}(e, k, n)) = k$$
-/
def Life.agent : Life → String
  | .spawn _ a _ | .stop _ a _ | .label _ a _ => a

/-- A usable agent name: non-empty and at most 120 UTF-16 units (a contract id).

$$\operatorname{okName}(n) \iff 0 < \operatorname{len}_{16}(n) \le 120$$

Is this string fit to be a name.
-/
def okName (n : String) : Bool := decide (0 < utf16Len n ∧ utf16Len n ≤ 120)

/-- The heartbeat event key of id $i$ at time $t$ in stop epoch $p$.

$$\operatorname{seenKey}(i, p, t) = \texttt{seen:} \cdot i \cdot \texttt{|} \cdot p \cdot \texttt{|} \cdot \lfloor t / 600000 \rfloor$$

($p$ and $\lfloor t / 600000 \rfloor$ written in decimal.) One key per id, epoch and 10 minutes.
-/
def seenKey (i : String) (p t : Nat) : String :=
  "seen:" ++ i ++ "|" ++ toString p ++ "|" ++ toString (t / seenBucketMs)

/-- The life commands of a record by its agent id $i$ (event $e$, obs key $k$, time $t$, stop epoch $p$
of $i$).

$$\operatorname{byId}(e, i, k, t, p) = \begin{cases} [\,] & i = \bot \\ [\mathrm{spawn}(\texttt{start:}k, i, t)] & i \ne \bot \land e = \texttt{SubagentStart} \\ [\mathrm{stop}(\texttt{stop:}k, i, t)] & i \ne \bot \land e = \texttt{SubagentStop} \\ [\mathrm{spawn}(\operatorname{seenKey}(i, p, t), i, t)] & \text{otherwise} \end{cases}$$

The id starts, stops, or is seen alive.
-/
def byId (event : String) (agentId : Option String) (key : String) (ts epoch : Nat) : List Life :=
  match agentId with
  | none => []
  | some i =>
    if event == "SubagentStart" then [.spawn ("start:" ++ key) i ts]
    else if event == "SubagentStop" then [.stop ("stop:" ++ key) i ts]
    else [.spawn (seenKey i epoch ts) i ts]

/-- The life commands of a spawn guard (event $e$, requested name $g$, obs key $k$, time $t$): a named
guard spawns its obs key and labels it with the name, when $k$, $g$ and the label's event key are
usable contract ids.

$$\operatorname{byGuard}(e, g, k, t) = \begin{cases} [\mathrm{spawn}(\texttt{guard:}k, k, t), \mathrm{label}(\texttt{guard-label:}k, k, \gamma)] & e = \texttt{SpawnGuard} \land g = \mathrm{some}(\gamma) \land \operatorname{okName}(\gamma) \land \operatorname{okName}(k) \land \operatorname{okName}(\texttt{guard-label:}k) \\ [\,] & \text{otherwise} \end{cases}$$

A guard makes the requested name running under the guard's own key.
-/
def byGuard (event : String) (agentName : Option String) (key : String) (ts : Nat) : List Life :=
  if event == "SpawnGuard" then
    match agentName with
    | some g =>
      if okName g && okName key && okName ("guard-label:" ++ key) then
        [.spawn ("guard:" ++ key) key ts, .label ("guard-label:" ++ key) key g]
      else []
    | none => []
  else []

/-- **The life decision of a record** (event $e$, agent id $i$, spawn-guard name $g$, obs key $k$,
time $t$, stop epoch $p$ of $i$): the guard commands, then the id commands.

$$\operatorname{lifeOf}(e, i, g, k, t, p) = \operatorname{byGuard}(e, g, k, t) \mathbin{+\!\!+} \operatorname{byId}(e, i, k, t, p)$$

What one spool record says about which agents live.
-/
def lifeOf (event : String) (agentId agentName : Option String) (key : String) (ts epoch : Nat) :
    List Life :=
  byGuard event agentName key ts ++ byId event agentId key ts epoch

/-- **Identity only** (`life_identity`): every life command of a record is keyed by the record's agent
id or by its obs key, and every stop is a stop of the agent id.

$$\forall e, i, g, k, t, p, c:\quad c \in \operatorname{lifeOf}(e, i, g, k, t, p) \Rightarrow \big(\operatorname{agent}(c) = k \lor \mathrm{some}(\operatorname{agent}(c)) = i\big) \land \big(\forall e', a, t':\ c = \mathrm{stop}(e', a, t') \Rightarrow \mathrm{some}(a) = i\big)$$

No name is ever a life key, and no record stops anything but its own agent.
-/
theorem life_identity (e : String) (i g : Option String) (k : String) (t p : Nat) (c : Life)
    (hc : c ∈ lifeOf e i g k t p) :
    (c.agent = k ∨ some c.agent = i) ∧ ∀ e' a t', c = .stop e' a t' → some a = i := by
  simp only [lifeOf, List.mem_append, byGuard, byId] at hc
  rcases hc with hc | hc
  · split at hc
    · split at hc
      · split at hc
        · simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
          rcases hc with rfl | rfl <;> simp [Life.agent]
        · simp at hc
      · simp at hc
    · simp at hc
  · split at hc
    · simp at hc
    · rename_i a
      split at hc
      · simp only [List.mem_singleton] at hc; subst hc; simp [Life.agent]
      · split at hc
        · simp only [List.mem_singleton] at hc; subst hc; simp [Life.agent]
        · simp only [List.mem_singleton] at hc; subst hc; simp [Life.agent]

/-- **A stop ends its id** (`stop_by_id`): a `SubagentStop` with agent id $i$ stops $i$ at the record
time, named or not, whatever `background_tasks` says (the decision has no such input).

$$\forall i, g, k, t, p:\quad \mathrm{stop}(\texttt{stop:}k, i, t) \in \operatorname{lifeOf}(\texttt{SubagentStop}, \mathrm{some}(i), g, k, t, p)$$

Every subagent stop reaches the board as a stop of that id.
-/
theorem stop_by_id (i : String) (g : Option String) (k : String) (t p : Nat) :
    Life.stop ("stop:" ++ k) i t ∈ lifeOf "SubagentStop" (some i) g k t p := by
  simp [lifeOf, byId]

/-- **A start spawns its id** (`start_by_id`): a `SubagentStart` with agent id $i$ spawns $i$ at the
record time.

$$\forall i, g, k, t, p:\quad \mathrm{spawn}(\texttt{start:}k, i, t) \in \operatorname{lifeOf}(\texttt{SubagentStart}, \mathrm{some}(i), g, k, t, p)$$

Every subagent start reaches the board as a spawn of that id.
-/
theorem start_by_id (i : String) (g : Option String) (k : String) (t p : Nat) :
    Life.spawn ("start:" ++ k) i t ∈ lifeOf "SubagentStart" (some i) g k t p := by
  simp [lifeOf, byId]

/-- **Any event revives its id** (`event_revives`): an event of id $i$ other than a start or stop,
named or unnamed, gives a heartbeat spawn of $i$ at the record time; applied to a plan state where
$i$ is a key labelled with name $a$ and every stop of $i$ is older
than $t$, it makes $i$ live and $a$ not ended.

$$\forall \pi, e, i, a, g, k, t, p:\quad e \ne \texttt{SubagentStart} \land e \ne \texttt{SubagentStop} \land i \in \operatorname{keysOf}(\pi, a) \land (\forall (j, s) \in \pi.\mathit{stops}:\ j = i \Rightarrow s < t) \Rightarrow \mathrm{spawn}(\operatorname{seenKey}(i, p, t), i, t) \in \operatorname{lifeOf}(e, \mathrm{some}(i), g, k, t, p) \land \operatorname{liveK}(\pi', i) = \mathrm{true} \land \operatorname{ended}(\pi', a) = \mathrm{false},\quad \pi' = \operatorname{step}(\pi, \mathrm{spawn}(i, t))$$

An agent that does anything after its stop is live again (running while that event is within the quiet limit).
-/
theorem event_revives (π : Fw.Plan.State) {e i a : String} (g : Option String) (k : String)
    (t p : Nat) (h1 : e ≠ "SubagentStart") (h2 : e ≠ "SubagentStop")
    (hk : i ∈ Fw.Plan.keysOf π a) (hs : ∀ q ∈ π.stops, q.1 = i → q.2 < t) :
    Life.spawn (seenKey i p t) i t ∈ lifeOf e (some i) g k t p ∧
      Fw.Plan.liveK (Fw.Plan.step π (.spawn i t)) i = true ∧
      Fw.Plan.ended (Fw.Plan.step π (.spawn i t)) a = false := by
  refine ⟨?_, Fw.Plan.revive_on_event π hk hs⟩
  simp [lifeOf, byId, h1, h2]

/-- The label command of an agent id from the health index: event key `label:<id>|<name>`, when the
id, the name and that key are all usable contract ids.

$$\operatorname{labelOf}(i, n) = \begin{cases} (e, i, n) & \operatorname{okName}(i) \land \operatorname{okName}(n) \land \operatorname{okName}(e) \\ \bot & \text{otherwise} \end{cases},\quad e = \texttt{label:} \cdot i \cdot \texttt{|} \cdot n$$

Tell the board which name an id goes by.
-/
def labelOf (id name : String) : Option (String × String × String) :=
  let e := "label:" ++ id ++ "|" ++ name
  if okName id && okName name && okName e then some (e, id, name) else none

/-! ## Examples: admission and life -/

/-- A real `SubagentStop` record of the spool (2026-10-18), with `background_tasks`. -/
private def realStop : List (String × Val) :=
  [("agent_id", .str "a0e52ab0600cc97da"), ("agent_type", .str ""),
   ("hook_event_name", .str "SubagentStop"), ("tool_name", .null), ("tool_use_id", .null),
   ("duration_ms", .null), ("is_error", .null), ("verb", .null), ("ts", .nat 1792269356759),
   ("background_tasks", .nat 20)]

-- the real stop line is accepted, background_tasks kept, nothing unknown, no notes
#guard admit realStop = .accept
  [("agent_id", .str "a0e52ab0600cc97da"), ("agent_type", .str ""),
   ("hook_event_name", .str "SubagentStop"), ("tool_name", .null), ("tool_use_id", .null),
   ("duration_ms", .null), ("is_error", .null), ("verb", .null),
   ("background_tasks", .nat 20), ("ts", .nat 1792269356759)] [] []
-- a new unknown field is accepted and reported, not rejected
#guard admit (realStop ++ [("future_field", .nat 3)]) matches .accept _ ["future_field"] []
-- the decision fields
#guard strictSpecs.map (·.name) = ["agent_id", "hook_event_name", "agent_name", "ts"]
-- rejections (decision fields only): missing ts, null or empty hook name, empty agent id, empty or
-- too long agent name
#guard admit (realStop.filter (·.1 != "ts")) = .reject (.missing "ts")
#guard admit (realStop.map fun p => if p.1 == "hook_event_name" then (p.1, .null) else p) =
  .reject (.invalid "hook_event_name")
#guard admit (realStop.map fun p => if p.1 == "hook_event_name" then (p.1, .str "") else p) =
  .reject (.invalid "hook_event_name")
#guard admit (realStop.map fun p => if p.1 == "agent_id" then (p.1, .str "") else p) =
  .reject (.invalid "agent_id")
#guard admit (realStop ++ [("agent_name", .str "")]) = .reject (.invalid "agent_name")
#guard admit (realStop ++ [("agent_name", .str (String.ofList (List.replicate 121 'n')))]) =
  .reject (.invalid "agent_name")
#guard admit (realStop ++ [("agent_name", .null)]) matches .accept _ [] []
-- soft fields never reject: a too long verb and a negative duration are kept as null and noted;
-- a missing soft required field is kept as null and noted; a bad optional one is left out and noted
#guard admit (realStop.map fun p => if p.1 == "verb" then (p.1, .str (String.ofList (List.replicate 41 'v'))) else p) =
  .accept
  [("agent_id", .str "a0e52ab0600cc97da"), ("agent_type", .str ""),
   ("hook_event_name", .str "SubagentStop"), ("tool_name", .null), ("tool_use_id", .null),
   ("duration_ms", .null), ("is_error", .null), ("verb", .null),
   ("background_tasks", .nat 20), ("ts", .nat 1792269356759)] [] [.invalid "verb"]
#guard admit (realStop.map fun p => if p.1 == "duration_ms" then (p.1, .other) else p) matches
  .accept _ [] [.invalid "duration_ms"]
#guard admit (realStop.filter (·.1 != "agent_type")) matches .accept _ [] [.missing "agent_type"]
#guard admit (realStop.map fun p => if p.1 == "background_tasks" then (p.1, .str "x") else p) =
  .accept
  [("agent_id", .str "a0e52ab0600cc97da"), ("agent_type", .str ""),
   ("hook_event_name", .str "SubagentStop"), ("tool_name", .null), ("tool_use_id", .null),
   ("duration_ms", .null), ("is_error", .null), ("verb", .null),
   ("ts", .nat 1792269356759)] [] [.invalid "background_tasks"]
#guard admit (realStop.filter (·.1 != "background_tasks")) matches .accept _ [] []
#guard (admit (realStop.filter (·.1 != "ts"))).why? = some (.missing "ts")
#guard (admit realStop).why? = none
#guard verdictOf none = .reject .json
#guard (Why.invalid "verb").name = "verb:invalid"
#guard (Verdict.reject (.missing "ts")).issues = ["rejected:ts:missing"]
#guard (Verdict.accept [] ["x"] [.invalid "verb"]).issues = ["verb:invalid", "x:unknown"]
-- utf16 length: an emoji counts 2
#guard utf16Len "a😀" = 3
-- drain counts: 2 accepted, 2 rejected, one unknown field
#guard (acceptedOf [some realStop, none, some (realStop ++ [("x", .bool true)]), some []]).length = 2
#guard (rejectedOf [some realStop, none, some (realStop ++ [("x", .bool true)]), some []]) =
  [.json, .missing "agent_id"]
#guard unknownOf [some realStop, none, some (realStop ++ [("x", .bool true)])] = ["x"]
#guard fieldCounts ["x", "y", "x"] = [("x", 2), ("y", 1)]
-- issues: rejected lines, then notes and unknown fields of accepted lines
#guard issuesOf [some realStop, none, some (realStop ++ [("x", .bool true)]), some [],
    some (realStop.filter (·.1 != "verb"))] =
  ["rejected:json", "x:unknown", "rejected:agent_id:missing", "verb:missing"]
#guard fieldCounts (issuesOf [none, none, some realStop] ++ ["lifeOf:error"]) =
  [("rejected:json", 2), ("lifeOf:error", 1)]
-- the spool alert: raised once, not while one is open, not when there is no issue
#guard (fieldAlert 5 [] [("x", 2)]).map (·.1) = some (Fw.Console.Alert.stepId (some "spool") 5)
#guard fieldAlert 5 [Fw.Console.Alert.stepId (some "spool") 1] [("x", 2)] = none
#guard fieldAlert 5 [Fw.Console.Alert.stepId (some "ci") 1] [("x", 2)] != none
#guard fieldAlert 5 [] [] = none
#guard alertTitle [("rejected:json", 2)] = "Spool lines need a look: rejected:json x2; fix emit.mjs or Fw.Ops.Obs.specs, then press Done"
#guard utf16Len (alertTitle ((List.range 40).map fun i => (s!"field{i}:unknown", i))) = 200
#guard (alertTitle ((List.range 40).map fun i => (s!"field{i}:unknown", i))).contains '…'
#guard takeU16 3 ['a', '😀', 'b'] = ['a', '😀']
#guard takeU16 2 ['a', '😀', 'b'] = ['a']
-- life decisions: by id
#guard lifeOf "SubagentStart" (some "i") none "k" 3 0 = [.spawn "start:k" "i" 3]
#guard lifeOf "SubagentStop" (some "i") none "k" 9 0 = [.stop "stop:k" "i" 9]
#guard lifeOf "SubagentStop" (some "i") (some "fix-nav") "k" 9 0 = [.stop "stop:k" "i" 9]
#guard lifeOf "SubagentStop" none none "k" 9 0 = []
-- any other event of an id is a heartbeat, named or not
#guard lifeOf "PostToolUse" (some "i") none "k" 1200000 9 = [.spawn "seen:i|9|2" "i" 1200000]
#guard lifeOf "PreToolUse" (some "i") none "k" 1200000 9 = [.spawn "seen:i|9|2" "i" 1200000]
#guard lifeOf "Notification" (some "i") none "k" 1 0 = [.spawn "seen:i|0|0" "i" 1]
#guard lifeOf "PreToolUse" none none "k" 1 0 = []
-- a named spawn guard spawns and labels its obs key, and is a heartbeat of the spawning id
#guard lifeOf "SpawnGuard" (some "i") (some "fix-nav") "k" 7 0 =
  [.spawn "guard:k" "k" 7, .label "guard-label:k" "k" "fix-nav", .spawn "seen:i|0|0" "i" 7]
#guard lifeOf "SpawnGuard" none (some "fix-nav") "k" 7 0 = [.spawn "guard:k" "k" 7, .label "guard-label:k" "k" "fix-nav"]
#guard lifeOf "SpawnGuard" none none "k" 7 0 = []
#guard lifeOf "SpawnGuard" none (some "") "k" 7 0 = []
#guard lifeOf "SpawnGuard" none (some "fix-nav") (String.ofList (List.replicate 110 'k')) 7 0 = []
-- the same bucket after a stop gives a new heartbeat key
#guard seenKey "i" 0 5 != seenKey "i" 3 5
-- labels
#guard labelOf "i" "fix-nav" = some ("label:i|fix-nav", "i", "fix-nav")
#guard labelOf "i" "" = none
#guard labelOf "" "fix-nav" = none
#guard labelOf "i" (String.ofList (List.replicate 115 'n')) = none
#guard admit (realStop.map fun p => if p.1 == "agent_id" then (p.1, .str (String.ofList (List.replicate 121 'i'))) else p) =
  .reject (.invalid "agent_id")

end Fw.Ops.Obs
