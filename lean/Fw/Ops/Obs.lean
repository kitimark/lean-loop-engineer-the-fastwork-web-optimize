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

The key names who did what, and which tool call or moment it was.
-/
def obsKey (agentId : Option String) (event : String) (toolUseId : Option String) (ts : Nat) : String :=
  agentId.getD "main" ++ "|" ++ event ++ "|" ++ toolUseId.getD (toString ts)

/-- With a tool-use id the key does not depend on the timestamp, so the hook record and the
transcript record of one tool call share a key.

Two records of the same tool call get the same key at any times.
-/
theorem obsKey_tool_ts (i : Option String) (e v : String) (t₁ t₂ : Nat) :
    obsKey i e (some v) t₁ = obsKey i e (some v) t₂ := rfl

/-- Without a tool-use id the timestamp is the last part of the key.

A hook-only event is keyed by its timestamp, exactly as if the timestamp were its tool-use id.
-/
theorem obsKey_no_tool (i : Option String) (e : String) (t : Nat) :
    obsKey i e none t = obsKey i e (some (toString t)) 0 := rfl

#guard obsKey none "Stop" none 42 == "main|Stop|42"
#guard obsKey (some "a1") "PostToolUse" (some "toolu_1") 7 == "a1|PostToolUse|toolu_1"
#guard obsKey (some "") "X" (some "") 7 == "|X|"

/-! ## Summary -/

/-- One observed line, as far as the summary reads it.

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

Only finished tool calls count; every other hook event is ignored by the summary.
-/
def isCall (l : Line) : Bool := l.event == "PostToolUse" || l.event == "PostToolUseFailure"

/-- The group of a line: its agent type (`main` when missing) and its tool name (`?` when missing).

Lines are grouped by who called which tool.
-/
def group (l : Line) : String × String := (l.agentType.getD "main", l.toolName.getD "?")

/-- One summary row: a group and its counts.

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

Walk the list and keep each element the first time it is met.
-/
def uniqAux {α : Type} [DecidableEq α] : List α → List α → List α
  | _, [] => []
  | seen, a :: as => if a ∈ seen then uniqAux seen as else a :: uniqAux (a :: seen) as

/-- The list without repeats, in first-occurrence order.

Each element once, in the order it first appears.
-/
def uniq {α : Type} [DecidableEq α] (l : List α) : List α := uniqAux [] l

/-- The groups of the tool calls, in the order of their first call.

Every (agent type, tool) pair that made at least one call, once each.
-/
def groups (ls : List Line) : List (String × String) := uniq ((ls.filter isCall).map group)

/-- The row of group `k`: its tool calls, their errors and their summed duration.

The counts of one group, read straight off the lines.
-/
def rowFor (ls : List Line) (k : String × String) : Row :=
  let c := ls.filter fun l => isCall l && group l == k
  ⟨k.1, k.2, c.length, (c.filter (·.isError == some true)).length, (c.map (·.durationMs.getD 0)).sum⟩

/-- The tool-call summary: one row per group, in the order of the group's first call.

Count calls, errors and time per (agent type, tool).
-/
def summarize (ls : List Line) : List Row := (groups ls).map (rowFor ls)

/-! ## Proofs -/

/-- Membership in `uniqAux`: an element of the list not already seen.

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

A group has a row exactly when some tool call falls in it.
-/
theorem mem_groups (ls : List Line) (k : String × String) :
    k ∈ groups ls ↔ ∃ l ∈ ls, isCall l = true ∧ group l = k := by
  simp [groups, uniq, mem_uniqAux, and_assoc]

/-- Each group appears once.

No (agent type, tool) pair gets two rows.
-/
theorem groups_nodup (ls : List Line) : (groups ls).Nodup := uniqAux_nodup _ _

/-- Every summary row holds the counts of its own group.

A row's calls, errors and time are the counts over the tool calls of that group.
-/
theorem summarize_row (ls : List Line) (r : Row) (h : r ∈ summarize ls) :
    (r.agentType, r.toolName) ∈ groups ls ∧ r = rowFor ls (r.agentType, r.toolName) := by
  simp only [summarize, List.mem_map] at h
  obtain ⟨k, hk, rfl⟩ := h
  exact ⟨hk, rfl⟩

/-- Lines that are not tool calls change nothing.

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

Count a string the way JavaScript does.
-/
def utf16Len (s : String) : Nat := s.toList.foldl (fun n c => n + if 0xFFFF < c.val.toNat then 2 else 1) 0

/-- A JSON field value as admission reads it: null, a string, a non-negative integer, a boolean, or
anything else (a negative or fractional number, an array, an object).
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
-/
inductive Ty where
  | str (max : Nat)
  | name (max : Nat)
  | nat
  | bool
deriving Repr, DecidableEq

/-- The spec of a known field: name, type, whether null is allowed, whether the field must be
present, and whether it is a decision field (strict: a bad value rejects the record).
-/
structure Spec where
  name     : String
  ty       : Ty
  nullable : Bool
  required : Bool
  strict   : Bool
deriving Repr, DecidableEq

/-- The known spool fields, as in the zod `ObsRecord` (`packages/contracts/src/obs.ts`). Strict
(decision fields, marked `^s`): `agent_id` (required, nullable, non-empty, at most 120 units: a
contract id, since it is a life key), `hook_event_name`
(required, not null, non-empty), `agent_name` (optional, nullable, non-empty, at most 120 units: a
contract id), `ts` (required, not null). All others are soft: six required nullable fields and eleven
optional nullable fields.

Unmarked: required and nullable; `^(?)`: optional and nullable; `^(!)`: required, not nullable;
`^s`: strict.
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
  ⟨"background_tasks", .nat, true, false, false⟩, ⟨"session_pid", .nat, true, false, false⟩,
  ⟨"ts", .nat, false, true, true⟩]

/-- Does a value fit a spec: null when nullable, a string within the length (non-empty for a name),
a natural for `nat`, a boolean for `bool`; `other` never fits.

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

Is the field in the spec list.
-/
def known (x : String) : Bool := specs.any (·.name == x)

/-- The value of field `x` in a record: that of its first occurrence, none when absent.

Read one field of a record.
-/
def look (fs : List (String × Val)) (x : String) : Option Val := (fs.find? (·.1 == x)).map (·.2)

/-- Why a spool line was rejected, or why a soft field was noted: not a JSON object, a field missing,
or a field whose value does not fit its spec.
-/
inductive Why where
  | json
  | missing (field : String)
  | invalid (field : String)
deriving Repr, DecidableEq

/-- The name of a reason, as the wire and `spool-rejects.jsonl` write it.

Spell a reason as text.
-/
def Why.name : Why → String
  | .json => "json"
  | .missing x => x ++ ":missing"
  | .invalid x => x ++ ":invalid"

/-- The error of one spec on a record: missing when required and absent, invalid when present and not
fitting, none otherwise.

Find what is wrong with one field.
-/
def Spec.err (fs : List (String × Val)) (sp : Spec) : Option Why :=
  match look fs sp.name with
  | none => if sp.required then some (.missing sp.name) else none
  | some v => if sp.fits v then none else some (.invalid sp.name)

/-- The kept pair of one spec: the value when it fits; null when it is missing or does not fit and
the field is required; nothing otherwise.

Keep a good value, and put null in place of a bad or missing required one.
-/
def Spec.keep (fs : List (String × Val)) (sp : Spec) : Option (String × Val) :=
  match look fs sp.name with
  | some v => if sp.fits v then some (sp.name, v) else if sp.required then some (sp.name, .null) else none
  | none => if sp.required then some (sp.name, .null) else none

/-- The verdict on a record: accepted with its kept known fields, the names of its unknown fields and
the notes on its soft fields, or rejected with a reason.
-/
inductive Verdict where
  | accept (kept : List (String × Val)) (unknown : List String) (notes : List Why)
  | reject (why : Why)
deriving Repr, DecidableEq

/-- The rejection reason of a verdict, none for an accepted record.

The reason a record was refused, if it was.
-/
def Verdict.why? : Verdict → Option Why
  | .reject w => some w
  | .accept .. => none

/-- The decision fields: the specs marked strict.

The fields whose value a decision reads.
-/
def strictSpecs : List Spec := specs.filter (·.strict)

/-- **Admission of a record**: rejected with the first error of a decision field, in spec order;
otherwise accepted, keeping the known fields in spec order (a soft field that is missing or does not
fit becomes null when required and is left out when optional), listing the unknown field names in
record order and the errors of the soft fields in spec order.

Refuse a record only for a bad decision field; keep everything else, noting what was wrong.
-/
def admit (fs : List (String × Val)) : Verdict :=
  match strictSpecs.findSome? (Spec.err fs) with
  | some w => .reject w
  | none => .accept (specs.filterMap (Spec.keep fs)) ((fs.map (·.1)).filter (!known ·))
      ((specs.filter (!·.strict)).filterMap (Spec.err fs))

/-- Appending a pair adds a value only for a name that had none.

A later duplicate of a field never changes its value.
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

/-- **Only decision fields decide a rejection** (`soft_never_rejects`): two records whose decision
fields read the same get the same rejection reason (or are both accepted), whatever their soft and
unknown fields hold.

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

Judge one raw line.
-/
def verdictOf : Option (List (String × Val)) → Verdict
  | none => .reject .json
  | some fs => admit fs

/-- The accepted lines of a drain: kept fields, unknown names and notes, in line order.

The lines that got in.
-/
def acceptedOf (ls : List (Option (List (String × Val)))) :
    List (List (String × Val) × List String × List Why) :=
  ls.filterMap fun l => match verdictOf l with
    | .accept k u n => some (k, u, n)
    | .reject _ => none

/-- The rejection reasons of a drain, one per rejected line, in line order.

Why each refused line was refused.
-/
def rejectedOf (ls : List (Option (List (String × Val)))) : List Why :=
  ls.filterMap fun l => (verdictOf l).why?

/-- The unknown field names of a drain's accepted lines, one entry per occurrence.

Every unknown field seen, with repeats.
-/
def unknownOf (ls : List (Option (List (String × Val)))) : List String :=
  (acceptedOf ls).flatMap (·.2.1)

/-- **The drain drops no line uncounted** (`drop_counted`): every line is accepted or rejected with a
reason, so the two counts add up to the number of lines.

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

/-- The unknown names of an accepted record are its field names that are not known. -/
private theorem unknown_of_accept {fs k : List (String × Val)} {u : List String} {n : List Why}
    (ha : admit fs = .accept k u n) : u = (fs.map (·.1)).filter (!known ·) := by
  unfold admit at ha; split at ha
  · cases ha
  · cases ha; rfl

/-- **Every unknown field is reported**: a name is among the drain's unknown names exactly when some
accepted line has a field of that name and the name is not known.

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

What a person should look at in one line.
-/
def Verdict.issues : Verdict → List String
  | .reject w => ["rejected:" ++ w.name]
  | .accept _ u n => n.map Why.name ++ u.map (· ++ ":unknown")

/-- The issues of a drain, one entry per occurrence, in line order.

Everything about the drained lines a person should look at.
-/
def issuesOf (ls : List (Option (List (String × Val)))) : List String :=
  ls.flatMap fun l => (verdictOf l).issues

/-- The issue names with their counts, in first-seen order.

Count each issue once per occurrence.
-/
def fieldCounts (u : List String) : List (String × Nat) := (uniq u).map fun x => (x, u.count x)

/-- The owner name of the spool alert step (`Fw.Console.Alert.stepId (some "spool") now`). -/
def spoolOwner : String := "spool"

/-- The JavaScript (UTF-16) length of one character: 2 above U+FFFF, else 1.

How many UTF-16 units JavaScript spends on the character.
-/
def u16 (c : Char) : Nat := if 0xFFFF < c.val.toNat then 2 else 1

/-- The longest prefix of a character list whose UTF-16 length fits a budget.

Keep characters from the front while they still fit.
-/
def takeU16 : Nat → List Char → List Char
  | _, [] => []
  | b, c :: l => if u16 c ≤ b then c :: takeU16 (b - u16 c) l else []

/-- The JavaScript length of a string is the sum of its characters' UTF-16 lengths.

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

What every spool alert title starts with.
-/
def alertHead : String := "Spool lines need a look: "
/-- The fixed end of the spool alert title (51 UTF-16 units).

What every spool alert title ends with.
-/
def alertTail : String := "; fix emit.mjs or Fw.Ops.Obs.specs, then press Done"

/-- The issue list of the spool alert as characters: `x₁ xn₁, x₂ xn₂, …`.

Each issue with its count, comma separated.
-/
def alertNames (cs : List (String × Nat)) : List Char :=
  (", ".intercalate (cs.map fun (x, n) => s!"{x} x{n}")).toList

/-- Whether an issue is a caught fwcore throw of the drain (`sweep:<op>`), not a spool-line problem. -/
def isSweep (x : String) : Bool := x.startsWith "sweep:"

/-- The fixed start of the title when every issue is a caught throw (23 UTF-16 units). -/
def sweepHead : String := "Drain threw in fwcore: "
/-- The fixed end of the title when every issue is a caught throw (38 UTF-16 units). -/
def sweepTail : String := "; see console-api log, then press Done"

/-- The title is the throw title exactly when there is an issue and all issues are caught throws. -/
def allSweep (cs : List (String × Nat)) : Bool := !cs.isEmpty && cs.all fun (x, _) => isSweep x

/-- The spool alert title: the issue list `x₁ xn₁, …` cut to 123 UTF-16 units (an ellipsis marks a cut)
between a fixed head and tail, so it fits the 200-unit step title. When every issue is a caught fwcore throw
(`sweep:<op>`) the head and tail are the throw ones (`sweepHead`, `sweepTail`: the fix is not in `emit.mjs`).

Name every issue with its count, cut short when the list is long.
-/
def alertTitle (cs : List (String × Nat)) : String :=
  let names := alertNames cs
  let kept := takeU16 123 names
  let (h, t) := if allSweep cs then (sweepHead, sweepTail) else (alertHead, alertTail)
  String.ofList (h.toList ++ kept ++ (if kept.length < names.length then ['…'] else []) ++ t.toList)

/-- **Throws get their own title**: when every issue is a caught throw the title has the throw head and tail and not the
`emit.mjs` ones.
-/
theorem alertTitle_sweep (cs : List (String × Nat)) (h : allSweep cs = true) :
    alertTitle cs = String.ofList (sweepHead.toList ++ takeU16 123 (alertNames cs) ++
      (if (takeU16 123 (alertNames cs)).length < (alertNames cs).length then ['…'] else []) ++ sweepTail.toList) := by
  unfold alertTitle
  simp [h]

/-- **A spool-line problem keeps the old title**: when some issue is not a caught throw the title is the old one. -/
theorem alertTitle_spool (cs : List (String × Nat)) (h : allSweep cs = false) :
    alertTitle cs = String.ofList (alertHead.toList ++ takeU16 123 (alertNames cs) ++
      (if (takeU16 123 (alertNames cs)).length < (alertNames cs).length then ['…'] else []) ++ alertTail.toList) := by
  unfold alertTitle
  simp [h]

/-- **The title fits**: the spool alert title is at most 200 UTF-16 units (the contract's step title).

The alert title is never too long for the board.
-/
theorem alertTitle_le (cs : List (String × Nat)) : utf16Len (alertTitle cs) ≤ 200 := by
  rw [utf16Len_eq]
  unfold alertTitle
  simp only [String.toList_ofList]
  have hk := takeU16_le 123 (alertNames cs)
  have hh : (alertHead.toList.map u16).sum = 25 := by decide
  have ht : (alertTail.toList.map u16).sum = 51 := by decide
  have hhs : (sweepHead.toList.map u16).sum = 23 := by decide
  have hts : (sweepTail.toList.map u16).sum = 38 := by decide
  have he : u16 '…' = 1 := by decide
  split <;> split <;> simp only [List.map_append, List.sum_append, hh, ht, hhs, hts, List.map_cons, List.map_nil,
    List.sum_cons, List.sum_nil, he] <;> omega

/-! ## Plain spool alerts and their automatic resolution (task `alert-steps-plain`)

A spool problem is the lead's to fix, never the owner's, so the spool alert step is posted for the `lead`
(`Fw.Console.Alert.Plain`): a plain title, then what happened, the impact and the action. The issue names
with counts go to the `Details` line only. A later sweep re-checks the condition and closes the step by itself
(`resolveSpool`), with a note.
-/

/-- What sort of problem an issue name is.

Which part of the reader a person looks at.
-/
inductive IssueClass where
  | unknownField | rejected | sweep | other
deriving Repr, DecidableEq

/-- The end of the issue name of an unknown field (`<field>:unknown`). -/
def unknownSuffix : String := ":unknown"

/-- The class of an issue name: `<field>:unknown`, `rejected:<why>`, `sweep:<op>`, anything else.

Tell the four sorts of issue apart by their names.
-/
def classOf (x : String) : IssueClass :=
  if x.endsWith unknownSuffix then .unknownField
  else if x.startsWith "rejected:" then .rejected
  else if isSweep x then .sweep else .other

/-- The classes present in an issue list, in a fixed order (unknown field, rejected, sweep, other). -/
def classes (cs : List (String × Nat)) : List IssueClass :=
  [IssueClass.unknownField, .rejected, .sweep, .other].filter fun c => cs.any fun (x, _) => classOf x == c

/-- What happened, in one plain sentence per class. -/
def classWhat : IssueClass → String
  | .unknownField => "The log reader met a field it does not know."
  | .rejected => "The log reader rejected some lines."
  | .sweep => "A background check inside the console failed."
  | .other => "The log reader could not use a value in some lines."

/-- The impact, in one plain sentence per class. -/
def classImpact : IssueClass → String
  | .unknownField => "Nothing is lost: the lines were still read; only the new field is not used by any rule yet."
  | .rejected => "Those lines were dropped, so the facts in them are missing from the board."
  | .sweep => "The console keeps running; the failed pass is tried again at the next sweep."
  | .other => "The lines were still read; the unusable value was ignored."

/-- The action for the lead, one sentence per class (the fix location). -/
def classAction : IssueClass → String
  | .unknownField => "Add the field to Fw.Ops.Obs.specs (lean/Fw/Ops/Obs.lean) or stop sending it from .claude/hooks/emit.mjs."
  | .rejected => "Read the reason in the details, then fix the sender (.claude/hooks/emit.mjs) or the record spec Fw.Ops.Obs.specs."
  | .sweep => "Read the console-api log for the error and fix the failing step."
  | .other => "Compare the note in the details with Fw.Ops.Obs.specs."

/-- The plain title of the spool alert: one title per single class, a general one for a mix. -/
def spoolTitle (cs : List (String × Nat)) : String :=
  match classes cs with
  | [.unknownField] => "The log reader saw a field it does not know"
  | [.rejected] => "The log reader rejected some lines"
  | [.sweep] => "A console background check failed"
  | _ => "The log reader found problems in some lines"

/-- The most UTF-16 units of the issue list in the details line. -/
def detailsCap : Nat := 600

/-- The details line: the issue list `x₁ xn₁, …`, cut at `detailsCap` units with an ellipsis. -/
def detailsOf (cs : List (String × Nat)) : String :=
  let names := alertNames cs
  let kept := takeU16 detailsCap names
  String.ofList (kept ++ (if kept.length < names.length then ['…'] else []))

/-- **The plain spool alert**: for the lead, a plain title, and a body with what happened, the impact, the action
(the fix location) and the details. -/
def spoolPlain (cs : List (String × Nat)) : Fw.Console.Alert.Plain :=
  { title := spoolTitle cs, audience := .lead,
    body := Fw.Console.Alert.bodyLines .lead
      (" ".intercalate ((classes cs).map classWhat)) (" ".intercalate ((classes cs).map classImpact))
      (" ".intercalate ((classes cs).map classAction) ++
        " This step closes by itself when a later sweep no longer shows these problems.")
      (detailsOf cs) }

/-- **The spool alert is the lead's**: whatever the issues, its audience is the lead, never the owner. -/
theorem spoolPlain_lead (cs : List (String × Nat)) : (spoolPlain cs).audience = .lead := rfl

/-- The title of the spool alert fits the contract's 200 units for every issue list. -/
theorem spoolTitle_le (cs : List (String × Nat)) : utf16Len (spoolTitle cs) ≤ 200 := by
  unfold spoolTitle
  split <;> decide

/-- The issue keys named by an item list `k₁ x₂, k₂ x₁`: empty unless every item reads as `<key> x<digits>`. -/
def parseNames (s : String) : List String :=
  let item (it : String) : Option String :=
    match (it.splitOn " x").reverse with
    | n :: k :: rest =>
      if n.isEmpty || !n.all Char.isDigit then none else some (" x".intercalate (k :: rest).reverse)
    | _ => none
  match (s.splitOn ", ").mapM item with
  | some ks => ks
  | none => []

/-- The issue keys an open spool alert step stands for: those of its `Details` line (none when the line was cut
with an ellipsis, so a cut list never closes by itself), or, for a step posted before details existed, those of
its title `Spool lines need a look: …; fix …` or `Drain threw in fwcore: …; see …`.
-/
def spoolKeys (title body : String) : List String :=
  match (body.splitOn "\n").find? (·.startsWith "Details: ") with
  | some d => if d.contains '…' then [] else parseNames (d.drop 9).toString
  | none =>
    if title.contains '…' then []
    else if title.startsWith alertHead && title.endsWith alertTail then
      parseNames ((title.drop alertHead.length).dropEnd alertTail.length).toString
    else if title.startsWith sweepHead && title.endsWith sweepTail then
      parseNames ((title.drop sweepHead.length).dropEnd sweepTail.length).toString
    else []

/-- One sweep window: how many spool lines it read and the issue names it raised. -/
structure Window where
  lines : Nat
  issues : List String
deriving Repr

/-- The field an `<field>:unknown` issue names. -/
def fieldOfKey (k : String) : String := (k.dropEnd unknownSuffix.length).toString

/-- **Is one issue key clean in this window?** It must not occur in the window, and then either (unknown field) the
field is known to the spec now, or (any other issue) the window read at least one line, so the reader did run.

Re-check the cause, not the silence: a fixed spec closes an unknown field; a quiet window closes nothing for it.
-/
def keyClean (w : Window) (k : String) : Bool :=
  !(w.issues.contains k) && (if classOf k == .unknownField then known (fieldOfKey k) else decide (0 < w.lines))

/-- A step resolves when it names at least one key and every key is clean. -/
def stepResolves (w : Window) (ks : List String) : Bool := !ks.isEmpty && ks.all (keyClean w)

/-- **Resolved only when the re-check is clean for every key**, and the step names a key. -/
theorem stepResolves_iff (w : Window) (ks : List String) :
    stepResolves w ks = true ↔ ks ≠ [] ∧ ∀ k ∈ ks, keyClean w k = true := by
  unfold stepResolves
  simp

/-- **A step with no readable key never closes** (a cut or foreign list stays open for a person). -/
theorem no_keys_never_closes (w : Window) : stepResolves w [] = false := rfl

/-- **A still-failing key never closes**: if one key of the step occurs in the window, the step stays open. -/
theorem failing_never_closes (w : Window) {ks : List String} {k : String} (hk : k ∈ ks) (hi : k ∈ w.issues) :
    stepResolves w ks = false := by
  cases h : stepResolves w ks
  · rfl
  · exfalso
    have := ((stepResolves_iff w ks).mp h).2 k hk
    simp [keyClean, hi] at this

/-- **An unknown field closes only when the spec knows it now.** -/
theorem unknown_closes_only_when_known (w : Window) {k : String} (hc : classOf k = .unknownField)
    (h : keyClean w k = true) : known (fieldOfKey k) = true := by
  simp [keyClean, hc] at h
  exact h.2

/-- **Any other issue closes only after a window that read a line**: a window with no line closes none. -/
theorem other_closes_only_after_lines (w : Window) {k : String} (hc : classOf k ≠ .unknownField)
    (h : keyClean w k = true) : 0 < w.lines := by
  simp [keyClean, hc] at h
  exact h.2

/-- An open step to re-check: its id, title, body and audience. -/
structure OpenStep where
  id : String
  title : String
  body : String
  audience : Fw.Console.Audience

/-- A step to close by itself: its id, the key of its `step.done` command and the note. -/
structure Resolution where
  step : String
  key : String
  note : String
deriving Repr, DecidableEq

/-- The key of the `step.done` command that resolves step `id` (one per step, so a repeat is a duplicate). -/
def resolveKey (id : String) : String := "alert-resolve:" ++ id

/-- A day count since 1970-01-01 as a (year, month, day) in the proleptic Gregorian calendar (the civil-from-days
algorithm, valid for every day count).

Which calendar date a day number is.
-/
def civil (z0 : Nat) : Nat × Nat × Nat :=
  let z := z0 + 719468
  let era := z / 146097
  let doe := z % 146097
  let yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp := (5 * doy + 2) / 153
  let d := doy - (153 * mp + 2) / 5 + 1
  let m := if mp < 10 then mp + 3 else mp - 9
  let y := yoe + era * 400
  (if m ≤ 2 then y + 1 else y, m, d)

/-- A number padded to two digits. -/
def pad2 (n : Nat) : String := if n < 10 then s!"0{n}" else toString n

/-- A time in milliseconds since the epoch as `YYYY-MM-DDTHH:MM:SSZ` (UTC). -/
def isoUtc (ms : Nat) : String :=
  let s := ms / 1000
  let (y, m, d) := civil (s / 86400)
  s!"{y}-{pad2 m}-{pad2 d}T{pad2 (s % 86400 / 3600)}:{pad2 (s % 3600 / 60)}:{pad2 (s % 60)}Z"

/-- Why one key is clean, in plain words. -/
def keyReason (w : Window) (k : String) : String :=
  if classOf k == .unknownField then s!"{fieldOfKey k} is now a known field"
  else s!"{k} did not occur in the latest sweep of {w.lines} lines"

/-- The note of an automatic resolution: `resolved automatically at <time>: <reason>`, cut to the 200 units of an
answer.
-/
def resolveNote (now : Nat) (w : Window) (ks : List String) : String :=
  String.ofList (takeU16 200 (s!"resolved automatically at {isoUtc now}: {"; ".intercalate (ks.map (keyReason w))}").toList)

/-- The note fits the contract's 200 units. -/
theorem resolveNote_le (now : Nat) (w : Window) (ks : List String) : utf16Len (resolveNote now w ks) ≤ 200 := by
  rw [utf16Len_eq]
  unfold resolveNote
  simp only [String.toList_ofList]
  exact takeU16_le 200 _

/-- **The spool steps to close by themselves**: each open step for the lead owned by the spool whose keys all re-check
clean in the window, with a `step.done` key and a note.

Close a spool alert when a re-check proves its cause gone.
-/
def resolveSpool (now : Nat) (w : Window) (steps : List OpenStep) : List Resolution :=
  steps.filterMap fun s =>
    if s.audience == .lead && Fw.Console.Alert.owner s.id == some spoolOwner then
      let ks := spoolKeys s.title s.body
      if stepResolves w ks then some ⟨s.id, resolveKey s.id, resolveNote now w ks⟩ else none
    else none

/-- **A resolution is sound**: it names an open lead step of the spool whose every key is clean in the window. -/
theorem resolveSpool_sound {now : Nat} {w : Window} {steps : List OpenStep} {r : Resolution}
    (h : r ∈ resolveSpool now w steps) :
    ∃ s ∈ steps, s.audience = .lead ∧ Fw.Console.Alert.owner s.id = some spoolOwner ∧ r.step = s.id ∧
      stepResolves w (spoolKeys s.title s.body) = true := by
  obtain ⟨s, hs, hr⟩ := List.mem_filterMap.mp h
  refine ⟨s, hs, ?_⟩
  by_cases hc : (s.audience == .lead && Fw.Console.Alert.owner s.id == some spoolOwner) = true
  · simp only [hc, ↓reduceIte] at hr
    by_cases hk : stepResolves w (spoolKeys s.title s.body) = true
    · simp only [hk, ↓reduceIte] at hr
      cases hr
      simp only [Bool.and_eq_true, beq_iff_eq] at hc
      exact ⟨hc.1, hc.2, rfl, hk⟩
    · simp [hk] at hr
  · simp [hc] at hr

/-- **A step for the owner is never closed by the script**: no resolution names a step whose audience is the user
(a decision only the owner can make).
-/
theorem user_step_never_resolved (now : Nat) (w : Window) (steps : List OpenStep)
    (h : ∀ s ∈ steps, s.audience = .user) : resolveSpool now w steps = [] := by
  apply List.eq_nil_iff_forall_not_mem.mpr
  intro r hr
  obtain ⟨s, hs, hl, _⟩ := resolveSpool_sound hr
  have := h s hs
  rw [hl] at this
  cases this

/-- **A still-failing key keeps its step open**: a resolved step has no key that occurs in the window. -/
theorem resolved_has_no_failing_key {now : Nat} {w : Window} {steps : List OpenStep} {r : Resolution}
    (h : r ∈ resolveSpool now w steps) :
    ∃ s ∈ steps, r.step = s.id ∧ ∀ k ∈ spoolKeys s.title s.body, k ∉ w.issues := by
  obtain ⟨s, hs, _, _, hid, hk⟩ := resolveSpool_sound h
  refine ⟨s, hs, hid, fun k hk' hi => ?_⟩
  have := failing_never_closes w hk' hi
  rw [hk] at this
  cases this

/-- **The spool alert**: none when there is no issue or a spool alert is still open; otherwise a step
`alert-spool-<now>` for the lead, with a plain title, a body (`spoolPlain`) and the issues with their counts in the details.

Raise one alert for all spool problems, unless one is already open.
-/
def fieldAlert (now : Nat) (opn : List String) (cs : List (String × Nat)) :
    Option (String × String × Fw.Console.Alert.Plain) :=
  if cs.isEmpty || opn.any (fun id => Fw.Console.Alert.owner id == some spoolOwner) then none
  else
    let id := Fw.Console.Alert.stepId (some spoolOwner) now
    some (id, "alert:" ++ id, spoolPlain cs)

/-- A spool alert is raised exactly when there is an issue and no spool alert is open.

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
rejected with reason `w` and no spool alert is open, the alert over the drain's issues (plus any
extra issues, such as `lifeOf:error`) fires and counts `rejected:` `w` at least once.

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

* `SubagentStart` of id `i` spawns `i` at the record time (event key `start:<obs key>`);
* `SubagentStop` of id `i` stops `i` at the record time (`stop:<obs key>`), named or not, and nothing
  else: two agents of one name are two keys, and the stop of one leaves the other live
  (`Fw.Plan.concurrent_keep`);
* **any other event** of id `i`, named or unnamed, is a heartbeat: a spawn of `i` at the record time
  with event key `seen:<i>|<epoch>|<time / 10 min>`, so at most one per id and 10 minutes, and only
  while no stop of the id was sent (`no_revive_after_stop`: after a stop only a `SubagentStart` revives it,
  `start_revives`, by `Fw.Plan.revive_on_event`; `stoppedAtOf` is the same rule over a whole spool); an id with no sighting within the quiet
  limit shows quiet with its last-seen time, never ended by the time
  (`Fw.Plan.running_needs_recent_sighting`, `Fw.Plan.timeout_never_ends`); a lead or user mark ends
  it (`Fw.Plan.mark_ends_quiet`);
* a named `SpawnGuard` record (the spawner's guard, before the new agent has an id) spawns its own
  obs key `k` (event key `guard:<k>`) and labels `k` with the requested name (event key
  `guard-label:<k>`): the task row is running from the spawn on, before the health index labels the
  new id. A `SubagentStop` record carries no obs key of the guard, so no record stops `k`: it runs
  for the quiet limit after its record and then shows quiet (`Fw.Plan.no_forever_running`), never
  ended.
-/

/-- The heartbeat bucket: 10 minutes in milliseconds. -/
def seenBucketMs : Nat := 10 * 60000

/-- What a record does to agent life: a spawn or stop of a life key (event key, life key, time), or a
label of a life key with a name (event key, life key, name).
-/
inductive Life where
  | spawn (key agent : String) (time : Nat)
  | stop (key agent : String) (time : Nat)
  | label (key agent name : String)
deriving Repr, DecidableEq

/-- The life key a life command names. -/
def Life.agent : Life → String
  | .spawn _ a _ | .stop _ a _ | .label _ a _ => a

/-- A usable agent name: non-empty and at most 120 UTF-16 units (a contract id).

Is this string fit to be a name.
-/
def okName (n : String) : Bool := decide (0 < utf16Len n ∧ utf16Len n ≤ 120)

/-- The heartbeat event key of id `i` at time `t` in stop epoch `p`.

(`p` and `⌊ t / 600000 ⌋` written in decimal.) One key per id, epoch and 10 minutes.
-/
def seenKey (i : String) (p t : Nat) : String :=
  "seen:" ++ i ++ "|" ++ toString p ++ "|" ++ toString (t / seenBucketMs)

/-- The life commands of a record by its agent id `i` (event `e`, obs key `k`, time `t`, stop epoch `p`
of `i`).

The id starts, stops, or is seen alive. Once the drain has sent a stop of `i` (`p > 0`), only a `SubagentStart` makes it live
again: 56 of 2026-10-19's stops were followed by a `PostToolUse` of tool `SubagentHandback` with no start (MEASURED).
-/
def byId (event : String) (agentId : Option String) (key : String) (ts epoch : Nat) : List Life :=
  match agentId with
  | none => []
  | some i =>
    if event == "SubagentStart" then [.spawn ("start:" ++ key) i ts]
    else if event == "SubagentStop" then [.stop ("stop:" ++ key) i ts]
    else if epoch == 0 then [.spawn (seenKey i epoch ts) i ts]
    else []

/-- The life commands of a spawn guard (event `e`, requested name `g`, obs key `k`, time `t`): a named
guard spawns its obs key and labels it with the name, when `k`, `g` and the label's event key are
usable contract ids.

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

/-- **The life decision of a record** (event `e`, agent id `i`, spawn-guard name `g`, obs key `k`,
time `t`, stop epoch `p` of `i`): the guard commands, then the id commands.

What one spool record says about which agents live.
-/
def lifeOf (event : String) (agentId agentName : Option String) (key : String) (ts epoch : Nat) :
    List Life :=
  byGuard event agentName key ts ++ byId event agentId key ts epoch

/-- **Identity only** (`life_identity`): every life command of a record is keyed by the record's agent
id or by its obs key, and every stop is a stop of the agent id.

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
        · split at hc
          · simp only [List.mem_singleton] at hc; subst hc; simp [Life.agent]
          · simp at hc

/-- **A stop ends its id** (`stop_by_id`): a `SubagentStop` with agent id `i` stops `i` at the record
time, named or not, whatever `background_tasks` says (the decision has no such input).

Every subagent stop reaches the board as a stop of that id.
-/
theorem stop_by_id (i : String) (g : Option String) (k : String) (t p : Nat) :
    Life.stop ("stop:" ++ k) i t ∈ lifeOf "SubagentStop" (some i) g k t p := by
  simp [lifeOf, byId]

/-- **A start spawns its id** (`start_by_id`): a `SubagentStart` with agent id `i` spawns `i` at the
record time.

Every subagent start reaches the board as a spawn of that id.
-/
theorem start_by_id (i : String) (g : Option String) (k : String) (t p : Nat) :
    Life.spawn ("start:" ++ k) i t ∈ lifeOf "SubagentStart" (some i) g k t p := by
  simp [lifeOf, byId]

/-- **An event revives an id nobody has stopped** (`event_revives`): an event of id `i` other than a start or stop,
named or unnamed, with no stop of `i` sent yet (`p = 0`), gives a heartbeat spawn of `i` at the record time; applied to a
plan state where `i` is a key labelled with name `a` and every stop of `i` is older than `t`, it makes `i` live and `a`
not ended.

An agent with no stop that does anything is live (running while that event is within the quiet limit).
-/
theorem event_revives (π : Fw.Plan.State) {e i a : String} (g : Option String) (k : String)
    (t : Nat) (h1 : e ≠ "SubagentStart") (h2 : e ≠ "SubagentStop")
    (hk : i ∈ Fw.Plan.keysOf π a) (hs : ∀ q ∈ π.stops, q.1 = i → q.2 < t) :
    Life.spawn (seenKey i 0 t) i t ∈ lifeOf e (some i) g k t 0 ∧
      Fw.Plan.liveK (Fw.Plan.step π (.spawn i t)) i = true ∧
      Fw.Plan.ended (Fw.Plan.step π (.spawn i t)) a = false := by
  refine ⟨?_, Fw.Plan.revive_on_event π hk hs⟩
  simp [lifeOf, byId, h1, h2]

/-- **No event but a start revives a stopped id** (`no_revive_after_stop`): once a stop of `i` was sent (`p > 0`), an
event of `i` other than a start or stop gives no life command for `i` (a `SubagentHandback` call after the stop is not a
resume).
-/
theorem no_revive_after_stop (e i k : String) (t p : Nat) (hp : 0 < p)
    (h1 : e ≠ "SubagentStart") (h2 : e ≠ "SubagentStop") :
    byId e (some i) k t p = [] := by
  have : (p == 0) = false := by simp; omega
  simp [byId, h1, h2, this]

/-- **A start revives a stopped id** (`start_revives`): a `SubagentStart` of `i` later than every stop of `i` makes `i`
live and its name not ended, whatever the stop epoch.
-/
theorem start_revives (π : Fw.Plan.State) {i a : String} (g : Option String) (k : String)
    (t p : Nat) (hk : i ∈ Fw.Plan.keysOf π a) (hs : ∀ q ∈ π.stops, q.1 = i → q.2 < t) :
    Life.spawn ("start:" ++ k) i t ∈ lifeOf "SubagentStart" (some i) g k t p ∧
      Fw.Plan.liveK (Fw.Plan.step π (.spawn i t)) i = true ∧
      Fw.Plan.ended (Fw.Plan.step π (.spawn i t)) a = false :=
  ⟨start_by_id i g k t p, Fw.Plan.revive_on_event π hk hs⟩

/-- **The stop epoch after a record** (`epochNext`): a `SubagentStop` at `t` raises the epoch to `max(p, t)`; a
`SubagentStart` at `t` newer than the epoch resets it to `0` (the agent lives again, so its tool calls are heartbeats
again; an older start resets nothing, as in `stoppedAtOf`); any other event leaves it.

The drain keeps one epoch per agent id and sets it from this function after each record.
-/
def epochNext (event : String) (ts epoch : Nat) : Nat :=
  if event == "SubagentStop" then max epoch ts
  else if event == "SubagentStart" && decide (epoch < ts) then 0
  else epoch

/-- **A resumed agent heartbeats again** (`heartbeat_after_resume`): a stop of `i` at `s`, then a start at `t` newer than
the stop and than every earlier stop (`p < t`), then an event `e` of `i` other than a start or stop at `u` gives a
heartbeat spawn of `i` at `u`, so the agent shows running again. Without the start the same event gives no command
(`silent_after_stop_epoch`).
-/
theorem heartbeat_after_resume (e i k : String) (p s t u : Nat) (hp : p < t) (hs : s < t)
    (h1 : e ≠ "SubagentStart") (h2 : e ≠ "SubagentStop") :
    byId e (some i) k u
      (epochNext "SubagentStart" t (epochNext "SubagentStop" s p)) =
      [Life.spawn (seenKey i 0 u) i u] := by
  have : max p s < t := by omega
  simp [byId, epochNext, h1, h2, this]

/-- **Stopped without a start stays silent** (`silent_after_stop_epoch`): after a stop at `s > 0` the epoch is positive, so an
event other than a start or stop gives no command.
-/
theorem silent_after_stop_epoch (e i k : String) (p s u : Nat) (hs : 0 < s)
    (h1 : e ≠ "SubagentStart") (h2 : e ≠ "SubagentStop") :
    byId e (some i) k u (epochNext "SubagentStop" s p) = [] :=
  no_revive_after_stop e i k u _ (by simp [epochNext]; omega) h1 h2

/-! ### The resume predicate (task `alert-rules-fix`)

A spool is a list of (hook name, time). The agent's stop time is the newest `SubagentStop`; it is resumed iff a
`SubagentStart` is newer than that stop. Nothing else resumes it: not a tool call, not `StructuredOutput`, not
`SubagentHandback` (MEASURED 2026-10-19: 56 stops were followed by a `SubagentHandback` and no start, 120 by a start,
0 real tool calls without a start).
-/

/-- Fold step of `lastStop`: a stop raises the running maximum. -/
def stopStep (acc : Option Nat) (x : String × Nat) : Option Nat :=
  if x.1 == "SubagentStop" then some (max (acc.getD 0) x.2) else acc

/-- The newest `SubagentStop` time of a spool.

(`none` for the empty set)
-/
def lastStop (h : List (String × Nat)) : Option Nat :=
  h.foldl stopStep none

/-- Whether a spool has a `SubagentStart` newer than `s`. -/
def startAfter (h : List (String × Nat)) (s : Nat) : Bool :=
  h.any fun (e, t) => e == "SubagentStart" && decide (s < t)

/-- **The stop time of an agent** (`stoppedAtOf`): the newest stop, unless a start is newer. -/
def stoppedAtOf (h : List (String × Nat)) : Option Nat :=
  match lastStop h with
  | none => none
  | some s => if startAfter h s then none else some s

/-- **A start after the stop resumes** (`resumed_by_start`): with a stop at `s` and a start at `t > s` the agent has no stop time. -/
theorem resumed_by_start (h : List (String × Nat)) (s t : Nat) (hs : lastStop h = some s)
    (hm : ("SubagentStart", t) ∈ h) (hlt : s < t) : stoppedAtOf h = none := by
  have : startAfter h s = true := by
    simp only [startAfter, List.any_eq_true]
    exact ⟨_, hm, by simp [hlt]⟩
  simp [stoppedAtOf, hs, this]

/-- **Nothing else resumes** (`not_resumed_without_start`): when no start is newer than the stop `s`, the stop time stays `s`. -/
theorem not_resumed_without_start (h : List (String × Nat)) (s : Nat) (hs : lastStop h = some s)
    (hm : ∀ t, ("SubagentStart", t) ∈ h → t ≤ s) : stoppedAtOf h = some s := by
  have : startAfter h s = false := by
    simp only [startAfter, Bool.eq_false_iff, ne_eq, List.any_eq_true, not_exists, not_and]
    intro ⟨e, t⟩ hmem
    by_cases he : e = "SubagentStart"
    · subst he; have := hm t hmem; simp; omega
    · simp [he]
  simp [stoppedAtOf, hs, this]

/-- **No stop, no stop time** (`no_stop_no_stoppedAt`): a spool without a `SubagentStop` has no stop time. -/
theorem no_stop_no_stoppedAt (h : List (String × Nat)) (hn : ∀ t, ("SubagentStop", t) ∉ h) :
    stoppedAtOf h = none := by
  have key : ∀ (l : List (String × Nat)) (acc : Option Nat), (∀ t, ("SubagentStop", t) ∉ l) →
      l.foldl stopStep acc = acc := by
    intro l; induction l with
    | nil => intros; rfl
    | cons x xs ih =>
      intro acc hl
      obtain ⟨e, t⟩ := x
      have hne : e ≠ "SubagentStop" := by
        rintro rfl; exact hl t (by simp)
      simp only [List.foldl_cons, stopStep, beq_iff_eq, hne, ite_false]
      exact ih _ (fun t' ht => hl t' (List.mem_cons_of_mem _ ht))
  simp [stoppedAtOf, lastStop, key h none hn]

/-- The label command of an agent id from the health index: event key `label:<id>|<name>`, when the
id, the name and that key are all usable contract ids.

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
#guard alertTitle [("sweep:lifeOf", 3)] = "Drain threw in fwcore: sweep:lifeOf x3; see console-api log, then press Done"
#guard alertTitle [("sweep:lifeOf", 3), ("rejected:json", 1)] = "Spool lines need a look: sweep:lifeOf x3, rejected:json x1; fix emit.mjs or Fw.Ops.Obs.specs, then press Done"
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
#guard lifeOf "PostToolUse" (some "i") none "k" 1200000 0 = [.spawn "seen:i|0|2" "i" 1200000]
#guard lifeOf "PreToolUse" (some "i") none "k" 1200000 0 = [.spawn "seen:i|0|2" "i" 1200000]
-- after a stop only a start revives: a heartbeat gives nothing
#guard lifeOf "PostToolUse" (some "i") none "k" 1200000 9 = []
#guard lifeOf "SubagentStart" (some "i") none "k" 1200000 9 = [.spawn "start:k" "i" 1200000]
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

-- plain spool alert (task alert-steps-plain): for the lead, plain title, identifiers only in the details
#guard (spoolPlain [("session_pid:unknown", 1)]).audience == .lead
#guard (spoolPlain [("session_pid:unknown", 1)]).title == "The log reader saw a field it does not know"
#guard (spoolPlain [("session_pid:unknown", 1)]).body ==
  "What happened: The log reader met a field it does not know.\n" ++
  "Impact: Nothing is lost: the lines were still read; only the new field is not used by any rule yet.\n" ++
  "Action (lead): Add the field to Fw.Ops.Obs.specs (lean/Fw/Ops/Obs.lean) or stop sending it from .claude/hooks/emit.mjs. This step closes by itself when a later sweep no longer shows these problems.\n" ++
  "Details: session_pid:unknown x1"
#guard (spoolPlain [("rejected:json", 2)]).title == "The log reader rejected some lines"
#guard (spoolPlain [("sweep:lifeOf", 3)]).title == "A console background check failed"
#guard (spoolPlain [("sweep:lifeOf", 3), ("rejected:json", 1)]).title == "The log reader found problems in some lines"
#guard classes [("sweep:lifeOf", 3), ("rejected:json", 1), ("a:unknown", 1), ("lifeOf:error", 1)] == [.unknownField, .rejected, .sweep, .other]
-- the longest body (all four classes, a cut details line) stays inside the 2000 units
#guard utf16Len (spoolPlain (("lifeOf:error", 1) :: ("sweep:drain", 1) :: ("rejected:json", 1) ::
  (List.range 80).map fun i => (s!"field{i}:unknown", i + 1))).body ≤ 2000
#guard (detailsOf ((List.range 80).map fun i => (s!"field{i}:unknown", i + 1))).contains '…'
-- the keys of a step: from the details line of a new step, from the title of a step posted before details existed
#guard spoolKeys "t" (spoolPlain [("session_pid:unknown", 1), ("rejected:json", 2)]).body == ["session_pid:unknown", "rejected:json"]
#guard spoolKeys "Spool lines need a look: session_pid:unknown x1; fix emit.mjs or Fw.Ops.Obs.specs, then press Done" "" == ["session_pid:unknown"]
#guard spoolKeys "Spool lines need a look: sweep:lifeOf x3, rejected:json x1; fix emit.mjs or Fw.Ops.Obs.specs, then press Done" ""
  == ["sweep:lifeOf", "rejected:json"]
#guard spoolKeys "Drain threw in fwcore: sweep:lifeOf x3; see console-api log, then press Done" "" == ["sweep:lifeOf"]
-- a cut or foreign list names no key: it never closes by itself
#guard spoolKeys "t" (spoolPlain ((List.range 80).map fun i => (s!"field{i}:unknown", i + 1))).body == []
#guard spoolKeys "Pick a number" "" == []
#guard spoolKeys "t" "Details: not a list" == []
-- the re-check
private def stale : OpenStep := ⟨"alert-spool-1792389046068",
  "Spool lines need a look: session_pid:unknown x1; fix emit.mjs or Fw.Ops.Obs.specs, then press Done", "", .lead⟩
#guard keyClean ⟨0, []⟩ "session_pid:unknown"
#guard !keyClean ⟨5, []⟩ "no_such_field:unknown"
#guard !keyClean ⟨5, ["session_pid:unknown"]⟩ "session_pid:unknown"
#guard !keyClean ⟨0, []⟩ "rejected:json"
#guard keyClean ⟨1, []⟩ "rejected:json"
#guard !keyClean ⟨7, ["rejected:json"]⟩ "rejected:json"
#guard resolveSpool 1792500000000 ⟨0, []⟩ [stale] ==
  [⟨"alert-spool-1792389046068", "alert-resolve:alert-spool-1792389046068",
    "resolved automatically at 2026-10-20T12:40:00Z: session_pid is now a known field"⟩]
-- a still-failing key, an unknown field the spec does not know, a user step and a step of another owner stay open
#guard resolveSpool 5 ⟨3, ["session_pid:unknown"]⟩ [stale] == []
#guard resolveSpool 5 ⟨3, []⟩ [{ stale with title := "Spool lines need a look: no_such_field:unknown x1; fix emit.mjs or Fw.Ops.Obs.specs, then press Done" }] == []
#guard resolveSpool 5 ⟨3, []⟩ [{ stale with audience := .user }] == []
#guard resolveSpool 5 ⟨3, []⟩ [{ stale with id := "alert-a1-9" }] == []
#guard resolveSpool 5 ⟨0, []⟩ [{ stale with title := "Spool lines need a look: rejected:json x1; fix emit.mjs or Fw.Ops.Obs.specs, then press Done" }] == []
#guard (resolveSpool 5000 ⟨2, []⟩ [{ stale with title := "Spool lines need a look: rejected:json x1; fix emit.mjs or Fw.Ops.Obs.specs, then press Done" }]).map (·.note)
  == ["resolved automatically at 1970-01-01T00:00:05Z: rejected:json did not occur in the latest sweep of 2 lines"]
#guard isoUtc 0 == "1970-01-01T00:00:00Z"
#guard isoUtc 1792389046068 == "2026-10-19T05:50:46Z"
#guard isoUtc 951782400000 == "2000-02-29T00:00:00Z"
#guard isoUtc 4102444799000 == "2099-12-31T23:59:59Z"

end Fw.Ops.Obs
