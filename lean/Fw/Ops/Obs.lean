import Fw.Console.Alert

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
is the list of its JSON fields; every known field is checked against its spec (the same types and
lengths as the zod `ObsRecord`); an unknown field never rejects the record but is reported
(`unknownOf`, raised as a spool alert by `fieldAlert`); a rejected record carries its reason. Proved:
an extra unknown field never turns an accepted record into a rejected one (`accept_extra`), a known
optional field with a valid value is kept (`accept_known`), and the drain counts every line as
accepted or rejected (`drop_counted`), and reports every unknown field of an accepted line
(`mem_unknown`).
-/

/-- The length of a string in UTF-16 code units, what zod's `.max` counts: 2 for a character above
U+FFFF, else 1.

$$\operatorname{len}_{16}(s) = \sum_{c \in s} \begin{cases} 2 & \operatorname{ord}(c) > \mathtt{0xFFFF} \\ 1 & \text{otherwise} \end{cases}$$
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

/-- The spec of a known field: name, type, whether null is allowed, whether the field must be present.

$$\mathit{sp} = (\mathit{name}, \mathit{ty}, \mathit{nullable}, \mathit{required})$$
-/
structure Spec where
  name     : String
  ty       : Ty
  nullable : Bool
  required : Bool
deriving Repr, DecidableEq

/-- The known spool fields, as in the zod `ObsRecord` (`packages/contracts/src/obs.ts`): eight
required nullable fields, `hook_event_name` (a non-empty string) and `ts` (required, not null), and
eleven optional nullable fields.

$$\mathit{specs} = [\texttt{agent\_id}{:}\,\mathrm{str}(200), \texttt{agent\_type}{:}\,\mathrm{str}(200), \texttt{hook\_event\_name}{:}\,\mathrm{name}(200)^{!}, \texttt{tool\_name}{:}\,\mathrm{str}(200), \texttt{tool\_use\_id}{:}\,\mathrm{str}(200), \texttt{duration\_ms}{:}\,\mathrm{nat}, \texttt{is\_error}{:}\,\mathrm{bool}, \texttt{verb}{:}\,\mathrm{str}(40), \texttt{agent\_name}{:}\,\mathrm{str}(200)^{?}, \texttt{seen\_by}{:}\,\mathrm{str}(40)^{?}, \texttt{role}{:}\,\mathrm{str}(200)^{?}, \texttt{want\_kind}{:}\,\mathrm{str}(40)^{?}, \texttt{got\_kind}{:}\,\mathrm{str}(40)^{?}, \texttt{isolation}{:}\,\mathrm{bool}^{?}, \texttt{depth}{:}\,\mathrm{nat}^{?}, \texttt{has\_name}{:}\,\mathrm{bool}^{?}, \texttt{notification\_type}{:}\,\mathrm{str}(40)^{?}, \texttt{message\_len}{:}\,\mathrm{nat}^{?}, \texttt{background\_tasks}{:}\,\mathrm{nat}^{?}, \texttt{ts}{:}\,\mathrm{nat}^{!}]$$

Unmarked: required and nullable; $^{?}$: optional and nullable; $^{!}$: required, not nullable.
-/
def specs : List Spec := [
  ⟨"agent_id", .str 200, true, true⟩, ⟨"agent_type", .str 200, true, true⟩,
  ⟨"hook_event_name", .name 200, false, true⟩, ⟨"tool_name", .str 200, true, true⟩,
  ⟨"tool_use_id", .str 200, true, true⟩, ⟨"duration_ms", .nat, true, true⟩,
  ⟨"is_error", .bool, true, true⟩, ⟨"verb", .str 40, true, true⟩,
  ⟨"agent_name", .str 200, true, false⟩, ⟨"seen_by", .str 40, true, false⟩,
  ⟨"role", .str 200, true, false⟩, ⟨"want_kind", .str 40, true, false⟩,
  ⟨"got_kind", .str 40, true, false⟩, ⟨"isolation", .bool, true, false⟩,
  ⟨"depth", .nat, true, false⟩, ⟨"has_name", .bool, true, false⟩,
  ⟨"notification_type", .str 40, true, false⟩, ⟨"message_len", .nat, true, false⟩,
  ⟨"background_tasks", .nat, true, false⟩, ⟨"ts", .nat, false, true⟩]

/-- Does a value fit a spec: null when nullable, a string within the length (non-empty for a name),
a natural for `nat`, a boolean for `bool`; `other` never fits.

$$\operatorname{fits}(\mathit{sp}, v) \iff (v = \mathrm{null} \land \mathit{sp}.\mathit{nullable}) \lor (v = \mathrm{str}(s) \land \mathit{sp}.\mathit{ty} = \mathrm{str}(m) \land \operatorname{len}_{16}(s) \le m) \lor (v = \mathrm{str}(s) \land \mathit{sp}.\mathit{ty} = \mathrm{name}(m) \land 0 < \operatorname{len}_{16}(s) \le m) \lor (v = \mathrm{nat}(n) \land \mathit{sp}.\mathit{ty} = \mathrm{nat}) \lor (v = \mathrm{bool}(b) \land \mathit{sp}.\mathit{ty} = \mathrm{bool})$$
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
-/
def known (x : String) : Bool := specs.any (·.name == x)

/-- The value of field `x` in a record: that of its first occurrence, none when absent.

$$\operatorname{look}(F, x) = \begin{cases} v & (x, v) \text{ is the first pair of } F \text{ with name } x \\ \bot & \text{no pair of } F \text{ has name } x \end{cases}$$
-/
def look (fs : List (String × Val)) (x : String) : Option Val := (fs.find? (·.1 == x)).map (·.2)

/-- Why a spool line was rejected: not a JSON object, a required field missing, or a field whose
value does not fit its spec.

$$\mathrm{Why} = \{\mathrm{json}\} \cup \mathrm{missing}(\mathrm{String}) \cup \mathrm{invalid}(\mathrm{String})$$
-/
inductive Why where
  | json
  | missing (field : String)
  | invalid (field : String)
deriving Repr, DecidableEq

/-- The name of a rejection reason, as the wire and `spool-rejects.jsonl` write it.

$$\operatorname{name}(\mathrm{json}) = \texttt{json},\quad \operatorname{name}(\mathrm{missing}(x)) = x \cdot \texttt{:missing},\quad \operatorname{name}(\mathrm{invalid}(x)) = x \cdot \texttt{:invalid}$$
-/
def Why.name : Why → String
  | .json => "json"
  | .missing x => x ++ ":missing"
  | .invalid x => x ++ ":invalid"

/-- The error of one spec on a record: missing when required and absent, invalid when present and not
fitting, none otherwise.

$$\operatorname{err}(F, \mathit{sp}) = \begin{cases} \mathrm{missing}(\mathit{sp}.\mathit{name}) & \operatorname{look}(F, \mathit{sp}.\mathit{name}) = \bot \land \mathit{sp}.\mathit{required} \\ \mathrm{invalid}(\mathit{sp}.\mathit{name}) & \operatorname{look}(F, \mathit{sp}.\mathit{name}) = v \land \lnot\operatorname{fits}(\mathit{sp}, v) \\ \bot & \text{otherwise} \end{cases}$$
-/
def Spec.err (fs : List (String × Val)) (sp : Spec) : Option Why :=
  match look fs sp.name with
  | none => if sp.required then some (.missing sp.name) else none
  | some v => if sp.fits v then none else some (.invalid sp.name)

/-- The verdict on a record: accepted with its kept known fields and the names of its unknown fields,
or rejected with a reason.

$$\mathrm{Verdict} = \mathrm{accept}(K, U) \cup \mathrm{reject}(w)$$
-/
inductive Verdict where
  | accept (kept : List (String × Val)) (unknown : List String)
  | reject (why : Why)
deriving Repr, DecidableEq

/-- **Admission of a record**: rejected with the first spec error in spec order; otherwise accepted,
keeping the present known fields in spec order and listing the unknown field names in record order.

$$\operatorname{admit}(F) = \begin{cases} \mathrm{reject}(w) & w = \text{the first } \operatorname{err}(F, \mathit{sp}) \ne \bot,\ \mathit{sp} \in \mathit{specs} \\ \mathrm{accept}\big([\, (\mathit{sp}.\mathit{name}, v) : \mathit{sp} \in \mathit{specs},\ \operatorname{look}(F, \mathit{sp}.\mathit{name}) = v \,],\ [\, x : (x, \_) \in F,\ \lnot\operatorname{known}(x) \,]\big) & \text{no spec has an error} \end{cases}$$
-/
def admit (fs : List (String × Val)) : Verdict :=
  match specs.findSome? (Spec.err fs) with
  | some w => .reject w
  | none => .accept (specs.filterMap fun sp => (look fs sp.name).map (sp.name, ·))
      ((fs.map (·.1)).filter (!known ·))

/-- Appending a pair adds a value only for a name that had none.

$$\forall F, x, v, y:\quad \operatorname{look}(F \mathbin{+\!\!+} [(x, v)], y) = \begin{cases} \operatorname{look}(F, y) & \operatorname{look}(F, y) \ne \bot \\ v & \operatorname{look}(F, y) = \bot \land x = y \\ \bot & \operatorname{look}(F, y) = \bot \land x \ne y \end{cases}$$
-/
theorem look_append (fs : List (String × Val)) (x : String) (v : Val) (y : String) :
    look (fs ++ [(x, v)]) y = (look fs y).or (if x = y then some v else none) := by
  unfold look
  rw [List.find?_append]
  cases fs.find? (·.1 == y) with
  | some p => simp
  | none => by_cases h : x = y <;> simp [h]

/-- `findSome?` agrees for two functions that agree on the list. -/
private theorem findSome?_congr {α β : Type} {f g : α → Option β} :
    ∀ {l : List α}, (∀ a ∈ l, f a = g a) → l.findSome? f = l.findSome? g
  | [], _ => rfl
  | a :: l, h => by
    simp only [List.findSome?_cons, h a (List.mem_cons_self ..),
      findSome?_congr (fun b hb => h b (List.mem_cons_of_mem _ hb))]

/-- `filterMap` agrees for two functions that agree on the list. -/
private theorem filterMap_congr' {α β : Type} {f g : α → Option β} :
    ∀ {l : List α}, (∀ a ∈ l, f a = g a) → l.filterMap f = l.filterMap g
  | [], _ => rfl
  | a :: l, h => by
    simp only [List.filterMap_cons, h a (List.mem_cons_self ..),
      filterMap_congr' (fun b hb => h b (List.mem_cons_of_mem _ hb))]

/-- Every spec name is known. -/
private theorem known_of_spec {sp : Spec} (h : sp ∈ specs) : known sp.name = true :=
  List.any_eq_true.mpr ⟨sp, h, by simp⟩

/-- **An extra unknown field never rejects a record** (`accept_extra`): a record that differs from an
accepted one only by one more field of an unknown name is accepted, with the same kept fields and
that name added to its unknown names.

$$\forall F, K, U, x, v:\quad \operatorname{admit}(F) = \mathrm{accept}(K, U) \land \lnot\operatorname{known}(x) \Rightarrow \operatorname{admit}(F \mathbin{+\!\!+} [(x, v)]) = \mathrm{accept}(K, U \mathbin{+\!\!+} [x])$$
-/
theorem accept_extra {fs k : List (String × Val)} {u : List String}
    (h : admit fs = .accept k u) (x : String) (v : Val) (hx : known x = false) :
    admit (fs ++ [(x, v)]) = .accept k (u ++ [x]) := by
  have hl : ∀ sp ∈ specs, look (fs ++ [(x, v)]) sp.name = look fs sp.name := by
    intro sp hs
    have hne : x ≠ sp.name := fun e => by rw [e, known_of_spec hs] at hx; cases hx
    rw [look_append]; simp [hne]
  have he : specs.findSome? (Spec.err (fs ++ [(x, v)])) = specs.findSome? (Spec.err fs) :=
    findSome?_congr fun sp hs => by simp only [Spec.err, hl sp hs]
  have hk : (specs.filterMap fun sp => (look (fs ++ [(x, v)]) sp.name).map (sp.name, ·)) =
      specs.filterMap fun sp => (look fs sp.name).map (sp.name, ·) :=
    filterMap_congr' fun sp hs => by rw [hl sp hs]
  unfold admit at h ⊢
  rw [he, hk]
  split at h
  · cases h
  · cases h
    simp [hx]

/-- **A known optional field with a fitting value is kept**: adding to an accepted record a field
that it lacks, whose name is known and whose value fits every spec of that name, gives an accepted
record that keeps the new pair and every pair kept before, with the same unknown names.

$$\forall F, K, U, x, v:\quad \operatorname{admit}(F) = \mathrm{accept}(K, U) \land \operatorname{known}(x) \land \operatorname{look}(F, x) = \bot \land (\forall \mathit{sp} \in \mathit{specs}:\ \mathit{sp}.\mathit{name} = x \Rightarrow \operatorname{fits}(\mathit{sp}, v)) \Rightarrow \exists K':\ \operatorname{admit}(F \mathbin{+\!\!+} [(x, v)]) = \mathrm{accept}(K', U) \land (x, v) \in K' \land K \subseteq K'$$
-/
theorem accept_known {fs k : List (String × Val)} {u : List String}
    (h : admit fs = .accept k u) {x : String} {v : Val} (hk : known x = true)
    (hn : look fs x = none) (hv : ∀ sp ∈ specs, sp.name = x → sp.fits v = true) :
    ∃ k', admit (fs ++ [(x, v)]) = .accept k' u ∧ (x, v) ∈ k' ∧ ∀ p ∈ k, p ∈ k' := by
  unfold admit at h ⊢
  split at h
  · cases h
  · rename_i hnone
    cases h
    have hall := List.findSome?_eq_none_iff.mp hnone
    have hnone' : specs.findSome? (Spec.err (fs ++ [(x, v)])) = none := by
      apply List.findSome?_eq_none_iff.mpr
      intro sp hs
      have h0 := hall sp hs
      by_cases e : sp.name = x
      · have hl : look (fs ++ [(x, v)]) sp.name = some v := by
          rw [look_append, e, hn]; simp
        simp [Spec.err, hl, hv sp hs e]
      · have hl : look (fs ++ [(x, v)]) sp.name = look fs sp.name := by
          rw [look_append]; simp [Ne.symm e]
        simp only [Spec.err, hl]; exact h0
    rw [hnone']
    refine ⟨specs.filterMap fun sp => (look (fs ++ [(x, v)]) sp.name).map (sp.name, ·), ?_, ?_, ?_⟩
    · simp [List.filter_append, hk]
    · obtain ⟨sp, hs, hsx⟩ := List.any_eq_true.mp hk
      have hsx' : sp.name = x := by simpa using hsx
      refine List.mem_filterMap.mpr ⟨sp, hs, ?_⟩
      rw [look_append, hsx', hn]; simp
    · intro p hp
      obtain ⟨sp, hs, hp⟩ := List.mem_filterMap.mp hp
      refine List.mem_filterMap.mpr ⟨sp, hs, ?_⟩
      cases hl : look fs sp.name with
      | none => rw [hl] at hp; cases hp
      | some w =>
        rw [hl] at hp
        rw [look_append, hl]; exact hp

/-- The verdict on a spool line: a line that is not a JSON object is rejected (`json`); an object is
admitted by its fields.

$$\operatorname{verdict}(\bot) = \mathrm{reject}(\mathrm{json}),\qquad \operatorname{verdict}(F) = \operatorname{admit}(F)$$
-/
def verdictOf : Option (List (String × Val)) → Verdict
  | none => .reject .json
  | some fs => admit fs

/-- The accepted lines of a drain: kept fields and unknown names, in line order.

$$\operatorname{acc}(L) = [\, (K, U) : \ell \in L,\ \operatorname{verdict}(\ell) = \mathrm{accept}(K, U) \,]$$
-/
def acceptedOf (ls : List (Option (List (String × Val)))) : List (List (String × Val) × List String) :=
  ls.filterMap fun l => match verdictOf l with
    | .accept k u => some (k, u)
    | .reject _ => none

/-- The rejection reasons of a drain, one per rejected line, in line order.

$$\operatorname{rej}(L) = [\, w : \ell \in L,\ \operatorname{verdict}(\ell) = \mathrm{reject}(w) \,]$$
-/
def rejectedOf (ls : List (Option (List (String × Val)))) : List Why :=
  ls.filterMap fun l => match verdictOf l with
    | .reject w => some w
    | .accept .. => none

/-- The unknown field names of a drain's accepted lines, one entry per occurrence.

$$\operatorname{unk}(L) = \operatorname{concat}[\, U : (K, U) \in \operatorname{acc}(L) \,]$$
-/
def unknownOf (ls : List (Option (List (String × Val)))) : List String :=
  (acceptedOf ls).flatMap (·.2)

/-- **The drain drops no line uncounted** (`drop_counted`): every line is accepted or rejected with a
reason, so the two counts add up to the number of lines.

$$\forall L:\quad |\operatorname{acc}(L)| + |\operatorname{rej}(L)| = |L|$$
-/
theorem drop_counted (ls : List (Option (List (String × Val)))) :
    (acceptedOf ls).length + (rejectedOf ls).length = ls.length := by
  induction ls with
  | nil => rfl
  | cons l ls ih =>
    simp only [acceptedOf, rejectedOf, List.filterMap_cons] at ih ⊢
    cases verdictOf l <;> simp <;> omega

/-- **Every unknown field is reported**: a name is among the drain's unknown names exactly when some
accepted line has a field of that name and the name is not known.

$$\forall L, x:\quad x \in \operatorname{unk}(L) \iff \exists F:\ \mathrm{some}(F) \in L \land (\exists K, U:\ \operatorname{admit}(F) = \mathrm{accept}(K, U)) \land x \in [\, y : (y, \_) \in F \,] \land \lnot\operatorname{known}(x)$$
-/
theorem mem_unknown (ls : List (Option (List (String × Val)))) (x : String) :
    x ∈ unknownOf ls ↔ ∃ fs, some fs ∈ ls ∧ (∃ k u, admit fs = .accept k u) ∧
      x ∈ fs.map (·.1) ∧ known x = false := by
  simp only [unknownOf, acceptedOf, List.mem_flatMap, List.mem_filterMap]
  constructor
  · rintro ⟨⟨k, u⟩, ⟨l, hl, hv⟩, hx⟩
    cases l with
    | none => simp [verdictOf] at hv
    | some fs =>
      simp only [verdictOf] at hv
      split at hv
      · rename_i k' u' ha
        cases hv
        have hu : u = (fs.map (·.1)).filter (!known ·) := by
          unfold admit at ha; split at ha
          · cases ha
          · cases ha; rfl
        rw [hu, List.mem_filter] at hx
        exact ⟨fs, hl, ⟨k, u, ha⟩, hx.1, by simpa using hx.2⟩
      · cases hv
  · rintro ⟨fs, hl, ⟨k, u, ha⟩, hx, hk⟩
    refine ⟨(k, u), ⟨some fs, hl, by simp [verdictOf, ha]⟩, ?_⟩
    have hu : u = (fs.map (·.1)).filter (!known ·) := by
      unfold admit at ha; split at ha
      · cases ha
      · cases ha; rfl
    rw [hu, List.mem_filter]
    exact ⟨hx, by simp [hk]⟩

/-- The unknown field names with their counts, in first-seen order.

$$\operatorname{counts}(U) = [\, (x, |[\, y \in U : y = x \,]|) : x \in \operatorname{uniq}(U) \,]$$
-/
def fieldCounts (u : List String) : List (String × Nat) := (uniq u).map fun x => (x, u.count x)

/-- The owner name of the spool alert step (`Fw.Console.Alert.stepId (some "spool") now`).

$$\operatorname{spoolOwner} = \texttt{spool}$$
-/
def spoolOwner : String := "spool"

/-- **The spool alert for unknown fields**: none when there are none or a spool alert is still open;
otherwise a step `alert-spool-<now>` naming each unknown field and its count.

$$\operatorname{fieldAlert}(t, O, C) = \begin{cases} \bot & C = [\,] \lor \exists \mathit{id} \in O:\ \operatorname{owner}(\mathit{id}) = \texttt{spool} \\ (s, \texttt{alert:} \cdot s, \text{“Spool records carry unknown fields: } x_1 \times n_1, \dots \text{; add them to Fw.Ops.Obs.specs or drop them in emit.mjs, then press Done”}) & \text{otherwise} \end{cases},\quad s = \operatorname{stepId}(\texttt{spool}, t)$$
-/
def fieldAlert (now : Nat) (opn : List String) (cs : List (String × Nat)) :
    Option (String × String × String) :=
  if cs.isEmpty || opn.any (fun id => Fw.Console.Alert.owner id == some spoolOwner) then none
  else
    let id := Fw.Console.Alert.stepId (some spoolOwner) now
    let names := ", ".intercalate (cs.map fun (x, n) => s!"{x} x{n}")
    some (id, "alert:" ++ id, s!"Spool records carry unknown fields: {names}; add them to Fw.Ops.Obs.specs or drop them in emit.mjs, then press Done")

/-- A spool alert is raised exactly when unknown fields were seen and no spool alert is open.

$$\forall t, O, C:\quad \operatorname{fieldAlert}(t, O, C) \ne \bot \iff C \ne [\,] \land \lnot\exists \mathit{id} \in O:\ \operatorname{owner}(\mathit{id}) = \texttt{spool}$$
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

/-! ## Agent life from spool records (task `task-state-truth`)

Which plan command an admitted record gives. The decision reads the event name, the agent id, the
spawn guard's `agent_name`, the name the console's health index gives the agent id, the obs key,
the record time and the stop epoch of that name (the time of the last stop the drain sent for it, 0
if none); it never reads `background_tasks` (MEASURED: a session-wide count, 6 to 31 on every one of
the spool's SubagentStop records, never 0, so the old "no stop while background tasks run" rule
never sent a stop).

* a named `SpawnGuard` spawns the name at the record time (key `spawn:<obs key>`);
* a `SubagentStop` of a named agent stops it at the record time (key `stop:<obs key>`); without a
  name it is counted as unnamed, never dropped silently;
* a tool event of a named agent is a heartbeat: a spawn at the record time with key
  `seen:<name>|<epoch>|<time / 10 min>`, so at most one per agent and 10 minutes between stops, and
  the first tool event after a stop gets a new key. A heartbeat later than the stop revives the
  agent (a resumed agent's SubagentStop ends a turn, not the agent), and it feeds the quiet timeout
  (`Fw.Plan.timeouts`).
-/

/-- The heartbeat bucket: 10 minutes in milliseconds.

$$\mathit{seenBucketMs} = 600000$$
-/
def seenBucketMs : Nat := 10 * 60000

/-- What a record does to agent life: a spawn or stop (key, agent name, time), an unnamed stop, or
nothing.

$$\mathrm{Life} = \mathrm{spawn}(k, a, t) \cup \mathrm{stop}(k, a, t) \cup \{\mathrm{unnamed}, \mathrm{skip}\}$$
-/
inductive Life where
  | spawn (key agent : String) (time : Nat)
  | stop (key agent : String) (time : Nat)
  | unnamed
  | skip
deriving Repr, DecidableEq

/-- A usable agent name: non-empty and at most 120 UTF-16 units (a contract id).

$$\operatorname{okName}(n) \iff 0 < \operatorname{len}_{16}(n) \le 120$$
-/
def okName (n : String) : Bool := decide (0 < utf16Len n ∧ utf16Len n ≤ 120)

/-- A tool event: `PreToolUse`, `PostToolUse` or `PostToolUseFailure`.

$$\operatorname{isTool}(e) \iff e \in \{\texttt{PreToolUse}, \texttt{PostToolUse}, \texttt{PostToolUseFailure}\}$$
-/
def isTool (e : String) : Bool := e == "PreToolUse" || e == "PostToolUse" || e == "PostToolUseFailure"

/-- **The life decision of a record** (event $e$, agent id $i$, spawn-guard name $g$, indexed name $m$,
obs key $k$, time $t$, stop epoch $p$).

$$\operatorname{life}(e, i, g, m, k, t, p) = \begin{cases} \mathrm{spawn}(\texttt{spawn:}k, g, t) & e = \texttt{SpawnGuard} \land g \ne \bot \land \operatorname{okName}(g) \\ \mathrm{stop}(\texttt{stop:}k, m, t) & e = \texttt{SubagentStop} \land i \ne \bot \land m \ne \bot \land \operatorname{okName}(m) \\ \mathrm{unnamed} & e = \texttt{SubagentStop} \land i \ne \bot \land \lnot(m \ne \bot \land \operatorname{okName}(m)) \\ \mathrm{spawn}(\texttt{seen:}m\texttt{|}p\texttt{|}\lfloor t / 600000 \rfloor, m, t) & \operatorname{isTool}(e) \land i \ne \bot \land m \ne \bot \land \operatorname{okName}(m) \\ \mathrm{skip} & \text{otherwise} \end{cases}$$

($p$ and $\lfloor t / 600000 \rfloor$ written in decimal.)
-/
def lifeOf (event : String) (agentId agentName name : Option String) (key : String) (ts epoch : Nat) :
    Life :=
  if event == "SpawnGuard" then
    match agentName with
    | some g => if okName g then .spawn ("spawn:" ++ key) g ts else .skip
    | none => .skip
  else if event == "SubagentStop" then
    match agentId, name with
    | some _, some m => if okName m then .stop ("stop:" ++ key) m ts else .unnamed
    | some _, none => .unnamed
    | none, _ => .skip
  else if isTool event then
    match agentId, name with
    | some _, some m =>
      if okName m then .spawn ("seen:" ++ m ++ "|" ++ toString epoch ++ "|" ++ toString (ts / seenBucketMs)) m ts
      else .skip
    | _, _ => .skip
  else .skip

/-- **No stop is dropped silently**: a `SubagentStop` with an agent id gives a stop of its name at the
record time, or is counted as unnamed.

$$\forall i, g, m, k, t, p:\quad i \ne \bot \Rightarrow \big(\exists a:\ \operatorname{life}(\texttt{SubagentStop}, i, g, m, k, t, p) = \mathrm{stop}(\texttt{stop:}k, a, t)\big) \lor \operatorname{life}(\texttt{SubagentStop}, i, g, m, k, t, p) = \mathrm{unnamed}$$
-/
theorem stop_counted {i : Option String} (g m : Option String) (k : String) (t p : Nat)
    (hi : i.isSome = true) :
    (∃ a, lifeOf "SubagentStop" i g m k t p = .stop ("stop:" ++ k) a t) ∨
      lifeOf "SubagentStop" i g m k t p = .unnamed := by
  obtain ⟨x, rfl⟩ := Option.isSome_iff_exists.mp hi
  cases m with
  | none => right; rfl
  | some n =>
    by_cases h : okName n = true
    · left; exact ⟨n, by simp [lifeOf, h]⟩
    · right; simp [lifeOf, h]

/-- **A named stop ends its agent at the record time, whatever `background_tasks` says** (the decision
has no such input).

$$\forall x, g, n, k, t, p:\quad \operatorname{okName}(n) \Rightarrow \operatorname{life}(\texttt{SubagentStop}, x, g, n, k, t, p) = \mathrm{stop}(\texttt{stop:}k, n, t)$$
-/
theorem stop_named (x : String) (g : Option String) {n : String} (k : String) (t p : Nat)
    (h : okName n = true) : lifeOf "SubagentStop" (some x) g (some n) k t p = .stop ("stop:" ++ k) n t := by
  simp [lifeOf, h]

/-! ## Examples: admission and life -/

/-- A real `SubagentStop` record of the spool (2026-10-18), with `background_tasks`. -/
private def realStop : List (String × Val) :=
  [("agent_id", .str "a0e52ab0600cc97da"), ("agent_type", .str ""),
   ("hook_event_name", .str "SubagentStop"), ("tool_name", .null), ("tool_use_id", .null),
   ("duration_ms", .null), ("is_error", .null), ("verb", .null), ("ts", .nat 1792269356759),
   ("background_tasks", .nat 20)]

-- the real stop line is accepted, background_tasks kept, nothing unknown
#guard admit realStop = .accept
  [("agent_id", .str "a0e52ab0600cc97da"), ("agent_type", .str ""),
   ("hook_event_name", .str "SubagentStop"), ("tool_name", .null), ("tool_use_id", .null),
   ("duration_ms", .null), ("is_error", .null), ("verb", .null),
   ("background_tasks", .nat 20), ("ts", .nat 1792269356759)] []
-- a new unknown field is accepted and reported, not rejected
#guard admit (realStop ++ [("future_field", .nat 3)]) matches .accept _ ["future_field"]
-- rejections: missing ts, null hook name, too long verb, negative duration, not an object
#guard admit (realStop.filter (·.1 != "ts")) = .reject (.missing "ts")
#guard admit (realStop.map fun p => if p.1 == "hook_event_name" then (p.1, .null) else p) =
  .reject (.invalid "hook_event_name")
#guard admit (realStop.map fun p => if p.1 == "hook_event_name" then (p.1, .str "") else p) =
  .reject (.invalid "hook_event_name")
#guard admit (realStop.map fun p => if p.1 == "verb" then (p.1, .str (String.ofList (List.replicate 41 'v'))) else p) =
  .reject (.invalid "verb")
#guard admit (realStop.map fun p => if p.1 == "duration_ms" then (p.1, .other) else p) =
  .reject (.invalid "duration_ms")
#guard admit (realStop.filter (·.1 != "background_tasks")) matches .accept _ []
#guard verdictOf none = .reject .json
#guard (Why.invalid "verb").name = "verb:invalid"
-- utf16 length: an emoji counts 2
#guard utf16Len "a😀" = 3
-- drain counts: 2 accepted, 2 rejected, one unknown field
#guard (acceptedOf [some realStop, none, some (realStop ++ [("x", .bool true)]), some []]).length = 2
#guard (rejectedOf [some realStop, none, some (realStop ++ [("x", .bool true)]), some []]) =
  [.json, .missing "agent_id"]
#guard unknownOf [some realStop, none, some (realStop ++ [("x", .bool true)])] = ["x"]
#guard fieldCounts ["x", "y", "x"] = [("x", 2), ("y", 1)]
-- the spool alert: raised once, not while one is open, not when nothing is unknown
#guard (fieldAlert 5 [] [("x", 2)]).map (·.1) = some (Fw.Console.Alert.stepId (some "spool") 5)
#guard fieldAlert 5 [Fw.Console.Alert.stepId (some "spool") 1] [("x", 2)] = none
#guard fieldAlert 5 [Fw.Console.Alert.stepId (some "ci") 1] [("x", 2)] != none
#guard fieldAlert 5 [] [] = none
-- life decisions
#guard lifeOf "SpawnGuard" (some "i") (some "fix-nav") none "k" 7 0 = .spawn "spawn:k" "fix-nav" 7
#guard lifeOf "SpawnGuard" (some "i") none none "k" 7 0 = .skip
#guard lifeOf "SpawnGuard" (some "i") (some "") none "k" 7 0 = .skip
#guard lifeOf "SubagentStop" (some "i") none (some "fix-nav") "k" 9 0 = .stop "stop:k" "fix-nav" 9
#guard lifeOf "SubagentStop" (some "i") none none "k" 9 0 = .unnamed
#guard lifeOf "SubagentStop" none none (some "fix-nav") "k" 9 0 = .skip
#guard lifeOf "PostToolUse" (some "i") none (some "fix-nav") "k" 1200000 9 =
  .spawn "seen:fix-nav|9|2" "fix-nav" 1200000
#guard lifeOf "PreToolUse" (some "i") none none "k" 1200000 9 = .skip
#guard lifeOf "Notification" (some "i") none (some "fix-nav") "k" 1 0 = .skip
-- the same bucket after a stop gives a new heartbeat key
#guard lifeOf "PostToolUse" (some "i") none (some "a") "k" 5 0 != lifeOf "PostToolUse" (some "i") none (some "a") "k" 5 3

end Fw.Ops.Obs

